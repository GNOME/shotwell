/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class LibraryWindow : AppWindow {
    public const int SIDEBAR_MIN_WIDTH = 160;
    public const int SIDEBAR_MAX_WIDTH = 320;
    public const int PAGE_MIN_WIDTH = 
        Thumbnail.MAX_SCALE + CollectionLayout.LEFT_PADDING + CollectionLayout.RIGHT_PADDING;
    
    public const long EVENT_LULL_SEC = 3 * 60 * 60;
    public const long EVENT_MAX_DURATION_SEC = 12 * 60 * 60;
    
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
    
    // Common actions available to all pages
    private const Gtk.ActionEntry[] COMMON_LIBRARY_ACTIONS = {
        { "CommonFileImport", Resources.IMPORT, "_Import From Folder...", "<Ctrl>I", "Import photos from disk to library",
            on_file_import },
        { "CommonSortEvents", null, "Sort _Events", null, null, on_sort_events }
    };
    
    private const Gtk.RadioActionEntry[] COMMON_SORT_EVENTS_ORDER_ACTIONS = {
        { "CommonSortEventsAscending", Gtk.STOCK_SORT_ASCENDING, "_Ascending", null, 
            "Sort photos in an ascending order", SORT_EVENTS_ORDER_ASCENDING },
        { "CommonSortEventsDescending", Gtk.STOCK_SORT_DESCENDING, "D_escending", null, 
            "Sort photos in a descending order", SORT_EVENTS_ORDER_DESCENDING }
    };

    public static Gdk.Color SIDEBAR_BG_COLOR = parse_color("#EEE");

    private string import_dir = Environment.get_home_dir();

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

    // configuration values set app-wide
    private int events_sort = SORT_EVENTS_ORDER_DESCENDING;
    
    // Static (default) pages
    private CollectionPage collection_page = null;
    private EventsDirectoryPage events_directory_page = null;
    private PhotoPage photo_page = null;
    private ImportQueuePage import_queue_page = null;
    
    // Dynamically added/removed pages
    private Gee.ArrayList<EventPage> event_list = new Gee.ArrayList<EventPage>();
    private Gee.HashMap<string, ImportPage> camera_pages = new Gee.HashMap<string, ImportPage>(
        str_hash, str_equal, direct_equal);
    private Gee.ArrayList<Page> pages_to_be_removed = new Gee.ArrayList<Page>();

    private PhotoTable photo_table = new PhotoTable();
    private EventTable event_table = new EventTable();
    
    private Sidebar sidebar = new Sidebar();
    private SidebarMarker cameras_marker = null;
    
    private Gtk.Notebook notebook = new Gtk.Notebook();
    private Gtk.Box layout = new Gtk.VBox(false, 0);
    
    public LibraryWindow() {
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
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, DEST_TARGET_ENTRIES,
            Gdk.DragAction.COPY | Gdk.DragAction.LINK | Gdk.DragAction.ASK);
        
        // monitor the camera table for additions and removals
        CameraTable.get_instance().camera_added += add_camera_page;
        CameraTable.get_instance().camera_removed += remove_camera_page;
        
        // need to populate pages with what's known now by the camera table
        foreach (DiscoveredCamera camera in CameraTable.get_instance().get_cameras())
            add_camera_page(camera);
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
    
    public override void add_common_actions(Gtk.ActionGroup action_group) {
        base.add_common_actions(action_group);
        
        action_group.add_actions(COMMON_LIBRARY_ACTIONS, this);
        action_group.add_radio_actions(COMMON_SORT_EVENTS_ORDER_ACTIONS, SORT_EVENTS_ORDER_ASCENDING,
            on_events_sort_changed);
    }
    
    private override void on_fullscreen() {
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
    
    private void on_file_import() {
        Gtk.CheckButton copy_toggle = new Gtk.CheckButton.with_mnemonic(
            "_Copy files to %s photo library".printf(get_photos_dir().get_basename()));
        copy_toggle.set_active(true);
        
        Gtk.FileChooserDialog import_dialog = new Gtk.FileChooserDialog("Import From Folder", null,
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
    
    public void enqueue_batch_import(BatchImport batch_import) {
        if (import_queue_page == null) {
            import_queue_page = new ImportQueuePage();
            import_queue_page.batch_removed += remove_import_queue_row;
            
            insert_page_after(events_directory_page.get_marker(), import_queue_page);
        }
        
        import_queue_page.enqueue_and_schedule(batch_import);
    }

    void dispatch_import_jobs(GLib.SList<string> uris, string job_name, bool copy_to_library) {
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

        string[] uris_array = selection_data.get_uris();

        GLib.SList<string> uris = new GLib.SList<string>();
        foreach (string uri in uris_array) {
            uris.append(uri);
        }
        
        if (context.suggested_action == Gdk.DragAction.ASK) {
            string msg = "Shotwell can copy or move the photos into your %s directory, or it can "
                + "link to the photos without duplicating them.";
            msg = msg.printf(get_photos_dir().get_basename());

            Gtk.MessageDialog dialog = new Gtk.MessageDialog(get_instance(), Gtk.DialogFlags.MODAL,
                Gtk.MessageType.QUESTION, Gtk.ButtonsType.CANCEL, msg);

            dialog.add_button("Copy into Library", Gdk.DragAction.COPY);
            dialog.add_button("Create Links", Gdk.DragAction.LINK);
            dialog.title = "Import to Library";

            Gtk.ResponseType result = (Gtk.ResponseType) dialog.run();
            
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

    private void add_camera_page(DiscoveredCamera camera) {
        ImportPage page = new ImportPage(camera.gcamera, camera.uri);
        
        // create the Cameras row if this is the first one
        if (cameras_marker == null)
            cameras_marker = sidebar.insert_grouping_after(events_directory_page.get_marker(),
                "Cameras");
        
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
        foreach (ImportPage page in camera_pages.get_values()) {
            if (is_page_selected(page, path)) {
                switch_to_page(page);
                
                return true;
            }
        }
        
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

        // this has to be done in Idle handler because the focus won't change properly inside 
        // this signal
        Idle.add(focus_on_current_page);
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

