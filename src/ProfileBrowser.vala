// SPDX-FileCopyrightText: Jens Georg <mail@jensge.org>
// SPDX-License-Identifier: LGPL-2.1-or-later

namespace Shotwell {
    class ProfileBrowser : Gtk.Box {
        public ProfileBrowser() {
            Object(orientation: Gtk.Orientation.VERTICAL, vexpand: true, hexpand: true);
        }

        public signal void profile_activated(string? profile);

        public override void constructed() {
            var scrollable = new Gtk.ScrolledWindow(null, null);
            scrollable.hexpand = true;
            scrollable.vexpand = true;

            var list_box = new Gtk.ListBox();
            list_box.activate_on_single_click = false;
            list_box.row_activated.connect((list_box, row) => {
                var index = row.get_index();
                var profile = (Profile) ProfileManager.get_instance().get_item(index);
                if (profile.id == Profile.SYSTEM) {
                    profile_activated(null);
                } else {
                    profile_activated(profile.name);
                }
            });
            list_box.get_style_context().add_class("rich-list");
            list_box.hexpand = true;
            list_box.vexpand = true;
            scrollable.add (list_box);
            list_box.bind_model(ProfileManager.get_instance(), on_widget_create);
            list_box.set_header_func(on_header);

            add(scrollable);
            show_all();
        }

        private Gtk.Widget on_widget_create(Object item) {
            var p = (Profile) item;
            var row = new Gtk.ListBoxRow();
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.margin_start = 6;
            box.margin_end = 6;
            box.halign = Gtk.Align.START;

            var a = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            a.hexpand = true;

            var label = new Gtk.Label(null);
            label.set_markup("<b>%s</b>".printf(p.name));
            label.halign = Gtk.Align.START;
            label.xalign = 0.0f;
            a.pack_start(label);

            label = new Gtk.Label(p.data_dir);
            label.get_style_context().add_class("dim-label");
            label.halign = Gtk.Align.START;
            label.xalign = 0.0f;
            a.pack_end(label);
            label.set_ellipsize(Pango.EllipsizeMode.MIDDLE);

            Gtk.Image i;
            if (p.active) {
                i = new Gtk.Image.from_icon_name ("emblem-default-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
                i.set_tooltip_text(_("This is the currently active profile"));
            } else {
                i = new Gtk.Image();
            }

            i.set_pixel_size(16);
            i.valign = Gtk.Align.START;
            i.halign = Gtk.Align.START;
            i.margin_top = 6;
            i.margin_bottom = 6;
            i.margin_start = 6;
            i.margin_end = 6;
            i.hexpand = false;

            box.pack_start(i);

            box.pack_start(a);

            if (p.id != Profile.SYSTEM && ! p.active) {
                var b = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON);
                b.margin_top = 6;
                b.margin_bottom = 6;
                b.margin_start = 6;
                b.margin_end = 6;
                b.set_tooltip_text(_("Remove this profile"));
                b.hexpand = false;
                b.halign = Gtk.Align.END;
                b.get_style_context().add_class("flat");
                box.pack_end(b);
                b.clicked.connect(() => {
                    var flags = Gtk.DialogFlags.DESTROY_WITH_PARENT | Gtk.DialogFlags.MODAL;
                    if (Resources.use_header_bar() == 1) {
                        flags |= Gtk.DialogFlags.USE_HEADER_BAR;
                    }

                    var d = new Gtk.MessageDialog((Gtk.Window) this.get_toplevel(), flags, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, null);
                    var title = _("Remove profile “%s”").printf(p.name);
                    var subtitle = _("None of the options will remove any of the images associated with this profile");
                    d.set_markup(_("<b><span size=\"larger\">%s</span></b>\n<span weight=\"light\">%s</span>").printf(title, subtitle));

                    d.add_buttons(_("Remove profile and files"), Gtk.ResponseType.OK, _("Remove profile only"), Gtk.ResponseType.ACCEPT, _("Cancel"), Gtk.ResponseType.CANCEL);
                    d.get_widget_for_response(Gtk.ResponseType.OK).get_style_context().add_class("destructive-action");
                    var response = d.run();
                    d.destroy();
                    if (response == Gtk.ResponseType.OK || response == Gtk.ResponseType.ACCEPT) {
                        ProfileManager.get_instance().remove(p.id, response == Gtk.ResponseType.OK);
                    }
                });
            }

            row.add (box);

            return row;
        }

        private void on_header(Gtk.ListBoxRow row, Gtk.ListBoxRow? before) {
            if (before == null || row.get_header() != null) {
                return;
            }

            var separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
            separator.show();
            row.set_header(separator);
        }
    }
}
