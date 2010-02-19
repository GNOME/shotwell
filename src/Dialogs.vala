/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace ExportUI {
private static File current_export_dir = null;

public File? choose_file(File current_file) {
    if (current_export_dir == null)
        current_export_dir = File.new_for_path(Environment.get_home_dir());
        
    Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog(_("Export Photo"),
        AppWindow.get_instance(), Gtk.FileChooserAction.SAVE, Gtk.STOCK_CANCEL, 
        Gtk.ResponseType.CANCEL, Gtk.STOCK_SAVE, Gtk.ResponseType.ACCEPT, null);
    chooser.set_do_overwrite_confirmation(true);
    chooser.set_current_folder(current_export_dir.get_path());
    chooser.set_current_name(current_file.get_basename());

    File file = null;
    if (chooser.run() == Gtk.ResponseType.ACCEPT) {
        file = File.new_for_path(chooser.get_filename());
        current_export_dir = file.get_parent();
    }
    
    chooser.destroy();
    
    return file;
}

public File? choose_dir() {
    if (current_export_dir == null)
        current_export_dir = File.new_for_path(Environment.get_home_dir());

    Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog(_("Export Photos"),
        AppWindow.get_instance(), Gtk.FileChooserAction.SELECT_FOLDER, Gtk.STOCK_CANCEL, 
        Gtk.ResponseType.CANCEL, Gtk.STOCK_OK, Gtk.ResponseType.ACCEPT, null);
    chooser.set_current_folder(current_export_dir.get_path());
    
    File dir = null;
    if (chooser.run() == Gtk.ResponseType.ACCEPT) {
        dir = File.new_for_path(chooser.get_filename());
        current_export_dir = dir;
    }
    
    chooser.destroy();
    
    return dir;
}

public bool query_overwrite(File file) {
    return AppWindow.yes_no_question(_("%s already exists.  Overwrite?").printf(file.get_path()),
        _("Export Photos"));
}
}

public class ExportDialog : Gtk.Dialog {
    public const int DEFAULT_SCALE = 1200;
    public const ScaleConstraint DEFAULT_CONSTRAINT = ScaleConstraint.DIMENSIONS;
    public const Jpeg.Quality DEFAULT_QUALITY = Jpeg.Quality.HIGH;
    
    public const ScaleConstraint[] CONSTRAINT_ARRAY = { ScaleConstraint.ORIGINAL,
        ScaleConstraint.DIMENSIONS, ScaleConstraint.WIDTH, ScaleConstraint.HEIGHT };
    
    public const Jpeg.Quality[] QUALITY_ARRAY = { Jpeg.Quality.LOW, Jpeg.Quality.MEDIUM, 
        Jpeg.Quality.HIGH, Jpeg.Quality.MAXIMUM };

    private static ScaleConstraint current_constraint = ScaleConstraint.DIMENSIONS;
    private static Jpeg.Quality current_quality = Jpeg.Quality.HIGH;
    private static int current_scale = DEFAULT_SCALE;
    
    private Gtk.Table table = new Gtk.Table(0, 0, false);
    private Gtk.ComboBox quality_combo;
    private Gtk.ComboBox constraint_combo;
    private Gtk.Entry pixels_entry;
    private Gtk.Widget ok_button;
    private bool in_insert = false;
    
