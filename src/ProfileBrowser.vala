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
            create_button.add_css_class("suggested-action");
            create_button.sensitive = false;
            set_title(_("Create new Profile"));

            data_folder = Path.build_filename(Environment.get_user_data_dir(), "shotwell", "profiles", id);
            library_folder = Environment.get_user_special_dir(UserDirectory.PICTURES);

            var grid = new Gtk.Grid();
            grid.hexpand = true;
            grid.vexpand = true;
            grid.margin_top = 6;
            grid.margin_bottom = 6;
            grid.margin_start = 6;
            grid.margin_end = 6;
            grid.set_row_spacing(12);
            grid.set_column_spacing(12);
            var label = new Gtk.Label(_("Name"));
            label.add_css_class("dim-label");
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
            label.add_css_class("dim-label");
            label.halign = Gtk.Align.END;
            grid.attach(label, 0, 1, 1, 1);

            entry = new Gtk.Entry();
            entry.hexpand = true;
            grid.attach(entry, 1, 1, 1, 1);
            bind_property("library-folder", entry, "text", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
            entry.bind_property("text", create_button, "sensitive", GLib.BindingFlags.DEFAULT, (binding, from, ref to) => {
                to = from.get_string() != "";
                return true;
            });

            var button = new FolderButton(File.new_for_commandline_arg (library_folder), _("Choose Library Folder"));
            button.bind_property("folder", this, "library-folder", GLib.BindingFlags.DEFAULT, (binding, from, ref to) => {
                var file = (File)from.get_object();
                to = file.get_path();

                return true;
            }, null);
            grid.attach(button, 2, 1, 1, 1);


            label = new Gtk.Label(_("Data Folder"));
            label.add_css_class("dim-label");
            label.halign = Gtk.Align.END;
            grid.attach(label, 0, 2, 1, 1);

            entry = new Gtk.Entry();
            entry.set_text(Environment.get_user_special_dir(UserDirectory.PICTURES));
            entry.hexpand = true;
            bind_property("data-folder", entry, "text", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
            entry.bind_property("text", create_button, "sensitive", GLib.BindingFlags.DEFAULT, (binding, from, ref to) => {
                to = from.get_string() != "";
                return true;
            });
            grid.attach(entry, 1, 2, 1, 1);

            button = new FolderButton(File.new_for_commandline_arg (data_folder), _("Choose Data Folder"));
            button.bind_property("folder", this, "data-folder", GLib.BindingFlags.DEFAULT, (binding, from, ref to) => {
                var file = (File)from.get_object();
                to = file.get_path();

                return true;
            }, null);
            grid.attach(button, 2, 2, 1, 1);

            get_content_area().append(grid);

            show();
        }
    }

    private class ProfileRow : Gtk.Box {
        public Profile profile{get; construct; }

        public ProfileRow(Profile profile) {
            Object(orientation: Gtk.Orientation.VERTICAL,
                profile: profile, margin_top: 6, margin_bottom:6, margin_start:6, margin_end:6);
        }
    
        public override void constructed() {
            base.constructed();

            var content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            content.vexpand = false;
            append(content);
    
            var revealer = new Gtk.Revealer();
            revealer.margin_top = 0;
            append(revealer);
                
            var label = new Gtk.Label(profile.name);
            label.halign = Gtk.Align.START;
            label.hexpand = true;
            content.prepend(label);

            Gtk.Image image;
            if (profile.active) {
                image = new Gtk.Image.from_icon_name ("emblem-default-symbolic");
                image.set_tooltip_text(_("This is the currently active profile"));

            } else {
                image = new Gtk.Image();
            }
            content.append(image);

            var button = new Gtk.ToggleButton();
            button.add_css_class("flat");
            button.set_icon_name("go-down-symbolic");
            content.append(button);
            button.bind_property("active", revealer, "reveal-child", BindingFlags.DEFAULT);

            // FIXME: Would love to use the facade here, but this is currently hardwired to use a fixed profile
            // and that even is not yet initialized
            string settings_path;
            if (profile.id == Profile.SYSTEM) {
                settings_path = "/org/gnome/shotwell/preferences/files/";
            } else {
                settings_path = "/org/gnome/shotwell/profiles/" + profile.id + "/preferences/files/";
            }

            var settings = new Settings.with_path("org.gnome.shotwell.preferences.files", settings_path);
            var import_dir = settings.get_string("import-dir");
            if (import_dir == "") {
                import_dir = Environment.get_user_special_dir(UserDirectory.PICTURES);
            }

            var grid = new Gtk.Grid();
            grid.add_css_class("content");
            grid.set_row_spacing(12);
            grid.set_column_spacing(6);
            revealer.set_child(grid);
            label = new Gtk.Label(_("Library Folder"));
            label.add_css_class("dim-label");
            label.halign = Gtk.Align.END;
            label.margin_start = 12;
            grid.attach(label, 0, 0, 1, 1);
            label = new Gtk.Label(import_dir);
            label.halign = Gtk.Align.START;
            label.set_ellipsize(Pango.EllipsizeMode.END);
            label.set_tooltip_text(import_dir);
            label.set_selectable(true);
            grid.attach(label, 1, 0, 1, 1);
    
            label = new Gtk.Label(_("Data Folder"));
            label.add_css_class("dim-label");
            label.halign = Gtk.Align.END;
            label.margin_start = 12;
            grid.attach(label, 0, 1, 1, 1);
            label = new Gtk.Label(profile.data_dir);
            label.halign = Gtk.Align.START;
            label.hexpand = true;
            label.set_ellipsize(Pango.EllipsizeMode.END);
            label.set_tooltip_text(profile.data_dir);
            label.set_selectable(true);
            grid.attach(label, 1, 1, 1, 1);
            
            if (profile.id != Profile.SYSTEM && !profile.active) {
                var remove_button = new Gtk.Button.with_label(_("Remove Profile"));
                remove_button.add_css_class("destructive-action");
                remove_button.set_tooltip_text(_("Remove this profile"));
                remove_button.hexpand = false;
                remove_button.halign = Gtk.Align.END;
                grid.attach(remove_button, 1, 2, 1, 1);

                remove_button.clicked.connect(() => {
                    var flags = Gtk.DialogFlags.DESTROY_WITH_PARENT | Gtk.DialogFlags.MODAL;
                    if (Resources.use_header_bar() == 1) {
                        flags |= Gtk.DialogFlags.USE_HEADER_BAR;
                    }

                    var d = new Gtk.MessageDialog((Gtk.Window) this.get_root(), flags, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, null);
                    var title = _("Remove profile “%s”").printf(profile.name);
                    var subtitle = _("None of the options will remove any of the images associated with this profile");
                    d.set_markup(_("<b><span size=\"larger\">%s</span></b>\n<span weight=\"light\">%s</span>").printf(title, subtitle));

                    d.add_buttons(_("Remove profile and files"), Gtk.ResponseType.OK, _("Remove profile only"), Gtk.ResponseType.ACCEPT, _("Cancel"), Gtk.ResponseType.CANCEL);
                    d.get_widget_for_response(Gtk.ResponseType.OK).add_css_class("destructive-action");
                    d.set_transient_for((Gtk.Window)remove_button.get_root());
                    d.set_modal(true);
                    d.response.connect((response) => {
                        if (response == Gtk.ResponseType.OK || response == Gtk.ResponseType.ACCEPT) {
                            ProfileManager.get_instance().remove(profile.id, response == Gtk.ResponseType.OK);
                        }    
                        d.destroy();
                    });
                });
            }
        }
    }

    class ProfileBrowser : Gtk.Box {
        public ProfileBrowser() {
            Object(orientation: Gtk.Orientation.VERTICAL, vexpand: true, hexpand: true, spacing: 12);
        }

        public signal void profile_activated(Profile profile);

        public override void constructed() {
            var scrollable = new Gtk.ScrolledWindow();
            scrollable.hexpand = true;
            scrollable.vexpand = true;

            var list_box = new Gtk.ListBox();
            list_box.activate_on_single_click = false;
            list_box.row_activated.connect((list_box, row) => {
                var index = row.get_index();
                var profile = (Profile) ProfileManager.get_instance().get_item(index);
                profile_activated(profile);
            });
            list_box.add_css_class("boxed-list");
            list_box.hexpand = true;
            list_box.vexpand = true;
            scrollable.set_child (list_box);
            list_box.bind_model(ProfileManager.get_instance(), on_widget_create);

            var button = new Gtk.Button.with_label(_("Create new Profile"));
            prepend(button);
            button.clicked.connect(() => {
                var editor = new ProfileEditor();
                editor.set_transient_for((Gtk.Window)get_ancestor(typeof(Gtk.Window)));
                editor.set_modal(true);
                editor.response.connect((d, response) => {
                    if (response == Gtk.ResponseType.OK) {
                        debug("Request to add new profile: %s %s %s %s", editor.id, editor.profile_name, editor.library_folder, editor.data_folder);
                        ProfileManager.get_instance().add_profile(editor.id, editor.profile_name, editor.library_folder, editor.data_folder);    
                    }
                    editor.destroy();
                });
                editor.show();
            });
            append(scrollable);
            show();
        }

        private Gtk.Widget on_widget_create(Object item) {
            return new ProfileRow((Profile) item);
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
