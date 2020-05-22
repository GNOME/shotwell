using Shotwell;
using Shotwell.Plugins;

namespace Publishing.Authenticator.Shotwell.Google {
    private const string OAUTH_CLIENT_ID = "534227538559-hvj2e8bj0vfv2f49r7gvjoq6jibfav67.apps.googleusercontent.com";
    private const string REVERSE_CLIENT_ID = "com.googleusercontent.apps.534227538559-hvj2e8bj0vfv2f49r7gvjoq6jibfav67";
    private const string OAUTH_CLIENT_SECRET = "pwpzZ7W1TCcD5uIfYCu8sM7x";
    private const string OAUTH_CALLBACK_URI = REVERSE_CLIENT_ID + ":/auth-callback";

    private class WebAuthenticationPane : Common.WebAuthenticationPane {
        public static bool cache_dirty = false;
        private string? auth_code = null;

        public signal void error();

        public override void constructed() {
            base.constructed();

            var ctx = WebKit.WebContext.get_default();
            ctx.register_uri_scheme(REVERSE_CLIENT_ID, this.on_shotwell_auth_request_cb);
        }

        public override void on_page_load() {
            if (this.load_error != null) {
                this.error ();

                return;
            }

            var uri = new Soup.URI(get_view().get_uri());
            if (uri.scheme == REVERSE_CLIENT_ID && this.auth_code == null) {
                var form_data = Soup.Form.decode (uri.query);
                this.auth_code = form_data.lookup("code");
            }

            if (this.auth_code != null) {
                this.authorized(this.auth_code);
            }
        }

        private void on_shotwell_auth_request_cb(WebKit.URISchemeRequest request) {
            var uri = new Soup.URI(request.get_uri());
            debug("URI: %s", request.get_uri());
            var form_data = Soup.Form.decode (uri.query);
            this.auth_code = form_data.lookup("code");

            var response = "";
            var mins = new MemoryInputStream.from_data(response.data, null);
            request.finish(mins, -1, "text/plain");
        }

        public signal void authorized(string auth_code);

        public WebAuthenticationPane(string auth_sequence_start_url) {
            Object (login_uri : auth_sequence_start_url);
        }

        public static bool is_cache_dirty() {
            return cache_dirty;
        }
    }

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
        private const string ENDPOINT_URL = "https://accounts.google.com/o/oauth2/token";

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
        private const string ENDPOINT_URL = "https://accounts.google.com/o/oauth2/token";

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
        private string scope = null;
        private Spit.Publishing.PluginHost host = null;
        private GLib.HashTable<string, Variant> params = null;
        private WebAuthenticationPane web_auth_pane = null;
        private Session session = null;
        private string welcome_message = null;

        public Google(string scope,
                      string welcome_message,
                      Spit.Publishing.PluginHost host) {
            this.host = host;
            this.params = new GLib.HashTable<string, Variant>(str_hash, str_equal);
            this.scope = scope;
            this.session = new Session();
            this.welcome_message = welcome_message;
        }

        public void authenticate() {
            var refresh_token = host.get_config_string("refresh_token", null);
            if (refresh_token != null && refresh_token != "") {
                on_refresh_token_available(refresh_token);
                do_exchange_refresh_token_for_access_token();
                return;
            }

            // FIXME: Find a way for a proper logout
            if (WebAuthenticationPane.is_cache_dirty()) {
                host.set_service_locked(false);

                host.install_static_message_pane(_("You have already logged in and out of a Google service during this Shotwell session.\n\nTo continue publishing to Google services, quit and restart Shotwell, then try publishing again."));
            } else {
                this.do_show_service_welcome_pane();
            }
        }

        public bool can_logout() {
            return true;
        }

        public GLib.HashTable<string, Variant> get_authentication_parameter() {
            return this.params;
        }

        public void logout() {
            session.deauthenticate();
            host.set_config_string("refresh_token", "");
        }

        public void refresh() {
            // TODO: Needs to re-auth
        }

        private void do_hosted_web_authentication() {
            debug("ACTION: running OAuth authentication flow in hosted web pane.");

            string user_authorization_url = "https://accounts.google.com/o/oauth2/auth?" +
                "response_type=code&" +
                "client_id=" + OAUTH_CLIENT_ID + "&" +
                "redirect_uri=" + Soup.URI.encode(OAUTH_CALLBACK_URI, null) + "&" +
                "scope=" + Soup.URI.encode(this.scope, null) + "+" +
                Soup.URI.encode("https://www.googleapis.com/auth/userinfo.profile", null) + "&" +
                "state=connect&" +
                "access_type=offline&" +
                "approval_prompt=force";

            web_auth_pane = new WebAuthenticationPane(user_authorization_url);
            web_auth_pane.authorized.connect(on_web_auth_pane_authorized);
            web_auth_pane.error.connect(on_web_auth_pane_error);

            host.install_dialog_pane(web_auth_pane);
        }

        private void on_web_auth_pane_authorized(string auth_code) {
            web_auth_pane.authorized.disconnect(on_web_auth_pane_authorized);

            debug("EVENT: user authorized scope %s with auth_code %s", scope, auth_code);

            do_get_access_tokens(auth_code);
        }

