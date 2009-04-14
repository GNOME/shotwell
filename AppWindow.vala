
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
    
    private CollectionPage collectionPage = null;
    private ImportPage importPage = null;
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
        
        build_sidebar();
        
        collectionPage = new CollectionPage();
        importPage = new ImportPage();
        photoPage = new PhotoPage();
        
        create_start_page();

        // set up main window as a drag-and-drop destination (rather than each page; assume
        // a drag and drop is for general library importation, which means it goes to collectionPage)
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, TARGET_ENTRIES, Gdk.DragAction.COPY);
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
    
    public void switch_to_collection_page() {
        switch_to_page(collectionPage);
    }
    
    public void switch_to_import_page() {
        switch_to_page(importPage);
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
        
        layout.show_all();
        
        currentPage = page;
    }
    
    private Gtk.TreeView sidebar = null;
    private Gtk.TreeStore sidebarStore = null;
    private Gtk.TreePath collectionPath = null;
    private Gtk.TreePath importPath = null;

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
        collectionPath = sidebarStore.get_path(parent);
        // start in the collection page
        sidebar.get_selection().select_path(collectionPath);

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Events");
        
        sidebarStore.append(out child, parent);
        sidebarStore.set(child, 0, "New Year's");

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Albums");
        
        sidebarStore.append(out child, parent);
        sidebarStore.set(child, 0, "Parties");

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, null);

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Import");
        importPath = sidebarStore.get_path(parent);

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Recent");

        sidebarStore.append(out parent, null);
        sidebarStore.set(parent, 0, "Trash");
        
        sidebar.cursor_changed += on_sidebar_cursor_changed;
    }
    
    private void on_sidebar_cursor_changed() {
        Gtk.TreePath selected;
        sidebar.get_cursor(out selected, null);
        
        if (selected.compare(collectionPath) == 0) {
            switch_to_collection_page();
        } else if (selected.compare(importPath) == 0) {
            switch_to_import_page();
        } else {
            debug("unknown");
        }
    }
}

