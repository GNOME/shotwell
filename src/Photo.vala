/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// PhotoBase is the base class for all objects which represent, in some form or another, an image
// or photo.
public abstract class PhotoBase : Object, Queryable, PhotoSource {
    public PhotoBase() {
    }
    
    // Queryable
    
    public abstract string get_name();
    
    // PhotoSource

    public abstract time_t get_exposure_time();

    public abstract Dimensions get_dimensions();

    public abstract uint64 get_filesize();

    public abstract Exif.Data? get_exif();
}

// PhotoCollection represents a grouping of photos.
public interface PhotoCollection : Object {
    public abstract int get_count();
    
    public abstract PhotoBase? get_first_photo();
    
    public abstract PhotoBase? get_last_photo();
    
    public abstract PhotoBase? get_next_photo(PhotoBase current);
    
    public abstract PhotoBase? get_previous_photo(PhotoBase current);
}

public enum ImportResult {
    SUCCESS,
    FILE_ERROR,
    DECODE_ERROR,
    DATABASE_ERROR,
    USER_ABORT,
    NOT_A_FILE,
    PHOTO_EXISTS,
    UNSUPPORTED_FORMAT;
    
    public string to_string() {
        switch (this) {
            case SUCCESS:
                return "Success";
            
            case FILE_ERROR:
                return "File error";
            
            case DECODE_ERROR:
                return "Unable to decode file";
            
            case DATABASE_ERROR:
                return "Database error";
            
            case USER_ABORT:
                return "User aborted import";
            
            case NOT_A_FILE:
                return "Not a file";
            
            case PHOTO_EXISTS:
                return "File already exists in database";
            
            case UNSUPPORTED_FORMAT:
                return "Unsupported file format";
            
            default:
                error("Bad import result: %d", (int) this);
                
                return "Bad import result (%d)".printf((int) this);
        }
    }
}

// TransformablePhoto is an abstract class that allows for applying transformations on-the-fly to a
// particular photo without modifying the backing image file.  The interface allows for
// transformations to be stored persistently elsewhere or in memory until they're commited en
// masse to an image file.
public abstract class TransformablePhoto: PhotoBase {
    public const int UNSCALED = 0;
    public const int SCREEN = -1;
    
    public const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.HYPER;
    
    public const Jpeg.Quality EXPORT_JPEG_QUALITY = Jpeg.Quality.HIGH;
    public const Gdk.InterpType EXPORT_INTERP = Gdk.InterpType.HYPER;
    
    public const string[] SUPPORTED_EXTENSIONS = {
        "jpg",
        "jpeg",
        "jpe"
    };
    
    public enum Exception {
        NONE            = 0,
        ORIENTATION     = 1 << 0,
        CROP            = 1 << 1,
        REDEYE          = 1 << 2,
        ADJUST          = 1 << 3,
        ENHANCE         = 1 << 4,
        ALL             = 0xFFFFFFFF
    }
    
    public enum Alteration {
        IMAGE,
        METADATA
    }
    
    protected static PhotoTable photo_table = null;

    private static PhotoID cached_photo_id = PhotoID();
    private static Gdk.Pixbuf cached_raw = null;
    
    protected PhotoID photo_id;
    
    // because fetching some items from the database is high-overhead, certain items are cached
    // here ... really want to be frugal about this, as maintaining coherency is complicated enough
    private time_t exposure_time = -1;
    
    // fired when the image itself (its visual representation) has changed
    public signal void altered();
    
    // fired when information about the image has changed
    public signal void metadata_altered();
    
    // The key to this implementation is that multiple instances of TransformablePhoto with the
    // same PhotoID cannot exist; it is up to the subclasses to ensure this.
    protected TransformablePhoto(PhotoID photo_id) {
        this.photo_id = photo_id;
    }
    
    protected static void base_init() {
        if (photo_table == null)
            photo_table = new PhotoTable();
    }
    
    protected static void base_terminate() {
    }
    
    public static ImportResult import_photo(File file, ImportID import_id, out PhotoID photo_id,
        out Gdk.Pixbuf pixbuf) {
        if (photo_table.is_photo_stored(file))
            return ImportResult.PHOTO_EXISTS;
        
        debug("Importing file %s", file.get_path());

        FileInfo info = null;
        try {
            info = file.query_info("*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            return ImportResult.FILE_ERROR;
        }
        
        if (info.get_file_type() != FileType.REGULAR)
            return ImportResult.NOT_A_FILE;
        
        if (info.get_content_type() != GPhoto.MIME.JPEG) {
            message("Not importing %s: Unsupported content type %s", file.get_path(),
                info.get_content_type());

            return ImportResult.UNSUPPORTED_FORMAT;
        }
        
        TimeVal timestamp = TimeVal();
        info.get_modification_time(timestamp);
        
        Dimensions dim = Dimensions();
        Orientation orientation = Orientation.TOP_LEFT;
        time_t exposure_time = 0;
        
        // TODO: Try to read JFIF metadata too
        PhotoExif exif = new PhotoExif(file);
        if (exif.has_exif()) {
            if (!exif.get_dimensions(out dim))
                message("Unable to read EXIF dimensions for %s", file.get_path());
            
            if (!exif.get_timestamp(out exposure_time))
                message("Unable to read EXIF orientation for %s", file.get_path());

            orientation = exif.get_orientation();
        }
        
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            // assume a decode error, although technically it could be I/O ... need better Gdk
            // bindings to determine which
            return ImportResult.DECODE_ERROR;
        }
        
        // verify basic mechanics of photo: RGB 8-bit encoding
        if (pixbuf.get_colorspace() != Gdk.Colorspace.RGB || pixbuf.get_n_channels() < 3 
            || pixbuf.get_bits_per_sample() != 8) {
            message("Not importing %s: Unsupported color format", file.get_path());
            
            return ImportResult.UNSUPPORTED_FORMAT;
        }
        
        // XXX: Trust EXIF or Pixbuf for dimensions?
        if (!dim.has_area())
            dim = Dimensions(pixbuf.get_width(), pixbuf.get_height());

        // photo information is stored in database in raw, non-modified format ... this is especially
        // important dealing with dimensions and orientation
        photo_id = photo_table.add(file, dim, info.get_size(), timestamp.tv_sec, exposure_time,
            orientation, import_id);
        if (photo_id.is_invalid())
            return ImportResult.DATABASE_ERROR;
        
        // transform pixbuf into initial image
        pixbuf = orientation.rotate_pixbuf(pixbuf);
        
        return ImportResult.SUCCESS;
    }
    
