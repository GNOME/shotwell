/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Source monitoring for saved searches.
private class SavedSearchManager : CollectionViewManager {
    SavedSearch search;
    public SavedSearchManager(SavedSearchPage owner, SavedSearch search) {
        base (owner);
        this.search = search;
    }
    
    public override bool include_in_view(DataSource source) {
        return search.predicate((MediaSource) source);
    }
}

// Page for displaying saved searches.
public class SavedSearchPage : CollectionPage {

    // The search logic and parameters are contained in the SavedSearch.
    private SavedSearch search;
    
    public SavedSearchPage(SavedSearch search) {
        base (search.get_name());
        this.search = search;
        
        
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all())
            get_view().monitor_source_collection(sources, new SavedSearchManager(this, search), null);
        
        init_page_context_menu("/SearchContextMenu");
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.Facade.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }
    
    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.Facade.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        ui_filenames.add("savedsearch.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry rename_search = { "RenameSearch", null, TRANSLATABLE, null, null, on_rename_search };
        actions += rename_search;
        
        Gtk.ActionEntry edit_search = { "EditSearch", null, TRANSLATABLE, null, null, on_edit_search };
        actions += edit_search;
        
        Gtk.ActionEntry delete_search = { "DeleteSearch", null, TRANSLATABLE, null, null, on_delete_search };
        actions += delete_search;
        
        return actions;
    }
    
    private void on_delete_search() {
        if (Dialogs.confirm_delete_saved_search(search))
            AppWindow.get_command_manager().execute(new DeleteSavedSearchCommand(search));
    }
    
    private void on_rename_search() {
        LibraryWindow.get_app().rename_search_in_sidebar(search);
    }
    
    private void on_edit_search() {
        SavedSearchDialog ssd = new SavedSearchDialog.edit_existing(search);
        ssd.show();
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_details("RenameSearch",
            Resources.RENAME_SEARCH_MENU,
            null, true);
        set_action_details("EditSearch",
            Resources.EDIT_SEARCH_MENU,
            null, true);
        set_action_details("DeleteSearch",
            Resources.DELETE_SEARCH_MENU,
            null, true);
        base.update_actions(selected_count, count);
    }
}

