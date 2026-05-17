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

    public async void spool_photo(Gee.Collection<Photo> to_print, Cancellable? cancellable = null) {
        var dialog = new Gtk.PrintDialog();
        dialog.set_accept_label(_("Continue..."));
        dialog.set_page_setup(user_page_setup);
        dialog.set_print_settings(print_settings);

        PrintPreview.Result result = PrintPreview.Result.UNDEFINED;
        PrintJob? job = null;
        Gtk.PrintSetup? user_print_setup = null;
        PrintSettings? local_settings = null;
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
            local_settings = preview.get_local_settings();
        } while (result == PrintPreview.Result.BACK);

        // If we landed here, the user definitely wants to print
        set_global_settings(local_settings);
        var config = Config.Facade.get_instance();
        config.set_printing_system_print_settings(print_settings);
        config.set_printing_system_page_setup(user_page_setup);
        job.set_print_size(get_standard_sizes()[settings.get_size_selection()]);

        // Do the actual print
        AppWindow.get_instance().set_busy_cursor();
        
        inner_cancellable = new Cancellable();
        ulong id = 0;
        if (cancellable != null) {
            id = cancellable.connect(() => {inner_cancellable.cancel(); });
        }
        progress_dialog = new ProgressDialog(AppWindow.get_instance(), _("Printing…"), inner_cancellable);
        
        // Create a PDF
        File? tmp_document = null;
        try {
            tmp_document = yield job.run(progress_dialog, inner_cancellable);
            yield dialog.print_file(AppWindow.get_instance(), user_print_setup, tmp_document, inner_cancellable);
            AppWindow.get_instance().add_toast(new Shotwell.Toast(_("Printing to “%s” succeeded").printf(user_print_setup.get_print_settings().get_printer())));
        } catch (Error err) {
            AppWindow.get_instance().add_toast(new Shotwell.Toast.from_error(_("Printing failed"), err));
        } finally {
            try {
                tmp_document.delete(null);
            } catch (Error error) {
                warning ("Failed to delete print spool file: %s", error.message);
            }
            progress_dialog.close();
            progress_dialog = null;
            if (id != 0) {
                cancellable.disconnect(id);
            }
            AppWindow.get_instance().set_normal_cursor();
        }
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