    public static bool is_file_supported(File file) {
        string name, ext;
        disassemble_filename(file.get_basename(), out name, out ext);
        if (ext == null)
            return false;
        
        // treat extensions as case-insensitive
        ext = ext.down();
        
        // search supported list
        foreach (string supported in SUPPORTED_EXTENSIONS) {
            if (ext == supported)
                return true;
        }
        
        return false;
    }
    
    public File get_file() {
        return photo_table.get_file(photo_id);
    }
    
    public time_t get_timestamp() {
        return photo_table.get_timestamp(photo_id);
    }

    public PhotoID get_photo_id() {
        return photo_id;
    }
    
    public string to_string() {
        return "[%lld] %s".printf(photo_id.id, get_file().get_path());
    }

    public bool equals(TransformablePhoto photo) {
        // identity works because of the photo_map, but the photo_table primary key is where the
        // rubber hits the road
        if (this == photo) {
            assert(photo_id.id == photo.photo_id.id);
            
            return true;
        }
        
        assert(photo_id.id != photo.photo_id.id);
        
        return false;
    }
    
    protected virtual void on_altered() {
    }
    
    protected virtual void on_metadata_altered() {
    }
    
    // This first allows the subclass to react to the event change, then notify listeners
    protected void notify_altered(Alteration alteration) {
        switch (alteration) {
            case Alteration.IMAGE:
                on_altered();
                altered();
            break;
            
            case Alteration.METADATA:
                // cache coherency
                exposure_time = photo_table.get_exposure_time(photo_id);
                
                on_metadata_altered();
                metadata_altered();
            break;
            
            default:
                error("Unknown alteration: %d", (int) alteration);
            break;
        }
    }
    
