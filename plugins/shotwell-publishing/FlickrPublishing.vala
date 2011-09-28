/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FlickrService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "flickr.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;
    
    public FlickrService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_icon_set(resource_directory.get_child(ICON_FILENAME));
    }

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.flickr";
    }
    
    public unowned string get_pluggable_name() {
        return "Flickr";
    }
    
    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Lucas Beeler";
        info.copyright = _("Copyright 2009-2011 Yorba Foundation");
        info.translators = Resources.TRANSLATORS;
        info.version = _VERSION;
        info.website_name = Resources.WEBSITE_NAME;
        info.website_url = Resources.WEBSITE_URL;
        info.is_license_wordwrapped = false;
        info.license = Resources.LICENSE;
        info.icons = icon_pixbuf_set;
    }

    public void activation(bool enabled) {
    }

    public Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host) {
        return new Publishing.Flickr.FlickrPublisher(this, host);
    }
    
    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO |
            Spit.Publishing.Publisher.MediaType.VIDEO);
    }
}

namespace Publishing.Flickr {

internal const string SERVICE_NAME = "Flickr";
internal const string SERVICE_WELCOME_MESSAGE = 
    _("You are not currently logged into Flickr.\n\nYou must have already signed up for a Flickr account to complete the login process. During login you will have to specifically authorize Shotwell Connect to link to your Flickr account.");
internal const string RESTART_ERROR_MESSAGE = 
    _("You have already logged in and out of Flickr during this Shotwell session.\nTo continue publishing to Flickr, quit and restart Shotwell, then try publishing again.");
internal const string ENDPOINT_URL = "http://api.flickr.com/services/rest";
internal const string API_KEY = "60dd96d4a2ad04888b09c9e18d82c26f";
internal const string API_SECRET = "d0960565e03547c1";
internal const int ORIGINAL_SIZE = -1;
internal const string EXPIRED_SESSION_ERROR_CODE = "98";

internal enum UserKind {
    PRO,
    FREE,
}

internal struct VisibilitySpecification {
    public int friends_level;
    public int family_level;
    public int everyone_level;

    VisibilitySpecification(int friends_level, int family_level, int everyone_level) {
        this.friends_level = friends_level;
        this.family_level = family_level;
        this.everyone_level = everyone_level;
    }
}

// not a struct because we want reference semantics
internal class PublishingParameters {
    public UserKind user_kind;
    public int quota_free_mb;
    public int photo_major_axis_size;
    public string username;
    public VisibilitySpecification visibility_specification;

    public PublishingParameters() {
    }
}

public class FlickrPublisher : Spit.Publishing.Publisher, GLib.Object {
    private Spit.Publishing.Service service;
    private Spit.Publishing.PluginHost host;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private bool running = false;
    private bool was_started = false;
    private Session session;
    private string? frob = null;
    private WebAuthenticationPane web_auth_pane = null;
    private PublishingParameters parameters = null;

    public FlickrPublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        debug("FlickrPublisher instantiated.");
        this.service = service;
        this.host = host;
        this.session = new Session();
        this.parameters = new PublishingParameters();
    }
    
    private void invalidate_persistent_session() {
        host.unset_config_key("auth_token");
        host.unset_config_key("username");
    }
    
    private bool is_persistent_session_valid() {
        return (get_persistent_username() != null && get_persistent_auth_token() != null);
    }
    
    private string? get_persistent_username() {
        return host.get_config_string("username", null);
    }
    
    private void set_persistent_username(string username) {
        host.set_config_string("username", username);
    }
    
    private string? get_persistent_auth_token() {
        return host.get_config_string("auth_token", null);
    }

    private void set_persistent_auth_token(string auth_token) {
        host.set_config_string("auth_token", auth_token);
    }

    private void on_welcome_pane_login_clicked() {
        if (!running)
            return;

        debug("EVENT: user clicked 'Login' button in the welcome pane");
        
        do_obtain_frob();
    }

    private void on_frob_fetch_txn_completed(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_frob_fetch_txn_completed);
        txn.network_error.disconnect(on_frob_fetch_txn_error);

        if (!is_running())
            return;

