/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

namespace FacebookConnector {
// this should not be changed by anyone unless they know what they're doing
private const string SERVICE_NAME = "Facebook";
private const string API_KEY = "3afe0a1888bd340254b1587025f8d1a5";
private const int MAX_PHOTO_DIMENSION = 720;
private const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");

private const string SERVICE_WELCOME_MESSAGE = 
    _("You are not currently logged into Facebook.\n\nIf you don't yet have a Facebook account, you can create one during the login process. During login, Shotwell Connect may ask you for permission to upload photos and publish to your feed. These permissions are required for Shotwell Connect to function.");
private const string RESTART_ERROR_MESSAGE = 
    _("You have already logged in and out of Facebook during this Shotwell session.\nTo continue publishing to Facebook, quit and restart Shotwell, then try publishing again.");

private struct Album {
    string name;
    string id;
    
    Album(string creator_name, string creator_id) {
        name = creator_name;
        id = creator_id;
    }
}

public class Capabilities : ServiceCapabilities {
    public override string get_name() {
        return SERVICE_NAME;
    }
    
    public override ServiceCapabilities.MediaType get_supported_media() {
        return MediaType.PHOTO;
    }
    
    public override ServiceInteractor factory(PublishingDialog host) {
        return new Interactor(host);
    }
}

public class Interactor : ServiceInteractor {
    private const int NO_ALBUM = -1;

    private Session session;
    // we need to hold a reference to the web_auth_pane to ensure that it is not destroyed after
    // it's unhooked from the publishing dialog. This is necessary, otherwise WebKit will get
    // very angry.
    private WebAuthenticationPane web_auth_pane = null;
    private ProgressPane progress_pane = null;
    private Album[] albums = null;
    private int publish_to_album = NO_ALBUM;
    private bool cancelled = false;

    public Interactor(PublishingDialog host) {
        base(host);

        session = new Session(API_KEY);
    }

    private int lookup_album(string name) {
        for (int i = 0; i < albums.length; i++) {
            if (albums[i].name == name)
                return i;
        }
        return NO_ALBUM;
    }

    private void on_service_welcome_login() {
        // ignore all events if the user has cancelled or we have and error situation
        if (has_error() || cancelled)
            return;

        do_test_connection_to_endpoint();
    }

    private void on_web_auth_pane_login_succeeded(string success_url) {
        if (has_error() || cancelled)
            return;

        web_auth_pane.hide();
        get_host().set_standard_window_mode();
        do_authenticate_session(success_url);
    }

    private void on_web_auth_pane_login_failed() {
        if (has_error() || cancelled)
            return;

        get_host().set_standard_window_mode();

        // In this case, "failed" doesn't mean that the user didn't enter the right username and
        // password -- Facebook handles that case inside the Facebook Connect web control. Instead,
        // it means that no session was initiated in response to our login request. The only
        // way this happens is if the user clicks the "Cancel" button that appears inside
        // the web control. In this case, the correct behavior is to return the user to the
        // service welcome pane so that they can start the web interaction again.
        do_show_service_welcome_pane();
    }

    private void on_publishing_options_pane_logout() {
        if (has_error() || cancelled)
            return;

        do_logout();
    }

    private void on_publishing_options_pane_publish(string album_name) {
        if (has_error() || cancelled)
            return;

        if (lookup_album(album_name) != NO_ALBUM) {
            publish_to_album = lookup_album(album_name);
            do_upload();
        } else {
            do_create_album(album_name);
        }
    }

    private void on_session_authenticated() {
        if (has_error() || cancelled)
            return;

        assert(session.is_authenticated());
        do_fetch_album_descriptions();
    }

    private void on_session_authentication_failed(PublishingError err) {
        if (has_error() || cancelled)
            return;

        post_error(err);
    }

    private void on_albums_extracted() {
        if (has_error() || cancelled)
            return;

        do_show_publishing_options_pane();
    }

    private void on_fetch_album_descriptions_completed(RESTTransaction txn) {
        txn.completed.disconnect(on_fetch_album_descriptions_completed);
        txn.network_error.disconnect(on_fetch_album_descriptions_error);

        if (has_error() || cancelled)
            return;

        do_extract_albums_from_xml(txn.get_response());
    }

    private void on_fetch_album_descriptions_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_fetch_album_descriptions_completed);
        bad_txn.network_error.disconnect(on_fetch_album_descriptions_error);

        if (has_error() || cancelled)
            return;

