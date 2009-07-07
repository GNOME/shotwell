/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class FullscreenWindow : Gtk.Window {
    public static const int TOOLBAR_INVOCATION_MSEC = 250;
    public static const int TOOLBAR_DISMISSAL_SEC = 2;
    public static const int TOOLBAR_CHECK_DISMISSAL_MSEC = 500;
    
    public static const double TOOLBAR_OPACITY = 0.75;
    
    private Gdk.ModifierType ANY_BUTTON_MASK = 
        Gdk.ModifierType.BUTTON1_MASK | Gdk.ModifierType.BUTTON2_MASK | Gdk.ModifierType.BUTTON3_MASK;
    
    private const Gtk.ActionEntry[] ACTIONS = {
        { "LeaveFullscreen", Gtk.STOCK_LEAVE_FULLSCREEN, "Leave _Fullscreen", "Escape", "Leave fullscreen", on_close }
    };

    private Gtk.Window toolbar_window = new Gtk.Window(Gtk.WindowType.POPUP);
    private Gtk.UIManager ui = new Gtk.UIManager();
    private Page page;
    private Gtk.ToolButton close_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_LEAVE_FULLSCREEN);
    private Gtk.ToggleToolButton pin_button = new Gtk.ToggleToolButton.from_stock(Resources.PIN_TOOLBAR);
    private bool is_toolbar_shown = false;
    private bool waiting_for_invoke = false;
    private time_t left_toolbar_time = 0;

    public FullscreenWindow(Page page) {
        this.page = page;

        File ui_file = Resources.get_ui("fullscreen.ui");

        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error err) {
            error("Error loading UI file %s: %s", ui_file.get_path(), err.message);
        }
        
        Gtk.ActionGroup action_group = new Gtk.ActionGroup("FullscreenActionGroup");
        action_group.add_actions(ACTIONS, this);
        ui.insert_action_group(action_group, 0);
        ui.ensure_update();

        Gtk.AccelGroup accel_group = ui.get_accel_group();
        if (accel_group != null)
            add_accel_group(accel_group);
        
        set_screen(AppWindow.get_instance().get_screen());
        set_border_width(0);
        
        pin_button.set_label("Pin Toolbar");
        pin_button.set_tooltip_text("Pin the toolbar open");
        
        // TODO: Don't stock items supply their own tooltips?
        close_button.set_tooltip_text("Leave fullscreen");
        close_button.clicked += on_close;
        
        Gtk.Toolbar toolbar = page.get_toolbar();
        toolbar.set_show_arrow(false);
        toolbar.insert(pin_button, -1);
        toolbar.insert(close_button, -1);
        
        // set up toolbar along bottom of screen
        toolbar_window.set_screen(get_screen());
        toolbar_window.set_border_width(0);
        toolbar_window.add(toolbar);
        
        add(page);
        
        // need to do this to create a Gdk.Window to set masks
        fullscreen();
        show_all();
        
        add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.KEY_PRESS_MASK
            | Gdk.EventMask.KEY_RELEASE_MASK | Gdk.EventMask.STRUCTURE_MASK);
        motion_notify_event += on_motion;
        key_press_event += on_key_pressed;
        key_release_event += on_key_released;
        configure_event += on_configured;
        
        // start off with toolbar invoked, as a clue for the user
        invoke_toolbar();

        page.switched_to();
    }
    
    private void on_close() {
        toolbar_window.hide();
        toolbar_window = null;
        
        page.switching_from();
        
        AppWindow.get_instance().end_fullscreen();
    }
    
    private bool on_motion(FullscreenWindow fsw, Gdk.EventMotion event) {
        if (is_toolbar_shown)
            return false;

        // if pointer is in toolbar height range without the mouse down (i.e. in the middle of an edit
        // operation) and it stays there the necessary amount of time, invoke the toolbar
        if (!waiting_for_invoke && is_pointer_in_toolbar()) {
            Timeout.add(TOOLBAR_INVOCATION_MSEC, on_check_toolbar_invocation);
            waiting_for_invoke = true;
        }
        
        return false;
    }
    
    private bool on_key_pressed(Gdk.EventKey event) {
        return (event.is_modifier != 0) ? page.notify_modifier_pressed(event) : false;
    }
    
    private bool on_key_released(Gdk.EventKey event) {
        return (event.is_modifier != 0) ? page.notify_modifier_released(event) : false;
    }
    
    private bool on_configured(Gdk.EventConfigure event) {
        return page.notify_configure_event(event);
    }

    private bool is_pointer_in_toolbar() {
        int y, height;
        window.get_geometry(null, out y, null, out height, null);

        int py;
        Gdk.ModifierType mask;
        get_display().get_pointer(null, null, out py, out mask);
        
        Gtk.Requisition req;
        toolbar_window.size_request(out req);

        return ((mask & ANY_BUTTON_MASK) == 0) && (py >= (y + height - req.height));
    }
    
    private bool on_check_toolbar_invocation() {
        waiting_for_invoke = false;
        
        if (is_toolbar_shown)
            return false;
        
        if (!is_pointer_in_toolbar())
            return false;
        
        invoke_toolbar();
        
        return false;
    }
    
    private void invoke_toolbar() {
        toolbar_window.show_all();

        Gtk.Requisition req;
        toolbar_window.size_request(out req);
        
        // place the toolbar in the center of the screen along the bottom edge
        Gdk.Screen screen = toolbar_window.get_screen();
        int tx = (screen.get_width() - req.width) / 2;
        if (tx < 0)
            tx = 0;

        int ty = screen.get_height() - req.height;
        if (ty < 0)
            ty = 0;
            
        toolbar_window.move(tx, ty);
        toolbar_window.set_opacity(TOOLBAR_OPACITY);

        is_toolbar_shown = true;
        
        Timeout.add(TOOLBAR_CHECK_DISMISSAL_MSEC, on_check_toolbar_dismissal);
    }
    
    private bool on_check_toolbar_dismissal() {
        if (!is_toolbar_shown)
            return false;
        
        if (toolbar_window == null)
            return false;
        
        // if pinned, keep open but keep checking
        if (pin_button.get_active())
            return true;
        
        // if the pointer is in toolbar range, keep it alive, but keep checking
        if (is_pointer_in_toolbar()) {
            left_toolbar_time = 0;

            return true;
        }
        
        // if this is the first time noticed, start the timer and keep checking
        if (left_toolbar_time == 0) {
            left_toolbar_time = time_t();
            
            return true;
        }
        
        // see if enough time has elapsed
        time_t now = time_t();
        assert(now >= left_toolbar_time);

        if (now - left_toolbar_time < TOOLBAR_DISMISSAL_SEC)
            return true;
        
        toolbar_window.hide();
        is_toolbar_shown = false;
        
        return false;
    }
}

