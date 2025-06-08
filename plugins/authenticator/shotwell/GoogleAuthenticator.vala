using Shotwell;
using Shotwell.Plugins;

namespace Publishing.Authenticator.Shotwell.Google {
    private const string OAUTH_CLIENT_ID = "534227538559-hvj2e8bj0vfv2f49r7gvjoq6jibfav67.apps.googleusercontent.com";
    private const string REVERSE_CLIENT_ID = "com.googleusercontent.apps.534227538559-hvj2e8bj0vfv2f49r7gvjoq6jibfav67";
    private const string OAUTH_CLIENT_SECRET = "pwpzZ7W1TCcD5uIfYCu8sM7x";
    private const string OAUTH_CALLBACK_URI = REVERSE_CLIENT_ID + ":/localhost";

    private const string SCHEMA_KEY_PROFILE_ID = "shotwell-profile-id";
    private const string SCHEMA_KEY_ACCOUNTNAME = "accountname";

    private class Session : Publishing.RESTSupport.Session {
        public string access_token = null;
        public string refresh_token = null;
        public int64 expires_at = -1;

        public override bool is_authenticated() {
            return (access_token != null);
        }

        public void deauthenticate() {
            access_token = null;
            refresh_token = null;
            expires_at = -1;
        }
    }

    private class GetAccessTokensTransaction : Publishing.RESTSupport.Transaction {
        private const string ENDPOINT_URL = "https://oauth2.googleapis.com/token";

        public GetAccessTokensTransaction(Session session, string auth_code) {
            base.with_endpoint_url(session, ENDPOINT_URL);

            add_argument("code", auth_code);
            add_argument("client_id", OAUTH_CLIENT_ID);
            add_argument("client_secret", OAUTH_CLIENT_SECRET);
            add_argument("redirect_uri", OAUTH_CALLBACK_URI);
            add_argument("grant_type", "authorization_code");
        }
    }

    private class RefreshAccessTokenTransaction : Publishing.RESTSupport.Transaction {
        private const string ENDPOINT_URL = "https://oauth2.googleapis.com/token";

        public RefreshAccessTokenTransaction(Session session) {
            base.with_endpoint_url(session, ENDPOINT_URL);

            add_argument("client_id", OAUTH_CLIENT_ID);
            add_argument("client_secret", OAUTH_CLIENT_SECRET);
            add_argument("refresh_token", session.refresh_token);
            add_argument("grant_type", "refresh_token");
        }
    }

    private class UsernameFetchTransaction : Publishing.RESTSupport.Transaction {
        private const string ENDPOINT_URL = "https://www.googleapis.com/oauth2/v1/userinfo";
        public UsernameFetchTransaction(Session session) {
            base.with_endpoint_url(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.GET);
            add_header("Authorization", "Bearer " + session.access_token);
        }
    }

    internal class Google : Spit.Publishing.Authenticator, Object {
        private const string PASSWORD_SCHEME = "org.gnome.Shotwell.Google";

        private string[] scopes = null;

        // Prepare for multiple user accounts
        private string accountname = "default";
        private Spit.Publishing.PluginHost host = null;
        private GLib.HashTable<string, Variant> params = null;
        private Session session = null;
        private string welcome_message = null;
        private Secret.Schema? schema = null;

        public Google(string[] scopes,
                      string welcome_message,
                      Spit.Publishing.PluginHost host) {
            this.host = host;
            this.params = new GLib.HashTable<string, Variant>(str_hash, str_equal);
            this.scopes = scopes;
            this.session = new Session();
            this.welcome_message = welcome_message;
            this.schema = new Secret.Schema(PASSWORD_SCHEME, Secret.SchemaFlags.NONE,
                SCHEMA_KEY_PROFILE_ID, Secret.SchemaAttributeType.STRING,
                SCHEMA_KEY_ACCOUNTNAME, Secret.SchemaAttributeType.STRING,
                "scope", Secret.SchemaAttributeType.STRING);
        }

        public void authenticate() {
            string? refresh_token = null;
            try {
                refresh_token = Secret.password_lookup_sync(this.schema, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    SCHEMA_KEY_ACCOUNTNAME, this.accountname, "scope", get_scopes());
            } catch (Error err) {
                critical("Failed to lookup refresh_token from password store: %s", err.message);
            }
            if (refresh_token != null && refresh_token != "") {
                on_refresh_token_available(refresh_token);
                do_exchange_refresh_token_for_access_token.begin();
                return;
            }

            this.do_show_service_welcome_pane();
        }

