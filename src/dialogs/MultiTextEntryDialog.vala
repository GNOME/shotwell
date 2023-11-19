/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/multitextentrydialog.ui")]
public class MultiTextEntryDialog : Gtk.Dialog {
    public delegate bool OnModifyValidateType(string text);

    private unowned OnModifyValidateType on_modify_validate;
    [GtkChild]
    private unowned Gtk.TextView entry;

    public MultiTextEntryDialog() {
        Object (use_header_bar: Resources.use_header_bar());

        var controller = new Gtk.EventControllerKey();
        controller.key_pressed.connect((val, code, state) => {
            if (!(Gdk.ModifierType.CONTROL_MASK in state)) {
                return false;
            }

            if (val != Gdk.Key.Return && val != Gdk.Key.KP_Enter) {
                return false;
            }

            response(Gtk.ResponseType.OK);

            return true;
        });
        entry.add_controller(controller);
    }

    public void setup(OnModifyValidateType? modify_validate, string title, string label, string? initial_text) {
        set_title(title);
        //set_parent_window(AppWindow.get_instance().get_parent_window());
        set_transient_for(AppWindow.get_instance());
        on_modify_validate = modify_validate;

        entry.buffer.text = (initial_text != null ? initial_text : "");

        entry.grab_focus();
    }

    public async string? execute() {
        string? text = null;

        show();

        SourceFunc continue_async = execute.callback;

        response.connect((source, response_id) => {
            if (response_id == Gtk.ResponseType.OK) {
                text = entry.buffer.text;
            }

            continue_async();
        });

        yield;

        destroy();

        return text;
    }
}
