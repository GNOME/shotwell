/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Publishing.Facebook {
// global parameters for the Facebook publishing plugin -- don't touch these (unless you really,
// truly, deep-down know what you're doing)
public const string SERVICE_NAME = "facebook";
internal const string USER_VISIBLE_NAME = "Facebook";
internal const string API_KEY = "3afe0a1888bd340254b1587025f8d1a5";
internal const string SIGNATURE_KEY = "sig";
internal const int MAX_PHOTO_DIMENSION = 720;
internal const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");
internal const string PHOTO_ENDPOINT_URL = "http://api.facebook.com/restserver.php";
internal const string VIDEO_ENDPOINT_URL = "http://api-video.facebook.com/restserver.php";
internal const string SERVICE_WELCOME_MESSAGE =
    _("You are not currently logged into Facebook.\n\nIf you don't yet have a Facebook account, you can create one during the login process. During login, Shotwell Connect may ask you for permission to upload photos and publish to your feed. These permissions are required for Shotwell Connect to function.");
internal const string RESTART_ERROR_MESSAGE =
    _("You have already logged in and out of Facebook during this Shotwell session.\nTo continue publishing to Facebook, quit and restart Shotwell, then try publishing again.");
// as of mid-November 2010, the privacy the simple string "SELF" is no longer a valid
// privacy value; "SELF" must be simulated by a "CUSTOM" setting; see the discussion
// http://forum.developers.facebook.net/viewtopic.php?pid=289287
internal const string PRIVACY_OBJECT_JUST_ME = "{ 'value' : 'CUSTOM', 'friends' : 'SELF' }";
internal const string PRIVACY_OBJECT_ALL_FRIENDS = "{ 'value' : 'ALL_FRIENDS' }";
internal const string PRIVACY_OBJECT_FRIENDS_OF_FRIENDS = "{ 'value' : 'FRIENDS_OF_FRIENDS' }";
internal const string PRIVACY_OBJECT_EVERYONE = "{ 'value' : 'EVERYONE' }";
internal const string API_VERSION = "1.0";
internal const string USER_AGENT = "Java/1.6.0_16";

internal struct FacebookAlbum {
    string name;
    string id;
    
    FacebookAlbum(string creator_name, string creator_id) {
        name = creator_name;
        id = creator_id;
    }
}

internal enum FacebookHttpMethod {
    GET,
    POST,
    PUT;

    public string to_string() {
        switch (this) {
            case FacebookHttpMethod.GET:
                return "GET";

            case FacebookHttpMethod.PUT:
                return "PUT";

            case FacebookHttpMethod.POST:
                return "POST";

            default:
                error("unrecognized HTTP method enumeration value");
        }
    }

    public static FacebookHttpMethod from_string(string str) {
        if (str == "GET") {
            return FacebookHttpMethod.GET;
        } else if (str == "PUT") {
            return FacebookHttpMethod.PUT;
        } else if (str == "POST") {
            return FacebookHttpMethod.POST;
        } else {
            error("unrecognized HTTP method name: %s", str);
        }
    }
}

public class FacebookPublisher : Spit.Publishing.Publisher, GLib.Object {
    private const int NO_ALBUM = -1;
    
    private string privacy_setting = PRIVACY_OBJECT_JUST_ME;
    private FacebookAlbum[] albums = null;
    private int publish_to_album = NO_ALBUM;
    private weak Spit.Publishing.PublishingInteractor interactor = null;
    private FacebookRESTSession session = null;
    private WebAuthenticationPane web_auth_pane = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;

    public FacebookPublisher() {
        debug("FacebookPublisher instantiated.");
    }
    
    private bool is_running() {
        return (interactor != null);
    }
    
    private int lookup_album(string name) {
        for (int i = 0; i < albums.length; i++) {
            if (albums[i].name == name)
                return i;
        }
        return NO_ALBUM;
    }
    
    private bool is_persistent_session_valid() {
        string? session_key = get_persistent_session_key();
        string? session_secret = get_persistent_session_secret();
        string? uid = get_persistent_uid();
        string? user_name = get_persistent_user_name();
       
        bool valid = ((session_key != null) && (session_secret != null) && (uid != null) &&
            (user_name != null));

        if (valid)
            debug("existing Facebook session for user = '%s' found in configuration database; using it.", user_name);
        else
            debug("no persisted Facebook session exists.");

        return valid;
    }
    
    private string? get_persistent_session_key() {
        return interactor.get_config_string("session_key", null);
    }
    
    private string? get_persistent_session_secret() {
        return interactor.get_config_string("session_secret", null);
    }
    
    private string? get_persistent_uid() {
        return interactor.get_config_string("uid", null);
    }
    
    private string? get_persistent_user_name() {
        return interactor.get_config_string("user_name", null);
    }
    
    private void set_persistent_session_key(string session_key) {
        interactor.set_config_string("session_key", session_key);
    }
    
    private void set_persistent_session_secret(string session_secret) {
        interactor.set_config_string("session_secret", session_secret);
    }
    
    private void set_persistent_uid(string uid) {
        interactor.set_config_string("uid", uid);
    }
    
    private void set_persistent_user_name(string user_name) {
        interactor.set_config_string("user_name", user_name);
    }

    private void invalidate_persistent_session() {
        debug("invalidating persisted Facebook session.");

        set_persistent_session_key("");
        set_persistent_session_secret("");
        set_persistent_uid("");
        set_persistent_user_name("");
    }

    private void do_show_service_welcome_pane() {
        debug("ACTION: showing service welcome pane.");

        interactor.install_welcome_pane(SERVICE_WELCOME_MESSAGE, on_login_clicked);
    }

    private void do_fetch_album_descriptions() {
        debug("ACTION: fetching album descriptions from remote endpoint.");
        interactor.set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode.CANCEL);
        interactor.set_service_locked(true);
        
        interactor.install_account_fetch_wait_pane();
        
        FacebookRESTTransaction albums_transaction = new FacebookAlbumsFetchTransaction(session);
        albums_transaction.completed.connect(on_fetch_album_descriptions_completed);
        albums_transaction.network_error.connect(on_fetch_album_descriptions_error);

        try {
            albums_transaction.execute();
        } catch (Spit.Publishing.PublishingError err) {
            warning("PublishingError: %s.", err.message);
    
            // only post an error if we're running; errors tend to come in groups, so it's possible
            // another error has already posted and caused us to stop        
            if (is_running())
                interactor.post_error(err);
        }
    }

    private void do_extract_albums_from_xml(string xml) {
        debug("ACTION: extracting album info from xml response '%s'.", xml);

        FacebookAlbum[] extracted = new FacebookAlbum[0];

        try {
            FacebookRESTXmlDocument response_doc = FacebookRESTXmlDocument.parse_string(xml);

            Xml.Node* root = response_doc.get_root_node();

            if (root->name != "photos_getAlbums_response")
               throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Document root node has unexpected name '%s'",
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
                    if (lookup_album(name_val) == NO_ALBUM)
                        extracted += FacebookAlbum(name_val, aid_val);

            }
        } catch (Spit.Publishing.PublishingError err) {
            warning("PublishingError: %s", err.message);

            // only post an error if we're running; errors tend to come in groups, so it's possible
            // another error has already posted and caused us to stop
            if (is_running())
                interactor.post_error(err);

            return;
        }

        albums = extracted;

        on_albums_extracted();
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: showing publishing options pane.");
        interactor.set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode.CANCEL);
        interactor.set_service_locked(false);

        PublishingOptionsPane publishing_options_pane = new PublishingOptionsPane(
            session.get_user_name(), albums, interactor.get_publishable_media_type());
        publishing_options_pane.logout.connect(on_publishing_options_pane_logout);
        publishing_options_pane.publish.connect(on_publishing_options_pane_publish);
        interactor.install_dialog_pane(publishing_options_pane);
    }
    
    private void do_logout() {
        debug("ACTION: clearing persistent session information and restaring interaction.");
        
        invalidate_persistent_session();

        Spit.Publishing.PublishingInteractor restart_with_interactor = interactor;
        stop();
        start(restart_with_interactor);
    }
    
    private void do_hosted_web_authentication() {
        debug("ACTION: doing hosted web authentication.");

        interactor.set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode.CANCEL);
        interactor.set_service_locked(false);

        web_auth_pane = new WebAuthenticationPane();
        web_auth_pane.login_succeeded.connect(on_web_auth_pane_login_succeeded);
        web_auth_pane.login_failed.connect(on_web_auth_pane_login_failed);
        
        interactor.install_dialog_pane(web_auth_pane);
    }

    private void do_authenticate_session(string success_url) {
        debug("ACTION: preparing to extract session information encoded in url = '%s'",
            success_url);

        interactor.set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode.CANCEL);
        interactor.set_service_locked(true);
        interactor.install_account_fetch_wait_pane();

        session.authenticated.connect(on_session_authenticated);
        session.authentication_failed.connect(on_session_authentication_failed);

        try {
            session.authenticate_from_uri(success_url);
        } catch (Spit.Publishing.PublishingError err) {
            // only post an error if we're running; errors tend to come in groups, so it's possible
            // another error has already posted and caused us to stop
            if (is_running())
                interactor.post_error(err);
        }
    }

    private void do_save_session_information() {
        debug("ACTION: saving session information to configuration system.");
        
        set_persistent_session_key(session.get_session_key());
        set_persistent_session_secret(session.get_session_secret());
        set_persistent_uid(session.get_user_id());
        set_persistent_user_name(session.get_user_name());
    }

    private void do_upload() {
        assert(publish_to_album != NO_ALBUM);
        debug("ACTION: uploading photos to album '%s'", albums[publish_to_album].name);

        interactor.set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode.CANCEL);
        interactor.set_service_locked(true);

        progress_reporter = interactor.install_progress_pane();

        Spit.Publishing.Publishable[] publishables = interactor.get_publishables();
        FacebookUploader uploader = new FacebookUploader(session, albums[publish_to_album].id,
            privacy_setting, publishables);
        uploader.status_updated.connect(on_upload_status_updated);
        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);

        uploader.upload();
    }

    private void do_create_album(string album_name) {
        debug("ACTION: creating new photo album with name '%s'", album_name);
        albums += FacebookAlbum(album_name, "");

        interactor.set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode.CANCEL);
        interactor.set_service_locked(true);

        interactor.install_static_message_pane(_("Creating album..."));

        FacebookRESTTransaction create_txn = new FacebookCreateAlbumTransaction(session,
            album_name, privacy_setting);
        create_txn.completed.connect(on_create_album_txn_completed);
        create_txn.network_error.connect(on_create_album_txn_error);

        try {
            create_txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            // only post an error if we're running; errors tend to come in groups, so it's possible
            // another error has already posted and caused us to stop
            if (is_running())
                interactor.post_error(err);
        }
    }

    private void do_extract_aid_from_xml(string xml) {
        debug("ACTION: extracting album id from newly created album xml description '%s'.", xml);

        try {
            FacebookRESTXmlDocument response_doc = FacebookRESTXmlDocument.parse_string(xml);

            Xml.Node* root = response_doc.get_root_node();
            Xml.Node* aid_node = response_doc.get_named_child(root, "aid");

            assert(albums[albums.length - 1].id == "");

            publish_to_album = albums.length - 1;
            albums[publish_to_album].id = aid_node->get_content();
        } catch (Spit.Publishing.PublishingError err) {
            // only post an error if we're running; errors tend to come in groups, so it's possible
            // another error has already posted and caused us to stop
            if (is_running())
                interactor.post_error(err);

            return;
        }

        on_album_name_extracted();
    }
    
    private void do_show_success_pane() {
        debug("ACTION: showing success pane.");

        interactor.set_service_locked(false);
        interactor.set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode.CLOSE);

        interactor.install_success_pane(interactor.get_publishable_media_type());
    }
    
    private void on_login_clicked() {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Login' on welcome pane.");

        do_hosted_web_authentication();
    }
    
    private void on_web_auth_pane_login_succeeded(string success_url) {
        if (!is_running())
            return;

        debug("EVENT: hosted web login succeeded.");

        do_authenticate_session(success_url);
    }

    private void on_web_auth_pane_login_failed() {
        if (!is_running())
            return;

        debug("EVENT: hosted web login failed.");

        // In this case, "failed" doesn't mean that the user didn't enter the right username and
        // password -- Facebook handles that case inside the Facebook Connect web control. Instead,
        // it means that no session was initiated in response to our login request. The only
        // way this happens is if the user clicks the "Cancel" button that appears inside
        // the web control. In this case, the correct behavior is to return the user to the
        // service welcome pane so that they can start the web interaction again.
        do_show_service_welcome_pane();
    }
    
    private void on_session_authenticated() {
        if (!is_running())
            return;

        assert(session.is_authenticated());
        debug("EVENT: an authenticated session has become available.");

        do_save_session_information();
        do_fetch_album_descriptions();
    }

    private void on_session_authentication_failed(Spit.Publishing.PublishingError err) {
        if (!is_running())
            return;

        debug("EVENT: session authentication failed.");

        interactor.post_error(err);
    }

    private void on_fetch_album_descriptions_completed(FacebookRESTTransaction txn) {
        if (!is_running())
            return;

        debug("EVENT: album descriptions fetch transaction completed; response = '%s'.", txn.get_response());
        txn.completed.disconnect(on_fetch_album_descriptions_completed);
        txn.network_error.disconnect(on_fetch_album_descriptions_error);

        do_extract_albums_from_xml(txn.get_response());
    }

    private void on_fetch_album_descriptions_error(FacebookRESTTransaction bad_txn,
        Spit.Publishing.PublishingError err) {
        if (!is_running())
            return;

        debug("EVENT: album description fetch attempt generated an error.");
        bad_txn.completed.disconnect(on_fetch_album_descriptions_completed);
        bad_txn.network_error.disconnect(on_fetch_album_descriptions_error);

        interactor.post_error(err);
    }

    private void on_albums_extracted() {
        if (!is_running())
            return;

        debug("EVENT: album descriptions successfully extracted from XML response.");

        do_show_publishing_options_pane();
    }

    public void on_publishing_options_pane_logout() {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Logout' in publishing options pane.");
        
        do_logout();
    }

    public void on_publishing_options_pane_publish(string target_album, string privacy_setting) {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Publish' in publishing options pane.");
        
        this.privacy_setting = privacy_setting;

        if (lookup_album(target_album) != NO_ALBUM) {
            publish_to_album = lookup_album(target_album);
            do_upload();
        } else {
            do_create_album(target_album);
        }
    }

    private void on_create_album_txn_completed(FacebookRESTTransaction txn) {
        if (!is_running())
            return;

        debug("EVENT: create album transaction completed on remote endpoint.");

        txn.completed.disconnect(on_create_album_txn_completed);
        txn.network_error.disconnect(on_create_album_txn_error);

        do_extract_aid_from_xml(txn.get_response());
    }

    private void on_create_album_txn_error(FacebookRESTTransaction bad_txn, Spit.Publishing.PublishingError err) {
        if (!is_running())
            return;
            
        debug("EVENT: create album transaction generated a publishing error: %s", err.message);

        bad_txn.completed.disconnect(on_create_album_txn_completed);
        bad_txn.network_error.disconnect(on_create_album_txn_error);

        interactor.post_error(err);
    }

    private void on_album_name_extracted() {
        if (!is_running())
            return;

        debug("EVENT: successfully extracted aid.");

        do_upload();
    }

    private void on_upload_status_updated(string status_text, double completed_fraction) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);

        progress_reporter(status_text, completed_fraction);
    }

    private void on_upload_complete(FacebookUploader uploader, int num_published) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload complete; %d items published.", num_published);

        uploader.status_updated.disconnect(on_upload_status_updated);
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        do_show_success_pane();
    }

    private void on_upload_error(FacebookUploader uploader, Spit.Publishing.PublishingError err) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload error = '%s'.", err.message);

        uploader.status_updated.disconnect(on_upload_status_updated);
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        interactor.post_error(err);
    }

    public string get_service_name() {
        return SERVICE_NAME;
    }
    
    public string get_user_visible_name() {
        return USER_VISIBLE_NAME;
    }
    
    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return Spit.Publishing.Publisher.MediaType.PHOTO |
            Spit.Publishing.Publisher.MediaType.VIDEO;
    }
    
    public void start(Spit.Publishing.PublishingInteractor interactor) {
        if (is_running())
            return;

        debug("FacebookPublisher: starting interaction.");

        this.interactor = interactor;
        
        // reset all publishing parameters to their default values -- in case this start is
        // actually a restart
        privacy_setting = PRIVACY_OBJECT_JUST_ME;
        albums = null;
        publish_to_album = NO_ALBUM;

        // determine whether a user is logged in; if so, then show the publishing options pane
        // for that user; otherwise, show the welcome pane
        if (is_persistent_session_valid()) {
            // if valid session information has been saved in the configuration system, build
            // a Session object and pre-authenticate it with the saved information, then simulate an
            // on_session_authenticated event to drive the rest of the interaction
            session = new FacebookRESTSession(PHOTO_ENDPOINT_URL, USER_AGENT);
            session.authenticate_with_parameters(get_persistent_session_key(), get_persistent_uid(),
                get_persistent_session_secret(), get_persistent_user_name());
            on_session_authenticated();
        } else {
            if (WebAuthenticationPane.is_cache_dirty()) {
                interactor.set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode.CANCEL);
                interactor.set_service_locked(false);
                interactor.install_static_message_pane(RESTART_ERROR_MESSAGE);
            } else {
                session = new FacebookRESTSession(PHOTO_ENDPOINT_URL, USER_AGENT);
                do_show_service_welcome_pane();
            }
        }
    }
    
    public void stop() {
        debug("FacebookPublisher: stop( ) invoked.");

        interactor = null;
        session.stop_transactions();
    }
}

