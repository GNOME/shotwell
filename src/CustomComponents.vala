/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

extern void qsort(void *p, size_t num, size_t size, GLib.CompareFunc func);

public class ThemeLoader {
    private struct LightweightColor {
        public uchar red;
        public uchar green;
        public uchar blue;
        
        public LightweightColor() {
            red = green = blue = 0;
        }
    }

    private const int NUM_SUPPORTED_INTENSITIES = 6;
    private const int THEME_OUTLINE_COLOR = 0;
    private const int THEME_BEVEL_DARKER_COLOR = 1;
    private const int THEME_BEVEL_DARK_COLOR = 2;
    private const int THEME_BASE_COLOR = 3;
    private const int THEME_BEVEL_LIGHT_COLOR = 4;
    private const int THEME_BEVEL_LIGHTER_COLOR = 5;

    private static LightweightColor[] theme_colors = null;

    private static void populate_theme_params() {
        if (theme_colors != null)
            return;
        
        theme_colors = new LightweightColor[NUM_SUPPORTED_INTENSITIES];

        Gtk.Settings settings = Gtk.Settings.get_default();
        HashTable<string, Gdk.Color?> color_table = settings.color_hash;
        Gdk.Color? base_color = color_table.lookup("bg_color");
        if (base_color == null && !Gdk.Color.parse("#fff", out base_color))
            error("can't parse color");

        RGBAnalyticPixel base_color_analytic_rgb =
            RGBAnalyticPixel.from_quantized_components(base_color.red >> 8,
            base_color.green >> 8, base_color.blue >> 8);
        HSVAnalyticPixel base_color_analytic_hsv =
            HSVAnalyticPixel.from_rgb(base_color_analytic_rgb);

        HSVAnalyticPixel bevel_light_analytic_hsv = base_color_analytic_hsv;
        bevel_light_analytic_hsv.light_value *= 1.15f;
        bevel_light_analytic_hsv.light_value =
            bevel_light_analytic_hsv.light_value.clamp(0.0f, 1.0f);
        
        HSVAnalyticPixel bevel_lighter_analytic_hsv = bevel_light_analytic_hsv;
        bevel_lighter_analytic_hsv.light_value *= 1.15f;
        bevel_lighter_analytic_hsv.light_value =
            bevel_lighter_analytic_hsv.light_value.clamp(0.0f, 1.0f);

        HSVAnalyticPixel bevel_dark_analytic_hsv = base_color_analytic_hsv;
        bevel_dark_analytic_hsv.light_value *= 0.85f;
        bevel_dark_analytic_hsv.light_value =
            bevel_dark_analytic_hsv.light_value.clamp(0.0f, 1.0f);

        HSVAnalyticPixel bevel_darker_analytic_hsv = bevel_dark_analytic_hsv;
        bevel_darker_analytic_hsv.light_value *= 0.85f;
        bevel_darker_analytic_hsv.light_value =
            bevel_darker_analytic_hsv.light_value.clamp(0.0f, 1.0f);

        HSVAnalyticPixel outline_analytic_hsv = bevel_darker_analytic_hsv;
        outline_analytic_hsv.light_value *= 0.66f;
        outline_analytic_hsv.light_value =
            outline_analytic_hsv.light_value.clamp(0.0f, 1.0f);

        RGBAnalyticPixel outline_analytic_rgb = outline_analytic_hsv.to_rgb();
        theme_colors[THEME_OUTLINE_COLOR] =
            populate_one_theme_param(outline_analytic_rgb);

        RGBAnalyticPixel bevel_darker_analytic_rgb = bevel_darker_analytic_hsv.to_rgb();
        theme_colors[THEME_BEVEL_DARKER_COLOR] =
            populate_one_theme_param(bevel_darker_analytic_rgb);
            
        RGBAnalyticPixel bevel_dark_analytic_rgb = bevel_dark_analytic_hsv.to_rgb();
        theme_colors[THEME_BEVEL_DARK_COLOR] =
            populate_one_theme_param(bevel_dark_analytic_rgb);

        theme_colors[THEME_BASE_COLOR] =
            populate_one_theme_param(base_color_analytic_rgb);

        RGBAnalyticPixel bevel_light_analytic_rgb = bevel_light_analytic_hsv.to_rgb();
        theme_colors[THEME_BEVEL_LIGHT_COLOR] =
            populate_one_theme_param(bevel_light_analytic_rgb);
        
        RGBAnalyticPixel bevel_lighter_analytic_rgb = bevel_light_analytic_hsv.to_rgb();
        theme_colors[THEME_BEVEL_LIGHTER_COLOR] =
            populate_one_theme_param(bevel_lighter_analytic_rgb);
    }
    
