/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PRINTING

public enum ContentLayout {
    FILL_PAGE,
    STANDARD_SIZE,
    CUSTOM_SIZE
}

public struct PrintSettings {
    public const int MIN_CONTENT_PPI = 72;    /* 72 ppi is the pixel resolution of a 14" VGA
                                                 display -- it's standard for historical reasons */
    public const int MAX_CONTENT_PPI = 1200;  /* 1200 ppi is appropriate for a 3600 dpi imagesetter
                                                 used to produce photographic plates for commercial
                                                 printing -- it's the highest pixel resolution
                                                 commonly used */
    private ContentLayout content_layout;
    private Measurement content_width;
    private Measurement content_height;
    private int content_ppi;
    private int size_selection;
    private bool match_aspect_ratio;

    public PrintSettings() {
        Config config = Config.get_instance();

        MeasurementUnit units = (MeasurementUnit) config.get_printing_content_units();
        
        content_width = Measurement(config.get_printing_content_width(), units);
        content_height = Measurement(config.get_printing_content_height(), units);
        size_selection = config.get_printing_size_selection();
        content_layout = (ContentLayout) config.get_printing_content_layout();
        match_aspect_ratio = config.get_printing_match_aspect_ratio();
        content_ppi = config.get_printing_content_ppi();
    }

    public void save() {
        Config config = Config.get_instance();

        config.set_printing_content_units(content_width.unit);
        config.set_printing_content_width(content_width.value);
        config.set_printing_content_height(content_height.value);
        config.set_printing_size_selection(size_selection);
        config.set_printing_content_layout(content_layout);
        config.set_printing_match_aspect_ratio(match_aspect_ratio);
        config.set_printing_content_ppi(content_ppi);
    }


    public Measurement get_content_width() {
        switch (get_content_layout()) {
            case ContentLayout.STANDARD_SIZE:
            case ContentLayout.FILL_PAGE:
                return (PrintManager.get_instance().get_standard_sizes()[
                    get_size_selection()]).width;

            case ContentLayout.CUSTOM_SIZE:
                return content_width;

            default:
                error("unknown ContentLayout enumeration value");
        }
    }

    public Measurement get_content_height() {
        switch (get_content_layout()) {
            case ContentLayout.STANDARD_SIZE:
            case ContentLayout.FILL_PAGE:
                return (PrintManager.get_instance().get_standard_sizes()[
                    get_size_selection()]).height;

            case ContentLayout.CUSTOM_SIZE:
                return content_height;

            default:
                error("unknown ContentLayout enumeration value");
        }
    }

    public Measurement get_minimum_content_dimension() {
        return Measurement(0.5, MeasurementUnit.INCHES);
    }

    public Measurement get_maximum_content_dimension() {
        return Measurement(30, MeasurementUnit.INCHES);
    }

    public bool is_match_aspect_ratio_enabled() {
        return match_aspect_ratio;
    }

    public int get_content_ppi() {
        return content_ppi;
    }

    public int get_size_selection() {
        return size_selection;
    }

    public ContentLayout get_content_layout() {
        return content_layout;
    }

    public void set_content_layout(ContentLayout content_layout) {
        this.content_layout = content_layout;
    }

    public void set_content_width(Measurement content_width) {
        this.content_width = content_width;
    }

    public void set_content_height(Measurement content_height) {
        this.content_height = content_height;
    }

    public void set_content_ppi(int content_ppi) {
        this.content_ppi = content_ppi;
    }

    public void set_size_selection(int size_selection) {
        this.size_selection = size_selection;
    }

    public void set_match_aspect_ratio_enabled(bool enable_state) {
        this.match_aspect_ratio = enable_state;
    }
}

/* we define our own measurement enum instead of using the Gtk.Unit enum
   provided by Gtk+ 2.0 because Gtk.Unit doesn't define a CENTIMETERS
   constant (thout it does define an MM for millimeters). This is
   unfortunate, because in metric countries people like to think about
   paper sizes for printing in CM not MM. so, to avoid having to
   multiply and divide everything by 10 (which is error prone) to convert
   from CM to MM and vice-versa whenever we read or write measurements, we
   eschew Gtk.Unit and substitute our own */
public enum MeasurementUnit {
    INCHES,
    CENTIMETERS
}

public struct Measurement {
    private const double CENTIMETERS_PER_INCH = 2.54;
    private const double INCHES_PER_CENTIMETER = (1.0 / 2.54);

    public double value;
    public MeasurementUnit unit;

    public Measurement(double value, MeasurementUnit unit) {
        this.value = value;
        this.unit = unit;
    }

