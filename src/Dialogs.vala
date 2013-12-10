/* Copyright 2009-2013 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// namespace for future migration of AppWindow alert and other question dialogs into single
// place: http://trac.yorba.org/ticket/3452
namespace Dialogs {

public bool confirm_delete_tag(Tag tag) {
    int count = tag.get_sources_count();
    if (count == 0)
        return true;
    string msg = ngettext(
        "This will remove the tag \"%s\" from one photo.  Continue?",
        "This will remove the tag \"%s\" from %d photos.  Continue?",
        count).printf(tag.get_user_visible_name(), count);
    
    return AppWindow.negate_affirm_question(msg, _("_Cancel"), _("_Delete"),
        Resources.DELETE_TAG_TITLE);
}

public bool confirm_delete_saved_search(SavedSearch search) {
    string msg = _("This will remove the saved search \"%s\".  Continue?")
        .printf(search.get_name());
    
    return AppWindow.negate_affirm_question(msg, _("_Cancel"), _("_Delete"),
        Resources.DELETE_SAVED_SEARCH_DIALOG_TITLE);
}

public bool confirm_warn_developer_changed(int number) {
    Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup(AppWindow.get_instance(),
        Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.NONE, "%s",
        "<span weight=\"bold\" size=\"larger\">%s</span>".printf(ngettext("Switching developers will undo all changes you have made to this photo in Shotwell",
        "Switching developers will undo all changes you have made to these photos in Shotwell", number)));

    dialog.add_buttons(Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL);
    dialog.add_buttons(_("_Switch Developer"), Gtk.ResponseType.YES);
    
    int response = dialog.run();
    
    dialog.destroy();
    
    return response == Gtk.ResponseType.YES;
}

}

namespace ExportUI {
private static File current_export_dir = null;

public File? choose_file(string current_file_basename) {
    if (current_export_dir == null)
        current_export_dir = File.new_for_path(Environment.get_home_dir());

    string file_chooser_title = VideoReader.is_supported_video_filename(current_file_basename) ?
        _("Export Video") : _("Export Photo");
        
    Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog(file_chooser_title,
        AppWindow.get_instance(), Gtk.FileChooserAction.SAVE, Gtk.Stock.CANCEL, 
        Gtk.ResponseType.CANCEL, Gtk.Stock.SAVE, Gtk.ResponseType.ACCEPT, null);
    chooser.set_do_overwrite_confirmation(true);
    chooser.set_current_folder(current_export_dir.get_path());
    chooser.set_current_name(current_file_basename);
    chooser.set_local_only(false);
    
    // The log handler reset should be removed once GTK 3.4 becomes widely available; 
    // please see https://bugzilla.gnome.org/show_bug.cgi?id=662814 for details.
    Log.set_handler("Gtk", LogLevelFlags.LEVEL_WARNING, suppress_warnings);
    File file = null;
    if (chooser.run() == Gtk.ResponseType.ACCEPT) {
        file = File.new_for_path(chooser.get_filename());
        current_export_dir = file.get_parent();
    }
    Log.set_handler("Gtk", LogLevelFlags.LEVEL_WARNING, Log.default_handler);    
    chooser.destroy();
    
    return file;
}

public File? choose_dir(string? user_title = null) {
    if (current_export_dir == null)
        current_export_dir = File.new_for_path(Environment.get_home_dir());

    if (user_title == null)
        user_title = _("Export Photos");

    Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog(user_title,
        AppWindow.get_instance(), Gtk.FileChooserAction.SELECT_FOLDER, Gtk.Stock.CANCEL, 
        Gtk.ResponseType.CANCEL, Gtk.Stock.OK, Gtk.ResponseType.ACCEPT, null);
    chooser.set_current_folder(current_export_dir.get_path());
    chooser.set_local_only(false);
    
    File dir = null;
    if (chooser.run() == Gtk.ResponseType.ACCEPT) {
        dir = File.new_for_path(chooser.get_filename());
        current_export_dir = dir;
    }
    
    chooser.destroy();
    
    return dir;
}
}

// Ticket #3023
// Attempt to replace the system error with something friendlier
// if we can't copy an image over for editing in an external tool.
public void open_external_editor_error_dialog(Error err, Photo photo) {
    // Did we fail because we can't write to this directory?
    if (err is IOError.PERMISSION_DENIED || err is FileError.PERM) {
         // Yes - display an alternate error message here.
         AppWindow.error_message(          
            _("Shotwell couldn't create a file for editing this photo because you do not have permission to write to %s.").printf(photo.get_master_file().get_parent().get_path()));
    } else {
        // No - something else is wrong, display the error message 
        // the system gave us.
        AppWindow.error_message(Resources.launch_editor_failed(err));
    }         
}

public Gtk.ResponseType export_error_dialog(File dest, bool photos_remaining) {
    string message = _("Unable to export the following photo due to a file error.\n\n") +
        dest.get_path();

    Gtk.ResponseType response = Gtk.ResponseType.NONE;

    if (photos_remaining) {
        message += _("\n\nWould you like to continue exporting?");
        response = AppWindow.affirm_cancel_question(message, _("Con_tinue"));
    } else {
        AppWindow.error_message(message);
    }

    return response;
}


public class ExportDialog : Gtk.Dialog {
    public const int DEFAULT_SCALE = 1200;

    // "Unmodified" and "Current," though they appear in the "Format:" popup menu, really
    // aren't formats so much as they are operating modes that determine specific formats.
    // Hereafter we'll refer to these as "special formats."
    public const int NUM_SPECIAL_FORMATS = 2;
    public const string UNMODIFIED_FORMAT_LABEL = _("Unmodified");
    public const string CURRENT_FORMAT_LABEL = _("Current");
    
    public const ScaleConstraint[] CONSTRAINT_ARRAY = { ScaleConstraint.ORIGINAL,
        ScaleConstraint.DIMENSIONS, ScaleConstraint.WIDTH, ScaleConstraint.HEIGHT };
    
    public const Jpeg.Quality[] QUALITY_ARRAY = { Jpeg.Quality.LOW, Jpeg.Quality.MEDIUM, 
        Jpeg.Quality.HIGH, Jpeg.Quality.MAXIMUM };

    private static ScaleConstraint current_constraint = ScaleConstraint.ORIGINAL;
    private static ExportFormatParameters current_parameters = ExportFormatParameters.current();
    private static int current_scale = DEFAULT_SCALE;
    
    private Gtk.Grid table = new Gtk.Grid();
    private Gtk.ComboBoxText quality_combo;
    private Gtk.ComboBoxText constraint_combo;
    private Gtk.ComboBoxText format_combo;
    private Gtk.CheckButton export_metadata;
    private Gee.ArrayList<string> format_options = new Gee.ArrayList<string>();
    private Gtk.Entry pixels_entry;
    private Gtk.Widget ok_button;
    private bool in_insert = false;
    
    public ExportDialog(string title) {
        this.title = title;
        resizable = false;

        quality_combo = new Gtk.ComboBoxText();
        int ctr = 0;
        foreach (Jpeg.Quality quality in QUALITY_ARRAY) {
            quality_combo.append_text(quality.to_string());
            if (quality == current_parameters.quality)
                quality_combo.set_active(ctr);
            ctr++;
        }
        
        constraint_combo = new Gtk.ComboBoxText();
        ctr = 0;
        foreach (ScaleConstraint constraint in CONSTRAINT_ARRAY) {
            constraint_combo.append_text(constraint.to_string());
            if (constraint == current_constraint)
                constraint_combo.set_active(ctr);
            ctr++;
        }

        format_combo = new Gtk.ComboBoxText();
        format_add_option(UNMODIFIED_FORMAT_LABEL);
        format_add_option(CURRENT_FORMAT_LABEL);
        foreach (PhotoFileFormat format in PhotoFileFormat.get_writeable()) {
            format_add_option(format.get_properties().get_user_visible_name());
        }

        pixels_entry = new Gtk.Entry();
        pixels_entry.set_max_length(6);
        pixels_entry.set_size_request(60, -1);
        pixels_entry.set_text("%d".printf(current_scale));
        
        // register after preparation to avoid signals during init
        constraint_combo.changed.connect(on_constraint_changed);
        format_combo.changed.connect(on_format_changed);
        pixels_entry.changed.connect(on_pixels_changed);
        pixels_entry.insert_text.connect(on_pixels_insert_text);
        pixels_entry.activate.connect(on_activate);

        // layout controls
        add_label(_("_Format:"), 0, 0, format_combo);
        add_control(format_combo, 1, 0);

        add_label(_("_Quality:"), 0, 1, quality_combo);
        add_control(quality_combo, 1, 1);
        
        add_label(_("_Scaling constraint:"), 0, 2, constraint_combo);
        add_control(constraint_combo, 1, 2);

        Gtk.Label pixels_label = new Gtk.Label.with_mnemonic(_(" _pixels"));
        pixels_label.set_mnemonic_widget(pixels_entry);
        
        Gtk.Box pixels_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        pixels_box.pack_start(pixels_entry, false, false, 0);
        pixels_box.pack_end(pixels_label, false, false, 0);
        add_control(pixels_box, 1, 3);
        
        export_metadata = new Gtk.CheckButton.with_label(_("Export metadata"));
        add_control(export_metadata, 1, 4);
        export_metadata.active = true;
        
        table.set_row_spacing(4);
        table.set_column_spacing(4);
        table.set_margin_top(4);
        table.set_margin_bottom(4);
        table.set_margin_left(4);
        table.set_margin_right(4);
        
        ((Gtk.Box) get_content_area()).add(table);
        
        // add buttons to action area
        add_button(Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL);
        ok_button = add_button(Gtk.Stock.OK, Gtk.ResponseType.OK);
        
        ok_button.set_can_default(true);
        ok_button.has_default = true;
        set_default(ok_button);

        if (current_constraint == ScaleConstraint.ORIGINAL) {
            pixels_entry.sensitive = false;
            quality_combo.sensitive = false;
        }

        ok_button.grab_focus();
    }
    
    private void format_add_option(string format_name) {
        format_options.add(format_name);
        format_combo.append_text(format_name);
    }
    
    private void format_set_active_text(string text) {
        int selection_ticker = 0;

        foreach (string current_text in format_options) {
            if (current_text == text) {
                format_combo.set_active(selection_ticker);
                return;
            }
            selection_ticker++;
        }
        
        error("format_set_active_text: text '%s' isn't in combo box", text);
    }
    
    private PhotoFileFormat get_specified_format() {
        int index = format_combo.get_active();
        if (index < NUM_SPECIAL_FORMATS)
            index = NUM_SPECIAL_FORMATS;

        index -= NUM_SPECIAL_FORMATS;
        PhotoFileFormat[] writeable_formats = PhotoFileFormat.get_writeable();
        return writeable_formats[index];
    }
    
    private string get_label_for_parameters(ExportFormatParameters params) {
        switch(params.mode) {
            case ExportFormatMode.UNMODIFIED:
                return UNMODIFIED_FORMAT_LABEL;
            
            case ExportFormatMode.CURRENT:
                return CURRENT_FORMAT_LABEL;
            
            case ExportFormatMode.SPECIFIED:
                return params.specified_format.get_properties().get_user_visible_name();            
            
            default:
                error("get_label_for_parameters: unrecognized export format mode");
        }
    }
    
    // unlike other parameters, which should be persisted across dialog executions, the
    // format parameters must be set each time the dialog is executed -- this is why
    // it's passed qualified as ref and not as out
    public bool execute(out int scale, out ScaleConstraint constraint,
        ref ExportFormatParameters parameters) {
        show_all();

        // if the export format mode isn't set to last (i.e., don't use the persisted settings),
        // reset the scale constraint to original size
        if (parameters.mode != ExportFormatMode.LAST) {
            current_constraint = constraint = ScaleConstraint.ORIGINAL;
            constraint_combo.set_active(0);
        }

        if (parameters.mode == ExportFormatMode.LAST)
            parameters = current_parameters;
        else if (parameters.mode == ExportFormatMode.SPECIFIED && !parameters.specified_format.can_write())
            parameters.specified_format = PhotoFileFormat.get_system_default_format();

        format_set_active_text(get_label_for_parameters(parameters));
        on_format_changed();
        
        bool ok = (run() == Gtk.ResponseType.OK);
        if (ok) {
            int index = constraint_combo.get_active();
            assert(index >= 0);
            constraint = CONSTRAINT_ARRAY[index];
            current_constraint = constraint;
            
            scale = int.parse(pixels_entry.get_text());
            if (constraint != ScaleConstraint.ORIGINAL)
                assert(scale > 0);
            current_scale = scale;
            
            parameters.export_metadata = export_metadata.sensitive ? export_metadata.active : false;
            
            if (format_combo.get_active_text() == UNMODIFIED_FORMAT_LABEL) {
                parameters.mode = current_parameters.mode = ExportFormatMode.UNMODIFIED;
            } else if (format_combo.get_active_text() == CURRENT_FORMAT_LABEL) {
                parameters.mode = current_parameters.mode = ExportFormatMode.CURRENT;
            } else {
                parameters.mode = current_parameters.mode = ExportFormatMode.SPECIFIED;
                parameters.specified_format = current_parameters.specified_format = get_specified_format();
                if (current_parameters.specified_format == PhotoFileFormat.JFIF)
                    parameters.quality = current_parameters.quality = QUALITY_ARRAY[quality_combo.get_active()];
            }
        } else {
            scale = 0;
            constraint = ScaleConstraint.ORIGINAL;
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
        
        table.attach(left_aligned, x, y, 1, 1);
    }
    
    private void add_control(Gtk.Widget widget, int x, int y) {
        Gtk.Alignment left_aligned = new Gtk.Alignment(0, 0.5f, 0, 0);
        left_aligned.add(widget);
        
        table.attach(left_aligned, x, y, 1, 1);
    }
    
    private void on_constraint_changed() {
        bool original = CONSTRAINT_ARRAY[constraint_combo.get_active()] == ScaleConstraint.ORIGINAL;
        bool jpeg = format_combo.get_active_text() ==
            PhotoFileFormat.JFIF.get_properties().get_user_visible_name();
        pixels_entry.sensitive = !original;
        quality_combo.sensitive = !original && jpeg;
        if (original)
            ok_button.sensitive = true;
        else
            on_pixels_changed();
    }

    private void on_format_changed() {
        bool original = CONSTRAINT_ARRAY[constraint_combo.get_active()] == ScaleConstraint.ORIGINAL;
        
        if (format_combo.get_active_text() == UNMODIFIED_FORMAT_LABEL) {
            // if the user wishes to export the media unmodified, then we just copy the original
            // files, so parameterizing size, quality, etc. is impossible -- these are all
            // just as they are in the original file. In this case, we set the scale constraint to
            // original and lock out all the controls
            constraint_combo.set_active(0); /* 0 == original size */
            constraint_combo.set_sensitive(false);
            quality_combo.set_sensitive(false);
            pixels_entry.sensitive = false;
            export_metadata.active = false;
            export_metadata.sensitive = false;
        } else if (format_combo.get_active_text() == CURRENT_FORMAT_LABEL) {
            // if the user wishes to export the media in its current format, we allow sizing but
            // not JPEG quality customization, because in a batch of many photos, it's not
            // guaranteed that all of them will be JPEGs or RAWs that get converted to JPEGs. Some
            // could be PNGs, and PNG has no notion of quality. So lock out the quality control.
            // If the user wants to set JPEG quality, he or she can explicitly specify the JPEG
            // format.
            constraint_combo.set_sensitive(true);
            quality_combo.set_sensitive(false);
            pixels_entry.sensitive = !original;
            export_metadata.sensitive = true;
        } else {
            // if the user has chosen a specific format, then allow JPEG quality customization if
            // the format is JPEG and the user is re-sizing the image, otherwise, disallow JPEG
            // quality customization; always allow scaling.
            constraint_combo.set_sensitive(true);
            bool jpeg = get_specified_format() == PhotoFileFormat.JFIF;
            quality_combo.sensitive = !original && jpeg;
            export_metadata.sensitive = true;
        }
    }
    
    private void on_activate() {
        response(Gtk.ResponseType.OK);
    }
    
    private void on_pixels_changed() {
        ok_button.sensitive = (pixels_entry.get_text_length() > 0) && (int.parse(pixels_entry.get_text()) > 0);
    }
    
    private void on_pixels_insert_text(string text, int length, ref int position) {
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
            pixels_entry.insert_text(new_text, (int) new_text.length, ref position);
        
        Signal.stop_emission_by_name(pixels_entry, "insert-text");
        
        in_insert = false;
    }
}

