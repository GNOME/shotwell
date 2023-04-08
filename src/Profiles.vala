/* Copyright 2019 Jens Georg.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Shotwell {
    class Profile : Object {
        public const string SYSTEM = "__shotwell_default_system";
        public Profile(string name, string id, string data_dir, bool active) {
            Object(name: name, id: id, data_dir: data_dir, active: active);
        }
        public string name {get; construct;}
        public string id {get; construct;}
        public string data_dir {get; construct;}
        public bool active {get; construct;}
    }

    class ProfileManager : Object, GLib.ListModel {
        // ListModel implementations
        Type get_item_type() {
            return typeof(Profile);
        }

        uint get_n_items() {
            // All that is in the ini file plus one for the default profile
            return profiles.get_groups().length + 1;
        }

        GLib.Object? get_item (uint position) {
            if (position == 0) {
                return new Profile(_("System Profile"), Profile.SYSTEM,
                            Path.build_path(Path.DIR_SEPARATOR_S, Environment.get_user_data_dir(), "shotwell"),
                            this.profile == null);
            }

            try {
                var group = profiles.get_groups()[position - 1];
                var id = profiles.get_value(group, "Id");
                var name = profiles.get_value(group, "Name");
                var active = this.profile == name;
                return new Profile(profiles.get_value(group, "Name"),
                                   id,
                                   get_data_dir_for_profile(id, group),
                                   active);
            } catch (KeyFileError err) {
                if (err is KeyFileError.GROUP_NOT_FOUND) {
                    assert_not_reached();
                }

                warning("Profile configuration file corrupt: %s", err.message);
            }

            return null;
        }

        private static ProfileManager instance;
        public static ProfileManager get_instance() {
            if (instance == null)
                instance = new ProfileManager();

            return instance;
        }

        private ProfileManager() {
            Object();
        }

        private void write() {
            try {
                profiles.save_to_file(path);
            } catch (Error error) {
                critical("Failed to write profiles: %s", error.message);
            }
        }

        private KeyFile profiles;
        private string profile = null;
        private string path;
        private string group_name;

        public override void constructed() {
            base.constructed();

            profiles = new KeyFile();
            path = Path.build_filename(Environment.get_user_config_dir(), "shotwell");
            DirUtils.create_with_parents(path, 0700);
            path = Path.build_filename(path, "profiles.ini");

            try {
                profiles.load_from_file(path, KeyFileFlags.KEEP_COMMENTS);
            } catch (Error error) {
                debug("Could not read profiles: %s", error.message);
            }
        }

        public bool has_profile (string profile, out string group_name = null) {
            group_name = Base64.encode (profile.data);
            return profiles.has_group(group_name);
        }

        public void set_profile(string profile) {
            message("Using profile %s for this session", profile);
            assert(this.profile == null);

            this.profile = profile;

            add_profile(Uuid.string_random(), profile, null, null);
        }

        public void add_profile(string id, string name, string? library_folder, string? data_folder) {
            if (has_profile(name, out this.group_name)) {
                return;
            }

            try {
                profiles.set_string(group_name, "Name", name);
                profiles.set_string(group_name, "Id", id);
                if (data_folder != null) {
                    profiles.set_string(group_name, "DataDir", data_folder);
                }

                // Need to set comment after setting keys since it does not create the group
                profiles.set_comment(group_name, null, "Profile settings for \"%s\"".printf(name));

                write();
            } catch (Error err) {
                error("Failed to create profile: %s", err.message);                
            }

            if (library_folder != null) {
                errno = 0;
                var f = File.new_for_commandline_arg(library_folder);
                try {
                    f.make_directory_with_parents();
                } catch (Error err) {
                    warning ("Failed to create library folder: %s", err.message);
                }
                var settings_path = "/org/gnome/shotwell/profiles/" + id + "/preferences/files/";

    
                var settings = new Settings.with_path("org.gnome.shotwell.preferences.files", settings_path);
                settings.set_string("import-dir", library_folder);
            }
            
            items_changed(profiles.get_groups().length, 0, 1);
        }

        public string derive_data_dir(string? data_dir) {
            if (data_dir != null) {
                debug ("Using user-provided data dir %s", data_dir);

                try {
                    profiles.get_string(group_name, "DataDir");
                } catch (Error error) {
                    if (profile != null && profile != "") {
                        profiles.set_string(group_name ,"DataDir", data_dir);
                        debug("Using %s as data dir for profile %s", data_dir, profile);
                        write();
                    }
                }

                return data_dir;
            }

            return Path.build_filename(Environment.get_user_data_dir(), "shotwell", "profiles", id());
        }

        public string id() {
            // We are not running on any profile
            if (profile == null || profile == "")
                return "";

            try {
                return profiles.get_string(group_name, "Id");
            } catch (Error error) {
                assert_not_reached();
            }
        }

        private string get_data_dir_for_profile(string id, string group) throws KeyFileError {
            if ("DataDir" in profiles.get_keys(group)) {
                return profiles.get_value(group, "DataDir");
            } else {
                return Path.build_filename(Environment.get_user_data_dir(), "shotwell", "profiles", id);
            }
        }

        public void print_profiles() {
            print("Available profiles:\n");
            print("-------------------\n");
            try {
                foreach (var group in profiles.get_groups()) {
                    print("Profile name: %s\n", profiles.get_value(group, "Name"));
                    var id = profiles.get_value(group, "Id");
                    print("Profile Id: %s\n", id);
                    print("Data dir: %s\n", get_data_dir_for_profile(id, group));
                    print("\n");
                }
            } catch (Error error) {
                print("Failed to print profiles: %s", error.message);
            }
        }

        const string SCHEMAS[] = {
            "sharing",
            "printing",
            "plugins.enable-state",
            "preferences.ui",
            "preferences.slideshow",
            "preferences.window",
            "preferences.files",
            "preferences.editing",
            "preferences.export",        
        };

        void reset_all_keys(Settings settings) {
            SettingsSchema schema;
            ((Object)settings).get("settings-schema", out schema, null);
        
            foreach (var key in schema.list_keys()) {
                debug("Resetting key %s", key);
                settings.reset(key);
            }
        
            foreach (var c in settings.list_children()) {
                debug("Checking children %s", c);
                var child = settings.get_child (c);
                reset_all_keys (child);
            }
        }
        
        private void remove_settings_recursively(string id) {
            var source = SettingsSchemaSource.get_default();
            foreach (var schema in SCHEMAS) {
                var path = "/org/gnome/shotwell/profiles/%s/%s/".printf(id, schema.replace(".", "/"));
                var schema_name = "org.gnome.shotwell.%s".printf(schema);
                debug("%s @ %s", schema_name, path);
                var schema_definition = source.lookup(schema_name, false);
                var settings = new Settings.full (schema_definition, null, path);
                settings.delay();
                reset_all_keys (settings);
                foreach (var key in schema_definition.list_keys()) {
                    debug("Resetting key %s", key);
                    settings.reset(key);
                }
                settings.apply();
                Settings.sync();
            }        
        }

        public void remove(string id, bool remove_all) {
            debug("Request to remove profile %s, with files? %s", id, remove_all.to_string());
            int index = 1;
            string group = null;

            foreach (var g in profiles.get_groups()) {
                try {
                    if (profiles.get_value(g, "Id") == id) {
                        group = g;
                        break;
                    }
                    index++;
                } catch (KeyFileError error) {
                    assert_not_reached();
                }
            }

            if (group != null) {
                string? data_dir = null;

                try {
                    data_dir = get_data_dir_for_profile(id, group);
                    // Remove profile
                    string? key = null;
                    profiles.remove_comment(group, key);
                    profiles.remove_group(group);
                } catch (KeyFileError err) {
                    // We checked the existence of the group above.
                    assert_not_reached();
                }

                remove_settings_recursively(id);

                if (remove_all) {
                    try {
                        var file = File.new_for_commandline_arg(data_dir);
                        file.trash();
                    } catch (Error error) {
                        warning("Failed to remove data folder: %s", error.message);
                    }
                }

                Idle.add(() => {
                    items_changed(index, 1, 0);

                    return false;
                });
                write();
            }
        }
    }
}
