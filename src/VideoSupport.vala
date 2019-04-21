/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public errordomain VideoError {
    FILE,          // there's a problem reading the video container file (doesn't exist, no read
                   // permission, etc.)

    CONTENTS,      // we can read the container file but its contents are indecipherable (no codec,
                   // malformed data, etc.)
}

public class VideoImportParams {
    // IN:
    public File file;
    public ImportID import_id = ImportID();
    public string? md5;
    public time_t exposure_time_override;
    
    // IN/OUT:
    public Thumbnails? thumbnails;
    
    // OUT:
    public VideoRow row = new VideoRow();
    
    public VideoImportParams(File file, ImportID import_id, string? md5,
        Thumbnails? thumbnails = null, time_t exposure_time_override = 0) {
        this.file = file;
        this.import_id = import_id;
        this.md5 = md5;
        this.thumbnails = thumbnails;
        this.exposure_time_override = exposure_time_override;
    }
}

public class VideoReader {
    private const double UNKNOWN_CLIP_DURATION = -1.0;
    private const uint THUMBNAILER_TIMEOUT = 10000; // In milliseconds.

    // File extensions for video containers that pack only metadata as per the AVCHD spec
    private const string[] METADATA_ONLY_FILE_EXTENSIONS = { "bdm", "bdmv", "cpi", "mpl" };
    
    private double clip_duration = UNKNOWN_CLIP_DURATION;
    private Gdk.Pixbuf preview_frame = null;
    private File file = null;
    private GLib.Pid thumbnailer_pid = 0;
    public DateTime? timestamp { get; private set; default = null; }

    public VideoReader(File file) {
        this.file = file;
     }
    
    public static bool is_supported_video_file(File file) {
        var mime_type = ContentType.guess(file.get_basename(), new uchar[0], null);
        // special case: deep-check content-type of files ending with .ogg
        if (mime_type == "audio/ogg" && file.has_uri_scheme("file")) {
            try {
                var info = file.query_info(FileAttribute.STANDARD_CONTENT_TYPE,
                                           FileQueryInfoFlags.NONE);
                var content_type = info.get_content_type();
                if (content_type != null && content_type.has_prefix ("video/")) {
                    return true;
                }
            } catch (Error error) {
                debug("Failed to query content type: %s", error.message);
            }
        }

        return is_supported_video_filename(file.get_basename());
    }

    public static bool is_supported_video_filename(string filename) {
        string mime_type;
        mime_type = ContentType.guess(filename, new uchar[0], null);
        // Guessed mp4 from filename has application/ as prefix, so check for mp4 in the end
        if (mime_type.has_prefix ("video/") || mime_type.has_suffix("mp4")) {
            string? extension = null;
            string? name = null;
            disassemble_filename(filename, out name, out extension);

            if (extension == null)
                return true;

            foreach (string s in METADATA_ONLY_FILE_EXTENSIONS) {
                if (utf8_ci_compare(s, extension) == 0)
                    return false;
            }

            return true;
        } else {
            debug("Skipping %s, unsupported mime type %s", filename, mime_type);
            return false;
        }
    }
    