        post_error(err);
    }

    private void on_create_album_txn_completed(RESTTransaction txn) {
        txn.completed.disconnect(on_create_album_txn_completed);
        txn.network_error.disconnect(on_create_album_txn_error);

        if (has_error() || cancelled)
            return;

        do_extract_aid_from_xml(txn.get_response());
    }

    private void on_create_album_txn_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_create_album_txn_completed);
        bad_txn.network_error.disconnect(on_create_album_txn_error);

        if (has_error() || cancelled)
            return;

        post_error(err);
    }

    private void on_album_name_extracted() {
        if (has_error() || cancelled)
            return;

        do_upload();
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

        do_show_success_pane();
    }

    private void on_upload_error(BatchUploader uploader, PublishingError err) {
        uploader.status_updated.disconnect(progress_pane.set_status);
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        if (has_error() || cancelled)
            return;

        post_error(err);
    }

    private void on_endpoint_test_completed(RESTTransaction txn) {
        txn.completed.disconnect(on_endpoint_test_completed);
        txn.network_error.disconnect(on_endpoint_test_error);

        if (has_error() || cancelled)
            return;

        do_hosted_web_authentication();
    }

    private void on_endpoint_test_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_endpoint_test_completed);
        bad_txn.network_error.disconnect(on_endpoint_test_error);

        if (has_error() || cancelled)
            return;

        post_error(err);
    }

    private void do_show_publishing_options_pane() {
        get_host().set_cancel_button_mode();
        get_host().unlock_service();

        PublishingOptionsPane publishing_options_pane =
            new PublishingOptionsPane(session.get_user_name(), albums);
        publishing_options_pane.logout.connect(on_publishing_options_pane_logout);
        publishing_options_pane.publish.connect(on_publishing_options_pane_publish);
        get_host().install_pane(publishing_options_pane);
    }

    private void do_show_service_welcome_pane() {
        get_host().set_cancel_button_mode();
        get_host().unlock_service();

        LoginWelcomePane service_welcome_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
        service_welcome_pane.login_requested.connect(on_service_welcome_login);
        get_host().install_pane(service_welcome_pane);
    }

    private void do_authenticate_session(string success_url) {
        debug("Facebook.Interactor: do_authenticate_session( ): ACTION: preparing to extract " +
            ("session key information encoded in url = '%s'").printf(success_url));

        get_host().set_cancel_button_mode();
        get_host().lock_service();
        get_host().install_pane(new AccountFetchWaitPane());

        session.authenticated.connect(on_session_authenticated);
        session.authentication_failed.connect(on_session_authentication_failed);

        try {
            session.authenticate(success_url);
        } catch (PublishingError err) {
            post_error(err);
        }
    }

    private void do_test_connection_to_endpoint() {
        get_host().set_cancel_button_mode();
        get_host().lock_service();

        get_host().install_pane(new StaticMessagePane(_("Testing connection to Facebook...")));

        EndpointTestTransaction txn = new EndpointTestTransaction(session);
        txn.completed.connect(on_endpoint_test_completed);
        txn.network_error.connect(on_endpoint_test_error);

        txn.execute();
    }

    private void do_hosted_web_authentication() {
        get_host().set_cancel_button_mode();
        get_host().unlock_service();

        web_auth_pane = new WebAuthenticationPane();
        web_auth_pane.login_succeeded.connect(on_web_auth_pane_login_succeeded);
        web_auth_pane.login_failed.connect(on_web_auth_pane_login_failed);

        get_host().install_pane(web_auth_pane);
        get_host().set_free_sizable_window_mode();
    }

    private void do_fetch_album_descriptions() {
        get_host().set_cancel_button_mode();
        get_host().lock_service();

        Transaction albums_transaction = new AlbumsFetchTransaction(session);
        albums_transaction.completed.connect(on_fetch_album_descriptions_completed);
        albums_transaction.network_error.connect(on_fetch_album_descriptions_error);

        albums_transaction.execute();
    }

    private void do_extract_albums_from_xml(string xml) {
        debug("Facebook.Interactor: do_extract_albums_from_xml( ): ACTION: extracting album info " +
            ("from xml response '%s'").printf(xml));

        Album[] extracted = new Album[0];

        try {
            RESTXmlDocument response_doc =
                RESTXmlDocument.parse_string(xml, Transaction.check_response);

            Xml.Node* root = response_doc.get_root_node();

            if (root->name != "photos_getAlbums_response")
               throw new PublishingError.MALFORMED_RESPONSE("Document root node has unexpected name '%s'",
                   root->name);

            Xml.Node* doc_node_iter = root->children;
            for ( ; doc_node_iter != null; doc_node_iter = doc_node_iter->next) {
                if (doc_node_iter->name != "album")
                    continue;

                string name_val = null;
                string aid_val = null;
                Xml.Node* album_node_iter = doc_node_iter->children;
                for ( ; album_node_iter != null; album_node_iter = album_node_iter->next) {
                    if (album_node_iter->name == "name") {
                        name_val = album_node_iter->get_content();
                    } else if (album_node_iter->name == "aid") {
                        aid_val = album_node_iter->get_content();
                    }
                }

                if (name_val != "Profile Pictures")
                    extracted += Album(name_val, aid_val);
            }
        } catch (PublishingError err) {
            post_error(err);
            return;
        }

        albums = extracted;

        on_albums_extracted();
    }

    private void do_create_album(string album_name) {
        albums += Album(album_name, "");

        get_host().set_cancel_button_mode();
        get_host().lock_service();

        get_host().install_pane(new StaticMessagePane(_("Creating album...")));

        Transaction create_txn = new AlbumCreationTransaction(session, album_name);
        create_txn.completed.connect(on_create_album_txn_completed);
        create_txn.network_error.connect(on_create_album_txn_error);

        create_txn.execute();
    }

    private void do_extract_aid_from_xml(string xml) {
        try {
            RESTXmlDocument response_doc = RESTXmlDocument.parse_string(xml,
                Transaction.check_response);

            Xml.Node* root = response_doc.get_root_node();
            Xml.Node* aid_node = response_doc.get_named_child(root, "aid");

            assert(albums[albums.length - 1].id == "");

            publish_to_album = albums.length - 1;
            albums[publish_to_album].id = aid_node->get_content();
        } catch (PublishingError err) {
            post_error(err);
            return;
        }

        on_album_name_extracted();
    }

    private void do_upload() {
        assert(publish_to_album != NO_ALBUM);

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        progress_pane = new ProgressPane();
        get_host().install_pane(progress_pane);

        Photo[] photos = get_host().get_photos();
        Uploader uploader = new Uploader(session, albums[publish_to_album].id, photos);
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

    private void do_logout() {
        session.deauthenticate();
        start_interaction();
    }

    public override string get_name() {
        return SERVICE_NAME;
    }

    public override void cancel_interaction() {
        session.stop_transactions();
        cancelled = true;
    }

    public override void start_interaction() {
        get_host().set_standard_window_mode();

        if (session.is_authenticated()) {
            // if a fully authenticated session has been loaded from GConf, then simulate a
            // session authenticated event
            on_session_authenticated();
        } else {
            if (WebAuthenticationPane.is_cache_dirty()) {
                get_host().set_cancel_button_mode();
                get_host().unlock_service();
                get_host().install_pane(new StaticMessagePane(RESTART_ERROR_MESSAGE));
            } else {
                do_show_service_welcome_pane();
            }
        }
    }

    public void logout_user() {
        do_logout();
    }
}