    public void update() {
        File file = get_file();
        
        Dimensions dim = Dimensions();
        Orientation orientation = Orientation.TOP_LEFT;
        time_t exposure_time = 0;

        // TODO: Try to read JFIF metadata too
        PhotoExif exif = new PhotoExif(file);
        if (exif.has_exif()) {
            if (!exif.get_dimensions(out dim))
                error("Unable to read EXIF dimensions for %s", to_string());
            
            if (!exif.get_timestamp(out exposure_time))
                error("Unable to read EXIF orientation for %s", to_string());

            orientation = exif.get_orientation();
        } 
    
        FileInfo info = null;
        try {
            info = file.query_info("*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            error("Unable to read file information for %s: %s", to_string(), err.message);
        }
        
        TimeVal timestamp = TimeVal();
        info.get_modification_time(timestamp);
        
        if (photo_table.update(photo_id, dim, info.get_size(), timestamp.tv_sec, exposure_time,
            orientation)) {
            // because image has changed, all transformations are suspect
            photo_table.remove_all_transformations(photo_id);
            
            // remove from decode cache as well
            if (cached_photo_id.id == photo_id.id)
                cached_raw = null;
            
            // could be both
            notify_altered(Alteration.METADATA);
            notify_altered(Alteration.IMAGE);
        }
    }

    // Queryable
    
    public override string get_name() {
        return photo_table.get_name(photo_id);
    }
    
    // PhotoSource
    
    public override uint64 get_filesize() {
        return photo_table.get_filesize(photo_id);
    }
    
    public override time_t get_exposure_time() {
        if (exposure_time == -1)
            exposure_time = photo_table.get_exposure_time(photo_id);
        
        return exposure_time;
    }
    
    // Returns cropped and rotated dimensions
    public override Dimensions get_dimensions() {
        Box crop;
        if (get_crop(out crop))
            return crop.get_dimensions();
        
        return get_uncropped_dimensions();
    }

    public override Exif.Data? get_exif() {
        PhotoExif photo_exif = new PhotoExif(get_file());
        
        return photo_exif.has_exif() ? photo_exif.get_exif() : null;
    }
    
    // Transformation storage and exporting

    public Dimensions get_raw_dimensions() {
        return photo_table.get_dimensions(photo_id);
    }

    public bool has_transformations() {
        // trivial check -- if the photo has been reoriented, then it has transformations
        if (photo_table.get_orientation(photo_id) != photo_table.get_original_orientation(photo_id))
            return true;

        // if execution reaches this point, we didn't return above, so perform a more
        // complicated series of tests
        if (!photo_table.has_transformations(photo_id))
            return false;
        if ((photo_table.get_transformation_count(photo_id) == 1) &&
            (photo_table.get_transformation(photo_id, "enhancement") != null) &&
            (!is_enhancement_enabled()))
            return false;
        
        // if we haven't returned by this point, then we have transformations other
        // than disabled enhancement, so return true
        return true;
    }
    
    public void remove_all_transformations() {
        bool altered = photo_table.remove_all_transformations(photo_id);
        
        Orientation orientation = photo_table.get_orientation(photo_id);
        Orientation original_orientation = photo_table.get_original_orientation(photo_id);
        if (orientation != original_orientation) {
            photo_table.set_orientation(photo_id, original_orientation);
            altered = true;
        }

        if (altered)
            notify_altered(Alteration.IMAGE);
    }
    
    public Orientation get_orientation() {
        return photo_table.get_orientation(photo_id);
    }
    
    public void set_orientation(Orientation orientation) {
        photo_table.set_orientation(photo_id, orientation);
        
        notify_altered(Alteration.IMAGE);
    }
    
    public virtual void rotate(Rotation rotation) {
        Orientation orientation = get_orientation();

        orientation = orientation.perform(rotation);

        set_orientation(orientation);
    }
    
    public bool has_crop() {
        return photo_table.get_transformation(photo_id, "crop") != null;
    }
    
    // Returns the crop in the raw photo's coordinate system
    private bool get_raw_crop(out Box crop) {
        KeyValueMap map = photo_table.get_transformation(photo_id, "crop");
        if (map == null)
            return false;
        
        int left = map.get_int("left", -1);
        int top = map.get_int("top", -1);
        int right = map.get_int("right", -1);
        int bottom = map.get_int("bottom", -1);
        
        if (left == -1 || top == -1 || right == -1 || bottom == -1)
            return false;
        
        crop = Box(left, top, right, bottom);
        
        return true;
    }
    
    // Sets the crop using the raw photo's unrotated coordinate system
    private void set_raw_crop(Box crop) {
        KeyValueMap map = new KeyValueMap("crop");
        map.set_int("left", crop.left);
        map.set_int("top", crop.top);
        map.set_int("right", crop.right);
        map.set_int("bottom", crop.bottom);
        
        if (photo_table.set_transformation(photo_id, map))
            notify_altered(Alteration.IMAGE);
    }
    
    public float get_color_adjustment(RGBTransformationKind adjust_kind) {
        KeyValueMap map = photo_table.get_transformation(photo_id, "adjustments");
        if (map == null)
            return 0.0f;
        
        switch (adjust_kind) {
            case RGBTransformationKind.EXPOSURE:
                return (float) map.get_double("exposure", 0.0f);

            case RGBTransformationKind.SATURATION:
                return (float) map.get_double("saturation", 0.0f);

            case RGBTransformationKind.TEMPERATURE:
                return (float) map.get_double("temperature", 0.0f);

            case RGBTransformationKind.TINT:
                return (float) map.get_double("tint", 0.0f);

            default:
                error("unrecognized RGBTransformationKind enumeration value");
                
                return 0.0f;
        }
    }
    
    public void set_color_adjustments(Gee.ArrayList<RGBTransformationInstance?> adjustments) {
        KeyValueMap map = photo_table.get_transformation(photo_id, "adjustments");
        if (map == null)
            map = new KeyValueMap("adjustments");
        
        foreach (RGBTransformationInstance adjustment in adjustments) {
            switch(adjustment.kind) {
                case RGBTransformationKind.EXPOSURE:
                    map.set_double("exposure", adjustment.parameter);
                break;

                case RGBTransformationKind.SATURATION:
                    map.set_double("saturation", adjustment.parameter);
                break;

                case RGBTransformationKind.TEMPERATURE:
                    map.set_double("temperature", adjustment.parameter);
                break;

                case RGBTransformationKind.TINT:
                    map.set_double("tint", adjustment.parameter);
                break;

                default:
                    error("unrecognized RGBTransformationKind enumeration value");
                break;
            }
        }

        if (photo_table.set_transformation(photo_id, map))
            notify_altered(Alteration.IMAGE);
    }

    // All instances are against the coordinate system of the unscaled, unrotated photo.
    private RedeyeInstance[] get_raw_redeye_instances() {
        KeyValueMap map = photo_table.get_transformation(photo_id, "redeye");
        if (map == null)
            return new RedeyeInstance[0];
            
        int num_points = map.get_int("num_points", -1);
        assert(num_points > 0);

        RedeyeInstance[] res = new RedeyeInstance[num_points];

        Gdk.Point default_point = {0};
        default_point.x = -1;
        default_point.y = -1;

        for (int i = 0; i < num_points; i++) {
            string center_key = "center%d".printf(i);
            string radius_key = "radius%d".printf(i);

            res[i].center = map.get_point(center_key, default_point);
            assert(res[i].center.x != default_point.x);
            assert(res[i].center.y != default_point.y);

            res[i].radius = map.get_int(radius_key, -1);
            assert(res[i].radius != -1);
        }

        return res;
    }

    // All instances are against the coordinate system of the unrotated photo.
    private void add_raw_redeye_instance(RedeyeInstance redeye) {
        KeyValueMap map = photo_table.get_transformation(photo_id, "redeye");
        if (map == null) {
            map = new KeyValueMap("redeye");
            map.set_int("num_points", 0);
        }
        
        int num_points = map.get_int("num_points", -1);
        assert(num_points >= 0);
        
        num_points++;
        
        string radius_key = "radius%d".printf(num_points - 1);
        string center_key = "center%d".printf(num_points - 1);
        
        map.set_int(radius_key, redeye.radius);
        map.set_point(center_key, redeye.center);
        
        map.set_int("num_points", num_points);

        if (photo_table.set_transformation(photo_id, map))
            notify_altered(Alteration.IMAGE);
    }

    public void set_enhancement_enabled() {
        KeyValueMap map = photo_table.get_transformation(photo_id,
            "enhancement");

        if (map == null) {
            map = new KeyValueMap("enhancement");
        }

        if (!map.has_key("encoded_transformation")) {
            Gdk.Pixbuf histogram_pixbuf = null;        
            try {
                histogram_pixbuf = get_pixbuf(1024, Exception.ALL, Gdk.InterpType.HYPER);
            } catch (Error e) {
                error("pixbuf generation failed");
            }
            IntensityTransformation transform =
                EnhancementFactory.create_current(histogram_pixbuf);
            map.set_int("version", EnhancementFactory.get_current_version());
            map.set_string("encoded_transformation", transform.to_string());
        }

        map.set_bool("enhanced", true);

        if (photo_table.set_transformation(photo_id, map))
            notify_altered(Alteration.IMAGE);
    }
    
    public void set_enhancement_disabled() {
        KeyValueMap map = photo_table.get_transformation(photo_id,
            "enhancement");

        if (map == null) {
            map = new KeyValueMap("enhancement");
        }
        
        map.set_bool("enhanced", false);

        if (photo_table.set_transformation(photo_id, map))
            notify_altered(Alteration.IMAGE);
    }
    
    private IntensityTransformation get_enhancement_transformation() {
        assert(is_enhancement_enabled());
        
        KeyValueMap map = photo_table.get_transformation(photo_id,
            "enhancement");
        assert(map != null);
        assert(map.has_key("encoded_transformation"));
        
        string encoded_transformation = map.get_string("encoded_transformation",
            "");
        assert(encoded_transformation != "");
        
        int version = map.get_int("version", 0);

        return EnhancementFactory.create_from_encoding(version,
            encoded_transformation);
    }
    
    public bool is_enhancement_enabled() {
        KeyValueMap map = photo_table.get_transformation(photo_id,
            "enhancement");

        /* if there's no enhancement group in the map, then enhancement is
           disabled */
        if (map == null)
            return false;

        /* if there is an enhancement group in the map, but the "enhanced" key
           has value false, then enhancement is disabled */
        if (!map.get_bool("enhanced", true))
            return false;

        /* if enhanced is set to true in the map, but the encoding version used
           is unsupported, then enhancement is disabled */
        if (!EnhancementFactory.is_encoding_version_supported(map.get_int("version", 0)))
            return false;
        
        /* otherwise, enhancement is enabled */
        return true;
    }

    // Pixbuf generation

    // Returns a raw, untransformed, unrotated, unscaled pixbuf from the source
    public Gdk.Pixbuf get_raw_pixbuf() throws Error {
        return new Gdk.Pixbuf.from_file(get_file().get_path());
    }

    // Converts a scale parameter for get_pixbuf or get_preview_pixbuf into an actual pixel
    // count to proportionally scale to.  Returns 0 if an unscaled pixbuf is specified.
    public static int scale_to_pixels(int scale) {
        return (scale == SCREEN) ? get_screen_scale() : scale;
    }

    // Returns a raw, untransformed, unscaled pixbuf from the source that has been rotated
    // according to its original EXIF settings
    public Gdk.Pixbuf get_original_pixbuf(int scale, Gdk.InterpType interp = DEFAULT_INTERP) throws Error {
#if MEASURE_PIPELINE
        Timer timer = new Timer();
        Timer total_timer = new Timer();
        double load_and_decode_time = 0.0, pixbuf_copy_time = 0.0, scale_time = 0.0,
            orientation_time = 0.0;
        
        total_timer.start();
#endif

        Gdk.Pixbuf pixbuf = null;
        
        if (cached_raw != null && cached_photo_id.id == photo_id.id) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = cached_raw.copy();
#if MEASURE_PIPELINE
            pixbuf_copy_time = timer.elapsed();
#endif
        } else {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = get_raw_pixbuf();
#if MEASURE_PIPELINE
            load_and_decode_time = timer.elapsed();
            
            timer.start();
#endif
            cached_raw = pixbuf.copy();
#if MEASURE_PIPELINE
            pixbuf_copy_time = timer.elapsed();
#endif
            cached_photo_id = photo_id;
        }
        
        // scale
#if MEASURE_PIPELINE
        timer.start();
#endif
        int pixels = scale_to_pixels(scale);
        if (pixels > 0)
            pixbuf = scale_pixbuf(pixbuf, pixels, interp);
#if MEASURE_PIPELINE
        scale_time = timer.elapsed();
#endif
        
        // orientation
#if MEASURE_PIPELINE
        timer.start();
#endif
        Orientation orientation = photo_table.get_original_orientation(photo_id);
        pixbuf = orientation.rotate_pixbuf(pixbuf);
#if MEASURE_PIPELINE
        orientation_time = timer.elapsed();

        debug("ORIGINAL PIPELINE: load_and_decode=%lf pixbuf_copy=%lf scale=%lf orientation=%lf total=%lf",
            load_and_decode_time, pixbuf_copy_time, scale_time, orientation_time, total_timer.elapsed());
#endif
        
        return pixbuf;
    }

