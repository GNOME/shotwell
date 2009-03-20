
public class AppWindow : Gtk.Window {
    public static const string TITLE = "Photo Organizer";
    public static const string VERSION = "0.0.1";
    public static const string DATA_DIR = ".photo";

    private static AppWindow mainWindow = null;
    private static Gtk.UIManager uiManager = null;
    private static string[] args = null;

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "File", null, "_File", null, null, null },
        { "Quit", Gtk.STOCK_QUIT, "_Quit", null, "Quit the program", Gtk.main_quit },
        
        { "Edit", null, "_Edit", null, null, on_edit_menu },
        { "SelectAll", Gtk.STOCK_SELECT_ALL, "Select _All", "<Ctrl>A", "Select all the photos in the library", on_select_all },
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove },
        
        { "Photos", null, "_Photos", null, null, null },
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
        
        uiManager = new Gtk.UIManager();

        File uiFile = get_exec_dir().get_child("photo.ui");
        assert(uiFile != null);

        try {
            uiManager.add_ui_from_file(uiFile.get_path());
        } catch (GLib.Error gle) {
            error("Error loading UI: %s", gle.message);
        }
    }
    
    public static AppWindow get_main_window() {
        return mainWindow;
    }
    
    public static Gtk.UIManager get_ui_manager() {
        return uiManager;
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
        
        // primary widgets
        Gtk.MenuBar menubar = (Gtk.MenuBar) uiManager.get_widget("/MenuBar");
        add_accel_group(uiManager.get_accel_group());
        
        Gtk.TreeStore pageTreeStore = new Gtk.TreeStore(1, typeof(string));
        Gtk.TreeView pageTreeView = new Gtk.TreeView.with_model(pageTreeStore);
        pageTreeView.modify_bg(Gtk.StateType.NORMAL, parse_color(CollectionPage.BG_COLOR));
        
        var text = new Gtk.CellRendererText();
        text.size_points = 9.0;
        var column = new Gtk.TreeViewColumn();
        column.pack_start(text, true);
        column.add_attribute(text, "text", 0);
        pageTreeView.append_column(column);
        
        pageTreeView.set_headers_visible(false);

        Gtk.TreeIter parent, child;
        pageTreeStore.append(out parent, null);
        pageTreeStore.set(parent, 0, "Photos");

        pageTreeStore.append(out parent, null);
        pageTreeStore.set(parent, 0, "Events");
        
        pageTreeStore.append(out child, parent);
        pageTreeStore.set(child, 0, "New Year's");

        pageTreeStore.append(out parent, null);
        pageTreeStore.set(parent, 0, "Albums");
        
        pageTreeStore.append(out child, parent);
        pageTreeStore.set(child, 0, "Parties");

        pageTreeStore.append(out parent, null);
        pageTreeStore.set(parent, 0, null);

        pageTreeStore.append(out parent, null);
        pageTreeStore.set(parent, 0, "Import");

        pageTreeStore.append(out parent, null);
        pageTreeStore.set(parent, 0, "Recent");

        pageTreeStore.append(out parent, null);
        pageTreeStore.set(parent, 0, "Trash");

        // set up as a drag-and-drop destination
        // this.drag_data_received() is called when a drop occurs
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, TARGET_ENTRIES, Gdk.DragAction.COPY);
        
        // if this is the first AppWindow, it's the main AppWindow
        if (mainWindow == null) {
            mainWindow = this;
        }
        
        photoTable = new PhotoTable();
        collectionPage = new CollectionPage();
        
        // layout the selection tree and the view side-by-side
        Gtk.HBox hbox = new Gtk.HBox(false, 0);
        hbox.pack_start(pageTreeView, false, false, 0);
        hbox.pack_end(collectionPage, true, true, 0);

        // layout everything vertically inside the main window
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(menubar, false, false, 0);
        vbox.pack_end(hbox, true, true, 0);
        
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
            debug("Importing file %s", file.get_path());
            
            if (photoTable.add(file)) {
                PhotoID photoID = photoTable.get_id(file);
                ThumbnailCache.big.import(photoID, file);
                collectionPage.add_photo(photoID, file);
            } else {
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
                    debug("Importing file %s", file.get_path());

                    if (photoTable.add(file)) {
                        PhotoID photoID = photoTable.get_id(file);
                        ThumbnailCache.big.import(photoID, file);
                        collectionPage.add_photo(photoID, file);
                    } else {
                        // TODO: Better error reporting
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
            collectionPage.remove_photo(thumbnail);
            ThumbnailCache.big.remove(photoTable.get_id(thumbnail.get_file()));
            photoTable.remove(thumbnail.get_file());
        }
        
        collectionPage.repack();
    }

    private void on_select_all() {
        collectionPage.select_all();
    }

    private void on_increase_size() {
        collectionPage.increase_thumb_size();
    }

    private void on_decrease_size() {
        collectionPage.decrease_thumb_size();
    }
}