private class Session : RESTSession {
    private const string API_VERSION = "1.0";
    private const string USER_AGENT = "Java/1.6.0_16";
    private const string ENDPOINT_URL = "http://api.facebook.com/restserver.php";

    private string session_key = null;
    private string uid = null;
    private string secret = null;
    private string api_key = null;
    private string user_name = null;

    public signal void authenticated();
    public signal void authentication_failed(PublishingError err);

    public Session(string api_key) {
        base(ENDPOINT_URL, USER_AGENT);

        this.api_key = api_key;

        if (is_persistent_session_valid()) {
            Config config = Config.get_instance();

            session_key = config.get_facebook_session_key();
            secret = config.get_facebook_session_secret();
            uid = config.get_facebook_uid();
            user_name = config.get_facebook_user_name();
        }
    }

    private static bool is_persistent_session_valid() {
        Config config = Config.get_instance();

        string session_key = config.get_facebook_session_key();
        string session_secret = config.get_facebook_session_secret();
        string uid = config.get_facebook_uid();
        string user_name = config.get_facebook_user_name();
       
        return ((session_key != null) && (session_secret != null) && (uid != null) &&
            (user_name != null));
    }

    private static void invalidate_persistent_session() {
        Config config = Config.get_instance();
        
        config.clear_facebook_session_key();
        config.clear_facebook_session_secret();
        config.clear_facebook_uid();
        config.clear_facebook_user_name();
    }

