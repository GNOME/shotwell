/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public enum SupportedAdjustments {
    TONE_EXPANSION,
    SHADOWS,
    TEMPERATURE,
    TINT,
    SATURATION,
    EXPOSURE,
    NUM
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
                return _("Success");
            
            case FILE_ERROR:
                return _("File error");
            
            case DECODE_ERROR:
                return _("Unable to decode file");
            
            case DATABASE_ERROR:
                return _("Database error");
            
            case USER_ABORT:
                return _("User aborted import");
            
            case NOT_A_FILE:
                return _("Not a file");
            
            case PHOTO_EXISTS:
                return _("File already exists in database");
            
            case UNSUPPORTED_FORMAT:
                return _("Unsupported file format");
            
            default:
                error("Bad import result: %d", (int) this);
                
                return _("Bad import result (%d)").printf((int) this);
        }
    }
}

// TransformablePhoto is an abstract class that allows for applying transformations on-the-fly to a
// particular photo without modifying the backing image file.  The interface allows for
// transformations to be stored persistently elsewhere or in memory until they're commited en
// masse to an image file.
public abstract class TransformablePhoto: PhotoSource {
    public const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.BILINEAR;
    
    public const Jpeg.Quality EXPORT_JPEG_QUALITY = Jpeg.Quality.HIGH;
    public const Gdk.InterpType EXPORT_INTERP = Gdk.InterpType.HYPER;
    
    public const string[] SUPPORTED_EXTENSIONS = {
        "jpg",
        "jpeg",
        "jpe"
    };
    
    // There are assertions in the photo pipeline to verify that the generated (or loaded) pixbuf
    // is scaled properly.  We have to allow for some wobble here because of rounding errors and
    // precision limitations of various subsystems.  Pixel-accuracy would be best, but barring that,
    // need to just make sure the pixbuf is in the ballpark.
    private const int SCALING_FUDGE = 8;
    
    public enum Exception {
        NONE            = 0,
        ORIENTATION     = 1 << 0,
        CROP            = 1 << 1,
        REDEYE          = 1 << 2,
        ADJUST          = 1 << 3,
        ALL             = 0xFFFFFFFF;
        
        public bool prohibits(Exception exception) {
            return ((this & exception) != 0);
        }
        
        public bool allows(Exception exception) {
            return ((this & exception) == 0);
        }
    }

    private static Mutex cache_mutex = null;
    private static PhotoID cached_photo_id = PhotoID();
    private static Gdk.Pixbuf cached_raw = null;
    
    // because fetching individual items from the database is high-overhead, store all of
    // the photo row in memory
    private PhotoRow row;
    
    private PixelTransformer transformer = null;
    private PixelTransformation[] adjustments = null;
    
    // The key to this implementation is that multiple instances of TransformablePhoto with the
    // same PhotoID cannot exist; it is up to the subclasses to ensure this.
    protected TransformablePhoto(PhotoRow row) {
        this.row = row;
        
        if (cache_mutex == null)
            cache_mutex = new Mutex();
    }
    
