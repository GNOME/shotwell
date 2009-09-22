/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class EditingToolWindow : Gtk.Window {
    private const int FRAME_BORDER = 6;

    private Gtk.Window container;
    private Gtk.Frame layout_frame = new Gtk.Frame(null);
    private bool user_moved = false;

    public EditingToolWindow(Gtk.Window container) {
        this.container = container;

        type_hint = Gdk.WindowTypeHint.TOOLBAR;
        set_transient_for(container);
        unset_flags(Gtk.WidgetFlags.CAN_FOCUS);
        set_accept_focus(false);
        set_focus_on_map(false);

        Gtk.Frame outer_frame = new Gtk.Frame(null);
        outer_frame.set_border_width(0);
        outer_frame.set_shadow_type(Gtk.ShadowType.OUT);
        
        layout_frame.set_border_width(FRAME_BORDER);
        layout_frame.set_shadow_type(Gtk.ShadowType.NONE);
        
        outer_frame.add(layout_frame);
        base.add(outer_frame);

        add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.FOCUS_CHANGE_MASK);
    }
    
    public override void add(Gtk.Widget widget) {
        layout_frame.add(widget);
    }
    
    public bool has_user_moved() {
        return user_moved;
    }

    private override bool button_press_event(Gdk.EventButton event) {
        // LMB only
        if (event.button != 1)
            return (base.button_press_event != null) ? base.button_press_event(event) : true;
        
        begin_move_drag((int) event.button, (int) event.x_root, (int) event.y_root, event.time);
        user_moved = true;
        
        return true;
    }
    
    private override void realize() {
        set_opacity(Resources.TRANSIENT_WINDOW_OPACITY);
        
        base.realize();
    }
    
    // This is necessary because some window managers (Metacity appears to be guilty of it) seem to
    // ignore the set_focus_on_map flag, and give the toolbar focus when it appears on the screen.
    // Thereafter, thanks to set_accept_focus, the toolbar will never accept it.  Because changing
    // focus inside of a focus signal is problematic, if the toolbar ever does receive
    // focus, it schedules a task to give it back to its owner.
    private override bool focus(Gtk.DirectionType direction) {
        Idle.add_full(Priority.HIGH, unsteal_focus);
        
        return true;
    }
    
    private bool unsteal_focus() {
        container.present_with_time(Gdk.CURRENT_TIME);
        
        return false;
    }
}

// The PhotoCanvas is an interface object between an EditingTool and its host.  It provides objects
// and primitives for an EditingTool to obtain information about the image, to draw on the host's
// canvas, and to be signalled when the canvas and its pixbuf changes (is resized).
public abstract class PhotoCanvas {
    private Gtk.Window container;
    private Gdk.Window drawing_window;
    private TransformablePhoto photo;
    private Gdk.GC default_gc;
    private Gdk.Drawable drawable;
    private Gdk.Pixbuf scaled;
    private Gdk.Rectangle scaled_position;
    
    public PhotoCanvas(Gtk.Window container, Gdk.Window drawing_window, TransformablePhoto photo, 
        Gdk.GC default_gc, Gdk.Drawable drawable, Gdk.Pixbuf scaled, Gdk.Rectangle scaled_position) {
        this.container = container;
        this.drawing_window = drawing_window;
        this.photo = photo;
        this.default_gc = default_gc;
        this.drawable = drawable;
        this.scaled = scaled;
        this.scaled_position = scaled_position;
    }
    
    public signal void new_drawable(Gdk.GC default_gc, Gdk.Drawable drawable);
    
