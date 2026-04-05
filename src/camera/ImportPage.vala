/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

private class ImportSourceCollection : SourceCollection {
    public ImportSourceCollection(string name) {
        base (name);
    }
    
    public override bool holds_type_of_source(DataSource source) {
        return source is ImportSource;
    }
}

public abstract class ImportSource : ThumbnailSource, Indexable {
    private string camera_name;
    private GPhoto.Camera camera;
    private int fsid;
    private string folder;
    private string filename;
    private string fulldir;
    private ulong file_size;
    private DateTime modification_time;
    private Gdk.Pixbuf? preview = null;
    private string? indexable_keywords = null;
    
    protected ImportSource(string camera_name, GPhoto.Camera camera, int fsid, string fulldir, string folder,
        string filename, ulong file_size, DateTime modification_time) {
        this.fulldir = fulldir;
        this.camera_name =camera_name;
        this.camera = camera;
        this.fsid = fsid;
        this.folder = folder;
        this.filename = filename;
        this.file_size = file_size;
        this.modification_time = modification_time;
        indexable_keywords = prepare_indexable_string(filename);
    }
    
    protected void set_preview(Gdk.Pixbuf? preview) {
        this.preview = preview;
    }
    
    public string get_camera_name() {
        return camera_name;
    }
    
    public GPhoto.Camera get_camera() {
        return camera;
    }
    
    public int get_fsid() {
        return fsid;
    }
    
    public string get_folder() {
        return folder;
    }
    
    public string get_filename() {
        return filename;
    }
    
    public ulong get_filesize() {
        return file_size;
    }
    
    public DateTime get_modification_time() {
        return modification_time;
    }
    
    public virtual Gdk.Pixbuf? get_preview() {
        return preview;
    }

    public virtual DateTime get_exposure_time() {
        return get_modification_time();
    }

    public string? get_fulldir() {
        return fulldir;
    }

    public override string to_string() {
        return "%s %s/%s".printf(get_camera_name(), get_folder(), get_filename());
    }
    
    // The actual deletion from the camera is performed asynchronously by
    // ImportPage.delete_from_camera(), which uses DiscoveredCamera.delete_file().  
    public override bool internal_delete_backing() throws Error {
        debug("Deleting %s from %s", to_string(), camera_name);

        return base.internal_delete_backing();
    }
    
    public unowned string? get_indexable_keywords() {
        return indexable_keywords;
    }
}

class VideoImportSource : ImportSource {
    public VideoImportSource(string camera_name, GPhoto.Camera camera, int fsid, string fulldir, string folder, 
        string filename, ulong file_size, DateTime modification_time) {
        base(camera_name, camera, fsid, fulldir, folder, filename, file_size, modification_time);
    }
    
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return create_thumbnail(scale);
    }
    
    public override Gdk.Pixbuf? create_thumbnail(int scale) throws Error {
        if (get_preview() == null)
            return null;
        
        // this satifies the return-a-new-instance requirement of create_thumbnail( ) because
        // scale_pixbuf( ) allocates a new pixbuf
        return (scale > 0) ? scale_pixbuf(get_preview(), scale, Gdk.InterpType.BILINEAR, true) :
            get_preview();
    }
    
    public override string get_typename() {
        return "videoimport";
    }
    
    public override int64 get_instance_id() {
        return get_object_id();
    }
    
    public override PhotoFileFormat get_preferred_thumbnail_format() {
        return PhotoFileFormat.get_system_default_format();
    }

    public override string get_name() {
        return get_filename();
    }
    
    public void update(Gdk.Pixbuf? preview) {
        set_preview((preview != null) ? preview : Resources.get_noninterpretable_badge_pixbuf());
    }
}

class PhotoImportSource : ImportSource {
    public const Gdk.InterpType INTERP = Gdk.InterpType.BILINEAR;

    private PhotoFileFormat file_format;
    private string? preview_md5 = null;
    private PhotoMetadata? metadata = null;
    private string? exif_md5 = null;
    private PhotoImportSource? associated = null; // JPEG source for RAW+JPEG
    
    public PhotoImportSource(string camera_name, GPhoto.Camera camera, int fsid, string fulldir, string folder, 
        string filename, ulong file_size, DateTime modification_time, PhotoFileFormat file_format) {
        base(camera_name, camera, fsid, fulldir, folder, filename, file_size, modification_time);
        this.file_format = file_format;
    }
    
    public override string get_name() {
        string? title = get_title();
        
        return !is_string_empty(title) ? title : get_filename();
    }
    
    public override string get_typename() {
        return "photoimport";
    }
    
    public override int64 get_instance_id() {
        return get_object_id();
    }
    
    public override PhotoFileFormat get_preferred_thumbnail_format() {
        return (file_format.can_write()) ? file_format :
            PhotoFileFormat.get_system_default_format();
    }

    public override Gdk.Pixbuf? create_thumbnail(int scale) throws Error {
        if (get_preview() == null)
            return null;
        
        // this satifies the return-a-new-instance requirement of create_thumbnail( ) because
        // scale_pixbuf( ) allocates a new pixbuf
        return (scale > 0) ? scale_pixbuf(get_preview(), scale, INTERP, true) : get_preview();
    }

    // Needed because previews and exif are loaded after other information has been gathered.
    public void update(Gdk.Pixbuf? preview, string? preview_md5, PhotoMetadata? metadata, string? exif_md5) {
        set_preview(preview);
        this.preview_md5 = preview_md5;
        this.metadata = metadata;
        this.exif_md5 = exif_md5;
    }

    public override DateTime get_exposure_time() {
        if (metadata == null)
            return get_modification_time();
        
        MetadataDateTime? date_time = metadata.get_exposure_date_time();
        
        return (date_time != null) ? date_time.get_timestamp() : get_modification_time();
    }
    
