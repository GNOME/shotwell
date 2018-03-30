/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public enum ScaleConstraint {
    ORIGINAL,
    DIMENSIONS,
    WIDTH,
    HEIGHT,
    FILL_VIEWPORT;
    
    public string? to_string() {
        switch (this) {
            case ORIGINAL:
                return _("Original size");
                
            case DIMENSIONS:
                return _("Longest edge");
            
            case WIDTH:
                return _("Width");
            
            case HEIGHT:
                return _("Height");
            
            case FILL_VIEWPORT:
                // TODO: Translate (not used in UI at this point)
                return "Fill Viewport";
        }

        warn_if_reached();

        return null;
    }
}
    
public struct Dimensions {
    public int width;
    public int height;
    
    public Dimensions(int width = 0, int height = 0) {
        if ((width < 0) || (height < 0))
            warning("Tried to construct a Dimensions object with negative width or height - forcing sensible default values.");
        
        this.width = width.clamp(0, width);
        this.height = height.clamp(0, height);
    }
    
    public static Dimensions for_pixbuf(Gdk.Pixbuf pixbuf) {
        return Dimensions(pixbuf.get_width(), pixbuf.get_height());
    }
    
    public static Dimensions for_allocation(Gtk.Allocation allocation) {
        return Dimensions(allocation.width, allocation.height);
    }
    
    public static Dimensions for_widget_allocation(Gtk.Widget widget) {
        Gtk.Allocation allocation;
        widget.get_allocation(out allocation);
        
        return Dimensions(allocation.width, allocation.height);
    }
    
    public static Dimensions for_rectangle(Gdk.Rectangle rect) {
        return Dimensions(rect.width, rect.height);
    }
    
    public bool has_area() {
        return (width > 0 && height > 0);
    }
    
    public Dimensions floor(Dimensions min = Dimensions(1, 1)) {
        return Dimensions((width > min.width) ? width : min.width, 
            (height > min.height) ? height : min.height);
    }
    
    public string to_string() {
        return "%dx%d".printf(width, height);
    }
    
    public bool equals(Dimensions dim) {
        return (width == dim.width && height == dim.height);
    }
    
    // sometimes a pixel or two is okay
    public bool approx_equals(Dimensions dim, int fudge = 1) {
        return (width - dim.width).abs() <= fudge && (height - dim.height).abs() <= fudge;
    }
    
    public bool approx_scaled(int scale, int fudge = 1) {
        return (width <= (scale + fudge)) && (height <= (scale + fudge));
    }
    
    public int major_axis() {
        return int.max(width, height);
    }
    
    public int minor_axis() {
        return int.min(width, height);
    }
    
    public Dimensions with_min(int min_width, int min_height) {
        return Dimensions(int.max(width, min_width), int.max(height, min_height));
    }
    
    public Dimensions with_max(int max_width, int max_height) {
        return Dimensions(int.min(width, max_width), int.min(height, max_height));
    }

    public Dimensions get_scaled(int scale, bool scale_up) {
        assert(scale > 0);
        
        // check for existing best-fit
        if ((width == scale && height < scale) || (height == scale && width < scale))
            return Dimensions(width, height);
        
        // watch for scaling up
        if (!scale_up && (width < scale && height < scale))
            return Dimensions(width, height);
        
        if ((width - scale) > (height - scale))
            return get_scaled_by_width(scale);
        else
            return get_scaled_by_height(scale);
    }
    
    public void get_scale_ratios(Dimensions scaled, out double width_ratio, out double height_ratio) {
        width_ratio = (double) scaled.width / (double) width;
        height_ratio = (double) scaled.height / (double) height;
    }

    public double get_aspect_ratio() {
        return ((double) width) / height;
    }

    public Dimensions get_scaled_proportional(Dimensions viewport) {
        double width_ratio, height_ratio;
        get_scale_ratios(viewport, out width_ratio, out height_ratio);
        
        double scaled_width, scaled_height;
        if (width_ratio < height_ratio) {
            scaled_width = viewport.width;
            scaled_height = (double) height * width_ratio;
        } else {
            scaled_width = (double) width * height_ratio;
            scaled_height = viewport.height;
        }
        
        Dimensions scaled = Dimensions((int) Math.round(scaled_width), 
            (int) Math.round(scaled_height)).floor();
        assert(scaled.height <= viewport.height);
        assert(scaled.width <= viewport.width);
        
        return scaled;
    }

