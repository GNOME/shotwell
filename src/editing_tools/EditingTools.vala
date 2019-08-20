/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* This file is the master unit file for the EditingTools unit.  It should be edited to include
 * whatever code is deemed necessary.
 *
 * The init() and terminate() methods are mandatory.
 *
 * If the unit needs to be configured prior to initialization, add the proper parameters to
 * the preconfigure() method, implement it, and ensure in init() that it's been called.
 */

namespace EditingTools {

// preconfigure may be deleted if not used.
public void preconfigure() {
}

public void init() throws Error {
}

public void terminate() {
}

public abstract class EditingToolWindow : Gtk.Window {
    private const int FRAME_BORDER = 6;

    private Gtk.Frame layout_frame = new Gtk.Frame(null);
    private bool user_moved = false;

    protected EditingToolWindow(Gtk.Window container) {
        set_decorated(false);
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
        set_can_focus(true);

        // Needed to prevent the (spurious) 'This event was synthesised outside of GDK'
        // warnings after a keypress.
        // TODO: Check if really still necessary
        Log.set_handler("Gdk", LogLevelFlags.LEVEL_WARNING, suppress_warnings);
    }

    ~EditingToolWindow() {
        Log.set_handler("Gdk", LogLevelFlags.LEVEL_WARNING, Log.default_handler);   
    }

    public override void add(Gtk.Widget widget) {
        layout_frame.add(widget);
    }

    public bool has_user_moved() {
        return user_moved;
    }

    public override bool key_press_event(Gdk.EventKey event) {
        if (base.key_press_event(event)) {
            return true;
        }
        return AppWindow.get_instance().key_press_event(event);
    }

    public override bool button_press_event(Gdk.EventButton event) {
        // LMB only
        if (event.button != 1)
            return (base.button_press_event != null) ? base.button_press_event(event) : true;

        begin_move_drag((int) event.button, (int) event.x_root, (int) event.y_root, event.time);
        user_moved = true;

        return true;
    }

    public override void realize() {
        (this as Gtk.Widget).set_opacity(Resources.TRANSIENT_WINDOW_OPACITY);
        
        base.realize();
    }

    private void suppress_warnings(string? log_domain, LogLevelFlags log_levels, string message) {
        // do nothing.
    }
}

// The PhotoCanvas is an interface object between an EditingTool and its host.  It provides objects
// and primitives for an EditingTool to obtain information about the image, to draw on the host's
// canvas, and to be signalled when the canvas and its pixbuf changes (is resized).
public abstract class PhotoCanvas {
    private Gtk.Window container;
    private Gdk.Window drawing_window;
    private Photo photo;
    private Cairo.Context default_ctx;
    private Dimensions surface_dim;
    private Cairo.Surface scaled;
    private Gdk.Pixbuf scaled_pixbuf;
    private Gdk.Rectangle scaled_position;

