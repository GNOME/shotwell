/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

namespace FacebookConnector {
// this should not be changed by anyone unless they know what they're doing
private const string API_KEY = "3afe0a1888bd340254b1587025f8d1a5";
private const int MAX_PHOTO_DIMENSION = 604;
private const string USER_AGENT = "Java/1.6.0_16";
private const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");
private const int MAX_RETRIES = 4;
private const string SERVICE_ERROR_MESSAGE = _("Publishing to Facebook can't continue because an error occurred.\n\nTo try publishing to another service, select one from the menu above.");
private const string SERVICE_WELCOME_MESSAGE = _("You are not currently logged in to Facebook.\n\nIf you don't yet have a Facebook account, you can create one during the login process.");
private const string RESTART_ERROR_MESSAGE = _("You have already logged in and out of Facebook during this Shotwell session.\nTo continue publishing to Facebook, quit and restart Shotwell, then try publishing again.");

class UploadPane : PublishingDialogPane {
    private Gtk.RadioButton use_existing_radio = null;
    private Gtk.RadioButton create_new_radio = null;
    private Gtk.ComboBox existing_albums_combo = null;
    private Gtk.Entry new_album_entry = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private Session host_session = null;
    private Gtk.Label how_to_label = null;

    public signal void logout();
    public signal void publish(string target_album);

    public UploadPane(Session creator_session) {
        host_session = creator_session;
        set_border_width(20);

        Gtk.SeparatorToolItem top_padding = new Gtk.SeparatorToolItem();
        top_padding.set_size_request(-1, 50);
        top_padding.set_draw(false);
        add(top_padding);

        // set up the "how to" label that tells the user how to use the pane
        Gtk.HBox how_to_label_layouter = new Gtk.HBox(false, 8);
        how_to_label = new Gtk.Label("");
        Gtk.SeparatorToolItem how_to_pusher = new Gtk.SeparatorToolItem();
        how_to_pusher.set_draw(false);
        how_to_label_layouter.add(how_to_label);
        how_to_label_layouter.add(how_to_pusher);
        how_to_pusher.set_size_request(100, -1);
        add(how_to_label_layouter);

        Gtk.VBox album_mode_layouter = new Gtk.VBox(false, 8);
        album_mode_layouter.set_border_width(44);
        use_existing_radio = new Gtk.RadioButton.with_label(null,
            _("Publish to an existing album:"));
        use_existing_radio.toggled += on_use_existing_toggled;
        create_new_radio = new Gtk.RadioButton.with_label(use_existing_radio.get_group(),
            _("Create a new album named:"));
        create_new_radio.toggled += on_create_new_toggled;

        Gtk.HBox use_existing_layouter = new Gtk.HBox(false, 8);
        use_existing_layouter.add(use_existing_radio);
        existing_albums_combo = new Gtk.ComboBox.text();

        use_existing_layouter.add(existing_albums_combo);

        Gtk.HBox create_new_layouter = new Gtk.HBox(false, 8);
        create_new_layouter.add(create_new_radio);
        new_album_entry = new Gtk.Entry();
        create_new_layouter.add(new_album_entry);
        new_album_entry.set_size_request(142, -1);

        publish_button = new Gtk.Button.with_label(_("Publish"));
        publish_button.clicked += on_publish_button_clicked;
        logout_button = new Gtk.Button.with_label(_("Logout"));
        logout_button.clicked += on_logout_button_clicked;
        Gtk.HBox buttons_layouter = new Gtk.HBox(false, 8);
        Gtk.SeparatorToolItem buttons_left_padding = new Gtk.SeparatorToolItem();
        buttons_left_padding.set_draw(false);
        Gtk.SeparatorToolItem buttons_right_padding = new Gtk.SeparatorToolItem();
        buttons_right_padding.set_draw(false);
        Gtk.SeparatorToolItem buttons_central_padding = new Gtk.SeparatorToolItem();
        buttons_central_padding.set_draw(false);
        buttons_layouter.add(buttons_left_padding);
        buttons_layouter.add(logout_button);
        buttons_layouter.add(buttons_central_padding);
        buttons_layouter.add(publish_button);
        buttons_layouter.add(buttons_right_padding);

        album_mode_layouter.add(use_existing_layouter);
        album_mode_layouter.add(create_new_layouter);

        add(album_mode_layouter);
        add(buttons_layouter);
        
        Gtk.SeparatorToolItem bottom_padding = new Gtk.SeparatorToolItem();
        bottom_padding.set_size_request(-1, 50);
        bottom_padding.set_draw(false);
        add(bottom_padding);
    }
    