    public Measurement convert_to(MeasurementUnit to_unit) {
        if (unit == to_unit)
            return this;

        if (to_unit == MeasurementUnit.INCHES) {
            return Measurement(value * INCHES_PER_CENTIMETER, MeasurementUnit.INCHES);
        } else if (to_unit == MeasurementUnit.CENTIMETERS) {
            return Measurement(value * CENTIMETERS_PER_INCH, MeasurementUnit.CENTIMETERS);
        } else {
            error("unrecognized unit");
        }
    }

    public bool is_less_than(Measurement rhs) {
        Measurement converted_rhs = (unit == rhs.unit) ? rhs : rhs.convert_to(unit);
        return (value < converted_rhs.value);
    }

    public bool is_greater_than(Measurement rhs) {
        Measurement converted_rhs = (unit == rhs.unit) ? rhs : rhs.convert_to(unit);
        return (value > converted_rhs.value);
    }
}

public class CustomPrintTab : Gtk.Fixed {
    private const int INCHES_COMBO_CHOICE = 0;
    private const int CENTIMETERS_COMBO_CHOICE = 1;

    private Gtk.RadioButton standard_size_radio = null;
    private Gtk.RadioButton custom_size_radio = null;
    private Gtk.RadioButton fill_page_radio = null;
    private Gtk.ComboBox standard_sizes_combo = null;
    private Gtk.ComboBox units_combo = null;
    private Gtk.Entry custom_width_entry = null;
    private Gtk.Entry custom_height_entry = null;
    private Gtk.Entry ppi_entry;
    private Gtk.CheckButton aspect_ratio_check = null;
    private Measurement local_content_width = Measurement(5.0, MeasurementUnit.INCHES);
    private Measurement local_content_height = Measurement(5.0, MeasurementUnit.INCHES);
    private int local_content_ppi;
    private bool is_text_insertion_in_progress = false;
    private PrintJob source_job;

