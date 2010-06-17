/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class LibraryWindow : AppWindow {
    public const int SIDEBAR_MIN_WIDTH = 180;
    public const int SIDEBAR_MAX_WIDTH = 320;
    public const int PAGE_MIN_WIDTH = 
        Thumbnail.MAX_SCALE + (CheckerboardLayout.COLUMN_GUTTER_PADDING * 2);
    
    public const int SORT_EVENTS_ORDER_ASCENDING = 0;
    public const int SORT_EVENTS_ORDER_DESCENDING = 1;
    
    private const string[] SUPPORTED_MOUNT_SCHEMES = {
        "gphoto2:",
        "disk:",
        "file:"
    };

    protected enum TargetType {
        URI_LIST,
        PHOTO_LIST
    }
    
    public const Gtk.TargetEntry[] DEST_TARGET_ENTRIES = {
        { "text/uri-list", Gtk.TargetFlags.OTHER_APP, TargetType.URI_LIST },
        { "shotwell/photo-id", Gtk.TargetFlags.SAME_APP, TargetType.PHOTO_LIST }
    };
    
    // In fullscreen mode, want to use LibraryPhotoPage, but fullscreen has different requirements,
    // esp. regarding when the widget is realized and when it should first try and throw them image
    // on the page.  This handles this without introducing lots of special cases in
    // LibraryPhotoPage.
    private class FullscreenPhotoPage : LibraryPhotoPage {
        private CollectionPage collection;
        private Thumbnail start;
        
        public FullscreenPhotoPage(CollectionPage collection, Thumbnail start) {
            this.collection = collection;
            this.start = start;
        }
        
        public override void switched_to() {
            display_for_collection(collection, start.get_photo());
            base.switched_to();
        }
    }
    
    private class PageLayout : Gtk.VBox {
        private string page_name;
        private Gtk.Toolbar toolbar;
        
        public PageLayout(Page page) {
            page_name = page.get_page_name();
            toolbar = page.get_toolbar();
            
            set_homogeneous(false);
            set_spacing(0);
            
            pack_start(page, true, true, 0);
            pack_end(toolbar, false, false, 0);
        }
        
        ~PageLayout() {
#if TRACE_DTORS
            debug("DTOR: PageLayout for %s", page_name);
#endif
        }
        
        public override void destroy() {
            // because Page destroys all its own widgets, need to prevent a double-destroy on
            // the toolbar
            if (toolbar is Gtk.Widget)
                remove(toolbar);
            toolbar = null;
            
            base.destroy();
        }
    }
    
    public static Gdk.Color SIDEBAR_BG_COLOR = parse_color("#EEE");

    private string import_dir = Environment.get_home_dir();

    private Gtk.VPaned sidebar_paned = new Gtk.VPaned();
    private Gtk.HPaned client_paned = new Gtk.HPaned();
    private Gtk.Frame bottom_frame = new Gtk.Frame(null);

    private class FileImportJob : BatchImportJob {
        private File file_or_dir;
        private bool copy_to_library;
        
        public FileImportJob(File file_or_dir, bool copy_to_library) {
            this.file_or_dir = file_or_dir;
            this.copy_to_library = copy_to_library;
        }
        
        public override string get_identifier() {
            return file_or_dir.get_path();
        }
        
        public override bool is_directory() {
            return query_is_directory(file_or_dir);
        }
        
        public override bool determine_file_size(out uint64 filesize, out File file) {
            file = file_or_dir;
            
            return false;
        }
        
        public override bool prepare(out File file_to_import, out bool copy) {
            file_to_import = file_or_dir;
            copy = copy_to_library;
            
            return true;
        }
    }

    // In order to prevent creating a slew of Pages at app startup, lazily create them as the
    // user needs them ... this may be supplemented in the future to discard unused Pages (in
    // a lifo)
    private abstract class PageStub : Object, SidebarPage {
        private Page page = null;
        private SidebarMarker marker = null;
        
        protected abstract Page construct_page();

        public abstract string get_name();

        public bool has_page() {
            return page != null;
        }
        
        public Page get_page() {
            if (page == null) {
                // create the page and set its marker, if one has been supplied
                page = construct_page();
                if (marker != null)
                    page.set_marker(marker);
                
                // add this to the notebook and tell the notebook to show it (as per DevHelp)
                LibraryWindow.get_app().add_to_notebook(page);
            }

            return page;
        }
        
        public string get_sidebar_text() {
            return (page != null) ? page.get_sidebar_text() : get_name();
        }
        
        public SidebarMarker? get_marker() {
            return (page != null) ? page.get_marker() : marker;
        }
        
        public void set_marker(SidebarMarker marker) {
            this.marker = marker;
            if (page != null)
                page.set_marker(marker);
        }
        
        public void clear_marker() {
            this.marker = null;
            if (page != null)
                page.clear_marker();
        }

        public virtual string get_page_name() {
            if (page == null)
                return get_name();
            return page.get_page_name();
        }

        public Gtk.Menu? get_page_context_menu() {
            if (page == null)
                get_page();
            return page.get_page_context_menu();
        }

        public bool popup_context_menu(Gtk.Menu? context_menu, Gdk.EventButton? event = null) {
            if (page == null)
                get_page();
            return page.popup_context_menu(context_menu, event);
        }
    }

    private class SubEventsDirectoryPageStub : PageStub {
        public SubEventsDirectoryPage.DirectoryType type;
        public Time time;
        private string page_name;

        public SubEventsDirectoryPageStub(SubEventsDirectoryPage.DirectoryType type, Time time) {
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
            debug("Creating new event directory page for %s", page_name);
            return new SubEventsDirectoryPage(type, time);
        }

        public int get_month() {
            return (type == SubEventsDirectoryPage.DirectoryType.MONTH) ? time.month : 0;
        }

        public int get_year() {
            return time.year;
        }

        public override string get_name() {
            return page_name;
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

    private class EventPageStub : PageStub {
        public Event event;

        public EventPageStub(Event event) {
            this.event = event;
        }

        public override string get_name() {
            return event.get_name();
        }

        protected override Page construct_page() {
            debug("Creating new event page for %s", event.get_name());
            return ((Page) new EventPage(event));
        }
    }
    
    private class TagPageStub : PageStub {
        public Tag tag;
        
        public TagPageStub(Tag tag) {
            this.tag = tag;
        }
        
        public override string get_name() {
            return tag.get_name();
        }
        
        protected override Page construct_page() {
            debug("Creating new tag page for %s", tag.get_name());
            return new TagPage(tag);
        }
    }
    
    // Static (default) pages
    private LibraryPage library_page = null;
    private MasterEventsDirectoryPage events_directory_page = null;
    private LibraryPhotoPage photo_page = null;
    private TrashPage trash_page = null;
    private ImportQueuePage import_queue_page = null;
    private bool displaying_import_queue_page = false;
    
    private bool notify_library_is_home_dir = true;
    
    // Dynamically added/removed pages
    private Gee.HashMap<Page, PageLayout> page_layouts = new Gee.HashMap<Page, PageLayout>();
    private Gee.ArrayList<EventPageStub> event_list = new Gee.ArrayList<EventPageStub>();
    private Gee.ArrayList<SubEventsDirectoryPageStub> events_dir_list = 
        new Gee.ArrayList<SubEventsDirectoryPageStub>();
    private Gee.HashMap<Tag, TagPageStub> tag_map = new Gee.HashMap<Tag, TagPageStub>();
#if !NO_CAMERA
    private Gee.HashMap<string, ImportPage> camera_pages = new Gee.HashMap<string, ImportPage>(
        str_hash, str_equal, direct_equal);

    // this is to keep track of cameras which initiate the app
    private static Gee.HashSet<string> initial_camera_uris = new Gee.HashSet<string>();
#endif

    private Sidebar sidebar = new Sidebar();
#if !NO_CAMERA
    private SidebarMarker cameras_marker = null;
#endif
    private SidebarMarker tags_marker = null;

    private BasicProperties basic_properties = new BasicProperties();
    private ExtendedPropertiesWindow extended_properties;
    
    private Gtk.Notebook notebook = new Gtk.Notebook();
    private Gtk.Box layout = new Gtk.VBox(false, 0);
    
    public LibraryWindow(ProgressMonitor monitor) {
        // prepare the default parent and orphan pages
        // (these are never removed from the system)
        library_page = new LibraryPage(monitor);
        events_directory_page = new MasterEventsDirectoryPage();
        import_queue_page = new ImportQueuePage();
        import_queue_page.batch_removed.connect(import_queue_batch_finished);
        photo_page = new LibraryPhotoPage();
        trash_page = new TrashPage();
        
        // create and connect extended properties window
        extended_properties = new ExtendedPropertiesWindow(this);
        extended_properties.hide.connect(hide_extended_properties);
        extended_properties.show.connect(show_extended_properties);

        // add the default parents and orphans to the notebook
        add_parent_page(library_page);
        add_parent_page(events_directory_page);
        add_parent_page(trash_page);
        add_orphan_page(photo_page);

        // watch for new & removed events
        Event.global.items_added.connect(on_added_events);
        Event.global.items_removed.connect(on_removed_events);
        Event.global.item_altered.connect(on_event_altered);
        
        // watch for new & removed tags
        Tag.global.contents_altered.connect(on_tags_added_removed);
        Tag.global.item_altered.connect(on_tag_altered);
        
        // start in the collection page
        sidebar.place_cursor(library_page);
        
        // monitor cursor changes to select proper page in notebook
        sidebar.cursor_changed.connect(on_sidebar_cursor_changed);
        
        create_layout(library_page);

        // settings that should persist between sessions
        load_configuration();

        // add stored events
        foreach (DataObject object in Event.global.get_all())
            add_event_page((Event) object);
        
        // if events exist, expand to first one
        if (Event.global.get_count() > 0)
            sidebar.expand_to_first_child(events_directory_page.get_marker());
        
        // add tags
        foreach (DataObject object in Tag.global.get_all())
            add_tag_page((Tag) object);
        
        // if tags exist, expand them
        if (tags_marker != null)
            sidebar.expand_branch(tags_marker);
        
        // set up main window as a drag-and-drop destination (rather than each page; assume
        // a drag and drop is for general library import, which means it goes to library_page)
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, DEST_TARGET_ENTRIES,
            Gdk.DragAction.COPY | Gdk.DragAction.LINK | Gdk.DragAction.ASK);
        
#if !NO_CAMERA
        // monitor the camera table for additions and removals
        CameraTable.get_instance().camera_added.connect(add_camera_page);
        CameraTable.get_instance().camera_removed.connect(remove_camera_page);
        
        // need to populate pages with what's known now by the camera table
        foreach (DiscoveredCamera camera in CameraTable.get_instance().get_cameras())
            add_camera_page(camera);
#endif
        
        // connect to sidebar signal used ommited on drag-and-drop orerations
        sidebar.drop_received.connect(drop_received);
        
        // monitor trash to keep common actions up-to-date
        LibraryPhoto.global.trashcan_contents_altered.connect(on_trashcan_contents_altered);
    }
    
    ~LibraryWindow() {
        Event.global.items_added.disconnect(on_added_events);
        Event.global.items_removed.disconnect(on_removed_events);
        Event.global.item_altered.disconnect(on_event_altered);
        
        Tag.global.contents_altered.disconnect(on_tags_added_removed);
        Tag.global.item_altered.disconnect(on_tag_altered);
        
#if !NO_CAMERA
        CameraTable.get_instance().camera_added.disconnect(add_camera_page);
        CameraTable.get_instance().camera_removed.disconnect(remove_camera_page);
#endif
        
        unsubscribe_from_basic_information(get_current_page());

        extended_properties.hide.disconnect(hide_extended_properties);
        extended_properties.show.disconnect(show_extended_properties);
        
        LibraryPhoto.global.trashcan_contents_altered.disconnect(on_trashcan_contents_altered);
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry import = { "CommonFileImport", Resources.IMPORT,
            TRANSLATABLE, "<Ctrl>I", TRANSLATABLE, on_file_import };
        import.label = _("_Import From Folder...");
        import.tooltip = _("Import photos from disk to library");
        actions += import;

        Gtk.ActionEntry sort = { "CommonSortEvents", null, TRANSLATABLE, null, null,
            on_sort_events };
        sort.label = _("Sort _Events");
        actions += sort;

        Gtk.ActionEntry preferences = { "CommonPreferences", Gtk.STOCK_PREFERENCES, TRANSLATABLE,
            null, TRANSLATABLE, on_preferences };
        preferences.label = Resources.PREFERENCES_MENU;
        preferences.tooltip = Resources.PREFERENCES_TOOLTIP;
        actions += preferences;
        
        Gtk.ActionEntry empty = { "CommonEmptyTrash", Gtk.STOCK_CLEAR, TRANSLATABLE, null, null,
            on_empty_trash };
        empty.label = _("Empty T_rash");
        empty.tooltip = _("Delete all photos in the trash");
        actions += empty;
        
        return actions;
    }
    
    private Gtk.ToggleActionEntry[] create_toggle_actions() {
        Gtk.ToggleActionEntry[] actions = new Gtk.ToggleActionEntry[0];

        Gtk.ToggleActionEntry basic_props = { "CommonDisplayBasicProperties", null,
            TRANSLATABLE, "<Ctrl><Shift>I", TRANSLATABLE, on_display_basic_properties, false };
        basic_props.label = _("_Basic Information");
        basic_props.tooltip = _("Display basic information for the selection");
        actions += basic_props;

        Gtk.ToggleActionEntry extended_props = { "CommonDisplayExtendedProperties", null,
            TRANSLATABLE, "<Ctrl><Shift>X", TRANSLATABLE, on_display_extended_properties, false };
        extended_props.label = _("E_xtended Information");
        extended_props.tooltip = _("Display extended information for the selection");
        actions += extended_props;

        return actions;
    }

    private Gtk.RadioActionEntry[] create_order_actions() {
        Gtk.RadioActionEntry[] actions = new Gtk.RadioActionEntry[0];

        Gtk.RadioActionEntry ascending = { "CommonSortEventsAscending",
            Gtk.STOCK_SORT_ASCENDING, TRANSLATABLE, null, TRANSLATABLE,
            SORT_EVENTS_ORDER_ASCENDING };
        ascending.label = _("_Ascending");
        ascending.tooltip = _("Sort photos in an ascending order");
        actions += ascending;

        Gtk.RadioActionEntry descending = { "CommonSortEventsDescending",
            Gtk.STOCK_SORT_DESCENDING, TRANSLATABLE, null, TRANSLATABLE,
            SORT_EVENTS_ORDER_DESCENDING };
        descending.label = _("D_escending");
        descending.tooltip = _("Sort photos in a descending order");
        actions += descending;

        return actions;
    }

    public override void show_all() {
        base.show_all();

        Gtk.ToggleAction basic_properties_action = 
            (Gtk.ToggleAction) get_current_page().common_action_group.get_action(
            "CommonDisplayBasicProperties");
        assert(basic_properties_action != null);

        if (!basic_properties_action.get_active()) {
            bottom_frame.hide();
        }
    }    

    public static LibraryWindow get_app() {
        assert(instance is LibraryWindow);
        
        return (LibraryWindow) instance;
    }
    
    private int64 get_event_directory_page_time(SubEventsDirectoryPageStub *stub) {
        return (stub->get_year() * 100) + stub->get_month();
    }
    
    private int64 event_branch_comparator(void *aptr, void *bptr) {
        SidebarPage *a = (SidebarPage *) aptr;
        SidebarPage *b = (SidebarPage *) bptr;
        
        int64 start_a, start_b;
        if (a is SubEventsDirectoryPageStub && b is SubEventsDirectoryPageStub) {
            start_a = get_event_directory_page_time((SubEventsDirectoryPageStub *) a);
            start_b = get_event_directory_page_time((SubEventsDirectoryPageStub *) b);
        } else {
            assert(a is EventPageStub);
            assert(b is EventPageStub);
            
            start_a = ((EventPageStub *) a)->event.get_start_time();
            start_b = ((EventPageStub *) b)->event.get_start_time();
        }
        
        return start_a - start_b;
    }
    
    private int64 event_branch_ascending_comparator(void *a, void *b) {
        return event_branch_comparator(a, b);
    }
    
    private int64 event_branch_descending_comparator(void *a, void *b) {
        return event_branch_comparator(b, a);
    }
    
    private Comparator get_event_branch_comparator(int event_sort) {
        if (event_sort == LibraryWindow.SORT_EVENTS_ORDER_ASCENDING) {
            return event_branch_ascending_comparator;
        } else {
            assert(event_sort == LibraryWindow.SORT_EVENTS_ORDER_DESCENDING);
            
            return event_branch_descending_comparator;
        }
    }
    
    public static bool is_mount_uri_supported(string uri) {
        foreach (string scheme in SUPPORTED_MOUNT_SCHEMES) {
            if (uri.has_prefix(scheme))
                return true;
        }
        
        return false;
    }
    
    public override void add_common_actions(Gtk.ActionGroup action_group) {
        base.add_common_actions(action_group);
        
        action_group.add_actions(create_actions(), this);
        action_group.add_toggle_actions(create_toggle_actions(), this);
        action_group.add_radio_actions(create_order_actions(),
            SORT_EVENTS_ORDER_ASCENDING, on_events_sort_changed);
    }
    
    public override string get_app_role() {
        return Resources.APP_LIBRARY_ROLE;
    }

    private override void on_quit() {
        Config.get_instance().set_library_window_state(maximized, dimensions);

        Config.get_instance().set_sidebar_position(client_paned.position);

        Config.get_instance().set_photo_thumbnail_scale(CollectionPage.get_photo_thumbnail_scale());
        
        base.on_quit();
    }
    
    private override void on_fullscreen() {
        CollectionPage collection = null;
        Thumbnail start = null;
        
        // This method indicates one of the shortcomings right now in our design: we need a generic
        // way to access the collection of items each page is responsible for displaying.  Once
        // that refactoring is done, this code should get much simpler.
        
        Page current_page = get_current_page();
        if (current_page is CollectionPage) {
            CheckerboardItem item = ((CollectionPage) current_page).get_fullscreen_photo();
            if (item == null) {
                message("No fullscreen photo for this view");
                
                return;
            }
            
            collection = (CollectionPage) current_page;
            start = (Thumbnail) item;
        } else if (current_page is EventsDirectoryPage) {
            collection = ((EventsDirectoryPage) current_page).get_fullscreen_event();
            start = (Thumbnail) collection.get_fullscreen_photo();
        } else if (current_page is LibraryPhotoPage) {
            collection = ((LibraryPhotoPage) current_page).get_controller_page();
            start =  (Thumbnail) collection.get_view().get_view_for_source(
                ((LibraryPhotoPage) current_page).get_photo());
        } else {
            message("Unable to present fullscreen view for this page");
            
            return;
        }
        
        if (collection == null || start == null)
            return;
        
        FullscreenPhotoPage fs_photo = new FullscreenPhotoPage(collection, start);

        go_fullscreen(fs_photo);
    }
    
    private void on_file_import() {
        Gtk.FileChooserDialog import_dialog = new Gtk.FileChooserDialog(_("Import From Folder"), null,
            Gtk.FileChooserAction.SELECT_FOLDER, Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, 
            Gtk.STOCK_OK, Gtk.ResponseType.OK);
        import_dialog.set_select_multiple(true);
        import_dialog.set_current_folder(import_dir);
        
        int response = import_dialog.run();

        if (response == Gtk.ResponseType.OK) {
            Gtk.ResponseType copy_files_response = copy_files_dialog();
            
            if (copy_files_response != Gtk.ResponseType.CANCEL) {
                dispatch_import_jobs(import_dialog.get_uris(), "folders", 
                    copy_files_response == Gtk.ResponseType.ACCEPT);
            }
        }
        import_dir = import_dialog.get_current_folder();
        import_dialog.destroy();
    }
        
    protected override void switched_pages(Page? old_page, Page? new_page) {
        set_common_action_sensitive("CommonEmptyTrash", LibraryPhoto.global.get_trashcan_count() > 0);
        
        base.switched_pages(old_page, new_page);
    }
    
    private void on_trashcan_contents_altered() {
        set_common_action_sensitive("CommonEmptyTrash", LibraryPhoto.global.get_trashcan_count() > 0);
    }
    
    private void on_empty_trash() {
        Gee.ArrayList<LibraryPhoto> to_remove = new Gee.ArrayList<LibraryPhoto>();
        to_remove.add_all(LibraryPhoto.global.get_trashcan());
        
        remove_from_app(to_remove, _("Empty Trash"),  _("Emptying Trash..."));
    }
    
    public int get_events_sort() {
        return Config.get_instance().get_events_sort_ascending() ? SORT_EVENTS_ORDER_ASCENDING :
            SORT_EVENTS_ORDER_DESCENDING;
    }    

    private void on_sort_events() {
        // any member of the group can be told the current value
        Gtk.RadioAction action = (Gtk.RadioAction) get_current_page().common_action_group.get_action(
            "CommonSortEventsAscending");
        assert(action != null);

        action.set_current_value(get_events_sort());
    }
    
    private void on_events_sort_changed() {
        // any member of the group knows the value
        Gtk.RadioAction action = (Gtk.RadioAction) get_current_page().common_action_group.get_action(
            "CommonSortEventsAscending");
        assert(action != null);
        
        int new_events_sort = action.get_current_value();
        
        // don't resort if the order hasn't changed
        if (new_events_sort == get_events_sort())
            return;

        Config.get_instance().set_events_sort_ascending(new_events_sort == SORT_EVENTS_ORDER_ASCENDING);
       
        sidebar.sort_branch(events_directory_page.get_marker(), 
            get_event_branch_comparator(new_events_sort));

        // the events directory pages need to know about resort
        foreach (SubEventsDirectoryPageStub events_dir in events_dir_list) {
            if (events_dir.has_page())
                ((SubEventsDirectoryPage) events_dir.get_page()).notify_sort_changed();
        }
        
        // set the tree cursor to the current page, which might have been lost in the
        // delete/insert
        sidebar.place_cursor(get_current_page());

        // the events directory page needs to know about this
        events_directory_page.notify_sort_changed();
    }
    
    private void on_preferences() {
        PreferencesDialog.show();        
    }
    
    private void on_display_basic_properties(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();

        if (display) {
            basic_properties.update_properties(get_current_page());
            bottom_frame.show();
        } else {
            if (sidebar_paned.child2 != null) {
                bottom_frame.hide();
            }
        }

        // sync the setting so it will persist
        Config.get_instance().set_display_basic_properties(display);
    }

    private void on_display_extended_properties(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();

        if (display) {
            extended_properties.update_properties(get_current_page());
            extended_properties.show_all();
        } else {
            extended_properties.hide();
        }
    }

    private void show_extended_properties() {
        sync_extended_properties(true);
    }

    private void hide_extended_properties() {
        sync_extended_properties(false);
    }

    private void sync_extended_properties(bool show) {
        Gtk.ToggleAction extended_display_action = 
            (Gtk.ToggleAction) get_current_page().common_action_group.get_action(
            "CommonDisplayExtendedProperties");
        assert(extended_display_action != null);
        extended_display_action.set_active(show);

        // sync the setting so it will persist
        Config.get_instance().set_display_extended_properties(show);
    }

    public void enqueue_batch_import(BatchImport batch_import) {
        if (!displaying_import_queue_page) {
            insert_page_after(events_directory_page.get_marker(), import_queue_page);
            displaying_import_queue_page = true;
        }
        
        import_queue_page.enqueue_and_schedule(batch_import);
    }
    
    private void import_queue_batch_finished() {
        if (displaying_import_queue_page && import_queue_page.get_batch_count() == 0) {
            // only hide the import queue page, as it might be used later
            hide_page(import_queue_page, library_page);
            displaying_import_queue_page = false;
        }
    }
    
    private void import_reporter(ImportManifest manifest) {
        ImportUI.report_manifest(manifest, true);
    }

    private void dispatch_import_jobs(GLib.SList<string> uris, string job_name, bool copy_to_library) {
        if (AppDirs.get_import_dir().get_path() == Environment.get_home_dir() && notify_library_is_home_dir) {
            Gtk.ResponseType response = AppWindow.affirm_cancel_question(
                _("Shotwell is configured to import photos to your home directory.\n" + 
                "We recommend changing this in <span weight=\"bold\">Edit %s Preferences</span>.\n" + 
                "Do you want to continue importing photos?").printf("▸"),
                _("_Import"), _("Library Location"), AppWindow.get_instance());
            
            if (response == Gtk.ResponseType.CANCEL)
                return;
            
            notify_library_is_home_dir = false;
        }
        
        Gee.ArrayList<FileImportJob> jobs = new Gee.ArrayList<FileImportJob>();
        foreach (string uri in uris) {
            File file_or_dir = File.new_for_uri(uri);
            if (file_or_dir.get_path() == null) {
                // TODO: Specify which directory/file.
                AppWindow.error_message(_("Photos cannot be imported from this directory."));
                
                continue;
            }

            jobs.add(new FileImportJob(file_or_dir, copy_to_library));
        }
        
        if (jobs.size > 0) {
            BatchImport batch_import = new BatchImport(jobs, job_name, import_reporter);
            enqueue_batch_import(batch_import);
            switch_to_import_queue_page();
        }
    }
    
    private Gdk.DragAction get_drag_action() {
        Gdk.ModifierType mask;
        
        window.get_pointer(null, null, out mask);

        bool ctrl = (mask & Gdk.ModifierType.CONTROL_MASK) != 0;
        bool alt = (mask & Gdk.ModifierType.MOD1_MASK) != 0;
        bool shift = (mask & Gdk.ModifierType.SHIFT_MASK) != 0;
        
        if (ctrl && !alt && !shift)
            return Gdk.DragAction.COPY;
        else if (!ctrl && alt && !shift)
            return Gdk.DragAction.ASK;
        else if (ctrl && !alt && shift)
            return Gdk.DragAction.LINK;
        else
            return Gdk.DragAction.DEFAULT;
    }
    
    private override bool drag_motion(Gdk.DragContext context, int x, int y, uint time) {
        Gdk.Atom target = Gtk.drag_dest_find_target(this, context, 
			Gtk.drag_dest_get_target_list(this));
        
        if (((int) target) == ((int) Gdk.NONE)) {
            debug("drag target is GDK_NONE");
            Gdk.drag_status(context, 0, time);
            return true;
        }
        
        // internal drag
        if (Gtk.drag_get_source_widget(context) != null) {
            Gdk.drag_status(context, Gdk.DragAction.PRIVATE, time);
            return true;
        }
        
        // since we cannot set a default action, we must set it when we spy a drag motion
        Gdk.DragAction drag_action = get_drag_action();
        
        if (drag_action == Gdk.DragAction.DEFAULT)
            drag_action = Gdk.DragAction.LINK;
        
        Gdk.drag_status(context, drag_action, time);

        return true;
    }
    
    private override void drag_data_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time) {
        if (selection_data.length < 0)
            debug("failed to retrieve SelectionData");
        
        drop_received(context, x, y, selection_data, info, time, null, null);
    }

    private void drop_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time, Gtk.TreePath? path, 
        SidebarPage? page) {
        // determine if drag is internal or external
        if (Gtk.drag_get_source_widget(context) != null) {
            drop_internal(context, x, y, selection_data, info, time, path, page);
        } else {
            if (get_drag_action() == Gdk.DragAction.DEFAULT) {
                // the library dir must be created in order for the filesystem check to work...
                // here we attempt to create it just in case it's been renamed or deleted
                File library = AppDirs.get_import_dir();
                try {
                    library.make_directory_with_parents(null);
                } catch (Error err) {                    
                    // silently ignore, not creating a directory that already exists
                }
                
                Filesystem drag_filesystem = get_filesystem_relativity(library, 
                    Uri.list_extract_uris((string) selection_data.data));
                
                if (drag_filesystem != Filesystem.INTERNAL)
                    context.action = Gdk.DragAction.ASK;
            }
            
            drop_external(context, x, y, selection_data, info, time);
        }
    }

    private void drop_internal(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time, Gtk.TreePath? path,
        SidebarPage? page = null) {
        Gee.List<PhotoID?>? photo_ids = unserialize_photo_ids(selection_data.data,
            selection_data.get_length());
        
        Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        if (photo_ids != null) {
            foreach (PhotoID photo_id in photo_ids)
                photos.add(LibraryPhoto.global.fetch(photo_id));
        }
        
        if (photos.size == 0) {
            Gtk.drag_finish(context, false, false, time);
            
            return;
        }
        
        bool success = false;
        if (page is EventPageStub) {
            Event event = ((EventPageStub) page).event;

            Gee.ArrayList<PhotoView> views = new Gee.ArrayList<PhotoView>();
            foreach (LibraryPhoto photo in photos) {
                // don't move a photo into the event it already exists in
                if (photo.get_event() == null || !photo.get_event().equals(event))
                    views.add(new PhotoView(photo));
            }

            if (views.size > 0) {
                get_command_manager().execute(new SetEventCommand(views, event));
                success = true;
            }
        } else if (page is TagPageStub) {
            get_command_manager().execute(new TagUntagPhotosCommand(((TagPageStub) page).tag, photos, 
                photos.size, true));
            success = true;
        } else if (page is TrashPage) {
            get_command_manager().execute(new TrashUntrashPhotosCommand(photos, true));
            success = true;
        } else if (path != null && path.compare(tags_marker.get_path()) == 0) {
            AddTagsDialog dialog = new AddTagsDialog();
            string[]? names = dialog.execute();
            if (names != null) {
                get_command_manager().execute(new AddTagsCommand(names, photos));
                success = true;
            }
        }
        
        Gtk.drag_finish(context, success, false, time);
    }

    private void drop_external(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time) {
        // We extract the URI list using Uri.list_extract_uris() rather than
        // Gtk.SelectionData.get_uris() to work around this bug on Windows:
        // https://bugzilla.gnome.org/show_bug.cgi?id=599321
        string uri_string = (string) selection_data.data;
        string[] uris_array = Uri.list_extract_uris(uri_string);

        GLib.SList<string> uris = new GLib.SList<string>();
        foreach (string uri in uris_array) {
            uris.append(uri);
        }
        
        if (context.action == Gdk.DragAction.ASK) {
            Gtk.ResponseType result = copy_files_dialog();
            
            switch (result) {
                case Gtk.ResponseType.ACCEPT:
                    context.action = Gdk.DragAction.COPY;
                    break;
                
                case Gtk.ResponseType.REJECT:
                    context.action = Gdk.DragAction.LINK;
                    break;
                
                default:
                    // cancelled
                    Gtk.drag_finish(context, false, false, time);
                    
                    return;
            }
        }

        dispatch_import_jobs(uris, "drag-and-drop", context.action == Gdk.DragAction.COPY);

        Gtk.drag_finish(context, true, false, time);
    }
    
    public void switch_to_library_page() {
        switch_to_page(library_page);
    }
    
    public void switch_to_events_directory_page() {
        switch_to_page(events_directory_page);
    }
    
    public void switch_to_event(Event event) {
        EventPage page = load_event_page(event);
        if (page == null) {
            debug("Cannot find page for event %s", event.to_string());

            return;
        }

        switch_to_page(page);
    }
    
    public void switch_to_tag(Tag tag) {
        TagPageStub? stub = tag_map.get(tag);
        assert(stub != null);
        
        switch_to_page(stub.get_page());
    }
    
    public void switch_to_photo_page(CollectionPage controller, Photo current) {
        photo_page.display_for_collection(controller, current);
        switch_to_page(photo_page);
    }
    
    public void switch_to_import_queue_page() {
        switch_to_page(import_queue_page);
    }
    
    public EventPage? load_event_page(Event event) {
        foreach (EventPageStub stub in event_list) {
            if (stub.event.equals(event)) {
                // this will create the EventPage if not already created
                return (EventPage) stub.get_page();
            }
        }
        
        return null;
    }
    
    private void on_added_events(Gee.Iterable<DataObject> objects) {
        foreach (DataObject object in objects)
            add_event_page((Event) object);
    }
    
    private void on_removed_events(Gee.Iterable<DataObject> objects) {
        foreach (DataObject object in objects)
            remove_event_page((Event) object);
    }

    private void on_event_altered(DataObject object) {
        Event event = (Event) object;
        foreach (EventPageStub stub in event_list) {
            if (event.equals(stub.event)) {
                SubEventsDirectoryPageStub old_parent = 
                    (SubEventsDirectoryPageStub) sidebar.get_parent_page(stub);

                // only re-add to sidebar if the event has changed directories or shares its dir
                if (sidebar.get_children_count(old_parent.get_marker()) > 1 || 
                    !(old_parent.get_month() == Time.local(event.get_start_time()).month &&
                     old_parent.get_year() == Time.local(event.get_start_time()).year)) {
                    // remove from sidebar
                    remove_event_tree(stub, false);

                    // add to sidebar again
                    sidebar.insert_child_sorted(find_parent_marker(stub), stub,
                        get_event_branch_comparator(get_events_sort()));

                    sidebar.expand_tree(stub.get_marker());

                    if (get_current_page() is EventPage &&
                        ((EventPage) get_current_page()).page_event.equals(event))
                        sidebar.place_cursor(stub);
                }

                // refresh name
                SidebarMarker marker = stub.get_marker();
                sidebar.rename(marker, event.get_name());
                break;
            }
        }

        on_selection_changed();
    }
    
    private void on_tags_added_removed(Gee.Iterable<DataObject>? added, Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added)
                add_tag_page((Tag) object);
        }
        
        if (removed != null) {
            foreach (DataObject object in removed)
                remove_tag_page((Tag) object);
        }
        
        // open Tags so user sees the new ones
        if (added != null && tags_marker != null)
            sidebar.expand_branch(tags_marker);
    }
    
    private void on_tag_altered(DataObject object) {
        TagPageStub page_stub = tag_map.get((Tag) object);
        assert(page_stub != null);
        
        bool expanded = sidebar.is_branch_expanded(tags_marker);
        sidebar.remove_page(page_stub);
        sidebar.insert_child_sorted(tags_marker, page_stub, tag_page_comparator);
        if (expanded)
            sidebar.expand_branch(tags_marker);
    }
    
    private SidebarMarker? find_parent_marker(PageStub page) {
        // EventPageStub
        if (page is EventPageStub) {
            time_t event_time = ((EventPageStub) page).event.get_start_time();

            SubEventsDirectoryPage.DirectoryType type = (event_time != 0 ?
                SubEventsDirectoryPage.DirectoryType.MONTH :
                SubEventsDirectoryPage.DirectoryType.UNDATED);

            SubEventsDirectoryPageStub month = find_event_dir_page(type, Time.local(event_time));

            // if a month directory already exists, return it, otherwise, create a new one
            return (month != null ? month : create_event_dir_page(type,
                Time.local(event_time))).get_marker();
        } else if (page is SubEventsDirectoryPageStub) {
            SubEventsDirectoryPageStub event_dir_page = (SubEventsDirectoryPageStub) page;
            // SubEventsDirectoryPageStub Month
            if (event_dir_page.type == SubEventsDirectoryPage.DirectoryType.MONTH) {
                SubEventsDirectoryPageStub year = find_event_dir_page(
                    SubEventsDirectoryPage.DirectoryType.YEAR, event_dir_page.time);

                // if a month directory already exists, return it, otherwise, create a new one
                return (year != null ? year : create_event_dir_page(
                    SubEventsDirectoryPage.DirectoryType.YEAR, event_dir_page.time)).get_marker();
            }
            
            // SubEventsDirectoryPageStub Year && Undated
            return events_directory_page.get_marker();
        } else if (page is TagPageStub) {
            return tags_marker;
        }

        return null;
    }
    
    private SubEventsDirectoryPageStub? find_event_dir_page(SubEventsDirectoryPage.DirectoryType type, Time time) {
        foreach (SubEventsDirectoryPageStub dir in events_dir_list) {
            if (dir.matches(type,  time))
                return dir;
        }

        return null;
    }

    private SubEventsDirectoryPageStub create_event_dir_page(SubEventsDirectoryPage.DirectoryType type, Time time) {
        Comparator comparator = get_event_branch_comparator(get_events_sort());
        
        SubEventsDirectoryPageStub new_dir = new SubEventsDirectoryPageStub(type, time);

        sidebar.insert_child_sorted(find_parent_marker(new_dir), new_dir,
            comparator);

        events_dir_list.add(new_dir);

        return new_dir;
    }
    
    private int64 tag_page_comparator(void *a, void *b) {
        Tag atag = ((TagPageStub *) a)->tag;
        Tag btag = ((TagPageStub *) b)->tag;
        
        return atag.get_name().collate(btag.get_name());
    }
    
    private void add_tag_page(Tag tag) {
        if (tags_marker == null) {
            tags_marker = sidebar.insert_grouping_after(events_directory_page.get_marker(),
                _("Tags"));
        }
        
        TagPageStub stub = new TagPageStub(tag);
        sidebar.insert_child_sorted(tags_marker, stub, tag_page_comparator);
        tag_map.set(tag, stub);
    }
    
    private void remove_tag_page(Tag tag) {
        TagPageStub stub = tag_map.get(tag);
        assert(stub != null);
        
        remove_stub(stub, library_page);
        
        if (tag_map.size == 0 && tags_marker != null) {
            sidebar.prune_branch(tags_marker);
            tags_marker = null;
        }
    }

    private void add_event_page(Event event) {
        EventPageStub event_stub = new EventPageStub(event);
        
        sidebar.insert_child_sorted(find_parent_marker(event_stub), event_stub,
            get_event_branch_comparator(get_events_sort()));
        
        event_list.add(event_stub);
    }
    
    private void remove_event_page(Event event) {
        // don't use load_event_page, because that will create an EventPage (which we're simply
        // going to remove)
        EventPageStub event_stub = null;
        foreach (EventPageStub stub in event_list) {
            if (stub.event.equals(event)) {
                event_stub = stub;
                
                break;
            }
        }
        
        if (event_stub == null)
            return;
        
        // remove from sidebar
        remove_event_tree(event_stub);
        
        // jump to the Events page
        if (event_stub.has_page() && event_stub.get_page() == get_current_page())
            switch_to_events_directory_page();
    }

    private void remove_event_tree(PageStub stub, bool delete_stub = true) {
        // grab parent page
        SidebarPage parent = sidebar.get_parent_page(stub);
        
        // remove from notebook and sidebar
        if (delete_stub)
            remove_stub(stub, events_directory_page);
        else
            sidebar.remove_page(stub);
        
        // remove parent if empty
        if (parent != null && !(parent is MasterEventsDirectoryPage)) {
            assert(parent is PageStub);
            
            if (!sidebar.has_children(parent.get_marker()))
                remove_event_tree((PageStub) parent);
        }
    }
    