        debug("EVENT: finished network transaction to get Yahoo! login frob. ");
        do_extract_frob_from_xml(txn.get_response());
    }

    private void on_frob_fetch_txn_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_frob_fetch_txn_completed);
        txn.network_error.disconnect(on_frob_fetch_txn_error);

        if (!is_running())
            return;

        debug("EVENT: network transaction to obtain Yahoo! login frob failed; response = '%s'",
            txn.get_response());

        host.post_error(err);
    }

    private void on_login_url_available(string login_url) {
        if (!is_running())
            return;

        debug("EVENT: hosted web login url = '%s' has become available", login_url);
        do_start_hosted_web_authentication(login_url);
    }

    private void on_frob_available(string frob) {
        if (!is_running())
            return;

        debug("EVENT: Yahoo! login frob = '%s' has become available", frob);
        do_build_login_url_from_frob(frob);
    }

    private void on_web_auth_pane_token_check_required() {
        if (!is_running())
            return;

        debug("EVENT: web pane has loaded a page, need to check if auth token has become valid");
        do_token_check();
    }

    private void on_token_check_txn_completed(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_token_check_txn_completed);
        txn.network_error.disconnect(on_token_check_txn_error);

        if (!is_running())
            return;

        debug("EVENT: token check transaction response received over the network");
        do_interpret_token_check_xml(txn.get_response());
    }

    // token check "error" vs "failure" -- "error" means that the actual network transaction
    // errored out, indicating a network transport issue such as bad DNS lookup, 404 error, etc.,
    // whereas "failure" means that the network transaction succeeded in making a round trip
    // to the server but the response didn't contain an authentication token

    private void on_token_check_txn_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_token_check_txn_completed);
        txn.network_error.disconnect(on_token_check_txn_error);

        if (!is_running())
            return;

        debug("EVENT: token check transaction caused a network error");

        host.post_error(err);
    }

    private void on_token_check_failed() {
        if (!is_running())
            return;

        debug("EVENT: checked response XML for token but one isn't available yet");
        do_continue_hosted_web_authentication();
    }

    private void on_token_check_succeeded(string token, string username) {
        if (!is_running())
            return;

        debug("EVENT: auth token = '%s' for username = '%s' has become available.", token, username);
        do_authenticate_session(token, username);
    }
    
    private void on_authenticated_session_ready() {
        if (!is_running())
            return;

        debug("EVENT: an authenticated session has become available");
        parameters.username = session.get_username();
        do_fetch_account_info();
    }

    private void on_account_fetch_txn_completed(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_account_fetch_txn_completed);
        txn.network_error.disconnect(on_account_fetch_txn_error);

        if (!is_running())
            return;

        debug("EVENT: account fetch transaction response received over the network");
        do_parse_account_info_from_xml(txn.get_response());
    }

    private void on_account_fetch_txn_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_account_fetch_txn_completed);
        txn.network_error.disconnect(on_account_fetch_txn_error);

        if (!is_running())
            return;

        debug("EVENT: account fetch transaction caused a network error");
        host.post_error(err);
    }

    private void on_account_info_available() {
        if (!is_running())
            return;

        debug("EVENT: account information has become available");
        do_show_publishing_options_pane();
    }

    private void on_publishing_options_pane_publish() {
        if (!is_running())
            return;

        debug("EVENT: user clicked the 'Publish' button in the publishing options pane");
        do_publish();
    }

    private void on_publishing_options_pane_logout() {
        if (!is_running())
            return;

        debug("EVENT: user clicked the 'Logout' button in the publishing options pane");

        do_logout();
    }

    private void on_upload_status_updated(int file_number, double completed_fraction) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);

        progress_reporter(file_number, completed_fraction);
    }

    private void on_upload_complete(Publishing.RESTSupport.BatchUploader uploader,
        int num_published) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload complete; %d items published.", num_published);

        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        do_show_success_pane();
    }

    private void on_upload_error(Publishing.RESTSupport.BatchUploader uploader,
        Spit.Publishing.PublishingError err) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload error = '%s'.", err.message);

        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        host.post_error(err);
    }

    private void do_show_login_welcome_pane() {
        debug("ACTION: installing login welcome pane");

        host.set_service_locked(false);
        host.install_welcome_pane(SERVICE_WELCOME_MESSAGE, on_welcome_pane_login_clicked);
    }

    private void do_obtain_frob() {
        debug("ACTION: running network transaction to obtain Yahoo! login frob");

        host.set_service_locked(true);
        host.install_static_message_pane(_("Preparing to login..."));

        FrobFetchTransaction frob_fetch_txn = new FrobFetchTransaction(session);
        frob_fetch_txn.completed.connect(on_frob_fetch_txn_completed);
        frob_fetch_txn.network_error.connect(on_frob_fetch_txn_error);

        try {
            frob_fetch_txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }

    private void do_extract_frob_from_xml(string xml) {
        debug("ACTION: extracting Yahoo! login frob from response xml = '%s'", xml);
        string frob = null;
        try {
            Publishing.RESTSupport.XmlDocument response_doc = Transaction.parse_flickr_response(xml);

            Xml.Node* root = response_doc.get_root_node();

            Xml.Node* frob_node = response_doc.get_named_child(root, "frob");
            
            string local_frob = frob_node->get_content();

            if (local_frob == null)
                throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("No frob returned " +
                    "in request");
            
            frob = local_frob;
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
            return;
        }
        
        assert(frob != null);
        this.frob = frob;
        on_frob_available(frob);
    }

    private void do_build_login_url_from_frob(string frob) {
        debug("ACTION: building hosted web login url from frob");

        string hash_string = session.get_api_secret() + "api_key%s".printf(session.get_api_key()) +
            "frob%s".printf(frob) + "permswrite";
        string sig = Checksum.compute_for_string(ChecksumType.MD5, hash_string);
        string login_url =
            "http://flickr.com/services/auth/?api_key=%s&perms=%s&frob=%s&api_sig=%s".printf(
            session.get_api_key(), "write", frob, sig);

        on_login_url_available(login_url);
    }

    private void do_start_hosted_web_authentication(string login_url) {
        debug("ACTION: running hosted web login");
        
        host.set_service_locked(false);
       
        web_auth_pane = new WebAuthenticationPane(login_url);
        web_auth_pane.token_check_required.connect(on_web_auth_pane_token_check_required);
        host.install_dialog_pane(web_auth_pane);
    }

    private void do_token_check() {
        // if the session is already authenticated, then we have a valid token, so do nothing
        if (session.is_authenticated())
            return;

        debug("ACTION: running network transaction to check if auth token has become available");
        
        TokenCheckTransaction token_check_txn = new TokenCheckTransaction(session, frob);
        token_check_txn.completed.connect(on_token_check_txn_completed);
        token_check_txn.network_error.connect(on_token_check_txn_error);
        
        try {
            token_check_txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }

    private void do_interpret_token_check_xml(string xml) {
        // if the session is already authenticated, then we have a valid token, so do nothing
        if (session.is_authenticated())
            return;

        debug("ACTION: checking response XML to see if it contains an auth token; xml = '%s'", xml);

        Publishing.RESTSupport.XmlDocument response_doc = null;
        try {
            response_doc = Transaction.parse_flickr_response(xml);
        } catch (Spit.Publishing.PublishingError err) {
            // if we get a service error during token check, it is recoverable -- it just means
            // that no authentication token is available yet -- so just spawn an event for it
            // and return
            if (err is Spit.Publishing.PublishingError.SERVICE_ERROR) {
                on_token_check_failed();
                return;
            }
            
            host.post_error(err);
            return;
        }

        string token = null;
        string username = null;

        try {
            Xml.Node* response_doc_root = response_doc.get_root_node();

            // search through the top-level child nodes looking for a node named '<auth>':
            // all authentication information is packaged within this node
            Xml.Node* auth_node = response_doc.get_named_child(response_doc_root, "auth");

            // search through the children of the '<auth>' node looking for the '<token>' and '<user>'
            // nodes
            Xml.Node* token_node = response_doc.get_named_child(auth_node, "token");
            Xml.Node* user_node = response_doc.get_named_child(auth_node, "user");

            token = token_node->children->content;
            username = response_doc.get_property_value(user_node, "username");
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
            return;
        }
        
        assert((token != null) && (username != null));
        web_auth_pane.interaction_completed();
        on_token_check_succeeded(token, username);
    }

    private void do_continue_hosted_web_authentication() {
        debug("ACTION: continuing hosted web authentication");
        assert(web_auth_pane != null);
        web_auth_pane.show_page();
    }
    
    private void do_authenticate_session(string token, string username) {
        debug("ACTION: authenicating session");

        session.authenticate(token, username);
        assert(session.is_authenticated());
        set_persistent_auth_token(token);
        set_persistent_username(username);

        on_authenticated_session_ready();
    }

    private void do_fetch_account_info() {
        debug("ACTION: running network transaction to fetch account information");

        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();

        AccountInfoFetchTransaction txn = new AccountInfoFetchTransaction(session);
        txn.completed.connect(on_account_fetch_txn_completed);
        txn.network_error.connect(on_account_fetch_txn_error);

        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }

    private void do_parse_account_info_from_xml(string xml) {
        debug("ACTION: parsing account information from xml = '%s'", xml);
        try {
            Publishing.RESTSupport.XmlDocument response_doc = Transaction.parse_flickr_response(xml);
            Xml.Node* root_node = response_doc.get_root_node();

            Xml.Node* user_node = response_doc.get_named_child(root_node, "user");

            string is_pro_str = response_doc.get_property_value(user_node, "ispro");

            Xml.Node* bandwidth_node = response_doc.get_named_child(user_node, "bandwidth");

            string remaining_kb_str = response_doc.get_property_value(bandwidth_node, "remainingkb");

            UserKind user_kind;
            if (is_pro_str == "0")
                user_kind = UserKind.FREE;
            else if (is_pro_str == "1")
                user_kind = UserKind.PRO;
            else
                throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "Unable to determine if user has free or pro account");
            
            int quota_mb_left = int.parse(remaining_kb_str) / 1024;

            parameters.quota_free_mb = quota_mb_left;
            parameters.user_kind = user_kind;

        } catch (Spit.Publishing.PublishingError err) {
            // expired session errors are recoverable, so handle it and then short-circuit return.
            // don't call post_error( ) on the plug-in host because that's intended for
            // unrecoverable errors and will halt publishing
            if (err is Spit.Publishing.PublishingError.EXPIRED_SESSION) {
                do_logout();
                return;
            }

            host.post_error(err);
            return;
        }
        on_account_info_available();
    }
    
    private void do_logout() {
        session.deauthenticate();
        invalidate_persistent_session();

        running = false;

        attempt_start();
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: displaying publishing options pane");
        host.set_service_locked(false);

        PublishingOptionsPane publishing_options_pane = new PublishingOptionsPane(this, parameters,
            host.get_publishable_media_type());
        publishing_options_pane.publish.connect(on_publishing_options_pane_publish);
        publishing_options_pane.logout.connect(on_publishing_options_pane_logout);
        host.install_dialog_pane(publishing_options_pane);
    }
    
    public static int flickr_date_time_compare_func(Spit.Publishing.Publishable a, 
        Spit.Publishing.Publishable b) {
        return a.get_exposure_date_time().compare(b.get_exposure_date_time());
    }

    private void do_publish() {
        debug("ACTION: uploading media items to remote server.");

        host.set_service_locked(true);
        progress_reporter = host.serialize_publishables(parameters.photo_major_axis_size);

        // Serialization is a long and potentially cancellable operation, so before we use
        // the publishables, make sure that the publishing interaction is still running. If it
        // isn't the publishing environment may be partially torn down so do a short-circuit
        // return
        if (!is_running())
            return;

        // Sort publishables in reverse-chronological order.
        Spit.Publishing.Publishable[] publishables = host.get_publishables();
        Gee.ArrayList<Spit.Publishing.Publishable> sorted_list =
            new Gee.ArrayList<Spit.Publishing.Publishable>();
        foreach (Spit.Publishing.Publishable p in publishables) {
            sorted_list.add(p);
        }
        sorted_list.sort((CompareFunc) flickr_date_time_compare_func);
        
        Uploader uploader = new Uploader(session, sorted_list.to_array(), parameters);
        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);
        uploader.upload(on_upload_status_updated);
    }

    private void do_show_success_pane() {
        debug("ACTION: showing success pane.");

        host.set_service_locked(false);
        host.install_success_pane();
    }

    internal int get_persistent_visibility() {
        return host.get_config_int("visibility", 0);
    }
    
    internal void set_persistent_visibility(int vis) {
        host.set_config_int("visibility", vis);
    }
    
    internal int get_persistent_default_size() {
        return host.get_config_int("default_size", 1);
    }
    
    internal void set_persistent_default_size(int size) {
        host.set_config_int("default_size", size);
    }

    public Spit.Publishing.Service get_service() {
        return service;
    }

    public bool is_running() {
        return running;
    }
    
    // this helper doesn't check state, merely validates and authenticates the session and installs
    // the proper panes
    private void attempt_start() {
        running = true;
        was_started = true;
        
        if (is_persistent_session_valid()) {
            session.authenticate(get_persistent_auth_token(), get_persistent_username());
            on_authenticated_session_ready();
        } else if (WebAuthenticationPane.is_cache_dirty()) {
            host.set_service_locked(false);
            host.install_static_message_pane(RESTART_ERROR_MESSAGE,
                Spit.Publishing.PluginHost.ButtonMode.CLOSE);
        } else {
            do_show_login_welcome_pane();
        }
    }
    
    public void start() {
        if (is_running())
            return;
        
        if (was_started)
            error("FlickrPublisher: start( ): can't start; this publisher is not restartable.");
        
        debug("FlickrPublisher: starting interaction.");
        
        attempt_start();
    }
    
    public void stop() {
        debug("FlickrPublisher: stop( ) invoked.");

        if (session != null)
            session.stop_transactions();

        running = false;
    }
}

