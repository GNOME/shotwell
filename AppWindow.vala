
public class FullscreenWindow : Gtk.Window {
    public static const int TOOLBAR_DISMISSAL_MSEC = 2500;
    
    private const Gtk.ActionEntry[] ACTIONS = {
        { "LeaveFullscreen", Gtk.STOCK_LEAVE_FULLSCREEN, "Leave _Fullscreen", "Escape", "Leave fullscreen", on_close }
    };

    private Gtk.Window toolbar_window = new Gtk.Window(Gtk.WindowType.POPUP);
    private Gtk.UIManager ui = new Gtk.UIManager();
    private PhotoPage photo_page = new PhotoPage();
    private Gtk.ToolButton close_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_LEAVE_FULLSCREEN);
    private Gtk.ToggleToolButton pin_button = new Gtk.ToggleToolButton();
    private bool is_toolbar_shown = false;
    
    public FullscreenWindow(Gdk.Screen screen, CheckerboardPage controller, Thumbnail start) {
        File ui_file = AppWindow.get_ui_dir().get_child("fullscreen.ui");

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
        
        set_screen(screen);
        set_border_width(0);
        
        pin_button.set_label("Pin toolbar");
        
        close_button.clicked += on_close;
        
        Gtk.Toolbar toolbar = photo_page.get_toolbar();
        toolbar.insert(pin_button, -1);
        toolbar.insert(close_button, -1);
        
        // set up toolbar along bottom of screen, but don't show yet
        toolbar_window.set_screen(get_screen());
        toolbar_window.set_default_size(screen.get_width(), -1);
        toolbar_window.set_border_width(0);
        toolbar_window.add(toolbar);
        
        add(photo_page);
        
        // need to do this to create a Gdk.Window to set masks
        fullscreen();
        show_all();
        
        // want to receive motion events
        Gdk.EventMask mask = window.get_events();
        mask |= Gdk.EventMask.POINTER_MOTION_MASK;
        window.set_events(mask);
        
        motion_notify_event += on_motion;

        photo_page.display(controller, start);
    }
    
    private void on_close() {
        toolbar_window.hide();
        toolbar_window = null;
        
        AppWindow.get_instance().end_fullscreen();
    }
    
    private bool on_motion(FullscreenWindow fsw, Gdk.EventMotion event) {
        show_toolbar();
        
        return false;
    }
    
    private void show_toolbar() {
        if (is_toolbar_shown)
            return;

        toolbar_window.show_all();

        Gtk.Requisition req;
        toolbar_window.size_request(out req);
        toolbar_window.move(0, toolbar_window.get_screen().get_height() - req.height);

        toolbar_window.present();
        is_toolbar_shown = true;
        
        Timeout.add(TOOLBAR_DISMISSAL_MSEC, on_check_toolbar_dismissal);
    }
    
    private bool on_check_toolbar_dismissal() {
        if (!is_toolbar_shown)
            return false;
        
        if (toolbar_window == null)
            return false;
        
        // if pinned, keep open but keep checking
        if (pin_button.get_active())
            return true;
        
        // if the pointer is on the window, keep it alive, but keep checking
        int x, y, width, height, px, py;
        toolbar_window.window.get_geometry(out x, out y, out width, out height, null);
        toolbar_window.get_display().get_pointer(null, out px, out py, null);
        
        if ((px >= x) && (px <= x + width) && (py >= y) && (py <= y + height))
            return true;
        
        toolbar_window.hide();
        is_toolbar_shown = false;
        
        return false;
    }
}

public class AppWindow : Gtk.Window {
    public static const string TITLE = "Shotwell";
    public static const string VERSION = "0.0.1";
    public static const string DATA_DIR = ".photo";
    public static const string PHOTOS_DIR = "Pictures";

    public static const int SIDEBAR_MIN_WIDTH = 160;
    public static const int SIDEBAR_MAX_WIDTH = 320;
    public static const int PAGE_MIN_WIDTH = 
        Thumbnail.MAX_SCALE + CollectionLayout.LEFT_PADDING + CollectionLayout.RIGHT_PADDING;
    
    public static Gdk.Color BG_COLOR = parse_color("#777");

