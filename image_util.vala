
Gdk.Color parse_color(string color) {
    Gdk.Color c;
    if (!Gdk.Color.parse(color, out c))
        error("can't parse color %s", color);

    return c;
}

Gdk.Pixbuf scale_pixbuf(Gdk.Pixbuf pixbuf, int scale, Gdk.InterpType interp) {
    Dimensions original = Dimensions(pixbuf.get_width(), pixbuf.get_height());
    Dimensions scaled = original.get_scaled(scale);
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

