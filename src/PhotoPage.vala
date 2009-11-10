/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class EditingHostPage : SinglePhotoPage {
    public const int TOOL_WINDOW_SEPARATOR = 8;
    public const int PIXBUF_CACHE_COUNT = 5;
    public const int ORIGINAL_PIXBUF_CACHE_COUNT = 5;
    public const int KEY_REPEAT_INTERVAL_MSEC = 150;
    
    private class EditingHostCanvas : PhotoCanvas {
        private EditingHostPage host_page;
        
        public EditingHostCanvas(EditingHostPage host_page) {
            base(host_page.get_container(), host_page.canvas.window, host_page.get_photo(),
                host_page.canvas_gc, host_page.get_drawable(), host_page.get_scaled_pixbuf(),
                host_page.get_scaled_pixbuf_position());
            
            this.host_page = host_page;
        }
        
        public override void repaint() {
            host_page.repaint();
        }
    }
    
    private SourceCollection sources;
    private bool use_readahead;
    private ViewCollection controller = null;
    private Gdk.Pixbuf swapped = null;
    private bool pixbuf_dirty = true;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToggleToolButton crop_button = null;
    private Gtk.ToggleToolButton redeye_button = null;
    private Gtk.ToggleToolButton adjust_button = null;
    private Gtk.ToolButton enhance_button = null;
    private Gtk.ToolButton prev_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
    private Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
    private EditingTool current_tool = null;
    private Gtk.ToggleToolButton current_editing_toggle = null;
    private Gdk.Pixbuf cancel_editing_pixbuf = null;
    private File drag_file = null;
    private uint32 last_nav_key = 0;
    private bool photo_missing = false;
    private bool drag_event_failed = true;
    private PixbufCache cache = null;
    private PixbufCache original_cache = null;
    
    // This signals when the current photo has changed (that is, a new photo is being viewed, not
    // that the current photo has been altered).
    public signal void photo_changed(TransformablePhoto? old_photo, TransformablePhoto new_photo);

    public EditingHostPage(SourceCollection sources, string name, bool use_readahead) {
        base(name);
        
        this.sources = sources;
        this.use_readahead = use_readahead;
        
        // when photo is altered need to update it here
        sources.item_altered += on_photo_altered;
        
        // set up page's toolbar (used by AppWindow for layout and FullscreenWindow as a popup)
        //
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.clicked += on_rotate_clockwise;
        rotate_button.is_important = true;
        toolbar.insert(rotate_button, -1);
        
        // crop tool
        crop_button = new Gtk.ToggleToolButton.from_stock(Resources.CROP);
        crop_button.set_label(_("Crop"));
        crop_button.set_tooltip_text(_("Crop the photo's size"));
        crop_button.toggled += on_crop_toggled;
        crop_button.is_important = true;
        toolbar.insert(crop_button, -1);

        // redeye reduction tool
        redeye_button = new Gtk.ToggleToolButton.from_stock(Resources.REDEYE);
        redeye_button.set_label(_("Red-eye"));
        redeye_button.set_tooltip_text(_("Reduce or eliminate any red-eye effects in the photo"));
        redeye_button.toggled += on_redeye_toggled;
        redeye_button.is_important = true;
        toolbar.insert(redeye_button, -1);
        
        // adjust tool
        adjust_button = new Gtk.ToggleToolButton.from_stock(Resources.ADJUST);
        adjust_button.set_label(_("Adjust"));
        adjust_button.set_tooltip_text(_("Adjust the photo's color and tone"));
        adjust_button.toggled += on_adjust_toggled;
        adjust_button.is_important = true;
        toolbar.insert(adjust_button, -1);

        // ehance tool
        enhance_button = new Gtk.ToolButton.from_stock(Resources.ENHANCE);
        enhance_button.set_label(Resources.ENHANCE_LABEL);
        enhance_button.set_tooltip_text(Resources.ENHANCE_TOOLTIP);
        enhance_button.clicked += on_enhance;
        enhance_button.is_important = true;
        toolbar.insert(enhance_button, -1);

        // separator to force next/prev buttons to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        toolbar.insert(separator, -1);
        
        // previous button
        prev_button.set_tooltip_text(_("Previous photo"));
        prev_button.clicked += on_previous_photo;
        toolbar.insert(prev_button, -1);
        
        // next button
        next_button.set_tooltip_text(_("Next photo"));
        next_button.clicked += on_next_photo;
        toolbar.insert(next_button, -1);
    }
    
    ~EditingHostPage() {
        sources.item_altered -= on_photo_altered;
    }
    
    public override void set_container(Gtk.Window container) {
        base.set_container(container);
        
        // DnD only available in full-window view
        if (!(container is FullscreenWindow))
            enable_drag_source(Gdk.DragAction.COPY);
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override ViewCollection get_controller() {
        return controller;
    }
    
    public bool has_photo() {
        // ViewCollection should have either zero or one photos in it at all times
        assert(get_view().get_count() <= 1);
        
        return get_view().get_count() == 1;
    }
    
    public TransformablePhoto? get_photo() {
        // use the photo stored in our ViewCollection ... should either be zero or one in the
        // collection at all times
        assert(get_view().get_count() <= 1);
        
        if (get_view().get_count() == 0)
            return null;
        
        PhotoView photo_view = (PhotoView) get_view().get_at(0);
        
        return (TransformablePhoto) photo_view.get_source();
    }
    
    private void set_photo(TransformablePhoto photo) {
        // clear out the collection and use this as its sole member
        get_view().clear();
        get_view().add(new PhotoView(photo));
    }
    
    public override void switched_to() {
        base.switched_to();
        
        rebuild_caches("switched_to");
        
        // check if the photo altered while away
        if (has_photo() && pixbuf_dirty)
            replace_photo(controller, get_photo());
    }
    
    public override void switching_from() {
        base.switching_from();

        deactivate_tool();
    }
    
    public override void switching_to_fullscreen() {
        base.switching_to_fullscreen();

        deactivate_tool();
    }
    
    private void rebuild_caches(string caller) {
        Scaling scaling = get_canvas_scaling();
        
        // only rebuild if not the same scaling
        if (cache != null && cache.get_scaling().equals(scaling))
            return;
        
        debug("Rebuild cache: %s (%s)", caller, scaling.to_string());
        
        // if dropping an old cache, clear the signal handler so currently executing requests
        // don't complete and cancel anything queued up
        if (cache != null) {
            cache.fetched -= on_pixbuf_fetched;
            cache.cancel_all();
        }
        
        cache = new PixbufCache(sources, PixbufCache.PhotoType.REGULAR, scaling, 
            use_readahead ? PIXBUF_CACHE_COUNT : 1);
        cache.fetched += on_pixbuf_fetched;
        
        original_cache = new PixbufCache(sources, PixbufCache.PhotoType.ORIGINAL, scaling,
            use_readahead ? ORIGINAL_PIXBUF_CACHE_COUNT : 1);
        
        if (has_photo())
            prefetch_neighbors(controller, get_photo());
    }
    
    private void on_pixbuf_fetched(TransformablePhoto photo, Gdk.Pixbuf? pixbuf, Error? err) {
        if (!photo.equals(get_photo()))
            return;
        
        if (pixbuf != null) {
            set_pixbuf(pixbuf);
            pixbuf_dirty = false;
        } else if (err != null) {
            set_photo_missing(true);
        }
    }
    
    private bool get_immediate_neighbors(ViewCollection controller, TransformablePhoto photo, 
        out TransformablePhoto? next, out TransformablePhoto? prev) {
        DataView photo_view = controller.get_view_for_source(photo);
        if (photo_view == null)
            return false;
        
        DataView? next_view = controller.get_next(photo_view);
        next = (next_view != null) ? (TransformablePhoto) next_view.get_source() : null;
        
        DataView? prev_view = controller.get_previous(photo_view);
        prev = (prev_view != null) ? (TransformablePhoto) prev_view.get_source() : null;

        return true;
    }
    
    private Gee.Set<TransformablePhoto> get_extended_neighbors(ViewCollection controller,
        TransformablePhoto photo) {
        // build list of new neighbors
        Gee.Set<TransformablePhoto> neighbors = new Gee.HashSet<TransformablePhoto>();
        
        // immediate neighbors
        TransformablePhoto next, prev;
        if (!get_immediate_neighbors(controller, photo, out next, out prev))
            return neighbors;
        
        // add next and its distant neighbor
        if (next != null) {
            neighbors.add(next);
            
            TransformablePhoto next_next, next_prev;
            get_immediate_neighbors(controller, next, out next_next, out next_prev);
            
            // only add next-next because next-prev is this photo
            if (next_next != null)
                neighbors.add(next_next);
        }
        
        // add previous and its distant neighbor
        if (prev != null) {
            neighbors.add(prev);
            
            TransformablePhoto next_prev, prev_prev;
            get_immediate_neighbors(controller, prev, out next_prev, out prev_prev);
            
            // only add prev-prev because next-prev is this photo
            if (prev_prev != null)
                neighbors.add(prev_prev);
        }
        
        // finally, in a small collection a neighbor could be this photo itself, so exclude it
        neighbors.remove(photo);
        
        return neighbors;
    }
    
    private void prefetch_neighbors(ViewCollection controller, TransformablePhoto photo) {
        if (!use_readahead)
            return;
        
        TransformablePhoto next, prev;
        if (!get_immediate_neighbors(controller, photo, out next, out prev))
            return;
        
        // prefetch the immediate neighbors and their outer neighbors, for plenty of readahead
        foreach (TransformablePhoto neighbor in get_extended_neighbors(controller, photo)) {
            BackgroundJob.JobPriority priority = BackgroundJob.JobPriority.NORMAL;
            if (neighbor.equals(next) || neighbor.equals(prev))
                priority = BackgroundJob.JobPriority.HIGH;
            
            cache.prefetch(neighbor, priority);
            
            if (neighbor.has_transformations())
                original_cache.prefetch(neighbor, BackgroundJob.JobPriority.LOWEST);
        }
    }
    
    // Cancels prefetches of old neighbors, but does not cancel them if they are the new
    // neighbors
    private void cancel_prefetch_neighbors(ViewCollection old_controller, TransformablePhoto old_photo,
        ViewCollection new_controller, TransformablePhoto new_photo) {
        if (!use_readahead)
            return;
        
        Gee.Set<TransformablePhoto> old_neighbors = get_extended_neighbors(old_controller,
            old_photo);
        Gee.Set<TransformablePhoto> new_neighbors = get_extended_neighbors(new_controller,
            new_photo);
        
        foreach (TransformablePhoto old_neighbor in old_neighbors) {
            // cancel prefetch and drop from cache if old neighbor is not part of the new
            // neighborhood
            if (!new_neighbors.contains(old_neighbor) && !new_photo.equals(old_neighbor)) {
                cache.drop(old_neighbor);
                original_cache.drop(old_neighbor);
            }
        }
        
        // do same for old photo
        if (!new_neighbors.contains(old_photo) && !new_photo.equals(old_photo)) {
            cache.drop(old_photo);
            original_cache.drop(old_photo);
        }
    }
    
    protected void display(ViewCollection controller, TransformablePhoto photo) {
        assert(controller.get_view_for_source(photo) != null);
        
        replace_photo(controller, photo);
    }

    protected void set_missing_photo_sensitivities(bool sensitivity) {
        rotate_button.sensitive = sensitivity;
        crop_button.sensitive = sensitivity;
        redeye_button.sensitive = sensitivity;
        adjust_button.sensitive = sensitivity;
        enhance_button.sensitive = sensitivity;

        deactivate_tool();

        set_item_sensitive("/PhotoMenuBar/PhotoMenu/RotateClockwise", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/RotateCounterclockwise", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Mirror", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Enhance", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Revert", sensitivity);

        set_item_sensitive("/PhotoContextMenu/ContextRotateClockwise", sensitivity);
        set_item_sensitive("/PhotoContextMenu/ContextRotateCounterclockwise", sensitivity);
        set_item_sensitive("/PhotoContextMenu/ContextMirror", sensitivity);
        set_item_sensitive("/PhotoContextMenu/ContextEnhance", sensitivity);
        set_item_sensitive("/PhotoContextMenu/ContextRevert", sensitivity);
    }

    private void draw_message(string message) {
        // draw the message in the center of the window
        Pango.Layout pango_layout = create_pango_layout(message);
        int text_width, text_height;
        pango_layout.get_pixel_size(out text_width, out text_height);

        int x = allocation.width - text_width;
        x = (x > 0) ? x / 2 : 0;
        
        int y = allocation.height - text_height;
        y = (y > 0) ? y / 2 : 0;

        Gdk.draw_layout(get_drawable(), text_gc, x, y, pango_layout);
    }

    protected void set_photo_missing(bool missing) {
        if (photo_missing == missing) {
            return;
        }

        photo_missing = missing;

        set_missing_photo_sensitivities(!photo_missing);

        if (photo_missing) {
            try {
                Gdk.Pixbuf pixbuf = get_photo().get_preview_pixbuf(get_canvas_scaling());

                pixbuf = pixbuf.composite_color_simple(pixbuf.get_width(), pixbuf.get_height(),
                    Gdk.InterpType.NEAREST, 100, 2, 0, 0);

                set_pixbuf(pixbuf);
            } catch (GLib.Error err) {
                warning("%s", err.message);
            }
        }
    }

    protected virtual bool confirm_replace_photo(TransformablePhoto? old_photo, TransformablePhoto new_photo) {
        return true;
    }

    protected void replace_photo(ViewCollection new_controller, TransformablePhoto new_photo) {
        ViewCollection old_controller = this.controller;
        controller = new_controller;
        
        // if it's the same Photo object, the scaling hasn't changed, and the photo's file
        // has not gone missing or re-appeared, there's nothing to do otherwise,
        // just need to reload the image for the proper scaling
        if (new_photo.equals(get_photo()) && !pixbuf_dirty && !photo_missing)
            return;

        // only check if okay to replace if there's something to replace and someone's concerned
        if (has_photo() && !new_photo.equals(get_photo()) && confirm_replace_photo != null) {
            if (!confirm_replace_photo(get_photo(), new_photo))
                return;
        }

        deactivate_tool();
        
        // swap out new photo and old photo and process change
        TransformablePhoto old_photo = get_photo();
        set_photo(new_photo);
        
        set_page_name(new_photo.get_name());

        // clear out the swap buffer
        swapped = null;

        // reset flags
        set_photo_missing(false);
        pixbuf_dirty = true;

        update_ui();

        if (!new_photo.equals(old_photo))
            photo_changed(old_photo, new_photo);
        
        // it's possible for this to be called prior to the page being realized, however, the
        // underlying canvas has a scaling, so use that
        rebuild_caches("replace_photo");
        
        if (old_photo != null)
            cancel_prefetch_neighbors(old_controller, old_photo, new_controller, new_photo);
        
        quick_update_pixbuf();
        
        prefetch_neighbors(new_controller, new_photo);
        
        // quick_update_pixbuf takes care of loading photo, need to prefetch the original (which
        // is not considered a neighbor)
        if (new_photo.has_transformations())
            original_cache.prefetch(new_photo, BackgroundJob.JobPriority.LOW);
    }
    
    private void quick_update_pixbuf() {
        Gdk.Pixbuf pixbuf = cache.get_ready_pixbuf(get_photo());
        if (pixbuf != null) {
            set_pixbuf(pixbuf);
            pixbuf_dirty = false;
            
            return;
        }
        
        Scaling scaling = get_canvas_scaling();
        
        debug("Using progressive load for %s (%s)", get_photo().to_string(), scaling.to_string());
        
        // throw a resized large thumbnail up to get an image on the screen quickly,
        // and when ready decode and display the full image
        try {
            set_pixbuf(get_photo().get_preview_pixbuf(scaling));
        } catch (Error err) {
            warning("%s", err.message);
        }
        
        cache.prefetch(get_photo(), BackgroundJob.JobPriority.HIGHEST);
        
        // although final pixbuf not in place, it's on its way, so set this to clean so later calls
        // don't reload again
        pixbuf_dirty = false;
    }
    
    private bool update_pixbuf() {
#if MEASURE_PIPELINE
        Timer timer = new Timer();
#endif
        Gdk.Pixbuf pixbuf = null;
        
        try {
            if (current_tool != null)
                pixbuf = current_tool.get_display_pixbuf(get_canvas_scaling(), get_photo());
            
            if (pixbuf == null)
                pixbuf = cache.fetch(get_photo());
        } catch (Error err) {
            warning("%s", err.message);
            set_photo_missing(true);
        }
        
        if (!photo_missing) {
            set_pixbuf(pixbuf);
            pixbuf_dirty = false;
        }
        
#if MEASURE_PIPELINE
        debug("UPDATE_PIXBUF: total=%lf", timer.elapsed());
#endif
        
        return false;
    }
    
    private override void on_resize(Gdk.Rectangle rect) {
        base.on_resize(rect);

        track_tool_window();
    }
    
    private override void on_resize_finished(Gdk.Rectangle rect) {
        // because we've loaded SinglePhotoPage with an image scaled to window size, as the window
        // is resized it scales that, which pixellates, especially scaling upward.  Once the window
        // resize is complete, we get a fresh image for the new window's size
        rebuild_caches("on_resize_finished");
        pixbuf_dirty = true;
        
        update_pixbuf();
    }
    
    private void update_ui() {
        bool multiple = controller.get_count() > 1;

        prev_button.sensitive = multiple;
        next_button.sensitive = multiple;
    }
    
    private override bool on_shift_pressed(Gdk.EventKey event) {
        // show quick compare of original only if no tool is in use, the original pixbuf is handy
        if (current_tool == null) {
            Gdk.Pixbuf original = original_cache.get_ready_pixbuf(get_photo());
            if (original != null) {
                // store what's currently displayed only for the duration of the shift pressing
                swapped = get_unscaled_pixbuf();
                
                set_pixbuf(original);
            }
        }
        
        return base.on_shift_pressed(event);
    }
    
    private override bool on_shift_released(Gdk.EventKey event) {
        if (current_tool == null && swapped != null) {
            set_pixbuf(swapped);
            
            // only store swapped once; it'll be set the next on_shift_pressed
            swapped = null;
        }
        
        return base.on_shift_pressed(event);
    }

    private void activate_tool(EditingTool tool) {
        // deactivate current tool ... current implementation is one tool at a time.  In the future,
        // tools may be allowed to be executing at the same time.
        deactivate_tool();
        
        // save current pixbuf to use if user cancels operation
        cancel_editing_pixbuf = get_unscaled_pixbuf();
        
        // see if the tool wants a different pixbuf displayed
        Gdk.Pixbuf unscaled;
        try {
            unscaled = tool.get_display_pixbuf(get_canvas_scaling(), get_photo());
        } catch (Error err) {
            warning("%s", err.message);
            set_photo_missing(true);

            // untoggle tool button (usually done after deactivate, but tool never deactivated)
            assert(current_editing_toggle != null);
            current_editing_toggle.active = false;
           
            return;
        }

        if (unscaled != null)
            set_pixbuf(unscaled);
        
        // create the PhotoCanvas object for a two-way interface to the tool
        PhotoCanvas photo_canvas = new EditingHostCanvas(this);

        // hook tool into event system and activate it
        current_tool = tool;
        current_tool.activate(photo_canvas);
        
        // if the tool has an auxilliary window, move it properly on the screen
        place_tool_window();

        // repaint entire view, with the tool now hooked in
        repaint();
    }
    
    private void deactivate_tool(Gdk.Pixbuf? new_pixbuf = null, bool needs_improvement = false) {
        if (current_tool == null)
            return;

        EditingTool tool = current_tool;
        current_tool = null;
        
        // deactivate with the tool taken out of the hooks
        tool.deactivate();
        tool = null;
        
        // only null the toggle when the tool is completely deactivated; that is, deactive the tool
        // before updating the UI
        current_editing_toggle = null;

        // display the (possibly) new photo
        Gdk.Pixbuf replacement = null;
        if (new_pixbuf != null) {
            replacement = new_pixbuf;
        } else if (cancel_editing_pixbuf != null) {
            replacement = cancel_editing_pixbuf;
            needs_improvement = false;
        } else {
            needs_improvement = true;
        }
        
        if (replacement != null)
            set_pixbuf(replacement);
        cancel_editing_pixbuf = null;
        
        // if this is a rough pixbuf, schedule an improvement
        if (needs_improvement) {
            pixbuf_dirty = true;
            Idle.add(update_pixbuf);
        }
    }
    
    private override void drag_begin(Gdk.DragContext context) {
        if (!has_photo() || photo_missing)
            return;
        
        // drag_data_get may be called multiple times within a drag as different applications
        // query for target type and information ... to prevent a lot of file generation, do all
        // the work up front
        File file = null;
        drag_event_failed = false;
        try {
            file = get_photo().generate_exportable();
        } catch (Error err) {
            drag_event_failed = true;
            file = null;
            warning("%s", err.message);
        }
        
        // set up icon for drag-and-drop
        try {
            Gdk.Pixbuf icon = get_photo().get_preview_pixbuf(Scaling.for_best_fit(AppWindow.DND_ICON_SCALE));
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

        if (drag_event_failed) {
            Idle.add(report_drag_failed);
        }
    }

    private bool report_drag_failed() {
        AppWindow.error_message(_("Photo source file is missing."));
        drag_event_failed = false;

        return false;
    }
    
    private override bool source_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        debug("Drag failed: %d", (int) drag_result);
        
        drag_file = null;
        get_photo().export_failed();
        
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
    
    private void on_photo_altered(DataObject object) {
        TransformablePhoto p = object as TransformablePhoto;

        // only interested in current photo
        if (p == null || !p.equals(get_photo()))
            return;
        
        pixbuf_dirty = true;
        
        // if transformed, want to prefetch the original pixbuf for this photo, but after the
        // signal is completed as PixbufCache may remove it in this round of fired signals
        if (get_photo().has_transformations())
            Idle.add(on_fetch_original);
        
        update_ui();
    }
    
    private bool on_fetch_original() {
        if (has_photo())
            original_cache.prefetch(get_photo(), BackgroundJob.JobPriority.LOW);
        
        return false;
    }
    
    private override bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        if (current_tool != null)
            current_tool.on_motion(x, y, mask);
            
        return false;
    }
    
    private virtual bool on_context_menu(Gdk.EventButton event) {
        return false;
    }
    
    private void track_tool_window() {
        // if editing tool window is present and the user hasn't touched it, it moves with the window
        if (current_tool != null) {
            EditingToolWindow tool_window = current_tool.get_tool_window();
            if (tool_window != null && !tool_window.has_user_moved())
                place_tool_window();
        }
    }
    
    private override void on_move(Gdk.Rectangle rect) {
        track_tool_window();
        
        base.on_move(rect);
    }
    
    private override bool key_press_event(Gdk.EventKey event) {
        // editing tool gets first crack at the keypress
        if (current_tool != null) {
            if (current_tool.on_keypress(event))
                return true;
        }
        
        // if the user holds the arrow keys down, we will receive a steady stream of key press
        // events for an operation that isn't designed for a rapid succession of output ... 
        // we staunch the supply of new photos to under a quarter second (#533)
        bool nav_ok = (event.time - last_nav_key) > KEY_REPEAT_INTERVAL_MSEC;
        
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "Left":
            case "KP_Left":
                if (nav_ok) {
                    on_previous_photo();
                    last_nav_key = event.time;
                }
            break;
            
            case "Right":
            case "KP_Right":
                if (nav_ok) {
                    on_next_photo();
                    last_nav_key = event.time;
                }
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
        // only purpose here is to inform editing tool of change and drop the cancelled
        // pixbuf, which is now sized incorrectly
        if (current_tool != null && reason != SinglePhotoPage.UpdateReason.QUALITY_IMPROVEMENT) {
            current_tool.canvas.resized_pixbuf(old_dim, pixbuf, get_scaled_pixbuf_position());
            cancel_editing_pixbuf = null;
        }
    }
    
    protected override void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        if (current_tool != null)
            current_tool.paint(gc, drawable);
        else
            base.paint(gc, drawable);

        if (photo_missing && has_photo())
            draw_message(_("Photo source file missing: %s").printf(get_photo().get_file().get_path()));
    }

    private void rotate(Rotation rotation) {
        deactivate_tool();
        
        if (!has_photo())
            return;
        
        get_photo().rotate(rotation);
        pixbuf_dirty = true;
        
        quick_update_pixbuf();
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
        
        if (!has_photo())
            return;
        
        get_photo().remove_all_transformations();

        set_photo_missing(false);
        pixbuf_dirty = true;
        
        quick_update_pixbuf();
    }

    private override bool on_ctrl_pressed(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.COUNTERCLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CCW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CCW_TOOLTIP);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.clicked -= on_rotate_counterclockwise;
        rotate_button.clicked += on_rotate_clockwise;
        
        return false;
    }
    
    private void on_tool_button_toggled(Gtk.ToggleToolButton toggle, EditingTool.Factory factory) {
        // if the button is an activate, deactivate any current tool running; if the button is
        // a deactivate, deactivate the current tool and exit
        bool deactivating_only = (!toggle.active && current_editing_toggle == toggle);
        deactivate_tool();
        
        if (deactivating_only)
            return;
        
        current_editing_toggle = toggle;
        
        // create the tool, hook its signals, and activate
        EditingTool tool = factory();
        tool.activated += on_tool_activated;
        tool.deactivated += on_tool_deactivated;
        tool.applied += on_tool_applied;
        tool.cancelled += on_tool_cancelled;
        tool.aborted += on_tool_aborted;
        
        activate_tool(tool);
    }
    
    private void on_tool_activated() {
        assert(current_editing_toggle != null);
        current_editing_toggle.active = true;
    }
    
    private void on_tool_deactivated() {
        assert(current_editing_toggle != null);
        current_editing_toggle.active = false;
    }
    
    private void on_tool_applied(Gdk.Pixbuf? new_pixbuf, bool needs_improvement) {
        deactivate_tool(new_pixbuf, needs_improvement);
    }
    
    private void on_tool_cancelled() {
        deactivate_tool();
    }

    private void on_tool_aborted() {
        deactivate_tool();
        set_photo_missing(true);
    }
    
    private void on_crop_toggled() {
        on_tool_button_toggled(crop_button, CropTool.factory);
    }

    private void on_redeye_toggled() {
        on_tool_button_toggled(redeye_button, RedeyeTool.factory);
    }
    
    private void on_adjust_toggled() {
        on_tool_button_toggled(adjust_button, AdjustTool.factory);
    }
    
    public void on_enhance() {
        // because running multiple tools at once is not currently supported, deactivate any current
        // tool; however, there is a special case of running enhancement while the AdjustTool is
        // open, so allow for that
        if (!(current_tool is AdjustTool))
            deactivate_tool();
        
        if (!has_photo())
            return;
        
        AppWindow.get_instance().set_busy_cursor();

#if MEASURE_ENHANCE
        Timer overall_timer = new Timer();
#endif
        /* if the current tool is the adjust tool, then don't commit to the database --
           just set the slider values in the adjust dialog and force it to repaint
           the canvas */
        if (current_tool is AdjustTool) {
            PixelTransformation[] transformations = get_photo().get_enhance_transformations();
            if (transformations != null) {
                ((AdjustTool) current_tool).set_adjustments(transformations);
            } else {
                set_photo_missing(true);
            }
        } else {
            /* if the current tool isn't the adjust tool then commit the changes
               to the database */
            if (get_photo().enhance()) {
                pixbuf_dirty = true;
                
                update_pixbuf();
            } else {
                set_photo_missing(true);
            }
        }

#if MEASURE_ENHANCE
        overall_timer.stop();
        debug("Auto-Enhance overall time: %f sec", overall_timer.elapsed());
#endif

        AppWindow.get_instance().set_normal_cursor();
    }

    private void place_tool_window() {
        if (current_tool == null)
            return;
            
        EditingToolWindow tool_window = current_tool.get_tool_window();
        if (tool_window == null)
            return;

        // do this so window size is properly allocated, but window not shown
        tool_window.show_all();
        tool_window.hide();

        Gtk.Allocation tool_alloc = tool_window.allocation;

        if (get_container() == AppWindow.get_instance()) {
            // Normal: position crop tool window centered on viewport/canvas at the bottom,
            // straddling the canvas and the toolbar
            int rx, ry;
            get_container().window.get_root_origin(out rx, out ry);
            
            int cx, cy, cwidth, cheight;
            cx = viewport.allocation.x;
            cy = viewport.allocation.y;
            cwidth = viewport.allocation.width;
            cheight = viewport.allocation.height;
            
            tool_window.move(rx + cx + (cwidth / 2) - (tool_alloc.width / 2), ry + cy + cheight);
        } else {
            assert(get_container() is FullscreenWindow);
            
            // Fullscreen: position crop tool window centered on screen at the bottom, just above the
            // toolbar
            Gtk.Allocation toolbar_alloc = toolbar.allocation;
            
            Gdk.Screen screen = get_container().get_screen();

            int x = screen.get_width();
            int y = screen.get_height() - toolbar_alloc.height -
                    tool_alloc.height - TOOL_WINDOW_SEPARATOR;
        
            // put larger adjust tool off to the side
            if (current_tool is AdjustTool) {
                x = x * 3 / 4;
            } else {
                x = (x - tool_alloc.width) / 2;
            }            

            tool_window.move(x, y);
        }

        // we need both show & present so we get keyboard focus
        tool_window.show();
        tool_window.present();
    }
    
    public void on_next_photo() {
        deactivate_tool();
        
        if (!has_photo())
            return;
        
        DataView current = controller.get_view_for_source(get_photo());
        assert(current != null);
        
        DataView? next = controller.get_next(current);
        if (next == null)
            return;

        TransformablePhoto next_photo = next.get_source() as TransformablePhoto;
        if (next_photo != null)
            replace_photo(controller, next_photo);
    }
    
    public void on_previous_photo() {
        deactivate_tool();
        
        if (!has_photo())
            return;
        
        DataView current = controller.get_view_for_source(get_photo());
        assert(current != null);
        
        DataView? previous = controller.get_previous(current);
        if (previous == null)
            return;
        
        TransformablePhoto previous_photo = previous.get_source() as TransformablePhoto;
        if (previous_photo != null)
            replace_photo(controller, previous_photo);
    }
}

