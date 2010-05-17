/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class EditingHostPage : SinglePhotoPage {
    public const int TOOL_WINDOW_SEPARATOR = 8;
    public const int PIXBUF_CACHE_COUNT = 5;
    public const int ORIGINAL_PIXBUF_CACHE_COUNT = 5;
    public const int KEY_REPEAT_INTERVAL_MSEC = 200;
    
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
    private ViewCollection controller = null;
    private Gdk.Pixbuf swapped = null;
    private bool pixbuf_dirty = true;
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToggleToolButton crop_button = null;
    private Gtk.ToggleToolButton redeye_button = null;
    private Gtk.ToggleToolButton adjust_button = null;
    private Gtk.ToolButton enhance_button = null;
    private Gtk.HScale zoom_slider = null;
    private Gtk.ToolButton prev_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
    private Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
    private EditingTool current_tool = null;
    private Gtk.ToggleToolButton current_editing_toggle = null;
    private Gdk.Pixbuf cancel_editing_pixbuf = null;
    private uint32 last_nav_key = 0;
    private bool photo_missing = false;
    private PixbufCache cache = null;
    private PixbufCache original_cache = null;
    private PixbufCache zoom_cache = null;
    private PhotoDragAndDropHandler dnd_handler = null;
    private Gdk.Pixbuf? zoom_optimized_pixbuf = null;
    private bool enable_interactive_zoom_refresh = false;
    private Gdk.Point zoom_pan_start_point;
    private bool is_pan_in_progress = false;
    private double saved_slider_val = 0.0;

    public EditingHostPage(SourceCollection sources, string name) {
        base(name, false);
        
        this.sources = sources;
        
        // when photo is altered need to update it here
        sources.item_altered += on_photo_altered;
        
        // set up page's toolbar (used by AppWindow for layout and FullscreenWindow as a popup)
        Gtk.Toolbar toolbar = get_toolbar();
        
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.clicked += on_rotate_clockwise;
        rotate_button.is_important = true;
        toolbar.insert(rotate_button, -1);
        
        // crop tool
        crop_button = new Gtk.ToggleToolButton.from_stock(Resources.CROP);
        crop_button.set_label(Resources.CROP_LABEL);
        crop_button.set_tooltip_text(Resources.CROP_TOOLTIP);
        crop_button.toggled += on_crop_toggled;
        crop_button.is_important = true;
        toolbar.insert(crop_button, -1);

        // redeye reduction tool
        redeye_button = new Gtk.ToggleToolButton.from_stock(Resources.REDEYE);
        redeye_button.set_label(Resources.RED_EYE_LABEL);
        redeye_button.set_tooltip_text(Resources.RED_EYE_TOOLTIP);
        redeye_button.toggled += on_redeye_toggled;
        redeye_button.is_important = true;
        toolbar.insert(redeye_button, -1);
        
        // adjust tool
        adjust_button = new Gtk.ToggleToolButton.from_stock(Resources.ADJUST);
        adjust_button.set_label(Resources.ADJUST_LABEL);
        adjust_button.set_tooltip_text(Resources.ADJUST_TOOLTIP);
        adjust_button.toggled += on_adjust_toggled;
        adjust_button.is_important = true;
        toolbar.insert(adjust_button, -1);

        // enhance tool
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
        
        // zoom slider
        zoom_slider = new Gtk.HScale(new Gtk.Adjustment(0.0, 0.0, 1.1, 0.1, 0.1, 0.1));
        zoom_slider.set_draw_value(false);
        Gtk.ToolItem zoom_slider_wrapper = new Gtk.ToolItem();
        zoom_slider_wrapper.add(zoom_slider);
        toolbar.insert(zoom_slider_wrapper, -1);
        zoom_slider.set_size_request(120, -1);
        zoom_slider.value_changed += on_zoom_slider_value_changed;
        zoom_slider.button_press_event += on_zoom_slider_drag_begin;
        zoom_slider.button_release_event += on_zoom_slider_drag_end;
        zoom_slider.key_press_event += on_zoom_slider_key_press;
        
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

    private void on_zoom_slider_value_changed() {
        ZoomState new_zoom_state = ZoomState.rescale(get_zoom_state(), zoom_slider.get_value());

        if (enable_interactive_zoom_refresh) {
            on_interactive_zoom(new_zoom_state);
            
            if (new_zoom_state.is_default())
                set_zoom_state(new_zoom_state);
        } else {
            if (new_zoom_state.is_default()) {
                cancel_zoom();
            } else {
                set_zoom_state(new_zoom_state);
                fetch_zoom_optimized_pixbuf(new_zoom_state);
            }
            repaint();
        }
    }

    private bool on_zoom_slider_drag_begin(Gdk.EventButton event) {
        enable_interactive_zoom_refresh = true;

        return false;
    }

    private bool on_zoom_slider_drag_end(Gdk.EventButton event) {
        enable_interactive_zoom_refresh = false;

        ZoomState zoom_state = ZoomState.rescale(get_zoom_state(), zoom_slider.get_value());
        fetch_zoom_optimized_pixbuf(zoom_state);
        set_zoom_state(zoom_state);

        return false;
    }
    
    private void fetch_zoom_optimized_pixbuf(ZoomState zoom_state) {
        if (zoom_cache != null)
            zoom_cache.fetched -= on_zoomed_photo_fetched;

        int fetch_width = zoom_state.get_zoomed_width().clamp(0,
            get_photo().get_dimensions().width);
        int fetch_height = zoom_state.get_zoomed_height().clamp(0,
            get_photo().get_dimensions().height);
        int fetch_major_axis = (fetch_width > fetch_height) ? fetch_width : fetch_height;
        Scaling fetch_scaling = Scaling.for_best_fit(fetch_major_axis, false);

        zoom_cache = new PixbufCache(sources, PixbufCache.PhotoType.REGULAR, fetch_scaling,
            PIXBUF_CACHE_COUNT);
        zoom_cache.prefetch(get_photo());
        zoom_cache.fetched += on_zoomed_photo_fetched;
    }

    private void on_zoomed_photo_fetched(TransformablePhoto photo, Gdk.Pixbuf? pixbuf, Error? err) {
        zoom_cache.fetched -= on_zoomed_photo_fetched;
        zoom_optimized_pixbuf = pixbuf;

        repaint();
    }

    protected void snap_zoom_to_min() {
        zoom_slider.set_value(0.0);       
    }

    protected void snap_zoom_to_max() {
        zoom_slider.set_value(1.0);
    }

    protected void snap_zoom_to_isomorphic() {
        ZoomState iso_state = ZoomState.rescale_to_isomorphic(get_zoom_state());
        zoom_slider.set_value(iso_state.get_interpolation_factor());
    }

    protected virtual bool on_zoom_slider_key_press(Gdk.EventKey event) {
        switch (Gdk.keyval_name(event.keyval)) {
            case "0":
                snap_zoom_to_min();
                return true;
            
            case "1":
                snap_zoom_to_isomorphic();
                return true;

            case "2":
                snap_zoom_to_max();
                return true;
        }

        return false;
    }

    protected virtual void on_increase_size() {
        double interp = get_zoom_state().get_interpolation_factor() + 0.1;
        if (interp < 0.03)
            interp = 0.0;
        else if (interp > 0.97)
            interp = 1.0;
        zoom_slider.set_value(interp);
    }
    
    protected virtual void on_decrease_size() {
        double interp = get_zoom_state().get_interpolation_factor() - 0.1;
        if (interp < 0.03)
            interp = 0.0;
        else if (interp > 0.97)
            interp = 1.0;
        zoom_slider.set_value(interp);
    }

    protected override Gdk.Pixbuf? get_zoom_optimized_pixbuf(ZoomState zoom_state) {
        return zoom_optimized_pixbuf;
    }

    protected override void save_zoom_state() {
        base.save_zoom_state();
        saved_slider_val = zoom_slider.get_value();
    }

    protected override bool on_mousewheel_up(Gdk.EventScroll event) {
        on_increase_size();

        return false;
    }
    
    protected override bool on_mousewheel_down(Gdk.EventScroll event) {
        on_decrease_size();
        
        return false;
    }

    protected override void restore_zoom_state() {
        base.restore_zoom_state();

        zoom_slider.value_changed -= on_zoom_slider_value_changed;
        zoom_slider.set_value(saved_slider_val);
        zoom_slider.value_changed += on_zoom_slider_value_changed;
        
        fetch_zoom_optimized_pixbuf(get_zoom_state());
    }

    public override bool is_zoom_supported() {
        return true;
    }

    public override void set_container(Gtk.Window container) {
        base.set_container(container);
        
        // DnD not available in fullscreen mode
        if (!(container is FullscreenWindow))
            dnd_handler = new PhotoDragAndDropHandler(this);
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
        zoom_slider.value_changed -= on_zoom_slider_value_changed;
        zoom_slider.set_value(0.0);
        zoom_slider.value_changed += on_zoom_slider_value_changed;

        // clear out the collection and use this as its sole member, selecting it so it's seen
        // as the item to be operated upon by various observers (including drag-and-drop)
        get_view().clear();
        get_view().add(new PhotoView(photo));
        get_view().select_all();
        
        // also select it in the controller's collection, so when the user returns to that view
        // it's apparent which one was being viewed here
        if (controller != null) {
            controller.unselect_all();
            Marker marker = controller.mark(controller.get_view_for_source(photo));
            controller.select_marked(marker);
        }
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
        
        cancel_zoom();
        is_pan_in_progress = false;
        
        deactivate_tool();
    }
    
    public override void switching_to_fullscreen() {
        base.switching_to_fullscreen();
        
        deactivate_tool();
        
        cancel_zoom();
        is_pan_in_progress = false;
        
        if (controller != null)
            controller.items_selected += on_selection_changed;
    }
    
    public override void returning_from_fullscreen() {
        base.returning_from_fullscreen();
                
        repaint();
        
        if (controller != null)
            controller.items_selected -= on_selection_changed;
    }
    
    private void on_selection_changed(Gee.Iterable<DataView> selected) {
        foreach (DataView view in selected) {
            replace_photo(controller, (TransformablePhoto) view.get_source());
            break;
        }
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
        
        cache = new PixbufCache(sources, PixbufCache.PhotoType.REGULAR, scaling, PIXBUF_CACHE_COUNT);
        cache.fetched += on_pixbuf_fetched;
        
        original_cache = new PixbufCache(sources, PixbufCache.PhotoType.ORIGINAL, scaling, 
            ORIGINAL_PIXBUF_CACHE_COUNT);
        
        if (has_photo())
            prefetch_neighbors(controller, get_photo());
    }
    
    private void on_pixbuf_fetched(TransformablePhoto photo, Gdk.Pixbuf? pixbuf, Error? err) {
        // if not of the current photo, nothing more to do
        if (!photo.equals(get_photo()))
            return;
        
        if (pixbuf != null) {
            // if no tool, use the pixbuf directly, otherwise, let the tool decide what should be
            // displayed
            Dimensions max_dim = photo.get_dimensions();
            if (current_tool != null) {
                try {
                    Gdk.Pixbuf? tool_pixbuf = current_tool.get_display_pixbuf(get_canvas_scaling(),
                        photo, out max_dim);
                    if (tool_pixbuf != null)
                        pixbuf = tool_pixbuf;
                } catch(Error err) {
                    warning("Unable to fetch tool pixbuf for %s: %s", photo.to_string(), err.message);
                    set_photo_missing(true);
                    
                    return;
                }
            }
            
            set_pixbuf(pixbuf, max_dim);
            pixbuf_dirty = false;
        } else if (err != null) {
            set_photo_missing(true);
        }
    }
    
    private void prefetch_neighbors(ViewCollection controller, TransformablePhoto photo) {
        cache.prefetch(photo, BackgroundJob.JobPriority.HIGHEST);

        if (photo.has_transformations())
            original_cache.prefetch(photo, BackgroundJob.JobPriority.LOW);

        DataSource next_source, prev_source;
        if (!controller.get_immediate_neighbors(photo, out next_source, out prev_source))
            return;
        
        TransformablePhoto next = (TransformablePhoto) next_source;
        TransformablePhoto prev = (TransformablePhoto) prev_source;
        
        // prefetch the immediate neighbors and their outer neighbors, for plenty of readahead
        foreach (DataSource neighbor_source in controller.get_extended_neighbors(photo)) {
            TransformablePhoto neighbor = (TransformablePhoto) neighbor_source;
            
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
        Gee.Set<TransformablePhoto> old_neighbors = (Gee.Set<TransformablePhoto>)
            old_controller.get_extended_neighbors(old_photo);
        Gee.Set<TransformablePhoto> new_neighbors = (Gee.Set<TransformablePhoto>)
            new_controller.get_extended_neighbors(new_photo);
        
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

    protected virtual void set_missing_photo_sensitivities(bool sensitivity) {
        rotate_button.sensitive = sensitivity;
        crop_button.sensitive = sensitivity;
        redeye_button.sensitive = sensitivity;
        adjust_button.sensitive = sensitivity;
        enhance_button.sensitive = sensitivity;

        deactivate_tool();
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

                set_pixbuf(pixbuf, get_photo().get_dimensions());
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

        // it's possible for this to be called prior to the page being realized, however, the
        // underlying canvas has a scaling, so use that
        rebuild_caches("replace_photo");
        
        if (old_photo != null)
            cancel_prefetch_neighbors(old_controller, old_photo, new_controller, new_photo);

        cancel_zoom();

        quick_update_pixbuf();
        
        prefetch_neighbors(new_controller, new_photo);
    }
    
    protected override void cancel_zoom() {
        base.cancel_zoom();

        zoom_slider.value_changed -= on_zoom_slider_value_changed;
        zoom_slider.set_value(0.0);
        zoom_slider.value_changed += on_zoom_slider_value_changed;

        set_zoom_state(ZoomState(get_photo().get_dimensions(), get_drawable_dim(), 0.0));
        zoom_optimized_pixbuf = null;
    }
    
    private void quick_update_pixbuf() {
        Gdk.Pixbuf pixbuf = cache.get_ready_pixbuf(get_photo());
        if (pixbuf != null) {
            set_pixbuf(pixbuf, get_photo().get_dimensions());
            pixbuf_dirty = false;
            
            return;
        }
        
        Scaling scaling = get_canvas_scaling();
        
        debug("Using progressive load for %s (%s)", get_photo().to_string(), scaling.to_string());
        
        // throw a resized large thumbnail up to get an image on the screen quickly,
        // and when ready decode and display the full image
        try {
            set_pixbuf(get_photo().get_preview_pixbuf(scaling), get_photo().get_dimensions());
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
        Dimensions max_dim = get_photo().get_dimensions();
        
        try {
            if (current_tool != null)
                pixbuf = current_tool.get_display_pixbuf(get_canvas_scaling(), get_photo(), out max_dim);
        } catch (Error err) {
            warning("%s", err.message);
            set_photo_missing(true);
        }
        
        if (!photo_missing) {
            // if no pixbuf, see if it's waiting in the cache
            if (pixbuf == null)
                pixbuf = cache.get_ready_pixbuf(get_photo());
            
            // if still no pixbuf, background fetch and let the signal handler update the display
            if (pixbuf == null)
                cache.prefetch(get_photo());
        }
        
        if (!photo_missing && pixbuf != null) {
            set_pixbuf(pixbuf, max_dim);
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
        
        TransformablePhoto photo = get_photo();
        Scaling scaling = get_canvas_scaling();
        
        rotate_button.sensitive = photo != null ? is_rotate_available(photo) : false;
        crop_button.sensitive = photo != null ? CropTool.is_available(photo, scaling) : false;
        redeye_button.sensitive = photo != null ? RedeyeTool.is_available(photo, scaling) : false;
        adjust_button.sensitive = photo != null ? AdjustTool.is_available(photo, scaling) : false;
        enhance_button.sensitive = photo != null ? is_enhance_available(photo) : false;
    }
    
    private override bool on_shift_pressed(Gdk.EventKey? event) {
        // show quick compare of original only if no tool is in use, the original pixbuf is handy
        if (current_tool == null && !ctrl_pressed && !alt_pressed) {
            swap_in_original();
        }
        
        return base.on_shift_pressed(event);
    }
    
    private override bool on_shift_released(Gdk.EventKey? event) {
        if (current_tool == null)
            swap_out_original();
        
        return base.on_shift_released(event);
    }

    private override bool on_alt_pressed(Gdk.EventKey? event) {
        if (current_tool == null)
            swap_out_original();
        
        return base.on_alt_pressed(event);
    }
    
    private override bool on_alt_released(Gdk.EventKey? event) {
        if (current_tool == null && shift_pressed && !ctrl_pressed)
            swap_in_original();
        
        return base.on_alt_released(event);
    }

    private void swap_in_original() {
        Gdk.Pixbuf original = original_cache.get_ready_pixbuf(get_photo());
        if (original != null) {
            // store what's currently displayed only for the duration of the shift pressing
            swapped = get_unscaled_pixbuf();
            
            set_pixbuf(original, get_photo().get_original_dimensions());
        }
    }

    private void swap_out_original() {
        if (swapped != null) {
            set_pixbuf(swapped, get_photo().get_dimensions());
            
            // only store swapped once; it'll be set the next on_shift_pressed
            swapped = null;
        }
    }

    private void activate_tool(EditingTool tool) {
        // cancel any zoom -- we don't currently allow tools to be used when an image is zoomed,
        // though we may at some point in the future.
        save_zoom_state();
        cancel_zoom();

        // deactivate current tool ... current implementation is one tool at a time.  In the future,
        // tools may be allowed to be executing at the same time.
        deactivate_tool();
        
        // save current pixbuf to use if user cancels operation
        cancel_editing_pixbuf = get_unscaled_pixbuf();
        
        // see if the tool wants a different pixbuf displayed and what its max dimensions should be
        Gdk.Pixbuf unscaled;
        Dimensions max_dim = get_photo().get_dimensions();
        try {
            unscaled = tool.get_display_pixbuf(get_canvas_scaling(), get_photo(), out max_dim);
        } catch (Error err) {
            warning("%s", err.message);
            set_photo_missing(true);

            // untoggle tool button (usually done after deactivate, but tool never deactivated)
            assert(current_editing_toggle != null);
            current_editing_toggle.active = false;
           
            return;
        }

        if (unscaled != null)
            set_pixbuf(unscaled, max_dim);
        
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
    
    private void deactivate_tool(Command? command = null, Gdk.Pixbuf? new_pixbuf = null, 
        Dimensions new_max_dim = Dimensions(), bool needs_improvement = false) {
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
            new_max_dim = Dimensions.for_pixbuf(replacement);
            needs_improvement = false;
        } else {
            needs_improvement = true;
        }
        
        if (replacement != null)
            set_pixbuf(replacement, new_max_dim);
        cancel_editing_pixbuf = null;
        
        // if this is a rough pixbuf, schedule an improvement
        if (needs_improvement) {
            pixbuf_dirty = true;
            Idle.add(update_pixbuf);
        }
        
        // execute the tool's command
        if (command != null)
            get_command_manager().execute(command);
    }
    
    // This virtual method is called only when the user double-clicks on the page and no tool
    // is active
    protected virtual bool on_double_click(Gdk.EventButton event) {
        return false;
    }
    
    // Return true to block the DnD handler from activating a drag
    protected override bool on_left_click(Gdk.EventButton event) {
        // report double-click if no tool is active, otherwise all double-clicks are eaten
        if (event.type == Gdk.EventType.2BUTTON_PRESS)
            return (current_tool == null) ? on_double_click(event) : false;
        
        int x = (int) event.x;
        int y = (int) event.y;

        // if no editing tool, then determine whether we should start a pan operation over the
        // zoomed photo or fall through to the default DnD behavior if we're not zoomed
        if ((current_tool == null) && (zoom_slider.get_value() != 0.0)) {
            zoom_pan_start_point.x = (int) event.x;
            zoom_pan_start_point.y = (int) event.y;
            is_pan_in_progress = true;

            return true;
        }

        // default behavior when photo isn't zoomed -- return false to start DnD operation
        if (current_tool == null) {
            return false;
        }

        // only concerned about mouse-downs on the pixbuf ... return true prevents DnD when the
        // user drags outside the displayed photo
        if (!is_inside_pixbuf(x, y))
            return true;

        current_tool.on_left_click(x, y);
        
        // block DnD handlers if tool is enabled
        return true;
    }
    
    protected override bool on_left_released(Gdk.EventButton event) {
        if (is_pan_in_progress) {
            Gdk.Point viewport_center = get_zoom_state().get_viewport_center();
            int delta_x = ((int) event.x) - zoom_pan_start_point.x;
            int delta_y = ((int) event.y) - zoom_pan_start_point.y;
            viewport_center.x -= delta_x;
            viewport_center.y -= delta_y;

            ZoomState zoom_state = ZoomState.pan(get_zoom_state(), viewport_center);

            set_zoom_state(zoom_state);

            repaint();

            is_pan_in_progress = false;
        }

        // report all releases, as it's possible the user click and dragged from inside the
        // pixbuf to the gutters
        if (current_tool != null)
            current_tool.on_left_released((int) event.x, (int) event.y);
        
        return false;
    }
    
    private override bool on_right_click(Gdk.EventButton event) {
        return on_context_buttonpress(event);
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
        if (current_tool != null) {
            current_tool.on_motion(x, y, mask);
            return false;
        }
        
        if (get_zoom_state().is_default()) {
            canvas.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
        } else {
            canvas.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.FLEUR));
        }
        
        if (is_pan_in_progress) {
            int delta_x = ((int) event.x) - zoom_pan_start_point.x;
            int delta_y = ((int) event.y) - zoom_pan_start_point.y;

            Gdk.Point viewport_center = get_zoom_state().get_viewport_center();
            viewport_center.x -= delta_x;
            viewport_center.y -= delta_y;

            ZoomState zoom_state = ZoomState.pan(get_zoom_state(), viewport_center);

            on_interactive_pan(zoom_state);
        }
            
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

        // if the user pressed the "0", "1" or "2" keys then handle the event as if were
        // directed at the zoom slider ("0", "1" and "2" are hotkeys that jump to preset
        // zoom levels
        if (on_zoom_slider_key_press(event))
            return true;
        
        // if the user holds the arrow keys down, we will receive a steady stream of key press
        // events for an operation that isn't designed for a rapid succession of output ... 
        // we staunch the supply of new photos to under a quarter second (#533)
        bool nav_ok = (event.time - last_nav_key) > KEY_REPEAT_INTERVAL_MSEC;
        
        bool handled = true;
        
        switch (Gdk.keyval_name(event.keyval)) {
            case "Left":
            case "KP_Left":
            case "BackSpace":
                if (nav_ok) {
                    on_previous_photo();
                    last_nav_key = event.time;
                }
            break;
            
            case "Right":
            case "KP_Right":
            case "space":
                if (nav_ok) {
                    on_next_photo();
                    last_nav_key = event.time;
                }
            break;

            // this block is only here to prevent base from moving focus to toolbar
            case "Down":
            case "KP_Down":
                ;
            break;
            
            case "equal":
            case "plus":
            case "KP_Add":
                on_increase_size();
            break;
            
            // underscore is the keysym generated by SHIFT-[minus sign] -- this means zoom out
            case "minus":
            case "underscore":
            case "KP_Subtract":
                on_decrease_size();
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
    
    public bool is_rotate_available(TransformablePhoto photo) {
        return true;
    }

    private void rotate(Rotation rotation, string name, string description) {
        cancel_zoom();

        deactivate_tool();
        
        if (!has_photo())
            return;
        
        RotateSingleCommand command = new RotateSingleCommand(get_photo(), rotation, name,
            description);
        get_command_manager().execute(command);
    }
    
    public void on_rotate_clockwise() {
        rotate(Rotation.CLOCKWISE, Resources.ROTATE_CW_FULL_LABEL, Resources.ROTATE_CW_TOOLTIP);
    }
    
    public void on_rotate_counterclockwise() {
        rotate(Rotation.COUNTERCLOCKWISE, Resources.ROTATE_CCW_FULL_LABEL, Resources.ROTATE_CCW_TOOLTIP);
    }
    
    public void on_mirror() {
        rotate(Rotation.MIRROR, Resources.MIRROR_LABEL, Resources.MIRROR_TOOLTIP);
    }
    
    public void on_flip() {
        rotate(Rotation.UPSIDE_DOWN, Resources.FLIP_LABEL, Resources.FLIP_TOOLTIP);
    }
    
    public void on_revert() {
        deactivate_tool();
        
        if (!has_photo())
            return;

        cancel_zoom();

        set_photo_missing(false);
        
        RevertSingleCommand command = new RevertSingleCommand(get_photo());
        get_command_manager().execute(command);
    }

    public void on_rename() {
        LibraryPhoto item;
        if (get_photo() is LibraryPhoto)
            item = get_photo() as LibraryPhoto;
        else
            return;
        
        PhotoRenameDialog rename_dialog = new PhotoRenameDialog(item.get_title());
        string? new_name = rename_dialog.execute();
        if (new_name == null)
            return;
        
        RenamePhotoCommand command = new RenamePhotoCommand(item, new_name);
        get_command_manager().execute(command);
    }

    public void on_adjust_date_time() {
        if (!has_photo())
            return;

        AdjustDateTimeDialog dialog = new AdjustDateTimeDialog(get_photo(), 1, !(this is DirectPhotoPage));

        int64 time_shift;
        bool keep_relativity, modify_originals;
        if (dialog.execute(out time_shift, out keep_relativity, out modify_originals)) {
            get_view().get_selected();
            
            AdjustDateTimePhotoCommand command = new AdjustDateTimePhotoCommand(get_photo(),
                time_shift, modify_originals);
            get_command_manager().execute(command);
        }
    }

#if !NO_SET_BACKGROUND
    public void on_set_background() {
        if (!has_photo())
            return;
        
        set_desktop_background(get_photo());
    }
#endif

    private override bool on_ctrl_pressed(Gdk.EventKey? event) {
        rotate_button.set_stock_id(Resources.COUNTERCLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CCW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CCW_TOOLTIP);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        if (current_tool == null)
            swap_out_original();

        return base.on_ctrl_pressed(event);
    }
    
    private override bool on_ctrl_released(Gdk.EventKey? event) {
        rotate_button.set_stock_id(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.clicked -= on_rotate_counterclockwise;
        rotate_button.clicked += on_rotate_clockwise;

        if (current_tool == null && shift_pressed && !alt_pressed)
            swap_in_original();
        
        return base.on_ctrl_released(event);
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
        zoom_slider.set_sensitive(false);
        current_editing_toggle.active = true;
    }
    
    private void on_tool_deactivated() {
        assert(current_editing_toggle != null);
        zoom_slider.set_sensitive(true);
        current_editing_toggle.active = false;
    }
    
    private void on_tool_applied(Command? command, Gdk.Pixbuf? new_pixbuf, Dimensions new_max_dim,
        bool needs_improvement) {
        deactivate_tool(command, new_pixbuf, new_max_dim, needs_improvement);
    }
    
    private void on_tool_cancelled() {
        deactivate_tool();

        restore_zoom_state();
        repaint();
    }

    private void on_tool_aborted() {
        deactivate_tool();
        set_photo_missing(true);
    }

    protected void toggle_crop() {
        crop_button.set_active(!crop_button.get_active());
    }

    protected void toggle_redeye() {
        redeye_button.set_active(!redeye_button.get_active());
    }
    
    protected void toggle_adjust() {
        adjust_button.set_active(!adjust_button.get_active());
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
    
    public bool is_enhance_available(TransformablePhoto photo) {
        return true;
    }
    
    public void on_enhance() {
        // because running multiple tools at once is not currently supported, deactivate any current
        // tool; however, there is a special case of running enhancement while the AdjustTool is
        // open, so allow for that
        if (!(current_tool is AdjustTool)) {
            deactivate_tool();
            
            cancel_zoom();
        }
        
        if (!has_photo())
            return;
        
        AdjustTool adjust_tool = current_tool as AdjustTool;
        if (adjust_tool != null) {
            adjust_tool.enhance();
            
            return;
        }
        
        EnhanceSingleCommand command = new EnhanceSingleCommand(get_photo());
        get_command_manager().execute(command);
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
            Gtk.Allocation toolbar_alloc = get_toolbar().allocation;
            
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
        if (current == null)
            return;
        
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
        if (current == null)
            return;
        
        DataView? previous = controller.get_previous(current);
        if (previous == null)
            return;
        
        TransformablePhoto previous_photo = previous.get_source() as TransformablePhoto;
        if (previous_photo != null)
            replace_photo(controller, previous_photo);
    }

    public bool has_current_tool() {
        return (current_tool != null);
    }
}

//
// LibraryPhotoPage
//

public class LibraryPhotoPage : EditingHostPage {
    private Gtk.Menu context_menu;
    private CollectionPage return_page = null;

    public const int TRINKET_SCALE = 20;
    public const int TRINKET_PADDING = 1;

    private bool return_to_collection_on_release = false;
    
    public LibraryPhotoPage() {
        base(LibraryPhoto.global, "Photo");

        init_ui("photo.ui", "/PhotoMenuBar", "PhotoActionGroup", create_actions());
        
#if !NO_PRINTING
        ui.add_ui(ui.new_merge_id(), "/PhotoMenuBar/FileMenu/PrintPlaceholder", "PageSetup",
            "PageSetup", Gtk.UIManagerItemType.MENUITEM, false);
        ui.add_ui(ui.new_merge_id(), "/PhotoMenuBar/FileMenu/PrintPlaceholder", "Print",
            "Print", Gtk.UIManagerItemType.MENUITEM, false);
#endif

#if !NO_PUBLISHING
        ui.add_ui(ui.new_merge_id(), "/PhotoMenuBar/FileMenu/PublishPlaceholder", "Publish",
            "Publish", Gtk.UIManagerItemType.MENUITEM, false);
#endif

#if !NO_SET_BACKGROUND
        ui.add_ui(ui.new_merge_id(), "/PhotoMenuBar/PhotoMenu/SetBackgroundPlaceholder",
            "SetBackground", "SetBackground", Gtk.UIManagerItemType.MENUITEM, false);
        ui.add_ui(ui.new_merge_id(), "/PhotoContextMenu/ContextSetBackgroundPlaceholder",
            "SetBackground", "SetBackground", Gtk.UIManagerItemType.MENUITEM, false);
#endif
        
        context_menu = (Gtk.Menu) ui.get_widget("/PhotoContextMenu");
        
        // watch for photos being destroyed or removed or altered, either here or in other pages
        LibraryPhoto.global.items_removed += on_photos_removed;
        LibraryPhoto.global.item_destroyed += on_photo_destroyed;
        LibraryPhoto.global.item_metadata_altered += on_metadata_altered;
    }
    
    ~LibraryPhotoPage() {
        LibraryPhoto.global.items_removed -= on_photos_removed;
        LibraryPhoto.global.item_destroyed -= on_photo_destroyed;
        LibraryPhoto.global.item_metadata_altered -= on_metadata_altered;
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, on_file_menu };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry export = { "Export", Gtk.STOCK_SAVE_AS, TRANSLATABLE, "<Ctrl><Shift>E",
            TRANSLATABLE, on_export };
        export.label = Resources.EXPORT_MENU;
        export.tooltip = Resources.EXPORT_TOOLTIP;
        actions += export;

#if !NO_PRINTING
        Gtk.ActionEntry page_setup = { "PageSetup", Gtk.STOCK_PAGE_SETUP, TRANSLATABLE, null,
            TRANSLATABLE, on_page_setup };
        page_setup.label = Resources.PAGE_SETUP_MENU;
        page_setup.tooltip = Resources.PAGE_SETUP_TOOLTIP;
        actions += page_setup;

        Gtk.ActionEntry print = { "Print", Gtk.STOCK_PRINT, TRANSLATABLE, "<Ctrl>P",
            TRANSLATABLE, on_print };
        print.label = Resources.PRINT_MENU;
        print.tooltip = Resources.PRINT_TOOLTIP;
        actions += print;
#endif
        
#if !NO_PUBLISHING
        Gtk.ActionEntry publish = { "Publish", Resources.PUBLISH, TRANSLATABLE, "<Ctrl><Shift>P",
            TRANSLATABLE, on_publish };
        publish.label = Resources.PUBLISH_MENU;
        publish.tooltip = Resources.PUBLISH_TOOLTIP;
        actions += publish;
#endif
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, on_edit_menu };
        edit.label = _("_Edit");
        actions += edit;
        
        Gtk.ActionEntry remove = { "Remove", Gtk.STOCK_REMOVE, TRANSLATABLE, "Delete",
            TRANSLATABLE, on_remove };
        remove.label = _("Re_move");
        remove.tooltip = _("Remove the photo from your library");
        actions += remove;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, on_view_menu };
        view.label = _("_View");
        actions += view;
        
        Gtk.ActionEntry photo = { "PhotoMenu", null, TRANSLATABLE, null, null, on_photo_menu };
        photo.label = _("_Photo");
        actions += photo;
        
        Gtk.ActionEntry tools = { "Tools", null, TRANSLATABLE, null, null, on_tools };
        tools.label = _("_Tools");
        actions += tools;
        
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
            "bracketright", TRANSLATABLE, on_rotate_clockwise };
        rotate_right.label = Resources.ROTATE_CW_MENU;
        rotate_right.tooltip = Resources.ROTATE_CW_TOOLTIP;
        actions += rotate_right;

        Gtk.ActionEntry rotate_left = { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE,
            TRANSLATABLE, "bracketleft", TRANSLATABLE, on_rotate_counterclockwise };
        rotate_left.label = Resources.ROTATE_CCW_MENU;
        rotate_left.tooltip = Resources.ROTATE_CCW_TOOLTIP;
        actions += rotate_left;

        Gtk.ActionEntry mirror = { "Mirror", Resources.MIRROR, TRANSLATABLE, null,
            TRANSLATABLE, on_mirror };
        mirror.label = Resources.MIRROR_MENU;
        mirror.tooltip = Resources.MIRROR_TOOLTIP;
        actions += mirror;
        
        Gtk.ActionEntry flip = { "Flip", Resources.FLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip };
        flip.label = Resources.FLIP_MENU;
        flip.tooltip = Resources.FLIP_TOOLTIP;
        actions += flip;
        
        Gtk.ActionEntry enhance = { "Enhance", Resources.ENHANCE, TRANSLATABLE, "<Ctrl>E",
            TRANSLATABLE, on_enhance };
        enhance.label = Resources.ENHANCE_MENU;
        enhance.tooltip = Resources.ENHANCE_TOOLTIP;
        actions += enhance;
        
        Gtk.ActionEntry crop = { "Crop", Resources.CROP, TRANSLATABLE, "<Ctrl>R",
            TRANSLATABLE, toggle_crop };
        crop.label = Resources.CROP_MENU;
        crop.tooltip = Resources.CROP_TOOLTIP;
        actions += crop;
        
        Gtk.ActionEntry red_eye = { "RedEye", Resources.REDEYE, TRANSLATABLE, "<Ctrl>Y",
            TRANSLATABLE, toggle_redeye };
        red_eye.label = Resources.RED_EYE_MENU;
        red_eye.tooltip = Resources.RED_EYE_TOOLTIP;
        actions += red_eye;
        
        Gtk.ActionEntry adjust = { "Adjust", Resources.ADJUST, TRANSLATABLE, "<Ctrl>D",
            TRANSLATABLE, toggle_adjust };
        adjust.label = Resources.ADJUST_MENU;
        adjust.tooltip = Resources.ADJUST_TOOLTIP;
        actions += adjust;
        
        Gtk.ActionEntry revert = { "Revert", Gtk.STOCK_REVERT_TO_SAVED, TRANSLATABLE,
            null, TRANSLATABLE, on_revert };
        revert.label = Resources.REVERT_MENU;
        revert.tooltip = Resources.REVERT_TOOLTIP;
        actions += revert;

        Gtk.ActionEntry rename = { "PhotoRename", null, TRANSLATABLE, "F2", TRANSLATABLE,
            on_rename };
        rename.label = Resources.RENAME_PHOTO_MENU;
        rename.tooltip = Resources.RENAME_PHOTO_TOOLTIP;
        actions += rename;

        Gtk.ActionEntry adjust_date_time = { "AdjustDateTime", null, TRANSLATABLE, null,
            TRANSLATABLE, on_adjust_date_time };
        adjust_date_time.label = Resources.ADJUST_DATE_TIME_MENU;
        adjust_date_time.tooltip = Resources.ADJUST_DATE_TIME_TOOLTIP;
        actions += adjust_date_time;

#if !NO_SET_BACKGROUND
        Gtk.ActionEntry set_background = { "SetBackground", null, TRANSLATABLE, "<Ctrl>B",
            TRANSLATABLE, on_set_background };
        set_background.label = Resources.SET_BACKGROUND_MENU;
        set_background.tooltip = Resources.SET_BACKGROUND_TOOLTIP;
        actions += set_background;
#endif

        Gtk.ActionEntry favorite = { "FavoriteUnfavorite", Resources.FAVORITE, TRANSLATABLE, 
            "<Ctrl>F", TRANSLATABLE, on_favorite_unfavorite };
        favorite.label = Resources.FAVORITE_MENU;
        favorite.tooltip = Resources.FAVORITE_TOOLTIP;
        actions += favorite;
        
        Gtk.ActionEntry hide_unhide = { "HideUnhide", Resources.HIDDEN, TRANSLATABLE, "<Ctrl>H",
            TRANSLATABLE, on_hide_unhide };
        hide_unhide.label = Resources.HIDE_MENU;
        hide_unhide.tooltip = Resources.HIDE_TOOLTIP;
        actions += hide_unhide;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        Gtk.ActionEntry increase_size = { "IncreaseSize", Gtk.STOCK_ZOOM_IN, TRANSLATABLE,
            "<Ctrl>plus", TRANSLATABLE, on_increase_size };
        increase_size.label = _("Zoom _In");
        increase_size.tooltip = _("Increase the magnification of the photo");
        actions += increase_size;

        Gtk.ActionEntry decrease_size = { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, TRANSLATABLE,
            "<Ctrl>minus", TRANSLATABLE, on_decrease_size };
        decrease_size.label = _("Zoom _Out");
        decrease_size.tooltip = _("Decrease the magnification of the photo");
        actions += decrease_size;

        return actions;
    }
    
    public void display_for_collection(CollectionPage return_page, Thumbnail thumbnail) {
        this.return_page = return_page;
        
        display(return_page.get_view(), thumbnail.get_photo());
    }
    
    public CollectionPage get_controller_page() {
        return return_page;
    }

    public override void switched_to() {
        base.switched_to();
        
        update_zoom_menu_item_sensitivity();
    }

    protected override void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        base.paint(gc, drawable);

        if (!has_current_tool()) {
            Gdk.Pixbuf? trinket = null;
            
            if (((LibraryPhoto) get_photo()).is_hidden())
                trinket = Resources.get_icon(Resources.ICON_HIDDEN, TRINKET_SCALE);
            else if (((LibraryPhoto) get_photo()).is_favorite())
                trinket = Resources.get_icon(Resources.ICON_FAVORITE, TRINKET_SCALE);
            
            if (trinket == null)
                return;
            
            Gdk.Pixbuf? pixbuf = get_scaled_pixbuf();
            
            if (pixbuf == null)
                return;

            int x, y;
            drawable.get_size(out x, out y);

            drawable.draw_pixbuf(gc, trinket, 0, 0, 
                (x / 2) + (pixbuf.get_width() / 2) - trinket.get_width() - TRINKET_PADDING, 
                (y / 2) + (pixbuf.get_height() / 2) - trinket.get_height() - TRINKET_PADDING, 
                trinket.get_width(), trinket.get_height(), Gdk.RgbDither.NORMAL, 0, 0);
        }
    }

    private void update_zoom_menu_item_sensitivity() {
        set_item_sensitive("/PhotoMenuBar/ViewMenu/IncreaseSize", !get_zoom_state().is_max());
        set_item_sensitive("/PhotoMenuBar/ViewMenu/DecreaseSize", !get_zoom_state().is_default());
    }

    protected override void on_increase_size() {
        base.on_increase_size();
        
        update_zoom_menu_item_sensitivity();
    }
    
    protected override void on_decrease_size() {
        base.on_decrease_size();

        update_zoom_menu_item_sensitivity();
    }

    protected override bool on_zoom_slider_key_press(Gdk.EventKey event) {
        if (base.on_zoom_slider_key_press(event))
            return true;

        if (Gdk.keyval_name(event.keyval) == "Escape") {
            return_to_collection();
            return true;
        } else {
            return false;
        }
    }

    protected override void set_missing_photo_sensitivities(bool sensitivity) {
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/RotateClockwise", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/RotateCounterclockwise", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Mirror", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Flip", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Tools/Enhance", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Tools/Crop", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Tools/RedEye", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Tools/Adjust", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Revert", sensitivity);

        set_item_sensitive("/PhotoContextMenu/ContextRotateClockwise", sensitivity);
        set_item_sensitive("/PhotoContextMenu/ContextRotateCounterclockwise", sensitivity);
        set_item_sensitive("/PhotoContextMenu/PhotoRename", sensitivity);
        set_item_sensitive("/PhotoContextMenu/AdjustDateTime", sensitivity);
        
#if !NO_SET_BACKGROUND
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/SetBackgroundPlaceholder/SetBackground",
            sensitivity);
        set_item_sensitive("/PhotoContextMenu/ContextSetBackgroundPlaceholder/SetBackground",
            sensitivity);
#endif

        set_item_sensitive("/PhotoContextMenu/ContextHideUnhide", sensitivity);
        set_item_sensitive("/PhotoContextMenu/ContextFavoriteUnfavorite", sensitivity);
        
        base.set_missing_photo_sensitivities(sensitivity);
    }
    
    private override bool key_press_event(Gdk.EventKey event) {
        if (base.key_press_event != null && base.key_press_event(event) == true)
            return true;
        
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "Escape":
                return_to_collection();
            break;
            
            case "Delete":
                // although bound as an accelerator in the menu, accelerators are currently
                // unavailable in fullscreen mode (a variant of #324), so we do this manually
                // here
                on_remove();
            break;
            
            default:
                handled = false;
            break;
        }
        
        return handled;
    }
    
    protected override bool on_double_click(Gdk.EventButton event) {
        if (!(get_container() is FullscreenWindow)) {
            return_to_collection_on_release = true;
            
            return true;
        }
        
        AppWindow.get_instance().end_fullscreen();
        
        return base.on_double_click(event);
    }
    
    protected override bool on_left_released(Gdk.EventButton event) {
        if (return_to_collection_on_release) {
            return_to_collection_on_release = false;
            return_to_collection();
            
            return true;
        }
        
        return base.on_left_released(event);
    }
    
    private override bool on_context_invoked() {
        if (!has_photo())
            return false;

        set_item_sensitive("/PhotoContextMenu/ContextRotateClockwise", is_rotate_available(get_photo()));
        set_item_sensitive("/PhotoContextMenu/ContextRotateCounterclockwise",
            is_rotate_available(get_photo()));
        set_item_sensitive("/PhotoContextMenu/ContextEnhance", is_enhance_available(get_photo()));
        set_item_sensitive("/PhotoContextMenu/ContextRevert", get_photo().has_transformations());

        set_hide_item_label("/PhotoContextMenu/ContextHideUnhide");
        set_favorite_item_label("/PhotoContextMenu/ContextFavoriteUnfavorite");

        return base.on_context_invoked();
    }    

    private override bool on_context_buttonpress(Gdk.EventButton event) {
        popup_context_menu(context_menu, event);

        return true;
    }

    private override bool on_context_keypress() {
        popup_context_menu(context_menu);
        
        return true;
    }

    private void return_to_collection() {
        ViewCollection controller = get_controller();
        if (controller != null && has_photo()) {
            controller.unselect_all();
            
            return_page.set_cursor((CheckerboardItem) controller.get_view_for_source(get_photo()));
        }
        
        LibraryWindow.get_app().switch_to_page(return_page);
    }

    private void on_remove() {
        if (!has_photo())
            return;
        
        LibraryPhoto photo = (LibraryPhoto) get_photo();
        
        Gee.Collection<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        photos.add(photo);
        
        // move on to next photo before executing
        on_next_photo();
        bool no_more = photo.equals(get_photo());
        
        get_command_manager().execute(new TrashUntrashPhotosCommand(photos, true));
        
        // this indicates there is only one photo in the controller, or now zero, so switch 
        // to the Photos page, which is guaranteed to be there
        if (no_more)
            LibraryWindow.get_app().switch_to_library_page();
    }
    
    private void on_photo_destroyed(DataSource source) {
        on_photo_removed(source);
    }
    
    private void on_photos_removed(Gee.Iterable<DataSource> removed) {
        foreach (DataSource source in removed)
            on_photo_removed((LibraryPhoto) source);
    }
    
    private void on_photo_removed(DataSource source) {
        LibraryPhoto photo = source as LibraryPhoto;
        
        // only interested in current photo
        if (photo == null || !photo.equals(get_photo()))
            return;
        
        // move on to the next one in the collection
        on_next_photo();
        if (photo.equals(get_photo())) {
            // this indicates there is only one photo in the controller, or now zero, so switch 
            // to the Photos page, which is guaranteed to be there
            LibraryWindow.get_app().switch_to_library_page();
        }
    }

#if !NO_PRINTING
    private void on_print() {
        PrintManager.get_instance().spool_photo(get_photo());
    }

    private void on_page_setup() {
        PrintManager.get_instance().do_page_setup();
    }
#endif

    private void on_export() {
        if (!has_photo())
            return;
        
        ExportDialog export_dialog = new ExportDialog(_("Export Photo"));
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        PhotoFileFormat format = get_photo().get_file_format();
        if (!export_dialog.execute(out scale, out constraint, out quality, ref format))
            return;
        
        File save_as = ExportUI.choose_file(get_photo().get_export_basename(format));
        if (save_as == null)
            return;
        
        Scaling scaling = Scaling.for_constraint(constraint, scale, false);
        
        try {
            get_photo().export(save_as, scaling, quality, format);
        } catch (Error err) {
            AppWindow.error_message(_("Unable to export %s: %s").printf(save_as.get_path(), err.message));
        }
    }
    
    private void on_file_menu() {
#if !NO_PRINTING
        set_item_sensitive("/PhotoMenuBar/FileMenu/PrintPlaceholder/Print", has_photo());
#endif

        set_item_sensitive("/PhotoMenuBar/FileMenu/Export", has_photo());

#if !NO_PUBLISHING
        set_item_sensitive("/PhotoMenuBar/FileMenu/PublishPlaceholder/Publish", has_photo());
#endif
    }
    
#if !NO_PUBLISHING
    private void on_publish() {
        if (get_view().get_count() == 0)
            return;
        
        PublishingDialog publishing_dialog = new PublishingDialog(
            (Gee.Iterable<DataView>) get_view().get_all());
        publishing_dialog.run();
    }
#endif
    
    private void on_edit_menu() {
        decorate_undo_item("/PhotoMenuBar/EditMenu/Undo");
        decorate_redo_item("/PhotoMenuBar/EditMenu/Redo");
        set_item_sensitive("/PhotoMenuBar/EditMenu/Remove", has_photo());
    }
    
    protected void set_favorite_item_label(string path) {
        // Favorite/Unfavorite menu item depends on several conditions
        Gtk.MenuItem favorite_menu_item = (Gtk.MenuItem) ui.get_widget(path);
        assert(favorite_menu_item != null);
        
        favorite_menu_item.set_label(can_favorite() ? Resources.FAVORITE_MENU :
            Resources.UNFAVORITE_MENU);
    }

    protected void set_hide_item_label(string path) {
        // Hide/Unhide menu item depends on several conditions
        Gtk.MenuItem hide_menu_item = (Gtk.MenuItem) ui.get_widget(path);
        assert(hide_menu_item != null);

        hide_menu_item.set_label(can_hide() ? Resources.HIDE_MENU : Resources.UNHIDE_MENU);
    }
    
    private void on_photo_menu() {
        bool multiple = (get_controller() != null) ? get_controller().get_count() > 1 : false;
        bool revert_possible = has_photo() ? get_photo().has_transformations() : false;
        bool rotate_possible = has_photo() ? is_rotate_available(get_photo()) : false;
        
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/NextPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/RotateClockwise", rotate_possible);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/RotateCounterclockwise", rotate_possible);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Mirror", rotate_possible);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Flip", rotate_possible);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Revert", revert_possible);
        set_hide_item_label("/PhotoMenuBar/PhotoMenu/HideUnhide");
        set_favorite_item_label("/PhotoMenuBar/PhotoMenu/FavoriteUnfavorite");
    }
    
    private void on_tools() {
        bool enhance_possible = has_photo() ? is_enhance_available(get_photo()) : false;
        
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Tools/Enhance", enhance_possible);
    }
    
    private void on_view_menu() {
        update_zoom_menu_item_sensitivity();
    }
    
    private void on_favorite_unfavorite() {
        if (!has_photo())
            return;

        FavoriteUnfavoriteSingleCommand command = new FavoriteUnfavoriteSingleCommand(get_photo(),
            can_favorite());

        get_command_manager().execute(command);
    }
    
    private void on_hide_unhide() {
        if (!has_photo())
            return;

        HideUnhideSingleCommand command = new HideUnhideSingleCommand(get_photo(),
            can_hide());

        if (!Config.get_instance().get_display_hidden_photos())
            on_photo_removed(get_photo());

        get_command_manager().execute(command);
    }

    protected bool can_favorite() {
        if (!has_photo())
            return false;
 
        return !((LibraryPhoto) get_photo()).is_favorite();
    }
    
    protected bool can_hide() {
        if (!has_photo())
            return false;

        return !((LibraryPhoto) get_photo()).is_hidden();
    }

    private void on_metadata_altered(DataObject item) {
        if (((TransformablePhoto) item).equals(get_photo()))
            repaint();
    }
}

