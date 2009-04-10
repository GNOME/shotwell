
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
    private Gtk.ActionGroup actionGroup = new Gtk.ActionGroup("ImportActionGroup");
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
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "File", null, "_File", null, null, on_file },
        { "ImportSelected", null, "Import _Selected", null, null, on_import_selected },
        { "ImportAll", null, "Import _All", null, null, on_import_all },
        { "Quit", Gtk.STOCK_QUIT, "_Quit", null, "Quit the program", Gtk.main_quit },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, "_About", null, "About this application", about_box }
    };
    
    construct {
        actionGroup.add_actions(ACTIONS, this);
        AppWindow.get_ui_manager().insert_action_group(actionGroup, 0);
        
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

        importSelectedButton = new Gtk.ToolButton(new Gtk.Label("Import Selected"), "ImportSelected");        
        importSelectedButton.clicked += on_import_selected;
        importSelectedButton.sensitive = false;
        
        toolbar.insert(importSelectedButton, -1);
        
        importAllButton = new Gtk.ToolButton(new Gtk.Label("Import All"), "Import All");
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
        
    public override string get_menubar_path() {
        return "/ImportMenuBar";
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void on_selection_changed(int count) {
        importSelectedButton.sensitive = (count > 0);
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
        GPhoto.Result res = camera.init(context);
        if (res != GPhoto.Result.OK) {
            error_message("Unable to access camera: %s".printf(res.as_string()));
            
            return;
        }
        
        GPhoto.CameraStorageInformation *sifs = null;
        int count = 0;
        res = camera.get_storageinfo(&sifs, out count, context);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
        
        remove_all();
        importSelectedButton.sensitive = false;
        importAllButton.sensitive = false;
        
        int previewCount = 0;
        GPhoto.CameraStorageInformation *ifs = sifs;
        for (int ctr = 0; ctr < count; ctr++, ifs++) {
            string basedir = "/";
            if ((ifs->fields & GPhoto.CameraStorageInfoFields.BASE) != 0)
                basedir = ifs->basedir;
            
            debug ("fs %s", basedir);
            
            previewCount += load_preview(basedir);
        }
        
        importAllButton.sensitive = (previewCount > 0);

        res = camera.exit(context);
        if (res != GPhoto.Result.OK) {
            error("%s", res.as_string());
        }
    }
    
    private int load_preview(string dir) {
        int count = 0;
        
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
                debug("preview=%02Xh file=%02Xh", (int) info.preview.fields, (int) info.file.fields);
                debug("preview=%s file=%s", info.preview.type, info.file.type);
                
                // at this point, only interested in JPEG files with a JPEG preview
                if (((info.preview.fields & GPhoto.CameraFileInfoFields.TYPE) == 0)
                    || ((info.file.fields & GPhoto.CameraFileInfoFields.TYPE) == 0)) {
                    continue;
                }
                
                if ((info.preview.type != GPhoto.MIME.JPEG) || (info.file.type != GPhoto.MIME.JPEG)) {
                    continue;
                }
                
                Gdk.Pixbuf pixbuf = GPhoto.load_preview(context, camera, dir, filename, buffer);
                Exif.Data exif = GPhoto.load_exif(context, camera, dir, filename, buffer);
                
                ImportPreview preview = new ImportPreview(pixbuf, exif, dir, filename);
                add_item(preview);
                count++;
            
                refresh();
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
            count += load_preview(dir + "/" + subdir);
        }
        
        return count;
    }
    
    private void error_message(string message) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_main_window(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", message);
        dialog.run();
        dialog.destroy();
    }
    
    private void on_file() {
        set_item_sensitive("/ImportMenuBar/FileMenu/ImportSelected", get_selected_count() > 0);
        set_item_sensitive("/ImportMenuBar/FileMenu/ImportAll", get_count() > 0);
    }
    
    private void on_import_selected() {
        import(get_selected());
    }
    
    private void on_import_all() {
        import(get_items());
    }
    
    private void import(Gee.Iterable<LayoutItem> items) {
        File photosDir = AppWindow.get_photos_dir();
        
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
        }
    }
}

