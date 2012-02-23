
/* Copyright 2009-2011 Yorba Foundation
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
    private const int MIN_SLIDER_SIZE = 250;
    private const int TEMP_PIXBUF_SIZE = 768;
    
    private class StraightenToolWindow : EditingToolWindow {
        public const int CONTROL_SPACING = 8;

        public Gtk.HScale angle_slider = new Gtk.HScale.with_range(MIN_ANGLE, MAX_ANGLE, INCREMENT);
        public Gtk.Label angle_label = new Gtk.Label("");
        public Gtk.Label description_label = new Gtk.Label(_("Angle:"));
        public Gtk.Button ok_button = new Gtk.Button.from_stock(Gtk.Stock.OK);
        public Gtk.Button cancel_button = new Gtk.Button.from_stock(Gtk.Stock.CANCEL);
        public Gtk.Button reset_button = new Gtk.Button.with_mnemonic(_("_Reset"));

        /**
         * Prepare straighten tool's window for use and initialize all its controls.
         *
         * @param container The application's main window.
         */
        public StraightenToolWindow(Gtk.Window container) {
            base(container);

            angle_slider.set_min_slider_size(MIN_SLIDER_SIZE);
            angle_slider.set_value(0.0);
            angle_slider.set_draw_value(false);

            description_label.set_padding(0,0);
            angle_label.set_padding(0,0);

            Gtk.Box slider_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            slider_layout.pack_start(angle_slider, true, true, 0);

            Gtk.Box button_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
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
    bool use_high_qual = false;

    private Gdk.Point crop_center;  // original center in image coordinates
    private int crop_width;
    private int crop_height;
    
    // As the crop box rotates, we adjust its center and/or scale it so that it fits in the image.
    private Gdk.Point rotated_center;   // in image coordinates
    private double rotate_scale;    // always <= 1.0: rotation may shrink but not grow box
    
    private double preview_scale;

    private StraightenTool() {
    }

    public static StraightenTool factory() {
        return new StraightenTool();
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
        AppWindow.get_command_manager().execute(command);            

        canvas.repaint();
        deactivate();
    }

    private void on_cancel_clicked() {
        canvas.repaint();
        deactivate();
    }

    private bool on_slider_released(Gdk.EventButton geb) {
        use_high_qual = true;
        this.canvas.repaint();
        return false;
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
        Gdk.cairo_set_source_pixbuf(ctx, low_res_tmp, 0, 0);
        ctx.rectangle(0, 0, low_res_tmp.width, low_res_tmp.height);
        ctx.fill();
        ctx.paint();

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

        window = new StraightenToolWindow(canvas.get_container());
        bind_window_handlers();

        // prepare ths slider for display
        window.angle_slider.set_value(incoming_angle);
        photo_angle = incoming_angle;

        string tmp = "%2.1f°".printf(incoming_angle);
        window.angle_label.set_text(tmp);

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
        window.ok_button.clicked.connect(on_ok_clicked);
        window.cancel_button.clicked.connect(on_cancel_clicked);
        window.angle_slider.value_changed.connect(on_angle_changed);
        window.angle_slider.button_release_event.connect(on_slider_released);
    }

    private void unbind_window_handlers() {
        window.ok_button.clicked.disconnect(on_ok_clicked);
        window.cancel_button.clicked.disconnect(on_cancel_clicked);
        window.angle_slider.value_changed.disconnect(on_angle_changed);
        window.angle_slider.button_release_event.disconnect(on_slider_released);
    }

    private void on_angle_changed() {
        photo_angle = window.angle_slider.get_value();
        string tmp = "%2.1f°".printf(window.angle_slider.get_value());
        window.angle_label.set_text(tmp);

        use_high_qual = false;

        adjust_for_rotation();
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
     * Render a smaller, rotated version of the image, with a grid superimposed over it.
     *
     * @param ctx The rendering context of a 'scratch' Cairo surface.  The tool makes its own
     *      surfaces and contexts so it can have things set up exactly like it wants them, so
     *      it's not used.
     */
    public override void paint(Cairo.Context ctx) {
        int w = canvas.get_drawing_window().get_width();
        int h = canvas.get_drawing_window().get_height();

        // draw the rotated photo and grid.
        draw_rotated_source(photo_surf, rotate_ctx, view_width, view_height, photo_angle);
        draw_superimposed_grid(rotate_ctx, view_width, view_height);

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
        canvas.draw_horizontal_line(dest_ctx, 0, view_height, width, false);

        canvas.draw_vertical_line(dest_ctx, 0, 0, height, false);
        canvas.draw_vertical_line(dest_ctx, half_width, 0, height, false);
        canvas.draw_vertical_line(dest_ctx, width, 0, height, false);

        dest_ctx.set_source_rgba(1.0, 1.0, 1.0, 0.33);

        canvas.draw_horizontal_line(dest_ctx, 0, quarter_height, width, false);
        canvas.draw_horizontal_line(dest_ctx, 0, half_height + quarter_height, width, false);
        canvas.draw_vertical_line(dest_ctx, quarter_width, 0, height, false);
        canvas.draw_vertical_line(dest_ctx, half_width + quarter_width, 0, height, false);
    }
}

} // end namespace