//
// DirectPhotoPage
//

// TODO: This implementation of a ViewCollection is solely for use in direct editing mode, and will 
// not satisfy all the requirements of a checkerboard-style file browser without additional work.
//
// TODO: With the new SourceCollection/ViewCollection model, we can start monitoring the cwd for
// files and generating DirectPhotoSource stubs to represent each possible image file in the
// directory, only importing them into the system when selected by the user.
private class DirectViewCollection : ViewCollection {
    private class DirectViewManager : ViewManager {
        public override DataView create_view(DataSource source) {
            return new DataView(source);
        }
    }
    
    private File dir;
    private SortedList<File>? cached = null;
    
    public DirectViewCollection(File dir) {
        base ("DirectViewCollection of %s".printf(dir.get_path()));
        
        this.dir = dir;
        
        monitor_source_collection(DirectPhoto.global, new DirectViewManager());
    }
    
    public override int get_count() {
        SortedList<File> list = get_children_photos();
        
        return (list != null) ? list.size : 0;
    }
    
    public override DataView? get_first() {
        SortedList<File> list = get_children_photos();
        if (list == null)
            return null;
        
        File file = null;
        while (list.size > 0) {
            file = list.get_at(0);
            
            if (validate(file))
                break;
            
            file = null;
        }
        
        if (file == null)
            return null;
        
        DirectPhoto? photo = null;
        try {
            photo = DirectPhoto.global.fetch(file);
        } catch (Error error) {
            warning("Fetching photo failed: %s", error.message);
        }
        
        return (photo != null) ? get_view_for_source(photo) : null;
    }
    