    public static ImportResult prepare_for_import(VideoImportParams params) {
#if MEASURE_IMPORT
        Timer total_time = new Timer();
#endif
        File file = params.file;
        
        FileInfo info = null;
        try {
            info = file.query_info(DirectoryMonitor.SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            return ImportResult.FILE_ERROR;
        }
        
        if (info.get_file_type() != FileType.REGULAR)
            return ImportResult.NOT_A_FILE;
        
        if (!is_supported_video_file(file)) {
            message("Not importing %s: file is marked as a video file but doesn't have a" +
                "supported extension", file.get_path());
            
            return ImportResult.UNSUPPORTED_FORMAT;
        }
        
        TimeVal timestamp = info.get_modification_time();
        
        // make sure params has a valid md5
        assert(params.md5 != null);

        time_t exposure_time = params.exposure_time_override;
        string title = "";
        string comment = "";
        
        VideoReader reader = new VideoReader(file);
        bool is_interpretable = true;
        double clip_duration = 0.0;
        Gdk.Pixbuf preview_frame = reader.read_preview_frame();
        try {
            clip_duration = reader.read_clip_duration();
        } catch (VideoError err) {
            if (err is VideoError.FILE) {
                return ImportResult.FILE_ERROR;
            } else if (err is VideoError.CONTENTS) {
                is_interpretable = false;
                clip_duration = 0.0;
            } else {
                error("can't prepare video for import: an unknown kind of video error occurred");
            }
        }
        
        try {
            VideoMetadata metadata = reader.read_metadata();
            MetadataDateTime? creation_date_time = metadata.get_creation_date_time();
            
            if (creation_date_time != null && creation_date_time.get_timestamp() != 0)
                exposure_time = creation_date_time.get_timestamp();
            
            string? video_title = metadata.get_title();
            string? video_comment = metadata.get_comment();
            if (video_title != null)
                title = video_title;
            if (video_comment != null)
                comment = video_comment;
        } catch (Error err) {
            warning("Unable to read video metadata: %s", err.message);
        }
        
        if (exposure_time == 0) {
            // Use time reported by Gstreamer, if available.
            exposure_time = (time_t) (reader.timestamp != null ? 
                reader.timestamp.to_unix() : 0);
        }
        
        params.row.video_id = VideoID();
        params.row.filepath = file.get_path();
        params.row.filesize = info.get_size();
        params.row.timestamp = timestamp.tv_sec;
        params.row.width = preview_frame.width;
        params.row.height = preview_frame.height;
        params.row.clip_duration = clip_duration;
        params.row.is_interpretable = is_interpretable;
        params.row.exposure_time = exposure_time;
        params.row.import_id = params.import_id;
        params.row.event_id = EventID();
        params.row.md5 = params.md5;
        params.row.time_created = 0;
        params.row.title = title;
        params.row.comment = comment;
        params.row.backlinks = "";
        params.row.time_reimported = 0;
        params.row.flags = 0;

        if (params.thumbnails != null) {
            params.thumbnails = new Thumbnails();
            ThumbnailCache.generate_for_video_frame(params.thumbnails, preview_frame);
        }
        
#if MEASURE_IMPORT
        debug("IMPORT: total time to import video = %lf", total_time.elapsed());
#endif
        return ImportResult.SUCCESS;
    }
    
    private void read_internal() throws VideoError {
        if (!does_file_exist())
            throw new VideoError.FILE("video file '%s' does not exist or is inaccessible".printf(
                file.get_path()));
        
        try {
            Gst.PbUtils.Discoverer d = new Gst.PbUtils.Discoverer((Gst.ClockTime) (Gst.SECOND * 5));
            Gst.PbUtils.DiscovererInfo info = d.discover_uri(file.get_uri());
            
            clip_duration = ((double) info.get_duration()) / 1000000000.0;
            
            // Get creation time.
            // TODO: Note that TAG_DATE can be changed to TAG_DATE_TIME in the future
            // (and the corresponding output struct) in order to implement #2836.
            Date? video_date = null;
            if (info.get_tags() != null && info.get_tags().get_date(Gst.Tags.DATE, out video_date)) {
                // possible for get_date() to return true and a null Date
                if (video_date != null) {
                    timestamp = new DateTime.local(video_date.get_year(), video_date.get_month(),
                        video_date.get_day(), 0, 0, 0);
                }
            }
        } catch (Error e) {
            debug("Video read error: %s", e.message);
            throw new VideoError.CONTENTS("GStreamer couldn't extract clip information: %s"
                .printf(e.message));
        }
    }
    
    // Used by thumbnailer() to kill the external process if need be.
    private bool on_thumbnailer_timer() {
        debug("Thumbnailer timer called");
        if (thumbnailer_pid != 0) {
            debug("Killing thumbnailer process: %d", thumbnailer_pid);
#if VALA_0_40
            Posix.kill(thumbnailer_pid, Posix.Signal.KILL);
#else
            Posix.kill(thumbnailer_pid, Posix.SIGKILL);
#endif
        }
        return false; // Don't call again.
    }
    
    // Performs video thumbnailing.
    // Note: not thread-safe if called from the same instance of the class.
    private Gdk.Pixbuf? thumbnailer(string video_file) {
        // Use Shotwell's thumbnailer, redirect output to stdout.
        debug("Launching thumbnailer process: %s", AppDirs.get_thumbnailer_bin().get_path());
        string[] argv = {AppDirs.get_thumbnailer_bin().get_path(), video_file};
        int child_stdout;
        try {
            GLib.Process.spawn_async_with_pipes(null, argv, null, GLib.SpawnFlags.SEARCH_PATH | 
                GLib.SpawnFlags.DO_NOT_REAP_CHILD, null, out thumbnailer_pid, null, out child_stdout,
                null);
            debug("Spawned thumbnailer, child pid: %d", (int) thumbnailer_pid);
        } catch (Error e) {
            debug("Error spawning process: %s", e.message);
            if (thumbnailer_pid != 0)
                GLib.Process.close_pid(thumbnailer_pid);
            return null;
        }
        
        // Start timer.
        Timeout.add(THUMBNAILER_TIMEOUT, on_thumbnailer_timer);
        
        // Read pixbuf from stream.
        Gdk.Pixbuf? buf = null;
        try {
            GLib.UnixInputStream unix_input = new GLib.UnixInputStream(child_stdout, true);
            buf = new Gdk.Pixbuf.from_stream(unix_input, null);
        } catch (Error e) {
            debug("Error creating pixbuf: %s", e.message);
            buf = null;
        }
        
        // Make sure process exited properly.
        int child_status = 0;
        int ret_waitpid = Posix.waitpid(thumbnailer_pid, out child_status, 0);
        if (ret_waitpid < 0) {
            debug("waitpid returned error code: %d", ret_waitpid);
            buf = null;
        } else if (0 != Process.exit_status(child_status)) {
            debug("Thumbnailer exited with error code: %d",
                    Process.exit_status(child_status));
            buf = null;
        }
        
        GLib.Process.close_pid(thumbnailer_pid);
        thumbnailer_pid = 0;
        return buf;
    }
    
    private bool does_file_exist() {
        return FileUtils.test(file.get_path(), FileTest.EXISTS | FileTest.IS_REGULAR);
    }
    
    public Gdk.Pixbuf? read_preview_frame() {
        if (preview_frame != null)
            return preview_frame;
        
        if (!does_file_exist())
            return null;
        
        // Get preview frame from thumbnailer.
        preview_frame = thumbnailer(file.get_path());
        if (null == preview_frame)
            preview_frame = Resources.get_noninterpretable_badge_pixbuf();
        
        return preview_frame;
    }
    
    public double read_clip_duration() throws VideoError {
        if (clip_duration == UNKNOWN_CLIP_DURATION)
            read_internal();

        return clip_duration;
    }
    
    public VideoMetadata read_metadata() throws Error {
        VideoMetadata metadata = new VideoMetadata();
        metadata.read_from_file(File.new_for_path(file.get_path()));
        
        return metadata;
    }
}

public class Video : VideoSource, Flaggable, Monitorable, Dateable {
    public const string TYPENAME = "video";
    
