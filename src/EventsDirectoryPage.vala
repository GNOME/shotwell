/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

class EventDirectoryItem : CheckerboardItem {
    public const int CROPPED_SCALE = ThumbnailCache.Size.MEDIUM.get_scale() 
        + ((ThumbnailCache.Size.BIG.get_scale() - ThumbnailCache.Size.MEDIUM.get_scale()) / 2);
        
    public static Scaling squared_scaling = Scaling.to_fill_viewport(Dimensions(CROPPED_SCALE, CROPPED_SCALE));
    
    public Event event;
    
    private Gdk.Rectangle paul_lynde = Gdk.Rectangle();
    
    public EventDirectoryItem(Event event) {
        base(event, Dimensions(CROPPED_SCALE, CROPPED_SCALE), get_formatted_title(event), true,
            Pango.Alignment.CENTER);
        
        this.event = event;
        
        // find the center square
        paul_lynde = get_paul_lynde_rect(event.get_primary_photo());
        
        // don't display yet, but claim its dimensions
        clear_image(Dimensions.for_rectangle(paul_lynde));
        
        // monitor the event for changes
        Event.global.items_altered.connect(on_events_altered);
    }
    
    ~EventDirectoryItem() {
        Event.global.items_altered.disconnect(on_events_altered);
    }
    
    // square the photo's dimensions and locate the pixbuf's center square
    private static Gdk.Rectangle get_paul_lynde_rect(LibraryPhoto photo) {
        Dimensions scaled = squared_scaling.get_scaled_dimensions(photo.get_dimensions());
        
        Gdk.Rectangle paul_lynde = Gdk.Rectangle();
        paul_lynde.x = (scaled.width - CROPPED_SCALE).clamp(0, scaled.width) / 2;
        paul_lynde.y = (scaled.height - CROPPED_SCALE).clamp(0, scaled.height) / 2;
        paul_lynde.width = CROPPED_SCALE;
        paul_lynde.height = CROPPED_SCALE;
        
        return paul_lynde;
    }
    
    // scale and crop the center square of the photo
    private static Gdk.Pixbuf get_paul_lynde(LibraryPhoto photo, Gdk.Rectangle paul_lynde) throws Error {
        Gdk.Pixbuf pixbuf = photo.get_preview_pixbuf(squared_scaling);
        
        // to catch rounding errors in the two algorithms
        paul_lynde = clamp_rectangle(paul_lynde, Dimensions.for_pixbuf(pixbuf));
        
        // crop the center square
        return new Gdk.Pixbuf.subpixbuf(pixbuf, paul_lynde.x, paul_lynde.y, paul_lynde.width,
            paul_lynde.height);
    }
    
    private static string get_formatted_title(Event event) {
        int count = event.get_photo_count();
        string count_text = ngettext("%d Photo", "%d Photos", count).printf(count);
        
        return "<b>%s</b>\n%s".printf(guarded_markup_escape_text(event.get_name()),
            guarded_markup_escape_text(count_text));
    }

    public override void exposed() {
        if (is_exposed())
            return;
        
        try {
            set_image(get_paul_lynde(event.get_primary_photo(), paul_lynde));
        } catch (Error err) {
            critical("Unable to fetch preview for %s: %s", event.to_string(), err.message);
        }
        
        base.exposed();
    }
    
    public override void unexposed() {
        if (!is_exposed())
            return;
        
        clear_image(Dimensions.for_rectangle(paul_lynde));
        
        base.unexposed();
    }
    
    private void on_events_altered(Gee.Map<DataObject, Alteration> map) {
        if (map.has_key(event))
            set_title(get_formatted_title(event), true, Pango.Alignment.CENTER);
    }
    
    protected override void thumbnail_altered() {
        LibraryPhoto photo = event.get_primary_photo();
        
        // get new center square
        paul_lynde = get_paul_lynde_rect(photo);
        
        if (is_exposed()) {
            try {
                set_image(get_paul_lynde(photo, paul_lynde));
            } catch (Error err) {
                critical("Unable to fetch preview for %s: %s", event.to_string(), err.message);
            }
        } else {
            clear_image(Dimensions.for_rectangle(paul_lynde));
        }
        
        base.thumbnail_altered();
    }
    
