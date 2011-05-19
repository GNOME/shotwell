/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class FacebookService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "facebook.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;
    
    public FacebookService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_icon_set(resource_directory.get_child(ICON_FILENAME));
    }
    
    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }

    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.facebook";
    }

    public unowned string get_pluggable_name() {
        return "Facebook";
    }

    public void get_info(out Spit.PluggableInfo info) {
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
        return new Publishing.Facebook.FacebookPublisher(this, host);
    }

    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO |
            Spit.Publishing.Publisher.MediaType.VIDEO);
    }
}

namespace Publishing.Facebook {
// global parameters for the Facebook publishing plugin -- don't touch these (unless you really,
// truly, deep-down know what you're doing)
public const string SERVICE_NAME = "facebook";
internal const string USER_VISIBLE_NAME = "Facebook";
internal const string API_KEY = "3afe0a1888bd340254b1587025f8d1a5";
internal const string SIGNATURE_KEY = "sig";
internal const int STANDARD_PHOTO_DIMENSION = 720;
internal const int HIGH_PHOTO_DIMENSION = 2048;
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

// Ticket #2916: we now allow users publishing to Facebook to choose the
// resolution at which they want to upload, either the standard 720 pixels
// across, or the newly-supported 2048 pixel size.
public enum Resolution {
    STANDARD,
    HIGH;

    public string get_name() {
        switch (this) {
            case STANDARD:
                return _("Standard (720 pixels)");

            case HIGH:
                return _("Large (2048 pixels)");

            default:
                error("Unknown resolution %s", this.to_string());
        }
    }

    public int get_pixels() {
        switch (this) {
            case STANDARD:
                return STANDARD_PHOTO_DIMENSION;

            case HIGH:
                return HIGH_PHOTO_DIMENSION;

            default:
                error("Unknown resolution %s", this.to_string());
        }
    }
}

public class FacebookPublisher : Spit.Publishing.Publisher, GLib.Object {
    private const int NO_ALBUM = -1;

    private string privacy_setting = PRIVACY_OBJECT_JUST_ME;
    private FacebookAlbum[] albums = null;
    private int publish_to_album = NO_ALBUM;
    private weak Spit.Publishing.PluginHost host = null;
    private FacebookRESTSession session = null;
    private WebAuthenticationPane web_auth_pane = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private weak Spit.Publishing.Service service = null;
    private bool running = false;

    private Resolution target_resolution = Resolution.HIGH;

    public FacebookPublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        debug("FacebookPublisher instantiated.");
        this.service = service;
        this.host = host;
    }

    private bool is_running() {
        return running;
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
        return host.get_config_string("session_key", null);
    }

    private string? get_persistent_session_secret() {
        return host.get_config_string("session_secret", null);
    }

    private string? get_persistent_uid() {
        return host.get_config_string("uid", null);
    }

    private string? get_persistent_user_name() {
        return host.get_config_string("user_name", null);
    }

    private void set_persistent_session_key(string session_key) {
        host.set_config_string("session_key", session_key);
    }

    private void set_persistent_session_secret(string session_secret) {
        host.set_config_string("session_secret", session_secret);
    }

    private void set_persistent_uid(string uid) {
        host.set_config_string("uid", uid);
    }

    private void set_persistent_user_name(string user_name) {
        host.set_config_string("user_name", user_name);
    }

    // Part of the fix for #3232. These have to be 
    // public so the legacy options pane may use them.
    public int get_persistent_default_size() {
        return host.get_config_int("default_size", 0);
    }
    
    public void set_persistent_default_size(int size) { 
        host.set_config_int("default_size", size);
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

        host.install_welcome_pane(SERVICE_WELCOME_MESSAGE, on_login_clicked);
        host.set_service_locked(false);
    }

