/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class ZoomBuffer : Object {
    private enum ObjectState {
        SOURCE_NOT_LOADED,
        SOURCE_LOAD_IN_PROGRESS,
        SOURCE_NOT_TRANSFORMED,
        TRANSFORMED_READY
    }

    private class IsoSourceFetchJob : BackgroundJob {
        private Photo to_fetch;
        
        public Gdk.Pixbuf? fetched = null;

        public IsoSourceFetchJob(ZoomBuffer owner, Photo to_fetch,
            CompletionCallback completion_callback) {
            base(owner, completion_callback);
            
            this.to_fetch = to_fetch;
        }
        
        public override void execute() {
            try {
                fetched = to_fetch.get_pixbuf_with_options(Scaling.for_original(),
                    Photo.Exception.ADJUST);
            } catch (Error fetch_error) {
                critical("IsoSourceFetchJob: execute( ): can't get pixbuf from backing photo");
            }
        }
    }

    // it's worth noting that there are two different kinds of transformation jobs (though this
    // single class supports them both). There are "isomorphic" (or "iso") transformation jobs that
    // operate over full-size pixbufs and are relatively long-running and then there are
    // "demand" transformation jobs that occur over much smaller pixbufs as needed; these are
    // relatively quick to run.
    private class TransformationJob : BackgroundJob {
        private Gdk.Pixbuf to_transform;
        private PixelTransformer? transformer;
        private Cancellable cancellable;
        
        public Gdk.Pixbuf transformed = null;

        public TransformationJob(ZoomBuffer owner, Gdk.Pixbuf to_transform, PixelTransformer?
            transformer, CompletionCallback completion_callback, Cancellable cancellable) {
            base(owner, completion_callback, cancellable);

            this.cancellable = cancellable;
            this.to_transform = to_transform;
            this.transformer = transformer;
            this.transformed = to_transform.copy();
        }
        
        public override void execute() {
            if (transformer != null) {
                transformer.transform_to_other_pixbuf(to_transform, transformed, cancellable);
            }
        }
    }
    
    private const int MEGAPIXEL = 1048576;
    private const int USE_REDUCED_THRESHOLD = (int) 2.0 * MEGAPIXEL;

    private Gdk.Pixbuf iso_source_image = null;
    private Gdk.Pixbuf? reduced_source_image = null;
    private Gdk.Pixbuf iso_transformed_image = null;
    private Gdk.Pixbuf? reduced_transformed_image = null;
    private Gdk.Pixbuf preview_image = null;
    private Photo backing_photo = null;
    private ObjectState object_state = ObjectState.SOURCE_NOT_LOADED;
    private Gdk.Pixbuf? demand_transform_cached_pixbuf = null;
    private ZoomState demand_transform_zoom_state;
    private TransformationJob? demand_transform_job = null; // only 1 demand transform job can be
                                                            // active at a time
    private Workers workers = null;
    private SinglePhotoPage parent_page;
    private bool is_interactive_redraw_in_progress = false;

    public ZoomBuffer(SinglePhotoPage parent_page, Photo backing_photo,
        Gdk.Pixbuf preview_image) {
        this.parent_page = parent_page;
        this.preview_image = preview_image;
        this.backing_photo = backing_photo;
        this.workers = new Workers(2, false);
    }

    private void on_iso_source_fetch_complete(BackgroundJob job) {
        IsoSourceFetchJob fetch_job = (IsoSourceFetchJob) job;
        if (fetch_job.fetched == null) {
            critical("ZoomBuffer: iso_source_fetch_complete( ): fetch job has null image member");
            return;
        }

        iso_source_image = fetch_job.fetched;
        if ((iso_source_image.width * iso_source_image.height) > USE_REDUCED_THRESHOLD) {
            reduced_source_image = iso_source_image.scale_simple(iso_source_image.width / 2,
                iso_source_image.height / 2, Gdk.InterpType.BILINEAR);
        }
        object_state = ObjectState.SOURCE_NOT_TRANSFORMED;

        if (!is_interactive_redraw_in_progress)
            parent_page.repaint();

        BackgroundJob transformation_job = new TransformationJob(this, iso_source_image,
            backing_photo.get_pixel_transformer(), on_iso_transformation_complete,
            new Cancellable());
        workers.enqueue(transformation_job);
    }
    
    private void on_iso_transformation_complete(BackgroundJob job) {
        TransformationJob transform_job = (TransformationJob) job;
        if (transform_job.transformed == null) {
            critical("ZoomBuffer: on_iso_transformation_complete( ): completed job has null " +
                "image");
            return;
        }

        iso_transformed_image = transform_job.transformed;
        if ((iso_transformed_image.width * iso_transformed_image.height) > USE_REDUCED_THRESHOLD) {
            reduced_transformed_image = iso_transformed_image.scale_simple(
                iso_transformed_image.width / 2, iso_transformed_image.height / 2,
                Gdk.InterpType.BILINEAR);
        }
        object_state = ObjectState.TRANSFORMED_READY;            
    }
    
    private void on_demand_transform_complete(BackgroundJob job) {
        TransformationJob transform_job = (TransformationJob) job;
        if (transform_job.transformed == null) {
            critical("ZoomBuffer: on_demand_transform_complete( ): completed job has null " +
                "image");
            return;
        }

        demand_transform_cached_pixbuf = transform_job.transformed;
        demand_transform_job = null;

        parent_page.repaint();
    }

    // passing a 'reduced_pixbuf' that has one-quarter the number of pixels as the 'iso_pixbuf' is
    // optional, but including one can dramatically increase performance obtaining projection
    // pixbufs at for ZoomStates with zoom factors less than 0.5
    private Gdk.Pixbuf get_view_projection_pixbuf(ZoomState zoom_state, Gdk.Pixbuf iso_pixbuf,
        Gdk.Pixbuf? reduced_pixbuf = null) {
        Gdk.Rectangle view_rect = zoom_state.get_viewing_rectangle_wrt_content();
        Gdk.Rectangle view_rect_proj = zoom_state.get_viewing_rectangle_projection(
            iso_pixbuf);
        Gdk.Pixbuf sample_source_pixbuf = iso_pixbuf;

        if ((reduced_pixbuf != null) && (zoom_state.get_zoom_factor() < 0.5)) {
            sample_source_pixbuf = reduced_pixbuf;
            view_rect_proj.x /= 2;
            view_rect_proj.y /= 2;
            view_rect_proj.width /= 2;
            view_rect_proj.height /= 2;
        }

        Gdk.Pixbuf proj_subpixbuf = new Gdk.Pixbuf.subpixbuf(sample_source_pixbuf, view_rect_proj.x,
            view_rect_proj.y, view_rect_proj.width, view_rect_proj.height);

        Gdk.Pixbuf zoomed = proj_subpixbuf.scale_simple(view_rect.width, view_rect.height,
            Gdk.InterpType.BILINEAR);

        return zoomed;
    }
    
    private Gdk.Pixbuf get_zoomed_image_source_not_transformed(ZoomState zoom_state) {
        if (demand_transform_cached_pixbuf != null) {
            if (zoom_state.equals(demand_transform_zoom_state)) {
                // if a cached pixbuf from a previous on-demand transform operation exists and
                // its zoom state is the same as the currently requested zoom state, then we
                // don't need to do any work -- just return the cached copy
                return demand_transform_cached_pixbuf;
            } else if (zoom_state.get_zoom_factor() ==
                       demand_transform_zoom_state.get_zoom_factor()) {
                // if a cached pixbuf from a previous on-demand transform operation exists and
                // its zoom state is different from the currently requested zoom state, then we
                // can't just use the cached pixbuf as-is. However, we might be able to use *some*
                // of the information in the previously cached pixbuf. Specifically, if the zoom
                // state of the previously cached pixbuf is merely a translation of the currently
                // requested zoom state (the zoom states are not equal but the zoom factors are the
                // same), then all that has happened is that the user has panned the viewing
                // window. So keep all the pixels from the cached pixbuf that are still on-screen
                // in the current view.
                Gdk.Rectangle curr_rect = zoom_state.get_viewing_rectangle_wrt_content();
                Gdk.Rectangle pre_rect =
                    demand_transform_zoom_state.get_viewing_rectangle_wrt_content();
                Gdk.Rectangle transfer_src_rect = {0};
                Gdk.Rectangle transfer_dest_rect = {0};
                                 
                transfer_src_rect.x = (curr_rect.x - pre_rect.x).clamp(0, pre_rect.width);
                transfer_src_rect.y = (curr_rect.y - pre_rect.y).clamp(0, pre_rect.height);
                int transfer_src_right = ((curr_rect.x + curr_rect.width) - pre_rect.width).clamp(0,
                    pre_rect.width);
                transfer_src_rect.width = transfer_src_right - transfer_src_rect.x;
                int transfer_src_bottom = ((curr_rect.y + curr_rect.height) - pre_rect.width).clamp(
                    0, pre_rect.height);
                transfer_src_rect.height = transfer_src_bottom - transfer_src_rect.y;
                
                transfer_dest_rect.x = (pre_rect.x - curr_rect.x).clamp(0, curr_rect.width);
                transfer_dest_rect.y = (pre_rect.y - curr_rect.y).clamp(0, curr_rect.height);
                int transfer_dest_right = (transfer_dest_rect.x + transfer_src_rect.width).clamp(0,
                    curr_rect.width);
                transfer_dest_rect.width = transfer_dest_right - transfer_dest_rect.x;
                int transfer_dest_bottom = (transfer_dest_rect.y + transfer_src_rect.height).clamp(0,
                    curr_rect.height);
                transfer_dest_rect.height = transfer_dest_bottom - transfer_dest_rect.y;

                Gdk.Pixbuf composited_result = get_zoom_preview_image_internal(zoom_state);
                demand_transform_cached_pixbuf.copy_area (transfer_src_rect.x,
                    transfer_src_rect.y, transfer_dest_rect.width, transfer_dest_rect.height,
                    composited_result, transfer_dest_rect.x, transfer_dest_rect.y);

                return composited_result;
            }
        }

        // ok -- the cached pixbuf didn't help us -- so check if there is a demand
        // transformation background job currently in progress. if such a job is in progress,
        // then check if it's for the same zoom state as the one requested here. If the
        // zoom states are the same, then just return the preview image for now -- we won't
        // get a crisper one until the background job completes. If the zoom states are not the
        // same however, then cancel the existing background job and initiate a new one for the
        // currently requested zoom state.
        if (demand_transform_job != null) {
            if (zoom_state.equals(demand_transform_zoom_state)) {
                return get_zoom_preview_image_internal(zoom_state);
            } else {
                demand_transform_job.cancel();
                demand_transform_job = null;

                Gdk.Pixbuf zoomed = get_view_projection_pixbuf(zoom_state, iso_source_image,
                    reduced_source_image);
                
                demand_transform_job = new TransformationJob(this, zoomed,
                    backing_photo.get_pixel_transformer(), on_demand_transform_complete,
                    new Cancellable());
                demand_transform_zoom_state = zoom_state;
                workers.enqueue(demand_transform_job);
                
                return get_zoom_preview_image_internal(zoom_state);
            }
        }
        
        // if no on-demand background transform job is in progress at all, then start one
        if (demand_transform_job == null) {
            Gdk.Pixbuf zoomed = get_view_projection_pixbuf(zoom_state, iso_source_image,
                reduced_source_image);
            
            demand_transform_job = new TransformationJob(this, zoomed,
                backing_photo.get_pixel_transformer(), on_demand_transform_complete,
                new Cancellable());

            demand_transform_zoom_state = zoom_state;
            
            workers.enqueue(demand_transform_job);
            
            return get_zoom_preview_image_internal(zoom_state);
        }
        
        // execution should never reach this point -- the various nested conditionals above should
        // account for every possible case that can occur when the ZoomBuffer is in the
        // SOURCE-NOT-TRANSFORMED state. So if execution does reach this point, print a critical
        // warning to the console and just zoom using the preview image (the preview image, since
        // it's managed by the SinglePhotoPage that created us, is assumed to be good).
        critical("ZoomBuffer: get_zoomed_image( ): in SOURCE-NOT-TRANSFORMED but can't transform " +
            "on-screen projection on-demand; using preview image");
        return get_zoom_preview_image_internal(zoom_state);
    }

    public Gdk.Pixbuf get_zoom_preview_image_internal(ZoomState zoom_state) {
        if (object_state == ObjectState.SOURCE_NOT_LOADED) {
            BackgroundJob iso_source_fetch_job = new IsoSourceFetchJob(this, backing_photo,
                on_iso_source_fetch_complete);
            workers.enqueue(iso_source_fetch_job);

            object_state = ObjectState.SOURCE_LOAD_IN_PROGRESS;
        }
        Gdk.Rectangle view_rect = zoom_state.get_viewing_rectangle_wrt_content();
        Gdk.Rectangle view_rect_proj = zoom_state.get_viewing_rectangle_projection(
            preview_image);

        Gdk.Pixbuf proj_subpixbuf = new Gdk.Pixbuf.subpixbuf(preview_image,
            view_rect_proj.x, view_rect_proj.y, view_rect_proj.width, view_rect_proj.height);

        Gdk.Pixbuf zoomed = proj_subpixbuf.scale_simple(view_rect.width, view_rect.height,
            Gdk.InterpType.BILINEAR);
       
        return zoomed;
    }

    public Photo get_backing_photo() {
        return backing_photo;
    }
    
    public void update_preview_image(Gdk.Pixbuf preview_image) {
        this.preview_image = preview_image;
    }
    
    // invoke with no arguments or with null to merely flush the cache or alternatively pass in a
    // single zoom state argument to re-seed the cache for that zoom state after it's been flushed
    public void flush_demand_cache(ZoomState? initial_zoom_state = null) {
        demand_transform_cached_pixbuf = null;
        if (initial_zoom_state != null)
            get_zoomed_image(initial_zoom_state);
    }

    public Gdk.Pixbuf get_zoomed_image(ZoomState zoom_state) {
        is_interactive_redraw_in_progress = false;
        // if request is for a zoomed image with an interpolation factor of zero (i.e., no zooming
        // needs to be performed since the zoom slider is all the way to the left), then just
        // return the zoom preview image
        if (zoom_state.get_interpolation_factor() == 0.0) {
            return get_zoom_preview_image_internal(zoom_state);
        }
        
        switch (object_state) {
            case ObjectState.SOURCE_NOT_LOADED:
            case ObjectState.SOURCE_LOAD_IN_PROGRESS:
                return get_zoom_preview_image_internal(zoom_state);
            
            case ObjectState.SOURCE_NOT_TRANSFORMED:
                return get_zoomed_image_source_not_transformed(zoom_state);
            
            case ObjectState.TRANSFORMED_READY:
                // if an isomorphic, transformed pixbuf is ready, then just sample the projection of
                // current viewing window from it and return that.
                return get_view_projection_pixbuf(zoom_state, iso_transformed_image,
                    reduced_transformed_image);
            
            default:
                critical("ZoomBuffer: get_zoomed_image( ): object is an inconsistent state");
                return get_zoom_preview_image_internal(zoom_state);
        }
    }

    public Gdk.Pixbuf get_zoom_preview_image(ZoomState zoom_state) {
        is_interactive_redraw_in_progress = true;

        return get_zoom_preview_image_internal(zoom_state);
    }
}