    public CustomPrintTab(PrintJob source_job) {
        this.source_job = source_job;

        Gtk.VBox inner_wrapper = new Gtk.VBox(true, 8);

        Gtk.Table master_layouter = new Gtk.Table(8, 3, false);

        Gtk.Label image_size_header = new Gtk.Label("");
        image_size_header.set_markup("<b>" + _("Printed Image Size") + "</b>");
        master_layouter.attach(image_size_header, 0, 3, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 4);
        image_size_header.set_alignment(0.0f, 0.5f);

        Gtk.Label indenter = new Gtk.Label(" ");
        master_layouter.attach(indenter, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 4);

        standard_size_radio = new Gtk.RadioButton.with_mnemonic(null,
            _("Use a _standard size:"));
        standard_size_radio.clicked.connect(on_radio_group_click);
        standard_size_radio.set_alignment(0.0f, 0.5f);
        custom_size_radio = new Gtk.RadioButton.with_mnemonic(
            standard_size_radio.get_group(), _("Use a c_ustom size:"));
        custom_size_radio.set_alignment(0.0f, 0.5f);
        custom_size_radio.clicked.connect(on_radio_group_click);
        fill_page_radio = new Gtk.RadioButton.with_mnemonic(
            standard_size_radio.get_group(), _("_Fill the entire page"));
        fill_page_radio.set_alignment(0.0f, 0.5f);
        fill_page_radio.clicked.connect(on_radio_group_click);
        master_layouter.attach(standard_size_radio, 1, 2, 1, 2,
             Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
             Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 8);
        master_layouter.attach(custom_size_radio, 1, 2, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 2);
        master_layouter.attach(fill_page_radio, 1, 2, 4, 5,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 2);

        StandardPrintSize[] standard_sizes = PrintManager.get_instance().get_standard_sizes();
        standard_sizes_combo = new Gtk.ComboBox();
        Gtk.CellRendererText standard_sizes_combo_text_renderer =
            new Gtk.CellRendererText();
        standard_sizes_combo.pack_start(standard_sizes_combo_text_renderer, true);
        standard_sizes_combo.add_attribute(standard_sizes_combo_text_renderer,
            "text", 0);
        standard_sizes_combo.set_row_separator_func(standard_sizes_combo_separator_func);
        Gtk.ListStore standard_sizes_combo_store = new Gtk.ListStore(1, typeof(string),
            typeof(string));
        Gtk.TreeIter iter;
        foreach (StandardPrintSize size in standard_sizes) {
            standard_sizes_combo_store.append(out iter);
            standard_sizes_combo_store.set_value(iter, 0, size.name);
        }
        standard_sizes_combo.set_model(standard_sizes_combo_store);
        Gtk.Alignment standard_sizes_combo_aligner =
            new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        standard_sizes_combo_aligner.add(standard_sizes_combo);
        master_layouter.attach(standard_sizes_combo_aligner, 2, 3, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 4);

        Gtk.HBox custom_entries_layouter = new Gtk.HBox(false, 0);
        custom_width_entry = new Gtk.Entry();
        custom_width_entry.set_size_request(48, -1);
        custom_width_entry.insert_text.connect(on_entry_insert_text);
        custom_width_entry.focus_out_event.connect(on_width_entry_focus_out);
        custom_height_entry = new Gtk.Entry();
        custom_height_entry.set_size_request(48, -1);
        custom_height_entry.insert_text.connect(on_entry_insert_text);
        custom_height_entry.focus_out_event.connect(on_height_entry_focus_out);
        Gtk.Label custom_mulsign_label = new Gtk.Label(" x ");
        units_combo = new Gtk.ComboBox.text();
        units_combo.append_text(_("in."));
        units_combo.append_text(_("cm"));
        units_combo.set_active(0);
        units_combo.changed.connect(on_units_combo_changed);
        custom_entries_layouter.add(custom_height_entry);
        custom_entries_layouter.add(custom_mulsign_label);
        custom_entries_layouter.add(custom_width_entry);
        Gtk.SeparatorToolItem pre_units_spacer = new Gtk.SeparatorToolItem();
        pre_units_spacer.set_size_request(2, -1);
        pre_units_spacer.set_draw(false);
        custom_entries_layouter.add(pre_units_spacer);
        Gtk.Alignment units_combo_aligner =
            new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        units_combo_aligner.add(units_combo);
        custom_entries_layouter.add(units_combo_aligner);
        master_layouter.attach(custom_entries_layouter, 2, 3, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 4);

        aspect_ratio_check =
            new Gtk.CheckButton.with_mnemonic(_("_Match photo aspect ratio"));
        master_layouter.attach(aspect_ratio_check, 2, 3, 3, 4,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 2);

        Gtk.SeparatorToolItem size_ppi_spacer = new Gtk.SeparatorToolItem();
        size_ppi_spacer.set_size_request(-1, 20);
        size_ppi_spacer.set_draw(false);
        master_layouter.attach(size_ppi_spacer, 0, 2, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 8);

        Gtk.Label ppi_header = new Gtk.Label("");
        ppi_header.set_markup("<b>" + _("Pixel Resolution") + "</b>");
        master_layouter.attach(ppi_header, 0, 3, 6, 7,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 4);
        ppi_header.set_alignment(0.0f, 0.5f);

        Gtk.HBox ppi_entry_layouter = new Gtk.HBox(false, 0);
        Gtk.Label ppi_entry_title = new Gtk.Label.with_mnemonic(_("_Output photo at:"));
        ppi_entry_title.set_alignment(0.0f, 0.5f);
        ppi_entry_layouter.add(ppi_entry_title);
        ppi_entry = new Gtk.Entry();
        ppi_entry.focus_out_event.connect(on_ppi_entry_focus_out);
        ppi_entry.insert_text.connect(on_ppi_entry_insert_text);
        ppi_entry_title.set_mnemonic_widget(ppi_entry);
        ppi_entry.set_size_request(60, -1);
        Gtk.Alignment ppi_entry_aligner =
            new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        ppi_entry_aligner.add(ppi_entry);
        ppi_entry_layouter.add(ppi_entry_aligner);
        Gtk.Label ppi_units_label = new Gtk.Label(_("pixels per inch"));
        ppi_entry_layouter.add(ppi_units_label);
        ppi_units_label.set_alignment(0.0f, 0.5f);
        Gtk.SeparatorToolItem ppi_entry_right_padding = new Gtk.SeparatorToolItem();
        ppi_entry_right_padding.set_size_request(-1, -1);
        ppi_entry_right_padding.set_draw(false);
        ppi_entry_layouter.add(ppi_entry_right_padding);
        master_layouter.attach(ppi_entry_layouter, 1, 3, 7, 8,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 9, 4);

        Gtk.HBox horiz_packer = new Gtk.HBox(false, 8);
        horiz_packer.add(master_layouter);
        Gtk.SeparatorToolItem right_padding = new Gtk.SeparatorToolItem();
        right_padding.set_size_request(50, -1);
        right_padding.set_draw(false);
        horiz_packer.add(right_padding);
        inner_wrapper.add(horiz_packer);
        Gtk.SeparatorToolItem bottom_padding = new Gtk.SeparatorToolItem();
        bottom_padding.set_size_request(-1, 40);
        bottom_padding.set_draw(false);
        inner_wrapper.add(bottom_padding);

        put(inner_wrapper, 8, 8);
        inner_wrapper.set_size_request(400, 340);

        sync_state_from_job(source_job);

        show_all();

        /* connect this signal after state is sync'd */
        aspect_ratio_check.clicked.connect(on_aspect_ratio_check_clicked);
    }

    private void on_aspect_ratio_check_clicked() {
        if (aspect_ratio_check.get_active()) {
            local_content_width =
                Measurement(local_content_height.value * source_job.get_source_aspect_ratio(),
                local_content_height.unit);
            custom_width_entry.set_text(format_measurement(local_content_width));
        }
    }

