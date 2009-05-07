
class ImportPreview : LayoutItem {
    public string folder;
    public string filename;

    private ImportPage parentPage;
    private Exif.Data exif;
    
    private Exif.Orientation orientation = Exif.Orientation.TOP_LEFT;
    
    public ImportPreview(ImportPage parentPage, Gdk.Pixbuf pixbuf, Exif.Data exif, string folder, 
        string filename) {
        this.parentPage = parentPage;
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

class ProgressBarContext {
    public GPhoto.Context context = new GPhoto.Context();
    
    private Gtk.ProgressBar progressBar;
    private string msg;
    private float taskTarget = 0.0;
    
    public ProgressBarContext(Gtk.ProgressBar progressBar, string msg) {
        this.progressBar = progressBar;
        this.msg = msg;

        context.set_idle_func(on_idle);
        context.set_error_func(on_error);
        context.set_status_func(on_status);
        context.set_message_func(on_message);
        context.set_progress_funcs(on_progress_start, on_progress_update, on_progress_stop);
    }
    
    public void set_message(string msg) {
        this.msg = msg;
        progressBar.set_text(msg);
    }

    private void on_idle() {
        while (Gtk.events_pending())
            Gtk.main_iteration();
    }
    
    private void on_error(GPhoto.Context context, string format, void *va_list) {
        debug("on_error: %s", format);
    }
    
    private void on_status(GPhoto.Context context, string format, void *va_list) {
        debug("on_status: %s", format);
    }
    
    private void on_message(GPhoto.Context context, string format, void *va_list) {
        debug("on_message: %s", format);
    }
    
    private uint on_progress_start(GPhoto.Context context, float target, string format, void *va_list) {
        debug("on_progress_start: %s", format);
        
        taskTarget = target;
        progressBar.set_fraction(0.0);
        progressBar.set_text(msg);
        
        return 0;
    }
    
    private void on_progress_update(GPhoto.Context context, uint id, float current) {
        progressBar.set_fraction(current / taskTarget);
        progressBar.set_text(msg);

        while (Gtk.events_pending())
            Gtk.main_iteration();
    }
    
    private void on_progress_stop(GPhoto.Context context, uint id) {
        progressBar.set_fraction(0.0);
        progressBar.set_text("");
    }
}

public class ImportPage : CheckerboardPage {
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.Label cameraLabel = new Gtk.Label(null);
    private Gtk.ToolButton importSelectedButton;
    private Gtk.ToolButton importAllButton;
    private Gtk.ProgressBar progressBar = new Gtk.ProgressBar();
    private GPhoto.Camera camera;
    private string uri;
    private ProgressBarContext init_context = null;
    private ProgressBarContext loading_context = null;
    private bool busy = false;
    private bool refreshed = false;
    private GPhoto.Result refreshResult = GPhoto.Result.OK;
    private string refreshError = null;
    private int fileCount = 0;
    private int completedCount = 0;
    private string camera_name;
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, on_file },
        { "ImportSelected", null, "Import _Selected", null, null, on_import_selected },
        { "ImportAll", null, "Import _All", null, null, on_import_all },
        
        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    public enum RefreshResult {
        OK,
        BUSY,
        LOCKED,
        LIBRARY_ERROR
    }
    
    public ImportPage(GPhoto.Camera camera, string uri) {
        base("Import");
        camera_name = "Import";
        
        this.camera = camera;
        this.uri = uri;
        
        init_ui("import.ui", "/ImportMenuBar", "ImportActionGroup", ACTIONS);
        
        init_context = new ProgressBarContext(progressBar, "Initializing camera ...");
        loading_context =  new ProgressBarContext(progressBar, "Fetching photo previews ..");
        
        // toolbar
        // Camera label
        Gtk.ToolItem cameraLabelItem = new Gtk.ToolItem();
        cameraLabelItem.add(cameraLabel);

        toolbar.insert(cameraLabelItem, -1);
        
        // separator to force buttons to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        progressBar.set_orientation(Gtk.ProgressBarOrientation.LEFT_TO_RIGHT);
        Gtk.ToolItem progressItem = new Gtk.ToolItem();
        progressItem.add(progressBar);
        
        toolbar.insert(progressItem, -1);

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
        
        GPhoto.CameraAbilities abilities;
        GPhoto.Result res = camera.get_abilities(out abilities);
        if (res != GPhoto.Result.OK) {
            debug("[%d] Unable to get camera abilities: %s", (int) res, res.as_string());
        } else {
            camera_name = abilities.model;
            cameraLabel.set_text(abilities.model);
        }

        show_all();
    }
    
    public override string get_name() {
        return camera_name;
    }
    
    public GPhoto.Camera get_camera() {
        return camera;
    }
    
    public string get_uri() {
        return uri;
    }
    
    public bool is_busy() {
        return busy;
    }
    
    public bool is_refreshed() {
        return refreshed && !busy;
    }
    
    public string? get_refresh_message() {
        string msg = null;
        if (refreshError != null) {
            msg = refreshError;
        } else if (refreshResult == GPhoto.Result.OK) {
            // all went well
        } else {
            msg = "%s (%d)".printf(refreshResult.as_string(), (int) refreshResult);
        }
        
        return msg;
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void switched_to() {
        if (busy || refreshed)
            return;
    }
    
    public override void on_selection_changed(int count) {
        importSelectedButton.sensitive = !busy && refreshed && (count > 0);
    }
    
    public override LayoutItem? get_fullscreen_photo() {
        error("No fullscreen support for import pages");
        
        return null;
    }
    
    public void on_unmounted(Object source, AsyncResult aresult) {
        debug("on_unmounted");

        Mount mount = (Mount) source;
        try {
            mount.unmount_finish(aresult);
            debug("unmounted");
        } catch (Error err) {
            // TODO: Better error reporting
            debug("%s", err.message);
            
            return;
        }

        // now with camera unmounted, refresh the view
        refresh_camera();
    }

    public RefreshResult refresh_camera() {
        if (busy)
            return RefreshResult.BUSY;
            
        refreshed = false;
        
        refreshError = null;
        refreshResult = camera.init(init_context.context);
        if (refreshResult != GPhoto.Result.OK)
            return (refreshResult == GPhoto.Result.IO_LOCK) ? RefreshResult.LOCKED : RefreshResult.LIBRARY_ERROR;
        
        busy = true;
        fileCount = 0;
        completedCount = 0;
        
        importSelectedButton.sensitive = false;
        importAllButton.sensitive = false;
        
        progressBar.set_fraction(0.0);

        GPhoto.CameraStorageInformation *sifs = null;
        int count = 0;
        refreshResult = camera.get_storageinfo(&sifs, out count, init_context.context);
        if (refreshResult == GPhoto.Result.OK) {
            remove_all();
            refresh();
            
            GPhoto.CameraStorageInformation *ifs = sifs;
            for (int ctr = 0; ctr < count; ctr++, ifs++) {
                string basedir = "/";
                if ((ifs->fields & GPhoto.CameraStorageInfoFields.BASE) != 0)
                    basedir = ifs->basedir;
                
                if (!load_preview(basedir))
                    break;
            }
        }

        GPhoto.Result res = camera.exit(init_context.context);
        if (res != GPhoto.Result.OK) {
            // log but don't fail
            message("Unable to unlock camera: %s (%d)", res.as_string(), (int) res);
        }
        
        importSelectedButton.sensitive = get_selected_count() > 0;
        importAllButton.sensitive = get_count() > 0;
        
        progressBar.set_text("");
        progressBar.set_fraction(0.0);

        busy = false;

        if (refreshResult != GPhoto.Result.OK) {
            refreshed = false;
            
            // show 'em all or show none
            remove_all();
            refresh();
            
            return (refreshResult == GPhoto.Result.IO_LOCK) ? RefreshResult.LOCKED : RefreshResult.LIBRARY_ERROR;
        }
        
        refreshed = true;

        return RefreshResult.OK;
    }
    
    private bool load_preview(owned string dir) {
        debug("Searching %s", dir);
        
        GPhoto.CameraList files;
        refreshResult = GPhoto.CameraList.create(out files);
        if (refreshResult != GPhoto.Result.OK)
            return false;
            
        refreshResult = camera.list_files(dir, files, loading_context.context);
        if (refreshResult != GPhoto.Result.OK)
            return false;
        
        // TODO: It *may* be more desireable to count files prior to importing them so the progress
        // bar is more accurate during import.  Otherwise, when one filesystem is completed w/ a
        // progress of 100%, the bar will reset to something lower as it traverses the next
        fileCount += files.count();
        
        uint8[] buffer = new uint8[64 * 1024];
        
        for (int ctr = 0; ctr < files.count(); ctr++) {
            string filename;
            refreshResult = files.get_name(ctr, out filename);
            if (refreshResult != GPhoto.Result.OK)
                return false;
            
            try {
                GPhoto.CameraFileInfo info;
                GPhoto.get_info(loading_context.context, camera, dir, filename, out info);
                
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
                
                Gdk.Pixbuf pixbuf = GPhoto.load_preview(loading_context.context, camera, dir, filename, buffer);
                Exif.Data exif = GPhoto.load_exif(loading_context.context, camera, dir, filename, buffer);
                
                ImportPreview preview = new ImportPreview(this, pixbuf, exif, dir, filename);
                add_item(preview);
            
                refresh();
                
                completedCount++;
                progressBar.set_fraction((double) completedCount / (double) fileCount);
                
                // spin the event loop so the UI doesn't freeze
                // TODO: Background thread
                while (Gtk.events_pending()) {
                    if (Gtk.main_iteration()) {
                        debug("Gtk.main_quit called");
                        
                        return false;
                    }
                }
            } catch (GPhotoError err) {
                refreshError = err.message;
                
                return false;
            }
        }
        
        GPhoto.CameraList folders;
        refreshResult = GPhoto.CameraList.create(out folders);
        if (refreshResult != GPhoto.Result.OK)
            return false;

        refreshResult = camera.list_folders(dir, folders, loading_context.context);
        if (refreshResult != GPhoto.Result.OK)
            return false;
        
        if (!dir.has_suffix("/"))
            dir = dir + "/";
        
        for (int ctr = 0; ctr < folders.count(); ctr++) {
            string subdir;
            refreshResult = folders.get_name(ctr, out subdir);
            if (refreshResult != GPhoto.Result.OK)
                return false;

            if (!load_preview(dir + subdir))
                return false;
        }
        
        return true;
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
        File photos_dir = AppWindow.get_photos_dir();

        GPhoto.Result res = camera.init(init_context.context);
        if (res != GPhoto.Result.OK) {
            AppWindow.error_message("Unable to lock camera: %s".printf(res.as_string()));
            
            return;
        }
        
        busy = true;
        importSelectedButton.sensitive = false;
        importAllButton.sensitive = false;
        
        ProgressBarContext saving_context = new ProgressBarContext(progressBar, "");
        GPhoto.Context null_context = new GPhoto.Context();
        
        AppWindow.get_instance().start_import_batch();
        try {
            foreach (LayoutItem item in items) {
                ImportPreview preview = (ImportPreview) item;
                
                // XXX: There is a condition in libgphoto where a dirty flag isn't being set on a directory
                // object and it's not updated from the camera, which means the file won't be found.
                // This forces a refresh of the folder.
                GPhoto.CameraList files;
                res = GPhoto.CameraList.create(out files);
                assert(res == GPhoto.Result.OK);
                
                res = camera.list_files(preview.folder, files, null_context);
                if (res != GPhoto.Result.OK) {
                    // log message and continue
                    debug("Unable to list files for %s: %d %s", preview.folder, (int) res, res.as_string());
                }
                
                GPhoto.CameraList folders;
                res = GPhoto.CameraList.create(out folders);
                assert(res == GPhoto.Result.OK);
                
                res = camera.list_folders(preview.folder, folders, null_context);
                if (res != GPhoto.Result.OK) {
                    // log and continue
                    debug("Unable to list folders for %s: %d %s", preview.folder, (int) res, res.as_string());
                }
        
                // TODO: Currently, files are stored flat in the directory and imported photos will
                // overwrite ones with the same name
                File dest_file = photos_dir.get_child(preview.filename);
                
                saving_context.set_message("Importing %s".printf(preview.filename));
                
                try {
                    GPhoto.save_image(saving_context.context, camera, preview.folder, preview.filename,
                        dest_file);
                } catch (Error err) {
                    // TODO: Give user option to cancel operation entirely
                    AppWindow.error_message("Unable to import %s: %s".printf(preview.filename, err.message));
                    
                    continue;
                }
                
                AppWindow.get_instance().import(dest_file);

                // have to do this because of bug: return will skip finally block
                bool quit = false;
                while (Gtk.events_pending()) {
                    if (Gtk.main_iteration()) {
                        // Gtk.main_quit was called, abort out to exit
                        quit = true;
                    }
                }
                
                if (quit)
                    break;
            }
        } finally {
            importSelectedButton.sensitive = get_selected_count() > 0;
            importAllButton.sensitive = get_count() > 0;
            saving_context.set_message("");
            
            AppWindow.get_instance().end_import_batch();

            res = camera.exit(init_context.context);
            if (res != GPhoto.Result.OK) {
                // log but don't fail
                message("Unable to unlock camera: %s (%d)", res.as_string(), (int) res);
            }

            busy = false;
        }
    }
}

