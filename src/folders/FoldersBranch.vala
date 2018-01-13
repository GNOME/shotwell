/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Folders.Branch : Sidebar.Branch {
    private Gee.HashMap<File, Folders.SidebarEntry> entries =
        new Gee.HashMap<File, Folders.SidebarEntry>(file_hash, file_equal);
    private File home_dir;
    
    public class Branch() {
        base (new Folders.Root(),
              Sidebar.Branch.Options.STARTUP_OPEN_GROUPING
              | Sidebar.Branch.Options.HIDE_IF_EMPTY,
              comparator);
        
        home_dir = File.new_for_path(Environment.get_home_dir());
        
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all()) {
            // seed
            on_media_contents_altered(sources.get_all(), null);
            
            // monitor
            sources.contents_altered.connect(on_media_contents_altered);
        }
    }
    
    ~Branch() {
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all())
            sources.contents_altered.disconnect(on_media_contents_altered);
    }
    
    private static int comparator(Sidebar.Entry a, Sidebar.Entry b) {
        if (a == b)
            return 0;
        
        int coll_key_equality = strcmp(((Folders.SidebarEntry) a).collation,
            ((Folders.SidebarEntry) b).collation);
        
        if (coll_key_equality == 0) {
            // Collation keys were the same, double-check that
            // these really are the same string...
            return strcmp(((Folders.SidebarEntry) a).get_sidebar_name(), 
                ((Folders.SidebarEntry) b).get_sidebar_name());
        }
        
        return coll_key_equality;
    }

    private void on_master_source_replaced(MediaSource media_source, File old_file, File new_file) {
        remove_entry(old_file);
        add_entry(media_source);
    }
    
    private void on_media_contents_altered(Gee.Iterable<DataObject>? added, Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added) {
                add_entry((MediaSource) object);
                ((MediaSource) object).master_replaced.connect(on_master_source_replaced);
            }
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                remove_entry(((MediaSource) object).get_file());
                ((MediaSource) object).master_replaced.disconnect(on_master_source_replaced);
            }
        }
    }
    
    void add_entry(MediaSource media) {
        File file = media.get_file();
        
        Gee.ArrayList<File> elements = new Gee.ArrayList<File>();
        
        // add the path elements in reverse order up to home directory
        File? parent = file.get_parent();
        while (parent != null && parent.get_path() != null) {
            // don't process paths above the user's home directory
            if (parent.equal(home_dir.get_parent()))
                break;
            
            elements.add(parent);
            
            parent = parent.get_parent();
        }
        
        // walk path elements in order from home directory down, building needed sidebar entries
        // along the way
        Folders.SidebarEntry? parent_entry = null;
        for (int ctr = elements.size - 1; ctr >= 0; ctr--) {
            File parent_dir = elements[ctr];
            
            // save current parent, needed if this entry needs to be grafted
            Folders.SidebarEntry? old_parent_entry = parent_entry;
            
            parent_entry = entries.get(parent_dir);
            if (parent_entry == null) {
                parent_entry = new Folders.SidebarEntry(parent_dir);
                entries.set(parent_dir, parent_entry);
                
                graft((old_parent_entry == null) ? get_root() : old_parent_entry, parent_entry);
            }
            
            // only increment entry's file count if File is going in this folder
            if (ctr == 0)
                parent_entry.count++;
        }
    }
    
    private void remove_entry(File file) {
        Folders.SidebarEntry? folder_entry = entries.get(file.get_parent());
        if (folder_entry == null)
            return;
        
        assert(folder_entry.count > 0);
        
        // decrement file count for folder of photo
        if (--folder_entry.count > 0 || get_child_count(folder_entry) > 0)
            return;
        
        // empty folder so prune tree
        Folders.SidebarEntry? prune_point = folder_entry;
        assert(prune_point != null);
        
        for (;;) {
            bool removed = entries.unset(prune_point.dir);
            assert(removed);
            
            Folders.SidebarEntry? parent = get_parent(prune_point) as Folders.SidebarEntry;
            if (parent == null || parent.count != 0 || get_child_count(parent) > 1)
                break;
            
            prune_point = parent;
        }
        
        prune(prune_point);
    }
}

private class Folders.Root : Sidebar.Header {
    public Root() {
        base (_("Folders"), _("Browse the library’s folder structure"));
    }
}

public class Folders.SidebarEntry : Sidebar.SimplePageEntry, Sidebar.ExpandableEntry {
    public File dir { get; private set; }
    public string collation { get; private set; }
    
    private int _count = 0;
    public int count { 
        get {
            return _count;
        }
        
        set {
            int prev_count = _count; 
            _count = value;
            
            // when count change 0->1 and 1->0 may need refresh icon
            if ((prev_count == 0 && _count == 1) || (prev_count == 1 && _count == 0))
                sidebar_icon_changed(get_sidebar_icon());
            
        }
    }
    
    public SidebarEntry(File dir) {
        this.dir = dir;
        collation = dir.get_path().collate_key_for_filename();
    }
    
    public override string get_sidebar_name() {
        return dir.get_basename();
    }
    
    public override string? get_sidebar_icon() {
        return count == 0 ? icon : have_photos_icon;
    }
    
    public override string to_string() {
        return dir.get_path();
    }
    
    public bool expand_on_select() {
        return true;
    }
    
    protected override global::Page create_page() {
        return new Folders.Page(dir);
    }
}
