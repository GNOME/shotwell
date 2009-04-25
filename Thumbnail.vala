
public class Thumbnail : LayoutItem {
    public static const int MIN_SCALE = 64;
    public static const int MAX_SCALE = 360;
    public static const int DEFAULT_SCALE = 128;
    public static const Gdk.InterpType LOW_QUALITY_INTERP = Gdk.InterpType.NEAREST;
    public static const Gdk.InterpType HIGH_QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    private PhotoID photoID;
    private File file;
    private int scale;
    private Dimensions originalDim;
    private Dimensions scaledDim;
    private Gdk.Pixbuf cached = null;
    private Gdk.InterpType scaledInterp = LOW_QUALITY_INTERP;
    private Exif.Orientation orientation = Exif.Orientation.TOP_LEFT;
    private time_t exposure_time = 0;
    
    public Thumbnail(PhotoID photoID, int scale = DEFAULT_SCALE) {
        this.photoID = photoID;
        this.scale = scale;
        
        PhotoRow row = PhotoRow();
        bool found = new PhotoTable().get_photo(photoID, out row);
        assert(found);

        file = row.file;
        orientation = row.orientation;
        exposure_time = row.exposure_time;
        originalDim = row.dim;
        scaledDim = get_scaled_dimensions(originalDim, scale);
        scaledDim = get_rotated_dimensions(scaledDim, orientation);
        
        title.set_text(file.get_basename());

        // the image widget is only filled with a Pixbuf when exposed; if the pixbuf is cleared or
        // not present, the widget will collapse, and so the layout manager won't account for it
        // properly when it's off the viewport.  The solution is to manually set the widget's
        // requisition size, even when it contains no pixbuf
        image.set_size_request(scaledDim.width, scaledDim.height);
    }
    
    public File get_file() {
        return file;
    }
    
    public int64 get_filesize() {
        int64 fileSize = -1;
        try {
            FileInfo info = file.query_info(FILE_ATTRIBUTE_STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            
            fileSize = info.get_size();
        } catch(Error err) {
            error("%s", err.message);
        }
        
        return fileSize;
    }
    
    public PhotoID get_photo_id() {
        return photoID;
    }
    
    public Gdk.Pixbuf? get_full_pixbuf() {
        debug("Loading full image %s", file.get_path());

        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }
        
        return pixbuf;
    }
    
    public override void on_backing_changed() {
        // reload everything from the database and update accordingly
        PhotoRow row = PhotoRow();
        bool found = new PhotoTable().get_photo(photoID, out row);
        assert(found);

        file = row.file;
        orientation = row.orientation;
        exposure_time = row.exposure_time;
        originalDim = row.dim;
        scaledDim = get_scaled_dimensions(originalDim, scale);
        scaledDim = get_rotated_dimensions(scaledDim, orientation);
        
        title.set_text(file.get_basename());

        // only fetch and scale if exposed
        if (cached != null) {
            cached = ThumbnailCache.fetch(photoID, scale);
            cached = rotate_to_exif(cached, orientation);
            Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, LOW_QUALITY_INTERP);
            scaledInterp = LOW_QUALITY_INTERP;
            image.set_from_pixbuf(scaled);
        }

        image.set_size_request(scaledDim.width, scaledDim.height);
    }
    
    public time_t get_exposure_time() {
        return exposure_time;
    }
    
    public void resize(int newScale) {
        assert(newScale >= MIN_SCALE);
        assert(newScale <= MAX_SCALE);
        
        if (scale == newScale)
            return;

        int oldScale = scale;
        scale = newScale;
        scaledDim = get_scaled_dimensions(originalDim, scale);
        scaledDim = get_rotated_dimensions(scaledDim, orientation);

        // only fetch and scale if exposed        
        if (cached != null) {
            if (ThumbnailCache.refresh_pixbuf(oldScale, newScale)) {
                cached = ThumbnailCache.fetch(photoID, newScale);
                cached = rotate_to_exif(cached, orientation);
            }
            
            Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, LOW_QUALITY_INTERP);
            scaledInterp = LOW_QUALITY_INTERP;
            image.set_from_pixbuf(scaled);
        }

        // set the image widget's size regardless of the presence of an image
        image.set_size_request(scaledDim.width, scaledDim.height);
    }
    
    public void paint_high_quality() {
        if (cached == null)
            return;
        
        if (scaledInterp == HIGH_QUALITY_INTERP)
            return;
        
        // only go through the scaling if indeed the image is going to be scaled ... although
        // scale_simple() will probably just return the pixbuf if it sees the stupid case, Gtk.Image
        // does not, and will fire off resized events when the new image (which is not really new)
        // is added
        if ((cached.get_width() != scaledDim.width) || (cached.get_height() != scaledDim.height)) {
            Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, HIGH_QUALITY_INTERP);
            image.set_from_pixbuf(scaled);
        }

        scaledInterp = HIGH_QUALITY_INTERP;
    }
    
    public override void exposed() {
        if (cached != null)
            return;

        cached = ThumbnailCache.fetch(photoID, scale);
        cached = rotate_to_exif(cached, orientation);
        Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, LOW_QUALITY_INTERP);
        scaledInterp = LOW_QUALITY_INTERP;
        image.set_from_pixbuf(scaled);
        image.set_size_request(scaledDim.width, scaledDim.height);
    }
    
    public override void unexposed() {
        if (cached == null)
            return;

        cached = null;
        image.clear();
        image.set_size_request(scaledDim.width, scaledDim.height);
    }
    
    public bool is_exposed() {
        return (cached != null);
    }
}

