/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

class ImportPreview : LayoutItem, PhotoSource {
    public const int MAX_SCALE = 128;
    public const Gdk.InterpType INTERP = Gdk.InterpType.BILINEAR;
    
    public int fsid;
    public string folder;
    public string filename;
    public ulong file_size;
    public Exif.Data exif;
    
    public ImportPreview(Gdk.Pixbuf pixbuf, Exif.Data exif, int fsid, string folder, string filename,
        ulong file_size) {
        this.fsid = fsid;
        this.folder = folder;
        this.filename = filename;
        this.file_size = file_size;
        this.exif = exif;
        
        Orientation orientation = Orientation.TOP_LEFT;
        
        Exif.Entry entry = Exif.find_first_entry(exif, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry != null) {
            int o = Exif.Convert.get_short(entry.data, exif.get_byte_order());
            if (o >= (int) Orientation.MIN && o <= (int) Orientation.MAX)
                orientation = (Orientation) o;
        }

        set_title(filename);
        
        // scale down pixbuf if necessary
        Gdk.Pixbuf scaled = pixbuf;
        if (pixbuf.get_width() > MAX_SCALE || pixbuf.get_height() > MAX_SCALE)
            scaled = scale_pixbuf(pixbuf, MAX_SCALE, INTERP);

        // honor rotation and display
        set_image(orientation.rotate_pixbuf(scaled));
    }

    public time_t get_exposure_time() {
        time_t exposure_time;
        if (!Exif.get_timestamp(exif, out exposure_time))
            exposure_time = 0;
        return exposure_time;
    }

    public uint64 get_filesize() {
        return file_size;   
    }

    public Dimensions get_dimensions() { 
        Dimensions dimensions;
        if (!Exif.get_dimensions(exif, out dimensions))
            dimensions = Dimensions(0,0);
        return dimensions;
    }

    public Exif.Data? get_exif() {
        return exif;
    }
}

public class ImportPage : CheckerboardPage {
    private class ImportFile {
        public int fsid;
        public string dir;
        public string filename;
        public ulong file_size;
        public ulong preview_size;
        
        public ImportFile(int fsid, string dir, string filename, ulong file_size, ulong preview_size) {
            this.fsid = fsid;
            this.dir = dir;
            this.filename = filename;
            this.file_size = file_size;
            this.preview_size = preview_size;
        }
    }
    
    private class CameraImportJob : BatchImportJob {
        private GPhoto.ContextWrapper context;
        private GPhoto.Camera camera;
        private string dir;
        private string filename;
        private ulong file_size;
        private time_t exposure_time;
        private File dest_file;
        
        public CameraImportJob(GPhoto.ContextWrapper context, GPhoto.Camera camera, string dir, 
            string filename, ulong file_size, time_t exposure_time, File dest_file) {
            this.context = context;
            this.camera = camera;
            this.dir = dir;
            this.filename = filename;
            this.file_size = file_size;
            this.exposure_time = exposure_time;
            this.dest_file = dest_file;
        }
        
        public time_t get_exposure_time() {
            return exposure_time;
        }
        
        public override string get_identifier() {
            return filename;
        }
        
        public override bool prepare(out File file_to_import, out bool copy_to_library) {
            try {
                GPhoto.save_image(context.context, camera, dir, filename, dest_file);
            } catch (Error err) {
                return false;
            }
            
            file_to_import = dest_file;
            copy_to_library = false;
            
            return true;
        }
    }
    
