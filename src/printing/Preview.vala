// SPDX-License-Identifier: LGPL-2.0-or-later
// SPDX-FileCopyrightText: 2016 Software Freedom Convervancy Inc.

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/printing_widget.ui")]
public class CustomPrintTab : Gtk.Box {
    private const int INCHES_COMBO_CHOICE = 0;
    private const int CENTIMETERS_COMBO_CHOICE = 1;

    [GtkChild]
    private unowned Gtk.CheckButton standard_size_radio;
    [GtkChild]
    private unowned Gtk.CheckButton custom_size_radio;
    [GtkChild]
    private unowned Gtk.CheckButton image_per_page_radio;
    [GtkChild]
    private unowned Gtk.DropDown image_per_page_combo;
    [GtkChild]
    private unowned Gtk.DropDown standard_sizes_combo;
    [GtkChild]
    private unowned Gtk.DropDown units_combo;
    [GtkChild]
    private unowned Gtk.Entry custom_width_entry;
    [GtkChild]
    private unowned Gtk.Entry custom_height_entry;
    [GtkChild]
    private unowned Gtk.Entry ppi_entry;
    [GtkChild]
    private unowned Gtk.CheckButton aspect_ratio_check;
    [GtkChild]
    private unowned Gtk.CheckButton title_print_check;
    [GtkChild]
    private unowned Gtk.FontButton title_print_font;

    private Measurement local_content_width = Measurement(5.0, MeasurementUnit.INCHES);
    private Measurement local_content_height = Measurement(5.0, MeasurementUnit.INCHES);
    private int local_content_ppi;
    private bool is_text_insertion_in_progress = false;
    private PrintJob source_job;

    public CustomPrintTab(PrintJob source_job) {
        this.source_job = source_job;

        standard_size_radio.toggled.connect(on_radio_group_click);
        custom_size_radio.toggled.connect(on_radio_group_click);
        image_per_page_radio.toggled.connect(on_radio_group_click);

        var model = (Gtk.StringList)image_per_page_combo.model;
        foreach (PrintLayout layout in PrintLayout.get_all()) {
            model.append(layout.to_string());
        }

        unowned StandardPrintSize[] standard_sizes = PrintManager.get_instance().get_standard_sizes();
        model = (Gtk.StringList)standard_sizes_combo.model;
        //standard_sizes_combo.set_row_separator_func(standard_sizes_combo_separator_func);
        foreach (StandardPrintSize size in standard_sizes) {
            model.append(size.name);
        }

        standard_sizes_combo.set_selected(9 * Resources.get_default_measurement_unit());

        var focus = new Gtk.EventControllerFocus();
        focus.leave.connect(on_width_entry_focus_out);
        custom_width_entry.add_controller(focus);
        custom_width_entry.insert_text.connect(on_entry_insert_text);

        focus = new Gtk.EventControllerFocus();
        focus.leave.connect(on_height_entry_focus_out);
        custom_height_entry.add_controller(focus);
        custom_height_entry.insert_text.connect(on_entry_insert_text);

        units_combo.notify["selected-item"].connect(on_units_combo_changed);
        units_combo.set_selected(Resources.get_default_measurement_unit());

        ppi_entry.insert_text.connect(on_ppi_entry_insert_text);
        focus = new Gtk.EventControllerFocus();
        focus.leave.connect(on_ppi_entry_focus_out);
        ppi_entry.add_controller(focus);

        sync_state_from_job(source_job);

        set_visible(true);

        /* connect this signal after state is sync'd */
        aspect_ratio_check.toggled.connect(on_aspect_ratio_check_clicked);
    }

    private void on_aspect_ratio_check_clicked() {
        if (aspect_ratio_check.get_active()) {
            local_content_width =
                Measurement(local_content_height.value * source_job.get_source_aspect_ratio(),
                local_content_height.unit);
            custom_width_entry.set_text(format_measurement(local_content_width));
        }
    }

