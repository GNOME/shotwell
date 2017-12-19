/* Copyright 2016 Software Freedom Conservancy Inc.
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
        "This will remove the tag “%s” from one photo. Continue?",
        "This will remove the tag “%s” from %d photos. Continue?",
        count).printf(tag.get_user_visible_name(), count);
    
    return AppWindow.negate_affirm_question(msg, _("_Cancel"), _("_Delete"),
        Resources.DELETE_TAG_TITLE);
}

public bool confirm_delete_saved_search(SavedSearch search) {
    string msg = _("This will remove the saved search “%s”. Continue?")
        .printf(search.get_name());
    
    return AppWindow.negate_affirm_question(msg, _("_Cancel"), _("_Delete"),
        Resources.DELETE_SAVED_SEARCH_DIALOG_TITLE);
}

public bool confirm_warn_developer_changed(int number) {
    Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup(AppWindow.get_instance(),
        Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.NONE,
        "<span weight=\"bold\" size=\"larger\">%s</span>",
        ngettext("Switching developers will undo all changes you have made to this photo in Shotwell",
        "Switching developers will undo all changes you have made to these photos in Shotwell", number));

    dialog.add_buttons(Resources.CANCEL_LABEL, Gtk.ResponseType.CANCEL);
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
        AppWindow.get_instance(), Gtk.FileChooserAction.SAVE, Resources.CANCEL_LABEL, 
        Gtk.ResponseType.CANCEL, Resources.SAVE_LABEL, Gtk.ResponseType.ACCEPT, null);
    chooser.set_do_overwrite_confirmation(true);
    chooser.set_current_folder(current_export_dir.get_path());
    chooser.set_current_name(current_file_basename);
    chooser.set_local_only(false);
    
    File file = null;
    if (chooser.run() == Gtk.ResponseType.ACCEPT) {
        file = File.new_for_path(chooser.get_filename());
        current_export_dir = file.get_parent();
    }
    chooser.destroy();
    
    return file;
}

public File? choose_dir(string? user_title = null) {
    if (current_export_dir == null)
        current_export_dir = File.new_for_path(Environment.get_home_dir());

    if (user_title == null)
        user_title = _("Export Photos");

    Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog(user_title,
        AppWindow.get_instance(), Gtk.FileChooserAction.SELECT_FOLDER, Resources.CANCEL_LABEL, 
        Gtk.ResponseType.CANCEL, Resources.OK_LABEL, Gtk.ResponseType.ACCEPT, null);
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
            _("Shotwell couldn’t create a file for editing this photo because you do not have permission to write to %s.").printf(photo.get_master_file().get_parent().get_path()));
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


namespace ImportUI {
private const int REPORT_FAILURE_COUNT = 4;
internal const string SAVE_RESULTS_BUTTON_NAME = _("Save Details…");
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
        builder.append(_("Files Not Imported Because They Weren’t Recognized as Photos or Videos:")
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
        builder.append(_("Photos/Videos Not Imported Because They Weren’t in a Format Shotwell Understands:")
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
        builder.append(_("Photos/Videos Not Imported Because Shotwell Couldn’t Copy Them into its Library:")
             + "\n\n");
        
        foreach (BatchImportResult result in manifest.write_failed) {
            current_file_summary = (_("couldn’t copy %s\n\tto %s")).printf(result.src_identifier,
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
        Gtk.Widget ok_button = dialog.add_button(Resources.OK_LABEL, Gtk.ResponseType.OK);
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
        Resources.CANCEL_LABEL, Gtk.ResponseType.CANCEL, Resources.SAVE_AS_LABEL, Gtk.ResponseType.ACCEPT, null);
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
        dialog = new TextEntryDialog();
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
        dialog = new MultiTextEntryDialog();
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
        // Dialog title
        base (C_("Dialog Title", "Edit Title"),
            _("Title:"), photo_title);
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
        string title_tmp = (is_event)
            // Dialog title
            ? _("Edit Event Comment")
            : _("Edit Photo/Video Comment");
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
    string trash_action = ngettext("Remove and _Trash File", "Remove and _Trash Files", count);
    
    Gtk.MessageDialog dialog = new Gtk.MessageDialog(owner, Gtk.DialogFlags.MODAL,
        Gtk.MessageType.WARNING, Gtk.ButtonsType.CANCEL, "%s", user_message);
    dialog.add_button(_("_Remove From Library"), Gtk.ResponseType.NO);
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
        "This will destroy all changes made to the external file. Continue?",
        "This will destroy all changes made to %d external files. Continue?",
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
        "This will remove the photo from the library. Continue?",
        "This will remove %d photos from the library. Continue?",
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
            cancel_button = new Gtk.Button.with_mnemonic(Resources.CANCEL_LABEL);
            cancel_button.clicked.connect(on_cancel);
            delete_event.connect(on_window_closed);
        }
        
        Gtk.Box hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        hbox.pack_start(vbox_bar, true, false, 0);
        if (cancel_button != null)
            hbox.pack_end(cancel_button, false, false, 0);
        
        Gtk.Label primary_text_label = new Gtk.Label("");
        primary_text_label.set_markup("<span weight=\"bold\">%s</span>".printf(text));
        primary_text_label.xalign = 0.0f;
        primary_text_label.yalign = 0.5f;

        Gtk.Box vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        vbox.pack_start(primary_text_label, false, false, 0);
        vbox.pack_start(hbox, true, false, 0);
        vbox.halign = Gtk.Align.CENTER;
        vbox.valign = Gtk.Align.CENTER;
        vbox.hexpand = true;
        vbox.vexpand = true;
        vbox.margin_start = 12;
        vbox.margin_end = 12;
        vbox.margin_top = 12;
        vbox.margin_bottom = 12;

        add(vbox);

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
        var title = GLib.dpgettext2 (null, "Dialog Title",
                Resources.ADD_TAGS_TITLE);
        base (title, _("Tags (separated by commas):"));
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
        Gtk.Widget ok_button = add_button(Resources.OK_LABEL, Gtk.ResponseType.OK);
        set_title(_("Welcome!"));
        set_resizable(false);
        set_type_hint(Gdk.WindowTypeHint.DIALOG);
        set_transient_for(owner);

        Gtk.Label primary_text = new Gtk.Label("");
        primary_text.set_markup(
            "<span size=\"large\" weight=\"bold\">%s</span>".printf(_("Welcome to Shotwell!")));
        primary_text.xalign = 0.0f;
        primary_text.yalign = 0.5f;
        secondary_text = new Gtk.Label("");
        secondary_text.set_markup("<span weight=\"normal\">%s</span>".printf(
            _("To get started, import photos in any of these ways:")));
        secondary_text.xalign = 0.0f;
        secondary_text.yalign = 0.5f;
        var image = new Gtk.Image.from_icon_name ("shotwell", Gtk.IconSize.DIALOG);
        
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
        instructions.xalign = 0.0f;
        instructions.yalign = 0.5f;
        
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
        instruction_header.xalign = 0.0f;
        instruction_header.yalign = 0.5f;
        instruction_header.set_margin_top(20);
        
        Gtk.Box content = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
        content.pack_start(header_content, true, true, 0);
        import_content = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        content.add(import_content);
        content.pack_start(instructions, false, false, 0);

        hide_button = new Gtk.CheckButton.with_mnemonic(_("_Don’t show this message again"));
        hide_button.set_active(true);
        content.pack_start(hide_button, false, false, 6);
        content.halign = Gtk.Align.FILL;
        content.valign = Gtk.Align.FILL;
        content.hexpand = false;
        content.vexpand = false;
        content.margin_top = 12;
        content.margin_bottom = 0;
        content.margin_start = 12;
        content.margin_end = 12;

        ((Gtk.Box) get_content_area()).pack_start(content, false, false, 0);

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
        user_message = ngettext("This will remove the photo/video from your Shotwell library. Would you also like to move the file to your desktop trash?\n\nThis action cannot be undone.",
            "This will remove %d photos/videos from your Shotwell library. Would you also like to move the files to your desktop trash?\n\nThis action cannot be undone.",
             sources.size).printf(sources.size);
    } else if (!videos.is_empty) {
        user_message = ngettext("This will remove the video from your Shotwell library. Would you also like to move the file to your desktop trash?\n\nThis action cannot be undone.",
            "This will remove %d videos from your Shotwell library. Would you also like to move the files to your desktop trash?\n\nThis action cannot be undone.",
             sources.size).printf(sources.size);
    } else {
        user_message = ngettext("This will remove the photo from your Shotwell library. Would you also like to move the file to your desktop trash?\n\nThis action cannot be undone.",
            "This will remove %d photos from your Shotwell library. Would you also like to move the files to your desktop trash?\n\nThis action cannot be undone.",
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
            ngettext("The photo or video cannot be moved to your desktop trash. Delete this file?",
                "%d photos/videos cannot be moved to your desktop trash. Delete these files?",
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

