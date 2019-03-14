/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if ENABLE_FACES

public abstract class FaceShape : Object {
    public const string SHAPE_TYPE = null;
    
    protected const int FACE_WINDOW_MARGIN = 5;
    protected const int LABEL_MARGIN = 12;
    protected const int LABEL_PADDING = 9;
    
    public signal void add_me_requested(FaceShape face_shape);
    public signal void delete_me_requested();
    
    protected FacesTool.EditingFaceToolWindow face_window;
    protected Gdk.CursorType current_cursor_type = Gdk.CursorType.BOTTOM_RIGHT_CORNER;
    protected EditingTools.PhotoCanvas canvas;
    protected string serialized = null;
    
    private bool editable = true;
    private bool visible = true;
    private bool known = true;
    
    private weak FacesTool.FaceWidget face_widget = null;
    
    protected FaceShape(EditingTools.PhotoCanvas canvas) {
        this.canvas = canvas;
        this.canvas.new_surface.connect(prepare_ctx);
        
        prepare_ctx(this.canvas.get_default_ctx(), this.canvas.get_surface_dim());
        
        face_window = new FacesTool.EditingFaceToolWindow(this.canvas.get_container());
        face_window.key_pressed.connect(key_press_event);
        
        face_window.show_all();
        face_window.hide();
        
        this.canvas.get_drawing_window().set_cursor(new Gdk.Cursor(current_cursor_type));
    }
    
    ~FaceShape() {
        if (visible)
            erase();
        
        face_window.destroy();
        
        canvas.new_surface.disconnect(prepare_ctx);
        
        // make sure the cursor isn't set to a modify indicator
        canvas.get_drawing_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
    }
    
    public static FaceShape from_serialized(EditingTools.PhotoCanvas canvas, string serialized)
    throws FaceShapeError {
        FaceShape face_shape;
        
        string[] args = serialized.split(";");
        switch (args[0]) {
            case "Rectangle":
                face_shape = FaceRectangle.from_serialized(canvas, args);
                
                break;
            default:
                assert_not_reached();
        }
        
        face_shape.serialized = serialized;
        
        return face_shape;
    }
    
    public void set_name(string face_name) {
        face_window.entry.set_text(face_name);
    }
    
    public string? get_name() {
        string face_name = face_window.entry.get_text();
        
        return face_name == "" ? null : face_name;
    }
    
    public void set_known(bool known) {
        this.known = known;
    }
    
    public bool get_known() {
        return known;
    }
    
    public void set_widget(FacesTool.FaceWidget face_widget) {
        this.face_widget = face_widget;
    }
    
    public FacesTool.FaceWidget get_widget() {
        assert(face_widget != null);
        
        return face_widget;
    }
    
    public void hide() {
        visible = false;
        erase();
        
        if (editable)
            face_window.hide();
        
        // make sure the cursor isn't set to a modify indicator
        canvas.get_drawing_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
    }
    
    public void show() {
        visible = true;
        paint();
        
        if (editable) {
            update_face_window_position();
            face_window.show();
            face_window.present();
            
            if (!known)
                face_window.entry.select_region(0, -1);
        }
    }
    
    public bool is_visible() {
        return visible;
    }
    
    public bool is_editable() {
        return editable;
    }
    
    public void set_editable(bool editable) {
        if (visible && editable != is_editable()) {
            hide();
            this.editable = editable;
            show();
            
            return;
        }
        
        this.editable = editable;
    }
    
    public bool key_press_event(Gdk.EventKey event) {
        switch (Gdk.keyval_name(event.keyval)) {
            case "Escape":
                delete_me_requested();
            break;
            case "Return":
            case "KP_Enter":
                add_me_requested(this);
            break;
            default:
                return false;
        }
        
        return true;
    }
    
    public abstract string serialize();
    public abstract void update_face_window_position();
    public abstract void prepare_ctx(Cairo.Context ctx, Dimensions dim);
    public abstract void on_resized_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled);
    public abstract void on_motion(int x, int y, Gdk.ModifierType mask);
    public abstract void on_left_released(int x, int y);
    public abstract bool on_left_click(int x, int y);
    public abstract bool cursor_is_over(int x, int y);
    public abstract bool equals(FaceShape face_shape);
    public abstract double get_distance(int x, int y);
    
    protected abstract void paint();
    protected abstract void erase();
}