    private bool on_width_entry_focus_out(Gdk.EventFocus event) {
        if (custom_width_entry.get_text() == (format_measurement_as(local_content_width,
            get_user_unit_choice())))
            return false;

        Measurement new_width = get_width_entry_value();
        Measurement min_width = source_job.get_local_settings().get_minimum_content_dimension();
        Measurement max_width = source_job.get_local_settings().get_maximum_content_dimension();

        if (new_width.is_less_than(min_width) || new_width.is_greater_than(max_width)) {
            custom_width_entry.set_text(format_measurement(local_content_width));
            return false;
        }

        if (is_match_aspect_ratio_enabled()) {
            Measurement new_height =
                Measurement(new_width.value / source_job.get_source_aspect_ratio(),
                new_width.unit);
            local_content_height = new_height;
            custom_height_entry.set_text(format_measurement(new_height));
        }

        local_content_width = new_width;
        custom_width_entry.set_text(format_measurement(new_width));
        return false;
    }

    private string format_measurement(Measurement measurement) {
        return "%.2f".printf(measurement.value);
    }

    private string format_measurement_as(Measurement measurement, MeasurementUnit to_unit) {
        Measurement converted_measurement = (measurement.unit == to_unit) ? measurement :
            measurement.convert_to(to_unit);
        return format_measurement(converted_measurement);
    }

    private bool on_ppi_entry_focus_out(Gdk.EventFocus event) {
        set_content_ppi(ppi_entry.get_text().to_int());
        return false;
    }

    private void on_ppi_entry_insert_text(Gtk.Editable editable, string text, int length,
        void *position) {
        Gtk.Entry sender = (Gtk.Entry) editable;
        
        if (is_text_insertion_in_progress)
            return;

        is_text_insertion_in_progress = true;
        
        if (length == -1)
            length = (int) text.length;

        string new_text = "";
        for (int ctr = 0; ctr < length; ctr++) {
            if (text[ctr].isdigit())
                new_text += ((char) text[ctr]).to_string();
        }

        if (new_text.length > 0)
            sender.insert_text(new_text, (int) new_text.length, position);

        Signal.stop_emission_by_name(sender, "insert-text");

        is_text_insertion_in_progress = false;
    }

    private bool on_height_entry_focus_out(Gdk.EventFocus event) {
        if (custom_height_entry.get_text() == (format_measurement_as(local_content_height,
            get_user_unit_choice())))
            return false;

        Measurement new_height = get_height_entry_value();
        Measurement min_height = source_job.get_local_settings().get_minimum_content_dimension();
        Measurement max_height = source_job.get_local_settings().get_maximum_content_dimension();

        if (new_height.is_less_than(min_height) || new_height.is_greater_than(max_height)) {
            custom_height_entry.set_text(format_measurement(local_content_height));
            return false;
        }

        if (is_match_aspect_ratio_enabled()) {
            Measurement new_width =
                Measurement(new_height.value * source_job.get_source_aspect_ratio(),
                new_height.unit);
            local_content_width = new_width;
            custom_width_entry.set_text(format_measurement(new_width));
        }

        local_content_height = new_height;
        custom_height_entry.set_text(format_measurement(new_height));
        return false;
    }

    private MeasurementUnit get_user_unit_choice() {
        if (units_combo.get_active() == INCHES_COMBO_CHOICE) {
            return MeasurementUnit.INCHES;
        } else if (units_combo.get_active() == CENTIMETERS_COMBO_CHOICE) {
            return MeasurementUnit.CENTIMETERS;
        } else {
            error("unknown unit combo box choice");
        }
    }

    private void set_user_unit_choice(MeasurementUnit unit) {
        if (unit == MeasurementUnit.INCHES) {
            units_combo.set_active(INCHES_COMBO_CHOICE);
        } else if (unit == MeasurementUnit.CENTIMETERS) {
            units_combo.set_active(CENTIMETERS_COMBO_CHOICE);
        } else {
            error("unknown MeasurementUnit enumeration");
        }
    }

    private Measurement get_width_entry_value() {
        return Measurement(custom_width_entry.get_text().to_double(),
            get_user_unit_choice());
    }

    private Measurement get_height_entry_value() {
        return Measurement(custom_height_entry.get_text().to_double(),
            get_user_unit_choice());
    }

