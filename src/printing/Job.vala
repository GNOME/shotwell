/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */


public class PrintJob : Object {
    private const double IMAGE_DISTANCE = 0.24;

    private PrintSettings settings;
    public Gtk.PageSetup page_setup { get; set; }
    public int n_pages { get; set; }
    private Gee.ArrayList<Photo> photos = new Gee.ArrayList<Photo>();
    private SourceFunc callback;
    private Cancellable? cancellable = null;
    private OutputStream output_stream;
    private StandardPrintSize print_size;
    private ProgressDialog? progress_dialog = null;
    
    public PrintJob(Gee.Collection<Photo> to_print) {
        this.settings = PrintManager.get_instance().get_global_settings();
        photos.add_all(to_print);
        
        double photo_aspect_ratio =  photos[0].get_dimensions().get_aspect_ratio();
        if (photo_aspect_ratio < 1.0)
            photo_aspect_ratio = 1.0 / photo_aspect_ratio;
    }

    public Gee.List<Photo> get_photos() {
        return photos;
    }

    public Photo get_source_photo() {
        return photos[0];
    }

    public double get_source_aspect_ratio() {
        double aspect_ratio = photos[0].get_dimensions().get_aspect_ratio();
        return (aspect_ratio < 1.0) ? (1.0 / aspect_ratio) : aspect_ratio;
    }

    public PrintSettings get_local_settings() {
        return settings;
    }

    public void set_local_settings(PrintSettings settings) {
        this.settings = settings;
    }

    public void relayout_images() {
        var photos = get_photos();
        if (get_local_settings().get_content_layout() == ContentLayout.IMAGE_PER_PAGE){
            var layout = (PrintLayout) get_local_settings().get_image_per_page_selection();
            n_pages = (int) Math.ceil((double) photos.size / (double) layout.get_per_page());
        } else {
            n_pages = photos.size;
        }        
    }

    public void set_print_size(StandardPrintSize print_size) {
        this.print_size = print_size;
    }

    // Draws the page given in the space page_width, page_height, must be INCHES
    public void draw_page(Cairo.Context dc, int page_num, double page_width, double page_height) {
        print("dp: page_num: %d, pw: %f, ph: %f\n", page_num, page_width, page_height);
        var photos = get_photos();
        
        var content_layout = get_local_settings().get_content_layout();
        switch (content_layout) {
            case ContentLayout.STANDARD_SIZE:
            case ContentLayout.CUSTOM_SIZE:
                double canvas_width, canvas_height;
                if (content_layout == ContentLayout.STANDARD_SIZE) {
                    canvas_width = print_size.width.convert_to(
                        MeasurementUnit.INCHES).value;
                    canvas_height = print_size.height.convert_to(
                        MeasurementUnit.INCHES).value;
                } else {
                    assert(content_layout == ContentLayout.CUSTOM_SIZE);
                    canvas_width = get_local_settings().get_content_width().convert_to(
                        MeasurementUnit.INCHES).value;
                    canvas_height = get_local_settings().get_content_height().convert_to(
                        MeasurementUnit.INCHES).value;
                }
                
                if (page_num < photos.size) {
                    Dimensions photo_dimensions = photos[page_num].get_dimensions();
                    double photo_aspect_ratio = photo_dimensions.get_aspect_ratio();
                    double canvas_aspect_ratio = ((double) canvas_width) / canvas_height;
                    if (Math.floor(canvas_aspect_ratio) != Math.floor(photo_aspect_ratio)) {
                        double canvas_tmp = canvas_width;
                        canvas_width = canvas_height;
                        canvas_height = canvas_tmp;
                    }
                    
                    double dx = (page_width - canvas_width) / 2.0;
                    double dy = (page_height - canvas_height) / 2.0;
                    fit_image_to_canvas(photos[page_num], dx, dy, canvas_width, canvas_height, true,
                        dc);
                    if (get_local_settings().is_print_titles_enabled()) {
                        add_title_to_canvas(page_width / 2, page_height, photos[page_num].get_name(),
                            dc);
                    }
                }
                
                if (progress_dialog != null) {
                    var id = Idle.add_once(() => {
                        progress_dialog.monitor(page_num, photos.size);
                    });
                    Source.set_name_by_id(id, "Printing progress push");
                }
            break;
            
            case ContentLayout.IMAGE_PER_PAGE:
                PrintLayout layout = (PrintLayout) get_local_settings().get_image_per_page_selection();
                int nx = layout.get_x();
                int ny = layout.get_y();
                print("%s: nx / ny: %d / %d\n", layout.to_string(), nx, ny);
                int start = page_num * layout.get_per_page();
                double canvas_width = (double) (page_width - IMAGE_DISTANCE * (nx - 1)) / nx;
                double canvas_height = (double) (page_height - IMAGE_DISTANCE * (ny - 1)) / ny;
                print("start: %d cw: %f ch: %f\n", start, canvas_width, canvas_height);
                print("photos.size: %d\n", photos.size);
                for (int y = 0; y < ny; y++){
                    print("y = %d ",y);
                    for (int x = 0; x < nx; x++){
                        int i = start + y * nx + x;
                        print("x = %d, i = %d \n",y, i);
                        if (i < photos.size) {
                            double dx = x * (canvas_width) + x * IMAGE_DISTANCE;
                            double dy = y * (canvas_height) + y * IMAGE_DISTANCE;
                            fit_image_to_canvas(photos[i], dx, dy, canvas_width, canvas_height, false,
                                dc);
                            print("Putting image at %f %f %f %f\n", dx, dy, canvas_width, canvas_height);
                            if (get_local_settings().is_print_titles_enabled()) {
                                add_title_to_canvas(dx + canvas_width / 2, dy + canvas_height, 
                                    photos[i].get_name(), dc);
                            }
                        }
                        
                        if (progress_dialog != null)
                            progress_dialog.monitor(i, photos.size);
                    }
                }
            break;
            
            default:
                error("unknown or unsupported layout mode");
        }        
    }