internal class FacebookRESTSession {
    private string endpoint_url = null;
    private Soup.Session soup_session = null;
    private bool transactions_stopped = false;
    private string? session_key = null;
    private string? uid = null;
    private string? secret = null;
    private string? user_name = null;
    
    public signal void wire_message_unqueued(Soup.Message message);
    public signal void authenticated();
    public signal void authentication_failed(Spit.Publishing.PublishingError err);

    public FacebookRESTSession(string creator_endpoint_url, string? user_agent = null) {
        endpoint_url = creator_endpoint_url;
        soup_session = new Soup.SessionAsync();
        if (user_agent != null)
            soup_session.user_agent = user_agent;
    }
    
    private void notify_wire_message_unqueued(Soup.Message message) {
        wire_message_unqueued(message);
    }
    
    private void notify_authenticated() {
        authenticated();
    }
    
    private void notify_authentication_failed(Spit.Publishing.PublishingError err) {
        authentication_failed(err);
    }

    private void on_user_info_txn_completed(FacebookRESTTransaction txn) {
        txn.completed.disconnect(on_user_info_txn_completed);
        txn.network_error.disconnect(on_user_info_txn_error);

        try {
            FacebookRESTXmlDocument response_doc = FacebookRESTXmlDocument.parse_string(txn.get_response());

            Xml.Node* root_node = response_doc.get_root_node();
            Xml.Node* user_node = response_doc.get_named_child(root_node, "user");
            Xml.Node* name_node = response_doc.get_named_child(user_node, "name");

            user_name = name_node->get_content();
        } catch (Spit.Publishing.PublishingError err) {
            notify_authentication_failed(err);
            return;
        }

        notify_authenticated();
    }