    public override void run_interaction() throws PublishingError {
        how_to_label.set_text(_("You are logged in to Facebook as %s.\nWhere would you like to publish the selected photos?").printf(host_session.get_user_name()));

        Album[] albums = get_albums(host_session);

        bool got_default_album = false;
        int default_album_seq_num = 0;
        int seq_num = 0;
        foreach (Album album in albums) {
            if (album.name == "Profile Pictures") {
                continue;
            } else if (album.name == DEFAULT_ALBUM_NAME) {
                got_default_album = true;
                default_album_seq_num = seq_num;
            }
            existing_albums_combo.append_text(album.name);
            seq_num++;
        }

        if (got_default_album) {
            existing_albums_combo.set_active(default_album_seq_num);
        } else {
            existing_albums_combo.set_active(0);
        }
    
        // if the default album (i.e. "Shotwell Connect") is present, then we
        // present it to the user as the default upload destination by selecting
        // it in the albums combo box. if the default album is not present, then
        // we present it to the user by writing it as the name of the new album
        // to create in the "Create New Album" text entry box
        if (is_default_album_present(host_session)) {
            new_album_entry.set_sensitive(false);
        } else {
            create_new_radio.set_active(true);
            new_album_entry.set_text(DEFAULT_ALBUM_NAME);
            existing_albums_combo.set_sensitive(false);
        }
    }
   
    private void on_use_existing_toggled() {
        if (use_existing_radio.active) {
            existing_albums_combo.set_sensitive(true);
            new_album_entry.set_sensitive(false);
        }
    }
    
    private void on_create_new_toggled() {
        if (create_new_radio.active) {
            existing_albums_combo.set_sensitive(false);
            new_album_entry.set_sensitive(true);
            PublishingDialog.get_active_instance().set_focus(new_album_entry);
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
}

public struct Album {
    string name;
    string id;
    
    Album(string creator_name, string creator_id) {
        name = creator_name;
        id = creator_id;
    }
}

private Album[] get_albums(Session session) throws PublishingError {
    Album[] result = new Album[0];

    FacebookTransaction albums_transaction = (FacebookTransaction) session.create_transaction();
    albums_transaction.add_argument("method", "photos.getAlbums");

    albums_transaction.execute();

    RESTXmlDocument response_doc = RESTXmlDocument.parse_string(albums_transaction.get_response());

    Xml.Node* root = response_doc.get_root_node();

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

        if (name_val == null)
            throw new PublishingError.BAD_XML("can't get albums: XML document contains " +
                "an <album> entity without a <name> child");

        if (aid_val == null) 
            throw new PublishingError.BAD_XML("can't get albums: XML document contains " +
                "an <album> entity without an <aid> child");

        result += Album(name_val, aid_val);
    }
    
    if (result.length == 0)
        throw new PublishingError.BAD_XML("can't get albums: failed to get at least one " +
            "valid album");

    return result;
}

public bool is_default_album_present(Session session) throws PublishingError {
    Album[] albums = get_albums(session);
    
    foreach (Album album in albums) {
        if (album.name == DEFAULT_ALBUM_NAME)
            return true;
    }
    
    return false;
}

public string create_album(Session session, string album_name) throws PublishingError {
    FacebookTransaction creation_transaction = (FacebookTransaction) session.create_transaction();
    creation_transaction.add_argument("method", "photos.createAlbum");
    creation_transaction.add_argument("name", album_name);

    creation_transaction.execute();

    RESTXmlDocument response_doc =
        RESTXmlDocument.parse_string(creation_transaction.get_response());

    Xml.Node* root = response_doc.get_root_node();
    Xml.Node* aid_node = response_doc.get_named_child(root, "aid");

    return aid_node->get_content();
}

bool is_persistent_session_valid() {
    Config config = Config.get_instance();

    string session_key = config.get_facebook_session_key();
    string session_secret = config.get_facebook_session_secret();
    string uid = config.get_facebook_uid();
    string user_name = config.get_facebook_user_name();
   
    return ((session_key != null) && (session_secret != null) && (uid != null) &&
        (user_name != null));
}

void invalidate_persistent_session() {
    Config config = Config.get_instance();
    
    config.clear_facebook_session_key();
    config.clear_facebook_session_secret();
    config.clear_facebook_uid();
    config.clear_facebook_user_name();
}

public class LoginShell : PublishingDialogPane {
    private WebKit.WebView webview = null;
    private Gtk.ScrolledWindow webview_frame = null;
    private static bool is_cache_dirty = false;

