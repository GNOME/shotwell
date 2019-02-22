/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class LibraryWindow : AppWindow {
    public const int SIDEBAR_MIN_WIDTH = 120;
    public const int EXTENDED_INFO_MIN_WIDTH = 360;
    
    public static int PAGE_MIN_WIDTH {
        get {
            return Thumbnail.MAX_SCALE + (CheckerboardLayout.COLUMN_GUTTER_PADDING * 2);
        }
    }
    
    public const string SORT_EVENTS_ORDER_ASCENDING = "ascending";
    public const string SORT_EVENTS_ORDER_DESCENDING = "descending";
    
    private const string[] SUPPORTED_MOUNT_SCHEMES = {
        "gphoto2:",
        "disk:",
        "file:",
        "mtp:"
    };
    
    private const int BACKGROUND_PROGRESS_PULSE_MSEC = 250;

    // If we're not operating on at least this many files, don't display the progress
    // bar at all; otherwise, it'll go by too quickly, giving the appearance of a glitch.
    const int MIN_PROGRESS_BAR_FILES = 20;
    
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
        CAMERAS,
        SAVED_SEARCH,
        EVENTS,
        IMPORT_ROLL,
        FOLDERS,
#if ENABLE_FACES   
        FACES,
#endif
        TAGS
    }
    
    public enum TargetType {
        URI_LIST,
        MEDIA_LIST,
        TAG_PATH
    }
    
    public const string TAG_PATH_MIME_TYPE = "shotwell/tag-path";
    public const string MEDIA_LIST_MIME_TYPE = "shotwell/media-id-atom";
    
    public const Gtk.TargetEntry[] DND_TARGET_ENTRIES = {
        { "text/uri-list", Gtk.TargetFlags.OTHER_APP, TargetType.URI_LIST },
        { MEDIA_LIST_MIME_TYPE, Gtk.TargetFlags.SAME_APP, TargetType.MEDIA_LIST },
        { TAG_PATH_MIME_TYPE, Gtk.TargetFlags.SAME_WIDGET, TargetType.TAG_PATH }
    };

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

        public override void switching_from() {
        }

        protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
            // We intentionally don't call the base class here since we don't want the
            // top-level menu in photo.ui.
            ui_filenames.add("photo_context.ui");
        }
    }

    private string import_dir = Environment.get_home_dir();
    private bool import_recursive = true;

    private Gtk.Paned sidebar_paned = new Gtk.Paned(Gtk.Orientation.VERTICAL);
    private Gtk.Paned client_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
    private Gtk.Frame bottom_frame = new Gtk.Frame(null);
    
    private OneShotScheduler properties_scheduler = null;
    private bool notify_library_is_home_dir = true;
    
    // Sidebar tree and roots (ordered by SidebarRootPosition)
    private Sidebar.Tree sidebar_tree;
    private Library.Branch library_branch = new Library.Branch();
    private Tags.Branch tags_branch = new Tags.Branch();
    private Folders.Branch folders_branch = new Folders.Branch();
#if ENABLE_FACES   
    private Faces.Branch faces_branch = new Faces.Branch();
#endif
    private Events.Branch events_branch = new Events.Branch();
    private Camera.Branch camera_branch = new Camera.Branch();
    private Searches.Branch saved_search_branch = new Searches.Branch();
    private ImportRoll.Branch import_roll_branch = new ImportRoll.Branch();
    private bool page_switching_enabled = true;
    
    private Gee.HashMap<Page, Sidebar.Entry> page_map = new Gee.HashMap<Page, Sidebar.Entry>();
    
    private LibraryPhotoPage photo_page = null;
    
    // this is to keep track of cameras which initiate the app
    private static Gee.HashSet<string> initial_camera_uris = new Gee.HashSet<string>();
    
    private bool is_search_toolbar_visible = false;
    
    // Want to instantiate this in the constructor rather than here because the search bar has its
    // own UIManager which will suck up the accelerators, and we want them to be associated with
    // AppWindows instead.
    private SearchFilterActions search_actions = new SearchFilterActions();
    private SearchFilterToolbar search_toolbar;
    
    private Gtk.Box top_section = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
    private Gtk.Frame background_progress_frame = new Gtk.Frame(null);
    private Gtk.ProgressBar background_progress_bar = new Gtk.ProgressBar();
    private bool background_progress_displayed = false;
    
    private BasicProperties basic_properties = new BasicProperties();
    private ExtendedProperties extended_properties = new ExtendedProperties();
    private Gtk.Revealer extended_properties_revealer = new Gtk.Revealer();
    
    private Gtk.Stack stack = new Gtk.Stack();
    private Gtk.Box layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
    private Gtk.Box right_vbox;
    private Gtk.Revealer toolbar_revealer = new Gtk.Revealer ();
    
    private int current_progress_priority = 0;
    private uint background_progress_pulse_id = 0;
    
