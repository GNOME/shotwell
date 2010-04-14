/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

bool is_color_parsable(string spec) {
    Gdk.Color color;
    return Gdk.Color.parse(spec, out color);
}

Gdk.Color parse_color(string spec) {
    return fetch_color(spec);
}

Gdk.Color fetch_color(string spec, Gdk.Drawable? drawable = null) {
    Gdk.Color color;
    if (!Gdk.Color.parse(spec, out color))
        error("Can't parse color %s", spec);
    
    if (drawable == null) {
        Gtk.Window app = AppWindow.get_instance();
        if (app != null)
            drawable = app.window;
    }
    
    if (drawable != null) {
        Gdk.Colormap colormap = drawable.get_colormap();
        if (colormap == null)
            error("Can't get colormap for drawable");
        
        if (!colormap.alloc_color(color, false, true))
            error("Can't allocate color %s", spec);
    }
    
    return color;
}

private inline uint32 convert_color(uint16 component) {
    return (uint32) (component / 256);
}

uint32 convert_rgba(Gdk.Color c, uint8 alpha) {
    return (convert_color(c.red) << 24) | (convert_color(c.green) << 16) | (convert_color(c.blue) << 8) 
        | alpha;
}

private const int MIN_SCALED_WIDTH = 10;
private const int MIN_SCALED_HEIGHT = 10;

Gdk.Pixbuf scale_pixbuf(Gdk.Pixbuf pixbuf, int scale, Gdk.InterpType interp, bool scale_up) {
    Dimensions original = Dimensions.for_pixbuf(pixbuf);
    Dimensions scaled = original.get_scaled(scale, scale_up);
    if ((original.width == scaled.width) && (original.height == scaled.height))
        return pixbuf;
    
    // use sane minimums ... scale_simple will hang if this is too low
    scaled = scaled.with_min(MIN_SCALED_WIDTH, MIN_SCALED_HEIGHT);
    
    return pixbuf.scale_simple(scaled.width, scaled.height, interp);
}

Gdk.Pixbuf resize_pixbuf(Gdk.Pixbuf pixbuf, Dimensions resized, Gdk.InterpType interp) {
    Dimensions original = Dimensions.for_pixbuf(pixbuf);
    if (original.width == resized.width && original.height == resized.height)
        return pixbuf;
    
    // use sane minimums ... scale_simple will hang if this is too low
    resized = resized.with_min(MIN_SCALED_WIDTH, MIN_SCALED_HEIGHT);
    
    return pixbuf.scale_simple(resized.width, resized.height, interp);
}

private const double DEGREE = Math.PI / 180.0;

void draw_rounded_corners_pixbuf(Gdk.Drawable drawable, Gdk.Pixbuf pixbuf, Gdk.Point origin, 
    double radius_proportion) {
    // establish a reasonable range
    radius_proportion = radius_proportion.clamp(2.0, 20.0);
    
    Dimensions dim = Dimensions.for_pixbuf(pixbuf);
    
    double left = origin.x;
    double top = origin.y;
    double right = origin.x + dim.width;
    double bottom = origin.y + dim.height;
    
    // the radius of the corners is proportional to the distance of the minor axis
    double radius = ((double) dim.minor_axis()) / radius_proportion;
    
    // create context and clipping region, starting from the top right arc and working around
    // clockwise
    Cairo.Context cx = Gdk.cairo_create(drawable);
    cx.arc(right - radius, top + radius, radius, -90 * DEGREE, 0 * DEGREE);
    cx.arc(right - radius, bottom - radius, radius, 0 * DEGREE, 90 * DEGREE);
    cx.arc(left + radius, bottom - radius, radius, 90 * DEGREE, 180 * DEGREE);
    cx.arc(left + radius, top + radius, radius, 180 * DEGREE, 270 * DEGREE);
    cx.clip();
    
    // load pixbuf into the clipped context
    Gdk.cairo_set_source_pixbuf(cx, pixbuf, origin.x, origin.y);
    
    cx.paint();
}

inline uchar shift_color_byte(int b, int shift) {
    return (uchar) (b + shift).clamp(0, 255);
}