#if !NO_CAMERA
    private void add_camera_page(DiscoveredCamera camera) {
        ImportPage page = new ImportPage(camera.gcamera, camera.uri);   

        // create the Cameras row if this is the first one
        if (cameras_marker == null) {
            cameras_marker = sidebar.insert_grouping_after(
                (tags_marker != null) ? tags_marker : events_directory_page.get_marker(),
                _("Cameras"));
        }
        
        camera_pages.set(camera.uri, page);
        add_child_page(cameras_marker, page);

        // automagically expand the Cameras branch so the user sees the attached camera(s)
        sidebar.expand_branch(cameras_marker);
        
        // if this page is for a camera which initialized the app, we want to switch to that page
        if (initial_camera_uris.contains(page.get_uri())) {
            File uri_file = File.new_for_uri(page.get_uri());//page.get_uri());
            
            // find the VFS mount point
            Mount mount = null;
            try {
                mount = uri_file.find_enclosing_mount(null);
            } catch (Error err) {
                // error means not mounted
            }
            
            // don't unmount mass storage cameras, as they are then unavailable to gPhoto
            if (!camera.uri.has_prefix("file://")) {
                if (page.unmount_camera(mount))
                    switch_to_page(page);
                else
                    error_message("Unable to unmount the camera at this time.");
            } else {
                switch_to_page(page);
            }
        }
    }
    
    private void remove_camera_page(DiscoveredCamera camera) {
        // remove from page table and then from the notebook
        ImportPage page = camera_pages.get(camera.uri);
        camera_pages.unset(camera.uri);
        remove_page(page, library_page);

        // if no cameras present, remove row
        if (CameraTable.get_instance().get_count() == 0 && cameras_marker != null) {
            sidebar.prune_branch(cameras_marker);
            cameras_marker = null;
        }
    }