    public static ImportResult import_photo(File file, ImportID import_id, out PhotoID photo_id,
        out Gdk.Pixbuf pixbuf) {
        if (PhotoTable.get_instance().is_photo_stored(file))
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
        
        if (!is_file_supported(file)) {
            message("Not importing %s: Unsupported type", file.get_path());
            return ImportResult.UNSUPPORTED_FORMAT;
        }
        
        TimeVal timestamp = TimeVal();
        info.get_modification_time(out timestamp);
        
        Orientation orientation = Orientation.TOP_LEFT;
        time_t exposure_time = 0;
        string thumbnail_md5 = null;
        string exif_md5 = null;
        
        // TODO: Try to read JFIF metadata too
        PhotoExif exif = new PhotoExif(file);
        if (exif.has_exif()) {
            if (!exif.get_timestamp(out exposure_time))
                message("Unable to read EXIF orientation for %s", file.get_path());

            orientation = exif.get_orientation();
            
            exif_md5 = exif.get_md5();
            thumbnail_md5 = exif.get_thumbnail_md5();
        }
        
        string md5 = null;
        
        // load Pixbuf for thumbnail generation and image preview, but also to generate its MD5
        // fingerprint
        ImportResult decode_result = ImportResult.SUCCESS;
        FileInputStream fins = null;
        Gdk.PixbufLoader pixbuf_loader = new Gdk.PixbufLoader();
        Checksum md5_checksum = new Checksum(ChecksumType.MD5);
        try {
            uint8[] buffer = new uint8[64 * 1024];
            
            fins = file.read(null);
            for(;;) {
                size_t bytes_read = fins.read(buffer, buffer.length, null);
                if (bytes_read <= 0)
                    break;
                
                md5_checksum.update(buffer, bytes_read);
                
                // because of bad bindings, PixbufLoader.write() only accepts the buffer reference,
                // not the length of data in the buffer, meaning partially-filled buffers need to 
                // be special-cased
                if (bytes_read == buffer.length) {
                    pixbuf_loader.write(buffer);
                } else {
                    uint8[] tmp = new uint8[bytes_read];
                    Memory.copy(tmp, buffer, bytes_read);
                    pixbuf_loader.write(tmp);
                }
            }
            
            pixbuf = pixbuf_loader.get_pixbuf();
            md5 = md5_checksum.get_string();
        } catch (Error err) {
            warning("Read/decode/checksum error for %s: %s", file.get_path(), err.message);
            
            // assume a decode error, although technically it could be I/O ... need better Gdk
            // bindings to determine which
            decode_result = ImportResult.DECODE_ERROR;
        } finally {
            try {
                pixbuf_loader.close();
            } catch (Error err) {
                // this does count as a decode error, as this indicates with the close the loader
                // didn't recognize the file format
                warning("Unable to close pixbuf loader for %s: %s", file.get_path(), err.message);
                decode_result = ImportResult.DECODE_ERROR;
            }
            
            if (fins != null) {
                try {
                    fins.close(null);
                } catch (Error err) {
                    warning("Unable to close import file %s: %s", file.get_path(), err.message);
                }
            }
        }
        
        if (decode_result != ImportResult.SUCCESS)
            return decode_result;
        
        // verify basic mechanics of photo: RGB 8-bit encoding
        if (pixbuf.get_colorspace() != Gdk.Colorspace.RGB || pixbuf.get_n_channels() < 3 
            || pixbuf.get_bits_per_sample() != 8) {
            message("Not importing %s: Unsupported color format", file.get_path());
            
            return ImportResult.UNSUPPORTED_FORMAT;
        }
        
        // Don't trust EXIF dimensions, they can lie or not be present
        Dimensions dim = Dimensions.for_pixbuf(pixbuf);

        // photo information is stored in database in raw, non-modified format ... this is especially
        // important dealing with dimensions and orientation
        photo_id = PhotoTable.get_instance().add(file, dim, info.get_size(), timestamp.tv_sec, 
            exposure_time, orientation, import_id, md5, thumbnail_md5, exif_md5);
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
    
    // Data element accessors ... by making these thread-safe, and by the remainder of this class
    // (and subclasses) accessing row *only* through these, helps ensure this object is suitable
    // for threads.  This implementation is specifically for PixbufCache to work properly.
    //
    // Much of the setter's thread-safety (especially in regard to writing to the database) is
    // that there is a single Photo object per row of the database.  The PhotoTable is accessed
    // elsewhere in the system (usually for aggregate and search functions).  Those would need to
    // be factored and locked in order to guarantee full thread safety.
    //
    // Note that return inside a lock block generates warnings and does not properly release the
    // mutex: https://bugzilla.gnome.org/show_bug.cgi?id=582553
    //
    // Also note there is a certain amount of paranoia here.  Many of PhotoRow's elements are
    // currently static, with no setters to change them.  However, since some of these may become
    // mutable in the future, the entire structure is locked.  If performance becomes an issue,
    // more fine-tuned locking may be implemented -- another reason to *only* use these getters
    // and setters inside this class.
    
    public File get_file() {
        File file = null;
        lock (row) {
            file = row.file;
        }
        
        return file;
    }
    
    public time_t get_timestamp() {
        time_t timestamp;
        lock (row) {
            timestamp = row.timestamp;
        }
        
        return timestamp;
    }

    public PhotoID get_photo_id() {
        PhotoID photo_id;
        lock (row) {
            photo_id = row.photo_id;
        }
        
        return photo_id;
    }
    
    public EventID get_event_id() {
        EventID event_id;
        lock (row) {
            event_id = row.event_id;
        }
        
        return event_id;
    }
    
    public Event? get_event() {
        EventID event_id = get_event_id();
        
        return event_id.is_valid() ? Event.global.fetch(event_id) : null;
    }
    
    public bool set_event(Event event) {
        bool committed = false;
        lock (row) {
            committed = PhotoTable.get_instance().set_event(row.photo_id, event.get_event_id());
            if (committed)
                row.event_id = event.get_event_id();
        }
        
        if (committed)
            notify_metadata_altered();
        
        return committed;
    }
    
    public override string to_string() {
        PhotoID photo_id = get_photo_id();
        File file = get_file();
        
        return "[%lld] %s".printf(photo_id.id, file.get_path());
    }

    public bool equals(TransformablePhoto? photo) {
        if (photo == null)
            return false;
            
        PhotoID photo_id = get_photo_id();
        PhotoID other_photo_id = photo.get_photo_id();
        
        // identity works because of the photo_map, but the PhotoTable primary key is where the
        // rubber hits the road
        if (this == photo) {
            assert(photo_id.id == other_photo_id.id);
            
            return true;
        }
        
        assert(photo_id.id != other_photo_id.id);
        
        return false;
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
        info.get_modification_time(out timestamp);
        
        // TODO: Use actual pixbuf dimensions, not EXIF
        // TODO: Generate MD5 fingerprints
        
        PhotoID photo_id = get_photo_id();
        if (PhotoTable.get_instance().update(photo_id, dim, info.get_size(), timestamp.tv_sec, 
            exposure_time, orientation)) {
            // cache coherency
            lock (row) {
                row.dim = dim;
                row.filesize = info.get_size();
                row.timestamp = timestamp.tv_sec;
                row.exposure_time = exposure_time;
                row.orientation = orientation;
                row.original_orientation = orientation;
                
                // because image has changed, all transformations are suspect
                remove_all_transformations();
            }
            
            // remove from decode cache as well
            cache_mutex.lock();
            if (cached_photo_id.id == photo_id.id)
                cached_raw = null;
            cache_mutex.unlock();
            
            // metadata currently only means Event
            notify_altered();
        }
    }

    // PhotoSource
    
    public override string get_name() {
        return get_file().get_basename();
    }
    
    public override uint64 get_filesize() {
        uint64 filesize;
        lock (row) {
            filesize = row.filesize;
        }
        
        return filesize;
    }
    
    public override time_t get_exposure_time() {
        time_t exposure_time;
        lock (row) {
            exposure_time = row.exposure_time;
        }
        
        return exposure_time;
    }
    
    // Returns cropped and rotated dimensions
    public override Dimensions get_dimensions() {
        Box crop;
        if (get_crop(out crop))
            return crop.get_dimensions();
        
        return get_uncropped_dimensions();
    }
    
    // This method *must* be called with row locked.
    private void create_adjustments_from_data() {
        KeyValueMap map = get_transformation("adjustments");

        adjustments = new PixelTransformation[SupportedAdjustments.NUM];
        transformer = new PixelTransformer();

        if (map == null) {
            adjustments[SupportedAdjustments.TONE_EXPANSION] =
                new ExpansionTransformation.from_extrema(0, 255);
            transformer.attach_transformation(adjustments[SupportedAdjustments.TONE_EXPANSION]);

            adjustments[SupportedAdjustments.SHADOWS] =
                new ShadowDetailTransformation(0.0f);
            transformer.attach_transformation(adjustments[SupportedAdjustments.SHADOWS]);

            adjustments[SupportedAdjustments.TEMPERATURE] =
                new TemperatureTransformation(0.0f);
            transformer.attach_transformation(adjustments[SupportedAdjustments.TEMPERATURE]);

            adjustments[SupportedAdjustments.TINT] =
                new TintTransformation(0.0f);
            transformer.attach_transformation(adjustments[SupportedAdjustments.TINT]);

            adjustments[SupportedAdjustments.SATURATION] =
                new SaturationTransformation(0.0f);
            transformer.attach_transformation(adjustments[SupportedAdjustments.SATURATION]);

            adjustments[SupportedAdjustments.EXPOSURE] =
                new ExposureTransformation(0.0f);
            transformer.attach_transformation(adjustments[SupportedAdjustments.EXPOSURE]);
        } else {
            string expansion_params_encoded = map.get_string("expansion", "-");
            if (expansion_params_encoded == "-")
                adjustments[SupportedAdjustments.TONE_EXPANSION] =
                    new ExpansionTransformation.from_extrema(0, 255);
            else
                adjustments[SupportedAdjustments.TONE_EXPANSION] =
                    new ExpansionTransformation.from_string(expansion_params_encoded);
            transformer.attach_transformation(adjustments[SupportedAdjustments.TONE_EXPANSION]);
            
            float shadow_param = (float) map.get_double("shadows", 0.0);
            adjustments[SupportedAdjustments.SHADOWS] = new ShadowDetailTransformation(shadow_param);
            transformer.attach_transformation(adjustments[SupportedAdjustments.SHADOWS]);

            float temp_param = (float) map.get_double("temperature", 0.0);
            adjustments[SupportedAdjustments.TEMPERATURE] = new TemperatureTransformation(temp_param);
            transformer.attach_transformation(adjustments[SupportedAdjustments.TEMPERATURE]);

            float tint_param = (float) map.get_double("tint", 0.0);
            adjustments[SupportedAdjustments.TINT] = new TintTransformation(tint_param);
            transformer.attach_transformation(adjustments[SupportedAdjustments.TINT]);
            
            float sat_param = (float) map.get_double("saturation", 0.0);
            adjustments[SupportedAdjustments.SATURATION] = new SaturationTransformation(sat_param);
            transformer.attach_transformation(adjustments[SupportedAdjustments.SATURATION]);

            float exposure_param = (float) map.get_double("exposure", 0.0);
            adjustments[SupportedAdjustments.EXPOSURE] = new ExposureTransformation(exposure_param);
            transformer.attach_transformation(adjustments[SupportedAdjustments.EXPOSURE]);
        }
    }
    
    // Returns a copy of the color adjustments array.  Use set_color_adjustments to persist.
    private PixelTransformation[] get_color_adjustments() {
        PixelTransformation[] result;
        lock (row) {
            if (adjustments == null)
                create_adjustments_from_data();
            
            int length = adjustments.length;
            result = new PixelTransformation[length];
            for (int ctr = 0; ctr < length; ctr++)
                result[ctr] = adjustments[ctr];
        }
        
        return result;
    }
    
    private void set_color_adjustments(PixelTransformation[] adjustments) {
        lock (row) {
            int length = adjustments.length;
            this.adjustments = new PixelTransformation[length];
            for (int ctr = 0; ctr < length; ctr++)
                this.adjustments[ctr] = adjustments[ctr];
        }
    }
    
    private PixelTransformer get_pixel_transformer() {
        PixelTransformer result;
        lock (row) {
            if (transformer == null)
                create_adjustments_from_data();
            
            result = transformer;
        }
        
        return result;
    }

    public bool has_color_adjustments() {
        return has_transformation("adjustments");
    }
    
    public PixelTransformation get_adjustment(SupportedAdjustments kind) {
        return get_color_adjustments()[kind];
    }

    public void set_adjustments(owned PixelTransformation[] new_adjustments) {
        if (new_adjustments.length != SupportedAdjustments.NUM)
            error("TransformablePhoto: set_adjustments( ): all adjustments must be set");

        /* if every transformation in 'new_adjustments' is the identity, then just remove all
           adjustments from the database */
        bool all_identity = true;
        for (int i = 0; i < ((int) SupportedAdjustments.NUM); i++) {
            if (!new_adjustments[i].is_identity()) {
                all_identity = false;
                break;
            }
        }
        
        if (all_identity) {
            bool result;
            lock (row) {
                result = remove_transformation("adjustments");
                adjustments = null;
                transformer = null;
            }
            
            if (result)
                notify_altered();

            return;
        }

        PixelTransformation[] adjustments = get_color_adjustments();

        KeyValueMap map = new KeyValueMap("adjustments");

        ExpansionTransformation new_expansion_trans =
            (ExpansionTransformation) new_adjustments[SupportedAdjustments.TONE_EXPANSION];
        map.set_string("expansion", new_expansion_trans.to_string());
        transformer.replace_transformation(adjustments[SupportedAdjustments.TONE_EXPANSION],
            new_expansion_trans);
        adjustments[SupportedAdjustments.TONE_EXPANSION] = new_expansion_trans;

        ShadowDetailTransformation new_shadows_trans =
            (ShadowDetailTransformation) new_adjustments[SupportedAdjustments.SHADOWS];
        map.set_double("shadows", new_shadows_trans.get_parameter());
        transformer.replace_transformation(adjustments[SupportedAdjustments.SHADOWS],
            new_shadows_trans);
        adjustments[SupportedAdjustments.SHADOWS] = new_shadows_trans;

        TemperatureTransformation new_temp_trans =
            (TemperatureTransformation) new_adjustments[SupportedAdjustments.TEMPERATURE];
        map.set_double("temperature", new_temp_trans.get_parameter());
        transformer.replace_transformation(adjustments[SupportedAdjustments.TEMPERATURE],
            new_temp_trans);
        adjustments[SupportedAdjustments.TEMPERATURE] = new_temp_trans;

        TintTransformation new_tint_trans =
            (TintTransformation) new_adjustments[SupportedAdjustments.TINT];
        map.set_double("tint", new_tint_trans.get_parameter());
        transformer.replace_transformation(adjustments[SupportedAdjustments.TINT],
            new_tint_trans);
        adjustments[SupportedAdjustments.TINT] = new_tint_trans;

        SaturationTransformation new_sat_trans =
            (SaturationTransformation) new_adjustments[SupportedAdjustments.SATURATION];
        map.set_double("saturation", new_sat_trans.get_parameter());
        transformer.replace_transformation(adjustments[SupportedAdjustments.SATURATION],
            new_sat_trans);
        adjustments[SupportedAdjustments.SATURATION] = new_sat_trans;

        ExposureTransformation new_exposure_trans =
            (ExposureTransformation) new_adjustments[SupportedAdjustments.EXPOSURE];
        map.set_double("exposure", new_exposure_trans.get_parameter());
        transformer.replace_transformation(adjustments[SupportedAdjustments.EXPOSURE],
            new_exposure_trans);
        adjustments[SupportedAdjustments.EXPOSURE] = new_exposure_trans;
        
        set_color_adjustments(adjustments);
        
        if (set_transformation(map))
            notify_altered();
    }

    public override Exif.Data? get_exif() {
        PhotoExif photo_exif = new PhotoExif(get_file());
        
        return photo_exif.has_exif() ? photo_exif.get_exif() : null;
    }
    
    // Transformation storage and exporting

    public Dimensions get_raw_dimensions() {
        Dimensions dim;
        lock (row) {
            dim = row.dim;
        }
        
        return dim;
    }

    public bool has_transformations() {
        bool transformed;
        lock (row) {
            if (row.orientation != row.original_orientation)
                transformed = true;
            else
                transformed = row.transformations != null;
        }
        
        return transformed;
    }
    
    private bool is_only_rotated() {
        bool only_rotated;
        lock (row) {
            only_rotated = row.transformations == null && row.orientation != row.original_orientation;
        }
        
        return only_rotated;
    }
    
    public void remove_all_transformations() {
        bool is_altered = false;
        lock (row) {
            is_altered = PhotoTable.get_instance().remove_all_transformations(row.photo_id);
            row.transformations = null;
            
            transformer = null;
            adjustments = null;
            
            if (row.orientation != row.original_orientation) {
                PhotoTable.get_instance().set_orientation(row.photo_id, row.original_orientation);
                row.orientation = row.original_orientation;
                is_altered = true;
            }
        }

        if (is_altered)
            notify_altered();
    }
    
    public Orientation get_original_orientation() {
        Orientation original_orientation;
        lock (row) {
            original_orientation = row.original_orientation;
        }
        
        return original_orientation;
    }
    
    public Orientation get_orientation() {
        Orientation orientation;
        lock (row) {
            orientation = row.orientation;
        }
        
        return orientation;
    }
    
    public void set_orientation(Orientation orientation) {
        lock (row) {
            row.orientation = orientation;
            PhotoTable.get_instance().set_orientation(row.photo_id, orientation);
        }
        
        notify_altered();
    }

    public virtual void rotate(Rotation rotation) {
        lock (row) {
            Orientation orientation = get_orientation();
            
            orientation = orientation.perform(rotation);
            
            set_orientation(orientation);
        }
    }

    private bool has_transformation(string name) {
        bool present;
        lock (row) {
            present = (row.transformations != null) ? row.transformations.has_key(name) : false;
        }
        
        return present;
    }
    
    // Note that obtaining the proper map is thread-safe here.  The returned map is a copy of
    // the original, so it is thread-safe as well.  However: modifying the returned map
    // does not modify the original; set_transformation() must be used.
    private KeyValueMap? get_transformation(string name) {
        KeyValueMap map = null;
        lock (row) {
            if (row.transformations != null) {
                map = row.transformations.get(name);
                if (map != null)
                    map = map.copy();
            }
        }
        
        return map;
    }

    private bool set_transformation(KeyValueMap trans) {
        bool committed;
        lock (row) {
            if (row.transformations == null)
                row.transformations = new Gee.HashMap<string, KeyValueMap>(str_hash, str_equal, direct_equal);
            
            row.transformations.set(trans.get_group(), trans);
            
            committed = PhotoTable.get_instance().set_transformation(row.photo_id, trans);
        }
        
        return committed;
    }

    private bool remove_transformation(string name) {
        bool altered_cache, altered_persistent;
        lock (row) {
            if (row.transformations != null) {
                altered_cache = row.transformations.unset(name);
                if (row.transformations.size == 0)
                    row.transformations = null;
            } else {
                altered_cache = false;
            }
            
            altered_persistent = PhotoTable.get_instance().remove_transformation(row.photo_id, 
                name);
        }

        return (altered_cache || altered_persistent);
    }

    public bool has_crop() {
        return has_transformation("crop");
    }

    // Returns the crop in the raw photo's coordinate system
    private bool get_raw_crop(out Box crop) {
        KeyValueMap map = get_transformation("crop");
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
        
        if (set_transformation(map))
            notify_altered();
    }
    
    // All instances are against the coordinate system of the unscaled, unrotated photo.
    private RedeyeInstance[] get_raw_redeye_instances() {
        KeyValueMap map = get_transformation("redeye");
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
    
    public bool has_redeye_transformations() {
        return has_transformation("redeye");
    }

    // All instances are against the coordinate system of the unrotated photo.
    private void add_raw_redeye_instance(RedeyeInstance redeye) {
        KeyValueMap map = get_transformation("redeye");
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

        if (set_transformation(map))
            notify_altered();
    }

    // Pixbuf generation
    
    // Returns dimensions for the pixbuf at various stages of the pipeline.
    //
    // scaled_image is the dimensions of the image after a scaled load-and-decode.
    // scaled_to_viewport is the dimensions of the image sized according to the scaling parameter.
    // scaled_image and scaled_to_viewport may be different if the photo is cropped.
    //
    // Returns true if scaling is to occur, false otherwise.  If false, scaled_image will be set to
    // the raw image dimensions and scaled_to_viewport will be the dimensions of the image scaled
    // to the Scaling viewport.
    private bool calculate_pixbuf_dimensions(Scaling scaling, Exception exceptions, 
        out Dimensions scaled_image, out Dimensions scaled_to_viewport) {
        bool scaling_required;
        lock (row) {
            // this function needs to access various elements of the Photo atomically
            scaling_required = locked_calculate_pixbuf_dimensions(scaling, exceptions,
                out scaled_image, out scaled_to_viewport);
        }
        
        return scaling_required;
    }
    
    // Must be called with row locked.
    private bool locked_calculate_pixbuf_dimensions(Scaling scaling, Exception exceptions,
        out Dimensions scaled_image, out Dimensions scaled_to_viewport) {
        Dimensions raw = get_raw_dimensions();
        
        if (scaling.is_unscaled()) {
            scaled_image = raw;
            scaled_to_viewport = raw;
            
            return false;
        }
        
        Orientation orientation = get_orientation();
        
        // If no crop, the scaled_image is simply raw scaled to fit into the viewport.  Otherwise,
        // the image is scaled enough so the cropped region fits the viewport.

        scaled_image = Dimensions();
        scaled_to_viewport = Dimensions();
        
        if (exceptions.allows(Exception.CROP)) {
            Box crop;
            if (get_raw_crop(out crop)) {
                // rotate the crop and raw space accordingly ... order is important here, rotate_box
                // works with the unrotated dimensions in space
                Dimensions rotated_raw = raw;
                if (exceptions.allows(Exception.ORIENTATION)) {
                    crop = orientation.rotate_box(raw, crop);
                    rotated_raw = orientation.rotate_dimensions(raw);
                }
                
                // scale the rotated crop to fit in the viewport
                Box scaled_crop = crop.get_scaled(scaling.get_scaled_dimensions(crop.get_dimensions()));
                
                // the viewport size is the size of the scaled crop
                scaled_to_viewport = scaled_crop.get_dimensions();
                    
                // only scale the image if the crop is larger than the viewport
                if (crop.get_width() <= scaled_crop.get_width() 
                    && crop.get_height() <= scaled_crop.get_height()) {
                    scaled_image = raw;
                    scaled_to_viewport = crop.get_dimensions();
                    
                    return false;
                }
                // resize the total pixbuf so the crop slices directly from the scaled pixbuf, 
                // with no need for resizing thereafter.  The decoded size is determined by the 
                // proportion of the actual size to the crop size
                scaled_image = rotated_raw.get_scaled_similar(crop.get_dimensions(), 
                    scaled_crop.get_dimensions());
                
                // derotate, as the loader knows nothing about orientation
                if (exceptions.allows(Exception.ORIENTATION))
                    scaled_image = orientation.derotate_dimensions(scaled_image);
            }
        }
        
        // if scaled_image not set, merely scale the raw pixbuf
        if (!scaled_image.has_area()) {
            // rotate for the scaler
            Dimensions rotated_raw = raw;
            if (exceptions.allows(Exception.ORIENTATION))
                rotated_raw = orientation.rotate_dimensions(raw);

            scaled_image = scaling.get_scaled_dimensions(rotated_raw);
            scaled_to_viewport = scaled_image;
        
            // derotate the scaled dimensions, as the loader knows nothing about orientation
            if (exceptions.allows(Exception.ORIENTATION))
                scaled_image = orientation.derotate_dimensions(scaled_image);
        }

        // do not scale up
        if (scaled_image.width >= raw.width && scaled_image.height >= raw.height) {
            scaled_image = raw;
            
            return false;
        }
        
        assert(scaled_image.has_area());
        assert(scaled_to_viewport.has_area());
        
        return true;
    }

    // Returns a raw, untransformed, unrotated pixbuf directly from the source.  Scaling provides
    // asked for a scaled-down image, which has certain performance benefits if the resized
    // JPEG is scaled down by a factor of a power of two (one-half, one-fourth, etc.).
    private Gdk.Pixbuf load_raw_pixbuf(Scaling scaling, Exception exceptions) throws Error {
        string path = get_file().get_path();
        
        // no scaling, load and get out
        if (scaling.is_unscaled()) {
#if MEASURE_PIPELINE
            debug("LOAD_RAW_PIXBUF UNSCALED %s: requested", path);
#endif
            
            return new Gdk.Pixbuf.from_file(path);
        }
        
        // Need the dimensions of the image to load
        Dimensions scaled_image, scaled_to_viewport;
        bool is_scaled = calculate_pixbuf_dimensions(scaling, exceptions, out scaled_image, 
            out scaled_to_viewport);
        if (!is_scaled) {
#if MEASURE_PIPELINE
            debug("LOAD_RAW_PIXBUF UNSCALED %s: scaling unavailable", path);
#endif
            
            return new Gdk.Pixbuf.from_file(path);
        }
        
        Gdk.Pixbuf pixbuf = new Gdk.Pixbuf.from_file_at_size(path, scaled_image.width, 
            scaled_image.height);

#if MEASURE_PIPELINE
        debug("LOAD_RAW_PIXBUF %s %s: %s -> %s (actual: %s)", scaling.to_string(), path,
            get_raw_dimensions().to_string(), scaled_image.to_string(), 
            Dimensions.for_pixbuf(pixbuf).to_string());
#endif
        
        assert(scaled_image.approx_equals(Dimensions.for_pixbuf(pixbuf), SCALING_FUDGE));
        
        return pixbuf;
    }

    // This find the best method possible to load-and-decode the photo's pixbuf, using caches
    // and scaled decodes whenever possible.  This pixbuf is untransformed and unrotated.
    // no_copy should only be set to true if the user specifically knows no transformations will 
    // be made on the returned pixbuf.
    private Gdk.Pixbuf get_raw_pixbuf(Scaling scaling, Exception exceptions, bool no_copy,
        Dimensions scaled_image) throws Error {
#if MEASURE_PIPELINE
        Timer timer = new Timer();
        Timer total_timer = new Timer();
        double pixbuf_copy_time = 0.0, load_and_decode_time = 0.0;
        
        total_timer.start();
#endif
        Gdk.Pixbuf pixbuf = null;
        string method = null;
        
        // check if a cached pixbuf is available to use, to avoid load-and-decode
        PhotoID photo_id = get_photo_id();
        cache_mutex.lock();
        if (cached_raw != null && cached_photo_id.id == photo_id.id) {
            // verify that the scaled image required for this request matches the dimensions of
            // the one in the cache
            if (scaled_image.approx_equals(Dimensions.for_pixbuf(cached_raw))) {
                method = "USING CACHED";
#if MEASURE_PIPELINE
                timer.start();
#endif
                pixbuf = (no_copy) ? cached_raw : cached_raw.copy();
#if MEASURE_PIPELINE
                pixbuf_copy_time = timer.elapsed();
#endif
            } else {
                method = "CACHE BLOWN";
            }
        }
        cache_mutex.unlock();
        
        if (pixbuf == null) {
            method = "LOADING";
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = load_raw_pixbuf(scaling, exceptions);
#if MEASURE_PIPELINE
            load_and_decode_time = timer.elapsed();
            
            timer.start();
#endif
            // stash in the cache ... note that this is thread-safe but not necessarily holding
            // the "last" pixbuf due to race conditions.
            //
            // TODO: Remove this cache.  Other caching mechanisms are better used.
            cache_mutex.lock();
            cached_photo_id = photo_id;
            cached_raw = (no_copy) ? pixbuf : pixbuf.copy();
            cache_mutex.unlock();
#if MEASURE_PIPELINE
            pixbuf_copy_time = timer.elapsed();
#endif
        }
        
#if MEASURE_PIPELINE
        debug("GET_RAW_PIXBUF (%s) %s (%s): load_and_decode=%lf pixbuf_copy=%lf total=%lf", method,
            to_string(), scaling.to_string(), load_and_decode_time, pixbuf_copy_time, 
            total_timer.elapsed());
#endif

        return pixbuf;
    }

    // Returns a raw, untransformed, scaled pixbuf from the source that has been rotated
    // according to its original EXIF settings
    public Gdk.Pixbuf get_original_pixbuf(Scaling scaling) throws Error {
#if MEASURE_PIPELINE
        Timer timer = new Timer();
        Timer total_timer = new Timer();
        double orientation_time = 0.0;
        
        total_timer.start();
#endif
        // get required fields all at once, to avoid holding the row lock
        Dimensions scaled_image, scaled_to_viewport;
        Orientation original_orientation;
        
        lock (row) {
            calculate_pixbuf_dimensions(scaling, Exception.NONE, out scaled_image, 
                out scaled_to_viewport);
            original_orientation = get_original_orientation();
        }
        
        // load-and-decode and scale
        // no copy made because the pixbuf goes unmodified in this pipeline
        Gdk.Pixbuf pixbuf = get_raw_pixbuf(scaling, Exception.NONE, true, scaled_image);
            
        // orientation
#if MEASURE_PIPELINE
        timer.start();
#endif
        pixbuf = original_orientation.rotate_pixbuf(pixbuf);
#if MEASURE_PIPELINE
        orientation_time = timer.elapsed();
        
        debug("ORIGINAL PIPELINE %s (%s): orientation=%lf total=%lf", to_string(), scaling.to_string(),
            orientation_time, total_timer.elapsed());
#endif
        
        return pixbuf;
    }

    // A preview pixbuf is one that can be quickly generated and scaled as a preview.  It is fully 
    // transformed.
    //
    // Note that an unscaled scaling is not considered a performance-killer for this method, 
    // although the quality of the pixbuf may be quite poor compared to the actual unscaled 
    // transformed pixbuf.
    public abstract Gdk.Pixbuf get_preview_pixbuf(Scaling scaling) throws Error;
    
    public override Gdk.Pixbuf get_pixbuf(Scaling scaling) throws Error {
        return get_pixbuf_with_exceptions(scaling, Exception.NONE);
    }
    
    // Returns a fully transformed and scaled pixbuf.  Transformations may be excluded via the mask.
    // If the image is smaller than the scaling, it will be returned in its actual size.  The
    // caller is responsible for scaling thereafter.
    //
    // Note that an unscaled fetch can be extremely expensive, and it's far better to specify an 
    // appropriate scale.
    public Gdk.Pixbuf get_pixbuf_with_exceptions(Scaling scaling, Exception exceptions) throws Error {
#if MEASURE_PIPELINE
        Timer timer = new Timer();
        Timer total_timer = new Timer();
        double redeye_time = 0.0, crop_time = 0.0, adjustment_time = 0.0, orientation_time = 0.0;

        total_timer.start();
#endif
        // to minimize holding the row lock, fetch everything needed for the pipeline up-front
        bool is_scaled, is_cropped;
        Dimensions scaled_image, scaled_to_viewport;
        Dimensions original = Dimensions();
        Dimensions scaled = Dimensions();
        RedeyeInstance[] redeye_instances = null;
        Box crop;
        PixelTransformer transformer = null;
        Orientation orientation;
        
        lock (row) {
            // it's possible for get_raw_pixbuf to not return an image scaled to the spec'd scaling,
            // particularly when the raw crop is smaller than the viewport
            is_scaled = calculate_pixbuf_dimensions(scaling, exceptions, out scaled_image,
                out scaled_to_viewport);
            
            if (is_scaled)
                original = get_raw_dimensions();
            
            redeye_instances = get_raw_redeye_instances();
            
            is_cropped = get_raw_crop(out crop);
            
            if (has_transformation("adjustments"))
                transformer = get_pixel_transformer();
            
            orientation = get_orientation();
        }
        
        //
        // Image load-and-decode
        //
        
        // look for ways to avoid the pixbuf copy; the following transformations do modify the
        // pixbuf
        bool no_copy = (exceptions.prohibits(Exception.REDEYE) || !has_redeye_transformations())
            && (exceptions.prohibits(Exception.ADJUST) || !has_color_adjustments());
        
        Gdk.Pixbuf pixbuf = get_raw_pixbuf(scaling, exceptions, no_copy, scaled_image);
        
        if (is_scaled)
            scaled = Dimensions.for_pixbuf(pixbuf);
        
        //
        // Image transformation pipeline
        //
        
        // redeye reduction
        if (exceptions.allows(Exception.REDEYE)) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            foreach (RedeyeInstance instance in redeye_instances) {
                // redeye is stored in raw coordinates; need to scale to scaled image coordinates
                if (is_scaled) {
                    instance.center = coord_scaled_in_space(instance.center.x, instance.center.y, 
                        original, scaled);
                    instance.radius = radius_scaled_in_space(instance.radius, original, scaled);
                    assert(instance.radius != -1);
                }
                
                pixbuf = do_redeye(pixbuf, instance);
            }
#if MEASURE_PIPELINE
            redeye_time = timer.elapsed();
#endif
        }

        // crop
        if (exceptions.allows(Exception.CROP)) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            if (is_cropped) {
                // crop is stored in raw coordinates; need to scale to scaled image coordinates;
                // also, no need to do this if the image itself was unscaled (which can happen
                // if the crop is smaller than the viewport)
                if (is_scaled)
                    crop = crop.get_scaled_similar(original, scaled);
                
                pixbuf = new Gdk.Pixbuf.subpixbuf(pixbuf, crop.left, crop.top, crop.get_width(),
                    crop.get_height());
            }

#if MEASURE_PIPELINE
            crop_time = timer.elapsed();
#endif
        }
        
        // color adjustment
        if (exceptions.allows(Exception.ADJUST)) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            if (transformer != null)
                transformer.transform_pixbuf(pixbuf);
#if MEASURE_PIPELINE
            adjustment_time = timer.elapsed();
#endif
        }

