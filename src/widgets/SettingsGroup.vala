// SPDX-FileCopyrightText: Jens Georg <mail@jensge.org>
// SPDX-License-Identifier: LGPL-2.1-or-later

/**
 * Small clone of Adw.SettingsGroup.
 */
public class Shotwell.SettingsGroup : Gtk.Box {
    public string? title { get; construct; }
    public string? subtitle { get; construct; }
    public bool fixed_header { private get; construct; }

    public signal void row_activated(SettingsGroup group, Gtk.ListBoxRow row);

    private Gtk.ListBox list_box;
    private Gtk.Box header;

    public SettingsGroup(string? title, string? subtitle = null, bool fixed_header = false) {
        Object(title: title, subtitle: subtitle, orientation: Gtk.Orientation.VERTICAL, spacing: 6, fixed_header: fixed_header);

        header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        header.hexpand = true;
        append(header);

        var labels = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        header.append(labels);

        var label = new Gtk.Label(null);
        bind_property("title", label, "label", GLib.BindingFlags.SYNC_CREATE);
        label.add_css_class("heading");
        label.halign = Gtk.Align.START;
        label.valign = Gtk.Align.CENTER;
        label.hexpand = true;
        labels.append(label);

        label = new Gtk.Label(null);
        bind_property("subtitle", label, "label", GLib.BindingFlags.SYNC_CREATE);
        bind_property("subtitle", label, "visible", GLib.BindingFlags.SYNC_CREATE, (binding, from, ref to) => {
            print("%s\n", from.get_string());
            to = from.get_string() != null && from.get_string() != "";

            return true;
        });
        label.add_css_class("dim-label");
        label.halign = Gtk.Align.START;
        label.hexpand = true;
        labels.append(label);


        var box = new Gtk.ListBox();

        box.add_css_class("boxed-list");
        box.set_selection_mode(Gtk.SelectionMode.NONE);
        box.hexpand = true;
        box.margin_bottom = 12;
        list_box = box;
        list_box.row_activated.connect(on_row_activated);
        if (fixed_header) {
            var scrollable = new Gtk.ScrolledWindow();
            scrollable.hexpand = true;
            scrollable.vexpand = true;
            scrollable.set_child(list_box);
            append(scrollable);
        } else {
            append(list_box);
        }
    }

    private void on_row_activated(Gtk.ListBox box, Gtk.ListBoxRow row) {
        row_activated(this, row);
    }

    public void add_row(Gtk.Widget row) {
        list_box.append(row);
    }

    public void set_suffix(Gtk.Widget suffix) {
        header.append(suffix);
        suffix.halign = Gtk.Align.END;
    }

    public void bind_model(GLib.ListModel? model, Gtk.ListBoxCreateWidgetFunc func) {
        list_box.bind_model(model, func);
    }
}