    public override DataView? get_last() {
        SortedList<File> list = get_children_photos();
        if (list == null)
            return null;
        
        File file = null;
        while (list.size > 0) {
            file = list.get_at(list.size - 1);
            
            if (validate(file))
                break;
            
            file = null;
        }
        
        if (file == null)
            return null;
        
        DirectPhoto? photo = null;
        try {
            photo = DirectPhoto.global.fetch(file);
        } catch (Error error) {
            warning("Fetching photo failed: %s", error.message);
        }
        
        return (photo != null) ? get_view_for_source(photo) : null;
    }
    
    public override DataView? get_next(DataView current) {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        int index = list.index_of(((DirectPhoto) current.get_source()).get_file());
        if (index < 0)
            index = 0;
        else
            index++;
        
        File file = null;
        while (list.size > 0) {
            if (index >= list.size)
                index = 0;
            
            file = list.get_at(index);
            
            if (validate(file))
                break;
            
            file = null;
        }
        
        if (file == null)
            return null;
        
        DirectPhoto? photo = null;
        try {
            photo = DirectPhoto.global.fetch(file);
        } catch (Error error) {
            warning("Fetching photo failed: %s", error.message);
        }
        
        return (photo != null) ? get_view_for_source(photo) : null;
    }
    
    public override DataView? get_previous(DataView current) {
        SortedList<File> list = get_children_photos();
        if (list == null || list.size == 0)
            return null;
        
        int index = list.index_of(((DirectPhoto) current.get_source()).get_file());
        if (index < 0)
            index = 0;
        else
            index--;
        
        File file = null;
        while (list.size > 0) {
            if (index < 0)
                index = list.size - 1;
            
            file = list.get_at(index);
            
            if (validate(file))
                break;
            
            file = null;
        }
        
        if (file == null)
            return null;
        
        DirectPhoto? photo = null;
        try {
            photo = DirectPhoto.global.fetch(file);
        } catch (Error error) {
            warning("Fetching photo failed: %s", error.message);
        }
        
        return (photo != null) ? get_view_for_source(photo) : null;
    }
    
