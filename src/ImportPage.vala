/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_CAMERA

class ImportSource : PhotoSource {
    public const Gdk.InterpType INTERP = Gdk.InterpType.BILINEAR;

    private string camera_name;
    private GPhoto.Camera camera;
    private int fsid;
    private string folder;
    private string filename;
    private ulong file_size;
    private ulong preview_size;
    private Gdk.Pixbuf preview = null;
    private string preview_md5 = null;
    private Exif.Data exif = null;
    private string exif_md5 = null;
    
    public ImportSource(string camera_name, GPhoto.Camera camera, int fsid, string folder, string filename, 
        ulong file_size, ulong preview_size) {
        this.camera_name = camera_name;
        this.camera = camera;
        this.fsid = fsid;
        this.folder = folder;
        this.filename = filename;
        this.file_size = file_size;
        this.preview_size = preview_size;
    }
    
    public override string get_name() {
        return filename;
    }
    
    public override string to_string() {
        return "%s %s/%s".printf(camera_name, folder, filename);
    }
    
    // Needed because previews and exif are loaded after other information has been gathered.
    public void update(Gdk.Pixbuf preview, string preview_md5, Exif.Data exif, string exif_md5) {
        this.preview = preview;
        this.preview_md5 = preview_md5;
        this.exif = exif;
        this.exif_md5 = exif_md5;
    }
    
    public GPhoto.Camera get_camera() {
        return camera;
    }
    
    public string get_filename() {
        return filename;
    }
    
    public string get_fulldir() {
        return ImportPage.get_fulldir(camera, camera_name, fsid, folder);
    }
    
    public override time_t get_exposure_time() {
        time_t timestamp;
        if (!Exif.get_timestamp(exif, out timestamp))
            return 0;
            
        return timestamp;
    }

    public override Dimensions get_dimensions() {
        Dimensions dim;
        if (!Exif.get_dimensions(exif, out dim))
            return Dimensions(0, 0);
        
        return Exif.get_orientation(exif).rotate_dimensions(dim);
    }

    public override uint64 get_filesize() {
        return file_size;
    }

    public override Exif.Data? get_exif() {
        return exif;
    }
    
    public string get_exif_md5() {
        return exif_md5;
    }
    
    public override Gdk.Pixbuf get_pixbuf(Scaling scaling) throws Error {
        return scaling.perform_on_pixbuf(preview, INTERP, false);
    }
    
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return (scale > 0) ? scale_pixbuf(preview, scale, INTERP, true) : preview;
    }
    
    public string get_preview_md5() {
        return preview_md5;
    }
}

class ImportPreview : LayoutItem {
    public const int MAX_SCALE = 128;
    
    public ImportPreview(ImportSource source) {
        base(source, Dimensions());
        
        set_title(source.get_filename());
        
        // scale down pixbuf if necessary
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = source.get_thumbnail(0);
        } catch (Error err) {
            error("Unable to fetch loaded import preview for %s: %s", to_string(), err.message);
        }
        
        // scale down if too large
        if (pixbuf.get_width() > MAX_SCALE || pixbuf.get_height() > MAX_SCALE)
            pixbuf = scale_pixbuf(pixbuf, MAX_SCALE, ImportSource.INTERP, false);

        // honor rotation
        Orientation orientation = Exif.get_orientation(source.get_exif());
        set_image(orientation.rotate_pixbuf(pixbuf));
    }
    
    public bool is_already_imported() {
        ImportSource source = (ImportSource) get_source();
        
        bool exif_match = PhotoTable.get_instance().has_exif_md5(source.get_exif_md5());
        bool thumbnail_match = PhotoTable.get_instance().has_thumbnail_md5(source.get_preview_md5());
        
        return exif_match || thumbnail_match;
    }
}

public class ImportPage : CheckerboardPage {
    private class ImportViewManager : ViewManager {
        private ImportPage owner;
        
        public ImportViewManager(ImportPage owner) {
            this.owner = owner;
        }
        
        public override DataView create_view(DataSource source) {
            ImportPreview import_preview = new ImportPreview((ImportSource) source);
            import_preview.display_title(owner.display_titles());
            
            return import_preview;
        }
    }
    
    private class CameraImportJob : BatchImportJob {
        private GPhoto.ContextWrapper context;
        private ImportSource import_file;
        private File? dest_file;
        