    public const uint64 FLAG_TRASH =    0x0000000000000001;
    public const uint64 FLAG_OFFLINE =  0x0000000000000002;
    public const uint64 FLAG_FLAGGED =  0x0000000000000004;
    
    public class InterpretableResults {
        internal Video video;
        internal bool update_interpretable = false;
        internal bool is_interpretable = false;
        internal Gdk.Pixbuf? new_thumbnail = null;
        
        public InterpretableResults(Video video) {
            this.video = video;
        }
        
        public void foreground_finish() {
            if (update_interpretable)
                video.set_is_interpretable(is_interpretable);
            
            if (new_thumbnail != null) {
                try {
                    ThumbnailCache.replace(video, ThumbnailCache.Size.BIG, new_thumbnail);
                    ThumbnailCache.replace(video, ThumbnailCache.Size.MEDIUM, new_thumbnail);
                    
                    video.notify_thumbnail_altered();
                } catch (Error err) {
                    message("Unable to update video thumbnails for %s: %s", video.to_string(),
                        err.message);
                }
            }
        }
    }
    
    private static bool interpreter_state_changed;
    private static int current_state;
    private static bool normal_regen_complete;
    private static bool offline_regen_complete;
    public static VideoSourceCollection global;

    private VideoRow backing_row;
    
    public Video(VideoRow row) {
        this.backing_row = row;
        
        // normalize user text
        this.backing_row.title = prep_title(this.backing_row.title);
        
        if (((row.flags & FLAG_TRASH) != 0) || ((row.flags & FLAG_OFFLINE) != 0))
            rehydrate_backlinks(global, row.backlinks);
    }