    protected PhotoCanvas(Gtk.Window container, Gdk.Window drawing_window, Photo photo,
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

    public Gdk.Window get_drawing_window() {
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
    // If these methods are not used, all painting to the drawable should be offet by
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
        default_ctx.save();

        default_ctx.set_operator(Cairo.Operator.SOURCE);
        default_ctx.set_source_surface(scaled, scaled_position.x, scaled_position.y);
        default_ctx.rectangle(scaled_position.x + x, scaled_position.y + y,
            width - 1, 1);
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

        // Ticket #3146 - artifacting when moving the crop box or
        // enlarging it from the lower right.
        // We now no longer subtract one from the height before choosing
        // a region to erase.
        default_ctx.set_operator(Cairo.Operator.SOURCE);
        default_ctx.set_source_surface(scaled, scaled_position.x, scaled_position.y);
        default_ctx.rectangle(scaled_position.x + x, scaled_position.y + y,
            1, height);
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

        drawing_window.invalidate_rect(rect, false);
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

public abstract class EditingTool {
    public PhotoCanvas canvas = null;

    private EditingToolWindow tool_window = null;
    protected Cairo.Surface surface;
    public string name;

    [CCode (has_target=false)]
    public delegate EditingTool Factory();

    public signal void activated();

    public signal void deactivated();

    public signal void applied(Command? command, Gdk.Pixbuf? new_pixbuf, Dimensions new_max_dim,
        bool needs_improvement);

    public signal void cancelled();

    public signal void aborted();

    protected EditingTool(string name) {
        this.name = name;
    }

    // base.activate() should always be called by an overriding member to ensure the base class
    // gets to set up and store the PhotoCanvas in the canvas member field.  More importantly,
    // the activated signal is called here, and should only be called once the tool is completely
    // initialized.
    public virtual void activate(PhotoCanvas canvas) {
        // multiple activates are not tolerated
        assert(this.canvas == null);
        assert(tool_window == null);

        this.canvas = canvas;

        tool_window = get_tool_window();
        if (tool_window != null)
            tool_window.key_press_event.connect(on_keypress);

        activated();
    }

    // Like activate(), this should always be called from an overriding subclass.
    public virtual void deactivate() {
        // multiple deactivates are tolerated
        if (canvas == null && tool_window == null)
            return;

        canvas = null;

        if (tool_window != null) {
            tool_window.key_press_event.disconnect(on_keypress);
            tool_window = null;
        }

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
    // If returns non-null, should also fill max_dim with the maximum dimensions of the original
    // image, as the editing host may not always scale images up to fit the viewport.
    //
    // Note this this method doesn't need to be returning the "proper" pixbuf on-the-fly (i.e.
    // a pixbuf with unsaved tool edits in it).  That can be handled in the paint() virtual method.
    public virtual Gdk.Pixbuf? get_display_pixbuf(Scaling scaling, Photo photo,
        out Dimensions max_dim) throws Error {
        max_dim = Dimensions();

        return null;
    }

    public virtual void on_left_click(int x, int y) {
    }

    public virtual void on_left_released(int x, int y) {
    }

    public virtual void on_motion(int x, int y, Gdk.ModifierType mask) {
    }

    public virtual bool on_leave_notify_event(){
        return false;
    }

    public virtual bool on_keypress(Gdk.EventKey event) {
        // check for an escape/abort first
        if (Gdk.keyval_name(event.keyval) == "Escape") {
            notify_cancel();

            return true;
        }

        return false;
    }

    public virtual void paint(Cairo.Context ctx) {
    }

    // Helper function that fires the cancelled signal.  (Can be connected to other signals.)
    protected void notify_cancel() {
        cancelled();
    }
}

public class CropTool : EditingTool {
    private const double CROP_INIT_X_PCT = 0.15;
    private const double CROP_INIT_Y_PCT = 0.15;

    private const int CROP_MIN_SIZE = 8;

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
    private const float MIN_ASPECT_RATIO = 1.0f / 64.0f;
    private const float MAX_ASPECT_RATIO = 64.0f;

    private class ConstraintDescription {
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
        
        public bool is_separator() {
            return !is_pivotable && aspect_ratio == SEPARATOR;
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

        public Gtk.Button ok_button = new Gtk.Button.with_label(Resources.CROP_LABEL);
        public Gtk.Button cancel_button = new Gtk.Button.with_mnemonic(Resources.CANCEL_LABEL);
        public Gtk.ComboBox constraint_combo;
        public Gtk.Button pivot_reticle_button = new Gtk.Button();
        public Gtk.Entry custom_width_entry = new Gtk.Entry();
        public Gtk.Entry custom_height_entry = new Gtk.Entry();
        public Gtk.Label custom_mulsign_label = new Gtk.Label.with_mnemonic("x");
        public Gtk.Entry most_recently_edited = null;
        public Gtk.Box response_layout = null;
        public Gtk.Box layout = null;
        public int normal_width = -1;
        public int normal_height = -1;

        public CropToolWindow(Gtk.Window container) {
            base(container);

            cancel_button.set_tooltip_text(_("Return to current photo dimensions"));
            cancel_button.set_image_position(Gtk.PositionType.LEFT);

            ok_button.set_tooltip_text(_("Set the crop for this photo"));
            ok_button.set_image_position(Gtk.PositionType.LEFT);

            constraint_combo = new Gtk.ComboBox();
            Gtk.CellRendererText combo_text_renderer = new Gtk.CellRendererText();
            constraint_combo.pack_start(combo_text_renderer, true);
            constraint_combo.add_attribute(combo_text_renderer, "text", 0);
            constraint_combo.set_row_separator_func(constraint_combo_separator_func);
            constraint_combo.set_active(0);

            var image = new Gtk.Image.from_icon_name("crop-pivot-reticle-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            pivot_reticle_button.set_image (image);
            pivot_reticle_button.set_tooltip_text(_("Pivot the crop rectangle between portrait and landscape orientations"));

            custom_width_entry.set_width_chars(4);
            custom_width_entry.editable = true;
            custom_height_entry.set_width_chars(4);
            custom_height_entry.editable = true;

            response_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            response_layout.homogeneous = true;
            response_layout.add(cancel_button);
            response_layout.add(ok_button);

            layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            layout.add(constraint_combo);
            layout.add(pivot_reticle_button);
            layout.add(response_layout);

            add(layout);
        }

        private static bool constraint_combo_separator_func(Gtk.TreeModel model, Gtk.TreeIter iter) {
            Value val;
            model.get_value(iter, 0, out val);

            return (val.dup_string() == "-");
        }
    }

    private CropToolWindow crop_tool_window = null;
    private Gdk.CursorType current_cursor_type = Gdk.CursorType.LEFT_PTR;
    private BoxLocation in_manipulation = BoxLocation.OUTSIDE;
    private Cairo.Context wide_black_ctx = null;
    private Cairo.Context wide_white_ctx = null;
    private Cairo.Context thin_white_ctx = null;
    private Cairo.Context text_ctx = null;

    // This is where we draw our crop tool
    private Cairo.Surface crop_surface = null;

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
        base("CropTool");
    }

    public static CropTool factory() {
        return new CropTool();
    }

    public static bool is_available(Photo photo, Scaling scaling) {
        Dimensions dim = scaling.get_scaled_dimensions(photo.get_original_dimensions());

        return dim.width > CROP_MIN_SIZE && dim.height > CROP_MIN_SIZE;
    }

    private static ConstraintDescription[] create_constraints() {
        ConstraintDescription[] result = new ConstraintDescription[0];

        result += new ConstraintDescription(_("Unconstrained"), 0, 0, false, ANY_ASPECT_RATIO);
        result += new ConstraintDescription(_("Square"), 1, 1, false);
        result += new ConstraintDescription(_("Screen"), 0, 0, true, SCREEN_ASPECT_RATIO);
        result += new ConstraintDescription(_("Original Size"), 0, 0, true, ORIGINAL_ASPECT_RATIO);
        result += new ConstraintDescription(_("-"), 0, 0, false, SEPARATOR);
        result += new ConstraintDescription(_("SD Video (4 ∶ 3)"), 4, 3, true);
        result += new ConstraintDescription(_("HD Video (16 ∶ 9)"), 16, 9, true);
        result += new ConstraintDescription(_("-"), 0, 0, false, SEPARATOR);
        result += new ConstraintDescription(_("Wallet (2 × 3 in.)"), 3, 2, true);
        result += new ConstraintDescription(_("Notecard (3 × 5 in.)"), 5, 3, true);
        result += new ConstraintDescription(_("4 × 6 in."), 6, 4, true);
        result += new ConstraintDescription(_("5 × 7 in."), 7, 5, true);
        result += new ConstraintDescription(_("8 × 10 in."), 10, 8, true);
        result += new ConstraintDescription(_("Letter (8.5 × 11 in.)"), 85, 110, true);
        result += new ConstraintDescription(_("11 × 14 in."), 14, 11, true);
        result += new ConstraintDescription(_("Tabloid (11 × 17 in.)"), 17, 11, true);
        result += new ConstraintDescription(_("16 × 20 in."), 20, 16, true);
        result += new ConstraintDescription(_("-"), 0, 0, false, SEPARATOR);
        result += new ConstraintDescription(_("Metric Wallet (9 × 13 cm)"), 13, 9, true);
        result += new ConstraintDescription(_("Postcard (10 × 15 cm)"), 15, 10, true);
        result += new ConstraintDescription(_("13 × 18 cm"), 18, 13, true);
        result += new ConstraintDescription(_("18 × 24 cm"), 24, 18, true);
        result += new ConstraintDescription(_("A4 (210 × 297 mm)"), 210, 297, true);
        result += new ConstraintDescription(_("20 × 30 cm"), 30, 20, true);
        result += new ConstraintDescription(_("24 × 40 cm"), 40, 24, true);
        result += new ConstraintDescription(_("30 × 40 cm"), 40, 30, true);
        result += new ConstraintDescription(_("A3 (297 × 420 mm)"), 420, 297, true);
        result += new ConstraintDescription(_("-"), 0, 0, false, SEPARATOR);
        result += new ConstraintDescription(_("Custom"), 0, 0, true, CUSTOM_ASPECT_RATIO);

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
            result.basis_width = canvas.get_scaled_pixbuf_position().width;
            result.basis_height = canvas.get_scaled_pixbuf_position().height;
        } else if (result.aspect_ratio == SCREEN_ASPECT_RATIO) {
            var dim = Scaling.get_screen_dimensions(AppWindow.get_instance());
            result.basis_width = dim.width;
            result.basis_height = dim.height;
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
        int width = int.parse(crop_tool_window.custom_width_entry.text);
        int height = int.parse(crop_tool_window.custom_height_entry.text);

        if(width < 1) {
            width = 1;
            crop_tool_window.custom_width_entry.set_text("%d".printf(width));
        }

        if(height < 1) {
            height = 1;
            crop_tool_window.custom_height_entry.set_text("%d".printf(height));
        }

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

    private void on_width_insert_text(string text, int length, ref int position) {
        on_entry_insert_text(crop_tool_window.custom_width_entry, text, length, ref position);
    }

    private void on_height_insert_text(string text, int length, ref int position) {
        on_entry_insert_text(crop_tool_window.custom_height_entry, text, length, ref position);
    }

    private void on_entry_insert_text(Gtk.Entry sender, string text, int length, ref int position) {
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
            sender.insert_text(new_text, (int) new_text.length, ref position);

        Signal.stop_emission_by_name(sender, "insert-text");

        entry_insert_in_progress = false;
    }

    private float get_constraint_aspect_ratio() {
        var result = get_selected_constraint().aspect_ratio;

        if (result == ORIGINAL_ASPECT_RATIO) {
            result = ((float) canvas.get_scaled_pixbuf_position().width) /
                ((float) canvas.get_scaled_pixbuf_position().height);
        } else if (result == SCREEN_ASPECT_RATIO) {
            var dim = Scaling.get_screen_dimensions(AppWindow.get_instance());
            result = ((float) dim.width) / ((float) dim.height);
        } else if (result == CUSTOM_ASPECT_RATIO) {
            result = custom_aspect_ratio;
        }
        if (reticle_orientation == ReticleOrientation.PORTRAIT)
            result = 1.0f / result;

        return result;
    }
    
    private float get_constraint_aspect_ratio_for_constraint(ConstraintDescription constraint, Photo photo) {
        float result = constraint.aspect_ratio;
        
        if (result == ORIGINAL_ASPECT_RATIO) {
            Dimensions orig_dim = photo.get_original_dimensions();
            result = ((float) orig_dim.width) / ((float) orig_dim.height);
        } else if (result == SCREEN_ASPECT_RATIO) {
            var dim = Scaling.get_screen_dimensions(AppWindow.get_instance());
            result = ((float) dim.width) / ((float) dim.height);
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
                // user may have switched away from 'Custom' without
                // accepting, so set these to default back to saved
                // values.
                custom_init_width = Config.Facade.get_instance().get_last_crop_width();
                custom_init_height = Config.Facade.get_instance().get_last_crop_height();
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

        crop_tool_window.layout.remove(crop_tool_window.constraint_combo);
        crop_tool_window.layout.remove(crop_tool_window.pivot_reticle_button);
        crop_tool_window.layout.remove(crop_tool_window.response_layout);

        crop_tool_window.layout.add(crop_tool_window.constraint_combo);
        crop_tool_window.layout.add(crop_tool_window.custom_width_entry);
        crop_tool_window.layout.add(crop_tool_window.custom_mulsign_label);
        crop_tool_window.layout.add(crop_tool_window.custom_height_entry);
        crop_tool_window.layout.add(crop_tool_window.pivot_reticle_button);
        crop_tool_window.layout.add(crop_tool_window.response_layout);

        if (reticle_orientation == ReticleOrientation.LANDSCAPE) {
            crop_tool_window.custom_width_entry.set_text("%d".printf(custom_init_width));
            crop_tool_window.custom_height_entry.set_text("%d".printf(custom_init_height));
        } else {
            crop_tool_window.custom_width_entry.set_text("%d".printf(custom_init_height));
            crop_tool_window.custom_height_entry.set_text("%d".printf(custom_init_width));
        }
        custom_aspect_ratio = ((float) custom_init_width) / ((float) custom_init_height);

        crop_tool_window.show_all();

        constraint_mode = ConstraintMode.CUSTOM;
    }

    private void set_normal_constraint_mode() {
        if (constraint_mode == ConstraintMode.NORMAL)
            return;

        crop_tool_window.layout.remove(crop_tool_window.constraint_combo);
        crop_tool_window.layout.remove(crop_tool_window.custom_width_entry);
        crop_tool_window.layout.remove(crop_tool_window.custom_mulsign_label);
        crop_tool_window.layout.remove(crop_tool_window.custom_height_entry);
        crop_tool_window.layout.remove(crop_tool_window.pivot_reticle_button);
        crop_tool_window.layout.remove(crop_tool_window.response_layout);

        crop_tool_window.layout.add(crop_tool_window.constraint_combo);
        crop_tool_window.layout.add(crop_tool_window.pivot_reticle_button);
        crop_tool_window.layout.add(crop_tool_window.response_layout);

        crop_tool_window.resize(crop_tool_window.normal_width,
            crop_tool_window.normal_height);

        crop_tool_window.show_all();

        constraint_mode = ConstraintMode.NORMAL;
    }

    private Box constrain_crop(Box crop) {
        float user_aspect_ratio = get_constraint_aspect_ratio();
        if (user_aspect_ratio == ANY_ASPECT_RATIO)
            return crop;

        // PHASE 1: Scale to the desired aspect ratio, preserving area and center.
        float old_area = (float) (crop.get_width() * crop.get_height());
        crop.adjust_height((int) Math.sqrt(old_area / user_aspect_ratio));
        crop.adjust_width((int) Math.sqrt(old_area * user_aspect_ratio));
        
        // PHASE 2: Crop to the image boundary.
        Dimensions image_size = get_photo_dimensions();
        double angle;
        canvas.get_photo().get_straighten(out angle);
        crop = clamp_inside_rotated_image(crop, image_size.width, image_size.height, angle, false);

        // PHASE 3: Crop down to the aspect ratio if necessary.
        if (crop.get_width() >= crop.get_height() * user_aspect_ratio)  // possibly too wide
            crop.adjust_width((int) (crop.get_height() * user_aspect_ratio));
        else    // possibly too tall
            crop.adjust_height((int) (crop.get_width() / user_aspect_ratio));
        
        return crop;
    }
    
    private ConstraintDescription? get_last_constraint(out int index) {
        index = Config.Facade.get_instance().get_last_crop_menu_choice();
        
        return (index < constraints.length) ? constraints[index] : null;
    }
    
    public override void activate(PhotoCanvas canvas) {
        bind_canvas_handlers(canvas);

        prepare_ctx(canvas.get_default_ctx(), canvas.get_surface_dim());

        if (crop_surface != null)
            crop_surface = null;

        crop_surface = new Cairo.ImageSurface(Cairo.Format.ARGB32,
            canvas.get_scaled_pixbuf_position().width,
            canvas.get_scaled_pixbuf_position().height);

        Cairo.Context ctx = new Cairo.Context(crop_surface);
        ctx.set_source_rgba(0.0, 0.0, 0.0, 1.0);
        ctx.paint();

        // create the crop tool window, where the user can apply or cancel the crop
        crop_tool_window = new CropToolWindow(canvas.get_container());

        // set up the constraint combo box
        crop_tool_window.constraint_combo.set_model(constraint_list);
        if(!canvas.get_photo().has_crop()) {
            int index;
            ConstraintDescription? desc = get_last_constraint(out index);
            if (desc != null && !desc.is_separator())
                crop_tool_window.constraint_combo.set_active(index);
        }
        else {
            // get aspect ratio of current photo
            Photo photo = canvas.get_photo();
            Dimensions cropped_dim = photo.get_dimensions();
            float ratio = (float) cropped_dim.width / (float) cropped_dim.height;
            for (int index = 1; index < constraints.length; index++) {
                if (Math.fabs(ratio - get_constraint_aspect_ratio_for_constraint(constraints[index], photo)) < 0.005)
                    crop_tool_window.constraint_combo.set_active(index);
                }
        }
        
        // set up the pivot reticle button
        update_pivot_button_state();
        reticle_orientation = ReticleOrientation.LANDSCAPE;

        bind_window_handlers();

        // obtain crop dimensions and paint against the uncropped photo
        Dimensions uncropped_dim = canvas.get_photo().get_dimensions(Photo.Exception.CROP);

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

        // get the custom width and height from the saved config and
        // set up the initial custom values with it.
        custom_width = Config.Facade.get_instance().get_last_crop_width();
        custom_height = Config.Facade.get_instance().get_last_crop_height();
        custom_init_width = custom_width;
        custom_init_height = custom_height;
        pre_aspect_ratio = ((float) custom_init_width) / ((float) custom_init_height);

        constraint_mode = ConstraintMode.NORMAL;

        base.activate(canvas);

        crop_tool_window.show_all();

        // was 'custom' the most-recently-chosen menu item?
        if(!canvas.get_photo().has_crop()) {
            ConstraintDescription? desc = get_last_constraint(null);
            if (desc != null && !desc.is_separator() && desc.aspect_ratio == CUSTOM_ASPECT_RATIO)
                set_custom_constraint_mode();
        }

        // since we no longer just run with the default, but rather
        // a saved value, we'll behave as if the saved constraint has
        // just been changed to so that everything gets updated and
        // the canvas stays in sync.
        Box new_crop = constrain_crop(scaled_crop);

        crop_resized(new_crop);
        scaled_crop = new_crop;
        canvas.invalidate_area(new_crop);
        canvas.repaint();

        pre_aspect_ratio = get_constraint_aspect_ratio();
    }

    private void bind_canvas_handlers(PhotoCanvas canvas) {
        canvas.new_surface.connect(prepare_ctx);
        canvas.resized_scaled_pixbuf.connect(on_resized_pixbuf);
    }

    private void unbind_canvas_handlers(PhotoCanvas canvas) {
        canvas.new_surface.disconnect(prepare_ctx);
        canvas.resized_scaled_pixbuf.disconnect(on_resized_pixbuf);
    }

    private void bind_window_handlers() {
        crop_tool_window.key_press_event.connect(on_keypress);
        crop_tool_window.ok_button.clicked.connect(on_crop_ok);
        crop_tool_window.cancel_button.clicked.connect(notify_cancel);
        crop_tool_window.constraint_combo.changed.connect(constraint_changed);
        crop_tool_window.pivot_reticle_button.clicked.connect(on_pivot_button_clicked);

        // set up the custom width and height entry boxes
        crop_tool_window.custom_width_entry.focus_out_event.connect(on_width_entry_focus_out);
        crop_tool_window.custom_height_entry.focus_out_event.connect(on_height_entry_focus_out);
        crop_tool_window.custom_width_entry.insert_text.connect(on_width_insert_text);
        crop_tool_window.custom_height_entry.insert_text.connect(on_height_insert_text);
    }

    private void unbind_window_handlers() {
        crop_tool_window.key_press_event.disconnect(on_keypress);
        crop_tool_window.ok_button.clicked.disconnect(on_crop_ok);
        crop_tool_window.cancel_button.clicked.disconnect(notify_cancel);
        crop_tool_window.constraint_combo.changed.disconnect(constraint_changed);
        crop_tool_window.pivot_reticle_button.clicked.disconnect(on_pivot_button_clicked);

        // set up the custom width and height entry boxes
        crop_tool_window.custom_width_entry.focus_out_event.disconnect(on_width_entry_focus_out);
        crop_tool_window.custom_height_entry.focus_out_event.disconnect(on_height_entry_focus_out);
        crop_tool_window.custom_width_entry.insert_text.disconnect(on_width_insert_text);
    }

    public override bool on_keypress(Gdk.EventKey event) {
        if ((Gdk.keyval_name(event.keyval) == "KP_Enter") ||
            (Gdk.keyval_name(event.keyval) == "Enter") ||
            (Gdk.keyval_name(event.keyval) == "Return")) {
            on_crop_ok();
            return true;
        }

        return base.on_keypress(event);
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
        if (canvas != null)
            unbind_canvas_handlers(canvas);

        if (crop_tool_window != null) {
            unbind_window_handlers();
            crop_tool_window.hide();
            crop_tool_window.destroy();
            crop_tool_window = null;
        }

        // make sure the cursor isn't set to a modify indicator
        if (canvas != null) {
            var drawing_window = canvas.get_drawing_window ();
            var display = drawing_window.get_display ();
            var cursor = new Gdk.Cursor.for_display (display,
                                                     Gdk.CursorType.LEFT_PTR);
            drawing_window.set_cursor (cursor);
        }

        crop_surface = null;

        base.deactivate();
    }

    public override EditingToolWindow? get_tool_window() {
        return crop_tool_window;
    }

    public override Gdk.Pixbuf? get_display_pixbuf(Scaling scaling, Photo photo,
        out Dimensions max_dim) throws Error {
        max_dim = photo.get_dimensions(Photo.Exception.CROP);

        return photo.get_pixbuf_with_options(scaling, Photo.Exception.CROP);
    }

    private void prepare_ctx(Cairo.Context ctx, Dimensions dim) {
        wide_black_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(wide_black_ctx, "#000");
        wide_black_ctx.set_line_width(1);

        wide_white_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(wide_white_ctx, "#FFF");
        wide_white_ctx.set_line_width(1);

        thin_white_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(thin_white_ctx, "#FFF");
        thin_white_ctx.set_line_width(0.5);

        text_ctx = new Cairo.Context(ctx.get_target());
        text_ctx.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
    }

    private void on_resized_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled, Gdk.Rectangle scaled_position) {
        Dimensions new_dim = Dimensions.for_pixbuf(scaled);
        Dimensions uncropped_dim = canvas.get_photo().get_dimensions(Photo.Exception.CROP);

        // rescale to full crop
        Box crop = scaled_crop.get_scaled_similar(old_dim, uncropped_dim);

        // rescale back to new size
        scaled_crop = crop.get_scaled_similar(uncropped_dim, new_dim);
        if (crop_surface != null)
            crop_surface = null;

        crop_surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, scaled.width, scaled.height);
        Cairo.Context ctx = new Cairo.Context(crop_surface);
        ctx.set_source_rgba(0.0, 0.0, 0.0, 1.0);
        ctx.paint();

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
        canvas.repaint();
    }

    public override void paint(Cairo.Context default_ctx) {
        // fill region behind the crop surface with neutral color
        int w = canvas.get_drawing_window().get_width();
        int h = canvas.get_drawing_window().get_height();

        default_ctx.set_source_rgba(0.0, 0.0, 0.0, 1.0);
        default_ctx.rectangle(0, 0, w, h);
        default_ctx.fill();
        default_ctx.paint();

        Cairo.Context ctx = new Cairo.Context(crop_surface);
        ctx.set_operator(Cairo.Operator.SOURCE);
        ctx.set_source_rgba(0.0, 0.0, 0.0, 0.5);
        ctx.paint();

        // paint exposed (cropped) part of pixbuf minus crop border
        ctx.set_source_rgba(0.0, 0.0, 0.0, 0.0);
        ctx.rectangle(scaled_crop.left, scaled_crop.top, scaled_crop.get_width(),
            scaled_crop.get_height());
        ctx.fill();
        canvas.paint_surface(crop_surface, true);

        // paint crop tool last
        paint_crop_tool(scaled_crop);
    }

    private void on_crop_ok() {
        // user's clicked OK, save the combobox choice and width/height.
        // safe to do, even if not in 'custom' mode - the previous values
        // will just get saved again.
        Config.Facade.get_instance().set_last_crop_menu_choice(
            crop_tool_window.constraint_combo.get_active());
        Config.Facade.get_instance().set_last_crop_width(custom_width);
        Config.Facade.get_instance().set_last_crop_height(custom_height);

        // scale screen-coordinate crop to photo's coordinate system
        Box crop = scaled_crop.get_scaled_similar(
            Dimensions.for_rectangle(canvas.get_scaled_pixbuf_position()),
            canvas.get_photo().get_dimensions(Photo.Exception.CROP));

        // crop the current pixbuf and offer it to the editing host
        Gdk.Pixbuf cropped = new Gdk.Pixbuf.subpixbuf(canvas.get_scaled_pixbuf(), scaled_crop.left,
            scaled_crop.top, scaled_crop.get_width(), scaled_crop.get_height());

        // signal host; we have a cropped image, but it will be scaled upward, and so a better one
        // should be fetched
        applied(new CropCommand(canvas.get_photo(), crop, Resources.CROP_LABEL,
            Resources.CROP_TOOLTIP), cropped, crop.get_dimensions(), true);
    }

    private void update_cursor(int x, int y) {
        // scaled_crop is not maintained relative to photo's position on canvas
        Gdk.Rectangle scaled_pos = canvas.get_scaled_pixbuf_position();
        Box offset_scaled_crop = scaled_crop.get_offset(scaled_pos.x, scaled_pos.y);

        Gdk.CursorType cursor_type = Gdk.CursorType.LEFT_PTR;
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
                // use Gdk.CursorType.LEFT_PTR
            break;
        }

        if (cursor_type != current_cursor_type) {
            var drawing_window = canvas.get_drawing_window ();
            var display = drawing_window.get_display ();
            var cursor = new Gdk.Cursor.for_display (display, cursor_type);
            drawing_window.set_cursor (cursor);
            current_cursor_type = cursor_type;
        }
    }

    private int eval_radial_line(double center_x, double center_y, double bounds_x,
        double bounds_y, double user_x) {
        double decision_slope = (bounds_y - center_y) / (bounds_x - center_x);
        double decision_intercept = bounds_y - (decision_slope * bounds_x);

        return (int) (decision_slope * user_x + decision_intercept);
    }

    // Return the dimensions of the uncropped source photo scaled to canvas coordinates.
    private Dimensions get_photo_dimensions() {
        Dimensions photo_dims = canvas.get_photo().get_dimensions(Photo.Exception.CROP);
        Dimensions surface_dims = canvas.get_surface_dim();
        double scale_factor = double.min((double) surface_dims.width / photo_dims.width,
                                         (double) surface_dims.height / photo_dims.height);
        scale_factor = double.min(scale_factor, 1.0);

        photo_dims = canvas.get_photo().get_dimensions(
            Photo.Exception.CROP | Photo.Exception.STRAIGHTEN);

        return { (int) (photo_dims.width * scale_factor),
                 (int) (photo_dims.height * scale_factor) };
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

        Dimensions photo_dims = get_photo_dimensions();
        double angle;
        canvas.get_photo().get_straighten(out angle);
        
        Box new_crop;
        if (get_constraint_aspect_ratio() == ANY_ASPECT_RATIO) {
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

            // preliminary crop region has been chosen, now clamp it inside the
            // image as needed.

            new_crop = clamp_inside_rotated_image(
                Box(left, top, right, bottom),
                photo_dims.width, photo_dims.height, angle,
                in_manipulation == BoxLocation.INSIDE);
                
        } else {
            // one of the constrained modes is active; revert instead of clamping so
            // that aspect ratio stays intact

            new_crop = Box(left, top, right, bottom);
            Box adjusted = clamp_inside_rotated_image(new_crop,
                photo_dims.width, photo_dims.height, angle,
                in_manipulation == BoxLocation.INSIDE);
            
            if (adjusted != new_crop || width < CROP_MIN_SIZE || height < CROP_MIN_SIZE) {
                new_crop = scaled_crop;     // revert crop move
            }
        }

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

        canvas.invalidate_area(scaled_crop);

        Box horizontal;
        bool horizontal_enlarged;
        Box vertical;
        bool vertical_enlarged;
        BoxComplements complements = scaled_crop.resized_complements(new_crop, out horizontal,
            out horizontal_enlarged, out vertical, out vertical_enlarged);

        // this should never happen ... this means that the operation wasn't a resize
        assert(complements != BoxComplements.NONE);

        if (complements == BoxComplements.HORIZONTAL || complements == BoxComplements.BOTH)
            set_area_alpha(horizontal, horizontal_enlarged ? 0.0 : 0.5);

        if (complements == BoxComplements.VERTICAL || complements == BoxComplements.BOTH)
            set_area_alpha(vertical, vertical_enlarged ? 0.0 : 0.5);

        paint_crop_tool(new_crop);
        canvas.invalidate_area(new_crop);
    }

    private void crop_moved(Box new_crop) {
        if (scaled_crop.equals(new_crop)) {
            // no change
            return;
        }

        canvas.invalidate_area(scaled_crop);

        set_area_alpha(scaled_crop, 0.5);
        set_area_alpha(new_crop, 0.0);


        // paint crop in new location
        paint_crop_tool(new_crop);
        canvas.invalidate_area(new_crop);
    }

    private void set_area_alpha(Box area, double alpha) {
        Cairo.Context ctx = new Cairo.Context(crop_surface);
        ctx.set_operator(Cairo.Operator.SOURCE);
        ctx.set_source_rgba(0.0, 0.0, 0.0, alpha);
        ctx.rectangle(area.left, area.top, area.get_width(), area.get_height());
        ctx.fill();
        canvas.paint_surface_area(crop_surface, area, true);
    }

    private void paint_crop_tool(Box crop) {
        // paint rule-of-thirds lines and current dimensions if user is manipulating the crop
        if (in_manipulation != BoxLocation.OUTSIDE) {
            int one_third_x = crop.get_width() / 3;
            int one_third_y = crop.get_height() / 3;

            canvas.draw_horizontal_line(thin_white_ctx, crop.left, crop.top + one_third_y, crop.get_width());
            canvas.draw_horizontal_line(thin_white_ctx, crop.left, crop.top + (one_third_y * 2), crop.get_width());

            canvas.draw_vertical_line(thin_white_ctx, crop.left + one_third_x, crop.top, crop.get_height());
            canvas.draw_vertical_line(thin_white_ctx, crop.left + (one_third_x * 2), crop.top, crop.get_height());

            // current dimensions
            // scale screen-coordinate crop to photo's coordinate system
            Box adj_crop = scaled_crop.get_scaled_similar(
                Dimensions.for_rectangle(canvas.get_scaled_pixbuf_position()),
                canvas.get_photo().get_dimensions(Photo.Exception.CROP));
            string text = adj_crop.get_width().to_string() + "x" + adj_crop.get_height().to_string();
            int x = crop.left + crop.get_width() / 2;
            int y = crop.top + crop.get_height() / 2;
            canvas.draw_text(text_ctx, text, x, y);
        }

        // outer rectangle ... outer line in black, inner in white, corners fully black
        canvas.draw_box(wide_black_ctx, crop);
        canvas.draw_box(wide_white_ctx, crop.get_reduced(1));
        canvas.draw_box(wide_white_ctx, crop.get_reduced(2));
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

public class RedeyeTool : EditingTool {
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
            close_button.set_image_position(Gtk.PositionType.LEFT);

            apply_button.set_tooltip_text(_("Remove any red-eye effects in the selected region"));
            apply_button.set_image_position(Gtk.PositionType.LEFT);

            Gtk.Box layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            layout.add(slider_label);
            layout.add(slider);
            layout.add(close_button);
            layout.add(apply_button);

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
    private Gdk.Cursor cached_arrow_cursor;
    private Gdk.Cursor cached_grab_cursor;
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
        wider_gray_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(wider_gray_ctx, "#111");
        wider_gray_ctx.set_line_width(3);

        thin_white_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(thin_white_ctx, "#FFF");
        thin_white_ctx.set_line_width(1);
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

        var display = canvas.get_drawing_window().get_display();
        cached_arrow_cursor = new Gdk.Cursor.for_display(display, Gdk.CursorType.LEFT_PTR);
        cached_grab_cursor = new Gdk.Cursor.for_display(display, Gdk.CursorType.FLEUR);

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

    public override bool on_keypress(Gdk.EventKey event) {
        if ((Gdk.keyval_name(event.keyval) == "KP_Enter") ||
            (Gdk.keyval_name(event.keyval) == "Enter") ||
            (Gdk.keyval_name(event.keyval) == "Return")) {
            on_close();
            return true;
        }

        return base.on_keypress(event);
    }
}

public class AdjustTool : EditingTool {
    private const int SLIDER_WIDTH = 200;
    private const uint SLIDER_DELAY_MSEC = 100;

    private class AdjustToolWindow : EditingToolWindow {
        public Gtk.Scale exposure_slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL,
            ExposureTransformation.MIN_PARAMETER, ExposureTransformation.MAX_PARAMETER,
            1.0);
        public Gtk.Scale contrast_slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL,
            ContrastTransformation.MIN_PARAMETER, ContrastTransformation.MAX_PARAMETER,
            1.0);
        public Gtk.Scale saturation_slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL,
            SaturationTransformation.MIN_PARAMETER, SaturationTransformation.MAX_PARAMETER,
            1.0);
        public Gtk.Scale tint_slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL,
            TintTransformation.MIN_PARAMETER, TintTransformation.MAX_PARAMETER, 1.0);
        public Gtk.Scale temperature_slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL,
            TemperatureTransformation.MIN_PARAMETER, TemperatureTransformation.MAX_PARAMETER,
            1.0);

        public Gtk.Scale shadows_slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL,
            ShadowDetailTransformation.MIN_PARAMETER, ShadowDetailTransformation.MAX_PARAMETER,
            1.0);

        public Gtk.Scale highlights_slider = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL,
            HighlightDetailTransformation.MIN_PARAMETER, HighlightDetailTransformation.MAX_PARAMETER,
            1.0);