public abstract class EditingHostPage : SinglePhotoPage {
    public const double ZOOM_INCREMENT_SIZE = 0.1;
    public const int PAN_INCREMENT_SIZE = 64; /* in pixels */
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
    private PixbufCache master_cache = null;
    private PhotoDragAndDropHandler dnd_handler = null;
    private bool enable_interactive_zoom_refresh = false;
    private Gdk.Point zoom_pan_start_point;
    private bool is_pan_in_progress = false;
    private double saved_slider_val = 0.0;
    private ZoomBuffer? zoom_buffer = null;
    
    public EditingHostPage(SourceCollection sources, string name) {
        base(name, false);
        
        this.sources = sources;
        
        // when photo is altered need to update it here
        sources.items_altered.connect(on_photos_altered);
        
        // set up page's toolbar (used by AppWindow for layout and FullscreenWindow as a popup)
        Gtk.Toolbar toolbar = get_toolbar();
        
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock("");
        rotate_button.set_icon_name(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.clicked.connect(on_rotate_clockwise);
        rotate_button.is_important = true;
        toolbar.insert(rotate_button, -1);
        
        // crop tool
        crop_button = new Gtk.ToggleToolButton.from_stock(Resources.CROP);
        crop_button.set_label(Resources.CROP_LABEL);
        crop_button.set_tooltip_text(Resources.CROP_TOOLTIP);
        crop_button.toggled.connect(on_crop_toggled);
        crop_button.is_important = true;
        toolbar.insert(crop_button, -1);

        // redeye reduction tool
        redeye_button = new Gtk.ToggleToolButton.from_stock(Resources.REDEYE);
        redeye_button.set_label(Resources.RED_EYE_LABEL);
        redeye_button.set_tooltip_text(Resources.RED_EYE_TOOLTIP);
        redeye_button.toggled.connect(on_redeye_toggled);
        redeye_button.is_important = true;
        toolbar.insert(redeye_button, -1);
        
        // adjust tool
        adjust_button = new Gtk.ToggleToolButton.from_stock(Resources.ADJUST);
        adjust_button.set_label(Resources.ADJUST_LABEL);
        adjust_button.set_tooltip_text(Resources.ADJUST_TOOLTIP);
        adjust_button.toggled.connect(on_adjust_toggled);
        adjust_button.is_important = true;
        toolbar.insert(adjust_button, -1);

        // enhance tool
        enhance_button = new Gtk.ToolButton.from_stock(Resources.ENHANCE);
        enhance_button.set_label(Resources.ENHANCE_LABEL);
        enhance_button.set_tooltip_text(Resources.ENHANCE_TOOLTIP);
        enhance_button.clicked.connect(on_enhance);
        enhance_button.is_important = true;
        toolbar.insert(enhance_button, -1);

        // separator to force next/prev buttons to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        toolbar.insert(separator, -1);
        
        Gtk.HBox zoom_group = new Gtk.HBox(false, 0);
        
        Gtk.Image zoom_out = new Gtk.Image.from_pixbuf(Resources.load_icon(Resources.ICON_ZOOM_OUT,
            Resources.ICON_ZOOM_SCALE));
        Gtk.EventBox zoom_out_box = new Gtk.EventBox();
        zoom_out_box.set_above_child(true);
        zoom_out_box.set_visible_window(false);
        zoom_out_box.add(zoom_out);

        zoom_out_box.button_press_event.connect(on_zoom_out_pressed);

        zoom_group.pack_start(zoom_out_box, false, false, 0);

        // zoom slider
        zoom_slider = new Gtk.HScale(new Gtk.Adjustment(0.0, 0.0, 1.1, 0.1, 0.1, 0.1));
        zoom_slider.set_draw_value(false);
        zoom_slider.set_size_request(120, -1);
        zoom_slider.value_changed.connect(on_zoom_slider_value_changed);
        zoom_slider.button_press_event.connect(on_zoom_slider_drag_begin);
        zoom_slider.button_release_event.connect(on_zoom_slider_drag_end);
        zoom_slider.key_press_event.connect(on_zoom_slider_key_press);

        zoom_group.pack_start(zoom_slider, false, false, 0);
        
        Gtk.Image zoom_in = new Gtk.Image.from_pixbuf(Resources.load_icon(Resources.ICON_ZOOM_IN,
            Resources.ICON_ZOOM_SCALE));
        Gtk.EventBox zoom_in_box = new Gtk.EventBox();
        zoom_in_box.set_above_child(true);
        zoom_in_box.set_visible_window(false);
        zoom_in_box.add(zoom_in);
        
        zoom_in_box.button_press_event.connect(on_zoom_in_pressed);

        zoom_group.pack_start(zoom_in_box, false, false, 0);

        Gtk.ToolItem group_wrapper = new Gtk.ToolItem();
        group_wrapper.add(zoom_group);

        toolbar.insert(group_wrapper, -1);

        // previous button
        prev_button.set_tooltip_text(_("Previous photo"));
        prev_button.clicked.connect(on_previous_photo);
        toolbar.insert(prev_button, -1);
        
        // next button
        next_button.set_tooltip_text(_("Next photo"));
        next_button.clicked.connect(on_next_photo);
        toolbar.insert(next_button, -1);
    }
    
    ~EditingHostPage() {
        sources.items_altered.disconnect(on_photos_altered);
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
            }
            repaint();
        }
        
