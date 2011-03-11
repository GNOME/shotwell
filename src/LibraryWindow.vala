/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class LibraryWindow : AppWindow {
    public const int SIDEBAR_MIN_WIDTH = 200;
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
    
    private const int BACKGROUND_PROGRESS_PULSE_MSEC = 250;
    
    // these values reflect the priority various background operations have when reporting
    // progress to the LibraryWindow progress bar ... higher values give priority to those reports
    private const int STARTUP_SCAN_PROGRESS_PRIORITY =      35;
    private const int REALTIME_UPDATE_PROGRESS_PRIORITY =   40;
    private const int REALTIME_IMPORT_PROGRESS_PRIORITY =   50;
    private const int METADATA_WRITER_PROGRESS_PRIORITY =   30;
    private const int MIMIC_MANAGER_PROGRESS_PRIORITY =     20;
    
    // This lists the order of the toplevel items in the sidebar.  New toplevel items should be
    // added here in the position they should appear in the sidebar.  To re-order, simply move
    // the item in this list to a new position.  These numbers should *not* persist anywhere
    // outside the app.
    private enum ToplevelPosition {
        LIBRARY_PAGE,
        FLAGGED_PAGE,
        LAST_IMPORT_PAGE,
        CAMERAS_GROUPING,
        IMPORT_QUEUE_PAGE,
        EVENTS_DIRECTORY_PAGE,
        TAGS_GROUPING,
        TRASH_PAGE,
        OFFLINE_PAGE
    }
    
    protected enum TargetType {
        URI_LIST,
        MEDIA_LIST
    }
    
    public const Gtk.TargetEntry[] DEST_TARGET_ENTRIES = {
        { "text/uri-list", Gtk.TargetFlags.OTHER_APP, TargetType.URI_LIST },
        { "shotwell/media-id-atom", Gtk.TargetFlags.SAME_APP, TargetType.MEDIA_LIST }
    };
    
    // special Yorba-selected sidebar background color for standard themes (humanity,
    // clearlooks, etc.); dark themes use the theme's native background color
    public static Gdk.Color SIDEBAR_STANDARD_BG_COLOR = parse_color("#EEE");
    
    // Max brightness value to trigger SIDEBAR_STANDARD_BG_COLOR 
    public const uint16 STANDARD_COMPONENT_MINIMUM = 0xe000;
    
    // In fullscreen mode, want to use LibraryPhotoPage, but fullscreen has different requirements,
    // esp. regarding when the widget is realized and when it should first try and throw them image
    // on the page.  This handles this without introducing lots of special cases in
    // LibraryPhotoPage.
    private class FullscreenPhotoPage : LibraryPhotoPage {
        private CollectionPage collection;
        private LibraryPhoto start;
        
        public FullscreenPhotoPage(CollectionPage collection, LibraryPhoto start) {
            this.collection = collection;
            this.start = start;
        }
        
        public override void switched_to() {
            display_for_collection(collection, start);
            
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

    private string import_dir = Environment.get_home_dir();

    private Gtk.VPaned sidebar_paned = new Gtk.VPaned();
    private Gtk.HPaned client_paned = new Gtk.HPaned();
    private Gtk.Frame bottom_frame = new Gtk.Frame(null);
    
    private Gtk.ActionGroup common_action_group = new Gtk.ActionGroup("LibraryWindowGlobalActionGroup");
    
    // Static (default) pages
    private LibraryPage library_page = null;
    private MasterEventsDirectoryPage.Stub events_directory_page = null;
    private LibraryPhotoPage photo_page = null;
    private TrashPage.Stub trash_page = null;
    private NoEventPage.Stub no_event_page = null;
    private OfflinePage.Stub offline_page = null;
    private LastImportPage.Stub last_import_page = null;
    private FlaggedPage.Stub flagged_page = null;
    private ImportQueuePage import_queue_page = null;
    private bool displaying_import_queue_page = false;
    private OneShotScheduler properties_scheduler = null;
    private bool notify_library_is_home_dir = true;
    
    // Dynamically added/removed pages
    private Gee.HashMap<Page, PageLayout> page_layouts = new Gee.HashMap<Page, PageLayout>();
    private Gee.ArrayList<EventPage.Stub> event_list = new Gee.ArrayList<EventPage.Stub>();
    private Gee.ArrayList<SubEventsDirectoryPage.Stub> events_dir_list =
        new Gee.ArrayList<SubEventsDirectoryPage.Stub>();
    private Gee.HashMap<Tag, TagPage.Stub> tag_map = new Gee.HashMap<Tag, TagPage.Stub>();
    private Gee.HashMap<string, ImportPage> camera_pages = new Gee.HashMap<string, ImportPage>(
        str_hash, str_equal, direct_equal);

    // this is to keep track of cameras which initiate the app
    private static Gee.HashSet<string> initial_camera_uris = new Gee.HashSet<string>();

    private Sidebar sidebar = new Sidebar();
    private SidebarMarker cameras_marker = null;
    private SidebarMarker tags_marker = null;
    
    private bool is_search_toolbar_visible = Config.get_instance().get_search_bar_hidden();
    
    // Want to instantiate this in the constructor rather than here because the search bar has its
    // own UIManager which will suck up the accelerators, and we want them to be associated with
    // AppWindows instead.
    private SearchFilterActions search_actions = new SearchFilterActions();
    private SearchFilterToolbar search_toolbar;
    
    private Gtk.VBox top_section = new Gtk.VBox(false, 0);
    private Gtk.Frame background_progress_frame = new Gtk.Frame(null);
    private Gtk.ProgressBar background_progress_bar = new Gtk.ProgressBar();
    private bool background_progress_displayed = false;
    
    private BasicProperties basic_properties = new BasicProperties();
    private ExtendedPropertiesWindow extended_properties;
    
    private Gtk.Notebook notebook = new Gtk.Notebook();
    private Gtk.Box layout = new Gtk.VBox(false, 0);
    
    private int current_progress_priority = 0;
    private uint background_progress_pulse_id = 0;
    
    public LibraryWindow(ProgressMonitor progress_monitor) {
        // prepare the default parent and orphan pages
        // (these are never removed from the system)
        library_page = new LibraryPage(progress_monitor);
        last_import_page = LastImportPage.create_stub();
        events_directory_page = MasterEventsDirectoryPage.create_stub();
        import_queue_page = new ImportQueuePage();
        import_queue_page.batch_removed.connect(import_queue_batch_finished);
        trash_page = TrashPage.create_stub();

        // create and connect extended properties window
        extended_properties = new ExtendedPropertiesWindow(this);
        extended_properties.hide.connect(hide_extended_properties);
        extended_properties.show.connect(show_extended_properties);

        // add the default parents and orphans to the notebook
        add_toplevel_page(library_page, ToplevelPosition.LIBRARY_PAGE);
        sidebar.add_toplevel(last_import_page, ToplevelPosition.LAST_IMPORT_PAGE);
        sidebar.add_toplevel(events_directory_page, ToplevelPosition.EVENTS_DIRECTORY_PAGE);
        sidebar.add_toplevel(trash_page, ToplevelPosition.TRASH_PAGE);
        
        properties_scheduler = new OneShotScheduler("LibraryWindow properties",
            on_update_properties_now);
        
        // watch for new & removed events
        Event.global.items_added.connect(on_added_events);
        Event.global.items_removed.connect(on_removed_events);
        Event.global.items_altered.connect(on_events_altered);
        
        // watch for new & removed tags
        Tag.global.contents_altered.connect(on_tags_added_removed);
        Tag.global.items_altered.connect(on_tags_altered);
        
        // watch for photos and videos placed offline
        LibraryPhoto.global.offline_contents_altered.connect(on_offline_contents_altered);
        Video.global.offline_contents_altered.connect(on_offline_contents_altered);
        sync_offline_page_state();

        // watch for photos with no events
        Event.global.no_event_collection_altered.connect(on_no_event_collection_altered);
        enable_disable_no_event_page(Event.global.get_no_event_objects().size > 0);
        
        // start in the collection page
        sidebar.place_cursor(library_page);
        
        // monitor cursor changes to select proper page in notebook
        sidebar.cursor_changed.connect(on_sidebar_cursor_changed);
        
        // set search bar's visibility to default state and add its accelerators to the window
        search_toolbar = new SearchFilterToolbar(search_actions);
        search_toolbar.visible = is_search_toolbar_visible;
        
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
        
        // monitor the camera table for additions and removals
        CameraTable.get_instance().camera_added.connect(add_camera_page);
        CameraTable.get_instance().camera_removed.connect(remove_camera_page);
        
        // need to populate pages with what's known now by the camera table
        foreach (DiscoveredCamera camera in CameraTable.get_instance().get_cameras())
            add_camera_page(camera);
        
        // connect to sidebar signal used ommited on drag-and-drop orerations
        sidebar.drop_received.connect(drop_received);
        
        // monitor various states of the media source collections to update page availability
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all()) {
            sources.trashcan_contents_altered.connect(on_trashcan_contents_altered);
            sources.import_roll_altered.connect(sync_last_import_visibility);
            sources.flagged_contents_altered.connect(sync_flagged_visibility);
            sources.items_altered.connect(on_media_altered);
        }
        
        sync_last_import_visibility();
        sync_flagged_visibility();
        
        MetadataWriter.get_instance().progress.connect(on_metadata_writer_progress);
        LibraryPhoto.mimic_manager.progress.connect(on_mimic_manager_progress);
        
        LibraryMonitor? monitor = LibraryMonitorPool.get_instance().get_monitor();
        if (monitor != null)
            on_library_monitor_installed(monitor);
        
        LibraryMonitorPool.get_instance().monitor_installed.connect(on_library_monitor_installed);
        LibraryMonitorPool.get_instance().monitor_destroyed.connect(on_library_monitor_destroyed);
    }
    
    ~LibraryWindow() {
        Event.global.items_added.disconnect(on_added_events);
        Event.global.items_removed.disconnect(on_removed_events);
        Event.global.items_altered.disconnect(on_events_altered);
        
        Tag.global.contents_altered.disconnect(on_tags_added_removed);
        Tag.global.items_altered.disconnect(on_tags_altered);
        
        CameraTable.get_instance().camera_added.disconnect(add_camera_page);
        CameraTable.get_instance().camera_removed.disconnect(remove_camera_page);
        
        unsubscribe_from_basic_information(get_current_page());

        extended_properties.hide.disconnect(hide_extended_properties);
        extended_properties.show.disconnect(show_extended_properties);
        
        LibraryPhoto.global.trashcan_contents_altered.disconnect(on_trashcan_contents_altered);
        Video.global.trashcan_contents_altered.disconnect(on_trashcan_contents_altered);
        
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.items_altered.disconnect(on_media_altered);
        
        MetadataWriter.get_instance().progress.disconnect(on_metadata_writer_progress);
        LibraryPhoto.mimic_manager.progress.disconnect(on_mimic_manager_progress);
        
        LibraryMonitor? monitor = LibraryMonitorPool.get_instance().get_monitor();
        if (monitor != null)
            on_library_monitor_destroyed(monitor);
        
        LibraryMonitorPool.get_instance().monitor_installed.disconnect(on_library_monitor_installed);
        LibraryMonitorPool.get_instance().monitor_destroyed.disconnect(on_library_monitor_destroyed);
    }
    
    private void on_library_monitor_installed(LibraryMonitor monitor) {
        debug("on_library_monitor_installed: %s", monitor.get_root().get_path());
        
        monitor.discovery_started.connect(on_library_monitor_discovery_started);
        monitor.discovery_completed.connect(on_library_monitor_discovery_completed);
        monitor.closed.connect(on_library_monitor_discovery_completed);
        monitor.auto_update_progress.connect(on_library_monitor_auto_update_progress);
        monitor.auto_import_preparing.connect(on_library_monitor_auto_import_preparing);
        monitor.auto_import_progress.connect(on_library_monitor_auto_import_progress);
    }
    
    private void on_library_monitor_destroyed(LibraryMonitor monitor) {
        debug("on_library_monitor_destroyed: %s", monitor.get_root().get_path());
        
        monitor.discovery_started.disconnect(on_library_monitor_discovery_started);
        monitor.discovery_completed.disconnect(on_library_monitor_discovery_completed);
        monitor.closed.disconnect(on_library_monitor_discovery_completed);
        monitor.auto_update_progress.disconnect(on_library_monitor_auto_update_progress);
        monitor.auto_import_preparing.disconnect(on_library_monitor_auto_import_preparing);
        monitor.auto_import_progress.disconnect(on_library_monitor_auto_import_progress);
    }
    
    private Gtk.ActionEntry[] create_common_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry import = { "CommonFileImport", Resources.IMPORT,
            TRANSLATABLE, "<Ctrl>I", TRANSLATABLE, on_file_import };
        import.label = _("_Import From Folder...");
        import.tooltip = _("Import photos from disk to library");
        actions += import;
        
        // Add one action per alien database driver
        foreach (AlienDb.AlienDatabaseDriver driver in AlienDb.AlienDatabaseHandler.get_instance().get_drivers()) {
            Gtk.ActionEntry import_from_alien_db = driver.get_action_entry();
            actions += import_from_alien_db;
        }

        Gtk.ActionEntry sort = { "CommonSortEvents", null, TRANSLATABLE, null, null, null };
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
        
        Gtk.ActionEntry jump_to_event = { "CommonJumpToEvent", null, TRANSLATABLE, null,
            TRANSLATABLE, on_jump_to_event };
        jump_to_event.label = _("View Eve_nt for Photo");
        jump_to_event.tooltip = _("Go to this photo's event");
        actions += jump_to_event;
        
        Gtk.ActionEntry find = { "CommonFind", Gtk.STOCK_FIND, TRANSLATABLE, null, null,
            on_find };
        find.label = _("_Find");
        find.tooltip = _("Find photos and videos by search criteria");
        actions += find;
        
        // add the common action for the FilterPhotos submenu (the submenu contains items from
        // SearchFilterActions)
        Gtk.ActionEntry filter_photos = { "CommonFilterPhotos", null, TRANSLATABLE, null, null, null };
        filter_photos.label = Resources.FILTER_PHOTOS_MENU;
        actions += filter_photos;
        
        return actions;
    }
    
    private Gtk.ToggleActionEntry[] create_common_toggle_actions() {
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
        
        Gtk.ToggleActionEntry searchbar = { "CommonDisplaySearchbar", Gtk.STOCK_FIND, TRANSLATABLE,
            "F8", TRANSLATABLE, on_display_searchbar, is_search_toolbar_visible };
        searchbar.label = _("_Search Bar");
        searchbar.tooltip = _("Display the search bar");
        actions += searchbar;
        
        return actions;
    }
    
    private void add_common_radio_actions(Gtk.ActionGroup group) {
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
        
        group.add_radio_actions(actions, SORT_EVENTS_ORDER_ASCENDING, on_events_sort_changed);
    }
    
    protected override Gtk.ActionGroup[] create_common_action_groups() {
        Gtk.ActionGroup[] groups = base.create_common_action_groups();
        
        common_action_group.add_actions(create_common_actions(), this);
        common_action_group.add_toggle_actions(create_common_toggle_actions(), this);
        add_common_radio_actions(common_action_group);
        
        Gtk.Action? action = common_action_group.get_action("CommonDisplaySearchbar");
        if (action != null) {
            action.short_label = Resources.FIND_LABEL;
            action.is_important = true;
        }
        
        groups += common_action_group;
        groups += search_actions.get_action_group();
        
        return groups;
    }
    
    public override void replace_common_placeholders(Gtk.UIManager ui) {
        base.replace_common_placeholders(ui);
        
        // Adds one menu entry per alien database driver
        AlienDb.AlienDatabaseHandler.get_instance().add_menu_entries(
            ui, "/MenuBar/FileMenu/CommonImportFromAlienDbPlaceholder"
        );
    }
    
    protected override void switched_pages(Page? old_page, Page? new_page) {
        base.switched_pages(old_page, new_page);
        
        // monitor when the ViewFilter is changed in any page
        if (old_page != null)
            old_page.get_view().view_filter_changed.disconnect(on_view_filter_changed);
        
        if (new_page != null)
            new_page.get_view().view_filter_changed.connect(on_view_filter_changed);
        
        search_actions.monitor_page_contents(old_page, new_page);
    }
    
    private void on_view_filter_changed(ViewCollection view, ViewFilter? old_filter, ViewFilter? new_filter) {
        // when the ViewFilter is changed, monitor when it's refreshed
        if (old_filter != null)
            old_filter.refresh.disconnect(on_view_filter_refreshed);
        
        if (new_filter != null)
            new_filter.refresh.connect(on_view_filter_refreshed);
    }
    
    private void on_view_filter_refreshed() {
        // if view filter is reset to show all items, do nothing (leave searchbar in current
        // state)
        if (!get_current_page().get_view().are_items_filtered_out())
            return;
        
        // always show the searchbar when items are filtered
        Gtk.ToggleAction? display_searchbar = get_common_action("CommonDisplaySearchbar")
            as Gtk.ToggleAction;
        if (display_searchbar != null)
            display_searchbar.active = true;
    }
    
    // show_all() may make visible certain items we wish to keep programmatically hidden
    public override void show_all() {
        base.show_all();
        
        Gtk.ToggleAction? basic_properties_action = get_current_page().get_common_action(
            "CommonDisplayBasicProperties") as Gtk.ToggleAction;
        assert(basic_properties_action != null);
        
        if (!basic_properties_action.get_active())
            bottom_frame.hide();
        
        Gtk.ToggleAction? searchbar_action = get_current_page().get_common_action(
            "CommonDisplaySearchbar") as Gtk.ToggleAction;
        assert(searchbar_action != null);
        
        search_toolbar.visible = should_show_search_bar();
    }
    
    public static LibraryWindow get_app() {
        assert(instance is LibraryWindow);
        
        return (LibraryWindow) instance;
    }
    
    private static int64 get_event_directory_page_time(SubEventsDirectoryPage.Stub *stub) {
        return (stub->get_year() * 100) + stub->get_month();
    }
    
    private int64 event_branch_comparator(void *aptr, void *bptr) {
        SidebarPage *a = (SidebarPage *) aptr;
        SidebarPage *b = (SidebarPage *) bptr;
        
        int64 start_a, start_b;
        if (a is SubEventsDirectoryPage.Stub && b is SubEventsDirectoryPage.Stub) {
            start_a = get_event_directory_page_time((SubEventsDirectoryPage.Stub *) a);
            start_b = get_event_directory_page_time((SubEventsDirectoryPage.Stub *) b);
        } else if (a is NoEventPage.Stub) {
            assert(b is SubEventsDirectoryPage.Stub || b is EventPage.Stub);
            return get_events_sort() == SORT_EVENTS_ORDER_ASCENDING ? 1 : -1;
        } else if (b is NoEventPage.Stub) {
            assert(a is SubEventsDirectoryPage.Stub || a is EventPage.Stub);
            return get_events_sort() == SORT_EVENTS_ORDER_ASCENDING ? -1 : 1;
        } else {
            assert(a is EventPage.Stub);
            assert(b is EventPage.Stub);
            
            start_a = ((EventPage.Stub *) a)->event.get_start_time();
            start_b = ((EventPage.Stub *) b)->event.get_start_time();
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
    
    // This may be called before Debug.init(), so no error logging may be made
    public static bool is_mount_uri_supported(string uri) {
        foreach (string scheme in SUPPORTED_MOUNT_SCHEMES) {
            if (uri.has_prefix(scheme))
                return true;
        }
        
        return false;
    }
    
    public override string get_app_role() {
        return Resources.APP_LIBRARY_ROLE;
    }
    
    protected override void on_quit() {
        Config.get_instance().set_library_window_state(maximized, dimensions);

        Config.get_instance().set_sidebar_position(client_paned.position);

        Config.get_instance().set_photo_thumbnail_scale(MediaPage.get_global_thumbnail_scale());
        
        base.on_quit();
    }
    
    protected override void on_fullscreen() {
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
        
        LibraryPhoto? photo = start.get_media_source() as LibraryPhoto;
        if (photo == null)
            return;
        
        FullscreenPhotoPage fs_photo = new FullscreenPhotoPage(collection, photo);

        go_fullscreen(fs_photo);
    }
    
    private void on_file_import() {
        Gtk.FileChooserDialog import_dialog = new Gtk.FileChooserDialog(_("Import From Folder"), null,
            Gtk.FileChooserAction.SELECT_FOLDER, Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, 
            Gtk.STOCK_OK, Gtk.ResponseType.OK);
        import_dialog.set_local_only(false);
        import_dialog.set_select_multiple(true);
        import_dialog.set_current_folder(import_dir);
        
        int response = import_dialog.run();
        
        if (response == Gtk.ResponseType.OK) {
            // force file linking if directory is inside current library directory
            Gtk.ResponseType copy_files_response =
                AppDirs.is_in_import_dir(File.new_for_uri(import_dialog.get_uri()))
                    ? Gtk.ResponseType.REJECT : copy_files_dialog();
            
            if (copy_files_response != Gtk.ResponseType.CANCEL) {
                dispatch_import_jobs(import_dialog.get_uris(), "folders", 
                    copy_files_response == Gtk.ResponseType.ACCEPT);
            }
        }
        
        import_dir = import_dialog.get_current_folder();
        import_dialog.destroy();
    }
    
    protected override void update_common_action_availability(Page? old_page, Page? new_page) {
        base.update_common_action_availability(old_page, new_page);
        
        bool is_checkerboard = new_page is CheckerboardPage;
        
        set_common_action_sensitive("CommonDisplaySearchbar", is_checkerboard);
        set_common_action_sensitive("CommonFind", is_checkerboard);
    }
    
    protected override void update_common_actions(Page page, int selected_count, int count) {
        // see on_fullscreen for the logic here ... both CollectionPage and EventsDirectoryPage
        // are CheckerboardPages (but in on_fullscreen have to be handled differently to locate
        // the view controller)
        bool can_fullscreen = false;
        if (page is CheckerboardPage) {
            CheckerboardItem? item = ((CheckerboardPage) page).get_fullscreen_photo();
            if (item != null)
                can_fullscreen = item.get_source() is Photo;
        } else if (page is LibraryPhotoPage) {
            can_fullscreen = true;
        }
        
        set_common_action_sensitive("CommonEmptyTrash", can_empty_trash());
        set_common_action_visible("CommonJumpToEvent", true);
        set_common_action_sensitive("CommonJumpToEvent", can_jump_to_event());
        set_common_action_sensitive("CommonFullscreen", can_fullscreen);
        
        base.update_common_actions(page, selected_count, count);
    }
    
    private void on_trashcan_contents_altered() {
        set_common_action_sensitive("CommonEmptyTrash", can_empty_trash());
        sidebar.update_page_icon(trash_page);
    }
    
    private bool can_empty_trash() {
        return (LibraryPhoto.global.get_trashcan_count() > 0) || (Video.global.get_trashcan_count() > 0);
    }
    
    private void on_empty_trash() {
        Gee.ArrayList<MediaSource> to_remove = new Gee.ArrayList<MediaSource>();
        to_remove.add_all(LibraryPhoto.global.get_trashcan_contents());
        to_remove.add_all(Video.global.get_trashcan_contents());
        
        remove_from_app(to_remove, _("Empty Trash"),  _("Emptying Trash..."));
        
        AppWindow.get_command_manager().reset();
    }
    
    private bool can_jump_to_event() {
        ViewCollection view = get_current_page().get_view();
        if (view.get_selected_count() == 1) {
            DataSource selected_source = view.get_selected_source_at(0);
            if (selected_source is Event)
                return true;
            else if (selected_source is MediaSource)
                return ((MediaSource) view.get_selected_source_at(0)).get_event() != null;
            else
                return false;
        } else {
            return false;
        }
    }
    
    private void on_jump_to_event() {
        ViewCollection view = get_current_page().get_view();
        
        if (view.get_selected_count() != 1)
            return;
        
        MediaSource? media = view.get_selected_source_at(0) as MediaSource;
        if (media == null)
            return;
        
        if (media.get_event() != null)
            switch_to_event(media.get_event());
    }
    
    private void on_find() {
        Gtk.ToggleAction action = (Gtk.ToggleAction) get_current_page().get_common_action(
            "CommonDisplaySearchbar");
        action.active = true;
        
        // give it focus (which should move cursor to the text entry control)
        search_toolbar.take_focus();
    }
    
    private void on_media_altered() {
        set_common_action_sensitive("CommonJumpToEvent", can_jump_to_event());
    }
    
    private void on_clear_search() {
        if (is_search_toolbar_visible)
            search_actions.reset();
    }
    
    public int get_events_sort() {
        Gtk.RadioAction? action = get_common_action("CommonSortEventsAscending") as Gtk.RadioAction;
        
        return (action != null) ? action.current_value : SORT_EVENTS_ORDER_DESCENDING;
    }

    private void on_events_sort_changed(Gtk.Action action, Gtk.Action c) {
        Gtk.RadioAction current = (Gtk.RadioAction) c;
        
        Config.get_instance().set_events_sort_ascending(
            current.current_value == SORT_EVENTS_ORDER_ASCENDING);
       
        sidebar.sort_branch(events_directory_page.get_marker(), 
            get_event_branch_comparator(current.current_value));

        // set the tree cursor to the current page, which might have been lost in the
        // delete/insert
        sidebar.place_cursor(get_current_page());
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
    
    private void on_display_searchbar(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        is_search_toolbar_visible = display;
        search_toolbar.visible = display;
        
        // if dismissing the toolbar, reset the filter
        if (!display)
            search_actions.reset();
        
        // Ticket #3222 - remember search bar status between sessions.
        Config.get_instance().set_search_bar_hidden(is_search_toolbar_visible);
    }
    
    private void show_extended_properties() {
        sync_extended_properties(true);
    }

    private void hide_extended_properties() {
        sync_extended_properties(false);
    }

    private void sync_extended_properties(bool show) {
        Gtk.ToggleAction? extended_display_action = get_common_action("CommonDisplayExtendedProperties")
            as Gtk.ToggleAction;
        assert(extended_display_action != null);
        extended_display_action.set_active(show);

        // sync the setting so it will persist
        Config.get_instance().set_display_extended_properties(show);
    }

    public void enqueue_batch_import(BatchImport batch_import, bool allow_user_cancel) {
        if (!displaying_import_queue_page) {
            add_toplevel_page(import_queue_page, ToplevelPosition.IMPORT_QUEUE_PAGE);
            displaying_import_queue_page = true;
        }
        
        import_queue_page.enqueue_and_schedule(batch_import, allow_user_cancel);
    }
    
    private void sync_last_import_visibility() {
        bool has_last_import = false;
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all()) {
            if (sources.get_last_import_id() != null) {
                has_last_import = true;
                
                break;
            }
        }
        
        enable_disable_last_import_page(has_last_import);
    }
    
    private void sync_flagged_visibility() {
        bool has_flagged = false;
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all()) {
            if (sources.get_flagged().size > 0) {
                has_flagged = true;
                
                break;
            }
        }
        
        enable_disable_flagged_page(has_flagged);
    }
    
    private void import_queue_batch_finished() {
        if (displaying_import_queue_page && import_queue_page.get_batch_count() == 0) {
            // only hide the import queue page, as it might be used later
            hide_page(import_queue_page, last_import_page != null ? 
                last_import_page.get_page() : library_page);
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
            enqueue_batch_import(batch_import, true);
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
    
    public override bool drag_motion(Gdk.DragContext context, int x, int y, uint time) {
        Gdk.Atom target = Gtk.drag_dest_find_target(this, context, Gtk.drag_dest_get_target_list(this));
        if (((int) target) == ((int) Gdk.Atom.NONE)) {
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
            drag_action = Gdk.DragAction.ASK;
        
        Gdk.drag_status(context, drag_action, time);

        return true;
    }
    
    public override void drag_data_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time) {
        if (selection_data.length < 0)
            debug("failed to retrieve SelectionData");
        
        drop_received(context, x, y, selection_data, info, time, null, null);
    }

    private void drop_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time, Gtk.TreePath? path, 
        SidebarPage? page) {
        // determine if drag is internal or external
        if (Gtk.drag_get_source_widget(context) != null)
            drop_internal(context, x, y, selection_data, info, time, path, page);
        else
            drop_external(context, x, y, selection_data, info, time);
    }

    private void drop_internal(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time, Gtk.TreePath? path,
        SidebarPage? page = null) {
		Gee.List<MediaSource>? media = unserialize_media_sources(selection_data.data,
            selection_data.get_length());
        
        if (media.size == 0) {
            Gtk.drag_finish(context, false, false, time);
            
            return;
        }
        
        bool success = false;
        if (page is EventPage.Stub) {
            Event event = ((EventPage.Stub) page).event;

            Gee.ArrayList<ThumbnailView> views = new Gee.ArrayList<ThumbnailView>();
            foreach (MediaSource current_media in media) {
                // don't move a photo into the event it already exists in
                if (current_media.get_event() == null || !current_media.get_event().equals(event))
                    views.add(new ThumbnailView(current_media));
            }

            if (views.size > 0) {
                get_command_manager().execute(new SetEventCommand(views, event));
                success = true;
            }
        } else if (page is TagPage.Stub) {
            get_command_manager().execute(new TagUntagPhotosCommand(((TagPage.Stub) page).tag, media, 
                media.size, true));
            success = true;
        } else if (page is TrashPage.Stub) {
            get_command_manager().execute(new TrashUntrashPhotosCommand(media, true));
            success = true;
        } else if ((path != null) && (tags_marker != null) && (tags_marker.get_path() != null) && 
                   (path.compare(tags_marker.get_path()) == 0)) {
            AddTagsDialog dialog = new AddTagsDialog();
            string[]? names = dialog.execute();
            if (names != null) {
                get_command_manager().execute(new AddTagsCommand(names, media));
                success = true;
            }
        }
        
        Gtk.drag_finish(context, success, false, time);
    }

    private void drop_external(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time) {

        string[] uris_array = selection_data.get_uris();
        
        GLib.SList<string> uris = new GLib.SList<string>();
        foreach (string uri in uris_array)
            uris.append(uri);
        
        if (context.action == Gdk.DragAction.ASK) {
            // Default action is to link, unless one or more URIs are external to the library
            Gtk.ResponseType result = Gtk.ResponseType.REJECT;
            foreach (string uri in uris) {
                if (!AppDirs.is_in_import_dir(File.new_for_uri(uri))) {
                    result = copy_files_dialog();
                    
                    break;
                }
            }
            
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
        switch_to_page(events_directory_page.get_page());
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
        TagPage.Stub? stub = tag_map.get(tag);
        assert(stub != null);
        
        switch_to_page(stub.get_page());
    }
    
    public void switch_to_photo_page(CollectionPage controller, Photo current) {
        assert(controller.get_view().get_view_for_source(current) != null);
        if (photo_page == null) {
            photo_page = new LibraryPhotoPage();
            add_orphan_page(photo_page);
            
            // need to do this to allow the event loop a chance to map and realize the page
            // before switching to it
            spin_event_loop();
        }
        
        photo_page.display_for_collection(controller, current);
        switch_to_page(photo_page);
    }
    
    public void switch_to_import_queue_page() {
        switch_to_page(import_queue_page);
    }
    
    public EventPage? load_event_page(Event event) {
        foreach (EventPage.Stub stub in event_list) {
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

    private void on_events_altered(Gee.Map<DataObject, Alteration> map) {
        foreach (DataObject object in map.keys) {
            Event event = (Event) object;
            
            foreach (EventPage.Stub stub in event_list) {
                if (event.equals(stub.event)) {
                    SubEventsDirectoryPage.Stub old_parent = 
                        (SubEventsDirectoryPage.Stub) sidebar.get_parent_page(stub);
                    
                    // only re-add to sidebar if the event has changed directories or shares its dir
                    if (sidebar.get_children_count(old_parent.get_marker()) > 1 || 
                        !(old_parent.get_month() == Time.local(event.get_start_time()).month &&
                         old_parent.get_year() == Time.local(event.get_start_time()).year)) {
                        // this prevents the cursor from jumping back to the library photos page
                        // should it be on this page as we re-sort by removing and reinserting it
                        sidebar.cursor_changed.disconnect(on_sidebar_cursor_changed);
                        
                        // remove from sidebar
                        remove_event_tree(stub, false);

                        // add to sidebar again
                        sidebar.insert_child_sorted(find_parent_marker(stub), stub,
                            get_event_branch_comparator(get_events_sort()));

                        sidebar.expand_tree(stub.get_marker());
                        
                        sidebar.cursor_changed.connect(on_sidebar_cursor_changed);

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
        }
        
        on_update_properties();
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
    
    private void on_tags_altered(Gee.Map<DataObject, Alteration> map) {
        // this prevents the cursor from jumping back to the library photos page
        // should it be on this page as we re-sort by removing and reinserting it
        sidebar.cursor_changed.disconnect(on_sidebar_cursor_changed);
        
        foreach (DataObject object in map.keys) {
            Tag tag = (Tag) object;
            TagPage.Stub page_stub = tag_map.get(tag);
            assert(page_stub != null);
            
            sidebar.rename(page_stub.get_marker(), tag.get_name());
            sidebar.sort_branch(tags_marker, TagPage.Stub.comparator);
        }
        
        sidebar.cursor_changed.connect(on_sidebar_cursor_changed);
    }

    private void sync_offline_page_state() {
        bool enable_page = (LibraryPhoto.global.get_offline_bin_contents().size > 0) ||
            (Video.global.get_offline_bin_contents().size > 0);
        enable_disable_offline_page(enable_page);
    }
    
    private void on_offline_contents_altered() {
        sync_offline_page_state();
    }
    
    private SidebarMarker? find_parent_marker(PageStub page) {
        // EventPageStub
        if (page is EventPage.Stub) {
            time_t event_time = ((EventPage.Stub) page).event.get_start_time();

            SubEventsDirectoryPage.DirectoryType type = (event_time != 0 ?
                SubEventsDirectoryPage.DirectoryType.MONTH :
                SubEventsDirectoryPage.DirectoryType.UNDATED);

            SubEventsDirectoryPage.Stub month = find_event_dir_page(type, Time.local(event_time));

            // if a month directory already exists, return it, otherwise, create a new one
            return (month != null ? month : create_event_dir_page(type,
                Time.local(event_time))).get_marker();
        } else if (page is SubEventsDirectoryPage.Stub) {
            SubEventsDirectoryPage.Stub event_dir_page = (SubEventsDirectoryPage.Stub) page;
            // SubEventsDirectoryPageStub Month
            if (event_dir_page.type == SubEventsDirectoryPage.DirectoryType.MONTH) {
                SubEventsDirectoryPage.Stub year = find_event_dir_page(
                    SubEventsDirectoryPage.DirectoryType.YEAR, event_dir_page.time);

                // if a month directory already exists, return it, otherwise, create a new one
                return (year != null ? year : create_event_dir_page(
                    SubEventsDirectoryPage.DirectoryType.YEAR, event_dir_page.time)).get_marker();
            }
            
            // SubEventsDirectoryPageStub Year && Undated
            return events_directory_page.get_marker();
        } else if (page is TagPage.Stub) {
            return tags_marker;
        }

        return null;
    }
    
    private SubEventsDirectoryPage.Stub? find_event_dir_page(SubEventsDirectoryPage.DirectoryType type, Time time) {
        foreach (SubEventsDirectoryPage.Stub dir in events_dir_list) {
            if (dir.matches(type,  time))
                return dir;
        }

        return null;
    }

    private SubEventsDirectoryPage.Stub create_event_dir_page(SubEventsDirectoryPage.DirectoryType type, Time time) {
        Comparator comparator = get_event_branch_comparator(get_events_sort());
        
        SubEventsDirectoryPage.Stub new_dir = SubEventsDirectoryPage.create_stub(type, time);

        sidebar.insert_child_sorted(find_parent_marker(new_dir), new_dir,
            comparator);

        events_dir_list.add(new_dir);

        return new_dir;
    }
    
    private void add_tag_page(Tag tag) {
        if (tags_marker == null) {
            tags_marker = sidebar.add_toplevel_grouping(_("Tags"), new GLib.ThemedIcon(Resources.ICON_TAGS),
                ToplevelPosition.TAGS_GROUPING);
        }
        
        TagPage.Stub stub = TagPage.create_stub(tag);
        sidebar.insert_child_sorted(tags_marker, stub, TagPage.Stub.comparator);
        tag_map.set(tag, stub);
    }
    
    private void remove_tag_page(Tag tag) {
        TagPage.Stub stub = tag_map.get(tag);
        assert(stub != null);
        
        remove_stub(stub, library_page, null);
        
        if (tag_map.size == 0 && tags_marker != null) {
            sidebar.prune_branch(tags_marker);
            tags_marker = null;
        }
    }
    
    private void on_no_event_collection_altered() {
        enable_disable_no_event_page(Event.global.get_no_event_objects().size > 0);
    }
    
    private void enable_disable_no_event_page(bool enable) {
        if (enable && no_event_page == null) {
            no_event_page = NoEventPage.create_stub();
            sidebar.add_child(events_directory_page.get_marker(), no_event_page);
        } else if (!enable && no_event_page != null) {
            remove_stub(no_event_page, null, events_directory_page);
            no_event_page = null;
        }
    }
    
    private void enable_disable_offline_page(bool enable) {
        if (enable && offline_page == null) {
            offline_page = OfflinePage.create_stub();
            sidebar.add_toplevel(offline_page, ToplevelPosition.OFFLINE_PAGE);
        } else if (!enable && offline_page != null) {
            remove_stub(offline_page, library_page, null);
            offline_page = null;
        }
    }

    private void enable_disable_last_import_page(bool enable) {
        if (enable && last_import_page == null) {
            last_import_page = LastImportPage.create_stub();
            sidebar.add_toplevel(last_import_page, ToplevelPosition.LAST_IMPORT_PAGE);
        } else if (!enable && last_import_page != null) {
            remove_stub(last_import_page, library_page, null);
            last_import_page = null;
        }
    }
    
    private void enable_disable_flagged_page(bool enable) {
        if (enable && flagged_page == null) {
            flagged_page = FlaggedPage.create_stub();
            sidebar.add_toplevel(flagged_page, ToplevelPosition.FLAGGED_PAGE);
        } else if (!enable && flagged_page != null) {
            remove_stub(flagged_page, library_page, null);
            flagged_page = null;
        }
    }
    
    private void add_event_page(Event event) {
        EventPage.Stub event_stub = EventPage.create_stub(event);
        
        sidebar.insert_child_sorted(find_parent_marker(event_stub), event_stub,
            get_event_branch_comparator(get_events_sort()));
        
        event_list.add(event_stub);
    }
    
    private void remove_event_page(Event event) {
        // don't use load_event_page, because that will create an EventPage (which we're simply
        // going to remove)
        EventPage.Stub event_stub = null;
        foreach (EventPage.Stub stub in event_list) {
            if (stub.event.equals(event)) {
                event_stub = stub;
                
                break;
            }
        }
        
        if (event_stub == null)
            return;
        
        // remove from sidebar
        remove_event_tree(event_stub);
    }

    private void remove_event_tree(PageStub stub, bool delete_stub = true) {
        // grab parent page
        SidebarPage parent = sidebar.get_parent_page(stub);
        
        // remove from notebook and sidebar
        if (delete_stub)
            remove_stub(stub, null, events_directory_page);
        else
            sidebar.remove_page(stub);
        
        // remove parent if empty
        if (parent != null && !(parent is MasterEventsDirectoryPage.Stub)) {
            assert(parent is PageStub);
            
            if (!sidebar.has_children(parent.get_marker()))
                remove_event_tree((PageStub) parent);
        }
    }
    
    private void add_camera_page(DiscoveredCamera camera) {
        ImportPage page = new ImportPage(camera.gcamera, camera.uri, camera.display_name, camera.icon);

        // create the Cameras row if this is the first one
        if (cameras_marker == null) {
            cameras_marker = sidebar.add_toplevel_grouping(_("Cameras"), 
                new GLib.ThemedIcon(Resources.ICON_CAMERAS), ToplevelPosition.CAMERAS_GROUPING);
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
            if (mount != null && !camera.uri.has_prefix("file://")) {
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
    
    // This should only be called by LibraryWindow and PageStub.
    public void add_to_notebook(Page page) {
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
    
    private void add_toplevel_page(Page parent, int position) {
        add_to_notebook(parent);

        sidebar.add_toplevel(parent, position);
    }

    private void add_child_page(SidebarMarker parent_marker, Page child) {
        add_to_notebook(child);
        
        sidebar.add_child(parent_marker, child);
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
    
    private void remove_stub(PageStub stub, Page? fallback_page, PageStub? fallback_stub) {
        // remove from appropriate list
        if (stub is SubEventsDirectoryPage.Stub) {
            // remove from events directory list 
            bool removed = events_dir_list.remove((SubEventsDirectoryPage.Stub) stub);
            assert(removed);
        } else if (stub is EventPage.Stub) {
            // remove from the events list
            bool removed = event_list.remove((EventPage.Stub) stub);
            assert(removed);
        } else if (stub is TagPage.Stub) {
            bool removed = tag_map.unset(((TagPage.Stub) stub).tag);
            assert(removed);
        }
        
        // remove stub (which holds a marker) from the sidebar
        sidebar.remove_page(stub);
        
        if (!sidebar.is_any_page_selected()) {
            if (fallback_page != null)
                switch_to_page(fallback_page);
            else if (fallback_stub != null)
                switch_to_page(fallback_stub.get_page());
        }
        
        if (stub.has_page()) {
            // detach from notebook
            remove_from_notebook(stub.get_page());
            
            // destroy page layout if it exists, otherwise just the page
            if (!destroy_page_layout(stub.get_page()))
                stub.get_page().destroy();
        }
    }
    
    // check for settings that should persist between instances
    private void load_configuration() {
        Gtk.ToggleAction? basic_display_action = get_common_action("CommonDisplayBasicProperties")
            as Gtk.ToggleAction;
        assert(basic_display_action != null);
        basic_display_action.set_active(Config.get_instance().get_display_basic_properties());

        Gtk.ToggleAction? extended_display_action = get_common_action("CommonDisplayExtendedProperties")
            as Gtk.ToggleAction;
        assert(extended_display_action != null);
        extended_display_action.set_active(Config.get_instance().get_display_extended_properties());

        Gtk.RadioAction? sort_events_action = get_common_action("CommonSortEventsAscending")
            as Gtk.RadioAction;
        assert(sort_events_action != null);
        sort_events_action.set_active(Config.get_instance().get_events_sort_ascending());
    }
    
    private void start_pulse_background_progress_bar(string label, int priority) {
        if (priority < current_progress_priority)
            return;
        
        stop_pulse_background_progress_bar(priority, false);
        
        current_progress_priority = priority;
        
        background_progress_bar.set_text(label);
        background_progress_bar.pulse();
        show_background_progress_bar();
        
        background_progress_pulse_id = Timeout.add(BACKGROUND_PROGRESS_PULSE_MSEC,
            on_pulse_background_progress_bar);
    }
    
    private bool on_pulse_background_progress_bar() {
        background_progress_bar.pulse();
        
        return true;
    }
    
    private void stop_pulse_background_progress_bar(int priority, bool clear) {
        if (priority < current_progress_priority)
            return;
        
        if (background_progress_pulse_id != 0) {
            Source.remove(background_progress_pulse_id);
            background_progress_pulse_id = 0;
        }
        
        if (clear)
            clear_background_progress_bar(priority);
    }
    
    private void update_background_progress_bar(string label, int priority, double count,
        double total) {
        if (priority < current_progress_priority)
            return;
        
        stop_pulse_background_progress_bar(priority, false);
        
        if (count <= 0.0 || total <= 0.0 || count >= total) {
            clear_background_progress_bar(priority);
            
            return;
        }
        
        current_progress_priority = priority;
        
        double fraction = count / total;
        background_progress_bar.set_fraction(fraction);
        background_progress_bar.set_text(_("%s (%d%%)").printf(label, (int) (fraction * 100.0)));
        show_background_progress_bar();
    }
    
    private void clear_background_progress_bar(int priority) {
        if (priority < current_progress_priority)
            return;
        
        stop_pulse_background_progress_bar(priority, false);
        
        current_progress_priority = 0;
        
        background_progress_bar.set_fraction(0.0);
        background_progress_bar.set_text("");
        hide_background_progress_bar();
    }
    
    private void show_background_progress_bar() {
        if (!background_progress_displayed) {
            top_section.pack_end(background_progress_frame, false, false, 0);
            background_progress_frame.show_all();
            background_progress_displayed = true;
        }
    }
    
    private void hide_background_progress_bar() {
        if (background_progress_displayed) {
            top_section.remove(background_progress_frame);
            background_progress_displayed = false;
        }
    }
    
    private void on_library_monitor_discovery_started() {
        start_pulse_background_progress_bar(_("Updating library..."), STARTUP_SCAN_PROGRESS_PRIORITY);
    }
    
    private void on_library_monitor_discovery_completed() {
        stop_pulse_background_progress_bar(STARTUP_SCAN_PROGRESS_PRIORITY, true);
    }
    
    private void on_library_monitor_auto_update_progress(int completed_files, int total_files) {
        update_background_progress_bar(_("Updating library..."), REALTIME_UPDATE_PROGRESS_PRIORITY,
            completed_files, total_files);
    }
    
    private void on_library_monitor_auto_import_preparing() {
        start_pulse_background_progress_bar(_("Preparing to auto-import photos..."),
            REALTIME_IMPORT_PROGRESS_PRIORITY);
    }
    
    private void on_library_monitor_auto_import_progress(uint64 completed_bytes, uint64 total_bytes) {
        update_background_progress_bar(_("Auto-importing photos..."),
            REALTIME_IMPORT_PROGRESS_PRIORITY, completed_bytes, total_bytes);
    }
    
    private void on_metadata_writer_progress(uint completed, uint total) {
        update_background_progress_bar(_("Writing metadata to files..."),
            METADATA_WRITER_PROGRESS_PRIORITY, completed, total);
    }
    
    private void on_mimic_manager_progress(int completed, int total) {
        update_background_progress_bar(_("Processing RAW files..."),
            MIMIC_MANAGER_PROGRESS_PRIORITY, completed, total);
    }
    
    private void create_layout(Page start_page) {
        // use a Notebook to hold all the pages, which are switched when a sidebar child is selected
        notebook.set_show_tabs(false);
        notebook.set_show_border(false);
        
        Gtk.Settings settings = Gtk.Settings.get_default();
        HashTable<string, Gdk.Color?> color_table = settings.color_hash;
        Gdk.Color? base_color = color_table.lookup("base_color");
        if (base_color != null && (base_color.red > STANDARD_COMPONENT_MINIMUM &&
            base_color.green > STANDARD_COMPONENT_MINIMUM &&
            base_color.blue > STANDARD_COMPONENT_MINIMUM)) {
            // if the current theme is a standard theme (as opposed to a dark theme), then
            // use the specially-selected Yorba muted background color for the sidebar.
            // otherwise, use the theme's native background color.
            sidebar.modify_base(Gtk.StateType.NORMAL, SIDEBAR_STANDARD_BG_COLOR);
        }
        
        // put the sidebar in a scrolling window
        Gtk.ScrolledWindow scrolled_sidebar = new Gtk.ScrolledWindow(null, null);
        scrolled_sidebar.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scrolled_sidebar.add(sidebar);

        // divy the sidebar up into selection tree list, background progress bar, and properties
        Gtk.Frame top_frame = new Gtk.Frame(null);
        top_frame.add(scrolled_sidebar);
        top_frame.set_shadow_type(Gtk.ShadowType.IN);
        
        background_progress_frame.add(background_progress_bar);
        background_progress_frame.set_shadow_type(Gtk.ShadowType.IN);

        // pad the bottom frame (properties)
        Gtk.Alignment bottom_alignment = new Gtk.Alignment(0, 0.5f, 1, 0);
        bottom_alignment.set_padding(10, 10, 6, 0);
        bottom_alignment.add(basic_properties);

        bottom_frame.add(bottom_alignment);
        bottom_frame.set_shadow_type(Gtk.ShadowType.IN);
        
        // "attach" the progress bar to the sidebar tree, so the movable ridge is to resize the
        // top two and the basic information pane
        top_section.pack_start(top_frame, true, true, 0);

        sidebar_paned.pack1(top_section, true, false);
        sidebar_paned.pack2(bottom_frame, false, false);
        sidebar_paned.set_position(1000);

        // layout the selection tree to the left of the collection/toolbar box with an adjustable
        // gutter between them, framed for presentation
        Gtk.Frame right_frame = new Gtk.Frame(null);
        right_frame.set_shadow_type(Gtk.ShadowType.IN);
        
        Gtk.VBox right_vbox = new Gtk.VBox(false, 0);
        right_frame.add(right_vbox);
        right_vbox.pack_start(search_toolbar, false, false, 0);
        right_vbox.pack_start(notebook, true, true, 0);
        
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
        
        Page current_page = get_current_page();
        if (current_page != null) {
            current_page.switching_from();
            
            // see note below about why the sidebar is uneditable while the LibraryPhotoPage is
            // visible
            if (current_page is LibraryPhotoPage)
                sidebar.enable_editing();
            
            Gtk.AccelGroup accel_group = current_page.ui.get_accel_group();
            if (accel_group != null)
                remove_accel_group(accel_group);
            
            // old page unsubscribes to these signals (new page subscribes below)
            unsubscribe_from_basic_information(current_page);
        }
        
        notebook.set_current_page(get_notebook_pos(page));
        
        // switch menus
        if (current_page != null)
            layout.remove(current_page.get_menubar());
        layout.pack_start(page.get_menubar(), false, false, 0);
        
        Gtk.AccelGroup accel_group = page.ui.get_accel_group();
        if (accel_group != null)
            add_accel_group(accel_group);
        
        // if the visible page is the LibraryPhotoPage, we need to prevent single-click inline
        // renaming in the sidebar because a single click while in the LibraryPhotoPage indicates
        // the user wants to return to the controlling page ... that is, in this special case, the
        // sidebar cursor is set not to the 'current' page, but the page the user came from
        if (page is LibraryPhotoPage)
            sidebar.disable_editing();
        
        // do this prior to changing selection, as the change will fire a cursor-changed event,
        // which will then call this function again
        base.set_current_page(page);
        
        // Update search filter to new page.
        if (should_show_search_bar()) {
            // restore visibility and install filters
            search_toolbar.visible = true;
            search_toolbar.set_view_filter(((CheckerboardPage) page).get_search_view_filter());
            page.get_view().install_view_filter(((CheckerboardPage) page).get_search_view_filter());
        } else {
            search_toolbar.visible = false;
        }
        
        sidebar.cursor_changed.disconnect(on_sidebar_cursor_changed);
        sidebar.place_cursor(page);
        sidebar.cursor_changed.connect(on_sidebar_cursor_changed);
        
        on_update_properties();
        
        page.show_all();
        
        // subscribe to these signals for each event page so basic properties display will update
        subscribe_for_basic_information(get_current_page());
        
        page.switched_to();
    }
    
    private bool should_show_search_bar() {
        return (get_current_page() is CheckerboardPage) ? is_search_toolbar_visible : false;
    }
    
    private bool is_page_selected(SidebarPage page, Gtk.TreePath path) {
        SidebarMarker? marker = page.get_marker();
        
        return marker != null ? path.compare(marker.get_row().get_path()) == 0 : false;
    }
    
    private bool select_from_collection(Gtk.TreePath path, Gee.Collection<PageStub> stubs) {
        foreach (PageStub stub in stubs) {
            if (is_page_selected(stub, path)) {
                switch_to_page(stub.get_page());
                
                return true;
            }
        }
        
        return false;
    }
    
    private bool is_camera_selected(Gtk.TreePath path) {
        foreach (ImportPage page in camera_pages.values) {
            if (is_page_selected(page, path)) {
                switch_to_page(page);
                
                return true;
            }
        }
        return false;
    }
    
    private bool is_events_directory_selected(Gtk.TreePath path) {
        return select_from_collection(path, events_dir_list);
    }
    
    private bool is_event_selected(Gtk.TreePath path) {
        return select_from_collection(path, event_list);
    }

    private bool is_no_event_selected(Gtk.TreePath path) {
        if (no_event_page != null && is_page_selected(no_event_page, path)) {
            switch_to_page(no_event_page.get_page());
            
            return true;
        }
        
        return false;
    }
    
    private bool is_tag_selected(Gtk.TreePath path) {
        return select_from_collection(path, tag_map.values);
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
        } else if (is_no_event_selected(path)) {
            // no event page selected and updated
        } else if (is_tag_selected(path)) {
            // tag page selected and updated
        } else if (is_page_selected(trash_page, path)) {
            switch_to_page(trash_page.get_page());
        } else if (offline_page != null && is_page_selected(offline_page, path)) {
            switch_to_page(offline_page.get_page());
        } else if (last_import_page != null && is_page_selected(last_import_page, path)) {
            switch_to_page(last_import_page.get_page());
        } else if (flagged_page != null && is_page_selected(flagged_page, path)) {
            switch_to_page(flagged_page.get_page());
        } else {
            // nothing recognized selected
        }
    }
    
    private void subscribe_for_basic_information(Page page) {
        ViewCollection view = page.get_view();
        
        view.items_state_changed.connect(on_update_properties);
        view.items_altered.connect(on_update_properties);
        view.contents_altered.connect(on_update_properties);
        view.items_visibility_changed.connect(on_update_properties);
    }
    
    private void unsubscribe_from_basic_information(Page page) {
        ViewCollection view = page.get_view();
        
        view.items_state_changed.disconnect(on_update_properties);
        view.items_altered.disconnect(on_update_properties);
        view.contents_altered.disconnect(on_update_properties);
        view.items_visibility_changed.disconnect(on_update_properties);
    }
    
    private void on_update_properties() {
        properties_scheduler.at_idle();
    }
    
    private void on_update_properties_now() {
        if (bottom_frame.visible)
            basic_properties.update_properties(get_current_page());

        if (extended_properties.visible)
            extended_properties.update_properties(get_current_page());
    }
    
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
    
    public override bool key_press_event(Gdk.EventKey event) {
        if (sidebar.has_focus && sidebar.is_keypress_interpreted(event) && sidebar.key_press_event(event))
            return true;
            
        if (base.key_press_event(event))
            return true;
        
        if (Gdk.keyval_name(event.keyval) == "Escape") {
            on_clear_search();
            return true;
        }
        
        return false;
    }

    public void sidebar_rename_in_place(Page page) {
        sidebar.expand_tree(page.get_marker());
        sidebar.place_cursor(page);
        sidebar.rename_in_place();
    }
    
}