    public string? get_title() {
        return (metadata != null) ? metadata.get_title() : null;
    }
    
    public PhotoMetadata? get_metadata() {
        if (associated != null)
            return associated.get_metadata();
        
        return metadata;
    }
    
    public override Gdk.Pixbuf? get_preview() {
        if (associated != null)
            return associated.get_preview();
            
        if (base.get_preview() != null) 
            return base.get_preview();
        
        return null;
    }
    
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        if (get_preview() == null)
            return null;
        
        return (scale > 0) ? scale_pixbuf(get_preview(), scale, INTERP, true) : get_preview();
    }
    
    public PhotoFileFormat get_file_format() {
        return file_format;
    }
    
    public string? get_preview_md5() {
        return preview_md5;
    }
    
    public void set_associated(PhotoImportSource? associated) {
        this.associated = associated;
    }
    
    public PhotoImportSource? get_associated() {
        return associated;
    }
    
    public override bool internal_delete_backing() throws Error {
        // The associated (RAW) file is deleted from the camera together with this source by
        // ImportPage.delete_from_camera(); here we only need to account for it locally.
        return base.internal_delete_backing();
    }
}

class ImportPreview : MediaSourceItem {
    public const int MAX_SCALE = 128;
    
    private static Gdk.Pixbuf placeholder_preview = null;
    
    private DuplicatedFile? duplicated_file;
    
    public ImportPreview(ImportSource source) {
        base(source, Dimensions(), source.get_name(), null);
        
        this.duplicated_file = null;

        // scale down pixbuf if necessary
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = source.get_thumbnail(0);
        } catch (Error err) {
            warning("Unable to fetch loaded import preview for %s: %s", to_string(), err.message);
        }

        // use placeholder if no preview available
        bool using_placeholder = (pixbuf == null);
        if (pixbuf == null) {
            if (placeholder_preview == null) {
                placeholder_preview = get_placeholder_pixbuf();
                placeholder_preview = scale_pixbuf(placeholder_preview, MAX_SCALE,
                    Gdk.InterpType.BILINEAR, true);
            }
            
            pixbuf = placeholder_preview;
        }
        
        // scale down if too large
        if (pixbuf.get_width() > MAX_SCALE || pixbuf.get_height() > MAX_SCALE)
            pixbuf = scale_pixbuf(pixbuf, MAX_SCALE, PhotoImportSource.INTERP, false);
        
        if (source is PhotoImportSource) {
            // honor rotation for photos -- we don't care about videos since they can't be rotated
            PhotoImportSource photo_import_source = source as PhotoImportSource;
            if (!using_placeholder && photo_import_source.get_metadata() != null)
                pixbuf = photo_import_source.get_metadata().get_orientation().rotate_pixbuf(pixbuf);
            
            if (photo_import_source.get_associated() != null) {
                set_subtitle("<small>%s</small>".printf(_("RAW+JPEG")), true);
            }
        }
        
        set_image(pixbuf);
    }
    
    public bool is_already_imported() {
        PhotoImportSource photo_import_source = get_import_source() as PhotoImportSource;
        if (photo_import_source != null) {
            string? preview_md5 = photo_import_source.get_preview_md5();
            PhotoFileFormat file_format = photo_import_source.get_file_format();
            
            // ignore trashed duplicates
            if (!is_string_empty(preview_md5)
                && LibraryPhoto.has_nontrash_duplicate(null, preview_md5, null, file_format)) {
                
                duplicated_file = DuplicatedFile.create_from_photo_id(
                    LibraryPhoto.get_nontrash_duplicate(null, preview_md5, null, file_format));
                
                return true;
            }
            
            // Because gPhoto doesn't reliably return thumbnails for RAW files, and because we want
            // to avoid downloading huge RAW files during an "import all" only to determine they're
            // duplicates, use the image's basename and filesize to do duplicate detection
            if (file_format == PhotoFileFormat.RAW) {
                uint64 filesize = get_import_source().get_filesize();
                // unlikely to be a problem, but what the hay
                if (filesize <= int64.MAX) {
                    PhotoID duplicated_photo_id = LibraryPhoto.global.get_basename_filesize_duplicate(
                                get_import_source().get_filename(), (int64) filesize);

                    if (duplicated_photo_id.is_valid()) {
                        // Check exposure timestamp
                        LibraryPhoto duplicated_photo = LibraryPhoto.global.fetch(duplicated_photo_id);
                        DateTime photo_exposure_time = photo_import_source.get_exposure_time();
                        DateTime duplicated_photo_exposure_time = duplicated_photo.get_exposure_time();
                        
                        if (photo_exposure_time.equal(duplicated_photo_exposure_time)) {
                            duplicated_file = DuplicatedFile.create_from_photo_id(
                                LibraryPhoto.global.get_basename_filesize_duplicate(
                                get_import_source().get_filename(), (int64) filesize));

                            return true;
                        }
                    }
                }
            }
            
            return false;
        }
        
        VideoImportSource video_import_source = get_import_source() as VideoImportSource;
        if (video_import_source != null) {
            // Unlike photos, if a video does have a thumbnail (i.e. gphoto2 can retrieve one from
            // a sidecar file), it will be unavailable to Shotwell during the import process, so
            // no comparison is available.  Instead, like RAW files, use name and filesize to
            // do a less-reliable but better-than-nothing comparison
            if (Video.global.has_basename_filesize_duplicate(video_import_source.get_filename(),
                video_import_source.get_filesize())) {
                
                duplicated_file = DuplicatedFile.create_from_video_id(
                    Video.global.get_basename_filesize_duplicate(
                    video_import_source.get_filename(),
                    video_import_source.get_filesize()));
                
                return true;
            }
            
            return false;
        }
        
        return false;
    }
    
    public DuplicatedFile? get_duplicated_file() {
        if (!is_already_imported())
            return null;
        
        return duplicated_file;
    }
    
    public ImportSource get_import_source() {
        return (ImportSource) get_source();
    }

    protected override Gdk.Pixbuf? get_top_left_trinket(int scale) {
        return (get_import_source() is VideoImportSource) ? Resources.get_video_trinket (scale) : null;
    }
}

