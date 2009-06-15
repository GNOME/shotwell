public enum ImportResult {
    SUCCESS,
    FILE_ERROR,
    DECODE_ERROR,
    DATABASE_ERROR,
    USER_ABORT,
    NOT_A_FILE,
    PHOTO_EXISTS
}

public class Photo : Object {
    public static const int EXCEPTION_NONE          = 0;
    public static const int EXCEPTION_ORIENTATION   = 1 << 0;
    public static const int EXCEPTION_CROP          = 1 << 1;
    
    public static const Jpeg.Quality EXPORT_JPEG_QUALITY = Jpeg.Quality.HIGH;
    public static const Gdk.InterpType EXPORT_INTERP = Gdk.InterpType.BILINEAR;
    
    private static Gee.HashMap<int64?, Photo> photo_map = null;
    private static PhotoTable photo_table = new PhotoTable();
    private static PhotoID cached_photo_id = PhotoID();
    private static Gdk.Pixbuf cached_raw = null;
    
    public enum Currency {
        CURRENT,
        DIRTY,
        GONE
    }
    
    private PhotoID photo_id;
    
    public static void init() {
        photo_map = new Gee.HashMap<int64?, Photo>(int64_hash, int64_equal, direct_equal);
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
    
    public time_t get_exposure_time() {
        return photo_table.get_exposure_time(photo_id);
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

        if (altered)
            photo_altered();
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
    
    // Retrieves a full-sized pixbuf for the Photo with all modifications, except those specified
    public Gdk.Pixbuf get_pixbuf(int exceptions = EXCEPTION_NONE) throws Error {
        Gdk.Pixbuf pixbuf = null;
        
        if (cached_raw != null && cached_photo_id.id == photo_id.id) {
            // used the cached raw pixbuf, which is merely the last loaded pixbuf
            pixbuf = cached_raw;
        } else {
            File file = get_file();

            debug("Loading raw photo %s", file.get_path());
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        
            // stash for next time
            cached_raw = pixbuf;
            cached_photo_id = photo_id;
        }
        
        //
        // Image modification pipeline
        //
        
        // crop
        if ((exceptions & EXCEPTION_CROP) == 0) {
            Box crop;
            if (get_raw_crop(out crop)) {
                pixbuf = new Gdk.Pixbuf.subpixbuf(pixbuf, crop.left, crop.top, crop.get_width(),
                    crop.get_height());
            }
        }

        // orientation (all modifications are stored in unrotated coordinate system)
        if ((exceptions & EXCEPTION_ORIENTATION) == 0) {
            Orientation orientation = photo_table.get_orientation(photo_id);
            pixbuf = orientation.rotate_pixbuf(pixbuf);
        }
        
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
    
    public void remove() {
        // signal all interested parties prior to removal from map
        removed();

        // remove all cached thumbnails
        ThumbnailCache.remove(photo_id);
        
        // remove exportable file
        remove_exportable_file();
        
        // remove from photo table -- should be wiped from storage now
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
            photo_altered();
        }
    }
}

