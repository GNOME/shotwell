/* SPDX-FileCopyrightText: 2016 Software Freedom Conservancy Inc.
 * SPDX-FileCopyrightText: 2019 Jens Georg <mail@jensge.org>
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

namespace PublishingUI {

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/progress_pane_widget.ui")]
public class ProgressPane : Spit.Publishing.DialogPane, Gtk.Box {
    [GtkChild]
    private unowned Gtk.ProgressBar progress_bar;

    public Gtk.Widget get_widget() {
        return this;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
    }

    public void on_pane_uninstalled() {
    }

    public void set_text(string text) {
        progress_bar.set_text(text);
    }

    public void set_progress(double progress) {
        progress_bar.set_fraction(progress);
    }

    public void set_status(string status_text, double progress) {
        if (status_text != progress_bar.get_text())
            progress_bar.set_text(status_text);

        set_progress(progress);
    }
}
} // namespace PublishingUI