    public static void init(ProgressMonitor? monitor = null) {
        // Must initialize static variables here.
        // TODO: set values at declaration time once the following Vala bug is fixed:
        //       https://bugzilla.gnome.org/show_bug.cgi?id=655594
        interpreter_state_changed = false;
        current_state = -1;
        normal_regen_complete = false;
        offline_regen_complete = false;
    
        // initialize GStreamer, but don't pass it our actual command line arguments -- we don't
        // want our end users to be able to parameterize the GStreamer configuration
        unowned string[] args = null;
        Gst.init(ref args);

        var registry = Gst.Registry.@get ();
        int saved_state = Config.Facade.get_instance().get_video_interpreter_state_cookie();
        current_state = (int) registry.get_feature_list_cookie();
        if (saved_state == Config.Facade.NO_VIDEO_INTERPRETER_STATE) {
            message("interpreter state cookie not found; assuming all video thumbnails are out of date");
            interpreter_state_changed = true;
        } else if (saved_state != current_state) {
            message("interpreter state has changed; video thumbnails may be out of date");
            interpreter_state_changed = true;
        }

        /* First do the cookie state handling, then update our local registry
         * to not include vaapi stuff. This is basically to work-around
         * concurrent access to VAAPI/X11 which it doesn't like, cf
         * https://bugzilla.gnome.org/show_bug.cgi?id=762416
         */

        var features = registry.feature_filter ((f) => {
            return f.get_name ().has_prefix ("vaapi");
        }, false);

        foreach (var feature in features) {
            debug ("Removing registry feature %s", feature.get_name ());
            registry.remove_feature (feature);
        }

        global = new VideoSourceCollection();
        
        Gee.ArrayList<VideoRow?> all = VideoTable.get_instance().get_all();
        Gee.ArrayList<Video> all_videos = new Gee.ArrayList<Video>();
        Gee.ArrayList<Video> trashed_videos = new Gee.ArrayList<Video>();
        Gee.ArrayList<Video> offline_videos = new Gee.ArrayList<Video>();
        int count = all.size;
        for (int ctr = 0; ctr < count; ctr++) {
            Video video = new Video(all.get(ctr));
            
            if (interpreter_state_changed)
                video.set_is_interpretable(false);
            
            if (video.is_trashed())
                trashed_videos.add(video);
            else if (video.is_offline())
                offline_videos.add(video);
            else
                all_videos.add(video);
            
            if (monitor != null)
                monitor(ctr, count);
        }

        global.add_many_to_trash(trashed_videos);
        global.add_many_to_offline(offline_videos);
        global.add_many(all_videos);
    }
    
    public static bool has_interpreter_state_changed() {
        return interpreter_state_changed;
    }
    
    public static void notify_normal_thumbs_regenerated() {
        if (normal_regen_complete)
            return;

        message("normal video thumbnail regeneration completed");

        normal_regen_complete = true;
        if (normal_regen_complete && offline_regen_complete)
            save_interpreter_state();
    }

    public static void notify_offline_thumbs_regenerated() {
        if (offline_regen_complete)
            return;

        message("offline video thumbnail regeneration completed");

        offline_regen_complete = true;
        if (normal_regen_complete && offline_regen_complete)
            save_interpreter_state();
    }

    private static void save_interpreter_state() {
        if (interpreter_state_changed) {
            message("saving video interpreter state to configuration system");

            Config.Facade.get_instance().set_video_interpreter_state_cookie(current_state);
            interpreter_state_changed = false;
        }
    }

    public static void terminate() {
    }
    
    public static ExporterUI? export_many(Gee.Collection<Video> videos, Exporter.CompletionCallback done,
        bool export_in_place = false) {       
        if (videos.size == 0)
            return null;
        
        // in place export is relatively easy -- provide a fast, separate code path for it
        if (export_in_place) {
             ExporterUI temp_exporter = new ExporterUI(new Exporter.for_temp_file(videos,
                Scaling.for_original(), ExportFormatParameters.unmodified()));
             temp_exporter.export(done);
             return temp_exporter;
        }

        // one video
        if (videos.size == 1) {
            Video video = null;
            foreach (Video v in videos) {
                video = v;
                break;
            }
            
            File save_as = ExportUI.choose_file(video.get_basename());
            if (save_as == null)
                return null;
            
            try {
                AppWindow.get_instance().set_busy_cursor();
                video.export(save_as);
                AppWindow.get_instance().set_normal_cursor();
            } catch (Error err) {
                AppWindow.get_instance().set_normal_cursor();
                export_error_dialog(save_as, false);
            }
            
            return null;
        }

        // multiple videos
        File export_dir = ExportUI.choose_dir(_("Export Videos"));
        if (export_dir == null)
            return null;
        
        ExporterUI exporter = new ExporterUI(new Exporter(videos, export_dir,
            Scaling.for_original(), ExportFormatParameters.unmodified()));
        exporter.export(done);

        return exporter;
    }

    protected override void commit_backlinks(SourceCollection? sources, string? backlinks) {        
        try {
            VideoTable.get_instance().update_backlinks(get_video_id(), backlinks);
            lock (backing_row) {
                backing_row.backlinks = backlinks;
            }
        } catch (DatabaseError err) {
            warning("Unable to update link state for %s: %s", to_string(), err.message);
        }
    }

