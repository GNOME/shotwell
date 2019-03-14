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

        protected Authenticator(string api_key, string api_secret, Spit.Publishing.PluginHost host) {
            base();
            this.host = host;

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

        public void invalidate_persistent_session() {
            set_persistent_access_phase_token("");
            set_persistent_access_phase_token_secret("");
            set_persistent_access_phase_username("");
        }
        protected bool is_persistent_session_valid() {
            return (get_persistent_access_phase_username() != null &&
                    get_persistent_access_phase_token() != null &&
                    get_persistent_access_phase_token_secret() != null);
        }

        protected string? get_persistent_access_phase_username() {
            return host.get_config_string("access_phase_username", null);
        }

        protected void set_persistent_access_phase_username(string username) {
            host.set_config_string("access_phase_username", username);
        }

        protected string? get_persistent_access_phase_token() {
            return host.get_config_string("access_phase_token", null);
        }

        protected void set_persistent_access_phase_token(string token) {
            host.set_config_string("access_phase_token", token);
        }

        protected string? get_persistent_access_phase_token_secret() {
            return host.get_config_string("access_phase_token_secret", null);
        }

        protected void set_persistent_access_phase_token_secret(string secret) {
            host.set_config_string("access_phase_token_secret", secret);
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