public class CameraViewTracker : Core.ViewTracker {
    public CameraAccumulator all = new CameraAccumulator();
    public CameraAccumulator visible = new CameraAccumulator();
    public CameraAccumulator selected = new CameraAccumulator();
    
    public CameraViewTracker(ViewCollection collection) {
        base (collection);
        
        start(all, visible, selected);
    }
}

public class CameraAccumulator : Object, Core.TrackerAccumulator {
    public int total { get; private set; default = 0; }
    public int photos { get; private set; default = 0; }
    public int videos { get; private set; default = 0; }
    public int raw { get; private set; default = 0; }
    
    public bool include(DataObject object) {
        ImportSource source = (ImportSource) ((DataView) object).get_source();
        
        total++;
        
        PhotoImportSource? photo = source as PhotoImportSource;
        if (photo != null && photo.get_file_format() != PhotoFileFormat.RAW)
            photos++;
        else if (photo != null && photo.get_file_format() == PhotoFileFormat.RAW)
            raw++;
        else if (source is VideoImportSource)
            videos++;
        
        // because of total, always fire "updated"
        return true;
    }
    
    public bool uninclude(DataObject object) {
        ImportSource source = (ImportSource) ((DataView) object).get_source();
        
        total++;
        
        PhotoImportSource? photo = source as PhotoImportSource;
        if (photo != null && photo.get_file_format() != PhotoFileFormat.RAW) {
            assert(photos > 0);
            photos--;
        } else if (photo != null && photo.get_file_format() == PhotoFileFormat.RAW) {
            assert(raw > 0);
            raw--;
        } else if (source is VideoImportSource) {
            assert(videos > 0);
            videos--;
        }
        
        // because of total, always fire "updated"
        return true;
    }
    
    public bool altered(DataObject object, Alteration alteration) {
        // no alteration affects accumulated data
        return false;
    }
    
    public string to_string() {
        return "%d total/%d photos/%d videos/%d raw".printf(total, photos, videos, raw);
    }
}

public class ImportPage : CheckerboardPage {
    private const string UNMOUNT_FAILED_MSG = _("Unable to unmount camera. Try unmounting the camera from the file manager.");
    
    private class ImportViewManager : ViewManager {
        private ImportPage owner;
        
        public ImportViewManager(ImportPage owner) {
            this.owner = owner;
        }
        
        public override DataView create_view(DataSource source) {
            return new ImportPreview((ImportSource) source);
        }
    }
    
   
    private class ImportPageSearchViewFilter : SearchViewFilter {
        public override uint get_criteria() {
            return SearchFilterCriteria.TEXT | SearchFilterCriteria.MEDIA;
        }
        
        public override bool predicate(DataView view) {
            ImportSource source = ((ImportPreview) view).get_import_source();
            
            // Media type.
            if ((bool) (SearchFilterCriteria.MEDIA & get_criteria()) && filter_by_media_type()) {
                if (source is VideoImportSource) {
                    if (!show_media_video)
                        return false;
                } else if (source is PhotoImportSource) {
                    PhotoImportSource photo = source as PhotoImportSource;
                    if (photo.get_file_format() == PhotoFileFormat.RAW) {
                        if (photo.get_associated() != null) {
                            if (!show_media_photos && !show_media_raw)
                                return false;
                        } else if (!show_media_raw) {
                            return false;
                        }
                    } else if (!show_media_photos)
                        return false;
                }
            }
            
            if ((bool) (SearchFilterCriteria.TEXT & get_criteria())) {
                unowned string? keywords = source.get_indexable_keywords();
                if (is_string_empty(keywords))
                    return false;
                
                // Return false if the word isn't found, true otherwise.
                foreach (unowned string word in get_search_filter_words()) {
                    if (!keywords.contains(word))
                        return false;
                }
            }
            
            return true;
        }
    }
    
    // View filter for already imported filter.
    private class HideImportedViewFilter : ViewFilter {
        public override bool predicate(DataView view) {
            return !((ImportPreview) view).is_already_imported();
        }
    }
    
    private SourceCollection import_sources = null;
    private Gtk.Label camera_label = new Gtk.Label(null);
    private Gtk.CheckButton hide_imported;
    private Gtk.ProgressBar progress_bar;
    private DiscoveredCamera dcamera;
    private bool busy = false;
    private bool refreshed = false;
    private GPhoto.Result refresh_result = GPhoto.Result.OK;
    private string refresh_error = null;
    private VolumeMonitor volume_monitor = null;
    private ImportPage? local_ref = null;
    private ImportPageSearchViewFilter search_filter = new ImportPageSearchViewFilter();
    private HideImportedViewFilter hide_imported_filter = new HideImportedViewFilter();
    private CameraViewTracker tracker;

    public enum RefreshResult {
        OK,
        BUSY,
        LOCKED,
        LIBRARY_ERROR
    }
    
