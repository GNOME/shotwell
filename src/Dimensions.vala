/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public enum ScaleConstraint {
    ORIGINAL,
    DIMENSIONS,
    WIDTH,
    HEIGHT;
    
    public string? to_string() {
        switch (this) {
            case ORIGINAL:
                return _("Original size");
                
            case DIMENSIONS:
                return _("Width or height");
            
            case WIDTH:
                return _("Width");
            
            case HEIGHT:
                return _("Height");
        }

        warn_if_reached();

        return null;
    }
}
    
public struct Dimensions {
    public int width;
    public int height;
    
    public Dimensions(int width = 0, int height = 0) {
        assert((width >= 0) && (height >= 0));

        this.width = width;
        this.height = height;
    }
    
    public static Dimensions for_pixbuf(Gdk.Pixbuf pixbuf) {
        return Dimensions(pixbuf.get_width(), pixbuf.get_height());
    }
    
    public static Dimensions for_allocation(Gtk.Allocation allocation) {
        return Dimensions(allocation.width, allocation.height);
    }
    
    public static Dimensions for_rectangle(Gdk.Rectangle rect) {
        return Dimensions(rect.width, rect.height);
    }
    
    public bool has_area() {
        return (width > 0 && height > 0);
    }
    
    public string to_string() {
        return "%dx%d".printf(width, height);
    }
    
    public bool equals(Dimensions dim) {
        return (width == dim.width && height == dim.height);
    }
    
    // sometimes a pixel or two is okay
    public bool approx_equals(Dimensions dim, int fudge = 1) {
        return (width - dim.width).abs() <= fudge && (height - dim.height).abs() <= fudge;
    }
    
    public int major_axis() {
        return int.max(width, height);
    }
    
    public int minor_axis() {
        return int.min(width, height);
    }
    
    public Dimensions get_scaled(int scale, bool scale_up) {
        assert(scale > 0);
        
        // check for existing best-fit
        if (width == scale || height == scale)
            return Dimensions(width, height);
        
        // watch for scaling up
        if (!scale_up && (width < scale && height < scale))
            return Dimensions(width, height);
        
        int diff_width = width - scale;
        int diff_height = height - scale;
        
        if (diff_width > diff_height)
            return get_scaled_by_width(scale);
        else
            return get_scaled_by_height(scale);
    }
    
    public void get_scale_ratios(Dimensions scaled, out double width_ratio, out double height_ratio) {
        width_ratio = (double) scaled.width / (double) width;
        height_ratio = (double) scaled.height / (double) height;
    }

    public Dimensions get_scaled_proportional(Dimensions viewport) {
        double width_ratio, height_ratio;
        get_scale_ratios(viewport, out width_ratio, out height_ratio);
        
        double scaled_width, scaled_height;
        if (width_ratio < height_ratio) {
            scaled_width = viewport.width;
            scaled_height = (double) height * width_ratio;
        } else {
            scaled_width = (double) width * height_ratio;
            scaled_height = viewport.height;
        }
        
        Dimensions scaled = Dimensions((int) Math.round(scaled_width), (int) Math.round(scaled_height));
        assert(scaled.height <= viewport.height);
        assert(scaled.width <= viewport.width);
        
        return scaled;
    }

    public Gdk.Rectangle get_scaled_rectangle(Dimensions scaled, Gdk.Rectangle rect) {
        double x_scale, y_scale;
        get_scale_ratios(scaled, out x_scale, out y_scale);
        
        Gdk.Rectangle scaled_rect = Gdk.Rectangle();
        scaled_rect.x = (int) Math.round((double) rect.x * x_scale);
        scaled_rect.y = (int) Math.round((double) rect.y * y_scale);
        scaled_rect.width = (int) Math.round((double) rect.width * x_scale);
        scaled_rect.height = (int) Math.round((double) rect.height * y_scale);
        
        return scaled_rect;
    }
    
    // Returns the current dimensions scaled in a similar proportion as the two suppled dimensions
    public Dimensions get_scaled_similar(Dimensions original, Dimensions scaled) {
        double x_scale, y_scale;
        original.get_scale_ratios(scaled, out x_scale, out y_scale);
        
        double scale = double.min(x_scale, y_scale);
        
        return Dimensions((int) Math.round((double) width * scale), 
            (int) Math.round((double) height * scale));
    }
    
    public Dimensions get_scaled_by_width(int scale) {
        double ratio = (double) scale / (double) width;
        
        return Dimensions(scale, (int) Math.round((double) height * ratio));
    }
    
    public Dimensions get_scaled_by_height(int scale) {
        double ratio = (double) scale / (double) height;
        
        return Dimensions((int) Math.round((double) width * ratio), scale);
    }
    
