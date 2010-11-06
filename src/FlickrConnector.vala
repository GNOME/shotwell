/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

namespace FlickrConnector {
private const string SERVICE_NAME = "Flickr";
private const string SERVICE_WELCOME_MESSAGE = 
    _("You are not currently logged into Flickr.\n\nYou must have already signed up for a Flickr account to complete the login process. During login you will have to specifically authorize Shotwell Connect to link to your Flickr account.");
private const string RESTART_ERROR_MESSAGE = 
    _("You have already logged in and out of Flickr during this Shotwell session.\nTo continue publishing to Flickr, quit and restart Shotwell, then try publishing again.");
private const string ENDPOINT_URL = "http://api.flickr.com/services/rest";
private const string API_KEY = "60dd96d4a2ad04888b09c9e18d82c26f";
private const string API_SECRET = "d0960565e03547c1";

private enum UserKind {
    PRO,
    FREE,
}

private struct VisibilitySpecification {
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
private class PublishingParameters {
    public UserKind user_kind;
    public int quota_free_mb;
    public int photo_major_axis_size;
    public string username;
    public VisibilitySpecification visibility_specification;

    public PublishingParameters() {
    }
}

public class Capabilities : ServiceCapabilities {
    public override string get_name() {
        return SERVICE_NAME;
    }
    
    public override ServiceCapabilities.MediaType get_supported_media() {
        return MediaType.PHOTO | MediaType.VIDEO;
    }
    
    public override ServiceInteractor factory(PublishingDialog host) {
        return new Interactor(host);
    }
}

public class Interactor : ServiceInteractor {
    private Session session = null;
    private WebAuthenticationPane web_auth_pane = null;
    private string frob = null;
    private PublishingParameters parameters;
    private bool cancelled = false;
    private ProgressPane progress_pane;

    public Interactor(PublishingDialog host) {
        base(host);
        
        session = new Session();
        parameters = new PublishingParameters();
        
        debug("Flickr.Interactor: created Session object with endpoint_url = '%s', api_key = '%s', api_secret = '%s'",
            session.get_endpoint_url(), session.get_api_key(), session.get_api_secret());
    }

    private void on_login_welcome_pane_login() {
        // ignore all events if the user cancelled or if we have an error situation
        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_login_welcome_pane_login( ): EVENT: user clicked 'Login' button in login welcome pane");
        do_obtain_frob();
    }

    private void on_frob_fetch_txn_completed(RESTTransaction txn) {
        txn.completed.disconnect(on_frob_fetch_txn_completed);
        txn.network_error.disconnect(on_frob_fetch_txn_error);

        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_frob_fetch_txn_completed( ): EVENT: frob fetch transaction response was received over the network");
        do_extract_frob_from_xml(txn.get_response());
    }

    private void on_frob_fetch_txn_error(RESTTransaction txn, PublishingError err) {
        txn.completed.disconnect(on_frob_fetch_txn_completed);
        txn.network_error.disconnect(on_frob_fetch_txn_error);

        if (has_error() || cancelled)
            return;

        post_error(err);
    }

    private void on_frob_available(string frob) {
        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_frob_available( ): EVENT: frob = '%s' is available", frob);
        do_build_login_url_from_frob(frob);
    }

    private void on_login_url_available(string login_url) {
        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_login_url_available( ): EVENT: login_url = '%s' is available", login_url);
        do_start_hosted_web_authentication(login_url);
    }

    private void on_web_auth_pane_token_check_required() {
        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_web_auth_pane_token_check_required( ): EVENT: web authentication pane has loaded a new page, need to check if auth token has become valid");
        do_token_check();
    }

    private void on_token_check_txn_completed(RESTTransaction txn) {
        txn.completed.disconnect(on_token_check_txn_completed);
        txn.network_error.disconnect(on_token_check_txn_error);

        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_token_check_txn_completed( ): EVENT: token check transaction response was received over the network");
        do_interpret_token_check_xml(txn.get_response());
    }

