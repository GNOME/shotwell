/* Copyright 2019 Jens Georg.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Shotwell {
    class ProfileManager : Object {
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

        public void set_profile(string profile) {
            assert(this.profile == null);

            this.profile = profile;
            group_name = Base64.encode(profile.data);
            if (profiles.has_group(group_name))
                return;

            try {
                profiles.set_string(group_name, "Name", profile);
                profiles.set_string(group_name, "Id", Uuid.string_random());

                // Need to set comment after setting keys since it does not create the group
                profiles.set_comment(group_name, null, "Profile settings for \"%s\"".printf(profile));
            } catch (Error err) {
                error("Failed to create profile: %s", err.message);
            }
            write();
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

            return Path.build_filename(Environment.get_user_data_dir(), "profiles", id());
        }

        public string id() {
            // We are not running on any profile
            if (profile == null)
                return "";

            try {
                return profiles.get_string(group_name, "Id");
            } catch (Error error) {
                assert_not_reached();
            }
        }
    }
}