    public ImportPage(DiscoveredCamera dcamera) {
        base(_("Camera"));
        this.dcamera = dcamera;
        this.import_sources = new ImportSourceCollection("ImportSources for %s".printf(dcamera.uri));
        
        tracker = new CameraViewTracker(get_view());
        
        camera_label.set_text(dcamera.display_name);
        set_page_name(dcamera.display_name);
        
        // Mount.unmounted signal is *only* fired when a VolumeMonitor has been instantiated.
        this.volume_monitor = VolumeMonitor.get();
        
        // monitor source collection to add/remove views
        get_view().monitor_source_collection(import_sources, new ImportViewManager(this), null);
        
        // sort by exposure time
        get_view().set_comparator(preview_comparator, preview_comparator_predicate);
        
        // monitor selection for UI
        get_view().items_state_changed.connect(on_view_changed);
        get_view().contents_altered.connect(on_view_changed);
        get_view().items_visibility_changed.connect(on_view_changed);
        
        // Show subtitles.
        get_view().set_property(CheckerboardItem.PROP_SHOW_SUBTITLES, true);
        
        // monitor Photos for removals, as that will change the result of the ViewFilter
        LibraryPhoto.global.contents_altered.connect(on_media_added_removed);
        Video.global.contents_altered.connect(on_media_added_removed);
        
        init_item_context_menu("ImportContextMenu");
        init_page_context_menu("ImportContextMenu");
        init_toolbar("ImportPageToolbar");
    }
    
    ~ImportPage() {
        LibraryPhoto.global.contents_altered.disconnect(on_media_added_removed);
        Video.global.contents_altered.disconnect(on_media_added_removed);
    }
    public override Gtk.Box get_toolbar() {
        if (toolbar == null) {
            base.get_toolbar();
            progress_bar = (Gtk.ProgressBar)builder.get_object("ImportProgressBar");
        }

        return toolbar;
    }
    
    public override Core.ViewTracker? get_view_tracker() {
        return tracker;
    }

    protected override string get_view_empty_icon() {
        if (this.dcamera.icon != null) {
            return this.dcamera.icon;
        }

        return "camera-photo-symbolic";
    }

    protected override string get_view_empty_message() {
        return _("The camera seems to be empty. No photos/videos found to import");
    }

    protected override string get_filter_no_match_message () {
        return _("No new photos/videos found on camera");
    }

    private static int64 preview_comparator(void *a, void *b) {
        return nullsafe_date_time_comperator(((ImportPreview *) a)->get_import_source().get_exposure_time(),
        ((ImportPreview *) b)->get_import_source().get_exposure_time());
    }
    
    private static bool preview_comparator_predicate(DataObject object, Alteration alteration) {
        return alteration.has_detail("metadata", "exposure-time");
    }
    
    private int64 import_job_comparator(void *a, void *b) {
        return nullsafe_date_time_comperator(((CameraImportJob *) a)->get_exposure_time(), ((CameraImportJob *) b)->get_exposure_time());
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("import.ui");
    }

    private const GLib.ActionEntry[] entries = {
        { "ImportSelected", on_import_selected },
        { "ImportAll", on_import_all },
        // Toggle actions
        { "ViewTitle", on_action_toggle, null, "false", on_display_titles },
        { "HideImported", on_action_toggle, null, "false", on_hide_imported }
    };

    protected override void add_actions (GLib.ActionMap map) {
        base.add_actions (map);

        map.add_action_entries (entries, this);

        get_action ("ViewTitle").change_state (Config.Facade.get_instance ().get_display_photo_titles ());
        get_action ("HideImported").change_state(Config.Facade.get_instance().get_hide_photos_already_imported());
    }

    protected override void remove_actions(GLib.ActionMap map) {
        base.remove_actions(map);
        map.remove_action_entries(entries);
    }

    public string get_uri() {
        return dcamera.uri;
    }
    
    public bool is_busy() {
        return busy;
    }
    
    protected override void init_actions(int selected_count, int count) {
        on_view_changed();
        
        set_action_sensitive("ImportSelected", true);
        set_action_sensitive("ImportAll", true);
        
        base.init_actions(selected_count, count);
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
            msg = refresh_result.to_full_string();
        }
        