    private void on_user_info_txn_completed(RESTTransaction txn) {
        txn.completed.disconnect(on_user_info_txn_completed);
        txn.network_error.disconnect(on_user_info_txn_error);

        try {
            RESTXmlDocument response_doc = RESTXmlDocument.parse_string(txn.get_response(),
                Transaction.check_response);

            Xml.Node* root_node = response_doc.get_root_node();
            Xml.Node* user_node = response_doc.get_named_child(root_node, "user");
            Xml.Node* name_node = response_doc.get_named_child(user_node, "name");

            user_name = name_node->get_content();
        } catch (PublishingError err) {
            authentication_failed(err);
            return;
        }

        authenticated();

        Config config = Config.get_instance();

        config.set_facebook_session_key(session_key);
        config.set_facebook_session_secret(secret);
        config.set_facebook_uid(uid);
        config.set_facebook_user_name(user_name);
    }

    private void on_user_info_txn_error(RESTTransaction txn, PublishingError err) {
        txn.completed.disconnect(on_user_info_txn_completed);
        txn.network_error.disconnect(on_user_info_txn_error);

        authentication_failed(err);
    }

    public void authenticate(string good_login_uri) throws PublishingError {       
        // the raw uri is percent-encoded, so decode it
        string decoded_uri = Soup.URI.decode(good_login_uri);

        // locate the session object description string within the decoded uri
        string session_desc = decoded_uri.str("session={");
        if (session_desc == null)
            throw new PublishingError.MALFORMED_RESPONSE("Server redirect URL contained no session description");

        // remove any trailing parameters from the session description string
        string trailing_params = session_desc.chr(-1, '&');
        if (trailing_params != null)
            session_desc = session_desc.replace(trailing_params, "");

        // remove the key from the session description string
        session_desc = session_desc.replace("session=", "");
        
        // remove the group open, group close, quote, list separator, and key-value
        // delimiter characters from the session description string
        session_desc = session_desc.replace("{", "");
        session_desc = session_desc.replace("}", "");
        session_desc = session_desc.replace("\"", "");
        session_desc = session_desc.replace(",", " ");
        session_desc = session_desc.replace(":", " ");
        
        // parse the session description string
        string[] session_tokens = session_desc.split(" ");
        for (int i = 0; i < session_tokens.length; i++) {
            if (session_tokens[i] == "session_key") {
                session_key = session_tokens[++i];
            } else if (session_tokens[i] == "uid") {
                uid = session_tokens[++i];
            } else if (session_tokens[i] == "secret") {
                secret = session_tokens[++i];
            }
        }

        if (session_key == null)
            throw new PublishingError.MALFORMED_RESPONSE("Session description object has no session key");
        if (uid == null)
            throw new PublishingError.MALFORMED_RESPONSE("Session description object has no user ID");
        if (secret == null)
            throw new PublishingError.MALFORMED_RESPONSE("Session description object has no session secret");

        UserInfoTransaction user_info_txn = new UserInfoTransaction(this, get_user_id());
        user_info_txn.completed.connect(on_user_info_txn_completed);
        user_info_txn.network_error.connect(on_user_info_txn_error);
        user_info_txn.execute();
    }

    public bool is_authenticated() {
        return ((session_key != null) && (uid != null) && (secret != null) && (api_key != null) &&
                (user_name != null));
    }

    public void deauthenticate() {
        session_key = null;
        uid = null;
        secret = null;
        user_name = null;

        invalidate_persistent_session();
    }

    public string get_api_key() {
        return api_key;
    }

    public string get_session_key() {
        assert(session_key != null);
        return session_key;
    }

    public string get_user_id() {
        assert(uid != null);
        return uid;
    }

    public string get_session_secret() {
        assert(secret != null);
        return secret;
    }

    public string get_next_call_id() {
        TimeVal currtime = TimeVal();
        currtime.get_current_time();

        return "%u.%u".printf((uint) currtime.tv_sec, (uint) currtime.tv_usec);
    }

    public string get_api_version() {
        return API_VERSION;
    }

    public string get_user_name() {
        assert(user_name != null);
        return user_name;
    }
}

private class Uploader : BatchUploader {
    private Session session;
    private string aid;