internal class Transaction : Publishing.RESTSupport.Transaction {
    public const string SIGNATURE_KEY = "api_sig";

    public Transaction(Session session) {
        base(session);

        add_argument("api_key", ((Session) get_parent_session()).get_api_key());
    }
    
    private void sign() {
        string sig = generate_signature(get_sorted_arguments(),
            ((Session) get_parent_session()).get_api_secret());

        add_argument(SIGNATURE_KEY, sig);
    }

    public static string generate_signature(Publishing.RESTSupport.Argument[] sorted_args,
        string api_secret) {
        string hash_string = "";
        foreach (Publishing.RESTSupport.Argument arg in sorted_args)
            hash_string = hash_string + ("%s%s".printf(arg.key, arg.value));

        return Checksum.compute_for_string(ChecksumType.MD5, api_secret + hash_string);
    }

    public override void execute() throws Spit.Publishing.PublishingError {
        sign();
        base.execute();
    }

    public static string? validate_xml(Publishing.RESTSupport.XmlDocument doc) {
        Xml.Node* root = doc.get_root_node();
        string? status = root->get_prop("stat");
        
        // treat malformed root as an error condition
        if (status == null)
            return "No status property in root node";
        
        if (status == "ok")
            return null;
        
        Xml.Node* errcode;
        try {
            errcode = doc.get_named_child(root, "err");
        } catch (Spit.Publishing.PublishingError err) {
            return "No error code specified";
        }
        
        // this error format is mandatory, because the parse_flickr_response( ) expects error
        // messages to be in this format. If you want to change the error reporting format, you
        // need to modify parse_flickr_response( ) to parse the new format too.
        return "%s (error code %s)".printf(errcode->get_prop("msg"), errcode->get_prop("code"));
    }

