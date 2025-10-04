// SPDX-License-Identifier: LGPL-2.1-or-later
// The PhotoCanvas is an interface object between an EditingTool and its host.  It provides objects
// and primitives for an EditingTool to obtain information about the image, to draw on the host's
// canvas, and to be signalled when the canvas and its pixbuf changes (is resized).
public abstract class EditingTools.PhotoCanvas {
    private Gtk.Window container;
    private Gdk.Surface drawing_window;
    private Photo photo;
    private Cairo.Context default_ctx;
    private Dimensions surface_dim;
    private Cairo.Surface scaled;
    private Gdk.Pixbuf scaled_pixbuf;
    private Gdk.Rectangle scaled_position;

    protected PhotoCanvas(Gtk.Window container, Gdk.Surface drawing_window, Photo photo,
        Cairo.Context default_ctx, Dimensions surface_dim, Gdk.Pixbuf scaled, Gdk.Rectangle scaled_position) {
        this.container = container;
        this.drawing_window = drawing_window;
        this.photo = photo;
        this.default_ctx = default_ctx;
        this.surface_dim = surface_dim;
        this.scaled_position = scaled_position;
        this.scaled_pixbuf = scaled;
        this.scaled = pixbuf_to_surface(default_ctx, scaled, scaled_position);
    }

    public signal void new_surface(Cairo.Context ctx, Dimensions dim);