public class FaceRectangle : FaceShape {
    public new const string SHAPE_TYPE = "Rectangle";
    
    private const int FACE_MIN_SIZE = 8;
    public const int NULL_SIZE = 0;
    
    private Box box;
    private Box? label_box;
    private BoxLocation in_manipulation = BoxLocation.OUTSIDE;
    private Cairo.Context wide_black_ctx = null;
    private Cairo.Context wide_white_ctx = null;
    private Cairo.Context thin_white_ctx = null;
    private int last_grab_x = -1;
    private int last_grab_y = -1;
    
    public FaceRectangle(EditingTools.PhotoCanvas canvas, int x, int y,
        int half_width = NULL_SIZE, int half_height = NULL_SIZE) {
        base(canvas);
        
        Gdk.Rectangle scaled_pixbuf_pos = canvas.get_scaled_pixbuf_position();
        x -= scaled_pixbuf_pos.x;
        y -= scaled_pixbuf_pos.y;
        
        // If half_width is NULL_SIZE we are creating a new FaceShape,
        // otherwise we are only showing a previously created one.
        if (half_width == NULL_SIZE) {
            box = Box(x, y, x, y);
            
            in_manipulation = BoxLocation.BOTTOM_RIGHT;
            last_grab_x = x;
            last_grab_y = y;
        } else {
            Dimensions pixbuf_dimensions = Dimensions.for_pixbuf(canvas.get_scaled_pixbuf());
            int right = (x + half_width).clamp(x, pixbuf_dimensions.width);
            int bottom = (y + half_height).clamp(y, pixbuf_dimensions.height);
        
            box = Box(x - half_width, y - half_height, right, bottom);
        }
    }
    
    ~FaceRectangle() {
        if (!is_editable())
            erase_label();
    }
    
    public static new FaceRectangle from_serialized(EditingTools.PhotoCanvas canvas, string[] args)
        throws FaceShapeError {
        assert(args[0] == SHAPE_TYPE);
        
        Photo photo = canvas.get_photo();
        Dimensions raw_dim = photo.get_raw_dimensions();
        
        int x = (int) (raw_dim.width * double.parse(args[1]));
        int y = (int) (raw_dim.height * double.parse(args[2]));
        int half_width = (int) (raw_dim.width * double.parse(args[3]));
        int half_height = (int) (raw_dim.height * double.parse(args[4]));
        
        Box box = Box(x - half_width, y - half_height, x + half_width, y + half_height);
        
        Dimensions current_dim = Dimensions.for_pixbuf(canvas.get_scaled_pixbuf());
        Box raw_cropped;
        
        if (photo.get_raw_crop(out raw_cropped)) {
            box.left = box.left.clamp(raw_cropped.left, box.left) - raw_cropped.left;
            box.right = box.right.clamp(box.right, raw_cropped.right) - raw_cropped.left;
            box.top = box.top.clamp(raw_cropped.top, box.top) - raw_cropped.top;
            box.bottom = box.bottom.clamp(box.bottom, raw_cropped.bottom) - raw_cropped.top;
            
            box = photo.get_orientation().rotate_box(raw_cropped.get_dimensions(), box);
            
            Box cropped;
            photo.get_crop(out cropped);
            box = box.get_scaled_similar(cropped.get_dimensions(), current_dim);
        } else {
            box = photo.get_orientation().rotate_box(raw_dim, box);
            
            box = box.get_scaled_similar(photo.get_dimensions(), current_dim);
        }
        
        Gdk.Rectangle scaled_pixbuf_pos = canvas.get_scaled_pixbuf_position();
        box.left += scaled_pixbuf_pos.x;
        box.right += scaled_pixbuf_pos.x;
        box.top += scaled_pixbuf_pos.y;
        box.bottom += scaled_pixbuf_pos.y;
        
        half_width = box.get_width() / 2;
        half_height = box.get_height() / 2;
        
        if (half_width < FACE_MIN_SIZE || half_height < FACE_MIN_SIZE)
            throw new FaceShapeError.CANT_CREATE("FaceShape is out of cropped photo area");
        
        return new FaceRectangle(canvas, box.left + half_width, box.top + half_height,
            half_width, half_height);
    }
    
