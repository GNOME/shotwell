/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Publishing.Authenticator.Shotwell.OAuth1 {

    internal abstract class Authenticator : GLib.Object, Spit.Publishing.Authenticator {
        protected GLib.HashTable<string, Variant> params;
        protected Publishing.RESTSupport.OAuth1.Session session;
        protected Spit.Publishing.PluginHost host;
        private Secret.Schema? schema = null;
        private const string SECRET_TYPE_USERNAME = "username";
        private const string SECRET_TYPE_AUTH_TOKEN = "auth-token";
        private const string SECRET_TYPE_AUTH_TOKEN_SECRET = "auth-token-secret";
        private const string SCHEMA_KEY_ACCOUNTNAME = "accountname";
        private const string SCHEMA_KEY_PROFILE_ID = "shotwell-profile-id";
        private string service = null;
        private string accountname = "default";

        protected Authenticator(string service, string api_key, string api_secret, Spit.Publishing.PluginHost host) {
            base();
            this.host = host;
            this.service = service;
            this.schema = new Secret.Schema("org.gnome.Shotwell." + service, Secret.SchemaFlags.NONE,
                SCHEMA_KEY_PROFILE_ID, Secret.SchemaAttributeType.STRING,
                SCHEMA_KEY_ACCOUNTNAME, Secret.SchemaAttributeType.STRING,
                "type", Secret.SchemaAttributeType.STRING);

            params = new GLib.HashTable<string, Variant>(str_hash, str_equal);
            params.insert("ConsumerKey", api_key);
            params.insert("ConsumerSecret", api_secret);

            session = new Publishing.RESTSupport.OAuth1.Session();
            session.set_api_credentials(api_key, api_secret);
            session.authenticated.connect(on_session_authenticated);
        }

        ~Authenticator() {
            session.authenticated.disconnect(on_session_authenticated);
        }

        // Methods from Authenticator interface
        public abstract void authenticate();

        public abstract bool can_logout();

        public GLib.HashTable<string, Variant> get_authentication_parameter() {
            return this.params;
        }

        public abstract void logout ();

        public abstract void refresh();

        public virtual void set_accountname(string name) {
            this.accountname = name;
        }

        public void invalidate_persistent_session() {
            set_persistent_access_phase_token(null);
            set_persistent_access_phase_token_secret(null);
            set_persistent_access_phase_username(null);
        }

        protected bool is_persistent_session_valid() {
            return (get_persistent_access_phase_username() != null &&
                    get_persistent_access_phase_token() != null &&
                    get_persistent_access_phase_token_secret() != null);
        }

        protected string? get_persistent_access_phase_username() {
            try {
                return Secret.password_lookup_sync(this.schema, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    SCHEMA_KEY_ACCOUNTNAME, this.accountname, "type", SECRET_TYPE_USERNAME);
            } catch (Error err) {
                critical("Failed to lookup username from password store: %s", err.message);
                return null;
            }
        }

        protected void set_persistent_access_phase_username(string? username) {
            try {
                if (username == null || username == "") {
                    Secret.password_clear_sync(this.schema, null,
                        SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                        SCHEMA_KEY_ACCOUNTNAME, this.accountname,
                        "type", SECRET_TYPE_USERNAME);
                } else {
                    Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                        "Shotwell publishing (%s@%s)".printf(this.accountname, this.service),
                        username, null,
                        SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                        SCHEMA_KEY_ACCOUNTNAME, this.accountname, "type", SECRET_TYPE_USERNAME);
                }
            } catch (Error err) {
                critical("Failed to store username in store: %s", err.message);
            }
        }

        protected string? get_persistent_access_phase_token() {
            try {
                return Secret.password_lookup_sync(this.schema, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    SCHEMA_KEY_ACCOUNTNAME, this.accountname,
                    "type", SECRET_TYPE_AUTH_TOKEN);
            } catch (Error err) {
                critical("Failed to lookup auth-token from password store: %s", err.message);
                return null;
            }
        }

        protected void set_persistent_access_phase_token(string? token) {
            try {
                if (token == null || token == "") {
                    Secret.password_clear_sync(this.schema, null,
                        SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                        SCHEMA_KEY_ACCOUNTNAME, this.accountname,
                        "type", SECRET_TYPE_AUTH_TOKEN);
                } else {
                    Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                        "Shotwell publishing (%s@%s)".printf(this.accountname, this.service),
                        token, null,
                        SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                        SCHEMA_KEY_ACCOUNTNAME, this.accountname,
                        "type", SECRET_TYPE_AUTH_TOKEN);
                }
            } catch (Error err) {
                critical("Failed to store auth-token store: %s", err.message);
            }
        }

        protected string? get_persistent_access_phase_token_secret() {
            try {
                return Secret.password_lookup_sync(this.schema, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    SCHEMA_KEY_ACCOUNTNAME, this.accountname,
                    "type", SECRET_TYPE_AUTH_TOKEN_SECRET);
            } catch (Error err) {
                critical("Failed to lookup auth-token-secret from password store: %s", err.message);
                return null;
            }
        }

        protected void set_persistent_access_phase_token_secret(string? secret) {
            try {
                if (secret == null || secret == "") {
                    Secret.password_clear_sync(this.schema, null,
                        SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                        SCHEMA_KEY_ACCOUNTNAME, this.accountname,
                        "type", SECRET_TYPE_AUTH_TOKEN_SECRET);
                } else {
                    Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                        "Shotwell publishing (%s@%s)".printf(this.accountname, this.service),
                        secret, null,
                        SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                        SCHEMA_KEY_ACCOUNTNAME, this.accountname,
                        "type", SECRET_TYPE_AUTH_TOKEN_SECRET);
                }
            } catch (Error err) {
                critical("Failed to store auth-token-secret store: %s", err.message);
            }
        }

        protected void on_session_authenticated() {
            params.insert("AuthToken", session.get_access_phase_token());
            params.insert("AuthTokenSecret", session.get_access_phase_token_secret());
            params.insert("Username", session.get_username());

            set_persistent_access_phase_token(session.get_access_phase_token());
            set_persistent_access_phase_token_secret(session.get_access_phase_token_secret());
            set_persistent_access_phase_username(session.get_username());


            this.authenticated();
        }
    }
}