    public Dimensions get_scaled_by_constraint(int scale, ScaleConstraint constraint) {
        switch (constraint) {
            case ScaleConstraint.ORIGINAL:
                return Dimensions(width, height);
                
            case ScaleConstraint.DIMENSIONS:
                return (width >= height) ? get_scaled_by_width(scale) : get_scaled_by_height(scale);
            
            case ScaleConstraint.WIDTH:
                return get_scaled_by_width(scale);
            
            case ScaleConstraint.HEIGHT:
                return get_scaled_by_height(scale);
        }

        error("Bad constraint: %d", (int) constraint);
        
        return Dimensions();
    }
}

public struct Scaling {
    private const int NO_SCALE = 0;
    
    private ScaleConstraint constraint;
    private int scale;
    private Dimensions viewport;
    private bool scale_up;
    
    private Scaling(ScaleConstraint constraint, int scale, Dimensions viewport, bool scale_up) {
        this.constraint = constraint;
        this.scale = scale;
        this.viewport = viewport;
        this.scale_up = scale_up;
    }
    
    public static Scaling for_original() {
        return Scaling(ScaleConstraint.ORIGINAL, NO_SCALE, Dimensions(), false);
    }
    
    public static Scaling for_screen(Gtk.Window window, bool scale_up) {
        return for_viewport(get_screen_dimensions(window), scale_up);
    }
    
    public static Scaling for_best_fit(int pixels, bool scale_up) {
        assert(pixels > 0);
        
        return Scaling(ScaleConstraint.DIMENSIONS, pixels, Dimensions(), scale_up);
    }
    
    public static Scaling for_viewport(Dimensions viewport, bool scale_up) {
        assert(viewport.has_area());
        
        return Scaling(ScaleConstraint.DIMENSIONS, NO_SCALE, viewport, scale_up);
    }
    
    public static Scaling for_widget(Gtk.Widget widget, bool scale_up) {
        Dimensions viewport = Dimensions.for_allocation(widget.allocation);
        assert(viewport.has_area());
        
        return Scaling(ScaleConstraint.DIMENSIONS, NO_SCALE, viewport, scale_up);
    }
    
    private static Dimensions get_screen_dimensions(Gtk.Window window) {
        Gdk.Screen screen = window.get_screen();
        
        return Dimensions(screen.get_width(), screen.get_height());
    }
    
    private int scale_to_pixels() {
        return (scale >= 0) ? scale : 0;
    }
    
    public bool is_unscaled() {
        return constraint == ScaleConstraint.ORIGINAL;
    }
    
    public bool is_best_fit(Dimensions original, out int pixels) {
        if (constraint == ScaleConstraint.ORIGINAL || scale == NO_SCALE)
            return false;
            
        pixels = scale_to_pixels();
        assert(pixels > 0);
        
        return true;
    }
    
    public bool is_best_fit_dimensions(Dimensions original, out Dimensions scaled) {
        int pixels;
        if (!is_best_fit(original, out pixels))
            return false;
        
        scaled = original.get_scaled(pixels, scale_up);
        
        return true;
    }
    
    public bool is_for_viewport(Dimensions original, out Dimensions scaled) {
        if (constraint == ScaleConstraint.ORIGINAL || scale != NO_SCALE)
            return false;
        
        assert(viewport.has_area());
        
        if (!scale_up && original.width < viewport.width && original.height < viewport.height)
            scaled = original;
        else
            scaled = original.get_scaled_proportional(viewport);
        
        return true;
    }
    
    public Dimensions get_scaled_dimensions(Dimensions original) {
        if (is_unscaled())
            return original;
        
        Dimensions scaled;
        if (is_best_fit_dimensions(original, out scaled))
            return scaled;
        
        bool is_viewport = is_for_viewport(original, out scaled);
        assert(is_viewport);
        
        return scaled;
    }
    
    public Gdk.Pixbuf perform_on_pixbuf(Gdk.Pixbuf pixbuf, Gdk.InterpType interp, bool scale_up) {
        if (is_unscaled())
            return pixbuf;
        
        Dimensions pixbuf_dim = Dimensions.for_pixbuf(pixbuf);
        
        int pixels;
        if (is_best_fit(pixbuf_dim, out pixels))
            return scale_pixbuf(pixbuf, pixels, interp, scale_up);
        
        Dimensions scaled;
        bool is_viewport = is_for_viewport(pixbuf_dim, out scaled);
        assert(is_viewport);
        
        return resize_pixbuf(pixbuf, scaled, interp);
    }
    
    public string to_string() {
        if (constraint == ScaleConstraint.ORIGINAL)
            return "scaling: UNSCALED";
        else if (scale != NO_SCALE)
            return "scaling: best-fit (%d pixels %s)".printf(scale_to_pixels(),
                scale_up ? "scaled up" : "not scaled up");
        else
            return "scaling: viewport %s (%s)".printf(viewport.to_string(),
                scale_up ? "scaled up" : "not scaled up");
    }
    
    public bool equals(Scaling scaling) {
        return (constraint == scaling.constraint) && (scale == scaling.scale) 
            && viewport.equals(scaling.viewport);
    }
}