        public Gtk.Button ok_button = new Gtk.Button.with_mnemonic(Resources.OK_LABEL);
        public Gtk.Button reset_button = new Gtk.Button.with_mnemonic(_("_Reset"));
        public Gtk.Button cancel_button = new Gtk.Button.with_mnemonic(Resources.CANCEL_LABEL);
        public RGBHistogramManipulator histogram_manipulator = new RGBHistogramManipulator();

        public AdjustToolWindow(Gtk.Window container) {
            base(container);

            Gtk.Grid slider_organizer = new Gtk.Grid();
            slider_organizer.set_column_homogeneous(false);
            slider_organizer.set_row_spacing(12);
            slider_organizer.set_column_spacing(12);
            slider_organizer.set_margin_start(12);
            slider_organizer.set_margin_bottom(12);

            Gtk.Label exposure_label = new Gtk.Label.with_mnemonic(_("Exposure:"));
            exposure_label.halign = Gtk.Align.START;
            exposure_label.valign = Gtk.Align.CENTER;
            slider_organizer.attach(exposure_label, 0, 0, 1, 1);
            slider_organizer.attach(exposure_slider, 1, 0, 1, 1);
            exposure_slider.set_size_request(SLIDER_WIDTH, -1);
            exposure_slider.set_value_pos(Gtk.PositionType.RIGHT);
            exposure_slider.set_margin_end(0);

            Gtk.Label contrast_label = new Gtk.Label.with_mnemonic(_("Contrast:"));
            contrast_label.halign = Gtk.Align.START;
            contrast_label.valign = Gtk.Align.CENTER;
            slider_organizer.attach(contrast_label, 0, 1, 1, 1);
            slider_organizer.attach(contrast_slider, 1, 1, 1, 1);
            contrast_slider.set_size_request(SLIDER_WIDTH, -1);
            contrast_slider.set_value_pos(Gtk.PositionType.RIGHT);
            contrast_slider.set_margin_end(0);

            Gtk.Label saturation_label = new Gtk.Label.with_mnemonic(_("Saturation:"));
            saturation_label.halign = Gtk.Align.START;
            saturation_label.valign = Gtk.Align.CENTER;
            slider_organizer.attach(saturation_label, 0, 2, 1, 1);
            slider_organizer.attach(saturation_slider, 1, 2, 1, 1);
            saturation_slider.set_size_request(SLIDER_WIDTH, -1);
            saturation_slider.set_draw_value(false);
            saturation_slider.set_margin_end(0);

            Gtk.Label tint_label = new Gtk.Label.with_mnemonic(_("Tint:"));
            tint_label.halign = Gtk.Align.START;
            tint_label.valign = Gtk.Align.CENTER;
            slider_organizer.attach(tint_label, 0, 3, 1, 1);
            slider_organizer.attach(tint_slider, 1, 3, 1, 1);
            tint_slider.set_size_request(SLIDER_WIDTH, -1);
            tint_slider.set_value_pos(Gtk.PositionType.RIGHT);
            tint_slider.set_margin_end(0);

            Gtk.Label temperature_label =
                new Gtk.Label.with_mnemonic(_("Temperature:"));
            temperature_label.halign = Gtk.Align.START;
            temperature_label.valign = Gtk.Align.CENTER;
            slider_organizer.attach(temperature_label, 0, 4, 1, 1);
            slider_organizer.attach(temperature_slider, 1, 4, 1, 1);
            temperature_slider.set_size_request(SLIDER_WIDTH, -1);
            temperature_slider.set_value_pos(Gtk.PositionType.RIGHT);
            temperature_slider.set_margin_end(0);

            Gtk.Label shadows_label = new Gtk.Label.with_mnemonic(_("Shadows:"));
            shadows_label.halign = Gtk.Align.START;
            shadows_label.valign = Gtk.Align.CENTER;
            slider_organizer.attach(shadows_label, 0, 5, 1, 1);
            slider_organizer.attach(shadows_slider, 1, 5, 1, 1);
            shadows_slider.set_size_request(SLIDER_WIDTH, -1);
            shadows_slider.set_value_pos(Gtk.PositionType.RIGHT);
            // FIXME: Hack to make the slider the same length as the other. Find out why it is aligned
            // Differently (probably because it only has positive values)
            shadows_slider.set_margin_end(5);

            Gtk.Label highlights_label = new Gtk.Label.with_mnemonic(_("Highlights:"));
            highlights_label.halign = Gtk.Align.START;
            highlights_label.valign = Gtk.Align.CENTER;
            slider_organizer.attach(highlights_label, 0, 6, 1, 1);
            slider_organizer.attach(highlights_slider, 1, 6, 1, 1);
            highlights_slider.set_size_request(SLIDER_WIDTH, -1);
            highlights_slider.set_value_pos(Gtk.PositionType.RIGHT);
            highlights_slider.set_margin_end(0);

            Gtk.Box button_layouter = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            button_layouter.set_homogeneous(true);
            button_layouter.pack_start(cancel_button, true, true, 1);
            button_layouter.pack_start(reset_button, true, true, 1);
            button_layouter.pack_start(ok_button, true, true, 1);

            histogram_manipulator.set_margin_start (12);
            histogram_manipulator.set_margin_end (12);
            histogram_manipulator.set_margin_top (12);
            histogram_manipulator.set_margin_bottom (8);

            Gtk.Box pane_layouter = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            pane_layouter.add(histogram_manipulator);
            pane_layouter.add(slider_organizer);
            pane_layouter.add(button_layouter);
            pane_layouter.set_child_packing(histogram_manipulator, false, true, 0, Gtk.PackType.START);

            add(pane_layouter);
        }
    }

