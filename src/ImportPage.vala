
class ImportPreview : LayoutItem {
    public int fsid;
    public string folder;
    public string filename;
    public Exif.Data exif;
    
    public ImportPreview(Gdk.Pixbuf pixbuf, Exif.Data exif, int fsid, string folder, string filename) {
        this.fsid = fsid;
        this.folder = folder;
        this.filename = filename;
        this.exif = exif;
        
        Orientation orientation = Orientation.TOP_LEFT;
        
        Exif.Entry entry = Exif.find_first_entry(exif, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry != null) {
            int o = Exif.Convert.get_short(entry.data, exif.get_byte_order());
            if (o >= (int) Orientation.MIN && o <= (int) Orientation.MAX)
                orientation = (Orientation) o;
        }

        title.set_text(filename);

        Gdk.Pixbuf rotated = orientation.rotate_pixbuf(pixbuf);
        image.set_from_pixbuf(rotated);
    }
}

class ProgressBarContext {
    public GPhoto.Context context = new GPhoto.Context();
    
    private Gtk.ProgressBar progress_bar;
    private string msg;
    private float task_target = 0.0;
    
    public ProgressBarContext(Gtk.ProgressBar progress_bar, string msg) {
        this.progress_bar = progress_bar;
        this.msg = msg;

        context.set_idle_func(on_idle);
        context.set_error_func(on_error);
        context.set_status_func(on_status);
        context.set_message_func(on_message);
        context.set_progress_funcs(on_progress_start, on_progress_update, on_progress_stop);
    }
    
    public void set_message(string msg) {
        this.msg = msg;
        progress_bar.set_text(msg);
    }

    private void on_idle() {
        spin_event_loop();
    }
    
    private void on_error(GPhoto.Context context, string format, void *va_list) {
    }
    
    private void on_status(GPhoto.Context context, string format, void *va_list) {
    }
    
    private void on_message(GPhoto.Context context, string format, void *va_list) {
    }
    
    private uint on_progress_start(GPhoto.Context context, float target, string format, void *va_list) {
        task_target = target;
        progress_bar.set_fraction(0.0);
        progress_bar.set_text(msg);
        
        return 0;
    }
    
    private void on_progress_update(GPhoto.Context context, uint id, float current) {
        progress_bar.set_fraction(current / task_target);
        progress_bar.set_text(msg);

        spin_event_loop();
    }
    
    private void on_progress_stop(GPhoto.Context context, uint id) {
        progress_bar.set_fraction(0.0);
        progress_bar.set_text("");
    }
}

public class ImportPage : CheckerboardPage {
    private class CameraImportJob : BatchImportJob {
        private ProgressBarContext context;
        private GPhoto.Camera camera;
        private string dir;
        private string filename;
        private File dest_file;
        
        public CameraImportJob(ProgressBarContext context, GPhoto.Camera camera, string dir, 
            string filename, File dest_file) {
            this.context = context;
            this.camera = camera;
            this.dir = dir;
            this.filename = filename;
            this.dest_file = dest_file;
        }
        
        public override string get_identifier() {
            return filename;
        }
        
        public override bool prepare(out File file_to_import) {
            context.set_message("Copying %s to photo library".printf(filename));
            
            try {
                GPhoto.save_image(context.context, camera, dir, filename, dest_file);
            } catch (Error err) {
                return false;
            }
            
            file_to_import = dest_file;
            
            return true;
        }
    }
    
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.Label camera_label = new Gtk.Label(null);
    private Gtk.ToolButton import_selected_button;
    private Gtk.ToolButton import_all_button;
    private Gtk.ProgressBar progress_bar = new Gtk.ProgressBar();
    private GPhoto.Camera camera;
    private string uri;
    private ProgressBarContext init_context = null;
    private ProgressBarContext loading_context = null;
    private ProgressBarContext saving_context = null;
    private bool busy = false;
    private bool refreshed = false;
    private GPhoto.Result refresh_result = GPhoto.Result.OK;
    private string refresh_error = null;
    private int file_count = 0;
    private int completed_count = 0;
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
        