    public override void update_face_window_position() {
        AppWindow appWindow = AppWindow.get_instance();
        Gtk.Allocation face_window_alloc;
        Gdk.Rectangle scaled_pixbuf_pos = canvas.get_scaled_pixbuf_position();
        int x = 0;
        int y = 0;
        
        if (canvas.get_container() == appWindow) {
            appWindow.get_current_page().get_window().get_origin(out x, out y);
        } else assert(canvas.get_container() is FullscreenWindow);
        
        face_window.get_allocation(out face_window_alloc);
        
        x += scaled_pixbuf_pos.x + box.left + ((box.get_width() - face_window_alloc.width) >> 1);
        y += scaled_pixbuf_pos.y + box.bottom + FACE_WINDOW_MARGIN;
        
        face_window.move(x, y);
    }
    
    protected override void paint() {
        canvas.draw_box(wide_black_ctx, box);
        canvas.draw_box(wide_white_ctx, box.get_reduced(1));
        canvas.draw_box(wide_white_ctx, box.get_reduced(2));
        
        canvas.invalidate_area(box);
        
        if (!is_editable())
            paint_label();
    }
    
    protected override void erase() {
        canvas.erase_box(box);
        canvas.erase_box(box.get_reduced(1));
        canvas.erase_box(box.get_reduced(2));
        
        canvas.invalidate_area(box);
        
        if (!is_editable())
            erase_label();
    }
    
    private void paint_label() {
        Cairo.Context ctx = canvas.get_default_ctx();
        Gdk.Rectangle scaled_pixbuf_pos = canvas.get_scaled_pixbuf_position();
        
        ctx.save();
        
        Cairo.TextExtents text_extents = Cairo.TextExtents();
        ctx.text_extents(get_name(), out text_extents);
        
        int width = (int) text_extents.width + LABEL_PADDING;
        int height = (int) text_extents.height;
        int x = box.left + (box.get_width() - width) / 2;
        int y = box.bottom + LABEL_MARGIN;
        
        label_box = Box(x, y, x + width, y + height + LABEL_PADDING);
        
        x += scaled_pixbuf_pos.x;
        y += scaled_pixbuf_pos.y;
        
        ctx.rectangle(x, y, width, height + LABEL_PADDING);
        ctx.set_source_rgba(0, 0, 0, 0.6);
        ctx.fill();
        
        ctx.set_source_rgb(1, 1, 1);
        ctx.move_to(x + LABEL_PADDING / 2, y + height + LABEL_PADDING / 2);
        ctx.show_text(get_name());
        
        ctx.restore();
    }
    
    private void erase_label() {
        if (label_box == null)
            return;
        
        Gdk.Rectangle scaled_pixbuf_pos = canvas.get_scaled_pixbuf_position();
        int x = scaled_pixbuf_pos.x + label_box.left;
        int y = scaled_pixbuf_pos.y + label_box.top;
        
        Cairo.Context ctx = canvas.get_default_ctx();
        ctx.save();
        
        ctx.set_operator(Cairo.Operator.OVER);
        ctx.rectangle(x, y, label_box.get_width(), label_box.get_height());
        
        ctx.set_source_rgb(0.0, 0.0, 0.0);
        ctx.fill_preserve();
        
        ctx.set_source_surface(canvas.get_scaled_surface(),
            scaled_pixbuf_pos.x, scaled_pixbuf_pos.y);
        ctx.fill();
        
        canvas.invalidate_area(label_box);
        label_box = null;
        
        ctx.restore();
    }
    
    public override string serialize() {
        if (serialized != null)
            return serialized;
        
        double x;
        double y;
        double half_width;
        double half_height;
        
        get_geometry(out x, out y, out half_width, out half_height);
        
        serialized = "%s;%s;%s;%s;%s".printf(SHAPE_TYPE, x.to_string(),
            y.to_string(), half_width.to_string(), half_height.to_string());
        
        return serialized;
    }
    
