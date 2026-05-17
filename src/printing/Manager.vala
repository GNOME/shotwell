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
    private Gtk.PageSetup user_page_setup;
    private CustomPrintTab custom_tab;
    private ProgressDialog? progress_dialog = null;
    private Cancellable? cancellable = null;
    private StandardPrintSize[] standard_sizes = null;
    
    private PrintManager() {
        user_page_setup = new Gtk.PageSetup();
        settings = new PrintSettings();
    }

    public unowned StandardPrintSize[] get_standard_sizes() {
        if (standard_sizes == null) {
            standard_sizes = new StandardPrintSize[0];

            standard_sizes += new StandardPrintSize(_("Wallet (2 × 3 in.)"),
                    Measurement(3, MeasurementUnit.INCHES),
                    Measurement(2, MeasurementUnit.INCHES));
            standard_sizes += new StandardPrintSize(_("Notecard (3 × 5 in.)"),
                    Measurement(5, MeasurementUnit.INCHES),
                    Measurement(3, MeasurementUnit.INCHES));
            standard_sizes += new StandardPrintSize(_("4 × 6 in."),
                    Measurement(6, MeasurementUnit.INCHES),
                    Measurement(4, MeasurementUnit.INCHES));
            standard_sizes += new StandardPrintSize(_("5 × 7 in."),
                    Measurement(7, MeasurementUnit.INCHES),
                    Measurement(5, MeasurementUnit.INCHES));
            standard_sizes += new StandardPrintSize(_("8 × 10 in."),
                    Measurement(10, MeasurementUnit.INCHES),
                    Measurement(8, MeasurementUnit.INCHES));
            standard_sizes += new StandardPrintSize(_("11 × 14 in."),
                    Measurement(14, MeasurementUnit.INCHES),
                    Measurement(11, MeasurementUnit.INCHES));
            standard_sizes += new StandardPrintSize(_("16 × 20 in."),
                    Measurement(20, MeasurementUnit.INCHES),
                    Measurement(16, MeasurementUnit.INCHES));
            standard_sizes += new StandardPrintSize(("-"),
                    Measurement(0, MeasurementUnit.INCHES),
                    Measurement(0, MeasurementUnit.INCHES));
            standard_sizes += new StandardPrintSize(_("Metric Wallet (9 × 13 cm)"),
                    Measurement(13, MeasurementUnit.CENTIMETERS),
                    Measurement(9, MeasurementUnit.CENTIMETERS));
            standard_sizes += new StandardPrintSize(_("Postcard (10 × 15 cm)"),
                    Measurement(15, MeasurementUnit.CENTIMETERS),
                    Measurement(10, MeasurementUnit.CENTIMETERS));
            standard_sizes += new StandardPrintSize(_("13 × 18 cm"),
                    Measurement(18, MeasurementUnit.CENTIMETERS),
                    Measurement(13, MeasurementUnit.CENTIMETERS));
            standard_sizes += new StandardPrintSize(_("18 × 24 cm"),
                    Measurement(24, MeasurementUnit.CENTIMETERS),
                    Measurement(18, MeasurementUnit.CENTIMETERS));
            standard_sizes += new StandardPrintSize(_("20 × 30 cm"),
                    Measurement(30, MeasurementUnit.CENTIMETERS),
                    Measurement(20, MeasurementUnit.CENTIMETERS));
            standard_sizes += new StandardPrintSize(_("24 × 40 cm"),
                    Measurement(40, MeasurementUnit.CENTIMETERS),
                    Measurement(24, MeasurementUnit.CENTIMETERS));
            standard_sizes += new StandardPrintSize(_("30 × 40 cm"),
                    Measurement(40, MeasurementUnit.CENTIMETERS),
                    Measurement(30, MeasurementUnit.CENTIMETERS));
        }

        return standard_sizes;
    }

    public static PrintManager get_instance() {
        if (instance == null)
            instance = new PrintManager();

        return instance;
    }

    public async void spool_photo(Gee.Collection<Photo> to_print) {
        var dialog = new Gtk.PrintDialog();
        dialog.set_accept_label(_("Continue..."));
        dialog.set_page_setup(user_page_setup);
        // FIXME: Set print settings
        // dialog.set_print_settings(user_print_settings);

        try {
            var setup = yield dialog.setup(AppWindow.get_instance(), null);
            user_page_setup = setup.get_page_setup();
        } catch (Error err) {
            if (err is Gtk.DialogError.DISMISSED) {
                return;
            }

            var toast = new Shotwell.Toast("Printing failed: %s".printf(err.message));
            AppWindow.get_instance().add_toast(toast);
            return;
        }


        PrintJob job = new PrintJob(to_print);
        job.set_custom_tab_label(_("Image Settings"));
        job.set_unit(Gtk.Unit.INCH);
        job.set_n_pages(1);
        job.set_job_name(job.get_source_photo().get_name());
        job.set_default_page_setup(user_page_setup);
        job.begin_print.connect(on_begin_print);
        job.draw_page.connect(on_draw_page);
        job.status_changed.connect(on_status_changed);

        var window = new Gtk.Window();
        window.set_child(new CustomPrintTab(job, this));
        window.set_transient_for(AppWindow.get_instance());
        window.set_modal(true);
        window.present();

        /* 
        PrintJob job = new PrintJob(to_print);
        job.set_custom_tab_label(_("Image Settings"));
        job.set_unit(Gtk.Unit.INCH);
        job.set_n_pages(1);
        job.set_job_name(job.get_source_photo().get_name());
        job.set_default_page_setup(user_page_setup);
        job.begin_print.connect(on_begin_print);
        job.draw_page.connect(on_draw_page);
        job.status_changed.connect(on_status_changed);
        AppWindow.get_instance().set_busy_cursor();
        
        cancellable = new Cancellable();
        progress_dialog = new ProgressDialog(AppWindow.get_instance(), _("Printing…"), cancellable);
        
        string? err_msg = null;
        try {
            Gtk.PrintOperationResult result = job.run(Gtk.PrintOperationAction.PRINT_DIALOG,
                AppWindow.get_instance());
            if (result == Gtk.PrintOperationResult.APPLY)
                user_page_setup = job.get_default_page_setup();
        } catch (Error e) {
            job.cancel();
            err_msg = e.message;
        }
        
        progress_dialog.close();
        progress_dialog = null;
        cancellable = null;
        
        AppWindow.get_instance().set_normal_cursor();
        
        if (err_msg != null)
            AppWindow.error_message(_("Unable to print photo:\n\n%s").printf(err_msg));
        */
    }

    private void on_begin_print(Gtk.PrintOperation emitting_object, Gtk.PrintContext job_context) {
        debug("on_begin_print");
        
        PrintJob job = (PrintJob) emitting_object;
        
        // cancel() can only be called from "begin-print", "paginate", or "draw-page"
        if (cancellable != null && cancellable.is_cancelled()) {
            job.cancel();
            
            return;
        }

        relayout_images(job);
        spin_event_loop();
    }
    
    public void relayout_images(PrintJob job) {
        var photos = job.get_photos();
        if (job.get_local_settings().get_content_layout() == ContentLayout.IMAGE_PER_PAGE){
            PrintLayout layout = (PrintLayout) job.get_local_settings().get_image_per_page_selection();
            job.set_n_pages((int) Math.ceil((double) photos.size / (double) layout.get_per_page()));
        } else {
            job.set_n_pages(photos.size);
        }

    }

    private void on_status_changed(Gtk.PrintOperation job) {
        debug("on_status_changed: %s", job.get_status_string());
        
        if (progress_dialog != null) {
            progress_dialog.set_status(job.get_status_string());
            spin_event_loop();
        }
    }
    
    private void on_draw_page(Gtk.PrintOperation emitting_object, Gtk.PrintContext job_context,
        int page_num) {
        debug("on_draw_page");
        
        PrintJob job = (PrintJob) emitting_object;
        
        // cancel() can only be called from "begin-print", "paginate", or "draw-page"
        if (cancellable != null && cancellable.is_cancelled()) {
            job.cancel();
            
            return;
        }
        
        spin_event_loop();
        Gtk.PageSetup page_setup = job_context.get_page_setup();
        double page_width = page_setup.get_page_width(Gtk.Unit.INCH);
        double page_height = page_setup.get_page_height(Gtk.Unit.INCH);

        double dpi = job.get_local_settings().get_content_ppi();
        double inv_dpi = 1.0 / dpi;
        Cairo.Context dc = job_context.get_cairo_context();
        dc.scale(inv_dpi, inv_dpi);

        draw_page(job, dc, page_num, page_width, page_height);
    }

    public void draw_page(PrintJob job, Cairo.Context dc, int page_num, double page_width, double page_height) {
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
                
                if (progress_dialog != null)
                    progress_dialog.monitor(page_num, photos.size);
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

    private void on_custom_widget_apply(Gtk.Widget custom_widget) {
        CustomPrintTab tab = (CustomPrintTab) custom_widget;
        tab.get_source_job().set_local_settings(tab.get_local_settings());
        set_global_settings(tab.get_local_settings());
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
        // FIXME: This should probably use the functions from Gtk.PrintContext, not rolling this on our own
        // But this is how it was, and it works nicely with the preview
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
        this.settings = settings;
        settings.save();
    }
}
