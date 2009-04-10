
public class Thumbnail : LayoutItem {
    public static const int MIN_SCALE = 64;
    public static const int MAX_SCALE = 360;
    public static const int DEFAULT_SCALE = 128;
    public static const Gdk.InterpType LOW_QUALITY_INTERP = Gdk.InterpType.NEAREST;
    public static const Gdk.InterpType HIGH_QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    private static Gee.HashMap<int, Thumbnail> thumbnailMap = null;
    
    public static Thumbnail get_existing(PhotoID photoID) {
        return thumbnailMap.get(photoID.id);
    }
    
    public static Thumbnail create(PhotoID photoID, File file, int scale = DEFAULT_SCALE) {
        Thumbnail thumbnail = null;

        // this gets around a problem with static initializers
        if (thumbnailMap == null) {
            thumbnailMap = new Gee.HashMap<int, Thumbnail>(direct_hash, direct_equal, direct_equal);
        } else {
            thumbnail = thumbnailMap.get(photoID.id);
        }
        
        if (thumbnail == null) {
            thumbnail = new Thumbnail(photoID, file, scale);
            thumbnailMap.set(photoID.id, thumbnail);
        }
        
        return thumbnail;
    }
    
    public static void remove_instance(Thumbnail thumbnail) {
        assert(thumbnailMap != null);
        
        thumbnailMap.remove(thumbnail.photoID.id);
    }
    
    private PhotoID photoID;
    private File file;
    private int scale;
    private Dimensions originalDim;
    private Dimensions scaledDim;
    private Gdk.Pixbuf cached = null;
    private Gdk.InterpType scaledInterp = LOW_QUALITY_INTERP;
    private PhotoExif exif;
    private time_t time = time_t();
    
    private Thumbnail(PhotoID photoID, File file, int scale = DEFAULT_SCALE) {
        this.photoID = photoID;
        this.file = file;
        this.scale = scale;
        this.exif = PhotoExif.create(file);
        this.originalDim = new PhotoTable().get_dimensions(photoID);
        this.scaledDim = get_scaled_dimensions(originalDim, scale);
        this.scaledDim = get_rotated_dimensions(scaledDim, exif.get_orientation());
        exif.get_datetime_time(out this.time);
        
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
    
    public void refresh_exif() {
        exif = PhotoExif.create(file);
        
        // flush the cached image and set size for next paint
        cached = null;
        scaledDim = get_scaled_dimensions(originalDim, scale);
        scaledDim = get_rotated_dimensions(scaledDim, exif.get_orientation());
        image.set_size_request(scaledDim.width, scaledDim.height);
    }

    public PhotoID get_photo_id() {
        return photoID;
    }
    
    public Exif.Orientation get_orientation() {
        return exif.get_orientation();
    }
    
    public void set_orientation(Exif.Orientation orientation) {
        if (orientation == exif.get_orientation())
            return;
            
        exif.set_orientation(orientation);
        
        // rotate dimensions from original dimensions (which doesn't require access to pixbuf)
        scaledDim = get_scaled_dimensions(originalDim, scale);
        scaledDim = get_rotated_dimensions(scaledDim, orientation);
        
        // rotate image if exposed ... need to rotate everything (the cached thumbnail and the
        // scaled image in the widget) to be ready for future events, i.e. resize()
        if (cached != null) {
            cached = ThumbnailCache.fetch(photoID, scale);
            cached = rotate_to_exif(cached, orientation);

            Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, LOW_QUALITY_INTERP);
            scaledInterp = LOW_QUALITY_INTERP;

            image.set_from_pixbuf(scaled);
        }
        
        image.set_size_request(scaledDim.width, scaledDim.height);
        
        // TODO: Write this in the background
        try {
            exif.commit();
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    public void display_title(bool display) {
        title.visible = display;
    }
    
    public time_t get_time_t() {
        return time;
    }
    
    public void resize(int newScale) {
        assert(newScale >= MIN_SCALE);
        assert(newScale <= MAX_SCALE);
        
        if (scale == newScale)
            return;

        int oldScale = scale;
        scale = newScale;
        scaledDim = get_scaled_dimensions(originalDim, scale);
        scaledDim = get_rotated_dimensions(scaledDim, exif.get_orientation());

        // only fetch and scale if exposed        
        if (cached != null) {
            if (ThumbnailCache.refresh_pixbuf(oldScale, newScale)) {
                cached = ThumbnailCache.fetch(photoID, newScale);
                cached = rotate_to_exif(cached, exif.get_orientation());
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
        cached = rotate_to_exif(cached, exif.get_orientation());
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