    private static LightweightColor populate_one_theme_param(RGBAnalyticPixel from) {
        LightweightColor into = LightweightColor();

        into.red = (uchar)(from.red * 255.0f);
        into.green = (uchar)(from.green * 255.0f);
        into.blue = (uchar)(from.blue * 255.0f);
        
        return into;
    }

    public static Gdk.Pixbuf load_icon(string source_basename) {
        populate_theme_params();

        Gdk.Pixbuf loaded_pixbuf = Resources.get_icon(source_basename, 0).copy();

        /* Sweep through the icon image data loaded from disk and determine how many
           unique colors are in it. We do this with the aid of a HashSet. */
        Gee.HashSet<RGBAnalyticPixel?> colors =
            new Gee.HashSet<RGBAnalyticPixel?>(rgb_pixel_hash_func,
            rgb_pixel_equal_func);
        unowned uchar[] pixel_data = loaded_pixbuf.get_pixels();
        for (int j = 0; j < loaded_pixbuf.height; j++) {
            for (int i = 0; i < loaded_pixbuf.width; i++) {
                int pixel_index = (j * loaded_pixbuf.rowstride) + (i * loaded_pixbuf.n_channels);

                RGBAnalyticPixel pixel_color = RGBAnalyticPixel.from_quantized_components(
                    pixel_data[pixel_index], pixel_data[pixel_index + 1],
                    pixel_data[pixel_index + 2]);
                colors.add(pixel_color);
            }
        }
        
        /* If the image data loaded from disk didn't contain NUM_SUPPORTED_INTENSITIES
           colors, then we can't unambiguously map the colors in the loaded image data
           to theme colors on the user's system, so propagate an error */
        if (colors.size != NUM_SUPPORTED_INTENSITIES)
            error("ThemeLoader: load_icon: pixbuf does not contain the correct number " +
                "of unique colors");
        
        /* sort the colors in the loaded image data in order of increasing intensity; this
           means that we have to convert the loaded colors from RGB to HSV format */
        HSVAnalyticPixel[] hsv_pixels = new HSVAnalyticPixel[6];
        int pixel_ticker = 0;
        foreach (RGBAnalyticPixel rgb_pixel in colors)
            hsv_pixels[pixel_ticker++] = HSVAnalyticPixel.from_rgb(rgb_pixel);
        qsort(hsv_pixels, hsv_pixels.length, sizeof(HSVAnalyticPixel), hsv_pixel_compare_func);

        /* step through each pixel in the image data loaded from disk and map its color
           to one of the user's theme colors */
        for (int j = 0; j < loaded_pixbuf.height; j++) {
            for (int i = 0; i < loaded_pixbuf.width; i++) {
                int pixel_index = (j * loaded_pixbuf.rowstride) + (i * loaded_pixbuf.n_channels);
                RGBAnalyticPixel pixel_color = RGBAnalyticPixel.from_quantized_components(
                    pixel_data[pixel_index], pixel_data[pixel_index + 1],
                    pixel_data[pixel_index + 2]);
                HSVAnalyticPixel pixel_color_hsv = HSVAnalyticPixel.from_rgb(pixel_color);
                int this_intensity = 0;
                for (int k = 0; k < NUM_SUPPORTED_INTENSITIES; k++) {
                    if (hsv_pixels[k].light_value == pixel_color_hsv.light_value) {
                        this_intensity = k;
                        break;
                    }
                }
                pixel_data[pixel_index] = theme_colors[this_intensity].red;
                pixel_data[pixel_index + 1] = theme_colors[this_intensity].green;
                pixel_data[pixel_index + 2] = theme_colors[this_intensity].blue;
            }
        }

        return loaded_pixbuf;
    }
    
    private static int hsv_pixel_compare_func(void* pixval1, void* pixval2) {
        HSVAnalyticPixel pixel_val_1 = * ((HSVAnalyticPixel*) pixval1);
        HSVAnalyticPixel pixel_val_2 = * ((HSVAnalyticPixel*) pixval2);
        
        return (int) (255.0f * (pixel_val_1.light_value - pixel_val_2.light_value));
    }
    
    private static bool rgb_pixel_equal_func(RGBAnalyticPixel? p1, RGBAnalyticPixel? p2) {
        return (p1.equals(p2));
    }

    private static uint rgb_pixel_hash_func(RGBAnalyticPixel? pixel_val) {        
        return pixel_val.hash_code();
    }
}