        private void on_web_auth_pane_error() {
            host.post_error(web_auth_pane.load_error);
        }

        private void do_get_access_tokens(string auth_code) {
            debug("ACTION: exchanging authorization code for access & refresh tokens");

            host.install_login_wait_pane();

            GetAccessTokensTransaction tokens_txn = new GetAccessTokensTransaction(session, auth_code);
            tokens_txn.completed.connect(on_get_access_tokens_complete);
            tokens_txn.network_error.connect(on_get_access_tokens_error);

            try {
                tokens_txn.execute();
            } catch (Spit.Publishing.PublishingError err) {
                host.post_error(err);
            }
        }

        private void on_get_access_tokens_complete(Publishing.RESTSupport.Transaction txn) {
            txn.completed.disconnect(on_get_access_tokens_complete);
            txn.network_error.disconnect(on_get_access_tokens_error);

            debug("EVENT: network transaction to exchange authorization code for access tokens " +
                    "completed successfully.");

            do_extract_tokens(txn.get_response());
        }

        private void on_get_access_tokens_error(Publishing.RESTSupport.Transaction txn,
                Spit.Publishing.PublishingError err) {
            txn.completed.disconnect(on_get_access_tokens_complete);
            txn.network_error.disconnect(on_get_access_tokens_error);

            debug("EVENT: network transaction to exchange authorization code for access tokens " +
                    "failed; response = '%s'", txn.get_response());

            host.post_error(err);
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

            do_fetch_username();
        }

        private void do_fetch_username() {
            debug("ACTION: running network transaction to fetch username.");

            host.install_login_wait_pane();
            host.set_service_locked(true);

            UsernameFetchTransaction txn = new UsernameFetchTransaction(session);
            txn.completed.connect(on_fetch_username_transaction_completed);
            txn.network_error.connect(on_fetch_username_transaction_error);

            try {
                txn.execute();
            } catch (Error err) {
                host.post_error(err);
            }
        }

        private void on_fetch_username_transaction_completed(Publishing.RESTSupport.Transaction txn) {
            txn.completed.disconnect(on_fetch_username_transaction_completed);
            txn.network_error.disconnect(on_fetch_username_transaction_error);

            debug("EVENT: username fetch transaction completed successfully.");

            do_extract_username(txn.get_response());
        }

        private void on_fetch_username_transaction_error(Publishing.RESTSupport.Transaction txn,
                Spit.Publishing.PublishingError err) {
            txn.completed.disconnect(on_fetch_username_transaction_completed);
            txn.network_error.disconnect(on_fetch_username_transaction_error);

            debug("EVENT: username fetch transaction caused a network error");

            host.post_error(err);
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
            host.set_config_string("refresh_token", session.refresh_token);

            this.authenticated();
            web_auth_pane.clear();
        }


        private void do_exchange_refresh_token_for_access_token() {
            debug("ACTION: exchanging OAuth refresh token for OAuth access token.");

            host.install_login_wait_pane();

            RefreshAccessTokenTransaction txn = new RefreshAccessTokenTransaction(session);

            txn.completed.connect(on_refresh_access_token_transaction_completed);
            txn.network_error.connect(on_refresh_access_token_transaction_error);

            try {
                txn.execute();
            } catch (Spit.Publishing.PublishingError err) {
                host.post_error(err);
            }
        }

        private void on_refresh_access_token_transaction_completed(Publishing.RESTSupport.Transaction
                txn) {
            txn.completed.disconnect(on_refresh_access_token_transaction_completed);
            txn.network_error.disconnect(on_refresh_access_token_transaction_error);

            debug("EVENT: refresh access token transaction completed successfully.");

            if (session.is_authenticated()) // ignore these events if the session is already auth'd
                return;

            do_extract_tokens(txn.get_response());
        }

        private void on_refresh_access_token_transaction_error(Publishing.RESTSupport.Transaction txn,
                Spit.Publishing.PublishingError err) {
            txn.completed.disconnect(on_refresh_access_token_transaction_completed);
            txn.network_error.disconnect(on_refresh_access_token_transaction_error);

            debug("EVENT: refresh access token transaction caused a network error.");

            if (session.is_authenticated()) // ignore these events if the session is already auth'd
                return;
            if (txn.get_status_code() == Soup.Status.BAD_REQUEST ||
                txn.get_status_code() == Soup.Status.UNAUTHORIZED) {
                // Refresh token invalid, starting over
                host.set_config_string("refresh_token", "");
                Idle.add (() => { this.authenticate(); return false; });
            }

            web_auth_pane.clear();
            host.post_error(err);
        }

        private void do_show_service_welcome_pane() {
            debug("ACTION: showing service welcome pane.");

            this.host.install_welcome_pane(this.welcome_message, on_service_welcome_login);
        }

        private void on_service_welcome_login() {
            debug("EVENT: user clicked 'Login' in welcome pane.");

            this.do_hosted_web_authentication();
        }


    }
}
