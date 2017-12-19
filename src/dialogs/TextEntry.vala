/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/textentrydialog.ui")]
public class TextEntryDialog : Gtk.Dialog {
    public delegate bool OnModifyValidateType(string text);

    private unowned OnModifyValidateType on_modify_validate;

    [GtkChild]
    private Gtk.Entry entry;

    [GtkChild]
    private Gtk.Label label;

    public TextEntryDialog() {
        Object (use_header_bar: Resources.use_header_bar());
    }

    public void setup(OnModifyValidateType? modify_validate, string title, string label,
        string? initial_text, Gee.Collection<string>? completion_list, string? completion_delimiter) {
        set_title(title);
        set_parent_window(AppWindow.get_instance().get_parent_window());
        set_transient_for(AppWindow.get_instance());
        on_modify_validate = modify_validate;

        this.label.set_text(label);

        entry.set_text(initial_text != null ? initial_text : "");
        entry.grab_focus();
        entry.changed.connect(on_entry_changed);

        if (completion_list != null) { // Textfield with autocompletion
            EntryMultiCompletion completion = new EntryMultiCompletion(completion_list,
                completion_delimiter);
            entry.set_completion(completion);
        }

        set_default_response(Gtk.ResponseType.OK);
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
