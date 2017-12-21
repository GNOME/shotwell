/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class FlaggedPage : CollectionPage {
    public const string NAME = _("Flagged");
    
    private class FlaggedViewManager : CollectionViewManager {
        public FlaggedViewManager(FlaggedPage owner) {
            base (owner);
        }
        
        public override bool include_in_view(DataSource source) {
            Flaggable? flaggable = source as Flaggable;
            
            return (flaggable != null) && flaggable.is_flagged();
        }
    }
    
    private class FlaggedSearchViewFilter : CollectionPage.CollectionSearchViewFilter {
        public override uint get_criteria() {
            return SearchFilterCriteria.TEXT | SearchFilterCriteria.MEDIA | 
                SearchFilterCriteria.RATING  | SearchFilterCriteria.SAVEDSEARCH;
        }
    }
    
    private ViewManager view_manager;
    private Alteration prereq = new Alteration("metadata", "flagged");
    private FlaggedSearchViewFilter search_filter = new FlaggedSearchViewFilter();
    
    public FlaggedPage() {
        base (NAME);
        
        view_manager = new FlaggedViewManager(this);
        
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all())
            get_view().monitor_source_collection(sources, view_manager, prereq);
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.Facade.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }
    
    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.Facade.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
    
    public override SearchViewFilter get_search_view_filter() {
        return search_filter;
    }
}