    public Dimensions get_scaled_to_fill_viewport(Dimensions viewport) {
        double width_ratio, height_ratio;
        get_scale_ratios(viewport, out width_ratio, out height_ratio);
        
        double scaled_width, scaled_height;
        if (width < viewport.width && height >= viewport.height) {
            // too narrow
            scaled_width = viewport.width;
            scaled_height = (double) height * width_ratio;
        } else if (width >= viewport.width && height < viewport.height) {
            // too short
            scaled_width = (double) width * height_ratio;
            scaled_height = viewport.height;
        } else {
            // both are smaller or larger
            double ratio = double.max(width_ratio, height_ratio);
            
            scaled_width = (double) width * ratio;
            scaled_height = (double) height * ratio;
        }
        
        return Dimensions((int) Math.round(scaled_width), (int) Math.round(scaled_height)).floor();
    }
    
    public Gdk.Rectangle get_scaled_rectangle(Dimensions scaled, Gdk.Rectangle rect) {
        double x_scale, y_scale;
        get_scale_ratios(scaled, out x_scale, out y_scale);
        
        Gdk.Rectangle scaled_rect = Gdk.Rectangle();
        scaled_rect.x = (int) Math.round((double) rect.x * x_scale);
        scaled_rect.y = (int) Math.round((double) rect.y * y_scale);
        scaled_rect.width = (int) Math.round((double) rect.width * x_scale);
        scaled_rect.height = (int) Math.round((double) rect.height * y_scale);
        
        if (scaled_rect.width <= 0)
            scaled_rect.width = 1;
        
        if (scaled_rect.height <= 0)
            scaled_rect.height = 1;
        
        return scaled_rect;
    }
    
    // Returns the current dimensions scaled in a similar proportion as the two supplied dimensions
    public Dimensions get_scaled_similar(Dimensions original, Dimensions scaled) {
        double x_scale, y_scale;
        original.get_scale_ratios(scaled, out x_scale, out y_scale);
        
        double scale = double.min(x_scale, y_scale);
        
        return Dimensions((int) Math.round((double) width * scale), 
            (int) Math.round((double) height * scale)).floor();
    }
    
    public Dimensions get_scaled_by_width(int scale) {
        assert(scale > 0);
        
        double ratio = (double) scale / (double) width;
        
        return Dimensions(scale, (int) Math.round((double) height * ratio)).floor();
    }
    
    public Dimensions get_scaled_by_height(int scale) {
        assert(scale > 0);
        
        double ratio = (double) scale / (double) height;
        
        return Dimensions((int) Math.round((double) width * ratio), scale).floor();
    }
    
    public Dimensions get_scaled_by_constraint(int scale, ScaleConstraint constraint) {
        switch (constraint) {
            case ScaleConstraint.ORIGINAL:
                return Dimensions(width, height);
                
            case ScaleConstraint.DIMENSIONS:
                return (width >= height) ? get_scaled_by_width(scale) : get_scaled_by_height(scale);
            
            case ScaleConstraint.WIDTH:
                return get_scaled_by_width(scale);
            
            case ScaleConstraint.HEIGHT:
                return get_scaled_by_height(scale);
            
            default:
                error("Bad constraint: %d", (int) constraint);
        }
    }
}

public struct Scaling {
    private const int NO_SCALE = 0;
    
    public ScaleConstraint constraint;
    public int scale;
    public Dimensions viewport;
    public bool scale_up;
    
    private Scaling(ScaleConstraint constraint, int scale, Dimensions viewport, bool scale_up) {
        this.constraint = constraint;
        this.scale = scale;
        this.viewport = viewport;
        this.scale_up = scale_up;
    }
    
    public static Scaling for_original() {
        return Scaling(ScaleConstraint.ORIGINAL, NO_SCALE, Dimensions(), false);
    }
    