    public signal void resized_scaled_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled, 
        Gdk.Rectangle scaled_position);
    
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

        Gdk.Rectangle unscaled_rect = {0};
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

        Gdk.Rectangle active_rect = {0};
        active_rect.x = upper_left.x;
        active_rect.y = upper_left.y;
        active_rect.width = lower_right.x - upper_left.x;
        active_rect.height = lower_right.y - upper_left.y;
        
        return active_rect;
    }

    public TransformablePhoto get_photo() {
        return photo;
    }
    
    public Gtk.Window get_container() {
        return container;
    }
    
    public Gdk.Window get_drawing_window() {
        return drawing_window;
    }
    
    public Gdk.GC get_default_gc() {
        return default_gc;
    }
    
    public Gdk.Drawable get_drawable() {
        return drawable;
    }
    
    public Scaling get_scaling() {
        int width, height;
        drawable.get_size(out width, out height);
        
        return Scaling.for_viewport(Dimensions(width, height));
    }
    
    public void set_drawable(Gdk.GC default_gc, Gdk.Drawable drawable) {
        this.default_gc = default_gc;
        this.drawable = drawable;
        
        new_drawable(default_gc, drawable);
    }
    
    public Gdk.Pixbuf get_scaled_pixbuf() {
        return scaled;
    }
    
    public Gdk.Rectangle get_scaled_pixbuf_position() {
        return scaled_position;
    }
    
    public void resized_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled, Gdk.Rectangle scaled_position) {
        this.scaled = scaled;
        this.scaled_position = scaled_position;
        
        resized_scaled_pixbuf(old_dim, scaled, scaled_position);
    }
    
    public abstract void repaint();
    
    // Because the editing tool should not have any need to draw on the gutters outside the photo,
    // and it's a pain to constantly calculate where it's laid out on the drawable, these convenience
    // methods automatically adjust for its position.
    //
    // If these methods are not used, all painting to the drawable should be offet by
    // get_scaled_pixbuf_position().x and get_scaled_pixbuf_position().y
    
    public void paint_pixbuf(Gdk.Pixbuf pixbuf) {
        drawable.draw_pixbuf(default_gc, pixbuf,
            0, 0,
            scaled_position.x, scaled_position.y,
            pixbuf.get_width(), pixbuf.get_height(),
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    public void paint_pixbuf_area(Gdk.Pixbuf pixbuf, Box source_area) {
        drawable.draw_pixbuf(default_gc, pixbuf,
            source_area.left, source_area.top,
            scaled_position.x + source_area.left, scaled_position.y + source_area.top,
            source_area.get_width(), source_area.get_height(),
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    public void draw_box(Gdk.GC gc, Box box) {
        Gdk.Rectangle rect = box.get_rectangle();
        rect.x += scaled_position.x;
        rect.y += scaled_position.y;
        
        // See note at gtk_drawable_draw_rectangle for info on off-by-one with unfilled rectangles
        drawable.draw_rectangle(gc, false, rect.x, rect.y, rect.width - 1, rect.height - 1);
    }
    
    public void draw_horizontal_line(Gdk.GC gc, int x, int y, int width) {
        x += scaled_position.x;
        y += scaled_position.y;
        
        Gdk.draw_line(drawable, gc, x, y, x + width - 1, y);
    }
    
    public void draw_vertical_line(Gdk.GC gc, int x, int y, int height) {
        x += scaled_position.x;
        y += scaled_position.y;
        
        Gdk.draw_line(drawable, gc, x, y, x, y + height - 1);
    }
    
    public void erase_horizontal_line(int x, int y, int width) {
        drawable.draw_pixbuf(default_gc, scaled,
            x, y,
            scaled_position.x + x, scaled_position.y + y,
            width, 1,
            Gdk.RgbDither.NORMAL, 0, 0);
    }

    public void draw_circle(Gdk.GC gc, int active_center_x, int active_center_y,
        int radius) {
        int center_x = active_center_x + get_scaled_pixbuf_position().x;
        int center_y = active_center_y + get_scaled_pixbuf_position().y;

        Gdk.Rectangle bounds = { 0 };
        bounds.x = center_x - radius;
        bounds.y = center_y - radius;
        bounds.width = 2 * radius;
        bounds.height = bounds.width;
        
        Gdk.draw_arc(get_drawable(), gc, false, bounds.x, bounds.y,
            bounds.width, bounds.height, 0, (360 * 64));
    }
    
    public void erase_vertical_line(int x, int y, int height) {
        drawable.draw_pixbuf(default_gc, scaled,
            x, y,
            scaled_position.x + x, scaled_position.y + y,
            1, height,
            Gdk.RgbDither.NORMAL, 0, 0);
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
        
        drawing_window.invalidate_rect(rect, false);
    }
}

public abstract class EditingTool {
    public PhotoCanvas canvas = null;
    
    public static delegate EditingTool Factory();

    public signal void activated();
    
    public signal void deactivated();
    
    public signal void applied(Gdk.Pixbuf? new_pixbuf, bool needs_improvement);
    
    public signal void cancelled();

    public signal void aborted();
    
    // base.activate() should always be called by an overriding member to ensure the base class
    // gets to set up and store the PhotoCanvas in the canvas member field.  More importantly,
    // the activated signal is called here, and should only be called once the tool is completely
    // initialized.
    public virtual void activate(PhotoCanvas canvas) {
        // multiple activates are not tolerated
        assert(this.canvas == null);
        
        this.canvas = canvas;
        
        activated();
    }

    // Like activate(), this should always be called from an overriding subclass.
    public virtual void deactivate() {
        // multiple deactivates are tolerated
        if (canvas == null)
            return;
        
        canvas = null;
        
        deactivated();
    }
    
    public bool is_activated() {
        return canvas != null;
    }
    
    public virtual EditingToolWindow? get_tool_window() {
        return null;
    }
    
    // This allows the EditingTool to specify which pixbuf to display during the tool's
    // operation.  Returning null means the host should use the pixbuf associated with the current
    // Photo.  Note: This will be called before activate(), primarily to display the pixbuf before
    // the tool is on the screen, and before paint_full() is hooked in.  It also means the PhotoCanvas
    // will have this pixbuf rather than one from the Photo class.
    //
    // Note this this method doesn't need to be returning the "proper" pixbuf on-the-fly (i.e.
    // a pixbuf with unsaved tool edits in it).  That can be handled in the paint() virtual method.
    public virtual Gdk.Pixbuf? get_display_pixbuf(Scaling scaling, TransformablePhoto photo) throws Error {
        return null;
    }
    
    public virtual void on_left_click(int x, int y) {
    }
    
    public virtual void on_left_released(int x, int y) {
    }
    
    public virtual void on_motion(int x, int y, Gdk.ModifierType mask) {
    }
    
    public virtual bool on_keypress(Gdk.EventKey event) {
        return false;
    }
    
    public virtual void paint(Gdk.GC gc, Gdk.Drawable drawable) {
    }
    
    // Helper function that fires the cancelled signal.  (Can be connected to other signals.)
    protected void notify_cancel() {
        cancelled();
    }
}

public class CropTool : EditingTool {
    private const double CROP_INIT_X_PCT = 0.15;
    private const double CROP_INIT_Y_PCT = 0.15;

    private const int CROP_MIN_WIDTH = 100;
    private const int CROP_MIN_HEIGHT = 100;

    private const float CROP_EXTERIOR_SATURATION = 0.00f;
    private const int CROP_EXTERIOR_RED_SHIFT = -32;
    private const int CROP_EXTERIOR_GREEN_SHIFT = -32;
    private const int CROP_EXTERIOR_BLUE_SHIFT = -32;
    private const int CROP_EXTERIOR_ALPHA_SHIFT = 0;
    
    private class CropToolWindow : EditingToolWindow {
        private const int CONTROL_SPACING = 8;
        
        public Gtk.Button apply_button = new Gtk.Button.from_stock(Gtk.STOCK_APPLY);
        public Gtk.Button cancel_button = new Gtk.Button.from_stock(Gtk.STOCK_CANCEL);

        public CropToolWindow(Gtk.Window container) {
            base(container);
            
            cancel_button.set_tooltip_text(_("Return to current photo dimensions"));
            cancel_button.set_image_position(Gtk.PositionType.LEFT);
            
            apply_button.set_tooltip_text(_("Set the crop for this photo"));
            apply_button.set_image_position(Gtk.PositionType.LEFT);

            Gtk.HBox layout = new Gtk.HBox(false, CONTROL_SPACING);
            layout.add(cancel_button);
            layout.add(apply_button);
            
            add(layout);
        }
    }

    private CropToolWindow crop_tool_window = null;
    private Gdk.Pixbuf color_shifted = null;
    private Gdk.CursorType current_cursor_type = Gdk.CursorType.ARROW;
    private BoxLocation in_manipulation = BoxLocation.OUTSIDE;
    private Gdk.GC wide_black_gc = null;
    private Gdk.GC wide_white_gc = null;
    private Gdk.GC thin_white_gc = null;

    // these are kept in absolute coordinates, not relative to photo's position on canvas
    private Box scaled_crop;
    private int last_grab_x = -1;
    private int last_grab_y = -1;
    
    private CropTool() {
    }
    
    public static CropTool factory() {
        return new CropTool();
    }
    
    public override void activate(PhotoCanvas canvas) {
        canvas.new_drawable += prepare_gc;
        canvas.resized_scaled_pixbuf += on_resized_pixbuf;

        prepare_gc(canvas.get_default_gc(), canvas.get_drawable());
        prepare_visuals(canvas.get_scaled_pixbuf());

        // create the crop tool window, where the user can apply or cancel the crop
        crop_tool_window = new CropToolWindow(canvas.get_container());
        crop_tool_window.apply_button.clicked += on_crop_apply;
        crop_tool_window.cancel_button.clicked += notify_cancel;
        
        // obtain crop dimensions and paint against the uncropped photo
        Dimensions uncropped_dim = canvas.get_photo().get_uncropped_dimensions();

        Box crop;
        if (!canvas.get_photo().get_crop(out crop)) {
            int xofs = (int) (uncropped_dim.width * CROP_INIT_X_PCT);
            int yofs = (int) (uncropped_dim.height * CROP_INIT_Y_PCT);
            
            // initialize the actual crop in absolute coordinates, not relative
            // to the photo's position on the canvas
            crop = Box(xofs, yofs, uncropped_dim.width - xofs, uncropped_dim.height - yofs);
        }
        
        // scale the crop to the scaled photo's size ... the scaled crop is maintained in
        // coordinates not relative to photo's position on canvas
        scaled_crop = crop.get_scaled_similar(uncropped_dim, 
            Dimensions.for_rectangle(canvas.get_scaled_pixbuf_position()));
        
        base.activate(canvas);
    }
    
    public override void deactivate() {
        if (crop_tool_window != null) {
            crop_tool_window.hide();
            crop_tool_window = null;
        }

        // make sure the cursor isn't set to a modify indicator
        canvas.get_drawing_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.ARROW));

        base.deactivate();
    }
    
    public override EditingToolWindow? get_tool_window() {
        return crop_tool_window;
    }
    
    public override Gdk.Pixbuf? get_display_pixbuf(Scaling scaling, TransformablePhoto photo) throws Error {
        // show the uncropped photo for editing, but return null if no crop so the current pixbuf
        // is used
        return photo.has_crop() ? photo.get_pixbuf(scaling, TransformablePhoto.Exception.CROP) : null;
    }
    
    private void prepare_gc(Gdk.GC default_gc, Gdk.Drawable drawable) {
        Gdk.GCValues gc_values = Gdk.GCValues();
        gc_values.foreground = fetch_color("#000", drawable);
        gc_values.function = Gdk.Function.COPY;
        gc_values.fill = Gdk.Fill.SOLID;
        gc_values.line_width = 1;
        gc_values.line_style = Gdk.LineStyle.SOLID;
        gc_values.cap_style = Gdk.CapStyle.BUTT;
        gc_values.join_style = Gdk.JoinStyle.MITER;

        Gdk.GCValuesMask mask = 
            Gdk.GCValuesMask.FOREGROUND
            | Gdk.GCValuesMask.FUNCTION
            | Gdk.GCValuesMask.FILL
            | Gdk.GCValuesMask.LINE_WIDTH 
            | Gdk.GCValuesMask.LINE_STYLE
            | Gdk.GCValuesMask.CAP_STYLE
            | Gdk.GCValuesMask.JOIN_STYLE;

        wide_black_gc = new Gdk.GC.with_values(drawable, gc_values, mask);
        
        gc_values.foreground = fetch_color("#FFF", drawable);
        
        wide_white_gc = new Gdk.GC.with_values(drawable, gc_values, mask);
        
        gc_values.line_width = 0;
        
        thin_white_gc = new Gdk.GC.with_values(drawable, gc_values, mask);
    }
    
    private void on_resized_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled, Gdk.Rectangle scaled_position) {
        Dimensions new_dim = Dimensions.for_pixbuf(scaled);
        Dimensions uncropped_dim = canvas.get_photo().get_uncropped_dimensions();
        
        // rescale to full crop
        Box crop = scaled_crop.get_scaled_similar(old_dim, uncropped_dim);
        
        // rescale back to new size
        scaled_crop = crop.get_scaled_similar(uncropped_dim, new_dim);

        prepare_visuals(scaled);
    }
    
    private void prepare_visuals(Gdk.Pixbuf pixbuf) {
        // create color shifted pixbuf for crop exterior
        color_shifted = pixbuf.copy();
        shift_colors(color_shifted, CROP_EXTERIOR_RED_SHIFT, CROP_EXTERIOR_GREEN_SHIFT,
            CROP_EXTERIOR_BLUE_SHIFT, CROP_EXTERIOR_ALPHA_SHIFT);
    }
    
    public override void on_left_click(int x, int y) {
        Gdk.Rectangle scaled_pixbuf_pos = canvas.get_scaled_pixbuf_position();
        
        // scaled_crop is not maintained relative to photo's position on canvas
        Box offset_scaled_crop = scaled_crop.get_offset(scaled_pixbuf_pos.x, scaled_pixbuf_pos.y);
        
        // determine where the mouse down landed and store for future events
        in_manipulation = offset_scaled_crop.approx_location(x, y);
        last_grab_x = x -= scaled_pixbuf_pos.x;
        last_grab_y = y -= scaled_pixbuf_pos.y;
        
        // repaint because the crop changes on a mouse down
        canvas.repaint();
    }
    
    public override void on_left_released(int x, int y) {
        // nothing to do if released outside of the crop box
        if (in_manipulation == BoxLocation.OUTSIDE)
            return;
        
        // end manipulation
        in_manipulation = BoxLocation.OUTSIDE;
        last_grab_x = -1;
        last_grab_y = -1;
        
        update_cursor(x, y);
        
        // repaint because crop changes when released
        canvas.repaint();
    }
    
    public override void on_motion(int x, int y, Gdk.ModifierType mask) {
        // only deal with manipulating the crop tool when click-and-dragging one of the edges
        // or the interior
        if (in_manipulation != BoxLocation.OUTSIDE)
            on_canvas_manipulation(x, y);
        
        update_cursor(x, y);
    }
    
    public override void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        // painter's algorithm: from the bottom up, starting with the color shifted portion of the
        // photo outside the crop
        canvas.paint_pixbuf(color_shifted);
        
        // paint exposed (cropped) part of pixbuf minus crop border
        canvas.paint_pixbuf_area(canvas.get_scaled_pixbuf(), scaled_crop);

        // paint crop tool last
        paint_crop_tool(scaled_crop);
    }
    
    private void on_crop_apply() {
        // up-scale scaled crop to photo's dimensions
        Box crop = scaled_crop.get_scaled_similar(
            Dimensions.for_rectangle(canvas.get_scaled_pixbuf_position()), 
            canvas.get_photo().get_uncropped_dimensions());

        // store the new crop
        canvas.get_photo().set_crop(crop);
        
        // crop the current pixbuf and offer it to the editing host
        Gdk.Pixbuf cropped = new Gdk.Pixbuf.subpixbuf(canvas.get_scaled_pixbuf(), scaled_crop.left,
            scaled_crop.top, scaled_crop.get_width(), scaled_crop.get_height());

        // signal host; we have a cropped image, but it will be scaled upward, and so a better one
        // should be fetched
        applied(cropped, true);
    }
    
    private void update_cursor(int x, int y) {
        // scaled_crop is not maintained relative to photo's position on canvas
        Gdk.Rectangle scaled_pos = canvas.get_scaled_pixbuf_position();
        Box offset_scaled_crop = scaled_crop.get_offset(scaled_pos.x, scaled_pos.y);
        
        Gdk.CursorType cursor_type = Gdk.CursorType.ARROW;
        switch (offset_scaled_crop.approx_location(x, y)) {
            case BoxLocation.LEFT_SIDE:
                cursor_type = Gdk.CursorType.LEFT_SIDE;
            break;

            case BoxLocation.TOP_SIDE:
                cursor_type = Gdk.CursorType.TOP_SIDE;
            break;

            case BoxLocation.RIGHT_SIDE:
                cursor_type = Gdk.CursorType.RIGHT_SIDE;
            break;

            case BoxLocation.BOTTOM_SIDE:
                cursor_type = Gdk.CursorType.BOTTOM_SIDE;
            break;

            case BoxLocation.TOP_LEFT:
                cursor_type = Gdk.CursorType.TOP_LEFT_CORNER;
            break;

            case BoxLocation.BOTTOM_LEFT:
                cursor_type = Gdk.CursorType.BOTTOM_LEFT_CORNER;
            break;

            case BoxLocation.TOP_RIGHT:
                cursor_type = Gdk.CursorType.TOP_RIGHT_CORNER;
            break;

            case BoxLocation.BOTTOM_RIGHT:
                cursor_type = Gdk.CursorType.BOTTOM_RIGHT_CORNER;
            break;

            case BoxLocation.INSIDE:
                cursor_type = Gdk.CursorType.FLEUR;
            break;
            
            default:
                // use Gdk.CursorType.ARROW
            break;
        }
        
        if (cursor_type != current_cursor_type) {
            Gdk.Cursor cursor = new Gdk.Cursor(cursor_type);
            canvas.get_drawing_window().set_cursor(cursor);
            current_cursor_type = cursor_type;
        }
    }

    private bool on_canvas_manipulation(int x, int y) {
        Gdk.Rectangle scaled_pos = canvas.get_scaled_pixbuf_position();
        
        // scaled_crop is maintained in coordinates non-relative to photo's position on canvas ...
        // but bound tool to photo itself
        x -= scaled_pos.x;
        if (x < 0)
            x = 0;
        else if (x >= scaled_pos.width)
            x = scaled_pos.width - 1;
        
        y -= scaled_pos.y;
        if (y < 0)
            y = 0;
        else if (y >= scaled_pos.height)
            y = scaled_pos.height - 1;
        
        // need to make manipulations outside of box structure, because its methods do sanity
        // checking
        int left = scaled_crop.left;
        int top = scaled_crop.top;
        int right = scaled_crop.right;
        int bottom = scaled_crop.bottom;

        switch (in_manipulation) {
            case BoxLocation.LEFT_SIDE:
                left = x;
            break;

            case BoxLocation.TOP_SIDE:
                top = y;
            break;

            case BoxLocation.RIGHT_SIDE:
                right = x;
            break;

            case BoxLocation.BOTTOM_SIDE:
                bottom = y;
            break;

            case BoxLocation.TOP_LEFT:
                top = y;
                left = x;
            break;

            case BoxLocation.BOTTOM_LEFT:
                bottom = y;
                left = x;
            break;

            case BoxLocation.TOP_RIGHT:
                top = y;
                right = x;
            break;

            case BoxLocation.BOTTOM_RIGHT:
                bottom = y;
                right = x;
            break;

            case BoxLocation.INSIDE:
                assert(last_grab_x >= 0);
                assert(last_grab_y >= 0);
                
                int delta_x = (x - last_grab_x);
                int delta_y = (y - last_grab_y);
                
                last_grab_x = x;
                last_grab_y = y;

                int width = right - left + 1;
                int height = bottom - top + 1;
                
                left += delta_x;
                top += delta_y;
                right += delta_x;
                bottom += delta_y;
                
                // bound crop inside of photo
                if (left < 0)
                    left = 0;
                
                if (top < 0)
                    top = 0;
                
                if (right >= scaled_pos.width)
                    right = scaled_pos.width - 1;
                
                if (bottom >= scaled_pos.height)
                    bottom = scaled_pos.height - 1;
                
                int adj_width = right - left + 1;
                int adj_height = bottom - top + 1;
                
                // don't let adjustments affect the size of the crop
                if (adj_width != width) {
                    if (delta_x < 0)
                        right = left + width - 1;
                    else
                        left = right - width + 1;
                }
                
                if (adj_height != height) {
                    if (delta_y < 0)
                        bottom = top + height - 1;
                    else
                        top = bottom - height + 1;
                }
            break;
            
            default:
                // do nothing, not even a repaint
                return false;
        }
        
        int width = right - left + 1;
        int height = bottom - top + 1;
        
        // max sure minimums are respected ... have to adjust the right value depending on what's
        // being manipulated
        switch (in_manipulation) {
            case BoxLocation.LEFT_SIDE:
            case BoxLocation.TOP_LEFT:
            case BoxLocation.BOTTOM_LEFT:
                if (width < CROP_MIN_WIDTH)
                    left = right - CROP_MIN_WIDTH;
            break;
            
            case BoxLocation.RIGHT_SIDE:
            case BoxLocation.TOP_RIGHT:
            case BoxLocation.BOTTOM_RIGHT:
                if (width < CROP_MIN_WIDTH)
                    right = left + CROP_MIN_WIDTH;
            break;

            default:
            break;
        }

        switch (in_manipulation) {
            case BoxLocation.TOP_SIDE:
            case BoxLocation.TOP_LEFT:
            case BoxLocation.TOP_RIGHT:
                if (height < CROP_MIN_HEIGHT)
                    top = bottom - CROP_MIN_HEIGHT;
            break;

            case BoxLocation.BOTTOM_SIDE:
            case BoxLocation.BOTTOM_LEFT:
            case BoxLocation.BOTTOM_RIGHT:
                if (height < CROP_MIN_HEIGHT)
                    bottom = top + CROP_MIN_HEIGHT;
            break;
            
            default:
            break;
        }
        
        Box new_crop = Box(left, top, right, bottom);
        
        if (in_manipulation != BoxLocation.INSIDE)
            crop_resized(new_crop);
        else
            crop_moved(new_crop);
        
        // load new values
        scaled_crop = new_crop;

        return false;
    }
    
    private void crop_resized(Box new_crop) {
        if(scaled_crop.equals(new_crop)) {
            // no change
            return;
        }
        
        // erase crop and rule-of-thirds lines
        erase_crop_tool(scaled_crop);
        canvas.invalidate_area(scaled_crop);
        
        Box horizontal;
        bool horizontal_enlarged;
        Box vertical;
        bool vertical_enlarged;
        BoxComplements complements = scaled_crop.resized_complements(new_crop, out horizontal,
            out horizontal_enlarged, out vertical, out vertical_enlarged);
        
        // this should never happen ... this means that the operation wasn't a resize
        assert(complements != BoxComplements.NONE);
        
        if (complements == BoxComplements.HORIZONTAL || complements == BoxComplements.BOTH) {
            Gdk.Pixbuf pb = horizontal_enlarged ? canvas.get_scaled_pixbuf() : color_shifted;
            canvas.paint_pixbuf_area(pb, horizontal);
            
            canvas.invalidate_area(horizontal);
        }
        
        if (complements == BoxComplements.VERTICAL || complements == BoxComplements.BOTH) {
            Gdk.Pixbuf pb = vertical_enlarged ? canvas.get_scaled_pixbuf() : color_shifted;
            canvas.paint_pixbuf_area(pb, vertical);
            
            canvas.invalidate_area(vertical);
        }
        
        paint_crop_tool(new_crop);
        canvas.invalidate_area(new_crop);
    }
    
    private void crop_moved(Box new_crop) {
        if (scaled_crop.equals(new_crop)) {
            // no change
            return;
        }
        
        // erase crop and rule-of-thirds lines
        erase_crop_tool(scaled_crop);
        canvas.invalidate_area(scaled_crop);
        
        Box scaled_horizontal;
        Box scaled_vertical;
        Box new_horizontal;
        Box new_vertical;
        BoxComplements complements = scaled_crop.shifted_complements(new_crop, out scaled_horizontal,
            out scaled_vertical, out new_horizontal, out new_vertical);
        
        if (complements == BoxComplements.HORIZONTAL || complements == BoxComplements.BOTH) {
            // paint in the horizontal complements appropriately
            canvas.paint_pixbuf_area(color_shifted, scaled_horizontal);
            canvas.paint_pixbuf_area(canvas.get_scaled_pixbuf(), new_horizontal);
            
            canvas.invalidate_area(scaled_horizontal);
            canvas.invalidate_area(new_horizontal);
        }
        
        if (complements == BoxComplements.VERTICAL || complements == BoxComplements.BOTH) {
            // paint in vertical complements appropriately
            canvas.paint_pixbuf_area(color_shifted, scaled_vertical);
            canvas.paint_pixbuf_area(canvas.get_scaled_pixbuf(), new_vertical);
            
            canvas.invalidate_area(scaled_vertical);
            canvas.invalidate_area(new_vertical);
        }
        
        if (complements == BoxComplements.NONE) {
            // this means the two boxes have no intersection, not that they're equal ... since
            // there's no intersection, fill in both new and old with apropriate pixbufs
            canvas.paint_pixbuf_area(color_shifted, scaled_crop);
            canvas.paint_pixbuf_area(canvas.get_scaled_pixbuf(), new_crop);
            
            canvas.invalidate_area(scaled_crop);
            canvas.invalidate_area(new_crop);
        }
        
        // paint crop in new location
        paint_crop_tool(new_crop);
        canvas.invalidate_area(new_crop);
    }

    private void paint_crop_tool(Box crop) {
        // paint rule-of-thirds lines if user is manipulating the crop
        if (in_manipulation != BoxLocation.OUTSIDE) {
            int one_third_x = crop.get_width() / 3;
            int one_third_y = crop.get_height() / 3;
            
            canvas.draw_horizontal_line(thin_white_gc, crop.left, crop.top + one_third_y, crop.get_width());
            canvas.draw_horizontal_line(thin_white_gc, crop.left, crop.top + (one_third_y * 2), crop.get_width());

            canvas.draw_vertical_line(thin_white_gc, crop.left + one_third_x, crop.top, crop.get_height());
            canvas.draw_vertical_line(thin_white_gc, crop.left + (one_third_x * 2), crop.top, crop.get_height());
        }

        // outer rectangle ... outer line in black, inner in white, corners fully black
        canvas.draw_box(wide_black_gc, crop);
        canvas.draw_box(wide_white_gc, crop.get_reduced(1));
        canvas.draw_box(wide_white_gc, crop.get_reduced(2));
    }
    
    private void erase_crop_tool(Box crop) {
        // erase rule-of-thirds lines if user is manipulating the crop
        if (in_manipulation != BoxLocation.OUTSIDE) {
            int one_third_x = crop.get_width() / 3;
            int one_third_y = crop.get_height() / 3;
            
            canvas.erase_horizontal_line(crop.left, crop.top + one_third_y, crop.get_width());
            canvas.erase_horizontal_line(crop.left, crop.top + (one_third_y * 2), crop.get_width());
            
            canvas.erase_vertical_line(crop.left + one_third_x, crop.top, crop.get_height());
            canvas.erase_vertical_line(crop.left + (one_third_x * 2), crop.top, crop.get_height());
        }

        // erase border
        canvas.erase_box(crop);
        canvas.erase_box(crop.get_reduced(1));
        canvas.erase_box(crop.get_reduced(2));
    }
}