        // orientation (all modifications are stored in unrotated coordinate system)
        if (exceptions.allows(Exception.ORIENTATION)) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = orientation.rotate_pixbuf(pixbuf);
#if MEASURE_PIPELINE
            orientation_time = timer.elapsed();
#endif
        }
        
        // this is to verify the generated pixbuf matches the scale requirements; crop and 
        // orientation are the only transformations that change the dimensions of the pixbuf, and
        // must be accounted for the test to be valid
        if (is_scaled)
            assert(scaled_to_viewport.approx_equals(Dimensions.for_pixbuf(pixbuf), SCALING_FUDGE));
        
#if MEASURE_PIPELINE
        debug("PIPELINE %s (%s): redeye=%lf crop=%lf adjustment=%lf orientation=%lf total=%lf",
            to_string(), scaling.to_string(), redeye_time, crop_time, adjustment_time, 
            orientation_time, total_timer.elapsed());
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
        if (is_only_rotated() && original_exif != null) {
            original_file.copy(dest_file, FileCopyFlags.OVERWRITE, null, null);

            PhotoExif dest_exif = new PhotoExif(dest_file);
            dest_exif.set_orientation(get_orientation());
            dest_exif.commit();
        } else {
            Gdk.Pixbuf pixbuf = get_pixbuf(Scaling.for_original());
            pixbuf.save(dest_file.get_path(), "jpeg", "quality", 
                EXPORT_JPEG_QUALITY.get_pct_text());
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
        
        Gdk.Pixbuf pixbuf = get_pixbuf(Scaling.for_original());
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

    public PixelTransformation[]? get_enhance_transformations() {
        Gdk.Pixbuf pixbuf = null;

#if MEASURE_ENHANCE
        Timer fetch_timer = new Timer();
#endif

        try {
            pixbuf = get_pixbuf_with_exceptions(Scaling.for_best_fit(360), 
                TransformablePhoto.Exception.ALL);

#if MEASURE_ENHANCE
            fetch_timer.stop();
#endif
        } catch (Error e) {
            warning("Photo: get_enhance_transformations: couldn't obtain pixbuf to build " + 
                "transform histogram");
            return null;
        }

#if MEASURE_ENHANCE
        Timer analyze_timer = new Timer();
#endif

        PixelTransformation[] transformations = AutoEnhance.create_auto_enhance_adjustments(pixbuf);

#if MEASURE_ENHANCE
        analyze_timer.stop();
        debug("Auto-Enhance fetch time: %f sec; analyze time: %f sec", fetch_timer.elapsed(),
            analyze_timer.elapsed());
#endif

        return transformations;
    }

    public bool enhance() {
        PixelTransformation[] transformations = get_enhance_transformations();

        if (transformations == null)
            return false;

#if MEASURE_ENHANCE
        Timer apply_timer = new Timer();
#endif

        set_adjustments(transformations);

#if MEASURE_ENHANCE
        apply_timer.stop();
        debug("Auto-Enhance apply time: %f sec", apply_timer.elapsed());
#endif
        return true;          
    }
}

