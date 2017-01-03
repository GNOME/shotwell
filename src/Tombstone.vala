/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class TombstoneSourceCollection : DatabaseSourceCollection {
    private Gee.HashMap<File, Tombstone> file_map = new Gee.HashMap<File, Tombstone>(file_hash,
        file_equal);
    
    public TombstoneSourceCollection() {
        base ("Tombstones", get_tombstone_id);
    }
    
    public override bool holds_type_of_source(DataSource source) {
        return source is Tombstone;
    }
    
    private static int64 get_tombstone_id(DataSource source) {
        return ((Tombstone) source).get_tombstone_id().id;
    }
    
    protected override void notify_contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added) {
                Tombstone tombstone = (Tombstone) object;
                
                file_map.set(tombstone.get_file(), tombstone);
            }
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                Tombstone tombstone = (Tombstone) object;
                
                // do we actually have this file?
                if (file_map.has_key(tombstone.get_file())) {
                    // yes, try to remove it.
                    bool is_removed = file_map.unset(tombstone.get_file());
                    assert(is_removed);
                }
                // if the hashmap didn't have the file to begin with,
                // we're already in the state we wanted to be in, so our
                // work is done; no need to assert.
            }
        }
        
        base.notify_contents_altered(added, removed);
    }
    
    protected override void notify_items_altered(Gee.Map<DataObject, Alteration> items) {
        foreach (DataObject object in items.keys) {
            Alteration alteration = items.get(object);
            if (!alteration.has_subject("file"))
                continue;
            
            Tombstone tombstone = (Tombstone) object;
            
            foreach (string detail in alteration.get_details("file")) {
                File old_file = File.new_for_path(detail);
                
                bool removed = file_map.unset(old_file);
                assert(removed);
                
                file_map.set(tombstone.get_file(), tombstone);
                
                break;
            }
        }
    }
    
    public Tombstone? locate(File file) {
        return file_map.get(file);
    }
    
    public bool matches(File file) {
        return file_map.has_key(file);
    }
    
    public void resurrect(Tombstone tombstone) {
        destroy_marked(mark(tombstone), false);
    }
    
    public void resurrect_many(Gee.Collection<Tombstone> tombstones) {
        Marker marker = mark_many(tombstones);
        
        freeze_notifications();
        DatabaseTable.begin_transaction();
        
        destroy_marked(marker, false);
        
        try {
            DatabaseTable.commit_transaction();
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        thaw_notifications();
    }
    
    // This initiates a scan of the tombstoned files, resurrecting them if the file is no longer
    // present on disk.  If a DirectoryMonitor is supplied, the scan will use that object's FileInfo
    // if available.  If not available or not supplied, the scan will query for the file's
    // existence.
    //
    // Note that this call is non-blocking.
    public void launch_scan(DirectoryMonitor? monitor, Cancellable? cancellable) {
        async_scan.begin(monitor, cancellable);
    }
    
    private async void async_scan(DirectoryMonitor? monitor, Cancellable? cancellable) {
        // search through all tombstones for missing files, which indicate the tombstone can go away
        Marker marker = start_marking();
        foreach (DataObject object in get_all()) {
            Tombstone tombstone = (Tombstone) object;
            File file = tombstone.get_file();
            
            FileInfo? info = null;
            if (monitor != null)
                info = monitor.get_file_info(file);
            
            // Want to be conservative here; only resurrect a tombstone if file is actually detected
            // as not present, and not some other problem (which may be intermittent)
            if (info == null) {
                try {
                    info = yield file.query_info_async(FileAttribute.STANDARD_NAME,
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, cancellable);
                } catch (Error err) {
                    // watch for cancellation, which signals it's time to go
                    if (err is IOError.CANCELLED)
                        break;
                    
                    if (!(err is IOError.NOT_FOUND)) {
                        warning("Unable to check for existence of tombstoned file %s: %s",
                            file.get_path(), err.message);
                    }
                }
            }
            
            // if not found, resurrect
            if (info == null)
                marker.mark(tombstone);
            
            Idle.add(async_scan.callback);
            yield;
        }
        
        if (marker.get_count() > 0) {
            debug("Resurrecting %d tombstones with no backing file", marker.get_count());
            DatabaseTable.begin_transaction();
            destroy_marked(marker, false);
            try {
                DatabaseTable.commit_transaction();
            } catch (DatabaseError err2) {
                AppWindow.database_error(err2);
            }
        }
    }
}