    // token check "error" vs "failure" -- "error" means that the actual network transaction
    // errored out, indicating a network transport issue such as bad DNS lookup, 404 error, etc.,
    // whereas "failure" means that the network transaction succeeded in making a round trip
    // to the server but the response didn't contain an authentication token

    private void on_token_check_txn_error(RESTTransaction txn, PublishingError err) {
        txn.completed.disconnect(on_token_check_txn_completed);
        txn.network_error.disconnect(on_token_check_txn_error);

        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_token_check_txn_error( ): EVENT: token check transaction caused a network error");

        post_error(err);
    }

    private void on_token_check_failed() {
        if (has_error() || cancelled)
            return;

        debug("Flick.Interactor: on_token_check_failed( ): EVENT: a token check attempt was made and failed");
        do_continue_hosted_web_authentication();
    }

    private void on_token_check_succeeded(string token, string username) {
        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_token_check_succeeded( ): EVENT: a token check succeeded with token = '%s', username = '%s'", token, username);
        do_authenticate_session(token, username);
    }

    private void on_authenticated_session_ready() {
        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_authenticated_session_ready( ): EVENT: an authenticated session is available for use");
        parameters.username = session.get_username();
        do_fetch_account_info();
    }

    private void on_account_fetch_txn_completed(RESTTransaction txn) {
        txn.completed.disconnect(on_account_fetch_txn_completed);
        txn.network_error.disconnect(on_account_fetch_txn_error);

        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_account_fetch_txn_completed( ): EVENT: account fetch transaction response was received over the network");
        do_parse_account_info_from_xml(txn.get_response());
    }

    private void on_account_fetch_txn_error(RESTTransaction txn, PublishingError err) {
        txn.completed.disconnect(on_account_fetch_txn_completed);
        txn.network_error.disconnect(on_account_fetch_txn_error);

        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor: on_account_fetch_txn_error( ): EVENT: account fetch transaction caused a network error");
        post_error(err);
    }

    private void on_account_info_available() {
        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor.on_account_info_available( ): EVENT: account information is available");
        do_show_publishing_options_pane();
    }

    private void on_publishing_options_pane_publish() {
        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor.on_publishing_options_pane_publish( ): EVENT: user clicked the 'Publish' button in the publishing options pane");
        do_publish();
    }

    private void on_publishing_options_pane_logout() {
        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor.on_publishing_options_pane_logout( ): EVENT: user clicked the 'Logout' button in the publishing options pane");
        session.deauthenticate();
        start_interaction(); // restart the interaction
    }

    private void on_upload_complete(BatchUploader uploader, int num_published) {
        uploader.status_updated.disconnect(progress_pane.set_status);
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        // TODO: add a descriptive, translatable error message string here
        if (num_published == 0)
            post_error(new PublishingError.LOCAL_FILE_ERROR(""));

        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor.on_upload_complete( ): EVENT: batch uploader reports all network upload transactions have completed");
        do_show_success_pane();
    }

    private void on_upload_error(BatchUploader uploader, PublishingError err) {
        uploader.status_updated.disconnect(progress_pane.set_status);
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        if (has_error() || cancelled)
            return;

        debug("Flickr.Interactor.on_upload_complete( ): EVENT: batch uploader reports that an upload transaction caused a network error");
        post_error(err);
    }

    private void do_show_login_welcome_pane() {
        debug("Flickr.Interactor.do_show_login_welcome_pane( ): ACTION: installing login welcome pane");

        get_host().unlock_service();
        get_host().set_cancel_button_mode();
        LoginWelcomePane login_welcome_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
        login_welcome_pane.login_requested.connect(on_login_welcome_pane_login);
        get_host().install_pane(login_welcome_pane);
    }

    private void do_obtain_frob() {
        debug("Flickr.Interactor.do_obtain_frob( ): ACTION: building and executing network transaction to obtain Yahoo! login frob");

        get_host().lock_service();
        get_host().set_cancel_button_mode();
        get_host().install_pane(new StaticMessagePane(_("Preparing to login...")));

        FrobFetchTransaction frob_fetch_txn = new FrobFetchTransaction(session);
        frob_fetch_txn.completed.connect(on_frob_fetch_txn_completed);
        frob_fetch_txn.network_error.connect(on_frob_fetch_txn_error);

        frob_fetch_txn.execute();
    }
    