    private abstract class AdjustToolCommand : Command {
        protected weak AdjustTool owner;

        protected AdjustToolCommand(AdjustTool owner, string name, string explanation) {
            base (name, explanation);

            this.owner = owner;
            owner.deactivated.connect(on_owner_deactivated);
        }

        ~AdjustToolCommand() {
            if (owner != null)
                owner.deactivated.disconnect(on_owner_deactivated);
        }

        private void on_owner_deactivated() {
            // This reset call is by design. See notes on ticket #1946 if this is undesirable or if
            // you are planning to change it.
            AppWindow.get_command_manager().reset();
        }
    }

    private class AdjustResetCommand : AdjustToolCommand {
        private PixelTransformationBundle original;
        private PixelTransformationBundle reset;

        public AdjustResetCommand(AdjustTool owner, PixelTransformationBundle current) {
            base (owner, _("Reset Colors"), _("Reset all color adjustments to original"));

            original = current.copy();
            reset = new PixelTransformationBundle();
            reset.set_to_identity();
        }

        public override void execute() {
            owner.set_adjustments(reset);
        }

        public override void undo() {
            owner.set_adjustments(original);
        }

        public override bool compress(Command command) {
            AdjustResetCommand reset_command = command as AdjustResetCommand;
            if (reset_command == null)
                return false;

            if (reset_command.owner != owner)
                return false;

            // multiple successive resets on the same photo as good as a single
            return true;
        }
    }

