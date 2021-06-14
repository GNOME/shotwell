/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public abstract class EventsDirectoryPage : CheckerboardPage {
    public class EventDirectoryManager : ViewManager {
        public override DataView create_view(DataSource source) {
            return new EventDirectoryItem((Event) source);
        }
    }
    
    private class EventsDirectorySearchViewFilter : SearchViewFilter {
        public override uint get_criteria() {
            return SearchFilterCriteria.TEXT;
        }

        public override bool predicate(DataView view) {
            assert(view.get_source() is Event);
            if (is_string_empty(get_search_filter()))
                return true;
            
            Event source = (Event) view.get_source();
            unowned string? event_keywords = source.get_indexable_keywords();
            if (is_string_empty(event_keywords))
                return false;
            
            // Return false if the word isn't found, true otherwise.
            foreach (unowned string word in get_search_filter_words()) {
                if (!event_keywords.contains(word))
                    return false;
            }
            
            return true;
        }
    }
   
    private const int MIN_PHOTOS_FOR_PROGRESS_WINDOW = 50;

    protected ViewManager view_manager;
    
    private EventsDirectorySearchViewFilter search_filter = new EventsDirectorySearchViewFilter();

    protected EventsDirectoryPage(string page_name, ViewManager view_manager,
        Gee.Collection<Event>? initial_events) {
        base (page_name);
        
        // set comparator before monitoring source collection, to prevent a re-sort
        get_view().set_comparator(get_event_comparator(Config.Facade.get_instance().get_events_sort_ascending()), 
            event_comparator_predicate);
        get_view().monitor_source_collection(Event.global, view_manager, null, initial_events);
        
        get_view().set_property(Event.PROP_SHOW_COMMENTS,
            Config.Facade.get_instance().get_display_event_comments());
        
        init_item_context_menu("EventsDirectoryContextMenu");

        this.view_manager = view_manager;

        // set up page's toolbar (used by AppWindow for layout and FullscreenWindow as a popup)
        Gtk.Toolbar toolbar = get_toolbar();
        
        // merge tool
        Gtk.ToolButton merge_button = new Gtk.ToolButton (null, Resources.MERGE_LABEL);
        merge_button.set_action_name("win.Merge");
        merge_button.is_important = true;
        merge_button.set_tooltip_text (Resources.MERGE_TOOLTIP);
        merge_button.set_icon_name ("events-merge-symbolic");
        
        toolbar.insert(merge_button, -1);
    }
    
    ~EventsDirectoryPage() {
        var action = get_action("CommonSortEvents") as GLib.SimpleAction;
        assert(action != null);
        action.change_state.disconnect(on_sort_changed);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        ui_filenames.add("events_directory.ui");
        
        base.init_collect_ui_filenames(ui_filenames);
    }

    protected static bool event_comparator_predicate(DataObject object, Alteration alteration) {
        return alteration.has_detail("metadata", "time");
    }
    
    private static int64 event_ascending_comparator(void *a, void *b) {
        time_t start_a = ((EventDirectoryItem *) a)->event.get_start_time();
        time_t start_b = ((EventDirectoryItem *) b)->event.get_start_time();
        
        return start_a - start_b;
    }
    
    private static int64 event_descending_comparator(void *a, void *b) {
        return event_ascending_comparator(b, a);
    }
    
    private static Comparator get_event_comparator(bool ascending) {
        if (ascending)
            return event_ascending_comparator;
        else
            return event_descending_comparator;
    }

    private const GLib.ActionEntry[] entries = {
        { "Rename", on_rename },
        { "Merge", on_merge },
        { "EditComment", on_edit_comment },

        // Toggle actions
        { "ViewComment", on_action_toggle, null, "false", on_display_comments  }
    };

    protected override void add_actions (GLib.ActionMap map) {
        base.add_actions (map);
        map.add_action_entries (entries, this);

        var display_comments = Config.Facade.get_instance().get_display_event_comments();
        get_action ("ViewComment").change_state (display_comments);
    }

    protected override void remove_actions(GLib.ActionMap map) {
        base.remove_actions(map);
        foreach (var entry in entries) {
            map.remove_action(entry.name);
        }
    }

    protected override void init_actions(int selected_count, int count) {
        base.init_actions(selected_count, count);
        
        var action = get_action("CommonSortEvents") as GLib.SimpleAction;
        assert(action != null);
        action.change_state.connect(on_sort_changed);
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("Merge", selected_count > 1);
        set_action_sensitive("Rename", selected_count == 1);
        set_action_sensitive("EditComment", selected_count == 1);
        
        base.update_actions(selected_count, count);
    }

    protected override string get_view_empty_message() {
        return _("No events");
    }

    protected override string get_filter_no_match_message() {
        return _("No events found");
    }
    
    public override void on_item_activated(CheckerboardItem item, CheckerboardPage.Activator 
        activator, CheckerboardPage.KeyboardModifiers modifiers) {
        EventDirectoryItem event = (EventDirectoryItem) item;
        LibraryWindow.get_app().switch_to_event(event.event);
    }
    
    private void on_sort_changed(GLib.SimpleAction action, Variant? value) {
        get_view().set_comparator(
            get_event_comparator(value.get_string() == LibraryWindow.SORT_EVENTS_ORDER_ASCENDING),
            event_comparator_predicate);

        action.set_state (value);
    }
    
    private void on_rename() {
        // only rename one at a time
        if (get_view().get_selected_count() != 1)
            return;
        
        EventDirectoryItem item = (EventDirectoryItem) get_view().get_selected_at(0);
        
        EventRenameDialog rename_dialog = new EventRenameDialog(item.event.get_raw_name());
        string? new_name = rename_dialog.execute();
        if (new_name == null)
            return;
        
        RenameEventCommand command = new RenameEventCommand(item.event, new_name);
        get_command_manager().execute(command);
    }
    
    protected void on_edit_comment() {
        // only edit one at a time
        if (get_view().get_selected_count() != 1)
            return;
        
        EventDirectoryItem item = (EventDirectoryItem) get_view().get_selected_at(0);
        
        EditCommentDialog edit_comment_dialog = new EditCommentDialog(item.event.get_comment(),
        true);
        string? new_comment = edit_comment_dialog.execute();
        if (new_comment == null)
            return;
        
        EditEventCommentCommand command = new EditEventCommentCommand(item.event, new_comment);
        get_command_manager().execute(command);
    }
    
    private void on_merge() {
        if (get_view().get_selected_count() <= 1)
            return;
        
        MergeEventsCommand command = new MergeEventsCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
    
    private void on_display_comments(GLib.SimpleAction action, Variant? value) {
        bool display = value.get_boolean ();
        
        set_display_comments(display);
        
        Config.Facade.get_instance().set_display_event_comments(display);

        action.set_state (value);
    }
    
    public override SearchViewFilter get_search_view_filter() {
       return search_filter;
    }
}

public class MasterEventsDirectoryPage : EventsDirectoryPage {
    public const string NAME = _("All Events");
    
    public MasterEventsDirectoryPage() {
        base (NAME, new EventDirectoryManager(), (Gee.Collection<Event>) Event.global.get_all());
    }
}

public class SubEventsDirectoryPage : EventsDirectoryPage {
    public enum DirectoryType {
        YEAR,
        MONTH,
        UNDATED;
    }
    
    public const string UNDATED_PAGE_NAME = _("Undated");
    public const string YEAR_FORMAT = _("%Y");
    public const string MONTH_FORMAT = _("%B");
    
    private class SubEventDirectoryManager : EventsDirectoryPage.EventDirectoryManager {
        private int month = 0;
        private int year = 0;
        DirectoryType type;

        public SubEventDirectoryManager(DirectoryType type, Time time) {
            base();
            
            if (type == DirectoryType.MONTH)
                month = time.month;
            this.type = type;
            year = time.year; 
        }

        public override bool include_in_view(DataSource source) {
            if (!base.include_in_view(source))
                return false;
            
            EventSource event = (EventSource) source;
            Time event_time = Time.local(event.get_start_time());
            if (event_time.year == year) {
                if (type == DirectoryType.MONTH) {
                    return (event_time.month == month);
                }
                return true;
            }
            return false;
        }

        public int get_month() {
            return month;
        }

        public int get_year() {
            return year;
        }

        public DirectoryType get_event_directory_type() {
            return type;
        }
    }

    public SubEventsDirectoryPage(DirectoryType type, Time time) {
        string page_name;
        if (type == SubEventsDirectoryPage.DirectoryType.UNDATED) {
            page_name = UNDATED_PAGE_NAME;
        } else {
            page_name = time.format((type == DirectoryType.YEAR) ? YEAR_FORMAT : MONTH_FORMAT);
        }

        base(page_name, new SubEventDirectoryManager(type, time), null); 
    }
    
    public int get_month() {
        return ((SubEventDirectoryManager) view_manager).get_month();
    }

    public int get_year() {
        return ((SubEventDirectoryManager) view_manager).get_year();
    }

    public DirectoryType get_event_directory_type() {
        return ((SubEventDirectoryManager) view_manager).get_event_directory_type();
    }
}

