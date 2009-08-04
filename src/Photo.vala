/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public enum ImportResult {
    SUCCESS,
    FILE_ERROR,
    DECODE_ERROR,
    DATABASE_ERROR,
    USER_ABORT,
    NOT_A_FILE,
    PHOTO_EXISTS,
    UNSUPPORTED_FORMAT
}

public class Photo : Object {
    public const int EXCEPTION_NONE          = 0;
    public const int EXCEPTION_ORIENTATION   = 1 << 0;
    public const int EXCEPTION_CROP          = 1 << 1;
    public const int EXCEPTION_REDEYE        = 1 << 2;
    public const int EXCEPTION_ADJUST        = 1 << 3;

    public const Jpeg.Quality EXPORT_JPEG_QUALITY = Jpeg.Quality.HIGH;
    public const Gdk.InterpType EXPORT_INTERP = Gdk.InterpType.BILINEAR;
    
    private static Gee.HashMap<int64?, Photo> photo_map = null;
    private static PhotoTable photo_table = null;
    private static PhotoID cached_photo_id = PhotoID();
    private static Gdk.Pixbuf cached_raw = null;
    
    public enum Currency {
        CURRENT,
        DIRTY,
        GONE
    }
    
    private PhotoID photo_id;
    
    // because fetching some items from the database is high-overhead, certain items are cached
    // here ... really want to be frugal about this, as maintaining coherency is complicated enough
    private time_t exposure_time = -1;
    
    public static void init() {
        photo_map = new Gee.HashMap<int64?, Photo>(int64_hash, int64_equal, direct_equal);
        photo_table = new PhotoTable();
    }
    
    public static void terminate() {
    }
    
    public static ImportResult import(File file, ImportID import_id, out Photo photo) {
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
        
        Gdk.Pixbuf pixbuf;
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

        if (photo_table.is_photo_stored(file))
            return ImportResult.PHOTO_EXISTS;
        
        // photo information is stored in database in raw, non-modified format ... this is especially
        // important dealing with dimensions and orientation
        PhotoID photo_id = photo_table.add(file, dim, info.get_size(), timestamp.tv_sec, exposure_time,
            orientation, import_id);
        if (photo_id.is_invalid())
            return ImportResult.DATABASE_ERROR;
        
        // sanity ... this would be very bad
        assert(!photo_map.contains(photo_id.id));
        
        // modify pixbuf for thumbnails, which are stored with modifications
        pixbuf = orientation.rotate_pixbuf(pixbuf);
        
        // import it into the thumbnail cache with modifications
        ThumbnailCache.import(photo_id, pixbuf);
        
        photo = fetch(photo_id);
        
        return ImportResult.SUCCESS;
    }
    
    public static Photo fetch(PhotoID photo_id) {
        Photo photo = photo_map.get(photo_id.id);

        if (photo == null) {
            photo = new Photo(photo_id);
            photo_map.set(photo_id.id, photo);
        }
        
        return photo;
    }
    
    private Photo(PhotoID photo_id) {
        assert(photo_id.is_valid());
        
        this.photo_id = photo_id;
        
        // catch our own signal, as this can happen in many different places throughout the code
        altered += remove_exportable_file;
    }
    
    public signal void altered();
    
    public signal void thumbnail_altered();
    
    public signal void removed();
    
    public PhotoID get_photo_id() {
        return photo_id;
    }
    
    public File get_file() {
        return photo_table.get_file(photo_id);
    }
    
    public string get_name() {
        return photo_table.get_name(photo_id);
    }
    