    private void do_extract_frob_from_xml(string xml) {
        debug("Flickr.Interactor: do_extract_frob_from_xml( ): ACTION: extracting frob from response xml = '%s'", xml);
        string frob = null;
        try {
            RESTXmlDocument response_doc = RESTXmlDocument.parse_string(xml,
                Transaction.check_response);

            Xml.Node* root = response_doc.get_root_node();

            Xml.Node* frob_node = response_doc.get_named_child(root, "frob");
            
            string local_frob = frob_node->get_content();

            if (local_frob == null)
                throw new PublishingError.MALFORMED_RESPONSE("No frob returned in request");
            
            frob = local_frob;
        } catch (PublishingError err) {
            post_error(err);
            return;
        }
        
        assert(frob != null);
        this.frob = frob;
        on_frob_available(frob);
    }
    
    private void do_build_login_url_from_frob(string frob) {
        debug("Flickr.Interactor: do_build_login_url_from_frob( ): ACTION: building login url from frob");

        string hash_string = session.get_api_secret() + "api_key%s".printf(session.get_api_key()) +
            "frob%s".printf(frob) + "permswrite";
        string sig = Checksum.compute_for_string(ChecksumType.MD5, hash_string);
        string login_url =
            "http://flickr.com/services/auth/?api_key=%s&perms=%s&frob=%s&api_sig=%s".printf(
            session.get_api_key(), "write", frob, sig);

        on_login_url_available(login_url);
    }

    private void do_start_hosted_web_authentication(string login_url) {
        debug("Flickr.Interactor: do_run_hosted_web_authentication( ): ACTION: running hosted web authentication");
        
        get_host().unlock_service();
        get_host().set_cancel_button_mode();
        get_host().set_large_window_mode();
       
        web_auth_pane = new WebAuthenticationPane(login_url);
        web_auth_pane.token_check_required.connect(on_web_auth_pane_token_check_required);
        get_host().install_pane(web_auth_pane);
    }

    private void do_token_check() {
        if (session.is_authenticated())
            return;

        debug("Flickr.Interactor: do_token_check( ): ACTION: building and executing network transaction to check if authentication token is available");
        
        TokenCheckTransaction token_check_txn = new TokenCheckTransaction(session, frob);
        token_check_txn.completed.connect(on_token_check_txn_completed);
        token_check_txn.network_error.connect(on_token_check_txn_error);
        
        token_check_txn.execute();
    }

    private void do_interpret_token_check_xml(string xml) {
        if (session.is_authenticated())
            return;

        debug("Flickr.Interactor: do_interpret_token_check_xml( ): ACTION: interpreting token check response xml = '%s'", xml);

        RESTXmlDocument response_doc = null;
        try {
            response_doc = RESTXmlDocument.parse_string(xml, Transaction.check_response);
        } catch (PublishingError err) {
            // if we get a service error during token check, it is recoverable -- it just means
            // that no authentication token is available yet -- so just post an event for it
            // and return
            if (err is PublishingError.SERVICE_ERROR) {
                on_token_check_failed();
                return;
            }
            
            post_error(err);
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
        } catch (PublishingError err) {
            post_error(err);
            return;
        }
        
        assert((token != null) && (username != null));
        on_token_check_succeeded(token, username);
    }

    private void do_continue_hosted_web_authentication() {
        debug("Flickr.Interactor: do_continue_hosted_web_authentication( ): ACTION: continuing hosted web authentication");
        assert(web_auth_pane != null);
        web_auth_pane.show_page();
    }

    private void do_authenticate_session(string token, string username) {
        debug("Flickr.Interactor: do_authenticate_session( ): ACTION: authenicating session");

        web_auth_pane.interaction_completed();

        get_host().set_standard_window_mode();

        session.authenticate(token, username);
        assert(session.is_authenticated());

        on_authenticated_session_ready();
    }

