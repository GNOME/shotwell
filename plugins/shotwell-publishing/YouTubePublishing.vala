/* Copyright 2009-2013 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class YouTubeService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "youtube.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;

    public YouTubeService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_icon_set(resource_directory.get_child(ICON_FILENAME));
    }

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }

    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.youtube";
    }

    public unowned string get_pluggable_name() {
        return "YouTube";
    }

    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Jani Monoses\nLucas Beeler";
        info.copyright = _("Copyright 2009-2013 Yorba Foundation");
        info.translators = Resources.TRANSLATORS;
        info.version = _VERSION;
        info.website_name = Resources.WEBSITE_NAME;
        info.website_url = Resources.WEBSITE_URL;
        info.is_license_wordwrapped = false;
        info.license = Resources.LICENSE;
        info.icons = icon_pixbuf_set;
    }

    public Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host) {
        return new Publishing.YouTube.YouTubePublisher(this, host);
    }

    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return Spit.Publishing.Publisher.MediaType.VIDEO;
    }

    public void activation(bool enabled) {
    }
}

namespace Publishing.YouTube {

private const string SERVICE_WELCOME_MESSAGE =
    _("You are not currently logged into YouTube.\n\nYou must have already signed up for a Google account and set it up for use with YouTube to continue. You can set up most accounts by using your browser to log into the YouTube site at least once.");
private const string DEVELOPER_KEY =
    "AI39si5VEpzWK0z-pzo4fonEj9E4driCpEs9lK8y3HJsbbebIIRWqW3bIyGr42bjQv-N3siAfqVoM8XNmtbbp5x2gpbjiSAMTQ";
internal const string OAUTH_CLIENT_ID = "1073902228337-gm4uf5etk25s0hnnm0g7uv2tm2bm1j0b.apps.googleusercontent.com";
internal const string OAUTH_CLIENT_SECRET = "_kA4RZz72xqed4DqfO7xMmMN";
    
private enum PrivacySetting {
    PUBLIC,
    UNLISTED,
    PRIVATE
}

private class PublishingParameters {
    private PrivacySetting privacy_setting;

    public PublishingParameters(PrivacySetting privacy_setting) {
        this.privacy_setting = privacy_setting;
    }

    public PrivacySetting get_privacy_setting() {
        return this.privacy_setting;
    }
}

public class YouTubePublisher : Spit.Publishing.Publisher, GLib.Object {
    private weak Spit.Publishing.PluginHost host = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private weak Spit.Publishing.Service service = null;
    private bool running = false;
    private Session session;
    private string? username = null;
    private PublishingParameters parameters = null;
    private string? channel_name = null;
    private WebAuthenticationPane? web_auth_pane = null;

    public YouTubePublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        this.service = service;
        this.host = host;
        this.session = new Session();
    }

    private string extract_channel_name(Xml.Node* document_root) throws
        Spit.Publishing.PublishingError {
        string result = "";

        Xml.Node* doc_node_iter = null;
        if (document_root->name == "feed")
            doc_node_iter = document_root->children;
        else if (document_root->name == "entry")
            doc_node_iter = document_root;
        else
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                "response root node isn't a <feed> or <entry>");

        for ( ; doc_node_iter != null; doc_node_iter = doc_node_iter->next) {
            if (doc_node_iter->name != "entry")
                continue;

            string name_val = null;
            string url_val = null;
            Xml.Node* channel_node_iter = doc_node_iter->children;
            for ( ; channel_node_iter != null; channel_node_iter = channel_node_iter->next) {
                if (channel_node_iter->name == "title") {
                    name_val = channel_node_iter->get_content();
                } else if (channel_node_iter->name == "id") {
                    // we only want nodes in the default namespace -- the feed that we get back
                    // from Google also defines <entry> child nodes named <id> in the media
                    // namespace
                    if (channel_node_iter->ns->prefix != null)
                        continue;
                    url_val = channel_node_iter->get_content();
                }
            }

            result = name_val;
            break;
        }

        debug("YouTubePublisher: extracted channel name '%s' from response XML.", result);

        return result;
    }

    internal void set_persistent_refresh_token(string token) {
        host.set_config_string("refresh_token", token);
    }

    internal string? get_persistent_refresh_token() {
        return host.get_config_string("refresh_token", null);
    }

    internal void invalidate_persistent_session() {
        debug("invalidating persisted YouTube session.");

        host.unset_config_key("refresh_name");
    }

    internal bool is_persistent_session_available() {
        return (get_persistent_refresh_token() != null);
    }

    public bool is_running() {
        return running;
    }

    public Spit.Publishing.Service get_service() {
        return service;
    }

    private void on_service_welcome_login() {
        debug("EVENT: user clicked 'Login' in welcome pane.");

        if (!is_running())
            return;
        
        do_web_authentication();
    }
    
    private void on_web_auth_pane_authorized(string auth_code) {
        web_auth_pane.authorized.disconnect(on_web_auth_pane_authorized);
        
        debug("EVENT: user authorized application; auth_code = '%s'", auth_code);
        
        if (!is_running())
            return;
        
        do_get_access_tokens(auth_code);
    }

    private void on_get_access_tokens_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_get_access_tokens_complete);
        txn.network_error.disconnect(on_get_access_tokens_error);

        debug("EVENT: network transaction to exchange authorization code for access tokens " +
            "completed successfully.");

        if (!is_running())
            return;

        do_extract_tokens(txn.get_response());
    }
    
    private void on_get_access_tokens_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_get_access_tokens_complete);
        txn.network_error.disconnect(on_get_access_tokens_error);

        debug("EVENT: network transaction to exchange authorization code for access tokens " +
            "failed; response = '%s'", txn.get_response());

        if (!is_running())
            return;

        host.post_error(err);
    }

    private void on_refresh_token_available(string token) {
        debug("EVENT: an OAuth refresh token has become available.");

        if (!is_running())
            return;

        do_save_refresh_token_to_configuration_system(token);
    }
    
    private void on_access_token_available(string token) {
        debug("EVENT: an OAuth access token has become available.");

        if (!is_running())
            return;

        do_authenticate_session(token);
    }

    private void on_refresh_access_token_transaction_completed(Publishing.RESTSupport.Transaction
        txn) {
        txn.completed.disconnect(on_refresh_access_token_transaction_completed);
        txn.network_error.disconnect(on_refresh_access_token_transaction_error);

        debug("EVENT: refresh access token transaction completed successfully.");

        if (!is_running())
            return;

        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;
        
        do_extract_tokens(txn.get_response());
    }
    
    private void on_refresh_access_token_transaction_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_refresh_access_token_transaction_completed);
        txn.network_error.disconnect(on_refresh_access_token_transaction_error);

        debug("EVENT: refresh access token transaction caused a network error.");

        if (!is_running())
            return;

        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;
        
        // 400 errors indicate that the OAuth client ID and secret have become invalid. In most
        // cases, this can be fixed by logging the user out
        if (txn.get_status_code() == 400) {
            do_logout();
            return;
        }
        
        host.post_error(err);       
    }

    private void on_fetch_username_transaction_completed(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_fetch_username_transaction_completed);
        txn.network_error.disconnect(on_fetch_username_transaction_error);
        
        debug("EVENT: username fetch transaction completed successfully.");

        if (!is_running())
            return;

        do_extract_username(txn.get_response());
        do_fetch_account_information();
    }
    
    private void on_fetch_username_transaction_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_fetch_username_transaction_completed);
        txn.network_error.disconnect(on_fetch_username_transaction_error);

        debug("EVENT: username fetch transaction caused a network error");

        if (!is_running())
            return;

        host.post_error(err);
    }

    private void on_session_authenticated() {
        session.authenticated.disconnect(on_session_authenticated);

        debug("EVENT: an authenticated session has become available.");

        if (!is_running())
            return;
        
        do_fetch_username();
    }

    private void on_initial_channel_fetch_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_initial_channel_fetch_complete);
        txn.network_error.disconnect(on_initial_channel_fetch_error);

        debug("EVENT: finished fetching account and channel information.");

        if (!is_running())
            return;

        do_parse_and_display_account_information((ChannelDirectoryTransaction) txn);
    }

    private void on_initial_channel_fetch_error(Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_initial_channel_fetch_complete);
        bad_txn.network_error.disconnect(on_initial_channel_fetch_error);

        debug("EVENT: fetching account and channel information failed; response = '%s'.",
            bad_txn.get_response());

        if (!is_running())
            return;

        host.post_error(err);
    }

    private void on_publishing_options_logout() {
        debug("EVENT: user clicked 'Logout' in the publishing options pane.");

        if (!is_running())
            return;

        do_logout();
    }

    private void on_publishing_options_publish(PublishingParameters parameters) {
        debug("EVENT: user clicked 'Publish' in the publishing options pane.");

        this.parameters = parameters;

        if (!is_running())
            return;

        do_upload();
    }

    private void on_upload_status_updated(int file_number, double completed_fraction) {
        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);
        
        if (!is_running())
            return;

        progress_reporter(file_number, completed_fraction);
    }

    private void on_upload_complete(Publishing.RESTSupport.BatchUploader uploader,
        int num_published) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);
        
        debug("EVENT: uploader reports upload complete; %d items published.", num_published);

        if (!is_running())
            return;

        do_show_success_pane();
    }

    private void on_upload_error(Publishing.RESTSupport.BatchUploader uploader,
        Spit.Publishing.PublishingError err) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);
        
        debug("EVENT: uploader reports upload error = '%s'.", err.message);

        if (!is_running())
            return;

        host.post_error(err);
    }

    private void do_show_service_welcome_pane() {
        debug("ACTION: showing service welcome pane.");

        host.install_welcome_pane(SERVICE_WELCOME_MESSAGE, on_service_welcome_login);
    }
    
    private void do_web_authentication() {
        debug("ACTION: running OAuth web authentication flow in hosted web pane.");
        
        string user_authorization_url = "https://accounts.google.com/o/oauth2/auth?" +
            "response_type=code&" +
            "client_id=" + OAUTH_CLIENT_ID + "&" +
            "redirect_uri=" + Soup.URI.encode("urn:ietf:wg:oauth:2.0:oob", null) + "&" +
            "scope=" + Soup.URI.encode("https://gdata.youtube.com/", null) + "+" +
            Soup.URI.encode("https://www.googleapis.com/auth/userinfo.profile", null) + "&" +
            "state=connect&" +
            "access_type=offline&" +
            "approval_prompt=force";

        web_auth_pane = new WebAuthenticationPane(user_authorization_url);
        web_auth_pane.authorized.connect(on_web_auth_pane_authorized);
        
        host.install_dialog_pane(web_auth_pane);
    }
    
    private void do_get_access_tokens(string auth_code) {
        debug("ACTION: exchanging authorization code for access & refresh tokens");
        
        host.install_login_wait_pane();
        
        GetAccessTokensTransaction tokens_txn = new GetAccessTokensTransaction(session, auth_code);
        tokens_txn.completed.connect(on_get_access_tokens_complete);
        tokens_txn.network_error.connect(on_get_access_tokens_error);
        
        try {
            tokens_txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            debug("publishing error: %s", err.message);
        }
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
                "neither access_token nor refresh_token not present in server response"));
            return;
        }

        if (response_obj.has_member("refresh_token")) {
            string refresh_token = response_obj.get_string_member("refresh_token");

            if (refresh_token != "")
                on_refresh_token_available(refresh_token);
        }
        
        if (response_obj.has_member("access_token")) {
            string access_token = response_obj.get_string_member("access_token");

            if (access_token != "")
                on_access_token_available(access_token);
        }
    }

    private void do_save_refresh_token_to_configuration_system(string token) {
        debug("ACTION: saving OAuth refresh token to configuration system");
        
        set_persistent_refresh_token(token);
    }
    
    private void do_authenticate_session(string token) {
        debug("ACTION: authenticating session.");
        
        session.authenticated.connect(on_session_authenticated);
        session.authenticate(token);
    }

    private void do_refresh_session(string refresh_token) {
        debug("ACTION: using OAuth refresh token to refresh session.");
        
        host.install_login_wait_pane();
        
        RefreshAccessTokenTransaction txn = new RefreshAccessTokenTransaction(session,
            refresh_token);
        
        txn.completed.connect(on_refresh_access_token_transaction_completed);
        txn.network_error.connect(on_refresh_access_token_transaction_error);
        
        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            // don't post an error to the host -- let the error handler signal connected above
            // handle the problem
        }
    }

    private void do_fetch_username() {
        debug("ACTION: running network transaction to fetch username.");

        host.install_login_wait_pane();
        host.set_service_locked(true);
        
        UsernameFetchTransaction txn = new UsernameFetchTransaction(session);
        txn.completed.connect(on_fetch_username_transaction_completed);
        txn.network_error.connect(on_fetch_username_transaction_error);
        
        try {
            txn.execute();
        } catch (Error err) {
            host.post_error(err);
        }
    }

    private void do_extract_username(string response_body) {
        debug("ACTION: extracting username from body of server response");
        
        Json.Parser parser = new Json.Parser();
        
        try {
            parser.load_from_data(response_body);
        } catch (Error err) {
            host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                "Couldn't parse JSON response: " + err.message));
            return;
        }
        
        Json.Object response_obj = parser.get_root().get_object();

        if (response_obj.has_member("name")) {
            string username = response_obj.get_string_member("name");

            if (username != "")
                this.username = username;
        }
        
        if (response_obj.has_member("access_token")) {
            string access_token = response_obj.get_string_member("access_token");

            if (access_token != "")
                on_access_token_available(access_token);
        }
    }

    private void do_fetch_account_information() {
        debug("ACTION: fetching account and channel information.");

        host.install_account_fetch_wait_pane();
        host.set_service_locked(true);

        ChannelDirectoryTransaction directory_trans =
            new ChannelDirectoryTransaction(session);
        directory_trans.network_error.connect(on_initial_channel_fetch_error);
        directory_trans.completed.connect(on_initial_channel_fetch_complete);

        try {
            directory_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            // don't just post the error and stop publishing -- 404 and 403 errors are
            // recoverable
            on_initial_channel_fetch_error(directory_trans, err);
        }
    }

    private void do_parse_and_display_account_information(ChannelDirectoryTransaction transaction) {
        debug("ACTION: extracting account and channel information from body of server response");

        Publishing.RESTSupport.XmlDocument response_doc;
        try {
            response_doc = Publishing.RESTSupport.XmlDocument.parse_string(
                transaction.get_response(), ChannelDirectoryTransaction.validate_xml);
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
            return;
        }

        try {
            channel_name = extract_channel_name(response_doc.get_root_node());
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
            return;
        }

        do_show_publishing_options_pane();
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: showing publishing options pane.");

        Gtk.Builder builder = new Gtk.Builder();

        try {
            builder.add_from_file(
                host.get_module_file().get_parent().get_child("youtube_publishing_options_pane.glade").get_path());
        } catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            host.post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is unavailable. Publishing to Youtube can't continue.")));
            return;
        }

        PublishingOptionsPane opts_pane = new PublishingOptionsPane(host, username, channel_name, builder);
        opts_pane.publish.connect(on_publishing_options_publish);
        opts_pane.logout.connect(on_publishing_options_logout);
        host.install_dialog_pane(opts_pane);

        host.set_service_locked(false);
    }

    private void do_upload() {
        debug("ACTION: uploading media items to remote server.");

        host.set_service_locked(true);

        progress_reporter = host.serialize_publishables(-1);

        // Serialization is a long and potentially cancellable operation, so before we use
        // the publishables, make sure that the publishing interaction is still running. If it
        // isn't the publishing environment may be partially torn down so do a short-circuit
        // return
        if (!is_running())
            return;

        Spit.Publishing.Publishable[] publishables = host.get_publishables();
        Uploader uploader = new Uploader(session, publishables, parameters);

        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);

        uploader.upload(on_upload_status_updated);
    }

    private void do_show_success_pane() {
        debug("ACTION: showing success pane.");

        host.set_service_locked(false);
        host.install_success_pane();
    }

    private void do_logout() {
        debug("ACTION: logging out user.");
        
        session.deauthenticate();
        invalidate_persistent_session();

        do_show_service_welcome_pane();
    }

    public void start() {
        if (is_running())
            return;

        if (host == null)
            error("YouTubePublisher: start( ): can't start; this publisher is not restartable.");

        debug("YouTubePublisher: starting interaction.");

        running = true;

        if (is_persistent_session_available()) {
            do_refresh_session(get_persistent_refresh_token());
        } else {
            do_show_service_welcome_pane();
        }
    }

    public void stop() {
        debug("YouTubePublisher: stop( ) invoked.");

        if (session != null)
            session.stop_transactions();

        host = null;
        running = false;
    }
}

internal class Session : Publishing.RESTSupport.Session {
    private string? auth_token = null;

    public Session() {
    }

    public override bool is_authenticated() {
        return (auth_token != null);
    }

    public void authenticate(string auth_token) {
        this.auth_token = auth_token;
        
        notify_authenticated();
    }
    
    public void deauthenticate() {
        auth_token = null;
    }
    
    public string? get_auth_token() {
        return auth_token;
    }
}

internal class GetAccessTokensTransaction : Publishing.RESTSupport.Transaction {
    private const string ENDPOINT_URL = "https://accounts.google.com/o/oauth2/token";
    
    public GetAccessTokensTransaction(Session session, string auth_code) {
        base.with_endpoint_url(session, ENDPOINT_URL);
        
        add_argument("code", auth_code);
        add_argument("client_id", OAUTH_CLIENT_ID);
        add_argument("client_secret", OAUTH_CLIENT_SECRET);
        add_argument("redirect_uri", "urn:ietf:wg:oauth:2.0:oob");
        add_argument("grant_type", "authorization_code");
    }
}

internal class RefreshAccessTokenTransaction : Publishing.RESTSupport.Transaction {
    private const string ENDPOINT_URL = "https://accounts.google.com/o/oauth2/token";
    
    public RefreshAccessTokenTransaction(Session session, string refresh_token) {
        base.with_endpoint_url(session, ENDPOINT_URL);
    
        add_argument("client_id", OAUTH_CLIENT_ID);
        add_argument("client_secret", OAUTH_CLIENT_SECRET);
        add_argument("refresh_token", refresh_token);
        add_argument("grant_type", "refresh_token");
    }
}

internal class AuthenticatedTransaction : Publishing.RESTSupport.Transaction {
    private AuthenticatedTransaction.with_endpoint_url(Session session, string endpoint_url,
        Publishing.RESTSupport.HttpMethod method) {
        base.with_endpoint_url(session, endpoint_url, method);
    }

    public AuthenticatedTransaction(Session session, string endpoint_url,
        Publishing.RESTSupport.HttpMethod method) {
        base.with_endpoint_url(session, endpoint_url, method);
        assert(session.is_authenticated());

        add_header("Authorization", "Bearer " + session.get_auth_token());
    }
}

internal class UsernameFetchTransaction : AuthenticatedTransaction {
    private const string ENDPOINT_URL = "https://www.googleapis.com/oauth2/v1/userinfo";
    
    public UsernameFetchTransaction(Session session) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.GET);
    }
}

internal class ChannelDirectoryTransaction : AuthenticatedTransaction {
    private const string ENDPOINT_URL = "http://gdata.youtube.com/feeds/users/default";

    public ChannelDirectoryTransaction(Session session) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.GET);
    }

    public static string? validate_xml(Publishing.RESTSupport.XmlDocument doc) {
        Xml.Node* document_root = doc.get_root_node();
        if ((document_root->name == "feed") || (document_root->name == "entry"))
            return null;
        else
            return "response root node isn't a <feed> or <entry>";
    }
}

internal class UploadTransaction : AuthenticatedTransaction {
    private const string ENDPOINT_URL = "http://uploads.gdata.youtube.com/feeds/api/users/default/uploads";
    private const string UNLISTED_XML = "<yt:accessControl action='list' permission='denied'/>";
    private const string PRIVATE_XML = "<yt:private/>";
    private const string METADATA_TEMPLATE ="""<?xml version='1.0'?>
                                                <entry xmlns='http://www.w3.org/2005/Atom'
                                                xmlns:media='http://search.yahoo.com/mrss/'
                                                xmlns:yt='http://gdata.youtube.com/schemas/2007'>
                                                <media:group>
                                                    <media:title type='plain'>%s</media:title>
                                                    <media:category
                                                    scheme='http://gdata.youtube.com/schemas/2007/categories.cat'>People
                                                    </media:category>
                                                    %s
                                                </media:group>
                                                    %s
                                                </entry>""";
    private PublishingParameters parameters;
    private Session session;
    private Spit.Publishing.Publishable publishable;

    public UploadTransaction(Session session, PublishingParameters parameters,
        Spit.Publishing.Publishable publishable) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.POST);
        assert(session.is_authenticated());
        this.session = session;
        this.parameters = parameters;
        this.publishable = publishable;
    }

    public override void execute() throws Spit.Publishing.PublishingError {
        // create the multipart request container
        Soup.Multipart message_parts = new Soup.Multipart("multipart/related");

        string unlisted_video =
            (parameters.get_privacy_setting() == PrivacySetting.UNLISTED) ? UNLISTED_XML : "";

        string private_video =
            (parameters.get_privacy_setting() == PrivacySetting.PRIVATE) ? PRIVATE_XML : "";

        // Set title to publishing name, but if that's empty default to filename.
        string title = publishable.get_publishing_name();
        if (title == "") {
            title = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        }

        string metadata = METADATA_TEMPLATE.printf(Publishing.RESTSupport.decimal_entity_encode(title),
            private_video, unlisted_video);
        Soup.Buffer metadata_buffer = new Soup.Buffer(Soup.MemoryUse.COPY, metadata.data);
        message_parts.append_form_file("", "", "application/atom+xml", metadata_buffer);

        // attempt to read the binary video data from disk
        string video_data;
        size_t data_length;
        try {
            FileUtils.get_contents(publishable.get_serialized_file().get_path(), out video_data,
                out data_length);
        } catch (FileError e) {
            string msg = "YouTube: couldn't read data from %s: %s".printf(
                publishable.get_serialized_file().get_path(), e.message);
            warning("%s", msg);

            throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(msg);
        }

        // bind the binary video data read from disk into a Soup.Buffer object so that we
        // can attach it to the multipart request, then actaully append the buffer
        // to the multipart request. Then, set the MIME type for this part.
        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.COPY, video_data.data[0:data_length]);

        message_parts.append_form_file("", publishable.get_serialized_file().get_path(), "video/mpeg",
            bindable_data);
        // create a message that can be sent over the wire whose payload is the multipart container
        // that we've been building up
        Soup.Message outbound_message =
            soup_form_request_new_from_multipart(get_endpoint_url(), message_parts);
        outbound_message.request_headers.append("X-GData-Key", "key=%s".printf(DEVELOPER_KEY));
        outbound_message.request_headers.append("Slug",
            publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME));
        outbound_message.request_headers.append("Authorization", "Bearer " + session.get_auth_token());
        set_message(outbound_message);

        // send the message and get its response
        set_is_executed(true);
        send();
    }
}

internal class WebAuthenticationPane : Spit.Publishing.DialogPane, Object {
    private WebKit.WebView webview = null;
    private Gtk.Box pane_widget = null;
    private Gtk.ScrolledWindow webview_frame = null;
    private string auth_sequence_start_url;

    public signal void authorized(string access_code);

    public WebAuthenticationPane(string auth_sequence_start_url) {
        this.auth_sequence_start_url = auth_sequence_start_url;

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
    
    private void on_page_load(WebKit.WebFrame origin_frame) {
        pane_widget.get_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
        
        string page_title = webview.get_title();
        if (page_title.index_of("state=connect") > 0) {
            int auth_code_field_start = page_title.index_of("code=");
            if (auth_code_field_start < 0)
                return;

            string auth_code =
                page_title.substring(auth_code_field_start + 5); // 5 = "code=".length
            
            stdout.printf("auth_code = %s.\n", auth_code);
            
            authorized(auth_code);
        }
    }

    private void on_load_started(WebKit.WebFrame frame) {
        pane_widget.get_window().set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }
    
    public Gtk.Widget get_widget() {
        return pane_widget;
    }

    public void on_pane_installed() {
        webview.open(auth_sequence_start_url);
    }

    public void on_pane_uninstalled() {
    }
}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {
    private class PrivacyDescription {
        public string description;
        public PrivacySetting privacy_setting;

        public PrivacyDescription(string description, PrivacySetting privacy_setting) {
            this.description = description;
            this.privacy_setting = privacy_setting;
        }
    }

    public signal void publish(PublishingParameters parameters);
    public signal void logout();

    private Gtk.Box pane_widget = null;
    private Gtk.ComboBoxText privacy_combo = null;
    private Gtk.Label publish_to_label = null;
    private Gtk.Label login_identity_label = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private Gtk.Builder builder = null;
    private Gtk.Label privacy_label = null;

    private string channel_name;
    private PrivacyDescription[] privacy_descriptions;

    public PublishingOptionsPane(Spit.Publishing.PluginHost host, string username,
        string channel_name, Gtk.Builder builder) {
        this.channel_name = channel_name;
        this.privacy_descriptions = create_privacy_descriptions();

        this.builder = builder;
        assert(builder != null);
        assert(builder.get_objects().length() > 0);

        login_identity_label = this.builder.get_object("login_identity_label") as Gtk.Label;
        privacy_combo = this.builder.get_object("privacy_combo") as Gtk.ComboBoxText;
        publish_to_label = this.builder.get_object("publish_to_label") as Gtk.Label;
        publish_button = this.builder.get_object("publish_button") as Gtk.Button;
        logout_button = this.builder.get_object("logout_button") as Gtk.Button;
        pane_widget = this.builder.get_object("youtube_pane_widget") as Gtk.Box;
        privacy_label = this.builder.get_object("privacy_label") as Gtk.Label;

        login_identity_label.set_label(_("You are logged into YouTube as %s.").printf(username));
        publish_to_label.set_label(_("Videos will appear in '%s'").printf(channel_name));

        foreach(PrivacyDescription desc in privacy_descriptions) {
            privacy_combo.append_text(desc.description);
        }

        privacy_combo.set_active(PrivacySetting.PUBLIC);
        privacy_label.set_mnemonic_widget(privacy_combo);

        logout_button.clicked.connect(on_logout_clicked);
        publish_button.clicked.connect(on_publish_clicked);
    }

    private void on_publish_clicked() {
        PrivacySetting privacy_setting = privacy_descriptions[privacy_combo.get_active()].privacy_setting;

        publish(new PublishingParameters(privacy_setting));
    }

    private void on_logout_clicked() {
        logout();
    }

    private void update_publish_button_sensitivity() {
        publish_button.set_sensitive(true);
    }

    private PrivacyDescription[] create_privacy_descriptions() {
        PrivacyDescription[] result = new PrivacyDescription[0];

        result += new PrivacyDescription(_("Public listed"), PrivacySetting.PUBLIC);
        result += new PrivacyDescription(_("Public unlisted"), PrivacySetting.UNLISTED);
        result += new PrivacyDescription(_("Private"), PrivacySetting.PRIVATE);

        return result;
    }


    public void installed() {
        update_publish_button_sensitivity();
    }

    protected void notify_publish(PublishingParameters parameters) {
        publish(parameters);
    }

    protected void notify_logout() {
        logout();
    }

    public Gtk.Widget get_widget() {
        assert (pane_widget != null);
        return pane_widget;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        publish.connect(notify_publish);
        logout.connect(notify_logout);

        installed();
    }

    public void on_pane_uninstalled() {
        publish.disconnect(notify_publish);
        logout.disconnect(notify_logout);
    }
}

internal class Uploader : Publishing.RESTSupport.BatchUploader {
    private PublishingParameters parameters;

    public Uploader(Session session, Spit.Publishing.Publishable[] publishables,
        PublishingParameters parameters) {
        base(session, publishables);

        this.parameters = parameters;
    }

    protected override Publishing.RESTSupport.Transaction create_transaction(
        Spit.Publishing.Publishable publishable) {
        return new UploadTransaction((Session) get_session(), parameters,
            get_current_publishable());
    }
}

}

