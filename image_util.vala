
Gdk.Color parse_color(string color) {
    Gdk.Color c;
    if (!Gdk.Color.parse(color, out c))
        error("can't parse color");

    return c;
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
}

public enum BoxLocation {
    OUTSIDE,
    INSIDE,
    TOP_SIDE,
    LEFT_SIDE,
    RIGHT_SIDE,
    BOTTOM_SIDE,
    TOP_LEFT,
    BOTTOM_LEFT,
    TOP_RIGHT,
    BOTTOM_RIGHT
}

public struct Box {
    public static const int HAND_GRENADES = 6;
    
    public int left;
    public int top;
    public int right;
    public int bottom;

    public Box(int left, int top, int right, int bottom) {
        assert(left >= 0);
        assert(top >= 0);
        assert(right >= left);
        assert(bottom >= top);
        
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
    }
    
    public static Box from_rectangle(Gdk.Rectangle rect) {
        return Box(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height);
    }
    
    public int get_width() {
        assert(right >= left);
        
        return right - left;
    }
    
    public int get_height() {
        assert(bottom >= top);
        
        return bottom - top;
    }
    
    public bool is_valid() {
        return (left >= 0) && (top >= 0) && (right >= left) && (bottom >= top);
    }
    
    public Box get_scaled(Dimensions orig, Dimensions scaled) {
        double x_scale = (double) scaled.width / (double) orig.width;
        double y_scale = (double) scaled.height / (double) orig.height;
    
        Box box = Box((int) (left * x_scale), (int) (top * y_scale), (int) (right * x_scale),
            (int) (bottom * y_scale));
        
        return box;
    }
    
    public Box get_offset(int xofs, int yofs) {
        return Box(left + xofs, top + yofs, right + xofs, bottom + yofs);
    }
    
    public Gdk.Rectangle get_rectangle() {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = left;
        rect.y = top;
        rect.width = get_width();
        rect.height = get_height();
        
        return rect;
    }
    
    public string to_string() {
        return "%d,%d %d,%d".printf(left, top, right, bottom);
    }

    private static bool in_zone(double pos, int zone) {
        int top_zone = zone - HAND_GRENADES;
        int bottom_zone = zone + HAND_GRENADES;
        
        return in_between(pos, top_zone, bottom_zone);
    }
    
    private static bool in_between(double pos, int top, int bottom) {
        int ipos = (int) pos;
        
        return (ipos > top) && (ipos < bottom);
    }
    
    private static bool near_in_between(double pos, int top, int bottom) {
        int ipos = (int) pos;
        int top_zone = top - HAND_GRENADES;
        int bottom_zone = bottom + HAND_GRENADES;
        
        return (ipos > top_zone) && (ipos < bottom_zone);
    }
    
    public BoxLocation location(int x, int y) {
        bool near_width = near_in_between(x, left, right);
        bool near_height = near_in_between(y, top, bottom);
        
        if (in_zone(x, left) && near_height) {
            if (in_zone(y, top)) {
                return BoxLocation.TOP_LEFT;
            } else if (in_zone(y, bottom)) {
                return BoxLocation.BOTTOM_LEFT;
            } else {
                return BoxLocation.LEFT_SIDE;
            }
        } else if (in_zone(x, right) && near_height) {
            if (in_zone(y, top)) {
                return BoxLocation.TOP_RIGHT;
            } else if (in_zone(y, bottom)) {
                return BoxLocation.BOTTOM_RIGHT;
            } else {
                return BoxLocation.RIGHT_SIDE;
            }
        } else if (in_zone(y, top) && near_width) {
            // if left or right was in zone, already caught top left & top right
            return BoxLocation.TOP_SIDE;
        } else if (in_zone(y, bottom) && near_width) {
            // if left or right was in zone, already caught bottom left & bottom right
            return BoxLocation.BOTTOM_SIDE;
        } else if (in_between(x, left, right) && in_between(y, top, bottom)) {
            return BoxLocation.INSIDE;
        } else {
            return BoxLocation.OUTSIDE;
        }
    }
}