    private SortedList<File>? get_children_photos() {
        if (cached != null)
            return cached;
        
        cached = new SortedList<File>(file_comparator);
        
        try {
            FileEnumerator enumerator = dir.enumerate_children(FILE_ATTRIBUTE_STANDARD_NAME,
                FileQueryInfoFlags.NONE, null);
            
            FileInfo file_info = null;
            while ((file_info = enumerator.next_file(null)) != null) {
                string basename = file_info.get_name();
                
                if (TransformablePhoto.is_basename_supported(basename))
                    cached.add(dir.get_child(basename));
            }
        } catch (Error err) {
            message("Unable to enumerate children in %s: %s", dir.get_path(), err.message);
            
            cached = null;
        }
        
        return cached;
    }
    
    private bool validate(File file) {
        if (file.query_exists(null))
            return true;
        
        // Remove from SortedList but not from the SourceCollection.  If the lost photo is the
        // current one, EditingHostPage has no way to determine what is next or previous, as the current
        // location is now invalid.
        //
        // TODO: Fix this behavior.
        if (cached != null)
            cached.remove(file);
        
        return false;
    }
}

public class DirectPhotoPage : EditingHostPage {
    private Gtk.Menu context_menu;
    private File initial_file;
    private File current_save_dir;
    private bool drop_if_dirty = false;