    private void do_fetch_account_info() {
        debug("Flickr.Interactor: do_fetching_account_information( ): ACTION: building and executing network transaction to fetch account information");

        get_host().set_cancel_button_mode();
        get_host().lock_service();
        get_host().install_pane(new AccountFetchWaitPane());

        AccountInfoFetchTransaction txn = new AccountInfoFetchTransaction(session);
        txn.completed.connect(on_account_fetch_txn_completed);
        txn.network_error.connect(on_account_fetch_txn_error);

        txn.execute();
    }

    private void do_parse_account_info_from_xml(string xml) {
        debug("Flickr.Interactor: do_parse_account_info_from_xml( ): ACTION: parsing account information from xml = '%s'", xml);
        try {
            RESTXmlDocument response_doc = RESTXmlDocument.parse_string(xml,
                Transaction.check_response);
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
                throw new PublishingError.MALFORMED_RESPONSE("Unable to determine if user has free or pro account");
            
            int quota_mb_left = remaining_kb_str.to_int() / 1024;

            parameters.quota_free_mb = quota_mb_left;
            parameters.user_kind = user_kind;

        } catch (PublishingError err) {
            post_error(err);
            return;
        }
        on_account_info_available();
    }

    private void do_show_publishing_options_pane() {
        debug("Flickr.Interactor: do_show_publishing_options_pane( ): ACTION: displaying publishing options pane");
        get_host().unlock_service();
        get_host().set_cancel_button_mode();

        PublishingOptionsPane publishing_options_pane = new PublishingOptionsPane(parameters, get_host().get_media_type());
        publishing_options_pane.publish.connect(on_publishing_options_pane_publish);
        publishing_options_pane.logout.connect(on_publishing_options_pane_logout);
        get_host().install_pane(publishing_options_pane);
    }

    private void do_publish() {
        debug("Flickr.Interactor: do_publish( ): ACTION: preparing to do publishing meta-action");

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        progress_pane = new ProgressPane();
        get_host().install_pane(progress_pane);

        MediaSource[] photos = get_host().get_media();
        Uploader uploader = new Uploader(session, parameters, photos);
        uploader.status_updated.connect(progress_pane.set_status);
        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);

        uploader.upload();
    }

    private void do_show_success_pane() {
        get_host().unlock_service();
        get_host().set_close_button_mode();

        get_host().install_pane(new SuccessPane());
    }

    public override string get_name() {
        return SERVICE_NAME;
    }

    public override void cancel_interaction() {
        session.stop_transactions();
        cancelled = true;
    }

    public override void start_interaction() {
        if (session.is_authenticated()) {
            // if a fully authenticated session has been loaded from GConf, then simulate an
            // authenticated session ready event
            on_authenticated_session_ready();
        } else {
            if (WebAuthenticationPane.is_cache_dirty()) {
                get_host().set_cancel_button_mode();
                get_host().unlock_service();
                get_host().install_pane(new StaticMessagePane(RESTART_ERROR_MESSAGE));
            } else {
                do_show_login_welcome_pane();
            }
        }
    }
}

private class Session : RESTSession {
    private string api_key;
    private string api_secret;
    private string auth_token;
    private string username;

    public Session() {
        base(ENDPOINT_URL);
        
        this.api_key = API_KEY;
        this.api_secret = API_SECRET;

        if (is_persistent_session_valid()) {
            Config config = Config.get_instance();
            auth_token = config.get_flickr_auth_token();
            username = config.get_flickr_username();
        }
    }

    private static bool is_persistent_session_valid() {
        Config config = Config.get_instance();

        string auth_token = config.get_flickr_auth_token();
        string username = config.get_flickr_username();
        
        return ((auth_token != null) && (username != null));
    }

    private static void invalidate_persistent_session() {
        Config config = Config.get_instance();
        config.clear_flickr_auth_token();
        config.clear_flickr_username();
    }

    public bool is_authenticated() {
        return (auth_token != null && username != null);
    }

    public void authenticate(string auth_token, string username) {
        this.auth_token = auth_token;
        this.username = username;

        Config config = Config.get_instance();
        config.set_flickr_auth_token(auth_token);
        config.set_flickr_username(username);
    }