    public ExportDialog(string title, int default_scale = DEFAULT_SCALE, 
        ScaleConstraint default_constraint = DEFAULT_CONSTRAINT, 
        Jpeg.Quality default_quality = DEFAULT_QUALITY) {
        this.title = title;
        has_separator = false;
        allow_grow = false;
        
        // use defaults for controls
        current_scale = default_scale;
        current_constraint = default_constraint;
        current_quality = default_quality;
        
        // prepare controls
        quality_combo = new Gtk.ComboBox.text();
        int ctr = 0;
        foreach (Jpeg.Quality quality in QUALITY_ARRAY) {
            quality_combo.append_text(quality.to_string());
            if (quality == current_quality)
                quality_combo.set_active(ctr);
            ctr++;
        }
        
        constraint_combo = new Gtk.ComboBox.text();
        ctr = 0;
        foreach (ScaleConstraint constraint in CONSTRAINT_ARRAY) {
            constraint_combo.append_text(constraint.to_string());
            if (constraint == current_constraint)
                constraint_combo.set_active(ctr);
            ctr++;
        }

        pixels_entry = new Gtk.Entry();
        pixels_entry.set_max_length(6);
        pixels_entry.set_size_request(60, -1);
        pixels_entry.set_text("%d".printf(current_scale));
        
        // register after preparation to avoid signals during init
        constraint_combo.changed += on_constraint_changed;
        pixels_entry.changed += on_pixels_changed;
        pixels_entry.insert_text += on_pixels_insert_text;
        pixels_entry.activate += on_activate;

        // layout controls 
        add_label(_("_Quality:"), 0, 0, quality_combo);
        add_control(quality_combo, 1, 0);
        
        add_label(_("_Scaling constraint:"), 0, 1, constraint_combo);
        add_control(constraint_combo, 1, 1);

        Gtk.Label pixels_label = new Gtk.Label.with_mnemonic(_(" _pixels"));
        pixels_label.set_mnemonic_widget(pixels_entry);
        
        Gtk.HBox pixels_box = new Gtk.HBox(false, 0);
        pixels_box.pack_start(pixels_entry, false, false, 0);
        pixels_box.pack_end(pixels_label, false, false, 0);
        add_control(pixels_box, 1, 2);
        
        ((Gtk.VBox) get_content_area()).add(table);
        
        // add buttons to action area
        add_button(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL);
        ok_button = add_button(Gtk.STOCK_OK, Gtk.ResponseType.OK);

        ok_button.set_flags(ok_button.get_flags() | Gtk.WidgetFlags.CAN_DEFAULT | Gtk.WidgetFlags.HAS_DEFAULT);
        set_default(ok_button);

        if (current_constraint == ScaleConstraint.ORIGINAL) {
            pixels_entry.sensitive = false;
            quality_combo.sensitive = false;
        }

        ok_button.grab_focus();
    }
    
    public bool execute(out int scale, out ScaleConstraint constraint, out Jpeg.Quality quality) {
        show_all();

        bool ok = (run() == Gtk.ResponseType.OK);
        if (ok) {
            int index = constraint_combo.get_active();
            assert(index >= 0);
            constraint = CONSTRAINT_ARRAY[index];
            current_constraint = constraint;
            
            scale = pixels_entry.get_text().to_int();
            if (constraint != ScaleConstraint.ORIGINAL)
                assert(scale > 0);
            current_scale = scale;
            
            index = quality_combo.get_active();
            assert(index >= 0);
            quality = QUALITY_ARRAY[index];
            current_quality = quality;
        }
        
        destroy();
        
        return ok;
    }
    
    private void add_label(string text, int x, int y, Gtk.Widget? widget = null) {
        Gtk.Alignment left_aligned = new Gtk.Alignment(0.0f, 0.5f, 0, 0);

        Gtk.Label new_label = new Gtk.Label.with_mnemonic(text);
        new_label.set_use_underline(true);

        if (widget != null)
            new_label.set_mnemonic_widget(widget);
        
        left_aligned.add(new_label);
        
        table.attach(left_aligned, x, x + 1, y, y + 1, Gtk.AttachOptions.FILL, Gtk.AttachOptions.FILL, 
            10, 5);
    }
    
    private void add_control(Gtk.Widget widget, int x, int y) {
        Gtk.Alignment left_aligned = new Gtk.Alignment(0, 0.5f, 0, 0);
        left_aligned.add(widget);
        
        table.attach(left_aligned, x, x + 1, y, y + 1, Gtk.AttachOptions.FILL, Gtk.AttachOptions.FILL,
            10, 5);
    }
    
    private void on_constraint_changed() {
        bool original = (CONSTRAINT_ARRAY[constraint_combo.get_active()] == ScaleConstraint.ORIGINAL);
        pixels_entry.sensitive = !original;
        quality_combo.sensitive = !original;
        if (original)
            ok_button.sensitive = true;
        else
            on_pixels_changed();
    }
    
