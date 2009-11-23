/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

class EventDirectoryItem : LayoutItem {
    public const int SCALE = ThumbnailCache.Size.MEDIUM.get_scale() 
        + ((ThumbnailCache.Size.BIG.get_scale() - ThumbnailCache.Size.MEDIUM.get_scale()) / 2);
    
    public Event event;

    private Dimensions image_dim = Dimensions();

    public EventDirectoryItem(Event event) {
        base(event, event.get_primary_photo().get_dimensions().get_scaled(SCALE, true));
        
        this.event = event;
        
        set_title(event.get_name());
        
        // stash the image size for when it's not being displayed
        image_dim = event.get_primary_photo().get_dimensions().get_scaled(SCALE, true);
        clear_image(image_dim);
        
        // monitor the event for changes
        event.altered += on_event_altered;
    }
    
    ~EventDirectoryItem() {
        event.altered -= on_event_altered;
    }

    public override void exposed() {
        if (is_exposed())
            return;
        
        try {
            set_image(event.get_primary_photo().get_preview_pixbuf(Scaling.for_best_fit(SCALE)));
        } catch (Error err) {
            critical("Unable to fetch preview for %s: %s", event.to_string(), err.message);
        }
        
        base.exposed();
    }
    
    public override void unexposed() {
        if (!is_exposed())
            return;
        
        clear_image(image_dim);
        
        base.unexposed();
    }
    
    private void on_event_altered() {
        set_title(event.get_name());
    }
    
    private override void thumbnail_altered() {
        // get new dimensions
        image_dim = event.get_primary_photo().get_dimensions().get_scaled(SCALE, true);
        
        if (is_exposed()) {
            try {
                set_image(event.get_primary_photo().get_preview_pixbuf(Scaling.for_best_fit(SCALE)));
            } catch (Error err) {
                critical("Unable to fetch preview for %s: %s", event.to_string(), err.message);
            }
        } else {
            clear_image(image_dim);
        }
        
        base.thumbnail_altered();
    }
}

public class EventsDirectoryPage : CheckerboardPage {
    private class CompareEventItem : Comparator<EventDirectoryItem> {
        private bool ascending;
        
        public CompareEventItem(bool ascending) {
            this.ascending = ascending;
        }
        
        public override int64 compare(EventDirectoryItem a, EventDirectoryItem b) {
            int64 start_a = (int64) a.event.get_start_time();
            int64 start_b = (int64) b.event.get_start_time();
            
            return (ascending) ? start_a - start_b : start_b - start_a;
        }
    }
    
    public class EventDirectoryManager : ViewManager {
        public override DataView create_view(DataSource source) {
            return new EventDirectoryItem((Event) source);
        }
    }
   
    private const int MIN_PHOTOS_FOR_PROGRESS_WINDOW = 50;

    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton merge_button;
    protected ViewManager view_manager;

    public EventsDirectoryPage(string page_name, ViewManager view_manager) {
        base(page_name);
        get_view().monitor_source_collection(Event.global, view_manager);
        init_ui_start("events_directory.ui", "EventsDirectoryActionGroup", create_actions());
        init_ui_bind("/EventsDirectoryMenuBar");
        
        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        get_view().set_comparator(new CompareEventItem(
            LibraryWindow.get_app().get_events_sort() == LibraryWindow.SORT_EVENTS_ORDER_ASCENDING));

        init_item_context_menu("/EventsDirectoryContextMenu");

        this.view_manager = view_manager;

        // set up page's toolbar (used by AppWindow for layout and FullscreenWindow as a popup)
        //
        // merge tool
        merge_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_ADD);
        merge_button.set_label(Resources.MERGE_LABEL);
        merge_button.set_tooltip_text(Resources.MERGE_TOOLTIP);
        merge_button.clicked += on_merge;
        merge_button.sensitive = (get_view().get_selected_count() > 1);
        merge_button.is_important = true;
        toolbar.insert(merge_button, -1);