    // Flickr responses have a special flavor of expired session reporting. Expired sessions
    // are reported as just another service error, so they have to be converted from
    // service errors. Always use this wrapper function to parse Flickr response XML instead
    // of the generic Publishing.RESTSupport.XmlDocument.parse_string( ) from the Yorba
    // REST support classes. While using Publishing.RESTSupport.XmlDocument.parse_string( ) won't
    // cause anything really bad to happen, it will make expired session errors unrecoverable,
    // which is annoying for users.
    public static Publishing.RESTSupport.XmlDocument parse_flickr_response(string xml)
        throws Spit.Publishing.PublishingError {
        Publishing.RESTSupport.XmlDocument? result = null;

        try {
            result = Publishing.RESTSupport.XmlDocument.parse_string(xml, validate_xml);
        } catch (Spit.Publishing.PublishingError e) {
            if (e.message.contains("(error code %s)".printf(EXPIRED_SESSION_ERROR_CODE))) {
                throw new Spit.Publishing.PublishingError.EXPIRED_SESSION(e.message);
            } else {
                throw e;
            }
        }
        
        return result;
    }
}

internal class FrobFetchTransaction : Transaction {
    public FrobFetchTransaction(Session session) {
        base(session);

        add_argument("method", "flickr.auth.getFrob");
    }
}

