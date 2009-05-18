
public class Photo : Object {
    public static const int EXCEPTION_NONE          = 0;
    public static const int EXCEPTION_ORIENTATION   = 1 << 0;
    public static const int EXCEPTION_CROP          = 1 << 1;
    
    private static Gee.HashMap<int64?, Photo> photo_map = null;
    private static PhotoTable photo_table = new PhotoTable();
    private static PhotoID cached_photo_id = PhotoID();
    private static Gdk.Pixbuf cached_raw = null;
    
    private PhotoID photo_id;
    
    public static void init() {
        photo_map = new Gee.HashMap<int64?, Photo>(int64_hash, int64_equal, direct_equal);
    }
    
    public static void terminate() {
    }
    
    public static Photo? import(File file, ImportID import_id) {
        debug("Importing file %s", file.get_path());

        Dimensions dim = Dimensions();
        Orientation orientation = Orientation.TOP_LEFT;
        time_t exposure_time = 0;
        
        // TODO: Try to read JFIF metadata too
        PhotoExif exif = new PhotoExif(file);
        if (exif.has_exif()) {
            if (!exif.get_dimensions(out dim)) {
                debug("Unable to read EXIF dimensions for %s", file.get_path());
            }
            
            if (!exif.get_datetime_time(out exposure_time)) {
                debug("Unable to read EXIF orientation for %s", file.get_path());
            }

            orientation = exif.get_orientation();
        } 
        
        Gdk.Pixbuf pixbuf;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // XXX: Trust EXIF or Pixbuf for dimensions?
        if (!dim.has_area())
            dim = Dimensions(pixbuf.get_width(), pixbuf.get_height());

        FileInfo info = null;
        try {
            info = file.query_info("*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            error("%s", err.message);
        }
        
        TimeVal timestamp = TimeVal();
        info.get_modification_time(timestamp);
        
        // photo information is stored in database in raw, non-modified format ... this is especially
        // important dealing with dimensions and orientation
        PhotoID photo_id = photo_table.add(file, dim, info.get_size(), timestamp.tv_sec, exposure_time,
            orientation, import_id);
        if (photo_id.is_invalid()) {
            debug("Not importing %s (already imported)", file.get_path());
            
            return null;
        }
        
        // sanity ... this would be very bad
        assert(!photo_map.contains(photo_id.id));
        
        // modify pixbuf for thumbnails which are stored with modifications
        pixbuf = orientation.rotate_pixbuf(pixbuf);
        
        // import it into the thumbnail cache with modifications
        ThumbnailCache.import(photo_id, pixbuf);
        
        return fetch(photo_id);
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
            
            debug("Loading full photo %s", file.get_path());
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

        // Orientation (all modifications are stored in unrotated coordinate system)
        if ((exceptions & EXCEPTION_ORIENTATION) == 0) {
            Orientation orientation = photo_table.get_orientation(photo_id);
            pixbuf = orientation.rotate_pixbuf(pixbuf);
        }
        
        return pixbuf;
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
        
        // remove from photo table -- should be wiped from storage now
        photo_table.remove(photo_id);

        // remove from global map
        photo_map.remove(photo_id.id);
    }
    
    private void photo_altered() {
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = get_pixbuf();
        } catch (Error err) {
            error("%s", err.message);
        }
        
        ThumbnailCache.import(photo_id, pixbuf, true);
        
        altered();
        thumbnail_altered();
    }
}