        return msg;
    }
    
    private void update_status(bool busy, bool refreshed) {
        this.busy = busy;
        this.refreshed = refreshed;
        
        on_view_changed();
    }

    private void update_toolbar_state() {
        if (hide_imported != null)
            hide_imported.sensitive = !busy && refreshed && (get_view().get_unfiltered_count() > 0);
    }
    
    private void on_view_changed() {
        set_action_sensitive("ImportSelected", !busy && refreshed && get_view().get_selected_count() > 0);
        set_action_sensitive("ImportAll", !busy && refreshed && get_view().get_count() > 0);
        set_action_sensitive("CommonSelectAll", !busy && (get_view().get_count() > 0));

        update_toolbar_state();
    }
    
    private void on_media_added_removed() {
        search_filter.refresh();
    }

    private void on_display_titles(GLib.SimpleAction action, Variant? value) {
        bool display = value.get_boolean ();

        set_display_titles(display);

        Config.Facade.get_instance().set_display_photo_titles(display);
        action.set_state (value);
    }

    public override void switched_to() {
        set_display_titles(Config.Facade.get_instance().get_display_photo_titles());
        
        base.switched_to();
    }

    private void on_camera_refreshed(Object? object, AsyncResult res) {
        try_refreshing_camera.end(res);
        hide_imported_filter.refresh();
    }

    public override void ready() {
        try_refreshing_camera.begin(false, on_camera_refreshed);
    }

    private async void try_refreshing_camera(bool fail_on_locked) {
        // if camera has been refreshed or is in the process of refreshing, go no further
        if (refreshed || busy)
            return;
        
        var res = yield refresh_camera();
        switch (res) {
            case ImportPage.RefreshResult.OK:
            case ImportPage.RefreshResult.BUSY:
                // nothing to report; if busy, let it continue doing its thing
                // (although earlier check should've caught this)
            break;
            
            case ImportPage.RefreshResult.LOCKED:
                if (fail_on_locked) {
                    AppWindow.error_message(UNMOUNT_FAILED_MSG);
                    
                    break;
                }
                
                // if locked because it's mounted, offer to unmount
                debug("Checking if %s is mounted…", dcamera.uri);

                var mount = dcamera.get_mount();
                
                if (mount != null) {
                    // it's mounted, offer to unmount for the user
                    string mounted_message = _("Shotwell needs to unmount the camera from the filesystem in order to access it. Continue?");

                    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(), 
                        Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION,
                        Gtk.ButtonsType.CANCEL, "%s", mounted_message);
                    dialog.title = Resources.APP_TITLE;
                    dialog.add_button(_("_Unmount"), Gtk.ResponseType.YES);
                    dialog.set_transient_for(AppWindow.get_instance());
                    dialog.present();
                    dialog.response.connect((source, res) => {
                        if (res != Gtk.ResponseType.YES) {
                            set_page_message(_("Please unmount the camera."));
                        } else {
                            unmount_camera(mount);
                        }
                        dialog.destroy();
                    });
                } else {
                    string locked_message = _("The camera is locked by another application. Shotwell can only access the camera when it’s unlocked. Please close any other application using the camera and try again.");

                    // it's not mounted, so another application must have it locked
                    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(),
                        Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING,
                        Gtk.ButtonsType.OK, "%s", locked_message);
                    dialog.title = Resources.APP_TITLE;
                    dialog.set_transient_for(AppWindow.get_instance());
                    dialog.present();
                    dialog.response.connect((source, res) => {                    
                        set_page_message(_("Please close any other application using the camera."));
                        dialog.destroy();
                    });
                }
            break;
            
            case ImportPage.RefreshResult.LIBRARY_ERROR:
                AppWindow.error_message(_("Unable to fetch previews from the camera:\n%s").printf(
                    get_refresh_message()));
            break;
            
            default:
                error("Unknown result type %d", (int) res);
        }
    }
    
    public bool unmount_camera(Mount mount) {
        if (busy)
            return false;
        
        update_status(true, false);
        progress_bar.visible = true;
        progress_bar.set_fraction(0.0);
        progress_bar.set_ellipsize(Pango.EllipsizeMode.NONE);
        progress_bar.set_text(_("Unmounting…"));
        
        // unmount_with_operation() can/will complete with the volume still mounted (probably meaning
        // it's been *scheduled* for unmounting).  However, this signal is fired when the mount
        // really is unmounted -- *if* a VolumeMonitor has been instantiated.
        mount.unmounted.connect(on_unmounted);
        
        debug("Unmounting camera…");
        mount.unmount_with_operation.begin(MountUnmountFlags.NONE, 
            new Gtk.MountOperation(AppWindow.get_instance()), null, on_unmount_finished);
        
        return true;
    }
    
    private void on_unmount_finished(Object? source, AsyncResult aresult) {
        debug("Async unmount finished");
        
        Mount mount = (Mount) source;
        try {
            mount.unmount_with_operation.end(aresult);
        } catch (Error err) {
            AppWindow.error_message(UNMOUNT_FAILED_MSG);
            
            // don't trap this signal, even if it does come in, we've backed off
            mount.unmounted.disconnect(on_unmounted);
            
            update_status(false, refreshed);
            progress_bar.set_ellipsize(Pango.EllipsizeMode.NONE);
            progress_bar.set_text("");
            progress_bar.visible = false;
        }
    }
    
    private void on_unmounted(Mount mount) {
        debug("on_unmounted");
        
        update_status(false, refreshed);
        progress_bar.set_ellipsize(Pango.EllipsizeMode.NONE);
        progress_bar.set_text("");
        progress_bar.visible = false;
        
        try_refreshing_camera.begin(true);
    }
    
    private void clear_all_import_sources() {
        Marker marker = import_sources.start_marking();
        marker.mark_all();
        import_sources.destroy_marked(marker, false);
    }


    private int claim_timeout = 500;

    private static Workers camera_workers = new Workers(1, false);

    private async void timeout_msec(int timeout) {
        Timeout.add (timeout, () => {timeout_msec.callback(); return Source.REMOVE; });
        yield;
    }

    private async RefreshResult refresh_camera() {
        dcamera.attach(camera_workers);
        while (claim_timeout < 4000) {
            var result = yield dcamera.init();
            refresh_result = result;
            if (result == GPhoto.Result.IO_USB_CLAIM) {
                debug("Could not claim camera, doing exponential back-off re-try");
                claim_timeout *= 2;
                yield timeout_msec(claim_timeout);
            } else {
                debug("Camera claim succeeded, exiting retry loop");
                break;
            }
        }
        claim_timeout = 500;

       if (refresh_result != GPhoto.Result.OK) {
            warning("Unable to initialize camera: %s", refresh_result.to_full_string());
            
            return (refresh_result == GPhoto.Result.IO_LOCK) ? RefreshResult.LOCKED : RefreshResult.LIBRARY_ERROR;
        }

        this.set_page_message (_("Starting import, please wait…"));
        update_status(true, refreshed);
        
        on_view_changed();

        progress_bar.set_ellipsize(Pango.EllipsizeMode.NONE);
        progress_bar.set_text(_("Fetching photo information"));
        progress_bar.set_fraction(0.0);
        progress_bar.set_pulse_step(0.01);
        progress_bar.visible = true;
        
        Gee.ArrayList<ImportSource> import_list = new Gee.ArrayList<ImportSource>();
        GPhoto.CameraStorageInformation[] sifs;
        var result = yield dcamera.get_storage_information(out sifs);

        if (result == GPhoto.Result.OK) {
            for (int fsid = 0; fsid < sifs.length; fsid++) {
                // Check well-known video and image paths first to prevent accidental
                // scanning of undesired directories (which can cause user annoyance with
                // some smartphones or camera-equipped media players)
                bool got_well_known_dir = false;

                // Check common paths for most primarily-still cameras, many (most?) smartphones
                if (yield dcamera.check_directory_exists(fsid, "/", "DCIM")) {
                    yield dcamera.enumerate_files(fsid, "/DCIM", import_list);
                    got_well_known_dir = true;
                }
                if (yield dcamera.check_directory_exists(fsid, "/", "dcim")) {
                    yield dcamera.enumerate_files(fsid, "/dcim", import_list);
                    got_well_known_dir = true;
                }

                // Check common paths for AVCHD camcorders, primarily-still
                // cameras that shoot .mts video files
                if (yield dcamera.check_directory_exists(fsid, "/PRIVATE/", "AVCHD")) {
                    yield dcamera.enumerate_files(fsid, "/PRIVATE/AVCHD", import_list);
                    got_well_known_dir = true;
                }
                if (yield dcamera.check_directory_exists(fsid, "/private/", "avchd")) {
                    yield dcamera.enumerate_files(fsid, "/private/avchd", import_list);
                    got_well_known_dir = true;
                }
                if (yield dcamera.check_directory_exists(fsid, "/", "AVCHD")) {
                    yield dcamera.enumerate_files(fsid, "/AVCHD", import_list);
                    got_well_known_dir = true;
                }
                if (yield dcamera.check_directory_exists(fsid, "/", "avchd")) {
                    yield dcamera.enumerate_files(fsid, "/avchd", import_list);
                    got_well_known_dir = true;
                }

                // Check common video paths for some Sony primarily-still
                // cameras
                if (yield dcamera.check_directory_exists(fsid, "/PRIVATE/", "SONY")) {
                    yield dcamera.enumerate_files(fsid, "/PRIVATE/SONY", import_list);
                    got_well_known_dir = true;
                }
                if (yield dcamera.check_directory_exists(fsid, "/PRIVATE/M4ROOT/", "CLIP")) {
                    yield dcamera.enumerate_files(fsid, "/PRIVATE/M4ROOT/CLIP", import_list);
                    got_well_known_dir = true;
                }
                if (yield dcamera.check_directory_exists(fsid, "/private/", "sony")) {
                    yield dcamera.enumerate_files(fsid, "/private/sony", import_list);
                    got_well_known_dir = true;
                }

                // Check common video paths for Sony NEX3, PSP addon camera 
                if (yield dcamera.check_directory_exists(fsid, "/", "MP_ROOT")) {
                    yield dcamera.enumerate_files(fsid, "/MP_ROOT", import_list);
                    got_well_known_dir = true;
                }
                if (yield dcamera.check_directory_exists(fsid, "/", "mp_root")) {
                    yield dcamera.enumerate_files(fsid, "/mp_root", import_list);
                    got_well_known_dir = true;
                }
                
                // Didn't find any of the common directories we know about
                // already - try scanning from device root.
                if (!got_well_known_dir) {
                    result = yield dcamera.enumerate_files(fsid, "/", import_list);
                    if (result != GPhoto.Result.OK)
                        break;
                }
            }
        }

        clear_all_import_sources();

        // Associate files (for RAW+JPEG)
        auto_match_raw_jpeg(import_list);
                
        yield load_previews_and_metadata(import_list);
                
        progress_bar.visible = false;
        progress_bar.set_ellipsize(Pango.EllipsizeMode.NONE);
        progress_bar.set_text("");
        progress_bar.set_fraction(0.0);

        var res = yield dcamera.shutdown();
        
        if (res != GPhoto.Result.OK) {
            // log but don't fail
            warning("Unable to unlock camera: %s", res.to_full_string());
        }
        
        if (refresh_result == GPhoto.Result.OK) {
            if (import_sources.get_count () == 0) {
                this.set_page_message (this.get_view_empty_message ());
            }
            update_status(false, true);
        } else {
            update_status(false, false);
            
            // show 'em all or show none
            clear_all_import_sources();
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
    

    // Try to match RAW+JPEG pairs.
    private void auto_match_raw_jpeg(Gee.ArrayList<ImportSource> import_list) {
        for (int i = 0; i < import_list.size; i++) {
            PhotoImportSource? current = import_list.get(i) as PhotoImportSource;
            PhotoImportSource? next = (i + 1 < import_list.size) ? 
                import_list.get(i + 1) as PhotoImportSource : null;
            PhotoImportSource? prev = (i > 0) ? 
                import_list.get(i - 1) as PhotoImportSource : null;
            if (current != null && current.get_file_format() == PhotoFileFormat.RAW) {
                string current_name;
                string ext;
                disassemble_filename(current.get_filename(), out current_name, out ext);
                
                // Try to find a matching pair.
                PhotoImportSource? associated = null;
                if (next != null && next.get_file_format() == PhotoFileFormat.JFIF) {
                    string next_name;
                    disassemble_filename(next.get_filename(), out next_name, out ext);
                    if (next_name == current_name)
                        associated = next;
                }
                if (prev != null && prev.get_file_format() == PhotoFileFormat.JFIF) {
                    string prev_name;
                    disassemble_filename(prev.get_filename(), out prev_name, out ext);
                    if (prev_name == current_name)
                        associated = prev;
                }
                
                // Associate!
                if (associated != null) {
                    debug("Found RAW+JPEG pair: %s and %s", current.get_filename(), associated.get_filename());
                    current.set_associated(associated);
                    if (!import_list.remove(associated)) {
                        debug("Unable to associate files");
                        current.set_associated(null);
                    }
                }
            }
        }
    }

    private async void load_previews_and_metadata(Gee.List<ImportSource> import_list) {
        int loaded_photos = 0;
        foreach (var import_source in import_list) {
            string filename = import_source.get_filename();
            string? fulldir = import_source.get_fulldir();
            if (fulldir == null) {
                warning("Skipping loading preview of %s: invalid folder name", import_source.to_string());
                
                continue;
            }
            
            // Get JPEG pair, if available.
            PhotoImportSource? associated = null;
            if (import_source is PhotoImportSource && 
                ((PhotoImportSource) import_source).get_associated() != null) {
                associated = ((PhotoImportSource) import_source).get_associated();
            }
            
            progress_bar.set_ellipsize(Pango.EllipsizeMode.MIDDLE);
            progress_bar.set_text(_("Fetching preview for %s").printf(import_source.get_name()));
            
            // Ask GPhoto to read the current file's metadata, but only if the file is not a
            // video. Across every memory card and camera type I've tested (lucas, as of 10/27/2010)
            // GPhoto always loads null metadata for videos. So without the is-not-video guard,
            // this code segment just needlessly and annoyingly prints a warning message to the
            // console.

            PhotoMetadata? metadata = null;
            if (!VideoReader.is_supported_video_filename(filename)) {
                try {
                    metadata = yield dcamera.load_metadata(fulldir, filename);
                } catch (Error err) {
                    warning("Unable to fetch metadata for %s/%s: %s", fulldir, filename, err.message);
                }
            }
            
            // calculate EXIF's fingerprint
            string? exif_only_md5 = null;
            if (metadata != null) {
                exif_only_md5 = metadata.exif_hash();
            }
            
            // XXX: Cannot use the metadata for the thumbnail preview because libgphoto2
            // 2.4.6 has a bug where the returned EXIF data object is complete garbage.  This
            // is fixed in 2.4.7, but need to work around this as best we can.  In particular,
            // this means the preview orientation will be wrong and the MD5 is not generated
            // if the EXIF did not parse properly (see above)
            
            Gdk.Pixbuf preview = null;
            string? preview_md5 = null;
            try {
                string preview_fulldir = fulldir;
                string preview_filename = filename;
                if (associated != null) {
                    preview_fulldir = associated.get_fulldir();
                    preview_filename = associated.get_filename();
                }

                preview = yield dcamera.load_preview(preview_fulldir, preview_filename, out preview_md5);
            } catch (Error err) {
                // only issue the warning message if we're not reading a video. GPhoto is capable
                // of reading video previews about 50% of the time, so we don't want to put a guard
                // around this entire code segment like we did with the metadata-read segment above,
                // however video previews being absent is so common that there's no reason
                // we should generate a warning for one.
                if (!VideoReader.is_supported_video_filename(filename)) {
                    warning("Unable to fetch preview for %s/%s: %s", fulldir, filename, err.message);
                }
            }
            
#if TRACE_MD5
            debug("camera MD5 %s: exif=%s preview=%s", filename, exif_only_md5, preview_md5);
#endif

            if (import_source is VideoImportSource) {
                var video_import_source = (VideoImportSource)import_source;
                video_import_source.update(preview);
            }

            if (import_source is PhotoImportSource) {
                var photo_import_source = (PhotoImportSource)import_source;
                photo_import_source.update(preview, preview_md5, metadata, exif_only_md5);
            }

            if (associated != null) {
                try {
                    var associated_metadata = yield dcamera.load_metadata(associated.get_fulldir(), associated.get_filename());
                    associated.update(preview, preview_md5, associated_metadata, null);
                } catch (Error err) {
                    warning("Unable to fetch metadata for %s/%s: %s",  associated.get_fulldir(),
                        associated.get_filename(), err.message);
                }
            }
            
            // *now* add to the SourceCollection, now that it is completed
            import_sources.add(import_source);
            
            progress_bar.set_fraction((double) (++loaded_photos) / (double) import_list.size);
        }
    }
    
    private void on_hide_imported(GLib.SimpleAction action, Variant? value) {
        var active = value.get_boolean();
        if (active)
            get_view().install_view_filter(hide_imported_filter);
        else
            get_view().remove_view_filter(hide_imported_filter);
        
        Config.Facade.get_instance().set_hide_photos_already_imported(active);
        action.set_state(active);
    }
    
    private void on_import_selected() {
        import.begin(get_view().get_selected());
    }
    
    private void on_import_all() {
        import.begin(get_view().get_all());
    }
    
    private async void import(Gee.Iterable<DataObject> items) {
        dcamera.attach(camera_workers);
        var res = yield dcamera.init();
        if (res != GPhoto.Result.OK) {
            AppWindow.error_message(_("Unable to lock camera: %s").printf(res.to_full_string()));
            
            return;
        }

        update_status(true, refreshed);
        
        on_view_changed();
        progress_bar.visible = false;

        var jobs = new SortedList<CameraImportJob>(import_job_comparator);
        var already_imported = new Gee.ArrayList<CameraImportJob>();
        
        foreach (DataObject object in items) {
            ImportPreview preview = (ImportPreview) object;
            ImportSource import_file = (ImportSource) preview.get_source();
            
            if (preview.is_already_imported()) {
                message("Skipping import of %s: checksum detected in library", 
                    import_file.get_filename());
                
                var j = dcamera.create_import_job(import_file, preview.get_duplicated_file());
                already_imported.add((CameraImportJob)j);
                
                continue;
            }
            
            var import_job = dcamera.create_import_job(import_file);
            
            // Maintain RAW+JPEG association.
            if (import_file is PhotoImportSource && 
                ((PhotoImportSource) import_file).get_associated() != null) {
                    var j = dcamera.create_import_job(((PhotoImportSource) import_file).get_associated());
                import_job.set_associated(j);
            }
            
            jobs.add((CameraImportJob)import_job);
        }
        
        debug("Importing %d files from %s", jobs.size, dcamera.display_name);
        
        if (jobs.size > 0) {
            // see import_reporter() to see why this is held during the duration of the import
            assert(local_ref == null);
            local_ref = this;
            
            BatchImport batch_import = new BatchImport(jobs, dcamera.display_name, import_reporter,
                null, already_imported);
            
            batch_import.import_job_failed.connect(on_import_job_failed);
            batch_import.import_complete.connect(on_import_complete);
            
            LibraryWindow.get_app().enqueue_batch_import(batch_import, true);
            LibraryWindow.get_app().switch_to_import_queue_page();
            // camera.exit() and busy flag will be handled when the batch import completes
        } else {
            // since failed up-front, build a fake (faux?) ImportManifest and report it here
            if (already_imported.size > 0)
                import_reporter(new ImportManifest(null, already_imported));

            // Nothing will be imported; release the camera we acquired above.
            res = yield dcamera.shutdown();
            close_import(res);
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

    private void on_import_complete() {
        // The camera is intentionally left open after a successful import so the user can
        // optionally delete the imported files from it (see delete_from_camera_async()).  The
        // session is released when the DiscoveredCamera is disposed.
        close_import(GPhoto.Result.OK);
    }
    
    private void import_reporter(ImportManifest manifest) {
        // TODO: Need to keep the ImportPage around until the BatchImport is completed, but the
        // page controller (i.e. LibraryWindow) needs to know (a) if ImportPage is busy before
        // removing and (b) if it is, to be notified when it ain't.  Until that's in place, need
        // to hold the ref so the page isn't destroyed ... this switcheroo keeps the ref alive
        // until this function returns (at any time)
        ImportPage? local_ref = this.local_ref;
        this.local_ref = null;

        if (manifest.success.size <= 0) {
            ImportUI.report_manifest.begin(manifest, false, null);
            return;
        }
        
        string photos_string = (ngettext("Delete this photo from camera?",
            "Delete these %d photos from camera?", 
            manifest.success.size)).printf(manifest.success.size);
        string videos_string = (ngettext("Delete this video from camera?",
            "Delete these %d videos from camera?", 
            manifest.success.size)).printf(manifest.success.size);
        string both_string = (ngettext("Delete this photo/video from camera?",
            "Delete these %d photos/videos from camera?", 
            manifest.success.size)).printf(manifest.success.size);
        string neither_string = (ngettext("Delete these files from camera?",
            "Delete these %d files from camera?", 
            manifest.success.size)).printf(manifest.success.size);

        string question_string = ImportUI.get_media_specific_string(manifest.success,
            photos_string, videos_string, both_string, neither_string);

        ImportUI.QuestionParams question = new ImportUI.QuestionParams(
            question_string, Resources.DELETE_LABEL, _("_Keep"));

        ImportUI.report_manifest.begin(manifest, false, question, (source, res) => {
            if (ImportUI.report_manifest.end(res)) {
                delete_from_camera(manifest);
            } else {
                // The user chose to keep the files on the camera.  The import left the camera
                // session open in case it would be needed for deletion, so release it now.
                release_camera_async.begin();
            }
        });

        local_ref = null;
    }

    void delete_from_camera(ImportManifest manifest) {
        delete_from_camera_async.begin(manifest);
    }

    // Releases the camera session that on_import_complete() deliberately left open, for the case
    // where the user declined to delete the imported files from the camera.
    private async void release_camera_async() {
        dcamera.attach(camera_workers);
        var res = yield dcamera.shutdown();
        if (res != GPhoto.Result.OK)
            // log but don't fail
            message("Unable to unlock camera: %s", res.to_full_string());
    }

    // Returns the ImportSource plus (for RAW+JPEG pairs) its associated source, so both can be
    // removed from the camera.
    private static void collect_sources(ImportSource source, Gee.ArrayList<ImportSource> sources) {
        sources.add(source);
        if (source is PhotoImportSource) {
            var associated = ((PhotoImportSource) source).get_associated();
            if (associated != null)
                sources.add(associated);
        }
    }

    private async void delete_from_camera_async(ImportManifest manifest) {
        // delete the photos from the camera and the SourceCollection
        Marker marker = import_sources.start_marking();
        var sources = new Gee.ArrayList<ImportSource>();
        foreach (BatchImportResult batch_result in manifest.success) {
            CameraImportJob job = batch_result.job as CameraImportJob;

            var source = job.get_source();
            marker.mark(source);
            collect_sources(source, sources);
        }

        ProgressDialog progress = new ProgressDialog(AppWindow.get_instance(),
            _("Removing photos/videos from camera"), new Cancellable());

        // The camera is still open from the import (see on_import_complete()); reuse that session
        // rather than shutting it down and re-locking it.
        dcamera.attach(camera_workers);

        int error_count = 0;
        uint64 deleted = 0;
        foreach (var source in sources) {
            deleted++;
            progress.monitor(deleted, (uint64) sources.size, false);

            string? fulldir = source.get_fulldir();
            if (fulldir == null) {
                warning("Skipping deleting %s from %s: invalid folder name",
                    source.to_string(), dcamera.display_name);
                error_count++;
                continue;
            }

            var result = yield dcamera.delete_file(fulldir, source.get_filename());
            if (result != GPhoto.Result.OK) {
                warning("Error deleting %s from %s: %s", source.to_string(),
                    dcamera.display_name, result.to_full_string());
                error_count++;
            }
        }

        // The camera-side deletion (including associated files) is done above; remove the sources
        // from the collection without attempting to touch the camera again.
        import_sources.destroy_marked(marker, false, progress.monitor);

        // The camera session is left open and released when the DiscoveredCamera is disposed.

        if (error_count > 0) {
            string error_string =
                (ngettext("Unable to delete %d photo/video from the camera due to errors.",
                "Unable to delete %d photos/videos from the camera due to errors.", error_count)).printf(
                error_count);
            AppWindow.error_message(error_string);
        }

        progress.close();

        // to stop build warnings
        local_ref = null;
    }

    private void close_import(GPhoto.Result res) {
        if (res != GPhoto.Result.OK) {
            // log but don't fail
            message("Unable to unlock camera: %s", res.to_full_string());
        }
        
        update_status(false, refreshed);
        
        on_view_changed();
    }

    public override void set_display_titles(bool display) {
        base.set_display_titles(display);

        set_action_active ("ViewTitle", display);
    }
    
    // Gets the search view filter for this page.
    public override SearchViewFilter get_search_view_filter() {
        return search_filter;
    }
}