    private void on_width_entry_focus_out(Gtk.EventControllerFocus event) {
        if (custom_width_entry.get_text() == (format_measurement_as(local_content_width,
            get_user_unit_choice())))
            return;

        Measurement new_width = get_width_entry_value();
        Measurement min_width = source_job.get_local_settings().get_minimum_content_dimension();
        Measurement max_width = source_job.get_local_settings().get_maximum_content_dimension();

        if (new_width.is_less_than(min_width) || new_width.is_greater_than(max_width)) {
            custom_width_entry.set_text(format_measurement(local_content_width));
            return;
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
        return;
    }

    private string format_measurement(Measurement measurement) {
        return "%.2f".printf(measurement.value);
    }

    private string format_measurement_as(Measurement measurement, MeasurementUnit to_unit) {
        Measurement converted_measurement = (measurement.unit == to_unit) ? measurement :
            measurement.convert_to(to_unit);
        return format_measurement(converted_measurement);
    }

    private void on_ppi_entry_focus_out(Gtk.EventControllerFocus event) {
        set_content_ppi(int.parse(ppi_entry.get_text()));
    }

    private void on_ppi_entry_insert_text(Gtk.Editable editable, string text, int length,
        ref int position) {
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
            sender.insert_text(new_text, (int) new_text.length, ref position);

        Signal.stop_emission_by_name(sender, "insert-text");

        is_text_insertion_in_progress = false;
    }

    private void on_height_entry_focus_out(Gtk.EventControllerFocus event) {
        if (custom_height_entry.get_text() == (format_measurement_as(local_content_height,
            get_user_unit_choice())))
            return;

        Measurement new_height = get_height_entry_value();
        Measurement min_height = source_job.get_local_settings().get_minimum_content_dimension();
        Measurement max_height = source_job.get_local_settings().get_maximum_content_dimension();

        if (new_height.is_less_than(min_height) || new_height.is_greater_than(max_height)) {
            custom_height_entry.set_text(format_measurement(local_content_height));
            return;
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
    }

    private MeasurementUnit get_user_unit_choice() {
        if (units_combo.get_selected() == INCHES_COMBO_CHOICE) {
            return MeasurementUnit.INCHES;
        } else if (units_combo.get_selected() == CENTIMETERS_COMBO_CHOICE) {
            return MeasurementUnit.CENTIMETERS;
        } else {
            error("unknown unit combo box choice");
        }
    }

    private void set_user_unit_choice(MeasurementUnit unit) {
        if (unit == MeasurementUnit.INCHES) {
            units_combo.set_selected(INCHES_COMBO_CHOICE);
        } else if (unit == MeasurementUnit.CENTIMETERS) {
            units_combo.set_selected(CENTIMETERS_COMBO_CHOICE);
        } else {
            error("unknown MeasurementUnit enumeration");
        }
    }

    private Measurement get_width_entry_value() {
        return Measurement(double.parse(custom_width_entry.get_text()), get_user_unit_choice());
    }

    private Measurement get_height_entry_value() {
        return Measurement(double.parse(custom_height_entry.get_text()), get_user_unit_choice());
    }

    private void on_entry_insert_text(Gtk.Editable editable, string text, int length,
        ref int position) {
        
        Gtk.Entry sender = (Gtk.Entry) editable;
        
        if (is_text_insertion_in_progress)
            return;

        is_text_insertion_in_progress = true;
        
        if (length == -1)
            length = (int) text.length;

        unowned string decimal_point = Posix.nl_langinfo (Posix.NLItem.RADIXCHAR);

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
            sender.insert_text(new_text, (int) new_text.length, ref position);

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
        set_image_per_page_selection(job.get_local_settings().get_image_per_page_selection());
        set_size_selection(job.get_local_settings().get_size_selection());
        set_match_aspect_ratio_enabled(job.get_local_settings().is_match_aspect_ratio_enabled());
        set_print_titles_enabled(job.get_local_settings().is_print_titles_enabled());
        set_print_titles_font(job.get_local_settings().get_print_titles_font());
    }

    private void on_radio_group_click(Gtk.CheckButton sender) {
        if (sender == standard_size_radio) {
            set_content_layout_control_state(ContentLayout.STANDARD_SIZE);
            standard_sizes_combo.grab_focus();
        } else if (sender == custom_size_radio) {
            set_content_layout_control_state(ContentLayout.CUSTOM_SIZE);
            custom_height_entry.grab_focus();
        } else if (sender == image_per_page_radio) {
            set_content_layout_control_state(ContentLayout.IMAGE_PER_PAGE);
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
                image_per_page_combo.set_sensitive(false);
            break;

            case ContentLayout.CUSTOM_SIZE:
                standard_sizes_combo.set_sensitive(false);
                units_combo.set_sensitive(true);
                custom_width_entry.set_sensitive(true);
                custom_height_entry.set_sensitive(true);
                aspect_ratio_check.set_sensitive(true);
                image_per_page_combo.set_sensitive(false);
            break;

            case ContentLayout.IMAGE_PER_PAGE:
                standard_sizes_combo.set_sensitive(false);
                units_combo.set_sensitive(false);
                custom_width_entry.set_sensitive(false);
                custom_height_entry.set_sensitive(false);
                aspect_ratio_check.set_sensitive(false);
                image_per_page_combo.set_sensitive(true);
            break;

            default:
                error("unknown ContentLayout enumeration value");
        }
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

            case ContentLayout.IMAGE_PER_PAGE:
                image_per_page_radio.set_active(true);
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
        if (image_per_page_radio.get_active())
            return ContentLayout.IMAGE_PER_PAGE;

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

    private void set_image_per_page_selection(int image_per_page) {
        image_per_page_combo.set_selected(image_per_page);
    }

    private int get_image_per_page_selection() {
        return (int)image_per_page_combo.get_selected();
    }

    private void set_size_selection(int size_selection) {
        standard_sizes_combo.set_selected(size_selection);
    }

    private int get_size_selection() {
        return (int)standard_sizes_combo.get_selected();
    }

    private void set_match_aspect_ratio_enabled(bool enable_state) {
        aspect_ratio_check.set_active(enable_state);
    }

    private void set_print_titles_enabled(bool print_titles) {
        title_print_check.set_active(print_titles);
    }

    private void set_print_titles_font(string fontname) {
        ((Gtk.FontChooser) title_print_font).set_font(fontname);
    }


    private bool is_match_aspect_ratio_enabled() {
        return aspect_ratio_check.get_active();
    }

    private bool is_print_titles_enabled() {
        return title_print_check.get_active();
    }

    private string get_print_titles_font() {
        return ((Gtk.FontChooser) title_print_font).get_font();
    }

    public PrintJob get_source_job() {
        return source_job;
    }

    public PrintSettings get_local_settings() {
        PrintSettings result = new PrintSettings();

        result.set_content_width(get_content_width());
        result.set_content_height(get_content_height());
        result.set_content_layout(get_content_layout());
        result.set_content_ppi(get_content_ppi());
        result.set_image_per_page_selection(get_image_per_page_selection());
        result.set_size_selection(get_size_selection());
        result.set_match_aspect_ratio_enabled(is_match_aspect_ratio_enabled());
        result.set_print_titles_enabled(is_print_titles_enabled());
        result.set_print_titles_font(get_print_titles_font());

        return result;
    }
}
