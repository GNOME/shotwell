/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class Searches.Branch : Sidebar.Branch {
    private Gee.HashMap<SavedSearch, Searches.SidebarEntry> entry_map = 
        new Gee.HashMap<SavedSearch, Searches.SidebarEntry>();
    
    public Branch() {
        base (new Searches.Grouping(),
            Sidebar.Branch.Options.HIDE_IF_EMPTY
                | Sidebar.Branch.Options.AUTO_OPEN_ON_NEW_CHILD
                | Sidebar.Branch.Options.STARTUP_EXPAND_TO_FIRST_CHILD,
            comparator);
        
        // seed the branch with existing searches
        foreach (SavedSearch search in SavedSearchTable.get_instance().get_all())
            on_saved_search_added(search);
        
        // monitor collection for future events
        SavedSearchTable.get_instance().search_added.connect(on_saved_search_added);
        SavedSearchTable.get_instance().search_removed.connect(on_saved_search_removed);
    }
    
    ~Branch() {
        SavedSearchTable.get_instance().search_added.disconnect(on_saved_search_added);
        SavedSearchTable.get_instance().search_removed.disconnect(on_saved_search_removed);
    }
    
    public Searches.SidebarEntry? get_entry_for_saved_search(SavedSearch search) {
        return entry_map.get(search);
    }
    
    private static int comparator(Sidebar.Entry a, Sidebar.Entry b) {
        if (a == b)
            return 0;
        
        return SavedSearch.compare_names(((Searches.SidebarEntry) a).for_saved_search(),
            ((Searches.SidebarEntry) b).for_saved_search());
    }
    
    private void on_saved_search_added(SavedSearch search) {
        debug("search added");
        Searches.SidebarEntry entry = new Searches.SidebarEntry(search);
        entry_map.set(search, entry);
        graft(get_root(), entry);
    }
    
    private void on_saved_search_removed(SavedSearch search) {
        debug("search removed");
        Searches.SidebarEntry? entry = entry_map.get(search);
        assert(entry != null);
        
        bool is_removed = entry_map.unset(search);
        assert(is_removed);
        
        prune(entry);
    }
}

public class Searches.Grouping : Sidebar.Grouping, Sidebar.Contextable {
    private Gtk.UIManager ui = new Gtk.UIManager();
    private Gtk.Menu? context_menu = null;
    
    public Grouping() {
        base (_("Saved Searches"), new ThemedIcon(Gtk.Stock.FIND));
        setup_context_menu();
    }
    
    private void setup_context_menu() {
        Gtk.ActionGroup group = new Gtk.ActionGroup("SidebarDefault");
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry new_search = { "CommonNewSearch", null, TRANSLATABLE, null, null, on_new_search };
        new_search.label = _("Ne_w Saved Search...");
        actions += new_search;
        
        group.add_actions(actions, this);
        ui.insert_action_group(group, 0);
        
        File ui_file = Resources.get_ui("search_sidebar_context.ui");
        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error err) {
            AppWindow.error_message("Error loading UI file %s: %s".printf(
                ui_file.get_path(), err.message));
            Application.get_instance().panic();
        }
        context_menu = (Gtk.Menu) ui.get_widget("/SidebarSearchContextMenu");
        
        ui.ensure_update();
    }
    
    public Gtk.Menu? get_sidebar_context_menu(Gdk.EventButton? event) {
        return context_menu;
    }
    
    private void on_new_search() {
        (new SavedSearchDialog()).show();
    }
}

public class Searches.SidebarEntry : Sidebar.SimplePageEntry, Sidebar.RenameableEntry,
    Sidebar.DestroyableEntry {
    private static Icon single_search_icon;
    
    private SavedSearch search;
    
    public SidebarEntry(SavedSearch search) {
        this.search = search;
    }
    
    internal static void init() {
        single_search_icon = new ThemedIcon(Gtk.Stock.FIND);
    }
    
    internal static void terminate() {
        single_search_icon = null;
    }
    
    public SavedSearch for_saved_search() {
        return search;
    }
    
    public override string get_sidebar_name() {
        return search.get_name();
    }
    
    public override Icon? get_sidebar_icon() {
        return single_search_icon;
    }
    
    protected override Page create_page() {
        return new SavedSearchPage(search);
    }
    
    public void rename(string new_name) {
        if (!SavedSearchTable.get_instance().exists(new_name))
            AppWindow.get_command_manager().execute(new RenameSavedSearchCommand(search, new_name));
        else if (new_name != search.get_name())
            AppWindow.error_message(Resources.rename_search_exists_message(new_name));
    }
    
    public void destroy_source() {
        if (Dialogs.confirm_delete_saved_search(search))
            AppWindow.get_command_manager().execute(new DeleteSavedSearchCommand(search));
    }
}
