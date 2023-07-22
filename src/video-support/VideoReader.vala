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

public class VideoReader {
    private const double UNKNOWN_CLIP_DURATION = -1.0;
    private const uint THUMBNAILER_TIMEOUT = 10000; // In milliseconds.

    // File extensions for video containers that pack only metadata as per the AVCHD spec
    private const string[] METADATA_ONLY_FILE_EXTENSIONS = { "bdm", "bdmv", "cpi", "mpl" };

    private double clip_duration = UNKNOWN_CLIP_DURATION;
    private Gdk.Pixbuf preview_frame = null;
    private File file = null;
    private Subprocess thumbnailer_process = null;
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
        // Guessed mp4/mxf from filename has application/ as prefix, so check for mp4/mxf in the end
        if (mime_type.has_prefix ("video/") ||
            mime_type.has_suffix("mp4") ||
            mime_type.has_suffix("mxf")) {
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

        var timestamp = coarsify_date_time(info.get_modification_date_time());

        // make sure params has a valid md5
        assert(params.md5 != null);

        DateTime exposure_time = params.exposure_time_override;
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

            if (creation_date_time != null && creation_date_time.get_timestamp() != null)
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

        if (exposure_time == null) {
            // Use time reported by Gstreamer, if available.
            exposure_time = reader.timestamp;
        }

        params.row.video_id = VideoID();
        params.row.filepath = file.get_path();
        params.row.filesize = info.get_size();
        params.row.timestamp = timestamp;
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

        uint id = 0;
        try {
            var cancellable = new Cancellable();

            id = Timeout.add_seconds(10, () => {
                cancellable.cancel();
                id = 0;

                return false;
            });

            Bytes stdout_buf = null;
            Bytes stderr_buf = null;

            var process = new GLib.Subprocess(GLib.SubprocessFlags.STDOUT_PIPE, AppDirs.get_metadata_helper().get_path(), file.get_uri());
            var result = process.communicate(null, cancellable, out stdout_buf, out stderr_buf);
            if (result && process.get_if_exited() && process.get_exit_status () == 0 && stdout_buf != null && stdout_buf.get_size() > 0) {
                string[] lines = ((string) stdout_buf.get_data()).split("\n");

                var old = Intl.setlocale(GLib.LocaleCategory.NUMERIC, "C");
                clip_duration = double.parse(lines[0]);
                Intl.setlocale(GLib.LocaleCategory.NUMERIC, old);
                if (lines[1] != "none")
                    timestamp = new DateTime.from_iso8601(lines[1], null);
            } else {
                string message = "";
                if (stderr_buf != null && stderr_buf.get_size() > 0) {
                    message = (string) stderr_buf.get_data();
                }
                warning ("External Metadata helper failed");
            }
        } catch (Error e) {
            debug("Video read error: %s", e.message);
            throw new VideoError.CONTENTS("GStreamer couldn't extract clip information: %s"
                .printf(e.message));
        }

        if (id != 0) {
            Source.remove(id);
        }
    }

    // Used by thumbnailer() to kill the external process if need be.
    private bool on_thumbnailer_timer() {
        debug("Thumbnailer timer called");
        if (thumbnailer_process != null) {
            thumbnailer_process.force_exit();
        }
        return false; // Don't call again.
    }

    // Performs video thumbnailing.
    // Note: not thread-safe if called from the same instance of the class.
    private Gdk.Pixbuf? thumbnailer(string video_file) {
        // Use Shotwell's thumbnailer, redirect output to stdout.
        debug("Launching thumbnailer process: %s", AppDirs.get_thumbnailer_bin().get_path());
        FileIOStream stream;
        File output_file;
        try {
            output_file = File.new_tmp(null, out stream);
        } catch (Error e) {
            debug("Failed to create temporary file: %s", e.message);
            return null;
        }

        try {
            thumbnailer_process = new Subprocess(SubprocessFlags.NONE,
                AppDirs.get_thumbnailer_bin().get_path(), video_file, output_file.get_path());
        } catch (Error e) {
            debug("Error spawning process: %s", e.message);
            return null;
        }

        // Start timer.
        Timeout.add(THUMBNAILER_TIMEOUT, on_thumbnailer_timer);

        // Make sure process exited properly.
        try {
            thumbnailer_process.wait_check();

            // Read pixbuf from stream.
            Gdk.Pixbuf? buf = null;
            try {
                buf = new Gdk.Pixbuf.from_stream(stream.get_input_stream(), null);
                return buf;
            } catch (Error e) {
                debug("Error creating pixbuf: %s", e.message);
            }
        } catch (Error err) {
            debug("Thumbnailer process exited with error: %s", err.message);
        }

        try {
            output_file.delete(null);
        } catch (Error err) {
            debug("Failed to remove temporary file: %s", err.message);
        }
        
        return null;
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