public struct RedeyeInstance {
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
    
    public static Gdk.Rectangle to_bounds_rect(RedeyeInstance inst) {
        Gdk.Rectangle result = {0};
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

public class RedeyeTool : EditingTool {
    private class RedeyeToolWindow : EditingToolWindow {
        private const int CONTROL_SPACING = 8;

        private Gtk.Label slider_label = new Gtk.Label.with_mnemonic(_("Size:"));

        public Gtk.Button apply_button =
            new Gtk.Button.from_stock(Gtk.STOCK_APPLY);
        public Gtk.Button close_button =
            new Gtk.Button.from_stock(Gtk.STOCK_CLOSE);
        public Gtk.HScale slider = new Gtk.HScale.with_range(
            RedeyeInstance.MIN_RADIUS, RedeyeInstance.MAX_RADIUS, 1.0);
    
        public RedeyeToolWindow(Gtk.Window container) {
            base(container);
            
            slider.set_size_request(80, -1);
            slider.set_draw_value(false);

            close_button.set_tooltip_text(_("Close the red-eye tool"));
            close_button.set_image_position(Gtk.PositionType.LEFT);
            
            apply_button.set_tooltip_text(_("Remove any red-eye effects in the selected region"));
            apply_button.set_image_position(Gtk.PositionType.LEFT);

            Gtk.HBox layout = new Gtk.HBox(false, CONTROL_SPACING);
            layout.add(slider_label);
            layout.add(slider);
            layout.add(close_button);
            layout.add(apply_button);
            
            add(layout);
        }
    }
    
    private Gdk.GC thin_white_gc = null;
    private Gdk.GC wider_gray_gc = null;
    private RedeyeToolWindow redeye_tool_window = null;
    private RedeyeInstance user_interaction_instance;
    private bool is_reticle_move_in_progress = false;
    private Gdk.Point reticle_move_mouse_start_point;
    private Gdk.Point reticle_move_anchor;
    private Gdk.Cursor cached_arrow_cursor;
    private Gdk.Cursor cached_grab_cursor;
    private Gdk.Rectangle old_scaled_pixbuf_position;
    private Gdk.Pixbuf current_pixbuf = null;
    
    private RedeyeTool() {
    }
    
    public static RedeyeTool factory() {
        return new RedeyeTool();
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
    
    private void prepare_gc(Gdk.GC default_gc, Gdk.Drawable drawable) {
        Gdk.GCValues gc_values = Gdk.GCValues();
        gc_values.function = Gdk.Function.COPY;
        gc_values.fill = Gdk.Fill.SOLID;
        gc_values.line_style = Gdk.LineStyle.SOLID;
        gc_values.cap_style = Gdk.CapStyle.BUTT;
        gc_values.join_style = Gdk.JoinStyle.MITER;

        Gdk.GCValuesMask mask = 
            Gdk.GCValuesMask.FOREGROUND
            | Gdk.GCValuesMask.FUNCTION
            | Gdk.GCValuesMask.FILL
            | Gdk.GCValuesMask.LINE_WIDTH 
            | Gdk.GCValuesMask.LINE_STYLE
            | Gdk.GCValuesMask.CAP_STYLE
            | Gdk.GCValuesMask.JOIN_STYLE;

        gc_values.foreground = fetch_color("#222", drawable);
        gc_values.line_width = 1;
        wider_gray_gc = new Gdk.GC.with_values(drawable, gc_values, mask);

        gc_values.foreground = fetch_color("#FFF", drawable);
        gc_values.line_width = 1;
        thin_white_gc = new Gdk.GC.with_values(drawable, gc_values, mask);
    }
    
    private void draw_redeye_instance(RedeyeInstance inst) {
        canvas.draw_circle(wider_gray_gc, inst.center.x, inst.center.y,
            inst.radius - 1);
        canvas.draw_circle(thin_white_gc, inst.center.x, inst.center.y,
            inst.radius - 2);
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
        
        RedeyeInstance instance_unscaled =
            RedeyeInstance.from_bounds_rect(bounds_rect_unscaled);

        canvas.get_photo().add_redeye_instance(instance_unscaled);
    
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
        applied(current_pixbuf, false);
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
    }
    
    public override void activate(PhotoCanvas canvas) {
        user_interaction_instance = new_interaction_instance(canvas);

        canvas.new_drawable += prepare_gc;

        prepare_gc(canvas.get_default_gc(), canvas.get_drawable());
        
        canvas.resized_scaled_pixbuf += on_canvas_resize;
        
        old_scaled_pixbuf_position = canvas.get_scaled_pixbuf_position();
        current_pixbuf = canvas.get_scaled_pixbuf();

        redeye_tool_window = new RedeyeToolWindow(canvas.get_container());
        redeye_tool_window.slider.set_value(user_interaction_instance.radius);
        redeye_tool_window.slider.change_value += on_size_slider_adjust;
        redeye_tool_window.apply_button.clicked += on_apply;
        redeye_tool_window.close_button.clicked += on_close;

        cached_arrow_cursor = new Gdk.Cursor(Gdk.CursorType.ARROW);
        cached_grab_cursor = new Gdk.Cursor(Gdk.CursorType.FLEUR);

        base.activate(canvas);
    }
    
    public override void deactivate() {
        if (redeye_tool_window != null) {
            redeye_tool_window.hide();
            redeye_tool_window = null;
        }
 
        base.deactivate();
    }

    public override EditingToolWindow? get_tool_window() {
        return redeye_tool_window;
    }
    
    public override void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        canvas.paint_pixbuf((current_pixbuf != null) ? current_pixbuf : canvas.get_scaled_pixbuf());
        
        /* user_interaction_instance has its radius in user coords, and
           draw_redeye_instance expects active region coords */
        RedeyeInstance active_inst = user_interaction_instance;
        active_inst.center =
            canvas.user_to_active_point(user_interaction_instance.center);
        draw_redeye_instance(active_inst);
    }
    
    public override void on_left_click(int x, int y) {
        Gdk.Rectangle bounds_rect =
            RedeyeInstance.to_bounds_rect(user_interaction_instance);

        if (coord_in_rectangle(x, y, bounds_rect)) {
            is_reticle_move_in_progress = true;
            reticle_move_mouse_start_point.x = x;
            reticle_move_mouse_start_point.y = y;
            reticle_move_anchor = user_interaction_instance.center;
        }
    }
    
    public override void on_left_released(int x, int y) {
        is_reticle_move_in_progress = false;
    }
    
    public override void on_motion(int x, int y, Gdk.ModifierType mask) {
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

            int delta_x = x - reticle_move_mouse_start_point.x;
            int delta_y = y - reticle_move_mouse_start_point.y;
            
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

            if (coord_in_rectangle(x, y, bounds)) {
                canvas.get_drawing_window().set_cursor(cached_grab_cursor);
            } else {
                canvas.get_drawing_window().set_cursor(cached_arrow_cursor);
            }
        }
    }
}

public class AdjustTool : EditingTool {
    const int SLIDER_WIDTH = 160;