        get_view().items_state_changed += on_selection_changed;
    }

    ~EventsDirectoryPage() {
        get_view().items_state_changed -= on_selection_changed;
    }

    private void on_selection_changed() {
        merge_button.sensitive = (get_view().get_selected_count() > 1);
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, null };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, on_view_menu };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, on_edit_menu };
        edit.label = _("_Edit");
        actions += edit;

        Gtk.ActionEntry event = { "EventsMenu", null, TRANSLATABLE, null, null, on_events_menu };
        event.label = _("Even_ts");
        actions += event;

        Gtk.ActionEntry rename = { "Rename", null, TRANSLATABLE, "F2", TRANSLATABLE, on_rename };
        rename.label = Resources.RENAME_EVENT_MENU;
        rename.tooltip = Resources.RENAME_EVENT_TOOLTIP;
        actions += rename;
       
        Gtk.ActionEntry merge = { "Merge", Gtk.STOCK_ADD, TRANSLATABLE, "<Ctrl>M", TRANSLATABLE, on_merge };
        merge.label = Resources.MERGE_MENU;
        merge.tooltip = Resources.MERGE_TOOLTIP;
        actions += merge;

        return actions;
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void on_item_activated(LayoutItem item) {
        EventDirectoryItem event = (EventDirectoryItem) item;
        LibraryWindow.get_app().switch_to_event(event.event);
    }

    protected override bool on_context_invoked(Gtk.Menu context_menu) {
        set_item_sensitive("/EventsDirectoryContextMenu/ContextRename", 
            get_view().get_selected_count() == 1);
        set_item_sensitive("/EventsDirectoryContextMenu/ContextMerge", 
            get_view().get_selected_count() > 1);
        
        return true;
    }

    private EventDirectoryItem? get_fullscreen_item() {
        // use first selected item, otherwise use first item
        if (get_view().get_selected_count() > 0)
            return (EventDirectoryItem?) get_view().get_selected_at(0);
        else if (get_view().get_count() > 0)
            return (EventDirectoryItem?) get_view().get_at(0);
        else
            return null;
    }
    
    public EventPage? get_fullscreen_event() {
        EventDirectoryItem item = get_fullscreen_item();

        // Yeah, this sucks.  We can do better.
        return (item != null) ? LibraryWindow.get_app().load_event_page(item.event) : null;
    }
    
    public override LayoutItem? get_fullscreen_photo() {
        EventPage page = get_fullscreen_event();
        
        return (page != null) ? page.get_fullscreen_photo() : null;
    }

    public void notify_sort_changed(int sort) {
        get_view().set_comparator(new CompareEventItem(sort == LibraryWindow.SORT_EVENTS_ORDER_ASCENDING));
    }
    
    private void on_view_menu() {
        set_item_sensitive("/EventsDirectoryMenuBar/ViewMenu/Fullscreen", get_view().get_count() > 0);
    }

    private void on_edit_menu() {
        decorate_undo_item("/EventsDirectoryMenuBar/EditMenu/Undo");
        decorate_redo_item("/EventsDirectoryMenuBar/EditMenu/Redo");
        set_item_sensitive("/EventsDirectoryMenuBar/EditMenu/EventRename", 
            get_view().get_selected_count() == 1);
    }

    private void on_events_menu() {
        set_item_sensitive("/EventsDirectoryMenuBar/EventsMenu/EventMerge", 
            get_view().get_selected_count() > 1);
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
    
    private void on_merge() {
        if (get_view().get_selected_count() <= 1)
            return;
        
        MergeEventsCommand command = new MergeEventsCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
}

public class EventPage : CollectionPage {
    private class EventViewManager : CollectionViewManager {
        private EventID event_id;
        
        public EventViewManager(EventPage page) {
            base(page);
            
            event_id = page.page_event.get_event_id();
        }
        
        public override bool include_in_view(DataSource source) {
            LibraryPhoto photo = (LibraryPhoto) source;
            EventID photo_event_id = photo.get_event_id();
            
            return photo_event_id.id == event_id.id;
        }
    }
    
    public Event page_event;

    public EventPage(Event page_event) {
        base(page_event.get_name(), "event.ui", create_actions());
        
        this.page_event = page_event;
        
        get_view().monitor_source_collection(LibraryPhoto.global, new EventViewManager(this));
        
        init_page_context_menu("/EventContextMenu");
    }
    
    private static Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] new_actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry make_primary = { "MakePrimary", Resources.MAKE_PRIMARY,
            TRANSLATABLE, null, null, on_make_primary };
        make_primary.label = Resources.MAKE_KEY_PHOTO_MENU;
        make_primary.tooltip = Resources.MAKE_KEY_PHOTO_TOOLTIP;
        new_actions += make_primary;

        Gtk.ActionEntry rename = { "Rename", null, TRANSLATABLE, "F2", TRANSLATABLE, on_rename };
        rename.label = Resources.RENAME_EVENT_MENU;
        rename.tooltip = Resources.RENAME_EVENT_TOOLTIP;
        new_actions += rename;

        return new_actions;
    }
    
    protected override void on_photos_menu() {
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/MakePrimary", 
            get_view().get_selected_count() == 1);
        
        base.on_photos_menu();
    }
    
    private void on_make_primary() {
        if (get_view().get_selected_count() == 0)
            return;
        
        // use first one
        DataView view = get_view().get_selected_at(0);
        page_event.set_primary_photo(((Thumbnail) view).get_photo());
    }

    public void rename(string name) {
        page_event.rename(name);
        set_page_name(page_event.get_name());
    }

    private void on_rename() {
        EventRenameDialog rename_dialog = new EventRenameDialog(page_event.get_raw_name());
        string? new_name = rename_dialog.execute();
        if (new_name == null)
            return;
        
        RenameEventCommand command = new RenameEventCommand(page_event, new_name);
        get_command_manager().execute(command);
    }
}

public class MasterEventsDirectoryPage : EventsDirectoryPage {
    public MasterEventsDirectoryPage() {
        base(_("Events"), new EventDirectoryManager());
    }
}

public class SubEventsDirectoryPage : EventsDirectoryPage {
    public enum DirectoryType {
        YEAR,
        MONTH;
    }

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
        base(time.format((type == DirectoryType.YEAR) ? _("%Y") : _("%B")), new SubEventDirectoryManager(type, time)); 
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