    private class SliderAdjustmentCommand : AdjustToolCommand {
        private PixelTransformationType transformation_type;
        private PixelTransformation new_transformation;
        private PixelTransformation old_transformation;

        public SliderAdjustmentCommand(AdjustTool owner, PixelTransformation old_transformation,
            PixelTransformation new_transformation, string name) {
            base(owner, name, name);

            this.old_transformation = old_transformation;
            this.new_transformation = new_transformation;
            transformation_type = old_transformation.get_transformation_type();
            assert(new_transformation.get_transformation_type() == transformation_type);
        }

        public override void execute() {
            // don't update slider; it's been moved by the user
            owner.update_transformation(new_transformation);
            owner.canvas.repaint();
        }

        public override void undo() {
            owner.update_transformation(old_transformation);

            owner.unbind_window_handlers();
            owner.update_slider(old_transformation);
            owner.bind_window_handlers();

            owner.canvas.repaint();
        }

        public override void redo() {
            owner.update_transformation(new_transformation);

            owner.unbind_window_handlers();
            owner.update_slider(new_transformation);
            owner.bind_window_handlers();

            owner.canvas.repaint();
        }

        public override bool compress(Command command) {
            SliderAdjustmentCommand slider_adjustment = command as SliderAdjustmentCommand;
            if (slider_adjustment == null)
                return false;

            // same photo
            if (slider_adjustment.owner != owner)
                return false;

            // same adjustment
            if (slider_adjustment.transformation_type != transformation_type)
                return false;

            // execute the command
            slider_adjustment.execute();

            // save it's transformation as ours
            new_transformation = slider_adjustment.new_transformation;

            return true;
        }
    }

