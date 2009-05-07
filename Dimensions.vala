
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

        int diffWidth = width - scale;
        int diffHeight = height - scale;

        Dimensions scaled = Dimensions();

        if (diffWidth == diffHeight) {
            // square image -- unlikely -- but this is the easy case
            scaled.width = scale;
            scaled.height = scale;
        } else if (diffWidth <= 0) {
            if (diffHeight <= 0) {
                // if both dimensions are less than the scaled size, return as-is
                return Dimensions(width, height);
            } 
            
            // height needs to be scaled down, so it determines the ratio
            double ratio = (double) scale / (double) height;
            scaled.width = (int) Math.round((double) width * ratio);
            scaled.height = scale;
        } else if (diffWidth > diffHeight) {
            // width is greater, so it's the determining factor
            // (this case is true even when diffHeight is negative)
            scaled.width = scale;
            double ratio = (double) scale / (double) width;
            scaled.height = (int) Math.round((double) height * ratio);
        } else {
            // height is the determining factor
            double ratio = (double) scale / (double) height;
            scaled.width = (int) Math.round((double) width * ratio);
            scaled.height = scale;
        }
        
        return scaled;
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

    public Dimensions get_rotated(Exif.Orientation orientation) {
        int w = width;
        int h = height;
        
        switch(orientation) {
            case Exif.Orientation.TOP_LEFT:
            case Exif.Orientation.TOP_RIGHT:
            case Exif.Orientation.BOTTOM_RIGHT:
            case Exif.Orientation.BOTTOM_LEFT: {
                // fine just as it is
            } break;

            case Exif.Orientation.LEFT_TOP:
            case Exif.Orientation.RIGHT_TOP:
            case Exif.Orientation.RIGHT_BOTTOM:
            case Exif.Orientation.LEFT_BOTTOM: {
                // swap
                w = height;
                h = width;
            } break;

            default: {
                error("Unknown orientation: %d", orientation);
            } break;
        }
        
        return Dimensions(w, h);
    }

    public Gdk.Rectangle get_scaled_rectangle(Dimensions scale, Gdk.Rectangle rect) {
        double x_scale = (double) scale.width / (double) width;
        double y_scale = (double) scale.height / (double) height;
        
        Gdk.Rectangle scaled_rect = Gdk.Rectangle();
        scaled_rect.x = (int) (rect.x * x_scale);
        scaled_rect.y = (int) (rect.y * y_scale);
        scaled_rect.width = (int) (rect.width * x_scale);
        scaled_rect.height = (int) (rect.height * y_scale);
        
        /*
        debug("orig:%dx%d scaled:%dx%d x_scale=%lf y_scale=%lf scaled=%d,%d %dx%d", orig.width,
            orig.height, scaled.width, scaled.height, x_scale, y_scale, scaled_rect.x, scaled_rect.y, 
            scaled_rect.width, scaled_rect.height);
        */
        
        return scaled_rect;
    }
}