public class RGBHistogramManipulator : Gtk.DrawingArea {
    private enum LocationCode { LEFT_NUB, RIGHT_NUB, LEFT_TROUGH, RIGHT_TROUGH,
        INSENSITIVE_AREA }
    private const int NUB_SIZE = 13;
    private const int NUB_HALF_WIDTH = NUB_SIZE / 2;
    private const int NUB_V_NUDGE = 4;
    private const int TROUGH_WIDTH = 256 + (2 * NUB_HALF_WIDTH);
    private const int TROUGH_HEIGHT = 4;
    private const int TROUGH_BOTTOM_OFFSET = 1;
    private const int CONTROL_WIDTH = TROUGH_WIDTH + 2;
    private const int CONTROL_HEIGHT = 118;
    private const int NUB_V_POSITION = CONTROL_HEIGHT - TROUGH_HEIGHT - TROUGH_BOTTOM_OFFSET
        - (NUB_SIZE - TROUGH_HEIGHT) / 2 - NUB_V_NUDGE - 2;
    private int left_nub_max = 255 - NUB_SIZE - 1;
    private int right_nub_min = NUB_SIZE + 1;

    private static Gtk.Widget dummy_slider = null;
    private static Gtk.Widget dummy_frame = null;
    private static Gtk.WidgetPath slider_draw_path = new Gtk.WidgetPath();
    private static Gtk.WidgetPath frame_draw_path = new Gtk.WidgetPath();
    private static bool paths_setup = false;

    private RGBHistogram histogram = null;
    private int left_nub_position = 0;
    private int right_nub_position = 255;
    private Gdk.Pixbuf nub_pixbuf = ThemeLoader.load_icon("drag_nub.png");
    private bool is_left_nub_tracking = false;
    private bool is_right_nub_tracking = false;
    private int track_start_x = 0;
    private int track_nub_start_position = 0;

    public RGBHistogramManipulator( ) {
        set_size_request(CONTROL_WIDTH, CONTROL_HEIGHT);
        
        if (dummy_slider == null)
            dummy_slider = new Gtk.Scale(Gtk.Orientation.HORIZONTAL, null);
            
        if (dummy_frame == null)
            dummy_frame = new Gtk.Frame(null);
            
        if (!paths_setup) {
            slider_draw_path.append_type(typeof(Gtk.Scale));
            slider_draw_path.iter_add_class(0, "scale");
            slider_draw_path.iter_add_class(0, "range");
            
            frame_draw_path.append_type(typeof(Gtk.Frame));
            frame_draw_path.iter_add_class(0, "default");
            
            paths_setup = true;
        }
            
        add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
        add_events(Gdk.EventMask.BUTTON_RELEASE_MASK);
        add_events(Gdk.EventMask.BUTTON_MOTION_MASK);

        button_press_event.connect(on_button_press);
        button_release_event.connect(on_button_release);
        motion_notify_event.connect(on_button_motion);
    }
    
    private LocationCode hit_test_point(int x, int y) {
        if (y < NUB_V_POSITION)
            return LocationCode.INSENSITIVE_AREA;

        if ((x > left_nub_position) && (x < left_nub_position + NUB_SIZE))
            return LocationCode.LEFT_NUB;

        if ((x > right_nub_position) && (x < right_nub_position + NUB_SIZE))
            return LocationCode.RIGHT_NUB;

        if (y < (NUB_V_POSITION + NUB_V_NUDGE + 1))
            return LocationCode.INSENSITIVE_AREA;

        if ((x - left_nub_position) * (x - left_nub_position) <
            (x - right_nub_position) * (x - right_nub_position))
            return LocationCode.LEFT_TROUGH;
        else
            return LocationCode.RIGHT_TROUGH;
    }
    
    private bool on_button_press(Gdk.EventButton event_record) {
        LocationCode loc = hit_test_point((int) event_record.x, (int) event_record.y);

        switch (loc) {
            case LocationCode.LEFT_NUB:
                track_start_x = ((int) event_record.x);
                track_nub_start_position = left_nub_position;
                is_left_nub_tracking = true;
                return true;

            case LocationCode.RIGHT_NUB:
                track_start_x = ((int) event_record.x);
                track_nub_start_position = right_nub_position;
                is_right_nub_tracking = true;
                return true;

            case LocationCode.LEFT_TROUGH:
                left_nub_position = ((int) event_record.x) - NUB_HALF_WIDTH;
                left_nub_position = left_nub_position.clamp(0, left_nub_max);
                force_update();
                nub_position_changed();
                update_nub_extrema();
                return true;

            case LocationCode.RIGHT_TROUGH:
                right_nub_position = ((int) event_record.x) - NUB_HALF_WIDTH;
                right_nub_position = right_nub_position.clamp(right_nub_min, 255);
                force_update();
                nub_position_changed();
                update_nub_extrema();
                return true;

            default:
                return false;
        }
    }
    
