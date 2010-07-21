/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class LastImportPage : CollectionPage {
    private class LastImportViewManager : CollectionViewManager {
        private ImportID import_id;
        
        public LastImportViewManager(LastImportPage owner, ImportID import_id) {
            base (owner);
            
            this.import_id = import_id;
        }
        
        public override bool include_in_view(DataSource source) {
            return ((LibraryPhoto) source).get_import_id().id == import_id.id;
        }
    }
    
    public LastImportPage() {
        base (_("Last Import"));
        
        // be notified when the import rolls change
        LibraryPhoto.global.import_roll_altered.connect(on_import_rolls_altered);
        
        // set up view manager for the last import roll
        on_import_rolls_altered();
    }
    
    private void on_import_rolls_altered() {
        get_view().halt_monitoring();
        
        ImportID? last_import_id = LibraryPhoto.global.get_last_import_id();
        if (last_import_id != null) {
            get_view().monitor_source_collection(LibraryPhoto.global,
                new LastImportViewManager(this, last_import_id));
        }
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }
    
    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