namespace ImportUI {
private const int REPORT_FAILURE_COUNT = 4;
internal const string SAVE_RESULTS_BUTTON_NAME = _("Save Details...");
internal const string SAVE_RESULTS_FILE_CHOOSER_TITLE = _("Save Details");
internal const int SAVE_RESULTS_RESPONSE_ID = 1024;

private string? generate_import_failure_list(Gee.List<BatchImportResult> failed, bool show_dest_id) {
    if (failed.size == 0)
        return null;
    
    string list = "";
    for (int ctr = 0; ctr < REPORT_FAILURE_COUNT && ctr < failed.size; ctr++) {
        list += "%s\n".printf(show_dest_id ? failed.get(ctr).dest_identifier : 
            failed.get(ctr).src_identifier);
    }
    
    int remaining = failed.size - REPORT_FAILURE_COUNT;
    if (remaining > 0)
        list += _("(and %d more)\n").printf(remaining);
    
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

public bool import_has_photos(Gee.Collection<BatchImportResult> import_collection) {
    foreach (BatchImportResult current_result in import_collection) {
        if (current_result.file != null
            && PhotoFileFormat.get_by_file_extension(current_result.file) != PhotoFileFormat.UNKNOWN) {
            return true;
        }
    }
    return false;
}

public bool import_has_videos(Gee.Collection<BatchImportResult> import_collection) {
    foreach (BatchImportResult current_result in import_collection) {
        if (current_result.file != null && VideoReader.is_supported_video_file(current_result.file))
            return true;
    }
    return false;
}

public string get_media_specific_string(Gee.Collection<BatchImportResult> import_collection,
    string photos_msg, string videos_msg, string both_msg, string neither_msg) {
    bool has_photos = import_has_photos(import_collection);
    bool has_videos = import_has_videos(import_collection);
        
    if (has_photos && has_videos)
        return both_msg;
    else if (has_photos)
        return photos_msg;
    else if (has_videos)
        return videos_msg;
    else
        return neither_msg;
}

public string create_result_report_from_manifest(ImportManifest manifest) {
    StringBuilder builder = new StringBuilder();
    
    string header = _("Import Results Report") + " (Shotwell " + Resources.APP_VERSION + " @ " +
        TimeVal().to_iso8601() + ")\n\n";
    builder.append(header);
    
    string subhead = (ngettext("Attempted to import %d file.", "Attempted to import %d files.",
        manifest.all.size)).printf(manifest.all.size);
    subhead += " ";
    subhead += (ngettext("Of these, %d file was successfully imported.",
        "Of these, %d files were successfully imported.", manifest.success.size)).printf(
        manifest.success.size);
    subhead += "\n\n";
    builder.append(subhead);
    
    string current_file_summary = "";
    
    //
    // Duplicates
    //
    if (manifest.already_imported.size > 0) {
        builder.append(_("Duplicate Photos/Videos Not Imported:") + "\n\n");
        
        foreach (BatchImportResult result in manifest.already_imported) {
            current_file_summary = result.src_identifier + " " +
            _("duplicates existing media item") + "\n\t" +
            result.duplicate_of.get_file().get_path() + "\n\n";
            
            builder.append(current_file_summary);
        }
    }
    
    //
    // Files Not Imported Due to Camera Errors
    //
    if (manifest.camera_failed.size > 0) {
        builder.append(_("Photos/Videos Not Imported Due to Camera Errors:") + "\n\n");
        
        foreach (BatchImportResult result in manifest.camera_failed) {
            current_file_summary = result.src_identifier + "\n\t" + _("error message:") + " " +
            result.errmsg + "\n\n";
            
            builder.append(current_file_summary);
        }
    }
    
    //
    // Files Not Imported Because They Weren't Recognized as Photos or Videos
    //
    if (manifest.skipped_files.size > 0) {
        builder.append(_("Files Not Imported Because They Weren't Recognized as Photos or Videos:")
            + "\n\n");
        
        foreach (BatchImportResult result in manifest.skipped_files) {
            current_file_summary = result.src_identifier + "\n\t" + _("error message:") + " " +
            result.errmsg + "\n\n";
            
            builder.append(current_file_summary);
        }
    }
    
    //
    // Photos/Videos Not Imported Because They Weren't in a Format Shotwell Understands
    //
    if (manifest.skipped_photos.size > 0) {
        builder.append(_("Photos/Videos Not Imported Because They Weren't in a Format Shotwell Understands:")
            + "\n\n");
        
        foreach (BatchImportResult result in manifest.skipped_photos) {
            current_file_summary = result.src_identifier + "\n\t" + _("error message:") + " " +
                result.errmsg + "\n\n";
            
            builder.append(current_file_summary);
        }
    }
    
    //
    // Photos/Videos Not Imported Because Shotwell Couldn't Copy Them into its Library
    //
    if (manifest.write_failed.size > 0) {
        builder.append(_("Photos/Videos Not Imported Because Shotwell Couldn't Copy Them into its Library:")
             + "\n\n");
        
        foreach (BatchImportResult result in manifest.write_failed) {
            current_file_summary = (_("couldn't copy %s\n\tto %s")).printf(result.src_identifier,
            result.dest_identifier) + "\n\t" + _("error message:") + " " +
            result.errmsg + "\n\n";

            builder.append(current_file_summary);
        }
    }

    //
    // Photos/Videos Not Imported Because GDK Pixbuf Library Identified them as Corrupt
    //
    if (manifest.corrupt_files.size > 0) {
        builder.append(_("Photos/Videos Not Imported Because Files Are Corrupt:")
             + "\n\n");
        
        foreach (BatchImportResult result in manifest.corrupt_files) {
            current_file_summary = result.src_identifier + "\n\t" + _("error message:") + " |" +
                result.errmsg + "|\n\n";

            builder.append(current_file_summary);
        }
    }
    
    //
    // Photos/Videos Not Imported for Other Reasons
    //
    if (manifest.failed.size > 0) {
        builder.append(_("Photos/Videos Not Imported for Other Reasons:") + "\n\n");
        
        foreach (BatchImportResult result in manifest.failed) {
            current_file_summary = result.src_identifier + "\n\t" + _("error message:") + " " +
            result.errmsg + "\n\n";
            
            builder.append(current_file_summary);
        }
    }
    
    return builder.str;
}

// Summarizes the contents of an import manifest in an on-screen message window. Returns
// true if the user selected the yes action, false otherwise.
public bool report_manifest(ImportManifest manifest, bool show_dest_id, 
    QuestionParams? question = null) {
    string message = "";
    
    if (manifest.already_imported.size > 0) {
        string photos_message = (ngettext("1 duplicate photo was not imported:\n",
            "%d duplicate photos were not imported:\n",
            manifest.already_imported.size)).printf(manifest.already_imported.size);
        string videos_message = (ngettext("1 duplicate video was not imported:\n",
            "%d duplicate videos were not imported:\n",
            manifest.already_imported.size)).printf(manifest.already_imported.size);
        string both_message = (ngettext("1 duplicate photo/video was not imported:\n",
            "%d duplicate photos/videos were not imported:\n",
            manifest.already_imported.size)).printf(manifest.already_imported.size);

        message += get_media_specific_string(manifest.already_imported, photos_message,
            videos_message, both_message, both_message);
        
        message += generate_import_failure_list(manifest.already_imported, show_dest_id);
    }
    
    if (manifest.failed.size > 0) {
        if (message.length > 0)
            message += "\n";
        
        string photos_message = (ngettext("1 photo failed to import due to a file or hardware error:\n",
            "%d photos failed to import due to a file or hardware error:\n",
            manifest.failed.size)).printf(manifest.failed.size);
        string videos_message = (ngettext("1 video failed to import due to a file or hardware error:\n",
            "%d videos failed to import due to a file or hardware error:\n",
            manifest.failed.size)).printf(manifest.failed.size);
        string both_message = (ngettext("1 photo/video failed to import due to a file or hardware error:\n",
            "%d photos/videos failed to import due to a file or hardware error:\n",
            manifest.failed.size)).printf(manifest.failed.size);
        string neither_message = (ngettext("1 file failed to import due to a file or hardware error:\n",
            "%d files failed to import due to a file or hardware error:\n",
            manifest.failed.size)).printf(manifest.failed.size);
        
        message += get_media_specific_string(manifest.failed, photos_message, videos_message,
            both_message, neither_message);
        
        message += generate_import_failure_list(manifest.failed, show_dest_id);
    }
    
    if (manifest.write_failed.size > 0) {
        if (message.length > 0)
            message += "\n";
        
        string photos_message = (ngettext("1 photo failed to import because the photo library folder was not writable:\n",
            "%d photos failed to import because the photo library folder was not writable:\n",
            manifest.write_failed.size)).printf(manifest.write_failed.size);
        string videos_message = (ngettext("1 video failed to import because the photo library folder was not writable:\n",
            "%d videos failed to import because the photo library folder was not writable:\n",
            manifest.write_failed.size)).printf(manifest.write_failed.size);
        string both_message = (ngettext("1 photo/video failed to import because the photo library folder was not writable:\n",
            "%d photos/videos failed to import because the photo library folder was not writable:\n",
            manifest.write_failed.size)).printf(manifest.write_failed.size);
        string neither_message = (ngettext("1 file failed to import because the photo library folder was not writable:\n",
            "%d files failed to import because the photo library folder was not writable:\n",
            manifest.write_failed.size)).printf(manifest.write_failed.size);
        
        message += get_media_specific_string(manifest.write_failed, photos_message, videos_message,
            both_message, neither_message);
        
        message += generate_import_failure_list(manifest.write_failed, show_dest_id);
    }
    
    if (manifest.camera_failed.size > 0) {
        if (message.length > 0)
            message += "\n";

        string photos_message = (ngettext("1 photo failed to import due to a camera error:\n",
            "%d photos failed to import due to a camera error:\n",
            manifest.camera_failed.size)).printf(manifest.camera_failed.size);
        string videos_message = (ngettext("1 video failed to import due to a camera error:\n",
            "%d videos failed to import due to a camera error:\n",
            manifest.camera_failed.size)).printf(manifest.camera_failed.size);
        string both_message = (ngettext("1 photo/video failed to import due to a camera error:\n",
            "%d photos/videos failed to import due to a camera error:\n",
            manifest.camera_failed.size)).printf(manifest.camera_failed.size);
        string neither_message = (ngettext("1 file failed to import due to a camera error:\n",
            "%d files failed to import due to a camera error:\n",
            manifest.camera_failed.size)).printf(manifest.camera_failed.size);
        
        message += get_media_specific_string(manifest.camera_failed, photos_message, videos_message,
            both_message, neither_message);
        
        message += generate_import_failure_list(manifest.camera_failed, show_dest_id);
    }

    if (manifest.corrupt_files.size > 0) {
        if (message.length > 0)
            message += "\n";
        
        string photos_message = (ngettext("1 photo failed to import because it was corrupt:\n",
            "%d photos failed to import because they were corrupt:\n",
            manifest.corrupt_files.size)).printf(manifest.corrupt_files.size);
        string videos_message = (ngettext("1 video failed to import because it was corrupt:\n",
            "%d videos failed to import because they were corrupt:\n",
            manifest.corrupt_files.size)).printf(manifest.corrupt_files.size);
        string both_message = (ngettext("1 photo/video failed to import because it was corrupt:\n",
            "%d photos/videos failed to import because they were corrupt:\n",
            manifest.corrupt_files.size)).printf(manifest.corrupt_files.size);
        string neither_message = (ngettext("1 file failed to import because it was corrupt:\n",
            "%d files failed to import because it was corrupt:\n",
            manifest.corrupt_files.size)).printf(manifest.corrupt_files.size);
        
        message += get_media_specific_string(manifest.corrupt_files, photos_message, videos_message,
            both_message, neither_message);
        
        message += generate_import_failure_list(manifest.corrupt_files, show_dest_id);
    }
    
    if (manifest.skipped_photos.size > 0) {
        if (message.length > 0)
            message += "\n";
        // we have no notion of "unsupported" video files right now in Shotwell (all
        // standard container formats are supported, it's just that the streams in them
        // might or might not be interpretable), so this message does not need to be
        // media specific
        string skipped_photos_message = (ngettext("1 unsupported photo skipped:\n",
            "%d unsupported photos skipped:\n", manifest.skipped_photos.size)).printf(
            manifest.skipped_photos.size);

        message += skipped_photos_message;
        
        message += generate_import_failure_list(manifest.skipped_photos, show_dest_id);
    }

    if (manifest.skipped_files.size > 0) {
        if (message.length > 0)
            message += "\n";

        // we have no notion of "non-video" video files right now in Shotwell, so this
        // message doesn't need to be media specific
        string skipped_files_message = (ngettext("1 non-image file skipped.\n",
            "%d non-image files skipped.\n", manifest.skipped_files.size)).printf(
            manifest.skipped_files.size);

        message += skipped_files_message;
    }
    
    if (manifest.aborted.size > 0) {
        if (message.length > 0)
            message += "\n";

        string photos_message = (ngettext("1 photo skipped due to user cancel:\n",
            "%d photos skipped due to user cancel:\n",
            manifest.aborted.size)).printf(manifest.aborted.size);
        string videos_message = (ngettext("1 video skipped due to user cancel:\n",
            "%d videos skipped due to user cancel:\n",
            manifest.aborted.size)).printf(manifest.aborted.size);
        string both_message = (ngettext("1 photo/video skipped due to user cancel:\n",
            "%d photos/videos skipped due to user cancel:\n",
            manifest.aborted.size)).printf(manifest.aborted.size);
        string neither_message = (ngettext("1 file skipped due to user cancel:\n",
            "%d file skipped due to user cancel:\n",
            manifest.aborted.size)).printf(manifest.aborted.size);
        
        message += get_media_specific_string(manifest.aborted, photos_message, videos_message,
            both_message, neither_message);
        
        message += generate_import_failure_list(manifest.aborted, show_dest_id);
    }
    
    if (manifest.success.size > 0) {
        if (message.length > 0)
            message += "\n";

        string photos_message = (ngettext("1 photo successfully imported.\n",
            "%d photos successfully imported.\n",
            manifest.success.size)).printf(manifest.success.size);
        string videos_message = (ngettext("1 video successfully imported.\n",
            "%d videos successfully imported.\n",
            manifest.success.size)).printf(manifest.success.size);
        string both_message = (ngettext("1 photo/video successfully imported.\n",
            "%d photos/videos successfully imported.\n",
            manifest.success.size)).printf(manifest.success.size);
        
        message += get_media_specific_string(manifest.success, photos_message, videos_message,
            both_message, "");
    }
    
    int total = manifest.success.size + manifest.failed.size + manifest.camera_failed.size
        + manifest.skipped_photos.size + manifest.skipped_files.size + manifest.corrupt_files.size
        + manifest.already_imported.size + manifest.aborted.size + manifest.write_failed.size;
    assert(total == manifest.all.size);
    
    // if no media items were imported at all (i.e. an empty directory attempted), need to at least
    // report that nothing was imported
    if (total == 0)
        message += _("No photos or videos imported.\n");
    
    Gtk.MessageDialog dialog = null;
    int dialog_response = Gtk.ResponseType.NONE;
    if (question == null) {
        dialog = new Gtk.MessageDialog(AppWindow.get_instance(), Gtk.DialogFlags.MODAL,
            Gtk.MessageType.INFO, Gtk.ButtonsType.NONE, "%s", message);
        dialog.title = _("Import Complete");
        Gtk.Widget save_results_button = dialog.add_button(ImportUI.SAVE_RESULTS_BUTTON_NAME,
            ImportUI.SAVE_RESULTS_RESPONSE_ID);
        save_results_button.set_visible(manifest.success.size < manifest.all.size);
        Gtk.Widget ok_button = dialog.add_button(Gtk.Stock.OK, Gtk.ResponseType.OK);
        dialog.set_default(ok_button);
        
        Gtk.Window dialog_parent = (Gtk.Window) dialog.get_parent();
        dialog_response = dialog.run();
        dialog.destroy();
        
        if (dialog_response == ImportUI.SAVE_RESULTS_RESPONSE_ID)
            save_import_results(dialog_parent, create_result_report_from_manifest(manifest));

    } else {
        message += ("\n" + question.question);
        
        dialog = new Gtk.MessageDialog(AppWindow.get_instance(), Gtk.DialogFlags.MODAL,
            Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", message);
        dialog.title = _("Import Complete");
        Gtk.Widget save_results_button = dialog.add_button(ImportUI.SAVE_RESULTS_BUTTON_NAME,
            ImportUI.SAVE_RESULTS_RESPONSE_ID);
        save_results_button.set_visible(manifest.success.size < manifest.all.size);
        Gtk.Widget no_button = dialog.add_button(question.no_button, Gtk.ResponseType.NO);
        dialog.add_button(question.yes_button, Gtk.ResponseType.YES);
        dialog.set_default(no_button);
        
        dialog_response = dialog.run();
        while (dialog_response == ImportUI.SAVE_RESULTS_RESPONSE_ID) {
            save_import_results(dialog, create_result_report_from_manifest(manifest));
            dialog_response = dialog.run();
        }
        
        dialog.hide();
        dialog.destroy();
    }
    
    return (dialog_response == Gtk.ResponseType.YES);
}

internal void save_import_results(Gtk.Window? chooser_dialog_parent, string results_log) {
    Gtk.FileChooserDialog chooser_dialog = new Gtk.FileChooserDialog(
        ImportUI.SAVE_RESULTS_FILE_CHOOSER_TITLE, chooser_dialog_parent, Gtk.FileChooserAction.SAVE,
        Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, Gtk.Stock.SAVE, Gtk.ResponseType.ACCEPT, null);
    chooser_dialog.set_do_overwrite_confirmation(true);
    chooser_dialog.set_current_folder(Environment.get_home_dir());
    chooser_dialog.set_current_name("Shotwell Import Log.txt");
    chooser_dialog.set_local_only(false);
    
    int dialog_result = chooser_dialog.run();
    File? chosen_file = chooser_dialog.get_file();
    chooser_dialog.hide();
    chooser_dialog.destroy();
    
    if (dialog_result == Gtk.ResponseType.ACCEPT && chosen_file != null) {
        try {
            FileOutputStream outstream = chosen_file.replace(null, false, FileCreateFlags.NONE);
            outstream.write(results_log.data);
            outstream.close();
        } catch (Error err) {
            critical("couldn't save import results to log file %s: %s", chosen_file.get_path(),
                err.message);
        }
    }
}

}

public abstract class TextEntryDialogMediator {
    private TextEntryDialog dialog;
    
    public TextEntryDialogMediator(string title, string label, string? initial_text = null,
        Gee.Collection<string>? completion_list = null, string? completion_delimiter = null) {
        Gtk.Builder builder = AppWindow.create_builder();
        dialog = new TextEntryDialog();
        dialog.get_content_area().add((Gtk.Box) builder.get_object("dialog-vbox2"));
        dialog.set_builder(builder);
        dialog.setup(on_modify_validate, title, label, initial_text, completion_list, completion_delimiter);
    }
    
    protected virtual bool on_modify_validate(string text) {
        return true;
    }

    protected string? _execute() {
        return dialog.execute();
    }
}

public abstract class MultiTextEntryDialogMediator {
    private MultiTextEntryDialog dialog;
    
    public MultiTextEntryDialogMediator(string title, string label, string? initial_text = null) {
        Gtk.Builder builder = AppWindow.create_builder();
        dialog = new MultiTextEntryDialog();
        dialog.get_content_area().add((Gtk.Box) builder.get_object("dialog-vbox4"));
        dialog.set_builder(builder);
        dialog.setup(on_modify_validate, title, label, initial_text);
    }
    
    protected virtual bool on_modify_validate(string text) {
        return true;
    }

    protected string? _execute() {
        return dialog.execute();
    }
}


// This method takes primary and secondary texts and returns ready-to-use pango markup 
// for a HIG-compliant alert dialog. Please see 
// http://library.gnome.org/devel/hig-book/2.32/windows-alert.html.en for details.
public string build_alert_body_text(string? primary_text, string? secondary_text, bool should_escape = true) {
    if (should_escape) {
        return "<span weight=\"Bold\" size=\"larger\">%s</span>\n%s".printf(
            guarded_markup_escape_text(primary_text), guarded_markup_escape_text(secondary_text));
    }
    
    return "<span weight=\"Bold\" size=\"larger\">%s</span>\n%s".printf(
        guarded_markup_escape_text(primary_text), secondary_text);
}

// Entry completion for values separated by separators (e.g. comma in the case of tags)
// Partly inspired by the class of the same name in gtkmm-utils by Marko Anastasov
public class EntryMultiCompletion : Gtk.EntryCompletion {
    private string delimiter;
    
    public EntryMultiCompletion(Gee.Collection<string> completion_list, string? delimiter) {
        assert(delimiter == null || delimiter.length == 1);
        this.delimiter = delimiter;
        
        set_model(create_completion_store(completion_list));
        set_text_column(0);
        set_match_func(match_func);
    }
    
    private static Gtk.ListStore create_completion_store(Gee.Collection<string> completion_list) {
        Gtk.ListStore completion_store = new Gtk.ListStore(1, typeof(string));
        Gtk.TreeIter store_iter;
        Gee.Iterator<string> completion_iter = completion_list.iterator();
        while (completion_iter.next()) {
            completion_store.append(out store_iter);
            completion_store.set(store_iter, 0, completion_iter.get(), -1);
        }
        
        return completion_store;
    }
    
    private bool match_func(Gtk.EntryCompletion completion, string key, Gtk.TreeIter iter) {
        Gtk.TreeModel model = completion.get_model();
        string possible_match;
        model.get(iter, 0, out possible_match);
        
        // Normalize key and possible matches to allow comparison of non-ASCII characters.
        // Use a "COMPOSE" normalization to allow comparison to the position value returned by 
        // Gtk.Entry, i.e. one character=one position. Using the default normalization a character
        // like "é" or "ö" would have a length of two.
        possible_match = possible_match.casefold().normalize(-1, NormalizeMode.ALL_COMPOSE);
        string normed_key = key.normalize(-1, NormalizeMode.ALL_COMPOSE);
        
        if (delimiter == null) {
            return possible_match.has_prefix(normed_key.strip());
        } else {
            if (normed_key.contains(delimiter)) {
                // check whether cursor is before last delimiter
                int offset = normed_key.char_count(normed_key.last_index_of_char(delimiter[0]));
                int position = ((Gtk.Entry) get_entry()).get_position();
                if (position <= offset)
                    return false; // TODO: Autocompletion for tags not last in list
            }
            
            string last_part = get_last_part(normed_key.strip(), delimiter);
            
            if (last_part.length == 0) 
                return false; // need at least one character to show matches
                
            return possible_match.has_prefix(last_part.strip());
        }
    }

    public override bool match_selected(Gtk.TreeModel model, Gtk.TreeIter iter) {
        string match;
        model.get(iter, 0, out match);
        
        Gtk.Entry entry = (Gtk.Entry)get_entry();
        
        string old_text = entry.get_text().normalize(-1, NormalizeMode.ALL_COMPOSE);
        if (old_text.length > 0) {
            if (old_text.contains(delimiter)) {
                old_text = old_text.substring(0, old_text.last_index_of_char(delimiter[0]) + 1) + (delimiter != " " ? " " : "");
            } else
                old_text = "";
        }
        
        string new_text = old_text + match + delimiter + (delimiter != " " ? " " : "");
        entry.set_text(new_text);
        entry.set_position((int) new_text.length);
        
        return true;
    }
    
    // Find last string after any delimiter
    private static string get_last_part(string s, string delimiter) {
        string[] split = s.split(delimiter);
        
        if((split != null) && (split[0] != null)) {
            return split[split.length - 1];
        } else {
            return "";
        }
    }
}

public class SetBackgroundSlideshowDialog {
    private Gtk.Dialog dialog;
    private Gtk.Label delay_value_label;
    private Gtk.Scale delay_scale;
    private int delay_value = 0;
    
    public SetBackgroundSlideshowDialog() {
        Gtk.Builder builder = AppWindow.create_builder("set_background_dialog.glade", this);
        
        dialog = builder.get_object("dialog1") as Gtk.Dialog;
        dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG);
        dialog.set_parent_window(AppWindow.get_instance().get_parent_window());
        dialog.set_transient_for(AppWindow.get_instance());
        dialog.set_default_response(Gtk.ResponseType.OK);
        
        delay_value_label = builder.get_object("delay_value_label") as Gtk.Label;
        
        delay_scale = builder.get_object("delay_scale") as Gtk.Scale;
        delay_scale.value_changed.connect(on_delay_scale_value_changed);
        delay_scale.adjustment.value = 50;
    }

    private void on_delay_scale_value_changed() {
        double value = delay_scale.adjustment.value;
        
        // f(x)=x^5 allows to have fine-grained values (seconds) to the left
        // and very coarse-grained values (hours) to the right of the slider.
        // We limit maximum value to 1 day and minimum to 5 seconds.
        delay_value = (int) (Math.pow(value, 5) / Math.pow(90, 5) * 60 * 60 * 24 + 5);
        
        // convert to text and remove fractions from values > 1 minute
        string text;
        if (delay_value < 60) {
            text = ngettext("%d second", "%d seconds", delay_value).printf(delay_value);
        } else if (delay_value < 60 * 60) {
            int minutes = delay_value / 60;
            text = ngettext("%d minute", "%d minutes", minutes).printf(minutes);
            delay_value = minutes * 60; 
        } else if (delay_value < 60 * 60 * 24) {
            int hours = delay_value / (60 * 60);
            text = ngettext("%d hour", "%d hours", hours).printf(hours);
            delay_value = hours * (60 * 60);
        } else {
            text = _("1 day");
            delay_value = 60 * 60 * 24;
        }
        
        delay_value_label.label = text;
    }

    public bool execute(out int delay_value) {
        dialog.show_all();
        
        bool result = dialog.run() == Gtk.ResponseType.OK;
        
        dialog.destroy();
        
        delay_value = this.delay_value;
        
        return result;
    }
}

public class TextEntryDialog : Gtk.Dialog {
    public delegate bool OnModifyValidateType(string text);
    