internal class TokenCheckTransaction : Transaction {
    public TokenCheckTransaction(Session session, string frob) {
        base(session);

        add_argument("method", "flickr.auth.getToken");
        add_argument("frob", frob);
    }
}

internal class AccountInfoFetchTransaction : Transaction {
    public AccountInfoFetchTransaction(Session session) {
        base(session);

        add_argument("method", "flickr.people.getUploadStatus");
        add_argument("auth_token", session.get_auth_token());
    }
}

private class UploadTransaction : Publishing.RESTSupport.UploadTransaction {
    private PublishingParameters parameters;

    public UploadTransaction(Session session, PublishingParameters parameters,
        Spit.Publishing.Publishable publishable) {
        base.with_endpoint_url(session, publishable, "http://api.flickr.com/services/upload");

        this.parameters = parameters;

        add_argument("api_key", session.get_api_key());
        add_argument("auth_token", session.get_auth_token());
        add_argument("is_public", ("%d".printf(parameters.visibility_specification.everyone_level)));
        add_argument("is_friend", ("%d".printf(parameters.visibility_specification.friends_level)));
        add_argument("is_family", ("%d".printf(parameters.visibility_specification.family_level)));

        GLib.HashTable<string, string> disposition_table =
            new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
        string? filename = publishable.get_publishing_name();
        if (filename == null || filename == "")
            filename = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        disposition_table.insert("filename",  Soup.URI.encode(filename, "'"));
        disposition_table.insert("name", "photo");

        set_binary_disposition_table(disposition_table);
    }
    
    public override void execute() throws Spit.Publishing.PublishingError {
        string sig = Transaction.generate_signature(get_sorted_arguments(),
            ((Session) get_parent_session()).get_api_secret());

        add_argument(Transaction.SIGNATURE_KEY, sig);
        
        base.execute();
    }
}

internal class Session : Publishing.RESTSupport.Session {
    private string api_key;
    private string api_secret;
    private string? auth_token = null;
    private string? username = null;

    public Session() {
        base(ENDPOINT_URL);
        
        this.api_key = API_KEY;
        this.api_secret = API_SECRET;
    }

    public override bool is_authenticated() {
        return (auth_token != null && username != null);
    }

    public void authenticate(string auth_token, string username) {
        this.auth_token = auth_token;
        this.username = username;
    }

    public void deauthenticate() {
        username = null;
        auth_token = null;
    }

    public string get_api_key() {
        return api_key;
    }
    
    public string get_api_secret() {
        return api_secret;
    }

    public string get_auth_token() {
        assert(is_authenticated());
        return auth_token;
    }

    public string get_username() {
        assert(is_authenticated());
        return username;
    }
}

internal class WebAuthenticationPane : Spit.Publishing.DialogPane, Object {
    private const string END_STAGE_URL = "http://www.flickr.com/services/auth/";

    private static bool cache_dirty = false;

    private WebKit.WebView webview = null;
    private Gtk.ScrolledWindow webview_frame = null;
    private Gtk.Container white_pane = null;
    private string login_url;
    private Gtk.VBox pane_widget = null;

    public signal void token_check_required();