    public signal void login_success(Session host_session);
    public signal void login_failure();
    public signal void login_error();

    public LoginShell() {
        set_size_request(476, 360);

        webview_frame = new Gtk.ScrolledWindow(null, null);
        webview_frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN);
        webview_frame.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        webview = new WebKit.WebView();
        webview.load_finished += on_page_load;
        webview.load_started += on_load_started;

        webview_frame.add(webview);
        add(webview_frame);
    }

    public static bool get_is_cache_dirty() {
        return is_cache_dirty;
    }
    
    public void load_login_page() {
        webview.open(get_login_url());
    }
    
    private string get_login_url() {
        return "http://www.facebook.com/login.php?api_key=%s&connect_display=popup&v=1.0&next=http://www.facebook.com/connect/login_success.html&cancel_url=http://www.facebook.com/connect/login_failure.html&fbconnect=true&return_session=true&req_perms=read_stream,publish_stream,offline_access,photo_upload".printf(FacebookConnector.API_KEY);
    }

    private void on_page_load(WebKit.WebFrame origin_frame) {
        webview.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.ARROW));

        string loaded_url = origin_frame.get_uri().dup();

        // strip parameters from the loaded url
        if (loaded_url.contains("?")) {
            string params = loaded_url.chr(-1, '?');
            loaded_url = loaded_url.replace(params, "");
        }

        // were we redirected to the facebook login success page?
        if (loaded_url.contains("login_success")) {
            try {
                is_cache_dirty = true;
                login_success(new Session.from_login_url(FacebookConnector.API_KEY,
                    origin_frame.get_uri()));
            } catch (PublishingError e) {
                login_error();
                return;
            }
        }

        // were we redirected to the login total failure page?
        if (loaded_url.contains("login_failure"))
            login_failure();
    }
    
    private void on_load_started(WebKit.WebFrame frame) {
        webview.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
    }
}

public class Session : RESTSession {
    private const string API_VERSION = "1.0";
    private const string ENDPOINT_URL = "http://api.facebook.com/restserver.php";

    private string session_key = null;
    private string uid = null;
    private string secret = null;
    private string api_key = null;
    private Soup.Session session_connection = null;
    private string user_name = null;
    
    public Session(string creator_session_key, string creator_secret, string creator_uid,
        string creator_api_key, string creator_user_name) {
        base(ENDPOINT_URL);

        session_key = creator_session_key;
        secret = creator_secret;
        uid = creator_uid;
        api_key = creator_api_key;
        user_name = creator_user_name;

        session_connection = new Soup.SessionSync();
        session_connection.user_agent = USER_AGENT;
    }
    
    public Session.from_login_url(string creator_api_key, string good_login_uri)
        throws PublishingError {
        base(ENDPOINT_URL);
        // the raw uri is percent-encoded, so decode it
        string decoded_uri = Soup.URI.decode(good_login_uri);

        // locate the session object description string within the decoded uri
        string session_desc = decoded_uri.str("session={");
        if (session_desc == null)
            throw new PublishingError.COMMUNICATION("server redirect URL contained no " +
                "session description");

        // remove any trailing parameters from the session description string
        string trailing_params = session_desc.chr(-1, '&');
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
            throw new PublishingError.COMMUNICATION("session description object has " +
                "no session key");
        if (uid == null)
            throw new PublishingError.COMMUNICATION("session description object has no user id");
        if (secret == null)
            throw new PublishingError.COMMUNICATION("session description object has no session secret");

        api_key = creator_api_key;

        session_connection = new Soup.SessionSync();
        session_connection.user_agent = USER_AGENT;
    }

    public string to_string() {
        return "Session { api_key: %s; session_key: %s; uid: %s; secret: %s; }.\n".printf(
            api_key, session_key, uid, secret);
    }

    public string get_api_key() {
        return api_key;
    }

    public string get_session_key() {
        return session_key;
    }

    public string get_user_id() {
        return uid;
    }

