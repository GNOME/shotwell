/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class FlaggedPage : CollectionPage {
    public class Stub : PageStub {
        public Stub() {
        }
        
        protected override Page construct_page() {
            return new FlaggedPage(get_name());
        }
        
        public override string get_name() {
            return _("Flagged");
        }
    }
    
    private class FlaggedViewManager : CollectionViewManager {
        public FlaggedViewManager(FlaggedPage owner) {
            base (owner);
        }
        
        public override bool include_in_view(DataSource source) {
            Flaggable? flaggable = source as Flaggable;
            
            return (flaggable != null) && flaggable.is_flagged();
        }
    }
    
    private ViewManager view_manager;
    private Alteration prereq = new Alteration("metadata", "flagged");
    
    private FlaggedPage(string name) {
        base (name);
        
        view_manager = new FlaggedViewManager(this);
        
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all())
            get_view().monitor_source_collection(sources, view_manager, prereq);
    }
    
    public static Stub create_stub() {
        return new Stub();
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }
    
    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