#endif
    
    private PageLayout? get_page_layout(Page page) {
        return page_layouts.get(page);
    }
    
    private PageLayout create_page_layout(Page page) {
        PageLayout layout = new PageLayout(page);
        page_layouts.set(page, layout);
        
        return layout;
    }
    
    private bool destroy_page_layout(Page page) {
        PageLayout? layout = get_page_layout(page);
        if (layout == null)
            return false;
        
        // destroy the layout, which destroys the page
        layout.destroy();
        
        bool unset = page_layouts.unset(page);
        assert(unset);
        
        return true;
    }
    
    private void add_to_notebook(Page page) {
        // get/create layout for this page (if the page is hidden the layout has already been
        // created)
        PageLayout? layout = get_page_layout(page);
        if (layout == null)
            layout = create_page_layout(page);
        
        // need to show all before handing over to notebook
        layout.show_all();
        
        int pos = notebook.append_page(layout, null);
        assert(pos >= 0);
        
        // need to show_all() after pages are added and removed
        notebook.show_all();
    }
    
    private void remove_from_notebook(Page page) {
        notebook.remove_page(get_notebook_pos(page));
        
        // need to show_all() after pages are added and removed
        notebook.show_all();
    }
    
    private int get_notebook_pos(Page page) {
        PageLayout? layout = get_page_layout(page);
        assert(layout != null);
        
        int pos = notebook.page_num(layout);
        assert(pos != -1);
        
        return pos;
    }
    
    private void add_parent_page(Page parent) {
        add_to_notebook(parent);

        sidebar.add_parent(parent);
    }