    public uint64 query_filesize() {
        FileInfo info = null;
        try {
            info = get_file().query_info(FILE_ATTRIBUTE_STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            debug("Unable to query filesize for %s: %s", get_file().get_path(), err.message);

            return 0;
        }
        
        return info.get_size();
    }
    
    public time_t get_exposure_time() {
        if (exposure_time == -1)
            exposure_time = photo_table.get_exposure_time(photo_id);
        
        return exposure_time;
    }
    
    public time_t get_timestamp() {
        return photo_table.get_timestamp(photo_id);
    }

    public EventID get_event_id() {
        return photo_table.get_event(photo_id);
    }
    
    public void set_event_id(EventID event_id) {
        photo_table.set_event(photo_id, event_id);
    }

    public string to_string() {
        return "[%lld] %s".printf(photo_id.id, get_file().get_path());
    }

    public bool equals(Photo photo) {
        // identity works because of the photo_map, but the photo_table primary key is where the
        // rubber hits the road
        if (this == photo) {
            assert(photo_id.id == photo.photo_id.id);
            
            return true;
        }
        
        assert(photo_id.id != photo.photo_id.id);
        
        return false;
    }
    
    public bool has_transformations() {
        return photo_table.has_transformations(photo_id) 
            || (photo_table.get_orientation(photo_id) != photo_table.get_original_orientation(photo_id));
    }
    
    public void remove_all_transformations() {
        bool altered = photo_table.remove_all_transformations(photo_id);
        
        Orientation orientation = photo_table.get_orientation(photo_id);
        Orientation original_orientation = photo_table.get_original_orientation(photo_id);
        if (orientation != original_orientation) {
            photo_table.set_orientation(photo_id, original_orientation);
            altered = true;
        }

        if (altered) {

            // REDEYE: if photo was altered, clear the pixbuf cache. This is
            // necessary because the redeye transformation, unlike rotate/crop,
            // actually modifies the pixel data in the pixbuf, so we need to
            // re-load the original pixel data from its source file when redeye
            // is cleared
            cached_raw = null;
      
            photo_altered();
        }
    }
    
    public void rotate(Rotation rotation) {
        Orientation orientation = photo_table.get_orientation(photo_id);
        
        orientation = orientation.perform(rotation);
        
        photo_table.set_orientation(photo_id, orientation);
        
        altered();

        // because rotations are (a) common and available everywhere in the app, (b) the user expects
        // a level of responsiveness not necessarily required by other modifications, and (c) can't 
        // cache a lot of full-sized pixbufs for rotate-and-scale ops, perform the rotation directly 
        // on the already-modified thumbnails.
        foreach (int scale in ThumbnailCache.SCALES) {
            Gdk.Pixbuf thumbnail = ThumbnailCache.fetch(photo_id, scale);
            thumbnail = rotation.perform(thumbnail);
            ThumbnailCache.replace(photo_id, scale, thumbnail);
        }

        thumbnail_altered();
    }
    
    // Returns uncropped (but rotated) dimensions
    public Dimensions get_uncropped_dimensions() {
        Dimensions dim = photo_table.get_dimensions(photo_id);
        Orientation orientation = photo_table.get_orientation(photo_id);
        
        return orientation.rotate_dimensions(dim);
    }
    
    // Returns dimensions for fully-modified photo
    public Dimensions get_dimensions() {
        Box crop;
        if (get_crop(out crop))
            return crop.get_dimensions();
        
        return get_uncropped_dimensions();
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
    
    // Returns the rotated crop for the photo
    public bool get_crop(out Box crop) {
        Box raw;
        if (!get_raw_crop(out raw))
            return false;
        
        Dimensions dim = photo_table.get_dimensions(photo_id);
        Orientation orientation = photo_table.get_orientation(photo_id);
        crop = orientation.rotate_box(dim, raw);
        
        return true;
    }
    
    private Orientation get_orientation() {
        return photo_table.get_orientation(photo_id);
    }
    
    // Sets the crop using the raw photo's unrotated coordinate system
    private bool set_raw_crop(Box crop) {
        KeyValueMap map = new KeyValueMap("crop");
        map.set_int("left", crop.left);
        map.set_int("top", crop.top);
        map.set_int("right", crop.right);
        map.set_int("bottom", crop.bottom);
        
        bool res = photo_table.set_transformation(photo_id, map);
        if (res)
            photo_altered();
        
        return res;
    }
    
    // Sets the crop, where the crop is in the rotated coordinate system
    public bool set_crop(Box crop) {
        // return crop to photo's coordinate system
        Dimensions dim = photo_table.get_dimensions(photo_id);
        Orientation orientation = photo_table.get_orientation(photo_id);
        Box derotated = orientation.derotate_box(dim, crop);
        
        assert(derotated.get_width() <= dim.width);
        assert(derotated.get_height() <= dim.height);
        
        return set_raw_crop(derotated);
    }
    
    public bool remove_crop() {
        bool res = photo_table.remove_transformation(photo_id, "crop");
        if (res)
            photo_altered();
        
        return res;
    }

    public bool add_redeye_instance(RedeyeInstance inst_unscaled) {
        Gdk.Rectangle bounds_rect_unscaled =
            RedeyeInstance.to_bounds_rect(inst_unscaled);
        Gdk.Rectangle bounds_rect_raw =
            unscaled_to_raw_rect(bounds_rect_unscaled);
        RedeyeInstance inst = RedeyeInstance.from_bounds_rect(bounds_rect_raw);

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
        
        map.set_int(radius_key, inst.radius);
        map.set_point(center_key, inst.center);
        
        map.set_int("num_points", num_points);

        bool res =  photo_table.set_transformation(photo_id, map);
        
        if (res)
            photo_altered();
        
        return res;
    }

    public bool set_adjustments(Gee.ArrayList<ColorTransformationInstance?> adjustments) {
        KeyValueMap map = photo_table.get_transformation(photo_id,
            "adjustments");

        if (map == null) {
            map = new KeyValueMap("adjustments");
        }
        
        foreach (ColorTransformationInstance adjustment in adjustments) {
            switch(adjustment.kind) {
                case ColorTransformationKind.EXPOSURE:
                    map.set_double("exposure", adjustment.parameter);
                break;
                case ColorTransformationKind.SATURATION:
                    map.set_double("saturation", adjustment.parameter);
                break;
                case ColorTransformationKind.TEMPERATURE:
                    map.set_double("temperature", adjustment.parameter);
                break;
                case ColorTransformationKind.TINT:
                    map.set_double("tint", adjustment.parameter);
                break;
                default:
                    error("unrecognized ColorTransformationKind enumeration value");
                break;
            }
        }

        bool res = photo_table.set_transformation(photo_id, map);
        
        if (res)
            photo_altered();
        
        return res;
    }    

    public float get_adjustment_parameter(ColorTransformationKind adjust_kind) {
        KeyValueMap map = photo_table.get_transformation(photo_id,
            "adjustments");

        if (map == null) {
            return 0.0f;
        }
        
        switch (adjust_kind) {
            case ColorTransformationKind.EXPOSURE:
                return (float) map.get_double("exposure", 0.0f);
            case ColorTransformationKind.SATURATION:
                return (float) map.get_double("saturation", 0.0f);
            case ColorTransformationKind.TEMPERATURE:
                return (float) map.get_double("temperature", 0.0f);
            case ColorTransformationKind.TINT:
                return (float) map.get_double("tint", 0.0f);
            default:
                error("unrecognized ColorTransformationKind enumeration value");
            break;
        }
        return 0.0f;        
    }
    
    public ColorTransformation get_composite_transformation() {
        float exposure_param = get_adjustment_parameter(
            ColorTransformationKind.EXPOSURE);
        float saturation_param = get_adjustment_parameter(
            ColorTransformationKind.SATURATION);
        float tint_param = get_adjustment_parameter(
            ColorTransformationKind.TINT);
        float temperature_param = get_adjustment_parameter(
            ColorTransformationKind.TEMPERATURE);

        ColorTransformation exposure_transform =
            ColorTransformationFactory.get_instance().from_parameter(
            ColorTransformationKind.EXPOSURE, exposure_param);
        ColorTransformation saturation_transform =
            ColorTransformationFactory.get_instance().from_parameter(
            ColorTransformationKind.SATURATION, saturation_param);
        ColorTransformation tint_transform =
            ColorTransformationFactory.get_instance().from_parameter(
            ColorTransformationKind.TINT, tint_param);
        ColorTransformation temperature_transform =
            ColorTransformationFactory.get_instance().from_parameter(
            ColorTransformationKind.TEMPERATURE, temperature_param);

        ColorTransformation composite_transform = ((
                exposure_transform.compose_against(
                saturation_transform)).compose_against(
                temperature_transform)).compose_against(
                tint_transform);
        
        return composite_transform;
    }

    private RedeyeInstance[] get_all_redeye() {
        KeyValueMap map = photo_table.get_transformation(photo_id, "redeye");
        if (map != null) {
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

        return new RedeyeInstance[0];
    }

    private Gdk.Pixbuf do_redeye(owned Gdk.Pixbuf pixbuf,
        owned RedeyeInstance inst) {
        
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

    // Retrieves a full-sized pixbuf for the Photo with all modifications, except those specified
    public Gdk.Pixbuf get_pixbuf(int exceptions = EXCEPTION_NONE, int scale = 0,
        Gdk.InterpType interp = Gdk.InterpType.HYPER) throws Error {
#if MEASURE_PIPELINE
        Timer timer = new Timer();
        Timer total_timer = new Timer();
        double load_and_decode_time = 0.0, pixbuf_copy_time = 0.0, redeye_time = 0.0, 
            adjustment_time = 0.0, crop_time = 0.0, orientation_time = 0.0, scale_time = 0.0;

        total_timer.start();
#endif
        Gdk.Pixbuf pixbuf = null;
        
        if (cached_raw != null && cached_photo_id.id == photo_id.id) {
            // used the cached raw pixbuf, which is merely the last loaded pixbuf
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = cached_raw.copy();
#if MEASURE_PIPELINE
            pixbuf_copy_time = timer.elapsed();
#endif
        } else {
            File file = get_file();

            debug("Loading raw photo %s", file.get_path());
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
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
        // Image modification pipeline
        //

        // redeye reduction
        if ((exceptions & EXCEPTION_REDEYE) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            RedeyeInstance[] redeye_instances = get_all_redeye();
            for (int i = 0; i < redeye_instances.length; i++) {
                pixbuf = do_redeye(pixbuf, redeye_instances[i]);
            }
#if MEASURE_PIPELINE
            redeye_time = timer.elapsed();
#endif
        }

        // crop
        if ((exceptions & EXCEPTION_CROP) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            Box crop;
            if (get_raw_crop(out crop)) {
                pixbuf = new Gdk.Pixbuf.subpixbuf(pixbuf, crop.left, crop.top, crop.get_width(),
                    crop.get_height());
            }
#if MEASURE_PIPELINE
            crop_time = timer.elapsed();
#endif
        }
        
        // scale
        if (scale > 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = scale_pixbuf(pixbuf, scale, interp);
#if MEASURE_PIPELINE
            scale_time = timer.elapsed();
#endif
        }

        // color adjustment
        if ((exceptions & EXCEPTION_ADJUST) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            ColorTransformation composite_transform = get_composite_transformation();
            
            if (!composite_transform.is_identity()) {
                ColorTransformation.transform_pixbuf(composite_transform, pixbuf);
            }
#if MEASURE_PIPELINE
            adjustment_time = timer.elapsed();
#endif
        }

        // orientation (all modifications are stored in unrotated coordinate system)
        if ((exceptions & EXCEPTION_ORIENTATION) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            Orientation orientation = photo_table.get_orientation(photo_id);
            pixbuf = orientation.rotate_pixbuf(pixbuf);
#if MEASURE_PIPELINE
            orientation_time = timer.elapsed();
#endif
        }
        
#if MEASURE_PIPELINE
        double total_time = total_timer.elapsed();
        
        debug("Pipeline: load_and_decode=%lf pixbuf_copy=%lf redeye=%lf crop=%lf scale=%lf adjustment=%lf orientation=%lf total=%lf",
            load_and_decode_time, pixbuf_copy_time, redeye_time, crop_time, scale_time, adjustment_time,
            orientation_time, total_time);
#endif
        
        return pixbuf;
    }
    
    private File generate_exportable_file() throws Error {
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
    
    private void copy_exported_exif(PhotoExif source, PhotoExif dest, Orientation orientation, 
        Dimensions dim) throws Error {
        if (!source.has_exif())
            return;
            
        dest.set_exif(source.get_exif());
        dest.set_dimensions(dim);
        dest.set_orientation(orientation);
        dest.remove_all_tags(Exif.Tag.RELATED_IMAGE_WIDTH);
        dest.remove_all_tags(Exif.Tag.RELATED_IMAGE_LENGTH);
        dest.remove_thumbnail();
        dest.commit();
    }

    // Returns a file appropriate for export.  The file should NOT be deleted once it's been used.
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
        PhotoExif original_exif = new PhotoExif(get_file());
        
        // if only rotated, only need to copy and modify the EXIF
        if (!photo_table.has_transformations(photo_id) && original_exif.has_exif()) {
            original_file.copy(dest_file, FileCopyFlags.OVERWRITE, null, null);

            PhotoExif dest_exif = new PhotoExif(dest_file);
            dest_exif.set_orientation(photo_table.get_orientation(photo_id));
            dest_exif.commit();
        } else {
            Gdk.Pixbuf pixbuf = get_pixbuf();
            pixbuf.save(dest_file.get_path(), "jpeg", "quality", EXPORT_JPEG_QUALITY.get_pct_text());
            copy_exported_exif(original_exif, new PhotoExif(dest_file), Orientation.TOP_LEFT,
                Dimensions.for_pixbuf(pixbuf));
        }
        
        return dest_file;
    }
    
    // Writes a file appropriate for export meeting the specified parameters.
    //
    // TODO: Lossless transformations, especially for mere rotations of JFIF files.
    public void export(File dest_file, int scale, ScaleConstraint constraint,
        Jpeg.Quality quality) throws Error {
        if (constraint == ScaleConstraint.ORIGINAL) {
            // generate a raw exportable file and copy that
            File exportable = generate_exportable();

            exportable.copy(dest_file, FileCopyFlags.OVERWRITE | FileCopyFlags.ALL_METADATA,
                null, null);
            
            return;
        }
        
        Gdk.Pixbuf pixbuf = get_pixbuf();
        Dimensions dim = Dimensions.for_pixbuf(pixbuf);
        Dimensions scaled = dim.get_scaled_by_constraint(scale, constraint);

        // only scale if necessary ... although scale_simple probably catches this, it's an easy
        // check to avoid image loss
        if (dim.width != scaled.width || dim.height != scaled.height)
            pixbuf = pixbuf.scale_simple(scaled.width, scaled.height, EXPORT_INTERP);
        
        pixbuf.save(dest_file.get_path(), "jpeg", "quality", quality.get_pct_text());
        copy_exported_exif(new PhotoExif(get_file()), new PhotoExif(dest_file), Orientation.TOP_LEFT,
            scaled);
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
    
    private void photo_altered() {
        altered();

        // load transformed image for thumbnail generation
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = get_pixbuf();
        } catch (Error err) {
            error("%s", err.message);
        }
        
        ThumbnailCache.import(photo_id, pixbuf, true);
        
        thumbnail_altered();
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
        
        File parent = file;
        
        // remove empty directories corresponding to imported path
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
            // cache coherency
            this.exposure_time = exposure_time;
            
            photo_altered();
        }
    }

    private Gdk.Point unscaled_to_raw_point(Gdk.Point unscaled_point) {
        Orientation unscaled_orientation = get_orientation();
    
        Dimensions unscaled_dims =
            unscaled_orientation.rotate_dimensions(get_dimensions());

        int unscaled_x_offset_raw = 0;
        int unscaled_y_offset_raw = 0;

        Box crop_box = {0};
        bool is_cropped = get_raw_crop(out crop_box);
        if (is_cropped) {
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
    
    private Gdk.Rectangle unscaled_to_raw_rect(Gdk.Rectangle unscaled_rect) {
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