        public CameraImportJob(GPhoto.ContextWrapper context, ImportSource import_file, File? dest_file) {
            this.context = context;
            this.import_file = import_file;
            this.dest_file = dest_file;
        }
        
        public time_t get_exposure_time() {
            return import_file.get_exposure_time();
        }
        
        public override string get_identifier() {
            return import_file.get_filename();
        }
        
        public ImportSource get_source() {
            return import_file;
        }
        
        public override bool prepare(out File file_to_import, out bool copy_to_library) {
            if (dest_file == null)
                return false;
            
            try {
                GPhoto.save_image(context.context, import_file.get_camera(), import_file.get_fulldir(),
                    import_file.get_filename(), dest_file);
            } catch (Error err) {
                warning("Unable to fetch photo from %s to %s: %s", import_file.to_string(), 
                    dest_file.get_path(), err.message);

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
    
    private static GPhoto.ContextWrapper null_context = null;

    private SourceCollection import_sources = new SourceCollection();
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.Label camera_label = new Gtk.Label(null);
    private Gtk.CheckButton hide_imported;
    private Gtk.ToolButton import_selected_button;
    private Gtk.ToolButton import_all_button;
    private Gtk.ProgressBar progress_bar = new Gtk.ProgressBar();
    private GPhoto.Camera camera;
    private string uri;
    private bool busy = false;
    private bool refreshed = false;
    private GPhoto.Result refresh_result = GPhoto.Result.OK;
    private string refresh_error = null;
    private string camera_name;

    public enum RefreshResult {
        OK,
        BUSY,
        LOCKED,
        LIBRARY_ERROR
    }
    
    public ImportPage(GPhoto.Camera camera, string uri) {
        base(_("Camera"));
        camera_name = _("Camera");

        this.camera = camera;
        this.uri = uri;
        
        // set up the global null context when needed
        if (null_context == null)
            null_context = new GPhoto.ContextWrapper();
        
        // monitor source collection to add/remove views
        get_view().monitor_source_collection(import_sources, new ImportViewManager(this));
        
        // monitor selection for UI
        get_view().items_state_changed += on_view_changed;
        get_view().contents_altered += on_view_changed;
        get_view().items_visibility_changed += on_view_changed;
        
        // monitor Photos for removals, at that will change the result of the ViewFilter
        LibraryPhoto.global.contents_altered += on_photos_added_removed;
        
        init_ui("import.ui", "/ImportMenuBar", "ImportActionGroup", create_actions(),
            create_toggle_actions());
        
        // toolbar
        // hide duplicates checkbox
        hide_imported = new Gtk.CheckButton.with_label(_("Hide photos already imported"));
        hide_imported.set_tooltip_text(_("Only display photos that have not been imported"));
        hide_imported.clicked += on_hide_imported;
        hide_imported.sensitive = false;
        hide_imported.active = false;
        Gtk.ToolItem hide_item = new Gtk.ToolItem();
        hide_item.add(hide_imported);
        
        toolbar.insert(hide_item, -1);
        
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
    
    ~ImportPage() {
        LibraryPhoto.global.contents_altered -= on_photos_added_removed;
    }

    private Gtk.ToggleActionEntry[] create_toggle_actions() {
        Gtk.ToggleActionEntry[] toggle_actions = new Gtk.ToggleActionEntry[0];

        Gtk.ToggleActionEntry titles = { "ViewTitle", null, TRANSLATABLE, "<Ctrl><Shift>T",
            TRANSLATABLE, on_display_titles, Config.get_instance().get_display_photo_titles() };
        titles.label = _("_Titles");
        titles.tooltip = _("Display the title of each photo");
        toggle_actions += titles;

        return toggle_actions;
    }

    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, on_file_menu };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry import_selected = { "ImportSelected", Resources.IMPORT,
            TRANSLATABLE, null, null, on_import_selected };
        import_selected.label = _("Import _Selected");
        actions += import_selected;

        Gtk.ActionEntry import_all = { "ImportAll", Resources.IMPORT_ALL, TRANSLATABLE,
            null, null, on_import_all };
        import_all.label = _("Import _All");
        actions += import_all;

        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, on_edit_menu };
        edit.label = _("_Edit");
        actions += edit;

        Gtk.ActionEntry select_all = { "SelectAll", Gtk.STOCK_SELECT_ALL, TRANSLATABLE,
            "<Ctrl>A", TRANSLATABLE, on_select_all };
        select_all.label = _("Select _All");
        select_all.tooltip = _("Select all the photos for importing");
        actions += select_all;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, null };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        return actions;
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
    