    public static Scaling for_screen(Gtk.Window window, bool scale_up) {
        return for_viewport(get_screen_dimensions(window), scale_up);
    }
    
    public static Scaling for_best_fit(int pixels, bool scale_up) {
        assert(pixels > 0);
        
        return Scaling(ScaleConstraint.DIMENSIONS, pixels, Dimensions(), scale_up);
    }
    
    public static Scaling for_viewport(Dimensions viewport, bool scale_up) {
        assert(viewport.has_area());
        
        return Scaling(ScaleConstraint.DIMENSIONS, NO_SCALE, viewport, scale_up);
    }
    
    public static Scaling for_widget(Gtk.Widget widget, bool scale_up) {
        Dimensions viewport = Dimensions.for_widget_allocation(widget);

        // Because it seems that Gtk.Application realizes the main window and its
        // attendant widgets lazily, it's possible to get here with the PhotoPage's
        // canvas believing it is 1px by 1px, which can lead to a scaling that
        // gdk_pixbuf_scale_simple can't handle.
        //
        // If we get here, and the widget we're being drawn into is 1x1, then, most likely,
        // it's not fully realized yet (since nothing in Shotwell requires this), so just
        // ignore it and return something safe instead.
        if ((viewport.width <= 1) || (viewport.height <= 1))
            return for_original();

        return Scaling(ScaleConstraint.DIMENSIONS, NO_SCALE, viewport, scale_up);
    }
    
    public static Scaling to_fill_viewport(Dimensions viewport) {
        // Please see the comment in Scaling.for_widget as to why this is
        // required.
        if ((viewport.width <= 1) || (viewport.height <= 1))
            return for_original();

        return Scaling(ScaleConstraint.FILL_VIEWPORT, NO_SCALE, viewport, true);
    }

    public static Scaling to_fill_screen(Gtk.Window window) {
        return to_fill_viewport(get_screen_dimensions(window));
    }
    
    public static Scaling for_constraint(ScaleConstraint constraint, int scale, bool scale_up) {
        return Scaling(constraint, scale, Dimensions(), scale_up);
    }
    
    public static Dimensions get_screen_dimensions(Gtk.Window window) {
        var display = window.get_window().get_display();
        var monitor = display.get_monitor_at_window(window.get_window());
        var geom = monitor.get_geometry();
        
        return Dimensions(geom.width, geom.height);
    }
    
    private int scale_to_pixels() {
        return (scale >= 0) ? scale : 0;
    }
    
    public bool is_unscaled() {
        return constraint == ScaleConstraint.ORIGINAL;
    }
    
    public bool is_best_fit(Dimensions original, out int pixels) {
        pixels = 0;
        
        if (scale == NO_SCALE)
            return false;
        
        switch (constraint) {
            case ScaleConstraint.ORIGINAL:
            case ScaleConstraint.FILL_VIEWPORT:
                return false;
            
            default:
                pixels = scale_to_pixels();
                assert(pixels > 0);
                
                return true;
        }
    }
    
    public bool is_best_fit_dimensions(Dimensions original, out Dimensions scaled) {
        scaled = Dimensions();
        
        if (scale == NO_SCALE)
            return false;
        
        switch (constraint) {
            case ScaleConstraint.ORIGINAL:
            case ScaleConstraint.FILL_VIEWPORT:
                return false;
            
            default:
                int pixels = scale_to_pixels();
                assert(pixels > 0);
                
                scaled = original.get_scaled_by_constraint(pixels, constraint);
                
                return true;
        }
    }
    
    public bool is_for_viewport(Dimensions original, out Dimensions scaled) {
        scaled = Dimensions();
        
        if (scale != NO_SCALE)
            return false;
        
        switch (constraint) {
            case ScaleConstraint.ORIGINAL:
            case ScaleConstraint.FILL_VIEWPORT:
                return false;
            
            default:
                assert(viewport.has_area());
                
                if (!scale_up && original.width < viewport.width && original.height < viewport.height)
                    scaled = original;
                else
                    scaled = original.get_scaled_proportional(viewport);
                
                return true;
        }
    }
    