    public DirectPhotoPage(File file) {
        base(DirectPhoto.global, file.get_basename());
        
        if (!check_editable_file(file)) {
            Posix.exit(1);
            
            return;
        }
        
        initial_file = file;
        current_save_dir = file.get_parent();
        
        init_ui("direct.ui", "/DirectMenuBar", "DirectActionGroup", create_actions());

#if !NO_PRINTING
        ui.add_ui(ui.new_merge_id(), "/DirectMenuBar/FileMenu/PrintPlaceholder", "PageSetup",
            "PageSetup", Gtk.UIManagerItemType.MENUITEM, false);
        ui.add_ui(ui.new_merge_id(), "/DirectMenuBar/FileMenu/PrintPlaceholder", "Print",
            "Print", Gtk.UIManagerItemType.MENUITEM, false);
#endif

        context_menu = (Gtk.Menu) ui.get_widget("/DirectContextMenu");
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, on_file_menu };
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

#if !NO_PRINTING
        Gtk.ActionEntry page_setup = { "PageSetup", Gtk.STOCK_PAGE_SETUP, TRANSLATABLE, null,
            TRANSLATABLE, on_page_setup };
        page_setup.label = _("Page _Setup...");
        actions += page_setup;

        Gtk.ActionEntry print = { "Print", Gtk.STOCK_PRINT, TRANSLATABLE, "<Ctrl>P",
            TRANSLATABLE, on_print };
        print.label = _("Prin_t...");
        print.tooltip = _("Print the photo to a printer connected to your computer");
        actions += print;
#endif
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, on_edit_menu };
        edit.label = _("Edit");
        actions += edit;

        Gtk.ActionEntry photo = { "PhotoMenu", null, "", null, null, on_photo_menu };
        photo.label = _("_Photo");
        actions += photo;
        
        Gtk.ActionEntry tools = { "Tools", null, TRANSLATABLE, null, null, on_tools };
        tools.label = _("_Tools");
        actions += tools;
        
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
            TRANSLATABLE, "bracketright", TRANSLATABLE, on_rotate_clockwise };
        rotate_right.label = Resources.ROTATE_CW_MENU;
        rotate_right.tooltip = Resources.ROTATE_CCW_TOOLTIP;
        actions += rotate_right;

        Gtk.ActionEntry rotate_left = { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE,
            TRANSLATABLE, "bracketleft", TRANSLATABLE, on_rotate_counterclockwise };
        rotate_left.label = Resources.ROTATE_CCW_MENU;
        rotate_left.tooltip = Resources.ROTATE_CCW_TOOLTIP;
        actions += rotate_left;

        Gtk.ActionEntry mirror = { "Mirror", Resources.MIRROR, TRANSLATABLE, null,
            TRANSLATABLE, on_mirror };
        mirror.label = Resources.MIRROR_MENU;
        mirror.tooltip = Resources.MIRROR_TOOLTIP;
        actions += mirror;
        
        Gtk.ActionEntry flip = { "Flip", Resources.FLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip };
        flip.label = Resources.FLIP_MENU;
        flip.tooltip = Resources.FLIP_TOOLTIP;
        actions += flip;
        
        Gtk.ActionEntry enhance = { "Enhance", Resources.ENHANCE, TRANSLATABLE, "<Ctrl>E",
            TRANSLATABLE, on_enhance };
        enhance.label = Resources.ENHANCE_MENU;
        enhance.tooltip = Resources.ENHANCE_TOOLTIP;
        actions += enhance;
        
        Gtk.ActionEntry crop = { "Crop", Resources.CROP, TRANSLATABLE, "<Ctrl>R",
            TRANSLATABLE, toggle_crop };
        crop.label = Resources.CROP_MENU;
        crop.tooltip = Resources.CROP_TOOLTIP;
        actions += crop;
        
        Gtk.ActionEntry red_eye = { "RedEye", Resources.REDEYE, TRANSLATABLE, "<Ctrl>Y",
            TRANSLATABLE, toggle_redeye };
        red_eye.label = Resources.RED_EYE_MENU;
        red_eye.tooltip = Resources.RED_EYE_TOOLTIP;
        actions += red_eye;
        
        Gtk.ActionEntry adjust = { "Adjust", Resources.ADJUST, TRANSLATABLE, "<Ctrl>D",
            TRANSLATABLE, toggle_adjust };
        adjust.label = Resources.ADJUST_MENU;
        adjust.tooltip = Resources.ADJUST_TOOLTIP;
        actions += adjust;
        
        Gtk.ActionEntry revert = { "Revert", Gtk.STOCK_REVERT_TO_SAVED, TRANSLATABLE,
            null, TRANSLATABLE, on_revert };
        revert.label = Resources.REVERT_MENU;
        revert.tooltip = Resources.REVERT_TOOLTIP;
        actions += revert;

        Gtk.ActionEntry adjust_date_time = { "AdjustDateTime", null, TRANSLATABLE, null,
            TRANSLATABLE, on_adjust_date_time };
        adjust_date_time.label = Resources.ADJUST_DATE_TIME_MENU;
        adjust_date_time.tooltip = Resources.ADJUST_DATE_TIME_TOOLTIP;
        actions += adjust_date_time;

