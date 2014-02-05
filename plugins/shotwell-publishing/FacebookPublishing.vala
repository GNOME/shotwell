/* Copyright 2009-2014 Yorba Foundation
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

    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Lucas Beeler";
        info.copyright = _("Copyright 2009-2014 Yorba Foundation");
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
internal const string APPLICATION_ID = "162702932093";
internal const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");
internal const string SERVICE_WELCOME_MESSAGE =
    _("You are not currently logged into Facebook.\n\nIf you don't yet have a Facebook account, you can create one during the login process. During login, Shotwell Connect may ask you for permission to upload photos and publish to your feed. These permissions are required for Shotwell Connect to function.");
internal const string RESTART_ERROR_MESSAGE =
    _("You have already logged in and out of Facebook during this Shotwell session.\nTo continue publishing to Facebook, quit and restart Shotwell, then try publishing again.");
internal const string USER_AGENT = "Java/1.6.0_16";
internal const int EXPIRED_SESSION_STATUS_CODE = 400;

internal class Album {
    public string name;
    public string id;

    public Album(string name, string id) {
        this.name = name;
        this.id = id;
    }
}

internal enum Resolution {
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
                return 720;

            case HIGH:
                return 2048;

            default:
                error("Unknown resolution %s", this.to_string());
        }
    }
}

internal class PublishingParameters {
    public const int UNKNOWN_ALBUM = -1;
    
    public bool strip_metadata;
    public Album[] albums;
    public int target_album;
    public string? new_album_name;  // the name of the new album being created during this
                                    // publishing interaction or null if publishing to an existing
                                    // album

    public string? privacy_object;  // a serialized JSON object encoding the privacy settings of the
                                    // published resources
    public Resolution resolution;
    
    public PublishingParameters() {
        this.albums = null;
        this.privacy_object = null;
        this.target_album = UNKNOWN_ALBUM;
        this.new_album_name = null;
        this.strip_metadata = false;
        this.resolution = Resolution.HIGH;
    }
    
    public void add_album(string name, string id) {
        if (albums == null)
            albums = new Album[0];
        
        Album new_album = new Album(name, id);
        albums += new_album;
    }
    
    public void set_target_album_by_name(string? name) {
        if (name == null) {
            target_album = UNKNOWN_ALBUM;
            return;
        }
    
        for (int i = 0; i < albums.length; i++) {

            if (albums[i].name == name) {
                target_album = i;
                return;
            }
        }
        
        target_album = UNKNOWN_ALBUM;
    }
    
    public string? get_target_album_name() {
        if (albums == null || target_album == UNKNOWN_ALBUM)
            return null;

        return albums[target_album].name;
    }
    
    public string? get_target_album_id() {
        if (albums == null || target_album == UNKNOWN_ALBUM)
            return null;

        return albums[target_album].id;    
    }
}

public class FacebookPublisher : Spit.Publishing.Publisher, GLib.Object {
    private PublishingParameters publishing_params;
    private weak Spit.Publishing.PluginHost host = null;
    private WebAuthenticationPane web_auth_pane = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private weak Spit.Publishing.Service service = null;
    private bool running = false;
    private GraphSession graph_session;
    private PublishingOptionsPane? publishing_options_pane = null;
    private Uploader? uploader = null;
    private string? uid = null;
    private string? username = null;

    public FacebookPublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        debug("FacebookPublisher instantiated.");

        this.service = service;
        this.host = host;

        this.publishing_params = new PublishingParameters();

        this.graph_session = new GraphSession();
        graph_session.authenticated.connect(on_session_authenticated);
    }

    private bool is_persistent_session_valid() {
        string? token = get_persistent_access_token();

        if (token != null)
            debug("existing Facebook session found in configuration database (access_token = %s).",
                token);
        else
            debug("no existing Facebook session available.");

        return token != null;
    }

    private string? get_persistent_access_token() {
        return host.get_config_string("access_token", null);
    }
    
    private bool get_persistent_strip_metadata() {
        return host.get_config_bool("strip_metadata", false);
    }

    private void set_persistent_access_token(string access_token) {
        host.set_config_string("access_token", access_token);
    }
    
    private void set_persistent_strip_metadata(bool strip_metadata) {
        host.set_config_bool("strip_metadata", strip_metadata);
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
        debug("invalidating saved Facebook session.");

        set_persistent_access_token("");
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
        
        GraphMessage endpoint_test_message = graph_session.new_endpoint_test();
        endpoint_test_message.completed.connect(on_endpoint_test_completed);
        endpoint_test_message.failed.connect(on_endpoint_test_error);
        
        graph_session.send_message(endpoint_test_message);
    }
    
    private void do_fetch_user_info() {
        debug("ACTION: fetching user information.");
        
        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();
        
        GraphMessage user_info_message = graph_session.new_query("/me");
        
        user_info_message.completed.connect(on_fetch_user_info_completed);
        user_info_message.failed.connect(on_fetch_user_info_error);
        
        graph_session.send_message(user_info_message);
    }

    private void do_fetch_album_descriptions() {
        debug("ACTION: fetching album list.");

        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();
        
        GraphMessage albums_message = graph_session.new_query("/%s/albums".printf(uid));
        
        albums_message.completed.connect(on_fetch_albums_completed);
        albums_message.failed.connect(on_fetch_albums_error);
        
        graph_session.send_message(albums_message);
    }
    
    private void do_extract_user_info_from_json(string json) {
        debug("ACTION: extracting user info from JSON response.");
        
        try {
            Json.Parser parser = new Json.Parser();
            parser.load_from_data(json);
            
            Json.Node root = parser.get_root();
            Json.Object response_object = root.get_object();
            uid = response_object.get_string_member("id");
            username = response_object.get_string_member("name");
        } catch (Error error) {
            host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(error.message));
            return;
        }
        
        on_user_info_extracted();
    }

    private void do_extract_albums_from_json(string json) {
        debug("ACTION: extracting album info from JSON response.");

        try {
            Json.Parser parser = new Json.Parser();
            parser.load_from_data(json);
            
            Json.Node root = parser.get_root();
            Json.Object response_object = root.get_object();
            Json.Array album_list = response_object.get_array_member("data");
            
            publishing_params.albums = new Album[0];

            for (int i = 0; i < album_list.get_length(); i++) {
                Json.Object current_album = album_list.get_object_element(i);
                string album_id = current_album.get_string_member("id");
                string album_name = current_album.get_string_member("name");

                // Note that we are completely ignoring the "can_upload" flag in the list of albums
                // that we pulled from facebook eariler -- effectively, we add every album to the
                // publishing_params album list regardless of the value of its can_upload flag. In
                // the future we may wish to make adding to the publishing_params album list
                // conditional on the value of the can_upload flag being true
                publishing_params.add_album(album_name, album_id);
            }
        } catch (Error error) {
            host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(error.message));
            return;
        }

        on_albums_extracted();
    }
    
    private void do_create_new_album() {
        debug("ACTION: creating a new album named \"%s\".\n", publishing_params.new_album_name);
        
        host.set_service_locked(true);
        host.install_static_message_pane(_("Creating album..."));
        
        GraphMessage create_album_message = graph_session.new_create_album(
            publishing_params.new_album_name, publishing_params.privacy_object);
        
        create_album_message.completed.connect(on_create_album_completed);
        create_album_message.failed.connect(on_create_album_error);

        graph_session.send_message(create_album_message);
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: showing publishing options pane.");

        host.set_service_locked(false);
        Gtk.Builder builder = new Gtk.Builder();

        try {
            // the trailing get_path() is required, since add_from_file can't cope
            // with File objects directly and expects a pathname instead.
            builder.add_from_file(
                host.get_module_file().get_parent().
                get_child("facebook_publishing_options_pane.glade").get_path());
        } catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            host.post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is unavailable. Publishing to Facebook can't continue.")));
            return;
        }
        
        publishing_options_pane = new PublishingOptionsPane(username, publishing_params.albums,
            host.get_publishable_media_type(), this, builder, get_persistent_strip_metadata());
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

    private void do_add_new_local_album_from_json(string album_name, string json) {
        try {
            Json.Parser parser = new Json.Parser();
            parser.load_from_data(json);
            
            Json.Node root = parser.get_root();
            Json.Object response_object = root.get_object();
            string album_id = response_object.get_string_member("id");
            
            publishing_params.add_album(album_name, album_id);
        } catch (Error error) {
            host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(error.message));
            return;
        }
        
        publishing_params.set_target_album_by_name(album_name);
        do_upload();
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

    private void do_authenticate_session(string good_login_uri) {
        debug("ACTION: preparing to extract session information encoded in uri = '%s'",
             good_login_uri);

        // the raw uri is percent-encoded, so decode it
        string decoded_uri = Soup.URI.decode(good_login_uri);

        // locate the access token within the URI
        string? access_token = null;
        int index = decoded_uri.index_of("#access_token=");
        if (index >= 0)
            access_token = decoded_uri[index:decoded_uri.length];
        if (access_token == null) {
            host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                "Server redirect URL contained no access token"));
            return;
        }

        // remove any trailing parameters from the session description string
        string? trailing_params = null;
        index = access_token.index_of_char('&');
        if (index >= 0)
            trailing_params = access_token[index:access_token.length];
        if (trailing_params != null)
            access_token = access_token.replace(trailing_params, "");

        // remove the key from the session description string
        access_token = access_token.replace("#access_token=", "");
        
        // we've got an access token!
        graph_session.authenticated.connect(on_session_authenticated);
        graph_session.authenticate(access_token);
    }

    private void do_save_session_information() {
        debug("ACTION: saving session information to configuration system.");

        set_persistent_access_token(graph_session.get_access_token());
    }
    
    private void do_upload() {
        debug("ACTION: uploading photos to album '%s'",
            publishing_params.target_album == PublishingParameters.UNKNOWN_ALBUM ? "(none)" :
            publishing_params.get_target_album_name());

        host.set_service_locked(true);

        progress_reporter = host.serialize_publishables(publishing_params.resolution.get_pixels(),
            publishing_params.strip_metadata);

        // Serialization is a long and potentially cancellable operation, so before we use
        // the publishables, make sure that the publishing interaction is still running. If it
        // isn't the publishing environment may be partially torn down so do a short-circuit
        // return
        if (!is_running())
            return;

        Spit.Publishing.Publishable[] publishables = host.get_publishables();
        uploader = new Uploader(graph_session, publishing_params, publishables);

        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);

        uploader.upload(on_upload_status_updated);
    }
    
    private void do_show_success_pane() {
        debug("ACTION: showing success pane.");

        host.set_service_locked(false);
        host.install_success_pane();
    }

    private void on_generic_error(Spit.Publishing.PublishingError error) {
        if (error is Spit.Publishing.PublishingError.EXPIRED_SESSION)
            do_logout();
        else
            host.post_error(error);
    }

    private void on_login_clicked() {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Login' on welcome pane.");

        do_test_connection_to_endpoint();
    }

    private void on_endpoint_test_completed(GraphMessage message) {
        message.completed.disconnect(on_endpoint_test_completed);
        message.failed.disconnect(on_endpoint_test_error);

        if (!is_running())
            return;

        debug("EVENT: endpoint test transaction detected that the Facebook endpoint is alive.");

        do_hosted_web_authentication();
    }

    private void on_endpoint_test_error(GraphMessage message,
        Spit.Publishing.PublishingError error) {
        message.completed.disconnect(on_endpoint_test_completed);
        message.failed.disconnect(on_endpoint_test_error);

        if (!is_running())
            return;

        debug("EVENT: endpoint test transaction failed to detect a connection to the Facebook " +
            "endpoint");

        on_generic_error(error);
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
        graph_session.authenticated.disconnect(on_session_authenticated);
        
        if (!is_running())
            return;

        assert(graph_session.is_authenticated());
        debug("EVENT: an authenticated session has become available.");

        do_save_session_information();
        do_fetch_user_info();
    }
    
    private void on_fetch_user_info_completed(GraphMessage message) {
        message.completed.disconnect(on_fetch_user_info_completed);
        message.failed.disconnect(on_fetch_user_info_error);

        if (!is_running())
            return;

        debug("EVENT: user info fetch completed; response = '%s'.", message.get_response_body());
        
        do_extract_user_info_from_json(message.get_response_body());
    }
    
    private void on_fetch_user_info_error(GraphMessage message,
        Spit.Publishing.PublishingError error) {
        message.completed.disconnect(on_fetch_user_info_completed);
        message.failed.disconnect(on_fetch_user_info_error);
        
        if (!is_running())
            return;

        debug("EVENT: fetching user info generated and error.");

        on_generic_error(error);
    }
    
    private void on_user_info_extracted() {
        if (!is_running())
            return;

        debug("EVENT: user info extracted from JSON response: uid = %s; name = %s.", uid, username);

        do_fetch_album_descriptions();
    }
    
    private void on_fetch_albums_completed(GraphMessage message) {
        message.completed.disconnect(on_fetch_albums_completed);
        message.failed.disconnect(on_fetch_albums_error);
        
        if (!is_running())
            return;

        debug("EVENT: album descriptions fetch transaction completed; response = '%s'.",
            message.get_response_body());

        do_extract_albums_from_json(message.get_response_body());
    }
    
    private void on_fetch_albums_error(GraphMessage message,
        Spit.Publishing.PublishingError err) {
        message.completed.disconnect(on_fetch_albums_completed);
        message.failed.disconnect(on_fetch_albums_error);
        
        if (!is_running())
            return;

        debug("EVENT: album description fetch attempt generated an error.");

        on_generic_error(err);
    }

    private void on_albums_extracted() {
        if (!is_running())
            return;

        debug("EVENT: successfully extracted %d albums from JSON response",
            publishing_params.albums.length);

        do_show_publishing_options_pane();
    }

    private void on_publishing_options_pane_logout() {
        publishing_options_pane.publish.disconnect(on_publishing_options_pane_publish);
        publishing_options_pane.logout.disconnect(on_publishing_options_pane_logout);

        if (!is_running())
            return;

        debug("EVENT: user clicked 'Logout' in publishing options pane.");

        do_logout();
    }

    private void on_publishing_options_pane_publish(string? target_album, string privacy_setting,
        Resolution resolution, bool strip_metadata) {
        publishing_options_pane.publish.disconnect(on_publishing_options_pane_publish);
        publishing_options_pane.logout.disconnect(on_publishing_options_pane_logout);
        
        if (!is_running())
            return;
        
        debug("EVENT: user clicked 'Publish' in publishing options pane.");
        
        publishing_params.strip_metadata = strip_metadata;
        set_persistent_strip_metadata(strip_metadata);
        publishing_params.resolution = resolution;
        set_persistent_default_size(resolution);
        publishing_params.privacy_object = privacy_setting;
        
        if (target_album != null) {
            // we are publishing at least one photo so we need the name of an album to which
            // we'll upload the photo(s)
            publishing_params.set_target_album_by_name(target_album);
            if (publishing_params.target_album != PublishingParameters.UNKNOWN_ALBUM) {
                do_upload();
            } else {
                publishing_params.new_album_name = target_album;
                do_create_new_album();
            }
        } else {
            // we're publishing only videos and we don't need an album name
            do_upload();
        }
    }
    
    private void on_create_album_completed(GraphMessage message) {
        message.completed.disconnect(on_create_album_completed);
        message.failed.disconnect(on_create_album_error);
        
        assert(publishing_params.new_album_name != null);
        
        if (!is_running())
            return;

        debug("EVENT: created new album resource on remote host; response body = %s.\n",
            message.get_response_body());

        do_add_new_local_album_from_json(publishing_params.new_album_name,
            message.get_response_body());
    }
    
    private void on_create_album_error(GraphMessage message, Spit.Publishing.PublishingError err) {
        message.completed.disconnect(on_create_album_completed);
        message.failed.disconnect(on_create_album_error);

        if (!is_running())
            return;

        debug("EVENT: attempt to create new album generated an error.");

        on_generic_error(err);
    }
    
    private void on_upload_status_updated(int file_number, double completed_fraction) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);

        progress_reporter(file_number, completed_fraction);
    }

    private void on_upload_complete(Uploader uploader, int num_published) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);
        
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload complete; %d items published.", num_published);

        do_show_success_pane();
    }

    private void on_upload_error(Uploader uploader, Spit.Publishing.PublishingError err) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);
        
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload error = '%s'.", err.message);

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
        publishing_params = new PublishingParameters();

        // Do we have saved user credentials? If so, go ahead and authenticate the session
        // with the saved credentials and proceed with the publishing interaction. Otherwise, show
        // the Welcome pane
        if (is_persistent_session_valid()) {
            graph_session.authenticate(get_persistent_access_token());
        } else {
            if (WebAuthenticationPane.is_cache_dirty()) {
                host.set_service_locked(false);
                host.install_static_message_pane(RESTART_ERROR_MESSAGE,
                    Spit.Publishing.PluginHost.ButtonMode.CANCEL);
            } else {
                do_show_service_welcome_pane();
            }
        }
    }

    public void stop() {
        debug("FacebookPublisher: stop( ) invoked.");

        if (graph_session != null)
            graph_session.stop_transactions();

        host = null;
        running = false;
    }
    
    public bool is_running() {
        return running;
    }
}

internal class WebAuthenticationPane : Spit.Publishing.DialogPane, Object {
    private WebKit.WebView webview = null;
    private Gtk.Box pane_widget = null;
    private Gtk.ScrolledWindow webview_frame = null;
    private static bool cache_dirty = false;

    public signal void login_succeeded(string success_url);
    public signal void login_failed();

    public WebAuthenticationPane() {
        pane_widget = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

        webview_frame = new Gtk.ScrolledWindow(null, null);
        webview_frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN);
        webview_frame.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        webview = new WebKit.WebView();
        webview.get_settings().enable_plugins = false;
        webview.get_settings().enable_default_context_menu = false;

        webview.load_finished.connect(on_page_load);
        webview.load_started.connect(on_load_started);

        webview_frame.add(webview);
        pane_widget.pack_start(webview_frame, true, true, 0);
    }
    
    private class LocaleLookup {
        public string prefix;
        public string translation;
        public string? exception_code;
        public string? exception_translation;
        public string? exception_code_2;
        public string? exception_translation_2;
        
        public LocaleLookup(string prefix, string translation, string? exception_code = null, 
            string? exception_translation  = null, string? exception_code_2  = null, 
            string? exception_translation_2 = null) {
            this.prefix = prefix;
            this.translation = translation;
            this.exception_code = exception_code;
            this.exception_translation = exception_translation;
            this.exception_code_2 = exception_code_2;
            this.exception_translation_2 = exception_translation_2;
        }
        
    }
    
    private LocaleLookup[] locale_lookup_table = {
        new LocaleLookup( "es", "es-la", "ES", "es-es" ),
        new LocaleLookup( "en", "en-gb", "US", "en-us" ),
        new LocaleLookup( "fr", "fr-fr", "CA", "fr-ca" ),
        new LocaleLookup( "pt", "pt-br", "PT", "pt-pt" ),
        new LocaleLookup( "zh", "zh-cn", "HK", "zh-hk", "TW", "zh-tw" ),
        new LocaleLookup( "af", "af-za" ),
        new LocaleLookup( "ar", "ar-ar" ),
        new LocaleLookup( "nb", "nb-no" ),
        new LocaleLookup( "no", "nb-no" ),
        new LocaleLookup( "id", "id-id" ),
        new LocaleLookup( "ms", "ms-my" ),
        new LocaleLookup( "ca", "ca-es" ),
        new LocaleLookup( "cs", "cs-cz" ),
        new LocaleLookup( "cy", "cy-gb" ),
        new LocaleLookup( "da", "da-dk" ),
        new LocaleLookup( "de", "de-de" ),
        new LocaleLookup( "tl", "tl-ph" ),
        new LocaleLookup( "ko", "ko-kr" ),
        new LocaleLookup( "hr", "hr-hr" ),
        new LocaleLookup( "it", "it-it" ),
        new LocaleLookup( "lt", "lt-lt" ),
        new LocaleLookup( "hu", "hu-hu" ),
        new LocaleLookup( "nl", "nl-nl" ),
        new LocaleLookup( "ja", "ja-jp" ),
        new LocaleLookup( "nb", "nb-no" ),
        new LocaleLookup( "no", "nb-no" ),
        new LocaleLookup( "pl", "pl-pl" ),
        new LocaleLookup( "ro", "ro-ro" ),
        new LocaleLookup( "ru", "ru-ru" ),
        new LocaleLookup( "sk", "sk-sk" ),
        new LocaleLookup( "sl", "sl-si" ),
        new LocaleLookup( "sv", "sv-se" ),
        new LocaleLookup( "th", "th-th" ),
        new LocaleLookup( "vi", "vi-vn" ),
        new LocaleLookup( "tr", "tr-tr" ),
        new LocaleLookup( "el", "el-gr" ),
        new LocaleLookup( "bg", "bg-bg" ),
        new LocaleLookup( "sr", "sr-rs" ),
        new LocaleLookup( "he", "he-il" ),
        new LocaleLookup( "hi", "hi-in" ),
        new LocaleLookup( "bn", "bn-in" ),
        new LocaleLookup( "pa", "pa-in" ),
        new LocaleLookup( "ta", "ta-in" ),
        new LocaleLookup( "te", "te-in" ),
        new LocaleLookup( "ml", "ml-in" )
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

        return "https://%s.facebook.com/dialog/oauth?client_id=%s&redirect_uri=https://www.facebook.com/connect/login_success.html&scope=publish_actions,user_photos,user_videos&response_type=token".printf(facebook_locale, APPLICATION_ID);
    }

    private void on_page_load(WebKit.WebFrame origin_frame) {
        pane_widget.get_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));

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
        pane_widget.get_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
    }

    public static bool is_cache_dirty() {
        return cache_dirty;
    }

    public Gtk.Widget get_widget() {
        return pane_widget;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        webview.open(get_login_url());
    }

    public void on_pane_uninstalled() {
    }
}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {
    private Gtk.Builder builder;
    private Gtk.Box pane_widget = null;
    private Gtk.RadioButton use_existing_radio = null;
    private Gtk.RadioButton create_new_radio = null;
    private Gtk.ComboBoxText existing_albums_combo = null;
    private Gtk.ComboBoxText visibility_combo = null;
    private Gtk.Entry new_album_entry = null;
    private Gtk.CheckButton strip_metadata_check = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private Gtk.Label how_to_label = null;
    private Album[] albums = null;
    private FacebookPublisher publisher = null;
    private PrivacyDescription[] privacy_descriptions;

    private Resolution[] possible_resolutions;
    private Gtk.ComboBoxText resolution_combo = null;

    private Spit.Publishing.Publisher.MediaType media_type;

    private const string HEADER_LABEL_TEXT = _("You are logged into Facebook as %s.\n\n");
    private const string PHOTOS_LABEL_TEXT = _("Where would you like to publish the selected photos?");
    private const string RESOLUTION_LABEL_TEXT = _("Upload _size:");
    private const int CONTENT_GROUP_SPACING = 32;
    private const int STANDARD_ACTION_BUTTON_WIDTH = 128;

    public signal void logout();
    public signal void publish(string? target_album, string privacy_setting,
        Resolution target_resolution, bool strip_metadata);

    private class PrivacyDescription {
        public string description;
        public string privacy_setting;

        public PrivacyDescription(string description, string privacy_setting) {
            this.description = description;
            this.privacy_setting = privacy_setting;
        }
    }

    public PublishingOptionsPane(string username, Album[] albums,
        Spit.Publishing.Publisher.MediaType media_type, FacebookPublisher publisher,
        Gtk.Builder builder, bool strip_metadata) {

        this.builder = builder;
        assert(builder != null);
        assert(builder.get_objects().length() > 0);

        this.albums = albums;
        this.privacy_descriptions = create_privacy_descriptions();

        this.possible_resolutions = create_resolution_list();
        this.publisher = publisher;

        // we'll need to know if the user is importing video or not when sorting out visibility.
        this.media_type = media_type;

        pane_widget = (Gtk.Box) builder.get_object("facebook_pane_box");
        pane_widget.set_border_width(16);

        use_existing_radio = (Gtk.RadioButton) this.builder.get_object("use_existing_radio");
        create_new_radio = (Gtk.RadioButton) this.builder.get_object("create_new_radio");
        existing_albums_combo = (Gtk.ComboBoxText) this.builder.get_object("existing_albums_combo");
        visibility_combo = (Gtk.ComboBoxText) this.builder.get_object("visibility_combo");
        publish_button = (Gtk.Button) this.builder.get_object("publish_button");
        logout_button = (Gtk.Button) this.builder.get_object("logout_button");
        new_album_entry = (Gtk.Entry) this.builder.get_object("new_album_entry");
        resolution_combo = (Gtk.ComboBoxText) this.builder.get_object("resolution_combo");
        how_to_label = (Gtk.Label) this.builder.get_object("how_to_label");
        strip_metadata_check = (Gtk.CheckButton) this.builder.get_object("strip_metadata_check");

        create_new_radio.clicked.connect(on_create_new_toggled);
        use_existing_radio.clicked.connect(on_use_existing_toggled);

        string label_text = HEADER_LABEL_TEXT.printf(username);
        if ((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) != 0)
            label_text += PHOTOS_LABEL_TEXT;
        how_to_label.set_label(label_text);
        strip_metadata_check.set_active(strip_metadata);

        setup_visibility_combo();
        visibility_combo.set_active(0);

        publish_button.clicked.connect(on_publish_button_clicked);
        logout_button.clicked.connect(on_logout_button_clicked);
        
        setup_resolution_combo();
        resolution_combo.set_active(publisher.get_persistent_default_size());
        resolution_combo.changed.connect(on_size_changed);
        
        // Ticket #3175, part 2: make sure this widget starts out sensitive
        // if it needs to by checking whether we're starting with a video
        // or a new gallery.
        visibility_combo.set_sensitive(
            (create_new_radio != null && create_new_radio.active) ||
            ((media_type & Spit.Publishing.Publisher.MediaType.VIDEO) != 0));
        
        // if publishing only videos, disable all photo-specific controls
        if (media_type == Spit.Publishing.Publisher.MediaType.VIDEO) {
            strip_metadata_check.set_active(false);
            strip_metadata_check.set_sensitive(false);
            resolution_combo.set_sensitive(false);
            use_existing_radio.set_sensitive(false);
            create_new_radio.set_sensitive(false);
            existing_albums_combo.set_sensitive(false);
            new_album_entry.set_sensitive(false);
        }
    }
    
    private bool publishing_photos() {
        return (media_type & Spit.Publishing.Publisher.MediaType.PHOTO) != 0;
    }

    private void setup_visibility_combo() {
        foreach (PrivacyDescription p in privacy_descriptions)
            visibility_combo.append_text(p.description);
    }

    private void setup_resolution_combo() {
        foreach (Resolution res in possible_resolutions)
            resolution_combo.append_text(res.get_name());
    }

    private void on_use_existing_toggled() {
        if (use_existing_radio.active) {
            existing_albums_combo.set_sensitive(true);
            new_album_entry.set_sensitive(false);

            // Ticket #3175 - if we're not adding a new gallery
            // or a video, then we shouldn't be allowed tof
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

        Resolution resolution_setting;

        if (publishing_photos()) {        
            resolution_setting = possible_resolutions[resolution_combo.get_active()];
            if (use_existing_radio.active) {
                album_name = existing_albums_combo.get_active_text();
            } else {
                album_name = new_album_entry.get_text();
            }
        } else {
            resolution_setting = Resolution.STANDARD;
            album_name = null;
        }

        publish(album_name, privacy_setting, resolution_setting, strip_metadata_check.get_active());
    }

    private PrivacyDescription[] create_privacy_descriptions() {
        PrivacyDescription[] result = new PrivacyDescription[0];

        result += new PrivacyDescription(_("Just me"), "{ 'value' : 'SELF' }");
        result += new PrivacyDescription(_("Friends"), "{ 'value' : 'ALL_FRIENDS' }");
        result += new PrivacyDescription(_("Everyone"), "{ 'value' : 'EVERYONE' }");

        return result;
    }

    private Resolution[] create_resolution_list() {
        Resolution[] result = new Resolution[0];

        result += Resolution.STANDARD;
        result += Resolution.HIGH;

        return result;
    }

    public void installed() {
        if (publishing_photos()) {
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
        }

        publish_button.grab_focus();
    }

    private void notify_logout() {
        logout();
    }

    private void notify_publish(string? target_album, string privacy_setting, Resolution target_resolution) {
        publish(target_album, privacy_setting, target_resolution, strip_metadata_check.get_active());
    }

    public Gtk.Widget get_widget() {
        return pane_widget;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        logout.connect(notify_logout);
        publish.connect(notify_publish);

        installed();
    }

    public void on_pane_uninstalled() {
        logout.disconnect(notify_logout);
        publish.disconnect(notify_publish);
    }
}

internal enum Endpoint {
    DEFAULT,
    VIDEO,
    TEST_CONNECTION;
    
    public string to_uri() {
        switch (this) {
            case DEFAULT:
                return "https://graph.facebook.com/";
                
            case VIDEO:
                return "https://graph-video.facebook.com/";
                
            case TEST_CONNECTION:
                return "https://www.facebook.com/";
                
            default:
                assert_not_reached();
        }
    }
}

internal abstract class GraphMessage {
    public signal void completed();
    public signal void failed(Spit.Publishing.PublishingError err);
    public signal void data_transmitted(int bytes_sent_so_far, int total_bytes);

    public abstract string get_uri();
    public abstract string get_response_body();
}

internal class GraphSession {
    private abstract class GraphMessageImpl : GraphMessage {
        public Publishing.RESTSupport.HttpMethod method;
        public string uri;
        public string access_token;
        public Soup.Message soup_message;
        public weak GraphSession host_session;
        public int bytes_so_far;
        
        public GraphMessageImpl(GraphSession host_session, Publishing.RESTSupport.HttpMethod method,
            string relative_uri, string access_token, Endpoint endpoint = Endpoint.DEFAULT) {
            this.method = method;
            this.access_token = access_token;
            this.host_session = host_session;
            this.bytes_so_far = 0;
            
            string endpoint_uri = endpoint.to_uri();
            try {
                Regex starting_slashes = new Regex("^/+");
                this.uri = endpoint_uri + starting_slashes.replace(relative_uri, -1, 0, "");
            } catch (RegexError err) {
                assert_not_reached();
            }
        }
        
        public virtual bool prepare_for_transmission() {
            return true;
        }

        public override string get_uri() {
            return uri;
        }
    
        public override string get_response_body() {
            return (string) soup_message.response_body.data;
        }
        
        public void on_wrote_body_data(Soup.Buffer chunk) {
            bytes_so_far += (int) chunk.length;
            
            data_transmitted(bytes_so_far, (int) soup_message.request_body.length);
        }
    }
    
    private class GraphQueryMessage : GraphMessageImpl {
        public GraphQueryMessage(GraphSession host_session, string relative_uri,
            string access_token) {
            base(host_session, Publishing.RESTSupport.HttpMethod.GET, relative_uri, access_token);

            Soup.URI destination_uri = new Soup.URI(uri + "?access_token=" + access_token);
            soup_message = new Soup.Message.from_uri(method.to_string(), destination_uri);
            soup_message.wrote_body_data.connect(on_wrote_body_data);
        }
    }
    
    private class GraphEndpointProbeMessage : GraphMessageImpl {
        public GraphEndpointProbeMessage(GraphSession host_session) {
            base(host_session, Publishing.RESTSupport.HttpMethod.GET, "/", "",
                Endpoint.TEST_CONNECTION);

            soup_message = new Soup.Message.from_uri(method.to_string(), new Soup.URI(uri));
            soup_message.wrote_body_data.connect(on_wrote_body_data);
        }
    }
    
    private class GraphUploadMessage : GraphMessageImpl {
        private MappedFile mapped_file = null;
        private Spit.Publishing.Publishable publishable;
        
        public GraphUploadMessage(GraphSession host_session, string access_token,
            string relative_uri, Spit.Publishing.Publishable publishable,
            bool suppress_titling, string? resource_privacy = null) {
            base(host_session, Publishing.RESTSupport.HttpMethod.POST, relative_uri, access_token,
                (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.VIDEO) ?
                Endpoint.VIDEO : Endpoint.DEFAULT);
            
            // Video uploads require a privacy string at the per-resource level. Since they aren't
            // placed in albums, they can't inherit their privacy settings from their containing
            // album like photos do
            assert(publishable.get_media_type() != Spit.Publishing.Publisher.MediaType.VIDEO ||
                resource_privacy != null);
            
            this.publishable = publishable;
            
            // attempt to map the binary payload from disk into memory
            try {
                this.mapped_file = new MappedFile(publishable.get_serialized_file().get_path(),
                    false);
            } catch (FileError e) {
                return;
            }
            
            this.soup_message = new Soup.Message.from_uri(method.to_string(), new Soup.URI(uri));
            soup_message.wrote_body_data.connect(on_wrote_body_data);
            
            unowned uint8[] payload = (uint8[]) mapped_file.get_contents();
            payload.length = (int) mapped_file.get_length();
            
            Soup.Buffer image_data = new Soup.Buffer(Soup.MemoryUse.TEMPORARY, payload);
            
            Soup.Multipart mp_envelope = new Soup.Multipart("multipart/form-data");
            
            mp_envelope.append_form_string("access_token", access_token);
            
            if (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.VIDEO)
                mp_envelope.append_form_string("privacy", resource_privacy);
            
            string publishable_title = publishable.get_publishing_name();
            if (!suppress_titling && publishable_title != "")
                mp_envelope.append_form_string("name", publishable_title);

            string source_file_mime_type =
                (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.VIDEO) ?
                "video" : "image/jpeg";
            mp_envelope.append_form_file("source", publishable.get_serialized_file().get_basename(),
                source_file_mime_type, image_data);
            
            mp_envelope.to_message(soup_message.request_headers, soup_message.request_body);
        }
        
        public override bool prepare_for_transmission() {
            if (mapped_file == null) {
                failed(new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    "File %s is unavailable.".printf(publishable.get_serialized_file().get_path())));
                return false;
            } else {
                return true;
            }
        }
    }

    private class GraphCreateAlbumMessage : GraphMessageImpl {
        public GraphCreateAlbumMessage(GraphSession host_session, string access_token,
            string album_name, string album_privacy) {
            base(host_session, Publishing.RESTSupport.HttpMethod.POST, "/me/albums", access_token);
            
            assert(album_privacy != null && album_privacy != "");
            
            this.soup_message = new Soup.Message.from_uri(method.to_string(), new Soup.URI(uri));
            
            Soup.Multipart mp_envelope = new Soup.Multipart("multipart/form-data");

            mp_envelope.append_form_string("access_token", access_token);
            mp_envelope.append_form_string("name", album_name);
            mp_envelope.append_form_string("privacy", album_privacy);
            
            mp_envelope.to_message(soup_message.request_headers, soup_message.request_body);
        }
    }

    public signal void authenticated();
    
    private Soup.Session soup_session;
    private string? access_token;
    private GraphMessage? current_message;
    
    public GraphSession() {
        this.soup_session = new Soup.SessionAsync();
        this.soup_session.request_unqueued.connect(on_request_unqueued);
        this.soup_session.timeout = 15;
        this.access_token = null;
        this.current_message = null;
    }

    ~GraphSession() {
         soup_session.request_unqueued.disconnect(on_request_unqueued);
     }
    
    private void manage_message(GraphMessage msg) {
        assert(current_message == null);
        
        current_message = msg;
    }
    
    private void unmanage_message(GraphMessage msg) {
        assert(current_message != null);
        
        current_message = null;
    }

     private void on_request_unqueued(Soup.Message msg) {
        assert(current_message != null);
        GraphMessageImpl real_message = (GraphMessageImpl) current_message;
        assert(real_message.soup_message == msg);
        
        // these error types are always recoverable given the unique behavior of the Facebook
        // endpoint, so try again
        if (msg.status_code == Soup.KnownStatusCode.IO_ERROR ||
            msg.status_code == Soup.KnownStatusCode.MALFORMED ||
            msg.status_code == Soup.KnownStatusCode.TRY_AGAIN) {
            real_message.bytes_so_far = 0;
            soup_session.queue_message(msg, null);
            return;
        }
        
        unmanage_message(real_message);
        msg.wrote_body_data.disconnect(real_message.on_wrote_body_data);
        
        Spit.Publishing.PublishingError? error = null;
        switch (msg.status_code) {
            case Soup.KnownStatusCode.OK:
            case Soup.KnownStatusCode.CREATED: // HTTP code 201 (CREATED) signals that a new
                                               // resource was created in response to a PUT
                                               // or POST
            break;
            
            case EXPIRED_SESSION_STATUS_CODE:
                error = new Spit.Publishing.PublishingError.EXPIRED_SESSION(
                    "OAuth Access Token has Expired. Logout user.", real_message.get_uri(), msg.status_code);
            break;
            
            case Soup.KnownStatusCode.CANT_RESOLVE:
            case Soup.KnownStatusCode.CANT_RESOLVE_PROXY:
                error = new Spit.Publishing.PublishingError.NO_ANSWER(
                    "Unable to resolve %s (error code %u)", real_message.get_uri(), msg.status_code);
            break;
            
            case Soup.KnownStatusCode.CANT_CONNECT:
            case Soup.KnownStatusCode.CANT_CONNECT_PROXY:
                error = new Spit.Publishing.PublishingError.NO_ANSWER(
                    "Unable to connect to %s (error code %u)", real_message.get_uri(), msg.status_code);
            break;
            
            default:
                // status codes below 100 are used by Soup, 100 and above are defined HTTP
                // codes
                if (msg.status_code >= 100) {
                    error = new Spit.Publishing.PublishingError.NO_ANSWER(
                        "Service %s returned HTTP status code %u %s", real_message.get_uri(),
                        msg.status_code, msg.reason_phrase);
                } else {
                    error = new Spit.Publishing.PublishingError.NO_ANSWER(
                        "Failure communicating with %s (error code %u)", real_message.get_uri(),
                        msg.status_code);
                }
            break;
        }

        // All valid communication with Facebook involves body data in the response
        if (error == null)
            if (msg.response_body.data == null || msg.response_body.data.length == 0)
                error = new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "No response data from %s", real_message.get_uri());
        
        if (error == null)
            real_message.completed();
        else
            real_message.failed(error);
     }
    
    public void authenticate(string access_token) {
        this.access_token = access_token;
        authenticated();
    }
    
    public bool is_authenticated() {
        return access_token != null;
    }
    
    public string get_access_token() {
        assert(is_authenticated());
        return access_token;
    }
    
    public GraphMessage new_endpoint_test() {
        return new GraphEndpointProbeMessage(this);
    }
    
    public GraphMessage new_query(string resource_path) {
        return new GraphQueryMessage(this, resource_path, access_token);
    }

    public GraphMessage new_upload(string resource_path, Spit.Publishing.Publishable publishable,
        bool suppress_titling, string? resource_privacy = null) {
        return new GraphUploadMessage(this, access_token, resource_path, publishable,
            suppress_titling, resource_privacy);
    }
    
    public GraphMessage new_create_album(string album_name, string privacy) {
        return new GraphSession.GraphCreateAlbumMessage(this, access_token, album_name, privacy);
    }
    
    public void send_message(GraphMessage message) {
        GraphMessageImpl real_message = (GraphMessageImpl) message;
        
        debug("making HTTP request to URI: " + real_message.soup_message.uri.to_string(false));
        
        if (real_message.prepare_for_transmission()) {
            manage_message(message);
            soup_session.queue_message(real_message.soup_message, null);
        }
    }
    
    public void stop_transactions() {
        soup_session.abort();
    }
}

internal class Uploader {
    private int current_file;
    private Spit.Publishing.Publishable[] publishables;
    private GraphSession session;
    private PublishingParameters publishing_params;
	private unowned Spit.Publishing.ProgressCallback? status_updated = null;

    public signal void upload_complete(int num_photos_published);
    public signal void upload_error(Spit.Publishing.PublishingError err);

    public Uploader(GraphSession session, PublishingParameters publishing_params,
        Spit.Publishing.Publishable[] publishables) {
        this.current_file = 0;
        this.publishables = publishables;
        this.session = session;
        this.publishing_params = publishing_params;
    }
    
    private void send_current_file() {
        Spit.Publishing.Publishable publishable = publishables[current_file];
        GLib.File? file = publishable.get_serialized_file();
            
        // if the current publishable hasn't been serialized, then skip it
        if (file == null) {
            current_file++;
            return;
        }
        
        string resource_uri =
            (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.PHOTO) ?
            "/%s/photos".printf(publishing_params.get_target_album_id()) : "/me/videos";
        string? resource_privacy =
            (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.VIDEO) ?
            publishing_params.privacy_object : null;
        GraphMessage upload_message = session.new_upload(resource_uri, publishable,
            publishing_params.strip_metadata, resource_privacy);

        upload_message.data_transmitted.connect(on_chunk_transmitted);
        upload_message.completed.connect(on_message_completed);
        upload_message.failed.connect(on_message_failed);
        
        session.send_message(upload_message);
    }

    private void send_files() {
        current_file = 0;
        send_current_file();
    }
    
    private void on_chunk_transmitted(int bytes_written_so_far, int total_bytes) {
        double file_span = 1.0 / publishables.length;
        double this_file_fraction_complete = ((double) bytes_written_so_far) / total_bytes;
        double fraction_complete = (current_file * file_span) + (this_file_fraction_complete *
            file_span);

		if (status_updated != null)
	        status_updated(current_file + 1, fraction_complete);
    }
    
    private void on_message_completed(GraphMessage message) {
        message.data_transmitted.disconnect(on_chunk_transmitted);
        message.completed.disconnect(on_message_completed);
        message.failed.disconnect(on_message_failed);

        current_file++;
        if (current_file < publishables.length) {
            send_current_file();
        } else {
            upload_complete(current_file);
        }
    }
    
    private void on_message_failed(GraphMessage message, Spit.Publishing.PublishingError error) {
        message.data_transmitted.disconnect(on_chunk_transmitted);
        message.completed.disconnect(on_message_completed);
        message.failed.disconnect(on_message_failed);
        
        upload_error(error);
    }
        
    public void upload(Spit.Publishing.ProgressCallback? status_updated = null) {
        this.status_updated = status_updated;

        if (publishables.length > 0)
           send_files();
    }
}

}

