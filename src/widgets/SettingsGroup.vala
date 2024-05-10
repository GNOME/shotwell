// SPDX-FileCopyrightText: Jens Georg <mail@jensge.org>
// SPDX-License-Identifier: LGPL-2.1-or-later

/**
 * Small clone of Adw.SettingsGroup.
 */
[GtkTemplate (ui="/org/gnome/Shotwell/ui/settings-group.ui")]
public class Shotwell.SettingsGroup : Gtk.Widget, Gtk.Buildable {
    public string? title { get; construct; }
    public string? subtitle { get; construct; }
    public bool fixed_header { get; construct; default = false; }

    public signal void row_activated(SettingsGroup group, Gtk.ListBoxRow row);

    [GtkChild]
    private unowned Gtk.Box? content;
    [GtkChild]
    private unowned Gtk.ListBox list_box;
    [GtkChild]
    private unowned Shotwell.ListHeader header;

    public SettingsGroup(string? title, string? subtitle = null, bool fixed_header = false) {
        Object(title: title, subtitle: subtitle, fixed_header: fixed_header);
    }

    class construct {
        set_layout_manager_type(typeof(Gtk.BinLayout));
    }

    construct {
        list_box.row_activated.connect(on_row_activated);
        if (fixed_header) {
            list_box.unparent();
            var scrollable = new Gtk.ScrolledWindow();
            scrollable.hexpand = true;
            scrollable.vexpand = true;
            scrollable.set_child(list_box);
            content.append(scrollable);
        }
    }


    private void on_row_activated(Gtk.ListBox box, Gtk.ListBoxRow row) {
        row_activated(this, row);
    }

    public void add_row(Gtk.Widget row) {
        list_box.append(row);
    }

    public void set_suffix(Gtk.Widget suffix) {
        header.set_suffix(suffix);
    }

    public void bind_model(GLib.ListModel? model, Gtk.ListBoxCreateWidgetFunc func) {
        list_box.bind_model(model, func);
    }

    public void add_child(Gtk.Builder builder, Object child, string? type) {
        if (content == null || !(child is Gtk.Widget)) {
            base.add_child(builder, child, type);
            return;
        }

        if (type != null && type == "suffix") {
            set_suffix((Gtk.Widget)child);
        } else {
            add_row((Gtk.Widget)child);            
        }
    }
}
