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

    internal class AccessTokenFetchTransaction : Publishing.RESTSupport.OAuth1.Transaction {
        public AccessTokenFetchTransaction(Publishing.RESTSupport.OAuth1.Session session, string username, string password) {
            base.with_uri(session, "https://www.tumblr.com/oauth/access_token",
                    Publishing.RESTSupport.HttpMethod.POST);
            add_argument("x_auth_username", Soup.URI.encode(username, ENCODE_RFC_3986_EXTRA));
            add_argument("x_auth_password", password);
            add_argument("x_auth_mode", "client_auth");
        }
    }

    internal class Tumblr : Publishing.Authenticator.Shotwell.OAuth1.Authenticator {
        public Tumblr(Spit.Publishing.PluginHost host) {
            base(API_KEY, API_SECRET, host);
        }

        public override void authenticate() {
            if (is_persistent_session_valid()) {
                debug("attempt start: a persistent session is available; using it");

                session.authenticate_from_persistent_credentials(get_persistent_access_phase_token(),
                        get_persistent_access_phase_token_secret(), "");
            } else {
                debug("attempt start: no persistent session available; showing login welcome pane");

                do_show_authentication_pane();
            }
        }

        public override bool can_logout() {
            return true;
        }

        public override void logout() {
            this.session.deauthenticate();
            invalidate_persistent_session();
        }

        public override void refresh() {
            // No-op with Tumblr
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
            debug("ACTION: extracting access phase credentials from '%s'", response);

            string? token = null;
            string? token_secret = null;

            var data = Soup.Form.decode(response);
            data.lookup_extended("oauth_token", null, out token);
            data.lookup_extended("oauth_token_secret", null, out token_secret);

            debug("access phase credentials: { token = '%s'; token_secret = '%s' }",
                    token, token_secret);

            if (token == null || token_secret == null) {
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Expected " +
                            "access phase credentials to contain token and token secret but at " +
                            "least one of these is absent"));
                this.authentication_failed();
            } else {
                session.set_access_phase_credentials(token, token_secret, "");
            }
        }
    }
}