    private void on_user_info_txn_error(FacebookRESTTransaction txn, Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_user_info_txn_completed);
        txn.network_error.disconnect(on_user_info_txn_error);

        notify_authentication_failed(err);
    }

    public bool is_authenticated() {
        return (session_key != null && uid != null && secret != null && user_name != null);
    }
    
    public void authenticate_with_parameters(string session_key, string uid, string secret,
        string user_name) {
        this.session_key = session_key;
        this.uid = uid;
        this.secret = secret;
        this.user_name = user_name;
    }
    
    public void authenticate_from_uri(string good_login_uri) throws Spit.Publishing.PublishingError {
        // the raw uri is percent-encoded, so decode it
        string decoded_uri = Soup.URI.decode(good_login_uri);

        // locate the session object description string within the decoded uri
        string session_desc = decoded_uri.str("session={");
        if (session_desc == null)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Server redirect URL contained no session description");

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
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Session description object has no session key");
        if (uid == null)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Session description object has no user ID");
        if (secret == null)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Session description object has no session secret");

        FacebookUserInfoTransaction user_info_txn = new FacebookUserInfoTransaction(this, get_user_id());
        user_info_txn.completed.connect(on_user_info_txn_completed);
        user_info_txn.network_error.connect(on_user_info_txn_error);
        user_info_txn.execute();
    }

    public string get_endpoint_url() {
        return endpoint_url;
    }
  
    public void stop_transactions() {
        transactions_stopped = true;
        soup_session.abort();
    }
    
    public bool are_transactions_stopped() {
        return transactions_stopped;
    }

    public string get_api_key() {
        return API_KEY;
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
    
    public void send_wire_message(Soup.Message message) {
        if (are_transactions_stopped())
            return;

        soup_session.request_unqueued.connect(notify_wire_message_unqueued);
        soup_session.send_message(message);
        
        soup_session.request_unqueued.disconnect(notify_wire_message_unqueued);
    }
}

