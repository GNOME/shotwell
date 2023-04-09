// SPDX-License-Identifier: LGPL-2.1-or-later
public struct EditingTools.RedeyeInstance {
    public const int MIN_RADIUS = 4;
    public const int MAX_RADIUS = 32;
    public const int DEFAULT_RADIUS = 10;

    public Gdk.Point center;
    public int radius;

    RedeyeInstance() {
        Gdk.Point default_center = Gdk.Point();
        center = default_center;
        radius = DEFAULT_RADIUS;
    }

    public static Gdk.Rectangle to_bounds_rect(EditingTools.RedeyeInstance inst) {
        Gdk.Rectangle result = Gdk.Rectangle();
        result.x = inst.center.x - inst.radius;
        result.y = inst.center.y - inst.radius;
        result.width = 2 * inst.radius;
        result.height = result.width;

        return result;
    }

    public static RedeyeInstance from_bounds_rect(Gdk.Rectangle rect) {
        Gdk.Rectangle in_rect = rect;

        RedeyeInstance result = RedeyeInstance();
        result.radius = (in_rect.width + in_rect.height) / 4;
        result.center.x = in_rect.x + result.radius;
        result.center.y = in_rect.y + result.radius;

        return result;
    }
}

public class EditingTools.RedeyeTool : EditingTool {
    private class RedeyeToolWindow : EditingToolWindow {
        private const int CONTROL_SPACING = 8;

        private Gtk.Label slider_label = new Gtk.Label.with_mnemonic(_("Size:"));

        public Gtk.Button apply_button =
            new Gtk.Button.with_mnemonic(Resources.APPLY_LABEL);
        public Gtk.Button close_button =
            new Gtk.Button.with_mnemonic(Resources.CANCEL_LABEL);
        public Gtk.Scale slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL,
            RedeyeInstance.MIN_RADIUS, RedeyeInstance.MAX_RADIUS, 1.0);

