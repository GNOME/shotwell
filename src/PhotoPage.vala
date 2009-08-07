/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class PhotoPage : SinglePhotoPage {
    public const int TOOL_WINDOW_SEPARATOR = 8;
    
    private class PhotoPageCanvas : PhotoCanvas {
        private PhotoPage photo_page;
        
        public PhotoPageCanvas(PhotoPage photo_page) {
            base(photo_page.container, photo_page.canvas.window, photo_page.photo, photo_page.canvas_gc, 
                photo_page.get_drawable(), photo_page.get_scaled_pixbuf(), photo_page.get_scaled_pixbuf_position());
            
            this.photo_page = photo_page;
        }
        
        public override void repaint() {
            photo_page.repaint(SinglePhotoPage.QUALITY_INTERP);
        }
    }
    
    private Gtk.Window container = null;
    private Gtk.Menu context_menu;
    private CheckerboardPage controller = null;
    private Photo photo = null;
    private Thumbnail thumbnail = null;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToggleToolButton crop_button = null;
    private Gtk.ToggleToolButton redeye_button = null;
    private Gtk.ToggleToolButton adjust_button = null;
    private Gtk.ToolButton prev_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
    private Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
    private EditingTool current_tool = null;
    
    // drag-and-drop state
    private File drag_file = null;
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, null },
        { "Export", Gtk.STOCK_SAVE_AS, "_Export Photos...", "<Ctrl>E", "Export photo to disk", on_export },
        
        { "ViewMenu", null, "_View", null, null, on_view_menu },
        { "ReturnToPage", Resources.RETURN_TO_PAGE, "_Return to Photos", "Escape", null, on_return_to_collection },

        { "PhotoMenu", null, "_Photo", null, null, on_photo_menu },
        { "PrevPhoto", Gtk.STOCK_GO_BACK, "_Previous Photo", null, "Previous Photo", on_previous_photo },
        { "NextPhoto", Gtk.STOCK_GO_FORWARD, "_Next Photo", null, "Next Photo", on_next_photo },
        { "RotateClockwise", Resources.CLOCKWISE, "Rotate _Right", "<Ctrl>R", "Rotate the selected photos clockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE, "Rotate _Left", "<Ctrl><Shift>R", "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", Resources.MIRROR, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", on_mirror },
        { "Revert", Gtk.STOCK_REVERT_TO_SAVED, "Re_vert to Original", null, "Revert to the original photo", on_revert },

        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    public PhotoPage() {
        base("Photo");
        
        init_ui("photo.ui", "/PhotoMenuBar", "PhotoActionGroup", ACTIONS);

        context_menu = (Gtk.Menu) ui.get_widget("/PhotoContextMenu");

        // set up page's toolbar (used by AppWindow for layout and FullscreenWindow as a popup)
        //
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CLOCKWISE_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CLOCKWISE_TOOLTIP);
        rotate_button.clicked += on_rotate_clockwise;
        toolbar.insert(rotate_button, -1);
        
        // crop tool
        crop_button = new Gtk.ToggleToolButton.from_stock(Resources.CROP);
        crop_button.set_label("Crop");
        crop_button.set_tooltip_text("Crop the photo's size");
        crop_button.toggled += on_crop_toggled;
        toolbar.insert(crop_button, -1);

        // redeye reduction tool
        redeye_button = new Gtk.ToggleToolButton.from_stock(Resources.REDEYE);
        redeye_button.set_label("Red-eye");
        redeye_button.set_tooltip_text("Reduce or eliminate any red-eye effects in the photo");
        redeye_button.toggled += on_redeye_toggled;
        toolbar.insert(redeye_button, -1);
        
        // adjust tool
        adjust_button = new Gtk.ToggleToolButton.from_stock(Resources.ADJUST);
        adjust_button.set_label("Adjust");
        adjust_button.set_tooltip_text("Adjust the photo's color and tone");
        adjust_button.toggled += on_adjust_toggled;
        toolbar.insert(adjust_button, -1);

        // separator to force next/prev buttons to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // previous button
        prev_button.set_tooltip_text("Previous photo");
        prev_button.clicked += on_previous_photo;
        toolbar.insert(prev_button, -1);
        
        // next button
        next_button.set_tooltip_text("Next photo");
        next_button.clicked += on_next_photo;
        toolbar.insert(next_button, -1);
        
    }
    
    public void set_container(Gtk.Window container) {
        // this should only be called once
        assert(this.container == null);

        this.container = container;

        // DnD only available in full-window view
        if (!(container is FullscreenWindow))
            enable_drag_source(Gdk.DragAction.COPY);
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
        base.switching_from();

        deactivate_tool();
    }
    
    public override void switching_to_fullscreen() {
        base.switching_to_fullscreen();

        deactivate_tool();
    }
    
    public void display(CheckerboardPage controller, Thumbnail thumbnail) {
        deactivate_tool();
        
        this.controller = controller;
        this.thumbnail = thumbnail;
        
        set_page_name(thumbnail.get_title());
        
        update_display();
        update_sensitivity();
    }
    
    private void update_display() {
        if (photo != null)
            photo.altered -= on_photo_altered;
            
        photo = thumbnail.get_photo();
        photo.altered += on_photo_altered;
        
        // throw a resized large thumbnail up to get an image on the screen quickly,
        // and when ready decode and display the full image
        set_pixbuf(photo.get_thumbnail(ThumbnailCache.BIG_SCALE));
        Idle.add(update_pixbuf);
    }
    
    private bool update_pixbuf() {
        // Photo.get_pixbuf() can optimize its pipeline if given a scale to work with ... since
        // SinglePhotoPage may need to resize its unscaled image thousands of times if the user
        // resizes the window, get a scaled image large enough for the screen
        Gdk.Screen screen = AppWindow.get_instance().window.get_screen();
        int scale = int.max(screen.get_width(), screen.get_height());

        set_pixbuf(photo.get_pixbuf(Photo.EXCEPTION_NONE, scale));
        
        return false;
    }
    
    private void update_sensitivity() {
        bool multiple = controller.get_count() > 1;
        
        prev_button.sensitive = multiple;
        next_button.sensitive = multiple;
    }

    private void activate_tool(EditingTool tool) {
        // during editing, always use the quality interpolation, so the editing tool is only
        // dealing with one pixbuf (unless page is resized)
        set_default_interp(QUALITY_INTERP);
        
        // deactivate current tool ... current implementation is one tool at a time.  In the future,
        // tools may be allowed to be executing at the same time.
        deactivate_tool();
        
        // see if the tool wants a different pixbuf displayed
        Gdk.Pixbuf unscaled = tool.get_unscaled_pixbuf(photo);
        if (unscaled != null)
            set_pixbuf(unscaled);
        
        // create the PhotoCanvas object for a two-way interface to the tool
        PhotoCanvas photo_canvas = new PhotoPageCanvas(this);

        // hook tool into event system and activate it
        current_tool = tool;
        current_tool.activate(photo_canvas);
        
        // if the tool has an auxilliary window, move it properly on the screen
        place_tool_window();
        
        // now that the tool window has been placed, show it
        show_tool_window();

        // repaint entire view, with the tool now hooked in
        default_repaint();
    }
    
    private void deactivate_tool() {
        if (current_tool == null)
            return;
        
        EditingTool tool = current_tool;
        current_tool = null;
        
        // deactivate with the tool taken out of the hooks
        tool.deactivate();
        
        // return to fast interpolation for viewing
        set_default_interp(FAST_INTERP);
        
        // display the (possibly) new photo
        update_pixbuf();
    }
    
    private override void drag_begin(Gdk.DragContext context) {
        // drag_data_get may be called multiple times within a drag as different applications
        // query for target type and information ... to prevent a lot of file generation, do all
        // the work up front
        File file = null;
        try {
            file = photo.generate_exportable();
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // set up icon for drag-and-drop
        Gdk.Pixbuf icon = photo.get_thumbnail(ThumbnailCache.MEDIUM_SCALE);
        Gtk.drag_source_set_icon_pixbuf(canvas, icon);

        debug("Prepared for export %s", file.get_path());
        
        drag_file = file;
    }
    
    private override void drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint target_type, uint time) {
        assert(target_type == TargetType.URI_LIST);
        
        if (drag_file == null)
            return;
        
        string[] uris = new string[1];
        uris[0] = drag_file.get_uri();
        
        selection_data.set_uris(uris);
    }
    
    private override void drag_end(Gdk.DragContext context) {
        drag_file = null;
    }
    
    private override bool source_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        debug("Drag failed: %d", (int) drag_result);
        
        drag_file = null;
        
        return false;
    }
    
    // Return true to block the DnD handler from activating a drag
    private override bool on_left_click(Gdk.EventButton event) {
        // on double-click, if not editing and not hosted by a fullscreen window, return to the
        // controller collection
        if (event.type == Gdk.EventType.2BUTTON_PRESS && current_tool == null 
            && !(container is FullscreenWindow)) {
            on_return_to_collection();
            
            return true;
        }
        
        int x = (int) event.x;
        int y = (int) event.y;
        
        // only concerned about mouse-downs on the pixbuf ... return true prevents DnD when the
        // user drags outside the displayed photo
        if (!is_inside_pixbuf(x, y))
            return true;
        
        // if no editing tool, then done
        if (current_tool == null)
            return false;
        
        current_tool.on_left_click(x, y);
        
        // block DnD handlers if tool is enabled
        return true;
    }
    
    private override bool on_left_released(Gdk.EventButton event) {
        // report all releases, as it's possible the user click and dragged from inside the
        // pixbuf to the gutters
        if (current_tool != null)
            current_tool.on_left_released((int) event.x, (int) event.y);
        
        return false;
    }
    
    private override bool on_right_click(Gdk.EventButton event) {
        return on_context_menu(event);
    }
    
    private void on_view_menu() {
        Gtk.MenuItem return_item = (Gtk.MenuItem) ui.get_widget("/PhotoMenuBar/ViewMenu/ReturnToPage");
        if (return_item != null && controller != null) {
            Gtk.Label label = (Gtk.Label) return_item.get_child();
            if (label != null)
                label.set_text("Return to %s".printf(controller.get_page_name()));
        }
    }
    
    private void on_return_to_collection() {
        AppWindow.get_instance().switch_to_page(controller);
    }
    
    private void on_export() {
        ExportDialog export_dialog = new ExportDialog(1);
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        if (!export_dialog.execute(out scale, out constraint, out quality))
            return;
        
        File save_as = ExportUI.choose_file(photo.get_file());
        if (save_as == null)
            return;
        
        try {
            photo.export(save_as, scale, constraint, quality);
        } catch (Error err) {
            AppWindow.error_message("Unable to export %s: %s".printf(save_as.get_path(), err.message));
        }
    }
    
    private void on_photo_altered(Photo p) {
        assert(photo.equals(p));
        
        update_pixbuf();
    }
    
    private override bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        if (current_tool != null)
            current_tool.on_motion(x, y, mask);
            
        return false;
    }
    
    private bool on_context_menu(Gdk.EventButton event) {
        if (photo == null)
            return false;
        
        set_item_sensitive("/PhotoContextMenu/ContextRevert", photo.has_transformations());

        context_menu.popup(null, null, null, event.button, event.time);
        
        return true;
    }
    
    private override bool on_configure(Gdk.EventConfigure event, Gdk.Rectangle rect) {
        // if editing tool window is present and the user hasn't touched it, it moves with the window
        if (current_tool != null) {
            EditingToolWindow tool_window = current_tool.get_tool_window();
            if (tool_window != null && !tool_window.has_user_moved())
                place_tool_window();
        }
        
        return (base.on_configure != null) ? base.on_configure(event, rect) : false;
    }
    
    private override bool key_press_event(Gdk.EventKey event) {
        // editing tool gets first crack at the keypress
        if (current_tool != null) {
            if (current_tool.on_keypress(event))
                return true;
        }
        
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "Left":
            case "KP_Left":
                on_previous_photo();
            break;
            
            case "Right":
            case "KP_Right":
                on_next_photo();
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled)
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : true;
    }
    
    protected override void new_drawable(Gdk.GC default_gc, Gdk.Drawable drawable) {
        // if tool is open, update its canvas object
        if (current_tool != null)
            current_tool.canvas.set_drawable(default_gc, drawable);
    }
    
    protected override void updated_pixbuf(Gdk.Pixbuf pixbuf, SinglePhotoPage.UpdateReason reason, 
        Dimensions old_dim) {
        // only purpose here is to inform editing tool of change
        if (current_tool != null)
            current_tool.canvas.resized_pixbuf(old_dim, pixbuf, get_scaled_pixbuf_position());
    }
    
    protected override void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        if (current_tool != null)
            current_tool.paint(gc, drawable);
        else
            base.paint(gc, drawable);
    }

    private void rotate(Rotation rotation) {
        deactivate_tool();
        
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
    
    private void on_revert() {
        deactivate_tool();
        
        photo.remove_all_transformations();
    }

    private override bool on_ctrl_pressed(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.COUNTERCLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_COUNTERCLOCKWISE_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_COUNTERCLOCKWISE_TOOLTIP);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CLOCKWISE_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CLOCKWISE_TOOLTIP);
        rotate_button.clicked -= on_rotate_counterclockwise;
        rotate_button.clicked += on_rotate_clockwise;
        
        return false;
    }
    
    private void on_crop_toggled() {
        if (crop_button.active) {
            // create the tool, hook its signals, and activate it
            CropTool crop_tool = new CropTool();
            crop_tool.activated += on_crop_activated;
            crop_tool.deactivated += on_crop_deactivated;
            crop_tool.applied += on_crop_done;
            crop_tool.cancelled += on_crop_done;
            
            activate_tool(crop_tool);
        } else {
            deactivate_tool();
        }
    }

    private void on_redeye_toggled() {
        if (redeye_button.active) {
            RedeyeTool redeye_tool = new RedeyeTool();
            redeye_tool.activated += on_redeye_activated;
            redeye_tool.deactivated += on_redeye_deactivated;
            redeye_tool.applied += on_redeye_applied;
            redeye_tool.cancelled += on_redeye_closed;
            
            activate_tool(redeye_tool);
        } else {
            deactivate_tool();
        }
    }
    
    private void on_adjust_toggled() {
        if (adjust_button.active) {
            AdjustTool adjust_tool = new AdjustTool();
            adjust_tool.activated += on_adjust_activated;
            adjust_tool.deactivated += on_adjust_deactivated;
            adjust_tool.cancelled += on_adjust_closed;
            adjust_tool.applied += on_adjust_applied;

            activate_tool(adjust_tool);
        } else {
            deactivate_tool();
        }
    }
    
    private void on_crop_done() {
        deactivate_tool();
    }

    private void on_redeye_applied() {
    }

    private void on_redeye_closed() {
        deactivate_tool();
    }
    
    private void on_adjust_closed() {
        deactivate_tool();
    }
    
    private void on_adjust_applied() {
        deactivate_tool();
    }
    
    private void on_crop_activated() {
        crop_button.set_active(true);
    }

    private void on_redeye_activated() {
        redeye_button.set_active(true);
    }

    private void on_crop_deactivated() {
        crop_button.set_active(false);
    }

    private void on_redeye_deactivated() {
        redeye_button.set_active(false);
    }

    private void on_adjust_activated() {
        adjust_button.set_active(true);
    }
    
    private void on_adjust_deactivated() {
        adjust_button.set_active(false);
    }

    private void place_tool_window() {
        if (current_tool == null)
            return;
            
        EditingToolWindow tool_window = current_tool.get_tool_window();
        if (tool_window == null)
            return;

        Gtk.Requisition req;
        tool_window.size_request(out req);

        if (container == AppWindow.get_instance()) {
            // Normal: position crop tool window centered on viewport/canvas at the bottom, straddling
            // the canvas and the toolbar
            int rx, ry;
            container.window.get_root_origin(out rx, out ry);
            
            int cx, cy, cwidth, cheight;
            cx = viewport.allocation.x;
            cy = viewport.allocation.y;
            cwidth = viewport.allocation.width;
            cheight = viewport.allocation.height;
            
            tool_window.move(rx + cx + (cwidth / 2) - (req.width / 2), ry + cy + cheight);
        } else {
            assert(container is FullscreenWindow);
            
            // Fullscreen: position crop tool window centered on screen at the bottom, just above the
            // toolbar
            Gtk.Requisition toolbar_req;
            toolbar.size_request(out toolbar_req);
            
            Gdk.Screen screen = container.get_screen();
            int x = (screen.get_width() - req.width) / 2;
            int y = screen.get_height() - toolbar_req.height - req.height - TOOL_WINDOW_SEPARATOR;
            
            tool_window.move(x, y);
        }
    }
    
    private void show_tool_window() {
         if (current_tool == null)
            return;

        EditingToolWindow tool_window = current_tool.get_tool_window();
        if (tool_window == null)
            return;
        
        tool_window.show_all();
    }
    
    private void on_photo_menu() {
        bool multiple = false;
        if (controller != null)
            multiple = controller.get_count() > 1;
        
        bool revert_possible = false;
        if (photo != null)
            revert_possible = photo.has_transformations();
            
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/NextPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Revert", revert_possible);
    }
    
    private void on_next_photo() {
        deactivate_tool();
        
        this.thumbnail = (Thumbnail) controller.get_next_item(thumbnail);
        update_display();
    }
    
    private void on_previous_photo() {
        deactivate_tool();
        
        this.thumbnail = (Thumbnail) controller.get_previous_item(thumbnail);
        update_display();
    }

    public override Gee.Iterable<Queryable>? get_queryables() {
        Gee.ArrayList<Photo> photo_array_list = new Gee.ArrayList<Photo>();
        photo_array_list.add(photo);
        return photo_array_list;
    }

    public override Gee.Iterable<Queryable>? get_selected_queryables() {
        return get_queryables();
    }
}