internal struct FacebookRESTArgument {
    public string key;
    public string value;

    public FacebookRESTArgument(string creator_key, string creator_val) {
        key = creator_key;
        value = creator_val;
    }

    public static int compare(void* p1, void* p2) {
        FacebookRESTArgument* arg1 = (FacebookRESTArgument*) p1;
        FacebookRESTArgument* arg2 = (FacebookRESTArgument*) p2;

        return strcmp(arg1->key, arg2->key);
    }
}

internal class FacebookRESTTransaction {
    private FacebookRESTArgument[] arguments;
    private string signature_value = null;
    private bool is_executed = false;
    private weak FacebookRESTSession parent_session = null;
    private Soup.Message message = null;
    private int bytes_written = 0;
    private Spit.Publishing.PublishingError? err = null;
    
    public signal void chunk_transmitted(int bytes_written_so_far, int total_bytes);
    public signal void network_error(Spit.Publishing.PublishingError err);
    public signal void completed();
    
    public FacebookRESTTransaction(FacebookRESTSession session, FacebookHttpMethod method = FacebookHttpMethod.POST) {
        parent_session = session;
        message = new Soup.Message(method.to_string(), parent_session.get_endpoint_url());
        message.wrote_body_data.connect(on_wrote_body_data);
    }

    public FacebookRESTTransaction.with_endpoint_url(FacebookRESTSession session, string endpoint_url,
        FacebookHttpMethod method = FacebookHttpMethod.POST) {
        parent_session = session;
        message = new Soup.Message(method.to_string(), endpoint_url);
    }

    private void on_wrote_body_data(Soup.Buffer written_data) {
        bytes_written += (int) written_data.length;
        chunk_transmitted(bytes_written, (int) message.request_body.length);
    }

    private void on_message_unqueued(Soup.Message message) {
        debug("FacebookRESTTransaction.on_message_unqueued( ).");
        if (this.message != message)
            return;
        
        try {
            check_response(message);
        } catch (Spit.Publishing.PublishingError err) {
            warning("Publishing error: %s", err.message);
            this.err = err;
        }
    }

