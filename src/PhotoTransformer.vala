/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// PhotoTransformer is an abstract class that allows for applying transformations on-the-fly to a
// particular photo without modifying the backing image file.  The interface allows for
// transformations to be stored persistently elsewhere or in memory until they're commited en
// masse to an image file.
public abstract class PhotoTransformer : Object {
    public const int UNSCALED = 0;
    public const int SCREEN = -1;
    
    public const Jpeg.Quality EXPORT_JPEG_QUALITY = Jpeg.Quality.HIGH;
    public const Gdk.InterpType EXPORT_INTERP = Gdk.InterpType.HYPER;
    
    public enum Exception {
        NONE            = 0,
        ORIENTATION     = 1 << 0,
        CROP            = 1 << 1,
        REDEYE          = 1 << 2,
        ADJUST          = 1 << 3,
        ALL             = 0xFFFFFFFF
    }
    
    private static PhotoTransformer cached_raw_instance = null;
    private static Gdk.Pixbuf cached_raw = null;

    public PhotoTransformer() {
    }
    
    //
    // Pixbuf generation
    //

    // Returns a raw, untransformed, unrotated, unscaled pixbuf from the source
    public abstract Gdk.Pixbuf get_raw_pixbuf() throws Error;
    
    // Converts a scale parameter for get_pixbuf or get_preview_pixbuf into an actual pixel
    // count to proportionally scale to.  Returns 0 if an unscaled pixbuf is specified.
    public static int scale_to_pixels(int scale) {
        return (scale == SCREEN) ? get_screen_scale() : scale;
    }

    // Returns a fully transformed (and scaled, if specified) pixbuf from the source.
    // Transformations may be excluded via the mask.
    //
    // Set scale to UNSCALED for unscaled pixbuf or SCREEN for a pixbuf scaled to the screen size
    // (which can be scaled further, with some loss).  Note that UNSCALED can be extremely expensive, 
    // and it's far better to specify an appropriate scale.
    public Gdk.Pixbuf get_pixbuf(int scale, Exception exceptions = Exception.NONE,
        Gdk.InterpType interp = Gdk.InterpType.HYPER) throws Error {
#if MEASURE_PIPELINE
        Timer timer = new Timer();
        Timer total_timer = new Timer();
        double load_and_decode_time = 0.0, pixbuf_copy_time = 0.0, redeye_time = 0.0, 
            adjustment_time = 0.0, crop_time = 0.0, orientation_time = 0.0, scale_time = 0.0;

        total_timer.start();
#endif
        Gdk.Pixbuf pixbuf = null;
        
        //
        // Image load-and-decode
        //
        
        if (cached_raw != null && cached_raw_instance == this) {
            // used the cached raw pixbuf for this instance, which is merely the decoded pixbuf
            // (no transformations)
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = cached_raw.copy();
#if MEASURE_PIPELINE
            pixbuf_copy_time = timer.elapsed();
#endif
        } else {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = get_raw_pixbuf();
#if MEASURE_PIPELINE
            load_and_decode_time = timer.elapsed();
#endif
        
            // stash for next time
#if MEASURE_PIPELINE
            timer.start();
#endif
            cached_raw = pixbuf.copy();
#if MEASURE_PIPELINE
            pixbuf_copy_time = timer.elapsed();
#endif
            cached_raw_instance = this;
        }

        //
        // Image transformation pipeline
        //

        // redeye reduction
        if ((exceptions & Exception.REDEYE) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            RedeyeInstance[] redeye_instances = get_raw_redeye_instances();
            foreach (RedeyeInstance instance in redeye_instances)
                pixbuf = do_redeye(pixbuf, instance);
#if MEASURE_PIPELINE
            redeye_time = timer.elapsed();
#endif
        }

        // crop
        if ((exceptions & Exception.CROP) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            Box crop;
            if (get_raw_crop(out crop))
                pixbuf = new Gdk.Pixbuf.subpixbuf(pixbuf, crop.left, crop.top, crop.get_width(),
                    crop.get_height());

#if MEASURE_PIPELINE
            crop_time = timer.elapsed();
#endif
        }
        
        // scale
        int scale_pixels = scale_to_pixels(scale);
        if (scale_pixels > 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = scale_pixbuf(pixbuf, scale_pixels, interp);
#if MEASURE_PIPELINE
            scale_time = timer.elapsed();
#endif
        }

        // color adjustment
        if ((exceptions & Exception.ADJUST) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            ColorTransformation composite_transform = get_composite_transformation();
            if (!composite_transform.is_identity())
                ColorTransformation.transform_pixbuf(composite_transform, pixbuf);
#if MEASURE_PIPELINE
            adjustment_time = timer.elapsed();
#endif
        }

        // orientation (all modifications are stored in unrotated coordinate system)
        if ((exceptions & Exception.ORIENTATION) == 0) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = get_orientation().rotate_pixbuf(pixbuf);
#if MEASURE_PIPELINE
            orientation_time = timer.elapsed();
#endif
        }
        
#if MEASURE_PIPELINE
        double total_time = total_timer.elapsed();
        