    public WebAuthenticationPane(string login_url) {
        this.pane_widget = new Gtk.VBox(false, 0);
        this.login_url = login_url;

        Gdk.Color white_color;
        Gdk.Color.parse("white", out white_color);
        white_pane = new Gtk.EventBox();
        white_pane.modify_bg(Gtk.StateType.NORMAL, white_color);
        white_pane.modify_base(Gtk.StateType.NORMAL, white_color);        
        pane_widget.add(white_pane);

        webview_frame = new Gtk.ScrolledWindow(null, null);
        webview_frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN);
        webview_frame.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        webview = new WebKit.WebView();
        webview.get_settings().enable_plugins = false;
        webview.get_settings().enable_default_context_menu = false;

        webview.load_finished.connect(on_load_finished);
        webview.load_started.connect(on_load_started);

        webview_frame.add(webview);
        white_pane.add(webview_frame);
        white_pane.set_size_request(820, 578);
        webview.set_size_request(840, 578);
    }
    
   
    private void on_load_finished(WebKit.WebFrame origin_frame) {
        if (origin_frame.uri == END_STAGE_URL) {
            token_check_required();
        } else {
            show_page();
        }
    }
    
    private void on_load_started(WebKit.WebFrame origin_frame) {
        webview.hide();
        pane_widget.get_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
    }

    public static bool is_cache_dirty() {
        return cache_dirty;
    }

    public void show_page() {
        webview.show();
        pane_widget.get_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
    }

    public void interaction_completed() {
        cache_dirty = true;
        pane_widget.get_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
    }
    
    public Gtk.Widget get_widget() {
        return pane_widget;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.EXTENDED_SIZE;
    }
    
    public void on_pane_installed() {
        webview.open(login_url);
    }
    
    public void on_pane_uninstalled() {
    }
}

internal class LegacyPublishingOptionsPane : Gtk.VBox {
    private struct SizeEntry {
        string title;
        int size;

        SizeEntry(string creator_title, int creator_size) {
            title = creator_title;
            size = creator_size;
        }
    }

    private struct VisibilityEntry {
        VisibilitySpecification specification;
        string title;

        VisibilityEntry(string creator_title, VisibilitySpecification creator_specification) {
            specification = creator_specification;
            title = creator_title;
        }
    }

    private const int ACTION_BUTTON_WIDTH = 128;

    private Gtk.Button logout_button = null;
    private Gtk.Button publish_button = null;
    private Gtk.ComboBox visibility_combo = null;
    private Gtk.ComboBox size_combo = null;
    private VisibilityEntry[] visibilities = null;
    private SizeEntry[] sizes = null;
    private PublishingParameters parameters = null;
    private FlickrPublisher publisher = null;

    public signal void publish();
    public signal void logout();

