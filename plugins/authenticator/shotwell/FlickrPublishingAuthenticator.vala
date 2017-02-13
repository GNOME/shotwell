/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Publishing.Authenticator.Shotwell.Flickr {
    internal const string ENDPOINT_URL = "https://api.flickr.com/services/rest";
    internal const string EXPIRED_SESSION_ERROR_CODE = "98";
    internal const string ENCODE_RFC_3986_EXTRA = "!*'();:@&=+$,/?%#[] \\";

    internal class Transaction : Publishing.RESTSupport.Transaction {
        public Transaction(Session session, Publishing.RESTSupport.HttpMethod method =
                Publishing.RESTSupport.HttpMethod.POST) {
            base(session, method);
            setup_arguments();
        }

        public Transaction.with_uri(Session session, string uri,
                Publishing.RESTSupport.HttpMethod method = Publishing.RESTSupport.HttpMethod.POST) {
            base.with_endpoint_url(session, uri, method);
            setup_arguments();
        }

        private void setup_arguments() {
            var session = (Session) get_parent_session();

            add_argument("oauth_nonce", session.get_oauth_nonce());
            add_argument("oauth_signature_method", "HMAC-SHA1");
            add_argument("oauth_version", "1.0");
            add_argument("oauth_callback", "oob");
            add_argument("oauth_timestamp", session.get_oauth_timestamp());
            add_argument("oauth_consumer_key", session.get_consumer_key());
        }


        public override void execute() throws Spit.Publishing.PublishingError {
            ((Session) get_parent_session()).sign_transaction(this);

            base.execute();
        }
    }

    internal class Session : Publishing.RESTSupport.Session {
        private string? request_phase_token = null;
        private string? request_phase_token_secret = null;
        private string? access_phase_token = null;
        private string? access_phase_token_secret = null;
        private string? username = null;
        private string? consumer_key = null;
        private string? consumer_secret = null;

        public Session() {
            base();
        }

        public override bool is_authenticated() {
            return (access_phase_token != null && access_phase_token_secret != null &&
                    username != null);
        }

        public void authenticate_from_persistent_credentials(string token, string secret,
                string username) {
            this.access_phase_token = token;
            this.access_phase_token_secret = secret;
            this.username = username;

            this.authenticated();
        }

        public void deauthenticate() {
            access_phase_token = null;
            access_phase_token_secret = null;
            username = null;
        }

        public void set_api_credentials(string consumer_key, string consumer_secret) {
            this.consumer_key = consumer_key;
            this.consumer_secret = consumer_secret;
        }

        public void sign_transaction(Publishing.RESTSupport.Transaction txn) {
            string http_method = txn.get_method().to_string();

            debug("signing transaction with parameters:");
            debug("HTTP method = " + http_method);

            Publishing.RESTSupport.Argument[] base_string_arguments = txn.get_arguments();

            Publishing.RESTSupport.Argument[] sorted_args =
                Publishing.RESTSupport.Argument.sort(base_string_arguments);

            string arguments_string = "";
            for (int i = 0; i < sorted_args.length; i++) {
                arguments_string += (sorted_args[i].key + "=" + sorted_args[i].value);
                if (i < sorted_args.length - 1)
                    arguments_string += "&";
            }

            string? signing_key = null;
            if (access_phase_token_secret != null) {
                debug("access phase token secret available; using it as signing key");

                signing_key = consumer_secret + "&" + access_phase_token_secret;
            } else if (request_phase_token_secret != null) {
                debug("request phase token secret available; using it as signing key");

                signing_key = consumer_secret + "&" + request_phase_token_secret;
            } else {
                debug("neither access phase nor request phase token secrets available; using API " +
                        "key as signing key");

                signing_key = consumer_secret + "&";
            }

            string signature_base_string = http_method + "&" + Soup.URI.encode(
                    txn.get_endpoint_url(), ENCODE_RFC_3986_EXTRA) + "&" +
                Soup.URI.encode(arguments_string, ENCODE_RFC_3986_EXTRA);

            debug("signature base string = '%s'", signature_base_string);

            debug("signing key = '%s'", signing_key);

            // compute the signature
            string signature = RESTSupport.hmac_sha1(signing_key, signature_base_string);
            signature = Soup.URI.encode(signature, ENCODE_RFC_3986_EXTRA);

            debug("signature = '%s'", signature);

            txn.add_argument("oauth_signature", signature);
        }

        public void set_request_phase_credentials(string token, string secret) {
            this.request_phase_token = token;
            this.request_phase_token_secret = secret;
        }

        public void set_access_phase_credentials(string token, string secret, string username) {
            this.access_phase_token = token;
            this.access_phase_token_secret = secret;
            this.username = username;

            authenticated();
        }

        public string get_oauth_nonce() {
            TimeVal currtime = TimeVal();
            currtime.get_current_time();

            return Checksum.compute_for_string(ChecksumType.MD5, currtime.tv_sec.to_string() +
                    currtime.tv_usec.to_string());
        }

        public string get_oauth_timestamp() {
            return GLib.get_real_time().to_string().substring(0, 10);
        }

        public string get_consumer_key() {
            assert(consumer_key != null);
            return consumer_key;
        }

        public string get_request_phase_token() {
            assert(request_phase_token != null);
            return request_phase_token;
        }

        public string get_access_phase_token() {
            assert(access_phase_token != null);
            return access_phase_token;
        }

        public string get_access_phase_token_secret() {
            assert(access_phase_token_secret != null);
            return access_phase_token_secret;
        }

        public string get_username() {
            assert(is_authenticated());
            return username;
        }
    }
    internal const string API_KEY = "60dd96d4a2ad04888b09c9e18d82c26f";
    internal const string API_SECRET = "d0960565e03547c1";

    internal const string SERVICE_WELCOME_MESSAGE =
        _("You are not currently logged into Flickr.\n\nClick Log in to log into Flickr in your Web browser. You will have to authorize Shotwell Connect to link to your Flickr account.");

    internal class AuthenticationRequestTransaction : Transaction {
        public AuthenticationRequestTransaction(Session session) {
            base.with_uri(session, "https://www.flickr.com/services/oauth/request_token",
                    Publishing.RESTSupport.HttpMethod.GET);
        }
    }

    internal class AccessTokenFetchTransaction : Transaction {
        public AccessTokenFetchTransaction(Session session, string user_verifier) {
            base.with_uri(session, "https://www.flickr.com/services/oauth/access_token",
                    Publishing.RESTSupport.HttpMethod.GET);
            add_argument("oauth_verifier", user_verifier);
            add_argument("oauth_token", session.get_request_phase_token());
        }
    }

    internal class PinEntryPane : Spit.Publishing.DialogPane, GLib.Object {
        private Gtk.Box pane_widget = null;
        private Gtk.Button continue_button = null;
        private Gtk.Entry pin_entry = null;
        private Gtk.Label pin_entry_caption = null;
        private Gtk.Label explanatory_text = null;
        private Gtk.Builder builder = null;

        public signal void proceed(PinEntryPane sender, string authorization_pin);

        public PinEntryPane(Gtk.Builder builder) {
            this.builder = builder;
            assert(builder != null);
            assert(builder.get_objects().length() > 0);

            explanatory_text = builder.get_object("explanatory_text") as Gtk.Label;
            pin_entry_caption = builder.get_object("pin_entry_caption") as Gtk.Label;
            pin_entry = builder.get_object("pin_entry") as Gtk.Entry;
            continue_button = builder.get_object("continue_button") as Gtk.Button;

            pane_widget = builder.get_object("pane_widget") as Gtk.Box;

            pane_widget.show_all();

            on_pin_entry_contents_changed();
        }

        private void on_continue_clicked() {
            proceed(this, pin_entry.get_text());
        }

        private void on_pin_entry_contents_changed() {
            continue_button.set_sensitive(pin_entry.text_length > 0);
        }

        public Gtk.Widget get_widget() {
            return pane_widget;
        }

        public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
            return Spit.Publishing.DialogPane.GeometryOptions.NONE;
        }

        public void on_pane_installed() {
            continue_button.clicked.connect(on_continue_clicked);
            pin_entry.changed.connect(on_pin_entry_contents_changed);
        }

        public void on_pane_uninstalled() {
            continue_button.clicked.disconnect(on_continue_clicked);
            pin_entry.changed.disconnect(on_pin_entry_contents_changed);
        }
    }


    internal class Flickr : GLib.Object, Spit.Publishing.Authenticator {
        private GLib.HashTable<string, Variant> params;
        private Session session;
        private Spit.Publishing.PluginHost host;

        public Flickr(Spit.Publishing.PluginHost host) {
            base();

            this.host = host;
            params = new GLib.HashTable<string, Variant>(str_hash, str_equal);
            params.insert("ConsumerKey", API_KEY);
            params.insert("ConsumerSecret", API_SECRET);

            session = new Session();
            session.set_api_credentials(API_KEY, API_SECRET);
            session.authenticated.connect(on_session_authenticated);
        }

        ~Flickr() {
            session.authenticated.disconnect(on_session_authenticated);
        }

        public void invalidate_persistent_session() {
            set_persistent_access_phase_token("");
            set_persistent_access_phase_token_secret("");
            set_persistent_access_phase_username("");
        }

        private bool is_persistent_session_valid() {
            return (get_persistent_access_phase_username() != null &&
                    get_persistent_access_phase_token() != null &&
                    get_persistent_access_phase_token_secret() != null);
        }

        private string? get_persistent_access_phase_username() {
            return host.get_config_string("access_phase_username", null);
        }

        private void set_persistent_access_phase_username(string username) {
            host.set_config_string("access_phase_username", username);
        }

        private string? get_persistent_access_phase_token() {
            return host.get_config_string("access_phase_token", null);
        }

        private void set_persistent_access_phase_token(string token) {
            host.set_config_string("access_phase_token", token);
        }

        private string? get_persistent_access_phase_token_secret() {
            return host.get_config_string("access_phase_token_secret", null);
        }

        private void set_persistent_access_phase_token_secret(string secret) {
            host.set_config_string("access_phase_token_secret", secret);
        }

        public void authenticate() {
            if (is_persistent_session_valid()) {
                debug("attempt start: a persistent session is available; using it");

                session.authenticate_from_persistent_credentials(get_persistent_access_phase_token(),
                        get_persistent_access_phase_token_secret(), get_persistent_access_phase_username());
            } else {
                debug("attempt start: no persistent session available; showing login welcome pane");
                do_show_login_welcome_pane();
            }
        }

        public bool can_logout() {
            return true;
        }

        public GLib.HashTable<string, Variant> get_authentication_parameter() {
            return this.params;
        }

        public void logout () {
            session.deauthenticate();
            invalidate_persistent_session();
        }

        public void refresh() {
            // No-Op with flickr
        }

        private void do_show_login_welcome_pane() {
            debug("ACTION: installing login welcome pane");

            host.set_service_locked(false);
            host.install_welcome_pane(SERVICE_WELCOME_MESSAGE, on_welcome_pane_login_clicked);
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

            do_launch_system_browser(token);
        }

        private void on_system_browser_launched() {
            debug("EVENT: system browser launched.");

            do_show_pin_entry_pane();
        }

        private void on_pin_entry_proceed(PinEntryPane sender, string pin) {
            sender.proceed.disconnect(on_pin_entry_proceed);

            debug("EVENT: user clicked 'Continue' in PIN entry pane.");

            do_verify_pin(pin);
        }

        private void do_launch_system_browser(string token) {
            string login_uri = "https://www.flickr.com/services/oauth/authorize?oauth_token=" + token +
                "&perms=write";

            debug("ACTION: launching system browser with uri = '%s'", login_uri);

            try {
                Process.spawn_command_line_async("xdg-open " + login_uri);
            } catch (SpawnError e) {
                host.post_error(new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                            "couldn't launch system web browser to complete Flickr login"));
                return;
            }

            on_system_browser_launched();
        }

        private void do_show_pin_entry_pane() {
            debug("ACTION: showing PIN entry pane");

            Gtk.Builder builder = new Gtk.Builder();

            try {
                builder.add_from_resource (Resources.RESOURCE_PATH + "/" +
                        "flickr_pin_entry_pane.ui");
            } catch (Error e) {
                warning("Could not parse UI file! Error: %s.", e.message);
                host.post_error(
                        new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                            _("A file required for publishing is unavailable. Publishing to Flickr can’t continue.")));
                return;
            }

            PinEntryPane pin_entry_pane = new PinEntryPane(builder);
            pin_entry_pane.proceed.connect(on_pin_entry_proceed);
            host.install_dialog_pane(pin_entry_pane);
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

        private void on_session_authenticated() {
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
