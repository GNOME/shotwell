/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Thumbnail : LayoutItem {
    public const int MIN_SCALE = ThumbnailCache.Size.SMALLEST.get_scale() / 2;
    public const int MAX_SCALE = ThumbnailCache.Size.LARGEST.get_scale();
    public const int DEFAULT_SCALE = ThumbnailCache.Size.MEDIUM.get_scale();
    
    public const Gdk.InterpType LOW_QUALITY_INTERP = Gdk.InterpType.NEAREST;
    public const Gdk.InterpType HIGH_QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    private int scale;
    private Dimensions dim;
    private Gdk.InterpType interp = LOW_QUALITY_INTERP;
    
    public Thumbnail(LibraryPhoto photo, int scale = DEFAULT_SCALE) {
        base(photo, photo.get_dimensions().get_scaled(scale));
        
        this.scale = scale;
        
        set_title(photo.get_name());

        // store for exposed/unexposed events
        dim = photo.get_dimensions().get_scaled(scale);
    }
    
    public LibraryPhoto get_photo() {
        return (LibraryPhoto) get_source();
    }
    
    private Gdk.Pixbuf? get_thumbnail() {
        try {
            return get_photo().get_thumbnail(scale);
        } catch (Error err) {
            error("Unable to fetch thumbnail at %d scale for %s: %s", scale, 
                get_photo().to_string(), err.message);
            
            return null;
        }
    }
    
    private override void thumbnail_altered() {
        dim = get_photo().get_dimensions().get_scaled(scale);
        
        // only fetch and scale if exposed
        if (is_exposed()) {
            Gdk.Pixbuf pixbuf = get_thumbnail();
            pixbuf = resize_pixbuf(pixbuf, dim, LOW_QUALITY_INTERP);
            interp = LOW_QUALITY_INTERP;
            
            set_image(pixbuf);
        } else {
            clear_image(dim.width, dim.height);
        }

        base.thumbnail_altered();
    }
    
    public bool is_low_quality_thumbnail() {
        return interp != HIGH_QUALITY_INTERP;
    }
    
    public void resize(int new_scale) {
        assert(new_scale >= MIN_SCALE);
        assert(new_scale <= MAX_SCALE);
        
        if (scale == new_scale)
            return;
        
        scale = new_scale;
        
        // piggy-back on signal handler
        notify_thumbnail_altered();
    }
    
    public void paint_high_quality() {
        if (!is_exposed())
            return;
        
        if (interp == HIGH_QUALITY_INTERP)
            return;
        
        Gdk.Pixbuf pixbuf = get_thumbnail();

        // only change pixbufs if indeed the image is scaled
        Gdk.Pixbuf scaled = resize_pixbuf(pixbuf, dim, HIGH_QUALITY_INTERP);
        if (scaled != pixbuf) {
            pixbuf = scaled;
            set_image(pixbuf);
        }

        interp = HIGH_QUALITY_INTERP;
    }
    
    public override void exposed() {
        if (!is_exposed()) {
            Gdk.Pixbuf pixbuf = get_thumbnail();
            pixbuf = scale_pixbuf(pixbuf, scale, LOW_QUALITY_INTERP);
            interp = LOW_QUALITY_INTERP;
            
            set_image(pixbuf);
        }

        base.exposed();
    }
    
    public override void unexposed() {
        if (is_exposed())
            clear_image(dim.width, dim.height);
        
        base.unexposed();
    }
}