#if !NO_CAMERA    
    private void add_child_page(SidebarMarker parent_marker, Page child) {
        add_to_notebook(child);
        
        sidebar.add_child(parent_marker, child);
    }
#endif
    
    private void insert_page_after(SidebarMarker after_marker, Page page) {
        add_to_notebook(page);
        
        sidebar.insert_sibling_after(after_marker, page);
    }
    
    // an orphan page is a Page that exists in the notebook (and can therefore be switched to) but
    // is not listed in the sidebar
    private void add_orphan_page(Page orphan) {
        add_to_notebook(orphan);
    }
    
    // This removes the page from the notebook and the sidebar, but does not actually notify it
    // that it's been removed from the system, allowing it to be added back later.
    private void hide_page(Page page, Page fallback_page) {
        if (get_current_page() == page)
            switch_to_page(fallback_page);
        
        debug("Hiding page %s", page.get_page_name());
        
        remove_from_notebook(page);
        sidebar.remove_page(page);
        
        debug("Hid page %s", page.get_page_name());
    }
    
    private void remove_page(Page page, Page fallback_page) {
        // a handful of pages just don't go away
        assert(page != library_page);
        assert(page != events_directory_page);
        assert(page != photo_page);
        assert(page != import_queue_page);
        
        // switch away if necessary to ensure Page is fully detached from system
        if (get_current_page() == page)
            switch_to_page(fallback_page);
        
        debug("Removing page %s", page.get_page_name());
        
        // detach from notebook and sidebar
        sidebar.remove_page(page);
        remove_from_notebook(page);
        
        // destroy layout if it exists, otherwise just the page
        if (!destroy_page_layout(page))
            page.destroy();
        
        debug("Removed page %s", page.get_page_name());
    }
    
    private void remove_stub(PageStub stub, Page fallback_page) {
        // remove from appropriate list
        if (stub is SubEventsDirectoryPageStub) {
            // remove from events directory list 
            bool removed = events_dir_list.remove((SubEventsDirectoryPageStub) stub);
            assert(removed);
        } else if (stub is EventPageStub) {
            // remove from the events list
            bool removed = event_list.remove((EventPageStub) stub);
            assert(removed);
        } else if (stub is TagPageStub) {
            bool removed = tag_map.unset(((TagPageStub) stub).tag);
            assert(removed);
        }
        
        // remove stub (which holds a marker) from the sidebar
        sidebar.remove_page(stub);
        
        if (stub.has_page()) {
            // ensure the page is fully detached
            if (get_current_page() == stub.get_page())
                switch_to_page(fallback_page);
            
            // detach from notebook
            remove_from_notebook(stub.get_page());
            
            // destroy page layout if it exists, otherwise just the page
            if (!destroy_page_layout(stub.get_page()))
                stub.get_page().destroy();
        }
    }
    
    // check for settings that should persist between instances
    private void load_configuration() {
        Gtk.ToggleAction basic_display_action = 
            (Gtk.ToggleAction) get_current_page().common_action_group.get_action(
            "CommonDisplayBasicProperties");
        assert(basic_display_action != null);
        basic_display_action.set_active(Config.get_instance().get_display_basic_properties());

        Gtk.ToggleAction extended_display_action = 
            (Gtk.ToggleAction) get_current_page().common_action_group.get_action(
            "CommonDisplayExtendedProperties");
        assert(extended_display_action != null);
        extended_display_action.set_active(Config.get_instance().get_display_extended_properties());

        Gtk.RadioAction sort_events_action = (Gtk.RadioAction) get_current_page().common_action_group.get_action("CommonSortEventsAscending");
        assert(sort_events_action != null);
        sort_events_action.set_active(Config.get_instance().get_events_sort_ascending());
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

        // divy the sidebar up into selection tree list and properties
        Gtk.Frame top_frame = new Gtk.Frame(null);
        top_frame.add(scrolled_sidebar);
        top_frame.set_shadow_type(Gtk.ShadowType.IN);

        // pad the bottom frame (properties)
        Gtk.Alignment bottom_alignment = new Gtk.Alignment(0, 0.5f, 1, 0);
        bottom_alignment.set_padding(10, 10, 6, 0);
        bottom_alignment.add(basic_properties);

        bottom_frame.add(bottom_alignment);
        bottom_frame.set_shadow_type(Gtk.ShadowType.IN);       

        sidebar_paned.pack1(top_frame, true, false);
        sidebar_paned.pack2(bottom_frame, false, false);
        sidebar_paned.set_position(1000);

        // layout the selection tree to the left of the collection/toolbar box with an adjustable
        // gutter between them, framed for presentation       
        Gtk.Frame right_frame = new Gtk.Frame(null);
        right_frame.add(notebook);
        right_frame.set_shadow_type(Gtk.ShadowType.IN);
        
        client_paned = new Gtk.HPaned();
        client_paned.pack1(sidebar_paned, false, false);
        sidebar.set_size_request(SIDEBAR_MIN_WIDTH, -1);
        client_paned.pack2(right_frame, true, false);
        client_paned.set_position(Config.get_instance().get_sidebar_position());
        // TODO: Calc according to layout's size, to give sidebar a maximum width
        notebook.set_size_request(PAGE_MIN_WIDTH, -1);

        layout.pack_end(client_paned, true, true, 0);
        
        add(layout);

        switch_to_page(start_page);
        start_page.grab_focus();
    }
    
    public override void set_current_page(Page page) {
        // switch_to_page() will call base.set_current_page(), maintain the semantics of this call
        switch_to_page(page);
    }
    
    public void switch_to_page(Page page) {
        if (page == get_current_page())
            return;

        // open sidebar directory containing page, if any
        if (page.get_marker() != null && page is EventPage)
            sidebar.expand_tree(page.get_marker());

        if (get_current_page() != null) {
            get_current_page().switching_from();
            
            Gtk.AccelGroup accel_group = get_current_page().ui.get_accel_group();
            if (accel_group != null)
                remove_accel_group(accel_group);

            // carry over menubar toggle activity between pages
            Gtk.ToggleAction old_basic_display_action = 
                (Gtk.ToggleAction) get_current_page().common_action_group.get_action(
                "CommonDisplayBasicProperties");
            assert(old_basic_display_action != null);

            Gtk.ToggleAction new_basic_display_action = 
                (Gtk.ToggleAction) page.common_action_group.get_action(
                "CommonDisplayBasicProperties");
            assert(new_basic_display_action != null);
            
            new_basic_display_action.set_active(old_basic_display_action.get_active());

            Gtk.ToggleAction old_extended_display_action = 
                (Gtk.ToggleAction) get_current_page().common_action_group.get_action(
                "CommonDisplayExtendedProperties");
            assert(old_basic_display_action != null);

            Gtk.ToggleAction new_extended_display_action = 
                (Gtk.ToggleAction) page.common_action_group.get_action(
                "CommonDisplayExtendedProperties");
            assert(new_basic_display_action != null);
            
            new_extended_display_action.set_active(old_extended_display_action.get_active());

            // old page unsubscribes to these signals (new page subscribes below)
            unsubscribe_from_basic_information(get_current_page());
        }

        notebook.set_current_page(get_notebook_pos(page));

        // switch menus
        if (get_current_page() != null)
            layout.remove(get_current_page().get_menubar());
        layout.pack_start(page.get_menubar(), false, false, 0);
        
        Gtk.AccelGroup accel_group = page.ui.get_accel_group();
        if (accel_group != null)
            add_accel_group(accel_group);
        
        // do this prior to changing selection, as the change will fire a cursor-changed event,
        // which will then call this function again
        base.set_current_page(page);
        
        sidebar.cursor_changed.disconnect(on_sidebar_cursor_changed);
        sidebar.place_cursor(page);
        sidebar.cursor_changed.connect(on_sidebar_cursor_changed);
        
        on_selection_changed();

        page.show_all();
        
        // subscribe to these signals for each event page so basic properties display will update
        subscribe_for_basic_information(get_current_page());

        page.switched_to();
    }
    
    private bool is_page_selected(SidebarPage page, Gtk.TreePath path) {
        SidebarMarker? marker = page.get_marker();
        if (marker == null)
            return false;
        
        return (path.compare(marker.get_row().get_path()) == 0);
    }
    
    private bool is_camera_selected(Gtk.TreePath path) {
#if !NO_CAMERA    
        foreach (ImportPage page in camera_pages.values) {
            if (is_page_selected(page, path)) {
                switch_to_page(page);
                
                return true;
            }
        }
#endif        
        return false;
    }
    
    private bool is_events_directory_selected(Gtk.TreePath path) {
        foreach (SubEventsDirectoryPageStub events_dir in events_dir_list) {
            if (is_page_selected(events_dir, path)) {
                switch_to_page(events_dir.get_page());
                
                return true;
            }
        }
        
        return false;
    }
    
    private bool is_event_selected(Gtk.TreePath path) {
        foreach (EventPageStub event_stub in event_list) {
            if (is_page_selected(event_stub, path)) {
                switch_to_page(event_stub.get_page());
                
                return true;
            }
        }
        
        return false;
    }
    
    private bool is_tag_selected(Gtk.TreePath path) {
        foreach (TagPageStub stub in tag_map.values) {
            if (is_page_selected(stub, path)) {
                switch_to_page(stub.get_page());
                
                return true;
            }
        }
        
        return false;
    }
    
    private void on_sidebar_cursor_changed() {
        Gtk.TreePath path;
        sidebar.get_cursor(out path, null);
        
        if (is_page_selected(library_page, path)) {
            switch_to_library_page();
        } else if (is_page_selected(events_directory_page, path)) {
            switch_to_events_directory_page();
        } else if (import_queue_page != null && is_page_selected(import_queue_page, path)) {
            switch_to_import_queue_page();
        } else if (is_camera_selected(path)) {
            // camera path selected and updated
        } else if (is_events_directory_selected(path)) {
            // events directory page selected and updated
        } else if (is_event_selected(path)) {
            // event page selected and updated
        } else if (is_tag_selected(path)) {
            // tag page selected and updated
        } else if (is_page_selected(trash_page, path)) {
            switch_to_page(trash_page);
        } else {
            // nothing recognized selected
        }
    }
    
    private void subscribe_for_basic_information(Page page) {
        ViewCollection view = page.get_view();
        
        view.items_state_changed.connect(on_selection_changed);
        view.items_altered.connect(on_selection_changed);
        view.items_metadata_altered.connect(on_selection_changed);
        view.contents_altered.connect(on_selection_changed);
        view.items_visibility_changed.connect(on_selection_changed);
    }
    
    private void unsubscribe_from_basic_information(Page page) {
        ViewCollection view = page.get_view();
        
        view.items_state_changed.disconnect(on_selection_changed);
        view.items_altered.disconnect(on_selection_changed);
        view.items_metadata_altered.disconnect(on_selection_changed);
        view.contents_altered.disconnect(on_selection_changed);
        view.items_visibility_changed.disconnect(on_selection_changed);
    }

    private void on_selection_changed() {
        if (bottom_frame.visible)
            basic_properties.update_properties(get_current_page());

        if (extended_properties.visible)
            extended_properties.update_properties(get_current_page());
    }
    
#if !NO_CAMERA
    public void mounted_camera_shell_notification(string uri, bool at_startup) {
        debug("mount point reported: %s", uri);
        
        // ignore unsupport mount URIs
        if (!is_mount_uri_supported(uri)) {
            debug("Unsupported mount scheme: %s", uri);
            
            return;
        }
        
        File uri_file = File.new_for_uri(uri);
        
        // find the VFS mount point
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
            alt_uri = CameraTable.get_port_uri(uri.replace("file://", "disk:"));
        
        // we only add uris when the notification is called on startup
        if (at_startup) {
            if (!is_string_empty(uri))
                initial_camera_uris.add(uri);

            if (!is_string_empty(alt_uri))
                initial_camera_uris.add(alt_uri);
        }
    }
#endif
}