    protected override bool set_event_id(EventID event_id) {
        lock (backing_row) {
            bool committed = VideoTable.get_instance().set_event(backing_row.video_id, event_id);

            if (committed)
                backing_row.event_id = event_id;

            return committed;
        }
    }

    public static bool is_duplicate(File? file, string? full_md5) {
        assert(file != null || full_md5 != null);
#if !NO_DUPE_DETECTION
        return VideoTable.get_instance().has_duplicate(file, full_md5);
#else
        return false;
#endif
    }
    
    public static ImportResult import_create(VideoImportParams params, out Video video) {
        video = null;
        
        // add to the database
        try {
            if (VideoTable.get_instance().add(params.row).is_invalid())
                return ImportResult.DATABASE_ERROR;
        } catch (DatabaseError err) {
            return ImportResult.DATABASE_ERROR;
        }
        
        // create local object but don't add to global until thumbnails generated
        video = new Video(params.row);

        return ImportResult.SUCCESS;
    }
    
    public static void import_failed(Video video) {
        try {
            VideoTable.get_instance().remove(video.get_video_id());
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
    }
    
    public override BackingFileState[] get_backing_files_state() {
        BackingFileState[] backing = new BackingFileState[1];
        lock (backing_row) {
            backing[0] = new BackingFileState(backing_row.filepath, backing_row.filesize, 
                backing_row.timestamp, backing_row.md5);
        }
        
        return backing;
    }
    
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return ThumbnailCache.fetch(this, scale);
    }

    public override string get_master_md5() {
        lock (backing_row) {
            return backing_row.md5;
        }
    }

    public override Gdk.Pixbuf get_preview_pixbuf(Scaling scaling) throws Error {
        Gdk.Pixbuf pixbuf = get_thumbnail(ThumbnailCache.Size.BIG);
        
        return scaling.perform_on_pixbuf(pixbuf, Gdk.InterpType.NEAREST, true);
    }

    public override Gdk.Pixbuf? create_thumbnail(int scale) throws Error {
        VideoReader reader = new VideoReader(get_file());
        Gdk.Pixbuf? frame = reader.read_preview_frame();
        
        return (frame != null) ? frame : Resources.get_noninterpretable_badge_pixbuf().copy();
    }
    
    public override string get_typename() {
        return TYPENAME;
    }
    
    public override int64 get_instance_id() {
        return get_video_id().id;
    }

    public override ImportID get_import_id() {
        lock (backing_row) {
            return backing_row.import_id;
        }
    }

    public override PhotoFileFormat get_preferred_thumbnail_format() {
        return PhotoFileFormat.get_system_default_format();
    }
    
    public override string? get_title() {
        lock (backing_row) {
            return backing_row.title;
        }
    }

    public override void set_title(string? title) {
        string? new_title = prep_title(title);
        
        lock (backing_row) {
            if (backing_row.title == new_title)
                return;

            try {
                VideoTable.get_instance().set_title(backing_row.video_id, new_title);
            } catch (DatabaseError e) {
                AppWindow.database_error(e);
                return;
            }
            // if we didn't short-circuit return in the catch clause above, then the change was
            // successfully committed to the database, so update it in the in-memory row cache
            backing_row.title = new_title;
        }

        notify_altered(new Alteration("metadata", "name"));
    }

    public override string? get_comment() {
        lock (backing_row) {
            return backing_row.comment;
        }
    }

    public override bool set_comment(string? comment) {
        string? new_comment = prep_title(comment);
        
        lock (backing_row) {
            if (backing_row.comment == new_comment)
                return true;

            try {
                VideoTable.get_instance().set_comment(backing_row.video_id, new_comment);
            } catch (DatabaseError e) {
                AppWindow.database_error(e);
                return false;
            }
            // if we didn't short-circuit return in the catch clause above, then the change was
            // successfully committed to the database, so update it in the in-memory row cache
            backing_row.comment = new_comment;
        }
        
        notify_altered(new Alteration("metadata", "comment"));

        return true;
    }


    public override Rating get_rating() {
        lock (backing_row) {
            return backing_row.rating;
        }
    }

    public override void set_rating(Rating rating) {
        lock (backing_row) {
            if ((!rating.is_valid()) || (rating == backing_row.rating))
                return;

            try {
                VideoTable.get_instance().set_rating(get_video_id(), rating);
            } catch (DatabaseError e) {
                AppWindow.database_error(e);
                return;
            }
            // if we didn't short-circuit return in the catch clause above, then the change was
            // successfully committed to the database, so update it in the in-memory row cache
            backing_row.rating = rating;
        }

        notify_altered(new Alteration("metadata", "rating"));
    }

