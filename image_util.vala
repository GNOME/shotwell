
static const bool DEBUG = false;

Gdk.Pixbuf scale_pixbuf(File file, Gdk.Pixbuf pixbuf, int scale, Gdk.InterpType interp) {
    int width = pixbuf.get_width();
    int height = pixbuf.get_height();

    int diffWidth = width - scale;
    int diffHeight = height - scale;
    
    int newWidth = 0;
    int newHeight = 0;

    if (diffWidth == diffHeight) {
        // square image -- unlikely -- but this is the easy case
        newWidth = scale;
        newHeight = scale;
    } else if (diffWidth <= 0) {
        if (diffHeight <= 0) {
            // if both dimensions are less than the scaled size, return image as-is
            return pixbuf;
        } 
        
        // height needs to be scaled down, so it determines the ratio
        double ratio = (double) scale / (double) height;
        newWidth = (int) Math.round((double) width * ratio);
        newHeight = scale;
    } else if (diffHeight <= 0) {
        // already know that width is greater than scale, so width determines the ratio
        newWidth = scale;
        double ratio = (double) scale / (double) width;
        newHeight = (int) Math.round((double) height * ratio);
    } else if (diffWidth > diffHeight) {
        // width is greater, so it's the determining factor
        newWidth = scale;
        double ratio = (double) scale / (double) width;
        newHeight = (int) Math.round((double) height * ratio);
    } else {
        // height is the determining factor
        double ratio = (double) scale / (double) height;
        newWidth = (int) Math.round((double) width * ratio);
        newHeight = scale;
    }

    if (DEBUG)
        message("%s %d x %d -> %d x %d", file.get_path(), width, height, newWidth, newHeight);
    
    return pixbuf.scale_simple(newWidth, newHeight, interp);
}