#if !NO_SET_BACKGROUND
        Gtk.ActionEntry set_background = { "SetBackground", null, TRANSLATABLE, "<Ctrl>B",
            TRANSLATABLE, on_set_background };
        set_background.label = Resources.SET_BACKGROUND_MENU;
        set_background.tooltip = Resources.SET_BACKGROUND_TOOLTIP;
        actions += set_background;
#endif

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, null };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        Gtk.ActionEntry increase_size = { "IncreaseSize", Gtk.STOCK_ZOOM_IN, TRANSLATABLE,
            "<Ctrl>plus", TRANSLATABLE, on_increase_size };
        increase_size.label = _("Zoom _In");
        increase_size.tooltip = _("Increase the magnification of the photo");
        actions += increase_size;

        Gtk.ActionEntry decrease_size = { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, TRANSLATABLE,
            "<Ctrl>minus", TRANSLATABLE, on_decrease_size };
        decrease_size.label = _("Zoom _Out");
        decrease_size.tooltip = _("Decrease the magnification of the photo");
        actions += decrease_size;

        return actions;
    }
    
    private static bool check_editable_file(File file) {
        if (!FileUtils.test(file.get_path(), FileTest.EXISTS))
            AppWindow.error_message(_("%s does not exist.").printf(file.get_path()));
        else if (!FileUtils.test(file.get_path(), FileTest.IS_REGULAR))
            AppWindow.error_message(_("%s is not a file.").printf(file.get_path()));
        else if (!TransformablePhoto.is_file_supported(file))
            AppWindow.error_message(_("%s does not support the file format of\n%s.").printf(
                Resources.APP_TITLE, file.get_path()));
        else
            return true;
        
        return false;
    }
    
    private override void realize() {
        if (base.realize != null)
            base.realize();
        
        DirectPhoto photo = null;
        try {
            photo = DirectPhoto.global.fetch(initial_file);
        } catch (Error error) {
            warning("Fetching photo failed: %s", error.message);
        }
        
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

    private override bool on_context_buttonpress(Gdk.EventButton event) {
        popup_context_menu(context_menu, event);

        return true;
    }

    private void update_zoom_menu_item_sensitivity() {
        set_item_sensitive("/DirectMenuBar/ViewMenu/IncreaseSize", !get_zoom_state().is_max());
        set_item_sensitive("/DirectMenuBar/ViewMenu/DecreaseSize", !get_zoom_state().is_default());
    }

    protected override void on_increase_size() {
        base.on_increase_size();
        
        update_zoom_menu_item_sensitivity();
    }
    
    protected override void on_decrease_size() {
        base.on_decrease_size();

        update_zoom_menu_item_sensitivity();
    }

    protected override void set_missing_photo_sensitivities(bool sensitivity) {
        set_item_sensitive("/DirectMenuBar/FileMenu/Save", sensitivity);
        set_item_sensitive("/DirectMenuBar/FileMenu/SaveAs", sensitivity);
        
        set_item_sensitive("/DirectMenuBar/PhotoMenu/RotateClockwise", sensitivity);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/RotateCounterclockwise", sensitivity);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/Mirror", sensitivity);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/Flip", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Tools/Enhance", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Tools/Crop", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Tools/RedEye", sensitivity);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Tools/Adjust", sensitivity);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/Revert", sensitivity);

        set_item_sensitive("/DirectContextMenu/ContextRotateClockwise", sensitivity);
        set_item_sensitive("/DirectContextMenu/ContextRotateCounterclockwise", sensitivity);
        set_item_sensitive("/DirectContextMenu/ContextEnhance", sensitivity);
        set_item_sensitive("/DirectContextMenu/ContextRevert", sensitivity);
        