    private void on_view_changed() {
        hide_imported.sensitive = !busy && refreshed && (get_view().get_count() > 0);
        import_selected_button.sensitive = !busy && refreshed && (get_view().get_selected_count() > 0);
        import_all_button.sensitive = !busy && refreshed && (get_view().get_count() > 0);
    }
    
    private void on_photos_added_removed() {
        get_view().reapply_view_filter();
    }

    private void on_display_titles(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();

        set_display_titles(display);
        Config.get_instance().set_display_photo_titles(display);
    }
    
    public override LayoutItem? get_fullscreen_photo() {
        error("No fullscreen support for import pages");
        
        return null;
    }
    
    public override void switched_to() {
        base.switched_to();
        
        try_refreshing_camera();
    
        set_display_titles(Config.get_instance().get_display_photo_titles());
        
        // when new pages are added to the notebook in LibraryWindow, notebook.show_all() must
        // be called ... this trickles down and causes all hidden widgets to be shown, so re-hide
        // here
        if (!busy)
            progress_bar.visible = false;
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
                    string mounted_message = _("Shotwell needs to unmount the camera from the filesystem in order to access it.  Continue?");

                    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(), 
                        Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION,
                        Gtk.ButtonsType.CANCEL, "%s", mounted_message);
                    dialog.title = Resources.APP_TITLE;
                    dialog.add_button(_("Unmount"), Gtk.ResponseType.YES);
                    int dialog_res = dialog.run();
                    dialog.destroy();
                    
                    if (dialog_res != Gtk.ResponseType.YES) {
                        set_page_message(_("Please unmount the camera."));
                    } else {
                        unmount_camera(mount);
                    }
                } else {
                    string locked_message = _("The camera is locked by another application.  Shotwell can only access the camera when it's unlocked.  Please close any other application using the camera and try again.");

                    // it's not mounted, so another application must have it locked
                    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(),
                        Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING,
                        Gtk.ButtonsType.OK, "%s", locked_message);
                    dialog.title = Resources.APP_TITLE;
                    dialog.run();
                    dialog.destroy();
                    
