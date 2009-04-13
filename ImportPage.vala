
public class ImportPreview : LayoutItem {
    public string folder;
    public string filename;
    public Exif.Data exif;
    
    private Exif.Orientation orientation = Exif.Orientation.TOP_LEFT;
    
    public ImportPreview(Gdk.Pixbuf pixbuf, Exif.Data exif, string folder, string filename) {
        this.folder = folder;
        this.filename = filename;
        this.exif = exif;
        
        Exif.Entry entry = Exif.find_first_entry(exif, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry != null) {
            int o = Exif.Convert.get_short(entry.data, exif.get_byte_order());
            assert(o >= Exif.ORIENTATION_MIN);
            assert(o <= Exif.ORIENTATION_MAX);
            
            orientation = (Exif.Orientation) o;
        }

        title.set_text(filename);

        Gdk.Pixbuf rotated = rotate_to_exif(pixbuf, orientation);
        image.set_from_pixbuf(rotated);
    }
}

public class ImportPage : CheckerboardPage {
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.Label cameraLabel = new Gtk.Label(null);
    private Gtk.ToolButton refreshButton = new Gtk.ToolButton.from_stock(Gtk.STOCK_REFRESH);
    private Gtk.ToolButton importSelectedButton;
    private Gtk.ToolButton importAllButton;
    private GPhoto.Context context = new GPhoto.Context();
    private GPhoto.PortInfoList portInfoList;
    private GPhoto.CameraAbilitiesList abilitiesList;
    private GPhoto.CameraAbilities cameraAbilities;
    private GPhoto.Camera camera;
    private bool busy = false;
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, on_file },
        { "ImportSelected", null, "Import _Selected", null, null, on_import_selected },
        { "ImportAll", null, "Import _All", null, null, on_import_all },
        
        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    private void on_idle() {
        debug("idle");
        
        while (Gtk.events_pending())
            Gtk.main_iteration();
    }
    
    private uint on_progress_start(GPhoto.Context context, float target, string format, void *va_list) {
        debug("progress start target=%f", target);
        
        return 0;
    }
    
    private void on_progress_update(GPhoto.Context context, uint id, float current) {
        debug("progress update id=%u current=%f", id, current);

        while (Gtk.events_pending())
            Gtk.main_iteration();
    }
    
    private void on_progress_stop(GPhoto.Context context, uint id) {
        debug("progress stop id=%u", id);
    }
    
    construct {
        init_ui("import.ui", "/ImportMenuBar", "ImportActionGroup", ACTIONS);
        
        context.set_idle_func(on_idle);
        context.set_progress_funcs(on_progress_start, on_progress_update, on_progress_stop);

        // toolbar
        // Refresh button
        refreshButton.sensitive = false;
        refreshButton.clicked += on_refresh_camera;
        
        toolbar.insert(refreshButton, -1);
        
        // Camera label
        Gtk.ToolItem cameraLabelItem = new Gtk.ToolItem();
        cameraLabelItem.add(cameraLabel);
        toolbar.insert(cameraLabelItem, -1);

        // separator to force buttons to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);

        importSelectedButton = new Gtk.ToolButton(new Gtk.Label("Import Selected"), "");
        importSelectedButton.clicked += on_import_selected;
        importSelectedButton.sensitive = false;
        
        toolbar.insert(importSelectedButton, -1);
        
        importAllButton = new Gtk.ToolButton(new Gtk.Label("Import All"), "");
        importAllButton.clicked += on_import_all;
        importAllButton.sensitive = false;
        
        toolbar.insert(importAllButton, -1);
        
        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        show_all();

        // persistent gphoto stuff
        GPhoto.Result res = GPhoto.PortInfoList.create(out portInfoList);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }

        res = portInfoList.load();
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        res = GPhoto.CameraAbilitiesList.create(out abilitiesList);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        res = abilitiesList.load(context);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        res = GPhoto.Camera.create(out camera);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
    }
        
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void on_selection_changed(int count) {
        importSelectedButton.sensitive = !busy && (count > 0);
    }
    
    public override void on_item_activated(LayoutItem item) {
        ImportPreview preview = (ImportPreview) item;
        
        GPhoto.Result res = camera.init(context);
        if (res != GPhoto.Result.OK) {
            error_message("Unable to access camera: %s".printf(res.as_string()));
            
            return;
        }
        
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = GPhoto.load_image(context, camera, preview.folder, preview.filename);
        } catch(Error err) {
            error("%s", err.message);
        }
        
        res = camera.exit(context);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        AppWindow.get_main_window().switch_to_import_preview_page(pixbuf, preview.exif);
    }

    public override void switched_to() {
        if (busy)
            return;
        
        GPhoto.CameraList cameraList;
        GPhoto.Result res = GPhoto.CameraList.create(out cameraList);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        res = abilitiesList.detect(portInfoList, cameraList, context);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        if (cameraList.count() == 0) {
            refreshButton.sensitive = false;
            cameraLabel.sensitive = false;
            cameraLabel.set_text("No camera attached");
            
            remove_all();
            importSelectedButton.sensitive = false;
            importAllButton.sensitive = false;
            
            return;
        }
        
        string name;
        string port;
        res = cameraList.get_name(0, out name);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }

        res = cameraList.get_value(0, out port);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        int index = abilitiesList.lookup_model(name);
        if (index < 0) {
            error("%d", index);
        }
        
        res = abilitiesList.get_abilities(index, out cameraAbilities);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        res = camera.set_abilities(cameraAbilities);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        debug("%s", port);
        index = portInfoList.lookup_path(port);
        if (index < 0) {
            error("%d", index);
        }
        
        GPhoto.PortInfo portInfo;
        res = portInfoList.get_info(index, out portInfo);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        res = camera.set_port_info(portInfo);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        cameraLabel.set_text("%s (%s)".printf(name, port));
        cameraLabel.sensitive = true;
        refreshButton.sensitive = true;
    }
    
    private void on_refresh_camera() {
        Gdk.Cursor busyCursor = new Gdk.Cursor(Gdk.CursorType.WATCH);
        AppWindow.get_main_window().window.set_cursor(busyCursor);

        GPhoto.Result res = camera.init(context);

        AppWindow.get_main_window().window.set_cursor(null);

        if (res != GPhoto.Result.OK) {
            error_message("Unable to access camera: %s".printf(res.as_string()));
            
            return;
        }
        
        busy = true;
        
        refreshButton.sensitive = false;
        importSelectedButton.sensitive = false;
        importAllButton.sensitive = false;

        try {
            
            GPhoto.CameraStorageInformation *sifs = null;
            int count = 0;
            res = camera.get_storageinfo(&sifs, out count, context);
            if (res != GPhoto.Result.OK) {
                error("%s", res.as_string());
            }
            
            remove_all();
            
            GPhoto.CameraStorageInformation *ifs = sifs;
            for (int ctr = 0; ctr < count; ctr++, ifs++) {
                string basedir = "/";
                if ((ifs->fields & GPhoto.CameraStorageInfoFields.BASE) != 0)
                    basedir = ifs->basedir;
                
                debug ("fs %s", basedir);
                
                if (!load_preview(basedir))
                    return;
            }
        } finally {
            res = camera.exit(context);
            if (res != GPhoto.Result.OK) {
                error("%s", res.as_string());
            }

            refreshButton.sensitive = true;
            importSelectedButton.sensitive = get_selected_count() > 0;
            importAllButton.sensitive = get_count() > 0;

            busy = false;
        }
    }
    
    private bool load_preview(string dir) {
        debug("Searching %s", dir);
        
        GPhoto.CameraList files;
        GPhoto.Result res = GPhoto.CameraList.create(out files);
        res = camera.list_files(dir, files, context);
        
        uint8[] buffer = new uint8[64 * 1024];
        
        for (int ctr = 0; ctr < files.count(); ctr++) {
            string filename;
            res = files.get_name(ctr, out filename);
            
            try {
                GPhoto.CameraFileInfo info;
                GPhoto.get_info(context, camera, dir, filename, out info);
                
                // at this point, only interested in JPEG files with a JPEG preview
                if (((info.preview.fields & GPhoto.CameraFileInfoFields.TYPE) == 0)
                    || ((info.file.fields & GPhoto.CameraFileInfoFields.TYPE) == 0)) {
                    debug("Skipping %s/%s: No preview (preview=%02Xh file=%02Xh)", dir, filename,
                        info.preview.fields, info.file.fields);
                        
                    continue;
                }
                
                if ((info.preview.type != GPhoto.MIME.JPEG) || (info.file.type != GPhoto.MIME.JPEG)) {
                    debug("Skipping %s/%s: Not a JPEG (preview=%s file=%s)", dir, filename,
                        info.preview.type, info.file.type);
                        
                    continue;
                }
                
                Gdk.Pixbuf pixbuf = GPhoto.load_preview(context, camera, dir, filename, buffer);
                Exif.Data exif = GPhoto.load_exif(context, camera, dir, filename, buffer);
                
                ImportPreview preview = new ImportPreview(pixbuf, exif, dir, filename);
                add_item(preview);
            
                refresh();
                
                // spin the event loop so the UI doesn't freeze
                // TODO: Background thread
                while (Gtk.events_pending()) {
                    if (Gtk.main_iteration()) {
                        // Gtk.main_quit was called, abort out to exit
                        return false;
                    }
                }
            } catch (Error err) {
                error("%s", err.message);
            }
        }
        
        GPhoto.CameraList folders;
        res = GPhoto.CameraList.create(out folders);
        res = camera.list_folders(dir, folders, context);
        
        for (int ctr = 0; ctr < folders.count(); ctr++) {
            string subdir;
            res = folders.get_name(ctr, out subdir);
            if (!load_preview(dir + "/" + subdir))
                return false;
        }
        
        return true;
    }
    
    private void error_message(string message) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_main_window(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", message);
        dialog.run();
        dialog.destroy();
    }
    
    private void on_file() {
        set_item_sensitive("/ImportMenuBar/FileMenu/ImportSelected", !busy && (get_selected_count() > 0));
        set_item_sensitive("/ImportMenuBar/FileMenu/ImportAll", !busy && (get_count() > 0));
    }
    
    private void on_import_selected() {
        import(get_selected());
    }
    
    private void on_import_all() {
        import(get_items());
    }
    
    private void import(Gee.Iterable<LayoutItem> items) {
        File photosDir = AppWindow.get_photos_dir();
        
        busy = true;

        refreshButton.sensitive = false;
        importSelectedButton.sensitive = false;
        importAllButton.sensitive = false;
        
        try {
            foreach (LayoutItem item in items) {
                ImportPreview preview = (ImportPreview) item;
                
                // TODO: Currently, files are stored flat in the directory and imported photos will
                // overwrite ones with the same name
                File destFile = photosDir.get_child(preview.filename);
                
                try {
                    GPhoto.save_image(context, camera, preview.folder, preview.filename, destFile);
                } catch (Error err) {
                    error_message("Unable to import %s: %s".printf(preview.filename, err.message));
                    
                    continue;
                }
                
                AppWindow.get_main_window().import(destFile);

                while (Gtk.events_pending()) {
                    if (Gtk.main_iteration()) {
                        // Gtk.main_quit was called, abort out to exit
                        return;
                    }
                }
            }
        } finally {
            refreshButton.sensitive = true;
            importSelectedButton.sensitive = get_selected_count() > 0;
            importAllButton.sensitive = get_count() > 0;

            busy = false;
        }
    }
}