    public void check_response(Soup.Message message) throws Spit.Publishing.PublishingError {
        switch (message.status_code) {
            case Soup.KnownStatusCode.OK:
            case Soup.KnownStatusCode.CREATED: // HTTP code 201 (CREATED) signals that a new
                                               // resource was created in response to a PUT or POST
            break;
            
            case Soup.KnownStatusCode.CANT_RESOLVE:
            case Soup.KnownStatusCode.CANT_RESOLVE_PROXY:
                throw new Spit.Publishing.PublishingError.NO_ANSWER("Unable to resolve %s (error code %u)",
                    get_endpoint_url(), message.status_code);
            
            case Soup.KnownStatusCode.CANT_CONNECT:
            case Soup.KnownStatusCode.CANT_CONNECT_PROXY:
                throw new Spit.Publishing.PublishingError.NO_ANSWER("Unable to connect to %s (error code %u)",
                    get_endpoint_url(), message.status_code);
            
            default:
                // status codes below 100 are used by Soup, 100 and above are defined HTTP codes
                if (message.status_code >= 100) {
                    throw new Spit.Publishing.PublishingError.NO_ANSWER("Service %s returned HTTP status code %u %s",
                        get_endpoint_url(), message.status_code, message.reason_phrase);
                } else {
                    throw new Spit.Publishing.PublishingError.NO_ANSWER("Failure communicating with %s (error code %u)",
                        get_endpoint_url(), message.status_code);
                }
        }
        
        // All valid communication with Facebook involves body data in the response
        if (message.response_body.data == null || message.response_body.data.length == 0)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("No response data from %s",
                get_endpoint_url());
    }

    protected FacebookRESTArgument[] get_arguments() {
        return arguments;
    }

    protected void set_message(Soup.Message message) {
        this.message = message;
    }
    
    protected FacebookRESTArgument[] get_sorted_arguments() {
        FacebookRESTArgument[] sorted_array = new FacebookRESTArgument[0];

        foreach (FacebookRESTArgument arg in arguments)
            sorted_array += arg;

        qsort(sorted_array, sorted_array.length, sizeof(FacebookRESTArgument),
            (CompareFunc) FacebookRESTArgument.compare);

        return sorted_array;
    }

    protected string generate_signature(FacebookRESTArgument[] sorted_args) {
        string hash_string = "";
        foreach (FacebookRESTArgument arg in sorted_args)
            hash_string = hash_string + ("%s=%s".printf(arg.key, arg.value));

        return Checksum.compute_for_string(ChecksumType.MD5, (hash_string +
            parent_session.get_session_secret()));
    }

    protected virtual void sign() {
        add_argument("api_key", parent_session.get_api_key());
        add_argument("session_key", parent_session.get_session_key());
        add_argument("v", parent_session.get_api_version());
        add_argument("call_id", parent_session.get_next_call_id());

        string sig = generate_signature(get_sorted_arguments());
       
        signature_value = sig;
    }
    
    protected bool get_is_signed() {
        return (signature_value != null);
    }

    protected void set_is_executed(bool is_executed) {
        this.is_executed = is_executed;
    }

    protected void send() throws Spit.Publishing.PublishingError {
        parent_session.wire_message_unqueued.connect(on_message_unqueued);
        message.wrote_body_data.connect(on_wrote_body_data);
        parent_session.send_wire_message(message);
        
        parent_session.wire_message_unqueued.disconnect(on_message_unqueued);
        message.wrote_body_data.disconnect(on_wrote_body_data);
        
        if (err != null)
            network_error(err);
        else
            completed();
        
        if (err != null)
            throw err;
     }

    protected FacebookHttpMethod get_method() {
        return FacebookHttpMethod.from_string(message.method);
    }
    
    protected string get_signature_value() {
        assert(get_is_signed());
        return signature_value;
    }
    
    protected void set_signature_value(string signature_value) {
        this.signature_value = signature_value;
    }

    public bool get_is_executed() {
        return is_executed;
    }
    
    public virtual void execute() throws Spit.Publishing.PublishingError {
        sign();

        assert(get_is_signed());

        // Facebook REST POST requests must transmit at least one argument
        if (get_method() == FacebookHttpMethod.POST)
            assert(arguments.length > 0);

        // concatenate the REST arguments array into an HTTP formdata string
        string formdata_string = "";
        foreach (FacebookRESTArgument arg in arguments) {
            formdata_string = formdata_string + ("%s=%s&".printf(Soup.URI.encode(arg.key, "&"),
                Soup.URI.encode(arg.value, "&+")));
        }

        // append the signature key-value pair to the formdata string
        formdata_string = formdata_string + ("%s=%s".printf(
            Soup.URI.encode(SIGNATURE_KEY, null), Soup.URI.encode(signature_value, null)));

        debug("formdata_string = '%s'", formdata_string);

        // for GET requests with arguments, append the formdata string to the endpoint url after a
        // query divider ('?') -- but make sure to save the old (caller-specified) endpoint URL
        // and restore it after the GET so that the underlying Soup message remains consistent
        string old_url = null;
        string url_with_query = null;
        if (get_method() == FacebookHttpMethod.GET && arguments.length > 0) {
            old_url = message.get_uri().to_string(false);
            url_with_query = get_endpoint_url() + "?" + formdata_string;
            message.set_uri(new Soup.URI(url_with_query));
        }

        message.set_request("application/x-www-form-urlencoded", Soup.MemoryUse.COPY,
            formdata_string, formdata_string.length);
        is_executed = true;
        try {
            send();
        } finally {
            // if old_url is non-null, then restore it
            if (old_url != null)
                message.set_uri(new Soup.URI(old_url));
        }
    }

    public string get_response() {
        assert(get_is_executed());
        return (string) message.response_body.data;
    }
   
    public void add_argument(string name, string value) {
        // if a request has already been signed, it's an error to add further arguments to it
        assert(!get_is_signed());

        arguments += FacebookRESTArgument(name, value);
    }
    
    public string get_endpoint_url() {
        return message.get_uri().to_string(false);
    }
    
