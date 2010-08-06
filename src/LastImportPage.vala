/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class LastImportPage : CollectionPage {
    public class Stub : PageStub {
        public Stub() {
        }
        
        protected override Page construct_page() {
            return new LastImportPage(get_name());
        }
        
        public override string get_name() {
            return _("Last Import");
        }
        
        public override string? get_icon_name() {
            return Resources.ICON_LAST_IMPORT;
        }
        
        public override bool is_renameable() {
            return false;
        }
    }
    
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
    
    private ImportID last_import_id = ImportID();
    
    private LastImportPage(string name) {
        base (name);
        
        // be notified when the import rolls change
        LibraryPhoto.global.import_roll_altered.connect(on_import_rolls_altered);
        
        // set up view manager for the last import roll
        on_import_rolls_altered();
    }
    
    public static Stub create_stub() {
        return new Stub();
    }
    
    private void on_import_rolls_altered() {
        // see if there's a new last ImportID, or no last import at all
        ImportID? current_last_import_id = LibraryPhoto.global.get_last_import_id();
        if (current_last_import_id == null) {
            get_view().halt_monitoring();
            get_view().clear();
            
            return;
        }
        
        if (current_last_import_id.id == last_import_id.id)
            return;
        
        last_import_id = current_last_import_id;
        
        get_view().monitor_source_collection(LibraryPhoto.global,
            new LastImportViewManager(this, last_import_id));
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }
    
    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