        debug("Pipeline: load_and_decode=%lf pixbuf_copy=%lf redeye=%lf crop=%lf scale=%lf adjustment=%lf orientation=%lf total=%lf",
            load_and_decode_time, pixbuf_copy_time, redeye_time, crop_time, scale_time, adjustment_time,
            orientation_time, total_time);
#endif
        
        return pixbuf;
    }
    
    // A preview pixbuf is one that can be quickly generated and scaled as a preview while the
    // fully transformed pixbuf is built.  It should be fully transformed for the user.  If the
    // subclass doesn't have one handy, PhotoTransformer will generate a usable one.
    //
    // Note that scale may be UNSCALED or SCREEN, and subclasses must support both.  Use 
    // scale_to_pixels for conversion.  UNSCALED is not considered a performance-killer for this
    // method, although the quality of the pixbuf may be quite poor compared to the actual
    // unscaled transformed pixbuf.
    public virtual Gdk.Pixbuf get_preview_pixbuf(int scale, 
        Gdk.InterpType interp = Gdk.InterpType.BILINEAR) throws Error {
        // as a fallback, return a small image that can be scaled quickly ... cap the size for
        // performance reasons
        if (scale == UNSCALED || scale == SCREEN || scale > 400)
            scale = 400;
            
        Gdk.Pixbuf pixbuf = get_pixbuf(scale, Exception.NONE, interp);
        
        // scale to what the user is asking for
        int scale_pixels = scale_to_pixels(scale);
        if (scale_pixels > 0)
            pixbuf = scale_pixbuf(pixbuf, scale_pixels, interp);
        
        return pixbuf;
    }
    
    //
    // File export
    //
    
    // Returns a File that can be used for exporting ... this file should persist for a reasonable
    // amount of time, as drag-and-drop exports can conclude long after the DnD source has seen
    // the end of the transaction. ... However, if failure is detected, export_failed() will be
    // called, and the file can be removed if necessary.
    public abstract File generate_exportable() throws Error;
    
    // Called when an export has failed; the object can use this to delete the exportable file
    // if necessary
    public virtual void export_failed() {
    }
    
    public static void copy_exported_exif(Exif.Data source, PhotoExif dest, Orientation orientation, 
        Dimensions dim) throws Error {
        dest.set_exif(source);
        dest.set_dimensions(dim);
        dest.set_orientation(orientation);
        dest.remove_all_tags(Exif.Tag.RELATED_IMAGE_WIDTH);
        dest.remove_all_tags(Exif.Tag.RELATED_IMAGE_LENGTH);
        dest.remove_thumbnail();
        dest.commit();
    }

    // Writes a file appropriate for export meeting the specified parameters.
    //
    // TODO: Lossless transformations, especially for mere rotations of JFIF files.
    public void export(File dest_file, int scale, ScaleConstraint constraint,
        Jpeg.Quality quality) throws Error {
        if (constraint == ScaleConstraint.ORIGINAL) {
            // generate a raw exportable file and copy that
            File exportable = generate_exportable();

            try {
                exportable.copy(dest_file, FileCopyFlags.OVERWRITE | FileCopyFlags.ALL_METADATA,
                    null, null);
            } catch (Error err) {
                export_failed();
                
                throw err;
            }
            
            return;
        }
        
        Gdk.Pixbuf pixbuf = get_pixbuf(PhotoTransformer.UNSCALED);
        Dimensions dim = Dimensions.for_pixbuf(pixbuf);
        Dimensions scaled = dim.get_scaled_by_constraint(scale, constraint);

        // only scale if necessary ... although scale_simple probably catches this, it's an easy
        // check to avoid image loss
        if (dim.width != scaled.width || dim.height != scaled.height)
            pixbuf = pixbuf.scale_simple(scaled.width, scaled.height, EXPORT_INTERP);
        
        try {
            pixbuf.save(dest_file.get_path(), "jpeg", "quality", quality.get_pct_text());
            
            Exif.Data exif = get_exif();
            if (exif != null)
                copy_exported_exif(exif, new PhotoExif(dest_file), Orientation.TOP_LEFT, scaled);
        } catch (Error err) {
            export_failed();
            
            throw err;
        }
    }
    
    //
    // Basic photo information
    //
    
    public virtual Exif.Data? get_exif() {
        return null;
    }
    
    // Returns dimensions of unscaled, unrotated photo
    protected virtual Dimensions get_raw_dimensions() {
        assert(false);
        
        // get straight from EXIF
        Exif.Data exif = get_exif();
        if (exif != null)
            // XXX: parse exif
            // return Exif.get_dimensions(exif);
            return Dimensions(0, 0);
        
        // Worst case: load the image and get its dimensions
        try {
            Gdk.Pixbuf pixbuf = get_raw_pixbuf();
        
            return Dimensions.for_pixbuf(pixbuf);
        } catch (Error err) {
            return Dimensions(0, 0);
        }
    }

    // Returns uncropped (but rotated) dimensions
    public Dimensions get_uncropped_dimensions() {
        Dimensions dim = get_raw_dimensions();
        Orientation orientation = get_orientation();
        
        return orientation.rotate_dimensions(dim);
    }
    
    // Returns dimensions for fully-modified photo
    public Dimensions get_dimensions() {
        Box crop;
        if (get_crop(out crop))
            return crop.get_dimensions();
        
        return get_uncropped_dimensions();
    }
    
    //
    // Image transformations
    //
    
    public abstract bool has_transformations();
    
    public abstract void remove_all_transformations();
    
    protected abstract Orientation get_orientation();
    
    protected abstract void set_orientation(Orientation orientation);
    
    public virtual void rotate(Rotation rotation) {
        Orientation orientation = get_orientation();

        orientation = orientation.perform(rotation);

        set_orientation(orientation);
    }
    
    public virtual bool has_crop() {
        Box crop;
        return get_raw_crop(out crop);
    }
    
    // This returns the crop against the coordinate system of the unrotated photo.
    protected abstract bool get_raw_crop(out Box crop);
    
    // This sets the crop against the coordinate system of the unrotated photo.
    protected abstract void set_raw_crop(Box crop);
    
    // Returns the crop against the coordinate system of the rotated photo
    public virtual bool get_crop(out Box crop) {
        Box raw;
        if (!get_raw_crop(out raw))
            return false;
        
        Dimensions dim = get_raw_dimensions();
        Orientation orientation = get_orientation();
        
        crop = orientation.rotate_box(dim, raw);
        
        return true;
    }
    
    // Sets the crop against the coordinate system of the rotated photo
    public void set_crop(Box crop) {
        Dimensions dim = get_raw_dimensions();
        Orientation orientation = get_orientation();

        Box derotated = orientation.derotate_box(dim, crop);
        
        assert(derotated.get_width() <= dim.width);
        assert(derotated.get_height() <= dim.height);
        
        set_raw_crop(derotated);
    }
    
    // All instances are against the coordinate system of the unrotated photo.
    protected abstract void add_raw_redeye_instance(RedeyeInstance redeye);
    
    // All instances are against the coordinate system of the unscaled, unrotated photo.
    protected abstract RedeyeInstance[] get_raw_redeye_instances();
    
    public void add_redeye_instance(RedeyeInstance inst_unscaled) {
        Gdk.Rectangle bounds_rect_unscaled = RedeyeInstance.to_bounds_rect(inst_unscaled);
        Gdk.Rectangle bounds_rect_raw = unscaled_to_raw_rect(bounds_rect_unscaled);
        RedeyeInstance inst = RedeyeInstance.from_bounds_rect(bounds_rect_raw);
        
        add_raw_redeye_instance(inst);
    }
    
    private Gdk.Pixbuf do_redeye(owned Gdk.Pixbuf pixbuf, owned RedeyeInstance inst) {
        /* we remove redeye within a circular region called the "effect
           extent." the effect extent is inscribed within its "bounding
           rectangle." */

        /* for each scanline in the top half-circle of the effect extent,
           compute the number of pixels by which the effect extent is inset
           from the edges of its bounding rectangle. note that we only have
           to do this for the first quadrant because the second quadrant's
           insets can be derived by symmetry */
        double r = (double) inst.radius;
        int[] x_insets_first_quadrant = new int[inst.radius + 1];
        
        int i = 0;
        for (double y = r; y >= 0.0; y -= 1.0) {
            double theta = Math.asin(y / r);
            int x = (int)((r * Math.cos(theta)) + 0.5);
            x_insets_first_quadrant[i] = inst.radius - x;
            
            i++;
        }

        int x_bounds_min = inst.center.x - inst.radius;
        int x_bounds_max = inst.center.x + inst.radius;
        int ymin = inst.center.y - inst.radius;
        ymin = (ymin < 0) ? 0 : ymin;
        int ymax = inst.center.y;
        ymax = (ymax > (pixbuf.height - 1)) ? (pixbuf.height - 1) : ymax;

        /* iterate over all the pixels in the top half-circle of the effect
           extent from top to bottom */
        int inset_index = 0;
        for (int y_it = ymin; y_it <= ymax; y_it++) {
            int xmin = x_bounds_min + x_insets_first_quadrant[inset_index];
            xmin = (xmin < 0) ? 0 : xmin;
            int xmax = x_bounds_max - x_insets_first_quadrant[inset_index];
            xmax = (xmax > (pixbuf.width - 1)) ? (pixbuf.width - 1) : xmax;

            for (int x_it = xmin; x_it <= xmax; x_it++) {
                red_reduce_pixel(pixbuf, x_it, y_it);
            }
            inset_index++;
        }

        /* iterate over all the pixels in the top half-circle of the effect
           extent from top to bottom */
        ymin = inst.center.y;
        ymax = inst.center.y + inst.radius;
        inset_index = x_insets_first_quadrant.length - 1;
        for (int y_it = ymin; y_it <= ymax; y_it++) {  
            int xmin = x_bounds_min + x_insets_first_quadrant[inset_index];
            xmin = (xmin < 0) ? 0 : xmin;
            int xmax = x_bounds_max - x_insets_first_quadrant[inset_index];
            xmax = (xmax > (pixbuf.width - 1)) ? (pixbuf.width - 1) : xmax;

            for (int x_it = xmin; x_it <= xmax; x_it++) {
                red_reduce_pixel(pixbuf, x_it, y_it);
            }
            inset_index--;
        }
        
        return pixbuf;
    }

    private Gdk.Pixbuf red_reduce_pixel(owned Gdk.Pixbuf pixbuf, int x, int y) {
        int px_start_byte_offset = (y * pixbuf.get_rowstride()) +
            (x * pixbuf.get_n_channels());
        
        unowned uchar[] pixel_data = pixbuf.get_pixels();
        
        /* The pupil of the human eye has no pigment, so we expect all
           color channels to be of about equal intensity. This means that at
           any point within the effects region, the value of the red channel
           should be about the same as the values of the green and blue
           channels. So set the value of the red channel to be the mean of the
           values of the red and blue channels. This preserves achromatic
           intensity across all channels while eliminating any extraneous flare
           affecting the red channel only (i.e. the red-eye effect). */
        uchar g = pixel_data[px_start_byte_offset + 1];
        uchar b = pixel_data[px_start_byte_offset + 2];
        
        uchar r = (g + b) / 2;
        
        pixel_data[px_start_byte_offset] = r;
        
        return pixbuf;
    }

    public abstract float get_color_adjustment(ColorTransformationKind kind);
    
    public abstract void set_color_adjustments(Gee.ArrayList<ColorTransformationInstance?> adjustments);

    public ColorTransformation get_composite_transformation() {
        float exposure_param = get_color_adjustment(ColorTransformationKind.EXPOSURE);
        float saturation_param = get_color_adjustment(ColorTransformationKind.SATURATION);
        float tint_param = get_color_adjustment(ColorTransformationKind.TINT);
        float temperature_param = get_color_adjustment(ColorTransformationKind.TEMPERATURE);

        ColorTransformation exposure_transform =
            ColorTransformationFactory.get_instance().from_parameter(
            ColorTransformationKind.EXPOSURE, exposure_param);

        ColorTransformation saturation_transform =
            ColorTransformationFactory.get_instance().from_parameter(
            ColorTransformationKind.SATURATION, saturation_param);

        ColorTransformation tint_transform =
            ColorTransformationFactory.get_instance().from_parameter(
            ColorTransformationKind.TINT, tint_param);

        ColorTransformation temperature_transform =
            ColorTransformationFactory.get_instance().from_parameter(
            ColorTransformationKind.TEMPERATURE, temperature_param);

        ColorTransformation composite_transform = ((
                exposure_transform.compose_against(
                saturation_transform)).compose_against(
                temperature_transform)).compose_against(
                tint_transform);
        
        return composite_transform;
    }

    private Gdk.Point unscaled_to_raw_point(Gdk.Point unscaled_point) {
        Orientation unscaled_orientation = get_orientation();
    
        Dimensions unscaled_dims =
            unscaled_orientation.rotate_dimensions(get_dimensions());

        int unscaled_x_offset_raw = 0;
        int unscaled_y_offset_raw = 0;

        Box crop_box;
        if (get_raw_crop(out crop_box)) {
            unscaled_x_offset_raw = crop_box.left;
            unscaled_y_offset_raw = crop_box.top;
        }
        
        Gdk.Point derotated_point =
            unscaled_orientation.derotate_point(unscaled_dims,
            unscaled_point);

        derotated_point.x += unscaled_x_offset_raw;
        derotated_point.y += unscaled_y_offset_raw;

        return derotated_point;
    }
    
    private Gdk.Rectangle unscaled_to_raw_rect(Gdk.Rectangle unscaled_rect) {
        Gdk.Point upper_left = {0};
        Gdk.Point lower_right = {0};
        upper_left.x = unscaled_rect.x;
        upper_left.y = unscaled_rect.y;
        lower_right.x = upper_left.x + unscaled_rect.width;
        lower_right.y = upper_left.y + unscaled_rect.height;
        
        upper_left = unscaled_to_raw_point(upper_left);
        lower_right = unscaled_to_raw_point(lower_right);
        
        if (upper_left.x > lower_right.x) {
            int temp = upper_left.x;
            upper_left.x = lower_right.x;
            lower_right.x = temp;
        }
        if (upper_left.y > lower_right.y) {
            int temp = upper_left.y;
            upper_left.y = lower_right.y;
            lower_right.y = temp;
        }
        
        Gdk.Rectangle raw_rect = {0};
        raw_rect.x = upper_left.x;
        raw_rect.y = upper_left.y;
        raw_rect.width = lower_right.x - upper_left.x;
        raw_rect.height = lower_right.y - upper_left.y;
        
        return raw_rect;
    }
}