    public bool is_fill_viewport(Dimensions original, out Dimensions scaled) {
        scaled = Dimensions();
        
        if (constraint != ScaleConstraint.FILL_VIEWPORT)
            return false;
        
        assert(viewport.has_area());
        scaled = original.get_scaled_to_fill_viewport(viewport);
        
        return true;
    }
    
    public Dimensions get_scaled_dimensions(Dimensions original) {
        if (is_unscaled())
            return original;
        
        Dimensions scaled;
        if (is_fill_viewport(original, out scaled))
            return scaled;
        
        if (is_best_fit_dimensions(original, out scaled))
            return scaled;
        
        bool is_viewport = is_for_viewport(original, out scaled);
        assert(is_viewport);
        
        return scaled;
    }
    
    public Gdk.Pixbuf perform_on_pixbuf(Gdk.Pixbuf pixbuf, Gdk.InterpType interp, bool scale_up) {
        if (is_unscaled())
            return pixbuf;
        
        Dimensions pixbuf_dim = Dimensions.for_pixbuf(pixbuf);
        
        int pixels;
        if (is_best_fit(pixbuf_dim, out pixels))
            return scale_pixbuf(pixbuf, pixels, interp, scale_up);
        
        Dimensions scaled;
        if (is_fill_viewport(pixbuf_dim, out scaled))
            return resize_pixbuf(pixbuf, scaled, interp);
        
        bool is_viewport = is_for_viewport(pixbuf_dim, out scaled);
        assert(is_viewport);
        
        return resize_pixbuf(pixbuf, scaled, interp);
    }
    
    public string to_string() {
        if (constraint == ScaleConstraint.ORIGINAL)
            return "scaling: UNSCALED";
        else if (constraint == ScaleConstraint.FILL_VIEWPORT)
            return "scaling: fill viewport %s".printf(viewport.to_string());
        else if (scale != NO_SCALE)
            return "scaling: best-fit (%s %d pixels %s)".printf(constraint.to_string(),
                scale_to_pixels(), scale_up ? "scaled up" : "not scaled up");
        else
            return "scaling: viewport %s (%s)".printf(viewport.to_string(),
                scale_up ? "scaled up" : "not scaled up");
    }
    
    public bool equals(Scaling scaling) {
        return (constraint == scaling.constraint) && (scale == scaling.scale) 
            && viewport.equals(scaling.viewport);
    }
}

public struct ZoomState {
    public Dimensions content_dimensions;
    public Dimensions viewport_dimensions;
    public double zoom_factor;
    public double interpolation_factor;
    public double min_factor;
    public double max_factor;
    public Gdk.Point viewport_center;
    
    public ZoomState(Dimensions content_dimensions, Dimensions viewport_dimensions,
        double slider_val = 0.0, Gdk.Point? viewport_center = null) {
        this.content_dimensions = content_dimensions;
        this.viewport_dimensions = viewport_dimensions;
        this.interpolation_factor = slider_val;

        compute_zoom_factors();

        if ((viewport_center == null) || ((viewport_center.x == 0) && (viewport_center.y == 0)) ||
            (slider_val == 0.0)) {
            center_viewport();
        } else {
            this.viewport_center = viewport_center;
            clamp_viewport_center();
        }
    }

    public ZoomState.rescale(ZoomState existing, double new_slider_val) {
        this.content_dimensions = existing.content_dimensions;
        this.viewport_dimensions = existing.viewport_dimensions;
        this.interpolation_factor = new_slider_val;

        compute_zoom_factors();

        if (new_slider_val == 0.0) {
            center_viewport();
        } else {
            viewport_center.x = (int) (zoom_factor * (existing.viewport_center.x /
                existing.zoom_factor));
            viewport_center.y = (int) (zoom_factor * (existing.viewport_center.y /
                existing.zoom_factor));
            clamp_viewport_center();
        }
    }

