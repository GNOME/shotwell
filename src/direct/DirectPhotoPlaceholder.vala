/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class DirectPhotoPlaceholder : DataSource, DataSourcePlaceholder {
    public static DirectPhotoPlaceholderSourceCollection global = null;
    
    private static int64 current_instance_id = 0;
    
    private File file;
    private int64 instance_id;
    private bool reimport = false;
    
    public DirectPhotoPlaceholder(File file) {
        this.file = file;
        instance_id = current_instance_id++;
    }
    
    public static void init(File initial_file) {
        global = new DirectPhotoPlaceholderSourceCollection(initial_file);
    }
    
    public static void terminate() {
    }
    
    public File get_file() {
        return file;
    }
    
    public DataSource fetch_real_source() {
        DirectPhoto photo;
        string? reason = DirectPhoto.global.fetch(file, out photo, reimport);
        
        // reset
        reimport = false;
        
        // if couldn't import the photo, return a dummy
        if (reason != null) {
            photo = DummyDirectPhoto.create(file, reason);
            DirectPhoto.global.add(photo);
        }
        
        return photo;
    }
    
    public void mark_for_reimport() {
        reimport = true;
    }
    
    public override string get_name() {
        return file.get_basename();
    }
    
    public override string get_typename() {
        return "directplaceholder";
    }
    
    public override int64 get_instance_id() {
        return instance_id;
    }
    
    public override string to_string() {
        return "DirectPhotoPlaceholder for %s".printf(file.get_path());
    }
}

public class DirectPhotoPlaceholderSourceCollection : SourceCollection {
    private const int DISCOVERED_FILES_BATCH_ADD = 25;
    
    private DirectoryMonitor monitor;
    private Gee.Collection<DirectPhotoPlaceholder> prepared_placeholders = new Gee.ArrayList<DirectPhotoPlaceholder>();
    private Gee.HashMap<File, DirectPhotoPlaceholder> file_map = new Gee.HashMap<File, DirectPhotoPlaceholder>(
        file_hash, file_equal);
    
    public DirectPhotoPlaceholderSourceCollection(File initial_file) {
        base ("DirectPhotoPlaceholderSourceCollection");
        
        // immediately add the initial file so it's ready (the other files will come in later)
        add(new DirectPhotoPlaceholder(initial_file));
        
        // only use the monitor for discovery in the specified directory, not its children
        monitor = new DirectoryMonitor(initial_file.get_parent(), false, false);
        monitor.file_discovered.connect(on_file_discovered);
        monitor.discovery_completed.connect(on_discovery_completed);
        
        monitor.start_discovery();
    }
    
    public override bool holds_type_of_source(DataSource source) {
        return source is DirectPhotoPlaceholder;
    }
    
    public bool has_source_for_file(File file) {
        return file_map.has_key(file);
    }
    
    public DirectPhotoPlaceholder? get_source_for_file(File file) {
        return file_map.get(file);
    }
    
    private void on_file_discovered(File file, FileInfo info) {
        // skip already-seen files
        if (has_source_for_file(file))
            return;
        
        // only add files that look like photo files we support
        if (!PhotoFileFormat.is_file_supported(file))
            return;
        
        prepared_placeholders.add(new DirectPhotoPlaceholder(file));
        if (prepared_placeholders.size >= DISCOVERED_FILES_BATCH_ADD)
            flush_prepared_placeholders();
    }
    
    private void on_discovery_completed() {
        flush_prepared_placeholders();
    }
    
    private void flush_prepared_placeholders() {
        add_many(prepared_placeholders);
        prepared_placeholders.clear();
    }
    
    protected override void notify_contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added) {
                DirectPhotoPlaceholder placeholder = (DirectPhotoPlaceholder) object;
                
                assert(!file_map.has_key(placeholder.get_file()));
                file_map.set(placeholder.get_file(), placeholder);
            }
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                DirectPhotoPlaceholder placeholder = (DirectPhotoPlaceholder) object;
                
                bool is_removed = file_map.unset(placeholder.get_file());
                assert(is_removed);
            }
        }
        
        base.notify_contents_altered(added, removed);
    }
}