public class LibraryPhotoPage : EditingHostPage {
    private Gtk.Menu context_menu;
    private CollectionPage return_page = null;

    public LibraryPhotoPage() {
        base(LibraryPhoto.global, "Photo", true);

        init_ui("photo.ui", "/PhotoMenuBar", "PhotoActionGroup", create_actions());

        context_menu = (Gtk.Menu) ui.get_widget("/PhotoContextMenu");
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, null };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry export = { "Export", Gtk.STOCK_SAVE_AS, TRANSLATABLE, "<Ctrl><Shift>E",
            TRANSLATABLE, on_export };
        export.label = _("_Export Photos...");
        export.tooltip = _("Export photo to disk");
        actions += export;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, null };
        view.label = _("_View");
        actions += view;
        
        Gtk.ActionEntry photo = { "PhotoMenu", null, TRANSLATABLE, null, null, on_photo_menu };
        photo.label = _("_Photo");
        actions += photo;

        Gtk.ActionEntry prev = { "PrevPhoto", Gtk.STOCK_GO_BACK, TRANSLATABLE, null,
            TRANSLATABLE, on_previous_photo };
        prev.label = _("_Previous Photo");
        prev.tooltip = _("Previous Photo");
        actions += prev;

        Gtk.ActionEntry next = { "NextPhoto", Gtk.STOCK_GO_FORWARD, TRANSLATABLE, null,
            TRANSLATABLE, on_next_photo };
        next.label = _("_Next Photo");
        next.tooltip = _("Next Photo");
        actions += next;

        Gtk.ActionEntry rotate_right = { "RotateClockwise", Resources.CLOCKWISE, TRANSLATABLE,
            "<Ctrl>R", TRANSLATABLE, on_rotate_clockwise };
        rotate_right.label = _("Rotate _Right");
        rotate_right.tooltip = _("Rotate the selected photos clockwise");
        actions += rotate_right;

        Gtk.ActionEntry rotate_left = { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE,
            TRANSLATABLE, "<Ctrl><Shift>R", TRANSLATABLE, on_rotate_counterclockwise };
        rotate_left.label = _("Rotate _Left");
        rotate_left.tooltip = _("Rotate the selected photos counterclockwise");
        actions += rotate_left;

        Gtk.ActionEntry mirror = { "Mirror", Resources.MIRROR, TRANSLATABLE, null,
            TRANSLATABLE, on_mirror };
        mirror.label = _("_Mirror");
        mirror.tooltip = _("Make mirror images of the selected photos");
        actions += mirror;

        Gtk.ActionEntry enhance = { "Enhance", Resources.ENHANCE, TRANSLATABLE, "<Ctrl>E",
            TRANSLATABLE, on_enhance };
        enhance.label = Resources.ENHANCE_LABEL;
        enhance.tooltip = Resources.ENHANCE_TOOLTIP;
        actions += enhance;

        Gtk.ActionEntry revert = { "Revert", Gtk.STOCK_REVERT_TO_SAVED, TRANSLATABLE,
            null, TRANSLATABLE, on_revert };
        revert.label = _("Re_vert to Original");
        revert.tooltip = _("Revert to the original photo");
        actions += revert;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        return actions;
    }
    
    public void display_for_collection(CollectionPage return_page, Thumbnail thumbnail) {
        this.return_page = return_page;
        
        display(return_page.get_view(), thumbnail.get_photo());
    }
    
    public CollectionPage get_controller_page() {
        return return_page;
    }
    
    private override bool key_press_event(Gdk.EventKey event) {
        if (base.key_press_event != null && base.key_press_event(event) == true)
            return true;
        
        if (Gdk.keyval_name(event.keyval) == "Escape") {
            return_to_collection();
            
            return true;
        }
        
        return false;
    }
    
    private override bool on_double_click(Gdk.EventButton event) {
        if (!(get_container() is FullscreenWindow)) {
            return_to_collection();
            
            return true;
        }
        
        return false;
    }

    private override bool on_context_menu(Gdk.EventButton event) {
        if (!has_photo())
            return false;

        set_item_sensitive("/PhotoContextMenu/ContextRevert", get_photo().has_transformations());

        context_menu.popup(null, null, null, event.button, event.time);
        
        return true;
    }

    private void return_to_collection() {
        LibraryWindow.get_app().switch_to_page(return_page);
    }
    
    private void on_export() {
        if (!has_photo())
            return;
        
        ExportDialog export_dialog = new ExportDialog(_("Export Photo"));
        
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
            AppWindow.error_message(_("Unable to export %s: %s").printf(save_as.get_path(), err.message));
        }
    }
    
    private void on_photo_menu() {
        bool multiple = (get_controller() != null) ? get_controller().get_count() > 1 : false;
        bool revert_possible = has_photo() ? get_photo().has_transformations() : false;
            
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/NextPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Revert", revert_possible);
    }
}