    private void on_activate() {
        response(Gtk.ResponseType.OK);
    }
    
    private void on_pixels_changed() {
        ok_button.sensitive = (pixels_entry.get_text_length() > 0) && (pixels_entry.get_text().to_int() > 0);
    }
    
    private void on_pixels_insert_text(string text, int length, void *position) {
        // This is necessary because SignalHandler.block_by_func() is not properly bound
        if (in_insert)
            return;
            
        in_insert = true;
        
        if (length == -1)
            length = (int) text.length;

        // only permit numeric text
        string new_text = "";
        for (int ctr = 0; ctr < length; ctr++) {
            if (text[ctr].isdigit()) {
                new_text += ((char) text[ctr]).to_string();
            }
        }
        
        if (new_text.length > 0)
            pixels_entry.insert_text(new_text, (int) new_text.length, position);

        Signal.stop_emission_by_name(pixels_entry, "insert-text");
        
        in_insert = false;
    }
}

namespace ImportUI {
private const int REPORT_FAILURE_COUNT = 4;

private string? generate_import_failure_list(Gee.List<BatchImportResult> failed) {
    if (failed.size == 0)
        return null;
    
    string list = "";
    for (int ctr = 0; ctr < REPORT_FAILURE_COUNT && ctr < failed.size; ctr++)
        list += "%s\n".printf(failed.get(ctr).identifier);
    
    int remaining = failed.size - REPORT_FAILURE_COUNT;
    if (remaining > 0) {
        string appendage = (ngettext("%d more photo not imported.\n",
            "%d more photos not imported.\n", remaining)).printf(remaining);
        list += appendage;
    }
    
    return list;
}

public class QuestionParams {
    public string question;
    public string yes_button;
    public string no_button;
    
    public QuestionParams(string question, string yes_button, string no_button) {
        this.question = question;
        this.yes_button = yes_button;
        this.no_button = no_button;
    }
}

// Returns true if the user selected the yes action, false otherwise.
public bool report_manifest(ImportManifest manifest, bool list, QuestionParams? question = null) {
    string message = "";
    
    if (manifest.success.size > 0) {
        string success_message = (ngettext("1 photo successfully imported.\n",
            "%d photos successfully imported.\n", manifest.success.size)).printf(
            manifest.success.size);
        message += success_message;
    }
    
    if (manifest.already_imported.size > 0) {
        if (list && message.length > 0)
            message += "\n";
        
        string already_imported_message =
            (ngettext("1 photo already in library was not imported.\n",
            "%d photos already in library were not imported.\n",
            manifest.already_imported.size)).printf(manifest.already_imported.size);

        message += already_imported_message;
        
        if (list)
            message += generate_import_failure_list(manifest.already_imported);
    }
    
    if (manifest.failed.size > 0) {
        if (list && message.length > 0)
            message += "\n";
        
        string failed_message =
            (ngettext("1 photo failed to import due to a file or hardware error.\n",
                "%d photos failed to import due to a file or hardware error.\n",
                manifest.failed.size)).printf(manifest.failed.size);

        message += failed_message;
        
        if (list)
            message += generate_import_failure_list(manifest.failed);
    }
    
    if (manifest.camera_failed.size > 0) {
        if (list && message.length > 0)
            message += "\n";
        
        string camera_failed_message =
            ngettext("1 photo failed to import due to a camera error.\n",
                "%d photos failed to import due to a camera error.\n",
                manifest.camera_failed.size).printf(manifest.camera_failed.size);
            
        message += camera_failed_message;
        
        if (list)
            message += generate_import_failure_list(manifest.camera_failed);
    }
    
    if (manifest.skipped.size > 0) {
        if (list && message.length > 0)
            message += "\n";
        
        string skipped_message = (ngettext("1 unsupported photo skipped.\n",
            "%d unsupported photos skipped.\n", manifest.skipped.size)).printf(
            manifest.skipped.size);

        message += skipped_message;
        
        if (list)
            message += generate_import_failure_list(manifest.skipped);
    }
    
    if (manifest.aborted.size > 0) {
        if (list && message.length > 0)
            message += "\n";
        
        string aborted_message = (ngettext("1 photo skipped due to user cancel.\n",
            "%d photos skipped due to user cancel.\n", manifest.aborted.size)).printf(
            manifest.aborted.size);

        message += aborted_message;
        
        if (list)
            message += generate_import_failure_list(manifest.aborted);
    }
    
    int total = manifest.success.size + manifest.failed.size + manifest.camera_failed.size
        + manifest.skipped.size + manifest.already_imported.size + manifest.aborted.size;
    assert(total == manifest.all.size);
    
    // if no photos imported at all (i.e. an empty directory attempted), need to at least report
    // that nothing was imported
    if (total == 0)
        message += _("No photos imported.\n");
    
    Gtk.MessageDialog dialog = null;
    if (question == null) {
        dialog = new Gtk.MessageDialog(AppWindow.get_instance(), Gtk.DialogFlags.MODAL,
            Gtk.MessageType.INFO, Gtk.ButtonsType.OK, "%s", message);
    } else {
        message += ("\n" + question.question);
    
        dialog = new Gtk.MessageDialog(AppWindow.get_instance(), Gtk.DialogFlags.MODAL,
            Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", message);
        dialog.add_button(question.no_button, Gtk.ResponseType.NO);
        dialog.add_button(question.yes_button, Gtk.ResponseType.YES);
    }
    
    dialog.title = _("Import Complete");
    
    bool yes = (dialog.run() == Gtk.ResponseType.YES);
    
    dialog.destroy();
    
    return yes;
}
}

public abstract class TextEntryDialog : Gtk.Dialog {
    private Gtk.Entry entry;