    public void deauthenticate() {
        invalidate_persistent_session();
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

private class Uploader : BatchUploader {
    private Session session;
    private PublishingParameters parameters;

    public Uploader(Session session, PublishingParameters params, MediaSource[] photos) {
        base.with_media(photos);

        this.session = session;
        this.parameters = params;
    }

    protected override bool prepare_file(BatchUploader.TemporaryFileDescriptor file) {
        Scaling scaling = (parameters.photo_major_axis_size == ORIGINAL_SIZE)
            ? Scaling.for_original() : Scaling.for_best_fit(parameters.photo_major_axis_size,
            false);
        
        try {
            if (file.media is Photo) {
                ((Photo) file.media).export(file.temp_file, scaling, Jpeg.Quality.MAXIMUM,
                    PhotoFileFormat.JFIF);
            }
        } catch (Error e) {
            return false;
        }
        
        return true;
    }

    protected override RESTTransaction create_transaction_for_file(
        BatchUploader.TemporaryFileDescriptor file) {
        return new UploadTransaction(session, parameters, file.temp_file.get_path(), file.media);
    }
}

private class Transaction : RESTTransaction {
    public const string SIGNATURE_KEY = "api_sig";

    public Transaction(Session session) {
        base(session);

        add_argument("api_key", ((Session) get_parent_session()).get_api_key());
    }
    
    protected override void sign() {
        string sig = generate_signature(get_sorted_arguments(),
            ((Session) get_parent_session()).get_api_secret());

        set_signature_key(SIGNATURE_KEY);
        set_signature_value(sig);
    }

    public static string generate_signature(RESTArgument[] sorted_args, string api_secret) {
        string hash_string = "";
        foreach (RESTArgument arg in sorted_args)
            hash_string = hash_string + ("%s%s".printf(arg.key, arg.value));

        return Checksum.compute_for_string(ChecksumType.MD5, api_secret + hash_string);
    }

    public static new string? check_response(RESTXmlDocument doc) {
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
        } catch (PublishingError err) {
            return "No error code specified";
        }
        
        return "%s (error code %s)".printf(errcode->get_prop("msg"), errcode->get_prop("code"));
    }
}

private class FrobFetchTransaction : Transaction {
    public FrobFetchTransaction(Session session) {
        base(session);

        add_argument("method", "flickr.auth.getFrob");
    }
}

private class TokenCheckTransaction : Transaction {
    public TokenCheckTransaction(Session session, string frob) {
        base(session);

        add_argument("method", "flickr.auth.getToken");
        add_argument("frob", frob);
    }
}

private class AccountInfoFetchTransaction : Transaction {
    public AccountInfoFetchTransaction(Session session) {
        base(session);

        add_argument("method", "flickr.people.getUploadStatus");
        add_argument("auth_token", session.get_auth_token());
    }
}

private class UploadTransaction : MediaUploadTransaction {
    public UploadTransaction(Session session, PublishingParameters params, string source_file_path,
        MediaSource media_source) {
        base.with_endpoint_url(session, "http://api.flickr.com/services/upload", source_file_path,
            media_source);

        add_argument("api_key", session.get_api_key());
        add_argument("auth_token", session.get_auth_token());
        add_argument("is_public", ("%d".printf(params.visibility_specification.everyone_level)));
        add_argument("is_friend", ("%d".printf(params.visibility_specification.friends_level)));
        add_argument("is_family", ("%d".printf(params.visibility_specification.family_level)));

        GLib.HashTable<string, string> disposition_table =
            new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
        disposition_table.insert("filename", media_source.get_name());
        disposition_table.insert("name", "photo");
        set_binary_disposition_table(disposition_table);
    }

    protected override void sign() {
        string sig = Transaction.generate_signature(get_sorted_arguments(),
            ((Session) get_parent_session()).get_api_secret());

        set_signature_key(Transaction.SIGNATURE_KEY);
        set_signature_value(sig);
    }
}

private class WebAuthenticationPane : PublishingDialogPane {
    private const string END_STAGE_URL = "http://www.flickr.com/services/auth/";