    public Uploader(Session session, string aid, Photo[] photos) {
        base(photos);

        this.session = session;
        this.aid = aid;
    }

    protected override bool prepare_file(BatchUploader.TemporaryFileDescriptor file) {
        Scaling scaling = Scaling.for_constraint(ScaleConstraint.DIMENSIONS, MAX_PHOTO_DIMENSION,
            false);
        
        try {
            file.source_photo.export(file.temp_file, scaling, Jpeg.Quality.MAXIMUM,
                PhotoFileFormat.JFIF);
        } catch (Error e) {
            return false;
        }

        return true;
    }

    protected override RESTTransaction create_transaction_for_file(
        BatchUploader.TemporaryFileDescriptor file) {
        return new UploadTransaction(session, aid, file.temp_file.get_path(), file.source_photo);
    }
}

private class WebAuthenticationPane : PublishingDialogPane {
    private WebKit.WebView webview = null;
    private Gtk.ScrolledWindow webview_frame = null;
    private static bool cache_dirty = false;

    public signal void login_succeeded(string success_url);
    public signal void login_failed();

    public WebAuthenticationPane() {
        webview_frame = new Gtk.ScrolledWindow(null, null);
        webview_frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN);
        webview_frame.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        webview = new WebKit.WebView();
        webview.load_finished.connect(on_page_load);
        webview.load_started.connect(on_load_started);

        webview_frame.add(webview);
        add(webview_frame);
    }

    private string get_login_url() {
        return "http://www.facebook.com/login.php?api_key=%s&connect_display=popup&v=1.0&next=http://www.facebook.com/connect/login_success.html&cancel_url=http://www.facebook.com/connect/login_failure.html&fbconnect=true&return_session=true&req_perms=read_stream,publish_stream,offline_access,photo_upload,user_photos".printf(FacebookConnector.API_KEY);
    }

    private void on_page_load(WebKit.WebFrame origin_frame) {
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));

        string loaded_url = origin_frame.get_uri().dup();

        // strip parameters from the loaded url
        if (loaded_url.contains("?")) {
            string params = loaded_url.chr(-1, '?');
            loaded_url = loaded_url.replace(params, "");
        }

        // were we redirected to the facebook login success page?
        if (loaded_url.contains("login_success")) {
            cache_dirty = true;
            login_succeeded(origin_frame.get_uri());
            return;
        }

        // were we redirected to the login total failure page?
        if (loaded_url.contains("login_failure")) {
            login_failed();
            return;
        }
    }
    
    private void on_load_started(WebKit.WebFrame frame) {
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
    }

    public static bool is_cache_dirty() {
        return cache_dirty;
    }
    
    public override void installed() {
        webview.open(get_login_url());
    }
}

private class PublishingOptionsPane : PublishingDialogPane {
    private const string HEADER_LABEL_TEXT = _("You are logged into Facebook as %s.\n\nWhere would you like to publish the selected photos?");
    private const int CONTENT_GROUP_SPACING = 32;

    private Gtk.RadioButton use_existing_radio = null;
    private Gtk.RadioButton create_new_radio = null;
    private Gtk.ComboBox existing_albums_combo = null;
    private Gtk.Entry new_album_entry = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private Gtk.Label how_to_label = null;
    private Album[] albums = null;

    public signal void logout();
    public signal void publish(string target_album);