    public override void increase_rating() {
        lock (backing_row) {
            set_rating(backing_row.rating.increase());
        }
    }

    public override void decrease_rating() {
        lock (backing_row) {
            set_rating(backing_row.rating.decrease());
        }
    }

    public override bool is_trashed() {
        return is_flag_set(FLAG_TRASH);
    }

    public override bool is_offline() {
        return is_flag_set(FLAG_OFFLINE);
    }

    public override void mark_offline() {
        add_flags(FLAG_OFFLINE);
    }
    
    public override void mark_online() {
        remove_flags(FLAG_OFFLINE);
        
        if ((!get_is_interpretable()) && has_interpreter_state_changed())
            check_is_interpretable().foreground_finish();
    }

    public override void trash() {
        add_flags(FLAG_TRASH);
    }
    
    public override void untrash() {
        remove_flags(FLAG_TRASH);
    }
    
    public bool is_flagged() {
        return is_flag_set(FLAG_FLAGGED);
    }
    
    public void mark_flagged() {
        add_flags(FLAG_FLAGGED, new Alteration("metadata", "flagged"));
    }
    
    public void mark_unflagged() {
        remove_flags(FLAG_FLAGGED, new Alteration("metadata", "flagged"));
    }
    
    public override EventID get_event_id() {
        lock (backing_row) {
            return backing_row.event_id;
        }
    }
    
    public override string to_string() {
        lock (backing_row) {
            return "[%s] %s".printf(backing_row.video_id.id.to_string(), backing_row.filepath);
        }
    }
    
    public VideoID get_video_id() {
        lock (backing_row) {
            return backing_row.video_id;
        }
    }
    
    public override time_t get_exposure_time() {
        lock (backing_row) {
            return backing_row.exposure_time;
        }
    }
    
    public void set_exposure_time(time_t time) {
        lock (backing_row) {
            try {
                VideoTable.get_instance().set_exposure_time(backing_row.video_id, time);
            } catch (Error e) {
                debug("Warning - %s", e.message);
            }
            backing_row.exposure_time = time;
        }
        
        notify_altered(new Alteration("metadata", "exposure-time"));
    }    
    
    public Dimensions get_frame_dimensions() {
        lock (backing_row) {
            return Dimensions(backing_row.width, backing_row.height);
        }
    }

    public override Dimensions get_dimensions(Photo.Exception disallowed_steps = Photo.Exception.NONE) {
        return get_frame_dimensions();
    }
    
    public override uint64 get_filesize() {
        return get_master_filesize();
    }
    
    public override uint64 get_master_filesize() {
        lock (backing_row) {
            return backing_row.filesize;
        }
    }
    
    public override time_t get_timestamp() {
        lock (backing_row) {
            return backing_row.timestamp;
        }
    }
    
    public void set_master_timestamp(FileInfo info) {
        TimeVal time_val = info.get_modification_time();
        
        try {
            lock (backing_row) {
                if (backing_row.timestamp == time_val.tv_sec)
                    return;
                
                VideoTable.get_instance().set_timestamp(backing_row.video_id, time_val.tv_sec);
                backing_row.timestamp = time_val.tv_sec;
            }
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
            
            return;
        }
        
        notify_altered(new Alteration("metadata", "master-timestamp"));
    }
    
    public string get_filename() {
        lock (backing_row) {
            return backing_row.filepath;
        }
    }
    
    public override File get_file() {
        return File.new_for_path(get_filename());
    }
    
    public override File get_master_file() {
        return get_file();
    }
    
    public void export(File dest_file) throws Error {
        File source_file = File.new_for_path(get_filename());
        source_file.copy(dest_file, FileCopyFlags.OVERWRITE | FileCopyFlags.TARGET_DEFAULT_PERMS,
            null, null);
    }
    
    public double get_clip_duration() {
        lock (backing_row) {
            return backing_row.clip_duration;
        }
    }
    
    public bool get_is_interpretable() {
        lock (backing_row) {
            return backing_row.is_interpretable;
        }
    }
    
    private void set_is_interpretable(bool is_interpretable) {
        lock (backing_row) {
            if (backing_row.is_interpretable == is_interpretable)
                return;
            
            backing_row.is_interpretable = is_interpretable;
        }
        
        try {
            VideoTable.get_instance().update_is_interpretable(get_video_id(), is_interpretable);
        } catch (DatabaseError e) {
            AppWindow.database_error(e);
        }
    }
    