    private class CameraImportComparator : Comparator<CameraImportJob> {
        public override int64 compare(CameraImportJob a, CameraImportJob b) {
            return (int64) a.get_exposure_time() - (int64) b.get_exposure_time();
        }
    }
    
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.Label camera_label = new Gtk.Label(null);
    private Gtk.ToolButton import_selected_button;
    private Gtk.ToolButton import_all_button;
    private Gtk.ProgressBar progress_bar = new Gtk.ProgressBar();
    private GPhoto.Camera camera;
    private GPhoto.ContextWrapper null_context = new GPhoto.ContextWrapper();
    private string uri;
    private bool busy = false;
    private bool refreshed = false;
    private GPhoto.Result refresh_result = GPhoto.Result.OK;
    private string refresh_error = null;
    private string camera_name;
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, on_file_menu },
        { "ImportSelected", Resources.IMPORT, "Import _Selected", null, null, on_import_selected },
        { "ImportAll", Resources.IMPORT_ALL, "Import _All", null, null, on_import_all },
        
        { "EditMenu", null, "_Edit", null, null, on_edit_menu },
        { "SelectAll", Gtk.STOCK_SELECT_ALL, "Select _All", "<Ctrl>A", "Select all the photos for importing",
            on_select_all },
        
        { "ViewMenu", null, "_View", null, null, null },

        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    public enum RefreshResult {
        OK,
        BUSY,
        LOCKED,
        LIBRARY_ERROR
    }
    
    public ImportPage(GPhoto.Camera camera, string uri) {
        base("Camera");
        camera_name = "Camera";
        
        this.camera = camera;
        this.uri = uri;
        
        init_ui("import.ui", "/ImportMenuBar", "ImportActionGroup", ACTIONS);
        
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
        progress_bar.visible = false;
        Gtk.ToolItem progress_item = new Gtk.ToolItem();
        progress_item.add(progress_bar);
        
        toolbar.insert(progress_item, -1);

        import_selected_button = new Gtk.ToolButton.from_stock(Resources.IMPORT);
        import_selected_button.set_label("Import Selected");
        import_selected_button.set_tooltip_text("Import the selected photos into your library");
        import_selected_button.clicked += on_import_selected;
        import_selected_button.sensitive = false;
        
        toolbar.insert(import_selected_button, -1);
        
        import_all_button = new Gtk.ToolButton.from_stock(Resources.IMPORT_ALL);
        import_all_button.set_label("Import All");
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
            
            set_page_name(camera_name);
        }

        show_all();
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
    
    public override void on_selection_changed(int count) {
        import_selected_button.sensitive = !busy && refreshed && (count > 0);
    }
    
    public override LayoutItem? get_fullscreen_photo() {
        error("No fullscreen support for import pages");
        
        return null;
    }
    
    public override void switched_to() {
        base.switched_to();
        
        try_refreshing_camera();
    }

    private void try_refreshing_camera() {
        // if camera has been refreshed or is in the process of refreshing, go no further
        if (refreshed || busy)
            return;
        
        RefreshResult res = refresh_camera();
        switch (res) {
            case ImportPage.RefreshResult.OK:
            case ImportPage.RefreshResult.BUSY:
                // nothing to report; if busy, let it continue doing its thing
                // (although earlier check should've caught this)
            break;
            
            case ImportPage.RefreshResult.LOCKED:
                // if locked because it's mounted, offer to unmount
                debug("Checking if %s is mounted ...", uri);

                File uri = File.new_for_uri(uri);

                Mount mount = null;
                try {
                    mount = uri.find_enclosing_mount(null);
                } catch (Error err) {
                    // error means not mounted
                }
                
                if (mount != null) {
                    // it's mounted, offer to unmount for the user
                    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(), 
                        Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION,
                        Gtk.ButtonsType.YES_NO,
                        "The camera is locked for use as a mounted drive.  "
                        + "Shotwell can only access the camera when it's unlocked.  "
                        + "Do you want Shotwell to unmount it for you?");
                    dialog.title = Resources.APP_TITLE;
                    int dialog_res = dialog.run();
                    dialog.destroy();
                    
                    if (dialog_res != Gtk.ResponseType.YES) {
                        set_page_message("Please unmount the camera.");
                        refresh();
                    } else {
                        unmount_camera(mount);
                    }
                } else {
                    // it's not mounted, so another application must have it locked
                    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(),
                        Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING,
                        Gtk.ButtonsType.OK,
                        "The camera is locked by another application.  "
                        + "Shotwell can only access the camera when it's unlocked.  "
                        + "Please close any other application using the camera and try again.");
                    dialog.title = Resources.APP_TITLE;
                    dialog.run();
                    dialog.destroy();
                    
                    set_page_message("Please close any other application using the camera.");
                    refresh();
                }
            break;
            
            case ImportPage.RefreshResult.LIBRARY_ERROR:
                AppWindow.error_message("Unable to fetch previews from the camera:\n%s".printf(
                    get_refresh_message()));
            break;
            
            default:
                error("Unknown result type %d", (int) res);
            break;
        }
    }
    
    public bool unmount_camera(Mount mount) {
        if (busy)
            return false;
            
        busy = true;
        refreshed = false;
        progress_bar.visible = true;
        progress_bar.set_fraction(0.0);
        progress_bar.set_text("Unmounting ...");

        debug("Unmounting camera ...");
        mount.unmount(MountUnmountFlags.NONE, null, on_unmounted);
        
        return true;
    }

    private void on_unmounted(Object source, AsyncResult aresult) {
        debug("Unmount complete");
        
        Mount mount = (Mount) source;
        try {
            mount.unmount_finish(aresult);
        } catch (Error err) {
            AppWindow.error_message("Unable to unmount camera.  Try dismounting the camera from the "
                + "file manager.");
            
            return;
        }
        
        // XXX: iPhone/iPod returns a USB error if a camera_init() is done too quickly after an
        // unmount.  A 50ms sleep gives it time to reorient itself.
        Thread.usleep(50000);
        
        busy = false;
        progress_bar.set_text("");
        progress_bar.visible = false;
        
        try_refreshing_camera();
    }
    
    private RefreshResult refresh_camera() {
        if (busy)
            return RefreshResult.BUSY;
            
        refreshed = false;
        
        refresh_error = null;
        refresh_result = camera.init(null_context.context);
        if (refresh_result != GPhoto.Result.OK)
            return (refresh_result == GPhoto.Result.IO_LOCK) ? RefreshResult.LOCKED : RefreshResult.LIBRARY_ERROR;
        
        busy = true;
        
        import_selected_button.sensitive = false;
        import_all_button.sensitive = false;
        
        Gee.ArrayList<ImportFile> file_list = new Gee.ArrayList<ImportFile>();
        ulong total_bytes = 0;
        ulong total_preview_bytes = 0;
        
        progress_bar.set_text("Fetching photo information");
        progress_bar.set_fraction(0.0);
        progress_bar.set_pulse_step(0.01);
        progress_bar.visible = true;

        GPhoto.CameraStorageInformation *sifs = null;
        int count = 0;
        refresh_result = camera.get_storageinfo(&sifs, out count, null_context.context);
        if (refresh_result == GPhoto.Result.OK) {
            remove_all();
            refresh();
            
            for (int fsid = 0; fsid < count; fsid++) {
                if (!enumerate_files(fsid, "/", file_list, out total_bytes, out total_preview_bytes))
                    break;
            }
        }
        
        load_previews(file_list, total_preview_bytes);
        
        progress_bar.visible = false;
        progress_bar.set_text("");
        progress_bar.set_fraction(0.0);

        GPhoto.Result res = camera.exit(null_context.context);
        if (res != GPhoto.Result.OK) {
            // log but don't fail
            message("Unable to unlock camera: %s (%d)", res.as_string(), (int) res);
        }
        
        import_selected_button.sensitive = get_selected_count() > 0;
        import_all_button.sensitive = get_count() > 0;
        
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
        GPhoto.Result res = camera.get_storageinfo(&sifs, out count, null_context.context);
        if (res != GPhoto.Result.OK)
            return null;
        
        if (fsid >= count)
            return null;
        
        GPhoto.CameraStorageInformation *ifs = sifs + fsid;
        
        return (ifs->fields & GPhoto.CameraStorageInfoFields.BASE) != 0 ? ifs->basedir : "/";
    }
    
    private string? get_fulldir(int fsid, string dir) {
        string basedir = get_fs_basedir(fsid);
        if (basedir == null) {
            debug("Unable to find base directory for fsid %d", fsid);
            
            return null;
        }
        
        if (!basedir.has_suffix("/") && !dir.has_prefix("/"))
            basedir += "/";
        
        return basedir + dir;
    }
    
    private bool enumerate_files(int fsid, string dir, Gee.ArrayList<ImportFile> file_list, 
        out ulong total_bytes, out ulong total_preview_bytes) {
        string fulldir = get_fulldir(fsid, dir);
        if (fulldir == null)
            return false;
        
        GPhoto.CameraList files;
        refresh_result = GPhoto.CameraList.create(out files);
        if (refresh_result != GPhoto.Result.OK)
            return false;
        
        refresh_result = camera.list_files(fulldir, files, null_context.context);
        if (refresh_result != GPhoto.Result.OK)
            return false;
        
        for (int ctr = 0; ctr < files.count(); ctr++) {
            string filename;
            refresh_result = files.get_name(ctr, out filename);
            if (refresh_result != GPhoto.Result.OK)
                return false;
            
            try {
                GPhoto.CameraFileInfo info;
                GPhoto.get_info(null_context.context, camera, fulldir, filename, out info);
                
                // at this point, only interested in JPEG files
                // TODO: Increase file format support, for TIFF and RAW at least
                if ((info.file.fields & GPhoto.CameraFileInfoFields.TYPE) == 0) {
                    message("Skipping %s/%s: No file (file=%02Xh)", fulldir, filename,
                        info.file.fields);
                        
                    continue;
                }
                
                if (info.file.type != GPhoto.MIME.JPEG) {
                    message("Skipping %s/%s: Not a JPEG (%s)", fulldir, filename, info.file.type);
                        
                    continue;
                }
                
                ulong preview_size = info.preview.size;
                
                // skip preview if it isn't JPEG
                // TODO: Accept previews if of any type recognized by Gdk.Pixbuf
                if (preview_size != 0) {
                    if ((info.preview.fields & GPhoto.CameraFileInfoFields.TYPE) != 0
                        && info.preview.type != GPhoto.MIME.JPEG) {
                        message("Not previewing %s/%s: Not a JPEG preview (%s)", fulldir, filename, 
                            info.preview.type);
                    
                        preview_size = 0;
                    }
                }
                
                ImportFile import_file = new ImportFile(fsid, dir, filename, info.file.size,
                    preview_size);
                
                file_list.add(import_file);
                total_bytes += info.file.size;
                total_preview_bytes += (preview_size != 0) ? preview_size : info.file.size;
                
                progress_bar.pulse();
                
                // spin the event loop so the UI doesn't freeze
                if (!spin_event_loop())
                    return false;
            } catch (Error err) {
                refresh_error = err.message;
                
                return false;
            }
        }
        
        GPhoto.CameraList folders;
        refresh_result = GPhoto.CameraList.create(out folders);
        if (refresh_result != GPhoto.Result.OK)
            return false;

        refresh_result = camera.list_folders(fulldir, folders, null_context.context);
        if (refresh_result != GPhoto.Result.OK)
            return false;
        
        for (int ctr = 0; ctr < folders.count(); ctr++) {
            string subdir;
            refresh_result = folders.get_name(ctr, out subdir);
            if (refresh_result != GPhoto.Result.OK)
                return false;
            
            string recurse_dir = null;
            if (!dir.has_suffix("/") && !subdir.has_prefix("/"))
                recurse_dir = dir + "/" + subdir;
            else
                recurse_dir = dir + subdir;

            if (!enumerate_files(fsid, recurse_dir, file_list, out total_bytes, out total_preview_bytes))
                return false;
        }
        
        return true;
    }
    
    private void load_previews(Gee.ArrayList<ImportFile> file_list, ulong total_preview_bytes) {
        ulong bytes = 0;
        try {
            foreach (ImportFile import_file in file_list) {
                string fulldir = get_fulldir(import_file.fsid, import_file.dir);
                if (fulldir == null)
                    continue;
                
                progress_bar.set_text("Fetching preview for %s".printf(import_file.filename));
                
                // if no preview, load full image for preview
                Gdk.Pixbuf pixbuf = null;
                if (import_file.preview_size > 0)
                    pixbuf = GPhoto.load_preview(null_context.context, camera, fulldir, 
                        import_file.filename);
                else
                    pixbuf = GPhoto.load_image(null_context.context, camera, fulldir,
                        import_file.filename);
                        
                Exif.Data exif = GPhoto.load_exif(null_context.context, camera, fulldir, 
                    import_file.filename);
                
                bytes += (import_file.preview_size != 0) ? import_file.preview_size : import_file.file_size;
                progress_bar.set_fraction((double) bytes / (double) total_preview_bytes);
                
                ImportPreview preview = new ImportPreview(pixbuf, exif, import_file.fsid, import_file.dir, 
                    import_file.filename, import_file.file_size);
                add_item(preview);
            
                refresh();
                
                // spin the event loop so the UI doesn't freeze
                if (!spin_event_loop())
                    break;
            }
        } catch (Error err) {
            AppWindow.error_message("Error while fetching previews from %s: %s".printf(camera_name,
                err.message));
        }
    }
    
    private void on_file_menu() {
        set_item_sensitive("/ImportMenuBar/FileMenu/ImportSelected", !busy && (get_selected_count() > 0));
        set_item_sensitive("/ImportMenuBar/FileMenu/ImportAll", !busy && (get_count() > 0));
    }
    
    private void on_import_selected() {
        import(get_selected());
    }
    
    private void on_import_all() {
        import(get_items());
    }
    
    private void on_edit_menu() {
        set_item_sensitive("/ImportMenuBar/EditMenu/SelectAll", !busy && (get_count() > 0));
    }
    
    private void on_select_all() {
        select_all();
    }
    
    private void import(Gee.Iterable<LayoutItem> items) {
        GPhoto.Result res = camera.init(null_context.context);
        if (res != GPhoto.Result.OK) {
            AppWindow.error_message("Unable to lock camera: %s".printf(res.as_string()));
            
            return;
        }
        
        busy = true;
        import_selected_button.sensitive = false;
        import_all_button.sensitive = false;
        progress_bar.visible = false;

        int failed = 0;
        ulong total_bytes = 0;
        SortedList<CameraImportJob> jobs = new SortedList<CameraImportJob>(new CameraImportComparator());
        
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
            
            bool collision;
            File dest_file = BatchImport.create_library_path(preview.filename, preview.exif, time_t(),
                out collision);
            if (dest_file == null) {
                message("Unable to generate local file for %s/%s", dir, preview.filename);
                failed++;
                
                continue;
            }
            
            time_t exposure_time;
            if (!Exif.get_timestamp(preview.exif, out exposure_time))
                exposure_time = 0;
            
            jobs.add(new CameraImportJob(null_context, camera, dir, preview.filename, 
                preview.file_size, exposure_time, dest_file));
            total_bytes += preview.file_size;
        }

        if (failed > 0) {
            // TODO: I18N
            string plural = (failed > 1) ? "s" : "";
            AppWindow.error_message("Unable to import %d photo%s from the camera due to fatal error%s.".printf(
                failed, plural, plural));
        }
        
        if (jobs.size > 0) {
            BatchImport batch_import = new BatchImport(jobs, camera_name, total_bytes);
            batch_import.import_job_failed += on_import_job_failed;
            batch_import.import_complete += close_import;
            LibraryWindow.get_app().enqueue_batch_import(batch_import);
            LibraryWindow.get_app().switch_to_import_queue_page();
            // camera.exit() and busy flag will be handled when the batch import completes
        } else {
            close_import();
        }
    }
    
    private void on_import_job_failed(ImportResult result, BatchImportJob job, File? file) {
        if (file == null || result == ImportResult.SUCCESS)
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
        
        GPhoto.Result res = camera.exit(null_context.context);
        if (res != GPhoto.Result.OK) {
            // log but don't fail
            message("Unable to unlock camera: %s (%d)", res.as_string(), (int) res);
        }

        busy = false;
    }
}

