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
            grid.margin_top = 6;
            grid.margin_bottom = 6;
            grid.margin_start = 6;
            grid.margin_end = 6;
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

            var button = new Gtk.Button.from_icon_name("folder-symbolic");
            button.hexpand = false;
            button.vexpand = false;
            button.halign = Gtk.Align.FILL;
            button.clicked.connect(() => {
                var dialog = new Gtk.FileChooserNative(_("Choose Library Folder"), this, Gtk.FileChooserAction.SELECT_FOLDER, _("_OK"), _("_Cancel"));
                dialog.set_current_folder(File.new_for_commandline_arg (library_folder));
                var result = Gtk.ResponseType.OK; //dialog.run();
                dialog.hide();
                if (result == Gtk.ResponseType.ACCEPT) {
                    library_folder = dialog.get_current_folder().get_path();
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

            button = new Gtk.Button.from_icon_name("folder-symbolic");
            button.hexpand = false;
            button.vexpand = false;
            button.halign = Gtk.Align.FILL;
            button.clicked.connect(() => {
                var dialog = new Gtk.FileChooserNative(_("Choose Data Folder"), this, Gtk.FileChooserAction.SELECT_FOLDER, _("_OK"), _("_Cancel"));
                dialog.set_current_folder(File.new_for_commandline_arg(data_folder));
                var result = Gtk.ResponseType.OK; //dialog.run();
                dialog.hide();
                if (result == Gtk.ResponseType.ACCEPT) {
                    data_folder = dialog.get_current_folder().get_path();
                }
                dialog.destroy();
            });

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
            pack_start(content, true);
    
            var revealer = new Gtk.Revealer();
            revealer.margin_top = 6;
            pack_end(revealer, true);
                
            var label = new Gtk.Label(null);
            label.set_markup("<span weight=\"bold\">%s</span>".printf(profile.name));
            label.halign = Gtk.Align.START;
            content.pack_start(label, true, true, 6);

            Gtk.Image image;
            if (profile.active) {
                image = new Gtk.Image.from_icon_name ("emblem-default-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
                image.set_tooltip_text(_("This is the currently active profile"));

            } else {
                image = new Gtk.Image();
            }
            content.pack_start(image, false, false, 6);

            var button = new Gtk.ToggleButton();
            button.get_style_context().add_class("flat");
            content.pack_start(button, false, false, 6);
            button.bind_property("active", revealer, "reveal-child", BindingFlags.DEFAULT);
            image = new Gtk.Image.from_icon_name("go-down-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
            button.add(image);

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
            grid.get_style_context().add_class("content");
            grid.set_row_spacing(12);
            grid.set_column_spacing(6);
            revealer.add(grid);
            label = new Gtk.Label(_("Library Folder"));
            label.get_style_context().add_class("dim-label");
            label.halign = Gtk.Align.END;
            label.margin_start = 12;
            grid.attach(label, 0, 0, 1, 1);
            label = new Gtk.Label(import_dir);
            label.halign = Gtk.Align.START;
            label.set_ellipsize(Pango.EllipsizeMode.END);
            grid.attach(label, 1, 0, 1, 1);
    
            label = new Gtk.Label(_("Data Folder"));
            label.get_style_context().add_class("dim-label");
            label.halign = Gtk.Align.END;
            label.margin_start = 12;
            grid.attach(label, 0, 1, 1, 1);
            label = new Gtk.Label(profile.data_dir);
            label.halign = Gtk.Align.START;
            label.hexpand = true;
            label.set_ellipsize(Pango.EllipsizeMode.END);
            grid.attach(label, 1, 1, 1, 1);
            
            if (profile.id != Profile.SYSTEM && !profile.active) {
                var remove_button = new Gtk.Button.with_label(_("Remove Profile"));
                remove_button.get_style_context().add_class("destructive-action");
                remove_button.set_tooltip_text(_("Remove this profile"));
                remove_button.hexpand = false;
                remove_button.halign = Gtk.Align.END;
                grid.attach(remove_button, 1, 2, 1, 1);

                remove_button.clicked.connect(() => {
                    var flags = Gtk.DialogFlags.DESTROY_WITH_PARENT | Gtk.DialogFlags.MODAL;
                    if (Resources.use_header_bar() == 1) {
                        flags |= Gtk.DialogFlags.USE_HEADER_BAR;
                    }

                    var d = new Gtk.MessageDialog((Gtk.Window) this.get_toplevel(), flags, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, null);
                    var title = _("Remove profile “%s”").printf(profile.name);
                    var subtitle = _("None of the options will remove any of the images associated with this profile");
                    d.set_markup(_("<b><span size=\"larger\">%s</span></b>\n<span weight=\"light\">%s</span>").printf(title, subtitle));

                    d.add_buttons(_("Remove profile and files"), Gtk.ResponseType.OK, _("Remove profile only"), Gtk.ResponseType.ACCEPT, _("Cancel"), Gtk.ResponseType.CANCEL);
                    d.get_widget_for_response(Gtk.ResponseType.OK).get_style_context().add_class("destructive-action");
                    var response = d.run();
                    d.destroy();
                    if (response == Gtk.ResponseType.OK || response == Gtk.ResponseType.ACCEPT) {
                        ProfileManager.get_instance().remove(profile.id, response == Gtk.ResponseType.OK);
                    }
                });
            }
        }
    }

    class ProfileBrowser : Gtk.Box {
        public ProfileBrowser() {
            Object(orientation: Gtk.Orientation.VERTICAL, vexpand: true, hexpand: true);
        }

        public signal void profile_activated(string? profile);

        public override void constructed() {
            var scrollable = new Gtk.ScrolledWindow();
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
            scrollable.set_child (list_box);
            list_box.bind_model(ProfileManager.get_instance(), on_widget_create);
            list_box.set_header_func(on_header);

            var button = new Gtk.Button.with_label(_("Create new Profile"));
            prepend(button);
            button.clicked.connect(() => {
                var editor = new ProfileEditor();
                editor.set_transient_for((Gtk.Window)get_ancestor(typeof(Gtk.Window)));
                //var result = editor.run();
                var result = Gtk.ResponseType.CANCEL;
                editor.hide();
                if (result == Gtk.ResponseType.OK) {
                    debug("Request to add new profile: %s %s %s %s", editor.id, editor.profile_name, editor.library_folder, editor.data_folder);
                    ProfileManager.get_instance().add_profile(editor.id, editor.profile_name, editor.library_folder, editor.data_folder);
                }
                editor.destroy();
            });
            append(scrollable);
            show();
        }

        private Gtk.Widget on_widget_create(Object item) {
            var row = new Gtk.ListBoxRow();
            row.add(new ProfileRow((Profile) item));
            row.show_all();

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
