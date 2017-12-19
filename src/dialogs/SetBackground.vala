/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/set_background_dialog.ui")]
public class SetBackgroundPhotoDialog : Gtk.Dialog {
    [GtkChild]
    private Gtk.CheckButton desktop_background_checkbox;
    [GtkChild]
    private Gtk.CheckButton screensaver_checkbox;

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

    public bool execute(out bool desktop_background, out bool screensaver) {
        this.show_all();
        var result = this.run() == Gtk.ResponseType.OK;
        this.hide ();

        desktop_background = desktop_background_checkbox.active;
        screensaver = screensaver_checkbox.active;

        this.destroy();
        return result;
    }
}
