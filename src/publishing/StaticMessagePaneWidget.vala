/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace PublishingUI {

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/static_message_pane_widget.ui")]
public class StaticMessagePane : Spit.Publishing.DialogPane, Gtk.Box {
    public bool show_spinner{get; construct; default=false; }

    [GtkChild]
    private unowned Gtk.Label static_msg_label;

    [GtkChild]
    private unowned Gtk.Spinner spinner;

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

    public StaticMessagePane(string message_string, bool enable_markup = false, bool show_spinner = false) {
        Object(show_spinner: false);

        spinner.spinning = show_spinner;

        if (enable_markup) {
            static_msg_label.set_markup(message_string);
            static_msg_label.set_wrap(true);
            static_msg_label.set_use_markup(true);
        } else {
            static_msg_label.set_label(message_string);
        }
    }
}

public class AccountFetchWaitPane : StaticMessagePane {
    public AccountFetchWaitPane() {
        base(_("Fetching account information…"), false, true);
    }
}

public class LoginWaitPane : StaticMessagePane {
    public LoginWaitPane() {
        base(_("Logging in…"), false, true);
    }
}


} // namespace PublishingUI