    private void on_entry_insert_text(Gtk.Editable editable, string text, int length, void *position) {
        Gtk.Entry sender = (Gtk.Entry) editable;
        
        if (is_text_insertion_in_progress)
            return;

        is_text_insertion_in_progress = true;
        
        if (length == -1)
            length = (int) text.length;

        string decimal_point = Intl.localeconv().decimal_point;
        bool contains_decimal_point = sender.get_text().contains(decimal_point);

        string new_text = "";
        for (int ctr = 0; ctr < length; ctr++) {
            if (text[ctr].isdigit()) {
                new_text += ((char) text[ctr]).to_string();
            } else if ((!contains_decimal_point) && (text[ctr] == decimal_point[0])) {
                new_text += ((char) text[ctr]).to_string();
            }
        }

        if (new_text.length > 0)
            sender.insert_text(new_text, (int) new_text.length, position);

        Signal.stop_emission_by_name(sender, "insert-text");

        is_text_insertion_in_progress = false;
    }

    private void sync_state_from_job(PrintJob job) {
        assert(job.get_local_settings().get_content_width().unit ==
            job.get_local_settings().get_content_height().unit);
        
        Measurement constrained_width = job.get_local_settings().get_content_width();
        if (job.get_local_settings().is_match_aspect_ratio_enabled())
            constrained_width = Measurement(job.get_local_settings().get_content_height().value *
                job.get_source_aspect_ratio(), job.get_local_settings().get_content_height().unit);
        set_content_width(constrained_width);
        set_content_height(job.get_local_settings().get_content_height());
        set_content_layout(job.get_local_settings().get_content_layout());
        set_content_ppi(job.get_local_settings().get_content_ppi());
        set_size_selection(job.get_local_settings().get_size_selection());
        set_match_aspect_ratio_enabled(job.get_local_settings().is_match_aspect_ratio_enabled());
    }

    private void on_radio_group_click(Gtk.Button b) {
        Gtk.RadioButton sender = (Gtk.RadioButton) b;
        
        if (sender == standard_size_radio) {
            set_content_layout_control_state(ContentLayout.STANDARD_SIZE);
            standard_sizes_combo.grab_focus();
        } else if (sender == custom_size_radio) {
            set_content_layout_control_state(ContentLayout.CUSTOM_SIZE);
            custom_height_entry.grab_focus();
        } else if (sender == fill_page_radio) {
            set_content_layout_control_state(ContentLayout.FILL_PAGE);
        }
    }

    private void on_units_combo_changed() {
        custom_height_entry.set_text(format_measurement_as(local_content_height,
            get_user_unit_choice()));
        custom_width_entry.set_text(format_measurement_as(local_content_width,
            get_user_unit_choice()));
    }

    private void set_content_layout_control_state(ContentLayout layout) {
        switch (layout) {
            case ContentLayout.STANDARD_SIZE:
                standard_sizes_combo.set_sensitive(true);
                units_combo.set_sensitive(false);
                custom_width_entry.set_sensitive(false);
                custom_height_entry.set_sensitive(false);
                aspect_ratio_check.set_sensitive(false);
            break;

            case ContentLayout.CUSTOM_SIZE:
                standard_sizes_combo.set_sensitive(false);
                units_combo.set_sensitive(true);
                custom_width_entry.set_sensitive(true);
                custom_height_entry.set_sensitive(true);
                aspect_ratio_check.set_sensitive(true);
            break;

            case ContentLayout.FILL_PAGE:
                standard_sizes_combo.set_sensitive(false);
                units_combo.set_sensitive(false);
                custom_width_entry.set_sensitive(false);
                custom_height_entry.set_sensitive(false);
                aspect_ratio_check.set_sensitive(false);
            break;

            default:
                error("unknown ContentLayout enumeration value");
        }
    }

    private static bool standard_sizes_combo_separator_func(Gtk.TreeModel model,
        Gtk.TreeIter iter) {
        Value val;
        model.get_value(iter, 0, out val);

        return (val.dup_string() == "-");
    }

    private void set_content_layout(ContentLayout content_layout) {
        set_content_layout_control_state(content_layout);
        switch (content_layout) {
            case ContentLayout.STANDARD_SIZE:
                standard_size_radio.set_active(true);
            break;

            case ContentLayout.CUSTOM_SIZE:
                custom_size_radio.set_active(true);
            break;

            case ContentLayout.FILL_PAGE:
                fill_page_radio.set_active(true);
            break;

            default:
                error("unknown ContentLayout enumeration value");
        }
    }

    private ContentLayout get_content_layout() {
        if (standard_size_radio.get_active())
            return ContentLayout.STANDARD_SIZE;
        if (custom_size_radio.get_active())
            return ContentLayout.CUSTOM_SIZE;
        if (fill_page_radio.get_active())
            return ContentLayout.FILL_PAGE;

        error("inconsistent content layout radio button group state");
    }

    private void set_content_width(Measurement content_width) {
        if (content_width.unit != local_content_height.unit) {
            set_user_unit_choice(content_width.unit);
            local_content_height = local_content_height.convert_to(content_width.unit);
            custom_height_entry.set_text(format_measurement(local_content_height));
        }
        local_content_width = content_width;
        custom_width_entry.set_text(format_measurement(content_width));
    }