    public ZoomState.rescale_to_isomorphic(ZoomState existing) {
        this.content_dimensions = existing.content_dimensions;
        this.viewport_dimensions = existing.viewport_dimensions;
        this.interpolation_factor = Math.log(1.0 / existing.min_factor) /
            (Math.log(existing.max_factor / existing.min_factor));

        compute_zoom_factors();

        if (this.interpolation_factor == 0.0) {
            center_viewport();
        } else {
            viewport_center.x = (int) (zoom_factor * (existing.viewport_center.x /
                existing.zoom_factor));
            viewport_center.y = (int) (zoom_factor * (existing.viewport_center.y /
                existing.zoom_factor));
            clamp_viewport_center();
        }
    }
    
    public ZoomState.pan(ZoomState existing, Gdk.Point new_viewport_center) {
        this.content_dimensions = existing.content_dimensions;
        this.viewport_dimensions = existing.viewport_dimensions;
        this.interpolation_factor = existing.interpolation_factor;

        compute_zoom_factors();

        this.viewport_center = new_viewport_center;
        
        clamp_viewport_center();
    }
    
    private void clamp_viewport_center() {
        int zoomed_width = get_zoomed_width();
        int zoomed_height = get_zoomed_height();

        viewport_center.x = viewport_center.x.clamp(viewport_dimensions.width / 2,
            zoomed_width - (viewport_dimensions.width / 2) - 1);
        viewport_center.y = viewport_center.y.clamp(viewport_dimensions.height / 2,
            zoomed_height - (viewport_dimensions.height / 2) - 1);
    }
    
    private void center_viewport() {
        viewport_center.x = get_zoomed_width() / 2;
        viewport_center.y = get_zoomed_height() / 2;
    }

    private void compute_zoom_factors() {
        max_factor = 2.0;
        
        double viewport_to_content_x;
        double viewport_to_content_y;
        content_dimensions.get_scale_ratios(viewport_dimensions, out viewport_to_content_x,
            out viewport_to_content_y);
        min_factor = double.min(viewport_to_content_x, viewport_to_content_y);
        if (min_factor > 1.0)
            min_factor = 1.0;

        zoom_factor = min_factor * Math.pow(max_factor / min_factor, interpolation_factor);
    }

    public double get_interpolation_factor() {
        return interpolation_factor;
    }

    /* gets the viewing rectangle with respect to the zoomed content */
    public Gdk.Rectangle get_viewing_rectangle_wrt_content() {
        int zoomed_width = get_zoomed_width();
        int zoomed_height = get_zoomed_height();

        Gdk.Rectangle result = Gdk.Rectangle();

        if (viewport_dimensions.width < zoomed_width) {
            result.x = viewport_center.x - (viewport_dimensions.width / 2);
        } else {
            result.x = (zoomed_width - viewport_dimensions.width) / 2;
        }
        if (result.x < 0)
            result.x = 0;

        if (viewport_dimensions.height < zoomed_height) {
            result.y = viewport_center.y - (viewport_dimensions.height / 2);
        } else {
            result.y = (zoomed_height - viewport_dimensions.height) / 2;
        }
        if (result.y < 0)
            result.y = 0;

        int right = result.x + viewport_dimensions.width;
        if (right > zoomed_width)
            right = zoomed_width;
        result.width = right - result.x;

        int bottom = result.y + viewport_dimensions.height;
        if (bottom > zoomed_height)
            bottom = zoomed_height;
        result.height = bottom - result.y;

        result.width = result.width.clamp(1, int.MAX);
        result.height = result.height.clamp(1, int.MAX);
       
        return result;
    }

    /* gets the viewing rectangle with respect to the on-screen canvas where zoomed content is
       drawn */
    public Gdk.Rectangle get_viewing_rectangle_wrt_screen() {
        Gdk.Rectangle wrt_content = get_viewing_rectangle_wrt_content();

        Gdk.Rectangle result = Gdk.Rectangle();
        result.x = (viewport_dimensions.width / 2) - (wrt_content.width / 2);
        if (result.x < 0)
            result.x = 0;
        result.y = (viewport_dimensions.height / 2) - (wrt_content.height / 2);
        if (result.y < 0)
            result.y = 0;
        result.width = wrt_content.width;
        result.height = wrt_content.height;

        return result;
    }