    protected override void paint_border(Gdk.GC gc, Gdk.Drawable drawable,
        Dimensions object_dimensions, Gdk.Point object_origin, int border_width) {
        Dimensions dimensions = get_border_dimensions(object_dimensions, border_width);
        Gdk.Point origin = get_border_origin(object_origin, border_width);

        draw_rounded_corners_filled(gc, drawable, dimensions, origin, 6.0);
    }

    protected override void paint_image(Gdk.GC gc, Gdk.Drawable drawable, Gdk.Pixbuf pixbuf,
        Gdk.Point origin) {
        Dimensions dimensions = Dimensions.for_pixbuf(pixbuf);

        if (pixbuf.get_has_alpha())
            draw_rounded_corners_filled(gc, drawable, dimensions, origin, 6.0);

        // use rounded corners on events
        Cairo.Context cx = get_rounded_corners_context(drawable, dimensions, origin, 6.0);
        Gdk.cairo_set_source_pixbuf(cx, pixbuf, origin.x, origin.y);
        cx.paint();
    }
}

public class EventsDirectoryPage : CheckerboardPage {
    public class EventDirectoryManager : ViewManager {
        public override DataView create_view(DataSource source) {
            return new EventDirectoryItem((Event) source);
        }
    }
   
    private const int MIN_PHOTOS_FOR_PROGRESS_WINDOW = 50;

    protected ViewManager view_manager;

    public EventsDirectoryPage(string page_name, ViewManager view_manager,
        Gee.Collection<Event>? initial_events) {
        base (page_name);
        
        // set comparator before monitoring source collection, to prevent a re-sort
        get_view().set_comparator(get_event_comparator(), event_comparator_predicate);
        get_view().monitor_source_collection(Event.global, view_manager, null, initial_events);
        
        // Adds one menu entry per alien database driver
        AlienDatabaseHandler.get_instance().add_menu_entries(
            ui, "/EventsDirectoryMenuBar/FileMenu/ImportFromAlienDbPlaceholder"
        );
        
        init_item_context_menu("/EventsDirectoryContextMenu");

        this.view_manager = view_manager;

        // set up page's toolbar (used by AppWindow for layout and FullscreenWindow as a popup)
        Gtk.Toolbar toolbar = get_toolbar();
        
        // merge tool
        Gtk.ToolButton merge_button = new Gtk.ToolButton.from_stock(Resources.MERGE);
        merge_button.set_related_action(action_group.get_action("Merge"));
        
        toolbar.insert(merge_button, -1);
    }
    
    protected override string? get_menubar_path() {
        return "/EventsDirectoryMenuBar";
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        ui_filenames.add("events_directory.ui");
        
        base.init_collect_ui_filenames(ui_filenames);
    }

    private static int64 event_ascending_comparator(void *a, void *b) {
        time_t start_a = ((EventDirectoryItem *) a)->event.get_start_time();
        time_t start_b = ((EventDirectoryItem *) b)->event.get_start_time();
        
        return start_a - start_b;
    }
    
    protected static bool event_comparator_predicate(DataObject object, Alteration alteration) {
        return alteration.has_detail("metadata", "time");
    }
    
    private int64 event_descending_comparator(void *a, void *b) {
        return event_ascending_comparator(b, a);
    }
    
