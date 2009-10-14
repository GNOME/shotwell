/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class EditingToolWindow : Gtk.Window {
    private const int FRAME_BORDER = 6;

    private Gtk.Window container;
    private EditingTool tool;
    private Gtk.Frame layout_frame = new Gtk.Frame(null);
    private bool user_moved = false;

    public EditingToolWindow(Gtk.Window container, EditingTool tool) {
        this.container = container;
        this.tool = tool;

        type_hint = Gdk.WindowTypeHint.TOOLBAR;
        set_transient_for(container);

        Gtk.Frame outer_frame = new Gtk.Frame(null);
        outer_frame.set_border_width(0);
        outer_frame.set_shadow_type(Gtk.ShadowType.OUT);
        
        layout_frame.set_border_width(FRAME_BORDER);
        layout_frame.set_shadow_type(Gtk.ShadowType.NONE);
        
        outer_frame.add(layout_frame);
        base.add(outer_frame);

        add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.KEY_PRESS_MASK);
        focus_on_map = true;
        set_accept_focus(true);
        set_flags(Gtk.WidgetFlags.CAN_FOCUS);
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

        get_tool_window().key_press_event += on_keypress;

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
        // check for an escape/abort first
        if (Gdk.keyval_name(event.keyval) == "Escape") {
            notify_cancel();

            return true;
        }

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

    private const int CROP_MIN_SIZE = 100;

    private const float CROP_EXTERIOR_SATURATION = 0.00f;
    private const int CROP_EXTERIOR_RED_SHIFT = -32;
    private const int CROP_EXTERIOR_GREEN_SHIFT = -32;
    private const int CROP_EXTERIOR_BLUE_SHIFT = -32;
    private const int CROP_EXTERIOR_ALPHA_SHIFT = 0;

    private const float ANY_ASPECT_RATIO = -1.0f;
    private const float SCREEN_ASPECT_RATIO = -2.0f;
    private const float ORIGINAL_ASPECT_RATIO = -3.0f;
    private const float CUSTOM_ASPECT_RATIO = -4.0f;
    private const float COMPUTE_FROM_BASIS = -5.0f;
    private const float SEPARATOR = -6.0f;
    private const float MIN_ASPECT_RATIO = 1.0f / 4.0f;
    private const float MAX_ASPECT_RATIO = 4.0f;
    
    private struct ConstraintDescription {
        public string name;
        public int basis_width;
        public int basis_height;
        public bool is_pivotable;
        public float aspect_ratio;
        
        public ConstraintDescription(string new_name, int new_basis_width, int new_basis_height,
            bool new_pivotable, float new_aspect_ratio = COMPUTE_FROM_BASIS) {
            name = new_name;
            basis_width = new_basis_width;
            basis_height = new_basis_height;
            if (new_aspect_ratio == COMPUTE_FROM_BASIS)
                aspect_ratio = ((float) basis_width) / ((float) basis_height);
            else
                aspect_ratio = new_aspect_ratio;
            is_pivotable = new_pivotable;
        }
    }
    
    private enum ReticleOrientation {
        LANDSCAPE,
        PORTRAIT;
        
        public ReticleOrientation toggle() {
            return (this == ReticleOrientation.LANDSCAPE) ? ReticleOrientation.PORTRAIT :
                ReticleOrientation.LANDSCAPE;
        }
    }
    
    private enum ConstraintMode {
        NORMAL,
        CUSTOM
    }

    private class CropToolWindow : EditingToolWindow {
        private const int CONTROL_SPACING = 8;
        
        public Gtk.Button apply_button = new Gtk.Button.from_stock(Gtk.STOCK_APPLY);
        public Gtk.Button cancel_button = new Gtk.Button.from_stock(Gtk.STOCK_CANCEL);
        public Gtk.ComboBox constraint_combo;
        public Gtk.Button pivot_reticle_button = new Gtk.Button();
        public Gtk.Entry custom_width_entry = new Gtk.Entry();
        public Gtk.Entry custom_height_entry = new Gtk.Entry();
        public Gtk.Label custom_mulsign_label = new Gtk.Label.with_mnemonic("x");
        public Gtk.Entry most_recently_edited = null;
        public Gtk.HBox layout = null;
        public int normal_width = -1;
        public int normal_height = -1;

        public CropToolWindow(Gtk.Window container, CropTool tool) {
            base(container, tool);
            
            cancel_button.set_tooltip_text(_("Return to current photo dimensions"));
            cancel_button.set_image_position(Gtk.PositionType.LEFT);
            
            apply_button.set_tooltip_text(_("Set the crop for this photo"));
            apply_button.set_image_position(Gtk.PositionType.LEFT);
            
            constraint_combo = new Gtk.ComboBox();
            Gtk.CellRendererText combo_text_renderer = new Gtk.CellRendererText();
            constraint_combo.pack_start(combo_text_renderer, true);
            constraint_combo.add_attribute(combo_text_renderer, "text", 0);
            constraint_combo.set_row_separator_func(constraint_combo_separator_func,
                constraint_combo_destroy_func);
            constraint_combo.set_active(0);
            
            pivot_reticle_button.set_image(new Gtk.Image.from_stock(Resources.CROP_PIVOT_RETICLE,
                Gtk.IconSize.LARGE_TOOLBAR));
            pivot_reticle_button.set_tooltip_text(_("Pivot the crop rectangle between portrait and landscape orientations"));

            custom_width_entry.set_width_chars(4);
            custom_width_entry.editable = true;
            custom_height_entry.set_width_chars(4);
            custom_height_entry.editable = true;

            layout = new Gtk.HBox(false, CONTROL_SPACING);
            layout.add(constraint_combo);
            layout.add(pivot_reticle_button);
            layout.add(cancel_button);
            layout.add(apply_button);
            
            add(layout);
        }

        private static bool constraint_combo_separator_func(Gtk.TreeModel model, Gtk.TreeIter iter) {
            Value val;
            model.get_value(iter, 0, out val);

            return (val.dup_string() == "-");
        }

        private static void constraint_combo_destroy_func() {
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
    
    private ConstraintDescription[] constraints = create_constraints();
    private Gtk.ListStore constraint_list = create_constraint_list(create_constraints());
    private ReticleOrientation reticle_orientation = ReticleOrientation.LANDSCAPE;
    private ConstraintMode constraint_mode = ConstraintMode.NORMAL;
    private bool entry_insert_in_progress = false;
    private float custom_aspect_ratio = 1.0f;
    private int custom_width = -1;
    private int custom_height = -1;
    private int custom_init_width = -1;
    private int custom_init_height = -1;
    private float pre_aspect_ratio = ANY_ASPECT_RATIO;
    
    private CropTool() {
    }
    
    public static CropTool factory() {
        return new CropTool();
    }

    private static ConstraintDescription[] create_constraints() {
        ConstraintDescription[] result = new ConstraintDescription[0];

        result += ConstraintDescription(_("Unconstrained"), 0, 0, false, ANY_ASPECT_RATIO);
        result += ConstraintDescription(_("Square"), 1, 1, false);
        result += ConstraintDescription(_("Screen"), 0, 0, false, SCREEN_ASPECT_RATIO);
        result += ConstraintDescription(_("Original Size"), 0, 0, false, ORIGINAL_ASPECT_RATIO);
        result += ConstraintDescription(_("-"), 0, 0, false, SEPARATOR);
        result += ConstraintDescription(_("SD Video (4 : 3)"), 4, 3, false);
        result += ConstraintDescription(_("HD Video (16 : 9)"), 16, 9, false);
        result += ConstraintDescription(_("-"), 0, 0, false, SEPARATOR);
        result += ConstraintDescription(_("Wallet (2 x 3 in.)"), 3, 2, true);
        result += ConstraintDescription(_("Notecard (3 x 5 in.)"), 5, 3, true);
        result += ConstraintDescription(_("4 x 6 in."), 6, 4, true);
        result += ConstraintDescription(_("5 x 7 in."), 7, 5, true);
        result += ConstraintDescription(_("8 x 10 in."), 10, 8, true);
        result += ConstraintDescription(_("11 x 14 in."), 14, 11, true);
        result += ConstraintDescription(_("16 x 20 in."), 20, 16, true);
        result += ConstraintDescription(_("-"), 0, 0, false, SEPARATOR);
        result += ConstraintDescription(_("Metric Wallet (9 x 13 cm.)"), 13, 9, true);
        result += ConstraintDescription(_("Postcard (10 x 15 cm.)"), 15, 10, true);
        result += ConstraintDescription(_("13 x 18 cm."), 18, 13, true);
        result += ConstraintDescription(_("18 x 24 cm."), 24, 18, true);
        result += ConstraintDescription(_("20 x 30 cm."), 30, 20, true);
        result += ConstraintDescription(_("24 x 40 cm."), 40, 24, true);
        result += ConstraintDescription(_("30 x 40 cm."), 40, 30, true);
        result += ConstraintDescription(_("-"), 0, 0, false, SEPARATOR);
        result += ConstraintDescription(_("Custom"), 0, 0, true, CUSTOM_ASPECT_RATIO);

        return result;
    }
    
    private static Gtk.ListStore create_constraint_list(ConstraintDescription[] constraint_data) {
        Gtk.ListStore result = new Gtk.ListStore(1, typeof(string), typeof(string));

        Gtk.TreeIter iter;
        foreach (ConstraintDescription constraint in constraint_data) {
            result.append(out iter);
            result.set_value(iter, 0, constraint.name);
        }

        return result;
    }
    
    private void update_pivot_button_state() {
        crop_tool_window.pivot_reticle_button.set_sensitive(
            get_selected_constraint().is_pivotable);
    }

    private ConstraintDescription get_selected_constraint() {
        ConstraintDescription result = constraints[crop_tool_window.constraint_combo.get_active()];

        if (result.aspect_ratio == ORIGINAL_ASPECT_RATIO) {
            result.basis_width = canvas.get_scaled_pixbuf().width;
            result.basis_height = canvas.get_scaled_pixbuf().height;
        } else if (result.aspect_ratio == SCREEN_ASPECT_RATIO) {
            Gdk.Screen screen = Gdk.Screen.get_default();
            result.basis_width = screen.get_width();
            result.basis_height = screen.get_height();
        }

        return result;
    }
    
    private bool on_width_entry_focus_out(Gdk.EventFocus event) {
        crop_tool_window.most_recently_edited = crop_tool_window.custom_width_entry;
        return on_custom_entry_focus_out(event);
    }
    
    private bool on_height_entry_focus_out(Gdk.EventFocus event) {
        crop_tool_window.most_recently_edited = crop_tool_window.custom_height_entry;
        return on_custom_entry_focus_out(event);
    }
    
    private bool on_custom_entry_focus_out(Gdk.EventFocus event) {
        int width = crop_tool_window.custom_width_entry.text.to_int();
        int height = crop_tool_window.custom_height_entry.text.to_int();
        
        if ((width == custom_width) && (height == custom_height))
            return false;

        custom_aspect_ratio = ((float) width) / ((float) height);
        
        if (custom_aspect_ratio < MIN_ASPECT_RATIO) {
            if (crop_tool_window.most_recently_edited == crop_tool_window.custom_height_entry) {
                height = (int) (width / MIN_ASPECT_RATIO);
                crop_tool_window.custom_height_entry.set_text("%d".printf(height));
            } else {
                width = (int) (height * MIN_ASPECT_RATIO);
                crop_tool_window.custom_width_entry.set_text("%d".printf(width));
            }
        } else if (custom_aspect_ratio > MAX_ASPECT_RATIO) {
            if (crop_tool_window.most_recently_edited == crop_tool_window.custom_height_entry) {
                height = (int) (width / MAX_ASPECT_RATIO);
                crop_tool_window.custom_height_entry.set_text("%d".printf(height));
            } else {
                width = (int) (height * MAX_ASPECT_RATIO);
                crop_tool_window.custom_width_entry.set_text("%d".printf(width));
            }
        }

        custom_aspect_ratio = ((float) width) / ((float) height);

        Box new_crop = constrain_crop(scaled_crop);
        
        crop_resized(new_crop);
        scaled_crop = new_crop;
        canvas.invalidate_area(new_crop);
        canvas.repaint();

        custom_width = width;
        custom_height = height;

        return false;
    }

    private void on_width_insert_text(string text, int length, void *position) {
        on_entry_insert_text(crop_tool_window.custom_width_entry, text, length, position);
    }

    private void on_height_insert_text(string text, int length, void *position) {
        on_entry_insert_text(crop_tool_window.custom_height_entry, text, length, position);
    }

    private void on_entry_insert_text(Gtk.Entry sender, string text, int length, void *position) {
        if (entry_insert_in_progress)
            return;
            
        entry_insert_in_progress = true;
        
        if (length == -1)
            length = (int) text.length;

        // only permit numeric text
        string new_text = "";
        for (int ctr = 0; ctr < length; ctr++) {
            if (text[ctr].isdigit()) {
                new_text += ((char) text[ctr]).to_string();
            }
        }
        
        if (new_text.length > 0)
            sender.insert_text(new_text, (int) new_text.length, position);

        Signal.stop_emission_by_name(sender, "insert-text");
        
        entry_insert_in_progress = false;
    }
    
    private float get_constraint_aspect_ratio() {
        float result = get_selected_constraint().aspect_ratio;

        if (result == ORIGINAL_ASPECT_RATIO) {
            result = ((float) canvas.get_scaled_pixbuf().width) /
                ((float) canvas.get_scaled_pixbuf().height);
        } else if (result == SCREEN_ASPECT_RATIO) {
            Gdk.Screen screen = Gdk.Screen.get_default();
            result = ((float) screen.get_width()) / ((float) screen.get_height());
        } else if (result == CUSTOM_ASPECT_RATIO) {
            result = custom_aspect_ratio;
        }
        if (reticle_orientation == ReticleOrientation.PORTRAIT)
            result = 1.0f / result;

        return result;
    }
    
    private void constraint_changed() {
        ConstraintDescription selected_constraint = get_selected_constraint();
        if (selected_constraint.aspect_ratio == CUSTOM_ASPECT_RATIO) {
            set_custom_constraint_mode();
        } else {
            set_normal_constraint_mode();

            if (selected_constraint.aspect_ratio != ANY_ASPECT_RATIO) {
                custom_init_width = selected_constraint.basis_width;
                custom_init_height = selected_constraint.basis_height;
                custom_aspect_ratio = ((float) custom_init_width) / ((float) custom_init_height);
            }
        }
        
        update_pivot_button_state();

        if (!get_selected_constraint().is_pivotable)
            reticle_orientation = ReticleOrientation.LANDSCAPE;

        if (get_constraint_aspect_ratio() != pre_aspect_ratio) {
            Box new_crop = constrain_crop(scaled_crop);
            
            crop_resized(new_crop);
            scaled_crop = new_crop;
            canvas.invalidate_area(new_crop);
            canvas.repaint();
            
            pre_aspect_ratio = get_constraint_aspect_ratio();
        }
    }
    
    private void set_custom_constraint_mode() {
        if (constraint_mode == ConstraintMode.CUSTOM)
            return;
        
        if ((crop_tool_window.normal_width == -1) || (crop_tool_window.normal_height == -1))
            crop_tool_window.get_size(out crop_tool_window.normal_width,
                out crop_tool_window.normal_height);

        int window_x_pos = 0;
        int window_y_pos = 0;
        crop_tool_window.get_position(out window_x_pos, out window_y_pos);

        crop_tool_window.hide();

        crop_tool_window.layout.remove(crop_tool_window.constraint_combo);
        crop_tool_window.layout.remove(crop_tool_window.pivot_reticle_button);
        crop_tool_window.layout.remove(crop_tool_window.cancel_button);
        crop_tool_window.layout.remove(crop_tool_window.apply_button);

        crop_tool_window.layout.add(crop_tool_window.constraint_combo);
        crop_tool_window.layout.add(crop_tool_window.custom_height_entry);
        crop_tool_window.layout.add(crop_tool_window.custom_mulsign_label);
        crop_tool_window.layout.add(crop_tool_window.custom_width_entry);
        crop_tool_window.layout.add(crop_tool_window.pivot_reticle_button);
        crop_tool_window.layout.add(crop_tool_window.cancel_button);
        crop_tool_window.layout.add(crop_tool_window.apply_button);
        
        if (reticle_orientation == ReticleOrientation.LANDSCAPE) {
            crop_tool_window.custom_width_entry.set_text("%d".printf(custom_init_width));
            crop_tool_window.custom_height_entry.set_text("%d".printf(custom_init_height));
        } else {
            crop_tool_window.custom_width_entry.set_text("%d".printf(custom_init_height));
            crop_tool_window.custom_height_entry.set_text("%d".printf(custom_init_width));
        }
        custom_aspect_ratio = ((float) custom_init_width) / ((float) custom_init_height);

        crop_tool_window.move(window_x_pos, window_y_pos);
        crop_tool_window.show_all();
        
        constraint_mode = ConstraintMode.CUSTOM;
    }
    
    private void set_normal_constraint_mode() {
        if (constraint_mode == ConstraintMode.NORMAL)
            return;

        int window_x_pos = 0;
        int window_y_pos = 0;
        crop_tool_window.get_position(out window_x_pos, out window_y_pos);

        crop_tool_window.hide();

        crop_tool_window.layout.remove(crop_tool_window.constraint_combo);
        crop_tool_window.layout.remove(crop_tool_window.custom_width_entry);
        crop_tool_window.layout.remove(crop_tool_window.custom_mulsign_label);
        crop_tool_window.layout.remove(crop_tool_window.custom_height_entry);
        crop_tool_window.layout.remove(crop_tool_window.pivot_reticle_button);
        crop_tool_window.layout.remove(crop_tool_window.cancel_button);
        crop_tool_window.layout.remove(crop_tool_window.apply_button);

        crop_tool_window.layout.add(crop_tool_window.constraint_combo);
        crop_tool_window.layout.add(crop_tool_window.pivot_reticle_button);
        crop_tool_window.layout.add(crop_tool_window.cancel_button);
        crop_tool_window.layout.add(crop_tool_window.apply_button);

        crop_tool_window.resize(crop_tool_window.normal_width,
            crop_tool_window.normal_height);

        crop_tool_window.move(window_x_pos, window_y_pos);
        crop_tool_window.show_all();

        constraint_mode = ConstraintMode.NORMAL;
    }
    
    private Box constrain_crop(Box crop) {
        float user_aspect_ratio = get_constraint_aspect_ratio();
        if (user_aspect_ratio == ANY_ASPECT_RATIO)
            return crop;

        float scaled_width = (float) crop.get_width();
        float scaled_height = (float) crop.get_height();
        float scaled_center_x = ((float) crop.left) + (scaled_width / 2.0f);
        float scaled_center_y = ((float) crop.top) + (scaled_height / 2.0f);
        float scaled_aspect_ratio = scaled_width / scaled_height;

        // Crop positioning in the presence of constraint is a three-phase process

        // PHASE 1: Naively rescale the width and the height of the box so that it has the
        //          user-specified aspect ratio. Even in this initial transformation, the
        //          box's center and minor axis length are preserved. Preserving the center
        //          is especially important since this way the subject that the user has framed
        //          within the crop reticle is preserved.
        if (scaled_aspect_ratio > 1.0f)
            scaled_width = scaled_height;
        else
            scaled_height = scaled_width;
        scaled_width *= user_aspect_ratio;

        // PHASE 2: Now that the box has the correct aspect ratio, grow it or shrink it such
        //          that it has the same area that it had prior to constraint. This prevents
        //          the box from growing or shrinking erratically as constraints are set and
        //          unset.
        float old_area = (float) (crop.get_width() * crop.get_height());
        float new_area = scaled_width * scaled_height;
        float area_correct_factor = (float) Math.sqrt(old_area / new_area);
        scaled_width *= area_correct_factor;
        scaled_height *= area_correct_factor;

        // PHASE 3: The new crop box may have edges that fall outside of the boundaries of
        //          the photo. Here, we rescale it such that it fits within the boundaries
        //          of the photo. Note that we prefer scaling to translation (as does iPhoto)
        //          because scaling preserves the center point of the box, so if the user
        //          has framed a particular subject, the frame remains on the subject after
        //          boundary correction.
        int photo_right_edge = canvas.get_scaled_pixbuf().width - 1;
        int photo_bottom_edge = canvas.get_scaled_pixbuf().height - 1;

        int new_box_left = (int) ((scaled_center_x - (scaled_width / 2.0f)));
        int new_box_right = (int) ((scaled_center_x + (scaled_width / 2.0f)));
        int new_box_top = (int) ((scaled_center_y - (scaled_height / 2.0f)));
        int new_box_bottom = (int) ((scaled_center_y + (scaled_height / 2.0f)));
        
        if (new_box_left < 0) {
            float overshoot = (float) (-new_box_left);
            float box_rescale_factor = (scaled_width - (2.0f * overshoot)) / scaled_width;
            scaled_width *= box_rescale_factor;
            scaled_height *= box_rescale_factor;
        }

        if (new_box_right > photo_right_edge) {
            float overshoot = (float) (new_box_right - photo_right_edge);
            float box_rescale_factor = (scaled_width - (2.0f * overshoot)) / scaled_width;
            scaled_width *= box_rescale_factor;
            scaled_height *= box_rescale_factor;
        }

        if (new_box_top < 0) {
            float overshoot = (float) (-new_box_top);
            float box_rescale_factor = (scaled_height - (2.0f * overshoot)) / scaled_height;
            scaled_width *= box_rescale_factor;
            scaled_height *= box_rescale_factor;
        }

        if (new_box_bottom > photo_bottom_edge) {
            float overshoot = (float) (new_box_bottom - photo_bottom_edge);
            float box_rescale_factor = (scaled_height - (2.0f * overshoot)) / scaled_height;
            scaled_width *= box_rescale_factor;
            scaled_height *= box_rescale_factor;
        }

        Box new_crop_box = Box((int) ((scaled_center_x - (scaled_width / 2.0f))),
            (int) ((scaled_center_y - (scaled_height / 2.0f))),
            (int) ((scaled_center_x + (scaled_width / 2.0f))),
            (int) ((scaled_center_y + (scaled_height / 2.0f))));
        
        return new_crop_box;
    }

    public override void activate(PhotoCanvas canvas) {
        canvas.new_drawable += prepare_gc;
        canvas.resized_scaled_pixbuf += on_resized_pixbuf;

        prepare_gc(canvas.get_default_gc(), canvas.get_drawable());
        prepare_visuals(canvas.get_scaled_pixbuf());

        // create the crop tool window, where the user can apply or cancel the crop
        crop_tool_window = new CropToolWindow(canvas.get_container(), this);
        crop_tool_window.apply_button.clicked += on_crop_apply;
        crop_tool_window.cancel_button.clicked += notify_cancel;
        
        // set up the constraint combo box
        crop_tool_window.constraint_combo.set_model(constraint_list);
        crop_tool_window.constraint_combo.changed += constraint_changed;

        // set up the pivot reticle button
        update_pivot_button_state();
        reticle_orientation = ReticleOrientation.LANDSCAPE;
        crop_tool_window.pivot_reticle_button.clicked += on_pivot_button_clicked;

        // set up the custom width and height entry boxes
        crop_tool_window.custom_width_entry.focus_out_event += on_width_entry_focus_out;
        crop_tool_window.custom_height_entry.focus_out_event += on_height_entry_focus_out;
        crop_tool_window.custom_width_entry.insert_text += on_width_insert_text;
        crop_tool_window.custom_height_entry.insert_text += on_height_insert_text;

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
        
        custom_init_width = scaled_crop.get_width();
        custom_init_height = scaled_crop.get_height();
        pre_aspect_ratio = ((float) custom_init_width) / ((float) custom_init_height);
        
        constraint_mode = ConstraintMode.NORMAL;

        base.activate(canvas);
    }
    
    private void on_pivot_button_clicked() {
        if (get_selected_constraint().aspect_ratio == CUSTOM_ASPECT_RATIO) {
            string width_text = crop_tool_window.custom_width_entry.get_text();
            string height_text = crop_tool_window.custom_height_entry.get_text();
            crop_tool_window.custom_width_entry.set_text(height_text);
            crop_tool_window.custom_height_entry.set_text(width_text);

            int temp = custom_width;
            custom_width = custom_height;
            custom_height = temp;
        }
        reticle_orientation = reticle_orientation.toggle();
        constraint_changed();
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
        return photo.has_crop() ? photo.get_pixbuf_with_exceptions(scaling, TransformablePhoto.Exception.CROP) : null;
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

    private void revert_crop(out int left, out int top, out int right, out int bottom) {
        left = scaled_crop.left;
        top = scaled_crop.top;
        right = scaled_crop.right;
        bottom = scaled_crop.bottom;
    }

    private int eval_radial_line(double center_x, double center_y, double bounds_x,
        double bounds_y, double user_x) {
        double decision_slope = (bounds_y - center_y) / (bounds_x - center_x);
        double decision_intercept = bounds_y - (decision_slope * bounds_x);

        return (int) (decision_slope * user_x + decision_intercept);
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

        // get extra geometric information needed to enforce constraints
        int photo_right_edge = canvas.get_scaled_pixbuf().width - 1;
        int photo_bottom_edge = canvas.get_scaled_pixbuf().height - 1;
        int center_x = (left + right) / 2;
        int center_y = (top + bottom) / 2;

        switch (in_manipulation) {
            case BoxLocation.LEFT_SIDE:
                left = x;
                if (get_constraint_aspect_ratio() != ANY_ASPECT_RATIO) {
                    float new_height = ((float) (right - left)) / get_constraint_aspect_ratio();
                    bottom = top + ((int) new_height);
                }
            break;

            case BoxLocation.TOP_SIDE:
                top = y;
                if (get_constraint_aspect_ratio() != ANY_ASPECT_RATIO) {
                    float new_width = ((float) (bottom - top)) * get_constraint_aspect_ratio();
                    right = left + ((int) new_width);
                }
            break;

            case BoxLocation.RIGHT_SIDE:
                right = x;
                if (get_constraint_aspect_ratio() != ANY_ASPECT_RATIO) {
                    float new_height = ((float) (right - left)) / get_constraint_aspect_ratio();
                    bottom = top + ((int) new_height);
                }
            break;

            case BoxLocation.BOTTOM_SIDE:
                bottom = y;
                if (get_constraint_aspect_ratio() != ANY_ASPECT_RATIO) {
                    float new_width = ((float) (bottom - top)) * get_constraint_aspect_ratio();
                    right = left + ((int) new_width);
                }
            break;

            case BoxLocation.TOP_LEFT:
                if (get_constraint_aspect_ratio() == ANY_ASPECT_RATIO) {
                    top = y;
                    left = x;
                } else {
                    if (y < eval_radial_line(center_x, center_y, left, top, x)) {
                        top = y;
                        float new_width = ((float) (bottom - top)) * get_constraint_aspect_ratio();
                        left = right - ((int) new_width);
                    } else {
                        left = x;
                        float new_height = ((float) (right - left)) / get_constraint_aspect_ratio();
                        top = bottom - ((int) new_height);
                    }
                }
            break;

            case BoxLocation.BOTTOM_LEFT:
                if (get_constraint_aspect_ratio() == ANY_ASPECT_RATIO) {
                    bottom = y;
                    left = x;
                } else {
                    if (y < eval_radial_line(center_x, center_y, left, bottom, x)) {
                        left = x;
                        float new_height = ((float) (right - left)) / get_constraint_aspect_ratio();
                        bottom = top + ((int) new_height);
                    } else {
                        bottom = y;
                        float new_width = ((float) (bottom - top)) * get_constraint_aspect_ratio();
                        left = right - ((int) new_width);
                    }
                }
            break;

            case BoxLocation.TOP_RIGHT:
                if (get_constraint_aspect_ratio() == ANY_ASPECT_RATIO) {
                    top = y;
                    right = x;
                } else {
                    if (y < eval_radial_line(center_x, center_y, right, top, x)) {
                        top = y;
                        float new_width = ((float) (bottom - top)) * get_constraint_aspect_ratio();
                        right = left + ((int) new_width);
                    } else {
                        right = x;
                        float new_height = ((float) (right - left)) / get_constraint_aspect_ratio();
                        top = bottom - ((int) new_height);
                    }
                }
            break;

            case BoxLocation.BOTTOM_RIGHT:
                if (get_constraint_aspect_ratio() == ANY_ASPECT_RATIO) {
                    bottom = y;
                    right = x;
                } else {
                    if (y < eval_radial_line(center_x, center_y, right, bottom, x)) {
                        right = x;
                        float new_height = ((float) (right - left)) / get_constraint_aspect_ratio();
                        bottom = top + ((int) new_height);
                    } else {
                        bottom = y;
                        float new_width = ((float) (bottom - top)) * get_constraint_aspect_ratio();
                        right = left + ((int) new_width);
                    }
                }
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

        // Check if the mouse has gone out of bounds, and if it has, make sure that the
        // crop reticle's edges stay within the photo bounds. This bounds check works
        // differently in constrained versus unconstrained mode. In unconstrained mode,
        // we need only to bounds clamp the one or two edge(s) that are actually out-of-bounds.
        // In constrained mode however, we need to bounds clamp the entire box, because the
        // positions of edges are all interdependent (so as to enforce the aspect ratio
        // constraint).
        int width = right - left + 1;
        int height = bottom - top + 1;
        if (get_constraint_aspect_ratio() == ANY_ASPECT_RATIO) {
            if (left < 0)
                left = 0;
            if (top < 0)
                top = 0;
            if (right > photo_right_edge)
                right = photo_right_edge;
            if (bottom > photo_bottom_edge)
                bottom = photo_bottom_edge;

            width = right - left + 1;
            height = bottom - top + 1;

            switch (in_manipulation) {
                case BoxLocation.LEFT_SIDE:
                case BoxLocation.TOP_LEFT:
                case BoxLocation.BOTTOM_LEFT:
                    if (width < CROP_MIN_SIZE)
                        left = right - CROP_MIN_SIZE;
                break;
                
                case BoxLocation.RIGHT_SIDE:
                case BoxLocation.TOP_RIGHT:
                case BoxLocation.BOTTOM_RIGHT:
                    if (width < CROP_MIN_SIZE)
                        right = left + CROP_MIN_SIZE;
                break;

                default:
                break;
            }

            switch (in_manipulation) {
                case BoxLocation.TOP_SIDE:
                case BoxLocation.TOP_LEFT:
                case BoxLocation.TOP_RIGHT:
                    if (height < CROP_MIN_SIZE)
                        top = bottom - CROP_MIN_SIZE;
                break;

                case BoxLocation.BOTTOM_SIDE:
                case BoxLocation.BOTTOM_LEFT:
                case BoxLocation.BOTTOM_RIGHT:
                    if (height < CROP_MIN_SIZE)
                        bottom = top + CROP_MIN_SIZE;
                break;
                
                default:
                break;
            }
        } else {
            if ((left < 0) || (top < 0) || (right > photo_right_edge) ||
                (bottom > photo_bottom_edge) || (width < CROP_MIN_SIZE) ||
                (height < CROP_MIN_SIZE)) {
                    revert_crop(out left, out top, out right, out bottom);
            }
        }
       
        Box new_crop = Box(left, top, right, bottom);
        
        if (in_manipulation != BoxLocation.INSIDE)
            crop_resized(new_crop);
        else
            crop_moved(new_crop);
        
        // load new values
        scaled_crop = new_crop;

        if (get_constraint_aspect_ratio() == ANY_ASPECT_RATIO) {
            custom_init_width = scaled_crop.get_width();
            custom_init_height = scaled_crop.get_height();
            custom_aspect_ratio = ((float) custom_init_width) / ((float) custom_init_height);
        }

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
    
        public RedeyeToolWindow(Gtk.Window container, RedeyeTool tool) {
            base(container, tool);
            
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

        redeye_tool_window = new RedeyeToolWindow(canvas.get_container(), this);
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

        public AdjustToolWindow(Gtk.Window container, AdjustTool tool) {
            base(container, tool);

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
        adjust_tool_window = new AdjustToolWindow(canvas.get_container(), this);
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
            ? photo.get_pixbuf_with_exceptions(scaling, TransformablePhoto.Exception.ADJUST) 
            : null;
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