    // A preview pixbuf is one that can be quickly generated and scaled as a preview while the
    // fully transformed pixbuf is built.  It is fully transformed.
    //
    // Note that scale may be UNSCALED or SCREEN.  UNSCALED is not 
    // considered a performance-killer for this method, although the quality of the pixbuf may be 
    // quite poor compared to the actual unscaled transformed pixbuf.
    public abstract Gdk.Pixbuf get_preview_pixbuf(int scale) throws Error;
    
    // Returns a fully transformed (and scaled, if specified) pixbuf from the source.
    // Transformations may be excluded via the mask.
    //
    // Set scale to UNSCALED for unscaled pixbuf or SCREEN for a pixbuf scaled to the screen size
    // (which can be scaled further, with some loss).  Note that UNSCALED can be extremely expensive, 
    // and it's far better to specify an appropriate scale.
    public virtual Gdk.Pixbuf get_pixbuf(int scale, Exception exceptions = Exception.NONE,
        Gdk.InterpType interp = DEFAULT_INTERP) throws Error {
#if MEASURE_PIPELINE
        Timer timer = new Timer();
        Timer total_timer = new Timer();
         double load_and_decode_time = 0.0, pixbuf_copy_time = 0.0, redeye_time = 0.0, 
            adjustment_time = 0.0, crop_time = 0.0, orientation_time = 0.0, scale_time = 0.0,
            enhance_time = 0.0;

        total_timer.start();
#endif
        Gdk.Pixbuf pixbuf = null;
        
        //
        // Image load-and-decode
        //
        
        if (cached_raw != null && cached_photo_id.id == photo_id.id) {
            // used the cached raw pixbuf for this instance, which is merely the decoded pixbuf
            // (no transformations)
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = cached_raw.copy();
#if MEASURE_PIPELINE
            pixbuf_copy_time = timer.elapsed();
#endif
        } else {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = get_raw_pixbuf();
#if MEASURE_PIPELINE
            load_and_decode_time = timer.elapsed();
#endif
        
            // stash for next time
#if MEASURE_PIPELINE
            timer.start();
#endif
            cached_raw = pixbuf.copy();
#if MEASURE_PIPELINE
            pixbuf_copy_time = timer.elapsed();
#endif
            cached_photo_id = photo_id;
        }

        //
        // Image transformation pipeline
        //

        // redeye reduction
        if ((exceptions & Exception.REDEYE) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            RedeyeInstance[] redeye_instances = get_raw_redeye_instances();
            foreach (RedeyeInstance instance in redeye_instances)
                pixbuf = do_redeye(pixbuf, instance);
#if MEASURE_PIPELINE
            redeye_time = timer.elapsed();
#endif
        }

        // crop
        if ((exceptions & Exception.CROP) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            Box crop;
            if (get_raw_crop(out crop))
                pixbuf = new Gdk.Pixbuf.subpixbuf(pixbuf, crop.left, crop.top, crop.get_width(),
                    crop.get_height());

#if MEASURE_PIPELINE
            crop_time = timer.elapsed();
#endif
        }
        
        // scale
        int scale_pixels = scale_to_pixels(scale);
        if (scale_pixels > 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = scale_pixbuf(pixbuf, scale_pixels, interp);
#if MEASURE_PIPELINE
            scale_time = timer.elapsed();
#endif
        }

        // color adjustment
        if ((exceptions & Exception.ADJUST) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            RGBTransformation composite_transform = get_composite_transformation();
            if (!composite_transform.is_identity())
                RGBTransformation.transform_pixbuf(composite_transform, pixbuf);
#if MEASURE_PIPELINE
            adjustment_time = timer.elapsed();
#endif
        }
        
        // auto-enhancement
        if ((exceptions & Exception.ENHANCE) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            if (is_enhancement_enabled()) {
                IntensityTransformation adaptive_transform =
                    get_enhancement_transformation();
                IntensityTransformation.transform_pixbuf(adaptive_transform, pixbuf);
            }

#if MEASURE_PIPELINE
            enhance_time = timer.elapsed();
#endif
        }

        // orientation (all modifications are stored in unrotated coordinate system)
        if ((exceptions & Exception.ORIENTATION) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = get_orientation().rotate_pixbuf(pixbuf);
#if MEASURE_PIPELINE
            orientation_time = timer.elapsed();
#endif
        }
        
#if MEASURE_PIPELINE
        double total_time = total_timer.elapsed();
        
        debug("PIPELINE: load_and_decode=%lf pixbuf_copy=%lf redeye=%lf crop=%lf scale=%lf adjustment=%lf enhancement=%lf orientation=%lf total=%lf",
            load_and_decode_time, pixbuf_copy_time, redeye_time, crop_time, scale_time, adjustment_time, 
            enhance_time, orientation_time, total_time);
#endif
        
        return pixbuf;
    }
    