    private void do_test_connection_to_endpoint() {
        debug("ACTION: testing connection to Facebook endpoint.");
        host.set_service_locked(true);
        
        host.install_static_message_pane(_("Testing connection to Facebook..."));

        FacebookEndpointTestTransaction txn = new FacebookEndpointTestTransaction(session);
        txn.completed.connect(on_endpoint_test_completed);
        txn.network_error.connect(on_endpoint_test_error);

        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            if (is_running())
                host.post_error(err);
        }
    }

    private void do_fetch_album_descriptions() {
        debug("ACTION: fetching album descriptions from remote endpoint.");

        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();

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
                host.post_error(err);
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
            
            // Expired session errors are recoverable, so log out the user and do a
            // short-circuit return to stop the error from being posted to our host
            if (err is Spit.Publishing.PublishingError.EXPIRED_SESSION) {
                do_logout();
                return;
            }

            // only post an error if we're running; errors tend to come in groups, so it's possible
            // another error has already posted and caused us to stop
            if (is_running())
                host.post_error(err);

            return;
        }

        // Due to this bug: https://bugzilla.gnome.org/show_bug.cgi?id=646298, we no longer
        // do a direct array assignment here
        albums = new FacebookAlbum[0];
        foreach (FacebookAlbum album in extracted)
            albums += album;

        on_albums_extracted();
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: showing publishing options pane.");

        host.set_service_locked(false);

        PublishingOptionsPane publishing_options_pane = new PublishingOptionsPane(
            session.get_user_name(), albums, host.get_publishable_media_type(), this);
        publishing_options_pane.logout.connect(on_publishing_options_pane_logout);
        publishing_options_pane.publish.connect(on_publishing_options_pane_publish);
        host.install_dialog_pane(publishing_options_pane,
            Spit.Publishing.PluginHost.ButtonMode.CANCEL);
    }

    private void do_logout() {
        debug("ACTION: clearing persistent session information and restaring interaction.");

        invalidate_persistent_session();

        running = false;
        start();
    }

    private void do_hosted_web_authentication() {
        debug("ACTION: doing hosted web authentication.");

        host.set_service_locked(false);

        web_auth_pane = new WebAuthenticationPane();
        web_auth_pane.login_succeeded.connect(on_web_auth_pane_login_succeeded);
        web_auth_pane.login_failed.connect(on_web_auth_pane_login_failed);

        host.install_dialog_pane(web_auth_pane,
            Spit.Publishing.PluginHost.ButtonMode.CANCEL);
    }

    private void do_authenticate_session(string success_url) {
        debug("ACTION: preparing to extract session information encoded in url = '%s'",
            success_url);

        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();

        session.authenticated.connect(on_session_authenticated);
        session.authentication_failed.connect(on_session_authentication_failed);

        try {
            session.authenticate_from_uri(success_url);
        } catch (Spit.Publishing.PublishingError err) {
            // only post an error if we're running; errors tend to come in groups, so it's possible
            // another error has already posted and caused us to stop
            if (is_running())
                host.post_error(err);
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

        host.set_service_locked(true);

        progress_reporter = host.serialize_publishables(target_resolution.get_pixels());

        Spit.Publishing.Publishable[] publishables = host.get_publishables();
        FacebookUploader uploader = new FacebookUploader(session, albums[publish_to_album].id,
            privacy_setting, publishables);

        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);

        uploader.upload(on_upload_status_updated);
    }

    private void do_create_album(string album_name) {
        debug("ACTION: creating new photo album with name '%s'", album_name);
        albums += FacebookAlbum(album_name, "");

        host.set_service_locked(true);

        host.install_static_message_pane(_("Creating album..."),
            Spit.Publishing.PluginHost.ButtonMode.CANCEL);

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
                host.post_error(err);
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
                host.post_error(err);

            return;
        }

        on_album_name_extracted();
    }

    private void do_show_success_pane() {
        debug("ACTION: showing success pane.");

        host.set_service_locked(false);
        host.install_success_pane();
    }

    private void on_login_clicked() {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Login' on welcome pane.");

        do_test_connection_to_endpoint();
    }

    private void on_endpoint_test_completed(FacebookRESTTransaction txn) {
        txn.completed.disconnect(on_endpoint_test_completed);
        txn.network_error.disconnect(on_endpoint_test_error);

        if (!is_running())
            return;

        debug("EVENT: endpoint test transaction detected that the Facebook endpoint is alive.");

        do_hosted_web_authentication();
    }

    private void on_endpoint_test_error(FacebookRESTTransaction bad_txn,
        Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_endpoint_test_completed);
        bad_txn.network_error.disconnect(on_endpoint_test_error);

        if (!is_running())
            return;

        debug("EVENT: endpoint test transaction failed to detect a connection to the Facebook endpoint");

        host.post_error(err);
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

        host.post_error(err);
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

        host.post_error(err);
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

    public void on_publishing_options_pane_publish(string target_album, string privacy_setting, Resolution target_resolution) {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Publish' in publishing options pane.");

        this.privacy_setting = privacy_setting;
        this.target_resolution = target_resolution;

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

        host.post_error(err);
    }

    private void on_album_name_extracted() {
        if (!is_running())
            return;

        debug("EVENT: successfully extracted aid.");

        do_upload();
    }

    private void on_upload_status_updated(int file_number, double completed_fraction) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);

        progress_reporter(file_number, completed_fraction);
    }

    private void on_upload_complete(FacebookUploader uploader, int num_published) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload complete; %d items published.", num_published);

        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        do_show_success_pane();
    }

    private void on_upload_error(FacebookUploader uploader, Spit.Publishing.PublishingError err) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload error = '%s'.", err.message);

        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        host.post_error(err);
    }

    public Spit.Publishing.Service get_service() {
        return service;
    }

    public string get_service_name() {
        return SERVICE_NAME;
    }

    public string get_user_visible_name() {
        return USER_VISIBLE_NAME;
    }

    public void start() {
        if (is_running())
            return;

        debug("FacebookPublisher: starting interaction.");

        running = true;

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
                host.set_service_locked(false);
                host.install_static_message_pane(RESTART_ERROR_MESSAGE,
                    Spit.Publishing.PluginHost.ButtonMode.CANCEL);
            } else {
                session = new FacebookRESTSession(PHOTO_ENDPOINT_URL, USER_AGENT);
                do_show_service_welcome_pane();
            }
        }
    }

    public void stop() {
        debug("FacebookPublisher: stop( ) invoked.");

        if (session != null)
            session.stop_transactions();

        host = null;
        running = false;
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

    protected void notify_wire_message_unqueued(Soup.Message message) {
        wire_message_unqueued(message);
    }

    protected void notify_authenticated() {
        authenticated();
    }

    protected void notify_authentication_failed(Spit.Publishing.PublishingError err) {
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
        string? session_desc = null;
        int index = decoded_uri.index_of("session={");
        if (index >= 0)
            session_desc = decoded_uri[index:decoded_uri.length];
        if (session_desc == null)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Server redirect URL contained no session description");

        // remove any trailing parameters from the session description string
        string? trailing_params = null;
        index = session_desc.index_of_char('&');
        if (index >= 0)
            trailing_params = session_desc[index:session_desc.length];
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

        // Facebook REST POST requests must transmit at least one argument
        if (get_method() == FacebookHttpMethod.POST)
            assert(arguments.length > 0);

        // concatenate the REST arguments array into an HTTP formdata string
        string formdata_string = "";
        foreach (FacebookRESTArgument arg in arguments) {
            formdata_string = formdata_string + ("%s=%s&".printf(Soup.URI.encode(arg.key, "&"),
                Soup.URI.encode(arg.value, "&+")));
        }

        // if this transaction has been signed, then we need to append the signature key-value pair
        // to the formdata string
        if (get_is_signed()) {
            formdata_string = formdata_string + ("%s=%s".printf(
                Soup.URI.encode(SIGNATURE_KEY, null), Soup.URI.encode(signature_value, null)));
        }

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
            formdata_string.data);
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

internal class FacebookEndpointTestTransaction : FacebookRESTTransaction {
    public FacebookEndpointTestTransaction(FacebookRESTSession session) {
        base(session, FacebookHttpMethod.GET);
    }

    public FacebookEndpointTestTransaction.with_endpoint_url(FacebookRESTSession session,
        string endpoint_url) {
        base(session, FacebookHttpMethod.GET);
    }

    protected override void sign() {
        // signing is a no-op for endpoint test transactions since we don't need any authentication
        // just to check if the remote host is alive.
    }
}

internal class FacebookUploadTransaction : FacebookRESTTransaction {
    private GLib.HashTable<string, string> binary_disposition_table = null;
    private Spit.Publishing.Publishable publishable = null;
    private File file = null;
    private string mime_type;
    private string endpoint_url;
    private string method;
    private MappedFile mapped_file = null;

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
        
        if (!publishable_metadata.has_iptc())
            return;
        
        if (publishable_metadata.has_tag("Iptc.Application2.Caption"))
            publishable_metadata.set_tag_string("Iptc.Application2.Caption", "");
        
        try {
            publishable_metadata.save_file(publishable.get_serialized_file().get_path());
        } catch (GLib.Error err) {
            warning("couldn't write metadata to file '%s' for upload preprocessing.",
                publishable.get_serialized_file().get_path());
        }
    }

    protected override void sign() {
        add_argument("call_id", get_parent_session().get_next_call_id());

        string sig = generate_signature(get_sorted_arguments());

        set_signature_value(sig);
    }

    public override void execute() throws Spit.Publishing.PublishingError {
        preprocess_publishable(publishable);
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

        // attempt to map the binary payload from disk into memory
        try {
            mapped_file = new MappedFile(file.get_path(), false);
        } catch (FileError e) {
            throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                _("A temporary file needed for publishing is unavailable"));
        }
        unowned uint8[] payload = (uint8[]) mapped_file.get_contents();
        payload.length = (int) mapped_file.get_length();

        // get the sequence number of the part that will soon become the binary data
        // part
        int payload_part_num = message_parts.get_length();

        // bind the binary data read from disk into a Soup.Buffer object so that we
        // can attach it to the multipart request, then actaully append the buffer
        // to the multipart request. Then, set the MIME type for this part.
        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.TEMPORARY, payload);
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