    public PublishingOptionsPane(string username, Album[] albums) {
        this.albums = albums;

        set_border_width(16);

        Gtk.SeparatorToolItem top_padding = new Gtk.SeparatorToolItem();
        top_padding.set_size_request(-1, 50);
        top_padding.set_draw(false);
        add(top_padding);

        Gtk.HBox how_to_label_layouter = new Gtk.HBox(false, 8);
        how_to_label = new Gtk.Label(HEADER_LABEL_TEXT.printf(username));
        Gtk.SeparatorToolItem how_to_pusher = new Gtk.SeparatorToolItem();
        how_to_pusher.set_draw(false);
        how_to_label_layouter.add(how_to_label);
        how_to_label_layouter.add(how_to_pusher);
        how_to_pusher.set_size_request(100, -1);
        add(how_to_label_layouter);

        Gtk.SeparatorToolItem how_to_albums_spacing = new Gtk.SeparatorToolItem();
        how_to_albums_spacing.set_size_request(-1, CONTENT_GROUP_SPACING);
        how_to_albums_spacing.set_draw(false);
        add(how_to_albums_spacing);

        Gtk.VBox album_mode_layouter = new Gtk.VBox(false, 8);
        use_existing_radio = new Gtk.RadioButton.with_mnemonic(null,
            _("Publish to an e_xisting album:"));
        use_existing_radio.clicked.connect(on_use_existing_toggled);
        create_new_radio = new Gtk.RadioButton.with_mnemonic(use_existing_radio.get_group(),
            _("Create a _new album named:"));
        create_new_radio.clicked.connect(on_create_new_toggled);

        Gtk.HBox use_existing_layouter = new Gtk.HBox(false, 8);
        use_existing_layouter.add(use_existing_radio);
        existing_albums_combo = new Gtk.ComboBox.text();
        Gtk.Alignment existing_combo_aligner = new Gtk.Alignment(1.0f, 0.5f, 0.0f, 0.0f);
        existing_combo_aligner.add(existing_albums_combo);
        use_existing_layouter.add(existing_combo_aligner);

        Gtk.HBox create_new_layouter = new Gtk.HBox(false, 8);
        create_new_layouter.add(create_new_radio);
        new_album_entry = new Gtk.Entry();
        create_new_layouter.add(new_album_entry);
        new_album_entry.set_size_request(142, -1);

        publish_button = new Gtk.Button.with_mnemonic(_("_Publish"));
        publish_button.clicked.connect(on_publish_button_clicked);
        logout_button = new Gtk.Button.with_mnemonic(_("_Logout"));
        logout_button.clicked.connect(on_logout_button_clicked);
        Gtk.HBox buttons_layouter = new Gtk.HBox(false, 8);
        Gtk.SeparatorToolItem buttons_left_padding = new Gtk.SeparatorToolItem();
        buttons_left_padding.set_draw(false);
        Gtk.SeparatorToolItem buttons_right_padding = new Gtk.SeparatorToolItem();
        buttons_right_padding.set_draw(false);
        Gtk.SeparatorToolItem buttons_central_padding = new Gtk.SeparatorToolItem();
        buttons_central_padding.set_draw(false);
        buttons_layouter.add(buttons_left_padding);
        Gtk.Alignment logout_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        logout_button_aligner.add(logout_button);
        Gtk.Alignment publish_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        publish_button_aligner.add(publish_button);
        buttons_layouter.add(logout_button_aligner);
        buttons_layouter.add(buttons_central_padding);
        buttons_layouter.add(publish_button_aligner);
        buttons_layouter.add(buttons_right_padding);
        publish_button.set_size_request(PublishingDialog.STANDARD_ACTION_BUTTON_WIDTH, -1);
        logout_button.set_size_request(PublishingDialog.STANDARD_ACTION_BUTTON_WIDTH, -1);

        album_mode_layouter.add(use_existing_layouter);
        album_mode_layouter.add(create_new_layouter);

        Gtk.Alignment album_mode_wrapper = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        album_mode_wrapper.add(album_mode_layouter);

        add(album_mode_wrapper);
        
        Gtk.SeparatorToolItem albums_buttons_spacing = new Gtk.SeparatorToolItem();
        albums_buttons_spacing.set_size_request(-1, CONTENT_GROUP_SPACING);
        albums_buttons_spacing.set_draw(false);
        add(albums_buttons_spacing);
        
        add(buttons_layouter);
        
        Gtk.SeparatorToolItem bottom_padding = new Gtk.SeparatorToolItem();
        bottom_padding.set_size_request(-1, 50);
        bottom_padding.set_draw(false);
        add(bottom_padding);
    }
  
    private void on_use_existing_toggled() {
        if (use_existing_radio.active) {
            existing_albums_combo.set_sensitive(true);
            new_album_entry.set_sensitive(false);
            existing_albums_combo.grab_focus();            
        }
    }
    
    private void on_create_new_toggled() {
        if (create_new_radio.active) {
            existing_albums_combo.set_sensitive(false);
            new_album_entry.set_sensitive(true);
            new_album_entry.grab_focus();
        }
    }
    
    private void on_logout_button_clicked() {
        logout();
    }
    
    private void on_publish_button_clicked() {
        if (use_existing_radio.active) {
            publish(existing_albums_combo.get_active_text());
        } else {
            publish(new_album_entry.get_text());
        }
    }

