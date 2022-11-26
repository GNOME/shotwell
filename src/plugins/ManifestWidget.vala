/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Plugins {


[GtkTemplate (ui = "/org/gnome/Shotwell/ui/manifest_widget.ui")]
public class ManifestWidgetMediator : Gtk.Box {
    [GtkChild]
    private unowned Gtk.Button about_button;
    
    [GtkChild]
    private unowned Gtk.ScrolledWindow list_bin;
    
    private ManifestListView list = new ManifestListView();
    
    public ManifestWidgetMediator() {
        Object();

        list_bin.add(list);
        
        about_button.clicked.connect(on_about);
        list.row_selected.connect(on_selection_changed);
    }
    
    private void on_about() {
        var pluggable = list.get_selected();
        if (pluggable == null) {
            return;
        }
        
        Spit.PluggableInfo info = Spit.PluggableInfo();
        pluggable.get_info(ref info);
        
        // prepare authors names (which are comma-delimited by the plugin) for the about box
        // (which wants an array of names)
        string[]? authors = null;
        if (info.authors != null) {
            string[] split = info.authors.split(",");
            for (int ctr = 0; ctr < split.length; ctr++) {
                string stripped = split[ctr].strip();
                if (!is_string_empty(stripped)) {
                    if (authors == null)
                        authors = new string[0];
                    
                    authors += stripped;
                }
            }
        }
        
        Gtk.AboutDialog about_dialog = new Gtk.AboutDialog();
        about_dialog.authors = authors;
        about_dialog.comments = info.brief_description;
        about_dialog.copyright = info.copyright;
        about_dialog.license = info.license;
        about_dialog.wrap_license = info.is_license_wordwrapped;
        about_dialog.logo = (info.icons != null && info.icons.length > 0) ? info.icons[0] :
            Resources.get_icon(Resources.ICON_GENERIC_PLUGIN);
        about_dialog.program_name = pluggable.get_pluggable_name();
        about_dialog.translator_credits = info.translators;
        about_dialog.version = info.version;
        about_dialog.website = info.website_url;
        about_dialog.website_label = info.website_name;
        
        about_dialog.run();
        
        about_dialog.destroy();
    }
    
    private void on_selection_changed(Spit.Pluggable? pluggable) {
        about_button.sensitive = pluggable != null;
    }
}

private class CollectionModel<G> : GLib.ListModel, Object {
    private Gee.Collection<G> target;
    private unowned Gee.List<G>? as_list = null;

    public CollectionModel(Gee.Collection<G> target) {
        Object();
        this.target = target.read_only_view;
        if (this.target is Gee.List) {
            this.as_list = (Gee.List<G>)this.target;
        }
    }

    GLib.Object? get_item(uint position) {
        if (position >= this.target.size) {
            return null;
        }

        if (this.as_list != null) {
            return (GLib.Object) this.as_list.@get((int) position);
        }

        var count = 0U;
        foreach (var g in this.target) {
            if (count == position) {
                return (GLib.Object)g;
            }
            count++;
        }

        return null;
    }

    GLib.Type get_item_type() {
        return typeof(G);
    }

    uint get_n_items() {
        return this.target.size;
    }

}

private class Selection : Object {
    public signal void changed();
}

private class PluggableRow : Gtk.Box {
    public Spit.Pluggable pluggable { get; construct; }
    public bool enabled {get; construct; }
    public PluggableRow(Spit.Pluggable pluggable_, bool enable_) {
        Object(orientation: Gtk.Orientation.HORIZONTAL, pluggable: pluggable_,
            enabled: enable_, margin_top: 6, margin_bottom:6, margin_start:6, margin_end:6);
    }

    public override void constructed() {
        base.constructed();

        Spit.PluggableInfo info = Spit.PluggableInfo();
        pluggable.get_info(ref info);
        
        var icon = (info.icons != null && info.icons.length > 0) 
            ? info.icons[0]
            : Resources.get_icon(Resources.ICON_GENERIC_PLUGIN, 24);

        var image = new Gtk.Image.from_pixbuf(icon);
        pack_start(image, false, false, 6);
        image.hexpand = false;

        var label = new Gtk.Label(pluggable.get_pluggable_name());
        label.halign = Gtk.Align.START;
        pack_start(label, true, true, 6);

        var plugin_enabled = new Gtk.Switch();
        plugin_enabled.hexpand = false;
        plugin_enabled.vexpand = false;
        plugin_enabled.valign = Gtk.Align.CENTER;
        plugin_enabled.set_active(enabled);
        pack_end(plugin_enabled, false, false, 6);
        plugin_enabled.notify["active"].connect(() => {
            var id = pluggable.get_id();
            set_pluggable_enabled(id, plugin_enabled.active);
        });

        if (pluggable is Spit.Publishing.Service) {
            var button = new Gtk.Button.from_icon_name("avatar-default-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
            button.get_style_context().add_class("flat");
            // TRANSLATORS: %s is the name of an online service such as YouTube, Mastodon, ...
            button.set_tooltip_text(_("Manage accounts for %s").printf(pluggable.get_pluggable_name()));
            pack_start(button, false, false, 6);
        }
    }
}

private class ManifestListView : Gtk.Box {
    private Gtk.ListBox box = new Gtk.ListBox();
    public ManifestListView() {
        Object(orientation: Gtk.Orientation.VERTICAL);
    }

    public signal void row_selected(Spit.Pluggable? pluggable);

    public override void constructed() {
        base.constructed();

        this.pack_start(this.box);
        foreach (var extension_point in get_extension_points(compare_extension_point_names)) {
            var row = new Gtk.ListBoxRow();
            row.selectable = false;
            row.activatable = false;
            var label = new Gtk.Label(null);
            label.set_markup("<span weight=\"bold\">%s</span>".printf(extension_point.name));
            label.halign = Gtk.Align.START;
            row.add(label);

            box.insert(row, -1);
            var pluggables = get_pluggables_for_type(extension_point.pluggable_type, compare_pluggable_names, true);
            foreach (var pluggable in pluggables) {
                bool enabled;

                if (!get_pluggable_enabled(pluggable.get_id(), out enabled))
                    continue;

                var pluggable_row = new PluggableRow(pluggable, enabled);

                box.insert(pluggable_row, -1);
            }
        }

        box.row_selected.connect((row) => {
            if (row != null) {
                row_selected(((PluggableRow)row.get_child()).pluggable);
            } else {
                row_selected(null);
            }
        });

        show_all();
    }

    public Spit.Pluggable? get_selected() {
        var row = box.get_selected_row();        
        if (row == null) {
            return null;
        }

        return ((PluggableRow)row.get_child()).pluggable;
    }
} 

}