    private void fit_image_to_canvas(Photo photo, double x, double y, double canvas_width, double canvas_height, bool crop, Cairo.Context dc) {
        print("Fitting to canvas: %f %f %f %f, %s\n", x, y, canvas_width, canvas_height, crop.to_string());
        Dimensions photo_dimensions = photo.get_dimensions();
        double photo_aspect_ratio = photo_dimensions.get_aspect_ratio();
        double canvas_aspect_ratio = ((double) canvas_width) / canvas_height;

        print("Dimensions (photo) %s\n", photo_dimensions.to_string());
        print("ARs: P %f c %f\n", photo_aspect_ratio, canvas_aspect_ratio);


        double target_width = 0.0;
        double target_height = 0.0;
        double dpi = get_local_settings().get_content_ppi();

        if (!crop) {
            if (canvas_aspect_ratio < photo_aspect_ratio) {
                target_width = canvas_width;
                target_height = target_width * (1.0 / photo_aspect_ratio);
            } else {
                target_height = canvas_height;
                target_width = target_height * photo_aspect_ratio;
            }
            x += (canvas_width - target_width) / 2.0;
            y += (canvas_height - target_height) / 2.0;
        }

        print("-> dpi %f tw %f th %f x %f y %f\n", dpi,  target_width, target_height, x, y);
        
        double x_offset = dpi * x;
        double y_offset = dpi * y;

        print("xo: %f, yo: %f\n", x_offset, y_offset);
        dc.save();
        dc.translate(x_offset, y_offset);

        int w = (int) (dpi * canvas_width);
        int h = (int) (dpi * canvas_height);
        Dimensions viewport = Dimensions(w, h);

        print("viewport: %s\n", viewport.to_string());

        try {
            if (crop && !are_approximately_equal(canvas_aspect_ratio, photo_aspect_ratio)) {
                Scaling pixbuf_scaling = Scaling.to_fill_viewport(viewport);
                print("a) Putting pixbuf at %s\n", pixbuf_scaling.to_string());
                Gdk.Pixbuf photo_pixbuf = photo.get_pixbuf(pixbuf_scaling);
                Dimensions scaled_photo_dimensions = Dimensions.for_pixbuf(photo_pixbuf);
                int shave_vertical = 0;
                int shave_horizontal = 0;
                if (canvas_aspect_ratio < photo_aspect_ratio) {
                    shave_vertical = (int) ((scaled_photo_dimensions.width - (scaled_photo_dimensions.height * canvas_aspect_ratio)) / 2.0);
                } else {
                    shave_horizontal = (int) ((scaled_photo_dimensions.height - (scaled_photo_dimensions.width * (1.0 / canvas_aspect_ratio))) / 2.0);
                }
                Gdk.Pixbuf shaved_pixbuf = new Gdk.Pixbuf.subpixbuf(photo_pixbuf, shave_vertical,shave_horizontal, scaled_photo_dimensions.width - (2 * shave_vertical), scaled_photo_dimensions.height - (2 * shave_horizontal));

                photo_pixbuf = pixbuf_scaling.perform_on_pixbuf(shaved_pixbuf, Gdk.InterpType.HYPER, true);
                Gdk.cairo_set_source_pixbuf(dc, photo_pixbuf, 0.0, 0.0);
            } else {
                Scaling pixbuf_scaling = Scaling.for_viewport(viewport, true);
                print("b) Putting pixbuf at %s\n", pixbuf_scaling.to_string());
                Gdk.Pixbuf photo_pixbuf = photo.get_pixbuf(pixbuf_scaling);
                photo_pixbuf = pixbuf_scaling.perform_on_pixbuf(photo_pixbuf, Gdk.InterpType.HYPER, true);
                Gdk.cairo_set_source_pixbuf(dc, photo_pixbuf, 0.0, 0.0);
            }
            dc.paint();

        } catch (Error e) {
            // FIXME: Meh
            AppWindow.error_message(_("Unable to print photo:\n\n%s").printf(e.message));
        }
        dc.restore();
    }
    