    private bool on_button_release(Gdk.EventButton event_record) {
        if (is_left_nub_tracking || is_right_nub_tracking) {
            nub_position_changed();
            update_nub_extrema();
        }

        is_left_nub_tracking = false;
        is_right_nub_tracking = false;

        return false;
    }
    
    private bool on_button_motion(Gdk.EventMotion event_record) {
        if ((!is_left_nub_tracking) && (!is_right_nub_tracking))
            return false;
    
        if (is_left_nub_tracking) {
            int track_x_delta = ((int) event_record.x) - track_start_x;
            left_nub_position = (track_nub_start_position + track_x_delta);
            left_nub_position = left_nub_position.clamp(0, left_nub_max);
        } else { /* right nub is tracking */
            int track_x_delta = ((int) event_record.x) - track_start_x;
            right_nub_position = (track_nub_start_position + track_x_delta);
            right_nub_position = right_nub_position.clamp(right_nub_min, 255);
        }
        
        force_update();
        return true;
    }
    
    public override bool draw(Cairo.Context ctx) {
        Gtk.Border padding = get_style_context().get_padding(Gtk.StateFlags.NORMAL);
        
        Gdk.Rectangle area = Gdk.Rectangle();
        area.x = padding.left;
        area.y = padding.top;
        area.width = RGBHistogram.GRAPHIC_WIDTH + padding.right;
        area.height = RGBHistogram.GRAPHIC_HEIGHT + padding.bottom;

        draw_histogram_frame(ctx, area);
        draw_histogram(ctx, area);
        draw_trough(ctx, area);
        draw_nub(ctx, area, left_nub_position);
        draw_nub(ctx, area, right_nub_position);

        return true;
    }
    
    private void draw_histogram_frame(Cairo.Context ctx, Gdk.Rectangle area) {
        // the framed area is inset and slightly smaller than the overall histogram
        // control area
        Gdk.Rectangle framed_area = area;
        framed_area.x += 5;
        framed_area.y += 1;
        framed_area.width -= 8;
        framed_area.height -= 12;
        
        Gtk.StyleContext stylectx = dummy_frame.get_style_context();
        stylectx.save();
        
        stylectx.get_path().append_type(typeof(Gtk.Frame));
        stylectx.get_path().iter_add_class(0, "default");
        stylectx.add_class(Gtk.STYLE_CLASS_TROUGH);
        stylectx.set_junction_sides(Gtk.JunctionSides.TOP | Gtk.JunctionSides.BOTTOM |
            Gtk.JunctionSides.LEFT | Gtk.JunctionSides.RIGHT);

        stylectx.render_frame(ctx, framed_area.x, framed_area.y, framed_area.width,
            framed_area.height);

        stylectx.restore();
    }
    