    // Intended to be called from a background thread but can be called from foreground as well.
    // Caller should call InterpretableResults.foreground_process() only from foreground thread,
    // however
    public InterpretableResults check_is_interpretable() {
        InterpretableResults results = new InterpretableResults(this);
        
        double clip_duration = -1.0;
        Gdk.Pixbuf? preview_frame = null;
        
        VideoReader backing_file_reader = new VideoReader(get_file());
        try {
            clip_duration = backing_file_reader.read_clip_duration();
            preview_frame = backing_file_reader.read_preview_frame();
        } catch (VideoError e) {
            // if we catch an error on an interpretable video here, then this video is
            // non-interpretable (e.g. its codec is not present on the users system).
            results.update_interpretable = get_is_interpretable();
            results.is_interpretable = false;
            
            return results;
        }
        
        // if already marked interpretable, this is only confirming what we already knew
        if (get_is_interpretable()) {
            results.update_interpretable = false;
            results.is_interpretable = true;
            
            return results;
        }
        
        debug("video %s has become interpretable", get_file().get_basename());
        
        // save this here, this can be done in background thread
        lock (backing_row) {
            backing_row.clip_duration = clip_duration;
        }
        
        results.update_interpretable = true;
        results.is_interpretable = true;
        results.new_thumbnail = preview_frame;
        
        return results;
    }
    
    public override void destroy() {
        VideoID video_id = get_video_id();

        ThumbnailCache.remove(this);
        
        try {
            VideoTable.get_instance().remove(video_id);
        } catch (DatabaseError err) {
            error("failed to remove video %s from video table", to_string());
        }
        
        base.destroy();
    }

    protected override bool internal_delete_backing() throws Error {
        bool ret = delete_original_file();
        
        // Return false if parent method failed.
        return base.internal_delete_backing() && ret;
    }
    
    private void notify_flags_altered(Alteration? additional_alteration) {
        Alteration alteration = new Alteration("metadata", "flags");
        if (additional_alteration != null)
            alteration = alteration.compress(additional_alteration);
        
        notify_altered(alteration);
    }
    
    public uint64 add_flags(uint64 flags_to_add, Alteration? additional_alteration = null) {
        uint64 new_flags;
        lock (backing_row) {
            new_flags = internal_add_flags(backing_row.flags, flags_to_add);
            if (backing_row.flags == new_flags)
                return backing_row.flags;
            
            try {
                VideoTable.get_instance().set_flags(get_video_id(), new_flags);
            } catch (DatabaseError e) {
                AppWindow.database_error(e);
                return backing_row.flags;
            }
            
            backing_row.flags = new_flags;
        }
        
        notify_flags_altered(additional_alteration);
        
        return new_flags;
    }
    
    public uint64 remove_flags(uint64 flags_to_remove, Alteration? additional_alteration = null) {
        uint64 new_flags;
        lock (backing_row) {
            new_flags = internal_remove_flags(backing_row.flags, flags_to_remove);
            if (backing_row.flags == new_flags)
                return backing_row.flags;
            
            try {
                VideoTable.get_instance().set_flags(get_video_id(), new_flags);
            } catch (DatabaseError e) {
                AppWindow.database_error(e);
                return backing_row.flags;
            }
            
            backing_row.flags = new_flags;
        }
        
        notify_flags_altered(additional_alteration);
        
        return new_flags;
    }
    
    public bool is_flag_set(uint64 flag) {
        lock (backing_row) {
            return internal_is_flag_set(backing_row.flags, flag);
        }
    }
    
    public void set_master_file(File file) {
        string new_filepath = file.get_path();
        string? old_filepath = null;
        try {
            lock (backing_row) {
                if (backing_row.filepath == new_filepath)
                    return;
                
                old_filepath = backing_row.filepath;
                
                VideoTable.get_instance().set_filepath(backing_row.video_id, new_filepath);
                backing_row.filepath = new_filepath;
            }
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
            
            return;
        }
        
        assert(old_filepath != null);
        notify_master_replaced(File.new_for_path(old_filepath), file);
        
        notify_altered(new Alteration.from_list("backing:master,metadata:name"));
    }
    
    public VideoMetadata read_metadata() throws Error {
        return (new VideoReader(get_file())).read_metadata();
    }
}

public class VideoSourceCollection : MediaSourceCollection {
    public enum State {
        UNKNOWN,
        ONLINE,
        OFFLINE,
        TRASH
    }
    