    /* gets the projection of the viewing rectangle into the arbitrary pixbuf 'for_pixbuf' */
    public Gdk.Rectangle get_viewing_rectangle_projection(Gdk.Pixbuf for_pixbuf) {
        double zoomed_width = get_zoomed_width();
        double zoomed_height = get_zoomed_height();
        
        double horiz_scale = for_pixbuf.width / zoomed_width;
        double vert_scale = for_pixbuf.height / zoomed_height;
        double scale = (horiz_scale + vert_scale) / 2.0;
        
        Gdk.Rectangle viewing_rectangle = get_viewing_rectangle_wrt_content();

        Gdk.Rectangle result = Gdk.Rectangle();
        result.x = (int) (viewing_rectangle.x * scale);
        result.x = result.x.clamp(0, for_pixbuf.width);
        result.y = (int) (viewing_rectangle.y * scale);
        result.y = result.y.clamp(0, for_pixbuf.height);
        int right = (int) ((viewing_rectangle.x + viewing_rectangle.width) * scale);
        right = right.clamp(0, for_pixbuf.width);
        int bottom = (int) ((viewing_rectangle.y + viewing_rectangle.height) * scale);
        bottom = bottom.clamp(0, for_pixbuf.height);
        result.width = right - result.x;
        result.height = bottom - result.y;
        
        return result;
    }


    public double get_zoom_factor() {
        return zoom_factor;
    }

    public int get_zoomed_width() {
        return (int) (content_dimensions.width * zoom_factor);
    }
    
    public int get_zoomed_height() {
        return (int) (content_dimensions.height * zoom_factor);
    }

    public Gdk.Point get_viewport_center() {
        return viewport_center;
    }

    public string to_string() {
        string named_modes = "";
        if (is_min())
            named_modes = named_modes + ((named_modes == "") ? "MIN" : ", MIN");
        if (is_default())
            named_modes = named_modes + ((named_modes == "") ? "DEFAULT" : ", DEFAULT");
        if (is_isomorphic())
            named_modes = named_modes + ((named_modes =="") ? "ISOMORPHIC" : ", ISOMORPHIC");
        if (is_max())
            named_modes = named_modes + ((named_modes =="") ? "MAX" : ", MAX");
        if (named_modes == "")
            named_modes = "(none)";

        Gdk.Rectangle viewing_rect = get_viewing_rectangle_wrt_content();

        return (("ZoomState {\n    content dimensions = %d x %d;\n    viewport dimensions = " +
            "%d x %d;\n    min factor = %f;\n    max factor = %f;\n    current factor = %f;" +
            "\n    zoomed width = %d;\n    zoomed height = %d;\n    named modes = %s;" +
            "\n    viewing rectangle = { x: %d, y: %d, width: %d, height: %d };" +
            "\n    viewport center = (%d, %d);\n}\n").printf(
            content_dimensions.width, content_dimensions.height, viewport_dimensions.width,
            viewport_dimensions.height, min_factor, max_factor, zoom_factor, get_zoomed_width(),
            get_zoomed_height(), named_modes, viewing_rect.x, viewing_rect.y, viewing_rect.width,
            viewing_rect.height, viewport_center.x, viewport_center.y));
    }

    public bool is_min() {
        return (zoom_factor == min_factor);
    }

    public bool is_default() {
        return is_min();
    }

    public bool is_max() {
        return (zoom_factor == max_factor);
    }

    public bool is_isomorphic() {
        return (zoom_factor == 1.0);
    }
    
    public bool equals(ZoomState other) {
        if (!content_dimensions.equals(other.content_dimensions))
            return false;
        if (!viewport_dimensions.equals(other.viewport_dimensions))
            return false;
        if (zoom_factor != other.zoom_factor)
            return false;
        if (min_factor != other.min_factor)
            return false;
        if (max_factor != other.max_factor)
            return false;
        if (viewport_center.x != other.viewport_center.x)
            return false;
        if (viewport_center.y != other.viewport_center.y)
            return false;

        return true;
    }
}