    public void get_geometry(out double x, out double y,
        out double half_width, out double half_height) {
        Photo photo = canvas.get_photo();
        Dimensions raw_dim = photo.get_raw_dimensions();
        
        Box temp_box = box;
        
        Dimensions current_dim = Dimensions.for_pixbuf(canvas.get_scaled_pixbuf());
        Box cropped;
        
        if (photo.get_crop(out cropped)) {
            temp_box = temp_box.get_scaled_similar(current_dim, cropped.get_dimensions());
            
            Box raw_cropped;
            photo.get_raw_crop(out raw_cropped);
            
            temp_box =
                photo.get_orientation().derotate_box(raw_cropped.get_dimensions(), temp_box);
            
            temp_box.left += raw_cropped.left;
            temp_box.right += raw_cropped.left;
            temp_box.top += raw_cropped.top;
            temp_box.bottom += raw_cropped.top;
        } else {
            temp_box = temp_box.get_scaled_similar(current_dim, photo.get_dimensions());
            
            temp_box = photo.get_orientation().derotate_box(raw_dim, temp_box);
        }
        
        x = (temp_box.left + (temp_box.get_width() / 2)) / (double) raw_dim.width;
        y = (temp_box.top + (temp_box.get_height() / 2)) / (double) raw_dim.height;
        
        double width_left_end = temp_box.left / (double) raw_dim.width;
        double width_right_end = temp_box.right / (double) raw_dim.width;
        double height_top_end = temp_box.top / (double) raw_dim.height;
        double height_bottom_end = temp_box.bottom / (double) raw_dim.height;
        
        half_width = (width_right_end - width_left_end) / 2;
        half_height = (height_bottom_end - height_top_end) / 2;
    }
    
    public override bool equals(FaceShape face_shape) {
        return serialize() == face_shape.serialize();
    }
    
    public override void prepare_ctx(Cairo.Context ctx, Dimensions dim) {
        wide_black_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(wide_black_ctx, "#000");
        wide_black_ctx.set_line_width(1);
        
        wide_white_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(wide_black_ctx, "#FFF");
        wide_white_ctx.set_line_width(1);
        
        thin_white_ctx = new Cairo.Context(ctx.get_target());
        set_source_color_from_string(wide_black_ctx, "#FFF");
        thin_white_ctx.set_line_width(0.5);
    }
    
    private bool on_canvas_manipulation(int x, int y) {
        Gdk.Rectangle scaled_pos = canvas.get_scaled_pixbuf_position();
        
        // box is maintained in coordinates non-relative to photo's position on canvas ...
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
        int left = box.left;
        int top = box.top;
        int right = box.right;
        int bottom = box.bottom;

        // get extra geometric information needed to enforce constraints
        int photo_right_edge = canvas.get_scaled_pixbuf().width - 1;
        int photo_bottom_edge = canvas.get_scaled_pixbuf().height - 1;
        
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
                
                // bound box inside of photo
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
                
                // don't let adjustments affect the size of the box
                if (adj_width != width) {
                    if (delta_x < 0)
                        right = left + width - 1;
                    else left = right - width + 1;
                }
                
                if (adj_height != height) {
                    if (delta_y < 0)
                        bottom = top + height - 1;
                    else top = bottom - height + 1;
                }
            break;
            
            default:
                // do nothing, not even a repaint
                return false;
        }

        // Check if the mouse has gone out of bounds, and if it has, make sure that the
        // face shape edges stay within the photo bounds.
        int width = right - left + 1;
        int height = bottom - top + 1;
        
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
                if (width < FACE_MIN_SIZE)
                    left = right - FACE_MIN_SIZE;
            break;
            
            case BoxLocation.RIGHT_SIDE:
            case BoxLocation.TOP_RIGHT:
            case BoxLocation.BOTTOM_RIGHT:
                if (width < FACE_MIN_SIZE)
                    right = left + FACE_MIN_SIZE;
            break;