    public signal void resized_scaled_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled,
        Gdk.Rectangle scaled_position);

    public Gdk.Rectangle unscaled_to_raw_rect(Gdk.Rectangle rectangle) {
        return photo.unscaled_to_raw_rect(rectangle);
    }

    public Gdk.Point active_to_unscaled_point(Gdk.Point active_point) {
        Gdk.Rectangle scaled_position = get_scaled_pixbuf_position();
        Dimensions unscaled_dims = photo.get_dimensions();

        double scale_factor_x = ((double) unscaled_dims.width) /
            ((double) scaled_position.width);
        double scale_factor_y = ((double) unscaled_dims.height) /
            ((double) scaled_position.height);

        Gdk.Point result = {0};
        result.x = (int)(((double) active_point.x) * scale_factor_x + 0.5);
        result.y = (int)(((double) active_point.y) * scale_factor_y + 0.5);

        return result;
    }

    public Gdk.Rectangle active_to_unscaled_rect(Gdk.Rectangle active_rect) {
        Gdk.Point upper_left = {0};
        Gdk.Point lower_right = {0};
        upper_left.x = active_rect.x;
        upper_left.y = active_rect.y;
        lower_right.x = upper_left.x + active_rect.width;
        lower_right.y = upper_left.y + active_rect.height;

        upper_left = active_to_unscaled_point(upper_left);
        lower_right = active_to_unscaled_point(lower_right);

        Gdk.Rectangle unscaled_rect = Gdk.Rectangle();
        unscaled_rect.x = upper_left.x;
        unscaled_rect.y = upper_left.y;
        unscaled_rect.width = lower_right.x - upper_left.x;
        unscaled_rect.height = lower_right.y - upper_left.y;

        return unscaled_rect;
    }

    public Gdk.Point user_to_active_point(Gdk.Point user_point) {
        Gdk.Rectangle active_offsets = get_scaled_pixbuf_position();

        Gdk.Point result = {0};
        result.x = user_point.x - active_offsets.x;
        result.y = user_point.y - active_offsets.y;

        return result;
    }

    public Gdk.Rectangle user_to_active_rect(Gdk.Rectangle user_rect) {
        Gdk.Point upper_left = {0};
        Gdk.Point lower_right = {0};
        upper_left.x = user_rect.x;
        upper_left.y = user_rect.y;
        lower_right.x = upper_left.x + user_rect.width;
        lower_right.y = upper_left.y + user_rect.height;

        upper_left = user_to_active_point(upper_left);
        lower_right = user_to_active_point(lower_right);

        Gdk.Rectangle active_rect = Gdk.Rectangle();
        active_rect.x = upper_left.x;
        active_rect.y = upper_left.y;
        active_rect.width = lower_right.x - upper_left.x;
        active_rect.height = lower_right.y - upper_left.y;

        return active_rect;
    }

    public Photo get_photo() {
        return photo;
    }

    public Gtk.Window get_container() {
        return container;
    }

    public Gdk.Surface get_drawing_window() {
        return drawing_window;
    }

    public Cairo.Context get_default_ctx() {
        return default_ctx;
    }

    public Dimensions get_surface_dim() {
        return surface_dim;
    }

    public Scaling get_scaling() {
        return Scaling.for_viewport(surface_dim, false);
    }

    public void set_surface(Cairo.Context default_ctx, Dimensions surface_dim) {
        this.default_ctx = default_ctx;
        this.surface_dim = surface_dim;

        new_surface(default_ctx, surface_dim);
    }

    public Cairo.Surface get_scaled_surface() {
        return scaled;
    }

    public Gdk.Pixbuf get_scaled_pixbuf() {
        return scaled_pixbuf;
    }

    public Gdk.Rectangle get_scaled_pixbuf_position() {
        return scaled_position;
    }

    public void resized_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled, Gdk.Rectangle scaled_position) {
        this.scaled = pixbuf_to_surface(default_ctx, scaled, scaled_position);
        this.scaled_pixbuf = scaled;
        this.scaled_position = scaled_position;

        resized_scaled_pixbuf(old_dim, scaled, scaled_position);
    }

    public abstract void repaint();

    // Because the editing tool should not have any need to draw on the gutters outside the photo,
    // and it's a pain to constantly calculate where it's laid out on the drawable, these convenience
    // methods automatically adjust for its position.
    //
    // If these methods are not used, all painting to the drawable should be offset by
    // get_scaled_pixbuf_position().x and get_scaled_pixbuf_position().y
    public void paint_pixbuf(Gdk.Pixbuf pixbuf) {
        default_ctx.save();

        // paint black background
        set_source_color_from_string(default_ctx, "#000");
        default_ctx.rectangle(0, 0, surface_dim.width, surface_dim.height);
        default_ctx.fill();

        // paint the actual image
        paint_pixmap_with_background(default_ctx, pixbuf, scaled_position.x, scaled_position.y);
        default_ctx.restore();
    }

    // Paint a surface on top of the photo
    public void paint_surface(Cairo.Surface surface, bool over) {
        default_ctx.save();
        if (over == false)
            default_ctx.set_operator(Cairo.Operator.SOURCE);
        else
            default_ctx.set_operator(Cairo.Operator.OVER);

        default_ctx.set_source_surface(scaled, scaled_position.x, scaled_position.y);
        default_ctx.paint();
        default_ctx.set_source_surface(surface, scaled_position.x, scaled_position.y);
        default_ctx.paint();
        default_ctx.restore();
    }

    public void paint_surface_area(Cairo.Surface surface, Box source_area, bool over) {
        default_ctx.save();
        if (over == false)
            default_ctx.set_operator(Cairo.Operator.SOURCE);
        else
            default_ctx.set_operator(Cairo.Operator.OVER);

        default_ctx.set_source_surface(scaled, scaled_position.x, scaled_position.y);
        default_ctx.rectangle(scaled_position.x + source_area.left,
            scaled_position.y + source_area.top,
            source_area.get_width(), source_area.get_height());
        default_ctx.fill();

        default_ctx.set_source_surface(surface, scaled_position.x, scaled_position.y);
        default_ctx.rectangle(scaled_position.x + source_area.left,
            scaled_position.y + source_area.top,
            source_area.get_width(), source_area.get_height());
        default_ctx.fill();
        default_ctx.restore();
    }

    public void draw_box(Cairo.Context ctx, Box box) {
        Gdk.Rectangle rect = box.get_rectangle();
        rect.x += scaled_position.x;
        rect.y += scaled_position.y;

        ctx.rectangle(rect.x + 0.5, rect.y + 0.5, rect.width - 1, rect.height - 1);
        ctx.stroke();
    }

     public void draw_text(Cairo.Context ctx, string text, int x, int y, bool use_scaled_pos = true) {
        if (use_scaled_pos) {
            x += scaled_position.x;
            y += scaled_position.y;
        }
        Cairo.TextExtents extents;
        ctx.text_extents(text, out extents);
        x -= (int) extents.width / 2;
        
        set_source_color_from_string(ctx, Resources.ONIMAGE_FONT_BACKGROUND);
        
        int pane_border = 5; // border around edge of pane in pixels
        ctx.rectangle(x - pane_border, y - pane_border - extents.height, 
            extents.width + 2 * pane_border, 
            extents.height + 2 * pane_border);
        ctx.fill();
        
        ctx.move_to(x, y);
        set_source_color_from_string(ctx, Resources.ONIMAGE_FONT_COLOR);
        ctx.show_text(text);
    }

    /**
     * Draw a horizontal line into the specified Cairo context at the specified position, taking
     * into account the scaled position of the image unless directed otherwise.
     *
     * @param ctx The drawing context of the surface we're drawing to.
     * @param x The horizontal position to place the line at.
     * @param y The vertical position to place the line at.
     * @param width The length of the line.
     * @param use_scaled_pos Whether to use absolute window positioning or take into account the 
     *      position of the scaled image.
     */
    public void draw_horizontal_line(Cairo.Context ctx, int x, int y, int width, bool use_scaled_pos = true) {
        if (use_scaled_pos) {
            x += scaled_position.x;
            y += scaled_position.y;
        }

        ctx.move_to(x + 0.5, y + 0.5);
        ctx.line_to(x + width - 1, y + 0.5);
        ctx.stroke();
    }

    /**
     * Draw a vertical line into the specified Cairo context at the specified position, taking
     * into account the scaled position of the image unless directed otherwise.
     *
     * @param ctx The drawing context of the surface we're drawing to.
     * @param x The horizontal position to place the line at.
     * @param y The vertical position to place the line at.
     * @param width The length of the line.
     * @param use_scaled_pos Whether to use absolute window positioning or take into account the 
     *      position of the scaled image.
     */
    public void draw_vertical_line(Cairo.Context ctx, int x, int y, int height, bool use_scaled_pos = true) {
        if (use_scaled_pos) {
            x += scaled_position.x;
            y += scaled_position.y;
        }

        ctx.move_to(x + 0.5, y + 0.5);
        ctx.line_to(x + 0.5, y + height - 1);
        ctx.stroke();
    }

    public void erase_horizontal_line(int x, int y, int width) {
        var scale = Application.get_scale();
        default_ctx.save();

        default_ctx.set_operator(Cairo.Operator.SOURCE);
        default_ctx.set_source_surface(scaled, scaled_position.x, scaled_position.y);
        default_ctx.rectangle(scaled_position.x + x, scaled_position.y + y,
            width - 1, 1 * scale);
        default_ctx.fill();

        default_ctx.restore();
    }

    public void draw_circle(Cairo.Context ctx, int active_center_x, int active_center_y,
        int radius) {
        int center_x = active_center_x + scaled_position.x;
        int center_y = active_center_y + scaled_position.y;

        ctx.arc(center_x, center_y, radius, 0, 2 * GLib.Math.PI);
        ctx.stroke();
    }

    public void erase_vertical_line(int x, int y, int height) {
        default_ctx.save();

        var scale = Application.get_scale();

        // Ticket #3146 - artifacting when moving the crop box or
        // enlarging it from the lower right.
        // We now no longer subtract one from the height before choosing
        // a region to erase.
        default_ctx.set_operator(Cairo.Operator.SOURCE);
        default_ctx.set_source_surface(scaled, scaled_position.x, scaled_position.y);
        default_ctx.rectangle(scaled_position.x + x, scaled_position.y + y,
            1 * scale, height);
        default_ctx.fill();

        default_ctx.restore();
    }

    public void erase_box(Box box) {
        erase_horizontal_line(box.left, box.top, box.get_width());
        erase_horizontal_line(box.left, box.bottom, box.get_width());

        erase_vertical_line(box.left, box.top, box.get_height());
        erase_vertical_line(box.right, box.top, box.get_height());
    }

    public void invalidate_area(Box area) {
        Gdk.Rectangle rect = area.get_rectangle();

        rect.x += scaled_position.x;
        rect.y += scaled_position.y;

       container.queue_draw();
    }

    public void set_cursor(string? cursor_type) {
        get_container().set_cursor_from_name(cursor_type);
    }

    private Cairo.Surface pixbuf_to_surface(Cairo.Context default_ctx, Gdk.Pixbuf pixbuf,
        Gdk.Rectangle pos) {
        Cairo.Surface surface = new Cairo.Surface.similar(default_ctx.get_target(),
            Cairo.Content.COLOR_ALPHA, pos.width, pos.height);
        Cairo.Context ctx = new Cairo.Context(surface);
        paint_pixmap_with_background(ctx, pixbuf, 0, 0);
        ctx.paint();
        return surface;
    }
}
