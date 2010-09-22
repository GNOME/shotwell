/* Copyright 2010 Yorba Foundation
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
    
    // IN/OUT:
    public Thumbnails? thumbnails;
    
    // OUT:
    public VideoRow row = VideoRow();
    
    public VideoImportParams(File file, ImportID import_id, string? md5,
        Thumbnails? thumbnails = null) {
        this.file = file;
        this.import_id = import_id;
        this.md5 = md5;
        this.thumbnails = thumbnails;
    }
}

public class VideoReader {
    private const double UNKNOWN_CLIP_DURATION = -1.0;
    
    private double clip_duration = UNKNOWN_CLIP_DURATION;
    private Gdk.Pixbuf preview_frame = null;
    private string filepath = null;
    private Gst.Element colorspace = null;

    public VideoReader(string filepath) {
        this.filepath = filepath;
    }
    
    public static string[] get_supported_file_extensions() {
        string[] result = { "avi", "mpg", "mov", "mts", "ogg", "ogv" };
        return result;
    }
    
    public static bool is_supported_video_file(File file) {
        return is_supported_video_filename(file.get_basename());
    }
    
    public static bool is_supported_video_filename(string filename) {
        string name;
        string extension;
        disassemble_filename(filename, out name, out extension);
        
        return is_in_ci_array(extension, get_supported_file_extensions());
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
        
        TimeVal timestamp;
        info.get_modification_time(out timestamp);
        
        // make sure params has a valid md5
        assert(params.md5 != null);

        time_t exposure_time = 0;
        string title = "";
        
        VideoReader reader = new VideoReader(file.get_path());
        bool is_interpretable = true;
        double clip_duration = 0.0;
        Gdk.Pixbuf? preview_frame = null;
        try {
            clip_duration = reader.read_clip_duration();
            preview_frame = reader.read_preview_frame();
        } catch (VideoError err) {
            if (err is VideoError.FILE) {
                return ImportResult.FILE_ERROR;
            } else if (err is VideoError.CONTENTS) {
                is_interpretable = false;
                preview_frame = Resources.get_noninterpretable_badge_pixbuf();
                clip_duration = 0.0;
            } else {
                error("can't prepare video for import: an unknown kind of video error occurred");
            }
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
        params.row.backlinks = "";
        params.row.time_reimported = 0;

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
        bool does_file_exist = FileUtils.test(filepath, FileTest.EXISTS | FileTest.IS_REGULAR);
        if (!does_file_exist)
            throw new VideoError.FILE("video file '%s' does not exist or is inaccessible".printf(
                filepath));
        
        Gst.Pipeline thumbnail_pipeline = new Gst.Pipeline("thumbnail-pipeline");
        
        Gst.Element thumbnail_source = Gst.ElementFactory.make("filesrc", "source");
        thumbnail_source.set_property("location", filepath);
        
        Gst.Element thumbnail_decode_bin = Gst.ElementFactory.make("decodebin2", "decode-bin");
        
        ThumbnailSink thumbnail_sink = new ThumbnailSink();
        thumbnail_sink.have_thumbnail.connect(on_have_thumbnail);
        
        colorspace = Gst.ElementFactory.make("ffmpegcolorspace", "colorspace");
        
        thumbnail_pipeline.add_many(thumbnail_source, thumbnail_decode_bin, colorspace,
            thumbnail_sink);

        thumbnail_source.link(thumbnail_decode_bin);
        colorspace.link(thumbnail_sink);
        thumbnail_decode_bin.pad_added.connect(on_pad_added);

        // the get_state( ) call is required after the call to set_state( ) to block this
        // thread until the pipeline thread has entered a consistent state
        thumbnail_pipeline.set_state(Gst.State.PLAYING);
        Gst.State from_state;
        Gst.State to_state;
        thumbnail_pipeline.get_state(out from_state, out to_state, 1000000000);

        Gst.Format time_query_format = Gst.Format.TIME;
        int64 video_length = -1;
        thumbnail_pipeline.query_duration(ref time_query_format, out video_length);
        if (video_length != -1)
            clip_duration = ((double) video_length) / 1000000000.0;
        else
            throw new VideoError.CONTENTS("GStreamer couldn't extract clip duration");
        
        thumbnail_pipeline.set_state(Gst.State.NULL);
        
        if (preview_frame == null) {
            clip_duration = UNKNOWN_CLIP_DURATION;
            throw new VideoError.CONTENTS("GStreamer couldn't extract preview frame");
        }
    }
    
    private void on_pad_added(Gst.Pad pad) {
        Gst.Caps c = pad.get_caps();

        if (c.to_string().has_prefix("video")) {
            pad.link(colorspace.get_static_pad("sink"));
        }
    }
    
    private void on_have_thumbnail(Gdk.Pixbuf pixbuf) {
        preview_frame = pixbuf.copy();
    }
    
    public Gdk.Pixbuf read_preview_frame() throws VideoError {
        if (preview_frame == null)
            read_internal();

        return preview_frame;
    }
    
    public double read_clip_duration() throws VideoError {
        if (clip_duration == UNKNOWN_CLIP_DURATION)
            read_internal();

        return clip_duration;
    }
}

// NOTE: this class is adapted from the class of the same name in project marina; see
//       media/src/marina/thumbnailsink.vala
class ThumbnailSink : Gst.BaseSink {
    int width;
    int height;
    
    const string caps_string = """video/x-raw-rgb,bpp = (int) 32, depth = (int) 32,
                                  endianness = (int) BIG_ENDIAN,
                                  blue_mask = (int)  0xFF000000,
                                  green_mask = (int) 0x00FF0000,
                                  red_mask = (int)   0x0000FF00,
                                  width = (int) [ 1, max ],
                                  height = (int) [ 1, max ],
                                  framerate = (fraction) [ 0, max ]""";

    public signal void have_thumbnail(Gdk.Pixbuf b);
    
    class construct {
        Gst.StaticPadTemplate pad;        
        pad.name_template = "sink";
        pad.direction = Gst.PadDirection.SINK;
        pad.presence = Gst.PadPresence.ALWAYS;
        pad.static_caps.str = caps_string;
        
        add_pad_template(pad.get());        
    }
    
    public ThumbnailSink() {
        Object();
        set_sync(false);
    }
    
    public override bool set_caps(Gst.Caps c) {
        if (c.get_size() < 1)
            return false;
            
        Gst.Structure s = c.get_structure(0);
        
        if (!s.get_int("width", out width) ||
            !s.get_int("height", out height))
            return false;
        return true;
    }
    
    void convert_pixbuf_to_rgb(Gdk.Pixbuf buf) {
        uchar* data = buf.get_pixels();
        int limit = buf.get_width() * buf.get_height();
        
        while (limit-- != 0) {
            uchar temp = data[0];
            data[0] = data[2];
            data[2] = temp;
            
            data += 4;
        }
    }
    
    public override Gst.FlowReturn preroll(Gst.Buffer b) {
        Gdk.Pixbuf buf = new Gdk.Pixbuf.from_data(b.data, Gdk.Colorspace.RGB, 
                                                    true, 8, width, height, width * 4, null);
        convert_pixbuf_to_rgb(buf);
               
        have_thumbnail(buf);
        return Gst.FlowReturn.OK;
    }
}

public class Video : VideoSource {
    public static VideoSourceCollection global = null;

    private VideoRow backing_row;
    
    public Video(VideoRow row) {
        this.backing_row = row;
    }

    public static void init() {
        global = new VideoSourceCollection();

        Gee.ArrayList<VideoRow?> all = VideoTable.get_instance().get_all();
        Gee.ArrayList<Video> all_videos = new Gee.ArrayList<Video>();
        int count = all.size;
        for (int ctr = 0; ctr < count; ctr++) {
            Video video = new Video(all.get(ctr));
            all_videos.add(video);
        }
        
        global.add_many(all_videos);
    }

    public static void terminate() {
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
        // add to the database
        try {
            if (VideoTable.get_instance().add(ref params.row).is_invalid())
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

    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return ThumbnailCache.fetch(this, scale);
    }
    
    public override Gdk.Pixbuf? create_thumbnail(int scale) throws Error {
        VideoReader reader = new VideoReader(backing_row.filepath);
        
        try {
            return reader.read_preview_frame();
        } catch (VideoError err) {
            return Resources.get_noninterpretable_badge_pixbuf().copy();
        }
    }
    
    public override string? get_unique_thumbnail_name() {
        return (THUMBNAIL_NAME_PREFIX + "-%016llx".printf(backing_row.video_id.id));
    }
    
    public override PhotoFileFormat get_preferred_thumbnail_format() {
        return PhotoFileFormat.get_system_default_format();
    }
    
    public override string get_name() {
        return get_basename();
    }

    public string get_basename() {
        lock (backing_row) {
            return Filename.display_basename(backing_row.filepath);
        }
    }

    public override string to_string() {
        lock (backing_row) {
            return "[%lld] %s".printf(backing_row.video_id.id, backing_row.filepath);
        }
    }
    
    public VideoID get_video_id() {
        lock (backing_row) {
            return backing_row.video_id;
        }
    }
    
    public time_t get_exposure_time() {
        lock (backing_row) {
            return backing_row.exposure_time;
        }
    }
    
    public Dimensions get_frame_dimensions() {
        lock (backing_row) {
            return Dimensions(backing_row.width, backing_row.height);
        }
    }
    
    public uint64 get_filesize() {
        lock (backing_row) {
            return backing_row.filesize;
        }
    }
    
    public string get_filename() {
        lock (backing_row) {
            return backing_row.filepath;
        }
    }
    
    public override File get_file() {
        return File.new_for_path(get_filename());
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

    public override bool internal_delete_backing() throws Error {
        debug("Deleting %s", to_string());
        
        File backing_file = File.new_for_path(get_filename());
        backing_file.delete(null);
        
        return base.internal_delete_backing();
    }
}

public class VideoSourceCollection : DatabaseSourceCollection {   
    public VideoSourceCollection() {
        base("VideoSourceCollection", get_video_key);
    }
    
    public static int64 get_video_key(DataSource source) {
        Video video = (Video) source;
        VideoID video_id = video.get_video_id();
        
        return video_id.id;
    }
    
    public Video fetch(VideoID video_id) {
        return (Video) fetch_by_key(video_id.id);
    }
}