                    set_page_message(_("Please close any other application using the camera."));
                }
            break;
            
            case ImportPage.RefreshResult.LIBRARY_ERROR:
                AppWindow.error_message(_("Unable to fetch previews from the camera:\n%s").printf(
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
        progress_bar.set_text(_("Unmounting..."));

        debug("Unmounting camera ...");
        mount.unmount(MountUnmountFlags.NONE, null, on_unmounted);
        
        return true;
    }

    private void on_unmounted(Object? source, AsyncResult aresult) {
        debug("Unmount complete");
        
        busy = false;
        progress_bar.set_text("");
        progress_bar.visible = false;
        
        Mount mount = (Mount) source;
        try {
            mount.unmount_finish(aresult);
        } catch (Error err) {
            AppWindow.error_message(_("Unable to unmount camera.  Try dismounting the camera from the file manager."));
            
            return;
        }
        
        // XXX: iPhone/iPod returns a USB error if a camera_init() is done too quickly after an
        // unmount.  A 50ms sleep gives it time to reorient itself.
        Thread.usleep(50000);
        
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
        
        on_view_changed();
        
        progress_bar.set_text(_("Fetching photo information"));
        progress_bar.set_fraction(0.0);
        progress_bar.set_pulse_step(0.01);
        progress_bar.visible = true;
        
        Gee.ArrayList<ImportSource> import_list = new Gee.ArrayList<ImportSource>();
        
        GPhoto.CameraStorageInformation *sifs = null;
        int count = 0;
        refresh_result = camera.get_storageinfo(&sifs, out count, null_context.context);
        if (refresh_result == GPhoto.Result.OK) {
            get_view().clear();
            
            for (int fsid = 0; fsid < count; fsid++) {
                if (!enumerate_files(fsid, "/", import_list))
                    break;
            }
        }
        
        import_sources.clear();
        load_previews(import_list);
        
        progress_bar.visible = false;
        progress_bar.set_text("");
        progress_bar.set_fraction(0.0);

        GPhoto.Result res = camera.exit(null_context.context);
        if (res != GPhoto.Result.OK) {
            // log but don't fail
            message("Unable to unlock camera: %s (%d)", res.as_string(), (int) res);
        }
        
        busy = false;
        
        if (refresh_result == GPhoto.Result.OK) {
            refreshed = true;
        } else {
            refreshed = false;
            
            // show 'em all or show none
            get_view().clear();
        }
        
        on_view_changed();
        
        switch (refresh_result) {
            case GPhoto.Result.OK:
                return RefreshResult.OK;
            
            case GPhoto.Result.IO_LOCK:
                return RefreshResult.LOCKED;
            
            default:
                return RefreshResult.LIBRARY_ERROR;
        }
    }
    
    public static string append_path(string basepath, string addition) {
        if (!basepath.has_suffix("/") && !addition.has_prefix("/"))
            return basepath + "/" + addition;
        else
            return basepath + addition;
    }
    
    // Need to do this because some phones (iPhone, in particular) changes the name of their filesystem
    // between each mount
    public static string? get_fs_basedir(GPhoto.Camera camera, int fsid) {
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
    
    public static string get_fulldir(GPhoto.Camera camera, string camera_name, int fsid, string folder) {
        string basedir = ImportPage.get_fs_basedir(camera, fsid);
        if (basedir == null) {
            debug("Unable to find base directory for %s fsid %d", camera_name, fsid);
            
            return folder;
        }
        
        return append_path(basedir, folder);
    }

    private bool enumerate_files(int fsid, string dir, Gee.List<ImportSource> import_list) {
        string fulldir = get_fulldir(camera, camera_name, fsid, dir);
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
                // TODO: Support all possible EXIF thumbnail file types
                if (preview_size != 0) {
                    if ((info.preview.fields & GPhoto.CameraFileInfoFields.TYPE) != 0
                        && info.preview.type != GPhoto.MIME.JPEG) {
                        message("Not previewing %s/%s: Not a JPEG preview (%s)", fulldir, filename, 
                            info.preview.type);
                    
                        preview_size = 0;
                    }
                }
                
                import_list.add(new ImportSource(camera_name, camera, fsid, dir, filename, 
                    info.file.size, preview_size));
                
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
            
            if (!enumerate_files(fsid, append_path(dir, subdir), import_list))
                return false;
        }
        
        return true;
    }
    
    private void load_previews(Gee.List<ImportSource> import_list) {
        int loaded_photos = 0;
        try {
            foreach (ImportSource import_source in import_list) {
                string filename = import_source.get_filename();
                string fulldir = import_source.get_fulldir();
                
                progress_bar.set_text(_("Fetching preview for %s").printf(import_source.get_name()));
                
                // load EXIF for photo, which will include the preview thumbnail
                uint8[] exif_raw;
                size_t exif_raw_length;
                Exif.Data exif = GPhoto.load_exif(null_context.context, camera, fulldir, filename,
                    out exif_raw, out exif_raw_length);
                
                // calculate EXIF's fingerprint
                string exif_md5 = null;
                if (exif != null && exif_raw != null && exif_raw_length > 0)
                    exif_md5 = md5_binary(exif_raw, exif_raw_length);
                
                // XXX: Cannot use the exif.data field for the thumbnail preview because libgphoto2
                // 2.4.6 has a bug where the returned EXIF data object is complete garbage.  This
                // is fixed in 2.4.7, but need to work around this as best we can.  In particular,
                // this means the preview orientation will be wrong and the MD5 is not generated
                // if the EXIF did not parse properly (see above)
                
                uint8[] preview_raw;
                size_t preview_raw_length;
                Gdk.Pixbuf preview = GPhoto.load_preview(null_context.context, camera, fulldir,
                    filename, out preview_raw, out preview_raw_length);
                
                // calculate thumbnail fingerprint
                string preview_md5 = null;
                if (preview != null && preview_raw != null && preview_raw_length > 0)
                    preview_md5 = md5_binary(preview_raw, preview_raw_length);
                
                // use placeholder if no pixbuf available
                if (preview == null) {
                    preview = render_icon(Gtk.STOCK_MISSING_IMAGE, Gtk.IconSize.DIALOG, null);
                    preview = scale_pixbuf(preview, ImportPreview.MAX_SCALE, Gdk.InterpType.BILINEAR,
                        true);
                }
                
                // update the ImportSource with the fetched information
                import_source.update(preview, preview_md5, exif, exif_md5);
                
                // *now* add to the SourceCollection, now that it is completed
                import_sources.add(import_source);
                
                progress_bar.set_fraction((double) (++loaded_photos) / (double) import_list.size);
                
                // spin the event loop so the UI doesn't freeze
                if (!spin_event_loop())
                    break;
            }
        } catch (Error err) {
            AppWindow.error_message(_("Error while fetching previews from %s: %s").printf(camera_name,
                err.message));
        }
    }
    
    private void on_file_menu() {
        set_item_sensitive("/ImportMenuBar/FileMenu/ImportSelected", 
            !busy && (get_view().get_selected_count() > 0));
        set_item_sensitive("/ImportMenuBar/FileMenu/ImportAll", !busy && (get_view().get_count() > 0));
    }
    
    private bool show_unimported_filter(DataView view) {
        return !((ImportPreview) view).is_already_imported();
    }
    
    private void on_hide_imported() {
        if (hide_imported.get_active())
            get_view().install_view_filter(show_unimported_filter);
        else
            get_view().reset_view_filter();
    }
    
    private void on_import_selected() {
        import(get_view().get_selected());
    }
    
    private void on_import_all() {
        import(get_view().get_all());
    }
    
    private void on_edit_menu() {
        set_item_sensitive("/ImportMenuBar/EditMenu/SelectAll", !busy && (get_view().get_count() > 0));
    }
    
    private void on_select_all() {
        get_view().select_all();
    }
    
    private void import(Gee.Iterable<DataObject> items) {
        GPhoto.Result res = camera.init(null_context.context);
        if (res != GPhoto.Result.OK) {
            AppWindow.error_message(_("Unable to lock camera: %s").printf(res.as_string()));
            
            return;
        }
        
        busy = true;
        
        on_view_changed();
        progress_bar.visible = false;

        uint64 total_bytes = 0;
        SortedList<CameraImportJob> jobs = new SortedList<CameraImportJob>(new CameraImportComparator());
        Gee.ArrayList<CameraImportJob> already_imported = new Gee.ArrayList<CameraImportJob>();
        Gee.ArrayList<CameraImportJob> failed = new Gee.ArrayList<CameraImportJob>();
        
        foreach (DataObject object in items) {
            ImportPreview preview = (ImportPreview) object;
            ImportSource import_file = (ImportSource) preview.get_source();
            
            if (preview.is_already_imported()) {
                message("Skipping import of %s: checksum detected in library", 
                    import_file.get_filename());
                already_imported.add(new CameraImportJob(null_context, import_file, null));
                
                continue;
            }
            
            bool collision;
            File dest_file = BatchImport.create_library_path(import_file.get_filename(), 
                import_file.get_exif(), time_t(), out collision);
            if (dest_file == null) {
                message("Unable to generate local file for %s", import_file.get_filename());
                failed.add(new CameraImportJob(null_context, import_file, null));
                
                continue;
            }
            
            jobs.add(new CameraImportJob(null_context, import_file, dest_file));
            total_bytes += import_file.get_filesize();
        }
        
        if (jobs.size > 0) {
            BatchImport batch_import = new BatchImport(jobs, camera_name, import_reporter, total_bytes, 
                failed, already_imported);
            batch_import.import_job_failed += on_import_job_failed;
            batch_import.import_complete += close_import;
            LibraryWindow.get_app().enqueue_batch_import(batch_import);
            LibraryWindow.get_app().switch_to_import_queue_page();
            // camera.exit() and busy flag will be handled when the batch import completes
        } else {
            // since failed up-front, build a fake (faux?) ImportManifest and report it here
            if (failed.size > 0 || already_imported.size > 0)
                import_reporter(new ImportManifest(failed, already_imported));
            
            close_import();
        }
    }
    
    private void on_import_job_failed(BatchImportResult result) {
        if (result.file == null || result.result == ImportResult.SUCCESS)
            return;
            
        // delete the copied file
        try {
            result.file.delete(null);
        } catch (Error err) {
            message("Unable to delete downloaded file %s: %s", result.file.get_path(), err.message);
        }
    }
    
    private void import_reporter(ImportManifest manifest) {
        // report to Event to organize into events
        if (manifest.success.size > 0)
            Event.generate_events(manifest.imported);
        
        ImportUI.QuestionParams question = new ImportUI.QuestionParams(
            _("Delete this photo from camera?"),
            _("Delete these %d photos from camera?"),
            Gtk.STOCK_DELETE);
        
        if (!ImportUI.report_manifest(manifest, false, question))
            return;
        
        int error_count = 0;
        
        // delete the photos from the camera and the SourceCollection... for now, this is an 
        // all-or-nothing deal
        Marker marker = import_sources.start_marking();
        foreach (BatchImportResult batch_result in manifest.all) {
            CameraImportJob job = batch_result.job as CameraImportJob;
            ImportSource source = job.get_source();
            
            debug("Deleting from camera %s/%s", source.get_fulldir(), source.get_filename());
            
            GPhoto.Result result = source.get_camera().delete_file(source.get_fulldir(), 
                source.get_filename(), null_context.context);
            if (result == GPhoto.Result.OK) {
                marker.mark(source);
            } else {
                error_count++;
                debug("Error deleting from camera %s/%s: %s", source.get_fulldir(),
                    source.get_filename(), result.as_string());
            }
        }
        
        if (error_count > 0) {
            AppWindow.error_message(_("Unable to delete %d photos from the camera due to errors.").printf(
                error_count));
        }
        
        import_sources.remove_marked(marker);
    }

    private void close_import() {
        GPhoto.Result res = camera.exit(null_context.context);
        if (res != GPhoto.Result.OK) {
            // log but don't fail
            message("Unable to unlock camera: %s (%d)", res.as_string(), (int) res);
        }
        
        busy = false;
        
        on_view_changed();
    }

    private bool display_titles() {
        Gtk.ToggleAction action = (Gtk.ToggleAction) ui.get_action("/ImportMenuBar/ViewMenu/ViewTitle");
        
        return action.get_active();
    }

    private override void set_display_titles(bool display) {
        base.set_display_titles(display);
    
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewTitle");
        if (action != null)
            action.set_active(display);
    }
}

