/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public abstract class SinglePhotoPage : Page {
    public const Gdk.InterpType FAST_INTERP = Gdk.InterpType.NEAREST;
    public const Gdk.InterpType QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    public const int KEY_REPEAT_INTERVAL_MSEC = 200;

    public enum UpdateReason {
        NEW_PIXBUF,
        QUALITY_IMPROVEMENT,
        RESIZED_CANVAS
    }

    protected Gtk.DrawingArea canvas = new Gtk.DrawingArea();
    //protected Gtk.Viewport viewport = new Gtk.Viewport(null, null);

    private bool scale_up_to_viewport;
    private TransitionClock transition_clock;
    private int transition_duration_msec = 0;
    private Cairo.Surface pixmap = null;
    private Cairo.Context pixmap_ctx = null;
    private Cairo.Context text_ctx = null;
    private Dimensions pixmap_dim = Dimensions();
    private Gdk.Pixbuf unscaled = null;
    private Dimensions max_dim = Dimensions();
    private Gdk.Pixbuf scaled = null;
    private Gdk.Pixbuf old_scaled = null; // previous scaled image
    private Gdk.Rectangle scaled_pos = Gdk.Rectangle();
    private ZoomState static_zoom_state;
    private bool zoom_high_quality = true;
    private ZoomState saved_zoom_state;
    private bool has_saved_zoom_state = false;
    private uint32 last_nav_key = 0;

    protected SinglePhotoPage(string page_name, bool scale_up_to_viewport) {
        base(page_name);

        this.scale_up_to_viewport = scale_up_to_viewport;

        transition_clock = TransitionEffectsManager.get_instance().create_null_transition_clock();

        // With the current code automatically resizing the image to the viewport, scrollbars
        // should never be shown, but this may change if/when zooming is supported
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        scrolled.set_child(canvas);

        scrolled.notify["default-width"].connect(on_viewport_resize);
        scrolled.notify["default-height"].connect(on_viewport_resize);
        scrolled.notify["maximized"].connect(on_viewport_resize);

        canvas.resize.connect(on_viewport_resize);
        canvas.set_draw_func(on_canvas_exposed);
        canvas.set_name ("SinglePhoto drawing");
        set_event_source(canvas);
        Config.Facade.get_instance().colors_changed.connect(on_colors_changed);

        var key = new Gtk.EventControllerKey();
        key.key_pressed.connect(key_press_event);
        add_controller(key);
    }

    ~SinglePhotoPage() {
        Config.Facade.get_instance().colors_changed.disconnect(on_colors_changed);
    }

    public bool is_transition_in_progress() {
        return transition_clock.is_in_progress();
    }

    public void cancel_transition() {
        if (transition_clock.is_in_progress())
            transition_clock.cancel();
    }

    public void set_transition(string effect_id, int duration_msec) {
        cancel_transition();

        transition_clock = TransitionEffectsManager.get_instance().create_transition_clock(effect_id);
        if (transition_clock == null)
            transition_clock = TransitionEffectsManager.get_instance().create_null_transition_clock();

        transition_duration_msec = duration_msec;
    }

    // This method includes a call to pixmap_ctx.paint().
    private void render_zoomed_to_pixmap(ZoomState zoom_state) {
        assert(is_zoom_supported());

        Gdk.Rectangle view_rect = zoom_state.get_viewing_rectangle_wrt_content();

        Gdk.Pixbuf zoomed;
        if (get_zoom_buffer() != null) {
            zoomed = (zoom_high_quality) ? get_zoom_buffer().get_zoomed_image(zoom_state) :
                get_zoom_buffer().get_zoom_preview_image(zoom_state);
        } else {
            Gdk.Rectangle view_rect_proj = zoom_state.get_viewing_rectangle_projection(unscaled);

            Gdk.Pixbuf proj_subpixbuf = new Gdk.Pixbuf.subpixbuf(unscaled, view_rect_proj.x,
                view_rect_proj.y, view_rect_proj.width, view_rect_proj.height);

            zoomed = proj_subpixbuf.scale_simple(view_rect.width, view_rect.height,
                Gdk.InterpType.BILINEAR);
        }

        if (zoomed == null) {
            return;
        }

        int draw_x = (pixmap_dim.width - view_rect.width) / 2;
        draw_x = draw_x.clamp(0, int.MAX);

        int draw_y = (pixmap_dim.height - view_rect.height) / 2;
        draw_y = draw_y.clamp(0, int.MAX);
        paint_pixmap_with_background(pixmap_ctx, zoomed, draw_x, draw_y);
    }

    protected void on_interactive_zoom(ZoomState interactive_zoom_state) {
        assert(is_zoom_supported());

        set_source_color_from_string(pixmap_ctx, "#000");
        pixmap_ctx.paint();

        bool old_quality_setting = zoom_high_quality;
        zoom_high_quality = false;
        render_zoomed_to_pixmap(interactive_zoom_state);
        zoom_high_quality = old_quality_setting;

        canvas.queue_draw();
    }

    protected void on_interactive_pan(ZoomState interactive_zoom_state) {
        assert(is_zoom_supported());

        set_source_color_from_string(pixmap_ctx, "#000");
        pixmap_ctx.paint();

        bool old_quality_setting = zoom_high_quality;
        zoom_high_quality = true;
        render_zoomed_to_pixmap(interactive_zoom_state);
        zoom_high_quality = old_quality_setting;

        canvas.queue_draw();
    }

    protected virtual bool is_zoom_supported() {
        return false;
    }

    protected virtual void cancel_zoom() {
        if (pixmap != null) {
            set_source_color_from_string(pixmap_ctx, "#000");
            pixmap_ctx.paint();
        }
    }

    protected virtual void save_zoom_state() {
        saved_zoom_state = static_zoom_state;
        has_saved_zoom_state = true;
    }

    protected virtual void restore_zoom_state() {
        if (!has_saved_zoom_state)
            return;

        static_zoom_state = saved_zoom_state;
        repaint();
        has_saved_zoom_state = false;
    }

    protected virtual ZoomBuffer? get_zoom_buffer() {
        return null;
    }

    protected ZoomState get_saved_zoom_state() {
        return saved_zoom_state;
    }

    protected void set_zoom_state(ZoomState zoom_state) {
        assert(is_zoom_supported());

        static_zoom_state = zoom_state;
    }

    protected ZoomState get_zoom_state() {
        assert(is_zoom_supported());

        return static_zoom_state;
    }

    public override void switched_to() {
        base.switched_to();

        if (unscaled != null)
            repaint();
    }

    public override void set_container(Gtk.Window container) {
        base.set_container(container);

        // scrollbar policy in fullscreen mode needs to be auto/auto, else the pixbuf will shift
        // off the screen
        if (container is FullscreenWindow)
            scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
    }

    // max_dim represents the maximum size of the original pixbuf (i.e. pixbuf may be scaled and
    // the caller capable of producing larger ones depending on the viewport size).  max_dim
    // is used when scale_up_to_viewport is set to true.  Pass a Dimensions with no area if
    // max_dim should be ignored (i.e. scale_up_to_viewport is false).
    public void set_pixbuf(Gdk.Pixbuf unscaled, Dimensions max_dim, Direction? direction = null) {
        static_zoom_state = ZoomState(max_dim, pixmap_dim,
            static_zoom_state.get_interpolation_factor(),
            static_zoom_state.get_viewport_center());

        cancel_transition();

        this.unscaled = unscaled;
        this.max_dim = max_dim;
        this.old_scaled = scaled;
        scaled = null;

        // need to make sure this has happened
        canvas.realize();

        repaint(direction);
    }

    public void blank_display() {
        unscaled = null;
        max_dim = Dimensions();
        scaled = null;
        pixmap = null;

        // this has to have happened
        canvas.realize();

        // force a redraw
        invalidate_all();
    }

    public Cairo.Surface? get_surface() {
        return pixmap;
    }

    public Dimensions get_surface_dim() {
        return pixmap_dim;
    }

    public Cairo.Context get_cairo_context() {
        return pixmap_ctx;
    }

    public void paint_text(Pango.Layout pango_layout, int x, int y) {
        text_ctx.move_to(x, y);
        Pango.cairo_show_layout(text_ctx, pango_layout);
    }

    public Scaling get_canvas_scaling() {
        return (get_container() is FullscreenWindow) ? Scaling.for_screen(AppWindow.get_instance(), scale_up_to_viewport)
            : Scaling.for_widget(scrolled, scale_up_to_viewport);
    }

    public Gdk.Pixbuf? get_unscaled_pixbuf() {
        return unscaled;
    }

    public Gdk.Pixbuf? get_scaled_pixbuf() {
        return scaled;
    }

    // Returns a rectangle describing the pixbuf in relation to the canvas
    public Gdk.Rectangle get_scaled_pixbuf_position() {
        return scaled_pos;
    }

    public bool is_inside_pixbuf(int x, int y) {
        return coord_in_rectangle((int)Math.lround(x * Application.get_scale()),
        (int)Math.lround(y * Application.get_scale()), scaled_pos);
    }

    public void invalidate(Gdk.Rectangle rect) {
        queue_draw();
    }

    public void invalidate_all() {
        canvas.queue_draw();
    }

    private void on_viewport_resize() {
        print("Viewport resized!");
        // do fast repaints while resizing
        internal_repaint(true, null);
    }

    protected override void on_resize_finished(Gdk.Rectangle rect) {
        base.on_resize_finished(rect);

        // when the resize is completed, do a high-quality repaint
        repaint();
    }

    private void on_canvas_exposed(Gtk.DrawingArea da, Cairo.Context exposed_ctx, int width, int height) {
        // draw pixmap onto canvas unless it's not been instantiated, in which case draw black
        // (so either old image or contents of another page is not left on screen)
        if (pixmap != null) {
            pixmap.set_device_scale(Application.get_scale(), Application.get_scale());
            exposed_ctx.set_source_surface(pixmap, 0, 0);
        }
        else
            set_source_color_from_string(exposed_ctx, "#000");

        exposed_ctx.rectangle(0, 0, get_allocated_width(), get_allocated_height());
        exposed_ctx.paint();
    }

    protected virtual void new_surface(Cairo.Context ctx, Dimensions ctx_dim) {}

    protected virtual void updated_pixbuf(Gdk.Pixbuf pixbuf, UpdateReason reason, Dimensions old_dim) {}

    protected virtual void paint(Cairo.Context ctx, Dimensions ctx_dim) {
        if (is_zoom_supported() && (!static_zoom_state.is_default())) {
            set_source_color_from_string(ctx, "#000");
            ctx.rectangle(0, 0, pixmap_dim.width, pixmap_dim.height);
            ctx.fill();

            render_zoomed_to_pixmap(static_zoom_state);
        } else if (!transition_clock.paint(ctx, ctx_dim.width, ctx_dim.height)) {
            // transition is not running, so paint the full image on a black background
            set_source_color_from_string(ctx, "#000");

            ctx.rectangle(0, 0, pixmap_dim.width, pixmap_dim.height);
            ctx.fill();

            //scaled.save("src%010d.png".printf(buffer_counter), "png");
            paint_pixmap_with_background(ctx, scaled, scaled_pos.x, scaled_pos.y);
            //pixmap.write_to_png("%010d.png".printf(buffer_counter++));
        }
    }

    private void repaint_pixmap() {
        if (pixmap_ctx == null)
            return;

        paint(pixmap_ctx, pixmap_dim);
        invalidate_all();
    }

    public void repaint(Direction? direction = null) {
        internal_repaint(false, direction);
    }

    private void internal_repaint(bool fast, Direction? direction) {
        // if not in view, assume a full repaint needed in future but do nothing more
        if (!is_in_view()) {
            pixmap = null;
            scaled = null;

            return;
        }

        // no image or window, no painting
        if (unscaled == null /*|| canvas.get_window() == null*/)
            return;

        Gtk.Allocation allocation;
        scrolled.get_allocation(out allocation);

        int width = allocation.width;
        int height = allocation.height;

        if (width <= 0 || height <= 0)
            return;

        bool new_pixbuf = (scaled == null);

        // save if reporting an image being rescaled
        Dimensions old_scaled_dim = Dimensions.for_rectangle(scaled_pos);

        Gdk.Rectangle old_scaled_pos = scaled_pos;

        // attempt to reuse pixmap
        if (pixmap_dim.width != width || pixmap_dim.height != height)
            pixmap = null;

        // if necessary, create a pixmap as large as the entire viewport
        bool new_pixmap = false;
        if (pixmap == null) {
            init_pixmap((int)Math.lround(width * Application.get_scale()), (int)Math.lround(height * Application.get_scale()));
            new_pixmap = true;
        }

        if (new_pixbuf || new_pixmap) {
            Dimensions unscaled_dim = Dimensions.for_pixbuf(unscaled);

            // determine scaled size of pixbuf ... if a max dimensions is set and not scaling up,
            // respect it
            Dimensions scaled_dim = Dimensions();
            if (!scale_up_to_viewport && max_dim.has_area() && max_dim.width < width && max_dim.height < height)
                scaled_dim = max_dim;
            else
                scaled_dim = unscaled_dim.get_scaled_proportional(pixmap_dim);

            // center pixbuf on the canvas
            scaled_pos.x = (int)Math.lround(((width * Application.get_scale()) - scaled_dim.width) / 2.0);
            scaled_pos.y = (int)Math.lround(((height * Application.get_scale()) - scaled_dim.height) / 2.0);
            scaled_pos.width = scaled_dim.width;
            scaled_pos.height = scaled_dim.height;
        }

        Gdk.InterpType interp = (fast) ? FAST_INTERP : QUALITY_INTERP;

        // rescale if canvas rescaled or better quality is requested
        if (scaled == null) {
            scaled = resize_pixbuf(unscaled, Dimensions.for_rectangle(scaled_pos), interp);

            UpdateReason reason = UpdateReason.RESIZED_CANVAS;
            if (new_pixbuf)
                reason = UpdateReason.NEW_PIXBUF;
            else if (!new_pixmap && interp == QUALITY_INTERP)
                reason = UpdateReason.QUALITY_IMPROVEMENT;

            static_zoom_state = ZoomState(max_dim, pixmap_dim,
                static_zoom_state.get_interpolation_factor(),
                static_zoom_state.get_viewport_center());

            updated_pixbuf(scaled, reason, old_scaled_dim);
        }

        zoom_high_quality = !fast;

        if (direction != null && !transition_clock.is_in_progress()) {
            Spit.Transitions.Visuals visuals = new Spit.Transitions.Visuals(old_scaled,
                old_scaled_pos, scaled, scaled_pos, parse_color("#000"));

            transition_clock.start(visuals, direction.to_transition_direction(), transition_duration_msec,
                repaint_pixmap);
        }

        if (!transition_clock.is_in_progress())
            repaint_pixmap();
    }

    private void init_pixmap(int width, int height) {
        assert(unscaled != null);
        // assert(canvas.get_window() != null);

        // Cairo backing surface (manual double-buffering)
        pixmap = new Cairo.ImageSurface(Cairo.Format.ARGB32, width, height);
        pixmap_dim = Dimensions(width, height);

        // Cairo context for drawing on the pixmap
        pixmap_ctx = new Cairo.Context(pixmap);

        // need a new pixbuf to fit this scale
        scaled = null;

        // Cairo context for drawing text on the pixmap
        text_ctx = new Cairo.Context(pixmap);
        set_source_color_from_string(text_ctx, "#fff");


        // no need to resize canvas, viewport does that automatically

        new_surface(pixmap_ctx, pixmap_dim);
    }

    protected override bool on_context_keypress() {
        // return popup_context_menu(get_page_context_menu());
        return false;
    }

    protected virtual void on_previous_photo() {}

    protected virtual void on_next_photo() {}

    public virtual bool key_press_event(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        // if the user holds the arrow keys down, we will receive a steady stream of key press
        // events for an operation that isn't designed for a rapid succession of output ...
        // we staunch the supply of new photos to under a quarter second (#533)
        bool nav_ok = (event.get_current_event_time() - last_nav_key) > KEY_REPEAT_INTERVAL_MSEC;

        bool handled = true;
        switch (Gdk.keyval_name(keyval)) {
            case "Left":
            case "KP_Left":
            case "BackSpace":
                if (nav_ok) {
                    on_previous_photo();
                    last_nav_key = event.get_current_event_time();
                }
            break;

            case "Right":
            case "KP_Right":
            case "space":
                if (nav_ok) {
                    on_next_photo();
                    last_nav_key = event.get_current_event_time();
                }
            break;

            default:
                handled = false;
            break;
        }

        return handled;
    }

    private void on_colors_changed() {
        invalidate_transparent_background();
        repaint();
    }
}