    private class AdjustToolWindow : EditingToolWindow {
        public Gtk.HScale exposure_slider = new Gtk.HScale.with_range(
            ExposureTransformation.MIN_PARAMETER, ExposureTransformation.MAX_PARAMETER,
            1.0);
        public Gtk.HScale saturation_slider = new Gtk.HScale.with_range(
            SaturationTransformation.MIN_PARAMETER, SaturationTransformation.MAX_PARAMETER,
            1.0);
        public Gtk.HScale tint_slider = new Gtk.HScale.with_range(
            TintTransformation.MIN_PARAMETER, TintTransformation.MAX_PARAMETER, 1.0);
        public Gtk.HScale temperature_slider = new Gtk.HScale.with_range(
            TemperatureTransformation.MIN_PARAMETER, TemperatureTransformation.MAX_PARAMETER,
            1.0);
        public Gtk.HScale shadows_slider = new Gtk.HScale.with_range(
            ShadowDetailTransformation.MIN_PARAMETER, ShadowDetailTransformation.MAX_PARAMETER,
            1.0);
        public Gtk.Button apply_button =
            new Gtk.Button.from_stock(Gtk.STOCK_APPLY);
        public Gtk.Button reset_button =
            new Gtk.Button.with_label(_("Reset"));
        public Gtk.Button cancel_button =
            new Gtk.Button.from_stock(Gtk.STOCK_CANCEL);
        public RGBHistogramManipulator histogram_manipulator =
            new RGBHistogramManipulator();