// TODO: This implementation of a ViewCollection is solely for use in direct editing mode, and will 
// not satisfy all the requirements of a checkerboard-style file browser without additional work.
//
// TODO: With the new SourceCollection/ViewCollection model, we can start monitoring the cwd for
// files and generating DirectPhotoSource stubs to represent each possible image file in the
// directory, only importing them into the system when selected by the user.
private class DirectViewCollection : ViewCollection {
    private static FileComparator file_comparator = new FileComparator();
    
    private class DirectViewManager : ViewManager {
        public override DataView create_view(DataSource source) {
            return new DataView(source);
        }
    }
    
    private File dir;
    
    public DirectViewCollection(File dir) {
        this.dir = dir;
        
        monitor_source_collection(DirectPhoto.global, new DirectViewManager());
    }
    
    public override int get_count() {
        SortedList<File> list = get_children_photos();
        
        return (list != null) ? list.size : 0;
    }
    
    public override DataView? get_first() {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        DirectPhoto photo = DirectPhoto.global.fetch(list.get(0));
        
        return (photo != null) ? get_view_for_source(photo) : null;
    }
    
    public override DataView? get_last() {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        DirectPhoto photo = DirectPhoto.global.fetch(list.get(list.size - 1));
        
        return (photo != null) ? get_view_for_source(photo) : null;
    }
    
