
public class CropToolWindow : Gtk.Window {
    public static const int CONTROL_SPACING = 8;
    public static const int WINDOW_BORDER = 8;
    
    public Gtk.Button apply_button = new Gtk.Button.with_label("Apply");
    public Gtk.Button cancel_button = new Gtk.Button.with_label("Cancel");
    public bool user_moved = false;

    private Gtk.HBox layout = new Gtk.HBox(false, CONTROL_SPACING);
    private Gtk.Frame layout_frame = new Gtk.Frame(null);
    
    public CropToolWindow(Gtk.Window parent) {
        type_hint = Gdk.WindowTypeHint.TOOLBAR;
        set_focus_on_map(false);
        set_accept_focus(false);
        set_transient_for(parent);
        
        layout.set_border_width(WINDOW_BORDER);
        layout.add(apply_button);
        layout.add(cancel_button);
        
        layout_frame.set_border_width(0);
        layout_frame.set_shadow_type(Gtk.ShadowType.OUT);
        layout_frame.add(layout);
        
        add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
        button_press_event += on_button_pressed;
        
        add(layout_frame);
    }
    
    private bool on_button_pressed(CropToolWindow ctw, Gdk.EventButton event) {
        // LMB only
        if (event.button != 1)
            return false;
        
        begin_move_drag((int) event.button, (int) event.x_root, (int) event.y_root, event.time);
        user_moved = true;
        
        return false;
    }
}

public class PhotoPage : Page {
    public static const Gdk.InterpType FAST_INTERP = Gdk.InterpType.NEAREST;
    public static const Gdk.InterpType QUALITY_INTERP = Gdk.InterpType.HYPER;
    
    public static const int IMPROVAL_MSEC = 250;
    
    private static const int CROP_BORDER_THICKNESS = 1;
    public static const double CROP_INIT_X_PCT = 0.15;
    public static const double CROP_INIT_Y_PCT = 0.15;
    public static const int CROP_MIN_WIDTH = 100;
    public static const int CROP_MIN_HEIGHT = 100;
    public static const float CROP_SATURATION = 0.00f;
    
    private CheckerboardPage controller = null;
    private Photo photo = null;
    private Thumbnail thumbnail = null;
    private Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToggleToolButton crop_button = null;
    private Gtk.ToolButton prev_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
    private Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
    private Gtk.DrawingArea canvas = new Gtk.DrawingArea();
    private Gdk.Pixmap pixmap = null;
    private Dimensions pixmap_dim = Dimensions();
    private Gdk.Pixbuf original = null;
    private Gdk.Pixbuf pixbuf = null;
    private Gdk.Pixbuf desaturated = null;
    private Gdk.InterpType interp = FAST_INTERP;
    private Gdk.Rectangle pixbuf_rect = Gdk.Rectangle();
    private bool improval_scheduled = false;
    private bool reschedule_improval = false;
    private Gdk.CursorType current_cursor_type = Gdk.CursorType.ARROW;
    private BoxLocation in_manipulation = BoxLocation.OUTSIDE;
    
    // cropping
    private bool show_crop = false;
    private Box scaled_crop;
    private CropToolWindow crop_tool_window = null;

    // these are kept in absolute coordinates, not relative to photo's position on canvas
    private int last_grab_x = -1;
    private int last_grab_y = -1;
    
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
    