    public string get_session_secret() {
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
    
    public Soup.Session get_connection() {
        return session_connection;
    }

    public string get_user_name() throws PublishingError {
        if (user_name == null) {
            FacebookTransaction user_info_transaction = (FacebookTransaction) create_transaction();
            user_info_transaction.add_argument("method", "users.getInfo");
            user_info_transaction.add_argument("uids", get_user_id());
            user_info_transaction.add_argument("fields", "name");
            
            user_info_transaction.execute();
        
            RESTXmlDocument response_doc =
                RESTXmlDocument.parse_string(user_info_transaction.get_response());

            Xml.Node* root_node = response_doc.get_root_node();
            Xml.Node* user_node = response_doc.get_named_child(root_node, "user");
            Xml.Node* name_node = response_doc.get_named_child(user_node, "name");

            user_name = name_node->get_content();
        }

        return user_name;
    }

    public override RESTTransaction create_transaction() {
        FacebookTransaction result = new FacebookTransaction(this);

        result.add_argument("api_key", get_api_key());
        result.add_argument("session_key", get_session_key());
        result.add_argument("v", get_api_version());

        return result;
    }
}

public class FacebookTransaction : RESTTransaction {
    public const string SIGNATURE_KEY = "sig";

    public FacebookTransaction(FacebookConnector.Session creator_session) {
        base(creator_session);
    }

    protected override void sign() {
        FacebookConnector.Session facebook_session =
            (FacebookConnector.Session) get_parent_session();
        add_argument("call_id", facebook_session.get_next_call_id());

        string sig = generate_signature(get_sorted_arguments(), facebook_session);
       
        set_signature_key(SIGNATURE_KEY);
        set_signature_value(sig);
    }

    public static string generate_signature(RESTArgument[] sorted_args, Session session) {
        string hash_string = "";
        foreach (RESTArgument arg in sorted_args)
            hash_string = hash_string + ("%s=%s".printf(arg.key, arg.value));

        return Checksum.compute_for_string(ChecksumType.MD5, (hash_string +
            session.get_session_secret()));
    }
}

public class FacebookUploadTransaction : PhotoUploadTransaction {
    public FacebookUploadTransaction(FacebookConnector.Session creator_session,
        string creator_target_album, string creator_source_file,
        TransformablePhoto creator_source_photo) {
        base(creator_session, creator_source_file, creator_source_photo);

        add_argument("api_key", creator_session.get_api_key());
        add_argument("session_key", creator_session.get_session_key());
        add_argument("v", creator_session.get_api_version());
        add_argument("method", "photos.upload");
        add_argument("aid", creator_target_album);
    }

    protected override void sign() {
        FacebookConnector.Session facebook_session =
            (FacebookConnector.Session) get_parent_session();
        add_argument("call_id", facebook_session.get_next_call_id());

        string sig = FacebookTransaction.generate_signature(get_sorted_arguments(),
            facebook_session);
       
        set_signature_key(FacebookTransaction.SIGNATURE_KEY);
        set_signature_value(sig);
    }
}

public class Interactor : ServiceInteractor {
    private const string TEMP_FILE_PREFIX = "publishing-";
    private LoginShell login_shell = null;

    private Session session;
    private bool user_cancelled = false;

    public Interactor(PublishingDialog host) {
        base(host);
    }

    public override void start_interaction() throws PublishingError {
        get_host().set_standard_window_mode();

        if (is_persistent_session_valid()) {
            Config config = Config.get_instance();
            session = new FacebookConnector.Session(config.get_facebook_session_key(),
                config.get_facebook_session_secret(), config.get_facebook_uid(),
                FacebookConnector.API_KEY, config.get_facebook_user_name());

            UploadPane upload_pane = new UploadPane(session);
            upload_pane.logout += on_logout;
            upload_pane.publish += on_publish;
            get_host().install_pane(upload_pane);
            get_host().set_cancel_button_mode();

            try {
                upload_pane.run_interaction();
            } catch (PublishingError e) {
                get_host().on_error(SERVICE_ERROR_MESSAGE);
                return;
            }
        } else {
            if (FacebookConnector.LoginShell.get_is_cache_dirty()) {
                get_host().on_error(RESTART_ERROR_MESSAGE);
            } else {
                LoginWelcomePane not_logged_in_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
                not_logged_in_pane.login_requested += on_login_requested;
                get_host().install_pane(not_logged_in_pane);
                get_host().set_cancel_button_mode();
            }
        }
    }
    
    public override void cancel_interaction() {
        user_cancelled = true;
    }

    public override string get_service_error_message() {
        return SERVICE_ERROR_MESSAGE;
    }

    private void on_logout() {
        FacebookConnector.invalidate_persistent_session();

        if (FacebookConnector.LoginShell.get_is_cache_dirty()) {
            get_host().on_error(RESTART_ERROR_MESSAGE);
        } else {
            LoginWelcomePane not_logged_in_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
            not_logged_in_pane.login_requested += on_login_requested;
            get_host().install_pane(not_logged_in_pane);
            get_host().set_cancel_button_mode();
        }
    }
    