            default:
            break;
        }

        switch (in_manipulation) {
            case BoxLocation.TOP_SIDE:
            case BoxLocation.TOP_LEFT:
            case BoxLocation.TOP_RIGHT:
                if (height < FACE_MIN_SIZE)
                    top = bottom - FACE_MIN_SIZE;
            break;

            case BoxLocation.BOTTOM_SIDE:
            case BoxLocation.BOTTOM_LEFT:
            case BoxLocation.BOTTOM_RIGHT:
                if (height < FACE_MIN_SIZE)
                    bottom = top + FACE_MIN_SIZE;
            break;
            
            default:
            break;
        }
       
        Box new_box = Box(left, top, right, bottom);
        
        if (!box.equals(new_box)) {
            erase();
            
            if (in_manipulation != BoxLocation.INSIDE)
                check_resized_box(new_box);
            
            box = new_box;
            paint();
        }
        
        if (is_editable())
            update_face_window_position();
        
        serialized = null;
        
        return false;
    }
    
    private void check_resized_box(Box new_box) {
        Box horizontal;
        bool horizontal_enlarged;
        Box vertical;
        bool vertical_enlarged;
        BoxComplements complements = box.resized_complements(new_box, out horizontal,
            out horizontal_enlarged, out vertical, out vertical_enlarged);
        
        // this should never happen ... this means that the operation wasn't a resize
        assert(complements != BoxComplements.NONE);
    }
    
    private void update_cursor(int x, int y) {
        // box is not maintained relative to photo's position on canvas
        Gdk.Rectangle scaled_pos = canvas.get_scaled_pixbuf_position();
        Box offset_scaled_box = box.get_offset(scaled_pos.x, scaled_pos.y);
        
        Gdk.CursorType cursor_type = Gdk.CursorType.LEFT_PTR;
        switch (offset_scaled_box.approx_location(x, y)) {
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
            Gdk.Cursor cursor = new Gdk.Cursor(cursor_type);
            canvas.get_drawing_window().set_cursor(cursor);
            current_cursor_type = cursor_type;
        }
    }
    
    public override void on_motion(int x, int y, Gdk.ModifierType mask) {
        // only deal with manipulating the box when click-and-dragging one of the edges
        // or the interior
        if (in_manipulation != BoxLocation.OUTSIDE)
            on_canvas_manipulation(x, y);
        
        update_cursor(x, y);
    }
    
    public override bool on_left_click(int x, int y) {
        Gdk.Rectangle scaled_pixbuf_pos = canvas.get_scaled_pixbuf_position();
        
        // box is not maintained relative to photo's position on canvas
        Box offset_scaled_box = box.get_offset(scaled_pixbuf_pos.x, scaled_pixbuf_pos.y);
        
        // determine where the mouse down landed and store for future events
        in_manipulation = offset_scaled_box.approx_location(x, y);
        last_grab_x = x -= scaled_pixbuf_pos.x;
        last_grab_y = y -= scaled_pixbuf_pos.y;
        
        return box.approx_location(x, y) != BoxLocation.OUTSIDE;
    }
    
    public override void on_left_released(int x, int y) {
        if (box.get_width() < FACE_MIN_SIZE) {
            delete_me_requested();
            
            return;
        }
        
        if (is_editable()) {
            face_window.show();
            face_window.present();
        }
        
        // nothing to do if released outside of the face box
        if (in_manipulation == BoxLocation.OUTSIDE)
            return;
        
        // end manipulation
        in_manipulation = BoxLocation.OUTSIDE;
        last_grab_x = -1;
        last_grab_y = -1;
        
        update_cursor(x, y);
    }
    
    public override void on_resized_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled) {
        Dimensions new_dim = Dimensions.for_pixbuf(scaled);
        Dimensions uncropped_dim = canvas.get_photo().get_original_dimensions();
        
        Box new_box = box.get_scaled_similar(old_dim, uncropped_dim);
        
        // rescale back to new size
        box = new_box.get_scaled_similar(uncropped_dim, new_dim);
        update_face_window_position();
    }
    
    public override bool cursor_is_over(int x, int y) {
        // box is not maintained relative to photo's position on canvas
        Gdk.Rectangle scaled_pos = canvas.get_scaled_pixbuf_position();
        Box offset_scaled_box = box.get_offset(scaled_pos.x, scaled_pos.y);
        
        return offset_scaled_box.approx_location(x, y) != BoxLocation.OUTSIDE;
    }
    
    public override double get_distance(int x, int y) {
        double center_x = box.left + box.get_width() / 2.0;
        double center_y = box.top + box.get_height() / 2.0;
        
        return Math.sqrt((center_x - x) * (center_x - x) + (center_y - y) * (center_y - y));
    }
}

#endif
