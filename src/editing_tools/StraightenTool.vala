
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

            Gtk.HBox slider_layout = new Gtk.HBox(false, CONTROL_SPACING);
            slider_layout.add(angle_slider);

            Gtk.HBox button_layout = new Gtk.HBox(false, CONTROL_SPACING);
            button_layout.add(cancel_button);
            button_layout.add(reset_button);
            button_layout.add(ok_button);

            Gtk.HBox main_layout = new Gtk.HBox(false, 0);
            main_layout.add(description_label);
            main_layout.add(slider_layout);
            main_layout.add(angle_label);
            main_layout.add(button_layout);

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

    // temporary surface we'll draw the rotated image into.
    private Cairo.Surface rotate_surf;
    private Cairo.Context rotate_ctx;

    private int photo_width;
    private int photo_height;
    private double photo_angle = 0.0;

    // should we use a nicer-but-more-expensive filter
    // when repainting the rotated image?
    bool use_high_qual = false;

    // the current crop region, along with a scaled version
    // for use in the preview. depending on how the image is
    // angled, we may have to set this to force the corners
    // of the crop region to stay inside the image.
    private Box crop_region;
    private Gdk.Point crop_region_center;
    private Box preview_crop_region;

    private double offset_x = 0;
    private double offset_y = 0;

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

        Gdk.Point new_crop_center = Gdk.Point();

        Dimensions dim_tmp = canvas.get_photo().get_dimensions(
            Photo.Exception.STRAIGHTEN | Photo.Exception.CROP);

        new_crop_center = rotate_point_arb(crop_region_center, dim_tmp.width, dim_tmp.height,
            slider_val);

        int crop_width = crop_region.get_width();
        int crop_height = crop_region.get_height();

        crop_region.left = new_crop_center.x - (crop_width / 2);
        crop_region.right = new_crop_center.x + (crop_width / 2);

        crop_region.top = new_crop_center.y - (crop_height / 2);
        crop_region.bottom = new_crop_center.y + (crop_height / 2);

        // set the new photo angle
        canvas.get_photo().set_straighten(slider_val);

        // set the new photo crop
        canvas.get_photo().set_crop(crop_region);

        // prevent weird bugs with undo; the following line should
        // be removed once #4475 has been implemented.
        AppWindow.get_command_manager().reset();

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

    /**
     * @brief Spawn the tool window, set up the scratch surfaces and prepare the straightening
     * tool for use.  If a valid pixbuf of the incoming Photo can't be loaded for any
     * reason, the tool will use a 1x1 temporary image instead to avoid crashing.
     *
     * @param canvas The PhotoCanvas the tool's output should be painted to.
     */
    public override void activate(PhotoCanvas canvas) {
        Gdk.Pixbuf? low_res_tmp = null;

        base.activate(canvas);
        this.canvas = canvas;
        bind_canvas_handlers(this.canvas);

        Dimensions dim_tmp = canvas.get_photo().get_dimensions(
            Photo.Exception.STRAIGHTEN | Photo.Exception.CROP);

        if (!canvas.get_photo().get_crop(out crop_region)) {
            crop_region.left = 0;
            crop_region.right = dim_tmp.width;

            crop_region.top = 0;
            crop_region.bottom = dim_tmp.height;
        }

        // read the photo's current angle and start the tool with the slider set to that value. we
        // also use this to de-rotate the crop region
        double incoming_angle = 0.0;
        canvas.get_photo().get_straighten(out incoming_angle);

        // compute and store the current crop region, de-rotated. later, if the angle of the photo
        // has changed, we'll re-rotate it as needed and set the crop to that rotated version
        crop_region_center = Gdk.Point();

        crop_region_center.x = (int) Math.round((crop_region.left + crop_region.right) / 2.0);
        crop_region_center.y = (int) Math.round((crop_region.top + crop_region.bottom) / 2.0);

        crop_region_center = derotate_point_arb(crop_region_center, dim_tmp.width, dim_tmp.height,
            incoming_angle);

        crop_region.left = crop_region_center.x - (crop_region.get_width() >> 1);
        crop_region.right = crop_region_center.x + (crop_region_center.x - crop_region.left);

        crop_region.top = crop_region_center.y - (crop_region.get_height() >> 1);
        crop_region.bottom = crop_region_center.y + (crop_region_center.y - crop_region.top);

        // fetch what the image looks like prior to any pipeline steps, scaled to fit the preview size.
        int desired_size = (dim_tmp.width > dim_tmp.height) ? dim_tmp.width : dim_tmp.height;
        desired_size = (desired_size < TEMP_PIXBUF_SIZE) ? desired_size : TEMP_PIXBUF_SIZE;

        try {
            low_res_tmp =
                canvas.get_photo().get_pixbuf_with_options(Scaling.for_best_fit(desired_size, true),
                    Photo.Exception.STRAIGHTEN | Photo.Exception.CROP);
        } catch (Error e) {
            warning("A pixbuf for %s couldn't be fetched.", canvas.get_photo().to_string());
            low_res_tmp = new Gdk.Pixbuf(Gdk.Colorspace.RGB, false, 8, 1, 1);
        }

        // create a scaled copy of the crop region; this will determine the size of
        // the preview pixbuf, as well as the center of rotation during previewing.
        double preview_crop_scale_factor = low_res_tmp.width / (double) dim_tmp.width;

        preview_crop_region = Box();

        preview_crop_region.left = (int) Math.round(crop_region.left * preview_crop_scale_factor);
        preview_crop_region.right = (int) Math.round(crop_region.right * preview_crop_scale_factor);

        preview_crop_region.top = (int) Math.round(crop_region.top * preview_crop_scale_factor);
        preview_crop_region.bottom = (int) Math.round(crop_region.bottom * preview_crop_scale_factor);

        compute_arb_rotated_size(low_res_tmp.width, low_res_tmp.height, incoming_angle, out offset_x, out offset_y);

        if (incoming_angle > 0.0) {
            offset_x = offset_x - low_res_tmp.width;
            offset_y = 0;
        } else {
            offset_x = 0;
            offset_y = offset_y - low_res_tmp.height;
        }

        // copy image data from photo into a cairo surface.
        photo_surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, low_res_tmp.width, low_res_tmp.height);
        Cairo.Context ctx = new Cairo.Context(photo_surf);
        Gdk.cairo_set_source_pixbuf(ctx, low_res_tmp, 0, 0);
        ctx.rectangle(0, 0, low_res_tmp.width, low_res_tmp.height);
        ctx.fill();
        ctx.paint();

        // prepare rotation surface and context. we paint a rotated,
        // low-res copy of the image into it, followed by a faint grid.
        rotate_surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, preview_crop_region.get_width(),
            preview_crop_region.get_height());
        rotate_ctx = new Cairo.Context(rotate_surf);

        photo_width = preview_crop_region.get_width();
        photo_height = preview_crop_region.get_height();

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

        this.canvas.repaint();
    }

    /**
     * @brief Called by the EditingHostPage when a resize event occurs. If the paintable
     * region is less than 640 by 640, we discard the old surface and make a new one to fit it.
     */
    private void on_resized_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled, Gdk.Rectangle scaled_position) {
        Dimensions canvas_dims = canvas.get_surface_dim();
        Dimensions img_dims = canvas.get_photo().get_dimensions(
            Photo.Exception.STRAIGHTEN | Photo.Exception.CROP);
        bool need_resizing = false;

        int desired_size = (img_dims.width > img_dims.height) ? img_dims.width : img_dims.height;
        desired_size = (desired_size < TEMP_PIXBUF_SIZE) ? desired_size : TEMP_PIXBUF_SIZE;

        // paintable region is smaller than the preferred preview size?
        if ((canvas_dims.width < desired_size) || (canvas_dims.height < desired_size)) {
            need_resizing = true;
        }

        // paintable region is large enough to hold the preferred preview size, but
        // preview is too small?
        if (((canvas_dims.width >= desired_size) && (canvas_dims.height >= desired_size)) &&
            (photo_width < desired_size) && (photo_height < desired_size)) {
            need_resizing = true;
        }

        // only discard and remake the surface if we actually need to.
        if (need_resizing) {
            int scaled_size = (canvas_dims.width < canvas_dims.height) ? canvas_dims.width :
                canvas_dims.height;

            if (scaled_size > desired_size)
                scaled_size = desired_size;

            Gdk.Pixbuf low_res_tmp = null;

            try {
                low_res_tmp =
                    canvas.get_photo().get_pixbuf_with_options(Scaling.for_best_fit(scaled_size, true),
                        Photo.Exception.STRAIGHTEN | Photo.Exception.CROP);
            } catch (Error e) {
                warning("A pixbuf for %s couldn't be fetched.", canvas.get_photo().to_string());
                low_res_tmp = new Gdk.Pixbuf(Gdk.Colorspace.RGB, false, 8, 1, 1);
            }

            photo_surf = null;
            rotate_surf = null;

            // copy image data from photo into a cairo surface.
            photo_surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, low_res_tmp.width, low_res_tmp.height);
            Cairo.Context ctx = new Cairo.Context(photo_surf);
            Gdk.cairo_set_source_pixbuf(ctx, low_res_tmp, 0, 0);
            ctx.rectangle(0, 0, low_res_tmp.width, low_res_tmp.height);
            ctx.fill();
            ctx.paint();

            // prepare rotation surface and context. we paint a rotated,
            // low-res copy of the image into it, followed by a faint grid.
            rotate_surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, low_res_tmp.width, low_res_tmp.height);
            rotate_ctx = new Cairo.Context(rotate_surf);

            photo_width = low_res_tmp.width;
            photo_height = low_res_tmp.height;
        }
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
        draw_rotated_source(photo_surf, rotate_ctx, photo_width, photo_height, photo_angle);
        draw_superimposed_grid(rotate_ctx, photo_width, photo_height);

        // fill region behind the rotation surface with neutral color.
        canvas.get_default_ctx().identity_matrix();
        canvas.get_default_ctx().set_source_rgba(0.0, 0.0, 0.0, 1.0);
        canvas.get_default_ctx().rectangle(0, 0, w, h);
        canvas.get_default_ctx().fill();

        // copy the composited result to the main window.
        canvas.get_default_ctx().translate((w - photo_width) / 2.0, (h - photo_height) / 2.0);
        canvas.get_default_ctx().set_source_surface(rotate_surf, 0, 0);
        canvas.get_default_ctx().rectangle(0, 0, photo_width, photo_height);
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
        dest_ctx.rectangle(0, 0, preview_crop_region.get_width(), preview_crop_region.get_height());
        dest_ctx.fill();

        // rotate the image, taking into account that the position of the
        // upper left corner must change depending on rotation amount and direction
        // and  translate so center of preview crop region is now center of rotation
        dest_ctx.identity_matrix();

        dest_ctx.translate(-preview_crop_region.left, -preview_crop_region.top);

        dest_ctx.translate((preview_crop_region.left + preview_crop_region.right) / 2.0,
            (preview_crop_region.top + preview_crop_region.bottom) / 2.0);
            
        dest_ctx.rotate(angle_internal);

        dest_ctx.translate((preview_crop_region.left + preview_crop_region.right) / -2.0,
            (preview_crop_region.top + preview_crop_region.bottom) / -2.0);

        dest_ctx.set_source_surface(src_surf, 0, 0);
        if (use_high_qual) {
            dest_ctx.get_source().set_filter(Cairo.Filter.BEST);
        } else {
            dest_ctx.get_source().set_filter(Cairo.Filter.NEAREST);
        }
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
        int half_width = width >> 1;
        int quarter_width = width >> 2;

        int half_height = height >> 1;
        int quarter_height = height >> 2;

        dest_ctx.identity_matrix();
        dest_ctx.set_source_rgba(1.0, 1.0, 1.0, 1.0);

        canvas.draw_horizontal_line(dest_ctx, 0, 0, width, false);
        canvas.draw_horizontal_line(dest_ctx, 0, half_height, width, false);
        canvas.draw_horizontal_line(dest_ctx, 0, photo_height, width, false);

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