    public TextEntryDialog(string title, string label, string? initial_text = null) {
        set_modal(true);

        add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, 
                    Gtk.STOCK_OK, Gtk.ResponseType.OK);
        set_title(title);

        Gtk.Label name_label = new Gtk.Label(label);
        entry = new Gtk.Entry();

        if (initial_text != null)
            entry.set_text(initial_text);

        entry.set_activates_default(true);
        entry.changed += on_entry_changed;

        Gtk.HBox query = new Gtk.HBox(false, 0);
        query.pack_start(name_label, false, false, 3);
        query.pack_start(entry, false, false, 3);

        set_default_response(Gtk.ResponseType.OK);

        vbox.pack_start(query, true, false, 6);
    }

    protected string? _execute() {
        string? text = null;
        
        // validate entry to start with
        set_response_sensitive(Gtk.ResponseType.OK, on_modify_validate(entry.get_text()));

        show_all();
        
        for (;;) {
            if (run() != Gtk.ResponseType.OK)
                break;
            
            text = entry.get_text();
            if (on_ok_validate(text))
                break;
            
            text = null;
        }
        
        destroy();
        
        return text;
    }
    
    private void on_entry_changed() {
        set_response_sensitive(Gtk.ResponseType.OK, on_modify_validate(entry.get_text()));
    }
    
    protected virtual bool on_modify_validate(string text) {
        return true;
    }
    
    protected virtual bool on_ok_validate(string text) {
        return true;
    }
}

public class EventRenameDialog : TextEntryDialog {
    public EventRenameDialog(string? event_name) {
        base (_("Rename Event"), _("Name:"), event_name);
    }
    
    public string? execute() {
        return _execute();
    }
}

