/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Shotwell.Plugins;

namespace Publishing.Authenticator.Shotwell.Flickr {
    internal const string ENDPOINT_URL = "https://api.flickr.com/services/rest";
    internal const string EXPIRED_SESSION_ERROR_CODE = "98";

    internal const string API_KEY = "60dd96d4a2ad04888b09c9e18d82c26f";
    internal const string API_SECRET = "d0960565e03547c1";

    internal const string SERVICE_WELCOME_MESSAGE =
        _("You are not currently logged into Flickr.\n\nClick Log in to log into Flickr in your Web browser. You will have to authorize Shotwell Connect to link to your Flickr account.");
    internal const string SERVICE_DISCLAIMER = "<b>This product uses the Flickr API but is not endorsed or certified by SmugMug, Inc.</b>";

    internal class AuthenticationRequestTransaction : Publishing.RESTSupport.OAuth1.Transaction {
        public AuthenticationRequestTransaction(Publishing.RESTSupport.OAuth1.Session session) {
            base.with_uri(session, "https://www.flickr.com/services/oauth/request_token",
                    Publishing.RESTSupport.HttpMethod.GET);
            add_argument("oauth_callback", "shotwell-auth%3A%2F%2Flocal-callback");
        }
    }

    internal class AccessTokenFetchTransaction : Publishing.RESTSupport.OAuth1.Transaction {
        public AccessTokenFetchTransaction(Publishing.RESTSupport.OAuth1.Session session, string user_verifier) {
            base.with_uri(session, "https://www.flickr.com/services/oauth/access_token",
                    Publishing.RESTSupport.HttpMethod.GET);
            add_argument("oauth_verifier", user_verifier);
            add_argument("oauth_token", session.get_request_phase_token());
            add_argument("oauth_callback", "shotwell-auth%3A%2F%2Flocal-callback");
        }
    }

    internal class WebAuthenticationPane : Common.WebAuthenticationPane {
        private string? auth_code = null;
        private const string LOGIN_URI = "https://www.flickr.com/services/oauth/authorize?oauth_token=%s&perms=write";

        public signal void authorized(string auth_code);
        public signal void error();

        public WebAuthenticationPane(string token) {
            Object(login_uri : LOGIN_URI.printf(token));
        }

        public override void constructed() {
            base.constructed();

            var ctx = WebKit.WebContext.get_default();
            ctx.register_uri_scheme("shotwell-auth", this.on_shotwell_auth_request_cb);

            var mgr = ctx.get_security_manager();
            mgr.register_uri_scheme_as_secure("shotwell-auth");
            mgr.register_uri_scheme_as_cors_enabled("shotwell-auth");
        }

        public override void on_page_load() {
            if (this.load_error != null) {
                this.error();

                return;
            }

            var uri = new Soup.URI(get_view().get_uri());
            if (uri.scheme == "shotwell-auth" && this.auth_code == null) {
                var form_data = Soup.Form.decode (uri.query);
                this.auth_code = form_data.lookup("oauth_verifier");
            }

            if (this.auth_code != null) {
                this.authorized(this.auth_code);
            }
        }

        private void on_shotwell_auth_request_cb(WebKit.URISchemeRequest request) {
            var uri = new Soup.URI(request.get_uri());
            var form_data = Soup.Form.decode (uri.query);
            this.auth_code = form_data.lookup("oauth_verifier");

            var response = "";
            var mins = new MemoryInputStream.from_data(response.data, null);
            request.finish(mins, -1, "text/plain");
        }
    }

    internal class Flickr : Publishing.Authenticator.Shotwell.OAuth1.Authenticator {
        private WebAuthenticationPane pane;

        public Flickr(Spit.Publishing.PluginHost host) {
            base(API_KEY, API_SECRET, host);
        }

        public override void authenticate() {
            if (is_persistent_session_valid()) {
                debug("attempt start: a persistent session is available; using it");

                session.authenticate_from_persistent_credentials(get_persistent_access_phase_token(),
                        get_persistent_access_phase_token_secret(), get_persistent_access_phase_username());
            } else {
                debug("attempt start: no persistent session available; showing login welcome pane");
                do_show_login_welcome_pane();
            }
        }

        public override bool can_logout() {
            return true;
        }

        public override void logout () {
            session.deauthenticate();
            invalidate_persistent_session();
        }

        public override void refresh() {
            // No-Op with flickr
        }

        private void do_show_login_welcome_pane() {
            debug("ACTION: installing login welcome pane");

            host.set_service_locked(false);
            host.install_welcome_pane("%s\n\n%s".printf(SERVICE_WELCOME_MESSAGE, SERVICE_DISCLAIMER), on_welcome_pane_login_clicked);
        }

        private void on_welcome_pane_login_clicked() {
            debug("EVENT: user clicked 'Login' button in the welcome pane");

            do_run_authentication_request_transaction();
        }