    public override DataView? get_next(DataView current) {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        int index = list.index_of(((DirectPhoto) current.get_source()).get_file());
        if (index < 0)
            return null;
        
        index++;
        if (index >= list.size)
            index = 0;
        
        DirectPhoto photo = DirectPhoto.global.fetch(list.get(index));
        
        return (photo != null) ? get_view_for_source(photo) : null;
    }
    
    public override DataView? get_previous(DataView current) {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        int index = list.index_of(((DirectPhoto) current.get_source()).get_file());
        if (index < 0)
            return null;
        
        index--;
        if (index < 0)
            index = list.size - 1;
        
        DirectPhoto photo = DirectPhoto.global.fetch(list.get(index));
        
        return (photo != null) ? get_view_for_source(photo) : null;
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
    private Gtk.Menu context_menu;
    private File initial_file;
    private File current_save_dir;
    private bool drop_if_dirty = false;

    public DirectPhotoPage(File file) {
        base(DirectPhoto.global, file.get_basename(), false);
        
        if (!check_editable_file(file)) {
            Posix.exit(1);
            
            return;
        }
        
        initial_file = file;
        current_save_dir = file.get_parent();
        
        init_ui("direct.ui", "/DirectMenuBar", "DirectActionGroup", create_actions());

        context_menu = (Gtk.Menu) ui.get_widget("/DirectContextMenu");
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, on_file };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry save = { "Save", Gtk.STOCK_SAVE, TRANSLATABLE, "<Ctrl>S", TRANSLATABLE,
            on_save };
        save.label = _("_Save");
        save.tooltip = _("Save photo");
        actions += save;

        Gtk.ActionEntry save_as = { "SaveAs", Gtk.STOCK_SAVE_AS, TRANSLATABLE,
            "<Ctrl><Shift>S", TRANSLATABLE, on_save_as };
        save_as.label = _("Save _As...");
        save_as.tooltip = _("Save photo with a different name");
        actions += save_as;

        Gtk.ActionEntry photo = { "PhotoMenu", null, "", null, null,
            on_photo_menu };
        photo.label = _("_Photo");
        actions += photo;

        Gtk.ActionEntry prev = { "PrevPhoto", Gtk.STOCK_GO_BACK, TRANSLATABLE, null,
            TRANSLATABLE, on_previous_photo };
        prev.label = _("_Previous Photo");
        prev.tooltip = _("Previous Photo");
        actions += prev;

        Gtk.ActionEntry next = { "NextPhoto", Gtk.STOCK_GO_FORWARD, TRANSLATABLE, null,
            TRANSLATABLE, on_next_photo };
        next.label = _("_Next Photo");
        next.tooltip = _("Next Photo");
        actions += next;

        Gtk.ActionEntry rotate_right = { "RotateClockwise", Resources.CLOCKWISE,
            TRANSLATABLE, "<Ctrl>R", TRANSLATABLE, on_rotate_clockwise };
        rotate_right.label = _("Rotate _Right");
        rotate_right.tooltip = _("Rotate the selected photos clockwise");
        actions += rotate_right;

        Gtk.ActionEntry rotate_left = { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE,
            TRANSLATABLE, "<Ctrl><Shift>R", TRANSLATABLE, on_rotate_counterclockwise };
        rotate_left.label = _("Rotate _Left");
        rotate_left.tooltip = _("Rotate the selected photos counterclockwise");
        actions += rotate_left;

        Gtk.ActionEntry mirror = { "Mirror", Resources.MIRROR, TRANSLATABLE, null,
            TRANSLATABLE, on_mirror };
        mirror.label = _("_Mirror");
        mirror.tooltip = _("Make mirror images of the selected photos");
        actions += mirror;

        Gtk.ActionEntry revert = { "Revert", Gtk.STOCK_REVERT_TO_SAVED, TRANSLATABLE,
            null, TRANSLATABLE, on_revert };
        revert.label = _("Re_vert to Original");
        revert.tooltip = _("Revert to the original photo");
        actions += revert;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, null };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        return actions;
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
        