    private Measurement get_content_width() {
        return local_content_width;
    }

    private void set_content_height(Measurement content_height) {
        if (content_height.unit != local_content_width.unit) {
            set_user_unit_choice(content_height.unit);
            local_content_width = local_content_width.convert_to(content_height.unit);
            custom_width_entry.set_text(format_measurement(local_content_width));
        }
        local_content_height = content_height;
        custom_height_entry.set_text(format_measurement(content_height));
    }

    private Measurement get_content_height() {
        return local_content_height;
    }

    private void set_content_ppi(int content_ppi) {
        local_content_ppi = content_ppi.clamp(PrintSettings.MIN_CONTENT_PPI,
            PrintSettings.MAX_CONTENT_PPI);

        ppi_entry.set_text("%d".printf(local_content_ppi));
    }

    private int get_content_ppi() {
        return local_content_ppi;
    }

    private void set_size_selection(int size_selection) {
        standard_sizes_combo.set_active(size_selection);
    }

    private int get_size_selection() {
        return standard_sizes_combo.get_active();
    }

    private void set_match_aspect_ratio_enabled(bool enable_state) {
        aspect_ratio_check.set_active(enable_state);
    }

    private bool is_match_aspect_ratio_enabled() {
        return aspect_ratio_check.get_active();
    }

    public PrintJob get_source_job() {
        return source_job;
    }

    public PrintSettings get_local_settings() {
        PrintSettings result = PrintSettings();

        result.set_content_width(get_content_width());
        result.set_content_height(get_content_height());
        result.set_content_layout(get_content_layout());
        result.set_content_ppi(get_content_ppi());
        result.set_size_selection(get_size_selection());
        result.set_match_aspect_ratio_enabled(is_match_aspect_ratio_enabled());

        return result;
    }
}

public class PrintJob : Gtk.PrintOperation {
    private Photo source_photo;
    private PrintSettings settings;

    public PrintJob(Photo source_photo) {
        this.settings = PrintManager.get_instance().get_global_settings();
        this.source_photo = source_photo;
        set_embed_page_setup (true);
        double photo_aspect_ratio =  source_photo.get_dimensions().get_aspect_ratio();
        if (photo_aspect_ratio < 1.0)
            photo_aspect_ratio = 1.0 / photo_aspect_ratio;
    }

    public Photo get_source_photo() {
        return source_photo;
    }

    public double get_source_aspect_ratio() {
        double aspect_ratio = source_photo.get_dimensions().get_aspect_ratio();
        return (aspect_ratio < 1.0) ? (1.0 / aspect_ratio) : aspect_ratio;
    }

    public PrintSettings get_local_settings() {
        return settings;
    }

    public void set_local_settings(PrintSettings settings) {
        this.settings = settings;
    }
}

public struct StandardPrintSize {
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
    private Gtk.PageSetup user_page_setup;
    private CustomPrintTab custom_tab;

    private PrintManager() {
        user_page_setup = new Gtk.PageSetup();
        settings = PrintSettings();
    }

    public StandardPrintSize[] get_standard_sizes() {
        StandardPrintSize[] result = new StandardPrintSize[0];

        result += StandardPrintSize(_("Wallet (2 x 3 in.)"),
            Measurement(3, MeasurementUnit.INCHES),
            Measurement(2, MeasurementUnit.INCHES));
        result += StandardPrintSize(_("Notecard (3 x 5 in.)"),
            Measurement(5, MeasurementUnit.INCHES),
            Measurement(3, MeasurementUnit.INCHES));
        result += StandardPrintSize(_("4 x 6 in."),
            Measurement(6, MeasurementUnit.INCHES),
            Measurement(4, MeasurementUnit.INCHES));
        result += StandardPrintSize(_("5 x 7 in."),
            Measurement(7, MeasurementUnit.INCHES),
            Measurement(5, MeasurementUnit.INCHES));
        result += StandardPrintSize(_("8 x 10 in."),
            Measurement(10, MeasurementUnit.INCHES),
            Measurement(8, MeasurementUnit.INCHES));
        result += StandardPrintSize(_("11 x 14 in."),
            Measurement(14, MeasurementUnit.INCHES),
            Measurement(11, MeasurementUnit.INCHES));
        result += StandardPrintSize(_("16 x 20 in."),
            Measurement(20, MeasurementUnit.INCHES),
            Measurement(16, MeasurementUnit.INCHES));
        result += StandardPrintSize(("-"),
            Measurement(0, MeasurementUnit.INCHES),
            Measurement(0, MeasurementUnit.INCHES));
        result += StandardPrintSize(_("Metric Wallet (9 x 13 cm)"),
            Measurement(13, MeasurementUnit.CENTIMETERS),
            Measurement(9, MeasurementUnit.CENTIMETERS));
        result += StandardPrintSize(_("Postcard (10 x 15 cm)"),
            Measurement(15, MeasurementUnit.CENTIMETERS),
            Measurement(10, MeasurementUnit.CENTIMETERS));
        result += StandardPrintSize(_("13 x 18 cm"),
            Measurement(18, MeasurementUnit.CENTIMETERS),
            Measurement(13, MeasurementUnit.CENTIMETERS));
        result += StandardPrintSize(_("18 x 24 cm"),
            Measurement(24, MeasurementUnit.CENTIMETERS),
            Measurement(18, MeasurementUnit.CENTIMETERS));
        result += StandardPrintSize(_("20 x 30 cm"),
            Measurement(30, MeasurementUnit.CENTIMETERS),
            Measurement(20, MeasurementUnit.CENTIMETERS));
        result += StandardPrintSize(_("24 x 40 cm"),
            Measurement(40, MeasurementUnit.CENTIMETERS),
            Measurement(24, MeasurementUnit.CENTIMETERS));
        result += StandardPrintSize(_("30 x 40 cm"),
            Measurement(40, MeasurementUnit.CENTIMETERS),
            Measurement(30, MeasurementUnit.CENTIMETERS));

        return result;
    }