    //
    // File export
    //
    
    // Returns a File object to create an unscaled copy of the photo suitable for exporting.  If
    // the file exists, that is considered export-ready (allowing for exportables to persist).
    // If it does not, it will be generated.
    public abstract File generate_exportable_file();

    // Returns a File of the unscaled image suitable for exporting ... this file should persist 
    // for a reasonable amount of time, as drag-and-drop exports can conclude long after the DnD 
    // source has seen the end of the transaction. ... However, if failure is detected, 
    // export_failed() will be called, and the file can be removed if necessary.
    //
    // TODO: Lossless transformations, especially for mere rotations of JFIF files.
    public File generate_exportable() throws Error {
        if (!has_transformations())
            return get_file();

        File dest_file = generate_exportable_file();
        if (dest_file.query_exists(null))
            return dest_file;
        
        // generate_exportable_file only generates a filename; create directory if necessary
        File dest_dir = dest_file.get_parent();
        if (!dest_dir.query_exists(null))
            dest_dir.make_directory_with_parents(null);
        
        File original_file = get_file();
        Exif.Data original_exif = get_exif();
        
        // if only rotated, only need to copy and modify the EXIF
        if (!photo_table.has_transformations(photo_id) && original_exif != null) {
            original_file.copy(dest_file, FileCopyFlags.OVERWRITE, null, null);

            PhotoExif dest_exif = new PhotoExif(dest_file);
            dest_exif.set_orientation(photo_table.get_orientation(photo_id));
            dest_exif.commit();
        } else {
            Gdk.Pixbuf pixbuf = get_pixbuf(UNSCALED);
            pixbuf.save(dest_file.get_path(), "jpeg", "quality", EXPORT_JPEG_QUALITY.get_pct_text());
            copy_exported_exif(original_exif, new PhotoExif(dest_file), Orientation.TOP_LEFT,
                Dimensions.for_pixbuf(pixbuf));
        }
        
        return dest_file;
    }
    
    // Called when a generate_exportable has failed; the object can use this to delete the exportable 
    // file from generate_exportable_file() if necessary
    public virtual void export_failed() {
    }
    
    public static void copy_exported_exif(Exif.Data source, PhotoExif dest, Orientation orientation, 
        Dimensions dim) throws Error {
        dest.set_exif(source);
        dest.set_dimensions(dim);
        dest.set_orientation(orientation);
        dest.remove_all_tags(Exif.Tag.RELATED_IMAGE_WIDTH);
        dest.remove_all_tags(Exif.Tag.RELATED_IMAGE_LENGTH);
        dest.remove_thumbnail();
        dest.commit();
    }

    // Writes a file meeting the specified parameters.
    //
    // TODO: Lossless transformations, especially for mere rotations of JFIF files.
    public void export(File dest_file, int scale, ScaleConstraint constraint,
        Jpeg.Quality quality) throws Error {
        if (constraint == ScaleConstraint.ORIGINAL) {
            // generate a raw exportable file and copy that
            File exportable = generate_exportable();

            try {
                exportable.copy(dest_file, FileCopyFlags.OVERWRITE | FileCopyFlags.ALL_METADATA,
                    null, null);
            } catch (Error err) {
                export_failed();
                
                throw err;
            }
            
            return;
        }
        
        Gdk.Pixbuf pixbuf = get_pixbuf(UNSCALED);
        Dimensions dim = Dimensions.for_pixbuf(pixbuf);
        Dimensions scaled = dim.get_scaled_by_constraint(scale, constraint);

        // only scale if necessary ... although scale_simple probably catches this, it's an easy
        // check to avoid image loss
        if (dim.width != scaled.width || dim.height != scaled.height)
            pixbuf = pixbuf.scale_simple(scaled.width, scaled.height, EXPORT_INTERP);
        
        try {
            pixbuf.save(dest_file.get_path(), "jpeg", "quality", quality.get_pct_text());
            
            Exif.Data exif = get_exif();
            if (exif != null)
                copy_exported_exif(exif, new PhotoExif(dest_file), Orientation.TOP_LEFT, scaled);
        } catch (Error err) {
            export_failed();
            
            throw err;
        }
    }
    
    // Aggregate/helper/translation functions
    
    // Returns uncropped (but rotated) dimensions
    public Dimensions get_uncropped_dimensions() {
        Dimensions dim = get_raw_dimensions();
        Orientation orientation = get_orientation();
        
        return orientation.rotate_dimensions(dim);
    }
    
    // Returns the crop against the coordinate system of the rotated photo
    public bool get_crop(out Box crop) {
        Box raw;
        if (!get_raw_crop(out raw))
            return false;
        
        Dimensions dim = get_raw_dimensions();
        Orientation orientation = get_orientation();
        
        crop = orientation.rotate_box(dim, raw);
        
        return true;
    }
    