    private static bool cache_dirty = false;

    private WebKit.WebView webview = null;
    private Gtk.ScrolledWindow webview_frame = null;
    private Gtk.Layout white_pane = null;
    private string login_url;

    public signal void token_check_required();

    public WebAuthenticationPane(string login_url) {
        this.login_url = login_url;

        Gdk.Color white_color;
        Gdk.Color.parse("white", out white_color);
        Gtk.Adjustment layout_pane_adjustment = new Gtk.Adjustment(0.5, 0.0, 1.0, 0.01, 0.1, 0.1);
        white_pane = new Gtk.Layout(layout_pane_adjustment, layout_pane_adjustment);
        white_pane.modify_bg(Gtk.StateType.NORMAL, white_color);
        add(white_pane);

        webview_frame = new Gtk.ScrolledWindow(null, null);
        webview_frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN);
        webview_frame.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        webview = new WebKit.WebView();
        webview.load_finished.connect(on_load_finished);
        webview.load_started.connect(on_load_started);

        webview_frame.add(webview);
        white_pane.add(webview_frame);
        webview.set_size_request(853, 587);
    }
    
   
    private void on_load_finished(WebKit.WebFrame origin_frame) {
        if (origin_frame.uri == END_STAGE_URL) {
            token_check_required();
        } else {
            show_page();
        }
    }
    
    private void on_load_started(WebKit.WebFrame origin_frame) {
        webview_frame.hide();
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
    }

    public static bool is_cache_dirty() {
        return cache_dirty;
    }

    public void show_page() {
        webview_frame.show();
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
    }
   
    public override void installed() {
        webview.open(login_url);
    }

    public void interaction_completed() {
        cache_dirty = true;
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
    }
}

private class PublishingOptionsPane : PublishingDialogPane {
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

    private Gtk.Button logout_button = null;
    private Gtk.Button publish_button = null;
    private Gtk.ComboBox visibility_combo = null;
    private Gtk.ComboBox size_combo = null;
    private VisibilityEntry[] visibilities = null;
    private SizeEntry[] sizes = null;
    private PublishingParameters parameters = null;

    public signal void publish();
    public signal void logout();

    public PublishingOptionsPane(PublishingParameters parameters, MediaType media_type) {
        this.parameters = parameters;

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
        if ((media_type == MediaType.VIDEO)) {
            visibility_label_text = _("Videos _visible to:");
        } else if ((media_type == MediaType.ALL)) {
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

        if ((media_type & MediaType.PHOTO) != 0) {
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
        logout_button.set_size_request(PublishingDialog.STANDARD_ACTION_BUTTON_WIDTH, -1);
        publish_button.set_size_request(PublishingDialog.STANDARD_ACTION_BUTTON_WIDTH, -1);

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
        Gtk.ComboBox result = new Gtk.ComboBox.text();

        if (visibilities == null)
            visibilities = create_visibilities();

        foreach (VisibilityEntry v in visibilities)
            result.append_text(v.title);

        Config config = Config.get_instance();
        result.set_active(config.get_flickr_visibility());

        return result;
    }

    private SizeEntry[] create_sizes() {
        SizeEntry[] result = new SizeEntry[0];

        result += SizeEntry(_("Medium (500 x 375 pixels)"), 500);
        result += SizeEntry(_("Large (1024 x 768 pixels)"), 1024);
        result += SizeEntry(_("Original size"), ORIGINAL_SIZE);

        return result;
    }

    private Gtk.ComboBox create_size_combo() {
        Gtk.ComboBox result = new Gtk.ComboBox.text();

        if (sizes == null)
            sizes = create_sizes();

        foreach (SizeEntry e in sizes)
            result.append_text(e.title);

        Config config = Config.get_instance();
        result.set_active(config.get_flickr_default_size());

        return result;
    }

    private void on_size_changed() {
        Config config = Config.get_instance();
        config.set_flickr_default_size(size_combo.get_active());
    }

    private void on_visibility_changed() {
        Config config = Config.get_instance();
        config.set_flickr_visibility(visibility_combo.get_active());
    }
}

}

#endif

