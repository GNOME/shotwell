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
        focusable = true;

        var focus = new Gtk.EventControllerFocus();
        focus.leave.connect(queue_draw);
        add_controller(focus);

        var key = new Gtk.EventControllerKey();
        key.key_pressed.connect(on_key_pressed);
        add_controller(key);

        var click = new Gtk.GestureClick();
        click.set_touch_only(false);
        click.set_button(Gdk.BUTTON_PRIMARY);
        click.pressed.connect(on_button_press);
        click.released.connect(on_button_released);
        add_controller(click);

        var motion = new Gtk.EventControllerMotion();
        motion.motion.connect(on_button_motion);
        add_controller(motion);

        this.resize.connect(on_resize);
        set_draw_func(on_draw);
    }

    private void on_resize(int width, int height) {
        this.offset = (width - RGBHistogram.GRAPHIC_WIDTH - NUB_SIZE) / 2;
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

    private void on_button_press(Gtk.GestureClick gesture, int press, double x, double y) {
        if (get_focus_on_click() && !has_focus) {
            grab_focus();
        }
        
        if (press != 1) {
            return;
        }

        // Adjust mouse position to drawing offset
        // Easier to modify the event and shit the whole drawing then adjusting the nub drawing code
        x -= this.offset;
        LocationCode loc = hit_test_point((int) x, (int) y);
        bool retval = true;

        switch (loc) {
            case LocationCode.LEFT_NUB:
                track_start_x = ((int) x);
                track_nub_start_position = left_nub_position;
                is_left_nub_tracking = true;
                break;

            case LocationCode.RIGHT_NUB:
                track_start_x = ((int) x);
                track_nub_start_position = right_nub_position;
                is_right_nub_tracking = true;
                break;

            case LocationCode.LEFT_TROUGH:
                left_nub_position = ((int) x) - NUB_HALF_WIDTH;
                left_nub_position = left_nub_position.clamp(0, left_nub_max);
                force_update();
                nub_position_changed();
                update_nub_extrema();
                break;

            case LocationCode.RIGHT_TROUGH:
                right_nub_position = ((int) x) - NUB_HALF_WIDTH;
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
        x += this.offset;

        if (retval) {
            var sequence = gesture.get_current_sequence ();
            gesture.set_sequence_state (sequence, Gtk.EventSequenceState.CLAIMED);
        }
    }
    
    private void on_button_released(Gtk.GestureClick gesture, int press, double x, double y) {
        if (is_left_nub_tracking || is_right_nub_tracking) {
            nub_position_changed();
            update_nub_extrema();
        }

        is_left_nub_tracking = false;
        is_right_nub_tracking = false;
    }
    
    private void on_button_motion(double x, double y) {
        if ((!is_left_nub_tracking) && (!is_right_nub_tracking))
            return;
    
        x -= this.offset;
        if (is_left_nub_tracking) {
            int track_x_delta = ((int) x) - track_start_x;
            left_nub_position = (track_nub_start_position + track_x_delta);
            left_nub_position = left_nub_position.clamp(0, left_nub_max);
        } else { /* right nub is tracking */
            int track_x_delta = ((int) x) - track_start_x;
            right_nub_position = (track_nub_start_position + track_x_delta);
            right_nub_position = right_nub_position.clamp(right_nub_min, 255);
        }
        
        force_update();
        x += this.offset;
    }

    public bool on_key_pressed(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        int delta = 0;

        if (keyval == Gdk.Key.Left || keyval == Gdk.Key.Up) {
            delta = -1;
        }

        if (keyval == Gdk.Key.Right || keyval == Gdk.Key.Down) {
            delta = 1;
        }

        if (!(Gdk.ModifierType.CONTROL_MASK in modifiers)) {
            delta *= 5;
        }

        if (delta == 0) {
            return false;
        }

        if (Gdk.ModifierType.SHIFT_MASK in modifiers) {
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
    
    public void on_draw(Gtk.DrawingArea self, Cairo.Context ctx, int width, int height) {
        var sctx = get_style_context();
        sctx.save();
        sctx.set_state (Gtk.StateFlags.NORMAL);
        Gtk.Border padding = sctx.get_padding();

        Gdk.Rectangle area = Gdk.Rectangle();
        area.x = padding.left + this.offset;
        area.y = padding.top;
        area.width = RGBHistogram.GRAPHIC_WIDTH + padding.right;
        area.height = RGBHistogram.GRAPHIC_HEIGHT + padding.bottom;

        if (has_focus) {
            sctx.render_focus(ctx, area.x, area.y,
                                             area.width + NUB_SIZE,
                                             area.height + NUB_SIZE + NUB_HALF_WIDTH);
        }

        draw_histogram(ctx, area);
        draw_nub(ctx, area, left_nub_position);
        draw_nub(ctx, area, right_nub_position);
        sctx.restore();
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
        queue_draw();
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