public class LibraryPhotoSourceCollection : DatabaseSourceCollection {
    public LibraryPhotoSourceCollection() {
        base(get_photo_key);
    }
    
    private static int64 get_photo_key(DataSource source) {
        LibraryPhoto photo = (LibraryPhoto) source;
        PhotoID photo_id = photo.get_photo_id();
        
        return photo_id.id;
    }
    
    public LibraryPhoto fetch(PhotoID photo_id) {
        return (LibraryPhoto) fetch_by_key(photo_id.id);
    }
}

public class LibraryPhoto : TransformablePhoto {
    public enum Currency {
        CURRENT,
        DIRTY,
        GONE
    }
    
    public static LibraryPhotoSourceCollection global = null;
    
    private bool block_thumbnail_generation = false;
    private bool delete_original = false;

    private LibraryPhoto(PhotoRow row) {
        base(row);
    }
    
    public static void init() {
        global = new LibraryPhotoSourceCollection();
        
        // prefetch all the photos from the database and add them to the global collection ...
        // do in batches to take advantage of add_many()
        Gee.ArrayList<PhotoRow?> all = PhotoTable.get_instance().get_all();
        Gee.ArrayList<LibraryPhoto> all_photos = new Gee.ArrayList<LibraryPhoto>();
        foreach (PhotoRow row in all)
            all_photos.add(new LibraryPhoto(row));
        
        global.add_many(all_photos);
    }
    