    private unowned OnModifyValidateType on_modify_validate;
    private Gtk.Entry entry;
    private Gtk.Builder builder;
    private Gtk.Button button1;
    private Gtk.Button button2;
    private Gtk.ButtonBox action_area_box;
    
    public void set_builder(Gtk.Builder builder) {
        this.builder = builder;
    }
    
    public void setup(OnModifyValidateType? modify_validate, string title, string label, 
        string? initial_text, Gee.Collection<string>? completion_list, string? completion_delimiter) {
        set_title(title);
        set_resizable(true);
        set_default_size (350, 104);
        set_parent_window(AppWindow.get_instance().get_parent_window());
        set_transient_for(AppWindow.get_instance());
        on_modify_validate = modify_validate;

        Gtk.Label name_label = builder.get_object("label") as Gtk.Label;
        name_label.set_text(label);

        entry = builder.get_object("entry") as Gtk.Entry;
        entry.set_text(initial_text != null ? initial_text : "");
        entry.grab_focus();
        entry.changed.connect(on_entry_changed);
        
        action_area_box = (Gtk.ButtonBox) get_action_area();
        action_area_box.set_layout(Gtk.ButtonBoxStyle.END);
        
        button1 = (Gtk.Button) add_button(Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL);
        button2 = (Gtk.Button) add_button(Gtk.Stock.SAVE, Gtk.ResponseType.OK);
        set_default_response(Gtk.ResponseType.OK);
        
        if (completion_list != null) { // Textfield with autocompletion
            EntryMultiCompletion completion = new EntryMultiCompletion(completion_list,
                completion_delimiter);
            entry.set_completion(completion);
        }
        
        set_default_response(Gtk.ResponseType.OK);
        set_has_resize_grip(false);
    }