    // Sets the crop against the coordinate system of the rotated photo
    public void set_crop(Box crop) {
        Dimensions dim = get_raw_dimensions();
        Orientation orientation = get_orientation();

        Box derotated = orientation.derotate_box(dim, crop);
        
        assert(derotated.get_width() <= dim.width);
        assert(derotated.get_height() <= dim.height);
        
        set_raw_crop(derotated);
    }
    
    public void add_redeye_instance(RedeyeInstance inst_unscaled) {
        Gdk.Rectangle bounds_rect_unscaled = RedeyeInstance.to_bounds_rect(inst_unscaled);
        Gdk.Rectangle bounds_rect_raw = unscaled_to_raw_rect(bounds_rect_unscaled);
        RedeyeInstance inst = RedeyeInstance.from_bounds_rect(bounds_rect_raw);
        
        add_raw_redeye_instance(inst);
    }

    private Gdk.Pixbuf do_redeye(owned Gdk.Pixbuf pixbuf, owned RedeyeInstance inst) {
        /* we remove redeye within a circular region called the "effect
           extent." the effect extent is inscribed within its "bounding
           rectangle." */

        /* for each scanline in the top half-circle of the effect extent,
           compute the number of pixels by which the effect extent is inset
           from the edges of its bounding rectangle. note that we only have
           to do this for the first quadrant because the second quadrant's
           insets can be derived by symmetry */
        double r = (double) inst.radius;
        int[] x_insets_first_quadrant = new int[inst.radius + 1];
        
        int i = 0;
        for (double y = r; y >= 0.0; y -= 1.0) {
            double theta = Math.asin(y / r);
            int x = (int)((r * Math.cos(theta)) + 0.5);
            x_insets_first_quadrant[i] = inst.radius - x;
            
            i++;
        }

        int x_bounds_min = inst.center.x - inst.radius;
        int x_bounds_max = inst.center.x + inst.radius;
        int ymin = inst.center.y - inst.radius;
        ymin = (ymin < 0) ? 0 : ymin;
        int ymax = inst.center.y;
        ymax = (ymax > (pixbuf.height - 1)) ? (pixbuf.height - 1) : ymax;

        /* iterate over all the pixels in the top half-circle of the effect
           extent from top to bottom */
        int inset_index = 0;
        for (int y_it = ymin; y_it <= ymax; y_it++) {
            int xmin = x_bounds_min + x_insets_first_quadrant[inset_index];
            xmin = (xmin < 0) ? 0 : xmin;
            int xmax = x_bounds_max - x_insets_first_quadrant[inset_index];
            xmax = (xmax > (pixbuf.width - 1)) ? (pixbuf.width - 1) : xmax;

            for (int x_it = xmin; x_it <= xmax; x_it++) {
                red_reduce_pixel(pixbuf, x_it, y_it);
            }
            inset_index++;
        }

        /* iterate over all the pixels in the top half-circle of the effect
           extent from top to bottom */
        ymin = inst.center.y;
        ymax = inst.center.y + inst.radius;
        inset_index = x_insets_first_quadrant.length - 1;
        for (int y_it = ymin; y_it <= ymax; y_it++) {  
            int xmin = x_bounds_min + x_insets_first_quadrant[inset_index];
            xmin = (xmin < 0) ? 0 : xmin;
            int xmax = x_bounds_max - x_insets_first_quadrant[inset_index];
            xmax = (xmax > (pixbuf.width - 1)) ? (pixbuf.width - 1) : xmax;

            for (int x_it = xmin; x_it <= xmax; x_it++) {
                red_reduce_pixel(pixbuf, x_it, y_it);
            }
            inset_index--;
        }
        
        return pixbuf;
    }

    private Gdk.Pixbuf red_reduce_pixel(owned Gdk.Pixbuf pixbuf, int x, int y) {
        int px_start_byte_offset = (y * pixbuf.get_rowstride()) +
            (x * pixbuf.get_n_channels());
        
        unowned uchar[] pixel_data = pixbuf.get_pixels();
        
        /* The pupil of the human eye has no pigment, so we expect all
           color channels to be of about equal intensity. This means that at
           any point within the effects region, the value of the red channel
           should be about the same as the values of the green and blue
           channels. So set the value of the red channel to be the mean of the
           values of the red and blue channels. This preserves achromatic
           intensity across all channels while eliminating any extraneous flare
           affecting the red channel only (i.e. the red-eye effect). */
        uchar g = pixel_data[px_start_byte_offset + 1];
        uchar b = pixel_data[px_start_byte_offset + 2];
        
        uchar r = (g + b) / 2;
        
        pixel_data[px_start_byte_offset] = r;
        
        return pixbuf;
    }

    public RGBTransformation get_composite_transformation() {
        float exposure_param = get_color_adjustment(RGBTransformationKind.EXPOSURE);
        float saturation_param = get_color_adjustment(RGBTransformationKind.SATURATION);
        float tint_param = get_color_adjustment(RGBTransformationKind.TINT);
        float temperature_param = get_color_adjustment(RGBTransformationKind.TEMPERATURE);

        RGBTransformation exposure_transform =
            RGBTransformationFactory.get_instance().from_parameter(
            RGBTransformationKind.EXPOSURE, exposure_param);

        RGBTransformation saturation_transform =
            RGBTransformationFactory.get_instance().from_parameter(
            RGBTransformationKind.SATURATION, saturation_param);

        RGBTransformation tint_transform =
            RGBTransformationFactory.get_instance().from_parameter(
            RGBTransformationKind.TINT, tint_param);

        RGBTransformation temperature_transform =
            RGBTransformationFactory.get_instance().from_parameter(
            RGBTransformationKind.TEMPERATURE, temperature_param);

        RGBTransformation composite_transform = ((
                exposure_transform.compose_against(
                saturation_transform)).compose_against(
                temperature_transform)).compose_against(
                tint_transform);
        
        return composite_transform;
    }