#if UNITY_SUPPORT
    //UnityProgressBar: init
    UnityProgressBar uniprobar = UnityProgressBar.get_instance();
#endif
    
    public LibraryWindow(ProgressMonitor progress_monitor) {
        base();

        // prep sidebar and add roots
        sidebar_tree = new Sidebar.Tree(DND_TARGET_ENTRIES, Gdk.DragAction.ASK,
            external_drop_handler);
        
        sidebar_tree.page_created.connect(on_page_created);
        sidebar_tree.destroying_page.connect(on_destroying_page);
        sidebar_tree.entry_selected.connect(on_sidebar_entry_selected);
        sidebar_tree.selected_entry_removed.connect(on_sidebar_selected_entry_removed);
        
        sidebar_tree.graft(library_branch, SidebarRootPosition.LIBRARY);
        sidebar_tree.graft(tags_branch, SidebarRootPosition.TAGS);
        sidebar_tree.graft(folders_branch, SidebarRootPosition.FOLDERS);
#if ENABLE_FACES   
        sidebar_tree.graft(faces_branch, SidebarRootPosition.FACES);
#endif

        sidebar_tree.graft(events_branch, SidebarRootPosition.EVENTS);
        sidebar_tree.graft(camera_branch, SidebarRootPosition.CAMERAS);
        sidebar_tree.graft(saved_search_branch, SidebarRootPosition.SAVED_SEARCH);
        sidebar_tree.graft(import_roll_branch, SidebarRootPosition.IMPORT_ROLL);
        
        properties_scheduler = new OneShotScheduler("LibraryWindow properties",
            on_update_properties_now);
        
        // setup search bar and add its accelerators to the window
        search_toolbar = new SearchFilterToolbar(search_actions);

        // create the main layout & start at the Library page
        create_layout(library_branch.photos_entry.get_page());
        
        // settings that should persist between sessions
        load_configuration();
        
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all()) {
            media_sources.trashcan_contents_altered.connect(on_trashcan_contents_altered);
            media_sources.items_altered.connect(on_media_altered);
        }
        
        // set up main window as a drag-and-drop destination (rather than each page; assume
        // a drag and drop is for general library import, which means it goes to library_page)
        Gtk.TargetEntry[] main_window_dnd_targets = {
            DND_TARGET_ENTRIES[TargetType.URI_LIST],
            DND_TARGET_ENTRIES[TargetType.MEDIA_LIST]
            /* the main window accepts URI lists and media lists but not tag paths -- yet; we
               might wish to support dropping tags onto photos at some future point */
        };
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, main_window_dnd_targets,
            Gdk.DragAction.COPY | Gdk.DragAction.LINK | Gdk.DragAction.ASK);
        
        MetadataWriter.get_instance().progress.connect(on_metadata_writer_progress);
        
        LibraryMonitor? monitor = LibraryMonitorPool.get_instance().get_monitor();
        if (monitor != null)
            on_library_monitor_installed(monitor);
        
        LibraryMonitorPool.get_instance().monitor_installed.connect(on_library_monitor_installed);
        LibraryMonitorPool.get_instance().monitor_destroyed.connect(on_library_monitor_destroyed);
        
        CameraTable.get_instance().camera_added.connect(on_camera_added);
        
        background_progress_bar.set_show_text(true);

        // Need to re-install F8 here as it will overwrite the binding created
        // by the menu
        const string[] accels = { "<Primary>f", "F8", null };
        Application.set_accels_for_action("win.CommonDisplaySearchbar", accels);
    }

    ~LibraryWindow() {
        sidebar_tree.page_created.disconnect(on_page_created);
        sidebar_tree.destroying_page.disconnect(on_destroying_page);
        sidebar_tree.entry_selected.disconnect(on_sidebar_entry_selected);
        sidebar_tree.selected_entry_removed.disconnect(on_sidebar_selected_entry_removed);
        
        unsubscribe_from_basic_information(get_current_page());

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

    private const GLib.ActionEntry[] common_actions = {
        // Normal actions
        { "CommonFileImport", on_file_import },
        { "ExternalLibraryImport", on_external_library_import },
        { "CommonPreferences", on_preferences },
        { "CommonEmptyTrash", on_empty_trash },
        { "CommonJumpToEvent", on_jump_to_event },
        { "CommonFind", on_find },
        { "CommonNewSearch", on_new_search },

        // Toogle actions
        { "CommonDisplayBasicProperties", on_action_toggle, null, "false", on_display_basic_properties },
        { "CommonDisplayExtendedProperties", on_action_toggle, null, "false", on_display_extended_properties },

        { "CommonDisplaySearchbar", null, null, "false", on_display_searchbar },
        { "CommonDisplaySidebar", on_action_toggle, null, "true", on_display_sidebar },
        { "CommonDisplayToolbar", null, null, "true", on_display_toolbar },

        { "CommonSortEvents", on_action_radio, "s", "'ascending'", on_events_sort_changed }
    };

    protected override void add_actions () {
        base.add_actions ();
        this.add_action_entries (common_actions, this);
        this.add_action_entries (search_actions.get_actions (), search_actions);

        lookup_action ("CommonDisplaySearchbar").change_state (Config.Facade.get_instance().get_display_search_bar());
        lookup_action ("CommonDisplaySidebar").change_state (is_sidebar_visible ());
        lookup_action ("CommonDisplayToolbar").change_state (is_toolbar_visible ());
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
        var action = this.lookup_action ("CommonDisplaySearchbar");

        if (action != null)
            action.change_state (true);
    }

    // show_all() may make visible certain items we wish to keep programmatically hidden
    public override void show_all() {
        base.show_all();

        var basic_properties_action = get_current_page ().get_common_action
            ("CommonDisplayBasicProperties");
        assert(basic_properties_action != null);

        if (!basic_properties_action.get_state().get_boolean())
            bottom_frame.hide();

        // Make sure rejected pictures are not being displayed on startup
        CheckerboardPage? current_page = get_current_page() as CheckerboardPage;
        if (current_page != null)
            init_view_filter(current_page);

        toggle_search_bar(should_show_search_bar(), current_page);

        // Sidebar
        set_sidebar_visible(is_sidebar_visible());
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
    
#if ENABLE_FACES
    public void rename_face_in_sidebar(Face face) {
        Faces.SidebarEntry? entry = faces_branch.get_entry_for_face(face);
        if (entry != null)
            sidebar_tree.rename_entry_in_place(entry);
        else
            assert_not_reached();
    }
#endif
    
    protected override void on_quit() {
        Config.Facade.get_instance().set_library_window_state(maximized, dimensions);

        Config.Facade.get_instance().set_sidebar_position(client_paned.position);

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
        collection = null;
        start = null;
        view_collection = null;
        
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
            Gtk.FileChooserAction.SELECT_FOLDER, Resources.CANCEL_LABEL, Gtk.ResponseType.CANCEL, 
            Resources.OK_LABEL, Gtk.ResponseType.OK);
        import_dialog.set_local_only(false);
        import_dialog.set_select_multiple(true);
        import_dialog.set_current_folder(import_dir);

        var recursive = new Gtk.CheckButton.with_label(_("Recurse Into Subfolders"));
        recursive.active = import_recursive;
        import_dialog.set_extra_widget(recursive);
        
        int response = import_dialog.run();
        
        if (response == Gtk.ResponseType.OK) {
            import_dialog.hide();
            // force file linking if directory is inside current library directory
            Gtk.ResponseType copy_files_response =
                AppDirs.is_in_import_dir(File.new_for_uri(import_dialog.get_uri()))
                    ? Gtk.ResponseType.REJECT : copy_files_dialog();
            
            if (copy_files_response != Gtk.ResponseType.CANCEL) {
                dispatch_import_jobs(import_dialog.get_uris(), "folders",
                    copy_files_response == Gtk.ResponseType.ACCEPT, recursive.active);
            }
        }
        
        import_dir = import_dialog.get_current_folder();
        import_recursive = recursive.active;
        import_dialog.destroy();
    }
    
    private void on_external_library_import() {
        Gtk.Dialog import_dialog = DataImportsUI.DataImportsDialog.get_or_create_instance();
        
        import_dialog.run();
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
        
        remove_from_app(to_remove, _("Empty Trash"),  _("Emptying Trash…"));
        
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
        var action = this.lookup_action ("CommonDisplaySearchbar");
        action.change_state (true);

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
        var action = this.lookup_action ("CommonSortEvents") as GLib.SimpleAction;
        
        return (action != null) ? (action.state.get_string () == SORT_EVENTS_ORDER_ASCENDING)
            ? 0 : 1
            : 1;
    }

    private void on_events_sort_changed(GLib.SimpleAction action, Variant? value) {
        
        Config.Facade.get_instance().set_events_sort_ascending(
            value.get_string () == SORT_EVENTS_ORDER_ASCENDING);

        action.set_state (value);
    }
    
    private void on_preferences() {
        PreferencesDialog.show_preferences();
    }
    
    private void on_display_basic_properties(GLib.SimpleAction action, Variant? value) {
        bool display = value.get_boolean ();

        if (display) {
            basic_properties.update_properties(get_current_page());
            bottom_frame.show();
        } else {
            if (sidebar_paned.get_child2() != null) {
                bottom_frame.hide();
            }
        }

        // sync the setting so it will persist
        Config.Facade.get_instance().set_display_basic_properties(display);
        action.set_state (value);
    }

    private void on_action_toggle (GLib.Action action, Variant? value) {
        Variant new_state = ! (bool) action.get_state ();
        action.change_state (new_state);
    }

    private void on_action_radio (GLib.Action action, Variant? value) {
        action.change_state (value);
    }

    private void on_display_extended_properties(GLib.SimpleAction action, Variant? value) {
        bool display = value.get_boolean ();

        if (display) {
            extended_properties.update_properties(get_current_page());
        }
        extended_properties_revealer.set_reveal_child(display);

        action.set_state (value);
        Config.Facade.get_instance().set_display_extended_properties(display);
    }
    
    private void on_display_searchbar(GLib.SimpleAction action, Variant? value) {
        bool is_shown = value.get_boolean ();

        Config.Facade.get_instance().set_display_search_bar(is_shown);
        show_search_bar(is_shown);
        action.set_state (is_shown);
    }
    
    public void show_search_bar(bool display) {
        if (!(get_current_page() is CheckerboardPage))
            return;
            
        is_search_toolbar_visible = display;
        toggle_search_bar(should_show_search_bar(), get_current_page() as CheckerboardPage);
        if (!display)
            search_actions.reset();
    }
    
    private void on_display_sidebar(GLib.SimpleAction action, Variant? variant) {
        set_sidebar_visible(variant.get_boolean ());

        action.set_state (variant);
    }

    private void set_sidebar_visible(bool visible) {
        sidebar_paned.set_visible(visible);
        Config.Facade.get_instance().set_display_sidebar(visible);
    }
    
    private bool is_sidebar_visible() {
        return Config.Facade.get_instance().get_display_sidebar();
    }
    
    private void on_display_toolbar (GLib.SimpleAction action, Variant? variant) {
        set_toolbar_visible (variant.get_boolean ());

        action.set_state (variant);
    }

    private void set_toolbar_visible (bool visible) {
        if (get_current_page() == null) {
            return;
        }

        var toolbar = get_current_page ().get_toolbar ();
        if (toolbar != null) {
            this.toolbar_revealer.set_reveal_child (visible);
        }
        Config.Facade.get_instance().set_display_toolbar (visible);
    }

    private bool is_toolbar_visible () {
        return Config.Facade.get_instance ().get_display_toolbar ();
    }

    public void enqueue_batch_import(BatchImport batch_import, bool allow_user_cancel) {
        library_branch.import_queue_entry.enqueue_and_schedule(batch_import, allow_user_cancel);
    }
    
    private void import_reporter(ImportManifest manifest) {
        ImportUI.report_manifest(manifest, true);
    }
    
    private void dispatch_import_jobs(GLib.SList<string> uris, string job_name, bool copy_to_library, bool recurse) {
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

            jobs.add(new FileImportJob(file_or_dir, copy_to_library, recurse));
        }
        
        if (jobs.size > 0) {
            BatchImport batch_import = new BatchImport(jobs, job_name, import_reporter);
            enqueue_batch_import(batch_import, true);
            switch_to_import_queue_page();
        }
    }
    
    private Gdk.DragAction get_drag_action() {
        Gdk.ModifierType mask;

        var seat = Gdk.Display.get_default().get_default_seat();
        get_window().get_device_position(seat.get_pointer(), null, null, out mask);

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
        if (target == Gdk.Atom.NONE) {
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
        if (selection_data.get_data().length < 0)
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
        
        Gdk.DragAction selected_action = context.get_selected_action();
        if (selected_action == Gdk.DragAction.ASK) {
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
                    selected_action = Gdk.DragAction.COPY;
                break;
                
                case Gtk.ResponseType.REJECT:
                    selected_action = Gdk.DragAction.LINK;
                break;
                
                default:
                    // cancelled
                    Gtk.drag_finish(context, false, false, time);
                    
                    return;
            }
        }
        
        dispatch_import_jobs(uris, "drag-and-drop", selected_action == Gdk.DragAction.COPY, true);
        
        Gtk.drag_finish(context, true, false, time);
    }
    
    public void switch_to_library_page() {
        switch_to_page(library_branch.photos_entry.get_page());
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
            add_to_stack(photo_page);
            
            // need to do this to allow the event loop a chance to map and realize the page
            // before switching to it
            spin_event_loop();
        }
        
        photo_page.display_for_collection(controller, current);
        switch_to_page(photo_page);
    }
    
    public void switch_to_import_queue_page() {
        switch_to_page(library_branch.import_queue_entry.get_page());
    }
    
    private void on_camera_added(DiscoveredCamera camera) {
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

    // This should only be called by LibraryWindow and PageStub.
    public void add_to_stack(Page page) {
        // need to show all before handing over to stack
        page.show_all();
        
        stack.add(page);
        // need to show_all() after pages are added and removed
        stack.show_all();
    }
    
    private void remove_from_stack(Page page) {
        stack.remove(page);
        
        // need to show_all() after pages are added and removed
        stack.show_all();
    }
    
    // check for settings that should persist between instances
    private void load_configuration() {
        var basic_display_action = lookup_action("CommonDisplayBasicProperties");
        assert(basic_display_action != null);
        basic_display_action.change_state (Config.Facade.get_instance().get_display_basic_properties());

        var extended_display_action = lookup_action("CommonDisplayExtendedProperties");
        assert(extended_display_action != null);
        extended_display_action.change_state(Config.Facade.get_instance().get_display_extended_properties());
        
        var search_bar_display_action = lookup_action("CommonDisplaySearchbar");
        assert(search_bar_display_action != null);
        search_bar_display_action.change_state(Config.Facade.get_instance().get_display_search_bar());

        var sort_events_action = lookup_action("CommonSortEvents");
        assert(sort_events_action != null);
        
        // Ticket #3321 - Event sorting order wasn't saving on exit.
        // Instead of calling set_active against one of the toggles, call
        // set_current_value against the entire radio group...
        string event_sort_val = Config.Facade.get_instance().get_events_sort_ascending() ? SORT_EVENTS_ORDER_ASCENDING :
            SORT_EVENTS_ORDER_DESCENDING;
        
        sort_events_action.change_state (event_sort_val);
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
        
#if UNITY_SUPPORT
        //UnityProgressBar: try to draw & set progress
        uniprobar.set_visible(true);
        uniprobar.set_progress(fraction);
#endif
    }
    
    private void clear_background_progress_bar(int priority) {
        if (priority < current_progress_priority)
            return;
        
        stop_pulse_background_progress_bar(priority, false);
        
        current_progress_priority = 0;
        
        background_progress_bar.set_fraction(0.0);
        background_progress_bar.set_text("");
        hide_background_progress_bar();
        
#if UNITY_SUPPORT
        //UnityProgressBar: reset
        uniprobar.reset();
#endif
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
        start_pulse_background_progress_bar(_("Updating library…"), STARTUP_SCAN_PROGRESS_PRIORITY);
    }
    
    private void on_library_monitor_discovery_completed() {
        stop_pulse_background_progress_bar(STARTUP_SCAN_PROGRESS_PRIORITY, true);
    }
    
    private void on_library_monitor_auto_update_progress(int completed_files, int total_files) {
        if (total_files < MIN_PROGRESS_BAR_FILES)
            clear_background_progress_bar(REALTIME_UPDATE_PROGRESS_PRIORITY);
        else {
            update_background_progress_bar(_("Updating library…"), REALTIME_UPDATE_PROGRESS_PRIORITY,
                completed_files, total_files);
        }
    }
    
    private void on_library_monitor_auto_import_preparing() {
        start_pulse_background_progress_bar(_("Preparing to auto-import photos…"),
            REALTIME_IMPORT_PROGRESS_PRIORITY);
    }
    
    private void on_library_monitor_auto_import_progress(uint64 completed_bytes, uint64 total_bytes) {
        update_background_progress_bar(_("Auto-importing photos…"),
            REALTIME_IMPORT_PROGRESS_PRIORITY, completed_bytes, total_bytes);
    }
    
    private void on_metadata_writer_progress(uint completed, uint total) {
        if (total < MIN_PROGRESS_BAR_FILES)
            clear_background_progress_bar(METADATA_WRITER_PROGRESS_PRIORITY);
        else {
            update_background_progress_bar(_("Writing metadata to files…"),
                METADATA_WRITER_PROGRESS_PRIORITY, completed, total);
        }
    }
    
    private void create_layout(Page start_page) {
        
        // put the sidebar in a scrolling window
        Gtk.ScrolledWindow scrolled_sidebar = new Gtk.ScrolledWindow(null, null);
        scrolled_sidebar.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scrolled_sidebar.add(sidebar_tree);
        
        background_progress_frame.set_border_width(2);
        background_progress_frame.add(background_progress_bar);
        background_progress_frame.get_style_context().remove_class("frame");

        // pad the bottom frame (properties)
        basic_properties.halign = Gtk.Align.FILL;
        basic_properties.valign = Gtk.Align.CENTER;
        basic_properties.hexpand = true;
        basic_properties.vexpand = false;
        basic_properties.margin_top = 10;
        basic_properties.margin_bottom = 10;
        basic_properties.margin_start = 6;
        basic_properties.margin_end = 0;

        bottom_frame.add(basic_properties);
        bottom_frame.get_style_context().remove_class("frame");
        
        // "attach" the progress bar to the sidebar tree, so the movable ridge is to resize the
        // top two and the basic information pane
        top_section.pack_start(scrolled_sidebar, true, true, 0);

        sidebar_paned.pack1(top_section, true, false);
        sidebar_paned.pack2(bottom_frame, false, false);
        sidebar_paned.set_position(1000);
        
        right_vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        right_vbox.pack_start(search_toolbar, false, false, 0);
        var stack_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        stack_box.pack_start(stack, true, true, 0);
        right_vbox.pack_start(stack_box, true, true, 0);
        right_vbox.add (toolbar_revealer);
        
        client_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
        client_paned.pack1(sidebar_paned, false, false);
        sidebar_tree.set_size_request(SIDEBAR_MIN_WIDTH, -1);
        client_paned.pack2(right_vbox, true, false);
        client_paned.set_position(Config.Facade.get_instance().get_sidebar_position());
        // TODO: Calc according to layout's size, to give sidebar a maximum width
        stack.set_size_request(PAGE_MIN_WIDTH, -1);
        var scrolled = new Gtk.ScrolledWindow(null, null);
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        scrolled.add(extended_properties);
        extended_properties_revealer.add(scrolled);
        extended_properties_revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_LEFT);
        extended_properties_revealer.halign = Gtk.Align.END;
        extended_properties_revealer.valign = Gtk.Align.FILL;

        extended_properties.vexpand = true;
        extended_properties.set_margin_top (9);
        extended_properties.set_margin_bottom (9);
        extended_properties.set_margin_start (9);
        extended_properties.set_margin_end (9);
        scrolled.set_size_request(EXTENDED_INFO_MIN_WIDTH, -1);

        stack_box.pack_end(extended_properties_revealer, false, false, 0);
        extended_properties_revealer.halign = Gtk.Align.END;
        extended_properties_revealer.hexpand = false;
        if (Config.Facade.get_instance().get_display_extended_properties()) {
            extended_properties_revealer.set_reveal_child(true);
        } else {
            extended_properties_revealer.set_reveal_child(false);
        }

        layout.pack_end(client_paned, true, true, 0);
        
        add(layout);

        switch_to_page(start_page);
        start_page.grab_focus();
    }
    
    public override void set_current_page(Page page) {
        // switch_to_page() will call base.set_current_page(), maintain the semantics of this call
        switch_to_page(page);
    }
    
    public void set_page_switching_enabled(bool should_enable) {
        page_switching_enabled = should_enable;
    }
    
    public void switch_to_page(Page page) {
        if (!page_switching_enabled)
            return;
        
        if (page == get_current_page())
            return;
        
        Page current_page = get_current_page();
        if (current_page != null) {
            set_show_menubar (false);
            Application.set_menubar (null);

            Gtk.Toolbar toolbar = current_page.get_toolbar();
            if (toolbar != null)
                toolbar_revealer.remove(toolbar);

            current_page.switching_from();
            
            // see note below about why the sidebar is uneditable while the LibraryPhotoPage is
            // visible
            if (current_page is LibraryPhotoPage)
                sidebar_tree.enable_editing();
            
            // old page unsubscribes to these signals (new page subscribes below)
            unsubscribe_from_basic_information(current_page);
        }
        
        stack.set_visible_child(page);
        
        // do this prior to changing selection, as the change will fire a cursor-changed event,
        // which will then call this function again
        base.set_current_page(page);
        
        // if the visible page is the LibraryPhotoPage, we need to prevent single-click inline
        // renaming in the sidebar because a single click while in the LibraryPhotoPage indicates
        // the user wants to return to the controlling page ... that is, in this special case, the
        // sidebar cursor is set not to the 'current' page, but the page the user came from
        if (page is LibraryPhotoPage)
            sidebar_tree.disable_editing();
        
        // Update search filter to new page.
        toggle_search_bar(should_show_search_bar(), page as CheckerboardPage);
        
        // Not all pages have sidebar entries
        Sidebar.Entry? entry = page_map.get(page);
        if (entry != null) {
            // if the corresponding sidebar entry is an expandable entry and wants to be
            // expanded when it's selected, then expand it
            Sidebar.ExpandableEntry expandable_entry = entry as Sidebar.ExpandableEntry;
            if (expandable_entry != null && expandable_entry.expand_on_select())
                sidebar_tree.expand_to_entry(entry);

            sidebar_tree.place_cursor(entry, true);
        }
        
        on_update_properties();
        
        if (page is CheckerboardPage)
            init_view_filter((CheckerboardPage)page);
        
        page.show_all();
        
        // subscribe to these signals for each event page so basic properties display will update
        subscribe_for_basic_information(get_current_page());
        
        page.switched_to();

        Application.set_menubar (page.get_menubar ());
        set_show_menubar (true);
        var old = get_settings().gtk_shell_shows_menubar;
        get_settings().gtk_shell_shows_menubar = !old;
        get_settings().gtk_shell_shows_menubar = old;
        
        Gtk.Toolbar toolbar = page.get_toolbar();
        if (toolbar != null) {
            toolbar_revealer.add(toolbar);
            toolbar.show_all();
            toolbar_revealer.set_reveal_child (this.is_toolbar_visible ());
        }

        page.ready();
    }

    private void init_view_filter(CheckerboardPage page) {
        search_toolbar.set_view_filter(page.get_search_view_filter());
        page.get_view().install_view_filter(page.get_search_view_filter());
    }

    private bool should_show_search_bar() {
        return (get_current_page() is CheckerboardPage) ? is_search_toolbar_visible : false;
    }
    
    // Turns the search bar on or off.  Note that if show is true, page must not be null.
    private void toggle_search_bar(bool show, CheckerboardPage? page = null) {
        search_toolbar.set_reveal_child(show);
        if (show) {
            assert(null != page);
            search_toolbar.set_view_filter(page.get_search_view_filter());
            page.get_view().install_view_filter(page.get_search_view_filter());
        } else {
            if (page != null)
                page.get_view().install_view_filter(new DisabledViewFilter());
        }
    }
    
    private void on_page_created(Sidebar.PageRepresentative entry, Page page) {
        assert(!page_map.has_key(page));
        page_map.set(page, entry);
        
        add_to_stack(page);
    }
    
    private void on_destroying_page(Sidebar.PageRepresentative entry, Page page) {
        // if page is the current page, switch to fallback before destroying
        if (page == get_current_page())
            switch_to_page(library_branch.photos_entry.get_page());
        
        remove_from_stack(page);
        
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
        
        Library.LastImportSidebarEntry last_import_entry = library_branch.last_imported_entry;
        
        // Importing... -> Last Import (if available)
        if (selectable is Library.ImportQueueSidebarEntry && last_import_entry.visible) {
            switch_to_page(last_import_entry.get_page());
            
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
        switch_to_page(library_branch.photos_entry.get_page());
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