    public string? execute() {
        string? text = null;
        
        // validate entry to start with
        set_response_sensitive(Gtk.ResponseType.OK, on_modify_validate(entry.get_text()));
        
        show_all();
        
        if (run() == Gtk.ResponseType.OK)
            text = entry.get_text();
        
        entry.changed.disconnect(on_entry_changed);
        destroy();
        
        return text;
    }
    
    public void on_entry_changed() {
        set_response_sensitive(Gtk.ResponseType.OK, on_modify_validate(entry.get_text()));
    }
}

public class MultiTextEntryDialog : Gtk.Dialog {
    public delegate bool OnModifyValidateType(string text);
    
    private unowned OnModifyValidateType on_modify_validate;
    private Gtk.TextView entry;
    private Gtk.Builder builder;
    private Gtk.Button button1;
    private Gtk.Button button2;
    private Gtk.ButtonBox action_area_box;
    
    public void set_builder(Gtk.Builder builder) {
        this.builder = builder;
    }
    
    public void setup(OnModifyValidateType? modify_validate, string title, string label, string? initial_text) {
        set_title(title);
        set_resizable(true);
        set_default_size(500,300);
        set_parent_window(AppWindow.get_instance().get_parent_window());
        set_transient_for(AppWindow.get_instance());
        on_modify_validate = modify_validate;
        
        Gtk.Label name_label = builder.get_object("label9") as Gtk.Label;
        name_label.set_text(label);
        
        Gtk.ScrolledWindow scrolled = builder.get_object("scrolledwindow1") as Gtk.ScrolledWindow;
        scrolled.set_shadow_type (Gtk.ShadowType.ETCHED_IN);
        
        entry = builder.get_object("textview1") as Gtk.TextView;
        entry.set_wrap_mode (Gtk.WrapMode.WORD);
        entry.buffer = new Gtk.TextBuffer(null);
        entry.buffer.text = (initial_text != null ? initial_text : "");
        
        entry.grab_focus();
        
        action_area_box = (Gtk.ButtonBox) get_action_area();
        action_area_box.set_layout(Gtk.ButtonBoxStyle.END);
        
        button1 = (Gtk.Button) add_button(Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL);
        button2 = (Gtk.Button) add_button(Gtk.Stock.SAVE, Gtk.ResponseType.OK);
        
        set_has_resize_grip(true);
    }
        
    public string? execute() {
        string? text = null;
        
        show_all();
        
        if (run() == Gtk.ResponseType.OK)
            text = entry.buffer.text;
        
        destroy();
        
        return text;
    }
}

public class EventRenameDialog : TextEntryDialogMediator {
    public EventRenameDialog(string? event_name) {
        base (_("Rename Event"), _("Name:"), event_name);
    }

    public virtual string? execute() {
        return Event.prep_event_name(_execute());
    }
}

public class EditTitleDialog : TextEntryDialogMediator {
    public EditTitleDialog(string? photo_title) {
        base (_("Edit Title"), _("Title:"), photo_title);
    }
    
    public virtual string? execute() {
        return MediaSource.prep_title(_execute());
    }
    
    protected override bool on_modify_validate(string text) {
        return true;
    }
}

public class EditCommentDialog : MultiTextEntryDialogMediator {
    public EditCommentDialog(string? comment, bool is_event = false) {
        string title_tmp = (is_event) ? _("Edit Event Comment") : _("Edit Photo/Video Comment");
        base(title_tmp, _("Comment:"), comment);
    }
    
    public virtual string? execute() {
        return MediaSource.prep_comment(_execute());
    }
    