    public Gdk.Point unscaled_to_raw_point(Gdk.Point unscaled_point) {
        Orientation unscaled_orientation = get_orientation();
    
        Dimensions unscaled_dims =
            unscaled_orientation.rotate_dimensions(get_dimensions());

        int unscaled_x_offset_raw = 0;
        int unscaled_y_offset_raw = 0;

        Box crop_box;
        if (get_raw_crop(out crop_box)) {
            unscaled_x_offset_raw = crop_box.left;
            unscaled_y_offset_raw = crop_box.top;
        }
        
        Gdk.Point derotated_point =
            unscaled_orientation.derotate_point(unscaled_dims,
            unscaled_point);

        derotated_point.x += unscaled_x_offset_raw;
        derotated_point.y += unscaled_y_offset_raw;

        return derotated_point;
    }
    
    public Gdk.Rectangle unscaled_to_raw_rect(Gdk.Rectangle unscaled_rect) {
        Gdk.Point upper_left = {0};
        Gdk.Point lower_right = {0};
        upper_left.x = unscaled_rect.x;
        upper_left.y = unscaled_rect.y;
        lower_right.x = upper_left.x + unscaled_rect.width;
        lower_right.y = upper_left.y + unscaled_rect.height;
        
        upper_left = unscaled_to_raw_point(upper_left);
        lower_right = unscaled_to_raw_point(lower_right);
        
        if (upper_left.x > lower_right.x) {
            int temp = upper_left.x;
            upper_left.x = lower_right.x;
            lower_right.x = temp;
        }
        if (upper_left.y > lower_right.y) {
            int temp = upper_left.y;
            upper_left.y = lower_right.y;
            lower_right.y = temp;
        }
        
        Gdk.Rectangle raw_rect = {0};
        raw_rect.x = upper_left.x;
        raw_rect.y = upper_left.y;
        raw_rect.width = lower_right.x - upper_left.x;
        raw_rect.height = lower_right.y - upper_left.y;
        
        return raw_rect;
    }
}

public class LibraryPhoto : TransformablePhoto {
    private static Gee.HashMap<int64?, LibraryPhoto> photo_map = null;
    
    public enum Currency {
        CURRENT,
        DIRTY,
        GONE
    }
    
    private bool generate_thumbnails = true;
    
    public signal void thumbnail_altered();
    
    public signal void removed();
    
    private LibraryPhoto(PhotoID photo_id) {
        base(photo_id);
    }
    
    public static void init() {
        TransformablePhoto.base_init();
        
        photo_map = new Gee.HashMap<int64?, LibraryPhoto>(int64_hash, int64_equal, direct_equal);
    }
    
    public static void terminate() {
        TransformablePhoto.base_terminate();
    }
    
    public static ImportResult import(File file, ImportID import_id, out LibraryPhoto photo) {
        PhotoID photo_id;
        Gdk.Pixbuf initial_pixbuf;
        ImportResult result = TransformablePhoto.import_photo(file, import_id, out photo_id,
            out initial_pixbuf);
        if (result != ImportResult.SUCCESS)
            return result;

        // sanity ... this would be very bad
        assert(!photo_map.contains(photo_id.id));
        
        // import initial image into the thumbnail cache with modifications
        ThumbnailCache.import(photo_id, initial_pixbuf);
        
        photo = fetch(photo_id);
        
        return ImportResult.SUCCESS;
    }

    public static LibraryPhoto fetch(PhotoID photo_id) {
        LibraryPhoto photo = photo_map.get(photo_id.id);

        if (photo == null) {
            photo = new LibraryPhoto(photo_id);
            photo_map.set(photo_id.id, photo);
        }
        
        return photo;
    }
    
    private override void on_altered () {
        // the exportable file is now not in sync with transformed photo
        remove_exportable_file();

        if (generate_thumbnails) {
            // load transformed image for thumbnail generation
            Gdk.Pixbuf pixbuf = null;
            try {
                pixbuf = get_pixbuf(SCREEN);
            } catch (Error err) {
                error("%s", err.message);
            }
            
            ThumbnailCache.import(photo_id, pixbuf, true);
            
            // fire signal that thumbnails have changed
            thumbnail_altered();
        }
        
        base.on_altered();
    }

    public EventID get_event_id() {
        return photo_table.get_event(photo_id);
    }
    
    public void set_event_id(EventID event_id) {
        photo_table.set_event(photo_id, event_id);
        notify_altered(Alteration.METADATA);
    }

    public override Gdk.Pixbuf get_preview_pixbuf(int scale) {
        Gdk.Pixbuf pixbuf = get_thumbnail(ThumbnailCache.BIG_SCALE);
        
        int pixels = scale_to_pixels(scale);
        if (pixels > 0)
            pixbuf = scale_pixbuf(pixbuf, pixels, Gdk.InterpType.BILINEAR);
        
        return pixbuf;
    }
    
    public override void rotate(Rotation rotation) {
        // block thumbnail generation for this operation; taken care of below
        generate_thumbnails = false;
        base.rotate(rotation);
        generate_thumbnails = true;

        // because rotations are (a) common and available everywhere in the app, (b) the user expects
        // a level of responsiveness not necessarily required by other modifications, (c) can be
        // performed on multiple images simultaneously, and (d) can't cache a lot of full-sized
        // pixbufs for rotate-and-scale ops, perform the rotation directly on the already-modified 
        // thumbnails.
        foreach (int scale in ThumbnailCache.SCALES) {
            Gdk.Pixbuf thumbnail = ThumbnailCache.fetch(photo_id, scale);
            thumbnail = rotation.perform(thumbnail);
            ThumbnailCache.replace(photo_id, scale, thumbnail);
        }

        thumbnail_altered();
    }
    
    private override File generate_exportable_file() {
        File original_file = get_file();

        File exportable_dir = AppWindow.get_data_subdir("export");
    
        // use exposure time, then file modified time, for directory (to prevent name collision)
        time_t timestamp = get_exposure_time();
        if (timestamp == 0)
            timestamp = get_timestamp();
        
        if (timestamp != 0) {
            Time tm = Time.local(timestamp);
            exportable_dir = exportable_dir.get_child("%04u".printf(tm.year + 1900));
            exportable_dir = exportable_dir.get_child("%02u".printf(tm.month + 1));
            exportable_dir = exportable_dir.get_child("%02u".printf(tm.day));
        }
        
        return exportable_dir.get_child(original_file.get_basename());
    }
    
    // We keep exportable photos around for now, as they're expensive to generate ...
    // this may change in the future.
    public override void export_failed() {
    }
    