        public AdjustToolWindow(Gtk.Window container) {
            base(container);

            Gtk.Table slider_organizer = new Gtk.Table(4, 2, false);
            slider_organizer.set_row_spacings(12);
            slider_organizer.set_col_spacings(12);

            Gtk.Label exposure_label = new Gtk.Label.with_mnemonic(_("Exposure:"));
            exposure_label.set_alignment(0.0f, 0.5f);
            slider_organizer.attach_defaults(exposure_label, 0, 1, 0, 1);
            slider_organizer.attach_defaults(exposure_slider, 1, 2, 0, 1);
            exposure_slider.set_size_request(SLIDER_WIDTH, -1);
            exposure_slider.set_draw_value(false);
            exposure_slider.set_update_policy(Gtk.UpdateType.DISCONTINUOUS);

            Gtk.Label saturation_label = new Gtk.Label.with_mnemonic(_("Saturation:"));
            saturation_label.set_alignment(0.0f, 0.5f);
            slider_organizer.attach_defaults(saturation_label, 0, 1, 1, 2);
            slider_organizer.attach_defaults(saturation_slider, 1, 2, 1, 2);
            saturation_slider.set_size_request(SLIDER_WIDTH, -1);
            saturation_slider.set_draw_value(false);
            saturation_slider.set_update_policy(Gtk.UpdateType.DISCONTINUOUS);

            Gtk.Label tint_label = new Gtk.Label.with_mnemonic(_("Tint:"));
            tint_label.set_alignment(0.0f, 0.5f);
            slider_organizer.attach_defaults(tint_label, 0, 1, 2, 3);
            slider_organizer.attach_defaults(tint_slider, 1, 2, 2, 3);
            tint_slider.set_size_request(SLIDER_WIDTH, -1);
            tint_slider.set_draw_value(false);
            tint_slider.set_update_policy(Gtk.UpdateType.DISCONTINUOUS);

            Gtk.Label temperature_label =
                new Gtk.Label.with_mnemonic(_("Temperature:"));
            temperature_label.set_alignment(0.0f, 0.5f);
            slider_organizer.attach_defaults(temperature_label, 0, 1, 3, 4);
            slider_organizer.attach_defaults(temperature_slider, 1, 2, 3, 4);
            temperature_slider.set_size_request(SLIDER_WIDTH, -1);
            temperature_slider.set_draw_value(false);
            temperature_slider.set_update_policy(Gtk.UpdateType.DISCONTINUOUS);

            Gtk.Label shadows_label = new Gtk.Label.with_mnemonic(_("Shadows:"));
            shadows_label.set_alignment(0.0f, 0.5f);
            slider_organizer.attach_defaults(shadows_label, 0, 1, 4, 5);
            slider_organizer.attach_defaults(shadows_slider, 1, 2, 4, 5);
            shadows_slider.set_size_request(SLIDER_WIDTH, -1);
            shadows_slider.set_draw_value(false);
            shadows_slider.set_update_policy(Gtk.UpdateType.DISCONTINUOUS);

            Gtk.HBox button_layouter = new Gtk.HBox(false, 8);
            button_layouter.set_homogeneous(true);
            button_layouter.pack_start(cancel_button, true, true, 1);
            button_layouter.pack_start(reset_button, true, true, 1);
            button_layouter.pack_start(apply_button, true, true, 1);

            Gtk.Alignment histogram_aligner = new Gtk.Alignment(0.5f, 0.0f, 0.0f, 0.0f);
            histogram_aligner.add(histogram_manipulator);

            Gtk.VBox pane_layouter = new Gtk.VBox(false, 8);
            pane_layouter.add(histogram_aligner);
            pane_layouter.add(slider_organizer);
            pane_layouter.add(button_layouter);
            pane_layouter.set_child_packing(histogram_aligner, true, true, 0, Gtk.PackType.START);

            add(pane_layouter);
        }
    }

