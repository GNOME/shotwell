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
    
    int total = manifest.success.size + manifest.failed.size + manifest.skipped.size 
        + manifest.already_imported.size + manifest.aborted.size;
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

public class EventRenameDialog : Gtk.Dialog {
    Gtk.Entry name_entry;

    public EventRenameDialog(string? event_name) {
        set_modal(true);

        add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, 
                    Gtk.STOCK_OK, Gtk.ResponseType.OK);
        set_title(_("Rename Event"));

        Gtk.Label name_label = new Gtk.Label(_("Name:"));
        name_entry = new Gtk.Entry();

        if (event_name != null)
            name_entry.set_text(event_name);

        name_entry.set_activates_default(true);

        Gtk.HBox query = new Gtk.HBox(false, 0);
        query.pack_start(name_label, false, false, 3);
        query.pack_start(name_entry, false, false, 3);

        set_default_response(Gtk.ResponseType.OK);

        vbox.pack_start(query, true, false, 6);
    }

    public string? execute() {
        show_all();

        string? event_name = null;

        if (run() == Gtk.ResponseType.OK)
            event_name = name_entry.get_text();

        destroy();

        return event_name;
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
    
    public ProgressDialog(Gtk.Window owner, string text, Cancellable? cancellable = null) {
        this.cancellable = cancellable;
        
        set_title(text);
        set_resizable(false);
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
    
    public void set_fraction(int current, int total) {
        set_percentage((double) current / (double) total);
    }
    
    public void set_percentage(double pct) {
        progress_bar.set_fraction(pct);
        progress_bar.set_text(_("%d%%").printf((int) (pct * 100.0)));
    }
    
    // This can be used as a ProgressMonitor delegate.
    public bool monitor(uint64 count, uint64 total) {
        set_percentage((double) count / (double) total);
        spin_event_loop();
        
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

