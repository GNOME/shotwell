/* Copyright 2009-2011 Yorba Foundation
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

void set_source_color_with_alpha(Cairo.Context ctx, Gdk.Color color, double alpha) {
    ctx.set_source_rgba((double) color.red / 65535.0, (double) color.green / 65535.0,
        (double) color.blue / 65535.0, alpha);
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

void draw_rounded_corners_filled(Cairo.Context ctx, Dimensions dim, Gdk.Point origin,
    double radius_proportion) {
    context_rounded_corners(ctx, dim, origin, radius_proportion);
    ctx.paint();
}

void context_rounded_corners(Cairo.Context cx, Dimensions dim, Gdk.Point origin, 
    double radius_proportion) {
    // establish a reasonable range
    radius_proportion = radius_proportion.clamp(2.0, 100.0);
    
    double left = origin.x;
    double top = origin.y;
    double right = origin.x + dim.width;
    double bottom = origin.y + dim.height;
    
    // the radius of the corners is proportional to the distance of the minor axis
    double radius = ((double) dim.minor_axis()) / radius_proportion;
    
    // create context and clipping region, starting from the top right arc and working around
    // clockwise
    cx.move_to(left, top);
    cx.arc(right - radius, top + radius, radius, -90 * DEGREE, 0 * DEGREE);
    cx.arc(right - radius, bottom - radius, radius, 0 * DEGREE, 90 * DEGREE);
    cx.arc(left + radius, bottom - radius, radius, 90 * DEGREE, 180 * DEGREE);
    cx.arc(left + radius, top + radius, radius, 180 * DEGREE, 270 * DEGREE);
    cx.clip();
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

public void dim_pixbuf(Gdk.Pixbuf pixbuf) {
    PixelTransformer transformer = new PixelTransformer();
    SaturationTransformation sat = new SaturationTransformation(SaturationTransformation.MIN_PARAMETER);
    transformer.attach_transformation(sat);
    transformer.transform_pixbuf(pixbuf);
    shift_colors(pixbuf, 0, 0, 0, -100);
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
	
public Gdk.Point scale_point(Gdk.Point p, double factor) {
    Gdk.Point result = {0};
    result.x = (int) (factor * p.x + 0.5);
    result.y = (int) (factor * p.y + 0.5);

    return result;
}

public Gdk.Point add_points(Gdk.Point p1, Gdk.Point p2) {
    Gdk.Point result = {0};
    result.x = p1.x + p2.x;
    result.y = p1.y + p2.y;

    return result;
}

public Gdk.Point subtract_points(Gdk.Point p1, Gdk.Point p2) {
    Gdk.Point result = {0};
    result.x = p1.x - p2.x;
    result.y = p1.y - p2.y;

    return result;
}

// Converts XRGB/ARGB (Cairo)-formatted pixels to RGBA (GDK).
void fix_cairo_pixbuf(Gdk.Pixbuf pixbuf) {
    uchar *gdk_pixels = pixbuf.pixels;
    for (int j = 0 ; j < pixbuf.height; ++j) {
        uchar *p = gdk_pixels;
        uchar *end = p + 4 * pixbuf.width;

        while (p < end) {
            uchar tmp = p[0];
#if G_BYTE_ORDER == G_LITTLE_ENDIAN
            p[0] = p[2];
            p[2] = tmp;
#else	  
            p[0] = p[1];
            p[1] = p[2];
            p[2] = p[3];
            p[3] = tmp;
#endif
            p += 4;
        }

      gdk_pixels += pixbuf.rowstride;
    }
}

// Rotates a pixbuf to an arbitrary angle, given in degrees, and returns the rotated 
// pixbuf. The caller is responsible for destroying the returned pixbuf after use.
Gdk.Pixbuf rotate_arb(Gdk.Pixbuf source_pixbuf, double angle) {
    angle = degrees_to_radians(angle);
    
    double x_min = 0.0, y_min = 0.0, x_max = 0.0, y_max = 0.0;
    
    double x_tmp, y_tmp;
    
    // Compute how much the corners of the source image will
    // move by to determine how big the dest pixbuf should be.

    // Lower left corner.
    x_tmp = -(Math.sin(angle) * source_pixbuf.height);
    y_tmp = (Math.cos(angle) * source_pixbuf.height);
    
    if(x_tmp < x_min) x_min = x_tmp;
    if(x_tmp > x_max) x_max = x_tmp;

    if(y_tmp < y_min) y_min = y_tmp;
    if(y_tmp > y_max) y_max = y_tmp;
    
    // Lower right corner.
    x_tmp = (Math.cos(angle) * source_pixbuf.width) - (Math.sin(angle) * source_pixbuf.height);
    y_tmp = (Math.sin(angle) * source_pixbuf.width) + (Math.cos(angle) * source_pixbuf.height);
    
    if(x_tmp < x_min) x_min = x_tmp;
    if(x_tmp > x_max) x_max = x_tmp;

    if(y_tmp < y_min) y_min = y_tmp;
    if(y_tmp > y_max) y_max = y_tmp;
    
    // Upper right corner.
    x_tmp = (Math.cos(angle) * source_pixbuf.width); 
    y_tmp = (Math.sin(angle) * source_pixbuf.width); 
    
    if(x_tmp < x_min) x_min = x_tmp;
    if(x_tmp > x_max) x_max = x_tmp;

    if(y_tmp < y_min) y_min = y_tmp;
    if(y_tmp > y_max) y_max = y_tmp;
    
    Gdk.Pixbuf dest_pixbuf = new Gdk.Pixbuf(Gdk.Colorspace.RGB, true, 8, (int) Math.round(x_max - x_min), (int) Math.round(y_max - y_min));

    Cairo.ImageSurface surface;
    
    if(source_pixbuf.has_alpha) {
         surface = new Cairo.ImageSurface.for_data(
            (uchar []) dest_pixbuf.pixels, Cairo.Format.ARGB32,
            dest_pixbuf.width, dest_pixbuf.height, dest_pixbuf.rowstride);
    } else {
         surface = new Cairo.ImageSurface.for_data(
            (uchar []) dest_pixbuf.pixels, Cairo.Format.RGB24,
            dest_pixbuf.width, dest_pixbuf.height, dest_pixbuf.rowstride);
    }
            
    Cairo.Context context = new Cairo.Context(surface);
    
    context.set_source_rgb(0, 0, 0);
    context.rectangle(0, 0, dest_pixbuf.width, dest_pixbuf.height);
    context.fill();
    
    context.translate(-x_min, -y_min);
    context.rotate(angle);
    Gdk.cairo_set_source_pixbuf(context, source_pixbuf, 0, 0);
    context.get_source().set_filter(Cairo.Filter.BEST);
    context.paint();

    fix_cairo_pixbuf(dest_pixbuf);

    return dest_pixbuf;
}