    private Comparator get_event_comparator() {
        if (Config.get_instance().get_events_sort_ascending())
            return event_ascending_comparator;
        else
            return event_descending_comparator;
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, null };
        file.label = _("_File");
        actions += file;
        
        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, null };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, null };
        edit.label = _("_Edit");
        actions += edit;

        Gtk.ActionEntry event = { "EventsMenu", null, TRANSLATABLE, null, null, null };
        event.label = _("Even_ts");
        actions += event;

        Gtk.ActionEntry rename = { "Rename", null, TRANSLATABLE, "F2", TRANSLATABLE, on_rename };
        rename.label = Resources.RENAME_EVENT_MENU;
        rename.tooltip = Resources.RENAME_EVENT_TOOLTIP;
        actions += rename;
       
        Gtk.ActionEntry merge = { "Merge", Resources.MERGE, TRANSLATABLE, null, TRANSLATABLE,
            on_merge };
        merge.label = Resources.MERGE_MENU;
        merge.tooltip = Resources.MERGE_TOOLTIP;
        actions += merge;
        
        return actions;
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("Merge", selected_count > 1);
        set_action_important("Merge", true);
        set_action_sensitive("Rename", selected_count == 1);
        
        base.update_actions(selected_count, count);
    }
    
    public override void on_item_activated(CheckerboardItem item, CheckerboardPage.Activator 
        activator, CheckerboardPage.KeyboardModifiers modifiers) {
        EventDirectoryItem event = (EventDirectoryItem) item;
        LibraryWindow.get_app().switch_to_event(event.event);
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
    
    public override CheckerboardItem? get_fullscreen_photo() {
        EventPage page = get_fullscreen_event();
        
        return (page != null) ? page.get_fullscreen_photo() : null;
    }

    public void notify_sort_changed() {
        get_view().set_comparator(get_event_comparator(), event_comparator_predicate);
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

public class NoEventPage : CollectionPage {
    static const string NO_EVENT_PAGE_NAME = _("No Event");
    
    public class Stub : PageStub {
        public override string? get_icon_name() {
            return Resources.ICON_MISSING_FILES;
        }
        
        public override string get_name() {
            return NO_EVENT_PAGE_NAME;
        }
        
        public override bool is_renameable() {
            return false;
        }
        
        protected override Page construct_page() {
            return ((Page) new NoEventPage());
        }
    }
    
    // This seems very similar to EventSourceCollection -> ViewManager
    private class NoEventViewManager : CollectionViewManager {
        public NoEventViewManager(NoEventPage page) {
            base(page);
        }
        
        // this is not threadsafe
        public override bool include_in_view(DataSource source) {
            return (((LibraryPhoto) source).get_event_id().id != EventID.INVALID) ? false :
                base.include_in_view(source);
        }
    }
    
    private static Alteration no_event_page_alteration = new Alteration("metadata", "event");
    
    private NoEventPage() {
        base(NO_EVENT_PAGE_NAME);
        
        // Adds one menu entry per alien database driver
        AlienDatabaseHandler.get_instance().add_menu_entries(
            ui, "/EventsDirectoryMenuBar/FileMenu/ImportFromAlienDbPlaceholder"
        );
        
        get_view().monitor_source_collection(LibraryPhoto.global, new NoEventViewManager(this),
            no_event_page_alteration);
    }
    
    public static Stub create_stub() {
        return new Stub();
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_event_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_event_photos_sort(sort_order, sort_by);
    }
}


public class EventPage : CollectionPage {
    public class Stub : PageStub {
        public Event event;

        public Stub(Event event) {
            this.event = event;
        }

        public override string? get_icon_name() {
            return Resources.ICON_ONE_EVENT;
        }

        public override string get_name() {
            return event.get_name();
        }
        
        public override bool is_renameable() {
            return (event != null);
        }

        protected override Page construct_page() {
            return ((Page) new EventPage(event));
        }
    }
    
    public Event page_event;
    
    private EventPage(Event page_event) {
        base (page_event.get_name());
        
        // Adds one menu entry per alien database driver
        AlienDatabaseHandler.get_instance().add_menu_entries(
            ui, "/EventsDirectoryMenuBar/FileMenu/ImportFromAlienDbPlaceholder"
        );
        
        this.page_event = page_event;
        page_event.mirror_photos(get_view(), create_thumbnail);
        
        init_page_context_menu("/EventContextMenu");
        
        // hide this command in CollectionPage, as it does not apply here
        set_action_visible("JumpToEvent", false);
        
        Event.global.items_altered.connect(on_events_altered);
    }
    
    ~EventPage() {
        Event.global.items_altered.disconnect(on_events_altered);
        get_view().halt_mirroring();
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("event.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] new_actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry make_primary = { "MakePrimary", Resources.MAKE_PRIMARY,
            TRANSLATABLE, null, TRANSLATABLE, on_make_primary };
        make_primary.label = Resources.MAKE_KEY_PHOTO_MENU;
        make_primary.tooltip = Resources.MAKE_KEY_PHOTO_TOOLTIP;
        new_actions += make_primary;

        Gtk.ActionEntry rename = { "Rename", null, TRANSLATABLE, null, TRANSLATABLE, on_rename };
        rename.label = Resources.RENAME_EVENT_MENU;
        rename.tooltip = Resources.RENAME_EVENT_TOOLTIP;
        new_actions += rename;

        return new_actions;
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("MakePrimary", selected_count == 1);
        
        base.update_actions(selected_count, count);
    }
    
    public static Stub create_stub(Event event) {
        return new Stub(event);
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_event_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_event_photos_sort(sort_order, sort_by);
    }
    
    private void on_events_altered(Gee.Map<DataObject, Alteration> map) {
        if (map.has_key(page_event))
            set_page_name(page_event.get_name());
    }
    
    private void on_make_primary() {
        if (get_view().get_selected_count() != 1)
            return;
        
        page_event.set_primary_photo((LibraryPhoto) get_view().get_selected_at(0).get_source());
    }

    private void on_rename() {
        LibraryWindow.get_app().sidebar_rename_in_place(this);
    }
    
    public override void rename(string new_name) {
        get_command_manager().execute(new RenameEventCommand(page_event, new_name));
    }
}

public class MasterEventsDirectoryPage : EventsDirectoryPage {
    public class Stub : PageStub {
        public Stub() {
        }
        
        protected override Page construct_page() {
            return new MasterEventsDirectoryPage(get_name());
        }
        
        public override string get_name() {
            return _("Events");
        }
        
        public override string? get_icon_name() {
            return Resources.ICON_EVENTS;
        }
        
        public override bool is_renameable() {
            return false;
        }
    }
    
    private MasterEventsDirectoryPage(string name) {
        base(name, new EventDirectoryManager(), (Gee.Collection<Event>) Event.global.get_all());
    }
    
    public static Stub create_stub() {
        return new Stub();
    }
}

public class SubEventsDirectoryPage : EventsDirectoryPage {
    public enum DirectoryType {
        YEAR,
        MONTH,
        UNDATED;
    }
    
    public class Stub : PageStub {
        public SubEventsDirectoryPage.DirectoryType type;
        public Time time;
        private string page_name;

        public Stub(SubEventsDirectoryPage.DirectoryType type, Time time) {
            if (type == SubEventsDirectoryPage.DirectoryType.UNDATED) {
                this.page_name = _("Undated");
            } else {
                this.page_name = time.format((type == SubEventsDirectoryPage.DirectoryType.YEAR) ?
                    _("%Y") : _("%B"));
            }

            this.type = type;
            this.time = time;
        }

        protected override Page construct_page() {
            return new SubEventsDirectoryPage(type, time);
        }

        public int get_month() {
            return (type == SubEventsDirectoryPage.DirectoryType.MONTH) ? time.month : 0;
        }

        public int get_year() {
            return time.year;
        }

        public override string? get_icon_name() {
            return Resources.ICON_FOLDER_CLOSED;
        }

        public override string get_name() {
            return page_name;
        }
        
        public override bool is_renameable() {
            return false;
        }
        
        public bool matches(SubEventsDirectoryPage.DirectoryType type, Time time) {
            if (type != this.type)
                return false;

            if (type == SubEventsDirectoryPage.DirectoryType.UNDATED) {
                return true;
            } else if (type == SubEventsDirectoryPage.DirectoryType.MONTH) {
                return time.year == this.time.year && time.month == this.time.month;
            } else {
                assert(type == SubEventsDirectoryPage.DirectoryType.YEAR);
                return time.year == this.time.year;
            }
        }
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

    private SubEventsDirectoryPage(DirectoryType type, Time time) {
        string page_name;
        if (type == SubEventsDirectoryPage.DirectoryType.UNDATED) {
            page_name = _("Undated");
        } else {
            page_name = time.format((type == DirectoryType.YEAR) ? _("%Y") : _("%B"));
        }

        base(page_name, new SubEventDirectoryManager(type, time), null); 
    }
    
    public static Stub create_stub(DirectoryType type, Time time) {
        return new Stub(type, time);
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
