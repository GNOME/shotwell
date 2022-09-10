// SPDX-FileCopyrightText: Jens Georg <mail@jensge.org>
// SPDX-License-Identifier: LGPL-2.1-or-later

namespace Shotwell {
    class ProfileEditor : Gtk.Dialog {
        public string profile_name {get; set;}
        public string id{get; default = Uuid.string_random();}
        public string library_folder{get; set;}
        public string data_folder{get; set;}

        public ProfileEditor() {
            Object(use_header_bar : Resources.use_header_bar());
        }

        public override void constructed() {
            base.constructed();

            set_size_request(640, -1);

            add_buttons(_("Create"), Gtk.ResponseType.OK, _("Cancel"), Gtk.ResponseType.CANCEL, null);
            var create_button = get_widget_for_response(Gtk.ResponseType.OK);
            create_button.get_style_context().add_class("suggested-action");
            create_button.sensitive = false;
            set_title(_("Create new Profile"));

            data_folder = Path.build_filename(Environment.get_user_data_dir(), "shotwell", "profiles", id);
            library_folder = Environment.get_user_special_dir(UserDirectory.PICTURES);

            var grid = new Gtk.Grid();
            grid.hexpand = true;
            grid.vexpand = true;
            grid.margin = 6;
            grid.set_row_spacing(12);
            grid.set_column_spacing(12);
            var label = new Gtk.Label(_("Name"));
            label.get_style_context().add_class("dim-label");
            label.halign = Gtk.Align.END;
            grid.attach(label, 0, 0, 1, 1);

            var entry = new Gtk.Entry();
            entry.hexpand = true;
            entry.bind_property("text", this, "profile-name", GLib.BindingFlags.DEFAULT);
            entry.bind_property("text", create_button, "sensitive", GLib.BindingFlags.DEFAULT, (binding, from, ref to) => {
                to = from.get_string() != "";
                return true;
            });
            grid.attach(entry, 1, 0, 2, 1);

            label = new Gtk.Label(_("Library Folder"));
            label.get_style_context().add_class("dim-label");
            label.halign = Gtk.Align.END;
            grid.attach(label, 0, 1, 1, 1);

            entry = new Gtk.Entry();
            entry.hexpand = true;
            grid.attach(entry, 1, 1, 1, 1);
            bind_property("library-folder", entry, "text", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);

            var button = new Gtk.Button.from_icon_name("folder-symbolic", Gtk.IconSize.BUTTON);
            button.hexpand = false;
            button.vexpand = false;
            button.halign = Gtk.Align.FILL;
            button.clicked.connect(() => {
                var dialog = new Gtk.FileChooserNative(_("Choose Library Folder"), this, Gtk.FileChooserAction.SELECT_FOLDER, _("_OK"), _("_Cancel"));
                dialog.set_current_folder(library_folder);
                var result = dialog.run();
                dialog.hide();
                if (result == Gtk.ResponseType.ACCEPT) {
                    library_folder = dialog.get_current_folder_file().get_path();
                }
                dialog.destroy();
            });
            grid.attach(button, 2, 1, 1, 1);


            label = new Gtk.Label(_("Data Folder"));
            label.get_style_context().add_class("dim-label");
            label.halign = Gtk.Align.END;
            grid.attach(label, 0, 2, 1, 1);

            entry = new Gtk.Entry();
            entry.set_text(Environment.get_user_special_dir(UserDirectory.PICTURES));
            entry.hexpand = true;
            bind_property("data-folder", entry, "text", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
            grid.attach(entry, 1, 2, 1, 1);

            button = new Gtk.Button.from_icon_name("folder-symbolic", Gtk.IconSize.BUTTON);
            button.hexpand = false;
            button.vexpand = false;
            button.halign = Gtk.Align.FILL;
            button.clicked.connect(() => {
                var dialog = new Gtk.FileChooserNative(_("Choose Data Folder"), this, Gtk.FileChooserAction.SELECT_FOLDER, _("_OK"), _("_Cancel"));
                dialog.set_current_folder(data_folder);
                var result = dialog.run();
                dialog.hide();
                if (result == Gtk.ResponseType.ACCEPT) {
                    data_folder = dialog.get_current_folder_file().get_path();
                }
                dialog.destroy();
            });

            grid.attach(button, 2, 2, 1, 1);

            get_content_area().add(grid);

            show_all();
        }
    }
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

            var button = new Gtk.Button.with_label(_("Create new Profile"));
            pack_start(button, false, false, 6);
            button.clicked.connect(() => {
                var editor = new ProfileEditor();
                editor.set_transient_for((Gtk.Window)get_ancestor(typeof(Gtk.Window)));
                var result = editor.run();
                editor.hide();
                if (result == Gtk.ResponseType.OK) {
                    debug("Request to add new profile: %s %s %s %s", editor.id, editor.profile_name, editor.library_folder, editor.data_folder);
                    ProfileManager.get_instance().add_profile(editor.id, editor.profile_name, editor.library_folder, editor.data_folder);
                }
                editor.destroy();
            });
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

            var a = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            a.hexpand = true;

            var label = new Gtk.Label(null);
            label.set_markup("<span weight=\"bold\" size=\"larger\">%s</span>".printf(p.name));
            label.xalign = 0.0f;
            a.pack_start(label);


            // FIXME: Would love to use the facade here, but this is currently hardwired to use a fixed profile
            // and that even is not yet initialized
            string settings_path;
            if (p.id == Profile.SYSTEM) {
                settings_path = "/org/gnome/shotwell/preferences/files/";
            } else {
                settings_path = "/org/gnome/shotwell/profiles/" + p.id + "/preferences/files/";
            }

            print ("Showing settings at path %s\n", settings_path);

            var settings = new Settings.with_path("org.gnome.shotwell.preferences.files", settings_path);
            var import_dir = settings.get_string("import-dir");
            if (import_dir == "") {
                import_dir = Environment.get_user_special_dir(UserDirectory.PICTURES);
            }

            label = new Gtk.Label(import_dir);
            label.get_style_context().add_class("dim-label");
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

            box.pack_start(i, false, false, 0);
            box.pack_start(a, true, true, 0);

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
                box.pack_end(b, false, false, 0);
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

            box.show_all();

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