#endif

public class ImportQueuePage : SinglePhotoPage {
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton stop_button = null;
    private Gee.ArrayList<BatchImport> queue = new Gee.ArrayList<BatchImport>();
    private BatchImport current_batch = null;
    private Gtk.ProgressBar progress_bar = new Gtk.ProgressBar();
    private uint64 progress_bytes = 0;
    private uint64 total_bytes = 0;
 
    public ImportQueuePage() {
        base(_("Importing..."));

        init_ui("import_queue.ui", "/ImportQueueMenuBar", "ImportQueueActionGroup",
            create_actions());
        
        stop_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_STOP);
        stop_button.set_tooltip_text(_("Stop importing photos"));
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

    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, on_file_menu };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry stop = { "Stop", Gtk.STOCK_STOP, TRANSLATABLE, null, TRANSLATABLE,
            on_stop };
        stop.label = _("_Stop Import");
        stop.tooltip = _("Stop importing photos");
        actions += stop;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, null };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        return actions;
    }
    
    public signal void batch_added(BatchImport batch_import);
    
    public signal void batch_removed(BatchImport batch_import);
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public void enqueue_and_schedule(BatchImport batch_import) {
        assert(!queue.contains(batch_import));
        
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
        try {
            set_pixbuf(photo.get_pixbuf(get_canvas_scaling()));
        } catch (Error err) {
            warning("%s", err.message);
        }
        
        // set the singleton collection to this item
        get_view().clear();
        get_view().add(new PhotoView(photo));
        
        progress_bytes += photo.get_filesize();
        double pct = (progress_bytes <= total_bytes) ? (double) progress_bytes / (double) total_bytes
            : 0.0;
        
        progress_bar.set_text(_("Imported %s").printf(photo.get_name()));
        progress_bar.set_fraction(pct);
    }
    
    private void on_import_complete(BatchImport batch_import, ImportManifest manifest) {
        assert(batch_import == current_batch);
        current_batch = null;
        
        assert(queue.size > 0);
        assert(queue.get(0) == batch_import);
        
        bool removed = queue.remove(batch_import);
        assert(removed);
        assert(!queue.contains(batch_import));
        
        // strip signal handlers
        batch_import.starting -= on_starting;
        batch_import.imported -= on_imported;
        batch_import.import_complete -= on_import_complete;
        
        // report the batch has been removed from the queue
        batch_removed(batch_import);
        
        // schedule next if available
        if (queue.size > 0) {
            stop_button.sensitive = true;
            queue.get(0).schedule();
        } else {
            // reset state
            progress_bytes = 0;
            total_bytes = 0;

            // reset UI
            stop_button.sensitive = false;
            progress_bar.set_text("");
            progress_bar.set_fraction(0.0);

            // blank the display
            blank_display();
        }
    }
}

