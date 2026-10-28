/* SPDX-FileCopyrightText: 2016 Software Freedom Conservancy Inc.
 * SPDX-FileCopyrightText: 2017 Jens Georg <mail@jensge.org>
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/set_background_dialog.ui")]
public class SetBackgroundPhotoDialog : Gtk.Dialog {
    [GtkChild]
    private unowned Gtk.CheckButton desktop_background_checkbox;
    [GtkChild]
    private unowned Gtk.CheckButton screensaver_checkbox;

    public SetBackgroundPhotoDialog() {
        Object(use_header_bar: Resources.use_header_bar());
        this.set_transient_for (AppWindow.get_instance());
    }

    [GtkCallback]
    private void on_checkbox_clicked() {
        set_response_sensitive (Gtk.ResponseType.OK,
                                desktop_background_checkbox.active ||
                                screensaver_checkbox.active);
    }

    public async bool execute(out bool desktop_background, out bool screensaver) {
        this.present();

        SourceFunc continue_cb = execute.callback;
        int response = 0;
        this.response.connect((source, res) => {
            this.set_visible(false);
            response = res;
            continue_cb();
        });
        
        yield;

        var result = response == Gtk.ResponseType.OK;

        desktop_background = desktop_background_checkbox.active;
        screensaver = screensaver_checkbox.active;

        this.destroy();
        return result;
    }
}