// Returns: Gtk.ResponseType.YES (delete photos), Gtk.ResponseType.NO (only remove photos) and
// Gtk.ResponseType.CANCEL.
public Gtk.ResponseType remove_photos_dialog(Gtk.Window owner, bool plural) {
    string msg_string = plural
        ? _("This will remove the selected photos from your Shotwell library.  Would you also like to delete the files from disk?\n\nThis action cannot be undone.")
        : _("This will remove the photo from your Shotwell library.  Would you also like to delete the file from disk?\n\nThis action cannot be undone.");
    
    Gtk.MessageDialog dialog = new Gtk.MessageDialog(owner, Gtk.DialogFlags.MODAL,
        Gtk.MessageType.WARNING, Gtk.ButtonsType.CANCEL, "%s", msg_string);
    dialog.add_button(_("Only _Remove"), Gtk.ResponseType.NO);
    dialog.add_button(Gtk.STOCK_DELETE, Gtk.ResponseType.YES);
    dialog.title = _("Remove");
    
    Gtk.ResponseType result = (Gtk.ResponseType) dialog.run();
    
    dialog.destroy();
    
    return result;
}

public class ProgressDialog : Gtk.Window {
    private Gtk.ProgressBar progress_bar = new Gtk.ProgressBar();
    private Gtk.Button cancel_button = null;
    private Cancellable cancellable;
    private uint64 last_count = uint64.MAX;
    private int update_every = 1;
    
    public ProgressDialog(Gtk.Window? owner, string text, Cancellable? cancellable = null) {
        this.cancellable = cancellable;
        
        set_title(text);
        set_resizable(false);
        if (owner != null)
            set_transient_for(owner);
        set_modal(true);
        set_position(Gtk.WindowPosition.CENTER_ON_PARENT);

        progress_bar.set_size_request(300, -1);
        
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(progress_bar, true, false, 0);
        
        if (cancellable != null) {
            cancel_button = new Gtk.Button.from_stock(Gtk.STOCK_CANCEL);
            cancel_button.clicked += on_cancel;
        }
        
        Gtk.HBox hbox = new Gtk.HBox(false, 8);
        hbox.pack_start(vbox, true, false, 0);
        if (cancel_button != null)
            hbox.pack_end(cancel_button, false, false, 0);
        
        Gtk.Alignment alignment = new Gtk.Alignment(0.5f, 0.5f, 1.0f, 1.0f);
        alignment.set_padding(12, 12, 12, 12);
        alignment.add(hbox);
        
        add(alignment);
        
        show_all();
    }
    
    public void update_display_every(int update_every) {
        assert(update_every >= 1);
        
        this.update_every = update_every;
    }
    
    public void set_fraction(int current, int total) {
        set_percentage((double) current / (double) total);
    }
    
    public void set_percentage(double pct) {
        pct = pct.clamp(0.0, 1.0);
        
        progress_bar.set_fraction(pct);
        progress_bar.set_text(_("%d%%").printf((int) (pct * 100.0)));
    }
    
    // This can be used as a ProgressMonitor delegate.
    public bool monitor(uint64 count, uint64 total) {
        if (last_count == uint64.MAX)
            last_count = count;
        
        if ((count - last_count) > update_every) {
            set_percentage((double) count / (double) total);
            spin_event_loop();
            
            last_count = count;
        }
        
        return (cancellable != null) ? !cancellable.is_cancelled() : true;
    }
    
    public void close() {
        hide();
        destroy();
    }
    
    private void on_cancel() {
        if (cancellable != null)
            cancellable.cancel();
        
        cancel_button.sensitive = false;
    }
}

public void generate_events_with_progress_dialog(Gee.List<LibraryPhoto> photos) {
    AppWindow.get_instance().set_busy_cursor();
    
    Cancellable cancellable = null;
    ProgressDialog progress = null;
    if (photos.size > 25) {
        cancellable = new Cancellable();
        progress = new ProgressDialog(AppWindow.get_instance(), _("Generating Events..."),
            cancellable);
        Event.generate_events(photos, progress.monitor);
        progress.close();
    } else {
        Event.generate_events(photos, null);
    }

    AppWindow.get_instance().set_normal_cursor();
}

public class AdjustDateTimeDialog : Gtk.Dialog {
    private const int64 SECONDS_IN_DAY = 60 * 60 * 24;
    private const int64 SECONDS_IN_HOUR = 60 * 60;
    private const int64 SECONDS_IN_MINUTE = 60;
    private const int YEAR_OFFSET = 1900;
    private bool no_original_time = false;