    private class AdjustEnhanceCommand : AdjustToolCommand {
        private Photo photo;
        private PixelTransformationBundle original;
        private PixelTransformationBundle enhanced = null;

        public AdjustEnhanceCommand(AdjustTool owner, Photo photo) {
            base(owner, Resources.ENHANCE_LABEL, Resources.ENHANCE_TOOLTIP);

            this.photo = photo;
            original = photo.get_color_adjustments();
        }

        public override void execute() {
            if (enhanced == null)
                enhanced = photo.get_enhance_transformations();

            owner.set_adjustments(enhanced);
        }

        public override void undo() {
            owner.set_adjustments(original);
        }

        public override bool compress(Command command) {
            // can compress both normal enhance and one with the adjust tool running
            EnhanceSingleCommand enhance_single = command as EnhanceSingleCommand;
            if (enhance_single != null) {
                Photo photo = (Photo) enhance_single.get_source();

                // multiple successive enhances are as good as a single, as long as it's on the
                // same photo
                return photo.equals(owner.canvas.get_photo());
            }

            AdjustEnhanceCommand enhance_command = command as AdjustEnhanceCommand;
            if (enhance_command == null)
                return false;

            if (enhance_command.owner != owner)
                return false;

            // multiple successive as good as a single
            return true;
        }
    }

    private AdjustToolWindow adjust_tool_window = null;
    private bool suppress_effect_redraw = false;
    private Gdk.Pixbuf draw_to_pixbuf = null;
    private Gdk.Pixbuf histogram_pixbuf = null;
    private Gdk.Pixbuf virgin_histogram_pixbuf = null;
    private PixelTransformer transformer = null;
    private PixelTransformer histogram_transformer = null;
    private PixelTransformationBundle transformations = null;
    private float[] fp_pixel_cache = null;
    private bool disable_histogram_refresh = false;
    private OneShotScheduler? temperature_scheduler = null;
    private OneShotScheduler? tint_scheduler = null;
    private OneShotScheduler? contrast_scheduler = null;
    private OneShotScheduler? saturation_scheduler = null;
    private OneShotScheduler? exposure_scheduler = null;
    private OneShotScheduler? shadows_scheduler = null;
    private OneShotScheduler? highlights_scheduler = null;

    private AdjustTool() {
        base("AdjustTool");
    }

    public static AdjustTool factory() {
        return new AdjustTool();
    }

    public static bool is_available(Photo photo, Scaling scaling) {
        return true;
    }

    public override void activate(PhotoCanvas canvas) {
        adjust_tool_window = new AdjustToolWindow(canvas.get_container());

        Photo photo = canvas.get_photo();
        transformations = photo.get_color_adjustments();
        transformer = transformations.generate_transformer();

        // the histogram transformer uses all transformations but contrast expansion
        histogram_transformer = new PixelTransformer();

        /* set up expansion */
        ExpansionTransformation expansion_trans = (ExpansionTransformation)
            transformations.get_transformation(PixelTransformationType.TONE_EXPANSION);
        adjust_tool_window.histogram_manipulator.set_left_nub_position(
            expansion_trans.get_black_point());
        adjust_tool_window.histogram_manipulator.set_right_nub_position(
            expansion_trans.get_white_point());

        /* set up shadows */
        ShadowDetailTransformation shadows_trans = (ShadowDetailTransformation)
            transformations.get_transformation(PixelTransformationType.SHADOWS);
        histogram_transformer.attach_transformation(shadows_trans);
        adjust_tool_window.shadows_slider.set_value(shadows_trans.get_parameter());

        /* set up highlights */
        HighlightDetailTransformation highlights_trans = (HighlightDetailTransformation)
            transformations.get_transformation(PixelTransformationType.HIGHLIGHTS);
        histogram_transformer.attach_transformation(highlights_trans);
        adjust_tool_window.highlights_slider.set_value(highlights_trans.get_parameter());

        /* set up temperature & tint */
        TemperatureTransformation temp_trans = (TemperatureTransformation)
            transformations.get_transformation(PixelTransformationType.TEMPERATURE);
        histogram_transformer.attach_transformation(temp_trans);
        adjust_tool_window.temperature_slider.set_value(temp_trans.get_parameter());

        TintTransformation tint_trans = (TintTransformation)
            transformations.get_transformation(PixelTransformationType.TINT);
        histogram_transformer.attach_transformation(tint_trans);
        adjust_tool_window.tint_slider.set_value(tint_trans.get_parameter());

        /* set up saturation */
        SaturationTransformation sat_trans = (SaturationTransformation)
            transformations.get_transformation(PixelTransformationType.SATURATION);
        histogram_transformer.attach_transformation(sat_trans);
        adjust_tool_window.saturation_slider.set_value(sat_trans.get_parameter());

        /* set up exposure */
        ExposureTransformation exposure_trans = (ExposureTransformation)
            transformations.get_transformation(PixelTransformationType.EXPOSURE);
        histogram_transformer.attach_transformation(exposure_trans);
        adjust_tool_window.exposure_slider.set_value(exposure_trans.get_parameter());

        /* set up contrast */
        ContrastTransformation contrast_trans = (ContrastTransformation)
            transformations.get_transformation(PixelTransformationType.CONTRAST);
        histogram_transformer.attach_transformation(contrast_trans);
        adjust_tool_window.contrast_slider.set_value(contrast_trans.get_parameter());

        bind_canvas_handlers(canvas);
        bind_window_handlers();

        draw_to_pixbuf = canvas.get_scaled_pixbuf().copy();
        init_fp_pixel_cache(canvas.get_scaled_pixbuf());

        /* if we have an 1x1 pixel image, then there's no need to deal with recomputing the
           histogram, because a histogram for a 1x1 image is meaningless. The histogram shows the
           distribution of color over all the many pixels in an image, but if an image only has
           one pixel, the notion of a "distribution over pixels" makes no sense. */
        if (draw_to_pixbuf.width == 1 && draw_to_pixbuf.height == 1)
            disable_histogram_refresh = true;

        /* don't sample the original image to create the histogram if the original image is
           sufficiently large -- if it's over 8k pixels, then we'll get pretty much the same
           histogram if we sample from a half-size image */
        if (((draw_to_pixbuf.width * draw_to_pixbuf.height) > 8192) && (draw_to_pixbuf.width > 1) &&
            (draw_to_pixbuf.height > 1)) {
            histogram_pixbuf = draw_to_pixbuf.scale_simple(draw_to_pixbuf.width / 2,
                draw_to_pixbuf.height / 2, Gdk.InterpType.HYPER);
        } else {
            histogram_pixbuf = draw_to_pixbuf.copy();
        }
        virgin_histogram_pixbuf = histogram_pixbuf.copy();

        DataCollection? owner = canvas.get_photo().get_membership();
        if (owner != null)
            owner.items_altered.connect(on_photos_altered);

        base.activate(canvas);
    }

