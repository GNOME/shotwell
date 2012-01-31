
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
    private const double INCREMENT = 0.05;
    private const int MIN_SLIDER_SIZE = 250;
    private const int TEMP_PIXBUF_SIZE = 640;

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

    private StraightenTool() {
    }

    public static StraightenTool factory() {
        return new StraightenTool();
    }

    private void on_ok_clicked() {
        assert(canvas.get_photo() != null);
        canvas.get_photo().set_straighten(window.angle_slider.get_value());
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
     * Spawn the tool window, set up the scratch surfaces and prepare the straightening
     * tool for use.  If a valid pixbuf of the incoming Photo can't be loaded for any
     * reason, the tool will use a 1x1 temporary image instead to avoid crashing.
     *
     * @param canvas The PhotoCanvas the tool's output should be painted to.
     */
    public override void activate(PhotoCanvas canvas) {
        Gdk.Pixbuf? low_res_tmp = null;

        base.activate(canvas);
        this.canvas = canvas;

        // fetch what the image currently looks like, scaled to fit the preview size.
        try {
            low_res_tmp =
                canvas.get_photo().get_pixbuf_with_options(Scaling.for_best_fit(TEMP_PIXBUF_SIZE, true),
                    Photo.Exception.STRAIGHTEN);
        } catch (Error e) {
            warning("A pixbuf for %s couldn't be fetched.", canvas.get_photo().to_string());
            low_res_tmp = new Gdk.Pixbuf(Gdk.Colorspace.RGB, false, 8, 1, 1);
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
        rotate_surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, low_res_tmp.width, low_res_tmp.height);
        rotate_ctx = new Cairo.Context(rotate_surf);

        photo_width = low_res_tmp.width;
        photo_height = low_res_tmp.height;

        window = new StraightenToolWindow(canvas.get_container());

        bind_window_handlers();

        // read the photo's current angle and start the tool
        // with the slider set to that value.
        double incoming_angle = 0.0;
        canvas.get_photo().get_straighten(out incoming_angle);

        window.angle_slider.set_value(incoming_angle);
        photo_angle = incoming_angle;

        string tmp = "%2.0f°".printf(incoming_angle);
        window.angle_label.set_text(tmp);

        window.show_all();
    }

    public override void deactivate() {
        if(window != null) {

            unbind_window_handlers();

            window.hide();
            window = null;
        }
        base.deactivate();
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
        string tmp = "%2.0f°".printf(window.angle_slider.get_value());
        window.angle_label.set_text(tmp);

        use_high_qual = false;

        this.canvas.repaint();
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

        // rotate the image, taking into account that both the scale of
        // the image and the position of the upper left corner must change
        // to properly zoom in on the center.

        dest_ctx.identity_matrix();

        dest_ctx.translate(src_width / 2.0f, src_height / 2.0f);
        dest_ctx.rotate(angle_internal);

        double shrink_factor = compute_shrink_factor(src_width, src_height, angle);
        dest_ctx.scale(shrink_factor, shrink_factor);

        dest_ctx.translate(-photo_width / 2.0f, -photo_height / 2.0f);

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