    public static PrintManager get_instance() {
        if (instance == null)
            instance = new PrintManager();

        return instance;
    }

    public void spool_photo(Photo source_photo) {
        PrintJob job = new PrintJob(source_photo);
        job.set_custom_tab_label(_("Image Settings"));
        job.set_unit(Gtk.Unit.INCH);
        job.set_n_pages(1);
        job.set_job_name(source_photo.get_name());
        job.set_default_page_setup(user_page_setup);
        job.draw_page.connect(on_draw_page);
        job.create_custom_widget.connect(on_create_custom_widget);

        Gtk.PrintOperationResult job_result;

        try {
            job_result = job.run(Gtk.PrintOperationAction.PRINT_DIALOG,
                AppWindow.get_instance());
            if (job_result == Gtk.PrintOperationResult.APPLY) {
                user_page_setup = job.get_default_page_setup();
            }
        } catch (Error e) {
            job.cancel();
            AppWindow.error_message(_("Unable to print photo:\n\n%s").printf(e.message));
        }
    }

    private void on_draw_page(Gtk.PrintOperation emitting_object,
        Gtk.PrintContext job_context, int page_num) {
        PrintJob job = (PrintJob) emitting_object;

        configure_photo_transformation(job, job_context);
        Cairo.Context dc = job_context.get_cairo_context();
        dc.paint();
    }

    private unowned Object on_create_custom_widget(Gtk.PrintOperation emitting_object) {
        custom_tab = new CustomPrintTab((PrintJob) emitting_object);
        ((PrintJob) emitting_object).custom_widget_apply.connect(on_custom_widget_apply);
        return custom_tab;
    }

    private void on_custom_widget_apply(Gtk.Widget custom_widget) {
        CustomPrintTab tab = (CustomPrintTab) custom_widget;
        tab.get_source_job().set_local_settings(tab.get_local_settings());
        set_global_settings(tab.get_local_settings());
    }

    private void configure_photo_transformation(PrintJob job, Gtk.PrintContext job_context) {
        switch (job.get_local_settings().get_content_layout()) {
            case ContentLayout.FILL_PAGE:
                configure_fill_page_transformation(job, job_context);
            break;

            case ContentLayout.STANDARD_SIZE:
            case ContentLayout.CUSTOM_SIZE:
                configure_fixed_size_transformation(job, job_context);
            break;

            default:
                error("unknown or unsupported layout mode");
        }
    }

    private void configure_fill_page_transformation(PrintJob job, Gtk.PrintContext job_context) {
        Cairo.Context dc = job_context.get_cairo_context();
        Gtk.PageSetup page_setup = job_context.get_page_setup();
        Dimensions photo_dimensions = job.get_source_photo().get_dimensions();
        double photo_aspect_ratio = photo_dimensions.get_aspect_ratio();
        int major_axis_num_pixels = 0;

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
            major_axis_num_pixels = (int)(target_width *
                job.get_local_settings().get_content_ppi() + 0.5);
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
            major_axis_num_pixels = (int)(target_height *
                job.get_local_settings().get_content_ppi() + 0.5);
        }

        double x_offset = (page_setup.get_page_width(Gtk.Unit.INCH) - target_width) / 2.0;
        double y_offset = (page_setup.get_page_height(Gtk.Unit.INCH) - target_height) / 2.0;

        double inv_dpi = 1.0 / ((double) job.get_local_settings().get_content_ppi());
        dc.translate(x_offset, y_offset);
        dc.scale(inv_dpi, inv_dpi);