    private AdjustToolWindow adjust_tool_window = null;
    private bool suppress_effect_redraw = false;
    private Gdk.Pixbuf draw_to_pixbuf = null;
    private Gdk.Pixbuf histogram_pixbuf = null;
    private Gdk.Pixbuf virgin_histogram_pixbuf = null;
    private PixelTransformer transformer = null;
    private PixelTransformer histogram_transformer = null;
    private PixelTransformation[] transformations =
        new PixelTransformation[SupportedAdjustments.NUM];
    private float[] fp_pixel_cache = null;
    
    private AdjustTool() {
    }
    
    public static AdjustTool factory() {
        return new AdjustTool();
    }

    public override void activate(PhotoCanvas canvas) {
        adjust_tool_window = new AdjustToolWindow(canvas.get_container());
        transformer = new PixelTransformer();
        histogram_transformer = new PixelTransformer();

        /* set up expansion */
        ExpansionTransformation expansion_trans = (ExpansionTransformation)
            canvas.get_photo().get_adjustment(SupportedAdjustments.TONE_EXPANSION);
        transformations[SupportedAdjustments.TONE_EXPANSION] = expansion_trans;
        transformer.attach_transformation(transformations[SupportedAdjustments.TONE_EXPANSION]);
        adjust_tool_window.histogram_manipulator.set_left_nub_position(
            expansion_trans.get_black_point());
        adjust_tool_window.histogram_manipulator.set_right_nub_position(
            expansion_trans.get_white_point());

        /* set up shadows */
        ShadowDetailTransformation shadows_trans = (ShadowDetailTransformation)
            canvas.get_photo().get_adjustment(SupportedAdjustments.SHADOWS);
        transformations[SupportedAdjustments.SHADOWS] = shadows_trans;
        transformer.attach_transformation(transformations[SupportedAdjustments.SHADOWS]);
        histogram_transformer.attach_transformation(transformations[SupportedAdjustments.SHADOWS]);
        adjust_tool_window.shadows_slider.set_value(shadows_trans.get_parameter());

        /* set up temperature & tint */
        TemperatureTransformation temp_trans = (TemperatureTransformation)
            canvas.get_photo().get_adjustment(SupportedAdjustments.TEMPERATURE);
        transformations[SupportedAdjustments.TEMPERATURE] = temp_trans;
        transformer.attach_transformation(transformations[SupportedAdjustments.TEMPERATURE]);
        histogram_transformer.attach_transformation(transformations[SupportedAdjustments.TEMPERATURE]);
        adjust_tool_window.temperature_slider.set_value(temp_trans.get_parameter());

        TintTransformation tint_trans = (TintTransformation)
            canvas.get_photo().get_adjustment(SupportedAdjustments.TINT);
        transformations[SupportedAdjustments.TINT] = tint_trans;
        transformer.attach_transformation(transformations[SupportedAdjustments.TINT]);
        histogram_transformer.attach_transformation(transformations[SupportedAdjustments.TINT]);
        adjust_tool_window.tint_slider.set_value(tint_trans.get_parameter());

        /* set up saturation */
        SaturationTransformation sat_trans = (SaturationTransformation)
            canvas.get_photo().get_adjustment(SupportedAdjustments.SATURATION);
        transformations[SupportedAdjustments.SATURATION] = sat_trans;
        transformer.attach_transformation(transformations[SupportedAdjustments.SATURATION]);
        histogram_transformer.attach_transformation(transformations[SupportedAdjustments.SATURATION]);
        adjust_tool_window.saturation_slider.set_value(sat_trans.get_parameter());

        /* set up exposure */
        ExposureTransformation exposure_trans = (ExposureTransformation)
            canvas.get_photo().get_adjustment(SupportedAdjustments.EXPOSURE);
        transformations[SupportedAdjustments.EXPOSURE] = exposure_trans;
        transformer.attach_transformation(transformations[SupportedAdjustments.EXPOSURE]);
        histogram_transformer.attach_transformation(transformations[SupportedAdjustments.EXPOSURE]);
        adjust_tool_window.exposure_slider.set_value(exposure_trans.get_parameter());

        bind_handlers();
        canvas.resized_scaled_pixbuf += on_canvas_resize;

        draw_to_pixbuf = canvas.get_scaled_pixbuf().copy();
        init_fp_pixel_cache(canvas.get_scaled_pixbuf());

        histogram_pixbuf = draw_to_pixbuf.scale_simple(draw_to_pixbuf.width / 2,
            draw_to_pixbuf.height / 2, Gdk.InterpType.HYPER);
        virgin_histogram_pixbuf = histogram_pixbuf.copy();

        base.activate(canvas);
    }

