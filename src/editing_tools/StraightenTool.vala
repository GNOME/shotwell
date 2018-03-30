
/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace EditingTools {

/**
 * An editing tool that allows one to introduce or remove a Dutch angle from
 * a photograph.
 */
public class StraightenTool : EditingTool {
    private const double MIN_ANGLE = -15.0;
    private const double MAX_ANGLE = 15.0;
    private const double INCREMENT = 0.1;
    private const int MIN_SLIDER_SIZE = 160;
    private const int MIN_LABEL_SIZE = 100;
    private const int MIN_BUTTON_SIZE = 84;
    private const int TEMP_PIXBUF_SIZE = 768;
    private const double GUIDE_DASH[2] = {10, 10};
    private const int REPAINT_ON_STOP_DELAY_MSEC = 100;

    private class StraightenGuide {
        private bool is_active = false;
        private int x[2]; // start & end drag coords
        private int y[2];
        private double angle0; // current angle

        public void reset(int x, int y, double angle) {
            this.x = {x, x};
            this.y = {y, y};
            this.is_active = true;
            this.angle0 = angle;
        }
        
        public bool update(int x, int y) {
            if (this.is_active) {
                this.x[1] = x;
                this.y[1] = y;
                return true;
            }

            return false;
        }
        
        public void clear() {
            this.is_active = false;
        }

        public double? get_angle() {
            double dx = x[1] - x[0];
            double dy = y[1] - y[0];

            // minimum radius to consider: discard clicks
            if (dy*dy + dx*dx < 40)
                return null;

            // distinguish guides closer to horizontal or vertical
            if (Math.fabs(dy) > Math.fabs(dx))
                return angle0 + Math.atan(dx / dy) / Math.PI * 180;
            else
                return angle0 - Math.atan(dy / dx) / Math.PI * 180;
        }

        public void draw(Cairo.Context ctx) {
            if (!is_active)
                return;
            
            double angle = get_angle() ?? 0.0;
            if (angle == 0.0)
                return;
                
            double alpha = 1.0;
            if (angle < MIN_ANGLE || angle > MAX_ANGLE)
                alpha = 0.35;
                
            // b&w dashing so it will be more visible on
            // different backgrounds.
            ctx.set_source_rgba(0.0, 0.0, 0.0, alpha);
            ctx.set_dash(GUIDE_DASH,  GUIDE_DASH[0] / 2);
            ctx.move_to(x[0] + 0.5, y[0] + 0.5);
            ctx.line_to(x[1] + 0.5, y[1] + 0.5);
            ctx.stroke();
            ctx.set_dash(GUIDE_DASH, -GUIDE_DASH[0] / 2);
            ctx.set_source_rgba(1.0, 1.0, 1.0, alpha); 
            ctx.move_to(x[0] + 0.5, y[0] + 0.5);
            ctx.line_to(x[1] + 0.5, y[1] + 0.5);
            ctx.stroke();
        }
    }
    
    private class StraightenToolWindow : EditingToolWindow {
        public const int CONTROL_SPACING = 8;

        public Gtk.Scale angle_slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, MIN_ANGLE, MAX_ANGLE, INCREMENT);
        public Gtk.Label angle_label = new Gtk.Label("");
        public Gtk.Label description_label = new Gtk.Label(_("Angle:"));
        public Gtk.Button ok_button = new Gtk.Button.with_mnemonic(_("_Straighten"));
        public Gtk.Button cancel_button = new Gtk.Button.with_mnemonic(Resources.CANCEL_LABEL);
        public Gtk.Button reset_button = new Gtk.Button.with_mnemonic(_("_Reset"));

        /**
         * Prepare straighten tool's window for use and initialize all its controls.
         *
         * @param container The application's main window.
         */
        public StraightenToolWindow(Gtk.Window container) {
            base(container);

            angle_slider.set_size_request(MIN_SLIDER_SIZE, -1);
            angle_slider.set_value(0.0);
            angle_slider.set_draw_value(false);

            description_label.margin_start = CONTROL_SPACING;
            description_label.margin_end = CONTROL_SPACING;
            description_label.margin_top = 0;
            description_label.margin_bottom = 0;

            angle_label.margin_start = 0;
            angle_label.margin_end = 0;
            angle_label.margin_top = 0;
            angle_label.margin_bottom = 0;
            angle_label.set_size_request(MIN_LABEL_SIZE,-1);

            Gtk.Box slider_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            slider_layout.pack_start(angle_slider, true, true, 0);

            Gtk.Box button_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            cancel_button.set_size_request(MIN_BUTTON_SIZE, -1);
            reset_button.set_size_request(MIN_BUTTON_SIZE, -1);
            ok_button.set_size_request(MIN_BUTTON_SIZE, -1);
            button_layout.pack_start(cancel_button, true, true, 0);
            button_layout.pack_start(reset_button, true, true, 0);
            button_layout.pack_start(ok_button, true, true, 0);

            Gtk.Box main_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            main_layout.pack_start(description_label, true, true, 0);
            main_layout.pack_start(slider_layout, true, true, 0);
            main_layout.pack_start(angle_label, true, true, 0);
            main_layout.pack_start(button_layout, true, true, 0);

            add(main_layout);

            reset_button.clicked.connect(on_reset_clicked);

            set_position(Gtk.WindowPosition.CENTER_ON_PARENT);
        }

        private void on_reset_clicked() {
            angle_slider.set_value(0.0);
        }
    }

    private StraightenToolWindow window;

    // the incoming image itself.
    private Cairo.Surface photo_surf;
    Dimensions image_dims;

    // temporary surface we'll draw the rotated image into.
    private Cairo.Surface rotate_surf;
    private Cairo.Context rotate_ctx;

    private Dimensions last_viewport;
    private int view_width;
    private int view_height;
    private double photo_angle = 0.0;

    // should we use a nicer-but-more-expensive filter
    // when repainting the rotated image?
    private bool use_high_qual = true;
    private OneShotScheduler? slider_sched = null;

    private Gdk.Point crop_center;  // original center in image coordinates
    private int crop_width;
    private int crop_height;

    private StraightenGuide guide = new StraightenGuide();
    
    // As the crop box rotates, we adjust its center and/or scale it so that it fits in the image.
    private Gdk.Point rotated_center;   // in image coordinates
    private double rotate_scale;    // always <= 1.0: rotation may shrink but not grow box
    
    private double preview_scale;

    private StraightenTool() {
        base("StraightenTool");
    }

    public static StraightenTool factory() {
        return new StraightenTool();
    }

    public static bool is_available(Photo photo, Scaling scaling) {
        return true;
    }

    /**
     * @brief Signal handler for when the 'OK' button has been clicked.  Computes where a previously-
     * set crop region should have rotated to (to match the Photo's straightening angle).
     *
     * @note After this has been called against a Photo, it will always have a crop region; in the
     * case of a previously-uncropped Photo, the crop region will be set to the original dimensions
     * of the photo and centered at the Photo's center.
     */
    private void on_ok_clicked() {
        assert(canvas.get_photo() != null);

        // compute where the crop box should be now and set the image's
        // current crop to it
        double slider_val = window.angle_slider.get_value();

        Gdk.Point new_crop_center = rotate_point_arb(rotated_center,
            image_dims.width, image_dims.height, slider_val);

        StraightenCommand command = new StraightenCommand(
            canvas.get_photo(), slider_val,
            Box.from_center(new_crop_center,
                (int) (rotate_scale * crop_width), (int) (rotate_scale * crop_height)),
            Resources.STRAIGHTEN_LABEL, Resources.STRAIGHTEN_TOOLTIP);
        applied(command, null, image_dims, true);
    }

    private void high_qual_repaint(){
        use_high_qual = true;
        update_rotated_surface();
        this.canvas.repaint();
    }
    
    private void on_slider_stopped_delayed() {
        high_qual_repaint();
    }

    public override void on_left_click(int x, int y) {
        guide.reset(x, y, photo_angle);
    }

    public override void on_left_released(int x, int y) {
        guide.update(x, y);
        double? a = guide.get_angle();
        guide.clear();
        if (a != null) {
            window.angle_slider.set_value(a);
            high_qual_repaint();
        }
    }

    public override void on_motion(int x, int y, Gdk.ModifierType mask) {
        if (guide.update(x, y))
            canvas.repaint();
    }

    public override bool on_keypress(Gdk.EventKey event) {
        if ((Gdk.keyval_name(event.keyval) == "KP_Enter") ||
            (Gdk.keyval_name(event.keyval) == "Enter") ||
            (Gdk.keyval_name(event.keyval) == "Return")) {
            on_ok_clicked();
            return true;
        }

        if (Gdk.keyval_name(event.keyval) == "Escape") {
            notify_cancel();
            return true;
        }

        return base.on_keypress(event);
    }

    private void prepare_image() {
        Dimensions canvas_dims = canvas.get_surface_dim();
        Dimensions viewport = canvas_dims.with_max(TEMP_PIXBUF_SIZE, TEMP_PIXBUF_SIZE);
        if (viewport == last_viewport)
            return;     // no change

        last_viewport = viewport;
            
        Gdk.Pixbuf low_res_tmp = null;
        try {
            low_res_tmp =
                canvas.get_photo().get_pixbuf_with_options(Scaling.for_viewport(viewport, false),
                    Photo.Exception.STRAIGHTEN | Photo.Exception.CROP);
        } catch (Error e) {
            warning("A pixbuf for %s couldn't be fetched.", canvas.get_photo().to_string());
            low_res_tmp = new Gdk.Pixbuf(Gdk.Colorspace.RGB, false, 8, 1, 1);
        }

        preview_scale = low_res_tmp.width / (double) image_dims.width;

        // copy image data from photo into a cairo surface.
        photo_surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, low_res_tmp.width, low_res_tmp.height);
        Cairo.Context ctx = new Cairo.Context(photo_surf);
        paint_pixmap_with_background(ctx, low_res_tmp, 0, 0);

        // prepare rotation surface and context. we paint a rotated,
        // low-res copy of the image into it, followed by a faint grid.
        view_width = (int) (crop_width * preview_scale);
        view_height = (int) (crop_height * preview_scale);
        rotate_surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, view_width, view_height);
        rotate_ctx = new Cairo.Context(rotate_surf);
    }

    // Adjust the rotated crop box so that it fits in the source image.
    void adjust_for_rotation() {
        double width, height;
        compute_arb_rotated_size(crop_width, crop_height, photo_angle, out width, out height);
        
        // First compute a scaling factor that will let the rotated box fit in the image.
        rotate_scale = double.min(image_dims.width / width, image_dims.height / height);
        rotate_scale = double.min(rotate_scale, 1.0);

        // Now nudge the box into the image if necessary.
        rotated_center = crop_center;
        int radius_x = (int) (rotate_scale * width / 2);
        int radius_y = (int) (rotate_scale * height / 2);
        rotated_center.x = rotated_center.x.clamp(radius_x, image_dims.width - radius_x);
        rotated_center.y = rotated_center.y.clamp(radius_y, image_dims.height - radius_y);
    }

    /**
     * @brief Spawn the tool window, set up the scratch surfaces and prepare the straightening
     * tool for use.  If a valid pixbuf of the incoming Photo can't be loaded for any
     * reason, the tool will use a 1x1 temporary image instead to avoid crashing.
     *
     * @param canvas The PhotoCanvas the tool's output should be painted to.
     */
    public override void activate(PhotoCanvas canvas) {
        base.activate(canvas);
        this.canvas = canvas;
        bind_canvas_handlers(this.canvas);

        image_dims = canvas.get_photo().get_dimensions(
            Photo.Exception.STRAIGHTEN | Photo.Exception.CROP);

        Box crop_region;
        if (!canvas.get_photo().get_crop(out crop_region)) {
            crop_region.left = 0;
            crop_region.right = image_dims.width;

            crop_region.top = 0;
            crop_region.bottom = image_dims.height;
        }

        // read the photo's current angle and start the tool with the slider set to that value. we
        // also use this to de-rotate the crop region
        double incoming_angle = 0.0;
        canvas.get_photo().get_straighten(out incoming_angle);

        // Translate the crop center to image coordinates.
        crop_center = derotate_point_arb(crop_region.get_center(),
            image_dims.width, image_dims.height, incoming_angle);
        crop_width = crop_region.get_width();
        crop_height = crop_region.get_height();
        
        adjust_for_rotation();

        prepare_image();

        // set crosshair cursor
        var drawing_window = canvas.get_drawing_window ();
        var display = drawing_window.get_display ();
        var cursor = new Gdk.Cursor.for_display (display,
                                                 Gdk.CursorType.CROSSHAIR);
        drawing_window.set_cursor (cursor);

        window = new StraightenToolWindow(canvas.get_container());
        bind_window_handlers();

        // prepare ths slider for display
        window.angle_slider.set_value(incoming_angle);
        photo_angle = incoming_angle;

        string tmp = "%2.1f°".printf(incoming_angle);
        window.angle_label.set_text(tmp);

        high_qual_repaint();
        window.show_all();
    }

    /**
     * Tears down the tool window and frees resources.
     */
    public override void deactivate() {
        if(window != null) {

            unbind_window_handlers();

            window.hide();
            window = null;
        }

        if (canvas != null) {
            unbind_canvas_handlers(canvas);
            canvas.get_drawing_window().set_cursor(null);
        }

        base.deactivate();
    }

    private void bind_canvas_handlers(PhotoCanvas canvas) {
        canvas.resized_scaled_pixbuf.connect(on_resized_pixbuf);
    }

    private void unbind_canvas_handlers(PhotoCanvas canvas) {
        canvas.resized_scaled_pixbuf.disconnect(on_resized_pixbuf);
    }

    private void bind_window_handlers() {
        window.key_press_event.connect(on_keypress);
        window.ok_button.clicked.connect(on_ok_clicked);
        window.cancel_button.clicked.connect(notify_cancel);
        window.angle_slider.value_changed.connect(on_angle_changed);
    }

    private void unbind_window_handlers() {
        window.key_press_event.disconnect(on_keypress);
        window.ok_button.clicked.disconnect(on_ok_clicked);
        window.cancel_button.clicked.disconnect(notify_cancel);
        window.angle_slider.value_changed.disconnect(on_angle_changed);
    }

    private void on_angle_changed() {
        photo_angle = window.angle_slider.get_value();
        string tmp = "%2.1f°".printf(window.angle_slider.get_value());
        window.angle_label.set_text(tmp);

        if (slider_sched == null)
            slider_sched = new OneShotScheduler("straighten", on_slider_stopped_delayed);
        slider_sched.after_timeout(REPAINT_ON_STOP_DELAY_MSEC, true);

        use_high_qual = false;

        adjust_for_rotation();
        update_rotated_surface();
        this.canvas.repaint();
    }

    /**
     * @brief Called by the EditingHostPage when a resize event occurs.
     */
    private void on_resized_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled, Gdk.Rectangle scaled_position) {
        prepare_image();
    }

    /**
     * Returns a reference to the current StraightenTool instance's tool window;
     * the PhotoPage uses this to control the tool window's positioning, etc.
     */
    public override EditingToolWindow? get_tool_window() {
        return window;
    }

    /**
     * Draw the rotated photo and grid.
     */
    private void update_rotated_surface() {        
        draw_rotated_source(photo_surf, rotate_ctx, view_width, view_height, photo_angle);
        rotate_ctx.set_line_width(1.0);
        draw_superimposed_grid(rotate_ctx, view_width, view_height);
    }

    /**
     * Render a smaller, rotated version of the image, with a grid superimposed over it.
     *
     * @param ctx The rendering context of a 'scratch' Cairo surface.  The tool makes its own
     *      surfaces and contexts so it can have things set up exactly like it wants them, so
     *      it's not used.
     */
    public override void paint(Cairo.Context ctx) {
        int w = canvas.get_drawing_window().get_width();
        int h = canvas.get_drawing_window().get_height();

        // fill region behind the rotation surface with neutral color.
        canvas.get_default_ctx().identity_matrix();
        canvas.get_default_ctx().set_source_rgba(0.0, 0.0, 0.0, 1.0);
        canvas.get_default_ctx().rectangle(0, 0, w, h);
        canvas.get_default_ctx().fill();

        // copy the composited result to the main window.
        canvas.get_default_ctx().translate((w - view_width) / 2.0, (h - view_height) / 2.0);
        canvas.get_default_ctx().set_source_surface(rotate_surf, 0, 0);
        canvas.get_default_ctx().rectangle(0, 0, view_width, view_height);
        canvas.get_default_ctx().fill();
        canvas.get_default_ctx().paint();

        // reset the 'modelview' matrix, since when the canvas is not in
        // 'tool' mode, it 'expects' things to be set up a certain way.
        canvas.get_default_ctx().identity_matrix();

        guide.draw(canvas.get_default_ctx());
    }

    /**
     * Copy a rotated version of the source image onto the destination
     * context.
     *
     * @param src_surf A Cairo surface containing the source image.
     * @param dest_ctx The rendering context of the destination image.
     * @param src_width The width of the image data in src_surf in pixels.
     * @param src_height The height of the image data in src_surf in pixels.
     * @param angle The angle the source image should be rotated by, in degrees.
     */
    private void draw_rotated_source(Cairo.Surface src_surf, Cairo.Context dest_ctx,
        int src_width, int src_height, double angle) {
        double angle_internal = degrees_to_radians(angle);

        // fill area behind rotated image with neutral color to avoid 'ghosting'.
        // this should be removed after #4612 has been addressed.
        dest_ctx.identity_matrix();
        dest_ctx.set_source_rgba(0.0, 0.0, 0.0, 1.0);
        dest_ctx.rectangle(0, 0, view_width, view_height);
        dest_ctx.fill();

        // rotate the image, taking into account that the position of the
        // upper left corner must change depending on rotation amount and direction
        // and  translate so center of preview crop region is now center of rotation
        dest_ctx.identity_matrix();

        dest_ctx.translate(view_width / 2, view_height / 2);
        dest_ctx.scale(1.0 / rotate_scale, 1.0 / rotate_scale);
        dest_ctx.rotate(angle_internal);
        dest_ctx.translate(- rotated_center.x * preview_scale, - rotated_center.y * preview_scale);

        dest_ctx.set_source_surface(src_surf, 0, 0);
        dest_ctx.get_source().set_filter(use_high_qual ? Cairo.Filter.BEST : Cairo.Filter.NEAREST);
        dest_ctx.rectangle(0, 0, src_width, src_height);
        dest_ctx.fill();
        dest_ctx.paint();
    }

    /**
     * Superimpose a faint grid over the supplied image.
     *
     * @param width The total width the grid should be drawn to.
     * @param height The total height the grid should be drawn to.
     * @param dest_ctx The rendering context of the destination image.
     */
    private void draw_superimposed_grid(Cairo.Context dest_ctx, int width, int height) {
        int half_width = width / 2;
        int quarter_width = width / 4;

        int half_height = height / 2;
        int quarter_height = height / 4;

        dest_ctx.identity_matrix();
        dest_ctx.set_source_rgba(1.0, 1.0, 1.0, 1.0);

        canvas.draw_horizontal_line(dest_ctx, 0, 0, width, false);
        canvas.draw_horizontal_line(dest_ctx, 0, half_height, width, false);
        canvas.draw_horizontal_line(dest_ctx, 0, view_height - 1, width, false);

        canvas.draw_vertical_line(dest_ctx, 0, 0, height + 1, false);
        canvas.draw_vertical_line(dest_ctx, half_width, 0, height + 1, false);
        canvas.draw_vertical_line(dest_ctx, width - 1, 0, height + 1, false);

        dest_ctx.set_source_rgba(1.0, 1.0, 1.0, 0.33);

        canvas.draw_horizontal_line(dest_ctx, 0, quarter_height, width, false);
        canvas.draw_horizontal_line(dest_ctx, 0, half_height + quarter_height, width, false);
        canvas.draw_vertical_line(dest_ctx, quarter_width, 0, height, false);
        canvas.draw_vertical_line(dest_ctx, half_width + quarter_width, 0, height, false);
    }
}

} // end namespace