    // Returns unscaled thumbnail with all modifications applied applicable to the scale
    public Gdk.Pixbuf? get_thumbnail(int scale) {
        return ThumbnailCache.fetch(photo_id, scale);
    }
    
    public void remove(bool remove_original) {
        // signal all interested parties prior to removal from map
        removed();

        // remove all cached thumbnails
        ThumbnailCache.remove(photo_id);
        
        // remove exportable file
        remove_exportable_file();
        
        // remove original
        if (remove_original)
            remove_original_file();

        // remove from photo table -- should be wiped from storage now (other classes may have added
        // photo_id to other parts of the database ... it's their responsibility to remove them
        // when removed() is called)
        photo_table.remove(photo_id);
        
        // remove from global map
        photo_map.remove(photo_id.id);
    }
    
    private void remove_exportable_file() {
        File file = null;
        try {
            file = generate_exportable_file();
            if (file.query_exists(null))
                file.delete(null);
        } catch (Error err) {
            if (file != null)
                message("Unable to delete exportable photo file %s: %s", file.get_path(), err.message);
            else
                message("Unable to generate exportable filename for %s", to_string());
        }
    }
    
    private void remove_original_file() {
        File file = get_file();
        
        debug("Deleting original photo file %s", file.get_path());
        
        try {
            file.delete(null);
        } catch (Error err) {
            // log error but don't abend, as this is not fatal to operation (also, could be
            // the photo is removed because it could not be found during a verify)
            message("Unable to delete original photo %s: %s", file.get_path(), err.message);
        }
        
        // remove empty directories corresponding to imported path, but only if file is located
        // inside the user's Pictures directory
        if (file.has_prefix(AppWindow.get_photos_dir())) {
            File parent = file;
            for (int depth = 0; depth < BatchImport.IMPORT_DIRECTORY_DEPTH; depth++) {
                parent = parent.get_parent();
                if (parent == null)
                    break;
                
                if (!query_is_directory_empty(parent))
                    break;
                
                try {
                    parent.delete(null);
                    debug("Deleted empty directory %s", parent.get_path());
                } catch (Error err) {
                    // again, log error but don't abend
                    message("Unable to delete empty directory %s: %s", parent.get_path(),
                        err.message);
                }
            }
        }
    }

    public Currency check_currency() {
        FileInfo info = null;
        try {
            info = get_file().query_info("*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            // treat this as the file has been deleted from the filesystem
            return Currency.GONE;
        }
        
        TimeVal timestamp = TimeVal();
        info.get_modification_time(timestamp);
        
        // trust modification time and file size
        if ((timestamp.tv_sec != get_timestamp()) || (info.get_size() != photo_table.get_filesize(photo_id)))
            return Currency.DIRTY;
        
        // verify thumbnail cache is all set
        if (!ThumbnailCache.exists(photo_id))
            return Currency.DIRTY;
        
        return Currency.CURRENT;
    }
}

public class DirectPhoto : TransformablePhoto {
    private static Gee.HashMap<File, DirectPhoto> photo_map = null;
    
    private Gdk.Pixbuf current_pixbuf;
    private File exportable = null;
    
    private DirectPhoto(PhotoID photo_id, Gdk.Pixbuf? initial_pixbuf) {
        base(photo_id);
        
        current_pixbuf = (initial_pixbuf != null) ? initial_pixbuf : base.get_pixbuf(SCREEN);
    }
    
    public static void init() {
        TransformablePhoto.base_init();

        photo_map = new Gee.HashMap<File, DirectPhoto>(file_hash, file_equal, direct_equal);
    }
    
    public static void terminate() {
        TransformablePhoto.base_terminate();
    }
    
    public static DirectPhoto? fetch(File file, bool reset = false) {
        // fetch from the map first, which ensures that only one DirectPhoto exists for each file
        DirectPhoto photo = photo_map.get(file);
        if (photo != null) {
            // if a reset is necessary, the database (and the object) need to reset to original
            // easiest way to do this: perform an update, which is a kind of in-place re-import
            if (reset)
                photo.update();
                
            return photo;
        }
        
        // for direct photos using an in-memory database, a fetch is an import if the file is
        // unknown
        PhotoID photo_id;
        Gdk.Pixbuf initial_pixbuf;
        ImportResult result = TransformablePhoto.import_photo(file, photo_table.generate_import_id(), 
            out photo_id, out initial_pixbuf);
        switch (result) {
            case ImportResult.SUCCESS:
                photo = new DirectPhoto(photo_id, initial_pixbuf);
            break;
            
            case ImportResult.PHOTO_EXISTS:
                // this should never happen; the photo_map guarantees it
                error("import_photo reports photo exists that is not in photo_map");
            break;
            
            default:
                // TODO: Better error reporting
                AppWindow.error_message("Unable to load %s: %s".printf(file.get_path(),
                    result.to_string()));
            break;
        }
        
        if (photo != null)
            photo_map.set(file, photo);
        
        return photo;
    }
    
    public override File generate_exportable_file() {
        // reuse exportable file if possible
        if (exportable != null)
            return exportable;
        
        // generate an exportable in the app temp directory with the same basename as the file
        // being edited ... as generate_exportable will reuse the file if it exists, and if
        // exportable is null then it's been discarded, delete the old file
        exportable = AppWindow.get_temp_dir().get_child(get_file().get_basename());
        if (exportable.query_exists(null)) {
            try {
                exportable.delete(null);
            } catch (Error err) {
                // this is actually a real problem, as the user will probably not get what they
                // wanted
                warning("Unable to delete exportable temp file %s: %s", exportable.get_path(),
                    err.message);
            }
        }
        
        return exportable;
    }
    
    public override Gdk.Pixbuf get_preview_pixbuf(int scale) throws Error {
        Gdk.Pixbuf pixbuf = current_pixbuf;
        
        int pixels = scale_to_pixels(scale);
        if (pixels > 0)
            pixbuf = scale_pixbuf(pixbuf, pixels, Gdk.InterpType.BILINEAR);
        
        return pixbuf;
    }
    
    private override void on_altered() {
        // stash the current pixbuf for previews and such, and flush the generated exportable file
        current_pixbuf = base.get_pixbuf(SCREEN);
        exportable = null;
        
        base.on_altered();
    }
}

