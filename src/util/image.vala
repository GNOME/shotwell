/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

Gdk.RGBA parse_color(string spec) {
    return fetch_color(spec);
}

Gdk.RGBA fetch_color(string spec) {
    Gdk.RGBA rgba = Gdk.RGBA();
    if (!rgba.parse(spec))
        error("Can't parse color %s", spec);
    
    return rgba;
}

void set_source_color_from_string(Cairo.Context ctx, string spec) {
    Gdk.RGBA rgba = fetch_color(spec);
    ctx.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha);
}

private const int MIN_SCALED_WIDTH = 10;
private const int MIN_SCALED_HEIGHT = 10;

Gdk.Pixbuf get_placeholder_pixbuf () {
    // Create empty pixbuf.
    Gdk.Pixbuf? pixbuf = null;

    try {
        pixbuf = new Gdk.Pixbuf.from_resource("/org/gnome/Shotwell/icons/image-missing.png");
    } catch (Error err) {
        warning("Could not load fall-back icon: %s", err.message);
    }

    return pixbuf;
}

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

void draw_rounded_corners_filled(Gtk.Snapshot snapshot, Gdk.RGBA color, Dimensions dim, Gdk.Point origin,
    int border_width, double radius_proportion) {        

    radius_proportion = radius_proportion.clamp(2.0, 100.0);

    // the radius of the corners is proportional to the distance of the minor axis
    float radius = ((float) dim.minor_axis()) / (float)radius_proportion;

    var border_rect = Graphene.Rect();
    border_rect.init(origin.x, origin.y,
        dim.width,
        dim.height);
    var cursor_rect = Gsk.RoundedRect();
    cursor_rect.init_from_rect(border_rect, radius);
    float border[4] = {border_width, border_width, border_width, border_width};
    Gdk.RGBA c[4] = {(!)color, (!)color, (!)color, (!)color};
    snapshot.append_border(cursor_rect, border, c);
}

