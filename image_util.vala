
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