internal class WebAuthenticationPane : Spit.Publishing.DialogPane, Object {
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
        webview.get_settings().enable_default_context_menu = false;

        webview.load_finished.connect(on_page_load);
        webview.load_started.connect(on_load_started);

        webview_frame.add(webview);
        pane_widget.add(webview_frame);
    }
    
    private struct LocaleLookup {
        public string prefix;
        public string translation;
        public string? exception_code;
        public string? exception_translation;
        public string? exception_code_2;
        public string? exception_translation_2;
    }
    
    private const LocaleLookup[] locale_lookup_table = {
        { "es", "es-la", "ES", "es-es" },
        { "en", "en-gb", "US", "www" },
        { "fr", "fr-fr", "CA", "fr-ca" },
        { "pt", "pt-br", "PT", "pt-pt" },
        { "zh", "zh-cn", "HK", "zh-hk", "TW", "zh-tw" },
        { "af", "af-za" },
        { "ar", "ar-ar" },
        { "nb", "nb-no" },
        { "no", "nb-no" },
        { "id", "id-id" },
        { "ms", "ms-my" },
        { "ca", "ca-es" },
        { "cs", "cs-cz" },
        { "cy", "cy-gb" },
        { "da", "da-dk" },
        { "de", "de-de" },
        { "tl", "tl-ph" },
        { "ko", "ko-kr" },
        { "hr", "hr-hr" },
        { "it", "it-it" },
        { "lt", "lt-lt" },
        { "hu", "hu-hu" },
        { "nl", "nl-nl" },
        { "ja", "ja-jp" },
        { "nb", "nb-no" },
        { "no", "nb-no" },
        { "pl", "pl-pl" },
        { "ro", "ro-ro" },
        { "ru", "ru-ru" },
        { "sk", "sk-sk" },
        { "sl", "sl-sl" },
        { "sv", "sv-se" },
        { "th", "th-th" },
        { "vi", "vi-vn" },
        { "tr", "tr-tr" },
        { "el", "el-gr" },
        { "bg", "bg-bg" },
        { "sr", "sr-rs" },
        { "he", "he-il" },
        { "hi", "hi-in" },
        { "bn", "bn-in" },
        { "pa", "pa-in" },
        { "ta", "ta-in" },
        { "te", "te-in" },
        { "ml", "ml-in" }
    };
    
    private string get_system_locale_as_facebook_locale() {
        unowned string? raw_system_locale = Intl.setlocale(LocaleCategory.ALL, "");
        if (raw_system_locale == null || raw_system_locale == "")
            return "www";
        
        string system_locale = raw_system_locale.split(".")[0];
        
        foreach (LocaleLookup locale_lookup in locale_lookup_table) {
            if (!system_locale.has_prefix(locale_lookup.prefix))
                continue;
            
            if (locale_lookup.exception_code != null) {
                assert(locale_lookup.exception_translation != null);
                
                if (system_locale.contains(locale_lookup.exception_code))
                    return locale_lookup.exception_translation;
            }
            
            if (locale_lookup.exception_code_2 != null) {
                assert(locale_lookup.exception_translation_2 != null);
                
                if (system_locale.contains(locale_lookup.exception_code_2))
                    return locale_lookup.exception_translation_2;
            }
            
            return locale_lookup.translation;
        }
        
        // default
        return "www";
    }

    private string get_login_url() {
        string facebook_locale = get_system_locale_as_facebook_locale();

        return "http://%s.facebook.com/login.php?api_key=%s&connect_display=popup&v=1.0&next=http://www.facebook.com/connect/login_success.html&cancel_url=http://www.facebook.com/connect/login_failure.html&fbconnect=true&return_session=true&req_perms=read_stream,publish_stream,offline_access,photo_upload,user_photos".printf(facebook_locale, API_KEY);
    }

    private void on_page_load(WebKit.WebFrame origin_frame) {
        pane_widget.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));

        string loaded_url = origin_frame.get_uri().dup();

        // strip parameters from the loaded url
        if (loaded_url.contains("?")) {
            int index = loaded_url.index_of_char('?');
            string params = loaded_url[index:loaded_url.length];
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

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.RESIZABLE;
    }

    public void on_pane_installed() {
        webview.open(get_login_url());
    }

    public void on_pane_uninstalled() {
    }
}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {
    private LegacyPublishingOptionsPane wrapped = null;

    public signal void logout();
    public signal void publish(string target_album, string privacy_setting, Resolution target_resolution);

    public PublishingOptionsPane(string username, FacebookAlbum[] albums,
        Spit.Publishing.Publisher.MediaType media_type, FacebookPublisher publisher) {
            wrapped = new LegacyPublishingOptionsPane(username, albums, media_type, publisher);
    }

    private void notify_logout() {
        logout();
    }

    private void notify_publish(string target_album, string privacy_setting, Resolution target_resolution) {
        publish(target_album, privacy_setting, target_resolution);
    }

    public Gtk.Widget get_widget() {
        return wrapped;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        wrapped.logout.connect(notify_logout);
        wrapped.publish.connect(notify_publish);

        wrapped.installed();
    }

    public void on_pane_uninstalled() {
        wrapped.logout.disconnect(notify_logout);
        wrapped.publish.disconnect(notify_publish);
    }
}

