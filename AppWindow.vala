
public class AppWindow : Gtk.Window {
    public static const string TITLE = "Photo Organizer";
    public static const string VERSION = "0.0.1";

    private static AppWindow mainWindow = null;
    private static string[] args = null;
    private static GLib.File execFile = null;

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "File", null, "_File", null, null, null },
        { "Quit", Gtk.STOCK_QUIT, "_Quit", null, "Quit the program", Gtk.main_quit },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, "_About", null, "About this application", on_about }
    };
    
    // drag and drop target entries
    private const Gtk.TargetEntry[] TARGET_ENTRIES = {
        { "text/uri-list", 0, 0 }
    };
    
    public static AppWindow get_main_window() {
        return mainWindow;
    }
    
    public static void set_commandline_args(string[] args) {
        args = args;
        execFile = GLib.File.new_for_commandline_arg(args[0]);
    }
    
    public static string[] get_commandline_args() {
        return args;
    }
    
    public static GLib.File get_exec_file() {
        return execFile;
    }
    
    public static GLib.File get_exec_dir() {
        return execFile.get_parent();
    }
    
    private Gtk.UIManager uiManager = new Gtk.UIManager();
    private CollectionPage collectionPage = new CollectionPage();

    construct {
        // set up display
        title = TITLE;
        set_default_size(800, 600);

        destroy += Gtk.main_quit;

        // window actions
        Gtk.ActionGroup actionGroup = new Gtk.ActionGroup("MainActionGroup");
        actionGroup.add_actions(ACTIONS, this);
        
        uiManager.insert_action_group(actionGroup, 0);
        
        GLib.File uiFile = get_exec_dir().get_child("photo.ui");
        assert(uiFile != null);

        try {
            uiManager.add_ui_from_file(uiFile.get_path());
        } catch (GLib.Error gle) {
            // TODO: Exit app immediately
            error("Error loading UI: %s", gle.message);
        }

        // primary widgets
        Gtk.MenuBar menubar = (Gtk.MenuBar) uiManager.get_widget("/MenuBar");
        add_accel_group(uiManager.get_accel_group());
        
        // layout widgets in vertical box
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(menubar, false, false, 0);
        vbox.pack_end(collectionPage, true, true, 0);
        add(vbox);

        // set up as a drag-and-drop destination
        // this.drag_data_received() is called when a drop occurs
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, TARGET_ENTRIES, Gdk.DragAction.COPY);
        
        // if this is the first AppWindow, it's the main AppWindow
        if (mainWindow == null) {
            mainWindow = this;
        }
        
        enter_notify_event += on_mouse_enter;
        leave_notify_event += on_mouse_exit;
    }
    
    private void on_about() {
        // TODO: More thorough About box
        Gtk.show_about_dialog(this,
            "version", VERSION,
            "comments", "a photo organizer",
            "copyright", "(c) 2009 yorba"
        );
    }
    
    private void import(File file) {
        FileType type = file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        if(type == FileType.REGULAR) {
            message("Importing file %s", file.get_path());
            collectionPage.add_photo(file);
            
            return;
        } else if (type != FileType.DIRECTORY) {
            message("Skipping file %s (not directory or file)", file.get_path());
            
            return;
        }
        
        message("Importing directory %s", file.get_path());
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
                    message("Importing file %s", file.get_path());
                    collectionPage.add_photo(file);
                } else if (type == FileType.DIRECTORY) {
                    message("Importing directory  %s", file.get_path());
                    import_dir(file);
                } else {
                    message("Skipped %s", file.get_path());
                }
            }
        } catch (Error err) {
            // TODO: Better error reporting
            error("Error importing: %s", err.message);
        }
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
    }
    
    private bool on_mouse_enter(AppWindow aw, Gdk.EventCrossing crossing) {
        message("on_mouse_enter");
        
        return false;
    }

    private bool on_mouse_exit(AppWindow aw, Gdk.EventCrossing crossing) {
        message("on_mouse_exit");
        
        return false;
    }
}