#if !NO_SET_BACKGROUND
        set_item_sensitive("/DirectContextMenu/ContextSetBackgroundPlaceholder/ContextSetBackground", sensitivity);
#endif
    
        base.set_missing_photo_sensitivities(sensitivity);
    }
    
    private override bool on_context_invoked() {
        if (get_photo() == null)
            return false;
        
        set_item_sensitive("/DirectContextMenu/ContextRotateClockwise", is_rotate_available(get_photo()));
        set_item_sensitive("/DirectContextMenu/ContextRotateCounterclockwise",
            is_rotate_available(get_photo()));
        set_item_sensitive("/DirectContextMenu/ContextEnhance", is_enhance_available(get_photo()));
        set_item_sensitive("/DirectContextMenu/ContextRevert", get_photo().has_transformations());
        
        return base.on_context_invoked();
    }
    
    private bool check_ok_to_close_photo(TransformablePhoto photo) {
        if (!photo.has_alterations())
            return true;
        
        if (drop_if_dirty) {
            // need to remove transformations, or else they stick around in memory (reappearing
            // if the user opens the file again)
            photo.remove_all_transformations();
            
            return true;
        }

        bool is_writeable = get_photo().get_file_format().can_write();
        string save_option = is_writeable ? _("_Save") : _("_Save a Copy");

        Gtk.ResponseType response = AppWindow.negate_affirm_cancel_question(
            _("Lose changes to %s?").printf(photo.get_name()), save_option,
            _("Close _without Saving"));

        if (response == Gtk.ResponseType.YES)
            photo.remove_all_transformations();
        else if (response == Gtk.ResponseType.NO) {
            if (is_writeable)
                save(photo.get_file(), 0, ScaleConstraint.ORIGINAL, Jpeg.Quality.HIGH,
                    get_photo().get_file_format());
            else
                on_save_as();
        } else if (response == Gtk.ResponseType.CANCEL)
            return false;

        return true;
    }
    
    public bool check_quit() {
        return check_ok_to_close_photo(get_photo());
    }
    
    private override bool confirm_replace_photo(TransformablePhoto? old_photo, TransformablePhoto new_photo) {
        return (old_photo != null) ? check_ok_to_close_photo(old_photo) : true;
    }
    
    private void on_file_menu() {
        set_item_sensitive("/DirectMenuBar/FileMenu/Save", get_photo().has_alterations() && get_photo().get_file_format().can_write());
    }
    
    private void save(File dest, int scale, ScaleConstraint constraint, Jpeg.Quality quality,
        PhotoFileFormat format) {
        Scaling scaling = Scaling.for_constraint(constraint, scale, false);
        
        try {
            get_photo().export(dest, scaling, quality, format);
        } catch (Error err) {
            AppWindow.error_message(_("Error while saving to %s: %s").printf(dest.get_path(),
                err.message));
            
            return;
        }
        
        DirectPhoto photo = null;
        try {
            photo = DirectPhoto.global.fetch(dest, true);
        } catch (Error error) {
            warning("Fetching photo failed: %s", error.message);
        }
        
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
        if (!get_photo().has_alterations() && !get_photo().get_file_format().can_write())
            return;

        // save full-sized version right on top of the current file
        save(get_photo().get_file(), 0, ScaleConstraint.ORIGINAL, Jpeg.Quality.HIGH,
            get_photo().get_file_format());
    }
    
    private void on_save_as() {
        ExportDialog export_dialog = new ExportDialog(_("Save As"));
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        PhotoFileFormat format = get_photo().get_file_format();
        if (!export_dialog.execute(out scale, out constraint, out quality, ref format))
            return;

        string basename = get_photo().get_file().get_basename();
        string ext;
        string filename;
        disassemble_filename(basename, out filename, out ext);

        // an optimization for a common case -- when the format chosen by the user in the
        // format combo box is the same as the format of the backing photo (e.g., the user
        // wants to save a JPEG image as a JPEG) AND the photo's existing filename uses a
        // known extension for the format, then there's no need to change the file's
        // extension, so skip doing an extension replacement
        if ((format == get_photo().get_file_format()) &&
            (format.get_properties().is_recognized_extension(ext))) {
            filename = basename;
        } else {
            if (filename == null || filename == "")
                filename = "shotwell";
            filename = format.get_default_basename(filename);
        }

        string[] output_format_extensions = format.get_properties().get_known_extensions();
        Gtk.FileFilter output_format_filter = new Gtk.FileFilter();
        foreach(string extension in output_format_extensions) {
            string uppercase_extension = extension.up();
            output_format_filter.add_pattern("*." + extension);
            output_format_filter.add_pattern("*." + uppercase_extension);
        }

        Gtk.FileChooserDialog save_as_dialog = new Gtk.FileChooserDialog(_("Save As"), 
            AppWindow.get_instance(), Gtk.FileChooserAction.SAVE, Gtk.STOCK_CANCEL, 
            Gtk.ResponseType.CANCEL, Gtk.STOCK_OK, Gtk.ResponseType.OK);
        save_as_dialog.set_select_multiple(false);
        save_as_dialog.set_current_name(filename);
        save_as_dialog.set_current_folder(current_save_dir.get_path());
        save_as_dialog.add_filter(output_format_filter);
        save_as_dialog.set_do_overwrite_confirmation(true);
        
        int response = save_as_dialog.run();
        if (response == Gtk.ResponseType.OK) {
            // flag to prevent asking user about losing changes to the old file (since they'll be
            // loaded right into the new one)
            drop_if_dirty = true;
            save(File.new_for_uri(save_as_dialog.get_uri()), scale, constraint, quality, format);
            drop_if_dirty = false;

            current_save_dir = File.new_for_path(save_as_dialog.get_current_folder());
        }
        
        save_as_dialog.destroy();
    }