        Scaling pixbuf_scaling = Scaling.for_best_fit(major_axis_num_pixels, true);
        try {
            Gdk.Pixbuf photo_pixbuf = job.get_source_photo().get_pixbuf(Scaling.for_original());
            photo_pixbuf = pixbuf_scaling.perform_on_pixbuf(photo_pixbuf, Gdk.InterpType.HYPER,
                true);
            Gdk.cairo_set_source_pixbuf(dc, photo_pixbuf, 0.0, 0.0);
        } catch (Error e) {
            job.cancel();
            AppWindow.error_message(_("Unable to print photo:\n\n%s").printf(e.message));
        }
    }

    private void configure_fixed_size_transformation(PrintJob job, Gtk.PrintContext job_context) {
        Cairo.Context dc = job_context.get_cairo_context();
        Dimensions orig_photo_dimensions = job.get_source_photo().get_dimensions();
        double emulsion_width = 0.0;
        double emulsion_height = 0.0;
        if (job.get_local_settings().get_content_layout() == ContentLayout.STANDARD_SIZE) {
            emulsion_width = get_standard_sizes()[
                job.get_local_settings().get_size_selection()].width.convert_to(
                MeasurementUnit.INCHES).value;
            emulsion_height = get_standard_sizes()[
                job.get_local_settings().get_size_selection()].height.convert_to(
                MeasurementUnit.INCHES).value;
        } else {
            emulsion_width = job.get_local_settings().get_content_width().convert_to(
                MeasurementUnit.INCHES).value;
            emulsion_height = job.get_local_settings().get_content_height().convert_to(
                MeasurementUnit.INCHES).value;
        }      
        double orig_photo_aspect_ratio = orig_photo_dimensions.get_aspect_ratio();
        double emulsion_aspect_ratio = emulsion_width / emulsion_height;
        if (((emulsion_aspect_ratio < 1.0) && (orig_photo_aspect_ratio > 1.0)) ||
            ((emulsion_aspect_ratio > 1.0) && (orig_photo_aspect_ratio < 1.0))) {
            double temp = emulsion_width;
            emulsion_width = emulsion_height;
            emulsion_height = temp;
            emulsion_aspect_ratio = 1.0 / emulsion_aspect_ratio;
        }

        Gdk.Pixbuf photo_pixbuf = null;
        try {
            photo_pixbuf = job.get_source_photo().get_pixbuf(Scaling.for_original());
        } catch (Error e) {
            AppWindow.error_message(_("Unable to print photo:\n\n%s").printf(e.message));
            
            return;
        }

        /* if the original photo's aspect ratio differs significantly from the aspect ratio
           we want the printed emulsion to have, then we have to shave pixels from the
           original photo to make its aspect ratio match that of the emulsion */
        if (!are_approximately_equal(emulsion_aspect_ratio, orig_photo_aspect_ratio)) {
            int shave_vertical = 0;
            int shave_horizontal = 0;
            if (emulsion_aspect_ratio < orig_photo_aspect_ratio) {
                shave_vertical = (int)((orig_photo_dimensions.width -
                    (orig_photo_dimensions.height * emulsion_aspect_ratio)) / 2.0);
            } else {
                shave_horizontal = (int)((orig_photo_dimensions.height -
                    (orig_photo_dimensions.width * (1.0 / emulsion_aspect_ratio))) / 2.0);
            }
            Gdk.Pixbuf shaved_pixbuf = new Gdk.Pixbuf.subpixbuf(photo_pixbuf, shave_vertical,
                shave_horizontal, orig_photo_dimensions.width - (2 * shave_vertical),
                orig_photo_dimensions.height - (2 * shave_horizontal));

            photo_pixbuf = shaved_pixbuf;
        }

        Gtk.PageSetup page_setup = job_context.get_page_setup();
        double x_offset = (page_setup.get_page_width(Gtk.Unit.INCH) - emulsion_width) / 2.0;
        double y_offset = (page_setup.get_page_height(Gtk.Unit.INCH) - emulsion_height) / 2.0;

        int major_axis_num_pixels = 0;
        if (emulsion_width > emulsion_height)
            major_axis_num_pixels = (int)(emulsion_width *
                job.get_local_settings().get_content_ppi() + 0.5);
        else
            major_axis_num_pixels = (int)(emulsion_height *
                job.get_local_settings().get_content_ppi() + 0.5);

        Scaling pixbuf_scaling = Scaling.for_best_fit(major_axis_num_pixels, true);
        photo_pixbuf = pixbuf_scaling.perform_on_pixbuf(photo_pixbuf, Gdk.InterpType.HYPER,
            true);

        double inv_dpi = 1.0 / ((double) job.get_local_settings().get_content_ppi());
        dc.translate(x_offset, y_offset);
        dc.scale(inv_dpi, inv_dpi);

        Gdk.cairo_set_source_pixbuf(dc, photo_pixbuf, 0.0, 0.0);
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

#endif