    public override EditingToolWindow? get_tool_window() {
        return adjust_tool_window;
    }

    public override void deactivate() {
        if (canvas != null) {
            DataCollection? owner = canvas.get_photo().get_membership();
            if (owner != null)
                owner.items_altered.disconnect(on_photos_altered);

            unbind_canvas_handlers(canvas);
        }

        if (adjust_tool_window != null) {
            unbind_window_handlers();
            adjust_tool_window.hide();
            adjust_tool_window.destroy();
            adjust_tool_window = null;
        }

        draw_to_pixbuf = null;
        fp_pixel_cache = null;

        base.deactivate();
    }

    public override void paint(Cairo.Context ctx) {
        if (!suppress_effect_redraw) {
            transformer.transform_from_fp(ref fp_pixel_cache, draw_to_pixbuf);
            histogram_transformer.transform_to_other_pixbuf(virgin_histogram_pixbuf,
                histogram_pixbuf);
            if (!disable_histogram_refresh)
                adjust_tool_window.histogram_manipulator.update_histogram(histogram_pixbuf);
        }

        canvas.paint_pixbuf(draw_to_pixbuf);
    }

    public override Gdk.Pixbuf? get_display_pixbuf(Scaling scaling, Photo photo,
        out Dimensions max_dim) throws Error {
        if (!photo.has_color_adjustments()) {
            max_dim = Dimensions();

            return null;
        }

        max_dim = photo.get_dimensions();

        return photo.get_pixbuf_with_options(scaling, Photo.Exception.ADJUST);
    }

    private void on_reset() {
        AdjustResetCommand command = new AdjustResetCommand(this, transformations);
        AppWindow.get_command_manager().execute(command);
    }

    private void on_ok() {
        suppress_effect_redraw = true;

        get_tool_window().hide();

        applied(new AdjustColorsSingleCommand(canvas.get_photo(), transformations,
            Resources.ADJUST_LABEL, Resources.ADJUST_TOOLTIP), draw_to_pixbuf,
            canvas.get_photo().get_dimensions(), false);
    }

    private void update_transformations(PixelTransformationBundle new_transformations) {
        foreach (PixelTransformation transformation in new_transformations.get_transformations())
            update_transformation(transformation);
    }

    private void update_transformation(PixelTransformation new_transformation) {
        PixelTransformation old_transformation = transformations.get_transformation(
            new_transformation.get_transformation_type());

        transformer.replace_transformation(old_transformation, new_transformation);
        if (new_transformation.get_transformation_type() != PixelTransformationType.TONE_EXPANSION)
            histogram_transformer.replace_transformation(old_transformation, new_transformation);

        transformations.set(new_transformation);
    }

    private void slider_updated(PixelTransformation new_transformation, string name) {
        PixelTransformation old_transformation = transformations.get_transformation(
            new_transformation.get_transformation_type());
        SliderAdjustmentCommand command = new SliderAdjustmentCommand(this, old_transformation,
            new_transformation, name);
        AppWindow.get_command_manager().execute(command);
    }

    private void on_temperature_adjustment() {
        if (temperature_scheduler == null)
            temperature_scheduler = new OneShotScheduler("temperature", on_delayed_temperature_adjustment);

        temperature_scheduler.after_timeout(SLIDER_DELAY_MSEC, true);
    }

    private void on_delayed_temperature_adjustment() {
        TemperatureTransformation new_temp_trans = new TemperatureTransformation(
            (float) adjust_tool_window.temperature_slider.get_value());
        slider_updated(new_temp_trans, _("Temperature"));
    }

    private void on_tint_adjustment() {
        if (tint_scheduler == null)
            tint_scheduler = new OneShotScheduler("tint", on_delayed_tint_adjustment);
        tint_scheduler.after_timeout(SLIDER_DELAY_MSEC, true);
    }

    private void on_delayed_tint_adjustment() {
        TintTransformation new_tint_trans = new TintTransformation(
            (float) adjust_tool_window.tint_slider.get_value());
        slider_updated(new_tint_trans, _("Tint"));
    }

    private void on_contrast_adjustment() {
        if (this.contrast_scheduler == null)
            this.contrast_scheduler = new OneShotScheduler("contrast", on_delayed_contrast_adjustment);
        this.contrast_scheduler.after_timeout(SLIDER_DELAY_MSEC, true);
    }

    private void on_delayed_contrast_adjustment() {
        ContrastTransformation new_exp_trans = new ContrastTransformation(
            (float) adjust_tool_window.contrast_slider.get_value());
        slider_updated(new_exp_trans, _("Contrast"));
    }


    private void on_saturation_adjustment() {
        if (saturation_scheduler == null)
            saturation_scheduler = new OneShotScheduler("saturation", on_delayed_saturation_adjustment);

        saturation_scheduler.after_timeout(SLIDER_DELAY_MSEC, true);
    }

    private void on_delayed_saturation_adjustment() {
        SaturationTransformation new_sat_trans = new SaturationTransformation(
            (float) adjust_tool_window.saturation_slider.get_value());
        slider_updated(new_sat_trans, _("Saturation"));
    }

    private void on_exposure_adjustment() {
        if (exposure_scheduler == null)
            exposure_scheduler = new OneShotScheduler("exposure", on_delayed_exposure_adjustment);

        exposure_scheduler.after_timeout(SLIDER_DELAY_MSEC, true);
    }

    private void on_delayed_exposure_adjustment() {
        ExposureTransformation new_exp_trans = new ExposureTransformation(
            (float) adjust_tool_window.exposure_slider.get_value());
        slider_updated(new_exp_trans, _("Exposure"));
    }

    private void on_shadows_adjustment() {
        if (shadows_scheduler == null)
            shadows_scheduler = new OneShotScheduler("shadows", on_delayed_shadows_adjustment);

        shadows_scheduler.after_timeout(SLIDER_DELAY_MSEC, true);
    }

    private void on_delayed_shadows_adjustment() {
        ShadowDetailTransformation new_shadows_trans = new ShadowDetailTransformation(
            (float) adjust_tool_window.shadows_slider.get_value());
        slider_updated(new_shadows_trans, _("Shadows"));
    }

    private void on_highlights_adjustment() {
        if (highlights_scheduler == null)
            highlights_scheduler = new OneShotScheduler("highlights", on_delayed_highlights_adjustment);

        highlights_scheduler.after_timeout(SLIDER_DELAY_MSEC, true);
    }

    private void on_delayed_highlights_adjustment() {
        HighlightDetailTransformation new_highlights_trans = new HighlightDetailTransformation(
            (float) adjust_tool_window.highlights_slider.get_value());
        slider_updated(new_highlights_trans, _("Highlights"));
    }

