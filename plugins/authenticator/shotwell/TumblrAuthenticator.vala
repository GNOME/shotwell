/* Copyright 2012 BJA Electronics
 * Copyright 2017 Jens Georg
 * Author: Jeroen Arnoldus (b.j.arnoldus@bja-electronics.nl)
 * Author: Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Publishing.Authenticator.Shotwell.Tumblr {
    internal const string ENDPOINT_URL = "https://www.tumblr.com/";
    internal const string API_KEY = "NdXvXQuKVccOsCOj0H4k9HUJcbcjDBYSo2AkaHzXFECHGNuP9k";
    internal const string API_SECRET = "BN0Uoig0MwbeD27OgA0IwYlp3Uvonyfsrl9pf1cnnMj1QoEUvi";
    internal const string ENCODE_RFC_3986_EXTRA = "!*'();:@&=+$,/?%#[] \\";

    /**
     * The authentication pane used when asking service URL, user name and password
     * from the user.
     */
    internal class AuthenticationPane : Spit.Publishing.DialogPane, Object {
        public enum Mode {
            INTRO,
            FAILED_RETRY_USER
        }
        private static string INTRO_MESSAGE = _("Enter the username and password associated with your Tumblr account.");
        private static string FAILED_RETRY_USER_MESSAGE = _("Username and/or password invalid. Please try again");

        private Gtk.Box pane_widget = null;
        private Gtk.Builder builder;
        private Gtk.Entry username_entry;
        private Gtk.Entry password_entry;
        private Gtk.Button login_button;

        public signal void login(string user, string password);

        public AuthenticationPane(Mode mode = Mode.INTRO) {
            this.pane_widget = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            try {
                builder = new Gtk.Builder();
                builder.add_from_resource (Resources.RESOURCE_PATH + "/tumblr_authentication_pane.ui");
                builder.connect_signals(null);
                var content = builder.get_object ("content") as Gtk.Widget;

                Gtk.Label message_label = builder.get_object("message_label") as Gtk.Label;
                switch (mode) {
                    case Mode.INTRO:
                        message_label.set_text(INTRO_MESSAGE);
                        break;

                    case Mode.FAILED_RETRY_USER:
                        message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                                        "Invalid User Name or Password"), FAILED_RETRY_USER_MESSAGE));
                        break;
                }

                username_entry = builder.get_object ("username_entry") as Gtk.Entry;

                password_entry = builder.get_object ("password_entry") as Gtk.Entry;



                login_button = builder.get_object("login_button") as Gtk.Button;

                username_entry.changed.connect(on_user_changed);
                password_entry.changed.connect(on_password_changed);
                login_button.clicked.connect(on_login_button_clicked);

                content.parent.remove (content);
                pane_widget.add (content);
            } catch (Error e) {
                warning(_("Could not load UI: %s"), e.message);
            }
        }

        public Gtk.Widget get_default_widget() {
            return login_button;
        }

        private void on_login_button_clicked() {
            login(username_entry.get_text(),
                    password_entry.get_text());
        }


        private void on_user_changed() {
            update_login_button_sensitivity();
        }

        private void on_password_changed() {
            update_login_button_sensitivity();
        }

        private void update_login_button_sensitivity() {
            login_button.set_sensitive(username_entry.text_length > 0 &&
                    password_entry.text_length > 0);
        }

        public Gtk.Widget get_widget() {
            return pane_widget;
        }

        public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
            return Spit.Publishing.DialogPane.GeometryOptions.NONE;
        }

        public void on_pane_installed() {
            username_entry.grab_focus();
            password_entry.set_activates_default(true);
            login_button.can_default = true;
            update_login_button_sensitivity();
        }

        public void on_pane_uninstalled() {
        }
    }

    // REST support classes
    internal class Transaction : Publishing.RESTSupport.Transaction {
        public Transaction(Session session, Publishing.RESTSupport.HttpMethod method =
                Publishing.RESTSupport.HttpMethod.POST) {
            base(session, method);

        }

        public Transaction.with_uri(Session session, string uri,
                Publishing.RESTSupport.HttpMethod method = Publishing.RESTSupport.HttpMethod.POST) {
            base.with_endpoint_url(session, uri, method);

            add_argument("oauth_nonce", session.get_oauth_nonce());
            add_argument("oauth_signature_method", "HMAC-SHA1");
            add_argument("oauth_version", "1.0");
            add_argument("oauth_timestamp", session.get_oauth_timestamp());
            add_argument("oauth_consumer_key", API_KEY);
            if (session.get_access_phase_token() != null) {
                add_argument("oauth_token", session.get_access_phase_token());
            }
        }

        public override void execute() throws Spit.Publishing.PublishingError {
            ((Session) get_parent_session()).sign_transaction(this);

            base.execute();
        }

    }

    internal class AccessTokenFetchTransaction : Transaction {
        public AccessTokenFetchTransaction(Session session, string username, string password) {
            base.with_uri(session, "https://www.tumblr.com/oauth/access_token",
                    Publishing.RESTSupport.HttpMethod.POST);
            add_argument("x_auth_username", Soup.URI.encode(username, ENCODE_RFC_3986_EXTRA));
            add_argument("x_auth_password", password);
            add_argument("x_auth_mode", "client_auth");
        }
    }


    /**
     * Session class that keeps track of the authentication status and of the
     * user token tumblr.
     */
    internal class Session : Publishing.RESTSupport.Session {
        private string? access_phase_token = null;
        private string? access_phase_token_secret = null;
        private string? username = null;

        public Session() {
            base(ENDPOINT_URL);
        }

        public override bool is_authenticated() {
            return (access_phase_token != null && access_phase_token_secret != null);
        }

        public void authenticate_from_persistent_credentials(string token, string secret) {
            this.access_phase_token = token;
            this.access_phase_token_secret = secret;


            debug("Emitting authenticated() signal");
            authenticated();
        }

        public void deauthenticate() {
            access_phase_token = null;
            access_phase_token_secret = null;
        }

        public void sign_transaction(Publishing.RESTSupport.Transaction txn) {
            string http_method = txn.get_method().to_string();

            debug("signing transaction with parameters:");
            debug("HTTP method = " + http_method);
            string? signing_key = null;
            if (access_phase_token_secret != null) {
                debug("access phase token secret available; using it as signing key");

                signing_key = API_SECRET + "&" + this.get_access_phase_token_secret();
            } else {
                debug("Access phase token secret not available; using API " +
                        "key as signing key");

                signing_key = API_SECRET + "&";
            }


            Publishing.RESTSupport.Argument[] base_string_arguments = txn.get_arguments();

            Publishing.RESTSupport.Argument[] sorted_args =
                Publishing.RESTSupport.Argument.sort(base_string_arguments);

            string arguments_string = "";
            for (int i = 0; i < sorted_args.length; i++) {
                arguments_string += (sorted_args[i].key + "=" + sorted_args[i].value);
                if (i < sorted_args.length - 1)
                    arguments_string += "&";
            }


            string signature_base_string = http_method + "&" + Soup.URI.encode(
                    txn.get_endpoint_url(), ENCODE_RFC_3986_EXTRA) + "&" +
                Soup.URI.encode(arguments_string, ENCODE_RFC_3986_EXTRA);

            debug("signature base string = '%s'", signature_base_string);
            debug("signing key = '%s'", signing_key);

            // compute the signature
            string signature = Publishing.RESTSupport.hmac_sha1(signing_key, signature_base_string);
            debug("signature = '%s'", signature);
            signature = Soup.URI.encode(signature, ENCODE_RFC_3986_EXTRA);

            debug("signature after RFC encode = '%s'", signature);

            txn.add_argument("oauth_signature", signature);
        }

        public void set_access_phase_credentials(string token, string secret) {
            this.access_phase_token = token;
            this.access_phase_token_secret = secret;

            authenticated();
        }

        public string get_access_phase_token() {
            return access_phase_token;
        }


        public string get_access_phase_token_secret() {
            return access_phase_token_secret;
        }

        public string get_username() {
            return this.username;
        }

        public void set_username(string username) {
            this.username = username;
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
    }

    internal class Tumblr : Spit.Publishing.Authenticator, GLib.Object {
        private GLib.HashTable<string, Variant> params;
        private Spit.Publishing.PluginHost host;
        private Session session;

        public Tumblr(Spit.Publishing.PluginHost host) {
            base();

            this.host = host;

            this.params = new GLib.HashTable<string, Variant>(str_hash, str_equal);
            params.insert("ConsumerKey", API_KEY);
            params.insert("ConsumerSecret", API_SECRET);

            this.session = new Session();
            this.session.authenticated.connect(this.on_session_authenticated);
        }

        ~Tumblr() {
            this.session.authenticated.disconnect(this.on_session_authenticated);
        }

        public void authenticate() {
            if (is_persistent_session_valid()) {
                debug("attempt start: a persistent session is available; using it");

                session.authenticate_from_persistent_credentials(get_persistent_access_phase_token(),
                        get_persistent_access_phase_token_secret());
            } else {
                debug("attempt start: no persistent session available; showing login welcome pane");

                do_show_authentication_pane();
            }
        }

        public bool can_logout() {
            return true;
        }

        public GLib.HashTable<string, Variant> get_authentication_parameter() {
            return this.params;
        }

        public void logout() {
            this.session.deauthenticate();
            invalidate_persistent_session();
        }

        public void refresh() { }

        private void on_session_authenticated() {
            params.insert("AuthToken", session.get_access_phase_token());
            params.insert("AuthTokenSecret", session.get_access_phase_token_secret());
            params.insert("Username", session.get_username());

            set_persistent_access_phase_token(session.get_access_phase_token());
            set_persistent_access_phase_token_secret(session.get_access_phase_token_secret());

            this.authenticated();
        }

        private void invalidate_persistent_session() {
            set_persistent_access_phase_token("");
            set_persistent_access_phase_token_secret("");
        }

        private void set_persistent_access_phase_token(string? token) {
            host.set_config_string("token", token);
        }

        private void set_persistent_access_phase_token_secret(string? token_secret) {
            host.set_config_string("token_secret", token_secret);
        }

        private bool is_persistent_session_valid() {
            string? access_phase_token = get_persistent_access_phase_token();
            string? access_phase_token_secret = get_persistent_access_phase_token_secret();

            bool valid = ((access_phase_token != null) && (access_phase_token_secret != null));

            if (valid)
                debug("existing Tumblr session found in configuration database; using it.");
            else
                debug("no persisted Tumblr session exists.");

            return valid;
        }

        public string? get_persistent_access_phase_token() {
            return host.get_config_string("token", null);
        }

        public string? get_persistent_access_phase_token_secret() {
            return host.get_config_string("token_secret", null);
        }

        /**
         * Action that shows the authentication pane.
         *
         * This action method shows the authentication pane. It is shown at the
         * very beginning of the interaction when no persistent parameters are found
         * or after a failed login attempt using persisted parameters. It can be
         * given a mode flag to specify whether it should be displayed in initial
         * mode or in any of the error modes that it supports.
         *
         * @param mode the mode for the authentication pane
         */
        private void do_show_authentication_pane(AuthenticationPane.Mode mode = AuthenticationPane.Mode.INTRO) {
            debug("ACTION: installing authentication pane");

            host.set_service_locked(false);
            AuthenticationPane authentication_pane = new AuthenticationPane(mode);
            authentication_pane.login.connect(on_authentication_pane_login_clicked);
            host.install_dialog_pane(authentication_pane, Spit.Publishing.PluginHost.ButtonMode.CLOSE);
            host.set_dialog_default_widget(authentication_pane.get_default_widget());
        }

        /**
         * Event triggered when the login button in the authentication panel is
         * clicked.
         *
         * This event is triggered when the login button in the authentication
         * panel is clicked. It then triggers a network login interaction.
         *
         * @param username the name of the Tumblr user as entered in the dialog
         * @param password the password of the Tumblr as entered in the dialog
         */
        private void on_authentication_pane_login_clicked( string username, string password ) {
            debug("EVENT: on_authentication_pane_login_clicked");

            do_network_login(username, password);
        }

        /**
         * Action to perform a network login to a Tumblr blog.
         *
         * This action performs a network login a Tumblr blog specified the given user name and password as credentials.
         *
         * @param username the name of the Tumblr user used to login
         * @param password the password of the Tumblr user used to login
         */
        private void do_network_login(string username, string password) {
            debug("ACTION: logging in");
            host.set_service_locked(true);
            host.install_login_wait_pane();
            session.set_username(username);

            AccessTokenFetchTransaction txn = new AccessTokenFetchTransaction(session,username,password);
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
        }

        private void do_parse_token_info_from_auth_request(string response) {
            debug("ACTION: parsing authorization request response '%s' into token and secret", response);

            string? oauth_token = null;
            string? oauth_token_secret = null;

            string[] key_value_pairs = response.split("&");
            foreach (string pair in key_value_pairs) {
                string[] split_pair = pair.split("=");

                if (split_pair.length != 2)
                    host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                                _("“%s” isn’t a valid response to an OAuth authentication request"), response));

                if (split_pair[0] == "oauth_token")
                    oauth_token = split_pair[1];
                else if (split_pair[0] == "oauth_token_secret")
                    oauth_token_secret = split_pair[1];
            }

            if (oauth_token == null || oauth_token_secret == null)
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                            _("“%s” isn’t a valid response to an OAuth authentication request"), response));

            session.set_access_phase_credentials(oauth_token, oauth_token_secret);
        }
    }
}