    public override TransactionController transaction_controller {
        get {
            if (_transaction_controller == null)
                _transaction_controller = new MediaSourceTransactionController(this);
            
            return _transaction_controller;
        }
    }
    
    private TransactionController _transaction_controller = null;
    private Gee.MultiMap<uint64?, Video> filesize_to_video =
        new Gee.TreeMultiMap<uint64?, Video>(uint64_compare);
    
    public VideoSourceCollection() {
        base("VideoSourceCollection", get_video_key);

        get_trashcan().contents_altered.connect(on_trashcan_contents_altered);
        get_offline_bin().contents_altered.connect(on_offline_contents_altered);
    }
    
    protected override MediaSourceHoldingTank create_trashcan() {
        return new MediaSourceHoldingTank(this, is_video_trashed, get_video_key);
    }
    
    protected override MediaSourceHoldingTank create_offline_bin() {
        return new MediaSourceHoldingTank(this, is_video_offline, get_video_key);
    }
    
    public override MediaMonitor create_media_monitor(Workers workers, Cancellable cancellable) {
        return new VideoMonitor(cancellable);
    }
    
    public override bool holds_type_of_source(DataSource source) {
        return source is Video;
    }
    
    public override string get_typename() {
        return Video.TYPENAME;
    }
    
    public override bool is_file_recognized(File file) {
        return VideoReader.is_supported_video_file(file);
    }
    
    private void on_trashcan_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        trashcan_contents_altered((Gee.Collection<Video>?) added,
            (Gee.Collection<Video>?) removed);
    }

    private void on_offline_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        offline_contents_altered((Gee.Collection<Video>?) added,
            (Gee.Collection<Video>?) removed);
    }

    protected override MediaSource? fetch_by_numeric_id(int64 numeric_id) {
        return fetch(VideoID(numeric_id));
    }

    public static int64 get_video_key(DataSource source) {
        Video video = (Video) source;
        VideoID video_id = video.get_video_id();
        
        return video_id.id;
    }
    
    public static bool is_video_trashed(DataSource source) {
        return ((Video) source).is_trashed();
    }
    
    public static bool is_video_offline(DataSource source) {
        return ((Video) source).is_offline();
    }
    
    public Video fetch(VideoID video_id) {
        return (Video) fetch_by_key(video_id.id);
    }
    
    public override Gee.Collection<string> get_event_source_ids(EventID event_id){
        return VideoTable.get_instance().get_event_source_ids(event_id);
    }
    
    public Video? get_state_by_file(File file, out State state) {
        Video? video = (Video?) fetch_by_master_file(file);
        if (video != null) {
            state = State.ONLINE;
            
            return video;
        }
        
        video = (Video?) get_trashcan().fetch_by_master_file(file);
        if (video != null) {
            state = State.TRASH;
            
            return video;
        }
        
        video = (Video?) get_offline_bin().fetch_by_master_file(file);
        if (video != null) {
            state = State.OFFLINE;
            
            return video;
        }
        
        state = State.UNKNOWN;
        
        return null;
    }
    
    private void compare_backing(Video video, FileInfo info, Gee.Collection<Video> matching_master) {
        if (video.get_filesize() != info.get_size())
            return;
        
        if (video.get_timestamp() == info.get_modification_time().tv_sec)
            matching_master.add(video);
    }
    
    public void fetch_by_matching_backing(FileInfo info, Gee.Collection<Video> matching_master) {
        foreach (DataObject object in get_all())
            compare_backing((Video) object, info, matching_master);
        
        foreach (MediaSource media in get_offline_bin_contents())
            compare_backing((Video) media, info, matching_master);
    }
    
    protected override void notify_contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added) {
                Video video = (Video) object;
                
                filesize_to_video.set(video.get_master_filesize(), video);
            }
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                Video video = (Video) object;
                
                filesize_to_video.remove(video.get_master_filesize(), video);
            }
        }
        
        base.notify_contents_altered(added, removed);
    }
    
    public VideoID get_basename_filesize_duplicate(string basename, uint64 filesize) {
        foreach (Video video in filesize_to_video.get(filesize)) {
            if (utf8_ci_compare(video.get_master_file().get_basename(), basename) == 0)
                return video.get_video_id();
        }
        
        return VideoID(); // the default constructor of the VideoID struct creates an invalid
                          // video id, which is just what we want in this case
    }
    
    public bool has_basename_filesize_duplicate(string basename, uint64 filesize) {
        return get_basename_filesize_duplicate(basename, filesize).is_valid();
    }
}