    public override EditingToolWindow? get_tool_window() {
        return adjust_tool_window;
    }

    public override void deactivate() {
        if (adjust_tool_window != null) {
            adjust_tool_window.hide();
            adjust_tool_window = null;
        }

        draw_to_pixbuf = null;
        fp_pixel_cache = null;

        base.deactivate();
    }

    public override void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        if (!suppress_effect_redraw) {
            transformer.transform_from_fp(ref fp_pixel_cache, draw_to_pixbuf);
            histogram_transformer.transform_to_other_pixbuf(virgin_histogram_pixbuf,
                histogram_pixbuf);
            adjust_tool_window.histogram_manipulator.update_histogram(histogram_pixbuf);
        }

        canvas.paint_pixbuf(draw_to_pixbuf);
    }

    public override Gdk.Pixbuf? get_display_pixbuf(Scaling scaling, TransformablePhoto photo) throws Error {
        return photo.has_color_adjustments() 
            ? photo.get_pixbuf(scaling, TransformablePhoto.Exception.ADJUST) : null;
    }

    private void on_reset() {
        suppress_effect_redraw = true;

        adjust_tool_window.exposure_slider.set_value(0.0);
        adjust_tool_window.saturation_slider.set_value(0.0);
        adjust_tool_window.temperature_slider.set_value(0.0);
        adjust_tool_window.tint_slider.set_value(0.0);
        adjust_tool_window.shadows_slider.set_value(0.0);
        
        adjust_tool_window.histogram_manipulator.set_left_nub_position(0);
        adjust_tool_window.histogram_manipulator.set_right_nub_position(255);
        on_histogram_constraint();
    
        suppress_effect_redraw = false;
        canvas.repaint();
    }

