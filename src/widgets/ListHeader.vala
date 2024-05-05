// SPDX-FileCopyrightText: Jens Georg <mail@jensge.org>
// SPDX-License-Identifier: LGPL-2.1-or-later

/**
 * Small clone of Adw.SettingsGroup.
 */
 [GtkTemplate (ui="/org/gnome/Shotwell/ui/list-header.ui")]
 public class Shotwell.ListHeader : Gtk.Box, Gtk.Buildable {
    public string? title { get; set; }
    public string? subtitle { get; set; }

    [GtkChild]
    unowned Gtk.Label? subtitle_label;

    public ListHeader(string? title, string? subtitle) {
        Object(title: title, subtitle: subtitle);
    }

    construct {
        bind_property("subtitle", subtitle_label, "visible", GLib.BindingFlags.SYNC_CREATE, (binding, from, ref to) => {
            to = from.get_string() != null && from.get_string() != "";

            return true;
        });
    }

    public void set_suffix(Gtk.Widget? suffix) {
        append(suffix);
        suffix.halign = Gtk.Align.END;
    }

    public void add_child(Gtk.Builder builder, Object object, string? type) {
        if (type != null && type == "suffix" && object is Gtk.Widget) {
            set_suffix((Gtk.Widget)object);
        }

        base.add_child(builder, object, type);
    }
}
