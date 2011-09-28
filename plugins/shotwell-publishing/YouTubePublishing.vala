/* Copyright 2009-2011 Yorba Foundation
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
        info.authors = "Jani Monoses";
        info.copyright = _("Copyright 2009-2011 Yorba Foundation");
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
    
    internal string? get_persistent_username() {
        return host.get_config_string("user_name", null);
    }
    
    internal string? get_persistent_auth_token() {
        return host.get_config_string("auth_token", null);
    }
    
    internal void set_persistent_username(string username) {
        host.set_config_string("user_name", username);
    }
    
    internal void set_persistent_auth_token(string auth_token) {
        host.set_config_string("auth_token", auth_token);
    }

    internal void invalidate_persistent_session() {
        debug("invalidating persisted YouTube session.");

        host.unset_config_key("user_name");
        host.unset_config_key("auth_token");
    }
    
    internal bool is_persistent_session_available() {
        return (get_persistent_username() != null && get_persistent_auth_token() != null);
    }

    public bool is_running() {
        return running;
    }
    
    public Spit.Publishing.Service get_service() {
        return service;
    }

    private void on_service_welcome_login() {
        if (!is_running())
            return;
        
        debug("EVENT: user clicked 'Login' in welcome pane.");

        do_show_credentials_pane(CredentialsPane.Mode.INTRO);
    }

    private void on_credentials_go_back() {
        if (!is_running())
            return;
            
        debug("EVENT: user clicked 'Go Back' in credentials pane.");

        do_show_service_welcome_pane();
    }

    private void on_credentials_login(string username, string password) {
        if (!is_running())
            return;    
    
        debug("EVENT: user clicked 'Login' in credentials pane.");

        this.username = username;

        do_network_login(username, password);
    }

    private void on_token_fetch_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_token_fetch_complete);
        txn.network_error.disconnect(on_token_fetch_error);

        if (!is_running())
            return;

        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;

        debug("EVENT: network transaction to fetch token for login completed successfully.");
        
        int index = txn.get_response().index_of("Auth=");
        string auth_substring = txn.get_response().substring(index);
        auth_substring = auth_substring.chomp();
        string auth_token = auth_substring.substring(5);

        session.authenticated.connect(on_session_authenticated);
        session.authenticate(auth_token, username);
    }

    private void on_token_fetch_error(Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_token_fetch_complete);
        bad_txn.network_error.disconnect(on_token_fetch_error);

        if (!is_running())
            return;

        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;

        debug("EVENT: network transaction to fetch token for login failed; response = '%s'.",
            bad_txn.get_response());

        // HTTP error 403 is invalid authentication -- if we get this error during token fetch
        // then we can just show the login screen again with a retry message; if we get any error
        // other than 403 though, we can't recover from it, so just post the error to the user
        if (bad_txn.get_status_code() == 403) {
            if (bad_txn.get_response().contains("CaptchaRequired"))
                do_show_credentials_pane(CredentialsPane.Mode.ADDITIONAL_SECURITY);
            else
                do_show_credentials_pane(CredentialsPane.Mode.FAILED_RETRY);
        }
        else {
            host.post_error(err);
        }
    }

    private void on_session_authenticated() {
        session.authenticated.disconnect(on_session_authenticated);

        if (!is_running())
            return;

        debug("EVENT: an authenticated session has become available.");
        
        do_save_auth_info();
        do_fetch_account_information();
    }

    private void on_initial_channel_fetch_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_initial_channel_fetch_complete);
        txn.network_error.disconnect(on_initial_channel_fetch_error);

        if (!is_running())
            return;

        debug("EVENT: finished fetching account and channel information.");

        do_parse_and_display_account_information((ChannelDirectoryTransaction) txn);
    }

    private void on_initial_channel_fetch_error(Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_initial_channel_fetch_complete);
        bad_txn.network_error.disconnect(on_initial_channel_fetch_error);

        if (!is_running())
            return;

        debug("EVENT: fetching account and channel information failed; response = '%s'.",
            bad_txn.get_response());

        if (bad_txn.get_status_code() == 404 || bad_txn.get_status_code() == 401) {
            // if we get a 404 error (resource not found) or a 401 (level of authentication
            // is insufficient to access the resource) on the initial channel fetch, then the
            // user's channel feed doesn't exist and/or hasn't been linked to their Google
            // account. This occurs when the user has a valid Google account but it hasn't
            // yet been set up for use with YouTube. In this case, we re-display the credentials
            // capture pane with an "account not set up" message. In addition, we deauthenticate
            // the session. Deauth is neccessary because we did previously auth the user's
            // account.
            session.deauthenticate();
            do_show_credentials_pane(CredentialsPane.Mode.NOT_SET_UP);
        } else if (bad_txn.get_status_code() == 403) {
            // if we get a 403 error (authentication failed) then we need to return to the login
            // screen because the user's auth token is no longer valid and he or she needs to
            // login again to obtain a new one
            session.deauthenticate();
            do_show_credentials_pane(CredentialsPane.Mode.INTRO);
        } else {
            host.post_error(err);
        }
    }

    private void on_publishing_options_logout() {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Logout' in the publishing options pane.");

        session.deauthenticate();
        invalidate_persistent_session();

        do_show_service_welcome_pane();
    }

    private void on_publishing_options_publish(PublishingParameters parameters) {
        if (!is_running())
            return;
                
        debug("EVENT: user clicked 'Publish' in the publishing options pane.");

        this.parameters = parameters;

        do_upload();
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

    private void do_show_service_welcome_pane() {
        debug("ACTION: showing service welcome pane.");

        host.install_welcome_pane(SERVICE_WELCOME_MESSAGE, on_service_welcome_login);
    }
    
    private void do_show_credentials_pane(CredentialsPane.Mode mode) {
        debug("ACTION: showing credentials capture pane in %s mode.", mode.to_string());
        
        CredentialsPane creds_pane = new CredentialsPane(host, mode);
        creds_pane.go_back.connect(on_credentials_go_back);
        creds_pane.login.connect(on_credentials_login);

        host.install_dialog_pane(creds_pane);
    }

    private void do_network_login(string username, string password) {
        debug("ACTION: running network login transaction for user = '%s'.", username);
        
        host.install_login_wait_pane();

        TokenFetchTransaction fetch_trans = new TokenFetchTransaction(session, username, password);
        fetch_trans.network_error.connect(on_token_fetch_error);
        fetch_trans.completed.connect(on_token_fetch_complete);

        try {
            fetch_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            // 403 errors are recoverable, so don't post the error to our host immediately;
            // instead, try to recover from it
            on_token_fetch_error(fetch_trans, err);
        }
    }
    
    private void do_save_auth_info() {
        debug("ACTION: saving authentication information to configuration system.");
        
        assert(session.is_authenticated());
        
        set_persistent_auth_token(session.get_auth_token());
        set_persistent_username(session.get_username());
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
        debug("ACTION: fetching account and channel information.");

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
        
        PublishingOptionsPane opts_pane = new PublishingOptionsPane(host, username, channel_name);
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
    
    public void start() {
        if (is_running())
            return;

        if (host == null)
            error("YouTubePublisher: start( ): can't start; this publisher is not restartable.");

        debug("YouTubePublisher: starting interaction.");
        
        running = true;

        if (is_persistent_session_available()) {
            username = get_persistent_username();
            session.authenticate(get_persistent_auth_token(), get_persistent_username());
            do_fetch_account_information();
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
    private string? username = null;

    public Session() {
    }

    public override bool is_authenticated() {
        return (auth_token != null);
    }

    public void authenticate(string auth_token, string username) {
        this.auth_token = auth_token;
        this.username = username;
        
        notify_authenticated();
    }
    
    public void deauthenticate() {
        auth_token = null;
        username = null;
    }

    public string? get_username() {
        return username;
    }
    
    public string? get_auth_token() {
        return auth_token;
    }
}

internal class TokenFetchTransaction : Publishing.RESTSupport.Transaction {
    private const string ENDPOINT_URL = "https://www.google.com/accounts/ClientLogin";

    public TokenFetchTransaction(Session session, string username, string password) {
        base.with_endpoint_url(session, ENDPOINT_URL);

        add_header("Content-Type", "application/x-www-form-urlencoded");
        add_argument("Email", username);
        add_argument("Passwd", password);
        add_argument("service", "youtube");
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

        add_header("Authorization", "GoogleLogin auth=%s".printf(session.get_auth_token()));
        add_header("X-GData-Key", "key=%s".printf(DEVELOPER_KEY));
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
        outbound_message.request_headers.append("Authorization", "GoogleLogin auth=%s".printf(
            session.get_auth_token()));
        outbound_message.request_headers.append("X-GData-Key", "key=%s".printf(DEVELOPER_KEY));
        outbound_message.request_headers.append("Slug", 
            publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME));
        set_message(outbound_message);

        // send the message and get its response
        set_is_executed(true);
        send();
    }
}

internal class CredentialsPane : Spit.Publishing.DialogPane, GLib.Object {
    public enum Mode {
        INTRO,
        FAILED_RETRY,
        NOT_SET_UP,
        ADDITIONAL_SECURITY;

        public string to_string() {
            switch (this) {
                case Mode.INTRO:
                    return "INTRO";

                case Mode.FAILED_RETRY:
                    return "FAILED_RETRY";

                case Mode.NOT_SET_UP:
                    return "NOT_SET_UP";

                case Mode.ADDITIONAL_SECURITY:
                    return "ADDITIONAL_SECURITY";

                default:
                    error("unrecognized CredentialsPane.Mode enumeration value");
            }
        }
    }

    private LegacyCredentialsPane wrapped = null;

    public signal void go_back();
    public signal void login(string email, string password);

    public CredentialsPane(Spit.Publishing.PluginHost host, Mode mode = Mode.INTRO,
        string? username = null) {
            wrapped = new LegacyCredentialsPane(host, mode, username);
    }
    
    protected void notify_go_back() {
        go_back();
    }
    
    protected void notify_login(string email, string password) {
        login(email, password);
    }

    public Gtk.Widget get_widget() {
        return wrapped;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }
    
    public void on_pane_installed() {        
        wrapped.go_back.connect(notify_go_back);
        wrapped.login.connect(notify_login);
        
        wrapped.installed();
    }
    
    public void on_pane_uninstalled() {
        wrapped.go_back.disconnect(notify_go_back);
        wrapped.login.disconnect(notify_login);
    }
}

internal class LegacyCredentialsPane : Gtk.VBox {
    private const string INTRO_MESSAGE = _("Enter the email address and password associated with your YouTube account.");
    private const string FAILED_RETRY_MESSAGE = _("YouTube didn't recognize the email address and password you entered. To try again, re-enter your email address and password below.");
    private const string NOT_SET_UP_MESSAGE = _("The email address and password you entered correspond to a Google account that isn't set up for use with YouTube. You can set up most accounts by using your browser to log into the YouTube site at least once. To try again, re-enter your email address and password below.");
    private const string ADDITIONAL_SECURITY_MESSAGE = _("The email address and password you entered correspond to a Google account that has been tagged as requiring additional security. You can clear this tag by using your browser to log into YouTube. To try again, re-enter your email address and password below.");
    
    private const int UNIFORM_ACTION_BUTTON_WIDTH = 102;
    public const int STANDARD_CONTENT_LABEL_WIDTH = 500;

    private weak Spit.Publishing.PluginHost host = null;
    private Gtk.Entry email_entry;
    private Gtk.Entry password_entry;
    private Gtk.Button login_button;
    private Gtk.Button go_back_button;
    private string? username = null;

    public signal void go_back();
    public signal void login(string email, string password);

    public LegacyCredentialsPane(Spit.Publishing.PluginHost host, CredentialsPane.Mode mode =
        CredentialsPane.Mode.INTRO, string? username = null) {
        this.host = host;
        this.username = username;

        Gtk.SeparatorToolItem top_space = new Gtk.SeparatorToolItem();
        top_space.set_draw(false);
        Gtk.SeparatorToolItem bottom_space = new Gtk.SeparatorToolItem();
        bottom_space.set_draw(false);
        add(top_space);
        top_space.set_size_request(-1, 40);

        Gtk.Label intro_message_label = new Gtk.Label("");
        intro_message_label.set_line_wrap(true);
        add(intro_message_label);
        intro_message_label.set_size_request(STANDARD_CONTENT_LABEL_WIDTH, -1);
        intro_message_label.set_alignment(0.5f, 0.0f);
        switch (mode) {
            case CredentialsPane.Mode.INTRO:
                intro_message_label.set_text(INTRO_MESSAGE);
            break;

            case CredentialsPane.Mode.FAILED_RETRY:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                    "Unrecognized User"), FAILED_RETRY_MESSAGE));
            break;

            case CredentialsPane.Mode.NOT_SET_UP:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_("Account Not Ready"),
                    NOT_SET_UP_MESSAGE));
                Gtk.SeparatorToolItem long_message_space = new Gtk.SeparatorToolItem();
                long_message_space.set_draw(false);
                add(long_message_space);
                long_message_space.set_size_request(-1, 40);
            break;

            case CredentialsPane.Mode.ADDITIONAL_SECURITY:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_("Additional Security Required"),
                    ADDITIONAL_SECURITY_MESSAGE));
                Gtk.SeparatorToolItem long_message_space = new Gtk.SeparatorToolItem();
                long_message_space.set_draw(false);
                add(long_message_space);
                long_message_space.set_size_request(-1, 40);
            break;
        }

        Gtk.Alignment entry_widgets_table_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        Gtk.Table entry_widgets_table = new Gtk.Table(3,2, false);
        Gtk.Label email_entry_label = new Gtk.Label.with_mnemonic(_("_Email address:"));
        email_entry_label.set_alignment(0.0f, 0.5f);
        Gtk.Label password_entry_label = new Gtk.Label.with_mnemonic(_("_Password:"));
        password_entry_label.set_alignment(0.0f, 0.5f);
        email_entry = new Gtk.Entry();
        if (username != null)
            email_entry.set_text(username);
        email_entry.changed.connect(on_email_changed);
        password_entry = new Gtk.Entry();
        password_entry.set_visibility(false);
        entry_widgets_table.attach(email_entry_label, 0, 1, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(password_entry_label, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(email_entry, 1, 2, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(password_entry, 1, 2, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        go_back_button = new Gtk.Button.with_mnemonic(_("Go _Back"));
        go_back_button.clicked.connect(on_go_back_button_clicked);
        Gtk.Alignment go_back_button_aligner = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        go_back_button_aligner.add(go_back_button);
        go_back_button.set_size_request(UNIFORM_ACTION_BUTTON_WIDTH, -1);
        login_button = new Gtk.Button.with_mnemonic(_("_Login"));
        login_button.clicked.connect(on_login_button_clicked);
        login_button.set_sensitive(username != null);
        Gtk.Alignment login_button_aligner = new Gtk.Alignment(1.0f, 0.5f, 0.0f, 0.0f);
        login_button_aligner.add(login_button);
        login_button.set_size_request(UNIFORM_ACTION_BUTTON_WIDTH, -1);
        entry_widgets_table.attach(go_back_button_aligner, 0, 1, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 40);
        entry_widgets_table.attach(login_button_aligner, 1, 2, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 40);
        entry_widgets_table_aligner.add(entry_widgets_table);
        add(entry_widgets_table_aligner);

        email_entry_label.set_mnemonic_widget(email_entry);
        password_entry_label.set_mnemonic_widget(password_entry);

        add(bottom_space);
        bottom_space.set_size_request(-1, 40);
    }

    private void on_login_button_clicked() {
        login(email_entry.get_text(), password_entry.get_text());
    }

    private void on_go_back_button_clicked() {
        go_back();
    }

    private void on_email_changed() {
        login_button.set_sensitive(email_entry.get_text() != "");
    }

    public void installed() {
        host.set_service_locked(false);

        email_entry.grab_focus();
        password_entry.set_activates_default(true);
        login_button.can_default = true;
        host.set_dialog_default_widget(login_button);
    }
}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {
    private LegacyPublishingOptionsPane wrapped = null;

    public signal void publish(PublishingParameters parameters);
    public signal void logout();

    public PublishingOptionsPane(Spit.Publishing.PluginHost host, string username,
        string channel_name) {
        wrapped = new LegacyPublishingOptionsPane(host, username, channel_name);
    }
    
    protected void notify_publish(PublishingParameters parameters) {
        publish(parameters);
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
        
        wrapped.installed();
    }
    
    public void on_pane_uninstalled() {
        wrapped.publish.disconnect(notify_publish);
        wrapped.logout.disconnect(notify_logout);
    }
}

internal class LegacyPublishingOptionsPane : Gtk.VBox {
    private struct PrivacyDescription {
        private string description;
        private PrivacySetting privacy_setting;

        PrivacyDescription(string description, PrivacySetting privacy_setting) {
            this.description = description;
            this.privacy_setting = privacy_setting;
        }
    }

    private const int PACKER_VERTICAL_PADDING = 16;
    private const int PACKER_HORIZ_PADDING = 128;
    private const int INTERSTITIAL_VERTICAL_SPACING = 20;
    private const int ACTION_BUTTON_SPACING = 48;
    private const int STANDARD_ACTION_BUTTON_WIDTH = 128;
    
    private Gtk.ComboBoxText privacy_combo;
    private string channel_name;
    private PrivacyDescription[] privacy_descriptions;
    private Gtk.Button publish_button;

    public signal void publish(PublishingParameters parameters);
    public signal void logout();

    public LegacyPublishingOptionsPane(Spit.Publishing.PluginHost host, string username,
        string channel_name) {
        this.channel_name = channel_name;
        this.privacy_descriptions = create_privacy_descriptions();

        Gtk.SeparatorToolItem top_pusher = new Gtk.SeparatorToolItem();
        top_pusher.set_draw(false);
        top_pusher.set_size_request(-1, 8);
        add(top_pusher);

        Gtk.Label login_identity_label =
            new Gtk.Label(_("You are logged into YouTube as %s.").printf(username));

        add(login_identity_label);

        Gtk.Label publish_to_label =
            new Gtk.Label(_("Videos will appear in '%s'").printf(channel_name));

        add(publish_to_label);

        Gtk.VBox vert_packer = new Gtk.VBox(false, 0);
        Gtk.SeparatorToolItem packer_top_padding = new Gtk.SeparatorToolItem();
        packer_top_padding.set_draw(false);
        packer_top_padding.set_size_request(-1, PACKER_VERTICAL_PADDING);

        Gtk.SeparatorToolItem identity_table_spacer = new Gtk.SeparatorToolItem();
        identity_table_spacer.set_draw(false);
        identity_table_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING);
        vert_packer.add(identity_table_spacer);

        Gtk.Table main_table = new Gtk.Table(6, 3, false);

        Gtk.SeparatorToolItem suboption_indent_spacer = new Gtk.SeparatorToolItem();
        suboption_indent_spacer.set_draw(false);
        suboption_indent_spacer.set_size_request(2, -1);
        main_table.attach(suboption_indent_spacer, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        Gtk.Label privacy_label = new Gtk.Label.with_mnemonic(_("Video privacy _setting:"));
        privacy_label.set_alignment(0.0f, 0.5f);
        main_table.attach(privacy_label, 0, 2, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        privacy_combo = new Gtk.ComboBoxText();
        foreach(PrivacyDescription desc in privacy_descriptions)
            privacy_combo.append_text(desc.description);
        privacy_combo.set_active(PrivacySetting.PUBLIC);
        Gtk.Alignment privacy_combo_frame = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        privacy_combo_frame.add(privacy_combo);
        main_table.attach(privacy_combo_frame, 2, 3, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        privacy_label.set_mnemonic_widget(privacy_combo);

        vert_packer.add(main_table);

        Gtk.SeparatorToolItem table_button_spacer = new Gtk.SeparatorToolItem();
        table_button_spacer.set_draw(false);
        table_button_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING);
        vert_packer.add(table_button_spacer);

        Gtk.HBox action_button_layouter = new Gtk.HBox(true, 0);

        Gtk.Button logout_button = new Gtk.Button.with_mnemonic(_("_Logout"));
        logout_button.clicked.connect(on_logout_clicked);
        logout_button.set_size_request(STANDARD_ACTION_BUTTON_WIDTH, -1);
        Gtk.Alignment logout_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        logout_button_aligner.add(logout_button);
        action_button_layouter.add(logout_button_aligner);
        Gtk.SeparatorToolItem button_spacer = new Gtk.SeparatorToolItem();
        button_spacer.set_draw(false);
        button_spacer.set_size_request(ACTION_BUTTON_SPACING, -1);
        action_button_layouter.add(button_spacer);
        publish_button = new Gtk.Button.with_mnemonic(_("_Publish"));
        publish_button.clicked.connect(on_publish_clicked);
        publish_button.set_size_request(STANDARD_ACTION_BUTTON_WIDTH, -1);
        Gtk.Alignment publish_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        publish_button_aligner.add(publish_button);
        action_button_layouter.add(publish_button_aligner);

        Gtk.Alignment action_button_wrapper = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        action_button_wrapper.add(action_button_layouter);

        vert_packer.add(action_button_wrapper);

        Gtk.SeparatorToolItem packer_bottom_padding = new Gtk.SeparatorToolItem();
        packer_bottom_padding.set_draw(false);
        packer_bottom_padding.set_size_request(-1, 2 * PACKER_VERTICAL_PADDING);
        vert_packer.add(packer_bottom_padding);

        Gtk.Alignment vert_packer_wrapper = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        vert_packer_wrapper.add(vert_packer);

        add(vert_packer_wrapper);
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

        result += PrivacyDescription(_("Public listed"), PrivacySetting.PUBLIC);
        result += PrivacyDescription(_("Public unlisted"), PrivacySetting.UNLISTED);
        result += PrivacyDescription(_("Private"), PrivacySetting.PRIVATE);

        return result;
    }


    public void installed() {
        update_publish_button_sensitivity();
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