Dimensions get_scaled_dimensions(Dimensions original, int scale) {
    assert(scale > 0);

    int diffWidth = original.width - scale;
    int diffHeight = original.height - scale;

    Dimensions scaled = Dimensions();

    if (diffWidth == diffHeight) {
        // square image -- unlikely -- but this is the easy case
        scaled.width = scale;
        scaled.height = scale;
    } else if (diffWidth <= 0) {
        if (diffHeight <= 0) {
            // if both dimensions are less than the scaled size, return as-is
            return original;
        } 
        
        // height needs to be scaled down, so it determines the ratio
        double ratio = (double) scale / (double) original.height;
        scaled.width = (int) Math.round((double) original.width * ratio);
        scaled.height = scale;
    } else if (diffWidth > diffHeight) {
        // width is greater, so it's the determining factor
        // (this case is true even when diffHeight is negative)
        scaled.width = scale;
        double ratio = (double) scale / (double) original.width;
        scaled.height = (int) Math.round((double) original.height * ratio);
    } else {
        // height is the determining factor
        double ratio = (double) scale / (double) original.height;
        scaled.width = (int) Math.round((double) original.width * ratio);
        scaled.height = scale;
    }
    
    return scaled;
}

Dimensions get_scaled_dimensions_for_view(Dimensions original, Dimensions view) {
    Dimensions scaled = Dimensions();

    // TODO: Surely this can be done by examining dimensions to avoid double calculations.
    scaled.width = view.width;
    double ratio = (double) view.width / (double) original.width;
    scaled.height = (int) ((double) original.height * ratio);
    if (scaled.height > view.height) {
        scaled.height = view.height;
        ratio = (double) view.height / (double) original.height;
        scaled.width = (int) ((double) original.width * ratio);
    }

    assert(scaled.height <= view.height);
    assert(scaled.width <= view.width);
    
    return scaled;
}

Dimensions get_rotated_dimensions(Dimensions dim, Exif.Orientation orientation) {
    int width = dim.width;
    int height = dim.height;
    
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
            int swap = width;
            width = height;
            height = swap;
        } break;

        default: {
            error("Unknown orientation: %d", orientation);
        } break;
    }
    
    return Dimensions(width, height);
}

Gdk.Pixbuf scale_pixbuf(Gdk.Pixbuf pixbuf, int scale, Gdk.InterpType interp) {
    Dimensions original = Dimensions(pixbuf.get_width(), pixbuf.get_height());
    Dimensions scaled = get_scaled_dimensions(original, scale);
    if ((original.width == scaled.width) && (original.height == scaled.height))
        return pixbuf;

    return pixbuf.scale_simple(scaled.width, scaled.height, interp);
}

Gdk.Pixbuf rotate_to_exif(Gdk.Pixbuf pixbuf, Exif.Orientation orientation) {
    switch(orientation) {
        case Exif.Orientation.TOP_LEFT: {
            // fine just as it is
        } break;
        
        case Exif.Orientation.TOP_RIGHT: {
            pixbuf = pixbuf.flip(true);
        } break;
        
        case Exif.Orientation.BOTTOM_RIGHT: {
            pixbuf = pixbuf.rotate_simple(Gdk.PixbufRotation.UPSIDEDOWN);
        } break;
        
        case Exif.Orientation.BOTTOM_LEFT: {
            pixbuf = pixbuf.flip(false);
        } break;
        
        case Exif.Orientation.LEFT_TOP: {
            pixbuf = pixbuf.rotate_simple(Gdk.PixbufRotation.COUNTERCLOCKWISE);
            pixbuf = pixbuf.flip(false);
        } break;
        
        case Exif.Orientation.RIGHT_TOP: {
            pixbuf = pixbuf.rotate_simple(Gdk.PixbufRotation.CLOCKWISE);
        } break;
        
        case Exif.Orientation.RIGHT_BOTTOM: {
            pixbuf = pixbuf.rotate_simple(Gdk.PixbufRotation.CLOCKWISE);
            pixbuf = pixbuf.flip(false);
        } break;
        
        case Exif.Orientation.LEFT_BOTTOM: {
            pixbuf = pixbuf.rotate_simple(Gdk.PixbufRotation.COUNTERCLOCKWISE);
        } break;
        
        default: {
            error("Unknown orientation: %d", orientation);
        } break;
    }
    
    return pixbuf;
}

public Gdk.Rectangle scaled_rectangle(Dimensions orig, Dimensions scaled, Gdk.Rectangle rect) {
    double x_scale = (double) scaled.width / (double) orig.width;
    double y_scale = (double) scaled.height / (double) orig.height;
    
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