        public string get_scopes(string separator=",") {
            return string.joinv(separator, this.scopes);
        }

        public bool can_logout() {
            return true;
        }

        public GLib.HashTable<string, Variant> get_authentication_parameter() {
            return this.params;
        }

        public void logout() {
            session.deauthenticate();
            try {
                Secret.password_clear_sync(this.schema, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    SCHEMA_KEY_ACCOUNTNAME, this.accountname, "scope", get_scopes());
            } catch (Error err) {
                critical("Failed to remove password for scope %s: %s", get_scopes(), err.message);
            }
        }

        public void refresh() {
            // TODO: Needs to re-auth
        }

        public void set_accountname(string accountname) {
            this.accountname = accountname;
        }
        private class AuthCallback : Spit.Publishing.AuthenticatedCallback, Object {
            public signal void auth(GLib.HashTable<string, string> params);

            public void authenticated(GLib.HashTable<string, string> params) {
                auth(params);
            }
        }

        private async void do_hosted_web_authentication() {
            debug("ACTION: running OAuth authentication flow in hosted web pane.");

            string user_authorization_url = "https://accounts.google.com/o/oauth2/auth?" +
                "response_type=code&" +
                "client_id=" + OAUTH_CLIENT_ID + "&" +
                "redirect_uri=" + GLib.Uri.escape_string(OAUTH_CALLBACK_URI, null) + "&" +
                "scope=" + GLib.Uri.escape_string(get_scopes(" "), null) + "+" +
                GLib.Uri.escape_string("https://www.googleapis.com/auth/userinfo.profile", null) + "&" +
                "state=connect&" +
                "access_type=offline&" +
                "approval_prompt=force";

            var auth_callback = new AuthCallback();
            string? web_auth_code = null;

            auth_callback.auth.connect((prm) => {
                if ("code" in prm) {
                    web_auth_code = prm["code"];
                }
                if ("scope" in prm) {
                    debug("Effective scopes as returned from login: %s", prm["scope"]);
                }
                do_hosted_web_authentication.callback();
            });
            host.register_auth_callback(REVERSE_CLIENT_ID, auth_callback);
            try {
                debug("Launching external authentication on URI %s", user_authorization_url);
                AppInfo.launch_default_for_uri(user_authorization_url, null);
                host.install_login_wait_pane();
                yield;

                // FIXME throw error missing scopes

                yield do_get_access_tokens(web_auth_code);
            } catch (Error err) {
                host.post_error(err);
            } finally {
                host.unregister_auth_callback(REVERSE_CLIENT_ID);
            }
        }

        private async void do_get_access_tokens(string auth_code) {
            debug("ACTION: exchanging authorization code for access & refresh tokens");

            host.install_login_wait_pane();

            GetAccessTokensTransaction tokens_txn = new GetAccessTokensTransaction(session, auth_code);

            try {
                yield tokens_txn.execute_async();
                debug("EVENT: network transaction to exchange authorization code for access tokens " +
                "completed successfully.");
                do_extract_tokens(tokens_txn.get_response());
            } catch (Error err) {
                debug("EVENT: network transaction to exchange authorization code for access tokens " +
                "failed; response = '%s'", tokens_txn.get_response());
                host.post_error(err);
            }

        }

        private void do_extract_tokens(string response_body) {
            debug("ACTION: extracting OAuth tokens from body of server response");

            Json.Parser parser = new Json.Parser();

            try {
                parser.load_from_data(response_body);
            } catch (Error err) {
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "Couldn't parse JSON response: " + err.message));
                return;
            }

            Json.Object response_obj = parser.get_root().get_object();

