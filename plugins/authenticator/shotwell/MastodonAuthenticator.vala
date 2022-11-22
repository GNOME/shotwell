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
                add_argument("redirect_uris", "http://localhost/shotwell-auth");
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
                add_argument("redirect_uri", "http://localhost/shotwell-auth");
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

    internal class SSLErrorPane : Common.BuilderPane {

        public signal void proceed ();
        public string host { owned get; construct; }
        public TlsCertificate? cert { get; construct; }
        public string error_text { owned get; construct; }
    
        public SSLErrorPane (Transactions.GetClientId transaction,
                             string host) {
            TlsCertificate cert;
            var text = transaction.detailed_error_from_tls_flags (out cert);
            Object (resource_path : Resources.RESOURCE_PATH +
                                    "/piwigo_ssl_failure_pane.ui",
                    default_id: "default",
                    cert : cert,
                    error_text : text,
                    host : host);
        }
    
        public override void constructed () {
            base.constructed ();
    
            var label = this.get_builder ().get_object ("main_text") as Gtk.Label;
            var bold_host = "<b>%s</b>".printf(host);
            // %s is the host name that we tried to connect to
            label.set_text (_("This does not look like the real %s. Attackers might be trying to steal or alter information going to or from this site (for example, private messages, credit card information, or passwords).").printf(bold_host));
            label.use_markup = true;
    
            label = this.get_builder ().get_object ("ssl_errors") as Gtk.Label;
            label.set_text (error_text);
    
            var info = this.get_builder ().get_object ("default") as Gtk.Button;
            if (cert != null) {
                info.clicked.connect (() => {
                    var simple_cert = new Gcr.SimpleCertificate (cert.certificate.data);
                    var widget = new Gcr.CertificateWidget (simple_cert);
                    bool use_header = true;
                    Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header);
                    var flags = (Gtk.DialogFlags) 0;
                    if (use_header) {
                        flags |= Gtk.DialogFlags.USE_HEADER_BAR;
                    }
    
                    var dialog = new Gtk.Dialog.with_buttons (
                                    _("Certificate of %s").printf (host),
                                    null,
                                    flags,
                                    _("_OK"), Gtk.ResponseType.OK);
                    dialog.get_content_area ().add (widget);
                    dialog.set_default_response (Gtk.ResponseType.OK);
                    dialog.set_default_size (640, -1);
                    dialog.show_all ();
                    dialog.run ();
                    dialog.destroy ();
                });
            } else {
                info.get_parent().remove(info);
            }
    
            var proceed = this.get_builder ().get_object ("proceed_button") as Gtk.Button;
            proceed.clicked.connect (() => { this.proceed (); });
        }
    }
    private class Session : Publishing.RESTSupport.Session {
        public string instance = null;
        public string client_id = null;
        public string client_secret = null;
        public string access_token = null;
        public TlsCertificate? accepted_certificate = null;

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
            login_button.can_default = true;
            update_login_button();
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


    private class WebAuthenticationPane : Common.WebAuthenticationPane {
        public static bool cache_dirty = false;
        private string? auth_code = null;

        public signal void error();

        public override void constructed() {
            base.constructed();

            var ctx = WebKit.WebContext.get_default();
        }

        public override void on_page_load() {
            if (this.load_error != null) {
                this.error ();

                return;
            }

            print("========================================= PAGE LOAD %s\n", get_view().get_uri());

            try {
                var uri = GLib.Uri.parse(get_view().get_uri(), UriFlags.NONE);
                print("--------------------------------- %s\n", uri.get_path());
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

        private void on_shotwell_auth_request_cb(WebKit.URISchemeRequest request) {
            try {
                var uri = GLib.Uri.parse(request.get_uri(), GLib.UriFlags.NONE);
                debug("URI: %s", request.get_uri());
                var form_data = Soup.Form.decode (uri.get_query());
                this.auth_code = form_data.lookup("code");
            } catch (Error err) {
                debug("Failed to parse request URI: %s", err.message);
            }

            var response = "";
            var mins = new MemoryInputStream.from_data(response.data, null);
            request.finish(mins, -1, "text/plain");
        }

        public signal void authorized(string auth_code);

        public WebAuthenticationPane(string auth_sequence_start_url, Session session) {
            Object (login_uri : auth_sequence_start_url, insecure : session.get_is_insecure(), accepted_certificate: session.accepted_certificate);
        }

        public static bool is_cache_dirty() {
            return cache_dirty;
        }
    }

    public class Mastodon : Spit.Publishing.Authenticator, Object {
        private Session session = null;
        private Secret.Schema? client_schema = null;
        private Secret.Schema? user_schema = null;
        private string? instance = null;
        private string? user = null;
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

        private void do_show_instance_pane() {
            var p = new InstancePane(null);
            host.install_dialog_pane(p);
            host.set_dialog_default_widget(p.get_default_widget());
            p.login.connect((account) => {
                this.account = account;
                session.instance = this.account.instance;
                debug("EVENT: login clicked");
                do_get_client_id.begin();
            });
        }

        private async void do_get_client_id() {
            host.set_service_locked(true);
            host.install_login_wait_pane();

            session.instance = this.account.instance;

            var txn = new Transactions.GetClientId(this.session);

            try {
                yield txn.execute_async();
                on_get_client_id_completed(txn);
            } catch (Spit.Publishing.PublishingError err) {
                if (err is Spit.Publishing.PublishingError.SSL_FAILED) {
                    debug("ERROR: SSL: connection problems, proposing SSL downgrade");
                    do_show_ssl_downgrade_pane((Transactions.GetClientId)txn, session.instance);
                } else {
                    host.post_error(err);            
                }
            }
        }

        private void on_get_client_id_completed(Publishing.RESTSupport.Transaction txn) {
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
                Secret.password_store_sync(this.client_schema, Secret.COLLECTION_DEFAULT, "Shotwell publishing client_id @%s".printf(this.account.instance),
                session.client_id, null, SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                CLIENT_KEY_INSTANCE_ID, this.account.instance, CLIENT_KEY_SECRET_ID, false);
                Secret.password_store_sync(this.client_schema, Secret.COLLECTION_DEFAULT, "Shotwell publishing client_secret @%s".printf(this.account.instance),
                session.client_secret, null, SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                CLIENT_KEY_INSTANCE_ID, this.account.instance, CLIENT_KEY_SECRET_ID, true);
            } catch (Error err) {
                critical("Issue persisting client credentials: %s", err.message);
            }

            do_show_web_login();
        }

        private void do_show_ssl_downgrade_pane (Transactions.GetClientId trans,
                                                string host_name) {
            host.set_service_locked (false);
            var ssl_pane = new SSLErrorPane (trans, host_name);
            ssl_pane.proceed.connect (() => {
                debug ("SSL: User wants us to retry with broken certificate");
                var old_session = this.session;
                this.session = new Session ();
                this.session.instance = old_session.instance;
                this.session.client_id = old_session.client_id;
                this.session.client_secret = old_session.client_secret;
                this.session.set_insecure ();
                this.session.accepted_certificate = ssl_pane.cert;

                do_get_client_id.begin();
            });
            debug ("Showing SSL downgrade pane");
            host.install_dialog_pane (ssl_pane,
                                    Spit.Publishing.PluginHost.ButtonMode.CLOSE);
            host.set_dialog_default_widget (ssl_pane.get_default_widget ());
        }        

        private void do_show_web_login() {
            debug("ACTION: running OAuth authentication flow in hosted web pane.");

            string user_authorization_url = "https://" + this.account.instance + "/oauth/authorize?" +
                "response_type=code&" +
                "client_id=" + this.session.client_id + "&" +
                "redirect_uri=" + GLib.Uri.escape_string("http://localhost/shotwell-auth", null) + "&" +
                "scope=read+write";

            web_auth_pane = new WebAuthenticationPane(user_authorization_url, session);
            web_auth_pane.authorized.connect(on_web_auth_pane_authorized);
            web_auth_pane.error.connect(on_web_auth_pane_error);

            host.install_dialog_pane(web_auth_pane);
        }

        private void on_web_auth_pane_authorized(string auth_code) {
            web_auth_pane.authorized.disconnect(on_web_auth_pane_authorized);
            web_auth_pane.error.disconnect(on_web_auth_pane_error);

            host.set_service_locked(true);
            host.install_static_message_pane(_("Getting user access token..."));

            debug("EVENT: user authorized scope %s with auth_code %s", this.account.display_name(), auth_code);

            do_get_access_tokens.begin(auth_code);
        }

        private void on_web_auth_pane_error() {
            host.post_error(web_auth_pane.load_error);
        }

        private async void do_get_access_tokens(string auth_code) {
            debug("ACTION: exchanging authorization code for access & refresh tokens");

            host.install_login_wait_pane();

            var tokens_txn = new Transactions.GetAccessToken(session, auth_code);

            try {
                yield tokens_txn.execute_async();
                on_get_access_tokens_complete(tokens_txn);
            } catch (Spit.Publishing.PublishingError err) {
                debug("EVENT: network transaction to exchange authorization code for access tokens " +
                    "failed; response = '%s'", tokens_txn.get_response());
                host.post_error(err);
            }
        }

        private void on_get_access_tokens_complete(Publishing.RESTSupport.Transaction txn) {
            debug("EVENT: network transaction to exchange authorization code for access tokens " +
                    "completed successfully.");

            do_extract_tokens(txn.get_response());
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
                    "neither access_token nor refresh_token present in server response"));
                return;
            }

            if (response_obj.has_member("access_token")) {
                string access_token = response_obj.get_string_member("access_token");

                if (access_token == "") {
                    return;
                }
                session.access_token = access_token;
                this.params.insert("AccessToken", new Variant.string(access_token));
            } else {
                return;
            }

            assert(session.is_authenticated());
            try {
                Secret.password_store_sync(this.user_schema, Secret.COLLECTION_DEFAULT,
                    "Shotwell publishing (Mastodon account %s)".printf(this.account.display_name()),
                    session.access_token, null,
                    SCHEMA_KEY_PROFILE_ID, host.get_current_profile_id(),
                    USER_KEY_CLIENT_ID, session.client_id,
                    USER_KEY_USERNAME_ID, account.user);
            } catch (Error err) {
                critical("Failed store user credendial for %s: %s", this.account.display_name(), err.message);
            }

            this.authenticated();
            web_auth_pane.clear();            
        }
    }
}