    public FacebookRESTSession get_parent_session() {
        return parent_session;
    }
}

internal class FacebookUserInfoTransaction : FacebookRESTTransaction {
    public FacebookUserInfoTransaction(FacebookRESTSession session, string user_id) {
        base(session);

        add_argument("method", "users.getInfo");
        add_argument("uids", user_id);
        add_argument("fields", "name");
    }
}

internal class FacebookAlbumsFetchTransaction : FacebookRESTTransaction {
    public FacebookAlbumsFetchTransaction(FacebookRESTSession session) {
        base(session);

        assert(session.is_authenticated());

        add_argument("method", "photos.getAlbums");
    }
}

internal class FacebookUploadTransaction : FacebookRESTTransaction {
    private GLib.HashTable<string, string> binary_disposition_table = null;
    private Spit.Publishing.Publishable publishable = null;
    private File file = null;
    private string mime_type;
    private string endpoint_url;
    private string method;

    public FacebookUploadTransaction(FacebookRESTSession session, string aid, string privacy_setting,
        Spit.Publishing.Publishable publishable, File file) {
        base(session);
        this.publishable = publishable;
        this.file = file;

        if (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.PHOTO) {
            mime_type = "image/jpeg";
            endpoint_url = PHOTO_ENDPOINT_URL;
            method = "photos.upload";
        } else if (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.VIDEO) {
            mime_type = "video/mpeg";
            endpoint_url = VIDEO_ENDPOINT_URL;
            method = "video.upload";
        } else {
            error("FacebookUploadTransaction: unsupported media type.");
        }

        add_argument("api_key", session.get_api_key());
        add_argument("session_key", session.get_session_key());
        add_argument("v", session.get_api_version());
        add_argument("method", method);
        add_argument("aid", aid);
        add_argument("privacy", privacy_setting);

        binary_disposition_table = create_default_binary_disposition_table();
    }

    private GLib.HashTable<string, string> create_default_binary_disposition_table() {
        GLib.HashTable<string, string> result =
            new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);

        result.insert("filename", Soup.URI.encode(file.get_basename(), null));

        return result;
    }

    protected override void sign() {
        add_argument("call_id", get_parent_session().get_next_call_id());

        string sig = generate_signature(get_sorted_arguments());
       
        set_signature_value(sig);
    }

    public override void execute() throws Spit.Publishing.PublishingError {
        sign();

        // before they can be executed, upload requests must be signed and must
        // contain at least one argument
        assert(get_is_signed());

        FacebookRESTArgument[] request_arguments = get_arguments();
        assert(request_arguments.length > 0);

        // create the multipart request container
        Soup.Multipart message_parts = new Soup.Multipart("multipart/form-data");

        // attach each REST argument as its own multipart formdata part
        foreach (FacebookRESTArgument arg in request_arguments)
            message_parts.append_form_string(arg.key, arg.value);
        
        // append the signature key-value pair to the formdata string
        message_parts.append_form_string(SIGNATURE_KEY, get_signature_value());

        // attempt to read the binary payload from disk
        string payload;
        size_t payload_length;
        try {
            FileUtils.get_contents(file.get_path(), out payload, out payload_length);
        } catch (FileError e) {
            throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(_("A temporary file needed for publishing " +
                "is unavailable"));
        }

        // get the sequence number of the part that will soon become the binary data
        // part
        int payload_part_num = message_parts.get_length();

        // bind the binary data read from disk into a Soup.Buffer object so that we
        // can attach it to the multipart request, then actaully append the buffer
        // to the multipart request. Then, set the MIME type for this part.
        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.COPY, payload,
            payload_length);
        message_parts.append_form_file("", file.get_path(), mime_type, bindable_data);

        // set up the Content-Disposition header for the multipart part that contains the
        // binary image data
        unowned Soup.MessageHeaders image_part_header;
        unowned Soup.Buffer image_part_body;
        message_parts.get_part(payload_part_num, out image_part_header, out image_part_body);
        image_part_header.set_content_disposition("form-data", binary_disposition_table);

        // create a message that can be sent over the wire whose payload is the multipart container
        // that we've been building up
        Soup.Message outbound_message =
            soup_form_request_new_from_multipart(endpoint_url, message_parts);
        set_message(outbound_message);
        
        // send the message and get its response
        set_is_executed(true);
        send();
    }
}

internal class FacebookCreateAlbumTransaction : FacebookRESTTransaction {
    public FacebookCreateAlbumTransaction(FacebookRESTSession session, string album_name,
        string privacy_setting) {
        base(session);

        assert(session.is_authenticated());

        add_argument("method", "photos.createAlbum");
        add_argument("name", album_name);
        add_argument("privacy", privacy_setting);
    }
}

internal class WebAuthenticationPane : Spit.Publishing.PublishingDialogPane, Object {
    private WebKit.WebView webview = null;
    private Gtk.VBox pane_widget = null;
    private Gtk.ScrolledWindow webview_frame = null;
    private static bool cache_dirty = false;

    public signal void login_succeeded(string success_url);
    public signal void login_failed();

    public WebAuthenticationPane() {
        pane_widget = new Gtk.VBox(false, 0);

        webview_frame = new Gtk.ScrolledWindow(null, null);
        webview_frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN);
        webview_frame.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        webview = new WebKit.WebView();
        webview.get_settings().enable_plugins = false;
        webview.load_finished.connect(on_page_load);
        webview.load_started.connect(on_load_started);

        webview_frame.add(webview);
        pane_widget.add(webview_frame);
    }

    private string get_login_url() {
        return "http://www.facebook.com/login.php?api_key=%s&connect_display=popup&v=1.0&next=http://www.facebook.com/connect/login_success.html&cancel_url=http://www.facebook.com/connect/login_failure.html&fbconnect=true&return_session=true&req_perms=read_stream,publish_stream,offline_access,photo_upload,user_photos".printf(API_KEY);
    }

    private void on_page_load(WebKit.WebFrame origin_frame) {
        pane_widget.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));

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
        pane_widget.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
    }

    public static bool is_cache_dirty() {
        return cache_dirty;
    }

    public Gtk.Widget get_widget() {
        return pane_widget;
    }
    
    public Spit.Publishing.PublishingDialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.PublishingDialogPane.GeometryOptions.RESIZABLE;
    }
    
    public void on_pane_installed() {
        webview.open(get_login_url());
    }
    
    public void on_pane_uninstalled() {
    }
}

