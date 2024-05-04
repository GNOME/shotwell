/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

 [GtkTemplate (ui = "/org/gnome/Shotwell/ui/detailed-row.ui")]
internal class DetailedRow : Gtk.Box {
    public string? icon_name { get; construct; default = null; }
    public string? title { get; construct; default = null; }

    [GtkChild]
    private unowned Gtk.Label title_label;

    [GtkChild]
    private unowned Gtk.Image icon;
    
    [GtkChild]
    private unowned Gtk.ToggleButton expand_details;

    [GtkChild]
    private unowned Gtk.Revealer revealer;

    [GtkChild]
    private unowned Gtk.Box row_container;

    public override void constructed() {
        base.constructed();

        bind_property("title", title_label, "label", BindingFlags.SYNC_CREATE);
        bind_property("icon-name", icon, "icon-name", BindingFlags.SYNC_CREATE);
        bind_property("icon-name", icon, "visible", BindingFlags.SYNC_CREATE, () => { 
            return icon_name != null;
        });
        expand_details.bind_property("active", revealer, "reveal-child", BindingFlags.DEFAULT);
    }

    public void append_widget(Gtk.Widget widget) {
        row_container.append(widget);
    }

    public void set_detail_widget(Gtk.Widget child) {
        child.margin_top += 12;
        revealer.set_child(child);
    }
}

namespace Plugins {


[GtkTemplate (ui = "/org/gnome/Shotwell/ui/manifest_widget.ui")]
public class ManifestWidgetMediator : Gtk.Box {
    [GtkChild]
    private unowned Gtk.ScrolledWindow list_bin;
    
    private ManifestListView list = new ManifestListView();
    
    public ManifestWidgetMediator() {
        Object();

        list_bin.set_child(list);
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

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/account-browser.ui")]
internal class AccountBrowser : Gtk.Dialog {
    public Gee.Collection<Spit.Publishing.Account> accounts {get; construct;}

    [GtkChild]
    private unowned Gtk.ListBox accounts_listbox;

    public AccountBrowser(Gee.Collection<Spit.Publishing.Account> accounts) {
        Object(accounts: accounts, use_header_bar: Resources.use_header_bar());
    }

    public override void constructed() {
        base.constructed();

        accounts_listbox.bind_model(new CollectionModel<Spit.Publishing.Account>(accounts), (item) => {
            return new Gtk.Label(((Spit.Publishing.Account)item).display_name());
        });
    }
}

private class PluggableRow : DetailedRow {
    public Spit.Pluggable pluggable { get; construct; }
    public bool enabled {get; construct; }

    public PluggableRow(Spit.Pluggable pluggable, bool enable) {
        Object(pluggable: pluggable, enabled: enable,
               icon_name: pluggable.get_info().icon_name,
               title: pluggable.get_pluggable_name());
    }

    public override void constructed() {
        base.constructed();


        var plugin_enabled = new Gtk.Switch();
        plugin_enabled.set_tooltip_text(_("Enable or disable the plugin"));
        plugin_enabled.halign = Gtk.Align.END;
        plugin_enabled.valign = Gtk.Align.CENTER;
        bind_property("enabled", plugin_enabled, "active", BindingFlags.SYNC_CREATE);
        plugin_enabled.notify["active"].connect(() => {
            var id = pluggable.get_id();
            set_pluggable_enabled(id, plugin_enabled.active);
        });
        append_widget(plugin_enabled);

        if (pluggable is Spit.Publishing.Service) {
            var manage = new Gtk.Button.from_icon_name("go-next-symbolic");
            manage.add_css_class("flat");
            // TRANSLATORS: %s is the name of an online service such as YouTube, Mastodon, ...
            manage.set_tooltip_text(_("Manage accounts for %s").printf(pluggable.get_pluggable_name()));
            append_widget(manage);
            manage.clicked.connect(() => {
                var list = new Gee.ArrayList<Spit.Publishing.Account>();
                list.add(new Spit.Publishing.DefaultAccount());

                var dialog = new AccountBrowser(list);
                dialog.set_modal(true);
                dialog.set_transient_for((Gtk.Window)(this.get_root()));
                dialog.response.connect(() => {dialog.destroy(); });
                dialog.show();
            });           
        }

        var info = pluggable.get_info();

        var grid = new Gtk.Grid();
        grid.add_css_class("content");
        grid.set_row_spacing(12);
        grid.set_column_spacing(6);

        var label = new Gtk.Label(info.copyright);
        label.hexpand = true;
        label.halign = Gtk.Align.START;
        grid.attach(label, 0, 0, 2, 1);
        label = new Gtk.Label(_("Authors"));
        label.add_css_class("dim-label");
        label.halign = Gtk.Align.END;
        label.margin_start = 12;
        grid.attach(label, 0, 1, 1, 1);
        label = new Gtk.Label(info.authors);
        label.halign = Gtk.Align.START;
        label.hexpand = true;
        grid.attach(label, 1, 1, 1, 1);

        label = new Gtk.Label(_("Version"));
        label.add_css_class("dim-label");
        label.halign = Gtk.Align.END;
        label.margin_start = 12;
        grid.attach(label, 0, 2, 1, 1);
        label = new Gtk.Label(info.version);
        label.halign = Gtk.Align.START;
        label.hexpand = true;
        grid.attach(label, 1, 2, 1, 1);

        label = new Gtk.Label(_("License"));
        label.add_css_class("dim-label");
        label.halign = Gtk.Align.END;
        label.margin_start = 12;
        grid.attach(label, 0, 3, 1, 1);
        var link = new Gtk.LinkButton.with_label(info.license_url, info.license_blurp);
        link.halign = Gtk.Align.START;
        // remove the annoying padding around the link
        link.remove_css_class("text-button");
        link.add_css_class("shotwell-plain-link");
        grid.attach(link, 1, 3, 1, 1);

        label = new Gtk.Label(_("Website"));
        label.add_css_class("dim-label");
        label.halign = Gtk.Align.END;
        label.margin_start = 12;
        grid.attach(label, 0, 4, 1, 1);
        link = new Gtk.LinkButton.with_label(info.website_url, info.website_name);
        link.halign = Gtk.Align.START;
        // remove the annoying padding around the link
        link.remove_css_class("text-button");
        link.add_css_class("shotwell-plain-link");
        grid.attach(link, 1, 4, 1, 1);
        
        set_detail_widget(grid);
    }
}

private class ManifestListView : Gtk.Box {
    public ManifestListView() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6);
    }

    public signal void row_selected(Spit.Pluggable? pluggable);
    public override void constructed() {
        base.constructed();

        foreach (var extension_point in get_extension_points(compare_extension_point_names)) {
            var pluggables = get_pluggables_for_type(extension_point.pluggable_type, compare_pluggable_names, true);
            if (pluggables.size == 0) {
                continue;
            }

            int added = 0;
            var group = new Shotwell.SettingsGroup(extension_point.name);
            foreach (var pluggable in pluggables) {
                bool enabled;

                if (!get_pluggable_enabled(pluggable.get_id(), out enabled))
                    continue;

                var pluggable_row = new PluggableRow(pluggable, enabled);

                added++;
                group.add_row(pluggable_row);
            }

            if (added > 0) {
                append(group);
            }
        }

        show();
    }
} 

}

