// SPDX-License-Identifier: LGPL-2.0-or-later
// SPDX-FileCopyrightText: 2016 Software Freedom Convervancy Inc.

public class StandardPrintSize {
    public StandardPrintSize(string name, Measurement width, Measurement height) {
        this.name = name;
        this.width = width;
        this.height = height;
    }

    public string name;
    public Measurement width;
    public Measurement height;
}

public class PrintManager {
    private const double IMAGE_DISTANCE = 0.24;
    
    private static PrintManager instance = null;
    
    private PrintSettings settings;
    private Gtk.PrintSettings print_settings;
    private Gtk.PageSetup user_page_setup;
    private ProgressDialog? progress_dialog = null;
    private Cancellable? inner_cancellable = null;
    private StandardPrintSize[]? standard_sizes = null;
    private GLib.OutputStream? temp_printstream = null;
    
    private PrintManager() {
        user_page_setup = Config.Facade.get_instance().get_printing_system_page_setup();
        settings = new PrintSettings();
        print_settings = Config.Facade.get_instance().get_printing_system_print_settings();
    }

    public unowned StandardPrintSize[] get_standard_sizes() {
        if (standard_sizes == null) {
            standard_sizes = new StandardPrintSize[0];
            print("%p\n", standard_sizes);

            standard_sizes += new StandardPrintSize(_("Wallet (2 × 3 in.)"),
                    Measurement(3, MeasurementUnit.INCHES),
                    Measurement(2, MeasurementUnit.INCHES));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("Notecard (3 × 5 in.)"),
                    Measurement(5, MeasurementUnit.INCHES),
                    Measurement(3, MeasurementUnit.INCHES));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("4 × 6 in."),
                    Measurement(6, MeasurementUnit.INCHES),
                    Measurement(4, MeasurementUnit.INCHES));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("5 × 7 in."),
                    Measurement(7, MeasurementUnit.INCHES),
                    Measurement(5, MeasurementUnit.INCHES));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("8 × 10 in."),
                    Measurement(10, MeasurementUnit.INCHES),
                    Measurement(8, MeasurementUnit.INCHES));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("11 × 14 in."),
                    Measurement(14, MeasurementUnit.INCHES),
                    Measurement(11, MeasurementUnit.INCHES));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("16 × 20 in."),
                    Measurement(20, MeasurementUnit.INCHES),
                    Measurement(16, MeasurementUnit.INCHES));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(("-"),
                    Measurement(0, MeasurementUnit.INCHES),
                    Measurement(0, MeasurementUnit.INCHES));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("Metric Wallet (9 × 13 cm)"),
                    Measurement(13, MeasurementUnit.CENTIMETERS),
                    Measurement(9, MeasurementUnit.CENTIMETERS));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("Postcard (10 × 15 cm)"),
                    Measurement(15, MeasurementUnit.CENTIMETERS),
                    Measurement(10, MeasurementUnit.CENTIMETERS));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("13 × 18 cm"),
                    Measurement(18, MeasurementUnit.CENTIMETERS),
                    Measurement(13, MeasurementUnit.CENTIMETERS));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("18 × 24 cm"),
                    Measurement(24, MeasurementUnit.CENTIMETERS),
                    Measurement(18, MeasurementUnit.CENTIMETERS));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("20 × 30 cm"),
                    Measurement(30, MeasurementUnit.CENTIMETERS),
                    Measurement(20, MeasurementUnit.CENTIMETERS));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("24 × 40 cm"),
                    Measurement(40, MeasurementUnit.CENTIMETERS),
                    Measurement(24, MeasurementUnit.CENTIMETERS));
            print("%p\n", standard_sizes);
            standard_sizes += new StandardPrintSize(_("30 × 40 cm"),
                    Measurement(40, MeasurementUnit.CENTIMETERS),
                    Measurement(30, MeasurementUnit.CENTIMETERS));
        }

        print("%p\n", standard_sizes);
        return standard_sizes;
    }

    public static PrintManager get_instance() {
        if (instance == null)
            instance = new PrintManager();

        return instance;
    }

    public async void spool_photo(Gee.Collection<Photo> to_print, Cancellable? cancellable = null) {
        var dialog = new Gtk.PrintDialog();
        dialog.set_accept_label(_("Continue..."));
        dialog.set_page_setup(user_page_setup);
        dialog.set_print_settings(print_settings);

        PrintPreview.Result result = PrintPreview.Result.UNDEFINED;
        PrintJob? job = null;
        Gtk.PrintSetup? user_print_setup = null;
        do {
            try {
                user_print_setup = yield dialog.setup(AppWindow.get_instance(), null);
                user_page_setup = user_print_setup.get_page_setup();
                print_settings = user_print_setup.get_print_settings();
            } catch (Error err) {
                if (err is Gtk.DialogError.DISMISSED || err is Gtk.DialogError.CANCELLED) {
                    return;
                }

                AppWindow.get_instance().add_toast(new Shotwell.Toast.from_error(_("Printing failed"), err));
                return;
            }

            job = new PrintJob(to_print);
            job.n_pages = 1;
            job.page_setup = user_page_setup;

            var preview = new PrintPreview(AppWindow.get_instance(), job, this);
            var size = job.get_photos().size;
            if (size > 1) {
                preview.set_title(ngettext("Print preview for a photo", "Print preview for %d photos", size).printf(size));
            } else {
                preview.set_title(_("Print preview for %s").printf(job.get_source_photo().get_name()));
            }

            result = yield preview.run();
            if (result == PrintPreview.Result.CANCEL) {
                return;
            }
        } while (result == PrintPreview.Result.BACK);

        // If we landed here, the user definitely wants to print
        set_global_settings(settings);
        var config = Config.Facade.get_instance();
        config.set_printing_system_print_settings(print_settings);
        config.set_printing_system_page_setup(user_page_setup);

        // Do the actual print
        AppWindow.get_instance().set_busy_cursor();
        
        inner_cancellable = new Cancellable();
        ulong id = 0;
        if (cancellable != null) {
            id = cancellable.connect(() => {inner_cancellable.cancel(); });
        }
        progress_dialog = new ProgressDialog(AppWindow.get_instance(), _("Printing…"), inner_cancellable);
        
        // Create an PDF
        try {
            temp_printstream = yield dialog.print(AppWindow.get_instance(), (!)user_print_setup, null);
        } catch (Error err) {
            AppWindow.get_instance().add_toast(new Shotwell.Toast.from_error(_("Printing failed"), err));
            return;            
        }

        var thread = new Thread<void>(null, () => {
            var ppi = ((!)job).get_local_settings().get_content_ppi();
            double inv_ppi = 1.0/ppi;
            var page_width = job.page_setup.get_page_width(Gtk.Unit.INCH) * ppi;
            var page_height = job.page_setup.get_page_height(Gtk.Unit.INCH) * ppi;
            var surface = new Cairo.PdfSurface.for_stream(pdf_write, page_width, page_height);
            double top = job.page_setup.get_top_margin(Gtk.Unit.INCH) * ppi;
            double bottom = job.page_setup.get_bottom_margin(Gtk.Unit.INCH) * ppi;
            double left = job.page_setup.get_left_margin(Gtk.Unit.INCH) * ppi;
            double right = job.page_setup.get_right_margin(Gtk.Unit.INCH) * ppi;
            double w = job.page_setup.get_page_width(Gtk.Unit.INCH) * ppi;
            double h = job.page_setup.get_page_height(Gtk.Unit.INCH) * ppi;
            var ctx = new Cairo.Context(surface);
            var effective_page_width = w - left - right;
            var effetcive_page_height = h - top - bottom;
            ctx.translate(left, top);
            ctx.rectangle(0, 0, effective_page_width, effetcive_page_height);
            ctx.clip();
            for (int i = 0; i < job.n_pages; i++) {
                draw_page(job, ctx, i, effective_page_width * inv_ppi, effetcive_page_height * inv_ppi);
                if (inner_cancellable.is_cancelled()) {
                    break;
                }
                ctx.show_page();
            }
            var idle_id = Idle.add(spool_photo.callback);
            Source.set_name_by_id(idle_id, "spool_photo Async callback");
        });
        yield;
        thread.join();
        progress_dialog.close();
        progress_dialog = null;
        if (id != 0) {
            cancellable.disconnect(id);
        }
        AppWindow.get_instance().set_normal_cursor();
    }

    private Cairo.Status pdf_write(uchar[] data) {
        try {
            size_t written;
            temp_printstream.write_all(data, out written, inner_cancellable);
            return Cairo.Status.SUCCESS;
        } catch (Error error) {
            return Cairo.Status.WRITE_ERROR;
        }
    }

    public void relayout_images(PrintJob job) {
        var photos = job.get_photos();
        if (job.get_local_settings().get_content_layout() == ContentLayout.IMAGE_PER_PAGE){
            PrintLayout layout = (PrintLayout) job.get_local_settings().get_image_per_page_selection();
            job.n_pages = (int) Math.ceil((double) photos.size / (double) layout.get_per_page());
        } else {
            job.n_pages = photos.size;
        }
    }

    // Draws the page given in the space page_width, page_height, must be INCHES
    public void draw_page(PrintJob job, Cairo.Context dc, int page_num, double page_width, double page_height) {
        print("dp: page_num: %d, pw: %f, ph: %f\n", page_num, page_width, page_height);
        Gee.List<Photo> photos = job.get_photos();
        
        ContentLayout content_layout = job.get_local_settings().get_content_layout();
        switch (content_layout) {
            case ContentLayout.STANDARD_SIZE:
            case ContentLayout.CUSTOM_SIZE:
                double canvas_width, canvas_height;
                if (content_layout == ContentLayout.STANDARD_SIZE) {
                    canvas_width = get_standard_sizes()[job.get_local_settings().get_size_selection()].width.convert_to(
                        MeasurementUnit.INCHES).value;
                    canvas_height = get_standard_sizes()[job.get_local_settings().get_size_selection()].height.convert_to(
                        MeasurementUnit.INCHES).value;
                } else {
                    assert(content_layout == ContentLayout.CUSTOM_SIZE);
                    canvas_width = job.get_local_settings().get_content_width().convert_to(
                        MeasurementUnit.INCHES).value;
                    canvas_height = job.get_local_settings().get_content_height().convert_to(
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
                        job, dc);
                    if (job.get_local_settings().is_print_titles_enabled()) {
                        add_title_to_canvas(page_width / 2, page_height, photos[page_num].get_name(),
                            job, dc);
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
                PrintLayout layout = (PrintLayout) job.get_local_settings().get_image_per_page_selection();
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
                                job, dc);
                            print("Putting image at %f %f %f %f\n", dx, dy, canvas_width, canvas_height);
                            if (job.get_local_settings().is_print_titles_enabled()) {
                                add_title_to_canvas(dx + canvas_width / 2, dy + canvas_height, 
                                    photos[i].get_name(), job, dc);
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

    private void fit_image_to_canvas(Photo photo, double x, double y, double canvas_width, double canvas_height, bool crop, PrintJob job, Cairo.Context dc) {
        print("Fitting to canvas: %f %f %f %f, %s\n", x, y, canvas_width, canvas_height, crop.to_string());
        Dimensions photo_dimensions = photo.get_dimensions();
        double photo_aspect_ratio = photo_dimensions.get_aspect_ratio();
        double canvas_aspect_ratio = ((double) canvas_width) / canvas_height;

        print("Dimensions (photo) %s\n", photo_dimensions.to_string());
        print("ARs: P %f c %f\n", photo_aspect_ratio, canvas_aspect_ratio);


        double target_width = 0.0;
        double target_height = 0.0;
        double dpi = job.get_local_settings().get_content_ppi();

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
            job.cancel();
            AppWindow.error_message(_("Unable to print photo:\n\n%s").printf(e.message));
        }
        dc.restore();
    }
    
    private void add_title_to_canvas(double x, double y, string title, PrintJob job, Cairo.Context dc) {
        double dpi = job.get_local_settings().get_content_ppi();
        var title_font_description = Pango.FontDescription.from_string(job.get_local_settings().get_print_titles_font());
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

    public PrintSettings get_global_settings() {
        return settings;
    }

    public void set_global_settings(PrintSettings settings) {
        print("=========> Setting global settings...\n");
        this.settings = settings;
        settings.save();
    }
}