internal class LegacyPublishingOptionsPane : Gtk.VBox {
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
    private const string RESOLUTION_LABEL_TEXT = _("Upload _size:");
    private const int CONTENT_GROUP_SPACING = 32;
    private const int STANDARD_ACTION_BUTTON_WIDTH = 128;

    private Gtk.RadioButton use_existing_radio = null;
    private Gtk.RadioButton create_new_radio = null;
    private Gtk.ComboBox existing_albums_combo = null;
    private Gtk.ComboBox visibility_combo = null;
    private Gtk.Entry new_album_entry = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private Gtk.Label how_to_label = null;
    private FacebookAlbum[] albums = null;
    private FacebookPublisher publisher = null;
    private PrivacyDescription[] privacy_descriptions;

    // Ticket #2916 - These are used to allow the user to choose
    // their target resolution.
    private Resolution[] possible_resolutions;
    private Gtk.ComboBox resolution_combo = null;

    private Spit.Publishing.Publisher.MediaType media_type;

    public signal void logout();
    public signal void publish(string target_album, string privacy_setting, Resolution target_resolution);

    public LegacyPublishingOptionsPane(string username, FacebookAlbum[] albums,
        Spit.Publishing.Publisher.MediaType media_type, FacebookPublisher publisher) {
        this.albums = albums;
        this.privacy_descriptions = create_privacy_descriptions();

        this.possible_resolutions = create_resolution_list();
        
        this.publisher = publisher;

        // Ticket #3175
        // Remember this for later - we'll need to know if
        // the user is importing video or not when sorting
        // out visibility.
        this.media_type = media_type;

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
        publish_button.set_size_request(STANDARD_ACTION_BUTTON_WIDTH, -1);
        logout_button.set_size_request(STANDARD_ACTION_BUTTON_WIDTH, -1);

        album_mode_layouter.add(use_existing_layouter);
        album_mode_layouter.add(create_new_layouter);

        Gtk.Alignment album_mode_wrapper = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        album_mode_wrapper.add(album_mode_layouter);

        if ((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) != 0)
            add(album_mode_wrapper);
        add(visibility_layouter);

        // Ticket #2916 - if the user is uploading photographs, allow
        // them to choose what resolution they should be uploaded at.
        if((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) != 0) {
            Gtk.HBox resolution_layouter = new Gtk.HBox(false, 8);

            // Create the controls. Each control is assigned to a
            // Gtk.Alignment to try to make it easier to line up.
            Gtk.Label resolution_label = new Gtk.Label.with_mnemonic(RESOLUTION_LABEL_TEXT);
            resolution_combo = create_resolution_combo();
            resolution_label.set_mnemonic_widget(resolution_combo);
            
            // Ticket #3232 - Remember facebook size settings.
            resolution_combo.set_active(publisher.get_persistent_default_size());
            resolution_combo.changed.connect(on_size_changed);

            Gtk.Alignment resolution_combo_aligner = new Gtk.Alignment(1.0f, 0.5f, 0.0f, 0.0f);
            resolution_combo_aligner.add(resolution_combo);
            resolution_combo_aligner.right_padding = CONTENT_GROUP_SPACING * 2;

            Gtk.Alignment resolution_label_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
            resolution_label_aligner.left_padding = CONTENT_GROUP_SPACING;
            resolution_label_aligner.add(resolution_label);

            Gtk.SeparatorToolItem resolution_pusher = new Gtk.SeparatorToolItem();
            resolution_pusher.set_size_request(-1,-1);
            resolution_pusher.set_draw(false);

            Gtk.Alignment resolution_pusher_aligner = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
            resolution_pusher_aligner.add(resolution_pusher);

            resolution_layouter.add(resolution_label_aligner);
            resolution_layouter.add(resolution_pusher_aligner);
            resolution_layouter.add(resolution_combo_aligner);

            // Actually add them to the pane.  We move them down slightly,
            // since they're not logically related to gallery privacy.
            Gtk.SeparatorToolItem resolution_padding = new Gtk.SeparatorToolItem();
            resolution_padding.set_size_request(-1, CONTENT_GROUP_SPACING);
            resolution_padding.set_draw(false);
            add(resolution_padding);
            add(resolution_layouter);
        }

        // Ticket #3175, part 2: make sure this widget starts out sensitive
        // if it needs to by checking whether we're starting with a video
        // or a new gallery.
        visibility_combo.set_sensitive((create_new_radio.active) || ((media_type & Spit.Publishing.Publisher.MediaType.VIDEO) != 0));

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


    private Gtk.ComboBox create_resolution_combo() {
        Gtk.ComboBox result = new Gtk.ComboBox.text();

        foreach (Resolution res in possible_resolutions)
            result.append_text(res.get_name());

        return result;
    }


    private void on_use_existing_toggled() {
        if (use_existing_radio.active) {
            existing_albums_combo.set_sensitive(true);
            new_album_entry.set_sensitive(false);

            // Ticket #3175 - if we're not adding a new gallery
            // or a video, then we shouldn't be allowed to
            // choose visibility, since it has no effect.
            visibility_combo.set_sensitive((media_type & Spit.Publishing.Publisher.MediaType.VIDEO) != 0);

            existing_albums_combo.grab_focus();
        }
    }

    private void on_create_new_toggled() {
        if (create_new_radio.active) {
            existing_albums_combo.set_sensitive(false);
            new_album_entry.set_sensitive(true);
            new_album_entry.grab_focus();

            // Ticket #3175 - if we're creating a new gallery, make sure this is
            // active, since it may have possibly been set inactive.
            visibility_combo.set_sensitive(true);
        }
    }
    
    private void on_size_changed() {
        publisher.set_persistent_default_size(resolution_combo.get_active());
    }

    private void on_logout_button_clicked() {
        logout();
    }

    private void on_publish_button_clicked() {
        string album_name;
        string privacy_setting = privacy_descriptions[visibility_combo.get_active()].privacy_setting;
        Resolution resolution_setting = possible_resolutions[resolution_combo.get_active()];

        if (use_existing_radio.active) {
            album_name = existing_albums_combo.get_active_text();
        } else {
            album_name = new_album_entry.get_text();
        }

        publish(album_name, privacy_setting, resolution_setting);
    }


    private PrivacyDescription[] create_privacy_descriptions() {
        PrivacyDescription[] result = new PrivacyDescription[0];

        result += PrivacyDescription(_("Just me"), PRIVACY_OBJECT_JUST_ME);
        result += PrivacyDescription(_("All friends"), PRIVACY_OBJECT_ALL_FRIENDS);
        result += PrivacyDescription(_("Friends of friends"), PRIVACY_OBJECT_FRIENDS_OF_FRIENDS);
        result += PrivacyDescription(_("Everyone"), PRIVACY_OBJECT_EVERYONE);

        return result;
    }

    private Resolution[] create_resolution_list() {
        Resolution[] result = new Resolution[0];

        result += Resolution.STANDARD;
        result += Resolution.HIGH;

        return result;
    }

    public void installed() {
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
    private int current_file = 0;
    private Spit.Publishing.Publishable[] publishables = null;
    private FacebookRESTSession session = null;
    private string aid;
    private string privacy_setting;
    private Spit.Publishing.ProgressCallback? status_updated = null;

    public signal void upload_complete(int num_photos_published);
    public signal void upload_error(Spit.Publishing.PublishingError err);

    public FacebookUploader(FacebookRESTSession session, string aid, string privacy_setting,
        Spit.Publishing.Publishable[] publishables) {
        this.publishables = publishables;
        this.aid = aid;
        this.privacy_setting = privacy_setting;
        this.session = session;
    }

    private void send_files() {
        current_file = 0;
        bool stop = false;
        foreach (Spit.Publishing.Publishable publishable in publishables) {
            GLib.File? file = publishable.get_serialized_file();
            assert (file != null);

            double fraction_complete = ((double) current_file) / publishables.length;
                if (status_updated != null)
                    status_updated(current_file + 1, fraction_complete);

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

            if (stop)
                break;

            current_file++;
        }

        if (!stop)
            upload_complete(current_file);
    }

    private void on_chunk_transmitted(int bytes_written_so_far, int total_bytes) {
        double file_span = 1.0 / publishables.length;
        double this_file_fraction_complete = ((double) bytes_written_so_far) / total_bytes;
        double fraction_complete = (current_file * file_span) + (this_file_fraction_complete *
            file_span);

        if (status_updated != null)
            status_updated(current_file + 1, fraction_complete);
    }

    public void upload(Spit.Publishing.ProgressCallback? status_updated = null) {
        this.status_updated = status_updated;

        if (publishables.length > 0)
           send_files();
    }
}

}