#if !NO_PRINTING
    private void on_print() {
        PrintManager.get_instance().spool_photo(get_photo());
    }

    private void on_page_setup() {
        PrintManager.get_instance().do_page_setup();
    }
#endif
    
    private void on_edit_menu() {
        decorate_undo_item("/DirectMenuBar/EditMenu/Undo");
        decorate_redo_item("/DirectMenuBar/EditMenu/Redo");
    }
    
    private void on_photo_menu() {
        bool multiple = (get_controller() != null) ? get_controller().get_count() > 1 : false;
        bool revert_possible = has_photo() ? get_photo().has_transformations() : false;
        bool rotate_possible = has_photo() ? is_rotate_available(get_photo()) : false;

        set_item_sensitive("/DirectMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/NextPhoto", multiple);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/RotateClockwise", rotate_possible);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/RotateCounterclockwise", rotate_possible);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/Mirror", rotate_possible);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/Flip", rotate_possible);
        set_item_sensitive("/DirectMenuBar/PhotoMenu/Revert", revert_possible);
    }
    
    private void on_tools() {
        bool enhance_possible = has_photo() ? is_enhance_available(get_photo()) : false;
        
        set_item_sensitive("/DirectMenuBar/PhotoMenu/Tools/Enhance", enhance_possible);
    }
}