    public override void installed() {
        if (albums.length == 0) {
            create_new_radio.set_active(true);
            new_album_entry.set_text(DEFAULT_ALBUM_NAME);
            existing_albums_combo.set_sensitive(false);
            use_existing_radio.set_sensitive(false);
        } else {
            int default_album_seq_num = -1;
            int ticker = 0;
            foreach (Album album in albums) {
                existing_albums_combo.append_text(album.name);
                if (album.name == DEFAULT_ALBUM_NAME)
                    default_album_seq_num = ticker;
                ticker++;
            }
            if (default_album_seq_num != -1) {
                existing_albums_combo.set_active(default_album_seq_num);
                use_existing_radio.set_active(true);
                new_album_entry.set_sensitive(false);
            }
            else {
                create_new_radio.set_active(true);
                existing_albums_combo.set_active(0);
                existing_albums_combo.set_sensitive(false);
                new_album_entry.set_text(DEFAULT_ALBUM_NAME);
            }
        }
 
       publish_button.grab_focus();
    }
}

private class Transaction : RESTTransaction {
    public const string SIGNATURE_KEY = "sig";

    public Transaction(Session session) {
        base(session);
    }

    protected override void sign() {
        Session facebook_session = (Session) get_parent_session();
        add_argument("api_key", facebook_session.get_api_key());
        add_argument("session_key", facebook_session.get_session_key());
        add_argument("v", facebook_session.get_api_version());
        add_argument("call_id", facebook_session.get_next_call_id());

        string sig = generate_signature(get_sorted_arguments(), facebook_session);
       
        set_signature_key(SIGNATURE_KEY);
        set_signature_value(sig);
    }

    public static new string? check_response(RESTXmlDocument doc) {
        Xml.Node* root = doc.get_root_node();
        if (root->name != "error_response")
            return null;
        
        Xml.Node* error_code = null;
        try {
            error_code = doc.get_named_child(root, "error_code");
        } catch (PublishingError err) {
            warning("Unable to parse error response for error code");
        }
        
        Xml.Node* error_msg = null;
        try {
            error_msg = doc.get_named_child(root, "error_msg");
        } catch (PublishingError err) {
            warning("Unable to parse error response for error message");
        }

        // 102 errors occur when the session key has become invalid -- the correct behavior in this
        // case is to log the user out
        if ((error_code != null) && (error_code->get_content() == "102")) {
            PublishingDialog shell = PublishingDialog.get_active_instance();
            Interactor interactor = (Interactor) shell.get_interactor();
            interactor.logout_user();
        }

        return "%s (error code %s)".printf(error_msg != null ? error_msg->get_content() : "(unknown)",
            error_code != null ? error_code->get_content() : "(unknown)");
    }

    public static string generate_signature(RESTArgument[] sorted_args, Session session) {
        string hash_string = "";
        foreach (RESTArgument arg in sorted_args)
            hash_string = hash_string + ("%s=%s".printf(arg.key, arg.value));

        return Checksum.compute_for_string(ChecksumType.MD5, (hash_string +
            session.get_session_secret()));
    }
}

private class UserInfoTransaction : Transaction {
    public UserInfoTransaction(Session session, string user_id) {
        base(session);

        add_argument("method", "users.getInfo");
        add_argument("uids", user_id);
        add_argument("fields", "name");
    }
}

private class AlbumsFetchTransaction : Transaction {
    public AlbumsFetchTransaction(Session session) {
        base(session);

        assert(session.is_authenticated());

        add_argument("method", "photos.getAlbums");
    }
}

private class AlbumCreationTransaction : Transaction {
    public AlbumCreationTransaction(Session session, string album_name) {
        base(session);

        assert(session.is_authenticated());

        add_argument("method", "photos.createAlbum");
        add_argument("name", album_name);
    }
}

private class UploadTransaction : PhotoUploadTransaction {
    public UploadTransaction(Session session, string aid, string source_file_path,
        Photo source_photo) {
        base(session, source_file_path, source_photo);

        add_argument("api_key", session.get_api_key());
        add_argument("session_key", session.get_session_key());
        add_argument("v", session.get_api_version());
        add_argument("method", "photos.upload");
        add_argument("aid", aid);
    }

    protected override void sign() {
        Session facebook_session = (Session) get_parent_session();
        add_argument("call_id", facebook_session.get_next_call_id());

        string sig = Transaction.generate_signature(get_sorted_arguments(),
            facebook_session);
       
        set_signature_key(Transaction.SIGNATURE_KEY);
        set_signature_value(sig);
    }
}

}

#endif