        private void do_run_authentication_request_transaction() {
            debug("ACTION: running authentication request transaction");

            host.set_service_locked(true);
            host.install_static_message_pane(_("Preparing for login…"));

            AuthenticationRequestTransaction txn = new AuthenticationRequestTransaction(session);
            txn.completed.connect(on_auth_request_txn_completed);
            txn.network_error.connect(on_auth_request_txn_error);

            try {
                txn.execute();
            } catch (Spit.Publishing.PublishingError err) {
                host.post_error(err);
            }
        }

        private void on_auth_request_txn_completed(Publishing.RESTSupport.Transaction txn) {
            txn.completed.disconnect(on_auth_request_txn_completed);
            txn.network_error.disconnect(on_auth_request_txn_error);

            debug("EVENT: OAuth authentication request transaction completed; response = '%s'",
                txn.get_response());

            do_parse_token_info_from_auth_request(txn.get_response());
        }

        private void on_auth_request_txn_error(Publishing.RESTSupport.Transaction txn,
                Spit.Publishing.PublishingError err) {
            txn.completed.disconnect(on_auth_request_txn_completed);
            txn.network_error.disconnect(on_auth_request_txn_error);

            debug("EVENT: OAuth authentication request transaction caused a network error");
            host.post_error(err);

            this.authentication_failed();
        }

        private void do_parse_token_info_from_auth_request(string response) {
            debug("ACTION: parsing authorization request response '%s' into token and secret", response);

            string? oauth_token = null;
            string? oauth_token_secret = null;

            var data = Soup.Form.decode(response);
            data.lookup_extended("oauth_token", null, out oauth_token);
            data.lookup_extended("oauth_token_secret", null, out oauth_token_secret);

            if (oauth_token == null || oauth_token_secret == null)
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                            "'%s' isn't a valid response to an OAuth authentication request", response));


            on_authentication_token_available(oauth_token, oauth_token_secret);
        }

        private void on_authentication_token_available(string token, string token_secret) {
            debug("EVENT: OAuth authentication token (%s) and token secret (%s) available",
                    token, token_secret);

            session.set_request_phase_credentials(token, token_secret);

            do_web_authentication(token);
        }

        private void do_web_authentication(string token) {
            pane = new WebAuthenticationPane(token);
            host.install_dialog_pane(pane);
            pane.authorized.connect(this.do_verify_pin);
            pane.error.connect(this.on_web_login_error);
        }

        private void on_web_login_error() {
            if (pane.load_error != null) {
                host.post_error(pane.load_error);
                return;
            }
            host.post_error(new Spit.Publishing.PublishingError.PROTOCOL_ERROR(_("Flickr authorization failed")));
        }

        private void do_verify_pin(string pin) {
            debug("ACTION: validating authorization PIN %s", pin);

            host.set_service_locked(true);
            host.install_static_message_pane(_("Verifying authorization…"));

            AccessTokenFetchTransaction txn = new AccessTokenFetchTransaction(session, pin);
            txn.completed.connect(on_access_token_fetch_txn_completed);
            txn.network_error.connect(on_access_token_fetch_error);

            try {
                txn.execute();
            } catch (Spit.Publishing.PublishingError err) {
                host.post_error(err);
            }
        }

        private void on_access_token_fetch_txn_completed(Publishing.RESTSupport.Transaction txn) {
            txn.completed.disconnect(on_access_token_fetch_txn_completed);
            txn.network_error.disconnect(on_access_token_fetch_error);

            debug("EVENT: fetching OAuth access token over the network succeeded");

            do_extract_access_phase_credentials_from_reponse(txn.get_response());
        }

        private void on_access_token_fetch_error(Publishing.RESTSupport.Transaction txn,
                Spit.Publishing.PublishingError err) {
            txn.completed.disconnect(on_access_token_fetch_txn_completed);
            txn.network_error.disconnect(on_access_token_fetch_error);

            debug("EVENT: fetching OAuth access token over the network caused an error.");

            host.post_error(err);
            this.authentication_failed();
        }

        private void do_extract_access_phase_credentials_from_reponse(string response) {
            debug("ACTION: extracting access phase credentials from '%s'", response);

            string? token = null;
            string? token_secret = null;
            string? username = null;

            var data = Soup.Form.decode(response);
            data.lookup_extended("oauth_token", null, out token);
            data.lookup_extended("oauth_token_secret", null, out token_secret);
            data.lookup_extended("username", null, out username);

            debug("access phase credentials: { token = '%s'; token_secret = '%s'; username = '%s' }",
                    token, token_secret, username);

            if (token == null || token_secret == null || username == null) {
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("expected " +
                            "access phase credentials to contain token, token secret, and username but at " +
                            "least one of these is absent"));
                this.authentication_failed();
            } else {
                session.set_access_phase_credentials(token, token_secret, username);
            }
        }

    }
}