        init_context = new ProgressBarContext(progress_bar, "Initializing camera ...");
        loading_context =  new ProgressBarContext(progress_bar, "Fetching photo previews ..");
        saving_context = new ProgressBarContext(progress_bar, "");
        
        // toolbar
        // Camera label
        Gtk.ToolItem camera_label_item = new Gtk.ToolItem();
        camera_label_item.add(camera_label);

        toolbar.insert(camera_label_item, -1);
        
        // separator to force buttons to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        progress_bar.set_orientation(Gtk.ProgressBarOrientation.LEFT_TO_RIGHT);
        Gtk.ToolItem progress_item = new Gtk.ToolItem();
        progress_item.add(progress_bar);
        
        toolbar.insert(progress_item, -1);

        import_selected_button = new Gtk.ToolButton(new Gtk.Label("Import Selected"), "");
        import_selected_button.set_tooltip_text("Import the selected photos into your library");
        import_selected_button.clicked += on_import_selected;
        import_selected_button.sensitive = false;
        
        toolbar.insert(import_selected_button, -1);
        
        import_all_button = new Gtk.ToolButton(new Gtk.Label("Import All"), "");
        import_all_button.set_tooltip_text("Import all the photos on this camera into your library");
        import_all_button.clicked += on_import_all;
        import_all_button.sensitive = false;
        