public class AppWindow : Gtk.Window {
    public static const string DATA_DIR = ".shotwell";
    public static const string PHOTOS_DIR = "Pictures";

    public static const int SIDEBAR_MIN_WIDTH = 160;
    public static const int SIDEBAR_MAX_WIDTH = 320;
    public static const int PAGE_MIN_WIDTH = 
        Thumbnail.MAX_SCALE + CollectionLayout.LEFT_PADDING + CollectionLayout.RIGHT_PADDING;
    
    public static Gdk.Color BG_COLOR = parse_color("#444");
    public static Gdk.Color SIDEBAR_BG_COLOR = parse_color("#EEE");

    public static const long EVENT_LULL_SEC = 3 * 60 * 60;
    public static const long EVENT_MAX_DURATION_SEC = 12 * 60 * 60;
    
    public static const int SORT_EVENTS_ORDER_ASCENDING = 0;
    public static const int SORT_EVENTS_ORDER_DESCENDING = 1;

    private static const string[] SUPPORTED_MOUNT_SCHEMES = {
        "gphoto2:",
        "disk:",
        "file:"
    };
    
    private static AppWindow instance = null;
    private static string[] args = null;
    private static bool user_quit = false;
    private static bool camera_update_scheduled = false;

    private const Gtk.TargetEntry[] DEST_TARGET_ENTRIES = {
        { "text/uri-list", 0, 0 }
    };
    
