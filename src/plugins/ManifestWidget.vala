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

    public override void constructed() {
        base.constructed();

        bind_property("title", title_label, "label", BindingFlags.SYNC_CREATE);
        bind_property("icon-name", icon, "icon-name", BindingFlags.SYNC_CREATE);
        bind_property("icon-name", icon, "visible", BindingFlags.SYNC_CREATE, () => { 
            return icon_name != null;
        });
        expand_details.bind_property("active", revealer, "reveal-child", BindingFlags.SYNC_CREATE);
    }

    public void set_detail_widget(Gtk.Widget child) {
        child.margin_top += 12;
        revealer.add(child);
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

        list_bin.add(list);
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

private class AccountRow : DetailedRow {
    public AccountRow(Spit.Publishing.Account account) {
        Object(title: account.display_name());
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
            var row = new AccountRow((Spit.Publishing.Account)item);

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            box.pack_start(new Gtk.Button.with_label(_("Log out")));
            box.pack_end(new Gtk.Button.with_label(_("Remove account")));
            box.show_all();
            row.set_detail_widget(box);

            return row;
        });
    }
}

private class PluggableRow : Gtk.Box {
    public Spit.Pluggable pluggable { get; construct; }
    public bool enabled {get; construct; }

    public PluggableRow(Spit.Pluggable pluggable_, bool enable_) {
        Object(orientation: Gtk.Orientation.VERTICAL, pluggable: pluggable_,
            enabled: enable_, margin_top: 6, margin_bottom:6, margin_start:6, margin_end:6);
    }

    public override void constructed() {
        base.constructed();
        var content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        pack_start(content, true);

        var revealer = new Gtk.Revealer();
        revealer.margin_top = 6;
        pack_end(revealer, true);
        
        var info = pluggable.get_info();
        
        var image = new Gtk.Image.from_icon_name(info.icon_name, Gtk.IconSize.BUTTON);
        content.pack_start(image, false, false, 6);
        image.hexpand = false;

        var label = new Gtk.Label(pluggable.get_pluggable_name());
        label.halign = Gtk.Align.START;
        content.pack_start(label, true, true, 6);

        var button = new Gtk.ToggleButton();
        button.get_style_context().add_class("flat");
        content.pack_end(button, false, false, 6);
        button.bind_property("active", revealer, "reveal-child", BindingFlags.DEFAULT);
        image = new Gtk.Image.from_icon_name("go-down-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
        button.add(image);

        var plugin_enabled = new Gtk.Switch();
        plugin_enabled.hexpand = false;
        plugin_enabled.vexpand = false;
        plugin_enabled.valign = Gtk.Align.CENTER;
        plugin_enabled.set_active(enabled);

        content.pack_end(plugin_enabled, false, false, 6);
        plugin_enabled.notify["active"].connect(() => {
            var id = pluggable.get_id();
            set_pluggable_enabled(id, plugin_enabled.active);
        });

        if (pluggable is Spit.Publishing.Service) {
#if 0
            var manage = new Gtk.Button.from_icon_name("avatar-default-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
            manage.get_style_context().add_class("flat");
            // TRANSLATORS: %s is the name of an online service such as YouTube, Mastodon, ...
            manage.set_tooltip_text(_("Manage accounts for %s").printf(pluggable.get_pluggable_name()));
            content.pack_start(manage, false, false, 6);
#endif
            manage.clicked.connect(() => {
                var service = (Spit.Publishing.Service) pluggable;
                var list = service.get_accounts(Shotwell.ProfileManager.get_instance().id());

                var dialog = new AccountBrowser(list);
                dialog.set_modal(true);
                dialog.set_transient_for((Gtk.Window)(this.get_toplevel()));
                dialog.response.connect(() => {dialog.destroy(); });
                dialog.show();
            });
        }

        var grid = new Gtk.Grid();
        grid.get_style_context().add_class("content");
        grid.set_row_spacing(12);
        grid.set_column_spacing(6);
        revealer.add(grid);
        label = new Gtk.Label(info.copyright);
        label.hexpand = true;
        label.halign = Gtk.Align.START;
        grid.attach(label, 0, 0, 2, 1);
        label = new Gtk.Label(_("Authors"));
        label.get_style_context().add_class("dim-label");
        label.halign = Gtk.Align.END;
        label.margin_start = 12;
        grid.attach(label, 0, 1, 1, 1);
        label = new Gtk.Label(info.authors);
        label.halign = Gtk.Align.START;
        label.hexpand = true;
        grid.attach(label, 1, 1, 1, 1);

        label = new Gtk.Label(_("Version"));
        label.get_style_context().add_class("dim-label");
        label.halign = Gtk.Align.END;
        label.margin_start = 12;
        grid.attach(label, 0, 2, 1, 1);
        label = new Gtk.Label(info.version);
        label.halign = Gtk.Align.START;
        label.hexpand = true;
        grid.attach(label, 1, 2, 1, 1);

        label = new Gtk.Label(_("License"));
        label.get_style_context().add_class("dim-label");
        label.halign = Gtk.Align.END;
        label.margin_start = 12;
        grid.attach(label, 0, 3, 1, 1);
        var link = new Gtk.LinkButton.with_label(info.license_url, info.license_blurp);
        link.halign = Gtk.Align.START;
        // remove the annoying padding around the link
        link.get_style_context().remove_class("text-button");
        link.get_style_context().add_class("shotwell-plain-link");
        grid.attach(link, 1, 3, 1, 1);

        label = new Gtk.Label(_("Website"));
        label.get_style_context().add_class("dim-label");
        label.halign = Gtk.Align.END;
        label.margin_start = 12;
        grid.attach(label, 0, 4, 1, 1);
        link = new Gtk.LinkButton.with_label(info.website_url, info.website_name);
        link.halign = Gtk.Align.START;
        // remove the annoying padding around the link
        link.get_style_context().remove_class("text-button");
        link.get_style_context().add_class("shotwell-plain-link");
        grid.attach(link, 1, 4, 1, 1);
        
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
            var label = new Gtk.Label(null);
            label.set_markup("<span weight=\"bold\">%s</span>".printf(extension_point.name));
            label.halign = Gtk.Align.START;
            label.hexpand = true;
            add(label);

            var pluggables = get_pluggables_for_type(extension_point.pluggable_type, compare_pluggable_names, true);
            var box = new Gtk.ListBox();
            box.set_selection_mode(Gtk.SelectionMode.NONE);
            box.hexpand = true;
            box.margin_start = 12;
            box.margin_end = 12;

            var added = 0;
            foreach (var pluggable in pluggables) {
                bool enabled;

                if (!get_pluggable_enabled(pluggable.get_id(), out enabled))
                    continue;

                var pluggable_row = new PluggableRow(pluggable, enabled);

                added++;
                box.insert(pluggable_row, -1);
            }
            if (added > 0) {
                add(box);
            }
        }

        show_all();
    }
} 

}