    public LegacyPublishingOptionsPane(FlickrPublisher publisher, PublishingParameters parameters,
        Spit.Publishing.Publisher.MediaType media_type) {
        this.parameters = parameters;
        this.publisher = publisher;

        visibilities = create_visibilities();
        sizes = create_sizes();

        string upload_label_text = _("You are logged into Flickr as %s.\n\n").printf(parameters.username);
        if (parameters.user_kind == UserKind.FREE) {
            upload_label_text += _("Your free Flickr account limits how much data you can upload per month.\nThis month, you have %d megabytes remaining in your upload quota.").printf(parameters.quota_free_mb);
        } else {
            upload_label_text += _("Your Flickr Pro account entitles you to unlimited uploads.");
        }

        Gtk.SeparatorToolItem top_space = new Gtk.SeparatorToolItem();
        top_space.set_draw(false);
        Gtk.SeparatorToolItem bottom_space = new Gtk.SeparatorToolItem();
        bottom_space.set_draw(false);
        add(top_space);
        top_space.set_size_request(-1, 32);

        Gtk.Label upload_info_label = new Gtk.Label(upload_label_text);
        add(upload_info_label);

        Gtk.SeparatorToolItem upload_combos_spacer = new Gtk.SeparatorToolItem();
        upload_combos_spacer.set_draw(false);
        add(upload_combos_spacer);
        upload_combos_spacer.set_size_request(-1, 32);

        Gtk.HBox combos_layouter_padder = new Gtk.HBox(false, 8);
        Gtk.SeparatorToolItem combos_left_padding = new Gtk.SeparatorToolItem();
        combos_left_padding.set_draw(false);
        Gtk.SeparatorToolItem combos_right_padding = new Gtk.SeparatorToolItem();
        combos_right_padding.set_draw(false);
        Gtk.Table combos_layouter = new Gtk.Table(2, 2, false);
        combos_layouter.set_row_spacing(0, 12);
        string visibility_label_text = _("Photos _visible to:");
        if ((media_type == Spit.Publishing.Publisher.MediaType.VIDEO)) {
            visibility_label_text = _("Videos _visible to:");
        } else if ((media_type == (Spit.Publishing.Publisher.MediaType.PHOTO | Spit.Publishing.Publisher.MediaType.VIDEO))) {
            visibility_label_text = _("Photos and videos _visible to:");
        }
        Gtk.Label visibility_label = new Gtk.Label.with_mnemonic(visibility_label_text);
        Gtk.Label size_label = new Gtk.Label.with_mnemonic(_("Photo _size:"));
        Gtk.Alignment visibility_combo_aligner = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        visibility_combo = create_visibility_combo();
        visibility_combo.changed.connect(on_visibility_changed);
        visibility_label.set_mnemonic_widget(visibility_combo);
        visibility_combo_aligner.add(visibility_combo);
        Gtk.Alignment size_combo_aligner = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        size_combo = create_size_combo();
        size_label.set_mnemonic_widget(size_combo);
        size_combo.changed.connect(on_size_changed);
        size_combo_aligner.add(size_combo);
        Gtk.Alignment vis_label_aligner = new Gtk.Alignment(0.0f, 0.5f, 0, 0);
        vis_label_aligner.add(visibility_label);
        Gtk.Alignment size_label_aligner = new Gtk.Alignment(0.0f, 0.5f, 0, 0);
        size_label_aligner.add(size_label);
        combos_layouter.attach_defaults(vis_label_aligner, 0, 1, 0, 1);
        combos_layouter.attach_defaults(visibility_combo_aligner, 1, 2, 0, 1);

        if ((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) != 0) {
            combos_layouter.attach_defaults(size_label_aligner, 0, 1, 1, 2);
            combos_layouter.attach_defaults(size_combo_aligner, 1, 2, 1, 2);
        }
        combos_layouter_padder.add(combos_left_padding);
        combos_layouter_padder.add(combos_layouter);
        combos_layouter_padder.add(combos_right_padding);
        add(combos_layouter_padder);

        Gtk.SeparatorToolItem combos_buttons_spacer = new Gtk.SeparatorToolItem();
        combos_buttons_spacer.set_draw(false);
        add(combos_buttons_spacer);
        combos_buttons_spacer.set_size_request(-1, 32);

        Gtk.Alignment logout_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        logout_button = new Gtk.Button.with_mnemonic(_("_Logout"));
        logout_button.clicked.connect(on_logout_clicked);
        logout_button_aligner.add(logout_button);
        Gtk.Alignment publish_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        publish_button = new Gtk.Button.with_mnemonic(_("_Publish"));
        publish_button_aligner.add(publish_button);
        publish_button.clicked.connect(on_publish_clicked);
        Gtk.HBox button_layouter = new Gtk.HBox(false, 8);
        Gtk.SeparatorToolItem buttons_left_padding = new Gtk.SeparatorToolItem();
        buttons_left_padding.set_draw(false);
        Gtk.SeparatorToolItem buttons_right_padding = new Gtk.SeparatorToolItem();
        buttons_right_padding.set_draw(false);
        Gtk.SeparatorToolItem buttons_interspacing = new Gtk.SeparatorToolItem();
        buttons_interspacing.set_draw(false);
        button_layouter.add(buttons_left_padding);
        button_layouter.add(logout_button_aligner);
        button_layouter.add(buttons_interspacing);
        button_layouter.add(publish_button_aligner);
        button_layouter.add(buttons_right_padding);
        add(button_layouter);
        logout_button.set_size_request(ACTION_BUTTON_WIDTH, -1);
        publish_button.set_size_request(ACTION_BUTTON_WIDTH, -1);

        add(bottom_space);
        bottom_space.set_size_request(-1, 32);
    }

    private void on_logout_clicked() {
        logout();
    }

    private void on_publish_clicked() {
        parameters.visibility_specification =
            visibilities[visibility_combo.get_active()].specification;
        parameters.photo_major_axis_size = sizes[size_combo.get_active()].size;

        publish();
    }

    private VisibilityEntry[] create_visibilities() {
        VisibilityEntry[] result = new VisibilityEntry[0];

        result += VisibilityEntry(_("Everyone"), VisibilitySpecification(1, 1, 1));
        result += VisibilityEntry(_("Friends & family only"), VisibilitySpecification(1, 1, 0));
        result += VisibilityEntry(_("Just me"), VisibilitySpecification(0, 0, 0));

        return result;
    }

    private Gtk.ComboBox create_visibility_combo() {
        Gtk.ComboBoxText result = new Gtk.ComboBoxText();

        if (visibilities == null)
            visibilities = create_visibilities();

        foreach (VisibilityEntry v in visibilities)
            result.append_text(v.title);

        result.set_active(publisher.get_persistent_visibility());

        return result;
    }

    private SizeEntry[] create_sizes() {
        SizeEntry[] result = new SizeEntry[0];

        result += SizeEntry(_("500 x 375 pixels"), 500);
        result += SizeEntry(_("1024 x 768 pixels"), 1024);
        result += SizeEntry(_("2048 x 1536 pixels"), 2048);
        result += SizeEntry(_("4096 x 3072 pixels"), 4096);
        result += SizeEntry(_("Original size"), ORIGINAL_SIZE);

        return result;
    }

    private Gtk.ComboBox create_size_combo() {
        Gtk.ComboBoxText result = new Gtk.ComboBoxText();

        if (sizes == null)
            sizes = create_sizes();

        foreach (SizeEntry e in sizes)
            result.append_text(e.title);

        result.set_active(publisher.get_persistent_default_size());

        return result;
    }

