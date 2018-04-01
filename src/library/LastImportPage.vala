/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class LastImportPage : CollectionPage {
    public const string NAME = _("Last Import");
    
    private class LastImportViewManager : CollectionViewManager {
        private ImportID import_id;
        
        public LastImportViewManager(LastImportPage owner, ImportID import_id) {
            base (owner);
            
            this.import_id = import_id;
        }
        
        public override bool include_in_view(DataSource source) {
            return ((MediaSource) source).get_import_id().id == import_id.id;
        }
    }
    
    private ImportID last_import_id = ImportID();
    private Alteration last_import_alteration = new Alteration("metadata", "import-id");
    
    public LastImportPage() {
        base (NAME);
        
        // be notified when the import rolls change
        foreach (MediaSourceCollection col in MediaCollectionRegistry.get_instance().get_all()) {
            col.import_roll_altered.connect(on_import_rolls_altered);
        }
        
        // set up view manager for the last import roll
        on_import_rolls_altered();
    }

    public LastImportPage.for_id(ImportID id) {
        base(NAME);

        this.last_import_id = id;

        get_view().halt_all_monitoring();
        get_view().clear();

        foreach (MediaSourceCollection col in MediaCollectionRegistry.get_instance().get_all()) {
            get_view().monitor_source_collection(col, new LastImportViewManager(this,
                last_import_id), last_import_alteration);
        }
     }
    
    ~LastImportPage() {
        foreach (MediaSourceCollection col in MediaCollectionRegistry.get_instance().get_all()) {
            col.import_roll_altered.disconnect(on_import_rolls_altered);
        }
    }
    
    private void on_import_rolls_altered() {
        // see if there's a new last ImportID, or no last import at all
        ImportID? current_last_import_id =
            MediaCollectionRegistry.get_instance().get_last_import_id();

        if (current_last_import_id == null) {
            get_view().halt_all_monitoring();
            get_view().clear();
            
            return;
        }
        
        if (current_last_import_id.id == last_import_id.id)
            return;
        
        last_import_id = current_last_import_id;
        
        get_view().halt_all_monitoring();
        get_view().clear();
        
        foreach (MediaSourceCollection col in MediaCollectionRegistry.get_instance().get_all()) {
            get_view().monitor_source_collection(col, new LastImportViewManager(this,
                last_import_id), last_import_alteration);
        }
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.Facade.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }
    
    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.Facade.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

