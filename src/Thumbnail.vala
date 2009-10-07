/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Thumbnail : LayoutItem {
    public const int MIN_SCALE = 72;
    public const int MAX_SCALE = ThumbnailCache.Size.LARGEST.get_scale();
    public const int DEFAULT_SCALE = ThumbnailCache.Size.MEDIUM.get_scale();
    
    public const Gdk.InterpType LOW_QUALITY_INTERP = Gdk.InterpType.NEAREST;
    public const Gdk.InterpType HIGH_QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    private const int HQ_IMPROVEMENT_MSEC = 250;
    
    private int scale;
    private Dimensions original_dim;
    private Dimensions dim;
    private Cancellable cancellable = null;
    private OneShotScheduler hq_scheduler = null;
    private Gdk.Pixbuf to_scale = null;
    
    public Thumbnail(LibraryPhoto photo, int scale = DEFAULT_SCALE) {
        base(photo, photo.get_dimensions().get_scaled(scale, true));
        
        this.scale = scale;
        hq_scheduler = new OneShotScheduler(on_schedule_high_quality);
        
        set_title(photo.get_name());

        original_dim = photo.get_dimensions();
        dim = original_dim.get_scaled(scale, true);
    }
    
    public LibraryPhoto get_photo() {
        return (LibraryPhoto) get_source();
    }
    
    private override void thumbnail_altered() {
        original_dim = get_photo().get_dimensions();
        dim = original_dim.get_scaled(scale, true);
        
        if (is_exposed())
            schedule_low_quality_fetch();
        else
            paint_empty();
        
        base.thumbnail_altered();
    }
    
    // This method fires no signals.  It's assumed this is being called as part of a
    // mass resizing and depends on the caller to initiate repaint/reflows.
    public void resize(int new_scale) {
        assert(new_scale >= MIN_SCALE);
        assert(new_scale <= MAX_SCALE);
        
        if (scale == new_scale)
            return;
        
        scale = new_scale;
        dim = original_dim.get_scaled(scale, true);
        
        cancel_async_fetch();
        
        to_scale = get_image();
        clear_image(dim, false);
    }
    
    private void paint_empty() {
        cancel_async_fetch();
        clear_image(dim);
    }
    
    private void schedule_low_quality_fetch() {
        cancel_async_fetch();
        cancellable = new Cancellable();
        
        ThumbnailCache.fetch_async_scaled(get_photo().get_photo_id(), ThumbnailCache.Size.SMALLEST, 
            dim, LOW_QUALITY_INTERP, on_low_quality_fetched, cancellable);
    }
    
    private void schedule_high_quality_fetch() {
        hq_scheduler.after_timeout(HQ_IMPROVEMENT_MSEC, true);
    }
    
    private void on_schedule_high_quality() {
        // cancel outstanding I/O (but not the hq_scheduler, hence not using cancel_async_fetch)
        if (cancellable != null)
            cancellable.cancel();
        cancellable = new Cancellable();
        
        ThumbnailCache.fetch_async_scaled(get_photo().get_photo_id(), scale, dim, HIGH_QUALITY_INTERP,
            on_high_quality_fetched, cancellable);
    }
    
    private void cancel_async_fetch() {
        // cancel the delayed fetch
        hq_scheduler.cancel();
        
        // cancel outstanding I/O
        if (cancellable != null)
            cancellable.cancel();
    }
    
    private void on_low_quality_fetched(Gdk.Pixbuf? pixbuf, Dimensions dim, Gdk.InterpType interp, 
        Error? err) {
        if (err != null)
            error("Unable to fetch low-quality thumbnail for %s (scale: %d): %s", to_string(), scale,
                err.message);
        
        if (pixbuf != null)
            set_image(pixbuf);

        schedule_high_quality_fetch();
    }
    
    private void on_high_quality_fetched(Gdk.Pixbuf? pixbuf, Dimensions dim, Gdk.InterpType interp, 
        Error? err) {
        if (err != null)
            error("Unable to fetch high-quality thumbnail for %s (scale: %d): %s", to_string(), scale, 
                err.message);
        
        if (pixbuf != null)
            set_image(pixbuf);
    }
    
    public override void exposed() {
        if (!is_exposed() || !has_image()) {
            if (to_scale != null) {
                set_image(resize_pixbuf(to_scale, dim, LOW_QUALITY_INTERP), false);
                to_scale = null;
            }
            
            schedule_low_quality_fetch();
        }

        base.exposed();
    }
    
    public override void unexposed() {
        cancel_async_fetch();
        to_scale = null;
        
        if (is_exposed() || has_image())
            paint_empty();
        
        base.unexposed();
    }
}