    private void draw_histogram(Cairo.Context ctx, Gdk.Rectangle area) {
        if (histogram == null)
            return;
        
        Gdk.Pixbuf histogram_graphic = histogram.get_graphic().copy();
        unowned uchar[] pixel_data = histogram_graphic.get_pixels();
        
        int edge_blend_red = 0;
        int edge_blend_green = 0;
        int edge_blend_blue = 0;
        int body_blend_red = 20;
        int body_blend_green = 20;
        int body_blend_blue = 20;

        if (left_nub_position > 0) {
            int edge_pixel_index = histogram_graphic.n_channels * left_nub_position;
            for (int i = 0; i < histogram_graphic.height; i++) {
                int body_pixel_index = i * histogram_graphic.rowstride;
                int row_last_pixel = body_pixel_index + histogram_graphic.n_channels *
                    left_nub_position;
                while (body_pixel_index < row_last_pixel) {
                    pixel_data[body_pixel_index] =
                        (uchar) ((pixel_data[body_pixel_index] + body_blend_red) / 2);
                    pixel_data[body_pixel_index + 1] =
                        (uchar) ((pixel_data[body_pixel_index + 1] + body_blend_green) / 2);
                    pixel_data[body_pixel_index + 2] =
                        (uchar) ((pixel_data[body_pixel_index + 2] + body_blend_blue) / 2);
                
                    body_pixel_index += histogram_graphic.n_channels;
                }
            
                pixel_data[edge_pixel_index] =
                    (uchar) ((pixel_data[edge_pixel_index] + edge_blend_red) / 2);
                pixel_data[edge_pixel_index + 1] =
                    (uchar) ((pixel_data[edge_pixel_index + 1] + edge_blend_green) / 2);
                pixel_data[edge_pixel_index + 2] =
                    (uchar) ((pixel_data[edge_pixel_index + 2] + edge_blend_blue) / 2);

                edge_pixel_index += histogram_graphic.rowstride;
            }
        }

        edge_blend_red = 250;
        edge_blend_green = 250;
        edge_blend_blue = 250;
        body_blend_red = 200;
        body_blend_green = 200;
        body_blend_blue = 200;

        if (right_nub_position < 255) {
            int edge_pixel_index = histogram_graphic.n_channels * right_nub_position;
            for (int i = 0; i < histogram_graphic.height; i++) {
                int body_pixel_index = i * histogram_graphic.rowstride +
                    histogram_graphic.n_channels * 255;
                int row_last_pixel = i * histogram_graphic.rowstride +
                    histogram_graphic.n_channels * right_nub_position;
                while (body_pixel_index > row_last_pixel) {
                    pixel_data[body_pixel_index] =
                        (uchar) ((pixel_data[body_pixel_index] + body_blend_red) / 2);
                    pixel_data[body_pixel_index + 1] =
                        (uchar) ((pixel_data[body_pixel_index + 1] + body_blend_green) / 2);
                    pixel_data[body_pixel_index + 2] =
                        (uchar) ((pixel_data[body_pixel_index + 2] + body_blend_blue) / 2);
                
                    body_pixel_index -= histogram_graphic.n_channels;
                }
                pixel_data[edge_pixel_index] =
                    (uchar) ((pixel_data[edge_pixel_index] + edge_blend_red) / 2);
                pixel_data[edge_pixel_index + 1] =
                    (uchar) ((pixel_data[edge_pixel_index + 1] + edge_blend_green) / 2);
                pixel_data[edge_pixel_index + 2] =
                    (uchar) ((pixel_data[edge_pixel_index + 2] + edge_blend_blue) / 2);

                edge_pixel_index += histogram_graphic.rowstride;
            }
        }
        
        Gdk.cairo_set_source_pixbuf(ctx, histogram_graphic, area.x + NUB_HALF_WIDTH, area.y + 2);
        ctx.paint();
    }
    
    private void draw_trough(Cairo.Context ctx, Gdk.Rectangle area) { 
        int trough_x = area.x;
        int trough_y = area.y + (CONTROL_HEIGHT - TROUGH_HEIGHT - TROUGH_BOTTOM_OFFSET - 3);
        
        Gtk.StyleContext stylectx = dummy_slider.get_style_context();
        stylectx.save();
        
        stylectx.get_path().append_type(typeof(Gtk.Scale));
        stylectx.get_path().iter_add_class(0, "scale");
        stylectx.add_class(Gtk.STYLE_CLASS_TROUGH);

        stylectx.render_activity(ctx, trough_x, trough_y, TROUGH_WIDTH, TROUGH_HEIGHT);

        stylectx.restore();
    }
    
    private void draw_nub(Cairo.Context ctx, Gdk.Rectangle area, int position) {
        Gdk.cairo_set_source_pixbuf(ctx, nub_pixbuf, area.x + position, area.y + NUB_V_POSITION);
        ctx.paint();
    }
    
    private void force_update() {
        get_window().invalidate_rect(null, true);
        get_window().process_updates(true);
    }
    
    private void update_nub_extrema() {
        right_nub_min = left_nub_position + NUB_SIZE + 1;
        left_nub_max = right_nub_position - NUB_SIZE - 1;
    }

    public signal void nub_position_changed();

    public void update_histogram(Gdk.Pixbuf source_pixbuf) {
        histogram = new RGBHistogram(source_pixbuf);
        force_update();
    }
    
    public int get_left_nub_position() {
        return left_nub_position;
    }
    
    public int get_right_nub_position() {
        return right_nub_position;
    }

    public void set_left_nub_position(int user_nub_pos) {
        assert ((user_nub_pos >= 0) && (user_nub_pos <= 255));
        left_nub_position = user_nub_pos.clamp(0, left_nub_max);
        update_nub_extrema();
    }
    
    public void set_right_nub_position(int user_nub_pos) {
        assert ((user_nub_pos >= 0) && (user_nub_pos <= 255));
        right_nub_position = user_nub_pos.clamp(right_nub_min, 255);
        update_nub_extrema();
    }
}

