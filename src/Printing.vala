/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class PrintManager {
    public enum ContentLayout {
        FILL_PAGE,
        FIXED_SIZE
    }

    private class Job : Gtk.PrintOperation {
        private TransformablePhoto source_photo;
        private ContentLayout content_layout;
        private double content_width;
        private double content_height;
        private int content_ppi;

        public Job(TransformablePhoto source_photo, ContentLayout content_layout,
            double content_width, double content_height, int content_ppi) {
            this.source_photo = source_photo;
            this.content_layout = content_layout;
            this.content_width = content_width;
            this.content_height = content_height;
            this.content_ppi = content_ppi;
        }

        public TransformablePhoto get_source_photo() {
            return source_photo;
        }

        public ContentLayout get_content_layout() {
            return content_layout;
        }

        public double get_content_width() {
            return content_width;
        }

        public double get_content_height() {
            return content_height;
        }

        public int get_content_ppi() {
            return content_ppi;
        }
    }

    private static PrintManager instance = null;

    private double content_width = 5.0;
    private double content_height = 5.0;
    private int content_ppi = 200;
    private ContentLayout content_layout = ContentLayout.FILL_PAGE;
    private Gtk.PageSetup user_page_setup;

    private PrintManager() {
        user_page_setup = new Gtk.PageSetup();
    }

    public static PrintManager get_instance() {
        if (instance == null)
            instance = new PrintManager();

        return instance;
    }

    public double get_content_width() {
        return content_width;
    }

    public double get_content_height() {
        return content_height;
    }

    public int get_content_ppi() {
        return content_ppi;
    }

    public void spool_photo(TransformablePhoto source_photo) {
        Job job = new Job(source_photo, content_layout, content_width,
            content_height, content_ppi);
        job.set_unit(Gtk.Unit.INCH);
        job.set_n_pages(1);
        job.set_job_name(source_photo.get_name());
        job.set_default_page_setup(user_page_setup);
        job.draw_page += on_draw_page;

        Gtk.PrintOperationResult job_result;

        try {
            job_result = job.run(Gtk.PrintOperationAction.PRINT_DIALOG,
                AppWindow.get_instance());
        } catch (Error e) {
            AppWindow.error_message(_("Unable to print photo:\n\n%s").printf(e.message));
        }
    }

    public void do_page_setup() {
        Gtk.PrintSettings dummy_settings = new Gtk.PrintSettings();
        user_page_setup = Gtk.print_run_page_setup_dialog(AppWindow.get_instance(),
            user_page_setup, dummy_settings);
    }

    private void on_draw_page(Gtk.PrintOperation emitting_object,
        Gtk.PrintContext job_context, int page_num) {
        Job job = (Job) emitting_object;

        int major_axis_num_pixels;
        configure_photo_transformation(job, job_context, out major_axis_num_pixels);

        Cairo.Context dc = job_context.get_cairo_context();

        Scaling pixbuf_scaling = Scaling.for_best_fit(major_axis_num_pixels, true);
        Gdk.Pixbuf photo_pixbuf = null;
        try {
            photo_pixbuf = job.get_source_photo().get_pixbuf(Scaling.for_original());
            photo_pixbuf = pixbuf_scaling.perform_on_pixbuf(photo_pixbuf, Gdk.InterpType.HYPER,
                true);
        } catch (Error e) {
            error(_("Unable to print photo:\n\n%s").printf(e.message));
            job.cancel();
            return;
        }
        Gdk.cairo_set_source_pixbuf(dc, photo_pixbuf, 0.0, 0.0);

        dc.paint();
    }

    private void configure_photo_transformation(Job job,
        Gtk.PrintContext job_context, out int major_axis_num_pixels) {
        switch (job.get_content_layout()) {
            case ContentLayout.FILL_PAGE:
                configure_fill_page_transformation(job, job_context,
                    out major_axis_num_pixels);
            break;

            case ContentLayout.FIXED_SIZE:
                error("fixed-size layout mode is not supported in this release of Shotwell");
            break;

            default:
                error("unknown layout mode");
            break;
        }
    }

    private void configure_fill_page_transformation(Job job, Gtk.PrintContext job_context,
        out int major_axis_num_pixels) {
        Cairo.Context dc = job_context.get_cairo_context();
        Gtk.PageSetup page_setup = job_context.get_page_setup();
        Dimensions photo_dimensions = job.get_source_photo().get_dimensions();
        double photo_aspect_ratio = ((double) photo_dimensions.width) /
            photo_dimensions.height;

        /* determine the photo's major axis and place the photo such that its major axis
           occupies the entire imageable area of the page. note that the imageable area is
           usually different from the physical page size, since most printers can't print
           over the entire page edge-to-edge */
        double target_width = 0.0;
        double target_height = 0.0;
        if (photo_dimensions.width > photo_dimensions.height) {
            /* landscape-oriented photo case: try to make the photo fill the page width, but if
               this makes the photo overflow vertically, then constrain the photo to fill the
               page height instead */
            target_width = page_setup.get_page_width(Gtk.Unit.INCH);
            target_height = target_width * (1.0 / photo_aspect_ratio);
            if (target_height > page_setup.get_page_height(Gtk.Unit.INCH)) {
                target_height = page_setup.get_page_height(Gtk.Unit.INCH);
                target_width = target_height * photo_aspect_ratio;
            }
            major_axis_num_pixels = (int)(target_width * job.get_content_ppi() + 0.5);
        } else {
            /* portrait-oriented photo case: try to make the photo fill the page height, but if
               this makes the photo overflow horizontally, then constrain the photo to fill the
               page width instead */
            target_height = page_setup.get_page_height(Gtk.Unit.INCH);
            target_width = target_height * photo_aspect_ratio;
            if (target_height > page_setup.get_page_height(Gtk.Unit.INCH)) {
                target_width = page_setup.get_page_width(Gtk.Unit.INCH);
                target_height = target_width * (1.0 / photo_aspect_ratio);
            }
            major_axis_num_pixels = (int)(target_height * job.get_content_ppi() + 0.5);
        }

        double x_offset = (page_setup.get_page_width(Gtk.Unit.INCH) - target_width) / 2.0;
        double y_offset = (page_setup.get_page_height(Gtk.Unit.INCH) - target_height) / 2.0;

        double inv_dpi = 1.0 / ((double) job.get_content_ppi());
        dc.translate(x_offset, y_offset);
        dc.scale(inv_dpi, inv_dpi);
    }
}