internal class PublishingOptionsPane : Spit.Publishing.PublishingDialogPane, GLib.Object {
    private LegacyPublishingOptionsPane wrapped = null;

    public signal void logout();
    public signal void publish(string target_album, string privacy_setting);

    public PublishingOptionsPane(string username, FacebookAlbum[] albums,
        Spit.Publishing.Publisher.MediaType media_type) {
            wrapped = new LegacyPublishingOptionsPane(username, albums, media_type);
    }
    
    private void notify_logout() {
        logout();
    }
    
    private void notify_publish(string target_album, string privacy_setting) {
        publish(target_album, privacy_setting);
    }

    public Gtk.Widget get_widget() {
        return wrapped;
    }
    
    public Spit.Publishing.PublishingDialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.PublishingDialogPane.GeometryOptions.NONE;
    }
    
    public void on_pane_installed() {        
        wrapped.logout.connect(notify_logout);
        wrapped.publish.connect(notify_publish);
    }
    
    public void on_pane_uninstalled() {
        wrapped.logout.disconnect(notify_logout);
        wrapped.publish.disconnect(notify_publish);
    }
}

internal class LegacyPublishingOptionsPane : global::PublishingDialogPane {
    private struct PrivacyDescription {
        private string description;
        private string privacy_setting;

        PrivacyDescription(string description, string privacy_setting) {
            this.description = description;
            this.privacy_setting = privacy_setting;
        }
    }

    private const string HEADER_LABEL_TEXT = _("You are logged into Facebook as %s.\n\n");
    private const string PHOTOS_LABEL_TEXT = _("Where would you like to publish the selected photos?");
    private const int CONTENT_GROUP_SPACING = 32;

    private Gtk.RadioButton use_existing_radio = null;
    private Gtk.RadioButton create_new_radio = null;
    private Gtk.ComboBox existing_albums_combo = null;
    private Gtk.ComboBox visibility_combo = null;
    private Gtk.Entry new_album_entry = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private Gtk.Label how_to_label = null;
    private FacebookAlbum[] albums = null;
    private PrivacyDescription[] privacy_descriptions;

    public signal void logout();
    public signal void publish(string target_album, string privacy_setting);

