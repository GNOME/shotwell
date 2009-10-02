/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class LibraryWindow : AppWindow {
    public const int SIDEBAR_MIN_WIDTH = 160;
    public const int SIDEBAR_MAX_WIDTH = 320;
    public const int PAGE_MIN_WIDTH = 
        Thumbnail.MAX_SCALE + CheckerboardLayout.LEFT_PADDING + CheckerboardLayout.RIGHT_PADDING;
    
    public const int SORT_EVENTS_ORDER_ASCENDING = 0;
    public const int SORT_EVENTS_ORDER_DESCENDING = 1;

    private const string[] SUPPORTED_MOUNT_SCHEMES = {
        "gphoto2:",
        "disk:",
        "file:"
    };
    
    private const Gtk.TargetEntry[] DEST_TARGET_ENTRIES = {
        { "text/uri-list", 0, 0 }
    };

    public static Gdk.Color SIDEBAR_BG_COLOR = parse_color("#EEE");

    private string import_dir = Environment.get_home_dir();

    private Gtk.VPaned sidebar_paned = new Gtk.VPaned();
    private Gtk.Frame bottom_frame = new Gtk.Frame(null);

    private class FileImportJob : BatchImportJob {
        private File file_or_dir;
        private bool copy_to_library;
        
        public FileImportJob(string uri, bool copy_to_library) {
            file_or_dir = File.new_for_uri(uri);
            this.copy_to_library = copy_to_library;
        }
        
        public override string get_identifier() {
            return file_or_dir.get_uri();
        }
        
        public override bool prepare(out File file_to_import, out bool copy) {
            file_to_import = file_or_dir;
            copy = copy_to_library;
            
            return true;
        }
    }
    
    // In order to prevent creating a slew of EventPages at app startup, lazily create them as the
    // user needs them ... this may be supplemented in the future to discard unused EventPages (in
    // a lifo), or simply replace them all with a single EventPage which reloads itself with
    // photos for the asked-for event.
    private class EventPageProxy : Object, SidebarPage {
        public Event event;

        private EventPage page = null;
        private SidebarMarker marker = null;
        
        public EventPageProxy(Event event) {
            this.event = event;
        }
        
        public bool has_page() {
            return page != null;
        }
        
        public EventPage get_page() {
            if (page == null) {
                debug("Creating new event page for %s", event.get_name());
                
                // create the event and set its marker, if one has been supplied
                page = new EventPage(event);
                if (marker != null)
                    page.set_marker(marker);
                
                // add this to the notebook and tell the notebook to show it (as per DevHelp)
                LibraryWindow.get_app().add_to_notebook(page);
                LibraryWindow.get_app().notebook.show_all();
            }
            
            return page;
        }
        
        public string get_sidebar_text() {
            return (page != null) ? page.get_sidebar_text() : event.get_name();
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
                return event.get_name();
            return page.get_page_name();
        }

        public Gtk.Menu? get_page_context_menu() {
            if (page == null)
                get_page();
            return page.get_page_context_menu();
        }
    }
    
    private class CompareEventPageProxy : Comparator<EventPageProxy> {
        private int event_sort;
        
        public CompareEventPageProxy(int event_sort) {
            assert(event_sort == SORT_EVENTS_ORDER_ASCENDING || event_sort == SORT_EVENTS_ORDER_DESCENDING);
            
            this.event_sort = event_sort;
        }
        
        public override int64 compare(EventPageProxy a, EventPageProxy b) {
            int64 start_a = (int64) a.event.get_start_time();
            int64 start_b = (int64) b.event.get_start_time();
            
            switch (event_sort) {
                case SORT_EVENTS_ORDER_ASCENDING:
                    return start_a - start_b;
                
                case SORT_EVENTS_ORDER_DESCENDING:
                default:
                    return start_b - start_a;
            }
        }
    }

    // configuration values set app-wide
    private int events_sort = SORT_EVENTS_ORDER_DESCENDING;
    
    // Static (default) pages
    private LibraryPage library_page = null;
    private EventsDirectoryPage events_directory_page = null;
    private LibraryPhotoPage photo_page = null;
    private ImportQueuePage import_queue_page = null;
    private bool displaying_import_queue_page = false;
    
    // Dynamically added/removed pages
    private Gee.ArrayList<EventPageProxy> event_list = new Gee.ArrayList<EventPageProxy>();
    private Gee.HashMap<string, ImportPage> camera_pages = new Gee.HashMap<string, ImportPage>(
        str_hash, str_equal, direct_equal);
    private Gee.ArrayList<Page> pages_to_be_removed = new Gee.ArrayList<Page>();

    private Sidebar sidebar = new Sidebar();
    private SidebarMarker cameras_marker = null;

    private BasicProperties basic_properties = new BasicProperties();
    
    private Gtk.Notebook notebook = new Gtk.Notebook();
    private Gtk.Box layout = new Gtk.VBox(false, 0);
    
    public LibraryWindow() {
        // prepare the default parent and orphan pages
        // (these are never removed from the system)
        library_page = new LibraryPage();
        events_directory_page = new EventsDirectoryPage();
        import_queue_page = new ImportQueuePage();
        import_queue_page.batch_removed += import_queue_batch_finished;
        photo_page = new LibraryPhotoPage();
        photo_page.set_container(this);

        // add the default parents and orphans to the notebook
        add_parent_page(library_page);
        add_parent_page(events_directory_page);
        add_orphan_page(photo_page);

        // watch for new & removed events
        Event.global.items_added += on_added_events;
        Event.global.items_removed += on_removed_events;
        Event.global.item_altered += on_event_altered;

        // add stored events
        foreach (DataObject object in Event.global.get_all())
            add_event_page((Event) object);
        
        // start in the collection page
        sidebar.place_cursor(library_page);
        sidebar.expand_all();
        
        // monitor cursor changes to select proper page in notebook
        sidebar.cursor_changed += on_sidebar_cursor_changed;
        
        create_layout(library_page);

        // settings that should persist between sessions
        load_configuration();

        // set up main window as a drag-and-drop destination (rather than each page; assume
        // a drag and drop is for general library import, which means it goes to library_page)
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, DEST_TARGET_ENTRIES,
            Gdk.DragAction.COPY | Gdk.DragAction.LINK | Gdk.DragAction.ASK);
        
        // monitor the camera table for additions and removals
        CameraTable.get_instance().camera_added += add_camera_page;
        CameraTable.get_instance().camera_removed += remove_camera_page;
        
        // need to populate pages with what's known now by the camera table
        foreach (DiscoveredCamera camera in CameraTable.get_instance().get_cameras())
            add_camera_page(camera);
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
        
        return actions;
    }
    
    private Gtk.ToggleActionEntry[] create_toggle_actions() {
        Gtk.ToggleActionEntry[] actions = new Gtk.ToggleActionEntry[0];

        Gtk.ToggleActionEntry basic_props = { "CommonDisplayBasicProperties", null,
            TRANSLATABLE, "<Ctrl><Shift>I", TRANSLATABLE, on_display_basic_properties, false };
        basic_props.label = _("Basic _Information");
        basic_props.tooltip = _("Display basic information of the selection");
        actions += basic_props;

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
            (Gtk.ToggleAction) current_page.common_action_group.get_action(
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
    
    public static bool is_mount_uri_supported(string uri) {
        foreach (string scheme in SUPPORTED_MOUNT_SCHEMES) {
            if (uri.has_prefix(scheme))
                return true;
        }
        
        return false;
    }
    
    private static string? generate_import_failure_list(Gee.List<string> failed) {
        if (failed.size == 0)
            return null;
        
        string list = "";
        for (int ctr = 0; ctr < 4 && ctr < failed.size; ctr++)
            list += "%s\n".printf(failed.get(ctr));
        
        if (failed.size > 4)
            list += _("%d more photo(s) not imported.\n").printf(failed.size - 4);
        
        return list;
    }
    
    public static void report_import_failures(string name, Gee.List<string> failed, 
        Gee.List<string> skipped) {
        string failed_list = generate_import_failure_list(failed);
        string skipped_list = generate_import_failure_list(skipped);
        
        if (failed_list == null && skipped_list == null)
            return;
            
        string message = _("Import from %s did not complete.\n").printf(name);

        if (failed_list != null) {
            message += _("\n%d photos failed due to error:\n").printf(failed.size);
            message += failed_list;
        }
        
        if (skipped_list != null) {
            message += _("\n%d photos were skipped:\n").printf(skipped.size);
            message += skipped_list;
        }
        
        error_message(message);
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
    
    private override void on_fullscreen() {
        CollectionPage collection = null;
        Thumbnail start = null;
        
        // This method indicates one of the shortcomings right now in our design: we need a generic
        // way to access the collection of items each page is responsible for displaying.  Once
        // that refactoring is done, this code should get much simpler.
        
        if (current_page is CollectionPage) {
            LayoutItem item = ((CollectionPage) current_page).get_fullscreen_photo();
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
        
        LibraryPhotoPage fs_photo = new LibraryPhotoPage();
        FullscreenWindow fs_window = new FullscreenWindow(fs_photo);
        fs_photo.set_container(fs_window);
        fs_photo.display_for_collection(collection, start);

        go_fullscreen(fs_window);
    }
    
    private void on_file_import() {
        Gtk.CheckButton copy_toggle = new Gtk.CheckButton.with_mnemonic(
            _("_Copy files to %s photo library").printf(get_photos_dir().get_basename()));
        copy_toggle.set_active(true);
        
        Gtk.FileChooserDialog import_dialog = new Gtk.FileChooserDialog(_("Import From Folder"), null,
            Gtk.FileChooserAction.SELECT_FOLDER, Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, 
            Gtk.STOCK_OK, Gtk.ResponseType.OK);
        import_dialog.set_select_multiple(true);
        import_dialog.set_current_folder(import_dir);
        import_dialog.set_extra_widget(copy_toggle);
        
        int response = import_dialog.run();

        if (response == Gtk.ResponseType.OK) {
            dispatch_import_jobs(import_dialog.get_uris(), "folders", copy_toggle.get_active());
        }
        import_dir = import_dialog.get_current_folder();
        import_dialog.destroy();
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
        
        CompareEventPageProxy comparator = new CompareEventPageProxy(events_sort);
        
        // re-insert each page in the sidebar in the new order ... does not add page
        // to notebook again or create a new layout
        foreach (EventPageProxy event_proxy in event_list)
            sidebar.insert_child_sorted(events_directory_page.get_marker(), event_proxy, comparator);
        
        // pruning will collapse the branch, expand automatically
        // TODO: Only expand if already expanded?
        sidebar.expand_branch(events_directory_page.get_marker());
        
        // set the tree cursor to the current page, which might have been lost in the
        // delete/insert
        sidebar.place_cursor(current_page);

        // the events directory page needs to know about this
        events_directory_page.notify_sort_changed(events_sort);
    }

    private void on_display_basic_properties(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();

        if (display) {
            bottom_frame.show();
        } else {
            if (sidebar_paned.child2 != null) {
                bottom_frame.hide();
            }
        }

        // sync the setting so it will persist
        Config.get_instance().set_display_basic_properties(display);
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
            remove_page(import_queue_page);
            displaying_import_queue_page = false;
        }
    }

    private void dispatch_import_jobs(GLib.SList<string> uris, string job_name, bool copy_to_library) {
        Gee.ArrayList<FileImportJob> jobs = new Gee.ArrayList<FileImportJob>();
        uint64 total_bytes = 0;

        foreach (string uri in uris) {
            jobs.add(new FileImportJob(uri, copy_to_library));
            
            try {
                total_bytes += query_total_file_size(File.new_for_uri(uri));
            } catch (Error err) {
                debug("Unable to query filesize of %s: %s", uri, err.message);
            }
        }
        
        if (jobs.size > 0) {
            BatchImport batch_import = new BatchImport(jobs, job_name, total_bytes);
            enqueue_batch_import(batch_import);
            switch_to_import_queue_page();
        }
    }

    private override void drag_data_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time) {
        // don't accept drops from our own application
        if (Gtk.drag_get_source_widget(context) != null) {
            Gtk.drag_finish(context, false, false, time);
            
            return;
        }

        string[] uris_array = selection_data.get_uris();

        GLib.SList<string> uris = new GLib.SList<string>();
        foreach (string uri in uris_array) {
            uris.append(uri);
        }
        
        if (context.suggested_action == Gdk.DragAction.ASK) {
            string msg = _("Shotwell can copy or move the photos into your %s directory, or it can link to the photos without duplicating them.");
            msg = msg.printf(get_photos_dir().get_basename());

            Gtk.MessageDialog dialog = new Gtk.MessageDialog(get_instance(), Gtk.DialogFlags.MODAL,
                Gtk.MessageType.QUESTION, Gtk.ButtonsType.CANCEL, "%s", msg);

            dialog.add_button(_("Copy into Library"), Gdk.DragAction.COPY);
            dialog.add_button(_("Create Links"), Gdk.DragAction.LINK);
            dialog.title = _("Import to Library");

            Gdk.DragAction result = (Gdk.DragAction) dialog.run();
            
            dialog.destroy();
            
            switch (result) {
                case Gdk.DragAction.COPY:
                case Gdk.DragAction.LINK:
                    context.action = (Gdk.DragAction) result;
                break;
                
                default:
                    // cancelled
                    Gtk.drag_finish(context, false, false, time);
                    
                    return;
            }
        } else {
            // use the suggested action
            context.action = context.suggested_action;
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
    
    public void switch_to_photo_page(CollectionPage controller, Thumbnail current) {
        photo_page.display_for_collection(controller, current);
        switch_to_page(photo_page);
    }
    
    public void switch_to_import_queue_page() {
        switch_to_page(import_queue_page);
    }
    
    public EventPage? load_event_page(Event event) {
        foreach (EventPageProxy proxy in event_list) {
            if (proxy.event.equals(event)) {
                // this will create the EventPage if not already created
                return proxy.get_page();
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
        
        // refresh sidebar
        foreach (EventPageProxy proxy in event_list) {
            if (proxy.event.equals(event)) {
                SidebarMarker marker = proxy.get_marker();
                sidebar.rename(marker, event.get_name());
                break;
            }
        }

        // refresh basic properties
        basic_properties.update_properties(current_page);
    }
    
    private void add_event_page(Event event) {
        EventPageProxy event_proxy = new EventPageProxy(event);
        
        sidebar.insert_child_sorted(events_directory_page.get_marker(), event_proxy,
            new CompareEventPageProxy(get_events_sort()));
        
        event_list.add(event_proxy);
    }
    
    private void remove_event_page(Event event) {
        // don't use load_event_page, because that will create an EventPage (which we're simply
        // going to remove)
        EventPageProxy event_proxy = null;
        foreach (EventPageProxy proxy in event_list) {
            if (proxy.event.equals(event)) {
                event_proxy = proxy;
                
                break;
            }
        }

        if (event_proxy == null)
            return;

        // remove the page from the notebook, if it's been added
        if (event_proxy.has_page()) {
            int pos = get_notebook_pos(event_proxy.get_page());
            assert(pos >= 0);
            notebook.remove_page(pos);
        }

        // remove from sidebar
        sidebar.remove_page(event_proxy);
    
        // finally, remove from the events list itself
        event_list.remove(event_proxy);
        
        // jump to the Photos page
        switch_to_library_page();
    }

    private void add_camera_page(DiscoveredCamera camera) {
        ImportPage page = new ImportPage(camera.gcamera, camera.uri);   

        // create the Cameras row if this is the first one
        if (cameras_marker == null)
            cameras_marker = sidebar.insert_grouping_after(events_directory_page.get_marker(),
                _("Cameras"));
        
        camera_pages.set(camera.uri, page);
        add_child_page(cameras_marker, page);

        // automagically expand the Cameras branch so the user sees the attached camera(s)
        sidebar.expand_branch(cameras_marker);
    }
    
    private void remove_camera_page(DiscoveredCamera camera) {
        // remove from page table and then from the notebook
        ImportPage page = camera_pages.get(camera.uri);
        camera_pages.remove(camera.uri);
        remove_page(page);

        // if no cameras present, remove row
        if (CameraTable.get_instance().get_count() == 0 && cameras_marker != null) {
            sidebar.prune_branch(cameras_marker);
            cameras_marker = null;
        }
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
    
    // an orphan page is a Page that exists in the notebook (and can therefore be switched to) but
    // is not listed in the sidebar
    private void add_orphan_page(Page orphan) {
        add_to_notebook(orphan);
        
        notebook.show_all();
    }
    
    private void remove_page(Page page) {
        // a handful of pages just don't go away
        assert(page != library_page);
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
            switch_to_library_page();
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
    
    // check for settings that should persist between instances
    private void load_configuration() {
        Gtk.ToggleAction action = 
            (Gtk.ToggleAction) current_page.common_action_group.get_action(
            "CommonDisplayBasicProperties");
        assert(action != null);
        action.set_active(Config.get_instance().get_display_basic_properties());
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
        bottom_frame.add(basic_properties);
        bottom_frame.set_shadow_type(Gtk.ShadowType.IN);

        sidebar_paned.pack1(top_frame, true, false);
        sidebar_paned.pack2(bottom_frame, false, false);
        sidebar_paned.set_position(1000);

        // layout the selection tree to the left of the collection/toolbar box with an adjustable
        // gutter between them, framed for presentation
        Gtk.Frame left_frame = new Gtk.Frame(null);
        left_frame.add(sidebar_paned);
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

            // carry over menubar toggle activity between pages
            Gtk.ToggleAction old_action = 
                (Gtk.ToggleAction) current_page.common_action_group.get_action(
                "CommonDisplayBasicProperties");
            assert(old_action != null);

            Gtk.ToggleAction new_action = 
                (Gtk.ToggleAction) page.common_action_group.get_action(
                "CommonDisplayBasicProperties");
            assert(new_action != null);
            
            new_action.set_active(old_action.get_active());

            // old page unsubscribes to these signals (new page subscribes below)
            current_page.get_view().items_state_changed -= on_selection_changed;
            current_page.get_view().item_altered -= on_selection_changed;
            current_page.get_view().item_metadata_altered -= on_selection_changed;
            current_page.get_view().contents_altered -= on_selection_changed;
        }

        int pos = get_notebook_pos(page);
        if (pos >= 0)
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
        
        on_selection_changed();

        page.show_all();
        
        // subscribe to these signals for each event page so basic properties display will update
        current_page.get_view().items_state_changed += on_selection_changed;
        current_page.get_view().item_altered += on_selection_changed;
        current_page.get_view().item_metadata_altered += on_selection_changed;
        current_page.get_view().contents_altered += on_selection_changed;

        page.switched_to();
    }

    private bool is_page_selected(SidebarPage page, Gtk.TreePath path) {
        SidebarMarker? marker = page.get_marker();
        if (marker == null)
            return false;
        
        return (path.compare(marker.get_row().get_path()) == 0);
    }
    
    private bool is_camera_selected(Gtk.TreePath path) {
        foreach (ImportPage page in camera_pages.get_values()) {
            if (is_page_selected(page, path)) {
                switch_to_page(page);
                
                return true;
            }
        }
        
        return false;
    }
    
    private bool is_event_selected(Gtk.TreePath path) {
        foreach (EventPageProxy event_proxy in event_list) {
            if (is_page_selected(event_proxy, path)) {
                switch_to_page(event_proxy.get_page());
                
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
        
        if (is_page_selected(library_page, path)) {
            switch_to_library_page();
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

        // this has to be done in Idle handler because the focus won't change properly inside 
        // this signal
        Idle.add(focus_on_current_page);
    }

    private void on_selection_changed() {
        basic_properties.update_properties(current_page);
    }
    
    public void mounted_camera_shell_notification(string uri) {
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
        
        // find the ImportPage for this camera ... it should have been detected and added to the
        // CameraTable (and therefore a page created) before the shell notification comes in ...
        // if it's not, that's fine, the user can select it and ask for it to be unmounted
        ImportPage page = camera_pages.get(uri_file.get_uri());
        if (page == null && alt_uri != null)
            page = camera_pages.get(alt_uri);

        if (page == null) {
            debug("Unable to find import page for %s", uri_file.get_uri());
            
            return;
        }
        
        // don't unmount mass storage cameras, as they are then unavailable to gPhoto
        if (!uri.has_prefix("file://")) {
            if (page.unmount_camera(mount))
                switch_to_page(page);
            else
                error_message("Unable to unmount the camera at this time.");
        } else {
            switch_to_page(page);
        }
    }
}

