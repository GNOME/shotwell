
public class Photo : Object {
    public enum Rotation {
        CLOCKWISE,
        COUNTERCLOCKWISE,
        MIRROR,
        UPSIDE_DOWN
    }
    
    private static Gee.HashMap<int64?, Photo> photo_map = null;
    private static PhotoTable photo_table = new PhotoTable();
    
    private PhotoID photo_id;
    
    public static Photo? import(File file, ImportID import_id) {
        debug("Importing file %s", file.get_path());

        Dimensions dim = Dimensions();
        Exif.Orientation orientation = Exif.Orientation.TOP_LEFT;
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
        
        // modify pixbuf for thumbnails which are stored with modifications
        pixbuf = rotate_to_exif(pixbuf, orientation);
        
        // import it into the thumbnail cache with modifications
        ThumbnailCache.import(photo_id, pixbuf);
        
        // sanity ... this would be very bad
        assert(!photo_map.contains(photo_id.id));
        
        return fetch(photo_id);
    }

    public static Photo fetch(PhotoID photo_id) {
        Photo photo = null;

        // static initializer isn't working
        if (photo_map == null) {
            photo_map = new Gee.HashMap<int64?, Photo>(int64_hash, int64_equal, direct_equal);
        } else {
            photo = photo_map.get(photo_id.id);
        }
        
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
        Exif.Orientation orientation = photo_table.get_orientation(photo_id);
        
        switch (rotation) {
            case Rotation.CLOCKWISE:
                orientation = orientation.rotate_clockwise();
            break;
            
            case Rotation.COUNTERCLOCKWISE:
                orientation = orientation.rotate_counterclockwise();
            break;
            
            case Rotation.MIRROR:
                orientation = orientation.flip_left_to_right();
            break;
            
            case Rotation.UPSIDE_DOWN:
                orientation = orientation.flip_top_to_bottom();
            break;
            
            default:
                error("Unknown rotation: %d", (int) rotation);
            break;
        }
        
        photo_table.set_orientation(photo_id, orientation);
        
        photo_altered();
    }
    
    public Dimensions get_dimensions() {
        Dimensions dim = photo_table.get_dimensions(photo_id);
        
        dim = dim.get_rotated(photo_table.get_orientation(photo_id));
        
        Box crop;
        if (get_crop(out crop)) {
        }
        
        return dim;
    }
    
    public Dimensions get_scaled_dimensions(int scale) {
        Dimensions dim = get_dimensions();

        return dim.get_scaled(scale);
    }
    
    public bool get_crop(out Box crop) {
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
    
    public bool set_crop(Box crop) {
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
    
    // Returns unscaled pixbuf with all modifications applied
    public Gdk.Pixbuf get_pixbuf() throws Error {
        Gdk.Pixbuf pixbuf = get_unmodified_pixbuf();
        
        // orientation
        pixbuf = rotate_to_exif(pixbuf, photo_table.get_orientation(photo_id));
        
        // crop
        Box crop;
        if (get_crop(out crop)) {
        }

        return pixbuf;
    }
    
    // Returns full pixbuf with all modifications applied scaled to size
    public Gdk.Pixbuf get_scaled_pixbuf(int scale, Gdk.InterpType interp) throws Error {
        Gdk.Pixbuf pixbuf = get_pixbuf();
        pixbuf = scale_pixbuf(pixbuf, scale, interp);
        
        return pixbuf;
    }
    
    // Returns full pixbuf with all modifications applied scaled to proportionally fit in dimensions
    public Gdk.Pixbuf get_pixbuf_for_dimensions(Dimensions dim, Gdk.InterpType interp) throws Error {
        Gdk.Pixbuf pixbuf = get_pixbuf();
        pixbuf = pixbuf.scale_simple(dim.width, dim.height, interp);
        
        return pixbuf;
    }
    
    // Returns pixbuf, unscaled, un-oriented and with no modifications applied
    public Gdk.Pixbuf get_unmodified_pixbuf() throws Error {
        File file = get_file();
        
        debug("Loading full photo %s", file.get_path());

        return new Gdk.Pixbuf.from_file(file.get_path());
    }
    
    // Returns unscaled thumbnail with all modifications applied applicable to the scale
    public Gdk.Pixbuf? get_thumbnail(int scale) {
        return ThumbnailCache.fetch(photo_id, scale);
    }
    
    // Returns scaled thumbnail with all modifications applied
    public Gdk.Pixbuf? get_scaled_thumbnail(int scale, Gdk.InterpType interp) {
        return ThumbnailCache.fetch_scaled(photo_id, scale, interp);
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
        // re-import modified photo into thumbnail cache
        Gdk.Pixbuf modified;
        try {
            modified = get_pixbuf();
        } catch (Error err) {
            error("%s", err.message);
            
            return;
        }
        
        ThumbnailCache.import(photo_id, modified, true);
        
        // signal change to all interested parties
        altered();
    }
}