        public RedeyeToolWindow(Gtk.Window container) {
            base(container);

            slider.set_size_request(80, -1);
            slider.set_draw_value(false);

            close_button.set_tooltip_text(_("Close the red-eye tool"));
            //close_button.set_image_position(Gtk.PositionType.LEFT);

            apply_button.set_tooltip_text(_("Remove any red-eye effects in the selected region"));
            //apply_button.set_image_position(Gtk.PositionType.LEFT);

            Gtk.Box layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            layout.append(slider_label);
            layout.append(slider);
            layout.append(close_button);
            layout.append(apply_button);

            add(layout);
        }
    }

    private Cairo.Context thin_white_ctx = null;
    private Cairo.Context wider_gray_ctx = null;
    private RedeyeToolWindow redeye_tool_window = null;
    private RedeyeInstance user_interaction_instance;
    private bool is_reticle_move_in_progress = false;
    private Gdk.Point reticle_move_mouse_start_point;
    private Gdk.Point reticle_move_anchor;
    private Gdk.Rectangle old_scaled_pixbuf_position;
    private Gdk.Pixbuf current_pixbuf = null;

    private RedeyeTool() {
        base("RedeyeTool");
    }

    public static RedeyeTool factory() {
        return new RedeyeTool();
    }

    public static bool is_available(Photo photo, Scaling scaling) {
        Dimensions dim = scaling.get_scaled_dimensions(photo.get_dimensions());

        return dim.width >= (RedeyeInstance.MAX_RADIUS * 2)
            && dim.height >= (RedeyeInstance.MAX_RADIUS * 2);
    }

    private RedeyeInstance new_interaction_instance(PhotoCanvas canvas) {
        Gdk.Rectangle photo_bounds = canvas.get_scaled_pixbuf_position();
        Gdk.Point photo_center = {0};
        photo_center.x = photo_bounds.x + (photo_bounds.width / 2);
        photo_center.y = photo_bounds.y + (photo_bounds.height / 2);

        RedeyeInstance result = RedeyeInstance();
        result.center.x = photo_center.x;
        result.center.y = photo_center.y;
        result.radius = RedeyeInstance.DEFAULT_RADIUS;

        return result;
    }

    private void prepare_ctx(Cairo.Context ctx, Dimensions dim) {
        var scale = Application.get_scale();
        wider_gray_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(wider_gray_ctx, "#111");
        wider_gray_ctx.set_line_width(3 * scale);

        thin_white_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(thin_white_ctx, "#FFF");
        thin_white_ctx.set_line_width(1 * scale);
    }

    private void draw_redeye_instance(RedeyeInstance inst) {
        canvas.draw_circle(wider_gray_ctx, inst.center.x, inst.center.y,
            inst.radius);
        canvas.draw_circle(thin_white_ctx, inst.center.x, inst.center.y,
            inst.radius);
    }

    private bool on_size_slider_adjust(Gtk.ScrollType type) {
        user_interaction_instance.radius =
            (int) redeye_tool_window.slider.get_value();

        canvas.repaint();

        return false;
    }

    private void on_apply() {
        Gdk.Rectangle bounds_rect_user =
            RedeyeInstance.to_bounds_rect(user_interaction_instance);

        Gdk.Rectangle bounds_rect_active =
            canvas.user_to_active_rect(bounds_rect_user);
        Gdk.Rectangle bounds_rect_unscaled =
            canvas.active_to_unscaled_rect(bounds_rect_active);
        Gdk.Rectangle bounds_rect_raw =
            canvas.unscaled_to_raw_rect(bounds_rect_unscaled);

        RedeyeInstance instance_raw =
            RedeyeInstance.from_bounds_rect(bounds_rect_raw);

        // transform screen coords back to image coords,
        // taking into account straightening angle.
        Dimensions dimensions = canvas.get_photo().get_dimensions(
            Photo.Exception.STRAIGHTEN | Photo.Exception.CROP);

        double theta = 0.0;

        canvas.get_photo().get_straighten(out theta);

        instance_raw.center = derotate_point_arb(instance_raw.center,
                                                 dimensions.width, dimensions.height, theta);

        RedeyeCommand command = new RedeyeCommand(canvas.get_photo(), instance_raw,
            Resources.RED_EYE_LABEL, Resources.RED_EYE_TOOLTIP);
        AppWindow.get_command_manager().execute(command);
    }

    private void on_photos_altered(Gee.Map<DataObject, Alteration> map) {
        if (!map.has_key(canvas.get_photo()))
            return;

        try {
            current_pixbuf = canvas.get_photo().get_pixbuf(canvas.get_scaling());
        } catch (Error err) {
            warning("%s", err.message);
            aborted();

            return;
        }

        canvas.repaint();
    }

    private void on_close() {
        applied(null, current_pixbuf, canvas.get_photo().get_dimensions(), false);
    }

    private void on_canvas_resize() {
        Gdk.Rectangle scaled_pixbuf_position =
            canvas.get_scaled_pixbuf_position();

        user_interaction_instance.center.x -= old_scaled_pixbuf_position.x;
        user_interaction_instance.center.y -= old_scaled_pixbuf_position.y;

        double scale_factor = ((double) scaled_pixbuf_position.width) /
            ((double) old_scaled_pixbuf_position.width);

        user_interaction_instance.center.x =
            (int)(((double) user_interaction_instance.center.x) *
            scale_factor + 0.5);
        user_interaction_instance.center.y =
            (int)(((double) user_interaction_instance.center.y) *
            scale_factor + 0.5);

        user_interaction_instance.center.x += scaled_pixbuf_position.x;
        user_interaction_instance.center.y += scaled_pixbuf_position.y;

        old_scaled_pixbuf_position = scaled_pixbuf_position;

        current_pixbuf = null;
    }

    public override void activate(PhotoCanvas canvas) {
        user_interaction_instance = new_interaction_instance(canvas);

        prepare_ctx(canvas.get_default_ctx(), canvas.get_surface_dim());

        bind_canvas_handlers(canvas);

        old_scaled_pixbuf_position = canvas.get_scaled_pixbuf_position();
        current_pixbuf = canvas.get_scaled_pixbuf();

        redeye_tool_window = new RedeyeToolWindow(canvas.get_container());
        redeye_tool_window.slider.set_value(user_interaction_instance.radius);

        bind_window_handlers();

        DataCollection? owner = canvas.get_photo().get_membership();
        if (owner != null)
            owner.items_altered.connect(on_photos_altered);

        base.activate(canvas);
    }

    public override void deactivate() {
        if (canvas != null) {
            DataCollection? owner = canvas.get_photo().get_membership();
            if (owner != null)
                owner.items_altered.disconnect(on_photos_altered);

            unbind_canvas_handlers(canvas);
        }

        if (redeye_tool_window != null) {
            unbind_window_handlers();
            redeye_tool_window.hide();
            redeye_tool_window.destroy();
            redeye_tool_window = null;
        }

        base.deactivate();
    }

    private void bind_canvas_handlers(PhotoCanvas canvas) {
        canvas.new_surface.connect(prepare_ctx);
        canvas.resized_scaled_pixbuf.connect(on_canvas_resize);
    }

    private void unbind_canvas_handlers(PhotoCanvas canvas) {
        canvas.new_surface.disconnect(prepare_ctx);
        canvas.resized_scaled_pixbuf.disconnect(on_canvas_resize);
    }

    private void bind_window_handlers() {
        redeye_tool_window.apply_button.clicked.connect(on_apply);
        redeye_tool_window.close_button.clicked.connect(on_close);
        redeye_tool_window.slider.change_value.connect(on_size_slider_adjust);
    }

    private void unbind_window_handlers() {
        redeye_tool_window.apply_button.clicked.disconnect(on_apply);
        redeye_tool_window.close_button.clicked.disconnect(on_close);
        redeye_tool_window.slider.change_value.disconnect(on_size_slider_adjust);
    }

    public override EditingToolWindow? get_tool_window() {
        return redeye_tool_window;
    }

    public override void paint(Cairo.Context ctx) {
        canvas.paint_pixbuf((current_pixbuf != null) ? current_pixbuf : canvas.get_scaled_pixbuf());

        /* user_interaction_instance has its radius in user coords, and
           draw_redeye_instance expects active region coords */
        RedeyeInstance active_inst = user_interaction_instance;
        active_inst.center =
            canvas.user_to_active_point(user_interaction_instance.center);
        draw_redeye_instance(active_inst);
    }

    public override void on_left_click(int x, int y) {
        var scale = Application.get_scale();

        Gdk.Rectangle bounds_rect =
            RedeyeInstance.to_bounds_rect(user_interaction_instance);


        if (coord_in_rectangle((int)Math.lround(x * scale), (int)Math.lround(y * scale), bounds_rect)) {
            print("Motion in progress!!\n");
            is_reticle_move_in_progress = true;
            reticle_move_mouse_start_point.x = (int)Math.lround(x * scale);
            reticle_move_mouse_start_point.y = (int)Math.lround(y * scale);
            reticle_move_anchor = user_interaction_instance.center;
        }
    }

    public override void on_left_released(int x, int y) {
        is_reticle_move_in_progress = false;
    }

    public override void on_motion(int x, int y, Gdk.ModifierType mask) {
        var scale = Application.get_scale();

        if (is_reticle_move_in_progress) {

            Gdk.Rectangle active_region_rect =
                canvas.get_scaled_pixbuf_position();

            int x_clamp_low =
                active_region_rect.x + user_interaction_instance.radius + 1;
            int y_clamp_low =
                active_region_rect.y + user_interaction_instance.radius + 1;
            int x_clamp_high =
                active_region_rect.x + active_region_rect.width -
                user_interaction_instance.radius - 1;
            int y_clamp_high =
                active_region_rect.y + active_region_rect.height -
                user_interaction_instance.radius - 1;

            int delta_x = (int)Math.lround(x * scale) - reticle_move_mouse_start_point.x;
            int delta_y = (int)Math.lround(y * scale) - reticle_move_mouse_start_point.y;

            user_interaction_instance.center.x = reticle_move_anchor.x +
                delta_x;
            user_interaction_instance.center.y = reticle_move_anchor.y +
                delta_y;

            user_interaction_instance.center.x =
                (reticle_move_anchor.x + delta_x).clamp(x_clamp_low,
                x_clamp_high);
            user_interaction_instance.center.y =
                (reticle_move_anchor.y + delta_y).clamp(y_clamp_low,
                y_clamp_high);

            canvas.repaint();
        } else {
            Gdk.Rectangle bounds =
                RedeyeInstance.to_bounds_rect(user_interaction_instance);

            if (coord_in_rectangle((int)Math.lround(x * scale), (int)Math.lround(y * scale), bounds)) {
                canvas.set_cursor("move");
            } else {
                canvas.set_cursor(null);
            }
        }
    }

    public override bool on_keypress(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if ((Gdk.keyval_name(keyval) == "KP_Enter") ||
            (Gdk.keyval_name(keyval) == "Enter") ||
            (Gdk.keyval_name(keyval) == "Return")) {
            on_close();
            return true;
        }

        return base.on_keypress(event, keyval, keycode, modifiers);
    }
}
