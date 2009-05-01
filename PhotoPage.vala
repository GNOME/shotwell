
public class PhotoPage : Page {
    public static const Gdk.InterpType FAST_INTERP = Gdk.InterpType.NEAREST;
    public static const Gdk.InterpType QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    public static const int VIEWPORT_BORDER = 1;
    public static const int CROP_STARTING_BORDER = 100;
    
    private Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToggleToolButton crop_button = null;
    private Gtk.ToolButton prev_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
    private Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
    private Gtk.DrawingArea canvas = new Gtk.DrawingArea();
    private Thumbnail thumbnail = null;
    private Gdk.Pixbuf original = null;
    private Exif.Orientation orientation;
    private Gdk.Pixbuf rotated = null;
    private Dimensions rotated_dim;
    private Dimensions scaled_dim;
    private Gdk.Rectangle photo_rect = Gdk.Rectangle();
    private CheckerboardPage controller = null;
    private Gdk.Pixmap pixmap = null;
    private Dimensions pixmap_dim;
    
    // cropping
    private bool show_crop = false;
    private Gdk.Rectangle crop = Gdk.Rectangle();
    private Gdk.Rectangle scaled_crop = Gdk.Rectangle();

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, null },
        
        { "ViewMenu", null, "_View", null, null, null },
        { "ReturnToPage", null, "_Return to collection", "Escape", null, on_return_to_collection },

        { "PhotoMenu", null, "_Photo", null, null, null },
        { "PrevPhoto", Gtk.STOCK_GO_BACK, "_Previous Photo", null, "Previous Photo", on_previous_photo },
        { "NextPhoto", Gtk.STOCK_GO_FORWARD, "_Next Photo", null, "Next Photo", on_next_photo },
        { "RotateClockwise", STOCK_CLOCKWISE, "Rotate c_lockwise", "<Ctrl>R", "Rotate the selected photos clockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", STOCK_COUNTERCLOCKWISE, "Rotate c_ounterclockwise", "<Ctrl><Shift>R", "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", null, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", on_mirror },

        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    private PhotoTable photo_table = new PhotoTable();
    
    public PhotoPage() {
        init_ui("photo.ui", "/PhotoMenuBar", "PhotoActionGroup", ACTIONS);

        // set up page's toolbar (used by AppWindow for layout)
        //
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(STOCK_CLOCKWISE);
        rotate_button.label = "Rotate Clockwise";
        rotate_button.clicked += on_rotate_clockwise;
        toolbar.insert(rotate_button, -1);
        
        // crop tool
        crop_button = new Gtk.ToggleToolButton();
        crop_button.set_label("Crop");
        crop_button.toggled += on_crop_toggled;
        toolbar.insert(crop_button, -1);
        
        // separator to force next/prev buttons to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // previous button
        prev_button.clicked += on_previous_photo;
        toolbar.insert(prev_button, -1);
        
        // next button
        next_button.clicked += on_next_photo;
        toolbar.insert(next_button, -1);
        
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        viewport.set_shadow_type(Gtk.ShadowType.NONE);
        viewport.add(canvas);
        
        add(viewport);
        
        canvas.set_double_buffered(false);
        canvas.set_events(Gdk.EventMask.EXPOSURE_MASK | Gdk.EventMask.POINTER_MOTION_MASK);
        
        viewport.size_allocate += repaint;
        canvas.expose_event += on_canvas_expose;
        canvas.motion_notify_event += on_canvas_motion;
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public CheckerboardPage get_controller() {
        return controller;
    }
    
    public Thumbnail get_thumbnail() {
        return thumbnail;
    }
    
    public void display(CheckerboardPage controller, Thumbnail thumbnail) {
        this.controller = controller;
        this.thumbnail = thumbnail;

        update_display();
        update_sensitivity();
    }
    
    private void update_display() {
        orientation = photo_table.get_orientation(thumbnail.get_photo_id());
        original = thumbnail.get_full_pixbuf();
        if (original == null) {
            debug("Unable to fetch full pixbuf for %s", thumbnail.get_name());

            return;
        }

        rotated = rotate_to_exif(original, orientation);
        rotated_dim = Dimensions.for_pixbuf(rotated);
        
        // resize canvas to fit in the viewport and realize
        canvas.set_size_request(viewport.allocation.width - (VIEWPORT_BORDER * 2), 
            viewport.allocation.height - (VIEWPORT_BORDER * 2));
        canvas.realize();
        
        repaint();
    }

    private override bool on_left_click(Gdk.EventButton event) {
        if (show_crop) {
        } else if (event.type == Gdk.EventType.2BUTTON_PRESS) {
            on_return_to_collection();
            
            return true;
        }
        
        return false;
    }
    
    private void on_return_to_collection() {
        AppWindow.get_instance().switch_to_page(controller);
    }
    
    private static const int HAND_GRENADES = 6;
    
    private bool in_zone(double pos, int zone) {
        int top_zone = zone - HAND_GRENADES;
        int bottom_zone = zone + HAND_GRENADES;
        
        return in_between(pos, top_zone, bottom_zone);
    }
    
    private bool in_between(double pos, int top, int bottom) {
        int ipos = (int) pos;
        
        return (ipos > top) && (ipos < bottom);
    }
    
    private bool near_in_between(double pos, int top, int bottom) {
        int ipos = (int) pos;
        int top_zone = top - HAND_GRENADES;
        int bottom_zone = bottom + HAND_GRENADES;
        
        return (ipos > top_zone) && (ipos < bottom_zone);
    }
    
    private bool on_canvas_motion(Gtk.DrawingArea da, Gdk.EventMotion event) {
        if (!show_crop)
            return false;
        
        int x = scaled_crop.x;
        int xr = x + scaled_crop.width;
        int y = scaled_crop.y;
        int yb = y + scaled_crop.height;
        
        bool near_width = near_in_between(event.x, x, xr);
        bool near_height = near_in_between(event.y, y, yb);
        
        Gdk.CursorType cursor_type = Gdk.CursorType.ARROW;
        if (in_zone(event.x, x) && near_height) {
            if (in_zone(event.y, y)) {
                cursor_type = Gdk.CursorType.TOP_LEFT_CORNER;
            } else if (in_zone(event.y, yb)) {
                cursor_type = Gdk.CursorType.BOTTOM_LEFT_CORNER;
            } else {
                cursor_type = Gdk.CursorType.LEFT_SIDE;
            }
        } else if (in_zone(event.x, xr) && near_height) {
            if (in_zone(event.y, y)) {
                cursor_type = Gdk.CursorType.TOP_RIGHT_CORNER;
            } else if (in_zone(event.y, yb)) {
                cursor_type = Gdk.CursorType.BOTTOM_RIGHT_CORNER;
            } else {
                cursor_type = Gdk.CursorType.RIGHT_SIDE;
            }
        } else if (in_zone(event.y, y) && near_width) {
            // if x or xr was in zone, already caught
            cursor_type = Gdk.CursorType.TOP_SIDE;
        } else if (in_zone(event.y, yb) && near_width) {
            cursor_type = Gdk.CursorType.BOTTOM_SIDE;
        } else if (in_between(event.x, x, xr) && in_between(event.y, y, yb)) {
            cursor_type = Gdk.CursorType.FLEUR;
        } else {
            // not in or near crop, so use normal arrow
        }
        
        Gdk.Cursor cursor = new Gdk.Cursor(cursor_type);
        canvas.window.set_cursor(cursor);
        
        return false;
    }

    private bool on_canvas_expose(Gtk.DrawingArea da, Gdk.EventExpose event) {
        // to avoid multiple exposes
        if (event.count > 0)
            return false;
        
        if (pixmap == null)
            return false;
        
        canvas.window.draw_drawable(canvas.style.fg_gc[Gtk.StateType.NORMAL], pixmap, event.area.x, 
            event.area.y, event.area.x, event.area.y, event.area.width, event.area.height);

        return false;
    }
    
    private void repaint() {
        // no image, no painting
        if (rotated == null)
            return;
        
        // account for border
        int width = viewport.allocation.width - (VIEWPORT_BORDER * 2);
        int height = viewport.allocation.height - (VIEWPORT_BORDER * 2);
        
        if (width <= 0 || height <= 0)
            return;
        
        // attempt to reuse pixmap
        if (pixmap != null) {
            if (pixmap_dim.width != width || pixmap_dim.height != height)
                pixmap = null;
        }
        
        // create a pixmap as large as the entire viewport
        if (pixmap == null) {
            pixmap = new Gdk.Pixmap(canvas.window, width, height, -1);
            pixmap_dim = Dimensions(width, height);

            // resize canvas for the pixmap (that is, the entire viewport)
            canvas.set_size_request(width, height);
        }

        // resize the rotated pixbuf to fit on the canvas
        scaled_dim = get_scaled_dimensions_for_view(rotated_dim, pixmap_dim);
        Gdk.Pixbuf pixbuf = rotated.scale_simple(scaled_dim.width, scaled_dim.height, FAST_INTERP);
        
        assert(scaled_dim.width == pixbuf.get_width());
        assert(scaled_dim.height == pixbuf.get_height());
        
        // center photo on the canvas
        int photo_x = (width - scaled_dim.width) / 2;
        int photo_y = (height - scaled_dim.height) / 2;

        // draw "background" by drawing exposed bands around photo
        if (photo_x > 0) {
            // draw bands on left/right of image
            pixmap.draw_rectangle(canvas.style.black_gc, true, 0, 0, photo_x, height);
            pixmap.draw_rectangle(canvas.style.black_gc, true, photo_x + scaled_dim.width - 1, 0,
                width - (photo_x * 2), height);
        }
        
        if (photo_y > 0) {
            // draw bands above/below image
            pixmap.draw_rectangle(canvas.style.black_gc, true, 0, 0, width, photo_y);
            pixmap.draw_rectangle(canvas.style.black_gc, true, 0, photo_y + scaled_dim.height - 1,
                width, height - (photo_y * 2));
        }

        // lay down the photo
        pixmap.draw_pixbuf(canvas.style.fg_gc[Gtk.StateType.NORMAL], pixbuf, 0, 0, photo_x, photo_y, 
            -1, -1, Gdk.RgbDither.NORMAL, 0, 0);
        
        // store photo's position in the pixmap/canvas
        photo_rect.x = photo_x;
        photo_rect.y = photo_y;
        photo_rect.width = scaled_dim.width;
        photo_rect.height = scaled_dim.height;
        
        // draw crop tool, if activated
        draw_crop();

        if (canvas.window != null)
            canvas.window.invalidate_rect(null, true);
    }
    
    private void set_orientation(Exif.Orientation newOrientation) {
        orientation = newOrientation;
        rotated = rotate_to_exif(original, orientation);
        rotated_dim = Dimensions.for_pixbuf(rotated);
        
        File file = thumbnail.get_file();
        PhotoExif exif = PhotoExif.create(file);
        
        // update file itself
        exif.set_orientation(orientation);
        
        // TODO: Write this in background
        try {
            exif.commit();
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // update database
        photo_table.set_orientation(thumbnail.get_photo_id(), orientation);
        
        // update everyone who cares
        AppWindow.get_instance().report_backing_changed(thumbnail.get_photo_id());

        repaint();
    }
    
    private void on_rotate_clockwise() {
        set_orientation(orientation.rotate_clockwise());
    }
    
    private void on_rotate_counterclockwise() {
        set_orientation(orientation.rotate_counterclockwise());
    }
    
    private void on_mirror() {
        set_orientation(orientation.flip_left_to_right());
    }

    private override bool on_ctrl_pressed(Gdk.EventKey event) {
        rotate_button.set_stock_id(STOCK_COUNTERCLOCKWISE);
        rotate_button.label = "Rotate Counterclockwise";
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotate_button.set_stock_id(STOCK_CLOCKWISE);
        rotate_button.label = "Rotate Clockwise";
        rotate_button.clicked -= on_rotate_counterclockwise;
        rotate_button.clicked += on_rotate_clockwise;
        
        return false;
    }
    
    private void on_crop_toggled() {
        if (crop_button.active)
            activate_crop();
        else
            deactivate_crop();
        
        repaint();
    }
    
    private void activate_crop() {
        assert(rotated != null);
            
        int width = rotated_dim.width;
        int height = rotated_dim.height;
        
        crop.x = 0 + CROP_STARTING_BORDER;
        crop.y = 0 + CROP_STARTING_BORDER;
        crop.width = width - (CROP_STARTING_BORDER * 2);
        crop.height = height - (CROP_STARTING_BORDER * 2);
        
        if (crop.x > width)
            crop.x = 0;
        
        if (crop.y > height)
            crop.y = 0;
        
        if (crop.width < 0)
            crop.width = width;
        
        if (crop.height < 0)
            crop.height = height;
        
        show_crop = true;
    }
    
    private void deactivate_crop() {
        show_crop = false;
    }
    
    private void draw_crop() {
        if (!show_crop)
            return;
        
        // the crop is maintained in photo coordinates; scale it for the display and offset it
        // on the photo
        scaled_crop = scaled_rectangle(rotated_dim, scaled_dim, crop);
        scaled_crop.x += photo_rect.x;
        scaled_crop.y += photo_rect.y;
        
        // the outline
        pixmap.draw_rectangle(canvas.style.white_gc, false, scaled_crop.x, scaled_crop.y, 
            scaled_crop.width, scaled_crop.height);
    }
    
    private void on_next_photo() {
        this.thumbnail = (Thumbnail) controller.get_next_item(thumbnail);
        update_display();
    }
    
    private void on_previous_photo() {
        this.thumbnail = (Thumbnail) controller.get_previous_item(thumbnail);
        update_display();
    }
    
    private void update_sensitivity() {
        assert(controller != null);
        
        bool multiple = (controller.get_count() > 1);
        
        prev_button.sensitive = multiple;
        next_button.sensitive = multiple;
        
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/NextPhoto", multiple);
    }
}