    protected override bool on_modify_validate(string text) {
        return true;
    }
}

// Returns: Gtk.ResponseType.YES (trash photos), Gtk.ResponseType.NO (only remove photos) and
// Gtk.ResponseType.CANCEL.
public Gtk.ResponseType remove_from_library_dialog(Gtk.Window owner, string title,
    string user_message, int count) {
    string trash_action = ngettext("_Trash File", "_Trash Files", count);
    
    Gtk.MessageDialog dialog = new Gtk.MessageDialog(owner, Gtk.DialogFlags.MODAL,
        Gtk.MessageType.WARNING, Gtk.ButtonsType.CANCEL, "%s", user_message);
    dialog.add_button(_("Only _Remove"), Gtk.ResponseType.NO);
    dialog.add_button(trash_action, Gtk.ResponseType.YES);

    // This dialog was previously created outright; we now 'hijack' 
    // dialog's old title and use it as the primary text, along with
    // using the message as the secondary text.
    dialog.set_markup(build_alert_body_text(title, user_message));
    
    Gtk.ResponseType result = (Gtk.ResponseType) dialog.run();
    
    dialog.destroy();
    
    return result;
}

// Returns: Gtk.ResponseType.YES (delete photos), Gtk.ResponseType.NO (keep photos)
public Gtk.ResponseType remove_from_filesystem_dialog(Gtk.Window owner, string title,
    string user_message) {
    Gtk.MessageDialog dialog = new Gtk.MessageDialog(owner, Gtk.DialogFlags.MODAL,
        Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", user_message);
    dialog.add_button(_("_Keep"), Gtk.ResponseType.NO);
    dialog.add_button(_("_Delete"), Gtk.ResponseType.YES);
    dialog.set_default_response( Gtk.ResponseType.NO);
   
    dialog.set_markup(build_alert_body_text(title, user_message));
    
    Gtk.ResponseType result = (Gtk.ResponseType) dialog.run();
    
    dialog.destroy();
    
    return result;
}

public bool revert_editable_dialog(Gtk.Window owner, Gee.Collection<Photo> photos) {
    int count = 0;
    foreach (Photo photo in photos) {
        if (photo.has_editable())
            count++;
    }
    
    if (count == 0)
        return false;
           
    string headline = (count == 1) ? _("Revert External Edit?") : _("Revert External Edits?");
    string msg = ngettext(
        "This will destroy all changes made to the external file.  Continue?",
        "This will destroy all changes made to %d external files.  Continue?",
        count).printf(count);

    string action = (count == 1) ? _("Re_vert External Edit") : _("Re_vert External Edits");
    
    Gtk.MessageDialog dialog = new Gtk.MessageDialog(owner, Gtk.DialogFlags.MODAL,
        Gtk.MessageType.WARNING, Gtk.ButtonsType.NONE, "%s", msg);
    dialog.add_button(_("_Cancel"), Gtk.ResponseType.CANCEL);
    dialog.add_button(action, Gtk.ResponseType.YES);

    dialog.set_markup(build_alert_body_text(headline, msg));
    
    Gtk.ResponseType result = (Gtk.ResponseType) dialog.run();
    
    dialog.destroy();
    
    return result == Gtk.ResponseType.YES;
}

public bool remove_offline_dialog(Gtk.Window owner, int count) {
    if (count == 0)
        return false;
    
    string msg = ngettext(
        "This will remove the photo from the library.  Continue?",
        "This will remove %d photos from the library.  Continue?",
        count).printf(count);
    
    Gtk.MessageDialog dialog = new Gtk.MessageDialog(owner, Gtk.DialogFlags.MODAL,
        Gtk.MessageType.WARNING, Gtk.ButtonsType.NONE, "%s", msg);
    dialog.add_button(_("_Cancel"), Gtk.ResponseType.CANCEL);
    dialog.add_button(_("_Remove"), Gtk.ResponseType.OK);
    dialog.title = (count == 1) ? _("Remove Photo From Library") : _("Remove Photos From Library");
    
    Gtk.ResponseType result = (Gtk.ResponseType) dialog.run();
    
    dialog.destroy();
    
    return result == Gtk.ResponseType.OK;
}

public class ProgressDialog : Gtk.Window {
    private Gtk.ProgressBar progress_bar = new Gtk.ProgressBar();
    private Gtk.Button cancel_button = null;
    private Cancellable cancellable;
    private uint64 last_count = uint64.MAX;
    private int update_every = 1;
    private int minimum_on_screen_time_msec = 500;
    private ulong time_started;
#if UNITY_SUPPORT
    UnityProgressBar uniprobar = UnityProgressBar.get_instance();
#endif
    
    public ProgressDialog(Gtk.Window? owner, string text, Cancellable? cancellable = null) {
        this.cancellable = cancellable;
        
        set_title(text);
        set_resizable(false);
        if (owner != null)
            set_transient_for(owner);
        set_modal(true);
        set_type_hint(Gdk.WindowTypeHint.DIALOG);
        
        progress_bar.set_size_request(300, -1);
        progress_bar.set_show_text(true);
        
        Gtk.Box vbox_bar = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        vbox_bar.pack_start(progress_bar, true, false, 0);
        
        if (cancellable != null) {
            cancel_button = new Gtk.Button.from_stock(Gtk.Stock.CANCEL);
            cancel_button.clicked.connect(on_cancel);
            delete_event.connect(on_window_closed);
        }
        
        Gtk.Box hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        hbox.pack_start(vbox_bar, true, false, 0);
        if (cancel_button != null)
            hbox.pack_end(cancel_button, false, false, 0);
        
        Gtk.Label primary_text_label = new Gtk.Label("");
        primary_text_label.set_markup("<span weight=\"bold\">%s</span>".printf(text));
        primary_text_label.set_alignment(0, 0.5f);

        Gtk.Box vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        vbox.pack_start(primary_text_label, false, false, 0);
        vbox.pack_start(hbox, true, false, 0);

        Gtk.Alignment alignment = new Gtk.Alignment(0.5f, 0.5f, 1.0f, 1.0f);
        alignment.set_padding(12, 12, 12, 12);
        alignment.add(vbox);
        
        add(alignment);
        
        time_started = now_ms();
    }
    
    public override void realize() {
        base.realize();
        
        // if unable to cancel the progress bar, remove the close button
        if (cancellable == null)
            get_window().set_functions(Gdk.WMFunction.MOVE);
    }
    
    public void update_display_every(int update_every) {
        assert(update_every >= 1);
        
        this.update_every = update_every;
    }
    
    public void set_minimum_on_screen_time_msec(int minimum_on_screen_time_msec) {
        this.minimum_on_screen_time_msec = minimum_on_screen_time_msec;
    }
    
    public void set_fraction(int current, int total) {
        set_percentage((double) current / (double) total);
    }
    
    public void set_percentage(double pct) {
        pct = pct.clamp(0.0, 1.0);
        
        maybe_show_all(pct);
        
        progress_bar.set_fraction(pct);
        progress_bar.set_text(_("%d%%").printf((int) (pct * 100.0)));
        
#if UNITY_SUPPORT
        //UnityProgressBar: set progress
        uniprobar.set_progress(pct);
#endif
    }
    
    public void set_status(string text) {
        progress_bar.set_text(text);
        
#if UNITY_SUPPORT
        //UnityProgressBar: try to draw progress bar
        uniprobar.set_visible(true);
#endif
        show_all();
    }
    
    // This can be used as a ProgressMonitor delegate.
    public bool monitor(uint64 count, uint64 total, bool do_event_loop = true) {
        if ((last_count == uint64.MAX) || (count - last_count) >= update_every) {
            set_percentage((double) count / (double) total);
            last_count = count;
        }
        
        bool keep_going = (cancellable != null) ? !cancellable.is_cancelled() : true;
        
        // TODO: get rid of this.  non-trivial, as some progress-monitor operations are blocking
        // and need to allow the event loop to spin
        //
        // Important: Since it's possible the progress dialog might be destroyed inside this call,
        // avoid referring to "this" afterwards at all costs (in case all refs have been dropped)
        
        if (do_event_loop)
            spin_event_loop();
        
        return keep_going;
    }
    
    public new void close() {
#if UNITY_SUPPORT
        //UnityProgressBar: reset
        uniprobar.reset();
#endif
        hide();
        destroy();
    }
    
    private bool on_window_closed() {
        on_cancel();
        return false; // return false so that the system handler will remove the window from
                      // the screen
    }
    
    private void on_cancel() {
        if (cancellable != null)
            cancellable.cancel();
        
        cancel_button.sensitive = false;
    }
    
    private void maybe_show_all(double pct) {
        // Appear only after a while because some jobs may take only a 
        // fraction of second to complete so there's no point in showing progress.
        if (!this.visible && now_ms() - time_started > minimum_on_screen_time_msec) {
            // calculate percents completed in one ms
            double pps = pct * 100.0 / minimum_on_screen_time_msec;
            // calculate [very rough] estimate of time to complete in ms
            double ttc = 100.0 / pps;
            // If there is still more work to do for at least MINIMUM_ON_SCREEN_TIME_MSEC, 
            // finally display the dialog.
            if (ttc > minimum_on_screen_time_msec) {
#if UNITY_SUPPORT
                //UnityProgressBar: try to draw progress bar
                uniprobar.set_visible(true);
#endif
                show_all(); 
                spin_event_loop();
            }
        }
    }
}

public class AdjustDateTimeDialog : Gtk.Dialog {
    private const int64 SECONDS_IN_DAY = 60 * 60 * 24;
    private const int64 SECONDS_IN_HOUR = 60 * 60;
    private const int64 SECONDS_IN_MINUTE = 60;
    private const int YEAR_OFFSET = 1900;
    private bool no_original_time = false;
    
    private const int CALENDAR_THUMBNAIL_SCALE = 1;

    time_t original_time;
    Gtk.Label original_time_label;
    Gtk.Calendar calendar;
    Gtk.SpinButton hour;
    Gtk.SpinButton minute;
    Gtk.SpinButton second;
    Gtk.ComboBoxText system;
    Gtk.RadioButton relativity_radio_button;
    Gtk.RadioButton batch_radio_button;
    Gtk.CheckButton modify_originals_check_button;
    Gtk.Label notification;

    private enum TimeSystem {
        AM,
        PM,
        24HR;
    }    

    TimeSystem previous_time_system;

    public AdjustDateTimeDialog(Dateable source, int photo_count, bool display_options = true,
        bool contains_video = false, bool only_video = false) {
        assert(source != null);

        set_modal(true);
        set_resizable(false);
        set_transient_for(AppWindow.get_instance());

        add_buttons(Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                    Gtk.Stock.OK, Gtk.ResponseType.OK);
        set_title(Resources.ADJUST_DATE_TIME_LABEL);

        calendar = new Gtk.Calendar();
        calendar.day_selected.connect(on_time_changed);
        calendar.month_changed.connect(on_time_changed);
        calendar.next_year.connect(on_time_changed);
        calendar.prev_year.connect(on_time_changed);

        if (Config.Facade.get_instance().get_use_24_hour_time())
            hour = new Gtk.SpinButton.with_range(0, 23, 1);
        else
            hour = new Gtk.SpinButton.with_range(1, 12, 1);

        hour.output.connect(on_spin_button_output);
        hour.set_width_chars(2);  

        minute = new Gtk.SpinButton.with_range(0, 59, 1);
        minute.set_width_chars(2);
        minute.output.connect(on_spin_button_output);

        second = new Gtk.SpinButton.with_range(0, 59, 1);
        second.set_width_chars(2);
        second.output.connect(on_spin_button_output);

        system = new Gtk.ComboBoxText();
        system.append_text(_("AM"));
        system.append_text(_("PM"));
        system.append_text(_("24 Hr"));
        system.changed.connect(on_time_system_changed);

        Gtk.Box clock = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

        clock.pack_start(hour, false, false, 3);
        clock.pack_start(new Gtk.Label(":"), false, false, 3); // internationalize?
        clock.pack_start(minute, false, false, 3);
        clock.pack_start(new Gtk.Label(":"), false, false, 3);
        clock.pack_start(second, false, false, 3);
        clock.pack_start(system, false, false, 3);

        set_default_response(Gtk.ResponseType.OK);
        
        relativity_radio_button = new Gtk.RadioButton.with_mnemonic(null, 
            _("_Shift photos/videos by the same amount"));
        relativity_radio_button.set_active(Config.Facade.get_instance().get_keep_relativity());
        relativity_radio_button.sensitive = display_options && photo_count > 1;

        batch_radio_button = new Gtk.RadioButton.with_mnemonic(relativity_radio_button.get_group(),
            _("Set _all photos/videos to this time"));
        batch_radio_button.set_active(!Config.Facade.get_instance().get_keep_relativity());
        batch_radio_button.sensitive = display_options && photo_count > 1;
        batch_radio_button.toggled.connect(on_time_changed);

        if (contains_video) {
            modify_originals_check_button = new Gtk.CheckButton.with_mnemonic((photo_count == 1) ?
                _("_Modify original photo file") : _("_Modify original photo files"));
        } else {
            modify_originals_check_button = new Gtk.CheckButton.with_mnemonic((photo_count == 1) ?
                _("_Modify original file") : _("_Modify original files"));
        }

        modify_originals_check_button.set_active(Config.Facade.get_instance().get_commit_metadata_to_masters() &&
            display_options);
        modify_originals_check_button.sensitive = (!only_video) &&
            (!Config.Facade.get_instance().get_commit_metadata_to_masters() && display_options);

        Gtk.Box time_content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

        time_content.pack_start(calendar, true, false, 3);
        time_content.pack_start(clock, true, false, 3);

        if (display_options) {
            time_content.pack_start(relativity_radio_button, true, false, 3);
            time_content.pack_start(batch_radio_button, true, false, 3);
            time_content.pack_start(modify_originals_check_button, true, false, 3);
        }

        Gdk.Pixbuf preview = null;
        try {
            // Instead of calling get_pixbuf() here, we use the thumbnail instead;
            // this was needed for Videos, since they don't support get_pixbuf().
            preview = source.get_thumbnail(CALENDAR_THUMBNAIL_SCALE);
        } catch (Error err) {
            warning("Unable to fetch preview for %s", source.to_string());
        }
        
        Gtk.Box image_content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        Gtk.Image image = (preview != null) ? new Gtk.Image.from_pixbuf(preview) : new Gtk.Image();
        original_time_label = new Gtk.Label(null);
        image_content.pack_start(image, true, false, 3);
        image_content.pack_start(original_time_label, true, false, 3);

        Gtk.Box hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        hbox.pack_start(image_content, true, false, 6);
        hbox.pack_start(time_content, true, false, 6);

        Gtk.Alignment hbox_alignment = new Gtk.Alignment(0.5f, 0.5f, 0, 0);
        hbox_alignment.set_padding(6, 3, 6, 6);
        hbox_alignment.add(hbox);

        ((Gtk.Box) get_content_area()).pack_start(hbox_alignment, true, false, 6);

        notification = new Gtk.Label("");
        notification.set_line_wrap(true);
        notification.set_justify(Gtk.Justification.CENTER);
        notification.set_size_request(-1, -1);
        notification.set_padding(12, 6);

        ((Gtk.Box) get_content_area()).pack_start(notification, true, true, 0);
        
        original_time = source.get_exposure_time();

        if (original_time == 0) {
            original_time = time_t();
            no_original_time = true;
        }

        set_time(Time.local(original_time));
        set_original_time_label(Config.Facade.get_instance().get_use_24_hour_time());
    }

    private void set_time(Time time) {
        calendar.select_month(time.month, time.year + YEAR_OFFSET);
        calendar.select_day(time.day);

        if (Config.Facade.get_instance().get_use_24_hour_time()) {
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

            keep_relativity = relativity_radio_button.get_active();

            if (relativity_radio_button.sensitive)
                Config.Facade.get_instance().set_keep_relativity(keep_relativity);

            modify_originals = modify_originals_check_button.get_active();

            if (modify_originals_check_button.sensitive)
                Config.Facade.get_instance().set_modify_originals(modify_originals);

            response = true;
        } else {
            time_shift = 0;
            keep_relativity = true;
            modify_originals = false;
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
        int64 time_shift = ((int64) get_time() - (int64) original_time);

        previous_time_system = (TimeSystem) system.get_active();

        if (time_shift == 0 || no_original_time || (batch_radio_button.get_active() &&
            batch_radio_button.sensitive)) {
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

        Config.Facade.get_instance().set_use_24_hour_time(system.get_active() == TimeSystem.24HR);

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

public abstract class TagsDialog : TextEntryDialogMediator {
    public TagsDialog(string title, string label, string? initial_text = null) {
        base (title, label, initial_text, HierarchicalTagIndex.get_global_index().get_all_tags(),
            ",");
    }
}

public class AddTagsDialog : TagsDialog {
    public AddTagsDialog() {
        base (Resources.ADD_TAGS_TITLE, _("Tags (separated by commas):"));
    }

    public string[]? execute() {
        string? text = _execute();
        if (text == null)
            return null;
        
        // only want to return null if the user chose cancel, however, on_modify_validate ensures
        // that Tag.prep_tag_names won't return a zero-length array (and it never returns null)
        return Tag.prep_tag_names(text.split(","));
    }

    protected override bool on_modify_validate(string text) {
        if (text.contains(Tag.PATH_SEPARATOR_STRING))
            return false;
            
        // Can't simply call Tag.prep_tag_names().length because of this bug:
        // https://bugzilla.gnome.org/show_bug.cgi?id=602208
        string[] names = Tag.prep_tag_names(text.split(","));
        
        return names.length > 0;
    }
}

public class ModifyTagsDialog : TagsDialog {
    public ModifyTagsDialog(MediaSource source) {
        base (Resources.MODIFY_TAGS_LABEL, _("Tags (separated by commas):"), 
            get_initial_text(source));
    }
    
    private static string? get_initial_text(MediaSource source) {
        Gee.Collection<Tag>? source_tags = Tag.global.fetch_for_source(source);
        if (source_tags == null)
            return null;

        Gee.Collection<Tag> terminal_tags = Tag.get_terminal_tags(source_tags);
        
        Gee.SortedSet<string> tag_basenames = new Gee.TreeSet<string>();
        foreach (Tag tag in terminal_tags)
            tag_basenames.add(HierarchicalTagUtilities.get_basename(tag.get_path()));
        
        string? text = null;
        foreach (string name in tag_basenames) {
            if (text == null)
                text = "";
            else
                text += ", ";
            
            text += name;
        }
        
        return text;
    }
    
    public Gee.ArrayList<Tag>? execute() {
        string? text = _execute();
        if (text == null)
            return null;
        
        Gee.ArrayList<Tag> new_tags = new Gee.ArrayList<Tag>();
        
        // return empty list if no tags specified
        if (is_string_empty(text))
            return new_tags;
        
        // break up by comma-delimiter, prep for use, and separate into list
        string[] tag_names = Tag.prep_tag_names(text.split(","));
        
        tag_names = HierarchicalTagIndex.get_global_index().get_paths_for_names_array(tag_names);

        foreach (string name in tag_names)
            new_tags.add(Tag.for_path(name));
        
        return new_tags;
    }
    
    protected override bool on_modify_validate(string text) {
        return (!text.contains(Tag.PATH_SEPARATOR_STRING));
    }
    
}

public interface WelcomeServiceEntry : GLib.Object {
    public abstract string get_service_name();
    
    public abstract void execute();
}

public class WelcomeDialog : Gtk.Dialog {
    Gtk.CheckButton hide_button;
    Gtk.CheckButton? system_pictures_import_check = null;
    Gtk.CheckButton[] external_import_checks = new Gtk.CheckButton[0];
    WelcomeServiceEntry[] external_import_entries = new WelcomeServiceEntry[0];
    Gtk.Label secondary_text;
    Gtk.Label instruction_header;
    Gtk.Box import_content;
    Gtk.Box import_action_checkbox_packer;
    Gtk.Box external_import_action_checkbox_packer;
    Spit.DataImports.WelcomeImportMetaHost import_meta_host;
    bool import_content_already_installed = false;
    bool ok_clicked = false;
    
    public WelcomeDialog(Gtk.Window owner) {
        import_meta_host = new Spit.DataImports.WelcomeImportMetaHost(this);
        bool show_system_pictures_import = is_system_pictures_import_possible();
        Gtk.Widget ok_button = add_button(Gtk.Stock.OK, Gtk.ResponseType.OK);
        set_title(_("Welcome!"));
        set_resizable(false);
        set_type_hint(Gdk.WindowTypeHint.DIALOG);
        set_transient_for(owner);

        Gtk.Label primary_text = new Gtk.Label("");
        primary_text.set_markup(
            "<span size=\"large\" weight=\"bold\">%s</span>".printf(_("Welcome to Shotwell!")));
        primary_text.set_alignment(0, 0.5f);
        secondary_text = new Gtk.Label("");
        secondary_text.set_markup("<span weight=\"normal\">%s</span>".printf(
            _("To get started, import photos in any of these ways:")));
        secondary_text.set_alignment(0, 0.5f);
        Gtk.Image image = new Gtk.Image.from_pixbuf(Resources.get_icon(Resources.ICON_APP, 50));
        
        Gtk.Box header_text = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        header_text.pack_start(primary_text, false, false, 5);
        header_text.pack_start(secondary_text, false, false, 0);

        Gtk.Box header_content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        header_content.pack_start(image, false, false, 0);
        header_content.pack_start(header_text, false, false, 0);

        Gtk.Label instructions = new Gtk.Label("");
        string indent_prefix = "   "; // we can't tell what the indent prefix is going to be so assume we need one
        
        string arrow_glyph = (get_direction() == Gtk.TextDirection.RTL) ? "◂" : "▸";
        
        instructions.set_markup(((indent_prefix + "&#8226; %s\n") + (indent_prefix + "&#8226; %s\n")
            + (indent_prefix + "&#8226; %s")).printf(
            _("Choose <span weight=\"bold\">File %s Import From Folder</span>").printf(arrow_glyph),
            _("Drag and drop photos onto the Shotwell window"),
            _("Connect a camera to your computer and import")));
        instructions.set_alignment(0, 0.5f);
        
        import_action_checkbox_packer = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        
        external_import_action_checkbox_packer = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        import_action_checkbox_packer.add(external_import_action_checkbox_packer);
        
        if (show_system_pictures_import) {
            system_pictures_import_check = new Gtk.CheckButton.with_mnemonic(
                _("_Import photos from your %s folder").printf(
                get_display_pathname(AppDirs.get_import_dir())));
            import_action_checkbox_packer.add(system_pictures_import_check);
            system_pictures_import_check.set_active(true);
        }
        
        instruction_header = new Gtk.Label(
            _("You can also import photos in any of these ways:"));
        instruction_header.set_alignment(0.0f, 0.5f);
        instruction_header.set_margin_top(20);
        
        Gtk.Box content = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
        content.pack_start(header_content, true, true, 0);
        import_content = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        content.add(import_content);
        content.pack_start(instructions, false, false, 0);

        hide_button = new Gtk.CheckButton.with_mnemonic(_("_Don't show this message again"));
        hide_button.set_active(true);
        content.pack_start(hide_button, false, false, 6);
        
        Gtk.Alignment alignment = new Gtk.Alignment(0, 0, 0, 0);
        alignment.set_padding(12, 0, 12, 12);
        alignment.add(content);

        ((Gtk.Box) get_content_area()).pack_start(alignment, false, false, 0);

        set_has_resize_grip(false);
        
        ok_button.grab_focus();
        
        install_import_content();
        
        import_meta_host.start();
    }

    private void install_import_content() {
        if (
            (external_import_checks.length > 0 || system_pictures_import_check != null) &&
            (import_content_already_installed == false)
        ) {
            secondary_text.set_markup("");
            import_content.add(import_action_checkbox_packer);
            import_content.add(instruction_header);
            import_content_already_installed = true;
        }
    }
    
    public void install_service_entry(WelcomeServiceEntry entry) {
        debug("WelcomeDialog: Installing service entry for %s".printf(entry.get_service_name()));
        external_import_entries += entry;
        Gtk.CheckButton entry_check = new Gtk.CheckButton.with_label(
            _("Import photos from your %s library").printf(entry.get_service_name()));
        external_import_checks += entry_check;
        entry_check.set_active(true);
        external_import_action_checkbox_packer.add(entry_check);
        install_import_content();
    }

    /**
     * Connected to the 'response' signal.  This is part of a workaround
     * for the fact that run()-ning this dialog can interfere with displaying
     * images from a camera; please see #4997 for details.
     */
    private void on_dismiss(int resp) {
        if (resp == Gtk.ResponseType.OK) {
            ok_clicked = true;
        }
        hide();
        Gtk.main_quit();
    }

    public bool execute(out WelcomeServiceEntry[] selected_import_entries, out bool do_system_pictures_import) {
        // it's unsafe to call run() here - it interferes with displaying
        // images from a camera - so we process the dialog ourselves.
        response.connect(on_dismiss);
        show_all();
        show();

        // this will block the thread we're in until a matching call
        // to main_quit() is encountered; this happens when either the window
        // is closed or OK is clicked.
        Gtk.main();
        
        // at this point, the inner main loop will have been exited.
        // we've got the response, so we don't need this signal anymore.
        response.disconnect(on_dismiss);

        bool ok = ok_clicked;
        bool show_dialog = true;

        if (ok)
            show_dialog = !hide_button.get_active();

        // Use a temporary variable as += cannot be used on parameters
        WelcomeServiceEntry[] result = new WelcomeServiceEntry[0];
        for (int i = 0; i < external_import_entries.length; i++) {
            if (external_import_checks[i].get_active() == true)
                result += external_import_entries[i];
        }
        selected_import_entries = result;
        do_system_pictures_import = 
            (system_pictures_import_check != null) ? system_pictures_import_check.get_active() : false;

        destroy();

        return show_dialog;
    }
    
    private static bool is_system_pictures_import_possible() {
        File system_pictures = AppDirs.get_import_dir();
        if (!system_pictures.query_exists(null))
            return false;
        
        if (!(system_pictures.query_file_type(FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY))
            return false;

        try {
            FileEnumerator syspics_child_enum = system_pictures.enumerate_children("standard::*",
                FileQueryInfoFlags.NONE, null);
            return (syspics_child_enum.next_file(null) != null);
        } catch (Error e) {
            return false;
        }
    }
}

public class PreferencesDialog {
    private class PathFormat {
        public PathFormat(string name, string? pattern) {
            this.name = name;
            this.pattern = pattern;
        }
        public string name;
        public string? pattern;
    } 
    
    private static PreferencesDialog preferences_dialog;
    
    private Gtk.Dialog dialog;
    private Gtk.Builder builder;
    private Gtk.Adjustment bg_color_adjustment;
    private Gtk.Scale bg_color_slider;
    private Gtk.ComboBox photo_editor_combo;
    private Gtk.ComboBox raw_editor_combo;
    private SortedList<AppInfo> external_raw_apps;
    private SortedList<AppInfo> external_photo_apps;
    private Gtk.FileChooserButton library_dir_button;
    private Gtk.ComboBoxText dir_pattern_combo;
    private Gtk.Entry dir_pattern_entry;
    private Gtk.Label dir_pattern_example;
    private bool allow_closing = false;
    private string? lib_dir = null;
    private Gee.ArrayList<PathFormat> path_formats = new Gee.ArrayList<PathFormat>();
    private GLib.DateTime example_date = new GLib.DateTime.local(2009, 3, 10, 18, 16, 11);
    private Gtk.CheckButton lowercase;
    private Gtk.Button close_button;
    private Plugins.ManifestWidgetMediator plugins_mediator = new Plugins.ManifestWidgetMediator();
    private Gtk.ComboBoxText default_raw_developer_combo;

    private PreferencesDialog() {
        builder = AppWindow.create_builder();
        
        dialog = builder.get_object("preferences_dialog") as Gtk.Dialog;
        dialog.set_parent_window(AppWindow.get_instance().get_parent_window());
        dialog.set_transient_for(AppWindow.get_instance());
        dialog.delete_event.connect(on_delete);
        dialog.response.connect(on_close);
        dialog.set_has_resize_grip(false);
        
        bg_color_adjustment = builder.get_object("bg_color_adjustment") as Gtk.Adjustment;
        bg_color_adjustment.set_value(bg_color_adjustment.get_upper() - 
            (Config.Facade.get_instance().get_bg_color().red * 65535.0));
        bg_color_adjustment.value_changed.connect(on_value_changed);

        bg_color_slider = builder.get_object("bg_color_slider") as Gtk.Scale;
        bg_color_slider.button_press_event.connect(on_bg_color_reset);

        library_dir_button = builder.get_object("library_dir_button") as Gtk.FileChooserButton;
        
        close_button = builder.get_object("close_button") as Gtk.Button;
        
        photo_editor_combo = builder.get_object("external_photo_editor_combo") as Gtk.ComboBox;
        raw_editor_combo = builder.get_object("external_raw_editor_combo") as Gtk.ComboBox;
        
        Gtk.Label pattern_help = builder.get_object("pattern_help") as Gtk.Label;

        // Ticket #3162 - Move dir pattern blurb into Gnome help. 
        // Because specifying a particular snippet of the help requires 
        // us to know where its located, we can't hardcode a URL anymore;
        // instead, we ask for the help path, and if we find it, we tell
        // yelp to read from there, otherwise, we read from system-wide. 
        string help_path = Resources.get_help_path();
        
        if (help_path == null) {
            // We're installed system-wide, so use the system help.
            pattern_help.set_markup("<a href=\"" + Resources.DIR_PATTERN_URI_SYSWIDE + "\">" + _("(Help)") + "</a>");
        } else {
            // We're being run from the build directory; we'll have to handle clicks to this
            // link manually ourselves, due to a limitation ghelp: URIs.
            pattern_help.set_markup("<a href=\"dummy:\">" + _("(Help)") + "</a>");
            pattern_help.activate_link.connect(on_local_pattern_help);
        }
        
        dir_pattern_combo = new Gtk.ComboBoxText();
        Gtk.Alignment dir_choser_align = builder.get_object("dir choser") as Gtk.Alignment;
        dir_choser_align.add(dir_pattern_combo);
        dir_pattern_entry = builder.get_object("dir_pattern_entry") as Gtk.Entry;
        dir_pattern_example = builder.get_object("dynamic example") as Gtk.Label;
        add_to_dir_formats(_("Year%sMonth%sDay").printf(Path.DIR_SEPARATOR_S, Path.DIR_SEPARATOR_S), 
            "%Y" + Path.DIR_SEPARATOR_S + "%m" + Path.DIR_SEPARATOR_S + "%d");
        add_to_dir_formats(_("Year%sMonth").printf(Path.DIR_SEPARATOR_S), "%Y" +
            Path.DIR_SEPARATOR_S + "%m");
        add_to_dir_formats(_("Year%sMonth-Day").printf(Path.DIR_SEPARATOR_S), 
            "%Y" + Path.DIR_SEPARATOR_S + "%m-%d");
        add_to_dir_formats(_("Year-Month-Day"), "%Y-%m-%d");
        add_to_dir_formats(_("Custom"), null); // Custom must always be last.
        dir_pattern_combo.changed.connect(on_dir_pattern_combo_changed);
        dir_pattern_entry.changed.connect(on_dir_pattern_entry_changed);
        
        (builder.get_object("dir_structure_label") as Gtk.Label).set_mnemonic_widget(dir_pattern_combo);
        
        lowercase = builder.get_object("lowercase") as Gtk.CheckButton;
        lowercase.toggled.connect(on_lowercase_toggled);
        
        Gtk.Bin plugin_manifest_container = builder.get_object("plugin-manifest-bin") as Gtk.Bin;
        plugin_manifest_container.add(plugins_mediator.widget);
        
        populate_preference_options();

        photo_editor_combo.changed.connect(on_photo_editor_changed);
        raw_editor_combo.changed.connect(on_raw_editor_changed);
        
        Gtk.CheckButton auto_import_button = builder.get_object("autoimport") as Gtk.CheckButton;
        auto_import_button.set_active(Config.Facade.get_instance().get_auto_import_from_library());
        
        Gtk.CheckButton commit_metadata_button = builder.get_object("write_metadata") as Gtk.CheckButton;
        commit_metadata_button.set_active(Config.Facade.get_instance().get_commit_metadata_to_masters());
        
        default_raw_developer_combo = builder.get_object("default_raw_developer") as Gtk.ComboBoxText;
        default_raw_developer_combo.append_text(RawDeveloper.CAMERA.get_label());
        default_raw_developer_combo.append_text(RawDeveloper.SHOTWELL.get_label());
        set_raw_developer_combo(Config.Facade.get_instance().get_default_raw_developer());
        default_raw_developer_combo.changed.connect(on_default_raw_developer_changed);
        
        dialog.map_event.connect(map_event);
    }
    
    public void populate_preference_options() {
        populate_app_combo_box(photo_editor_combo, PhotoFileFormat.get_editable_mime_types(), 
            Config.Facade.get_instance().get_external_photo_app(), out external_photo_apps);

        populate_app_combo_box(raw_editor_combo, PhotoFileFormat.RAW.get_mime_types(), 
            Config.Facade.get_instance().get_external_raw_app(), out external_raw_apps);
        
        setup_dir_pattern(dir_pattern_combo, dir_pattern_entry);
        
        lowercase.set_active(Config.Facade.get_instance().get_use_lowercase_filenames());
    }
    
    // Ticket #3162, part II - if we're not yet installed, then we have to manually launch
    // the help viewer and specify the full path to the subsection we want...
    private bool on_local_pattern_help(string ignore) {
        try {
            Resources.launch_help(AppWindow.get_instance().get_screen(), "?other-files");
        } catch (Error e) {
            message("Unable to launch help: %s", e.message);
        }
        return true;
    }
    
    private void populate_app_combo_box(Gtk.ComboBox combo_box, string[] mime_types,
        string current_app_executable, out SortedList<AppInfo> external_apps) {
        // get list of all applications for the given mime types
        assert(mime_types.length != 0);
        external_apps = DesktopIntegration.get_apps_for_mime_types(mime_types);
        
        if (external_apps.size == 0)
            return;
        
        // populate application ComboBox with app names and icons
        Gtk.CellRendererPixbuf pixbuf_renderer = new Gtk.CellRendererPixbuf();
        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
        combo_box.clear();
        combo_box.pack_start(pixbuf_renderer, false);
        combo_box.pack_start(text_renderer, false);
        combo_box.add_attribute(pixbuf_renderer, "pixbuf", 0);
        combo_box.add_attribute(text_renderer, "text", 1);
        
        // TODO: need more space between icons and text
        Gtk.ListStore combo_store = new Gtk.ListStore(2, typeof(Gdk.Pixbuf), typeof(string));
        Gtk.TreeIter iter;
        
        int current_app = -1;
        
        foreach (AppInfo app in external_apps) {
            combo_store.append(out iter);

            Icon app_icon = app.get_icon();
            try {
                if (app_icon is FileIcon) {
                    combo_store.set_value(iter, 0, scale_pixbuf(new Gdk.Pixbuf.from_file(
                        ((FileIcon) app_icon).get_file().get_path()), Resources.DEFAULT_ICON_SCALE,
                        Gdk.InterpType.BILINEAR, false));
                } else if (app_icon is ThemedIcon) {
                    Gdk.Pixbuf icon_pixbuf = 
                        Gtk.IconTheme.get_default().load_icon(((ThemedIcon) app_icon).get_names()[0],
                        Resources.DEFAULT_ICON_SCALE, Gtk.IconLookupFlags.FORCE_SIZE);
                    
                    combo_store.set_value(iter, 0, icon_pixbuf);
                }
            } catch (GLib.Error error) {
                warning("Error loading icon pixbuf: " + error.message);
            }

            combo_store.set_value(iter, 1, app.get_name());
            
            if (app.get_commandline() == current_app_executable)
                current_app = external_apps.index_of(app);
        }
        
        // TODO: allow users to choose unlisted applications like Nautilus's "Open with -> Other Application..."

        combo_box.set_model(combo_store);

        if (current_app != -1)
            combo_box.set_active(current_app);
    }
    
    private void setup_dir_pattern(Gtk.ComboBox combo_box, Gtk.Entry entry) {
        string? pattern = Config.Facade.get_instance().get_directory_pattern();
        bool found = false;
        if (null != pattern) {
            // Locate pre-built text.
            int i = 0;
            foreach (PathFormat pf in path_formats) {
                if (pf.pattern == pattern) {
                    combo_box.set_active(i);
                    found = true;
                    break;
                }
                i++;
            }
        } else {
            // Custom path.
            string? s = Config.Facade.get_instance().get_directory_pattern_custom();
            if (!is_string_empty(s)) {
                combo_box.set_active(path_formats.size - 1); // Assume "custom" is last.
                found = true;
            }
        }
        
        if (!found) {
            combo_box.set_active(0);
        }
        
        on_dir_pattern_combo_changed();
    }
    
    public static void show() {
        if (preferences_dialog == null) 
            preferences_dialog = new PreferencesDialog();
        
        preferences_dialog.populate_preference_options();
        preferences_dialog.dialog.show_all();
        preferences_dialog.library_dir_button.set_current_folder(AppDirs.get_import_dir().get_path());

        // Ticket #3001: Cause the dialog to become active if the user chooses 'Preferences'
        // from the menus a second time.
        preferences_dialog.dialog.present();
    }

    // For items that should only be committed when the dialog is closed, not as soon as the change
    // is made.
    private void commit_on_close() {
        Config.Facade.get_instance().commit_bg_color();
        
        Gtk.CheckButton? autoimport = builder.get_object("autoimport") as Gtk.CheckButton;
        if (autoimport != null)
            Config.Facade.get_instance().set_auto_import_from_library(autoimport.active);
        
        Gtk.CheckButton? commit_metadata = builder.get_object("write_metadata") as Gtk.CheckButton;
        if (commit_metadata != null)
            Config.Facade.get_instance().set_commit_metadata_to_masters(commit_metadata.active);
       
        if (lib_dir != null)
            AppDirs.set_import_dir(lib_dir);
        
        PathFormat pf = path_formats.get(dir_pattern_combo.get_active());
        if (null == pf.pattern) {
            Config.Facade.get_instance().set_directory_pattern_custom(dir_pattern_entry.text);
            Config.Facade.get_instance().set_directory_pattern(null);
        } else {
            Config.Facade.get_instance().set_directory_pattern(pf.pattern);
        }
    }
    
    private bool on_delete() {
        if (!get_allow_closing())
            return true;
        
        commit_on_close();
        return dialog.hide_on_delete(); //prevent widgets from getting destroyed
    }
    
    private void on_close() {
        if (!get_allow_closing())
            return;
            
        dialog.hide();
        commit_on_close();
    }
    
    private void on_value_changed() {
        set_background_color((double)(bg_color_adjustment.get_upper() - 
            bg_color_adjustment.get_value()) / 65535.0);
    }

    private bool on_bg_color_reset(Gdk.EventButton event) {
        if (event.button == 1 && event.type == Gdk.EventType.BUTTON_PRESS
            && has_only_key_modifier(event.state, Gdk.ModifierType.CONTROL_MASK)) {
            // Left Mouse Button and CTRL pressed
            bg_color_slider.set_value(bg_color_adjustment.get_upper() - 
                (parse_color(Config.Facade.DEFAULT_BG_COLOR).red * 65536.0f));
            on_value_changed();

            return true;
        }

        return false;
    }
    
    private void on_dir_pattern_combo_changed() {
        PathFormat pf = path_formats.get(dir_pattern_combo.get_active());
        if (null == pf.pattern) {
            // Custom format.
            string? dir_pattern = Config.Facade.get_instance().get_directory_pattern_custom();
            if (is_string_empty(dir_pattern))
                dir_pattern = "";
            dir_pattern_entry.set_text(dir_pattern);
            dir_pattern_entry.editable = true;
            dir_pattern_entry.sensitive = true;
        } else {
            dir_pattern_entry.set_text(pf.pattern);
            dir_pattern_entry.editable = false;
            dir_pattern_entry.sensitive = false;
        }
    }
    
    private void on_dir_pattern_entry_changed() {
         string example = example_date.format(dir_pattern_entry.text);
         if (is_string_empty(example) && !is_string_empty(dir_pattern_entry.text)) {
            // Invalid pattern.
            dir_pattern_example.set_text(_("Invalid pattern"));
            dir_pattern_entry.set_icon_from_stock(Gtk.EntryIconPosition.SECONDARY, Gtk.Stock.DIALOG_ERROR);
            dir_pattern_entry.set_icon_activatable(Gtk.EntryIconPosition.SECONDARY, false);
            set_allow_closing(false);
         } else {
            // Valid pattern.
            dir_pattern_example.set_text(example);
            dir_pattern_entry.set_icon_from_stock(Gtk.EntryIconPosition.SECONDARY, null);
            set_allow_closing(true);
         }
    }
    
    private void set_allow_closing(bool allow) {
        dialog.set_deletable(allow);
        close_button.set_sensitive(allow);
        allow_closing = allow;
    }
    
    private bool get_allow_closing() {
        return allow_closing;
    }

    private void set_background_color(double bg_color_value) {
        Config.Facade.get_instance().set_bg_color(to_grayscale(bg_color_value));
    }

    private Gdk.RGBA to_grayscale(double color_value) {
        Gdk.RGBA color = Gdk.RGBA();
        
        color.red = color_value;
        color.green = color_value;
        color.blue = color_value;
        color.alpha = 1.0;
        
        return color;
    }
    
    private void on_photo_editor_changed() {
        int photo_app_choice_index = (photo_editor_combo.get_active() < external_photo_apps.size) ? 
            photo_editor_combo.get_active() : external_photo_apps.size;
            
        AppInfo app = external_photo_apps.get_at(photo_app_choice_index);

        Config.Facade.get_instance().set_external_photo_app(DesktopIntegration.get_app_open_command(app));

        debug("setting external photo editor to: %s", DesktopIntegration.get_app_open_command(app));
    }
    
    private void on_raw_editor_changed() {
        int raw_app_choice_index = (raw_editor_combo.get_active() < external_raw_apps.size) ? 
            raw_editor_combo.get_active() : external_raw_apps.size;
        
        AppInfo app = external_raw_apps.get_at(raw_app_choice_index);
        
        Config.Facade.get_instance().set_external_raw_app(app.get_commandline());
        
        debug("setting external raw editor to: %s", app.get_commandline());
    }
    
    private RawDeveloper raw_developer_from_combo() {
        if (default_raw_developer_combo.get_active() == 0)
            return RawDeveloper.CAMERA;
        return RawDeveloper.SHOTWELL;
    }
    
    private void set_raw_developer_combo(RawDeveloper d) {
        if (d == RawDeveloper.CAMERA)
            default_raw_developer_combo.set_active(0);
        else
            default_raw_developer_combo.set_active(1);
    }
    
    private void on_default_raw_developer_changed() {
        Config.Facade.get_instance().set_default_raw_developer(raw_developer_from_combo());
    }
    
    private void on_current_folder_changed() {
        lib_dir = library_dir_button.get_filename();
    }
    
    private bool map_event() {
        // Set the signal for the lib dir button after the dialog is displayed, 
        // because the FileChooserButton has a nasty habbit of selecting a
        // different folder when displayed if the provided path doesn't exist.
        // See ticket #3000 for more info.
        library_dir_button.current_folder_changed.connect(on_current_folder_changed);
        return true;
    }
    
    private void add_to_dir_formats(string name, string? pattern) {
        PathFormat pf = new PathFormat(name, pattern);
        path_formats.add(pf);
        dir_pattern_combo.append_text(name);
    }
    
    private void on_lowercase_toggled() {
        Config.Facade.get_instance().set_use_lowercase_filenames(lowercase.get_active());
    }
}

// This function is used to determine whether or not files should be copied or linked when imported.
// Returns ACCEPT for copy, REJECT for link, and CANCEL for (drum-roll) cancel.
public Gtk.ResponseType copy_files_dialog() {
    string msg = _("Shotwell can copy the photos into your library folder or it can import them without copying.");

    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(), Gtk.DialogFlags.MODAL,
        Gtk.MessageType.QUESTION, Gtk.ButtonsType.CANCEL, "%s", msg);

    dialog.add_button(_("Co_py Photos"), Gtk.ResponseType.ACCEPT);
    dialog.add_button(_("_Import in Place"), Gtk.ResponseType.REJECT);
    dialog.title = _("Import to Library");

    Gtk.ResponseType result = (Gtk.ResponseType) dialog.run();
    
    dialog.destroy();

    return result;
}

public void remove_photos_from_library(Gee.Collection<LibraryPhoto> photos) {
    remove_from_app(photos, _("Remove From Library"),
        (photos.size == 1) ? _("Removing Photo From Library") : _("Removing Photos From Library"));
}

public void remove_from_app(Gee.Collection<MediaSource> sources, string dialog_title, 
    string progress_dialog_text) {
    if (sources.size == 0)
        return;
    
    Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
    Gee.ArrayList<Video> videos = new Gee.ArrayList<Video>();
    MediaSourceCollection.filter_media(sources, photos, videos);
    
    string? user_message = null;
    if ((!photos.is_empty) && (!videos.is_empty)) {
        user_message = ngettext("This will remove the photo/video from your Shotwell library.  Would you also like to move the file to your desktop trash?\n\nThis action cannot be undone.",
            "This will remove %d photos/videos from your Shotwell library.  Would you also like to move the files to your desktop trash?\n\nThis action cannot be undone.",
             sources.size).printf(sources.size);
    } else if (!videos.is_empty) {
        user_message = ngettext("This will remove the video from your Shotwell library.  Would you also like to move the file to your desktop trash?\n\nThis action cannot be undone.",
            "This will remove %d videos from your Shotwell library.  Would you also like to move the files to your desktop trash?\n\nThis action cannot be undone.",
             sources.size).printf(sources.size);
    } else {
        user_message = ngettext("This will remove the photo from your Shotwell library.  Would you also like to move the file to your desktop trash?\n\nThis action cannot be undone.",
            "This will remove %d photos from your Shotwell library.  Would you also like to move the files to your desktop trash?\n\nThis action cannot be undone.",
             sources.size).printf(sources.size);
    }
    
    Gtk.ResponseType result = remove_from_library_dialog(AppWindow.get_instance(), dialog_title,
        user_message, sources.size);
    if (result != Gtk.ResponseType.YES && result != Gtk.ResponseType.NO)
        return;
    
    bool delete_backing = (result == Gtk.ResponseType.YES);
    
    AppWindow.get_instance().set_busy_cursor();
    
    ProgressDialog progress = null;
    ProgressMonitor monitor = null;
    if (sources.size >= 20) {
        progress = new ProgressDialog(AppWindow.get_instance(), progress_dialog_text);
        monitor = progress.monitor;
    }
        
    Gee.ArrayList<LibraryPhoto> not_removed_photos = new Gee.ArrayList<LibraryPhoto>();
    Gee.ArrayList<Video> not_removed_videos = new Gee.ArrayList<Video>();
    
    // Remove and attempt to trash.
    LibraryPhoto.global.remove_from_app(photos, delete_backing, monitor, not_removed_photos);
    Video.global.remove_from_app(videos, delete_backing, monitor, not_removed_videos);
    
    // Check for files we couldn't trash.
    int num_not_removed = not_removed_photos.size + not_removed_videos.size;
    if (delete_backing && num_not_removed > 0) {
        string not_deleted_message = 
            ngettext("The photo or video cannot be moved to your desktop trash.  Delete this file?",
                "%d photos/videos cannot be moved to your desktop trash.  Delete these files?",
                num_not_removed).printf(num_not_removed);
        Gtk.ResponseType result_delete = remove_from_filesystem_dialog(AppWindow.get_instance(), 
            dialog_title, not_deleted_message);
            
        if (Gtk.ResponseType.YES == result_delete) {
            // Attempt to delete the files.
            Gee.ArrayList<LibraryPhoto> not_deleted_photos = new Gee.ArrayList<LibraryPhoto>();
            Gee.ArrayList<Video> not_deleted_videos = new Gee.ArrayList<Video>();
            LibraryPhoto.global.delete_backing_files(not_removed_photos, monitor, not_deleted_photos);
            Video.global.delete_backing_files(not_removed_videos, monitor, not_deleted_videos);
            
            int num_not_deleted = not_deleted_photos.size + not_deleted_videos.size;
            if (num_not_deleted > 0) {
                // Alert the user that the files were not removed.
                string delete_failed_message = 
                    ngettext("The photo or video cannot be deleted.",
                        "%d photos/videos cannot be deleted.",
                        num_not_deleted).printf(num_not_deleted);
                AppWindow.error_message_with_title(dialog_title, delete_failed_message, AppWindow.get_instance());
            }
        }
    }
    
    if (progress != null)
        progress.close();
    
    AppWindow.get_instance().set_normal_cursor();
}