    public static void terminate() {
    }
    
    public static ImportResult import(File file, ImportID import_id, out LibraryPhoto photo) {
        PhotoID photo_id;
        Gdk.Pixbuf initial_pixbuf;
        ImportResult result = TransformablePhoto.import_photo(file, import_id, out photo_id,
            out initial_pixbuf);
        if (result != ImportResult.SUCCESS)
            return result;

        // import initial image into the thumbnail cache with modifications
        ThumbnailCache.import(photo_id, initial_pixbuf);
        
        // add to global
        photo = new LibraryPhoto(PhotoTable.get_instance().get_row(photo_id));
        global.add(photo);
        
        return ImportResult.SUCCESS;
    }
    
    private bool generate_thumbnails() {
        // load transformed image for thumbnail generation
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = get_pixbuf(Scaling.for_best_fit(ThumbnailCache.Size.BIG.get_scale()));
        } catch (Error err) {
            warning("%s", err.message);
            return false;
        }
        ThumbnailCache.import(get_photo_id(), pixbuf, true);
        
        // fire signal that thumbnails have changed
        notify_thumbnail_altered();
        
        return false;
    }
    
    private override void altered () {
        // the exportable file is now not in sync with transformed photo
        delete_exportable_file();

        // generate new thumbnails in the background
        if (!block_thumbnail_generation)
            Idle.add_full(Priority.LOW, generate_thumbnails);
        
        base.altered();
    }

    public override Gdk.Pixbuf get_preview_pixbuf(Scaling scaling) throws Error {
        Gdk.Pixbuf pixbuf = get_thumbnail(ThumbnailCache.Size.BIG);
        
        return scaling.perform_on_pixbuf(pixbuf, Gdk.InterpType.NEAREST, true);
    }
    
    public override void rotate(Rotation rotation) {
        // block thumbnail generation for this operation; taken care of below
        block_thumbnail_generation = true;
        base.rotate(rotation);
        block_thumbnail_generation = false;

        // because rotations are (a) common and available everywhere in the app, (b) the user expects
        // a level of responsiveness not necessarily required by other modifications, (c) can be
        // performed on multiple images simultaneously, and (d) can't cache a lot of full-sized
        // pixbufs for rotate-and-scale ops, perform the rotation directly on the already-modified 
        // thumbnails.
        foreach (ThumbnailCache.Size size in ThumbnailCache.ALL_SIZES) {
            try {
                Gdk.Pixbuf thumbnail = ThumbnailCache.fetch(get_photo_id(), size);
                thumbnail = rotation.perform(thumbnail);
                ThumbnailCache.replace(get_photo_id(), size, thumbnail);
            } catch (Error err) {
                // TODO: Mark thumbnails as dirty in database
                warning("Unable to update thumbnails for %s: %s", to_string(), err.message);
            }
        }

        notify_thumbnail_altered();
    }
    
    private override File generate_exportable_file() {
        File original_file = get_file();

        File exportable_dir = AppDirs.get_data_subdir("export");
    
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
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return ThumbnailCache.fetch(get_photo_id(), scale);
    }
    
    public void delete_original_on_destroy() {
        delete_original = true;
    }
    
    public override void destroy() {
        PhotoID photo_id = get_photo_id();

        // remove all cached thumbnails
        ThumbnailCache.remove(photo_id);
        
        // remove exportable file
        delete_exportable_file();
        
        // remove original
        if (delete_original)
            delete_original_file();

        // remove from photo table -- should be wiped from storage now (other classes may have added
        // photo_id to other parts of the database ... it's their responsibility to remove them
        // when removed() is called)
        PhotoTable.get_instance().remove(photo_id);
        
        base.destroy();
    }
    
    private void delete_exportable_file() {
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
    
    private void delete_original_file() {
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
        if (file.has_prefix(AppDirs.get_photos_dir())) {
            File parent = file;
            for (int depth = 0; depth < BatchImport.IMPORT_DIRECTORY_DEPTH; depth++) {
                parent = parent.get_parent();
                if (parent == null)
                    break;
                
                try {
                    if (!query_is_directory_empty(parent))
                        break;
                } catch (Error err) {
                    warning("Unable to query file info for %s: %s", parent.get_path(), err.message);
                    
                    break;
                }
                
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
        info.get_modification_time(out timestamp);
        
        // trust modification time and file size
        if ((timestamp.tv_sec != get_timestamp()) || (info.get_size() != get_filesize()))
            return Currency.DIRTY;
        
        // verify thumbnail cache is all set
        if (!ThumbnailCache.exists(get_photo_id()))
            return Currency.DIRTY;
        
        return Currency.CURRENT;
    }
}

public class DirectPhotoSourceCollection : DatabaseSourceCollection {
    private Gee.HashMap<File, DirectPhoto> file_map = new Gee.HashMap<File, DirectPhoto>(file_hash, 
        file_equal, direct_equal);
    
    public DirectPhotoSourceCollection() {
        base(get_direct_key);
    }
    
    private static int64 get_direct_key(DataSource source) {
        DirectPhoto photo = (DirectPhoto) source;
        PhotoID photo_id = photo.get_photo_id();
        
        return photo_id.id;
    }
    
    public override void notify_items_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            DirectPhoto photo = (DirectPhoto) object;
            File file = photo.get_file();
            
            assert(!file_map.has_key(file));
            
            file_map.set(file, photo);
        }
        
        base.notify_items_added(added);
    }
    
    public override void notify_items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            DirectPhoto photo = (DirectPhoto) object;
            File file = photo.get_file();
            
            bool is_removed = file_map.unset(file);
            assert(is_removed);
        }
        
        base.notify_items_removed(removed);
    }
    
    public DirectPhoto? fetch(File file, bool reset = false) {
        // fetch from the map first, which ensures that only one DirectPhoto exists for each file
        DirectPhoto? photo = (DirectPhoto?) file_map.get(file);
        if (photo != null) {
            // if a reset is necessary, the database (and the object) need to reset to original
            // easiest way to do this: perform an update, which is a kind of in-place re-import
            if (reset)
                photo.update();
            
            return photo;
        }
            
        // for DirectPhoto, a fetch on an unknown file is an implicit import into the in-memory
        // database (which automatically adds the new DirectPhoto object to DirectPhoto.global,
        // which be us)
        return DirectPhoto.internal_import(file);
    }
}