    private void on_apply() {
        suppress_effect_redraw = true;

        get_tool_window().hide();
        
        AppWindow.get_instance().set_busy_cursor();

        canvas.get_photo().set_adjustments(transformations);

        AppWindow.get_instance().set_normal_cursor();

        applied(draw_to_pixbuf, false);
    }
    
    private void update_transformations(PixelTransformation[] new_transformations) {
        for (int i = 0; i < ((int) SupportedAdjustments.NUM); i++)
            update_transformation((SupportedAdjustments) i, new_transformations[i]);
    }
    
    private void update_transformation(SupportedAdjustments type, PixelTransformation trans) {
        transformer.replace_transformation(transformations[type], trans);
        if (type != SupportedAdjustments.TONE_EXPANSION)
            histogram_transformer.replace_transformation(transformations[type], trans);
        transformations[type] = trans;
    }
    
    private void update_and_repaint(SupportedAdjustments type, PixelTransformation trans) {
        update_transformation(type, trans);
        canvas.repaint();
    }

    private void on_temperature_adjustment() {
        TemperatureTransformation new_temp_trans = new TemperatureTransformation(
            (float) adjust_tool_window.temperature_slider.get_value());
        update_and_repaint(SupportedAdjustments.TEMPERATURE, new_temp_trans);
    }

    private void on_tint_adjustment() {
        TintTransformation new_tint_trans = new TintTransformation(
            (float) adjust_tool_window.tint_slider.get_value());
        update_and_repaint(SupportedAdjustments.TINT, new_tint_trans);
    }

    private void on_saturation_adjustment() {
        SaturationTransformation new_sat_trans = new SaturationTransformation(
            (float) adjust_tool_window.saturation_slider.get_value());
        update_and_repaint(SupportedAdjustments.SATURATION, new_sat_trans);
    }

    private void on_exposure_adjustment() {
        ExposureTransformation new_exp_trans = new ExposureTransformation(
            (float) adjust_tool_window.exposure_slider.get_value());
        update_and_repaint(SupportedAdjustments.EXPOSURE, new_exp_trans);
    }
    
    private void on_shadows_adjustment() {
        ShadowDetailTransformation new_shadows_trans = new ShadowDetailTransformation(
            (float) adjust_tool_window.shadows_slider.get_value());
        update_and_repaint(SupportedAdjustments.SHADOWS, new_shadows_trans);
    }

    private void on_histogram_constraint() {
        int expansion_black_point =
            adjust_tool_window.histogram_manipulator.get_left_nub_position();
        int expansion_white_point =
            adjust_tool_window.histogram_manipulator.get_right_nub_position();
        ExpansionTransformation new_exp_trans =
            new ExpansionTransformation.from_extrema(expansion_black_point, expansion_white_point);
        update_and_repaint(SupportedAdjustments.TONE_EXPANSION, new_exp_trans);
    }

    private void on_canvas_resize() {
        draw_to_pixbuf = canvas.get_scaled_pixbuf().copy();
        init_fp_pixel_cache(canvas.get_scaled_pixbuf());
    }
    
    private void bind_handlers() {
        adjust_tool_window.apply_button.clicked += on_apply;
        adjust_tool_window.reset_button.clicked += on_reset;
        adjust_tool_window.cancel_button.clicked += notify_cancel;
        adjust_tool_window.exposure_slider.value_changed += on_exposure_adjustment;
        adjust_tool_window.saturation_slider.value_changed +=
            on_saturation_adjustment;
        adjust_tool_window.tint_slider.value_changed += on_tint_adjustment;
        adjust_tool_window.temperature_slider.value_changed +=
            on_temperature_adjustment;
        adjust_tool_window.shadows_slider.value_changed +=
            on_shadows_adjustment;
        adjust_tool_window.histogram_manipulator.nub_position_changed +=
            on_histogram_constraint;
    }

    private void unbind_handlers() {
        adjust_tool_window.apply_button.clicked -= on_apply;
        adjust_tool_window.reset_button.clicked -= on_reset;
        adjust_tool_window.cancel_button.clicked -= notify_cancel;
        adjust_tool_window.exposure_slider.value_changed -= on_exposure_adjustment;
        adjust_tool_window.saturation_slider.value_changed -=
            on_saturation_adjustment;
        adjust_tool_window.tint_slider.value_changed -= on_tint_adjustment;
        adjust_tool_window.temperature_slider.value_changed -=
            on_temperature_adjustment;
        adjust_tool_window.shadows_slider.value_changed -=
            on_shadows_adjustment;
        adjust_tool_window.histogram_manipulator.nub_position_changed -=
            on_histogram_constraint;
    }
    
    public void set_adjustments(PixelTransformation[] new_adjustments) {
        unbind_handlers();

        update_transformations(new_adjustments);

        adjust_tool_window.histogram_manipulator.set_left_nub_position(((ExpansionTransformation)
            new_adjustments[SupportedAdjustments.TONE_EXPANSION]).get_black_point());
        adjust_tool_window.histogram_manipulator.set_right_nub_position(((ExpansionTransformation)
            new_adjustments[SupportedAdjustments.TONE_EXPANSION]).get_white_point());
        adjust_tool_window.shadows_slider.set_value(((ShadowDetailTransformation)
            new_adjustments[SupportedAdjustments.SHADOWS]).get_parameter());
        adjust_tool_window.exposure_slider.set_value(((ExposureTransformation)
            new_adjustments[SupportedAdjustments.EXPOSURE]).get_parameter());
        adjust_tool_window.saturation_slider.set_value(((SaturationTransformation)
            new_adjustments[SupportedAdjustments.SATURATION]).get_parameter());
        adjust_tool_window.tint_slider.set_value(((TintTransformation)
            new_adjustments[SupportedAdjustments.TINT]).get_parameter());
        adjust_tool_window.temperature_slider.set_value(((TemperatureTransformation)
            new_adjustments[SupportedAdjustments.TEMPERATURE]).get_parameter());

        bind_handlers();
        canvas.repaint();
    }
    
    private void init_fp_pixel_cache(Gdk.Pixbuf source) {
        int source_width = source.get_width();
        int source_height = source.get_height();
        int source_num_channels = source.get_n_channels();
        int source_rowstride = source.get_rowstride();
        unowned uchar[] source_pixels = source.get_pixels();

        fp_pixel_cache = new float[3 * source_width * source_height];
        int cache_pixel_index = 0;
        float INV_255 = 1.0f / 255.0f;

        for (int j = 0; j < source_height; j++) {
            int row_start_index = j * source_rowstride;
            int row_end_index = row_start_index + (source_width * source_num_channels);
            for (int i = row_start_index; i < row_end_index; i += source_num_channels) {
                fp_pixel_cache[cache_pixel_index++] = ((float) source_pixels[i]) * INV_255;
                fp_pixel_cache[cache_pixel_index++] = ((float) source_pixels[i + 1]) * INV_255;
                fp_pixel_cache[cache_pixel_index++] = ((float) source_pixels[i + 2]) * INV_255;
            }
        }
    }
}