void context_rounded_corners(Gtk.Snapshot snapshot, Dimensions dim, Gdk.Point origin,
    double radius_proportion) {
    radius_proportion = radius_proportion.clamp(2.0, 100.0);

    // the radius of the corners is proportional to the distance of the minor axis
    float radius = ((float) dim.minor_axis()) / (float)radius_proportion;

    var border_rect = Graphene.Rect();
    border_rect.init(origin.x, origin.y,
        dim.width,
        dim.height);
    var cursor_rect = Gsk.RoundedRect();
    cursor_rect.init_from_rect(border_rect, radius);
    snapshot.push_rounded_clip(cursor_rect);
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

Gdk.Pixbuf apply_alpha_channel(Gdk.Pixbuf source, bool strip = false) {
    var dest = new Gdk.Pixbuf (source.colorspace, false, source.bits_per_sample, source.width, source.height);
    uchar *sp = source.pixels;
    uchar *dp = dest.pixels;

    for (int j = 0; j < source.height; j++) {
        uchar *s = sp;
        uchar *d = dp;
        uchar *end = s + 4 * source.width;
        while (s < end) {
            if (strip) {
                d[0] = s[0];
                d[1] = s[1];
                d[2] = s[2]; 
            } else {
                double alpha = s[3] / 255.0;
                d[0] = (uchar)Math.round((255.0 * (1.0 - alpha)) + (s[0] * alpha));
                d[1] = (uchar)Math.round((255.0 * (1.0 - alpha)) + (s[1] * alpha));
                d[2] = (uchar)Math.round((255.0 * (1.0 - alpha)) + (s[2] * alpha));
            }
            s += 4;
            d += 3;
        }

        sp += source.rowstride;
        dp += dest.rowstride;
    }

    return dest;
}

// Converts XRGB/ARGB (Cairo)-formatted pixels to RGBA (GDK).
void argb2rgba(Gdk.Pixbuf pixbuf) {
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

/**
 * Finds the size of the smallest axially-aligned rectangle that could contain
 * a rectangle src_width by src_height, rotated by angle.
 *
 * @param src_width The width of the incoming rectangle.
 * @param src_height The height of the incoming rectangle.
 * @param angle The amount to rotate by, given in degrees.
 * @param dest_width The width of the computed rectangle.
 * @param dest_height The height of the computed rectangle.
 */ 
void compute_arb_rotated_size(double src_width, double src_height, double angle,
    out double dest_width, out double dest_height) {
    
    angle = Math.fabs(degrees_to_radians(angle));
    assert(angle <= Math.PI_2);
    dest_width = src_width * Math.cos(angle) + src_height * Math.sin(angle);
    dest_height = src_height * Math.cos(angle) + src_width * Math.sin(angle);
}

/**
 * @brief Rotates a pixbuf to an arbitrary angle, given in degrees, and returns the rotated pixbuf.
 *
 * @param source_pixbuf The source image that needs to be angled.
 * @param angle The angle the source image should be rotated by.
 */ 
Gdk.Pixbuf rotate_arb(Gdk.Pixbuf source_pixbuf, double angle) {
    // if the straightening angle has been reset
    // or was never set in the first place, nothing
    // needs to be done to the source image.
    if (angle == 0.0) {
        return source_pixbuf;
    }

    // Compute how much the corners of the source image will
    // move by to determine how big the dest pixbuf should be.

    double x_tmp, y_tmp;
    compute_arb_rotated_size(source_pixbuf.width, source_pixbuf.height, angle,
                             out x_tmp, out y_tmp);
                             
    Gdk.Pixbuf dest_pixbuf = new Gdk.Pixbuf(
            Gdk.Colorspace.RGB, true, 8, (int) Math.round(x_tmp), (int) Math.round(y_tmp));

    Cairo.ImageSurface surface = new Cairo.ImageSurface.for_data(
        (uchar []) dest_pixbuf.pixels,
        source_pixbuf.has_alpha ? Cairo.Format.ARGB32 : Cairo.Format.RGB24,
        dest_pixbuf.width, dest_pixbuf.height, dest_pixbuf.rowstride);
            
    Cairo.Context context = new Cairo.Context(surface);
    
    context.set_source_rgb(0, 0, 0);
    context.rectangle(0, 0, dest_pixbuf.width, dest_pixbuf.height);
    context.fill();
    
    context.translate(dest_pixbuf.width / 2, dest_pixbuf.height / 2);
    context.rotate(degrees_to_radians(angle));
    context.translate(- source_pixbuf.width / 2, - source_pixbuf.height / 2);
    
    Gdk.cairo_set_source_pixbuf(context, source_pixbuf, 0, 0);
    context.get_source().set_filter(Cairo.Filter.BEST);
    context.paint();
    
    // prepare the newly-drawn image for use by
    // the rest of the pipeline.
    argb2rgba(dest_pixbuf);
    return apply_alpha_channel(dest_pixbuf, true);
}

/**
 * @brief Rotates a point around the upper left corner of an image to an arbitrary angle,
 * given in degrees, and returns the rotated point, translated such that it, along with its attendant
 * image, are in positive x, positive y.
 *
 * @note May be subject to slight inaccuracy as Gdk points' coordinates may only be in whole pixels,
 * so the fractional component is lost.
 *
 * @param source_point The point to be rotated and scaled.
 * @param img_w The width of the source image (unrotated).
 * @param img_h The height of the source image (unrotated).
 * @param angle The angle the source image is to be rotated by to straighten it.
 */
Gdk.Point rotate_point_arb(Gdk.Point source_point, int img_w, int img_h, double angle,
                           bool invert = false) {
    // angle of 0 degrees or angle was never set?
    if (angle == 0.0) {
        // nothing needs to be done.
        return source_point;
    }

    double dest_width;
    double dest_height;
    compute_arb_rotated_size(img_w, img_h, angle, out dest_width, out dest_height);
    
    Cairo.Matrix matrix = Cairo.Matrix.identity();
    matrix.translate(dest_width / 2, dest_height / 2);
    matrix.rotate(degrees_to_radians(angle));
    matrix.translate(- img_w / 2, - img_h / 2);
    if (invert)
        assert(matrix.invert() == Cairo.Status.SUCCESS);
    
    double dest_x = source_point.x; 
    double dest_y = source_point.y;
    matrix.transform_point(ref dest_x, ref dest_y);
    
    return { (int) dest_x, (int) dest_y };
}
    
/**
 * @brief <u>De</u>rotates a point around the upper left corner of an image from an arbitrary angle,
 * given in degrees, and returns the de-rotated point, taking into account any translation necessary
 * to make sure all of the rotated image stays in positive x, positive y.
 *
 * @note May be subject to slight inaccuracy as Gdk points' coordinates may only be in whole pixels,
 * so the fractional component is lost.
 *
 * @param source_point The point to be de-rotated.
 * @param img_w The width of the source image (unrotated).
 * @param img_h The height of the source image (unrotated).
 * @param angle The angle the source image is to be rotated by to straighten it.
 */
Gdk.Point derotate_point_arb(Gdk.Point source_point, int img_w, int img_h, double angle) {
    return rotate_point_arb(source_point, img_w, img_h, angle, true);
}

private static Cairo.Surface background_surface = null;

private Cairo.Surface get_background_surface() {
    if (background_surface == null) {
        string color_a;
        string color_b;
        var config = Config.Facade.get_instance();

        var type = config.get_transparent_background_type();
        switch (type) {
            case "checkered":
                color_a = "#808080";
                color_b = "#ccc";
                break;
            case "solid":
                color_a = color_b = config.get_transparent_background_color();
                break;
            default:
                color_a = color_b = "#000";
                break;
        }

        background_surface = new Cairo.ImageSurface(Cairo.Format.RGB24, 16, 16);
        var ctx = new Cairo.Context(background_surface);
        ctx.set_operator(Cairo.Operator.SOURCE);
        set_source_color_from_string(ctx, color_a);
        ctx.rectangle(0,0,8,8);
        ctx.rectangle(8,8,8,8);
        ctx.fill();
        set_source_color_from_string(ctx, color_b);
        ctx.rectangle(0,8,8,8);
        ctx.rectangle(8,0,8,8);
        ctx.fill();
    }

    return background_surface;
}

public void invalidate_transparent_background() {
    background_surface = null;
}

public void paint_pixmap_with_background (Cairo.Context ctx, Gdk.Pixbuf pixbuf, int x, int y) {
    if (pixbuf.get_has_alpha()) {
        ctx.set_source_surface(get_background_surface(), 0, 0);
        ctx.get_source().set_extend(Cairo.Extend.REPEAT);
        ctx.rectangle(x, y, pixbuf.width, pixbuf.height);
        ctx.fill();
    }

    Gdk.cairo_set_source_pixbuf(ctx, pixbuf, x, y);
    ctx.rectangle(x, y, pixbuf.width , pixbuf.height);
    ctx.fill();
}

// Force an axially-aligned box to be inside a rotated rectangle.
Box clamp_inside_rotated_image(Box src, int img_w, int img_h, double angle_deg,
    bool preserve_geom) {

    Gdk.Point top_left = derotate_point_arb({src.left, src.top}, img_w, img_h, angle_deg);
    Gdk.Point top_right = derotate_point_arb({src.right, src.top}, img_w, img_h, angle_deg);
    Gdk.Point bottom_left = derotate_point_arb({src.left, src.bottom}, img_w, img_h, angle_deg);
    Gdk.Point bottom_right = derotate_point_arb({src.right, src.bottom}, img_w, img_h, angle_deg);
    
    double angle = degrees_to_radians(angle_deg);
    int top_offset = 0, bottom_offset = 0, left_offset = 0, right_offset = 0;
    
    int top = int.min(top_left.y, top_right.y);
    if (top < 0)
        top_offset = (int) ((0 - top) * Math.cos(angle));
        
    int bottom = int.max(bottom_left.y, bottom_right.y);
    if (bottom > img_h)
        bottom_offset = (int) ((img_h - bottom) * Math.cos(angle));
        
    int left = int.min(top_left.x, bottom_left.x);
    if (left < 0)
        left_offset = (int) ((0 - left) * Math.cos(angle));
        
    int right = int.max(top_right.x, bottom_right.x);
    if (right > img_w)
        right_offset = (int) ((img_w - right) * Math.cos(angle));

    return preserve_geom ? src.get_offset(left_offset + right_offset, top_offset + bottom_offset)
                         : Box(src.left + left_offset, src.top + top_offset,
                               src.right + right_offset, src.bottom + bottom_offset);
}

double degrees_to_radians(double theta) {
    return (theta * (GLib.Math.PI / 180.0));
}