        update_cursor_for_zoom_context();
    }

    private bool on_zoom_slider_drag_begin(Gdk.EventButton event) {
        enable_interactive_zoom_refresh = true;
        
        if (get_container() is FullscreenWindow)
            ((FullscreenWindow) get_container()).disable_toolbar_dismissal();

        return false;
    }

    private bool on_zoom_slider_drag_end(Gdk.EventButton event) {
        enable_interactive_zoom_refresh = false;

        if (get_container() is FullscreenWindow)
            ((FullscreenWindow) get_container()).enable_toolbar_dismissal();

        ZoomState zoom_state = ZoomState.rescale(get_zoom_state(), zoom_slider.get_value());
        set_zoom_state(zoom_state);
        
        repaint();

        return false;
    }

    private bool on_zoom_out_pressed(Gdk.EventButton event) {
        snap_zoom_to_min();
        return true;
    }
    
    private bool on_zoom_in_pressed(Gdk.EventButton event) {
        snap_zoom_to_max();
        return true;
    }

    private Gdk.Point get_cursor_wrt_viewport(Gdk.EventScroll event) {
        Gdk.Point cursor_wrt_canvas = {0};
        cursor_wrt_canvas.x = (int) event.x;
        cursor_wrt_canvas.y = (int) event.y;

        Gdk.Rectangle viewport_wrt_canvas = get_zoom_state().get_viewing_rectangle_wrt_screen();
        Gdk.Point result = {0};
        result.x = cursor_wrt_canvas.x - viewport_wrt_canvas.x;
        result.x = result.x.clamp(0, viewport_wrt_canvas.width);
        result.y = cursor_wrt_canvas.y - viewport_wrt_canvas.y;
        result.y = result.y.clamp(0, viewport_wrt_canvas.height);

        return result;
    }

    private Gdk.Point get_cursor_wrt_viewport_center(Gdk.EventScroll event) {
        Gdk.Point cursor_wrt_viewport = get_cursor_wrt_viewport(event);
        Gdk.Rectangle viewport_wrt_canvas = get_zoom_state().get_viewing_rectangle_wrt_screen();
        
        Gdk.Point viewport_center = {0};
        viewport_center.x = viewport_wrt_canvas.width / 2;
        viewport_center.y = viewport_wrt_canvas.height / 2;

        return subtract_points(cursor_wrt_viewport, viewport_center);
    }

    private Gdk.Point get_iso_pixel_under_cursor(Gdk.EventScroll event) {
        Gdk.Point viewport_center_iso = scale_point(get_zoom_state().get_viewport_center(),
            1.0 / get_zoom_state().get_zoom_factor());

        Gdk.Point cursor_wrt_center_iso = scale_point(get_cursor_wrt_viewport_center(event),
            1.0 / get_zoom_state().get_zoom_factor());

        return add_points(viewport_center_iso, cursor_wrt_center_iso);
    }

    private double snap_interpolation_factor(double interp) {
        if (interp < 0.03)
            interp = 0.0;
        else if (interp > 0.97)
            interp = 1.0;

        return interp;
    }

    private double adjust_interpolation_factor(double adjustment) {
        return snap_interpolation_factor(get_zoom_state().get_interpolation_factor() + adjustment);
    }

    private void zoom_about_event_cursor_point(Gdk.EventScroll event, double zoom_increment) {
        if (photo_missing)
            return;

        Gdk.Point cursor_wrt_viewport_center = get_cursor_wrt_viewport_center(event);
        Gdk.Point iso_pixel_under_cursor = get_iso_pixel_under_cursor(event);
    
        double interp = adjust_interpolation_factor(zoom_increment);
        zoom_slider.value_changed.disconnect(on_zoom_slider_value_changed);
        zoom_slider.set_value(interp);
        zoom_slider.value_changed.connect(on_zoom_slider_value_changed);

        ZoomState new_zoom_state = ZoomState.rescale(get_zoom_state(), interp);

        if (new_zoom_state.is_min()) {
            cancel_zoom();
            update_cursor_for_zoom_context();
            repaint();
            return;
        }

        Gdk.Point new_zoomed_old_cursor = scale_point(iso_pixel_under_cursor,
            new_zoom_state.get_zoom_factor());
        Gdk.Point desired_new_viewport_center = subtract_points(new_zoomed_old_cursor,
            cursor_wrt_viewport_center);

        new_zoom_state = ZoomState.pan(new_zoom_state, desired_new_viewport_center);

        set_zoom_state(new_zoom_state);
        repaint();

        update_cursor_for_zoom_context();
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
            case "equal":
            case "plus":
            case "KP_Add":
                on_increase_size();
                return true;
            
            case "minus":
            case "underscore":
            case "KP_Subtract":
                on_decrease_size();
                return true;
            
            case "KP_Divide":
                snap_zoom_to_isomorphic();
                return true;

            case "KP_Multiply":
                snap_zoom_to_min();
                return true;
        }

        return false;
    }

    protected virtual void on_increase_size() {
        zoom_slider.set_value(adjust_interpolation_factor(ZOOM_INCREMENT_SIZE));
    }
    
    protected virtual void on_decrease_size() {
        zoom_slider.set_value(adjust_interpolation_factor(-ZOOM_INCREMENT_SIZE));
    }

    protected override void save_zoom_state() {
        base.save_zoom_state();
        saved_slider_val = zoom_slider.get_value();
    }

    protected override ZoomBuffer? get_zoom_buffer() {
        return zoom_buffer;
    }
    
    protected override bool on_mousewheel_up(Gdk.EventScroll event) {
        if (get_zoom_state().is_max() || !zoom_slider.get_sensitive())
            return false;

        zoom_about_event_cursor_point(event, ZOOM_INCREMENT_SIZE);
        return false;
    }
    
    protected override bool on_mousewheel_down(Gdk.EventScroll event) {
        if (get_zoom_state().is_min() || !zoom_slider.get_sensitive())
            return false;
        
        zoom_about_event_cursor_point(event, -ZOOM_INCREMENT_SIZE);
        return false;
    }

    protected override void restore_zoom_state() {
        base.restore_zoom_state();

        zoom_slider.value_changed.disconnect(on_zoom_slider_value_changed);
        zoom_slider.set_value(saved_slider_val);
        zoom_slider.value_changed.connect(on_zoom_slider_value_changed);
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
    
    public Photo? get_photo() {
        // use the photo stored in our ViewCollection ... should either be zero or one in the
        // collection at all times
        assert(get_view().get_count() <= 1);
        
        return (get_view().get_count() > 0)
            ? (Photo?) ((PhotoView) get_view().get_at(0)).get_source()
            : null;
    }
    
    private void set_photo(Photo photo) {
        zoom_slider.value_changed.disconnect(on_zoom_slider_value_changed);
        zoom_slider.set_value(0.0);
        zoom_slider.value_changed.connect(on_zoom_slider_value_changed);

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

        get_view().clear();
    }
    
    public override void switching_to_fullscreen(FullscreenWindow fsw) {
        base.switching_to_fullscreen(fsw);
        
        deactivate_tool();
        
        cancel_zoom();
        is_pan_in_progress = false;
        
        Page page = fsw.get_current_page();
        if (page != null)
            page.get_view().items_selected.connect(on_selection_changed);
    }
    
    public override void returning_from_fullscreen(FullscreenWindow fsw) {
        base.returning_from_fullscreen(fsw);
        
        repaint();
        
        Page page = fsw.get_current_page();
        if (page != null)
            page.get_view().items_selected.disconnect(on_selection_changed);
    }
    
    private void on_selection_changed(Gee.Iterable<DataView> selected) {
        foreach (DataView view in selected) {
            replace_photo(controller, (Photo) view.get_source());
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
            cache.fetched.disconnect(on_pixbuf_fetched);
            cache.cancel_all();
        }
        
        cache = new PixbufCache(sources, PixbufCache.PhotoType.BASELINE, scaling, PIXBUF_CACHE_COUNT);
        cache.fetched.connect(on_pixbuf_fetched);
        
        master_cache = new PixbufCache(sources, PixbufCache.PhotoType.MASTER, scaling, 
            ORIGINAL_PIXBUF_CACHE_COUNT, master_cache_filter);
        
        if (has_photo())
            prefetch_neighbors(controller, get_photo());
    }
    
    private bool master_cache_filter(Photo photo) {
        return photo.has_transformations() || photo.has_editable();
    }
    
    private void on_pixbuf_fetched(Photo photo, Gdk.Pixbuf? pixbuf, Error? err) {
        // if not of the current photo, nothing more to do
        if (!photo.equals(get_photo()))
            return;

        if (pixbuf != null) {
            // update the preview image in the zoom buffer
            if ((zoom_buffer != null) && (zoom_buffer.get_backing_photo() == photo))
                zoom_buffer.update_preview_image(pixbuf);

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
            
            notify_photo_backing_missing((Photo) photo, false);
        } else if (err != null) {
            // this call merely updates the UI, and can be called indiscriminantly, whether or not
            // the photo is actually missing
            set_photo_missing(true);
            
            // this call should only be used when we're sure the photo is missing
            notify_photo_backing_missing((Photo) photo, true);
        }
    }
    
    private void prefetch_neighbors(ViewCollection controller, Photo photo) {
        PixbufCache.PixbufCacheBatch normal_batch = new PixbufCache.PixbufCacheBatch();
        PixbufCache.PixbufCacheBatch master_batch = new PixbufCache.PixbufCacheBatch();
        
        normal_batch.set(BackgroundJob.JobPriority.HIGHEST, photo);
        master_batch.set(BackgroundJob.JobPriority.LOW, photo);
        
        DataSource next_source, prev_source;
        if (!controller.get_immediate_neighbors(photo, out next_source, out prev_source))
            return;
        
        Photo next = (Photo) next_source;
        Photo prev = (Photo) prev_source;
        
        // prefetch the immediate neighbors and their outer neighbors, for plenty of readahead
        foreach (DataSource neighbor_source in controller.get_extended_neighbors(photo)) {
            Photo neighbor = (Photo) neighbor_source;
            
            BackgroundJob.JobPriority priority = BackgroundJob.JobPriority.NORMAL;
            if (neighbor.equals(next) || neighbor.equals(prev))
                priority = BackgroundJob.JobPriority.HIGH;
            
            normal_batch.set(priority, neighbor);
            master_batch.set(BackgroundJob.JobPriority.LOWEST, neighbor);
        }
        
        cache.prefetch_batch(normal_batch);
        master_cache.prefetch_batch(master_batch);
    }
    
    // Cancels prefetches of old neighbors, but does not cancel them if they are the new
    // neighbors
    private void cancel_prefetch_neighbors(ViewCollection old_controller, Photo old_photo,
        ViewCollection new_controller, Photo new_photo) {
        Gee.Set<Photo> old_neighbors = (Gee.Set<Photo>)
            old_controller.get_extended_neighbors(old_photo);
        Gee.Set<Photo> new_neighbors = (Gee.Set<Photo>)
            new_controller.get_extended_neighbors(new_photo);
        
        foreach (Photo old_neighbor in old_neighbors) {
            // cancel prefetch and drop from cache if old neighbor is not part of the new
            // neighborhood
            if (!new_neighbors.contains(old_neighbor) && !new_photo.equals(old_neighbor)) {
                cache.drop(old_neighbor);
                master_cache.drop(old_neighbor);
            }
        }
        
        // do same for old photo
        if (!new_neighbors.contains(old_photo) && !new_photo.equals(old_photo)) {
            cache.drop(old_photo);
            master_cache.drop(old_photo);
        }
    }
    
    protected void display(ViewCollection controller, Photo photo) {
        assert(controller.get_view_for_source(photo) != null);
        
        replace_photo(controller, photo);
    }

    protected virtual void update_ui(Photo photo, bool missing) {
        bool sensitivity = !missing;
        
        rotate_button.sensitive = sensitivity;
        crop_button.sensitive = sensitivity;
        redeye_button.sensitive = sensitivity;
        adjust_button.sensitive = sensitivity;
        enhance_button.sensitive = sensitivity;
        zoom_slider.sensitive = sensitivity;
        
        deactivate_tool();
    }
    
    // This should only be called when it's known that the photo is actually missing.
    protected virtual void notify_photo_backing_missing(Photo photo, bool missing) {
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

    // This method can be called indiscriminantly, whether or not the backing is actually present.
    protected void set_photo_missing(bool missing) {
        if (photo_missing == missing)
            return;
        
        photo_missing = missing;
        
        Photo? photo = get_photo();
        if (photo == null)
            return;
        
        update_ui(photo, missing);
        
        if (photo_missing) {
            try {
                Gdk.Pixbuf pixbuf = photo.get_preview_pixbuf(get_canvas_scaling());
                
                pixbuf = pixbuf.composite_color_simple(pixbuf.get_width(), pixbuf.get_height(),
                    Gdk.InterpType.NEAREST, 100, 2, 0, 0);
                
                set_pixbuf(pixbuf, photo.get_dimensions());
            } catch (GLib.Error err) {
                warning("%s", err.message);
            }
        }
    }

    public bool get_photo_missing() {
        return photo_missing;
    }

    protected virtual bool confirm_replace_photo(Photo? old_photo, Photo new_photo) {
        return true;
    }

    protected void replace_photo(ViewCollection new_controller, Photo new_photo) {
        ViewCollection old_controller = this.controller;
        controller = new_controller;
        
        // if it's the same Photo object, the scaling hasn't changed, and the photo's file
        // has not gone missing or re-appeared, there's nothing to do otherwise,
        // just need to reload the image for the proper scaling. Of course, the photo's pixels
        // might've changed, so rebuild the zoom buffer.
        if (new_photo.equals(get_photo()) && !pixbuf_dirty && !photo_missing) {
            zoom_buffer = new ZoomBuffer(this, new_photo, cache.get_ready_pixbuf(new_photo));
            return;
        }

        // only check if okay to replace if there's something to replace and someone's concerned
        if (has_photo() && !new_photo.equals(get_photo()) && confirm_replace_photo != null) {
            if (!confirm_replace_photo(get_photo(), new_photo))
                return;
        }

        deactivate_tool();
        
        // swap out new photo and old photo and process change
        Photo old_photo = get_photo();
        set_photo(new_photo);
        set_page_name(new_photo.get_name());

        // clear out the swap buffer
        swapped = null;

        // reset flags
        set_photo_missing(false);
        pixbuf_dirty = true;

        update_toolbar();

        // it's possible for this to be called prior to the page being realized, however, the
        // underlying canvas has a scaling, so use that
        rebuild_caches("replace_photo");
        
        if (old_photo != null)
            cancel_prefetch_neighbors(old_controller, old_photo, new_controller, new_photo);

        cancel_zoom();

        Gdk.Pixbuf? zoom_preview_pixbuf = cache.get_ready_pixbuf(new_photo);
        if (zoom_preview_pixbuf == null) {
            try {
                zoom_preview_pixbuf = new_photo.get_preview_pixbuf(get_canvas_scaling());
            } catch (Error err) {
                warning("%s", err.message);
            }
        }
        zoom_buffer = new ZoomBuffer(this, new_photo, zoom_preview_pixbuf);

        quick_update_pixbuf();
        
        prefetch_neighbors(new_controller, new_photo);
    }
    
    protected override void cancel_zoom() {
        base.cancel_zoom();

        zoom_slider.value_changed.disconnect(on_zoom_slider_value_changed);
        zoom_slider.set_value(0.0);
        zoom_slider.value_changed.connect(on_zoom_slider_value_changed);

        set_zoom_state(ZoomState(get_photo().get_dimensions(), get_drawable_dim(), 0.0));

        // when cancelling zoom, panning becomes impossible, so set the cursor back to
        // a left pointer in case it had been a hand-grip cursor indicating that panning
        // was possible; the null guards are required because zoom can be cancelled at
        // any time
        if (canvas != null && canvas.window != null)
            set_page_cursor(Gdk.CursorType.LEFT_PTR);
        
        repaint();
    }
    
    private void quick_update_pixbuf() {
        Gdk.Pixbuf? pixbuf = cache.get_ready_pixbuf(get_photo());
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
        
        Photo? photo = get_photo();
        if (photo == null)
            return false;
        
        Gdk.Pixbuf pixbuf = null;
        Dimensions max_dim = photo.get_dimensions();
        
        try {
            if (current_tool != null)
                pixbuf = current_tool.get_display_pixbuf(get_canvas_scaling(), photo, out max_dim);
        } catch (Error err) {
            warning("%s", err.message);
            set_photo_missing(true);
        }
        
        if (!photo_missing) {
            // if no pixbuf, see if it's waiting in the cache
            if (pixbuf == null)
                pixbuf = cache.get_ready_pixbuf(photo);
            
            // if still no pixbuf, background fetch and let the signal handler update the display
            if (pixbuf == null)
                cache.prefetch(photo);
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
    
    protected override void on_resize(Gdk.Rectangle rect) {
        base.on_resize(rect);

        track_tool_window();
    }
    
    protected override void on_resize_finished(Gdk.Rectangle rect) {
        // because we've loaded SinglePhotoPage with an image scaled to window size, as the window
        // is resized it scales that, which pixellates, especially scaling upward.  Once the window
        // resize is complete, we get a fresh image for the new window's size
        rebuild_caches("on_resize_finished");
        pixbuf_dirty = true;
        
        update_pixbuf();
    }
    
    private void update_toolbar() {
        bool multiple = controller.get_count() > 1;

        prev_button.sensitive = multiple;
        next_button.sensitive = multiple;
        
        Photo photo = get_photo();
        Scaling scaling = get_canvas_scaling();
        
        rotate_button.sensitive = photo != null ? is_rotate_available(photo) : false;
        crop_button.sensitive = photo != null ? CropTool.is_available(photo, scaling) : false;
        redeye_button.sensitive = photo != null ? RedeyeTool.is_available(photo, scaling) : false;
        adjust_button.sensitive = photo != null ? AdjustTool.is_available(photo, scaling) : false;
        enhance_button.sensitive = photo != null ? is_enhance_available(photo) : false;
    }
    
    protected override bool on_shift_pressed(Gdk.EventKey? event) {
        // show quick compare of original only if no tool is in use, the original pixbuf is handy
        if (current_tool == null && !get_ctrl_pressed() && !get_alt_pressed())
            swap_in_original();
        
        return base.on_shift_pressed(event);
    }
    
    protected override bool on_shift_released(Gdk.EventKey? event) {
        if (current_tool == null)
            swap_out_original();
        
        return base.on_shift_released(event);
    }

    protected override bool on_alt_pressed(Gdk.EventKey? event) {
        if (current_tool == null)
            swap_out_original();
        
        return base.on_alt_pressed(event);
    }
    
    protected override bool on_alt_released(Gdk.EventKey? event) {
        if (current_tool == null && get_shift_pressed() && !get_ctrl_pressed())
            swap_in_original();
        
        return base.on_alt_released(event);
    }

    private void swap_in_original() {
        Gdk.Pixbuf? original = master_cache.get_ready_pixbuf(get_photo());
        if (original == null)
            return;
        
        // store what's currently displayed only for the duration of the shift pressing
        swapped = get_unscaled_pixbuf();

        // save the zoom state and cancel zoom so that the user can see all of the original
        // photo
        if (zoom_slider.get_value() != 0.0) {
            save_zoom_state();
            cancel_zoom();
        }
        
        set_pixbuf(original, get_photo().get_master_dimensions());
    }

    private void swap_out_original() {
        if (swapped != null) {
            set_pixbuf(swapped, get_photo().get_dimensions());
            
            restore_zoom_state();
            update_cursor_for_zoom_context();
            
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
            suspend_cursor_hiding();

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
            get_zoom_buffer().flush_demand_cache(zoom_state);

            is_pan_in_progress = false;
            restore_cursor_hiding();
        }

        // report all releases, as it's possible the user click and dragged from inside the
        // pixbuf to the gutters
        if (current_tool != null)
            current_tool.on_left_released((int) event.x, (int) event.y);
        
        return false;
    }
    
    protected override bool on_right_click(Gdk.EventButton event) {
        return on_context_buttonpress(event);
    }
    
    private void on_photos_altered(Gee.Map<DataObject, Alteration> map) {
        if (!map.has_key(get_photo()))
            return;
        
        pixbuf_dirty = true;
        
        // if transformed, want to prefetch the original pixbuf for this photo, but after the
        // signal is completed as PixbufCache may remove it in this round of fired signals
        if (get_photo().has_transformations())
            Idle.add(on_fetch_original);
        
        update_toolbar();
    }
    
    private bool on_fetch_original() {
        if (has_photo())
            master_cache.prefetch(get_photo(), BackgroundJob.JobPriority.LOW);
        
        return false;
    }
    
    private bool is_panning_possible() {
        // panning is impossible if all the content to be drawn completely fits on the drawing
        // canvas
        Dimensions content_dim = {0};
        content_dim.width = get_zoom_state().get_zoomed_width();
        content_dim.height = get_zoom_state().get_zoomed_height();
        Dimensions canvas_dim = get_drawable_dim();

        return (!(canvas_dim.width >= content_dim.width && canvas_dim.height >= content_dim.height));
    }
    
    private void update_cursor_for_zoom_context() {
        if (is_panning_possible())
            set_page_cursor(Gdk.CursorType.FLEUR);
        else
            set_page_cursor(Gdk.CursorType.LEFT_PTR);
    }
    
    // Return true to block the DnD handler from activating a drag
    protected override bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        if (current_tool != null) {
            current_tool.on_motion(x, y, mask);
            return true;
        }
        
        update_cursor_for_zoom_context();
        
        if (is_pan_in_progress) {
            int delta_x = ((int) event.x) - zoom_pan_start_point.x;
            int delta_y = ((int) event.y) - zoom_pan_start_point.y;

            Gdk.Point viewport_center = get_zoom_state().get_viewport_center();
            viewport_center.x -= delta_x;
            viewport_center.y -= delta_y;

            ZoomState zoom_state = ZoomState.pan(get_zoom_state(), viewport_center);

            on_interactive_pan(zoom_state);
            return true;
        }
        
        return base.on_motion(event, x, y, mask);
    }
    
    private void track_tool_window() {
        // if editing tool window is present and the user hasn't touched it, it moves with the window
        if (current_tool != null) {
            EditingToolWindow tool_window = current_tool.get_tool_window();
            if (tool_window != null && !tool_window.has_user_moved())
                place_tool_window();
        }
    }
    
    protected override void on_move(Gdk.Rectangle rect) {
        track_tool_window();
        
        base.on_move(rect);
    }
    
    private bool on_keyboard_pan_event(Gdk.EventKey event) {
        ZoomState current_zoom_state = get_zoom_state();
        Gdk.Point viewport_center = current_zoom_state.get_viewport_center();

        switch (Gdk.keyval_name(event.keyval)) {
            case "Left":
            case "KP_Left":
            case "KP_4":
                viewport_center.x -= PAN_INCREMENT_SIZE;
            break;
            
            case "Right":
            case "KP_Right":
            case "KP_6":
                viewport_center.x += PAN_INCREMENT_SIZE;
            break;

            case "Down":
            case "KP_Down":
            case "KP_2":
                viewport_center.y += PAN_INCREMENT_SIZE;
            break;
            
            case "Up":
            case "KP_Up":
            case "KP_8":
                viewport_center.y -= PAN_INCREMENT_SIZE;
            break;
            
            default:
                return false;
        }

        ZoomState new_zoom_state = ZoomState.pan(current_zoom_state, viewport_center);
        set_zoom_state(new_zoom_state);
        repaint();

        return true;
    }
    
    public override bool key_press_event(Gdk.EventKey event) {
        // editing tool gets first crack at the keypress
        if (current_tool != null) {
            if (current_tool.on_keypress(event))
                return true;
        }
        
        // if panning is possible, the pan handler (on MUNI?) gets second crack at the keypress
        if (is_panning_possible()) {
            if (on_keyboard_pan_event(event))
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
    
    public bool is_rotate_available(Photo photo) {
        return !photo_missing;
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
    
    public void on_flip_horizontally() {
        rotate(Rotation.MIRROR, Resources.HFLIP_LABEL, Resources.HFLIP_TOOLTIP);
    }
    
    public void on_flip_vertically() {
        rotate(Rotation.UPSIDE_DOWN, Resources.VFLIP_LABEL, Resources.VFLIP_TOOLTIP);
    }
    
    public void on_revert() {
        if (photo_missing)
            return;

        deactivate_tool();
        
        if (!has_photo())
            return;

        if (get_photo().has_editable()) {
            if (!revert_editable_dialog(AppWindow.get_instance(), 
                (Gee.Collection<Photo>) get_view().get_sources())) {
                return;
            }
            
            get_photo().revert_to_master();
        }
        
        cancel_zoom();

        set_photo_missing(false);
        
        RevertSingleCommand command = new RevertSingleCommand(get_photo());
        get_command_manager().execute(command);
    }
    
    public void on_edit_title() {
        LibraryPhoto item;
        if (get_photo() is LibraryPhoto)
            item = get_photo() as LibraryPhoto;
        else
            return;
        
        EditTitleDialog edit_title_dialog = new EditTitleDialog(item.get_title());
        string? new_title = edit_title_dialog.execute();
        if (new_title == null)
            return;
        
        EditTitleCommand command = new EditTitleCommand(item, new_title);
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

    protected override bool on_ctrl_pressed(Gdk.EventKey? event) {
        rotate_button.set_icon_name(Resources.COUNTERCLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CCW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CCW_TOOLTIP);
        rotate_button.clicked.disconnect(on_rotate_clockwise);
        rotate_button.clicked.connect(on_rotate_counterclockwise);
        
        if (current_tool == null)
            swap_out_original();

        return base.on_ctrl_pressed(event);
    }
    
    protected override bool on_ctrl_released(Gdk.EventKey? event) {
        rotate_button.set_icon_name(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.clicked.disconnect(on_rotate_counterclockwise);
        rotate_button.clicked.connect(on_rotate_clockwise);

        if (current_tool == null && get_shift_pressed() && !get_alt_pressed())
            swap_in_original();
        
        return base.on_ctrl_released(event);
    }
    
    private void on_tool_button_toggled(Gtk.ToggleToolButton toggle, EditingTool.Factory factory) {
        // if the button is an activate, deactivate any current tool running; if the button is
        // a deactivate, deactivate the current tool and exit
        bool deactivating_only = (!toggle.active && current_editing_toggle == toggle);
        deactivate_tool();
        
        if (deactivating_only) {
            restore_cursor_hiding();
            return;
        }
        
        suspend_cursor_hiding();

        current_editing_toggle = toggle;
        
        // create the tool, hook its signals, and activate
        EditingTool tool = factory();
        tool.activated.connect(on_tool_activated);
        tool.deactivated.connect(on_tool_deactivated);
        tool.applied.connect(on_tool_applied);
        tool.cancelled.connect(on_tool_cancelled);
        tool.aborted.connect(on_tool_aborted);
        
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
    
    public bool is_enhance_available(Photo photo) {
        return !photo_missing;
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

        // we need both show & present so we get keyboard focus in metacity, but due to a bug in
        // compiz, we only want to show the window. 
        // ticket #2141 prompted this: http://trac.yorba.org/ticket/2141
        tool_window.show();
        if (!get_window_manager().contains("compiz"))
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

        Photo next_photo = next.get_source() as Photo;
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
        
        Photo previous_photo = previous.get_source() as Photo;
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
        
        // Adds one menu entry per alien database driver
        AlienDatabaseHandler.get_instance().add_menu_entries(
            ui, "/PhotoMenuBar/FileMenu/ImportFromAlienDbPlaceholder"
        );
        
        context_menu = (Gtk.Menu) ui.get_widget("/PhotoContextMenu");
        
        // monitor view to update UI elements
        get_view().items_altered.connect(on_photos_altered);
        
        // watch for photos being destroyed or altered, either here or in other pages
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
        LibraryPhoto.global.items_altered.connect(on_metadata_altered);
        
        // watch for updates to the external app settings
        Config.get_instance().external_app_changed.connect(on_external_app_changed);
    }
    
    ~LibraryPhotoPage() {
        LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
        LibraryPhoto.global.items_altered.disconnect(on_metadata_altered);
        Config.get_instance().external_app_changed.disconnect(on_external_app_changed);
    }
    
    protected override string? get_menubar_path() {
        return "/PhotoMenuBar";
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("photo.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, null };
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
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, null };
        edit.label = _("_Edit");
        actions += edit;
        
        Gtk.ActionEntry remove_from_library = { "RemoveFromLibrary", Gtk.STOCK_REMOVE, TRANSLATABLE,
            "<Shift>Delete", TRANSLATABLE, on_remove_from_library };
        remove_from_library.label = Resources.REMOVE_FROM_LIBRARY_MENU;
        remove_from_library.tooltip = Resources.REMOVE_FROM_LIBRARY_SINGULAR_TOOLTIP;
        actions += remove_from_library;

        Gtk.ActionEntry move_to_trash = { "MoveToTrash", "user-trash-full", TRANSLATABLE, "Delete",
            TRANSLATABLE, on_move_to_trash };
        move_to_trash.label = Resources.MOVE_TO_TRASH_MENU;
        move_to_trash.tooltip = Resources.MOVE_TO_TRASH_SINGULAR_TOOLTIP;
        actions += move_to_trash;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, on_view_menu };
        view.label = _("_View");
        actions += view;
        
        Gtk.ActionEntry photo = { "PhotoMenu", null, TRANSLATABLE, null, null, null };
        photo.label = _("_Photo");
        actions += photo;
        
        Gtk.ActionEntry tools = { "Tools", null, TRANSLATABLE, null, null, null };
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

        Gtk.ActionEntry hflip = { "FlipHorizontally", Resources.HFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_horizontally };
        hflip.label = Resources.HFLIP_MENU;
        hflip.tooltip = Resources.HFLIP_TOOLTIP;
        actions += hflip;
        
        Gtk.ActionEntry vflip = { "FlipVertically", Resources.VFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_vertically };
        vflip.label = Resources.VFLIP_MENU;
        vflip.tooltip = Resources.VFLIP_TOOLTIP;
        actions += vflip;
        
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
        
        Gtk.ActionEntry edit_title = { "EditTitle", null, TRANSLATABLE, "F2", TRANSLATABLE,
            on_edit_title };
        edit_title.label = Resources.EDIT_TITLE_MENU;
        edit_title.tooltip = Resources.EDIT_TITLE_TOOLTIP;
        actions += edit_title;

        Gtk.ActionEntry adjust_date_time = { "AdjustDateTime", null, TRANSLATABLE, null,
            TRANSLATABLE, on_adjust_date_time };
        adjust_date_time.label = Resources.ADJUST_DATE_TIME_MENU;
        adjust_date_time.tooltip = Resources.ADJUST_DATE_TIME_TOOLTIP;
        actions += adjust_date_time;
        
        Gtk.ActionEntry external_edit = { "ExternalEdit", Gtk.STOCK_EDIT, TRANSLATABLE,
            "<Ctrl>Return", TRANSLATABLE, on_external_edit };
        external_edit.label = Resources.EXTERNAL_EDIT_MENU;
        external_edit.tooltip = Resources.EXTERNAL_EDIT_TOOLTIP;
        actions += external_edit;

#if !NO_RAW
        Gtk.ActionEntry edit_raw = { "ExternalEditRAW", null, TRANSLATABLE, "<Ctrl><Shift>Return", 
            TRANSLATABLE, on_external_edit_raw };
        edit_raw.label = Resources.EXTERNAL_EDIT_RAW_MENU;
        edit_raw.tooltip = Resources.EXTERNAL_EDIT_RAW_TOOLTIP;
        actions += edit_raw;
#endif
        
#if !NO_SET_BACKGROUND
        Gtk.ActionEntry set_background = { "SetBackground", null, TRANSLATABLE, "<Ctrl>B",
            TRANSLATABLE, on_set_background };
        set_background.label = Resources.SET_BACKGROUND_MENU;
        set_background.tooltip = Resources.SET_BACKGROUND_TOOLTIP;
        actions += set_background;
#endif

        Gtk.ActionEntry set_rating = { "Rate", null, TRANSLATABLE, null, null, null };
        set_rating.label = Resources.RATING_MENU;
        actions += set_rating;

        Gtk.ActionEntry increase_rating = { "IncreaseRating", null, TRANSLATABLE, 
            "greater", TRANSLATABLE, on_increase_rating };
        increase_rating.label = Resources.INCREASE_RATING_MENU;
        increase_rating.tooltip = Resources.INCREASE_RATING_TOOLTIP;
        actions += increase_rating;

        Gtk.ActionEntry decrease_rating = { "DecreaseRating", null, TRANSLATABLE, 
            "less", TRANSLATABLE, on_decrease_rating };
        decrease_rating.label = Resources.DECREASE_RATING_MENU;
        decrease_rating.tooltip = Resources.DECREASE_RATING_TOOLTIP;
        actions += decrease_rating;

        Gtk.ActionEntry rate_rejected = { "RateRejected", null, TRANSLATABLE, 
            "9", TRANSLATABLE, on_rate_rejected };
        rate_rejected.label = Resources.rating_menu(Rating.REJECTED);
        rate_rejected.tooltip = Resources.rating_tooltip(Rating.REJECTED);
        actions += rate_rejected;

        Gtk.ActionEntry rate_unrated = { "RateUnrated", null, TRANSLATABLE, 
            "0", TRANSLATABLE, on_rate_unrated };
        rate_unrated.label = Resources.rating_menu(Rating.UNRATED);
        rate_unrated.tooltip = Resources.rating_tooltip(Rating.UNRATED);
        actions += rate_unrated;

        Gtk.ActionEntry rate_one = { "RateOne", null, TRANSLATABLE, 
            "1", TRANSLATABLE, on_rate_one };
        rate_one.label = Resources.rating_menu(Rating.ONE);
        rate_one.tooltip = Resources.rating_tooltip(Rating.ONE);
        actions += rate_one;

        Gtk.ActionEntry rate_two = { "RateTwo", null, TRANSLATABLE, 
            "2", TRANSLATABLE, on_rate_two };
        rate_two.label = Resources.rating_menu(Rating.TWO);
        rate_two.tooltip = Resources.rating_tooltip(Rating.TWO);
        actions += rate_two;

        Gtk.ActionEntry rate_three = { "RateThree", null, TRANSLATABLE, 
            "3", TRANSLATABLE, on_rate_three };
        rate_three.label = Resources.rating_menu(Rating.THREE);
        rate_three.tooltip = Resources.rating_tooltip(Rating.THREE);
        actions += rate_three;

        Gtk.ActionEntry rate_four = { "RateFour", null, TRANSLATABLE, 
            "4", TRANSLATABLE, on_rate_four };
        rate_four.label = Resources.rating_menu(Rating.FOUR);
        rate_four.tooltip = Resources.rating_tooltip(Rating.FOUR);
        actions += rate_four;

        Gtk.ActionEntry rate_five = { "RateFive", null, TRANSLATABLE, 
            "5", TRANSLATABLE, on_rate_five };
        rate_five.label = Resources.rating_menu(Rating.FIVE);
        rate_five.tooltip = Resources.rating_tooltip(Rating.FIVE);
        actions += rate_five;

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

        Gtk.ActionEntry best_fit = { "ZoomFit", Gtk.STOCK_ZOOM_FIT, TRANSLATABLE,
            "<Ctrl>0", TRANSLATABLE, snap_zoom_to_min };
        best_fit.label = _("Fit to _Page");
        best_fit.tooltip = _("Zoom the photo to fit on the screen");
        actions += best_fit;

        Gtk.ActionEntry actual_size = { "Zoom100", Gtk.STOCK_ZOOM_100, TRANSLATABLE,
            "<Ctrl>1", TRANSLATABLE, snap_zoom_to_isomorphic };
        actual_size.label = _("Zoom _100%");
        actual_size.tooltip = _("Zoom the photo to 100% magnification");
        actions += actual_size;
        
        Gtk.ActionEntry max_size = { "Zoom200", null, TRANSLATABLE,
            "<Ctrl>2", TRANSLATABLE, snap_zoom_to_max };
        max_size.label = _("Zoom _200%");
        max_size.tooltip = _("Zoom the photo to 200% magnification");
        actions += max_size;

        Gtk.ActionEntry tags = { "TagsMenu", null, TRANSLATABLE, null, null, null };
        tags.label = _("Ta_gs");
        actions += tags;
        
        Gtk.ActionEntry add_tags = { "AddTags", null, TRANSLATABLE, "<Ctrl>T", TRANSLATABLE, 
            on_add_tags };
        add_tags.label = Resources.ADD_TAGS_MENU;
        add_tags.tooltip = Resources.ADD_TAGS_TOOLTIP;
        actions += add_tags;
        
        Gtk.ActionEntry modify_tags = { "ModifyTags", null, TRANSLATABLE, "<Ctrl>M", TRANSLATABLE, 
            on_modify_tags };
        modify_tags.label = Resources.MODIFY_TAGS_MENU;
        modify_tags.tooltip = Resources.MODIFY_TAGS_TOOLTIP;
        actions += modify_tags;
        
        Gtk.ActionEntry slideshow = { "Slideshow", Gtk.STOCK_MEDIA_PLAY, TRANSLATABLE, "F5",
            TRANSLATABLE, on_slideshow };
        slideshow.label = _("_Slideshow");
        slideshow.tooltip = _("Play a slideshow");
        actions += slideshow;
        
        return actions;
    }
    
    protected override Gtk.ToggleActionEntry[] init_collect_toggle_action_entries() {
        Gtk.ToggleActionEntry[] toggle_actions = base.init_collect_toggle_action_entries();
        
        Gtk.ToggleActionEntry ratings = { "ViewRatings", null, TRANSLATABLE, "<Ctrl><Shift>R",
            TRANSLATABLE, on_display_ratings, Config.get_instance().get_display_photo_ratings() };
        ratings.label = Resources.VIEW_RATINGS_MENU;
        ratings.tooltip = Resources.VIEW_RATINGS_TOOLTIP;
        toggle_actions += ratings;
        
        return toggle_actions;
    }
    
    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();
        
#if !NO_PRINTING
        InjectionGroup print_group = new InjectionGroup("/PhotoMenuBar/FileMenu/PrintPlaceholder");
        print_group.add_menu_item("PageSetup");
        print_group.add_menu_item("Print");
        
        groups += print_group;
#endif
        
#if !NO_PUBLISHING
        InjectionGroup publish_group = new InjectionGroup("/PhotoMenuBar/FileMenu/PublishPlaceholder");
        publish_group.add_menu_item("Publish");
        
        groups += publish_group;
#endif
        
#if !NO_SET_BACKGROUND
        InjectionGroup bg_group = new InjectionGroup("/PhotoMenuBar/FileMenu/SetBackgroundPlaceholder");
        bg_group.add_menu_item("SetBackground");
        
        groups += bg_group;
#endif
        
        return groups;
    }
    
    private void on_display_ratings(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_ratings(display);
        
        Config.get_instance().set_display_photo_ratings(display);
        repaint();
    }

    private void set_display_ratings(bool display) {
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewRatings");
        if (action != null)
            action.set_active(display);
    }
    
    protected override void update_actions(int selected_count, int count) {
        bool multiple = (get_controller() != null) ? get_controller().get_count() > 1 : false;
        bool rotate_possible = has_photo() ? is_rotate_available(get_photo()) : false;
#if !NO_RAW
        bool is_raw = has_photo() && get_photo().get_master_file_format() == PhotoFileFormat.RAW;
#endif
        
        set_action_sensitive("ExternalEdit",
            has_photo() && Config.get_instance().get_external_photo_app() != "");
        
        set_action_sensitive("Revert", has_photo() ?
            (get_photo().has_transformations() || get_photo().has_editable()) : false);
        
        if (has_photo() && !get_photo_missing())
            update_rating_menu_item_sensitivity();
        
#if !NO_SET_BACKGROUND
        set_action_sensitive("SetBackground", has_photo());
#endif

        set_action_sensitive("PrevPhoto", multiple);
        set_action_sensitive("NextPhoto", multiple);
        set_action_sensitive("RotateClockwise", rotate_possible);
        set_action_sensitive("RotateCounterclockwise", rotate_possible);
        set_action_sensitive("FlipHorizontally", rotate_possible);
        set_action_sensitive("FlipVertically", rotate_possible);
        
#if !NO_RAW
        set_action_visible("ExternalEditRAW", 
            is_raw && Config.get_instance().get_external_raw_app() != "");
#endif
        
        base.update_actions(selected_count, count);
    }
    
    private void on_photos_altered() {
        set_action_sensitive("Revert", has_photo() ?
            (get_photo().has_transformations() || get_photo().has_editable()) : false);
    }
    
    public void display_for_collection(CollectionPage return_page, Photo photo) {
        this.return_page = return_page;
        
        display(return_page.get_view(), photo);
    }
    
    public CollectionPage get_controller_page() {
        return return_page;
    }

    public override void switched_to() {
        // since LibraryPhotoPages often rest in the background, their stored photo can be deleted by 
        // another page. this checks to make sure a display photo has been established before the
        // switched_to call.
        assert(get_photo() != null);
        
        lock_controller();
        
        base.switched_to();
        
        update_zoom_menu_item_sensitivity();
        update_rating_menu_item_sensitivity();
        
        set_display_ratings(Config.get_instance().get_display_photo_ratings());
    }

    public override void switching_from() {
        base.switching_from();
        
        unlock_controller();
    }
    
    private void on_controller_page_destroyed() {
        unlock_controller();
    }
    
    private void lock_controller() {
        get_controller().lock_view();
        get_controller_page().destroy.connect(on_controller_page_destroyed);
        get_controller().items_removed.connect(on_photos_removed);
    }
    
    private void unlock_controller() {
        if (get_controller().is_view_locked()) {
            get_controller().unlock_view();
            get_controller_page().destroy.disconnect(on_controller_page_destroyed);
            get_controller().items_removed.disconnect(on_photos_removed);
        }
    }
    
    protected override void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        base.paint(gc, drawable);

        if (!has_current_tool() && get_zoom_state().is_default()) {
            Gdk.Pixbuf? trinket = null;
            
            if (Config.get_instance().get_display_photo_ratings())
                trinket = Resources.get_rating_trinket(((LibraryPhoto) get_photo()).get_rating(), 
                    TRINKET_SCALE);
            
            if (trinket == null)
                return;
            
            Gdk.Pixbuf? pixbuf = get_scaled_pixbuf();
            
            if (pixbuf == null)
                return;

            int x, y;
            drawable.get_size(out x, out y);

            drawable.draw_pixbuf(gc, trinket, 0, 0, 
                (x / 2) - (pixbuf.get_width() / 2) + TRINKET_PADDING,
                (y / 2) + (pixbuf.get_height() / 2) - trinket.get_height() - TRINKET_PADDING, 
                trinket.get_width(), trinket.get_height(), Gdk.RgbDither.NORMAL, 0, 0);
        }
    }
    
    private void on_slideshow() {
        LibraryPhoto? photo = (LibraryPhoto?) get_photo();
        if (photo == null)
            return;
        
        AppWindow.get_instance().go_fullscreen(new SlideshowPage(LibraryPhoto.global, get_controller(),
            photo));
    }
    
    private void update_zoom_menu_item_sensitivity() {
        set_action_sensitive("IncreaseSize", !get_zoom_state().is_max() && !get_photo_missing());
        set_action_sensitive("DecreaseSize", !get_zoom_state().is_default() && !get_photo_missing());
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

    protected override void update_ui(Photo photo, bool missing) {
        bool sensitivity = !missing;
        
        set_action_sensitive("Publish", sensitivity);
        set_action_sensitive("Print", sensitivity);
        set_action_sensitive("JumpToFile", sensitivity);
        
        set_action_sensitive("Undo", sensitivity);
        set_action_sensitive("Redo", sensitivity);
        
        set_action_sensitive("IncreaseSize", sensitivity);
        set_action_sensitive("DecreaseSize", sensitivity);
        set_action_sensitive("ZoomFit", sensitivity);
        set_action_sensitive("Zoom100", sensitivity);
        set_action_sensitive("Zoom200", sensitivity);
        set_action_sensitive("Slideshow", sensitivity);
        
        set_action_sensitive("RotateClockwise", sensitivity);
        set_action_sensitive("RotateCounterclockwise", sensitivity);
        set_action_sensitive("FlipHorizontally", sensitivity);
        set_action_sensitive("FlipVertically", sensitivity);
        set_action_sensitive("Enhance", sensitivity);
        set_action_sensitive("Crop", sensitivity);
        set_action_sensitive("RedEye", sensitivity);
        set_action_sensitive("Adjust", sensitivity);
        set_action_sensitive("EditTitle", sensitivity);
        set_action_sensitive("AdjustDateTime", sensitivity);
        set_action_sensitive("ExternalEdit", sensitivity);
        set_action_sensitive("ExternalEditRAW", sensitivity);
        set_action_sensitive("Revert", sensitivity);
        
        set_action_sensitive("Rate", sensitivity);
        set_action_sensitive("AddTags", sensitivity);
        set_action_sensitive("ModifyTags", sensitivity);
        
#if !NO_SET_BACKGROUND
        set_action_sensitive("SetBackground", sensitivity);
#endif
        
        base.update_ui(photo, missing);
    }
    
    protected override void notify_photo_backing_missing(Photo photo, bool missing) {
        if (missing)
            ((LibraryPhoto) photo).mark_offline();
        else
            ((LibraryPhoto) photo).mark_online();
        
        base.notify_photo_backing_missing(photo, missing);
    }
    
    public override bool key_press_event(Gdk.EventKey event) {
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
                on_move_to_trash();
            break;

            case "period":
            case "greater":
                on_increase_rating();
            break;
            
            case "comma":
            case "less":
                on_decrease_rating();
            break;

            case "KP_1":
                on_rate_one();
            break;
            
            case "KP_2":
                on_rate_two();
            break;

            case "KP_3":
                on_rate_three();
            break;
        
            case "KP_4":
                on_rate_four();
            break;

            case "KP_5":
                on_rate_five();
            break;

            case "KP_0":
                on_rate_unrated();
            break;

            case "KP_9":
                on_rate_rejected();
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
    
    protected override bool on_context_buttonpress(Gdk.EventButton event) {
        popup_context_menu(context_menu, event);

        return true;
    }

    protected override bool on_context_keypress() {
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
    
    private void on_remove_from_library() {
        LibraryPhoto photo = (LibraryPhoto) get_photo();
        
        Gee.Collection<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        photos.add(photo);
        
        remove_from_app(photos, _("Remove From Library"), _("Removing Photo From Library"));
    }
    
    private void on_move_to_trash() {
        if (!has_photo())
            return;
        
        LibraryPhoto photo = (LibraryPhoto) get_photo();
        
        Gee.Collection<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        photos.add(photo);
        
        // move on to next photo before executing
        on_next_photo();
        
        // this indicates there is only one photo in the controller, or about to be zero, so switch 
        // to the Photos page, which is guaranteed to be there when this disappears
        if (photo.equals(get_photo()))
            LibraryWindow.get_app().switch_to_library_page();
        
        get_command_manager().execute(new TrashUntrashPhotosCommand(photos, true));
    }
    
    private void on_photo_destroyed(DataSource source) {
        on_photo_removed((LibraryPhoto) source);
    }
    
    private void on_photos_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed)
            on_photo_removed((LibraryPhoto) ((DataView) object).get_source());
    }
    
    private void on_photo_removed(LibraryPhoto photo) {
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

    private void on_external_app_changed() {
        set_action_sensitive("ExternalEdit", has_photo() && 
            Config.get_instance().get_external_photo_app() != "");
    }
    
    private void on_external_edit() {
        if (!has_photo())
            return;
        
        try {
            AppWindow.get_instance().set_busy_cursor();
            get_photo().open_with_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            AppWindow.error_message(Resources.launch_editor_failed(err));
        }
    }

#if !NO_RAW    
    private void on_external_edit_raw() {
        if (!has_photo())
            return;
        
        if (get_photo().get_master_file_format() != PhotoFileFormat.RAW)
            return;
        
        try {
            AppWindow.get_instance().set_busy_cursor();
            get_photo().open_master_with_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            AppWindow.error_message(Resources.launch_editor_failed(err));
        }
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
    
#if !NO_PUBLISHING
    private void on_publish() {
        if (get_view().get_count() == 0)
            return;
        
        PublishingDialog.go((Gee.Iterable<DataView>) get_view().get_all());
    }
#endif
    
    private void on_view_menu() {
        update_zoom_menu_item_sensitivity();
    }

    private void on_increase_rating() {
        if (!has_photo() || get_photo_missing())
            return;
        
        SetRatingSingleCommand command = new SetRatingSingleCommand.inc_dec(get_photo(), true);
        get_command_manager().execute(command);
    
        update_rating_menu_item_sensitivity();
    }

    private void on_decrease_rating() {
        if (!has_photo() || get_photo_missing())
            return;
        
        SetRatingSingleCommand command = new SetRatingSingleCommand.inc_dec(get_photo(), false);
        get_command_manager().execute(command);

        update_rating_menu_item_sensitivity();
    }

    private void on_set_rating(Rating rating) {
        if (!has_photo() || get_photo_missing())
            return;
        
        SetRatingSingleCommand command = new SetRatingSingleCommand(get_photo(), rating);
        get_command_manager().execute(command);
        
        update_rating_menu_item_sensitivity();
    }

    private void on_rate_rejected() {
        on_set_rating(Rating.REJECTED);
    }
    
    private void on_rate_unrated() {
        on_set_rating(Rating.UNRATED);
    }

    private void on_rate_one() {
        on_set_rating(Rating.ONE);
    }

    private void on_rate_two() {
        on_set_rating(Rating.TWO);
    }

    private void on_rate_three() {
        on_set_rating(Rating.THREE);
    }

    private void on_rate_four() {
        on_set_rating(Rating.FOUR);
    }

    private void on_rate_five() {
        on_set_rating(Rating.FIVE);
    }

    private void update_rating_menu_item_sensitivity() {
        set_action_sensitive("RateRejected", get_photo().get_rating() != Rating.REJECTED);
        set_action_sensitive("RateUnrated", get_photo().get_rating() != Rating.UNRATED);
        set_action_sensitive("RateOne", get_photo().get_rating() != Rating.ONE);
        set_action_sensitive("RateTwo", get_photo().get_rating() != Rating.TWO);
        set_action_sensitive("RateThree", get_photo().get_rating() != Rating.THREE);
        set_action_sensitive("RateFour", get_photo().get_rating() != Rating.FOUR);
        set_action_sensitive("RateFive", get_photo().get_rating() != Rating.FIVE);
        set_action_sensitive("IncreaseRating", get_photo().get_rating().can_increase());
        set_action_sensitive("DecreaseRating", get_photo().get_rating().can_decrease());
    }

    private void on_metadata_altered(Gee.Map<DataObject, Alteration> map) {
        if (map.has_key(get_photo()) && map.get(get_photo()).has_subject("metadata"))
            repaint();
    }

    private void on_add_tags() {
        AddTagsDialog dialog = new AddTagsDialog();
        string[]? names = dialog.execute();
        if (names != null) {
            get_command_manager().execute(new AddTagsCommand(names, 
                (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources()));
        }
    }

    private void on_modify_tags() {
        LibraryPhoto photo = (LibraryPhoto) get_view().get_selected_at(0).get_source();
        
        ModifyTagsDialog dialog = new ModifyTagsDialog(photo);
        Gee.ArrayList<Tag>? new_tags = dialog.execute();
        
        if (new_tags == null)
            return;
        
        get_command_manager().execute(new ModifyTagsCommand(photo, new_tags));
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
        
        monitor_source_collection(DirectPhoto.global, new DirectViewManager(), null);
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
            DirectPhoto.global.fetch(file, out photo);
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
            DirectPhoto.global.fetch(file, out photo);
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
            DirectPhoto.global.fetch(file, out photo);
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
            DirectPhoto.global.fetch(file, out photo);
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
                
                if (Photo.is_basename_supported(basename))
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
        base (DirectPhoto.global, file.get_basename());
        
        if (!check_editable_file(file)) {
            Application.get_instance().panic();
            
            return;
        }
        
        initial_file = file;
        current_save_dir = file.get_parent();
        
        context_menu = (Gtk.Menu) ui.get_widget("/DirectContextMenu");
        
        DirectPhoto.global.items_altered.connect(on_photos_altered);
    }
    
    ~DirectPhotoPage() {
        DirectPhoto.global.items_altered.disconnect(on_photos_altered);
    }
    
    protected override string? get_menubar_path() {
        return "/DirectMenuBar";
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("direct.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, null };
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
        print.label = Resources.PRINT_MENU;
        print.tooltip = _("Print the photo to a printer connected to your computer");
        actions += print;
#endif
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, null };
        edit.label = _("Edit");
        actions += edit;

        Gtk.ActionEntry photo = { "PhotoMenu", null, "", null, null, null };
        photo.label = _("_Photo");
        actions += photo;
        
        Gtk.ActionEntry tools = { "Tools", null, TRANSLATABLE, null, null, null };
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

        Gtk.ActionEntry hflip = { "FlipHorizontally", Resources.HFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_horizontally };
        hflip.label = Resources.HFLIP_MENU;
        hflip.tooltip = Resources.HFLIP_TOOLTIP;
        actions += hflip;
        
        Gtk.ActionEntry vflip = { "FlipVertically", Resources.VFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_vertically };
        vflip.label = Resources.VFLIP_MENU;
        vflip.tooltip = Resources.VFLIP_TOOLTIP;
        actions += vflip;
        
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

        Gtk.ActionEntry best_fit = { "ZoomFit", Gtk.STOCK_ZOOM_FIT, TRANSLATABLE,
            "0", TRANSLATABLE, snap_zoom_to_min };
        best_fit.label = _("Fit to _Page");
        best_fit.tooltip = _("Zoom the photo to fit on the screen");
        actions += best_fit;

        Gtk.ActionEntry actual_size = { "Zoom100", Gtk.STOCK_ZOOM_100, TRANSLATABLE,
            "1", TRANSLATABLE, snap_zoom_to_isomorphic };
        actual_size.label = _("Zoom _100%");
        actual_size.tooltip = _("Zoom the photo to 100% magnification");
        actions += actual_size;
        
        Gtk.ActionEntry max_size = { "Zoom200", null, TRANSLATABLE,
            "2", TRANSLATABLE, snap_zoom_to_max };
        max_size.label = _("Zoom _200%");
        max_size.tooltip = _("Zoom the photo to 200% magnification");
        actions += max_size;

        return actions;
    }
    
    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();
        
#if !NO_PRINTING
        InjectionGroup print_group = new InjectionGroup("/DirectMenuBar/FileMenu/PrintPlaceholder");
        print_group.add_menu_item("PageSetup");
        print_group.add_menu_item("Print");
        
        groups += print_group;
#endif
        
#if !NO_SET_BACKGROUND
        InjectionGroup bg_group = new InjectionGroup("/DirectMenuBar/FileMenu/SetBackgroundPlaceholder");
        bg_group.add_menu_item("SetBackground");
        
        groups += bg_group;
#endif
        
        return groups;
    }
    
    private static bool check_editable_file(File file) {
        if (!FileUtils.test(file.get_path(), FileTest.EXISTS))
            AppWindow.error_message(_("%s does not exist.").printf(file.get_path()));
        else if (!FileUtils.test(file.get_path(), FileTest.IS_REGULAR))
            AppWindow.error_message(_("%s is not a file.").printf(file.get_path()));
        else if (!Photo.is_file_supported(file))
            AppWindow.error_message(_("%s does not support the file format of\n%s.").printf(
                Resources.APP_TITLE, file.get_path()));
        else
            return true;
        
        return false;
    }
    
    public override void realize() {
        if (base.realize != null)
            base.realize();
        
        DirectPhoto photo = null;
        ImportResult import_result = ImportResult.SUCCESS;
        try {
            import_result = DirectPhoto.global.fetch(initial_file, out photo);
        } catch (Error error) {
            warning("Fetching photo failed: %s", error.message);
        }
        
        if (photo == null) {
            AppWindow.error_message(import_result.to_string());
            Application.get_instance().panic();
        }

        display(new DirectViewCollection(initial_file.get_parent()), photo);
        initial_file = null;
    }
    
    public File get_current_file() {
        return get_photo().get_file();
    }

    protected override bool on_context_buttonpress(Gdk.EventButton event) {
        popup_context_menu(context_menu, event);

        return true;
    }

    private void update_zoom_menu_item_sensitivity() {
        set_action_sensitive("IncreaseSize", !get_zoom_state().is_max() && !get_photo_missing());
        set_action_sensitive("DecreaseSize", !get_zoom_state().is_default() && !get_photo_missing());
    }

    protected override void on_increase_size() {
        base.on_increase_size();
        
        update_zoom_menu_item_sensitivity();
    }
    
    protected override void on_decrease_size() {
        base.on_decrease_size();

        update_zoom_menu_item_sensitivity();
    }
    
    private void on_photos_altered(Gee.Iterable<DataObject> objects) {
        bool contains = false;
        if (has_photo()) {
            Photo photo = get_photo();
            foreach (DataObject object in objects) {
                if (((Photo) object) == photo) {
                    contains = true;
                    
                    break;
                }
            }
        }
        
        bool sensitive = has_photo() && !get_photo_missing();
        if (sensitive)
            sensitive = contains;
        
        set_action_sensitive("Save", sensitive && get_photo().get_file_format().can_write());
        set_action_sensitive("Revert", sensitive);
    }
    
    protected override void update_ui(Photo photo, bool missing) {
        bool sensitivity = !missing;
        
        set_action_sensitive("Save", sensitivity);
        set_action_sensitive("SaveAs", sensitivity);
        set_action_sensitive("Publish", sensitivity);
        set_action_sensitive("Print", sensitivity);
        set_action_sensitive("JumpToFile", sensitivity);
        
        set_action_sensitive("Undo", sensitivity);
        set_action_sensitive("Redo", sensitivity);
        
        set_action_sensitive("IncreaseSize", sensitivity);
        set_action_sensitive("DecreaseSize", sensitivity);
        set_action_sensitive("ZoomFit", sensitivity);
        set_action_sensitive("Zoom100", sensitivity);
        set_action_sensitive("Zoom200", sensitivity);
        
        set_action_sensitive("RotateClockwise", sensitivity);
        set_action_sensitive("RotateCounterclockwise", sensitivity);
        set_action_sensitive("FlipHorizontally", sensitivity);
        set_action_sensitive("FlipVertically", sensitivity);
        set_action_sensitive("Enhance", sensitivity);
        set_action_sensitive("Crop", sensitivity);
        set_action_sensitive("RedEye", sensitivity);
        set_action_sensitive("Adjust", sensitivity);
        set_action_sensitive("Revert", sensitivity);
        set_action_sensitive("AdjustDateTime", sensitivity);
        set_action_sensitive("Fullscreen", sensitivity);
        
#if !NO_SET_BACKGROUND
        set_action_sensitive("SetBackground", has_photo() && !get_photo_missing());
#endif
        
        base.update_ui(photo, missing);
    }
    
    protected override void update_actions(int selected_count, int count) {
        bool multiple = (get_controller() != null) ? get_controller().get_count() > 1 : false;
        bool revert_possible = has_photo() ? get_photo().has_transformations() 
            && !get_photo_missing() : false;
        bool rotate_possible = has_photo() ? is_rotate_available(get_photo()) : false;
        bool enhance_possible = has_photo() ? is_enhance_available(get_photo()) : false;
        
        set_action_sensitive("PrevPhoto", multiple);
        set_action_sensitive("NextPhoto", multiple);
        set_action_sensitive("RotateClockwise", rotate_possible);
        set_action_sensitive("RotateCounterclockwise", rotate_possible);
        set_action_sensitive("FlipHorizontally", rotate_possible);
        set_action_sensitive("FlipVertically", rotate_possible);
        set_action_sensitive("Revert", revert_possible);
        set_action_sensitive("Enhance", enhance_possible);
        
#if !NO_SET_BACKGROUND
        set_action_sensitive("SetBackground", has_photo());
#endif
        
        base.update_actions(selected_count, count);
    }
    
    private bool check_ok_to_close_photo(Photo photo) {
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
    
    protected override bool confirm_replace_photo(Photo? old_photo, Photo new_photo) {
        return (old_photo != null) ? check_ok_to_close_photo(old_photo) : true;
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
        ImportResult fetch_result = ImportResult.SUCCESS;
        try {
            fetch_result = DirectPhoto.global.fetch(dest, out photo, true);
        } catch (Error error) {
            warning("Fetching photo failed: %s", error.message);
        }
        
        if (photo == null) {
            // dead in the water
            Application.get_instance().panic();
        }
        
        // switch to that file ... if saving on top of the original file, this will re-import the
        // photo into the in-memory database, which is key because its stored transformations no
        // longer match the backing photo
        display(new DirectViewCollection(dest.get_parent()), photo);
    }

    private void on_save() {
        if (!get_photo().has_alterations() || !get_photo().get_file_format().can_write() || 
            get_photo_missing())
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
        save_as_dialog.set_local_only(false);
        
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
}