    private void on_publish(string target_album_name) {
        get_host().lock_service();

        FacebookUploadActionPane action_pane = new FacebookUploadActionPane(get_host(), session,
            target_album_name);
        get_host().install_pane(action_pane);
        get_host().set_cancel_button_mode();

        action_pane.upload();

        if (user_cancelled)
            return;
        
        get_host().unlock_service();
        get_host().on_success();

        action_pane = null;
    }

    private void on_login_requested() {
        if (!get_is_connection_alive()) {
            get_host().on_error(SERVICE_ERROR_MESSAGE);
            return;
        }

        login_shell = new LoginShell();
        login_shell.login_failure += on_login_failed;
        login_shell.login_success += on_login_success;
        login_shell.login_error += on_login_error;

        get_host().install_pane(login_shell);
        get_host().set_cancel_button_mode();

        login_shell.load_login_page();
    }

    private void on_login_failed() {
        LoginWelcomePane not_logged_in_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
        not_logged_in_pane.login_requested += on_login_requested;
        get_host().install_pane(not_logged_in_pane);
        get_host().set_cancel_button_mode();
    }

    private void on_login_error() {
        get_host().on_error(SERVICE_ERROR_MESSAGE);
    }

    private void on_login_success(Session login_session) {
        session = login_session;
        // retrieving the username associated with a session requires a network round-trip, so
        // PublishingError.COMMUNICATION errors are possible
        string username = null;
        try {
            username = login_session.get_user_name();
        } catch (PublishingError e) {
            get_host().on_error(SERVICE_ERROR_MESSAGE);
            return;
        }

        Config config = Config.get_instance();
        config.set_facebook_session_key(login_session.get_session_key());
        config.set_facebook_session_secret(login_session.get_session_secret());
        config.set_facebook_uid(login_session.get_user_id());  
        config.set_facebook_user_name(username);

        UploadPane upload_pane = new UploadPane(login_session);
        upload_pane.logout += on_logout;
        upload_pane.publish += on_publish;

        get_host().install_pane(upload_pane);
        get_host().set_cancel_button_mode();

        try {
            upload_pane.run_interaction();
        } catch (PublishingError e) {
            get_host().on_error(SERVICE_ERROR_MESSAGE);
        }
    }
}

class FacebookUploadActionPane : UploadActionPane {
    private Session session;
    private string target_album_name;
    private string aid = null;
    private bool aid_fetch_failed = false;
    
    public FacebookUploadActionPane(PublishingDialog host, Session session,
        string target_album_name) {
        base(host);

        this.target_album_name = target_album_name;
        this.session = session;
    }

    protected override void prepare_file(UploadActionPane.TemporaryFileDescriptor file) {
        try {
            file.source_photo.export(file.temp_file, MAX_PHOTO_DIMENSION,
                ScaleConstraint.DIMENSIONS, Jpeg.Quality.MAXIMUM);
        } catch (Error e) {
            error("FacebookUploadPane: can't create temporary files");
        }
    }

    protected override void upload_file(UploadActionPane.TemporaryFileDescriptor file) {
        if (aid == null) {
            aid_fetch_failed = false;
            aid = fetch_aid();

            if (aid_fetch_failed)
                return;
        }

        FacebookUploadTransaction upload_transaction = new FacebookUploadTransaction(session,
            aid, file.temp_file.get_path(), file.source_photo);
        upload_transaction.chunk_transmitted += on_chunk_transmitted;
        upload_transaction.execute();
        upload_transaction.chunk_transmitted -= on_chunk_transmitted;
    }

    private string fetch_aid() {
        Album[] albums = null;
        try {
            albums = get_albums(session);
        } catch (PublishingError e) {
            get_host().unlock_service();
            get_host().on_error(SERVICE_ERROR_MESSAGE);

            aid_fetch_failed = true;
            return "";
        }

        string target_aid = null;
        foreach (Album album in albums) {
            if (album.name == target_album_name)
                target_aid = album.id;
        }
        if (target_aid == null) {
            try {
                target_aid = create_album(session, target_album_name);
            } catch (PublishingError e) {
                get_host().unlock_service();
                get_host().on_error(SERVICE_ERROR_MESSAGE);

                aid_fetch_failed = true;
                return "";
            }
        }

        return target_aid;
    }
}


bool get_is_connection_alive() {
    Soup.Session test_connection = new Soup.SessionSync();
    test_connection.user_agent = USER_AGENT;
    Soup.Message test_req = new Soup.Message("GET", "http://api.facebook.com/restserver.php");
    test_connection.send_message(test_req);
    return (test_req.response_body.data != null);
}

}

#endif