    public LegacyPublishingOptionsPane(string username, FacebookAlbum[] albums,
        Spit.Publishing.Publisher.MediaType media_type) {
        this.albums = albums;
        this.privacy_descriptions = create_privacy_descriptions();

        set_border_width(16);

        Gtk.SeparatorToolItem top_padding = new Gtk.SeparatorToolItem();
        top_padding.set_size_request(-1, 50);
        top_padding.set_draw(false);
        add(top_padding);

        Gtk.HBox how_to_label_layouter = new Gtk.HBox(false, 8);

        string label_text = HEADER_LABEL_TEXT.printf(username);
        if ((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) != 0)
            label_text += PHOTOS_LABEL_TEXT;
        how_to_label = new Gtk.Label(label_text);

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

        Gtk.Label visibility_label = new Gtk.Label.with_mnemonic(_("Videos and new photo albums _visible to:"));

        Gtk.Alignment visibility_label_aligner = new Gtk.Alignment(1.0f, 0.5f, 0, 0);
        visibility_label_aligner.add(visibility_label);

        Gtk.Alignment visibility_combo_aligner = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        visibility_combo = create_visibility_combo();
        visibility_label.set_mnemonic_widget(visibility_combo);
        visibility_combo.set_active(0);
        visibility_combo_aligner.add(visibility_combo);

        Gtk.HBox visibility_layouter = new Gtk.HBox(false, 8);
        visibility_layouter.add(visibility_label_aligner);
        visibility_layouter.add(visibility_combo_aligner);

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

        if ((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) != 0)
            add(album_mode_wrapper);
        add(visibility_layouter);

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

    private Gtk.ComboBox create_visibility_combo() {
        Gtk.ComboBox result = new Gtk.ComboBox.text();

        foreach (PrivacyDescription p in privacy_descriptions)
            result.append_text(p.description);

        return result;
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
        string album_name;
        string privacy_setting = privacy_descriptions[visibility_combo.get_active()].privacy_setting;

        if (use_existing_radio.active) {
            album_name = existing_albums_combo.get_active_text();
        } else {
            album_name = new_album_entry.get_text();
        }

        publish(album_name, privacy_setting);
    }

    private PrivacyDescription[] create_privacy_descriptions() {
        PrivacyDescription[] result = new PrivacyDescription[0];

        result += PrivacyDescription(_("Just me"), PRIVACY_OBJECT_JUST_ME);
        result += PrivacyDescription(_("All friends"), PRIVACY_OBJECT_ALL_FRIENDS);
        result += PrivacyDescription(_("Friends of friends"), PRIVACY_OBJECT_FRIENDS_OF_FRIENDS);
        result += PrivacyDescription(_("Everyone"), PRIVACY_OBJECT_EVERYONE);

        return result;
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
            foreach (FacebookAlbum album in albums) {
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

internal class FacebookRESTXmlDocument {
    private Xml.Doc* document;

    private FacebookRESTXmlDocument(Xml.Doc* doc) {
        document = doc;
    }

    ~FacebookRESTXmlDocument() {
        delete document;
    }

    private static void check_for_error_response(FacebookRESTXmlDocument doc) throws Spit.Publishing.PublishingError {
        Xml.Node* root = doc.get_root_node();
        if (root->name != "error_response")
            return;
        
        Xml.Node* error_code = null;
        try {
            error_code = doc.get_named_child(root, "error_code");
        } catch (Spit.Publishing.PublishingError err) {
            warning("Unable to parse error response for error code");
        }
        
        Xml.Node* error_msg = null;
        try {
            error_msg = doc.get_named_child(root, "error_msg");
        } catch (Spit.Publishing.PublishingError err) {
            warning("Unable to parse error response for error message");
        }

        // 102 errors occur when the session key has become invalid
        if ((error_code != null) && (error_code->get_content() == "102")) {
            throw new Spit.Publishing.PublishingError.EXPIRED_SESSION("session key has become invalid");
        }

        string diagnostic_string = "%s (error code %s)".printf(error_msg != null ?
            error_msg->get_content() : "(unknown)", error_code != null ? error_code->get_content() :
            "(unknown)");

        throw new Spit.Publishing.PublishingError.SERVICE_ERROR(diagnostic_string);
    }

    public Xml.Node* get_root_node() {
        return document->get_root_element();
    }

    public Xml.Node* get_named_child(Xml.Node* parent, string child_name) throws Spit.Publishing.PublishingError {
        Xml.Node* doc_node_iter = parent->children;
    
        for ( ; doc_node_iter != null; doc_node_iter = doc_node_iter->next) {
            if (doc_node_iter->name == child_name)
                return doc_node_iter;
        }

        throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Can't find XML node %s", child_name);
    }

    public static FacebookRESTXmlDocument parse_string(string? input_string)
        throws Spit.Publishing.PublishingError {
        if (input_string == null || input_string.length == 0)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Empty XML string");
        
        // Don't want blanks to be included as text nodes, and want the XML parser to tolerate
        // tolerable XML
        Xml.Doc* doc = Xml.Parser.read_memory(input_string, (int) input_string.length, null, null,
            Xml.ParserOption.NOBLANKS | Xml.ParserOption.RECOVER);
        if (doc == null)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Unable to parse XML document");
        
        FacebookRESTXmlDocument rest_doc = new FacebookRESTXmlDocument(doc);
        check_for_error_response(rest_doc);
        
        return rest_doc;
    }
}

internal class FacebookUploader {
    private const string PREPARE_STATUS_DESCRIPTION = _("Preparing for upload");
    private const string UPLOAD_STATUS_DESCRIPTION = _("Uploading %d of %d");
    private const string TEMP_FILE_PREFIX = "publishing-";
    private const double PREPARATION_PHASE_FRACTION = 0.3;
    private const double UPLOAD_PHASE_FRACTION = 0.7;

    private int current_file = 0;
    private Spit.Publishing.Publishable[] publishables = null;
    private GLib.File[] temp_files = null;
    private FacebookRESTSession session = null;
    private string aid;
    private string privacy_setting;

    public signal void status_updated(string description, double fraction_complete);
    public signal void upload_complete(int num_photos_published);
    public signal void upload_error(Spit.Publishing.PublishingError err);

    public FacebookUploader(FacebookRESTSession session, string aid, string privacy_setting,
        Spit.Publishing.Publishable[] publishables) {
        this.publishables = publishables;
        this.aid = aid;
        this.privacy_setting = privacy_setting;
        this.session = session;
    }

    private void prepare_files() {
        temp_files = new GLib.File[0];

        int i = 0;
        foreach (Spit.Publishing.Publishable publishable in publishables) {
            try {
                temp_files += publishable.serialize_for_publishing(MAX_PHOTO_DIMENSION);
            } catch (Spit.Publishing.PublishingError err) {
                upload_error(err);
                return;
            }

            double phase_fraction_complete = ((double) (i + 1)) / ((double) publishables.length);
            double fraction_complete = phase_fraction_complete * PREPARATION_PHASE_FRACTION;
            
            debug("prepare_file( ): fraction_complete = %f.", fraction_complete);
            
            status_updated(PREPARE_STATUS_DESCRIPTION, fraction_complete);
            
            spin_event_loop();

            i++;
        }
    }

    private void send_files() {
        current_file = 0;
        bool stop = false;
        foreach (File file in temp_files) {
            double fraction_complete = PREPARATION_PHASE_FRACTION +
                (current_file * (UPLOAD_PHASE_FRACTION / temp_files.length));
            status_updated(_("Uploading %d of %d").printf(current_file + 1, temp_files.length),
                fraction_complete);

            FacebookRESTTransaction txn = new FacebookUploadTransaction(session, aid, privacy_setting,
                publishables[current_file], file);
           
            txn.chunk_transmitted.connect(on_chunk_transmitted);
            
            try {
                txn.execute();
            } catch (Spit.Publishing.PublishingError err) {
                upload_error(err);
                stop = true;
            }
                
            txn.chunk_transmitted.disconnect(on_chunk_transmitted);           
            delete_file(file);
            
            if (stop)
                break;
            
            current_file++;
        }
        
        if (!stop)
            upload_complete(current_file);
    }

    private void delete_file(GLib.File file) {
        try {
            debug("Deleting publishing temporary file '%s'", file.get_path());
            file.delete(null);
        } catch (Error e) {
            // if deleting temporary files generates an exception, just print a warning
            // message -- temp directory clean-up will be done on launch or at exit or
            // both
            warning("FacebookUploader: deleting temporary files failed.");
        }
    }
    
    private void on_chunk_transmitted(int bytes_written_so_far, int total_bytes) {
        double file_span = UPLOAD_PHASE_FRACTION / temp_files.length;
        double this_file_fraction_complete = ((double) bytes_written_so_far) / total_bytes;
        double fraction_complete = PREPARATION_PHASE_FRACTION + (current_file * file_span) +
            (this_file_fraction_complete * file_span);

        string status_desc = UPLOAD_STATUS_DESCRIPTION.printf(current_file + 1, temp_files.length);
        status_updated(status_desc, fraction_complete);
    }
    
    public void upload() {
        status_updated(_("Preparing for upload"), 0);

        prepare_files();

        if (temp_files.length > 0)
           send_files();
    }
}

}