    time_t original_time;
    Gtk.Label original_time_label;
    Gtk.Calendar calendar;
    Gtk.SpinButton hour;
    Gtk.SpinButton minute;
    Gtk.SpinButton second;
    Gtk.ComboBox system;
    Gtk.CheckButton relativity_check_button;
    Gtk.CheckButton modify_originals_check_button;
    Gtk.Label notification;

    private enum TimeSystem {
        AM,
        PM,
        24HR;
    }    

    TimeSystem previous_time_system;

    public AdjustDateTimeDialog(PhotoSource source, int photo_count, bool display_modify_original = true) {
        assert(source != null);

        set_modal(true);
        set_resizable(false);
        set_transient_for(AppWindow.get_instance());

        add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, 
                    Gtk.STOCK_OK, Gtk.ResponseType.OK);
        set_title(_(Resources.ADJUST_DATE_TIME_LABEL));

        calendar = new Gtk.Calendar();
        calendar.day_selected += on_time_changed;
        calendar.month_changed += on_time_changed;
        calendar.next_year += on_time_changed;
        calendar.prev_year += on_time_changed;

        if (Config.get_instance().get_24_hr_time())
            hour = new Gtk.SpinButton.with_range(0, 23, 1);
        else
            hour = new Gtk.SpinButton.with_range(1, 12, 1);

        hour.output += on_spin_button_output;
        hour.set_width_chars(2);  

        minute = new Gtk.SpinButton.with_range(0, 59, 1);
        minute.set_width_chars(2);
        minute.output += on_spin_button_output;

        second = new Gtk.SpinButton.with_range(0, 59, 1);
        second.set_width_chars(2);
        second.output += on_spin_button_output;

        system = new Gtk.ComboBox.text();
        system.append_text(_("AM"));
        system.append_text(_("PM"));
        system.append_text(_("24 Hr"));
        system.changed += on_time_system_changed;

        Gtk.HBox clock = new Gtk.HBox(false, 0);

        clock.pack_start(hour, false, false, 3);
        clock.pack_start(new Gtk.Label(":"), false, false, 3); // internationalize?
        clock.pack_start(minute, false, false, 3);
        clock.pack_start(new Gtk.Label(":"), false, false, 3);
        clock.pack_start(second, false, false, 3);
        clock.pack_start(system, false, false, 3);

        set_default_response(Gtk.ResponseType.OK);

        relativity_check_button = new Gtk.CheckButton.with_mnemonic(_("Keep _Relativity"));
        relativity_check_button.set_active(Config.get_instance().get_keep_relativity());
        relativity_check_button.sensitive = photo_count > 1;

        modify_originals_check_button = new Gtk.CheckButton.with_mnemonic(ngettext(
            "_Modify Original", "_Modify Originals", photo_count));
        modify_originals_check_button.set_active(Config.get_instance().get_modify_originals() &&
            display_modify_original);
        modify_originals_check_button.sensitive = display_modify_original;

        Gtk.VBox time_content = new Gtk.VBox(false, 0);

        time_content.pack_start(calendar, true, false, 3);
        time_content.pack_start(clock, true, false, 3);
        time_content.pack_start(relativity_check_button, true, false, 3);
        time_content.pack_start(modify_originals_check_button, true, false, 3);
        
        Gdk.Pixbuf preview = null;
        try {
            preview = source.get_pixbuf(Scaling.for_viewport(Dimensions(500, 260), false));
        } catch (Error err) {
            warning("Unable to fetch preview for %s", source.to_string());
        }
        
        Gtk.VBox image_content = new Gtk.VBox(false, 0);
        Gtk.Image image = (preview != null) ? new Gtk.Image.from_pixbuf(preview) : new Gtk.Image();
        original_time_label = new Gtk.Label(null);
        image_content.pack_start(image, true, false, 3);
        image_content.pack_start(original_time_label, true, false, 3);

        Gtk.HBox hbox = new Gtk.HBox(false, 0);
        hbox.pack_start(image_content, true, false, 6);
        hbox.pack_start(time_content, true, false, 6);

