// SPDX-LicenseIdentifier: LGPL-2.1-or-later
// SPDX-FileCopyrightText: Copyright 2016 Software Freedom Conservancy Inc.
// SPDX-FileCopryrightText: 2024 Jens Georg <mail@jensge.org>

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
    private unowned SinglePhotoPage parent_page;
    private bool is_interactive_redraw_in_progress = false;

    public ZoomBuffer(SinglePhotoPage parent_page, Photo backing_photo,
        Gdk.Pixbuf preview_image) {
        this.parent_page = parent_page;
        this.parent_page.add_weak_pointer(&this.parent_page);
        this.preview_image = preview_image;
        this.backing_photo = backing_photo;
        this.workers = new Workers(2, false);
    }

    ~ZoomBuffer() {
        if (this.parent_page != null) {
            this.parent_page.remove_weak_pointer(&this.parent_page);
        }
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

        if (!is_interactive_redraw_in_progress && parent_page != null)
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

        if (parent_page != null) parent_page.repaint();
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

        // On very small images, it's possible for these to
        // be 0, and GTK doesn't like sampling a region 0 px
        // across.
        view_rect_proj.width = view_rect_proj.width.clamp(1, int.MAX);
        view_rect_proj.height = view_rect_proj.height.clamp(1, int.MAX);

        view_rect.width = view_rect.width.clamp(1, int.MAX);
        view_rect.height = view_rect.height.clamp(1, int.MAX);

        Gdk.Pixbuf proj_subpixbuf = new Gdk.Pixbuf.subpixbuf(sample_source_pixbuf, view_rect_proj.x,
            view_rect_proj.y, view_rect_proj.width, view_rect_proj.height);

        Gdk.Pixbuf zoomed = proj_subpixbuf.scale_simple(view_rect.width, view_rect.height,
            Gdk.InterpType.BILINEAR);

        assert(zoomed != null);

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
                Gdk.Rectangle transfer_src_rect = Gdk.Rectangle();
                Gdk.Rectangle transfer_dest_rect = Gdk.Rectangle();
                                 
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

        view_rect_proj.width = view_rect_proj.width.clamp(1, int.MAX);   
        view_rect_proj.height = view_rect_proj.height.clamp(1, int.MAX);   

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