    public PhotoPage(Gtk.Window container) {
        init_ui("photo.ui", "/PhotoMenuBar", "PhotoActionGroup", ACTIONS);

        // set up page's toolbar (used by AppWindow for layout)
        //
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(STOCK_CLOCKWISE);
        rotate_button.label = "Rotate";
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
        viewport.set_border_width(0);
        viewport.add(canvas);
        
        add(viewport);
        
        canvas.set_double_buffered(false);
        canvas.set_events(Gdk.EventMask.EXPOSURE_MASK | Gdk.EventMask.POINTER_MOTION_MASK 
            | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON1_MOTION_MASK 
            | Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.STRUCTURE_MASK | Gdk.EventMask.SUBSTRUCTURE_MASK);
        
        viewport.size_allocate += on_viewport_resize;
        canvas.expose_event += on_canvas_expose;
        canvas.motion_notify_event += on_canvas_motion;
        canvas.button_press_event += on_canvas_button_pressed;
        canvas.button_release_event += on_canvas_button_released;
        canvas.configure_event += on_window_configured;
        
        // PhotoPage can't use the event virtuals declared in Page because it can be hosted by 
        // FullscreenWindow as well as AppWindow.
        container.configure_event += on_window_configured;
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
    
    public override void switching_from() {
        deactivate_crop();
        
        if (photo != null)
            photo.altered -= on_photo_altered;
            
        photo = null;
        original = null;
        pixbuf = null;
        pixmap = null;
        desaturated = null;
    }
    
    public void display(CheckerboardPage controller, Thumbnail thumbnail) {
        this.controller = controller;
        this.thumbnail = thumbnail;
        
        update_display();
        update_sensitivity();
    }
    
    private void update_display() {
        if (photo != null)
            photo.altered -= on_photo_altered;
            
        photo = thumbnail.get_photo();
        photo.altered += on_photo_altered;

        // fetch and cache original unscaled pixbuf ... this is more efficient than going to Photo
        // for each resize, as Photo doesn't itself cache it
        original = photo.get_pixbuf();

        // flush old image
        pixmap = null;

        // resize canvas to fit in the viewport and realize (if not already realized)
        canvas.set_size_request(viewport.allocation.width, viewport.allocation.height);
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
    
    private void on_photo_altered(Photo p) {
        assert(photo.equals(p));
        
        // fetch a new original to work with
        original = photo.get_pixbuf();
        
        // flush pixmap to force redraw
        pixmap = null;
        
        repaint();
    }
    
    private bool on_canvas_motion(Gtk.DrawingArea da, Gdk.EventMotion event) {
        if (!show_crop)
            return false;
        
        int x, y;
        if (event.is_hint) {
            Gdk.ModifierType mask;
            canvas.window.get_pointer(out x, out y, out mask);
        } else {
            x = (int) event.x;
            y = (int) event.y;
        }
        
        if (in_manipulation != BoxLocation.OUTSIDE)
            return on_canvas_manipulation(x, y);
        
        update_cursor(x, y);
        
        return false;
    }
    
    private bool on_canvas_button_pressed(Gtk.DrawingArea da, Gdk.EventButton event) {
        // only interested in LMB
        if (event.button != 1)
            return false;
        
        if (!show_crop)
            return false;
        
        // scaled_crop is not maintained relative to photo's position on canvas
        Box offset_scaled_crop = scaled_crop.get_offset(pixbuf_rect.x, pixbuf_rect.y);
        
        int x = (int) event.x;
        int y = (int) event.y;
        
        in_manipulation = offset_scaled_crop.location(x, y);
        last_grab_x = x -= pixbuf_rect.x;
        last_grab_y = y -= pixbuf_rect.y;
        
        assert(last_grab_x >= 0);
        assert(last_grab_y >= 0);
        
        // repaint because crop changes on a manipulation
        repaint();
        
        return false;
    }
    
    private bool on_canvas_button_released(Gtk.DrawingArea da, Gdk.EventButton event) {
        // only interested in LMB
        if (event.button != 1)
            return false;
        
        if (in_manipulation == BoxLocation.OUTSIDE)
            return false;
        
        // end manipulation
        in_manipulation = BoxLocation.OUTSIDE;
        last_grab_x = -1;
        last_grab_y = -1;
        
        update_cursor((int) event.x, (int) event.y);
        
        // repaint because crop changes on a manipulation
        repaint();

        return false;
    }
    
    private void update_cursor(int x, int y) {
        assert(show_crop);
        
        // scaled_crop is not maintained relative to photo's position on canvas
        Box offset_scaled_crop = scaled_crop.get_offset(pixbuf_rect.x, pixbuf_rect.y);
        
        Gdk.CursorType cursor_type = Gdk.CursorType.ARROW;
        switch (offset_scaled_crop.location(x, y)) {
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
        }
        
        if (cursor_type != current_cursor_type) {
            Gdk.Cursor cursor = new Gdk.Cursor(cursor_type);
            canvas.window.set_cursor(cursor);
            current_cursor_type = cursor_type;
        }
    }
    
    private bool on_canvas_manipulation(int x, int y) {
        // scaled_crop is maintained in coordinates non-relative to photo's position on canvas ...
        // but bound tool to photo itself
        x -= pixbuf_rect.x;
        if (x < 0)
            x = 0;
        else if (x >= pixbuf_rect.width)
            x = pixbuf_rect.width - 1;
        
        y -= pixbuf_rect.y;
        if (y < 0)
            y = 0;
        else if (y >= pixbuf_rect.height)
            y = pixbuf_rect.height - 1;
        
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
                
                if (right >= pixbuf_rect.width)
                    right = pixbuf_rect.width - 1;
                
                if (bottom >= pixbuf_rect.height)
                    bottom = pixbuf_rect.height - 1;
                
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
    
    private void on_viewport_resize() {
        repaint();
    }
    
    private bool on_window_configured() {
        // if crop window is present and the user hasn't touched it, it moves with the window
        if (crop_tool_window != null && !crop_tool_window.user_moved)
            place_crop_tool_window();
        
        return false;
    }
    
    private bool on_canvas_expose(Gtk.DrawingArea da, Gdk.EventExpose event) {
        // to avoid multiple exposes
        if (event.count > 0)
            return false;
        
        if (pixmap == null)
            return false;
        
        canvas.window.draw_drawable(canvas.style.fg_gc[(int) Gtk.StateType.NORMAL], pixmap, event.area.x, 
            event.area.y, event.area.x, event.area.y, event.area.width, event.area.height);

        return true;
    }
    
    private void repaint(Gdk.InterpType paint_interp = FAST_INTERP) {
        // no image, no painting
        if (original == null)
            return;
        
        // account for border
        int width = viewport.allocation.width;
        int height = viewport.allocation.height;
        
        if (width <= 0 || height <= 0)
            return;
        
        bool new_image = (pixmap == null);
        
        // attempt to reuse pixmap
        if (pixmap != null) {
            if (pixmap_dim.width != width || pixmap_dim.height != height)
                pixmap = null;
        }
        
        // if necessary, create a pixmap as large as the entire viewport
        if (pixmap == null) {
            pixmap = new Gdk.Pixmap(canvas.window, width, height, -1);
            pixmap_dim = Dimensions(width, height);
            
            // need a new pixbuf to fit this scale
            pixbuf = null;

            // resize canvas for the pixmap (that is, the entire viewport)
            canvas.set_size_request(width, height);

            // determine size of pixbuf that will fit on the canvas
            Dimensions old_pixbuf_dim = Dimensions.for_rectangle(pixbuf_rect);
            Dimensions pixbuf_dim = Dimensions.for_pixbuf(original).get_scaled_proportional(pixmap_dim);

            // center pixbuf on the canvas
            int photo_x = (width - pixbuf_dim.width) / 2;
            int photo_y = (height - pixbuf_dim.height) / 2;

            // store pixbuf's position in the pixmap/canvas
            pixbuf_rect.x = photo_x;
            pixbuf_rect.y = photo_y;
            pixbuf_rect.width = pixbuf_dim.width;
            pixbuf_rect.height = pixbuf_dim.height;
        
            // only rescale the crop if resizing an existing image
            if (show_crop) {
                if (new_image)
                    init_crop();
                else
                    rescale_crop(old_pixbuf_dim, pixbuf_dim);
            }
            
            // override caller's request ... pixbuf will be rescheduled for improvement
            paint_interp = FAST_INTERP;

            // draw background
            pixmap.draw_rectangle(canvas.style.black_gc, true, 0, 0, width, height);
        } else if (paint_interp == FAST_INTERP) {
            // block calls where the pixmap is not being regenerated and the caller is asking for
            // a lower interp
            if (interp == QUALITY_INTERP)
                paint_interp = QUALITY_INTERP;
        }
        
        // fetch photo or rescale photo if canvas rescaled or better quality is requested
        if (pixbuf == null || interp != paint_interp) {
            pixbuf = original.scale_simple(pixbuf_rect.width, pixbuf_rect.height, paint_interp);
            interp = paint_interp;

            // create desaturated pixbuf for crop tool
            if (show_crop) {
                desaturated = new Gdk.Pixbuf(pixbuf.get_colorspace(), pixbuf.get_has_alpha(), 
                    pixbuf.get_bits_per_sample(), pixbuf.get_width(), pixbuf.get_height());
                pixbuf.saturate_and_pixelate(desaturated, CROP_SATURATION, false);
            } else {
                desaturated = null;
            }
        }

        if (show_crop) {
            draw_with_crop();
        } else {
            // lay down the photo and nothing else
            pixmap.draw_pixbuf(canvas.style.fg_gc[(int) Gtk.StateType.NORMAL], pixbuf, 0, 0, pixbuf_rect.x, 
                pixbuf_rect.y, -1, -1, Gdk.RgbDither.NORMAL, 0, 0);
        }
        
        // invalidate everything
        if (canvas.window != null)
            canvas.window.invalidate_rect(null, true);
        
        // schedule improvement if low-quality pixbuf was used
        if (interp != QUALITY_INTERP)
            schedule_improval();
    }
    
    private void schedule_improval() {
        if (improval_scheduled) {
            reschedule_improval = true;
            
            return;
        }
        
        Timeout.add(IMPROVAL_MSEC, image_improval);
        improval_scheduled = true;
    }
    
    private bool image_improval() {
        if (reschedule_improval) {
            reschedule_improval = false;
            
            return true;
        }
        
        repaint(QUALITY_INTERP);
        improval_scheduled = false;
        
        return false;
    }
    
    private void rotate(Rotation rotation) {
        deactivate_crop();
        
        // let the signal generate a repaint
        photo.rotate(rotation);
    }
    
    private void on_rotate_clockwise() {
        rotate(Rotation.CLOCKWISE);
    }
    
    private void on_rotate_counterclockwise() {
        rotate(Rotation.COUNTERCLOCKWISE);
    }
    
    private void on_mirror() {
        rotate(Rotation.MIRROR);
    }

    private override bool on_ctrl_pressed(Gdk.EventKey event) {
        rotate_button.set_stock_id(STOCK_COUNTERCLOCKWISE);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotate_button.set_stock_id(STOCK_CLOCKWISE);
        rotate_button.clicked -= on_rotate_counterclockwise;
        rotate_button.clicked += on_rotate_clockwise;
        
        return false;
    }
    
    private void on_crop_toggled() {
        if (crop_button.active) {
            activate_crop();
        } else {
            // return to original view ... do this before deactivating crop, so its repaint takes
            // effect
            original = photo.get_pixbuf();
            pixmap = null;

            deactivate_crop();
        }
    }
    
    private void place_crop_tool_window() {
        assert(crop_tool_window != null);

        // position crop tool window centered on viewport/canvas at the bottom, straddling
        // the canvas and the toolbar
        int rx, ry;
        AppWindow.get_instance().window.get_root_origin(out rx, out ry);
        
        int cx, cy, cwidth, cheight;
        cx = viewport.allocation.x;
        cy = viewport.allocation.y;
        cwidth = viewport.allocation.width;
        cheight = viewport.allocation.height;
        
        Gtk.Requisition req;
        crop_tool_window.size_request(out req);
        crop_tool_window.move(rx + cx + (cwidth / 2) - (req.width / 2), ry + cy + cheight);
    }
    
    private void activate_crop() {
        if (show_crop)
            return;
            
        // show uncropped photo for editing
        original = photo.get_pixbuf(Photo.EXCEPTION_CROP);

        // flush to force repaint
        pixmap = null;
        
        crop_button.set_active(true);

        show_crop = true;
        
        crop_tool_window = new CropToolWindow(AppWindow.get_instance());
        crop_tool_window.apply_button.clicked += on_crop_apply;
        crop_tool_window.cancel_button.clicked += on_crop_cancel;
        crop_tool_window.show_all();
        
        place_crop_tool_window();

        repaint();
    }
    
    private void deactivate_crop() {
        if (!show_crop)
            return;
        
        if (crop_tool_window != null) {
            crop_tool_window.hide();
            crop_tool_window = null;
        }
        
        crop_button.set_active(false);
        
        // make sure the cursor isn't set to a modify indicator
        canvas.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.ARROW));
        
        show_crop = false;
        
        repaint();
    }
    
    private void init_crop() {
        // using uncropped photo to work with
        Dimensions photo_dim = photo.get_uncropped_dimensions();

        Box crop;
        if (!photo.get_crop(out crop)) {
            int xofs = (int) (photo_dim.width * CROP_INIT_X_PCT);
            int yofs = (int) (photo_dim.height * CROP_INIT_Y_PCT);
            
            // initialize the actual crop in absolute coordinates, not relative
            // to the photo's position on the canvas
            crop = Box(xofs, yofs, photo_dim.width - xofs, photo_dim.height - yofs);
        }
        
        // scale the crop to the scaled photo's size ... the scaled crop is maintained in
        // coordinates not relative to photo's position on canvas
        scaled_crop = crop.get_scaled_proportional(photo_dim, Dimensions.for_rectangle(pixbuf_rect));
    }

    private void rescale_crop(Dimensions old_pixbuf_dim, Dimensions new_pixbuf_dim) {
        assert(show_crop);
        
        Dimensions photo_dim = photo.get_uncropped_dimensions();
        
        // rescale to full crop
        Box crop = scaled_crop.get_scaled_proportional(old_pixbuf_dim, photo_dim);
        
        // rescale back to new size
        scaled_crop = crop.get_scaled_proportional(photo_dim, new_pixbuf_dim);
    }
    
    private void paint_pixbuf(Gdk.Pixbuf pb, Box source) {
        pixmap.draw_pixbuf(canvas.style.fg_gc[(int) Gtk.StateType.NORMAL], pb,
            source.left, source.top,
            pixbuf_rect.x + source.left, pixbuf_rect.y + source.top,
            source.get_width(), source.get_height(),
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    private void paint_horizontal_line(Gdk.Pixbuf pb, int x, int y, int width) {
        pixmap.draw_pixbuf(canvas.style.fg_gc[(int) Gtk.StateType.NORMAL], pb,
            x, y,
            pixbuf_rect.x + x, pixbuf_rect.y + y,
            width, 1,
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    private void paint_vertical_line(Gdk.Pixbuf pb, int x, int y, int height) {
        pixmap.draw_pixbuf(canvas.style.fg_gc[(int) Gtk.StateType.NORMAL], pb,
            x, y,
            pixbuf_rect.x + x, pixbuf_rect.y + y,
            1, height,
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    private void paint_rectangle(Gdk.Pixbuf pb, Box box) {
        paint_horizontal_line(pb, box.left, box.top, box.get_width());
        paint_horizontal_line(pb, box.left, box.bottom, box.get_width());
        
        paint_vertical_line(pb, box.left, box.top, box.get_height());
        paint_vertical_line(pb, box.right, box.top, box.get_height());
    }
    
    private void invalidate_box(Box dirty) {
        Gdk.Rectangle rect = dirty.get_rectangle();
        rect.x += pixbuf_rect.x;
        rect.y += pixbuf_rect.y;
        
        canvas.window.invalidate_rect(rect, false);
    }
    
    private void invalidate_horizontal_line(int x, int y, int width) {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = x + pixbuf_rect.x;
        rect.y = y + pixbuf_rect.y;
        rect.width = width;
        rect.height = 1;
        
        canvas.window.invalidate_rect(rect, false);
    }
    
    private void invalidate_vertical_line(int x, int y, int height) {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = x + pixbuf_rect.x;
        rect.y = y + pixbuf_rect.y;
        rect.width = 1;
        rect.height = height;
        
        canvas.window.invalidate_rect(rect, false);
    }
    
    private void paint_crop_tool(Box crop) {
        // crop is maintained in photo coordinates ... move to offset of photo on canvas
        Box offset_crop = crop.get_offset(pixbuf_rect.x, pixbuf_rect.y);
        
        Gdk.GC gc = canvas.style.white_gc;
        
        // outer rectangle ... see note at gtk_drawable_draw_rectangle for info on off-by-one with
        // unfilled rectangles
        pixmap.draw_rectangle(gc, false, offset_crop.left, offset_crop.top, 
            offset_crop.get_width() - 1, offset_crop.get_height() - 1);
        
        // paint rule-of-thirds lines if user is manipulating the crop
        if (in_manipulation != BoxLocation.OUTSIDE) {
            int one_third_x = offset_crop.get_width() / 3;
            int one_third_y = offset_crop.get_height() / 3;
            
            // horizontal lines
            Gdk.draw_line(pixmap, gc, offset_crop.left, offset_crop.top + one_third_y,
                offset_crop.right, offset_crop.top + one_third_y);
            Gdk.draw_line(pixmap, gc, offset_crop.left, offset_crop.top + (one_third_y * 2),
                offset_crop.right, offset_crop.top + (one_third_y * 2));
            
            // vertical lines
            Gdk.draw_line(pixmap, gc, offset_crop.left + one_third_x, offset_crop.top,
                offset_crop.left + one_third_x, offset_crop.bottom);
            Gdk.draw_line(pixmap, gc, offset_crop.left + (one_third_x * 2), offset_crop.top,
                offset_crop.left + (one_third_x * 2), offset_crop.bottom);
        }
    }
    
    private void erase_crop_tool(Box crop) {
        // outer border
        paint_rectangle(pixbuf, crop);
        
        // paint rule-of-thirds lines if user is manipulating the crop
        if (in_manipulation != BoxLocation.OUTSIDE) {
            int one_third_x = crop.get_width() / 3;
            int one_third_y = crop.get_height() / 3;
            
            // horizontal lines
            paint_horizontal_line(pixbuf, crop.left, crop.top + one_third_y, crop.get_width());
            paint_horizontal_line(pixbuf, crop.left, crop.top + (one_third_y * 2), crop.get_width());
            
            // vertical lines
            paint_vertical_line(pixbuf, crop.left + one_third_x, crop.top, crop.get_height());
            paint_vertical_line(pixbuf, crop.left + (one_third_x * 2), crop.top, crop.get_height());
        }
    }
    
    private void invalidate_crop_tool(Box crop) {
        // outer border
        invalidate_box(crop);
        
        // paint rule-of-thirds lines if user is manipulating the crop
        if (in_manipulation != BoxLocation.OUTSIDE) {
            int one_third_x = crop.get_width() / 3;
            int one_third_y = crop.get_height() / 3;
            
            // horizontal lines
            invalidate_horizontal_line(crop.left, crop.top + one_third_y, crop.get_width());
            invalidate_horizontal_line(crop.left, crop.top + (one_third_y * 2), crop.get_width());

            // vertical lines
            invalidate_vertical_line(crop.left + one_third_x, crop.top, crop.get_height());
            invalidate_vertical_line(crop.left + (one_third_x * 2), crop.top, crop.get_height());
        }
    }
    
    private void crop_resized(Box new_crop) {
        if(scaled_crop.equals(new_crop)) {
            // no change
            return;
        }
        
        // erase crop and rule-of-thirds lines
        erase_crop_tool(scaled_crop);
        invalidate_crop_tool(scaled_crop);
        
        Box horizontal;
        bool horizontal_enlarged;
        Box vertical;
        bool vertical_enlarged;
        BoxComplements complements = scaled_crop.resized_complements(new_crop, out horizontal,
            out horizontal_enlarged, out vertical, out vertical_enlarged);
        
        // this should never happen ... this means that the operation wasn't a resize
        assert(complements != BoxComplements.NONE);
        
        if (complements == BoxComplements.HORIZONTAL || complements == BoxComplements.BOTH) {
            Gdk.Pixbuf pb = horizontal_enlarged ? pixbuf : desaturated;
            paint_pixbuf(pb, horizontal);
            
            invalidate_box(horizontal);
        }
        
        if (complements == BoxComplements.VERTICAL || complements == BoxComplements.BOTH) {
            Gdk.Pixbuf pb = vertical_enlarged ? pixbuf : desaturated;
            paint_pixbuf(pb, vertical);
            
            invalidate_box(vertical);
        }
        
        paint_crop_tool(new_crop);
        invalidate_crop_tool(new_crop);
    }
    
    private void crop_moved(Box new_crop) {
        if (scaled_crop.equals(new_crop)) {
            // no change
            return;
        }
        
        // erase crop and rule-of-thirds lines
        erase_crop_tool(scaled_crop);
        invalidate_crop_tool(scaled_crop);
        
        Box scaled_horizontal;
        Box scaled_vertical;
        Box new_horizontal;
        Box new_vertical;
        BoxComplements complements = scaled_crop.shifted_complements(new_crop, out scaled_horizontal,
            out scaled_vertical, out new_horizontal, out new_vertical);
        
        if (complements == BoxComplements.HORIZONTAL || complements == BoxComplements.BOTH) {
            // paint in the horizontal complements appropriately
            paint_pixbuf(desaturated, scaled_horizontal);
            paint_pixbuf(pixbuf, new_horizontal);
            
            invalidate_box(scaled_horizontal);
            invalidate_box(new_horizontal);
        }
        
        if (complements == BoxComplements.VERTICAL || complements == BoxComplements.BOTH) {
            // paint in vertical complements appropriately
            paint_pixbuf(desaturated, scaled_vertical);
            paint_pixbuf(pixbuf, new_vertical);
            
            invalidate_box(scaled_vertical);
            invalidate_box(new_vertical);
        }
        
        if (complements == BoxComplements.NONE) {
            // this means the two boxes have no intersection, not that they're equal ... since
            // there's no intersection, fill in both new and old with apropriate pixbufs
            paint_pixbuf(desaturated, scaled_crop);
            paint_pixbuf(pixbuf, new_crop);
            
            invalidate_box(scaled_crop);
            invalidate_box(new_crop);
        }
        
        // paint crop in new location
        paint_crop_tool(new_crop);
        invalidate_crop_tool(new_crop);
    }
    
    private void draw_with_crop() {
        assert(show_crop);
        
        Gdk.GC image_gc = canvas.style.fg_gc[(int) Gtk.StateType.NORMAL];
        
        // painter's algorithm: from the bottom up, starting with the desaturated portion of the
        // photo outside the crop
        pixmap.draw_pixbuf(image_gc, desaturated, 
            0, 0, 
            pixbuf_rect.x, pixbuf_rect.y, 
            pixbuf_rect.width, pixbuf_rect.height,
            Gdk.RgbDither.NORMAL, 0, 0);
        
        // paint exposed (cropped) part of pixbuf minus crop border
        paint_pixbuf(pixbuf, scaled_crop);

        // paint crop tool last
        paint_crop_tool(scaled_crop);
    }
    
    private void on_crop_apply() {
        // up-scale scaled crop to photo's dimensions
        Box crop = scaled_crop.get_scaled_proportional(Dimensions.for_rectangle(pixbuf_rect), 
            photo.get_uncropped_dimensions());

        deactivate_crop();

        // let the signal generate a repaint
        photo.set_crop(crop);
    }
    
    private void on_crop_cancel() {
        deactivate_crop();
        
        // let the signal generate a repaint
        photo.remove_crop();
    }
    
    private void on_next_photo() {
        deactivate_crop();
        
        this.thumbnail = (Thumbnail) controller.get_next_item(thumbnail);
        update_display();
    }
    
    private void on_previous_photo() {
        deactivate_crop();
        
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