public class TombstonedFile {
    public File file;
    public int64 filesize;
    public string? md5;
    
    public TombstonedFile(File file, int64 filesize, string? md5) {
        this.file = file;
        this.filesize = filesize;
        this.md5 = md5;
    }
}

public class Tombstone : DataSource {
    // These values are persisted.  Do not change.
    public enum Reason {
        REMOVED_BY_USER = 0,
        AUTO_DETECTED_DUPLICATE = 1;
        
        public int serialize() {
            return (int) this;
        }
        
        public static Reason unserialize(int value) {
            switch ((Reason) value) {
                case AUTO_DETECTED_DUPLICATE:
                    return AUTO_DETECTED_DUPLICATE;
                
                // 0 is the default in the database, so it should remain so here
                case REMOVED_BY_USER:
                default:
                    return REMOVED_BY_USER;
            }
        }
    }
    
    public static TombstoneSourceCollection global = null;
    
    private TombstoneRow row;
    private File? file = null;
    
    private Tombstone(TombstoneRow row) {
        this.row = row;
    }
    
    public static void init() {
        global = new TombstoneSourceCollection();
        
        TombstoneRow[]? rows = null;
        try {
            rows = TombstoneTable.get_instance().fetch_all();
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        if (rows != null) {
            Gee.ArrayList<Tombstone> tombstones = new Gee.ArrayList<Tombstone>();
            foreach (TombstoneRow row in rows)
                tombstones.add(new Tombstone(row));
            
            global.add_many(tombstones);
        }
    }
    
    public static void terminate() {
    }
    
    public static void entomb_many_sources(Gee.Collection<MediaSource> sources, Reason reason)
        throws DatabaseError {
        Gee.Collection<TombstonedFile> files = new Gee.ArrayList<TombstonedFile>();
        foreach (MediaSource source in sources) {
            foreach (BackingFileState state in source.get_backing_files_state())
                files.add(new TombstonedFile(state.get_file(), state.filesize, state.md5));
        }
        
        entomb_many_files(files, reason);
    }
    
    public static void entomb_many_files(Gee.Collection<TombstonedFile> files, Reason reason)
        throws DatabaseError {
        // destroy any out-of-date tombstones so they may be updated
        Marker to_destroy = global.start_marking();
        foreach (TombstonedFile file in files) {
            Tombstone? tombstone = global.locate(file.file);
            if (tombstone != null)
                to_destroy.mark(tombstone);
        }
        
        global.destroy_marked(to_destroy, false);
        
        Gee.ArrayList<Tombstone> tombstones = new Gee.ArrayList<Tombstone>();
        foreach (TombstonedFile file in files) {
            tombstones.add(new Tombstone(TombstoneTable.get_instance().add(file.file.get_path(),
                file.filesize, file.md5, reason)));
        }
        
        global.add_many(tombstones);
    }
    
    public override string get_typename() {
        return "tombstone";
    }
    
    public override int64 get_instance_id() {
        return get_tombstone_id().id;
    }
    
    public override string get_name() {
        return row.filepath;
    }
    
    public override string to_string() {
        return "Tombstone %s".printf(get_name());
    }
    
    public TombstoneID get_tombstone_id() {
        return row.id;
    }
    
    public File get_file() {
        if (file == null)
            file = File.new_for_path(row.filepath);
        
        return file;
    }
    
    public string? get_md5() {
        return is_string_empty(row.md5) ? null : row.md5;
    }
    
    public Reason get_reason() {
        return row.reason;
    }
    
    public void move(File file) {
        try {
            TombstoneTable.get_instance().update_file(row.id, file.get_path());
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        string old_filepath = row.filepath;
        row.filepath = file.get_path();
        this.file = file;
        
        notify_altered(new Alteration("file", old_filepath));
    }
    
    public bool matches(File file, int64 filesize, string? md5) {
        if (row.filesize != filesize)
            return false;
        
        // normalize to deal with empty strings
        string? this_md5 = is_string_empty(row.md5) ? null : row.md5;
        string? other_md5 = is_string_empty(md5) ? null : md5;
        
        if (this_md5 != other_md5)
            return false;
        
        if (!get_file().equal(file))
            return false;
        
        return true;
    }
    
    public override void destroy() {
        try {
            TombstoneTable.get_instance().remove(row.id);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        base.destroy();
    }
}

