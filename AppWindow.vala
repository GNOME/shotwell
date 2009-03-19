
public class AppWindow : Gtk.Window {
    public static const string TITLE = "Photo Organizer";
    public static const string VERSION = "0.0.1";
    public static const string DATA_DIR = ".photo";

    private static AppWindow mainWindow = null;
    private static string[] args = null;
    private static Sqlite.Database db = null;

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "File", null, "_File", null, null, null },
        { "Quit", Gtk.STOCK_QUIT, "_Quit", null, "Quit the program", Gtk.main_quit },
        
        { "Edit", null, "_Edit", null, null, on_edit_menu },
        { "SelectAll", Gtk.STOCK_SELECT_ALL, "Select _All", "<Ctrl>A", "Select all the photos in the library", on_select_all },
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove },
        
        { "Photos", null, "_Photos", null, null, on_photos_menu },
        { "IncreaseSize", Gtk.STOCK_ZOOM_IN, "Zoom _in", "KP_Add", "Increase the magnification of the thumbnails", on_increase_size },
        { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, "Zoom _out", "KP_Subtract", "Decrease the magnification of the thumbnails", on_decrease_size },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, "_About", null, "About this application", on_about }
    };
    
    // drag and drop target entries
    private const Gtk.TargetEntry[] TARGET_ENTRIES = {
        { "text/uri-list", 0, 0 }
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
        
        File dbFile = get_data_subdir("data").get_child("photo.db");
        int res = Sqlite.Database.open_v2(dbFile.get_path(), out db, 
            Sqlite.OPEN_READWRITE | Sqlite.OPEN_CREATE, null);
        if (res != Sqlite.OK) {
            error("Unable to open/create photo database %s: %d", dbFile.get_path(), res);
        }

        ThumbnailCache.init();
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
    
    public static unowned Sqlite.Database get_db() {
        return db;
    }

    private Gtk.UIManager uiManager = new Gtk.UIManager();
    private CollectionPage collectionPage = null;
    private PhotoTable photoTable = null;

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
        
        // set up as a drag-and-drop destination
        // this.drag_data_received() is called when a drop occurs
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, TARGET_ENTRIES, Gdk.DragAction.COPY);
        
        // if this is the first AppWindow, it's the main AppWindow
        if (mainWindow == null) {
            mainWindow = this;
        }
        
        button_press_event += on_button_press;

        photoTable = new PhotoTable();
        collectionPage = new CollectionPage();

        // layout widgets in vertical box
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(menubar, false, false, 0);
        vbox.pack_end(collectionPage, true, true, 0);
        add(vbox);
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
            
            if (photoTable.add_photo(file)) {
                int id = photoTable.get_photo_id(file);
                ThumbnailCache.big.import(id, file);
                collectionPage.add_photo(id, file);
            } else {
                Gtk.MessageDialog dialog = new Gtk.MessageDialog(this, Gtk.DialogFlags.MODAL,
                    Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s already stored",
                    file.get_path());
                dialog.run();
                dialog.destroy();
            }
            
            return;
        } else if (type != FileType.DIRECTORY) {
            message("Skipping file %s (neither a directory nor a file)", file.get_path());
            
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
                    if (photoTable.add_photo(file)) {
                        int id = photoTable.get_photo_id(file);
                        ThumbnailCache.big.import(id, file);
                        collectionPage.add_photo(id, file);
                    } else {
                        // TODO: Better error reporting
                    }
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
    
    private bool on_button_press(AppWindow aw, Gdk.EventButton event) {
        // don't handle anything but primary button for now
        if (event.button != 1) {
            return false;
        }
        
        // only interested in single-clicks presses for now
        if (event.type != Gdk.EventType.BUTTON_PRESS) {
            return false;
        }
        
        // mask out the modifiers we're interested in
        uint state = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
        
        Thumbnail thumbnail = collectionPage.get_thumbnail_at(event.x, event.y);
        if (thumbnail != null) {
            message("clicked on %s", thumbnail.get_file().get_basename());
            
            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK: {
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    thumbnail.toggle_select();
                } break;
                
                case Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                default: {
                    // a "raw" click deselects all thumbnails and selects the single chosen
                    collectionPage.unselect_all();
                    thumbnail.select();
                } break;
            }
        } else {
            // user clicked on "dead" area
            collectionPage.unselect_all();
        }

        return false;
    }
    
    private void set_item_sensitive(string path, bool sensitive) {
        Gtk.Widget widget = uiManager.get_widget(path);
        widget.set_sensitive(sensitive);
    }
    
    private void on_edit_menu() {
        set_item_sensitive("/MenuBar/EditMenu/EditSelectAll", collectionPage.get_count() > 0);
        set_item_sensitive("/MenuBar/EditMenu/EditRemove", collectionPage.get_selected_count() > 0);
    }
    
    private void on_remove() {
        Thumbnail[] thumbnails = collectionPage.get_selected();
        foreach (Thumbnail thumbnail in thumbnails) {
            message("Removing %s", thumbnail.get_file().get_basename());
            collectionPage.remove_photo(thumbnail);
            ThumbnailCache.big.remove(photoTable.get_photo_id(thumbnail.get_file()));
            photoTable.remove_photo(thumbnail.get_file());
        }
        
        collectionPage.repack();
    }

    private void on_select_all() {
        collectionPage.select_all();
    }

    private void on_photos_menu() {
    }

    private void on_increase_size() {
        collectionPage.increase_thumb_size();
    }

    private void on_decrease_size() {
        collectionPage.decrease_thumb_size();
    }
}