            if ((!response_obj.has_member("access_token")) && (!response_obj.has_member("refresh_token"))) {
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "neither access_token nor refresh_token not present in server response"));
                return;
            }

            if (response_obj.has_member("expires_in")) {
                var duration = response_obj.get_int_member("expires_in");
                var abs_time = GLib.get_real_time() + duration * 1000L * 1000L;
                on_expiry_time_avilable(abs_time);
            }

            if (response_obj.has_member("refresh_token")) {
                string refresh_token = response_obj.get_string_member("refresh_token");

                if (refresh_token != "")
                    on_refresh_token_available(refresh_token);
            }

            if (response_obj.has_member("access_token")) {
                string access_token = response_obj.get_string_member("access_token");

                if (access_token != "")
                    on_access_token_available(access_token);
            }
        }

        private void on_refresh_token_available(string token) {
            debug("EVENT: an OAuth refresh token has become available; token = '%s'.", token);
            this.params.insert("RefreshToken", new Variant.string(token));

            session.refresh_token = token;
        }

        private void on_expiry_time_avilable(int64 abs_time) {
            debug("EVENT: an OAuth access token expiry time became available; time = %'" + int64.FORMAT +
                    "'.", abs_time);

            session.expires_at = abs_time;
            this.params.insert("ExpiryTime", new Variant.int64(abs_time));
        }


        private void on_access_token_available(string token) {
            debug("EVENT: an OAuth access token has become available; token = '%s'.", token);

            session.access_token = token;
            this.params.insert("AccessToken", new Variant.string(token));

            do_fetch_username.begin();
        }

        private async void do_fetch_username() {
            debug("ACTION: running network transaction to fetch username.");

            host.install_login_wait_pane();
            host.set_service_locked(true);

            UsernameFetchTransaction txn = new UsernameFetchTransaction(session);

            try {
                yield txn.execute_async();
                debug("EVENT: username fetch transaction completed successfully.");
                do_extract_username(txn.get_response());
            } catch (Error err) {
                debug("EVENT: username fetch transaction caused a network error");

                host.post_error(err);
            }
        }

        private void do_extract_username(string response_body) {
            debug("ACTION: extracting username from body of server response");

            Json.Parser parser = new Json.Parser();

            try {
                parser.load_from_data(response_body);
            } catch (Error err) {
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                            "Couldn't parse JSON response: " + err.message));
                return;
            }

            Json.Object response_obj = parser.get_root().get_object();

            if (response_obj.has_member("name")) {
                string username = response_obj.get_string_member("name");

                if (username != "")
                    this.params.insert("UserName", new Variant.string(username));
            }

            if (response_obj.has_member("access_token")) {
                string access_token = response_obj.get_string_member("access_token");

                if (access_token != "")
                    this.params.insert("AccessToken", new Variant.string(access_token));
            }

            // by the time we get a username, the session should be authenticated, or else something
            // really tragic has happened
            assert(session.is_authenticated());
            try {
                Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                    "Shotwell publishing (Google account scope %s@%s)".printf(this.accountname, get_scopes()),
                    session.refresh_token, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    SCHEMA_KEY_ACCOUNTNAME, this.accountname, "scope", get_scopes());
            } catch (Error err) {
                critical("Failed to look up password for scope %s: %s", get_scopes(), err.message);
            }

            this.authenticated();
        }

        private async void do_exchange_refresh_token_for_access_token() {
            debug("ACTION: exchanging OAuth refresh token for OAuth access token.");

            host.install_login_wait_pane();

            RefreshAccessTokenTransaction txn = new RefreshAccessTokenTransaction(session);
            try {
                yield txn.execute_async();
                debug("EVENT: refresh access token transaction completed successfully.");

                if (session.is_authenticated()) // ignore these events if the session is already auth'd
                    return;
    
                do_extract_tokens(txn.get_response());
            } catch (Error err) {
                debug("EVENT: refresh access token transaction caused a network error.");

                if (session.is_authenticated()) // ignore these events if the session is already auth'd
                    return;

                if (txn.get_status_code() == Soup.Status.BAD_REQUEST ||
                    txn.get_status_code() == Soup.Status.UNAUTHORIZED) {
                    // Refresh token invalid, starting over
                    try {
                        Secret.password_clear_sync(this.schema, null,
                            SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                            SCHEMA_KEY_ACCOUNTNAME, this.accountname, "scope", get_scopes());
                    } catch (Error err) {
                        critical("Failed to remove password for accountname@scope %s@%s: %s", this.accountname, get_scopes(), err.message);
                    }

                    Idle.add (() => { this.authenticate(); return false; });
                }

                host.post_error(err);
            }
        }

        private void do_show_service_welcome_pane() {
            debug("ACTION: showing service welcome pane.");

            this.host.install_welcome_pane(this.welcome_message, on_service_welcome_login);
        }

        private void on_service_welcome_login() {
            debug("EVENT: user clicked 'Login' in welcome pane.");

            this.do_hosted_web_authentication.begin();
        }
    }
}