    private void on_size_changed() {
        publisher.set_persistent_default_size(size_combo.get_active());
    }

    private void on_visibility_changed() {
        publisher.set_persistent_visibility(visibility_combo.get_active());
    }
}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {
    private LegacyPublishingOptionsPane wrapped = null;

    public signal void publish();
    public signal void logout();

    public PublishingOptionsPane(FlickrPublisher publisher, PublishingParameters parameters,
        Spit.Publishing.Publisher.MediaType media_type) {
        wrapped = new LegacyPublishingOptionsPane(publisher, parameters, media_type);
    }
    
    protected void notify_publish() {
        publish();
    }
    
    protected void notify_logout() {
        logout();
    }

    public Gtk.Widget get_widget() {
        return wrapped;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }
    
    public void on_pane_installed() {        
        wrapped.publish.connect(notify_publish);
        wrapped.logout.connect(notify_logout);
    }
    
    public void on_pane_uninstalled() {
        wrapped.publish.disconnect(notify_publish);
        wrapped.logout.disconnect(notify_logout);
    }
}

internal class Uploader : Publishing.RESTSupport.BatchUploader {
    private PublishingParameters parameters;

    public Uploader(Session session, Spit.Publishing.Publishable[] publishables,
        PublishingParameters parameters) {
        base(session, publishables);
        
        this.parameters = parameters;
    }
    
    private void preprocess_publishable(Spit.Publishing.Publishable publishable) {
        if (publishable.get_media_type() != Spit.Publishing.Publisher.MediaType.PHOTO)
            return;

        GExiv2.Metadata publishable_metadata = new GExiv2.Metadata();
        try {
            publishable_metadata.open_path(publishable.get_serialized_file().get_path());
        } catch (GLib.Error err) {
            warning("couldn't read metadata from file '%s' for upload preprocessing.",
                publishable.get_serialized_file().get_path());
        }
        
        // Flickr internationalization issues only affect IPTC tags; XMP, being an XML
        // grammar and using standard XML internationalization mechanisms, doesn't need any i18n
        // massaging before upload, so if the publishable doesn't have any IPTC metadata, then
        // just do a short-circuit return
        if (!publishable_metadata.has_iptc())
            return;

        if (publishable_metadata.has_tag("Iptc.Application2.Caption"))
            publishable_metadata.set_tag_string("Iptc.Application2.Caption",
                Publishing.RESTSupport.asciify_string(publishable_metadata.get_tag_string(
                "Iptc.Application2.Caption")));

        if (publishable_metadata.has_tag("Iptc.Application2.Headline"))
            publishable_metadata.set_tag_string("Iptc.Application2.Headline",
                Publishing.RESTSupport.asciify_string(publishable_metadata.get_tag_string(
                "Iptc.Application2.Headline")));

        if (publishable_metadata.has_tag("Iptc.Application2.Keywords")) {
            Gee.Set<string> keyword_set = new Gee.HashSet<string>();
            string[] iptc_keywords = publishable_metadata.get_tag_multiple("Iptc.Application2.Keywords");
            if (iptc_keywords != null)
                foreach (string keyword in iptc_keywords)
                    keyword_set.add(keyword);

            string[] xmp_keywords = publishable_metadata.get_tag_multiple("Xmp.dc.subject");
            if (xmp_keywords != null)
                foreach (string keyword in xmp_keywords)
                    keyword_set.add(keyword);

            string[] all_keywords = keyword_set.to_array();
            // append a null pointer to the end of all_keywords -- this is a necessary workaround
            // for http://trac.yorba.org/ticket/3264. See also http://trac.yorba.org/ticket/3257,
            // which describes the user-visible behavior seen in the Flickr Connector as a result
            // of the former bug.
            all_keywords += null;

            string[] no_keywords = new string[1];
            // append a null pointer to the end of no_keywords -- this is a necessary workaround
            // for http://trac.yorba.org/ticket/3264. See also http://trac.yorba.org/ticket/3257,
            // which describes the user-visible behavior seen in the Flickr Connector as a result
            // of the former bug.
            no_keywords[0] = null;
            
            publishable_metadata.set_tag_multiple("Xmp.dc.subject", all_keywords);
            publishable_metadata.set_tag_multiple("Iptc.Application2.Keywords", no_keywords);

            try {
                publishable_metadata.save_file(publishable.get_serialized_file().get_path());
            } catch (GLib.Error err) {
                warning("couldn't write metadata to file '%s' for upload preprocessing.",
                    publishable.get_serialized_file().get_path());
            }
        }
    }
    
    protected override Publishing.RESTSupport.Transaction create_transaction(
        Spit.Publishing.Publishable publishable) {
        preprocess_publishable(get_current_publishable());
        return new UploadTransaction((Session) get_session(), parameters,
            get_current_publishable());
    }
}

}