    // Common actions available to all pages
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] COMMON_ACTIONS = {
        { "CommonQuit", Gtk.STOCK_QUIT, "_Quit", "<Ctrl>Q", "Quit Shotwell", on_quit },
        { "CommonAbout", Gtk.STOCK_ABOUT, "_About", null, "About Shotwell", on_about },
        { "CommonFullscreen", Gtk.STOCK_FULLSCREEN, "_Fullscreen", "F11", "Use Shotwell at fullscreen", 
            on_fullscreen },
        { "CommonSortEvents", null, "Sort _Events", null, null, on_sort_events },
        { "CommonHelpContents", Gtk.STOCK_HELP, "_Contents", "F1", "More informaton on Shotwell", 
            on_help_contents }
    };
    
    private const Gtk.RadioActionEntry[] COMMON_SORT_EVENTS_ORDER_ACTIONS = {
        { "CommonSortEventsAscending", Gtk.STOCK_SORT_ASCENDING, "_Ascending", null, 
            "Sort photos in an ascending order", SORT_EVENTS_ORDER_ASCENDING },
        { "CommonSortEventsDescending", Gtk.STOCK_SORT_DESCENDING, "D_escending", null, 
            "Sort photos in a descending order", SORT_EVENTS_ORDER_DESCENDING }
    };

    private class DragDropImportJob : BatchImportJob {
        private File file_or_dir;
        
        public DragDropImportJob(string uri) {
            file_or_dir = File.new_for_uri(uri);
        }
        
        public override string get_identifier() {
            return file_or_dir.get_uri();
        }
        
        public override bool prepare(out File file_to_import, out bool copy_to_library) {
            // Copy the file into the photo library; this version of the app, all imports are
            // copied.  Later updates may allow for links and moves.
            file_to_import = file_or_dir;
            copy_to_library = true;
            
            return true;
        }
    }
    
    private class CompareEventPage : Comparator<EventPage> {
        private int event_sort;
        private EventTable event_table = new EventTable();
        
        public CompareEventPage(int event_sort) {
            assert(event_sort == SORT_EVENTS_ORDER_ASCENDING || event_sort == SORT_EVENTS_ORDER_DESCENDING);
            
            this.event_sort = event_sort;
        }
        
        public override int64 compare(EventPage a, EventPage b) {
            int64 start_a = (int64) event_table.get_start_time(a.event_id);
            int64 start_b = (int64) event_table.get_start_time(b.event_id);
            
            switch (event_sort) {
                case SORT_EVENTS_ORDER_ASCENDING:
                    return start_a - start_b;
                
                case SORT_EVENTS_ORDER_DESCENDING:
                default:
                    return start_b - start_a;
            }
        }
    }

    public static void init(string[] args) {
        AppWindow.args = args;

        File data_dir = get_data_dir();
        try {
            if (data_dir.query_exists(null) == false) {
                if (!data_dir.make_directory_with_parents(null))
                    error("Unable to create data directory %s", data_dir.get_path());
            } 
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    public static void terminate() {
    }
    
    public static AppWindow get_instance() {
        return instance;
    }
    
    public static string[] get_commandline_args() {
        return args;
    }
    
    public static GLib.File get_exec_file() {
        return File.new_for_path(Environment.find_program_in_path(args[0]));
    }

    public static File get_exec_dir() {
        return get_exec_file().get_parent();
    }
    
    public static File get_data_dir() {
        return File.new_for_path(Environment.get_home_dir()).get_child(DATA_DIR);
    }
    
    public static File get_photos_dir() {
        return File.new_for_path(Environment.get_home_dir()).get_child(PHOTOS_DIR);
    }
    
    public static File get_temp_dir() {
        // TODO: I know, I know.  Better ways to locate a temp file.
        return get_data_subdir("tmp");
    }
    
    public static File get_data_subdir(string name, string? subname = null) {
        File subdir = get_data_dir().get_child(name);
        if (subname != null)
            subdir = subdir.get_child(subname);

        try {
            if (subdir.query_exists(null) == false) {
                if (!subdir.make_directory_with_parents(null))
                    error("Unable to create data subdirectory %s", subdir.get_path());
            }
        } catch (Error err) {
            error("%s", err.message);
        }
        
        return subdir;
    }
    
    public static File get_resources_dir() {
        File exec_dir = get_exec_dir();
        File prefix_dir = File.new_for_path(Resources.PREFIX);

        // if running in the prefix'd path, the app has been installed and is running from there;
        // use its installed resources; otherwise running locally, so use local resources
        if (exec_dir.has_prefix(prefix_dir))
            return prefix_dir.get_child("share").get_child("shotwell");
        else
            return AppWindow.get_exec_dir();
    }

    public static void error_message(string message) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(get_instance(), Gtk.DialogFlags.MODAL, 
            Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", message);
        dialog.title = Resources.APP_TITLE;
        dialog.run();
        dialog.destroy();
    }
    
    private static string? generate_import_failure_list(Gee.List<string> failed) {
        if (failed.size == 0)
            return null;
        
        string list = "";
        for (int ctr = 0; ctr < 4 && ctr < failed.size; ctr++)
            list += "%s\n".printf(failed.get(ctr));
        
        if (failed.size > 4)
            list += "%d more photo(s) not imported.\n".printf(failed.size - 4);
        
        return list;
    }
    
    public static void report_import_failures(string name, Gee.List<string> failed, 
        Gee.List<string> skipped) {
        string failed_list = generate_import_failure_list(failed);
        string skipped_list = generate_import_failure_list(skipped);
        
        if (failed_list == null && skipped_list == null)
            return;
            
        string message = "Import from %s did not complete.\n".printf(name);

        if (failed_list != null) {
            message += "\n%d photos failed due to error:\n".printf(failed.size);
            message += failed_list;
        }
        
        if (skipped_list != null) {
            message += "\n%d photos were skipped:\n".printf(skipped.size);
            message += skipped_list;
        }
        
        error_message(message);
    }
    
    public static bool has_user_quit() {
        return user_quit;
    }
    
    // configuration values set app-wide
    private int events_sort = SORT_EVENTS_ORDER_DESCENDING;
    
    // this needs to be ref'd the lifetime of the application
    private Hal.Context hal_context = new Hal.Context();
    private DBus.Connection hal_conn = null;
    
    // Static (default) pages
    private CollectionPage collection_page = null;
    private EventsDirectoryPage events_directory_page = null;
    private PhotoPage photo_page = null;
    private ImportQueuePage import_queue_page = null;
    
    // Dynamically added pages
    private Gee.ArrayList<EventPage> event_list = new Gee.ArrayList<Page>();
    private Gee.HashMap<string, ImportPage> camera_map = new Gee.HashMap<string, ImportPage>(
        str_hash, str_equal, direct_equal);
    private Gee.ArrayList<Page> pages_to_be_removed = new Gee.ArrayList<Page>();

    private PhotoTable photo_table = new PhotoTable();
    private EventTable event_table = new EventTable();
    
    private Sidebar sidebar = new Sidebar();
    private SidebarMarker cameras_marker = null;
    
    private Gtk.Notebook notebook = new Gtk.Notebook();
    private Gtk.Box layout = new Gtk.VBox(false, 0);
    private Page current_page = null;
    
    private GPhoto.Context null_context = new GPhoto.Context();
    private GPhoto.CameraAbilitiesList abilities_list;
    
    private FullscreenWindow fullscreen_window = null;
    
    public AppWindow() {
        // if this is the first AppWindow, it's the main AppWindow
        assert(instance == null);
        instance = this;
        
        title = Resources.APP_TITLE;
        set_default_size(1024, 768);
        set_default_icon(Resources.get_icon(Resources.ICON_APP));

        // the pages want to know when modifier keys are pressed
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK | Gdk.EventMask.STRUCTURE_MASK);
        key_press_event += on_key_pressed;
        key_release_event += on_key_released;
        configure_event += on_configure;
        
        // prepare the default parent and orphan pages
        // (these are never removed from the system)
        collection_page = new CollectionPage();
        events_directory_page = new EventsDirectoryPage();
        photo_page = new PhotoPage();
        photo_page.set_container(this);

        // add the default parents and orphans to the notebook
        add_parent_page(collection_page);
        add_parent_page(events_directory_page);
        add_orphan_page(photo_page);

        // create Photo objects for all photos in the database and load into the Photos page
        Gee.ArrayList<PhotoID?> photo_ids = photo_table.get_photos();
        foreach (PhotoID photo_id in photo_ids) {
             Photo photo = Photo.fetch(photo_id);
             photo.removed += on_photo_removed;
             
             collection_page.add_photo(photo);
        }

        // add stored events
        Gee.ArrayList<EventID?> event_ids = event_table.get_events();
        foreach (EventID event_id in event_ids)
            add_event_page(event_id);
        
        // start in the collection page
        sidebar.place_cursor(collection_page);
        sidebar.expand_all();
        
        // monitor cursor changes to select proper page in notebook
        sidebar.cursor_changed += on_sidebar_cursor_changed;
        
        create_layout(collection_page);

        // set up main window as a drag-and-drop destination (rather than each page; assume
        // a drag and drop is for general library import, which means it goes to collection_page)
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, DEST_TARGET_ENTRIES, Gdk.DragAction.COPY);
        
        // set up HAL connection to monitor for device insertion/removal, to look for cameras
        hal_conn = DBus.Bus.get(DBus.BusType.SYSTEM);
        if (!hal_context.set_dbus_connection(hal_conn.get_connection()))
            error("Unable to set DBus connection for HAL");

        DBus.RawError raw = DBus.RawError();
        if (!hal_context.init(ref raw))
            error("Unable to initialize context: %s", raw.message);

        if (!hal_context.set_device_added(on_device_added))
            error("Unable to register device-added callback");
        if (!hal_context.set_device_removed(on_device_removed))
            error("Unable to register device-removed callback");

        try {
            init_camera_table();
            update_camera_table();
        } catch (GPhotoError err) {
            error("%s", err.message);
        }

        Gtk.AboutDialog.set_url_hook(on_about_link);
        Gtk.AboutDialog.set_email_hook(on_about_link);
    }
    
    public Gtk.ActionGroup get_common_action_group() {
        // each page gets its own one
        Gtk.ActionGroup action_group = new Gtk.ActionGroup("CommonActionGroup");
        action_group.add_actions(COMMON_ACTIONS, this);
        action_group.add_radio_actions(COMMON_SORT_EVENTS_ORDER_ACTIONS, SORT_EVENTS_ORDER_ASCENDING,
            on_events_sort_changed);
        
        return action_group;
    }
    
    private void on_about() {
        // TODO: More thorough About box
        Gtk.show_about_dialog(this,
            "version", Resources.APP_VERSION,
            "comments", Resources.APP_SUBTITLE,
            "copyright", Resources.COPYRIGHT,
            "website", Resources.YORBA_URL,
            "license", Resources.LICENSE,
            "website-label", "Visit the Yorba web site",
            "authors", Resources.AUTHORS,
            "logo", Resources.get_icon(Resources.ICON_ABOUT_LOGO, -1)
        );
    }
    
    // This callback needs to be installed for the links to be active in the About dialog.  However,
    // this callback doesn't actually have to do anything in order to activate the URL.
    private void on_about_link(Gtk.AboutDialog about_dialog, string url) {
    }
    
    private void on_quit() {
        user_quit = true;
        Gtk.main_quit();
    }
    
    private override void destroy() {
        on_quit();
    }
    
    private void on_help_contents() {
        open_link(Resources.HELP_URL);
    }
    
    private void open_link(string url) {
        try {
            Gtk.show_uri(window.get_screen(), url, Gdk.CURRENT_TIME);
        } catch (Error err) {
            critical("Unable to load URL: %s", err.message);
        }
    }
    
    private void on_fullscreen() {
        CheckerboardPage controller = null;
        Thumbnail start = null;
        
        if (current_page is CheckerboardPage) {
            LayoutItem item = ((CheckerboardPage) current_page).get_fullscreen_photo();
            if (item == null) {
                message("No fullscreen photo for this view");
                
                return;
            }
            
            controller = (CheckerboardPage) current_page;
            start = (Thumbnail) item;
        } else if (current_page is PhotoPage) {
            controller = ((PhotoPage) current_page).get_controller();
            start = ((PhotoPage) current_page).get_thumbnail();
        } else {
            message("Unable to present fullscreen view for this page");
            
            return;
        }
        
        if (controller == null || start == null)
            return;
        
        PhotoPage fs_photo = new PhotoPage();
        FullscreenWindow fs_window = new FullscreenWindow(fs_photo);
        fs_photo.set_container(fs_window);
        fs_photo.display(controller, start);

        go_fullscreen(fs_window);
    }
    
    public void go_fullscreen(FullscreenWindow fullscreen_window) {
        // if already fullscreen, use that
        if (this.fullscreen_window != null) {
            this.fullscreen_window.present();
            
            return;
        }
        
        current_page.switching_to_fullscreen();
        
        this.fullscreen_window = fullscreen_window;
        this.fullscreen_window.present();
        hide();
    }
    
    public void end_fullscreen() {
        if (fullscreen_window == null)
            return;
        
        show_all();
        
        fullscreen_window.hide();
        fullscreen_window = null;
        
        current_page.returning_from_fullscreen();
        
        present();
    }
    
    public int get_events_sort() {
        return events_sort;
    }
    
    private void on_sort_events() {
        // any member of the group can be told the current value
        Gtk.RadioAction action = (Gtk.RadioAction) current_page.common_action_group.get_action(
            "CommonSortEventsAscending");
        assert(action != null);
        
        action.set_current_value(events_sort);
    }
    
    private void on_events_sort_changed() {
        // any member of the group knows the value
        Gtk.RadioAction action = (Gtk.RadioAction) current_page.common_action_group.get_action(
            "CommonSortEventsAscending");
        assert(action != null);
        
        events_sort = action.get_current_value();
        assert(events_sort == SORT_EVENTS_ORDER_ASCENDING || events_sort == SORT_EVENTS_ORDER_DESCENDING);
        
        // rebuild sidebar with new sorting rules ... start by pruning branch from sidebar
        // (note that this doesn't remove the pages from the notebook object)
        sidebar.prune_branch_children(events_directory_page.get_marker());
        
        CompareEventPage comparator = new CompareEventPage(events_sort);
        
        // re-insert each page in the sidebar in the new order ... does not add page
        // to notebook again or create a new layout
        foreach (EventPage event_page in event_list)
            sidebar.insert_child_sorted(events_directory_page.get_marker(), event_page, comparator);
        
        // pruning will collapse the branch, expand automatically
        // TODO: Only expand if already expanded?
        sidebar.expand_branch(events_directory_page.get_marker());
        
        // set the tree cursor to the current page, which might have been lost in the
        // delete/insert
        sidebar.place_cursor(current_page);

        // the events directory page needs to know about this
        events_directory_page.notify_sort_changed(events_sort);
    }
    
    public void set_busy_cursor() {
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
    }
    
    public void set_normal_cursor() {
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.ARROW));
    }
    
    public void enqueue_batch_import(BatchImport batch_import) {
        if (import_queue_page == null) {
            import_queue_page = new ImportQueuePage();
            import_queue_page.batch_removed += remove_import_queue_row;
            
            insert_page_after(events_directory_page.get_marker(), import_queue_page);
        }
        
        import_queue_page.enqueue_and_schedule(batch_import);
    }
    
    private void remove_import_queue_row() {
        if (import_queue_page.get_batch_count() == 0) {
            remove_page(import_queue_page);
            import_queue_page = null;
        }
    }
    
    public void photo_imported(Photo photo) {
        // want to know when it's removed from the system for cleanup
        photo.removed += on_photo_removed;

        // automatically add to the Photos page
        collection_page.add_photo(photo);
        collection_page.refresh();
    }
    
    public void batch_import_complete(SortedList<Photo> imported_photos) {
        debug("Processing imported photos to create events ...");

        // walk through photos, splitting into events based on criteria
        time_t last_exposure = 0;
        time_t current_event_start = 0;
        EventID current_event_id = EventID();
        EventPage current_event_page = null;
        foreach (Photo photo in imported_photos) {
            time_t exposure_time = photo.get_exposure_time();

            if (exposure_time == 0) {
                // no time recorded; skip
                debug("Skipping event assignment to %s: No exposure time", photo.to_string());
                
                continue;
            }
            
            if (photo.get_event_id().is_valid()) {
                // already part of an event; skip
                debug("Skipping event assignment to %s: Already part of event %lld", photo.to_string(),
                    photo.get_event_id().id);
                    
                continue;
            }
            
            // see if enough time has elapsed to create a new event, or to store this photo in
            // the current one
            bool create_event = false;
            if (last_exposure == 0) {
                // first photo, start a new event
                create_event = true;
            } else {
                assert(last_exposure <= exposure_time);
                assert(current_event_start <= exposure_time);

                if (exposure_time - last_exposure >= EVENT_LULL_SEC) {
                    // enough time has passed between photos to signify a new event
                    create_event = true;
                } else if (exposure_time - current_event_start >= EVENT_MAX_DURATION_SEC) {
                    // the current event has gone on for too long, stop here and start a new one
                    create_event = true;
                }
            }
            
            if (create_event) {
                if (current_event_id.is_valid()) {
                    assert(last_exposure != 0);
                    event_table.set_end_time(current_event_id, last_exposure);

                    events_directory_page.add_event(current_event_id);
                    events_directory_page.refresh();
                }

                current_event_start = exposure_time;
                current_event_id = event_table.create(photo.get_photo_id(), current_event_start);
                
                current_event_page = add_event_page(current_event_id);

                debug("Created event [%lld]", current_event_id.id);
            }
            
            assert(current_event_id.is_valid());
            
            debug("Adding %s to event %lld (exposure=%ld last_exposure=%ld)", photo.to_string(), 
                current_event_id.id, exposure_time, last_exposure);
            
            photo.set_event_id(current_event_id);

            current_event_page.add_photo(photo);

            last_exposure = exposure_time;
        }
    }
    
    private bool on_key_pressed(Gdk.EventKey event) {
        return (event.is_modifier != 0) ? current_page.notify_modifier_pressed(event) : false;
    }
    
    private bool on_key_released(Gdk.EventKey event) {
        return (event.is_modifier != 0) ? current_page.notify_modifier_released(event) : false;
    }
    
    private bool on_configure(Gdk.EventConfigure event) {
        return current_page.notify_configure_event(event);
    }
    
    private void on_photo_removed(Photo photo) {
        PhotoID photo_id = photo.get_photo_id();
        
        // update event's primary photo if this is the one; remove event if no more photos in it
        EventID event_id = photo_table.get_event(photo_id);
        if (event_id.is_valid() && (event_table.get_primary_photo(event_id).id == photo_id.id)) {
            Gee.ArrayList<PhotoID?> photo_ids = photo_table.get_event_photos(event_id);
            
            PhotoID found = PhotoID();
            // TODO: For now, simply selecting the first photo possible
            foreach (PhotoID id in photo_ids) {
                if (id.id != photo_id.id) {
                    found = id;
                    
                    break;
                }
            }
            
            if (found.is_valid()) {
                event_table.set_primary_photo(event_id, found);
            } else {
                // this indicates this is the last photo of the event, so no more event
                assert(photo_ids.size <= 1);
                remove_event_page(event_id);
                event_table.remove(event_id);
            }
        }
    }
    
    private override void drag_data_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time) {
        // don't accept drops from our own application
        if (Gtk.drag_get_source_widget(context) != null) {
            Gtk.drag_finish(context, false, false, time);
            
            return;
        }

        string[] uris = selection_data.get_uris();
        Gee.ArrayList<DragDropImportJob> jobs = new Gee.ArrayList<DragDropImportJob>();
        uint64 total_bytes = 0;

        foreach (string uri in uris) {
            jobs.add(new DragDropImportJob(uri));
            
            try {
                total_bytes += query_total_file_size(File.new_for_uri(uri));
            } catch (Error err) {
                debug("Unable to query filesize of %s: %s", uri, err.message);
            }
        }
        
        if (jobs.size > 0) {
            BatchImport batch_import = new BatchImport(jobs, "drag-and-drop", total_bytes);
            enqueue_batch_import(batch_import);
            switch_to_import_queue_page();
        }

        Gtk.drag_finish(context, true, false, time);
    }
    
    public void switch_to_collection_page() {
        switch_to_page(collection_page);
    }
    
    public void switch_to_events_directory_page() {
        switch_to_page(events_directory_page);
    }
    
    public void switch_to_event(EventID event_id) {
        EventPage page = find_event_page(event_id);
        if (page == null) {
            debug("Cannot find page for event %lld", event_id.id);

            return;
        }

        switch_to_page(page);
    }
    
    public void switch_to_photo_page(CheckerboardPage controller, Thumbnail current) {
        photo_page.display(controller, current);
        switch_to_page(photo_page);
    }
    
    public void switch_to_import_queue_page() {
        switch_to_page(import_queue_page);
    }
    
    public EventPage? find_event_page(EventID event_id) {
        foreach (EventPage page in event_list) {
            if (page.event_id.id == event_id.id)
                return page;
        }
        
        return null;
    }
    
    private EventPage add_event_page(EventID event_id) {
        EventPage event_page = new EventPage(event_id);
        
        Gee.ArrayList<PhotoID?> photo_ids = photo_table.get_event_photos(event_id);
        foreach (PhotoID photo_id in photo_ids)
            event_page.add_photo(Photo.fetch(photo_id));

        insert_child_page_sorted(events_directory_page.get_marker(), event_page, 
            new CompareEventPage(get_events_sort()));
        event_list.add(event_page);
        
        return event_page;
    }
    
    private void remove_event_page(EventID event_id) {
        EventPage page = find_event_page(event_id);
        assert(page != null);
        
        remove_page(page);
        event_list.remove(page);
    }

    private void add_to_notebook(Page page) {
        // need to show all before handing over to notebook
        page.show_all();
        
        int pos = notebook.append_page(page.get_layout(), null);
        assert(pos >= 0);
    }
    
    private int get_notebook_pos(Page page) {
        int pos = notebook.page_num(page.get_layout());
        assert(pos != -1);
        
        return pos;
    }
    
    private void add_parent_page(Page parent) {
        add_to_notebook(parent);

        sidebar.add_parent(parent);
        
        notebook.show_all();
    }
    
    private void add_child_page(SidebarMarker parent_marker, Page child) {
        add_to_notebook(child);
        
        sidebar.add_child(parent_marker, child);
        
        notebook.show_all();
    }
    
    private void insert_page_after(SidebarMarker after_marker, Page page) {
        add_to_notebook(page);
        
        sidebar.insert_sibling_after(after_marker, page);
        
        notebook.show_all();
    }
    
    private void insert_child_page_sorted(SidebarMarker parent_marker, Page page,
        Comparator<Page> comparator) {
        add_to_notebook(page);
        
        sidebar.insert_child_sorted(parent_marker, page, comparator);
        
        notebook.show_all();
    }
    
    // an orphan page is a Page that exists in the notebook (and can therefore be switched to) but
    // is not listed in the sidebar
    private void add_orphan_page(Page orphan) {
        add_to_notebook(orphan);
        
        notebook.show_all();
    }
    
    private void remove_page(Page page) {
        // a handful of pages just don't go away
        assert(page != collection_page);
        assert(page != events_directory_page);
        assert(page != photo_page);
        
        // because removing a page while executing inside a signal or from a call from the page
        // itself causes problems (i.e. the page being unref'd beneath its feet), schedule all
        // removals outside of UI event and in Idle handler
        if (!pages_to_be_removed.contains(page)) {
            pages_to_be_removed.add(page);
            Idle.add(remove_page_internal);
        }
        
        // switch away if necessary to collection page (which is always present)
        if (current_page == page)
            switch_to_collection_page();
    }
    
    private bool remove_page_internal() {
        // remove all the pages scheduled for removal (in Idle)
        while (pages_to_be_removed.size > 0) {
            Page page = pages_to_be_removed.get(0);
            
            // remove from notebook
            int pos = get_notebook_pos(page);
            assert(pos >= 0);
            notebook.remove_page(pos);

            // remove from sidebar, if present
            sidebar.remove_page(page);
            
            pages_to_be_removed.remove_at(0);
        }
        
        return false;
    }
    
    private void create_layout(Page start_page) {
        // use a Notebook to hold all the pages, which are switched when a sidebar child is selected
        notebook.set_show_tabs(false);
        notebook.set_show_border(false);
        
        sidebar.modify_base(Gtk.StateType.NORMAL, SIDEBAR_BG_COLOR);
        
        // put the sidebar in a scrolling window
        Gtk.ScrolledWindow scrolled_sidebar = new Gtk.ScrolledWindow(null, null);
        scrolled_sidebar.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scrolled_sidebar.add(sidebar);

        // layout the selection tree to the left of the collection/toolbar box with an adjustable
        // gutter between them, framed for presentation
        Gtk.Frame left_frame = new Gtk.Frame(null);
        left_frame.add(scrolled_sidebar);
        left_frame.set_shadow_type(Gtk.ShadowType.IN);
        
        Gtk.Frame right_frame = new Gtk.Frame(null);
        right_frame.add(notebook);
        right_frame.set_shadow_type(Gtk.ShadowType.IN);
        
        Gtk.HPaned client_paned = new Gtk.HPaned();
        client_paned.pack1(left_frame, false, false);
        sidebar.set_size_request(SIDEBAR_MIN_WIDTH, -1);
        client_paned.pack2(right_frame, true, false);
        // TODO: Calc according to layout's size, to give sidebar a maximum width
        notebook.set_size_request(PAGE_MIN_WIDTH, -1);

        layout.pack_end(client_paned, true, true, 0);
        
        add(layout);

        switch_to_page(start_page);
    }
    
    public void switch_to_page(Page page) {
        if (page == current_page)
            return;
        
        if (current_page != null) {
            current_page.switching_from();
        
            remove_accel_group(current_page.ui.get_accel_group());
        }

        int pos = get_notebook_pos(page);
        notebook.set_current_page(pos);

        // switch menus
        if (current_page != null)
            layout.remove(current_page.get_menubar());
        layout.pack_start(page.get_menubar(), false, false, 0);

        Gtk.AccelGroup accel_group = page.ui.get_accel_group();
        if (accel_group != null)
            add_accel_group(accel_group);
        
        // do this prior to changing selection, as the change will fire a cursor-changed event,
        // which will then call this function again
        current_page = page;

        sidebar.place_cursor(page);
        
        page.show_all();
        
        page.switched_to();
    }

    private bool is_page_selected(Page page, Gtk.TreePath path) {
        SidebarMarker marker = page.get_marker();
        if (marker == null)
            return false;
        
        return (path.compare(marker.get_row().get_path()) == 0);
    }
    
    private bool is_camera_selected(Gtk.TreePath path) {
        foreach (ImportPage page in camera_map.get_values()) {
            if (!is_page_selected(page, path))
                continue;

            switch_to_page(page);

            if (page.is_refreshed() || page.is_busy()) {
                return true;
            }
            
            ImportPage.RefreshResult res = page.refresh_camera();
            switch (res) {
                case ImportPage.RefreshResult.OK:
                case ImportPage.RefreshResult.BUSY: {
                    // nothing to report; if busy, let it continue doing its thing
                    // (although earlier check should've caught this)
                } break;
                
                case ImportPage.RefreshResult.LOCKED: {
                    // if locked because it's mounted, offer to unmount
                    debug("Checking if %s is mounted ...", page.get_uri());

                    File uri = File.new_for_uri(page.get_uri());

                    Mount mount = null;
                    try {
                        mount = uri.find_enclosing_mount(null);
                    } catch (Error err) {
                        // error means not mounted
                    }
                    
                    if (mount != null) {
                        // it's mounted, offer to unmount for the user
                        Gtk.MessageDialog dialog = new Gtk.MessageDialog(this, 
                            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION,
                            Gtk.ButtonsType.YES_NO,
                            "The camera is locked for use as a mounted drive.  "
                            + "Shotwell can only access the camera when it's unlocked.  "
                            + "Do you want Shotwell to unmount it for you?");
                        dialog.title = Resources.APP_TITLE;
                        int dialog_res = dialog.run();
                        dialog.destroy();
                        
                        if (dialog_res != Gtk.ResponseType.YES) {
                            page.set_page_message("Please unmount the camera.");
                            page.refresh();
                        } else {
                            page.unmount_camera(mount);
                        }
                    } else {
                        // it's not mounted, so another application must have it locked
                        Gtk.MessageDialog dialog = new Gtk.MessageDialog(this,
                            Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING,
                            Gtk.ButtonsType.OK,
                            "The camera is locked by another application.  "
                            + "Shotwell can only access the camera when it's unlocked.  "
                            + "Please close any other application using the camera and try again.");
                        dialog.title = Resources.APP_TITLE;
                        dialog.run();
                        dialog.destroy();
                        
                        page.set_page_message("Please close any other application using the camera.");
                        page.refresh();
                    }
                } break;
                
                case ImportPage.RefreshResult.LIBRARY_ERROR: {
                    error_message("Unable to fetch previews from the camera:\n%s".printf(page.get_refresh_message()));
                } break;
                
                default: {
                    error("Unknown result type %d", (int) res);
                } break;
            }

            return true;
        }
        
        // not found
        return false;
    }
    
    private bool is_event_selected(Gtk.TreePath path) {
        foreach (EventPage page in event_list) {
            if (is_page_selected(page, path)) {
                switch_to_page(page);
                
                return true;
            }
        }
        
        return false;
    }
    
    private bool focus_on_current_page() {
        current_page.grab_focus();
        
        return false;
    }

    private void on_sidebar_cursor_changed() {
        Gtk.TreePath path;
        sidebar.get_cursor(out path, null);
        
        if (is_page_selected(collection_page, path)) {
            switch_to_collection_page();
        } else if (is_page_selected(events_directory_page, path)) {
            switch_to_events_directory_page();
        } else if (import_queue_page != null && is_page_selected(import_queue_page, path)) {
            switch_to_import_queue_page();
        } else if (is_camera_selected(path)) {
            // camera path selected and updated
        } else if (is_event_selected(path)) {
            // event page selected and updated
        } else {
            // nothing recognized selected
        }

        // this has to be done in Idle handler because the focus/ won't change properly inside 
        // this signal
        Idle.add(focus_on_current_page);
    }
    
    private void do_op(GPhoto.Result res, string op) throws GPhotoError {
        if (res != GPhoto.Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Unable to %s: %s", (int) res, op, res.as_string());
    }
    
    private void init_camera_table() throws GPhotoError {
        do_op(GPhoto.CameraAbilitiesList.create(out abilities_list), "create camera abilities list");
        do_op(abilities_list.load(null_context), "load camera abilities list");
    }
    
    // USB (or libusb) is a funny beast; if only one USB device is present (i.e. the camera),
    // then a single camera is detected at port usb:.  However, if multiple USB devices are
    // present (including non-cameras), then the first attached camera will be listed twice,
    // first at usb:, then at usb:xxx,yyy.  If the usb: device is removed, another usb:xxx,yyy
    // device will lose its full-path name and be referred to as usb: only.
    //
    // This function gleans the full port name of a particular port, even if it's the unadorned
    // "usb:", by using HAL.
    private string? esp_usb_to_udi(int camera_count, string port, out string full_port) {
        // sanity
        assert(camera_count > 0);
        
        debug("ESP: camera_count=%d port=%s", camera_count, port);

        DBus.RawError raw = DBus.RawError();
        string[] udis = hal_context.find_device_by_capability("camera", ref raw);
        
        string[] usbs = new string[0];
        foreach (string udi in udis) {
            if (hal_context.device_get_property_string(udi, "info.subsystem", ref raw) == "usb")
                usbs += udi;
        }

        // if GPhoto detects one camera, and HAL reports one USB camera, all is swell
        if (camera_count == 1) {
            if (usbs.length == 1) {
                string usb = usbs[0];
                
                int hal_bus = hal_context.device_get_property_int(usb, "usb.bus_number", ref raw);
                int hal_device = hal_context.device_get_property_int(usb, "usb.linux.device_number", ref raw);

                if (port == "usb:") {
                    // the most likely case, so make a full path
                    full_port = "usb:%03d,%03d".printf(hal_bus, hal_device);
                } else {
                    full_port = port;
                }
                
                debug("ESP: port=%s full_port=%s udi=%s", port, full_port, usb);
                
                return usb;
            }
        }

        // with more than one camera, skip the mirrored "usb:" port
        if (port == "usb:") {
            debug("ESP: Skipping %s", port);
            
            return null;
        }
        
        // parse out the bus and device ID
        int bus, device;
        if (port.scanf("usb:%d,%d", out bus, out device) < 2)
            error("ESP: Failed to scanf %s", port);
        
        foreach (string usb in usbs) {
            int hal_bus = hal_context.device_get_property_int(usb, "usb.bus_number", ref raw);
            int hal_device = hal_context.device_get_property_int(usb, "usb.linux.device_number", ref raw);
            
            if ((bus == hal_bus) && (device == hal_device)) {
                full_port = port;
                
                debug("ESP: port=%s full_port=%s udi=%s", port, full_port, usb);

                return usb;
            }
        }
        
        debug("ESP: No UDI found for port=%s", port);
        
        return null;
    }
    
    private static string get_port_uri(string port) {
        return "gphoto2://[%s]/".printf(port);
    }

    private void update_camera_table() throws GPhotoError {
        // need to do this because virtual ports come and go in the USB world (and probably others)
        GPhoto.PortInfoList port_info_list;
        do_op(GPhoto.PortInfoList.create(out port_info_list), "create port list");
        do_op(port_info_list.load(), "load port list");

        GPhoto.CameraList camera_list;
        do_op(GPhoto.CameraList.create(out camera_list), "create camera list");
        do_op(abilities_list.detect(port_info_list, camera_list, null_context), "detect cameras");
        
        Gee.HashMap<string, string> detected_map = new Gee.HashMap<string, string>(str_hash, str_equal,
            str_equal);
        
        for (int ctr = 0; ctr < camera_list.count(); ctr++) {
            string name;
            do_op(camera_list.get_name(ctr, out name), "get detected camera name");

            string port;
            do_op(camera_list.get_value(ctr, out port), "get detected camera port");
            
            debug("Detected %s @ %s", name, port);
            
            // do some USB ESP
            if (port.has_prefix("usb:")) {
                string full_port;
                string udi = esp_usb_to_udi(camera_list.count(), port, out full_port);
                if (udi == null)
                    continue;
                
                port = full_port;
            }

            detected_map.set(port, name);
        }
        
        // first, find cameras that have disappeared
        ImportPage[] missing = new ImportPage[0];
        foreach (ImportPage page in camera_map.get_values()) {
            GPhoto.Camera camera = page.get_camera();
            
            GPhoto.PortInfo port_info;
            do_op(camera.get_port_info(out port_info), "retrieve missing camera port information");
            
            GPhoto.CameraAbilities abilities;
            do_op(camera.get_abilities(out abilities), "retrieve camera abilities");
            
            if (detected_map.contains(port_info.path)) {
                debug("Found page for %s @ %s in detected cameras", abilities.model, port_info.path);
                
                continue;
            }
            
            debug("%s @ %s missing", abilities.model, port_info.path);
            
            missing += page;
        }
        
        // have to remove from hash map outside of iterator
        foreach (ImportPage page in missing) {
            GPhoto.Camera camera = page.get_camera();
            
            GPhoto.PortInfo port_info;
            do_op(camera.get_port_info(out port_info), "retrieve missing camera port information");
            
            GPhoto.CameraAbilities abilities;
            do_op(camera.get_abilities(out abilities), "retrieve missing camera abilities");

            debug("Removing from camera table: %s @ %s", abilities.model, port_info.path);

            camera_map.remove(get_port_uri(port_info.path));
            remove_page(page);
        }

        // add cameras which were not present before
        foreach (string port in detected_map.get_keys()) {
            string name = detected_map.get(port);
            string uri = get_port_uri(port);

            if (camera_map.contains(uri)) {
                // already known about
                debug("%s @ %s already registered, skipping", name, port);
                
                continue;
            }
            
            int index = port_info_list.lookup_path(port);
            if (index < 0)
                do_op((GPhoto.Result) index, "lookup port %s".printf(port));
            
            GPhoto.PortInfo port_info;
            do_op(port_info_list.get_info(index, out port_info), "get port info for %s".printf(port));
            
            // this should match, every time
            assert(port == port_info.path);
            
            index = abilities_list.lookup_model(name);
            if (index < 0)
                do_op((GPhoto.Result) index, "lookup camera model %s".printf(name));

            GPhoto.CameraAbilities camera_abilities;
            do_op(abilities_list.get_abilities(index, out camera_abilities), 
                "lookup camera abilities for %s".printf(name));
                
            GPhoto.Camera camera;
            do_op(GPhoto.Camera.create(out camera), "create camera object for %s".printf(name));
            do_op(camera.set_abilities(camera_abilities), "set camera abilities for %s".printf(name));
            do_op(camera.set_port_info(port_info), "set port info for %s on %s".printf(name, port));
            
            debug("Adding to camera table: %s @ %s", name, port);
            
            ImportPage page = new ImportPage(camera, uri);
            
            // create the Cameras row if this is the first one
            if (cameras_marker == null)
                cameras_marker = sidebar.insert_grouping_after(events_directory_page.get_marker(),
                    "Cameras");
            
            add_child_page(cameras_marker, page);

            camera_map.set(uri, page);
            
            // automagically expand the Cameras branch so the user sees the attached camera(s)
            sidebar.expand_branch(cameras_marker);
        }
        
        // if no cameras present, remove row
        if (camera_map.size == 0 && cameras_marker != null) {
            sidebar.prune_branch(cameras_marker);
            cameras_marker = null;
        }
    }
    
    private static void on_device_added(Hal.Context context, string udi) {
        debug("on_device_added: %s", udi);
        
        schedule_camera_update();
    }
    
    private static void on_device_removed(Hal.Context context, string udi) {
        debug("on_device_removed: %s", udi);
        
        schedule_camera_update();
    }
    
    // Device add/removes often arrive in pairs; this allows for a single
    // update to occur when they come in all at once
    private static void schedule_camera_update() {
        if (camera_update_scheduled)
            return;
        
        Timeout.add(500, background_camera_update);
        camera_update_scheduled = true;
    }
    
    private static bool background_camera_update() {
        debug("background_camera_update");
    
        try {
            AppWindow.get_instance().update_camera_table();
        } catch (GPhotoError err) {
            debug("Error updating camera table: %s", err.message);
        }
        
        camera_update_scheduled = false;

        return false;
    }
    
    public static bool is_mount_uri_supported(string uri) {
        foreach (string scheme in SUPPORTED_MOUNT_SCHEMES) {
            if (uri.has_prefix(scheme))
                return true;
        }
        
        return false;
    }
    
    public static void mounted_camera_shell_notification(string uri) {
        debug("mount point reported: %s", uri);

        if (!is_mount_uri_supported(uri)) {
            debug("Unsupported mount scheme: %s", uri);
            
            return;
        }
        
        File uri_file = File.new_for_uri(uri);
        
        Mount mount = null;
        try {
            mount = uri_file.find_enclosing_mount(null);
        } catch (Error err) {
            debug("%s", err.message);
            
            return;
        }
        
        // convert file: URIs into gphoto disk: URIs
        string alt_uri = null;
        if (uri.has_prefix("file://"))
            alt_uri = get_port_uri(uri.replace("file://", "disk:"));
        
        ImportPage page = get_instance().camera_map.get(uri_file.get_uri());
        if (page == null && alt_uri != null)
            page = get_instance().camera_map.get(alt_uri);

        if (page == null) {
            debug("Unable to find import page for %s", uri_file.get_uri());
            
            return;
        }
        
        // don't unmount mass storage cameras, as they are then unavailble to gPhoto
        if (!uri.has_prefix("file://")) {
            if (!page.unmount_camera(mount))
                error_message("Unable to unmount the camera at this time.");
        } else {
            page.switch_to_and_refresh();
        }
    }
}
