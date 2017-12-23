/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

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

    private static Gtk.WidgetPath slider_draw_path = new Gtk.WidgetPath();
    private static Gtk.WidgetPath frame_draw_path = new Gtk.WidgetPath();
    private static bool paths_setup = false;

    private RGBHistogram histogram = null;
    private int left_nub_position = 0;
    private int right_nub_position = 255;
    private bool is_left_nub_tracking = false;
    private bool is_right_nub_tracking = false;
    private int track_start_x = 0;
    private int track_nub_start_position = 0;
    private int offset = 0;

    public RGBHistogramManipulator( ) {
        set_size_request(CONTROL_WIDTH, CONTROL_HEIGHT);
        can_focus = true;
        
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
        add_events(Gdk.EventMask.FOCUS_CHANGE_MASK);
        add_events(Gdk.EventMask.KEY_PRESS_MASK);

        button_press_event.connect(on_button_press);
        button_release_event.connect(on_button_release);
        motion_notify_event.connect(on_button_motion);

        this.size_allocate.connect(on_size_allocate);
    }

    private void on_size_allocate(Gtk.Allocation region) {
        this.offset = (region.width - RGBHistogram.GRAPHIC_WIDTH - NUB_SIZE) / 2;
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
        // Adjust mouse position to drawing offset
        // Easier to modify the event and shit the whole drawing then adjusting the nub drawing code
        event_record.x -= this.offset;
        LocationCode loc = hit_test_point((int) event_record.x, (int) event_record.y);
        bool retval = true;

        switch (loc) {
            case LocationCode.LEFT_NUB:
                track_start_x = ((int) event_record.x);
                track_nub_start_position = left_nub_position;
                is_left_nub_tracking = true;
                break;

            case LocationCode.RIGHT_NUB:
                track_start_x = ((int) event_record.x);
                track_nub_start_position = right_nub_position;
                is_right_nub_tracking = true;
                break;

            case LocationCode.LEFT_TROUGH:
                left_nub_position = ((int) event_record.x) - NUB_HALF_WIDTH;
                left_nub_position = left_nub_position.clamp(0, left_nub_max);
                force_update();
                nub_position_changed();
                update_nub_extrema();
                break;

            case LocationCode.RIGHT_TROUGH:
                right_nub_position = ((int) event_record.x) - NUB_HALF_WIDTH;
                right_nub_position = right_nub_position.clamp(right_nub_min, 255);
                force_update();
                nub_position_changed();
                update_nub_extrema();
                break;

            default:
                retval = false;
                break;
        }

        // Remove adjustment position to drawing offset
        event_record.x += this.offset;

        return retval;
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
    
        event_record.x -= this.offset;
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
        event_record.x += this.offset;

        return true;
    }

    public override bool focus_out_event(Gdk.EventFocus event) {
        if (base.focus_out_event(event)) {
            return true;
        }

        queue_draw();

        return false;
    }

    public override bool key_press_event(Gdk.EventKey event) {
        if (base.key_press_event(event)) {
            return true;
        }

        int delta = 0;

        if (event.keyval == Gdk.Key.Left || event.keyval == Gdk.Key.Up) {
            delta = -1;
        }

        if (event.keyval == Gdk.Key.Right || event.keyval == Gdk.Key.Down) {
            delta = 1;
        }

        if (!(Gdk.ModifierType.CONTROL_MASK in event.state)) {
            delta *= 5;
        }

        if (delta == 0) {
            return false;
        }

        if (Gdk.ModifierType.SHIFT_MASK in event.state) {
            right_nub_position += delta;
            right_nub_position = right_nub_position.clamp(right_nub_min, 255);
        } else {
            left_nub_position += delta;
            left_nub_position = left_nub_position.clamp(0, left_nub_max);

        }

        nub_position_changed();
        update_nub_extrema();
        force_update();

        return true;
    }
    
    public override bool draw(Cairo.Context ctx) {
        Gtk.Border padding = get_style_context().get_padding(Gtk.StateFlags.NORMAL);

        Gdk.Rectangle area = Gdk.Rectangle();
        area.x = padding.left + this.offset;
        area.y = padding.top;
        area.width = RGBHistogram.GRAPHIC_WIDTH + padding.right;
        area.height = RGBHistogram.GRAPHIC_HEIGHT + padding.bottom;

        if (has_focus) {
            get_style_context().render_focus(ctx, area.x, area.y,
                                             area.width + NUB_SIZE,
                                             area.height + NUB_SIZE + NUB_HALF_WIDTH);
        }

        draw_histogram(ctx, area);
        draw_nub(ctx, area, left_nub_position);
        draw_nub(ctx, area, right_nub_position);

        return true;
    }
    
    private void draw_histogram(Cairo.Context ctx, Gdk.Rectangle area) {
        if (histogram == null)
            return;

        var histogram_graphic = histogram.get_graphic();

        Gdk.cairo_set_source_pixbuf(ctx, histogram_graphic, area.x + NUB_HALF_WIDTH, area.y + 2);
        ctx.paint();

        if (left_nub_position > 0) {
            ctx.rectangle(area.x + NUB_HALF_WIDTH, area.y + 2,
                          left_nub_position,
                          histogram_graphic.height);
            ctx.set_source_rgba(0.0, 0.0, 0.0, 0.45);
            ctx.fill();
        }

        if (right_nub_position < 255) {
            ctx.rectangle(area.x + right_nub_position + NUB_HALF_WIDTH,
                          area.y + 2,
                          histogram_graphic.width - right_nub_position,
                          histogram_graphic.height);
            ctx.set_source_rgba(1.0, 1.0, 1.0, 0.45);
            ctx.fill();
        }
    }

    private void draw_nub(Cairo.Context ctx, Gdk.Rectangle area, int position) {
        ctx.move_to(area.x + position, area.y + NUB_V_POSITION + NUB_SIZE);
        ctx.line_to(area.x + position + NUB_HALF_WIDTH, area.y + NUB_V_POSITION);
        ctx.line_to(area.x + position + NUB_SIZE, area.y + NUB_V_POSITION + NUB_SIZE);
        ctx.close_path();
        ctx.set_source_rgb(0.333, 0.333, 0.333);
        ctx.fill();
    }
    
    private void force_update() {
        get_window().invalidate_rect(null, true);
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

