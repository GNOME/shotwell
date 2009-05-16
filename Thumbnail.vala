
public class Thumbnail : LayoutItem {
    // cannot use consts in ThumbnailCache for some reason
    public static const int MIN_SCALE = 64;
    public static const int MAX_SCALE = 360;
    public static const int DEFAULT_SCALE = 128;
    
    public static const Gdk.InterpType LOW_QUALITY_INTERP = Gdk.InterpType.NEAREST;
    public static const Gdk.InterpType HIGH_QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    private Photo photo;
    private int scale;
    private Dimensions dim;
    private bool thumb_exposed = false;
    private Gdk.InterpType interp = LOW_QUALITY_INTERP;
    
    public Thumbnail(Photo photo, int scale = DEFAULT_SCALE) {
        this.photo = photo;
        this.scale = scale;
        
        title.set_text(photo.get_file().get_basename());

        dim = photo.get_dimensions().get_scaled(scale);

        // the image widget is only filled with a Pixbuf when exposed; if the pixbuf is cleared or
        // not present, the widget will collapse, and so the layout manager won't account for it
        // properly when it's off the viewport.  The solution is to manually set the widget's
        // requisition size, even when it contains no pixbuf
        image.set_size_request(dim.width, dim.height);

        photo.thumbnail_altered += on_thumbnail_altered;
    }
    
    public Photo get_photo() {
        return photo;
    }
    
    private void on_thumbnail_altered(Photo p) {
        assert(photo.equals(p));
        
        dim = photo.get_dimensions().get_scaled(scale);
        
        // only fetch and scale if exposed
        if (thumb_exposed) {
            Gdk.Pixbuf pixbuf = photo.get_thumbnail(scale);
            pixbuf = pixbuf.scale_simple(dim.width, dim.height, LOW_QUALITY_INTERP);
            interp = LOW_QUALITY_INTERP;
            
            image.set_from_pixbuf(pixbuf);
        }
        
        image.set_size_request(dim.width, dim.height);
    }
    
    public void resize(int new_scale) {
        assert(new_scale >= MIN_SCALE);
        assert(new_scale <= MAX_SCALE);
        
        if (scale == new_scale)
            return;
        
        scale = new_scale;
        
        // piggy-back on signal handler
        on_thumbnail_altered(photo);
    }
    
    public void paint_high_quality() {
        if (!thumb_exposed)
            return;
        
        if (interp == HIGH_QUALITY_INTERP)
            return;
        
        Gdk.Pixbuf pixbuf = photo.get_thumbnail(scale);

        // only change pixbufs if indeed the image is scaled ... although
        // scale_simple() will probably just return the pixbuf if it sees the stupid case, Gtk.Image
        // does not see the case, and will fire off resized events when the new image (which is not 
        // really new) is added
        if ((pixbuf.get_width() != dim.width) || (pixbuf.get_height() != dim.height)) {
            pixbuf = pixbuf.scale_simple(dim.width, dim.height, HIGH_QUALITY_INTERP);
            image.set_from_pixbuf(pixbuf);
        }

        interp = HIGH_QUALITY_INTERP;
    }
    
    public override void exposed() {
        if (thumb_exposed)
            return;

        Gdk.Pixbuf pixbuf = photo.get_thumbnail(scale);
        pixbuf = scale_pixbuf(pixbuf, scale, LOW_QUALITY_INTERP);
        interp = LOW_QUALITY_INTERP;

        image.set_from_pixbuf(pixbuf);
        image.set_size_request(dim.width, dim.height);
        
        thumb_exposed = true;
    }
    
    public override void unexposed() {
        if (!thumb_exposed)
            return;

        image.clear();
        image.set_size_request(dim.width, dim.height);
        
        thumb_exposed = false;
    }
    
    public bool is_exposed() {
        return thumb_exposed;
    }
}