public void shift_colors(Gdk.Pixbuf pixbuf, int red, int green, int blue, int alpha) {
    assert(red >= -255 && red <= 255);
    assert(green >= -255 && green <= 255);
    assert(blue >= -255 && blue <= 255);
    assert(alpha >= -255 && alpha <= 255);
    
    int width = pixbuf.get_width();
    int height = pixbuf.get_height();
    int rowstride = pixbuf.get_rowstride();
    int channels = pixbuf.get_n_channels();
    uchar *pixels = pixbuf.get_pixels();

    assert(channels >= 3);
    assert(pixbuf.get_colorspace() == Gdk.Colorspace.RGB);
    assert(pixbuf.get_bits_per_sample() == 8);

    for (int y = 0; y < height; y++) {
        int y_offset = y * rowstride;
        
        for (int x = 0; x < width; x++) {
            int offset = y_offset + (x * channels);
            
            if (red != 0)
                pixels[offset] = shift_color_byte(pixels[offset], red);
            
            if (green != 0)
                pixels[offset + 1] = shift_color_byte(pixels[offset + 1], green);
            
            if (blue != 0)
                pixels[offset + 2] = shift_color_byte(pixels[offset + 2], blue);
            
            if (alpha != 0 && channels >= 4)
                pixels[offset + 3] = shift_color_byte(pixels[offset + 3], alpha);
        }
    }
}

bool coord_in_rectangle(int x, int y, Gdk.Rectangle rect) {
    return (x >= rect.x && x < (rect.x + rect.width) && y >= rect.y && y <= (rect.y + rect.height));
}

Gdk.Point coord_scaled_in_space(int x, int y, Dimensions original, Dimensions scaled) {
    double x_scale, y_scale;
    original.get_scale_ratios(scaled, out x_scale, out y_scale);
    
    Gdk.Point point = Gdk.Point();
    point.x = (int) Math.round(x * x_scale);
    point.y = (int) Math.round(y * y_scale);
    
    // watch for rounding errors
    if (point.x >= scaled.width)
        point.x = scaled.width - 1;
    
    if (point.y >= scaled.height)
        point.y = scaled.height - 1;
    
    return point;
}

public bool rectangles_equal(Gdk.Rectangle a, Gdk.Rectangle b) {
    return (a.x == b.x) && (a.y == b.y) && (a.width == b.width) && (a.height == b.height);
}

public string rectangle_to_string(Gdk.Rectangle rect) {
    return "%d,%d %dx%d".printf(rect.x, rect.y, rect.width, rect.height);
}

public Gdk.Rectangle clamp_rectangle(Gdk.Rectangle original, Dimensions max) {
    Gdk.Rectangle rect = Gdk.Rectangle();
    rect.x = original.x.clamp(0, max.width);
    rect.y = original.y.clamp(0, max.height);
    rect.width = original.width.clamp(0, max.width);
    rect.height = original.height.clamp(0, max.height);
    
    return rect;
}

// Can only scale a radius when the scale is proportional; returns -1 if not.  Only two points of
// precision are considered here.
int radius_scaled_in_space(int radius, Dimensions original, Dimensions scaled) {
    double x_scale, y_scale;
    original.get_scale_ratios(scaled, out x_scale, out y_scale);
    
    // using floor() or round() both present problems, since the two values could straddle any FP
    // boundary ... instead, look for a reasonable delta
    if (Math.fabs(x_scale - y_scale) > 1.0)
        return -1;
    
    return (int) Math.round(radius * x_scale);
}

#if !NO_SET_BACKGROUND
public void set_desktop_background(TransformablePhoto photo) {
    File save_as = AppDirs.get_data_subdir("wallpaper").get_child("wallpaper.jpg");

    if (Config.get_instance().get_background() == save_as.get_path())
        save_as = AppDirs.get_data_subdir("wallpaper").get_child("wallpaper_alt.jpg");

    if (save_as == null)
        return;
    
    try {
        photo.export(save_as, Scaling.for_original(), Jpeg.Quality.MAXIMUM);
    } catch (Error err) {
        AppWindow.error_message(_("Unable to export background to %s: %s").printf(save_as.get_path(), err.message));
        return;
    }

    Config.get_instance().set_background(save_as.get_path());

    GLib.FileUtils.chmod(save_as.get_parse_name(), 0644);
}
#endif
