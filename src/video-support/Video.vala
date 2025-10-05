/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

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
        normal_regen_complete = false;
        offline_regen_complete = false;

        // initialize GStreamer, but don't pass it our actual command line arguments -- we don't
        // want our end users to be able to parameterize the GStreamer configuration
        unowned string[] args = null;
        Gst.init(ref args);

        var registry = Gst.Registry.@get ();

        /* Update our local registry to not include vaapi stuff. This is basically to
         * work-around concurrent access to VAAPI/X11 which it doesn't like, cf
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

    public static void notify_normal_thumbs_regenerated() {
        if (normal_regen_complete)
            return;

        message("normal video thumbnail regeneration completed");

        normal_regen_complete = true;
    }

    public static void notify_offline_thumbs_regenerated() {
        if (offline_regen_complete)
            return;

        message("offline video thumbnail regeneration completed");

        offline_regen_complete = true;
    }

    public static void terminate() {
    }

    public static async ExporterUI? export_many(Gee.Collection<Video> videos, bool export_in_place = false) {
        if (videos.size == 0)
            return null;

        // in place export is relatively easy -- provide a fast, separate code path for it
        if (export_in_place) {
             ExporterUI temp_exporter = new ExporterUI.for_temp_file(videos,
                Scaling.for_original(), ExportFormatParameters.unmodified());
             return temp_exporter;
        }

        // one video
        if (videos.size == 1) {
            Video video = null;
            // We only have a Gee.Collection here, so we have to iterate it
            foreach (Video v in videos) {
                video = v;
                break;
            }

            var save_as = yield  ExportUI.choose_file(video.get_basename());
            if (save_as == null)
                return null;
            try {

                AppWindow.get_instance().set_busy_cursor();
                video.export(save_as);
                AppWindow.get_instance().set_normal_cursor();
            } catch (Error err) {
                AppWindow.get_instance().set_normal_cursor();
                var message = _("Unable to export the following video due to a file error.\n\n") +
                            save_as.get_path();
                AppWindow.error_message(message);
            }
    
            return null;
        }

        // multiple videos
        var export_dir = yield ExportUI.choose_dir(_("Export Videos"));
        if (export_dir == null)
            return null;

        ExporterUI exporter = new ExporterUI(videos, export_dir,
            Scaling.for_original(), ExportFormatParameters.unmodified());

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

        if ((!get_is_interpretable()))
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

    public override DateTime? get_exposure_time() {
        lock (backing_row) {
            return backing_row.exposure_time;
        }
    }

    public void set_exposure_time(DateTime time) {
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

    public override DateTime? get_timestamp() {
        lock (backing_row) {
            return backing_row.timestamp;
        }
    }

    public void set_master_timestamp(FileInfo info) {
        var time_val = info.get_modification_date_time();

        try {
            lock (backing_row) {
                if (backing_row.timestamp.equal(time_val))
                    return;

                VideoTable.get_instance().set_timestamp(backing_row.video_id, time_val);
                backing_row.timestamp = time_val;
            }
        } catch (Error err) {
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
        } catch (Error err) {
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