        DirectPhoto photo = DirectPhoto.global.fetch(initial_file);
        if (photo == null) {
            // dead in the water
            Posix.exit(1);
        }

        display(new DirectViewCollection(initial_file.get_parent()), photo);
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
        
        bool ok = AppWindow.yes_no_question(_("Lose changes to %s?").printf(photo.get_name()));
        if (ok)
            photo.remove_all_transformations();
        
        return ok;
    }
    
    public bool check_quit() {
        return check_ok_to_close_photo(get_photo());
    }
    
    private override bool confirm_replace_photo(TransformablePhoto? old_photo, TransformablePhoto new_photo) {
        return (old_photo != null) ? check_ok_to_close_photo(old_photo) : true;
    }
    
    private void on_file() {
        set_item_sensitive("/DirectMenuBar/FileMenu/Save", get_photo().has_transformations());
    }
    
    private void save(File dest, int scale, ScaleConstraint constraint, Jpeg.Quality quality) {
        try {
            get_photo().export(dest, scale, constraint, quality);
        } catch (Error err) {
            AppWindow.error_message(_("Error while saving photo: %s").printf(err.message));
            
            return;
        }
        
        DirectPhoto photo = DirectPhoto.global.fetch(dest, true);
        if (photo == null) {
            // dead in the water
            Posix.exit(1);
        }
        
        // switch to that file ... if saving on top of the original file, this will re-import the
        // photo into the in-memory database, which is key because its stored transformations no
        // longer match the backing photo
        display(new DirectViewCollection(dest.get_parent()), photo);
    }
    
    private void on_save() {
        if (!get_photo().has_transformations())
            return;
        
        // save full-sized version right on top of the current file
        save(get_photo().get_file(), 0, ScaleConstraint.ORIGINAL, Jpeg.Quality.HIGH);
    }
    
    private void on_save_as() {
        ExportDialog export_dialog = new ExportDialog(_("Save As"), ExportDialog.DEFAULT_SCALE,
            ScaleConstraint.ORIGINAL, ExportDialog.DEFAULT_QUALITY);
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        if (!export_dialog.execute(out scale, out constraint, out quality))
            return;

        Gtk.FileChooserDialog save_as_dialog = new Gtk.FileChooserDialog(_("Save As"), 
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
        bool revert_possible = has_photo() ? get_photo().has_transformations() : false;

        set_item_sensitive("/DirectMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/NextPhoto", multiple);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/Revert", revert_possible);
    }
}
