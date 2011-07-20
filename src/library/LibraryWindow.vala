/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class LibraryWindow : AppWindow {
    public const int SIDEBAR_MIN_WIDTH = 200;
    public const int SIDEBAR_MAX_WIDTH = 320;
    
    public static int PAGE_MIN_WIDTH {
        get {
            return Thumbnail.MAX_SCALE + (CheckerboardLayout.COLUMN_GUTTER_PADDING * 2);
        }
    }
    
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
    
    // This lists the order of the toplevel items in the sidebar.  New toplevel items should be
    // added here in the position they should appear in the sidebar.  To re-order, simply move
    // the item in this list to a new position.  These numbers should *not* persist anywhere
    // outside the app.
    private enum SidebarRootPosition {
        LIBRARY,
        FLAGGED,
        LAST_IMPORTED,
        CAMERAS,
        IMPORT_QUEUE,
        SAVED_SEARCH,
        EVENTS,
        TAGS,
        TRASH,
        OFFLINE
    }
    
    protected enum TargetType {
        URI_LIST,
        MEDIA_LIST
    }
    
    private const Gtk.TargetEntry[] DEST_TARGET_ENTRIES = {
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
        private Photo start;
        private ViewCollection? view;
        
        public FullscreenPhotoPage(CollectionPage collection, Photo start, ViewCollection? view) {
            this.collection = collection;
            this.start = start;
            this.view = view;
        }
        
        public override void switched_to() {
            display_for_collection(collection, start, view);
            
            base.switched_to();
        }
    }
    
    private class PageLayout : Gtk.VBox {
        private string page_name;
        private Gtk.Toolbar toolbar;
        private Page page;
        
        public PageLayout(Page page) {
            page_name = page.get_page_name();
            toolbar = page.get_toolbar();
            this.page = page;
            
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
            
            // because the appropriate Branch creates the Page, it is up to it to call destroy,
            // so remove that as well
            if (page is Gtk.Widget)
                remove(page);
            page = null;
            
            base.destroy();
        }
    }

    private string import_dir = Environment.get_home_dir();

    private Gtk.VPaned sidebar_paned = new Gtk.VPaned();
    private Gtk.HPaned client_paned = new Gtk.HPaned();
    private Gtk.Frame bottom_frame = new Gtk.Frame(null);
    
    private Gtk.ActionGroup common_action_group = new Gtk.ActionGroup("LibraryWindowGlobalActionGroup");
    
    private OneShotScheduler properties_scheduler = null;
    private bool notify_library_is_home_dir = true;
    
    // Sidebar tree and roots (ordered by SidebarRootPosition)
    private Sidebar.Tree sidebar_tree;
    private Library.Branch library_branch = new Library.Branch();
    private Tags.Branch tags_branch = new Tags.Branch();
    private Library.TrashBranch trash_branch = new Library.TrashBranch();
    private Events.Branch events_branch = new Events.Branch();
    private Library.OfflineBranch offline_branch = new Library.OfflineBranch();
    private Library.FlaggedBranch flagged_branch = new Library.FlaggedBranch();
    private Library.LastImportBranch last_import_branch = new Library.LastImportBranch();
    private Library.ImportQueueBranch import_queue_branch = new Library.ImportQueueBranch();
    private Camera.Branch camera_branch = new Camera.Branch();
    private Searches.Branch saved_search_branch = new Searches.Branch();
    
    private Gee.HashMap<Page, Sidebar.Entry> page_map = new Gee.HashMap<Page, Sidebar.Entry>();
    
    // Dynamically added/removed pages
    private Gee.HashMap<Page, PageLayout> page_layouts = new Gee.HashMap<Page, PageLayout>();
    private LibraryPhotoPage photo_page = null;
    
    // this is to keep track of cameras which initiate the app
    private static Gee.HashSet<string> initial_camera_uris = new Gee.HashSet<string>();
    
    private bool is_search_toolbar_visible = false;
    
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
        // prep sidebar and add roots
        sidebar_tree = new Sidebar.Tree(DEST_TARGET_ENTRIES, Gdk.DragAction.ASK,
            external_drop_handler);
        
        sidebar_tree.page_created.connect(on_page_created);
        sidebar_tree.destroying_page.connect(on_destroying_page);
        sidebar_tree.entry_selected.connect(on_sidebar_entry_selected);
        sidebar_tree.selected_entry_removed.connect(on_sidebar_selected_entry_removed);
        
        sidebar_tree.graft(library_branch, SidebarRootPosition.LIBRARY);
        sidebar_tree.graft(tags_branch, SidebarRootPosition.TAGS);
        sidebar_tree.graft(trash_branch, SidebarRootPosition.TRASH);
        sidebar_tree.graft(events_branch, SidebarRootPosition.EVENTS);
        sidebar_tree.graft(offline_branch, SidebarRootPosition.OFFLINE);
        sidebar_tree.graft(flagged_branch, SidebarRootPosition.FLAGGED);
        sidebar_tree.graft(last_import_branch, SidebarRootPosition.LAST_IMPORTED);
        sidebar_tree.graft(import_queue_branch, SidebarRootPosition.IMPORT_QUEUE);
        sidebar_tree.graft(camera_branch, SidebarRootPosition.CAMERAS);
        sidebar_tree.graft(saved_search_branch, SidebarRootPosition.SAVED_SEARCH);
        
        // create and connect extended properties window
        extended_properties = new ExtendedPropertiesWindow(this);
        extended_properties.hide.connect(hide_extended_properties);
        extended_properties.show.connect(show_extended_properties);
        
        properties_scheduler = new OneShotScheduler("LibraryWindow properties",
            on_update_properties_now);
        
        // setup search bar and add its accelerators to the window
        search_toolbar = new SearchFilterToolbar(search_actions);
        
        // create the main layout & start at the Library page
        create_layout(library_branch.get_main_page());
        
        // settings that should persist between sessions
        load_configuration();
        
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all()) {
            media_sources.trashcan_contents_altered.connect(on_trashcan_contents_altered);
            media_sources.items_altered.connect(on_media_altered);
        }
        
        // set up main window as a drag-and-drop destination (rather than each page; assume
        // a drag and drop is for general library import, which means it goes to library_page)
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, DEST_TARGET_ENTRIES,
            Gdk.DragAction.COPY | Gdk.DragAction.LINK | Gdk.DragAction.ASK);
        
        MetadataWriter.get_instance().progress.connect(on_metadata_writer_progress);
        
        LibraryMonitor? monitor = LibraryMonitorPool.get_instance().get_monitor();
        if (monitor != null)
            on_library_monitor_installed(monitor);
        
        LibraryMonitorPool.get_instance().monitor_installed.connect(on_library_monitor_installed);
        LibraryMonitorPool.get_instance().monitor_destroyed.connect(on_library_monitor_destroyed);
        
        CameraTable.get_instance().camera_added.connect(on_camera_added);
    }
    
    ~LibraryWindow() {
        sidebar_tree.page_created.disconnect(on_page_created);
        sidebar_tree.destroying_page.disconnect(on_destroying_page);
        sidebar_tree.entry_selected.disconnect(on_sidebar_entry_selected);
        sidebar_tree.selected_entry_removed.disconnect(on_sidebar_selected_entry_removed);
        
        unsubscribe_from_basic_information(get_current_page());

        extended_properties.hide.disconnect(hide_extended_properties);
        extended_properties.show.disconnect(show_extended_properties);
        
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all()) {
            media_sources.trashcan_contents_altered.disconnect(on_trashcan_contents_altered);
            media_sources.items_altered.disconnect(on_media_altered);
        }
        
        MetadataWriter.get_instance().progress.disconnect(on_metadata_writer_progress);
        
        LibraryMonitor? monitor = LibraryMonitorPool.get_instance().get_monitor();
        if (monitor != null)
            on_library_monitor_destroyed(monitor);
        
        LibraryMonitorPool.get_instance().monitor_installed.disconnect(on_library_monitor_installed);
        LibraryMonitorPool.get_instance().monitor_destroyed.disconnect(on_library_monitor_destroyed);
        
        CameraTable.get_instance().camera_added.disconnect(on_camera_added);
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

        Gtk.ActionEntry preferences = { "CommonPreferences", Gtk.Stock.PREFERENCES, TRANSLATABLE,
            null, TRANSLATABLE, on_preferences };
        preferences.label = Resources.PREFERENCES_MENU;
        actions += preferences;
        
        Gtk.ActionEntry empty = { "CommonEmptyTrash", Gtk.Stock.CLEAR, TRANSLATABLE, null, null,
            on_empty_trash };
        empty.label = _("Empty T_rash");
        empty.tooltip = _("Delete all photos in the trash");
        actions += empty;
        
        Gtk.ActionEntry jump_to_event = { "CommonJumpToEvent", null, TRANSLATABLE, null,
            TRANSLATABLE, on_jump_to_event };
        jump_to_event.label = _("View Eve_nt for Photo");
        actions += jump_to_event;
        
        Gtk.ActionEntry find = { "CommonFind", Gtk.Stock.FIND, TRANSLATABLE, null, null,
            on_find };
        find.label = _("_Find");
        find.tooltip = _("Find photos and videos by search criteria");
        actions += find;
        
        // add the common action for the FilterPhotos submenu (the submenu contains items from
        // SearchFilterActions)
        Gtk.ActionEntry filter_photos = { "CommonFilterPhotos", null, TRANSLATABLE, null, null, null };
        filter_photos.label = Resources.FILTER_PHOTOS_MENU;
        actions += filter_photos;
        
        Gtk.ActionEntry new_search = { "CommonNewSearch", null, TRANSLATABLE, "<Ctrl>S", null, 
            on_new_search };
        new_search.label =  _("Ne_w Search...");
        actions += new_search;
        
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
        
        Gtk.ToggleActionEntry searchbar = { "CommonDisplaySearchbar", Gtk.Stock.FIND, TRANSLATABLE,
            "F8", TRANSLATABLE, on_display_searchbar, is_search_toolbar_visible };
        searchbar.label = _("_Search Bar");
        searchbar.tooltip = _("Display the search bar");
        actions += searchbar;
        
        return actions;
    }
    
    private void add_common_radio_actions(Gtk.ActionGroup group) {
        Gtk.RadioActionEntry[] actions = new Gtk.RadioActionEntry[0];
        
        Gtk.RadioActionEntry ascending = { "CommonSortEventsAscending",
            Gtk.Stock.SORT_ASCENDING, TRANSLATABLE, null, TRANSLATABLE,
            SORT_EVENTS_ORDER_ASCENDING };
        ascending.label = _("_Ascending");
        ascending.tooltip = _("Sort photos in an ascending order");
        actions += ascending;

        Gtk.RadioActionEntry descending = { "CommonSortEventsDescending",
            Gtk.Stock.SORT_DESCENDING, TRANSLATABLE, null, TRANSLATABLE,
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
        if (old_page != null) {
            old_page.get_view().view_filter_installed.disconnect(on_view_filter_installed);
            old_page.get_view().view_filter_removed.disconnect(on_view_filter_removed);
        }
        
        if (new_page != null) {
            new_page.get_view().view_filter_installed.connect(on_view_filter_installed);
            new_page.get_view().view_filter_removed.connect(on_view_filter_removed);
        }
        
        search_actions.monitor_page_contents(old_page, new_page);
    }
    
    private void on_view_filter_installed(ViewFilter filter) {
        filter.refresh.connect(on_view_filter_refreshed);
    }
    
    private void on_view_filter_removed(ViewFilter filter) {
        filter.refresh.disconnect(on_view_filter_refreshed);
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
        
        toggle_search_bar(should_show_search_bar(), get_current_page() as CheckerboardPage);
    }
    
    public static LibraryWindow get_app() {
        assert(instance is LibraryWindow);
        
        return (LibraryWindow) instance;
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
    
    public void rename_tag_in_sidebar(Tag tag) {
        Tags.SidebarEntry? entry = tags_branch.get_entry_for_tag(tag);
        if (entry != null)
            sidebar_tree.rename_entry_in_place(entry);
        else
            debug("No tag entry found for rename");
    }
    
    public void rename_event_in_sidebar(Event event) {
        Events.EventEntry? entry = events_branch.get_entry_for_event(event);
        if (entry != null)
            sidebar_tree.rename_entry_in_place(entry);
        else
            debug("No event entry found for rename");
    }
    
    public void rename_search_in_sidebar(SavedSearch search) {
        Searches.SidebarEntry? entry = saved_search_branch.get_entry_for_saved_search(search);
        if (entry != null)
            sidebar_tree.rename_entry_in_place(entry);
        else
            debug("No search entry found for rename");
    }
    
    protected override void on_quit() {
        Config.Facade.get_instance().set_library_window_state(maximized, dimensions);

        Config.Facade.get_instance().set_sidebar_position(client_paned.position);

        Config.Facade.get_instance().set_photo_thumbnail_scale(MediaPage.get_global_thumbnail_scale());
        
        base.on_quit();
    }
    
    private Photo? get_start_fullscreen_photo(CollectionPage page) {
        ViewCollection view = page.get_view();
        
        // if a selection is present, use the first selected LibraryPhoto, otherwise do
        // nothing; if no selection present, use the first LibraryPhoto
        Gee.List<DataSource>? sources = (view.get_selected_count() > 0)
            ? view.get_selected_sources_of_type(typeof(LibraryPhoto))
            : view.get_sources_of_type(typeof(LibraryPhoto));
        
        return (sources != null && sources.size != 0)
            ? (Photo) sources[0] : null;
    }
    
    private bool get_fullscreen_photo(Page page, out CollectionPage collection, out Photo start,
         out ViewCollection? view_collection = null) {
        // fullscreen behavior depends on the type of page being looked at
        if (page is CollectionPage) {
            collection = (CollectionPage) page;
            Photo? photo = get_start_fullscreen_photo(collection);
            if (photo == null)
                return false;
            
            start = photo;
            view_collection = null;
            
            return true;
        }
        
        if (page is EventsDirectoryPage) {
            ViewCollection view = page.get_view();
            if (view.get_count() == 0)
                return false;
            
            Event? event = (Event?) ((DataView) view.get_at(0)).get_source();
            if (event == null)
                return false;
            
            Events.EventEntry? entry = events_branch.get_entry_for_event(event);
            if (entry == null)
                return false;
            
            collection = (EventPage) entry.get_page();
            Photo? photo = get_start_fullscreen_photo(collection);
            if (photo == null)
                return false;
            
            start = photo;
            view_collection = null;
            
            return true;
        }
        
        if (page is LibraryPhotoPage) {
            LibraryPhotoPage photo_page = (LibraryPhotoPage) page;
            
            CollectionPage? controller = photo_page.get_controller_page();
            if (controller == null)
                return false;
            
            if (!photo_page.has_photo())
                return false;
            
            collection = controller;
            start = photo_page.get_photo();
            view_collection = photo_page.get_view();
            
            return true;
        }
        
        return false;
    }
    
    protected override void on_fullscreen() {
        Page? current_page = get_current_page();
        if (current_page == null)
            return;
        
        CollectionPage collection;
        Photo start;
        ViewCollection? view = null;
        if (!get_fullscreen_photo(current_page, out collection, out start, out view))
            return;
        
        FullscreenPhotoPage fs_photo = new FullscreenPhotoPage(collection, start, view);

        go_fullscreen(fs_photo);
    }
    
    private void on_file_import() {
        Gtk.FileChooserDialog import_dialog = new Gtk.FileChooserDialog(_("Import From Folder"), null,
            Gtk.FileChooserAction.SELECT_FOLDER, Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, 
            Gtk.Stock.OK, Gtk.ResponseType.OK);
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
        CollectionPage collection;
        Photo start;
        bool can_fullscreen = get_fullscreen_photo(page, out collection, out start);
        
        set_common_action_sensitive("CommonEmptyTrash", can_empty_trash());
        set_common_action_visible("CommonJumpToEvent", true);
        set_common_action_sensitive("CommonJumpToEvent", can_jump_to_event());
        set_common_action_sensitive("CommonFullscreen", can_fullscreen);
        
        base.update_common_actions(page, selected_count, count);
    }
    
    private void on_trashcan_contents_altered() {
        set_common_action_sensitive("CommonEmptyTrash", can_empty_trash());
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
    
    private void on_new_search() {
        (new SavedSearchDialog()).show();
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
        
        Config.Facade.get_instance().set_events_sort_ascending(
            current.current_value == SORT_EVENTS_ORDER_ASCENDING);
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
        Config.Facade.get_instance().set_display_basic_properties(display);
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
        show_search_bar(((Gtk.ToggleAction) action).get_active());
    }
    
    public void show_search_bar(bool display) {
        if (!(get_current_page() is CheckerboardPage))
            return;
            
        is_search_toolbar_visible = display;
        toggle_search_bar(should_show_search_bar(), get_current_page() as CheckerboardPage);
        if (!display)
            search_actions.reset();
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
        Config.Facade.get_instance().set_display_extended_properties(show);
    }

    public void enqueue_batch_import(BatchImport batch_import, bool allow_user_cancel) {
        import_queue_branch.enqueue_and_schedule(batch_import, allow_user_cancel);
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
        
        // If an external drop, piggyback on the sidebar ExternalDropHandler, otherwise it's an
        // internal drop, which isn't handled by the main window
        if (Gtk.drag_get_source_widget(context) == null)
            external_drop_handler(context, null, selection_data, info, time);
        else
            Gtk.drag_finish(context, false, false, time);
    }
    
    private void external_drop_handler(Gdk.DragContext context, Sidebar.Entry? entry,
        Gtk.SelectionData data, uint info, uint time) {
        string[] uris_array = data.get_uris();
        
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
        switch_to_page(library_branch.get_main_page());
    }
    
    public void switch_to_event(Event event) {
        Events.EventEntry? entry = events_branch.get_entry_for_event(event);
        if (entry != null)
            switch_to_page(entry.get_page());
    }
    
    public void switch_to_tag(Tag tag) {
        Tags.SidebarEntry? entry = tags_branch.get_entry_for_tag(tag);
        if (entry != null)
            switch_to_page(entry.get_page());
    }
    
    public void switch_to_saved_search(SavedSearch search) {
        Searches.SidebarEntry? entry = saved_search_branch.get_entry_for_saved_search(search);
        if (entry != null)
            switch_to_page(entry.get_page());
    }
    
    public void switch_to_photo_page(CollectionPage controller, Photo current) {
        assert(controller.get_view().get_view_for_source(current) != null);
        if (photo_page == null) {
            photo_page = new LibraryPhotoPage();
            add_to_notebook(photo_page);
            
            // need to do this to allow the event loop a chance to map and realize the page
            // before switching to it
            spin_event_loop();
        }
        
        photo_page.display_for_collection(controller, current);
        switch_to_page(photo_page);
    }
    
    public void switch_to_import_queue_page() {
        switch_to_page(import_queue_branch.get_queue_page());
    }
    
    private void on_camera_added(DiscoveredCamera camera) {
        // if this page is for a camera which initialized the app, we want to switch to that page
        if (!initial_camera_uris.contains(camera.uri))
            return;
        
        Camera.SidebarEntry? entry = camera_branch.get_entry_for_camera(camera);
        if (entry == null)
            return;
        
        ImportPage page = (ImportPage) entry.get_page();
        File uri_file = File.new_for_uri(camera.uri);
        
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
        destroy_page_layout(page);
        
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
    
    // check for settings that should persist between instances
    private void load_configuration() {
        Gtk.ToggleAction? basic_display_action = get_common_action("CommonDisplayBasicProperties")
            as Gtk.ToggleAction;
        assert(basic_display_action != null);
        basic_display_action.set_active(Config.Facade.get_instance().get_display_basic_properties());

        Gtk.ToggleAction? extended_display_action = get_common_action("CommonDisplayExtendedProperties")
            as Gtk.ToggleAction;
        assert(extended_display_action != null);
        extended_display_action.set_active(Config.Facade.get_instance().get_display_extended_properties());

        Gtk.RadioAction? sort_events_action = get_common_action("CommonSortEventsAscending")
            as Gtk.RadioAction;
        assert(sort_events_action != null);
        
        // Ticket #3321 - Event sorting order wasn't saving on exit.
        // Instead of calling set_active against one of the toggles, call
        // set_current_value against the entire radio group...
        int event_sort_val = Config.Facade.get_instance().get_events_sort_ascending() ? SORT_EVENTS_ORDER_ASCENDING :
            SORT_EVENTS_ORDER_DESCENDING;
        
        sort_events_action.set_current_value(event_sort_val);
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
            sidebar_tree.modify_base(Gtk.StateType.NORMAL, SIDEBAR_STANDARD_BG_COLOR);
        }
        
        // put the sidebar in a scrolling window
        Gtk.ScrolledWindow scrolled_sidebar = new Gtk.ScrolledWindow(null, null);
        scrolled_sidebar.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scrolled_sidebar.add(sidebar_tree);
        
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
        sidebar_tree.set_size_request(SIDEBAR_MIN_WIDTH, -1);
        client_paned.pack2(right_frame, true, false);
        client_paned.set_position(Config.Facade.get_instance().get_sidebar_position());
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
        
        Page current_page = get_current_page();
        if (current_page != null) {
            current_page.switching_from();
            
            // see note below about why the sidebar is uneditable while the LibraryPhotoPage is
            // visible
            if (current_page is LibraryPhotoPage)
                sidebar_tree.enable_editing();
            
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
            sidebar_tree.disable_editing();
        
        // do this prior to changing selection, as the change will fire a cursor-changed event,
        // which will then call this function again
        base.set_current_page(page);
        
        // Update search filter to new page.
        toggle_search_bar(should_show_search_bar(), page as CheckerboardPage);
        
        // Not all pages have sidebar entries
        Sidebar.Entry? entry = page_map.get(page);
        if (entry != null) {
            sidebar_tree.expand_to_entry(entry);
            sidebar_tree.place_cursor(entry, true);
        }
        
        on_update_properties();
        
        page.show_all();
        
        // subscribe to these signals for each event page so basic properties display will update
        subscribe_for_basic_information(get_current_page());
        
        page.switched_to();
    }
    
    private bool should_show_search_bar() {
        return (get_current_page() is CheckerboardPage) ? is_search_toolbar_visible : false;
    }
    
    // Turns the search bar on or off.  Note that if show is true, page must not be null.
    private void toggle_search_bar(bool show, CheckerboardPage? page = null) {
        search_toolbar.visible = show;
        if (show) {
            assert(null != page);
            search_toolbar.set_view_filter(page.get_search_view_filter());
            page.get_view().install_view_filter(page.get_search_view_filter());
        }
    }
    
    private void on_page_created(Sidebar.PageRepresentative entry, Page page) {
        assert(!page_map.has_key(page));
        page_map.set(page, entry);
        
        add_to_notebook(page);
    }
    
    private void on_destroying_page(Sidebar.PageRepresentative entry, Page page) {
        // if page is the current page, switch to fallback before destroying
        if (page == get_current_page())
            switch_to_page(library_branch.get_main_page());
        
        remove_from_notebook(page);
        
        bool removed = page_map.unset(page);
        assert(removed);
    }
    
    private void on_sidebar_entry_selected(Sidebar.SelectableEntry selectable) {
        Sidebar.PageRepresentative? page_rep = selectable as Sidebar.PageRepresentative;
        if (page_rep != null)
            switch_to_page(page_rep.get_page());
    }
    
    private void on_sidebar_selected_entry_removed(Sidebar.SelectableEntry selectable) {
        // if the currently selected item is removed, want to jump to fallback page (which
        // depends on the item that was selected)
        
        // Importing... -> Last Import (if available)
        if (selectable is Library.ImportQueueSidebarEntry && last_import_branch.get_show_branch()) {
            switch_to_page(last_import_branch.get_main_entry().get_page());
            
            return;
        }
        
        // Event page -> Events (master event directory)
        if (selectable is Events.EventEntry && events_branch.get_show_branch()) {
            switch_to_page(events_branch.get_master_entry().get_page());
            
            return;
        }
        
        // Any event directory -> Events (master event directory)
        if (selectable is Events.DirectoryEntry && events_branch.get_show_branch()) {
            switch_to_page(events_branch.get_master_entry().get_page());
            
            return;
        }
        
        // basic all-around default: jump to the Library page
        switch_to_page(library_branch.get_main_page());
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
        if (sidebar_tree.has_focus && sidebar_tree.is_keypress_interpreted(event)
            && sidebar_tree.key_press_event(event)) {
            return true;
        }
        
        if (base.key_press_event(event))
            return true;
        
        if (Gdk.keyval_name(event.keyval) == "Escape") {
            on_clear_search();
            return true;
        }
        
        return false;
    }
}