        Gtk.Alignment hbox_alignment = new Gtk.Alignment(0.5f, 0.5f, 0, 0);
        hbox_alignment.set_padding(6, 3, 6, 6);
        hbox_alignment.add(hbox);

        vbox.pack_start(hbox_alignment, true, false, 6);

        notification = new Gtk.Label("");
        notification.set_line_wrap(true);
        notification.set_justify(Gtk.Justification.CENTER);
        notification.set_size_request(-1, -1);
        notification.set_padding(12, 6);

        vbox.pack_start(notification, true, true, 0);
        
        original_time = source.get_exposure_time();

        if (original_time == 0) {
            original_time = time_t();
            no_original_time = true;
        }

        set_time(Time.local(original_time));
        set_original_time_label(Config.get_instance().get_24_hr_time());
    }

    private void set_time(Time time) {
        calendar.select_month(time.month, time.year + YEAR_OFFSET);
        calendar.select_day(time.day);

        if (Config.get_instance().get_24_hr_time()) {
            hour.set_value(time.hour);
            system.set_active(TimeSystem.24HR);
        } else {
            int AMPM_hour = time.hour % 12;
            hour.set_value((AMPM_hour == 0) ? 12 : AMPM_hour);
            system.set_active((time.hour >= 12) ? TimeSystem.PM : TimeSystem.AM);
        }

        minute.set_value(time.minute);
        second.set_value(time.second);

        previous_time_system = (TimeSystem) system.get_active();
    }

    private void set_original_time_label(bool use_24_hr_format) {
        if (no_original_time)
            return;

        original_time_label.set_text(_("Original: ") + 
            Time.local(original_time).format(use_24_hr_format ? _("%m/%d/%Y, %H:%M:%S") :
            _("%m/%d/%Y, %I:%M:%S %p")));
    }

    private time_t get_time() {
        Time time = Time();

        time.second = (int) second.get_value();
        time.minute = (int) minute.get_value();

        // convert to 24 hr
        int hour = (int) hour.get_value();
        time.hour = (hour == 12 && system.get_active() != TimeSystem.24HR) ? 0 : hour;
        time.hour += ((system.get_active() == TimeSystem.PM) ? 12 : 0);

        uint year, month, day;
        calendar.get_date(out year, out month, out day);
        time.year = ((int) year) - YEAR_OFFSET;
        time.month = (int) month;
        time.day = (int) day;

        time.isdst = -1;

        return time.mktime();
    }

    public bool execute(out int64 time_shift, out bool keep_relativity, 
        out bool modify_originals) {
        show_all();

        bool response = false;

        if (run() == Gtk.ResponseType.OK) {
            if (no_original_time)
                time_shift = (int64) get_time();
            else
                time_shift = (int64) (get_time() - original_time);

            keep_relativity = relativity_check_button.get_active();

            if (relativity_check_button.sensitive)
                Config.get_instance().set_keep_relativity(keep_relativity);

            modify_originals = modify_originals_check_button.get_active();

            if (modify_originals_check_button.sensitive)
                Config.get_instance().set_modify_originals(modify_originals);

            response = true;
        }

        destroy();

        return response;
    }

    private bool on_spin_button_output(Gtk.SpinButton button) {
        button.set_text("%02d".printf((int) button.get_value()));

        on_time_changed();

        return true;
    }

    private void on_time_changed() {
        int64 time_shift = (int64) (get_time() - original_time);

        previous_time_system = (TimeSystem) system.get_active();

        if (time_shift == 0 || no_original_time) {
            notification.hide();
        } else {
            bool forward = time_shift > 0;
            int days, hours, minutes, seconds;

            time_shift = time_shift.abs();

            days = (int) (time_shift / SECONDS_IN_DAY);
            time_shift = time_shift % SECONDS_IN_DAY;
            hours = (int) (time_shift / SECONDS_IN_HOUR);
            time_shift = time_shift % SECONDS_IN_HOUR;
            minutes = (int) (time_shift / SECONDS_IN_MINUTE);
            seconds = (int) (time_shift % SECONDS_IN_MINUTE);

            string shift_status = (forward) ?
                _("Exposure time will be shifted forward by\n%d %s, %d %s, %d %s, and %d %s.") :
                _("Exposure time will be shifted backward by\n%d %s, %d %s, %d %s, and %d %s.");

            notification.set_text(shift_status.printf(days, ngettext("day", "days", days),
                hours, ngettext("hour", "hours", hours), minutes, 
                ngettext("minute", "minutes", minutes), seconds, 
                ngettext("second", "seconds", seconds)));

            notification.show();
        }
    }

    private void on_time_system_changed() {
        if (previous_time_system == system.get_active())
            return;

        Config.get_instance().set_24_hr_time(system.get_active() == TimeSystem.24HR);

        if (system.get_active() == TimeSystem.24HR) {
            int time = (hour.get_value() == 12.0) ? 0 : (int) hour.get_value();
            time = time + ((previous_time_system == TimeSystem.PM) ? 12 : 0);

            hour.set_range(0, 23);
            set_original_time_label(true);

            hour.set_value(time);
        } else {
            int AMPM_hour = ((int) hour.get_value()) % 12;

            hour.set_range(1, 12);
            set_original_time_label(false);

            hour.set_value((AMPM_hour == 0) ? 12 : AMPM_hour);
        }

        on_time_changed();
    }
}

