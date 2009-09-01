/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class EditingHostPage : SinglePhotoPage {
    public const int TOOL_WINDOW_SEPARATOR = 8;
    
    private class EditingHostCanvas : PhotoCanvas {
        private EditingHostPage host_page;
        
        public EditingHostCanvas(EditingHostPage host_page) {
            base(host_page.container, host_page.canvas.window, host_page.photo, host_page.canvas_gc, 
                host_page.get_drawable(), host_page.get_scaled_pixbuf(), host_page.get_scaled_pixbuf_position());
            
            this.host_page = host_page;
        }
        
        public override void repaint() {
            host_page.repaint(SinglePhotoPage.QUALITY_INTERP);
        }
    }
    
    private Gtk.Window container = null;
    private PhotoCollection controller = null;
    private TransformablePhoto photo = null;
    private Gdk.Pixbuf original = null;
    private Gdk.Pixbuf swapped = null;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToggleToolButton crop_button = null;
    private Gtk.ToggleToolButton redeye_button = null;
    private Gtk.ToggleToolButton adjust_button = null;
    private Gtk.ToolButton enhance_button = null;
    private Gtk.ToolButton prev_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
    private Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
    private EditingTool current_tool = null;
    private File drag_file = null;
    private uint32 last_nav_key = 0;

    public virtual signal void check_replace_photo(TransformablePhoto old_photo, 
        TransformablePhoto new_photo, out bool ok) {
        ok = true;
    }

    public EditingHostPage(string name) {
        base(name);
        
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

        // ehance tool
        enhance_button = new Gtk.ToolButton.from_stock(Resources.ENHANCE);
        enhance_button.set_label("Enhance");
        enhance_button.set_tooltip_text("Automatically improve the photo's appearance");
        enhance_button.clicked += on_enhance_clicked;
        toolbar.insert(enhance_button, -1);

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
    
    public Gtk.Window? get_container() {
        return container;
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
    
    public PhotoCollection get_controller() {
        return controller;
    }
    
    public TransformablePhoto get_photo() {
        return photo;
    }
    
    public override void switching_from() {
        base.switching_from();

        deactivate_tool();
    }
    
    public override void switching_to_fullscreen() {
        base.switching_to_fullscreen();

        deactivate_tool();
    }
    
    protected void display(PhotoCollection controller, TransformablePhoto photo) {
        this.controller = controller;
        replace_photo(photo);
    }
    
    protected void replace_photo(TransformablePhoto new_photo) {
        if (new_photo == photo)
            return;
        
        // only check if okay if there's something to replace
        if (photo != null) {
            bool ok;
            check_replace_photo(photo, new_photo, out ok);
            
            if (!ok)
                return;
        }

        deactivate_tool();
        
        if (photo != null)
            photo.altered -= on_photo_altered;

        photo = new_photo;
        photo.altered += on_photo_altered;

        set_page_name(photo.get_name());

        quick_update_pixbuf();
        
        update_ui();
        
        // signal the photo has been replaced
        contents_changed(1);
        selection_changed(1);
        
        // clear out the comparison buffers
        original = null;
        swapped = null;
    }
    
    private void quick_update_pixbuf() {
        // throw a resized large thumbnail up to get an image on the screen quickly,
        // and when ready decode and display the full image
        set_pixbuf(photo.get_preview_pixbuf(TransformablePhoto.SCREEN));
        Idle.add(update_pixbuf);
    }
    
    private bool update_pixbuf() {
        set_pixbuf(photo.get_pixbuf(TransformablePhoto.SCREEN));

        // fetch the original for quick comparisons ... want a pixbuf with no transformations
        // (except original orientation)
        if (original == null)
            original = photo.get_original_pixbuf(TransformablePhoto.SCREEN);

        return false;
    }
    
    private void update_ui() {
        bool multiple = controller.get_count() > 1;

        prev_button.sensitive = multiple;
        next_button.sensitive = multiple;
    }
    
    private override bool on_shift_pressed(Gdk.EventKey event) {
        // show quick compare of original only if no tool is in use, the original pixbuf is handy,
        // and using quality interp to avoid pixellation if the user goes crazy with the shift key
        if (current_tool == null && original != null) {
            // store what's currently displayed only for the duration of the shift pressing
            swapped = get_unscaled_pixbuf();
            
            Gdk.InterpType interp = set_default_interp(QUALITY_INTERP);
            set_pixbuf(original);
            set_default_interp(interp);
        }
        
        return base.on_shift_pressed(event);
    }
    
    private override bool on_shift_released(Gdk.EventKey event) {
        if (current_tool == null && swapped != null) {
            Gdk.InterpType interp = set_default_interp(QUALITY_INTERP);
            set_pixbuf(swapped);
            set_default_interp(interp);
            
            // only store swapped once; it'll be set the next on_shift_pressed
            swapped = null;
        }
        
        return base.on_shift_pressed(event);
    }

    private void activate_tool(EditingTool tool) {
        // during editing, always use the quality interpolation, so the editing tool is only
        // dealing with one pixbuf (unless page is resized)
        set_default_interp(QUALITY_INTERP);
        
        // deactivate current tool ... current implementation is one tool at a time.  In the future,
        // tools may be allowed to be executing at the same time.
        deactivate_tool();
        
        // see if the tool wants a different pixbuf displayed
        Gdk.Pixbuf unscaled = tool.get_display_pixbuf(photo);
        if (unscaled != null)
            set_pixbuf(unscaled);
        
        // create the PhotoCanvas object for a two-way interface to the tool
        PhotoCanvas photo_canvas = new EditingHostCanvas(this);

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
        quick_update_pixbuf();
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
        try {
            Gdk.Pixbuf icon = photo.get_preview_pixbuf(AppWindow.DND_ICON_SCALE);
            Gtk.drag_source_set_icon_pixbuf(canvas, icon);
        } catch (Error err) {
            message("Unable to get drag-and-drop icon: %s", err.message);
        }

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
        photo.export_failed();
        
        return false;
    }
    
    // This virtual method is called only when the user double-clicks on the page and no tool
    // is active
    private virtual bool on_double_click(Gdk.EventButton event) {
        return false;
    }
    
    // Return true to block the DnD handler from activating a drag
    private override bool on_left_click(Gdk.EventButton event) {
        // report double-click if no tool is active, otherwise all double-clicks are eaten
        if (event.type == Gdk.EventType.2BUTTON_PRESS)
            return (current_tool == null) ? on_double_click(event) : false;
        
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
    
    private void on_photo_altered(TransformablePhoto p) {
        assert(p.equals(photo));

        // signal that the photo has been altered
        queryable_altered(photo);

        quick_update_pixbuf();

        update_ui();
    }
    
    private override bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        if (current_tool != null)
            current_tool.on_motion(x, y, mask);
            
        return false;
    }
    
    private virtual bool on_context_menu(Gdk.EventButton event) {
        return false;
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
        
        // if the user holds the arrow keys down, we will receive a steady stream of key press
        // events for an operation that isn't designed for a rapid succession of output ... 
        // we staunch the supply of new photos to once a second (#533)
        bool nav_ok = (event.time - last_nav_key) > 1000;
        
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "Left":
            case "KP_Left":
                if (nav_ok)
                    on_previous_photo();
                else
                    handled = false;
            break;
            
            case "Right":
            case "KP_Right":
                if (nav_ok)
                    on_next_photo();
                else
                    handled = false;
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled) {
            last_nav_key = event.time;
        
            return true;
        }

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
    
    public void on_rotate_clockwise() {
        rotate(Rotation.CLOCKWISE);
    }
    
    public void on_rotate_counterclockwise() {
        rotate(Rotation.COUNTERCLOCKWISE);
    }
    
    public void on_mirror() {
        rotate(Rotation.MIRROR);
    }
    
    public void on_revert() {
        deactivate_tool();
        
        photo.remove_all_transformations();
        
        queryable_altered(photo);
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

    private void on_enhance_clicked() {
        // because running multiple tools at once is not currently supported, deactivate any current
        // tool; however, there is a special case of running enhancement while the AdjustTool is
        // open, so allow for that
        if (!(current_tool is AdjustTool))
            deactivate_tool();
        
        AppWindow.get_instance().set_busy_cursor();

        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = photo.get_pixbuf(1024, TransformablePhoto.Exception.ALL);
        } catch (Error e) {
            error("PhotoPage: on_enhance_clicked: couldn't obtain pixbuf to build " +
                "transform histogram");
        }

        PixelTransformation[] transformations =
            new PixelTransformation[SupportedAdjustments.NUM];

        transformations[SupportedAdjustments.TONE_EXPANSION] =
            new ExpansionTransformation(new IntensityHistogram(pixbuf));

        /* zero out any existing color transformations as these may conflict with
           auto-enhancement */
        transformations[SupportedAdjustments.TEMPERATURE] =
            new TemperatureTransformation(0.0f);
        transformations[SupportedAdjustments.TINT] =
            new TintTransformation(0.0f);
        transformations[SupportedAdjustments.EXPOSURE] =
            new ExposureTransformation(0.0f);
        transformations[SupportedAdjustments.SATURATION] =
            new SaturationTransformation(0.0f);

        /* if the current tool is the adjust tool, then don't commit to the database --
           just set the slider values in the adjust dialog and force it to repaint
           the canvas */
        if (current_tool is AdjustTool) {
            ((AdjustTool) current_tool).set_adjustments(transformations);
        } else {
              /* if the current tool isn't the adjust tool then commit the changes
                 to the database */
            photo.set_adjustments(transformations);
        }

        AppWindow.get_instance().set_normal_cursor();
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
    
    public void on_next_photo() {
        deactivate_tool();
        
        TransformablePhoto new_photo = (TransformablePhoto) controller.get_next_photo(photo);
        if (new_photo != null)
            replace_photo(new_photo);
    }
    
    public void on_previous_photo() {
        deactivate_tool();
        
        TransformablePhoto new_photo = (TransformablePhoto) controller.get_previous_photo(photo);
        if (new_photo != null)
            replace_photo(new_photo);
    }

    public override Gee.Iterable<Queryable>? get_queryables() {
        Gee.ArrayList<PhotoSource> photo_array_list = new Gee.ArrayList<PhotoSource>();

        photo_array_list.add(photo);
        return photo_array_list;
    }

    public override Gee.Iterable<Queryable>? get_selected_queryables() {
        return get_queryables();
    }

    public override int get_queryable_count() {
        return 1;
    }

    public override int get_selected_queryable_count() {
        return get_queryable_count();
    }
}

public class LibraryPhotoPage : EditingHostPage {
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, null },
        { "Export", Gtk.STOCK_SAVE_AS, "_Export Photos...", "<Ctrl>E", "Export photo to disk", on_export },
        
        { "ViewMenu", null, "_View", null, null, on_view_menu },
        { "ReturnToPage", Resources.RETURN_TO_PAGE, "_Return to Photos", "Escape", null, on_return_to_collection },

        { "PhotoMenu", null, "_Photo", null, null, on_photo_menu },
        { "PrevPhoto", Gtk.STOCK_GO_BACK, "_Previous Photo", null, "Previous Photo", on_previous_photo },
        { "NextPhoto", Gtk.STOCK_GO_FORWARD, "_Next Photo", null, "Next Photo", on_next_photo },
        { "RotateClockwise", Resources.CLOCKWISE, "Rotate _Right", "<Ctrl>R", "Rotate the selected photos clockwise",
            on_rotate_clockwise },
        { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE, "Rotate _Left", "<Ctrl><Shift>R", 
            "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", Resources.MIRROR, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", 
            on_mirror },
        { "Revert", Gtk.STOCK_REVERT_TO_SAVED, "Re_vert to Original", null, "Revert to the original photo", 
            on_revert },

        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    private Gtk.Menu context_menu;
    private CollectionPage return_page = null;
    
    public LibraryPhotoPage() {
        base("Photo");
        
        init_ui("photo.ui", "/PhotoMenuBar", "PhotoActionGroup", ACTIONS);

        context_menu = (Gtk.Menu) ui.get_widget("/PhotoContextMenu");
    }
    
    public void display_for_collection(CollectionPage return_page, TransformablePhoto photo) {
        this.return_page = return_page;
        
        display(return_page.get_photo_collection(), photo);
    }
    
    public CollectionPage get_controller_page() {
        return return_page;
    }
    
    private override bool on_double_click(Gdk.EventButton event) {
        if (!(get_container() is FullscreenWindow)) {
            on_return_to_collection();
            
            return true;
        }
        
        return false;
    }

    private override bool on_context_menu(Gdk.EventButton event) {
        if (get_photo() == null)
            return false;
        
        set_item_sensitive("/PhotoContextMenu/ContextRevert", get_photo().has_transformations());

        context_menu.popup(null, null, null, event.button, event.time);
        
        return true;
    }

    private void on_view_menu() {
        Gtk.MenuItem return_item = (Gtk.MenuItem) ui.get_widget("/PhotoMenuBar/ViewMenu/ReturnToPage");
        if (return_item != null && return_page != null) {
            Gtk.Label label = (Gtk.Label) return_item.get_child();
            if (label != null)
                label.set_text("Return to %s".printf(return_page.get_page_name()));
        }
    }
    
    private void on_return_to_collection() {
        LibraryWindow.get_app().switch_to_page(return_page);
    }
    
    private void on_export() {
        if (get_photo() == null)
            return;
        
        ExportDialog export_dialog = new ExportDialog("Export Photo");
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        if (!export_dialog.execute(out scale, out constraint, out quality))
            return;
        
        File save_as = ExportUI.choose_file(get_photo().get_file());
        if (save_as == null)
            return;
        
        try {
            get_photo().export(save_as, scale, constraint, quality);
        } catch (Error err) {
            AppWindow.error_message("Unable to export %s: %s".printf(save_as.get_path(), err.message));
        }
    }
    
    private void on_photo_menu() {
        bool multiple = (get_controller() != null) ? get_controller().get_count() > 1 : false;
        bool revert_possible = (get_photo() != null) ? get_photo().has_transformations() : false;
            
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/NextPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Revert", revert_possible);
    }
}

public class DirectPhotoCollection : Object, PhotoCollection {
    private static FileComparator file_comparator = new FileComparator();
    
    private File dir;
    
    public DirectPhotoCollection(File dir) {
        this.dir = dir;
    }
    
    public int get_count() {
        SortedList<File> list = get_children_photos();
        
        return (list != null) ? list.size : 0;
    }
    
    public PhotoBase? get_first_photo() {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        return DirectPhoto.fetch(list.get(0));
    }
    
    public PhotoBase? get_last_photo() {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        return DirectPhoto.fetch(list.get(list.size - 1));
    }
    
    public PhotoBase? get_next_photo(PhotoBase current) {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        int index = list.index_of(((DirectPhoto) current).get_file());
        if (index < 0)
            return null;
        
        index++;
        if (index >= list.size)
            index = 0;
        
        return DirectPhoto.fetch(list.get(index));
    }
    
    public PhotoBase? get_previous_photo(PhotoBase current) {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        int index = list.index_of(((DirectPhoto) current).get_file());
        if (index < 0)
            return null;
        
        index--;
        if (index < 0)
            index = list.size - 1;

        return DirectPhoto.fetch(list.get(index));
    }
    
    private SortedList<File>? get_children_photos() {
        try {
            FileEnumerator enumerator = dir.enumerate_children(FILE_ATTRIBUTE_STANDARD_NAME,
                FileQueryInfoFlags.NONE, null);
            
            SortedList<File> list = new SortedList<File>(file_comparator);
            
            FileInfo file_info = null;
            while ((file_info = enumerator.next_file(null)) != null) {
                File file = dir.get_child(file_info.get_name());
                
                if (!TransformablePhoto.is_file_supported(file))
                    continue;
                
                list.add(file);
            }

            return list;
        } catch (Error err) {
            message("Unable to enumerate children in %s: %s", dir.get_path(), err.message);
            
            return null;
        }
    }
}

public class DirectPhotoPage : EditingHostPage {
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, on_file },
        { "Save", Gtk.STOCK_SAVE, "_Save", "<Ctrl>S", "Save photo", on_save },
        { "SaveAs", Gtk.STOCK_SAVE_AS, "Save _As...", "<Ctrl><Shift>S", "Save photo with a different name", 
            on_save_as },
        
        { "PhotoMenu", null, "_Photo", null, null, on_photo_menu },
        { "PrevPhoto", Gtk.STOCK_GO_BACK, "_Previous Photo", null, "Previous Photo", on_previous_photo },
        { "NextPhoto", Gtk.STOCK_GO_FORWARD, "_Next Photo", null, "Next Photo", on_next_photo },
        { "RotateClockwise", Resources.CLOCKWISE, "Rotate _Right", "<Ctrl>R", "Rotate the selected photos clockwise",
            on_rotate_clockwise },
        { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE, "Rotate _Left", "<Ctrl><Shift>R", 
            "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", Resources.MIRROR, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", 
            on_mirror },
        { "Revert", Gtk.STOCK_REVERT_TO_SAVED, "Re_vert to Original", null, "Revert to the original photo", 
            on_revert },

        { "ViewMenu", null, "_View", null, null, null },
        
        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    private Gtk.Menu context_menu;
    private File initial_file;
    private File current_save_dir;
    private bool drop_if_dirty = false;

    public DirectPhotoPage(File file) {
        base(file.get_basename());
        
        if (!check_editable_file(file)) {
            Posix.exit(1);
            
            return;
        }
        
        initial_file = file;
        current_save_dir = file.get_parent();
        
        init_ui("direct.ui", "/DirectMenuBar", "DirectActionGroup", ACTIONS);

        context_menu = (Gtk.Menu) ui.get_widget("/DirectContextMenu");
    }
    
    private static bool check_editable_file(File file) {
        bool ok = false;
        if (!FileUtils.test(file.get_path(), FileTest.EXISTS))
            AppWindow.error_message("%s does not exist.".printf(file.get_path()));
        else if (!FileUtils.test(file.get_path(), FileTest.IS_REGULAR))
            AppWindow.error_message("%s is not a file.".printf(file.get_path()));
        else if (!TransformablePhoto.is_file_supported(file))
            AppWindow.error_message("%s does not support the file format of\n%s.".printf(
                Resources.APP_TITLE, file.get_path()));
        else
            ok = true;
        
        return ok;
    }
    
    private override void realize() {
        if (base.realize != null)
            base.realize();
        
        DirectPhoto photo = DirectPhoto.fetch(initial_file);
        if (photo == null) {
            // dead in the water
            Posix.exit(1);
        }

        display(new DirectPhotoCollection(initial_file.get_parent()), photo);
        initial_file = null;
    }
    
    public File get_current_file() {
        return get_photo().get_file();
    }
    
    private override bool on_context_menu(Gdk.EventButton event) {
        if (get_photo() == null)
            return false;
        
        set_item_sensitive("/DirectContextMenu/ContextRevert", get_photo().has_transformations());

        context_menu.popup(null, null, null, event.button, event.time);
        
        return true;
    }
    
    private bool check_ok_to_close_photo(TransformablePhoto photo) {
        if (!photo.has_transformations())
            return true;
        
        if (drop_if_dirty) {
            // need to remove transformations, or else they stick around in memory (reappearing
            // if the user opens the file again)
            photo.remove_all_transformations();
            
            return true;
        }
        
        bool ok = AppWindow.yes_no_question("Lose changes to %s?".printf(photo.get_name()));
        if (ok)
            photo.remove_all_transformations();
        
        return ok;
    }
    
    public bool check_quit() {
        return check_ok_to_close_photo(get_photo());
    }
    
    private override void check_replace_photo(TransformablePhoto old_photo, TransformablePhoto new_photo,
        out bool ok) {
        ok = check_ok_to_close_photo(old_photo);
    }
    
    private void on_file() {
        set_item_sensitive("/DirectMenuBar/FileMenu/Save", get_photo().has_transformations());
    }
    
    private void save(File dest, int scale, ScaleConstraint constraint, Jpeg.Quality quality) {
        try {
            get_photo().export(dest, scale, constraint, quality);
        } catch (Error err) {
            AppWindow.error_message("Error while saving photo: %s".printf(err.message));
            
            return;
        }
        
        // switch to that file ... if saving on top of the original file, this will re-import the
        // photo into the in-memory database, which is key because its stored transformations no
        // longer match the backing photo
        display(new DirectPhotoCollection(dest.get_parent()), DirectPhoto.fetch(dest, true));
    }
    
    private void on_save() {
        if (!get_photo().has_transformations())
            return;
        
        // save full-sized version right on top of the current file
        save(get_photo().get_file(), 0, ScaleConstraint.ORIGINAL, Jpeg.Quality.HIGH);
    }
    
    private void on_save_as() {
        ExportDialog export_dialog = new ExportDialog("Save As", ExportDialog.DEFAULT_SCALE,
            ScaleConstraint.ORIGINAL, ExportDialog.DEFAULT_QUALITY);
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        if (!export_dialog.execute(out scale, out constraint, out quality))
            return;

        Gtk.FileChooserDialog save_as_dialog = new Gtk.FileChooserDialog("Save As", 
            AppWindow.get_instance(), Gtk.FileChooserAction.SAVE, Gtk.STOCK_CANCEL, 
            Gtk.ResponseType.CANCEL, Gtk.STOCK_OK, Gtk.ResponseType.OK);
        save_as_dialog.set_select_multiple(false);
        save_as_dialog.set_filename(get_photo().get_file().get_path());
        save_as_dialog.set_current_folder(current_save_dir.get_path());
        save_as_dialog.set_do_overwrite_confirmation(true);
        
        int response = save_as_dialog.run();
        if (response == Gtk.ResponseType.OK) {
            // flag to prevent asking user about losing changes to the old file (since they'll be
            // loaded right into the new one)
            drop_if_dirty = true;
            save(File.new_for_uri(save_as_dialog.get_uri()), scale, constraint, quality);
            drop_if_dirty = false;

            current_save_dir = File.new_for_path(save_as_dialog.get_current_folder());
        }
        
        save_as_dialog.destroy();
    }
    
    private void on_photo_menu() {
        bool multiple = (get_controller() != null) ? get_controller().get_count() > 1 : false;
        bool revert_possible = (get_photo() != null) ? get_photo().has_transformations() : false;

        set_item_sensitive("/DirectMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/NextPhoto", multiple);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/Revert", revert_possible);
    }
}