    private void on_histogram_constraint() {
        int expansion_black_point =
            adjust_tool_window.histogram_manipulator.get_left_nub_position();
        int expansion_white_point =
            adjust_tool_window.histogram_manipulator.get_right_nub_position();
        ExpansionTransformation new_exp_trans =
            new ExpansionTransformation.from_extrema(expansion_black_point, expansion_white_point);
        slider_updated(new_exp_trans, _("Contrast Expansion"));
    }

    private void on_canvas_resize() {
        draw_to_pixbuf = canvas.get_scaled_pixbuf().copy();
        init_fp_pixel_cache(canvas.get_scaled_pixbuf());
    }

    private bool on_hscale_reset(Gtk.Widget widget, Gdk.EventButton event) {
        Gtk.Scale source = (Gtk.Scale) widget;

        if (event.button == 1 && event.type == Gdk.EventType.BUTTON_PRESS
            && has_only_key_modifier(event.state, Gdk.ModifierType.CONTROL_MASK)) {
            // Left Mouse Button and CTRL pressed
            source.set_value(0);

            return true;
        }

        return false;
    }

    private void bind_canvas_handlers(PhotoCanvas canvas) {
        canvas.resized_scaled_pixbuf.connect(on_canvas_resize);
    }

    private void unbind_canvas_handlers(PhotoCanvas canvas) {
        canvas.resized_scaled_pixbuf.disconnect(on_canvas_resize);
    }

    private void bind_window_handlers() {
        adjust_tool_window.ok_button.clicked.connect(on_ok);
        adjust_tool_window.reset_button.clicked.connect(on_reset);
        adjust_tool_window.cancel_button.clicked.connect(notify_cancel);
        adjust_tool_window.exposure_slider.value_changed.connect(on_exposure_adjustment);
        adjust_tool_window.contrast_slider.value_changed.connect(on_contrast_adjustment);
        adjust_tool_window.saturation_slider.value_changed.connect(on_saturation_adjustment);
        adjust_tool_window.tint_slider.value_changed.connect(on_tint_adjustment);
        adjust_tool_window.temperature_slider.value_changed.connect(on_temperature_adjustment);
        adjust_tool_window.shadows_slider.value_changed.connect(on_shadows_adjustment);
        adjust_tool_window.highlights_slider.value_changed.connect(on_highlights_adjustment);
        adjust_tool_window.histogram_manipulator.nub_position_changed.connect(on_histogram_constraint);

        adjust_tool_window.saturation_slider.button_press_event.connect(on_hscale_reset);
        adjust_tool_window.exposure_slider.button_press_event.connect(on_hscale_reset);
        adjust_tool_window.contrast_slider.button_press_event.connect(on_hscale_reset);
        adjust_tool_window.tint_slider.button_press_event.connect(on_hscale_reset);
        adjust_tool_window.temperature_slider.button_press_event.connect(on_hscale_reset);
        adjust_tool_window.shadows_slider.button_press_event.connect(on_hscale_reset);
        adjust_tool_window.highlights_slider.button_press_event.connect(on_hscale_reset);
    }

    private void unbind_window_handlers() {
        adjust_tool_window.ok_button.clicked.disconnect(on_ok);
        adjust_tool_window.reset_button.clicked.disconnect(on_reset);
        adjust_tool_window.cancel_button.clicked.disconnect(notify_cancel);
        adjust_tool_window.exposure_slider.value_changed.disconnect(on_exposure_adjustment);
        adjust_tool_window.contrast_slider.value_changed.disconnect(on_contrast_adjustment);
        adjust_tool_window.saturation_slider.value_changed.disconnect(on_saturation_adjustment);
        adjust_tool_window.tint_slider.value_changed.disconnect(on_tint_adjustment);
        adjust_tool_window.temperature_slider.value_changed.disconnect(on_temperature_adjustment);
        adjust_tool_window.shadows_slider.value_changed.disconnect(on_shadows_adjustment);
        adjust_tool_window.highlights_slider.value_changed.disconnect(on_highlights_adjustment);
        adjust_tool_window.histogram_manipulator.nub_position_changed.disconnect(on_histogram_constraint);

        adjust_tool_window.saturation_slider.button_press_event.disconnect(on_hscale_reset);
        adjust_tool_window.exposure_slider.button_press_event.disconnect(on_hscale_reset);
        adjust_tool_window.contrast_slider.button_press_event.disconnect(on_hscale_reset);
        adjust_tool_window.tint_slider.button_press_event.disconnect(on_hscale_reset);
        adjust_tool_window.temperature_slider.button_press_event.disconnect(on_hscale_reset);
        adjust_tool_window.shadows_slider.button_press_event.disconnect(on_hscale_reset);
        adjust_tool_window.highlights_slider.button_press_event.disconnect(on_hscale_reset);
    }

    public bool enhance() {
        AdjustEnhanceCommand command = new AdjustEnhanceCommand(this, canvas.get_photo());
        AppWindow.get_command_manager().execute(command);

        return true;
    }

    private void on_photos_altered(Gee.Map<DataObject, Alteration> map) {
        if (!map.has_key(canvas.get_photo()))
            return;

        PixelTransformationBundle adjustments = canvas.get_photo().get_color_adjustments();
        set_adjustments(adjustments);
    }

    private void set_adjustments(PixelTransformationBundle new_adjustments) {
        unbind_window_handlers();

        update_transformations(new_adjustments);

        foreach (PixelTransformation adjustment in new_adjustments.get_transformations())
            update_slider(adjustment);

        bind_window_handlers();
        canvas.repaint();
    }

    // Note that window handlers should be unbound (unbind_window_handlers) prior to calling this
    // if the caller doesn't want the widget's signals to fire with the change.
    private void update_slider(PixelTransformation transformation) {
        switch (transformation.get_transformation_type()) {
            case PixelTransformationType.TONE_EXPANSION:
                ExpansionTransformation expansion = (ExpansionTransformation) transformation;

                if (!disable_histogram_refresh) {
                    adjust_tool_window.histogram_manipulator.set_left_nub_position(
                        expansion.get_black_point());
                    adjust_tool_window.histogram_manipulator.set_right_nub_position(
                        expansion.get_white_point());
                }
            break;

            case PixelTransformationType.SHADOWS:
                adjust_tool_window.shadows_slider.set_value(
                    ((ShadowDetailTransformation) transformation).get_parameter());
            break;

            case PixelTransformationType.CONTRAST:
                adjust_tool_window.contrast_slider.set_value(
                    ((ContrastTransformation) transformation).get_parameter());
            break;

            case PixelTransformationType.HIGHLIGHTS:
                adjust_tool_window.highlights_slider.set_value(
                    ((HighlightDetailTransformation) transformation).get_parameter());
            break;

            case PixelTransformationType.EXPOSURE:
                adjust_tool_window.exposure_slider.set_value(
                    ((ExposureTransformation) transformation).get_parameter());
            break;

            case PixelTransformationType.SATURATION:
                adjust_tool_window.saturation_slider.set_value(
                    ((SaturationTransformation) transformation).get_parameter());
            break;

            case PixelTransformationType.TINT:
                adjust_tool_window.tint_slider.set_value(
                    ((TintTransformation) transformation).get_parameter());
            break;

            case PixelTransformationType.TEMPERATURE:
                adjust_tool_window.temperature_slider.set_value(
                    ((TemperatureTransformation) transformation).get_parameter());
            break;

            default:
                error("Unknown adjustment: %d", (int) transformation.get_transformation_type());
        }
    }

    private void init_fp_pixel_cache(Gdk.Pixbuf source) {
        int source_width = source.get_width();
        int source_height = source.get_height();
        int source_num_channels = source.get_n_channels();
        int source_rowstride = source.get_rowstride();
        unowned uchar[] source_pixels = source.get_pixels();

        fp_pixel_cache = new float[3 * source_width * source_height];
        int cache_pixel_index = 0;

        for (int j = 0; j < source_height; j++) {
            int row_start_index = j * source_rowstride;
            int row_end_index = row_start_index + (source_width * source_num_channels);
            for (int i = row_start_index; i < row_end_index; i += source_num_channels) {
                fp_pixel_cache[cache_pixel_index++] = rgb_lookup_table[source_pixels[i]];
                fp_pixel_cache[cache_pixel_index++] = rgb_lookup_table[source_pixels[i + 1]];
                fp_pixel_cache[cache_pixel_index++] = rgb_lookup_table[source_pixels[i + 2]];
            }
        }
    }

    public override bool on_keypress(Gdk.EventKey event) {
        if ((Gdk.keyval_name(event.keyval) == "KP_Enter") ||
            (Gdk.keyval_name(event.keyval) == "Enter") ||
            (Gdk.keyval_name(event.keyval) == "Return")) {
            on_ok();
            return true;
        }

        return base.on_keypress(event);
    }
}


}

