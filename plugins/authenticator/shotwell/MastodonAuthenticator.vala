// SPDX-License-Identifer: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2022 Jens Georg <mail@jensge.org>

using Shotwell;
using Shotwell.Plugins;

namespace Publishing.Authenticator.Shotwell.Mastodon {

internal class Account : Object, Spit.Publishing.Account {
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


    namespace Transactions {
        private class GetClientId : global::Publishing.RESTSupport.Transaction {
            const string ENDPOINT_URL = "https://%s/api/v1/apps";

            public GetClientId(Session session) {
                base.with_endpoint_url(session, ENDPOINT_URL.printf(session.instance));

                add_argument("client_name", "Shotwell Connect");
                add_argument("redirect_uris", "shotwell://client-auth-callback");
                // FIXME: Should write:media, write:statuses be enough?
                add_argument("scopes", "read write");
                add_argument("website", "https://shotwell-project.org");
            }
        }

        private class GetAccessToken : global::Publishing.RESTSupport.Transaction {
            const string ENDPOINT_URL = "https://%s/oauth/token";

            public GetAccessToken(Session session, string code) {
                base.with_endpoint_url(session, ENDPOINT_URL.printf(session.instance));

                add_argument("client_id", session.client_id);
                add_argument("client_secret", session.client_secret);
                add_argument("redirect_uri", "shotwell://user-auth-callback");
                add_argument("grant_type", "authorization_code");
                add_argument("code", code);
                add_argument("scope", "read write");
            }
        }

        private class RevokeAccessToken : global::Publishing.RESTSupport.Transaction {
            const string ENDPOINT_URL = "https://%s/oauth/revoke";

            public RevokeAccessToken(Session session, string token) {
                base.with_endpoint_url(session, ENDPOINT_URL.printf(session.instance));

                add_argument("client_id", session.client_id);
                add_argument("client_secret", session.client_secret);
                add_argument("token", token);
            }
        }
    }

    private class Session : Publishing.RESTSupport.Session {
        public string instance = null;
        public string client_id = null;
        public string client_secret = null;
        public string access_token = null;

        public override bool is_authenticated() {
            return client_id != null && client_secret != null && access_token != null;
        }

        public void deauthenticate() {
            access_token = null;
        }
    }

    internal class InstancePane : Common.BuilderPane {
        public Account? account {get; set; default = null; }
        private Gtk.Button login_button;
        private Gtk.Entry user_entry;
        private Gtk.Entry instance_entry;

        public InstancePane(Account? account) {
            Object(resource_path : "/org/gnome/Shotwell/Authenticator/mastodon_instance_pane.ui",
                   default_id : "login_button",
                   account: account);
        }

        public signal void login();

        public override void constructed() {
            base.constructed();
            if (account == null) {
                account = new Account(null, null);
            }

            var builder = this.get_builder();
            this.login_button = (Gtk.Button)builder.get_object("login_button");
            this.login_button.clicked.connect(() => {
                this.login();
            });

            this.instance_entry = (Gtk.Entry)builder.get_object("instance_entry");
            if (account.instance != null) {
                this.instance_entry.set_text(account.instance);
            }
            this.instance_entry.changed.connect(() => {
                update_login_button();
            });

            this.user_entry = (Gtk.Entry)builder.get_object("user_entry");
            if (account.user != null) {
                this.user_entry.set_text(account.user);
            }
            user_entry.changed.connect(() => {
                update_login_button();
            });

            update_login_button();
        }

        private void update_login_button() {
            login_button.set_sensitive(user_entry.text_length != 0 && instance_entry.text_length != 0);
        }
    }

    private const string CLIENT_SCHEME_ID = "org.gnome.Shotwell.Mastodon.Client";
    private const string USER_SCHEME_ID = "org.gnome.Shotwell.Mastodon.Account";
    public const string SCHEMA_KEY_PROFILE_ID = "shotwell-profile-id";
    public const string CLIENT_KEY_INSTANCE_ID = "instance";
    public const string CLIENT_KEY_SECRET_ID = "id";
    public const string USER_KEY_CLIENT_ID = "client";
    public const string USER_KEY_USERNAME_ID = "username";

    public static Secret.Schema get_client_schema() {
        return new Secret.Schema(CLIENT_SCHEME_ID,
                Secret.SchemaFlags.NONE,
                // Internal id of the shotwell profile
                "shotwell-profile-id", Secret.SchemaAttributeType.STRING,
                // url of the instance
                "instance", Secret.SchemaAttributeType.STRING,
                // TRUE: Client ID, FALSE: Client Secret - This is a bit abusive
                // of Secret
                "id", Secret.SchemaAttributeType.BOOLEAN);
    }

    public static Secret.Schema get_user_schema() {
        return new Secret.Schema(USER_SCHEME_ID,
                Secret.SchemaFlags.NONE,
                // Internal id of the shotwell profile
                "shotwell-profile-id", Secret.SchemaAttributeType.STRING,
                // Client-id as in the client_schema
                "client", Secret.SchemaAttributeType.STRING,
                // Username as used when logging in
                "username", Secret.SchemaAttributeType.STRING);
    }


    public class Mastodon : Spit.Publishing.Authenticator, Object {
        private Session session = null;
        private Secret.Schema? client_schema = null;
        private Secret.Schema? user_schema = null;
        private string? instance = null;
        private string? user = null;
        private Spit.Publishing.PluginHost host;
        private HashTable<string, Variant> params;

        public Mastodon(Spit.Publishing.PluginHost host) {
            this.host = host;
            this.session = new Session();
            this.client_schema = get_client_schema();
            this.user_schema = get_user_schema();
            this.params = new HashTable<string, Variant>(str_hash, str_equal);
        }

       public void authenticate() {
            if (this.instance == null || this.user == null) {
                do_show_instance_pane();
                return;
            }
        }

        public bool can_logout() {
            return true;
        }

        public GLib.HashTable<string, Variant> get_authentication_parameter() {
            return this.params;
        }

        public void logout() {
            var txn = new Transactions.RevokeAccessToken(this.session, session.access_token);

            session.deauthenticate();
            try {
                Secret.password_clear_sync(this.user_schema, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    USER_KEY_CLIENT_ID, session.client_id,
                    USER_KEY_USERNAME_ID, this.user);
            } catch (Error err) {
                critical("Failed to remove password for %s@%s: %s", this.user, this.instance, err.message);
            }

            try {
                txn.execute();
            } catch (Spit.Publishing.PublishingError err) {
                host.post_error(err);
            }
        }

        public void refresh() {
        }

        public void set_accountname(string accountname) {
            var data = accountname.split("@");
            this.instance = data[2];
            this.user = data[1];
        }

        private void do_show_instance_pane() {
            var p = new InstancePane(null);
            host.install_dialog_pane(p);
        }
    }
}