    private void add_title_to_canvas(double x, double y, string title, Cairo.Context dc) {
        double dpi = get_local_settings().get_content_ppi();
        var title_font_description = Pango.FontDescription.from_string(get_local_settings().get_print_titles_font());
        var title_layout = Pango.cairo_create_layout(dc);
        Pango.Context context = title_layout.get_context();
        Pango.cairo_context_set_resolution (context, dpi);
        title_layout.set_font_description(title_font_description);
        title_layout.set_text(title, -1);
        int title_width, title_height;
        title_layout.get_pixel_size(out title_width, out title_height);
        double tx = dpi * x - title_width / 2;
        double ty = dpi * y - title_height;

        // Transparent title text background
        dc.rectangle(tx - 10, ty + 2, title_width + 20, title_height);
        dc.set_source_rgba(1, 1, 1, 1);
        dc.set_line_width(2);
        dc.stroke_preserve();
        dc.set_source_rgba(1, 1, 1, 0.5);
        dc.fill();
        dc.set_source_rgba(0, 0, 0, 1);

        dc.move_to(tx, ty + 2);
        Pango.cairo_show_layout(dc, title_layout);
    }

    private bool are_approximately_equal(double val1, double val2) {
        double accept_err = 0.005;
        return (Math.fabs(val1 - val2) <= accept_err);
    }

    public async void run(GLib.OutputStream output_stream, ProgressDialog? progress_dialog, Cancellable? cancellable) throws Error {
        this.cancellable = cancellable;
        this.callback = run.callback;
        this.output_stream = output_stream;
        this.progress_dialog = progress_dialog;
        var thread = new Thread<Error?>("ShotwellPrintJob", printing_thread);
        yield;

        var error = thread.join();
        if (error != null) {
            throw error;
        }
    }

    private Error? printing_thread() {
        try {
            if (cancellable.set_error_if_cancelled()) {
            // FIXME            
            }
        } catch (Error err) {
            return err;
        }
        var ppi = get_local_settings().get_content_ppi();
        double inv_ppi = 1.0/ppi;
        var page_width = page_setup.get_page_width(Gtk.Unit.INCH) * ppi;
        var page_height = page_setup.get_page_height(Gtk.Unit.INCH) * ppi;
        var surface = new Cairo.PdfSurface.for_stream(pdf_write, page_width, page_height);
        double top = page_setup.get_top_margin(Gtk.Unit.INCH) * ppi;
        double bottom = page_setup.get_bottom_margin(Gtk.Unit.INCH) * ppi;
        double left = page_setup.get_left_margin(Gtk.Unit.INCH) * ppi;
        double right = page_setup.get_right_margin(Gtk.Unit.INCH) * ppi;
        double w = page_setup.get_page_width(Gtk.Unit.INCH) * ppi;
        double h = page_setup.get_page_height(Gtk.Unit.INCH) * ppi;
        var ctx = new Cairo.Context(surface);
        var effective_page_width = w - left - right;
        var effetcive_page_height = h - top - bottom;
        ctx.translate(left, top);
        ctx.rectangle(0, 0, effective_page_width, effetcive_page_height);
        ctx.clip();
        for (int i = 0; i < n_pages; i++) {
            draw_page(ctx, i, effective_page_width * inv_ppi, effetcive_page_height * inv_ppi);
            if (cancellable.is_cancelled()) {
                break;
            }
            ctx.show_page();
        }
        var idle_id = Idle.add(this.callback);
        Source.set_name_by_id(idle_id, "spool_photo Async callback");

        return null;
    }

    private Cairo.Status pdf_write(uchar[] data) {
        try {
            size_t written;
            output_stream.write_all(data, out written, cancellable);
            return Cairo.Status.SUCCESS;
        } catch (Error error) {
            return Cairo.Status.WRITE_ERROR;
        }
    }

}
