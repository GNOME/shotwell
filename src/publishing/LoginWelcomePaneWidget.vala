/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace PublishingUI {

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/login_welcome_pane_widget.ui")]
public class LoginWelcomePane : Spit.Publishing.DialogPane, Gtk.Box {
    [GtkChild]
    private unowned Gtk.Button login_button;
    [GtkChild]
    private unowned Gtk.Label not_logged_in_label;

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

    public signal void login_requested();

    public LoginWelcomePane(string service_welcome_message) {
        Object();

        login_button.clicked.connect(on_login_clicked);
        not_logged_in_label.set_use_markup(true);
        not_logged_in_label.set_markup(service_welcome_message);
    }

    private void on_login_clicked() {
        login_requested();
    }
}
} // namespace PublishingUI