public class DirectPhoto : TransformablePhoto {
    private const int PREVIEW_BEST_FIT = 360;
    
    public static DirectPhotoSourceCollection global = null;
    
    private Gdk.Pixbuf preview;
    private File exportable = null;
    
    private DirectPhoto(PhotoRow row, Gdk.Pixbuf? initial_pixbuf) {
        base(row);
        
        try {
            // Use the initial pixbuf for preview, since it's decoded; if not available generate
            // one now
            preview = (initial_pixbuf != null) ? initial_pixbuf : base.get_pixbuf(
                Scaling.for_best_fit(PREVIEW_BEST_FIT));
        } catch (Error err) {
            warning("%s", err.message);
        } 
    }
    
    public static void init() {
        global = new DirectPhotoSourceCollection();
    }
    
    public static void terminate() {
    }
    
    // This method should only be called by DirectPhotoSourceCollection.  Use
    // DirectPhoto.global.fetch to import files into the system.
    public static DirectPhoto? internal_import(File file) {
        DirectPhoto photo = null;
        
        PhotoID photo_id;
        Gdk.Pixbuf initial_pixbuf;
        ImportResult result = TransformablePhoto.import_photo(file, 
            PhotoTable.get_instance().generate_import_id(), out photo_id, out initial_pixbuf);
        switch (result) {
            case ImportResult.SUCCESS:
                PhotoRow row = PhotoTable.get_instance().get_row(photo_id);
                photo = new DirectPhoto(row, initial_pixbuf);
            break;
            
            case ImportResult.PHOTO_EXISTS:
                // this should never happen; DirectPhotoSourceCollection guarantees it.
                error("import_photo reports photo exists that is not in file_map");
            break;
            
            default:
                photo = null;
            break;
        }
        
        // add to SourceCollection
        if (photo != null)
            global.add(photo);
        
        return photo;
    }
    
    public override File generate_exportable_file() {
        // reuse exportable file if possible
        if (exportable != null)
            return exportable;
        
        // generate an exportable in the app temp directory with the same basename as the file
        // being edited ... as generate_exportable will reuse the file if it exists, and if
        // exportable is null then it's been discarded, delete the old file
        exportable = AppDirs.get_temp_dir().get_child(get_file().get_basename());
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
    
    public override Gdk.Pixbuf get_preview_pixbuf(Scaling scaling) throws Error {
        return scaling.perform_on_pixbuf(preview, Gdk.InterpType.BILINEAR, true);
    }
    
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return scale_pixbuf(preview, scale, Gdk.InterpType.BILINEAR, true);
    }
    
    private override void altered() {
        // stash the current pixbuf for previews and such, and flush the generated exportable file
        try {
            preview = base.get_pixbuf(Scaling.for_best_fit(PREVIEW_BEST_FIT));
        } catch (Error err) {
            warning("%s", err.message);
        }

        exportable = null;
        
        base.altered();
    }
}