public class ImportQueuePage : SinglePhotoPage {
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton stop_button = null;
    private Gee.ArrayList<BatchImport> queue = new Gee.ArrayList<BatchImport>();
    private BatchImport current_batch = null;
    private Gtk.ProgressBar progress_bar = new Gtk.ProgressBar();
    private uint64 progress_bytes = 0;
    private uint64 total_bytes = 0;
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, on_file_menu },
        { "Stop", Gtk.STOCK_STOP, "_Stop Import", null, "Stop importing photos", on_stop },
        
        { "ViewMenu", null, "_View", null, null, null },
        
        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    public ImportQueuePage() {
        base("Importing ...");
        
        init_ui("import_queue.ui", "/ImportQueueMenuBar", "ImportQueueActionGroup", ACTIONS);
        
        stop_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_STOP);
        stop_button.set_tooltip_text("Stop importing photos");
        stop_button.clicked += on_stop;
        stop_button.sensitive = false;
        
        toolbar.insert(stop_button, -1);

        // separator to force progress bar to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        Gtk.ToolItem progress_item = new Gtk.ToolItem();
        progress_item.add(progress_bar);
        
        toolbar.insert(progress_item, -1);
   }
    
    public signal void batch_added(BatchImport batch_import);
    
    public signal void batch_removed(BatchImport batch_import);
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public void enqueue_and_schedule(BatchImport batch_import) {
        total_bytes += batch_import.get_total_bytes();
        
        batch_import.starting += on_starting;
        batch_import.imported += on_imported;
        batch_import.import_complete += on_import_complete;
        
        queue.add(batch_import);
        batch_added(batch_import);

        if (queue.size == 1)
            batch_import.schedule();
        
        stop_button.sensitive = true;
    }
    
    public int get_batch_count() {
        return queue.size;
    }
    
    private void on_file_menu() {
        set_item_sensitive("/ImportQueueMenuBar/FileMenu/Stop", queue.size > 0);
    }
    
    private void on_stop() {
        // mark all as halted and let each signal failure
        foreach (BatchImport batch_import in queue)
            batch_import.user_halt();
    }
    
    private void on_starting(BatchImport batch_import) {
        current_batch = batch_import;
    }
    
    private void on_imported(LibraryPhoto photo) {
        set_pixbuf(photo.get_pixbuf(TransformablePhoto.SCREEN));
        
        progress_bytes += photo.get_filesize();
        double pct = (progress_bytes <= total_bytes) ? (double) progress_bytes / (double) total_bytes
            : 0.0;
        
        progress_bar.set_text("Imported %s".printf(photo.get_name()));
        progress_bar.set_fraction(pct);
    }
    
    private void on_import_complete(BatchImport batch_import, ImportID import_id, 
        SortedList<LibraryPhoto> imported, Gee.ArrayList<string> failed, Gee.ArrayList<string> skipped) {
        assert(batch_import == current_batch);
        current_batch = null;
        
        bool removed = queue.remove(batch_import);
        assert(removed);
        
        if (failed.size > 0 || skipped.size > 0)
            LibraryWindow.report_import_failures(batch_import.get_name(), failed, skipped);
        
        batch_removed(batch_import);
        
        // schedule next if available
        if (queue.size > 0) {
            stop_button.sensitive = true;
            queue.get(0).schedule();
        } else {
            stop_button.sensitive = false;
        }
    }

    public override Gee.Iterable<Queryable>? get_queryables() {
        return null;
    }

    public override Gee.Iterable<Queryable>? get_selected_queryables() {
        return get_queryables();
    }
}
