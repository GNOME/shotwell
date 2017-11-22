/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Folders.Page : CollectionPage {
    private class FolderViewManager : CollectionViewManager {
        public File dir;
        
        public FolderViewManager(Folders.Page owner, File dir) {
            base (owner);
            
            this.dir = dir;
        }
        
        public override bool include_in_view(DataSource source) {
            return ((MediaSource) source).get_file().has_prefix(dir);
        }
    }
    
    private FolderViewManager view_manager;
    
    public Page(File dir) {
        base (dir.get_path());
        
        view_manager = new FolderViewManager(this, dir);
        
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all())
            get_view().monitor_source_collection(sources, view_manager, null);
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.Facade.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }
    
    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.Facade.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

