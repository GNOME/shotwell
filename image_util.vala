
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
}

Dimensions get_scaled_dimensions(Dimensions original, int scale) {
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

Gdk.Pixbuf scale_pixbuf(Gdk.Pixbuf pixbuf, int scale, Gdk.InterpType interp) {
    Dimensions original = Dimensions(pixbuf.get_width(), pixbuf.get_height());
    Dimensions scaled = get_scaled_dimensions(original, scale);
    if ((original.width == scaled.width) && (original.height == scaled.height))
        return pixbuf;

    return pixbuf.scale_simple(scaled.width, scaled.height, interp);
}

