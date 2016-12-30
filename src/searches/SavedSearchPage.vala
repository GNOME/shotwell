/* Copyright 2016 Software Freedom Conservancy Inc.
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
        
        init_page_context_menu("SearchContextMenu");
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

    private const GLib.ActionEntry[] entries = {
        { "RenameSearch", on_rename_search },
        { "EditSearch", on_edit_search },
        { "DeleteSearch", on_delete_search }
    };

    protected override void add_actions(GLib.ActionMap map) {
        base.add_actions(map);

        map.add_action_entries(entries, this);
    }

    protected override void remove_actions(GLib.ActionMap map) {
        base.remove_actions(map);
        foreach (var entry in entries) {
            map.remove_action(entry.name);
        }
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
        set_action_sensitive ("RenameSearch", true);
        set_action_sensitive ("EditSearch", true);
        set_action_sensitive ("DeleteSearch", true);

        base.update_actions(selected_count, count);
    }
}

