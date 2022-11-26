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
        /**
         * Call to register client with the instance.
         * 
         * For a normal OAuth2 flow, these ids would be provided by the site after
         * a "complex review" of the application, but with Mastodon you can just
         * request them from the instance.
         */
        private class GetClientId : global::Publishing.RESTSupport.Transaction {
            const string ENDPOINT_URL = "https://%s/api/v1/apps";

            /**
             * Constructor.
             * 
             * @session: A Publishing.RESTSupport.Session used to communicate
             */
            public GetClientId(Session session) {
                base.with_endpoint_url(session, ENDPOINT_URL.printf(session.instance));

                add_argument("client_name", "Shotwell Connect");
                add_argument("redirect_uris", "http://localhost/shotwell-auth");
                // FIXME: Should write:media, write:statuses be enough?
                add_argument("scopes", "read write");
                add_argument("website", "https://shotwell-project.org");
            }
        }

        /**
         * Call to exchange the user code that is returned from the web-bases authentication
         * flow into the OAuth2 access token.
         */
        private class GetAccessToken : global::Publishing.RESTSupport.Transaction {
            const string ENDPOINT_URL = "https://%s/oauth/token";

            /**
             * Constructor.
             * 
             * @session: A Publishing.RESTSupport.Session used to communicate
             * @code: Result of the web authentication flow
             */
             public GetAccessToken(Session session, string code) {
                base.with_endpoint_url(session, ENDPOINT_URL.printf(session.instance));

                add_argument("client_id", session.client_id);
                add_argument("client_secret", session.client_secret);
                add_argument("redirect_uri", "http://localhost/shotwell-auth");
                add_argument("grant_type", "authorization_code");
                add_argument("code", code);
                add_argument("scope", "read write");
            }
        }

        /**
         * Transaction to revoke an access token (aka logout)
         */
        private class RevokeAccessToken : global::Publishing.RESTSupport.Transaction {
            const string ENDPOINT_URL = "https://%s/oauth/revoke";

            /**
             * Constructor.
             * 
             * @session: A Publishing.RESTSupport.Session used to communicate
             * @token: An user access token, as obtained by GetAccessToken
             */
             public RevokeAccessToken(Session session, string token) {
                base.with_endpoint_url(session, ENDPOINT_URL.printf(session.instance));

                add_argument("client_id", session.client_id);
                add_argument("client_secret", session.client_secret);
                add_argument("token", token);
            }
        }

        /**
         * Transaction to introspect information about the instance, stuff
         * like supported server version, file formats, size and rate limits
         */
         private class InstanceInfo : global::Publishing:RESTSupport.Transaction {
            const string ENDPOINT_URL = "https://%s/api/v1/instance";

            /**
             * Constructor.
             * 
             * @session: A Publishing.RESTSupport.Session used to communicate
             */
             public InstanceInfo(Session session) {
                base.with_endpoint_url(session, ENDPOINT_URL.printf(session.instance,
                                        Publishing.RESTSupport.HttpMethod.GET));
            }

            // There is no body, basically could just use a SoupMessage, but 
            // for consistency just go with this.
            public override async void execute_async() throws Spit.Publishing.PublishingError {
                set_is_executed(true);
                yield send_async();
            }
        }
    }

    /**
     * Implementation of Publishing.RESTSupport.Session. Keeping track of information
     * necessary during authentication flows.
     */
    private class Session : Publishing.RESTSupport.Session {
        public string instance = null;
        public string client_id = null;
        public string client_secret = null;
        public string access_token = null;
        public TlsCertificate? accepted_certificate = null;

        public override bool is_authenticated() {
            return client_id != null && client_secret != null && access_token != null;
        }

        public bool is_client_authenticated() {
            return client_id != null && client_id != "" && client_secret != null && client_secret != "";
        }

        public void deauthenticate() {
            access_token = null;
        }
    }

    /**
     * Ui panel to get basic instance infortmation (instance name and user)
     */
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

        public signal void login(Account account);

        public override void constructed() {
            base.constructed();
            if (account == null) {
                account = new Account(null, null);
            }

            var builder = this.get_builder();
            this.login_button = (Gtk.Button)builder.get_object("login_button");
            this.login_button.clicked.connect(() => {
                this.login(new Account(this.instance_entry.get_text(),
                 this.user_entry.get_text()));
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

        public override void on_pane_installed() {
            this.instance_entry.grab_focus();
            this.user_entry.set_activates_default(true);
            update_login_button();
        }
    }

    // Information for the secret store
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
                SCHEMA_KEY_PROFILE_ID, Secret.SchemaAttributeType.STRING,
                // url of the instance
                CLIENT_KEY_INSTANCE_ID, Secret.SchemaAttributeType.STRING,
                // TRUE: Client ID, FALSE: Client Secret - This is a bit abusive
                // of Secret
                CLIENT_KEY_SECRET_ID, Secret.SchemaAttributeType.BOOLEAN);
    }

    public static Secret.Schema get_user_schema() {
        return new Secret.Schema(USER_SCHEME_ID,
                Secret.SchemaFlags.NONE,
                // Internal id of the shotwell profile
                SCHEMA_KEY_PROFILE_ID, Secret.SchemaAttributeType.STRING,
                // Client-id as in the client_schema
                USER_KEY_CLIENT_ID, Secret.SchemaAttributeType.STRING,
                // Username as used when logging in
                USER_KEY_USERNAME_ID, Secret.SchemaAttributeType.STRING);
    }

    /**
     * UI panel for the Web authentication flow
     */
    private class WebAuthenticationPane : Common.WebAuthenticationPane {
        private string? auth_code = null;

        public signal void authorized(string auth_code);
        public signal void error();

        public WebAuthenticationPane(string auth_sequence_start_url, Session session) {
            Object (login_uri : auth_sequence_start_url, insecure : session.get_is_insecure(), accepted_certificate: session.accepted_certificate, allow_insecure: true);
        }

        public override void on_page_load() {
            if (this.load_error != null) {
                this.error ();

                return;
            }

            try {
                var uri = GLib.Uri.parse(get_view().get_uri(), UriFlags.NONE);
                if ((uri.get_scheme() == "shotwell-auth://" || uri.get_path() == "/shotwell-auth") && this.auth_code == null) {
                    var form_data = Soup.Form.decode (uri.get_query());
                    this.auth_code = form_data.lookup("code");
                }
            } catch (Error err) {
                debug ("Failed to parse auth code from URI %s: %s", get_view().get_uri(),
                    err.message);
            }

            if (this.auth_code != null) {
                this.authorized(this.auth_code);
            }
        }
    }

    public class Mastodon : Spit.Publishing.Authenticator, Object {
        private Session session = null;
        private Secret.Schema? client_schema = null;
        private Secret.Schema? user_schema = null;
        private Spit.Publishing.PluginHost host;
        private HashTable<string, Variant> params;
        private Account account;
        private WebAuthenticationPane web_auth_pane;

        public Mastodon(Spit.Publishing.PluginHost host) {
            this.host = host;
            this.session = new Session();
            this.client_schema = get_client_schema();
            this.user_schema = get_user_schema();
            this.params = new HashTable<string, Variant>(str_hash, str_equal);
        }

        public void authenticate() {
            do_authentication_flow.begin();
        }

        private async void do_authentication_flow() {
            try {
                yield get_client_secret();
                yield get_user_secret();
                
                this.params["User"] = new Variant.string(this.account.user);
                this.params["Instance"] = new Variant.string(this.account.instance);
    
                debug("Authentication flow complete. signalizing to caller");
                this.authenticated();
            } catch (Error err) {
                host.post_error(err);
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
                    USER_KEY_USERNAME_ID, this.account.user);
            } catch (Error err) {
                critical("Failed to remove password for %s: %s", this.account.display_name(), err.message);
            }

            txn.execute_async.begin((_, res) => {
                try {
                    txn.execute_async.end(res);
                    host.install_static_message_pane("Successfully logged out from %s".printf(this.account.display_name()),
                        Spit.Publishing.PluginHost.ButtonMode.CLOSE);
                }
                catch (Spit.Publishing.PublishingError err) {
                    host.post_error(err);
                }
            });
        }

        public void refresh() {
        }

        public void set_accountname(string accountname) {
            var data = accountname.split("@");
            this.account = new Account(data[2], data[1]);
            session.instance = this.account.instance;
        }

        private async void do_get_client_id(bool do_downgrade = true) throws Error {
            host.set_service_locked(true);
            host.install_login_wait_pane();

            session.instance = this.account.instance;

            var txn = new Transactions.GetClientId(this.session);

            try {
                yield txn.execute_async();
                yield on_get_client_id_completed(txn);
            } catch (Spit.Publishing.PublishingError err) {
                if (do_downgrade && err is Spit.Publishing.PublishingError.SSL_FAILED) {
                    debug("ERROR: SSL: connection problems, proposing SSL downgrade");
                    yield do_show_ssl_downgrade_pane((Transactions.GetClientId)txn, session.instance);
                    yield do_get_client_id(false);
                } else {
                    throw err;
                }
            }
        }

        private async void on_get_client_id_completed(Publishing.RESTSupport.Transaction txn) {
            debug("EVENT: get client id transaction completed successfully");
            var response = txn.get_response();
            var parser = new Json.Parser();

            try {
                parser.load_from_data(response);
            } catch (Error err) {
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "Couldn't parse JSON response: " + err.message));
                return;
            }

            var response_obj = parser.get_root().get_object();
            if (!(response_obj.has_member("client_id") && response_obj.has_member("client_secret"))) {
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "neither client_id nor client_secret present in server response"));
                return;            
            }

            session.client_id = response_obj.get_string_member("client_id");
            session.client_secret = response_obj.get_string_member("client_secret");
            this.params.insert("ClientId", new Variant.string(session.client_id));
            this.params.insert("ClientSecret", new Variant.string(session.client_secret));

            try {
                yield Secret.password_store (this.client_schema, Secret.COLLECTION_DEFAULT,
                    "Shotwell publishing client_id @%s".printf(this.account.instance),
                    session.client_id, null, 
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    CLIENT_KEY_INSTANCE_ID, this.account.instance,
                    CLIENT_KEY_SECRET_ID, false);
                yield Secret.password_store (this.client_schema, Secret.COLLECTION_DEFAULT,
                    "Shotwell publishing client_secret @%s".printf(this.account.instance),
                    session.client_secret, null, 
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    CLIENT_KEY_INSTANCE_ID, this.account.instance, CLIENT_KEY_SECRET_ID, true);
            } catch (Error err) {
                critical("Issue persisting client credentials: %s", err.message);
            }
        }

        private async void do_show_ssl_downgrade_pane (Transactions.GetClientId trans,
                                                       string host_name) {
            host.set_service_locked (false);
            var ssl_pane = new Common.SslCertificatePane(trans, host, host_name);

            ssl_pane.proceed.connect (() => {
                debug ("SSL: User wants us to retry with broken certificate");
                var old_session = this.session;
                this.session = new Session ();
                this.session.instance = old_session.instance;
                this.session.client_id = old_session.client_id;
                this.session.client_secret = old_session.client_secret;
                this.session.set_insecure ();
                this.session.accepted_certificate = ssl_pane.cert;
                do_show_ssl_downgrade_pane.callback();
            });

            debug ("Showing SSL downgrade pane");
            host.install_dialog_pane (ssl_pane,
                                    Spit.Publishing.PluginHost.ButtonMode.CLOSE);
            host.set_dialog_default_widget (ssl_pane.get_default_widget ());

            yield;
        }        


        private async void fetch_user_auth_token(string auth_code) throws Error {
            debug("ACTION: exchanging authorization code for access & refresh tokens");

            host.install_login_wait_pane();

            var tokens_txn = new Transactions.GetAccessToken(session, auth_code);

            yield tokens_txn.execute_async();
            debug("EVENT: network transaction to exchange authorization code for access tokens " +
            "completed successfully.");

            yield do_extract_tokens(tokens_txn.get_response());
        }
        
        private async void do_extract_tokens(string response_body) throws Error {
            debug("ACTION: extracting OAuth tokens from body of server response");

            Json.Parser parser = new Json.Parser();

            try {
                parser.load_from_data(response_body);
            } catch (Error err) {
                throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "Couldn't parse JSON response: " + err.message);
            }

            Json.Object response_obj = parser.get_root().get_object();

            if (!response_obj.has_member("access_token")) {
                throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "No access token available in response");
            }

            string access_token = response_obj.get_string_member("access_token");

            if (access_token == "") {
                throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "Access token is empty in response");
            }

            session.access_token = access_token;
            this.params.insert("AccessToken", new Variant.string(access_token));

            assert(session.is_authenticated());
            try {
                yield Secret.password_store(this.user_schema, Secret.COLLECTION_DEFAULT,
                    "Shotwell publishing (Mastodon account %s)".printf(this.account.display_name()),
                    session.access_token, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    USER_KEY_CLIENT_ID, session.client_id,
                    USER_KEY_USERNAME_ID, account.user);
            } catch (Error err) {
                // Ignore that, user has to log in again then next time
                critical("Failed store user credendtial for %s: %s", this.account.display_name(), err.message);
            }
        }

        private async void get_account_details() {
            var p = new InstancePane(this.account);
            host.install_dialog_pane(p);
            host.set_dialog_default_widget(p.get_default_widget());

            p.login.connect((account) => {
                this.account = account;
                session.instance = this.account.instance;
                debug("EVENT: login clicked");
                get_account_details.callback();
            });

            yield;
        }

        /**
         * Fetch client secret for this instance.
         * 
         * If we do not have any information at all - for example if the authentiator was not
         * called with a known account - it will show the instance selection account first.
         * 
         * When that is known, check for known secrets, otherwise run client secret
         * obtaining flow.
         */
        private async void get_client_secret() throws Error {
            if (this.account == null || (this.account.instance == null || this.account.user == null)) {
                debug("We don't have any account configured, ask the user for an instance");
                yield get_account_details();
            }

            debug("We have an account set: %s, checking if cached client credentials are available", account.display_name());
            try {
                this.session.client_id = yield Secret.password_lookup(this.client_schema, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    CLIENT_KEY_INSTANCE_ID, this.account.instance, CLIENT_KEY_SECRET_ID, false);
                this.session.client_secret = yield Secret.password_lookup(this.client_schema, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    CLIENT_KEY_INSTANCE_ID, this.account.instance, CLIENT_KEY_SECRET_ID, true);            
                
                debug("Got client credentials from store: %s/%s", this.session.client_id, this.session.client_secret);
                if (!this.session.is_client_authenticated()) {
                    debug("Missing one part of the client secrets, invalidating and fetching new ones");
                    this.session.client_id = null;
                    this.session.client_secret = null;
                } else {
                    // We are done here, proceed with next step
                    this.params.insert("ClientId", new Variant.string(session.client_id));
                    this.params.insert("ClientSecret", new Variant.string(session.client_secret));
                    return;
                }
            } catch (Error err) {
                debug("Error fetching client secrets from password store, requesting new secrets");
            }

            yield do_get_client_id();
        }

        private async string run_web_auth_flow() throws Error {
            debug("ACTION: running OAuth authentication flow in hosted web pane.");

            string user_authorization_url = "https://" + this.account.instance + "/oauth/authorize?" +
                "response_type=code&" +
                "client_id=" + this.session.client_id + "&" +
                "redirect_uri=" + GLib.Uri.escape_string("http://localhost/shotwell-auth", null) + "&" +
                "scope=read+write";

            web_auth_pane = new WebAuthenticationPane(user_authorization_url, session);
            string? received_auth_code = null;

            web_auth_pane.authorized.connect((auth_code) =>{
                received_auth_code = auth_code;
                run_web_auth_flow.callback();
            });

            web_auth_pane.error.connect(() => {
                run_web_auth_flow.callback();
            });

            host.install_dialog_pane(web_auth_pane);
            
            yield;

            if (web_auth_pane.load_error != null) {
                throw web_auth_pane.load_error;
            }

            return received_auth_code;
        }

        /**
         * Get the user secret
         * 
         * Check if there is a cached secret. If not, start web-based authentication flow. 
         */
        private async void get_user_secret() throws Error {
            try {
                this.session.access_token = yield Secret.password_lookup(this.user_schema, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    USER_KEY_CLIENT_ID, session.client_id,
                    USER_KEY_USERNAME_ID, account.user);
                if (this.session.is_authenticated()) {
                    this.params.insert("AccessToken", new Variant.string(this.session.access_token));
                    debug("Found cached user credentials for %s: %s", this.account.display_name(), this.session.access_token);

                    return;
                }
                debug("Did not find cached credentials for %s, proceeding with login flow", this.account.display_name());
            } catch (Error err) {
                debug("Failed fetching user credendial for %s: %s, proceeding with login flow", this.account.display_name(), err.message);
            }

            var auth_code = yield run_web_auth_flow();

            web_auth_pane.clear();
            host.set_service_locked(true);

            debug("EVENT: user authorized scope %s with auth_code %s", this.account.display_name(), auth_code);
            host.install_static_message_pane(_("Getting user access token..."));

            yield fetch_user_auth_token(auth_code);
        }
    }
}
