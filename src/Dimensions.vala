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
                return "Original size";
                
            case DIMENSIONS:
                return "Width or height";
            
            case WIDTH:
                return "Width";
            
            case HEIGHT:
                return "Height";
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

    public Dimensions get_scaled(int scale) {
        assert(scale > 0);

        int diff_width = width - scale;
        int diff_height = height - scale;

        if (diff_width == diff_height) {
            // square image -- unlikely -- but this is the easy case
            return Dimensions(scale, scale);
        } else if (diff_width <= 0) {
            if (diff_height <= 0) {
                // if both dimensions are less than the scaled size, return as-is
                return Dimensions(width, height);
            } 
            
            // height needs to be scaled down, so it determines the ratio
            return get_scaled_by_height(scale);
        } else if (diff_width > diff_height) {
            // width is greater, so it's the determining factor
            // (this case is true even when diff_height is negative)
            return get_scaled_by_width(scale);
        } else {
            // height is the determining factor
            return get_scaled_by_height(scale);
        }
    }
    
    public void get_scale_factors(Dimensions scaled, out double x_scale, out double y_scale) {
        x_scale = (double) scaled.width / (double) width;
        y_scale = (double) scaled.height / (double) height;
    }

    public Dimensions get_scaled_proportional(Dimensions viewport) {
        Dimensions scaled = Dimensions();

        // TODO: Surely this can be done by examining dimensions to avoid double calculations.
        scaled.width = viewport.width;
        double ratio = (double) viewport.width / (double) width;
        scaled.height = (int) ((double) height * ratio);
        if (scaled.height > viewport.height) {
            scaled.height = viewport.height;
            ratio = (double) viewport.height / (double) height;
            scaled.width = (int) ((double) width * ratio);
        }

        assert(scaled.height <= viewport.height);
        assert(scaled.width <= viewport.width);
        
        return scaled;
    }

    public Gdk.Rectangle get_scaled_rectangle(Dimensions scaled, Gdk.Rectangle rect) {
        double x_scale, y_scale;
        get_scale_factors(scaled, out x_scale, out y_scale);
        
        Gdk.Rectangle scaled_rect = Gdk.Rectangle();
        scaled_rect.x = (int) (rect.x * x_scale);
        scaled_rect.y = (int) (rect.y * y_scale);
        scaled_rect.width = (int) (rect.width * x_scale);
        scaled_rect.height = (int) (rect.height * y_scale);
        
        return scaled_rect;
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

