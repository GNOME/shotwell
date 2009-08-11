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

public class Photo : PhotoTransformer, Queryable {
    private static Gee.HashMap<int64?, Photo> photo_map = null;
    private static PhotoTable photo_table = null;
    
    public enum Currency {
        CURRENT,
        DIRTY,
        GONE
    }
    
    private PhotoID photo_id;
    
    // because fetching some items from the database is high-overhead, certain items are cached
    // here ... really want to be frugal about this, as maintaining coherency is complicated enough
    private time_t exposure_time = -1;
    
    public signal void altered();
    
    public signal void thumbnail_altered();
    
    public signal void removed();
    
    private Photo(PhotoID photo_id) {
        assert(photo_id.is_valid());
        
        this.photo_id = photo_id;
        
        // catch our own signal, as this can happen in many different places throughout the code
        altered += remove_exportable_file;
    }
    
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
    
    public PhotoID get_photo_id() {
        return photo_id;
    }
    
    public File get_file() {
        return photo_table.get_file(photo_id);
    }
    
    public string get_name() {
        return photo_table.get_name(photo_id);
    }

    public Queryable.Type get_queryable_type() {
        return Queryable.Type.PHOTO;
    }

    public Value? query_property(Queryable.Property queryable_property) {
        switch (queryable_property) {
            case Queryable.Property.NAME:
                return get_name();

            case Queryable.Property.DIMENSIONS:
                return new BoxedDimensions(get_dimensions());

            case Queryable.Property.TIME:
                return new BoxedTime(get_exposure_time());

            case Queryable.Property.SIZE:
                return get_filesize();

            case Queryable.Property.EXIF:
                return (new PhotoExif(get_file())).get_exif();

            default:
                return null;
        }
    }

    public Gee.Iterable<Queryable>? get_queryables() {
        return null;    
    }

    public uint64 get_filesize() {
        return photo_table.get_filesize(photo_id);    
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
    
    public override Gdk.Pixbuf get_raw_pixbuf() throws Error {
        return new Gdk.Pixbuf.from_file(get_file().get_path());
    }
    
    public override Gdk.Pixbuf get_quick_pixbuf(int scale) throws Error {
        return scale_pixbuf(get_thumbnail(scale), scale, Gdk.InterpType.BILINEAR);
    }
    
    public override Exif.Data? get_exif() {
        PhotoExif photo_exif = new PhotoExif(get_file());
        
        return photo_exif.has_exif() ? photo_exif.get_exif() : null;
    }
    
    public override Dimensions get_raw_dimensions() {
        return photo_table.get_dimensions(photo_id);
    }
    
    public override bool has_transformations() {
        return photo_table.has_transformations(photo_id) 
            || (photo_table.get_orientation(photo_id) != photo_table.get_original_orientation(photo_id));
    }
    
    public override void remove_all_transformations() {
        bool altered = photo_table.remove_all_transformations(photo_id);
        
        Orientation orientation = photo_table.get_orientation(photo_id);
        Orientation original_orientation = photo_table.get_original_orientation(photo_id);
        if (orientation != original_orientation) {
            photo_table.set_orientation(photo_id, original_orientation);
            altered = true;
        }

        if (altered)
            photo_altered();
    }
    
    private override Orientation get_orientation() {
        return photo_table.get_orientation(photo_id);
    }
    
    private override void set_orientation(Orientation orientation) {
        photo_table.set_orientation(photo_id, orientation);
        
        altered();
    }
    
    public override void rotate(Rotation rotation) {
        base.rotate(rotation);

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
    
    public override bool has_crop() {
        return photo_table.get_transformation(photo_id, "crop") != null;
    }
    
    // Returns the crop in the raw photo's coordinate system
    private override bool get_raw_crop(out Box crop) {
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
    private override void set_raw_crop(Box crop) {
        KeyValueMap map = new KeyValueMap("crop");
        map.set_int("left", crop.left);
        map.set_int("top", crop.top);
        map.set_int("right", crop.right);
        map.set_int("bottom", crop.bottom);
        
        if (photo_table.set_transformation(photo_id, map))
            photo_altered();
    }
    
    private override void add_raw_redeye_instance(RedeyeInstance redeye) {
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
            photo_altered();
    }

    private override RedeyeInstance[] get_raw_redeye_instances() {
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

    public override float get_color_adjustment(ColorTransformationKind adjust_kind) {
        KeyValueMap map = photo_table.get_transformation(photo_id, "adjustments");
        if (map == null)
            return 0.0f;
        
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
                
                return 0.0f;
        }
    }
    
    public override void set_color_adjustments(Gee.ArrayList<ColorTransformationInstance?> adjustments) {
        KeyValueMap map = photo_table.get_transformation(photo_id, "adjustments");
        if (map == null)
            map = new KeyValueMap("adjustments");
        
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

        if (photo_table.set_transformation(photo_id, map))
            photo_altered();
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
    
    // Returns a file appropriate for export.  The file should NOT be deleted once it's been used.
    //
    // TODO: Lossless transformations, especially for mere rotations of JFIF files.
    public override File generate_exportable() throws Error {
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
            Gdk.Pixbuf pixbuf = get_pixbuf();
            pixbuf.save(dest_file.get_path(), "jpeg", "quality", EXPORT_JPEG_QUALITY.get_pct_text());
            copy_exported_exif(original_exif, new PhotoExif(dest_file), Orientation.TOP_LEFT,
                Dimensions.for_pixbuf(pixbuf));
        }
        
        return dest_file;
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
        // fire signal
        altered();

        // load transformed image for thumbnail generation
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = get_pixbuf();
        } catch (Error err) {
            error("%s", err.message);
        }
        
        ThumbnailCache.import(photo_id, pixbuf, true);
        
        // fire signal
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
}