        toolbar.insert(import_all_button, -1);
        
        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        GPhoto.CameraAbilities abilities;
        GPhoto.Result res = camera.get_abilities(out abilities);
        if (res != GPhoto.Result.OK) {
            debug("[%d] Unable to get camera abilities: %s", (int) res, res.as_string());
        } else {
            camera_name = abilities.model;
            camera_label.set_text(abilities.model);
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
        if (refresh_error != null) {
            msg = refresh_error;
        } else if (refresh_result == GPhoto.Result.OK) {
            // all went well
        } else {
            msg = "%s (%d)".printf(refresh_result.as_string(), (int) refresh_result);
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
        import_selected_button.sensitive = !busy && refreshed && (count > 0);
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
        
        // XXX: iPhone/iPod returns a USB error if a camera_init() is done too quickly after an
        // unmount.  A 50ms sleep gives it time to reorient itself.
        Thread.usleep(50000);

        // now with camera unmounted, refresh the view
        RefreshResult res = refresh_camera();
        if (res != RefreshResult.OK) {
            string reason = null;
            switch (res) {
                case RefreshResult.LOCKED:
                    reason = "The camera is locked.";
                break;
                
                case RefreshResult.BUSY:
                    reason = "The camera is busy.";
                break;
                
                case RefreshResult.LIBRARY_ERROR:
                default:
                    reason = "The camera is unavailable at this time.";
                break;
            }
            
            AppWindow.error_message("Unable to unmount camera.  %s  Please try again.".printf(reason));
        }
    }
    
    public RefreshResult refresh_camera() {
        if (busy)
            return RefreshResult.BUSY;
            
        refreshed = false;
        
        refresh_error = null;
        refresh_result = camera.init(init_context.context);
        if (refresh_result != GPhoto.Result.OK)
            return (refresh_result == GPhoto.Result.IO_LOCK) ? RefreshResult.LOCKED : RefreshResult.LIBRARY_ERROR;
        
        busy = true;
        file_count = 0;
        completed_count = 0;
        
        import_selected_button.sensitive = false;
        import_all_button.sensitive = false;
        
        progress_bar.set_fraction(0.0);

        GPhoto.CameraStorageInformation *sifs = null;
        int count = 0;
        refresh_result = camera.get_storageinfo(&sifs, out count, init_context.context);
        if (refresh_result == GPhoto.Result.OK) {
            remove_all();
            refresh();
            
            GPhoto.CameraStorageInformation *ifs = sifs;
            for (int fsid = 0; fsid < count; fsid++, ifs++) {
                if (!load_preview(fsid, "/"))
                    break;
            }
        }

        GPhoto.Result res = camera.exit(init_context.context);
        if (res != GPhoto.Result.OK) {
            // log but don't fail
            message("Unable to unlock camera: %s (%d)", res.as_string(), (int) res);
        }
        
        import_selected_button.sensitive = get_selected_count() > 0;
        import_all_button.sensitive = get_count() > 0;
        
        progress_bar.set_text("");
        progress_bar.set_fraction(0.0);

        busy = false;

        if (refresh_result != GPhoto.Result.OK) {
            refreshed = false;
            
            // show 'em all or show none
            remove_all();
            refresh();
            
            return (refresh_result == GPhoto.Result.IO_LOCK) ? RefreshResult.LOCKED : RefreshResult.LIBRARY_ERROR;
        }
        
        refreshed = true;

        return RefreshResult.OK;
    }
    
    // Need to do this because some phones (iPhone, in particular) changes the name of their filesystem
    // between each mount
    private string? get_fs_basedir(int fsid) {
        GPhoto.CameraStorageInformation *sifs = null;
        int count = 0;
        GPhoto.Result res = camera.get_storageinfo(&sifs, out count, init_context.context);
        if (res != GPhoto.Result.OK)
            return null;
        
        if (fsid >= count)
            return null;
        
        GPhoto.CameraStorageInformation *ifs = sifs + fsid;
        
        return (ifs->fields & GPhoto.CameraStorageInfoFields.BASE) != 0 ? ifs->basedir : "/";
    }
    
    private bool load_preview(int fsid, owned string dir) {
        if (!dir.has_prefix("/"))
            dir = "/" + dir;
            
        string basedir = get_fs_basedir(fsid);
        if (basedir == null) {
            debug("Unable to find base directory for fsid %d", fsid);
            
            return false;
        }
            
        string fulldir = basedir + dir;
        
        GPhoto.CameraList files;
        refresh_result = GPhoto.CameraList.create(out files);
        if (refresh_result != GPhoto.Result.OK)
            return false;
            
        refresh_result = camera.list_files(fulldir, files, loading_context.context);
        if (refresh_result != GPhoto.Result.OK)
            return false;
        
        // TODO: It *may* be more desireable to count files prior to importing them so the progress
        // bar is more accurate during import.  Otherwise, when one filesystem is completed w/ a
        // progress of 100%, the bar will reset to something lower as it traverses the next
        file_count += files.count();
        
        uint8[] buffer = new uint8[64 * 1024];
        
        for (int ctr = 0; ctr < files.count(); ctr++) {
            string filename;
            refresh_result = files.get_name(ctr, out filename);
            if (refresh_result != GPhoto.Result.OK)
                return false;
            
            try {
                GPhoto.CameraFileInfo info;
                GPhoto.get_info(loading_context.context, camera, fulldir, filename, out info);
                
                // at this point, only interested in JPEG files with a JPEG preview
                if (((info.preview.fields & GPhoto.CameraFileInfoFields.TYPE) == 0)
                    || ((info.file.fields & GPhoto.CameraFileInfoFields.TYPE) == 0)) {
                    debug("Skipping %s/%s: No preview (preview=%02Xh file=%02Xh)", fulldir, filename,
                        info.preview.fields, info.file.fields);
                        
                    continue;
                }
                
                if ((info.preview.type != GPhoto.MIME.JPEG) || (info.file.type != GPhoto.MIME.JPEG)) {
                    debug("Skipping %s/%s: Not a JPEG (preview=%s file=%s)", fulldir, filename,
                        info.preview.type, info.file.type);
                        
                    continue;
                }
                
                Gdk.Pixbuf pixbuf = GPhoto.load_preview(loading_context.context, camera, fulldir, filename, 
                    buffer);
                Exif.Data exif = GPhoto.load_exif(loading_context.context, camera, fulldir, filename, 
                    buffer);
                
                ImportPreview preview = new ImportPreview(pixbuf, exif, fsid, dir, filename);
                add_item(preview);
            
                refresh();
                
                completed_count++;
                progress_bar.set_fraction((double) completed_count / (double) file_count);
                
                // spin the event loop so the UI doesn't freeze
                if (!spin_event_loop())
                    return false;
            } catch (GPhotoError err) {
                refresh_error = err.message;
                
                return false;
            }
        }
        
        GPhoto.CameraList folders;
        refresh_result = GPhoto.CameraList.create(out folders);
        if (refresh_result != GPhoto.Result.OK)
            return false;

        refresh_result = camera.list_folders(fulldir, folders, loading_context.context);
        if (refresh_result != GPhoto.Result.OK)
            return false;
        
        if (!dir.has_suffix("/"))
            dir = dir + "/";
        
        for (int ctr = 0; ctr < folders.count(); ctr++) {
            string subdir;
            refresh_result = folders.get_name(ctr, out subdir);
            if (refresh_result != GPhoto.Result.OK)
                return false;

            if (!load_preview(fsid, dir + subdir))
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
        GPhoto.Result res = camera.init(init_context.context);
        if (res != GPhoto.Result.OK) {
            AppWindow.error_message("Unable to lock camera: %s".printf(res.as_string()));
            
            return;
        }
        
        busy = true;
        import_selected_button.sensitive = false;
        import_all_button.sensitive = false;
        saving_context.set_message("");

        int failed = 0;
        Gee.ArrayList<CameraImportJob> jobs = new Gee.ArrayList<CameraImportJob>();
        
        foreach (LayoutItem item in items) {
            ImportPreview preview = (ImportPreview) item;
            
            string basedir = get_fs_basedir(preview.fsid);
            if (basedir == null) {
                debug("Unable to find basedir for fsid %d", preview.fsid);
                failed++;
                
                continue;
            }
            
            string dir = preview.folder;
            if (!dir.has_prefix("/"))
                dir = "/" + dir;
                
            dir = basedir + dir;
            
            debug("Importing %d %s %s", preview.fsid, dir, preview.filename);
            
            bool collision;
            File dest_file = BatchImport.create_library_path(preview.filename, preview.exif, time_t(),
                out collision);
            if (dest_file == null) {
                debug("Unable to generate local file for %s/%s", dir, preview.filename);
                failed++;
                
                continue;
            }
            
            jobs.add(new CameraImportJob(saving_context, camera, dir, preview.filename, dest_file));
        }

        if (failed > 0) {
            // TODO: I18N
            string plural = (failed > 1) ? "s" : "";
            AppWindow.error_message("Unable to import %d photo%s from the camera due to fatal error%s.".printf(
                failed, plural, plural));
        }
        
        if (jobs.size > 0) {
            BatchImport batch_import = new BatchImport(jobs);
            batch_import.import_complete += on_import_complete;
            batch_import.import_job_failed += on_import_job_failed;
            batch_import.schedule();
            // camera.exit() and busy flag will be handled when the batch import completes
        } else {
            close_import();
        }
    }
    
    private void on_import_complete(ImportID import_id, SortedList<Photo> photos,
        Gee.ArrayList<string> failed, Gee.ArrayList<string> skipped) {
        if (failed.size > 0 || skipped.size > 0)
            AppWindow.report_import_failures(failed, skipped);
        
        close_import();
    }
    
    private void on_import_job_failed(ImportResult result, BatchImportJob job, File? file) {
        if (file == null)
            return;
            
        // delete the copied file
        try {
            file.delete(null);
        } catch (Error err) {
            message("Unable to delete downloaded file %s: %s", file.get_path(), err.message);
        }
    }

    private void close_import() {
        import_selected_button.sensitive = get_selected_count() > 0;
        import_all_button.sensitive = get_count() > 0;
        saving_context.set_message("");
        
        GPhoto.Result res = camera.exit(init_context.context);
        if (res != GPhoto.Result.OK) {
            // log but don't fail
            message("Unable to unlock camera: %s (%d)", res.as_string(), (int) res);
        }

        busy = false;
    }
}