public const int MAX_OBJECTS_DISPLAYED = 3;
public void multiple_object_error_dialog(Gee.ArrayList<DataObject> objects, string message, 
    string title) {
    string dialog_message = message + "\n";

    //add objects
    for(int i = 0; i < MAX_OBJECTS_DISPLAYED && objects.size > i; i++)
        dialog_message += "\n" + objects.get(i).to_string();

    int remainder = objects.size - MAX_OBJECTS_DISPLAYED;
    if (remainder > 0) {
        dialog_message += ngettext("\n\nAnd %d other.", "\n\nAnd %d others.",
            remainder).printf(remainder);
    }

    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(),
        Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", dialog_message);
    
    dialog.title = title;
    
    dialog.run();
    dialog.destroy();
}

public class NewTagDialog : TextEntryDialog {
    public NewTagDialog() {
        base (Resources.NEW_TAG_TITLE, _("Tag:"));
    }
    
    public string? execute() {
        return _execute();
    }
    
    protected override bool on_ok_validate(string text) {
        if (!Tag.global.exists(text))
            return true;
        
        AppWindow.error_message(_("%s already exists.  Please choose a new tag name.").printf(text),
            this);
        
        return false;
    }
}

public class RenameTagDialog : TextEntryDialog {
    private string current_name;
    
    public RenameTagDialog(string current_name) {
        base (Resources.RENAME_TAG_TITLE, _("Name:"), current_name);
        
        this.current_name = current_name;
    }
    
    public string? execute() {
        return _execute();
    }
    
    protected override bool on_modify_validate(string text) {
        return !is_string_empty(text) && text != current_name;
    }
}

public class SetTagsDialog : TextEntryDialog {
    public SetTagsDialog(string[]? current_tags) {
        base (Resources.SET_TAGS_LABEL, _("Tags (separated by commas):"), get_initial_text(current_tags));
    }
    
    private static string? get_initial_text(string[]? tags) {
        if (tags == null)
            return null;
        
        string text = null;
        foreach (string tag in tags) {
            if (text == null)
                text = "";
            else
                text += ", ";
            
            text += tag;
        }
        
        return text;
    }
    
    public string[]? execute() {
        string? text = _execute();
        if (text == null)
            return null;
        
        // return empty list if no tags specified
        if (is_string_empty(text))
            return new string[0];
        
        string[] tags = new string[0];
        
        // break up by comma-delimiter, trim whitespace, and separate into list
        string[] tokens = text.split(",");
        for (int ctr = 0; ctr < tokens.length; ctr++) {
            string stripped = tokens[ctr].strip();
            if (!is_string_empty(stripped))
                tags += stripped;
        }
        
        return tags;
    }
}

