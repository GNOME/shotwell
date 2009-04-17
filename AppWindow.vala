
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

    private static AppWindow mainWindow = null;
    private static string[] args = null;

    // drag and drop target entries
    private const Gtk.TargetEntry[] TARGET_ENTRIES = {
        { "text/uri-list", 0, 0 }
    };
    
    // Common actions available to all pages
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] COMMON_ACTIONS = {
        { "CommonQuit", Gtk.STOCK_QUIT, "_Quit", "<Ctrl>Q", "Quit Shotwell", Gtk.main_quit },
        { "CommonAbout", Gtk.STOCK_ABOUT, "_About", null, "About Shotwell", on_about }
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
    
    public static AppWindow get_main_window() {
        return mainWindow;
    }
    
    public static string[] get_commandline_args() {
        return args;
    }
    
    public static GLib.File get_exec_file() {
        return File.new_for_commandline_arg(args[0]);
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
    
    // this needs to be ref'd the lifetime of the application
    private Hal.Context halContext = new Hal.Context();
    private DBus.Connection halConn = null;
    
    private CollectionPage collectionPage = null;
    private PhotoPage photoPage = null;
    
    private PhotoTable photoTable = new PhotoTable();
    
    construct {
        // if this is the first AppWindow, it's the main AppWindow
        if (mainWindow == null) {
            mainWindow = this;
        }
        
        title = TITLE;
        set_default_size(1024, 768);

        destroy += Gtk.main_quit;
        
        collectionPage = new CollectionPage();
        photoPage = new PhotoPage();
        
        build_sidebar();
        
        create_start_page();

        // set up main window as a drag-and-drop destination (rather than each page; assume
        // a drag and drop is for general library importation, which means it goes to collectionPage)
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, TARGET_ENTRIES, Gdk.DragAction.COPY);
        
        halConn = DBus.Bus.get(DBus.BusType.SYSTEM);
        if (!halContext.set_dbus_connection(halConn.get_connection()))
            error("Unable to set DBus connection for HAL");

        DBus.RawError raw = DBus.RawError();
        if (!halContext.init(ref raw))
            error("Unable to initialize context: %s", raw.message);

        if (!halContext.set_device_added(on_device_added))
            error("Unable to register device-added callback");
        if (!halContext.set_device_removed(on_device_removed))
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
        Gtk.ActionGroup actionGroup = new Gtk.ActionGroup("CommonActionGroup");
        actionGroup.add_actions(COMMON_ACTIONS, this);
        
        return actionGroup;
    }
    
    public void on_about() {
        // TODO: More thorough About box
        Gtk.show_about_dialog(this,
            "version", AppWindow.VERSION,
            "comments", "A photo organizer",
            "copyright", "(c) 2009 Yorba Foundation",
            "website", "http://www.yorba.org"
        );
    }

    public void import(File file) {
        FileType type = file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        if(type == FileType.REGULAR) {
            if (!import_file(file)) {
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
                        error("Failed to import %s (already imported?)", file.get_path());
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
        debug("Importing file %s", file.get_path());

        // TODO: Attempt to discover photo information from its metadata
        Gdk.Pixbuf original;
        try {
            original = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }
        
        Dimensions dim = Dimensions(original.get_width(), original.get_height());

        if (photoTable.add(file, dim)) {
            PhotoID photoID = photoTable.get_id(file);
            ThumbnailCache.import(photoID, original);
            collectionPage.add_photo(photoID, file);
            collectionPage.refresh();
            
            return true;
        }
        
        debug("Not importing %s (already imported)", file.get_path());
        
        return true;
    }
    
    public override void drag_data_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selectionData, uint info, uint time) {
        // grab data and release back to system
        string[] uris = selectionData.get_uris();
        Gtk.drag_finish(context, true, false, time);
        
        // import
        foreach (string uri in uris) {
            import(File.new_for_uri(uri));
        }
        
        collectionPage.refresh();
    }
    
    public static void error_message(string message) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(get_main_window(), Gtk.DialogFlags.MODAL, 
            Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", message);
        dialog.run();
        dialog.destroy();
    }
    
    public void switch_to_collection_page() {
        switch_to_page(collectionPage);
    }
    
    public void switch_to_photo_page(CheckerboardPage controller, LayoutItem current) {
        photoPage.display(controller, current);
        switch_to_page(photoPage);
    }
    
    private Gtk.Box layout = null;
    private Gtk.Box pageBox = null;
    private Gtk.Paned clientPaned = null;
    private Page currentPage = null;
    
    private void create_start_page() {
        currentPage = collectionPage;
        
        // layout the growable collection page with the toolbar beneath
        pageBox = new Gtk.VBox(false, 0);
        pageBox.pack_start(currentPage, true, true, 0);
        pageBox.pack_end(currentPage.get_toolbar(), false, false, 0);
        
        // put the sidebar in a scrolling window
        Gtk.ScrolledWindow scrolledSidebar = new Gtk.ScrolledWindow(null, null);
        scrolledSidebar.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scrolledSidebar.add(sidebar);
        
        // layout the selection tree to the left of the collection/toolbar box with an adjustable
        // gutter between them, framed for presentation
        Gtk.Frame leftFrame = new Gtk.Frame(null);
        leftFrame.add(scrolledSidebar);
        leftFrame.set_shadow_type(Gtk.ShadowType.IN);
        
        Gtk.Frame rightFrame = new Gtk.Frame(null);
        rightFrame.add(pageBox);
        rightFrame.set_shadow_type(Gtk.ShadowType.IN);
        
        clientPaned = new Gtk.HPaned();
        clientPaned.pack1(leftFrame, false, false);
        sidebar.set_size_request(SIDEBAR_MIN_WIDTH, -1);
        clientPaned.pack2(rightFrame, true, false);
        // TODO: Calc according to layout's size, to give sidebar a maximum width
        pageBox.set_size_request(PAGE_MIN_WIDTH, -1);

        // layout client beneath menu
        layout = new Gtk.VBox(false, 0);
        layout.pack_start(currentPage.get_menubar(), false, false, 0);
        layout.pack_end(clientPaned, true, true, 0);
        
        add(layout);

        add_accel_group(currentPage.ui.get_accel_group());

        currentPage.switched_to();

        show_all();
    }
    
    public void switch_to_page(Page page) {
        if (page == currentPage)
            return;
            
        currentPage.switching_from();
        
        remove_accel_group(currentPage.ui.get_accel_group());

        pageBox.remove(currentPage);
        pageBox.pack_start(page, true, true, 0);
        
        pageBox.remove(currentPage.get_toolbar());
        pageBox.pack_end(page.get_toolbar(), false, false, 0);
        
        layout.remove(currentPage.get_menubar());
        layout.pack_start(page.get_menubar(), false, false, 0);

        add_accel_group(page.ui.get_accel_group());
        
        page.switched_to();
        
        unowned Gtk.TreeRowReference row = page.get_tree_row();
        if (row != null)
            sidebar.get_selection().select_path(row.get_path());
        
        layout.show_all();
        
        currentPage = page;
    }
    
    private Gtk.TreeView sidebar = null;
    private Gtk.TreeStore sidebarStore = null;
    private Gtk.TreeRowReference camerasRow = null;

    private void build_sidebar() {
        sidebarStore = new Gtk.TreeStore(1, typeof(string));
        sidebar = new Gtk.TreeView.with_model(sidebarStore);

        var text = new Gtk.CellRendererText();
        //text.size_points = 9.0;
        var column = new Gtk.TreeViewColumn();
        column.pack_start(text, true);
        column.add_attribute(text, "text", 0);
        sidebar.append_column(column);
        
        sidebar.set_headers_visible(false);

        Gtk.TreeIter parent, child;
        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Photos");
        collectionPage.set_tree_row(sidebarStore, parent);

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Events");
        
        sidebarStore.append(out child, parent);
        sidebarStore.set(child, 0, "New Year's");

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Albums");
        
        sidebarStore.append(out child, parent);
        sidebarStore.set(child, 0, "Parties");

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Cameras");
        camerasRow = new Gtk.TreeRowReference(sidebarStore, sidebarStore.get_path(parent));

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Trash");
        
        sidebar.cursor_changed += on_sidebar_cursor_changed;
        
        // start in the collection page & control selection aspects
        Gtk.TreeSelection selection = sidebar.get_selection();
        selection.select_path(collectionPage.get_tree_row().get_path());
        selection.set_mode(Gtk.SelectionMode.BROWSE);

        sidebar.expand_all();
    }
    
    private void on_sidebar_cursor_changed() {
        Gtk.TreePath selected;
        sidebar.get_cursor(out selected, null);
        
        if (selected.compare(collectionPage.get_tree_row().get_path()) == 0) {
            switch_to_collection_page();
        } else {
            foreach (ImportPage page in cameraTable.get_values()) {
                if (selected.compare(page.get_tree_row().get_path()) == 0) {
                    switch_to_page(page);
                    
                    return;
                }
            }
            
            debug("Unimplemented page selected");
        }
    }
    
    private GPhoto.Context nullContext = new GPhoto.Context();
    private GPhoto.CameraAbilitiesList abilitiesList;
    private Gee.HashMap<string, ImportPage> cameraTable = new Gee.HashMap<string, ImportPage>(
        str_hash, str_equal, direct_equal);

    private void do_op(GPhoto.Result res, string op) throws GPhotoError {
        if (res != GPhoto.Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Unable to %s: %s", (int) res, op, res.as_string());
    }
    
    private void init_camera_table() throws GPhotoError {
        do_op(GPhoto.CameraAbilitiesList.create(out abilitiesList), "create camera abilities list");
        do_op(abilitiesList.load(nullContext), "load camera abilities list");
    }
    
    private string? esp_usb_to_udi(int cameraCount, string port, out string fullPort) {
        // sanity
        assert(cameraCount > 0);
        
        debug("ESP: cameraCount=%d port=%s", cameraCount, port);

        DBus.RawError raw = DBus.RawError();
        string[] udis = halContext.find_device_by_capability("camera", ref raw);
        
        string[] usbs = new string[0];
        foreach (string udi in udis) {
            if (halContext.device_get_property_string(udi, "info.subsystem", ref raw) == "usb")
                usbs += udi;
        }

        // if GPhoto detects one camera, and HAL reports one USB camera, all is swell
        if (cameraCount == 1) {
            if (usbs.length == 1) {
                string usb = usbs[0];
                
                int halBus = halContext.device_get_property_int(usb, "usb.bus_number", ref raw);
                int halDevice = halContext.device_get_property_int(usb, "usb.linux.device_number", ref raw);

                if (port == "usb:") {
                    // the most likely case, so make a full path
                    fullPort = "usb:%03d,%03d".printf(halBus, halDevice);
                } else {
                    fullPort = port;
                }
                
                debug("ESP: port=%s fullPort=%s udi=%s", port, fullPort, usb);
                
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
            int halBus = halContext.device_get_property_int(usb, "usb.bus_number", ref raw);
            int halDevice = halContext.device_get_property_int(usb, "usb.linux.device_number", ref raw);
            
            if ((bus == halBus) && (device == halDevice)) {
                fullPort = port;
                
                debug("ESP: port=%s fullPort=%s udi=%s", port, fullPort, usb);

                return usb;
            }
        }
        
        debug("ESP: No UDI found for port=%s", port);
        
        return null;
    }

    //
    // NOTE:
    // USB (or libusb) is a funny beast; if only one USB device is present (i.e. the camera),
    // then a single camera is detected at port usb:.  However, if multiple USB devices are
    // present (including non-cameras), then the first attached camera will be listed twice,
    // first at usb:, then at usb:xxx,yyy.  If the usb: device is removed, another usb:xxx,yyy
    // device will lose its full-path name and be referred to as usb: only.
    //
    // For now, relying on the model name reported by libgphoto2 to find the duplicate.  This is
    // problematic, especially when you have cameras who do not report a model name and are referred
    // to as "USB PTP Class Camera" by libgphoto2.
    //
    // A better strategy needs to be developed (probably involving HAL UID's).
    //
    private void update_camera_table() throws GPhotoError {
        // need to do this because virtual ports come and go in the USB world (and probably others)
        GPhoto.PortInfoList portInfoList;
        do_op(GPhoto.PortInfoList.create(out portInfoList), "create port list");
        do_op(portInfoList.load(), "load port list");

        GPhoto.CameraList cameraList;
        do_op(GPhoto.CameraList.create(out cameraList), "create camera list");
        do_op(abilitiesList.detect(portInfoList, cameraList, nullContext), "detect cameras");
        
        Gee.HashMap<string, string> detectedMap = new Gee.HashMap<string, string>(str_hash, str_equal,
            str_equal);
        
        for (int ctr = 0; ctr < cameraList.count(); ctr++) {
            string name;
            do_op(cameraList.get_name(ctr, out name), "get detected camera name");

            string port;
            do_op(cameraList.get_value(ctr, out port), "get detected camera port");
            
            debug("Detected %s @ %s", name, port);
            
            // do some USB ESP
            if (port.has_prefix("usb:")) {
                string fullPort;
                string udi = esp_usb_to_udi(cameraList.count(), port, out fullPort);
                if (udi == null)
                    continue;
                
                port = fullPort;
            }

            detectedMap.set(port, name);
        }
        
        // first, find cameras that have disappeared
        ImportPage[] missing = new ImportPage[0];
        foreach (ImportPage page in cameraTable.get_values()) {
            GPhoto.Camera camera = page.get_camera();
            
            GPhoto.PortInfo portInfo;
            do_op(camera.get_port_info(out portInfo), "retrieve missing camera port information");
            
            GPhoto.CameraAbilities abilities;
            do_op(camera.get_abilities(out abilities), "retrieve camera abilities");
            
            if (detectedMap.contains(portInfo.path)) {
                debug("Found page for %s @ %s in detected cameras", abilities.model, portInfo.path);
                
                continue;
            }
            
            debug("%s @ %s missing", abilities.model, portInfo.path);
            
            missing += page;
        }
        
        // have to remove from hash map outside of iterator
        foreach (ImportPage page in missing) {
            GPhoto.Camera camera = page.get_camera();
            
            GPhoto.PortInfo portInfo;
            do_op(camera.get_port_info(out portInfo), "retrieve missing camera port information");
            
            GPhoto.CameraAbilities abilities;
            do_op(camera.get_abilities(out abilities), "retrieve missing camera abilities");

            debug("Removing from camera table: %s @ %s", abilities.model, portInfo.path);

            Gtk.TreeIter cameraIter;
            sidebarStore.get_iter(out cameraIter, page.get_tree_row().get_path());
            sidebarStore.remove(cameraIter);

            cameraTable.remove(portInfo.path);
            
            // switch away if necessary
            if (currentPage == page)
                switch_to_collection_page();
        }

        // add cameras which were not present before
        foreach (string port in detectedMap.get_keys()) {
            string name = detectedMap.get(port);

            if (cameraTable.contains(port)) {
                // already known about
                debug("%s @ %s already registered, skipping", name, port);
                
                continue;
            }
            
            int index = portInfoList.lookup_path(port);
            if (index < 0)
                do_op((GPhoto.Result) index, "lookup port %s".printf(port));
            
            GPhoto.PortInfo portInfo;
            do_op(portInfoList.get_info(index, out portInfo), "get port info for %s".printf(port));
            
            // this should match, every time
            assert(port == portInfo.path);
            
            index = abilitiesList.lookup_model(name);
            if (index < 0)
                do_op((GPhoto.Result) index, "lookup camera model %s".printf(name));

            GPhoto.CameraAbilities cameraAbilities;
            do_op(abilitiesList.get_abilities(index, out cameraAbilities), 
                "lookup camera abilities for %s".printf(name));
                
            GPhoto.Camera camera;
            do_op(GPhoto.Camera.create(out camera), "create camera object for %s".printf(name));
            do_op(camera.set_abilities(cameraAbilities), "set camera abilities for %s".printf(name));
            do_op(camera.set_port_info(portInfo), "set port info for %s on %s".printf(name, port));
            
            debug("Adding to camera table: %s @ %s", name, port);
            
            Gtk.TreeIter camerasIter, child;
            sidebarStore.get_iter(out camerasIter, camerasRow.get_path());
            sidebarStore.append(out child, camerasIter);
            sidebarStore.set(child, 0, name);
            
            /*
            Gtk.TreeRowReference pageRow = new Gtk.TreeRowReference(sidebarStore,
                sidebarStore.get_path(child));
            */

            ImportPage page = new ImportPage(camera);
            page.set_tree_row(sidebarStore, child);

            cameraTable.set(port, page);
            
            page.refresh_camera();
        }
    }
    
    private static void on_device_added(Hal.Context context, string udi) {
        debug("******* on_device_added: %s", udi);
        
        try {
            AppWindow.get_main_window().update_camera_table();
        } catch (GPhotoError err) {
            debug("Error updating camera table: %s", err.message);
        }
    }
    
    private static void on_device_removed(Hal.Context context, string udi) {
        debug("******** on_device_removed: %s", udi);
        
        try {
            AppWindow.get_main_window().update_camera_table();
        } catch (GPhotoError err) {
            debug("Error updating camera table: %s", err.message);
        }
    }
}