    public static const long EVENT_LULL_SEC = 3 * 60 * 60;
    public static const long EVENT_MAX_DURATION_SEC = 12 * 60 * 60;

    private static AppWindow instance = null;
    private static string[] args = null;

    // drag and drop target entries
    private const Gtk.TargetEntry[] TARGET_ENTRIES = {
        { "text/uri-list", 0, 0 }
    };
    
    // Common actions available to all pages
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] COMMON_ACTIONS = {
        { "CommonQuit", Gtk.STOCK_QUIT, "_Quit", "<Ctrl>Q", "Quit Shotwell", Gtk.main_quit },
        { "CommonAbout", Gtk.STOCK_ABOUT, "_About", null, "About Shotwell", on_about },
        { "CommonFullscreen", Gtk.STOCK_FULLSCREEN, "_Fullscreen", "F11", "Use Shotwell at fullscreen", on_fullscreen }
    };
    
    public static void init(string[] args) {
        AppWindow.args = args;

        File dataDir = get_data_dir();
        try {
            if (dataDir.query_exists(null) == false) {
                if (dataDir.make_directory_with_parents(null) == false) {
                    error("Unable to create data directory %s", dataDir.get_path());
                }
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
    
    public static File get_data_subdir(string name, string? subname = null) {
        File subdir = get_data_dir().get_child(name);
        if (subname != null) {
            subdir = subdir.get_child(subname);
        }

        try {
            if (subdir.query_exists(null) == false) {
                if (subdir.make_directory_with_parents(null) == false) {
                    error("Unable to create data subdirectory %s", subdir.get_path());
                }
            }
        } catch (Error err) {
            error("%s", err.message);
        }
        
        return subdir;
    }
    
    public static File get_ui_dir() {
        // TODO: Programatically determine where runtime data is stored from API calls ...
        // for now, this uses the installed data if running from /usr, otherwise looks for
        // them in the executable's folder
        if (AppWindow.get_exec_dir().get_path().has_prefix("/usr")) {
            return File.new_for_path("/usr/local/share/shotwell");
        } else {
            return AppWindow.get_exec_dir();
        }
    }

    // this needs to be ref'd the lifetime of the application
    private Hal.Context hal_context = new Hal.Context();
    private DBus.Connection hal_conn = null;
    
    // NOTE: When new pages are added, they should be added as well to report_backing_changed(),
    // and on_remove, if appropriate.
    //
    // Static (default) pages
    private CollectionPage collection_page = null;
    private EventsDirectoryPage events_directory_page = null;
    private PhotoPage photo_page = null;
    
    // Dynamically added pages
    private Gee.ArrayList<EventPage> event_list = new Gee.ArrayList<Page>();
    private Gee.HashMap<string, ImportPage> camera_map = new Gee.HashMap<string, ImportPage>(
        str_hash, str_equal, direct_equal);

    private PhotoTable photo_table = new PhotoTable();
    private EventTable event_table = new EventTable();
    
    private Gtk.TreeView sidebar = null;
    private Gtk.TreeStore sidebar_store = null;
    private Gtk.TreeRowReference cameras_row = null;
    
    private Gtk.Notebook notebook = new Gtk.Notebook();
    private Gtk.Box layout = new Gtk.VBox(false, 0);
    private Page current_page = null;
    
    private GPhoto.Context null_context = new GPhoto.Context();
    private GPhoto.CameraAbilitiesList abilities_list;
    
    private SortedList<int64?> imported_photos = null;
    private ImportID import_id = ImportID();
    
    private FullscreenWindow fullscreen_window = null;
    
    public AppWindow() {
        // if this is the first AppWindow, it's the main AppWindow
        assert(instance == null);
        instance = this;
        
        title = TITLE;
        set_default_size(1024, 768);

        destroy += Gtk.main_quit;
        
        debug("Verifying databases ...");
        verify_databases();
        
        // prepare the default parent and orphan pages
        collection_page = new CollectionPage();
        events_directory_page = new EventsDirectoryPage();
        photo_page = new PhotoPage();

        // create Photo objects for all photos in the database and load into the Photos page
        PhotoID[] all_photo_ids = photo_table.get_photos();
        foreach (PhotoID photo_id in all_photo_ids) {
             Photo photo = Photo.fetch(photo_id);
             photo.removed += on_photo_removed;
             
             collection_page.add_photo(photo);
        }

        // prepare the sidebar
        sidebar_store = new Gtk.TreeStore(1, typeof(string));
        sidebar = new Gtk.TreeView.with_model(sidebar_store);

        var text = new Gtk.CellRendererText();
        var column = new Gtk.TreeViewColumn();
        column.pack_start(text, true);
        column.add_attribute(text, "text", 0);
        sidebar.append_column(column);
        
        sidebar.set_headers_visible(false);

        // add the default parents and orphans
        add_parent_page(collection_page, "Photos");
        add_parent_page(events_directory_page, "Events");
        add_orphan_page(photo_page);

        // "Cameras" doesn't have its own page, just a parent row
        Gtk.TreeIter parent;
        sidebar_store.append(out parent, null);
        sidebar_store.set(parent, 0, "Cameras");
        cameras_row = new Gtk.TreeRowReference(sidebar_store, sidebar_store.get_path(parent));
        
        // add stored events
        EventID[] events = event_table.get_events();
        foreach (EventID event_id in events)
            add_event_page(event_id);
        
        sidebar.cursor_changed += on_sidebar_cursor_changed;
        
        // start in the collection page & control selection aspects
        Gtk.TreeSelection selection = sidebar.get_selection();
        selection.select_path(collection_page.get_marker().get_row().get_path());
        selection.set_mode(Gtk.SelectionMode.BROWSE);

        sidebar.expand_all();
        
        create_layout(collection_page);

        // set up main window as a drag-and-drop destination (rather than each page; assume
        // a drag and drop is for general library importation, which means it goes to collection_page)
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, TARGET_ENTRIES, Gdk.DragAction.COPY);
        
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
    }
    
    public Gtk.ActionGroup get_common_action_group() {
        // each page gets its own one
        Gtk.ActionGroup action_group = new Gtk.ActionGroup("CommonActionGroup");
        action_group.add_actions(COMMON_ACTIONS, this);
        
        return action_group;
    }
    
    private void on_about() {
        // TODO: More thorough About box
        Gtk.show_about_dialog(this,
            "version", AppWindow.VERSION,
            "comments", "A photo organizer",
            "copyright", "(c) 2009 Yorba Foundation",
            "website", "http://www.yorba.org"
        );
    }
    
    private void on_fullscreen() {
        if (fullscreen_window != null) {
            fullscreen_window.present();
            
            return;
        }

        if (current_page is CheckerboardPage) {
            LayoutItem item = ((CheckerboardPage) current_page).get_fullscreen_photo();
            if (item == null) {
                debug("No fullscreen photo for this view");
                
                return;
            }
                
            // needs to be a thumbnail
            assert(item is Thumbnail);
            
            // set up fullscreen view and hide ourselves until it's closed
            fullscreen_window = new FullscreenWindow(get_screen(), (CheckerboardPage) current_page, 
                (Thumbnail) item);
        } else if (current_page is PhotoPage) {
            fullscreen_window = new FullscreenWindow(get_screen(), ((PhotoPage) current_page).get_controller(),
                ((PhotoPage) current_page).get_thumbnail());
        } else {
            error("Unable to present fullscreen view for this page");
        }
        
        fullscreen_window.present();
        hide();
    }
    
    public void end_fullscreen() {
        if (fullscreen_window == null)
            return;
        
        show_all();
        
        fullscreen_window.hide();
        fullscreen_window = null;
        
        present();
    }
    
    public class DateComparator : Comparator<int64?> {
        private PhotoTable photo_table;
        
        public DateComparator(PhotoTable photo_table) {
            this.photo_table = photo_table;
        }
        
        public override int64 compare(int64? ida, int64? idb) {
            time_t timea = photo_table.get_exposure_time(PhotoID(ida));
            time_t timeb = photo_table.get_exposure_time(PhotoID(idb));
            
            return timea - timeb;
        }
    }
    
    public void start_import_batch() {
        imported_photos = new SortedList<int64?>(new Gee.ArrayList<int64?>(), new DateComparator(photo_table));
        import_id = photo_table.generate_import_id();
    }

    public void import(File file) {
        FileType type = file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        if(type == FileType.REGULAR) {
            if (!import_file(file)) {
                // TODO: These should be aggregated so the user gets one report and not multiple,
                // one for each file imported
                Gtk.MessageDialog dialog = new Gtk.MessageDialog(this, Gtk.DialogFlags.MODAL,
                    Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s already stored",
                    file.get_path());
                dialog.run();
                dialog.destroy();
            }
            
            return;
        } else if (type != FileType.DIRECTORY) {
            debug("Skipping file %s (neither a directory nor a file)", file.get_path());
            
            return;
        }
        
        debug("Importing directory %s", file.get_path());
        import_dir(file);
    }
    
    public void end_import_batch() {
        if (imported_photos == null)
            return;
        
        split_into_events(imported_photos);

        // reset
        imported_photos = null;
        import_id = ImportID();
    }
    
    public void split_into_events(SortedList<int64?> list) {
        debug("Processing photos to create events ...");

        // walk through photos, splitting into events based on criteria
        time_t last_exposure = 0;
        time_t current_event_start = 0;
        EventID current_event_id = EventID();
        EventPage current_page = null;
        foreach (int64 id in imported_photos) {
            PhotoID photo_id = PhotoID(id);

            PhotoRow photo;
            bool found = photo_table.get_photo(photo_id, out photo);
            assert(found);
            
            if (photo.exposure_time == 0) {
                // no time recorded; skip
                debug("Skipping %s: No exposure time", photo.file.get_path());
                
                continue;
            }
            
            if (photo.event_id.is_valid()) {
                // already part of an event; skip
                debug("Skipping %s: Already part of event %lld", photo.file.get_path(),
                    photo.event_id.id);
                    
                continue;
            }
            
            bool create_event = false;
            if (last_exposure == 0) {
                // first photo, start a new event
                create_event = true;
            } else {
                assert(last_exposure <= photo.exposure_time);
                assert(current_event_start <= photo.exposure_time);

                if (photo.exposure_time - last_exposure >= EVENT_LULL_SEC) {
                    // enough time has passed between photos to signify a new event
                    create_event = true;
                } else if (photo.exposure_time - current_event_start >= EVENT_MAX_DURATION_SEC) {
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

                current_event_start = photo.exposure_time;
                current_event_id = event_table.create(photo_id, current_event_start);
                
                current_page = add_event_page(current_event_id);

                debug("Created event [%lld]", current_event_id.id);
            }
            
            assert(current_event_id.is_valid());
            
            debug("Adding %s to event %lld (exposure=%ld last_exposure=%ld)", photo.file.get_path(), 
                current_event_id.id, photo.exposure_time, last_exposure);
            
            photo_table.set_event(photo_id, current_event_id);

            current_page.add_photo(Photo.fetch(photo_id));
            
            last_exposure = photo.exposure_time;
        }
    }
    
    private void import_dir(File dir) {
        assert(dir.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null) == FileType.DIRECTORY);
        
        try {
            FileEnumerator enumerator = dir.enumerate_children("*",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            if (enumerator == null) {
                return;
            }
            
            for (;;) {
                FileInfo info = enumerator.next_file(null);
                if (info == null) {
                    break;
                }
                
                File file = dir.get_child(info.get_name());
                
                FileType type = info.get_file_type();
                if (type == FileType.REGULAR) {
                    if (!import_file(file)) {
                        // TODO: Better error reporting
                        message("Failed to import %s (already imported?)", file.get_path());
                    }
                } else if (type == FileType.DIRECTORY) {
                    debug("Importing directory  %s", file.get_path());

                    import_dir(file);
                } else {
                    debug("Skipped %s", file.get_path());
                }
            }
        } catch (Error err) {
            // TODO: Better error reporting
            error("Error importing: %s", err.message);
        }
    }
    
    private bool import_file(File file) {
        // TODO: This eases the pain until background threads are implemented
        while (Gtk.events_pending()) {
            if (Gtk.main_iteration()) {
                debug("import_dir: Gtk.main_quit called");
                
                return false;
            }
        }
        
        Photo photo = Photo.import(file, import_id);
        if (photo == null)
            return false;

        // want to know when it's removed from the system for cleanup
        photo.removed += on_photo_removed;
        
        // automatically add to the Photos page
        collection_page.add_photo(photo);
        collection_page.refresh();
            
        // add to imported list for splitting into events
        if (imported_photos != null) {
            PhotoID photo_id = photo.get_photo_id();
            imported_photos.add(photo_id.id);
        }

        return true;
    }
    
    private void on_photo_removed(Photo photo) {
        debug("on_photo_removed");
        
        PhotoID photo_id = photo.get_photo_id();
        
        // update event's primary photo if this is the one; remove event if no more photos in it
        EventID event_id = photo_table.get_event(photo_id);
        if (event_id.is_valid() && (event_table.get_primary_photo(event_id).id == photo_id.id)) {
            PhotoID[] photos = photo_table.get_event_photos(event_id);
            
            PhotoID found = PhotoID();
            // TODO: For now, simply selecting the first photo possible
            foreach (PhotoID id in photos) {
                if (id.id != photo_id.id) {
                    found = id;
                    
                    break;
                }
            }
            
            if (found.is_valid()) {
                event_table.set_primary_photo(event_id, found);
            } else {
                // this indicates this is the last photo of the event, so no more event
                assert(photos.length <= 1);
                remove_event_page(event_id);
                event_table.remove(event_id);
            }
        }
    }

    // This function should only be called prior to creating Photo objects, as once they're created,
    // they assume full knowledge/control over their assigned photo
    private void verify_databases() {
        PhotoID[] ids = photo_table.get_photos();

        // verify photo table
        foreach (PhotoID photo_id in ids) {
            PhotoRow row = PhotoRow();
            photo_table.get_photo(photo_id, out row);
            
            FileInfo info = null;
            try {
                info = row.file.query_info("*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            } catch (Error err) {
                error("%s", err.message);
            }
            
            TimeVal timestamp = TimeVal();
            info.get_modification_time(timestamp);
            
            // trust modification time and file size
            if ((timestamp.tv_sec == row.timestamp) && (info.get_size() == row.filesize))
                continue;
            
            message("Time or filesize changed on %s, reimporting ...", row.file.get_path());
            
            Dimensions dim = Dimensions();
            Orientation orientation = Orientation.TOP_LEFT;
            time_t exposure_time = 0;

            // TODO: Try to read JFIF metadata too
            PhotoExif exif = new PhotoExif(row.file);
            if (exif.has_exif()) {
                if (!exif.get_dimensions(out dim)) {
                    error("Unable to read EXIF dimensions for %s", row.file.get_path());
                }
                
                if (!exif.get_datetime_time(out exposure_time)) {
                    error("Unable to read EXIF orientation for %s", row.file.get_path());
                }

                orientation = exif.get_orientation();
            } 
        
            Gdk.Pixbuf original;
            try {
                original = new Gdk.Pixbuf.from_file(row.file.get_path());
                
                if (!exif.has_exif())
                    dim = Dimensions(original.get_width(), original.get_height());
            } catch (Error err) {
                error("%s", err.message);
            }
        
            if (photo_table.update(photo_id, dim, info.get_size(), timestamp.tv_sec, exposure_time,
                orientation)) {
                ThumbnailCache.import(photo_id, original, true);
            }
        }

        // verify event table
        EventID[] events = event_table.get_events();
        foreach (EventID event_id in events) {
            PhotoID[] photos = photo_table.get_event_photos(event_id);
            if (photos.length == 0) {
                message("Removing event %lld: No photos associated with event", event_id.id);
                event_table.remove(event_id);
            }
        }
    }

    public override void drag_data_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time) {
        // grab data and release back to system
        string[] uris = selection_data.get_uris();
        Gtk.drag_finish(context, true, false, time);
        
        // TODO: Background threads
        start_import_batch();
        foreach (string uri in uris) {
            import(File.new_for_uri(uri));
        }
        end_import_batch();
        
        collection_page.refresh();
    }
    
    public static void error_message(string message) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(get_instance(), Gtk.DialogFlags.MODAL, 
            Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", message);
        dialog.run();
        dialog.destroy();
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
    
    public EventPage? find_event_page(EventID event_id) {
        foreach (EventPage page in event_list) {
            if (page.event_id.id == event_id.id)
                return page;
        }
        
        return null;
    }
    
    private EventPage add_event_page(EventID event_id) {
        string name = event_table.get_name(event_id);
        EventPage event_page = new EventPage(event_id);
        
        PhotoID[] photo_ids = photo_table.get_event_photos(event_id);
        foreach (PhotoID photo_id in photo_ids)
            event_page.add_photo(Photo.fetch(photo_id));

        add_child_page(events_directory_page, event_page, name);
        event_list.add(event_page);
        
        return event_page;
    }
    
    private void remove_event_page(EventID event_id) {
        EventPage page = find_event_page(event_id);
        assert(page != null);
        
        remove_page(page);
        event_list.remove(page);
    }

    private Gtk.TreePath add_sidebar_parent(string name) {
        Gtk.TreeIter parent;
        sidebar_store.append(out parent, null);
        sidebar_store.set(parent, 0, name);

        return sidebar_store.get_path(parent);
    }
    
    private Gtk.TreePath add_sidebar_child(Gtk.TreeRowReference row, string name) {
        Gtk.TreeIter parent, child;
        sidebar_store.get_iter(out parent, row.get_path());
        sidebar_store.append(out child, parent);
        sidebar_store.set(child, 0, name);
        
        return sidebar_store.get_path(child);
    }
    
    private void add_parent_page(Page parent, string name) {
        // need to show all before handing over to notebook
        parent.show_all();
    
        // layout for notebook
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(parent, true, true, 0);
        vbox.pack_end(parent.get_toolbar(), false, false, 0);
        
        // add to notebook
        int pos = notebook.append_page(vbox, null);
        assert(pos >= 0);
        
        // add to sidebar
        Gtk.TreePath path = add_sidebar_parent(name);
        
        parent.set_marker(new PageMarker(vbox, sidebar_store, path));
        
        notebook.show_all();
    }
    
    private void add_child_page_to_row(Gtk.TreeRowReference parent, Page child, string name) {
        // need to show_all before handing over to notebook
        child.show_all();
        
        // layout for notebook
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(child, true, true, 0);
        vbox.pack_end(child.get_toolbar(), false, false, 0);
        
        // add to notebook
        int pos = notebook.append_page(vbox, null);
        assert(pos >= 0);
        
        // add to sidebar
        Gtk.TreePath path = add_sidebar_child(parent, name);
        
        child.set_marker(new PageMarker(vbox, sidebar_store, path));
        
        notebook.show_all();
    }
    
    private void add_child_page(Page parent, Page child, string name) {
        add_child_page_to_row(parent.get_marker().get_row(), child, name);
    }

    // an orphan page is a Page that exists in the notebook (and can therefore be switched to) but
    // is not listed in the sidebar
    private void add_orphan_page(Page orphan) {
        // need to show_all before handing over to notebook
        orphan.show_all();
        
        // layout for notebook
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(orphan, true, true, 0);
        vbox.pack_end(orphan.get_toolbar(), false, false, 0);
        
        // add to notebook
        int pos = notebook.append_page(vbox, null);
        assert(pos >= 0);
        
        orphan.set_marker(new PageMarker(vbox));
        
        notebook.show_all();
    }
    
    private void remove_page(Page page) {
        // a handful of pages just don't go away
        assert(page != collection_page);
        assert(page != events_directory_page);
        assert(page != photo_page);
        
        PageMarker marker = page.get_marker();

        // remove from notebook
        int pos = get_notebook_pos(page);
        assert(pos >= 0);
        notebook.remove_page(pos);

        // remove from sidebar, if present
        if (marker.get_row() != null) {
            Gtk.TreeIter iter;
            bool found = sidebar_store.get_iter(out iter, marker.get_row().get_path());
            assert(found);
            sidebar_store.remove(iter);
        }

        // switch away if necessary to collection page (which is always present)
        if (current_page == page)
            switch_to_collection_page();
    }
    
    private int get_notebook_pos(Page page) {
        PageMarker marker = page.get_marker();
        
        int pos = notebook.page_num(marker.notebook_page);
        assert(pos != -1);
        
        return pos;
    }
    
    private void create_layout(Page start_page) {
        // use a Notebook to hold all the pages, which are switched when a sidebar child is selected
        notebook.set_show_tabs(false);
        notebook.set_show_border(false);
        
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

        PageMarker marker = page.get_marker();
        if (marker.get_row() != null)
            sidebar.get_selection().select_path(marker.get_row().get_path());
        
        page.show_all();
        
        page.switched_to();
    }
    
    private bool is_page_selected(Page page, Gtk.TreePath path) {
        PageMarker marker = page.get_marker();
        if (marker.get_row() == null)
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
                            + "Shotwell can only access the drive when it's unlocked.  "
                            + "Do you want Shotwell to unmount the drive for you?");
                        int dialog_res = dialog.run();
                        dialog.destroy();
                        
                        if (dialog_res != Gtk.ResponseType.YES) {
                            page.set_page_message("Please unmount the camera.");
                            page.refresh();
                        } else {
                            mount.unmount(MountUnmountFlags.NONE, null, page.on_unmounted);
                        }
                    } else {
                        // it's not mounted, so another application must have it locked
                        Gtk.MessageDialog dialog = new Gtk.MessageDialog(this,
                            Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING,
                            Gtk.ButtonsType.OK,
                            "The camera is locked by another application.  "
                            + "Shotwell can only access the drive when it's unlocked.  "
                            + "Please close any other application using the camera and try again.");
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

    private void on_sidebar_cursor_changed() {
        Gtk.TreePath path;
        sidebar.get_cursor(out path, null);
        
        if (is_page_selected(collection_page, path)) {
            switch_to_collection_page();
        } else if (is_page_selected(events_directory_page, path)) {
            switch_to_events_directory_page();
        } else if (path.compare(cameras_row.get_path()) == 0) {
            // TODO: Make Cameras unselectable and invisible when no cameras attached
            message("Cameras selected");
        } else if (is_camera_selected(path)) {
            // camera path selected and updated
        } else if (is_event_selected(path)) {
            // event page selected and updated
        } else {
            debug("Unimplemented page selected");
        }
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
    
    private string get_port_uri(string port) {
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
            add_child_page_to_row(cameras_row, page, name);

            camera_map.set(uri, page);
            
            // automagically expand the Cameras branch so the user sees the attached camera(s)
            sidebar.expand_row(cameras_row.get_path(), true);
        }
    }
    
    private static void on_device_added(Hal.Context context, string udi) {
        debug("******* on_device_added: %s", udi);
        
        try {
            AppWindow.get_instance().update_camera_table();
        } catch (GPhotoError err) {
            debug("Error updating camera table: %s", err.message);
        }
    }
    
    private static void on_device_removed(Hal.Context context, string udi) {
        debug("******** on_device_removed: %s", udi);
        
        try {
            AppWindow.get_instance().update_camera_table();
        } catch (GPhotoError err) {
            debug("Error updating camera table: %s", err.message);
        }
    }
    
    public static void mounted_camera_shell_notification(File uri) {
        debug("mount point reported: %s", uri.get_uri());

        if (uri.has_uri_scheme("gphoto2:")) {
            debug("Only unmount URIs with gphoto2 scheme: %s (%s)", uri.get_uri(), uri.get_uri_scheme());
            
            return;
        }
        
        Mount mount = null;
        try {
            mount = uri.find_enclosing_mount(null);
        } catch (Error err) {
            debug("%s", err.message);
            
            return;
        }
        
        ImportPage page = get_instance().camera_map.get(uri.get_uri());
        if (page == null) {
            debug("Unable to find camera for %s", uri.get_uri());
            
            return;
        }
        
        mount.unmount(MountUnmountFlags.NONE, null, page.on_unmounted);
    }
}
