// SPDX-License-Identifer: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2022 Jens Georg <mail@jensge.org>

internal class Publishing.Mastodon.Account : Object, Spit.Publishing.Account {
    public string instance;
    public string user;

    public Account(string? instance, string? user) {
        this.instance = instance;
        this.user = user;
    }

    public string display_name() {
        return "@" + user + "@" + instance;
    }
}

public class Publishing.Mastodon.Service : Object, Spit.Pluggable, Spit.Publishing.Service {
    public Service() {}

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
                                         Spit.Publishing.CURRENT_INTERFACE);
    }

    public unowned string get_id() {
        return "org.gnome.shotwell.publishing.mastodon";
    }

    public unowned string get_pluggable_name() {
        return "Mastodon";
    }

    public Spit.PluggableInfo get_info() {
        var info = new Spit.PluggableInfo();
        info.authors = "Jens Georg";
        info.copyright = _("Copyright 2022 Jens Georg <mail@jensge.org>");
        info.icon_name = "mastodon";

        return info;
    }

    public Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host) {
        return new Publishing.Mastodon.Publisher(this, host, null);
    }

    public Spit.Publishing.Publisher create_publisher_with_account(Spit.Publishing.PluginHost host,
            Spit.Publishing.Account? account) {
        return new Publishing.Mastodon.Publisher(this, host, account);
    }


    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO |
            Spit.Publishing.Publisher.MediaType.VIDEO);
    }

    public void activation(bool enabled) {
    }

    public override Gee.List<Spit.Publishing.Account>? get_accounts(string profile_id) {
        var list = new Gee.ArrayList<Spit.Publishing.Account>();
        list.add(new Spit.Publishing.DefaultAccount());

        var client_schema = Publishing.Authenticator.Shotwell.Mastodon.get_client_schema();
        var user_schema = Publishing.Authenticator.Shotwell.Mastodon.get_user_schema();
        var attributes = new HashTable<string, string>(str_hash, str_equal);
        attributes[Publishing.Authenticator.Shotwell.Mastodon.CLIENT_KEY_SECRET_ID] = "false";
        attributes[Publishing.Authenticator.Shotwell.Mastodon.SCHEMA_KEY_PROFILE_ID] = profile_id;

        var entries = Secret.password_searchv_sync(client_schema, attributes, Secret.SearchFlags.ALL, null);

        foreach (var entry in entries) {
            var found_attributes = entry.get_attributes();
            var instance = found_attributes[Publishing.Authenticator.Shotwell.Mastodon.CLIENT_KEY_INSTANCE_ID];

            var client_id = entry.retrieve_secret_sync(null).get_text();

            var user_attributes = new HashTable<string, string>(str_hash, str_equal);
            user_attributes[Publishing.Authenticator.Shotwell.Mastodon.USER_KEY_CLIENT_ID] = client_id;

            var user_entries = Secret.password_searchv_sync(user_schema, user_attributes, Secret.SearchFlags.ALL, null);
            foreach (var user in user_entries) {
                var found_user_attributes = user.get_attributes();
                var user_name = found_user_attributes[Publishing.Authenticator.Shotwell.Mastodon.USER_KEY_USERNAME_ID];
                list.add(new Account(instance, user_name));
            }
        }

        return list;
    }
}
