/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class PicasaService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "picasa.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;
    
    public PicasaService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_icon_set(resource_directory.get_child(ICON_FILENAME));
    }

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.picasa";
    }
    
    public unowned string get_pluggable_name() {
        return "Picasa Web Albums";
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
    
    public Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host) {
        return new Publishing.Picasa.PicasaPublisher(this, host);
    }

    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO |
            Spit.Publishing.Publisher.MediaType.VIDEO);
    }
    
    public void activation(bool enabled) {
    }
}

namespace Publishing.Picasa {

internal const string SERVICE_WELCOME_MESSAGE = 
    _("You are not currently logged into Picasa Web Albums.\n\nYou must have already signed up for a Google account and set it up for use with Picasa to continue. You can set up most accounts by using your browser to log into the Picasa Web Albums site at least once.");
internal const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");

public class PicasaPublisher : Spit.Publishing.Publisher, GLib.Object {
    private weak Spit.Publishing.PluginHost host = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private weak Spit.Publishing.Service service = null;
    private bool running = false;
    private Session session;
    private string? username = null;
    private Album[] albums = null;
    private PublishingParameters parameters = null;
    private Spit.Publishing.Publisher.MediaType media_type = Spit.Publishing.Publisher.MediaType.NONE;

    public PicasaPublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        this.service = service;
        this.host = host;
        this.session = new Session();
        
        // Ticket #3212 - Only display the size chooser if we're uploading a
        // photograph, since resizing of video isn't supported.
        //
        // Find the media types involved. We need this to decide whether
        // to show the size combobox or not.
        foreach(Spit.Publishing.Publishable p in host.get_publishables()) {
            media_type |= p.get_media_type();
        }         
    }
    
    private Album[] extract_albums(Xml.Node* document_root) throws Spit.Publishing.PublishingError {
        Album[] result = new Album[0];

        Xml.Node* doc_node_iter = null;
        if (document_root->name == "feed")
            doc_node_iter = document_root->children;
        else if (document_root->name == "entry")
            doc_node_iter = document_root;
        else
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("response root node " +
                "isn't a <feed> or <entry>");

        for ( ; doc_node_iter != null; doc_node_iter = doc_node_iter->next) {
            if (doc_node_iter->name != "entry")
                continue;

            string name_val = null;
            string url_val = null;
            Xml.Node* album_node_iter = doc_node_iter->children;
            for ( ; album_node_iter != null; album_node_iter = album_node_iter->next) {
                if (album_node_iter->name == "title") {
                    name_val = album_node_iter->get_content();
                } else if (album_node_iter->name == "id") {
                    // we only want nodes in the default namespace -- the feed that we get back
                    // from Google also defines <entry> child nodes named <id> in the gphoto and
                    // media namespaces
                    if (album_node_iter->ns->prefix != null)
                        continue;
                    url_val = album_node_iter->get_content();
                }
            }

            result += Album(name_val, url_val);
        }

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
        debug("invalidating persisted Picasa Web Albums session.");

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
        string auth_substring = (index >= 0) ? txn.get_response()[index:txn.get_response().length] : "";
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

    private void on_initial_album_fetch_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_initial_album_fetch_complete);
        txn.network_error.disconnect(on_initial_album_fetch_error);

        if (!is_running())
            return;

        debug("EVENT: finished fetching account and album information.");

        do_parse_and_display_account_information((AlbumDirectoryTransaction) txn);
    }

    private void on_initial_album_fetch_error(Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_initial_album_fetch_complete);
        bad_txn.network_error.disconnect(on_initial_album_fetch_error);

        if (!is_running())
            return;

        debug("EVENT: fetching account and album information failed; response = '%s'.",
            bad_txn.get_response());

        if (bad_txn.get_status_code() == 404) {
            // if we get a 404 error (resource not found) on the initial album fetch, then the
            // user's album feed doesn't exist -- this occurs when the user has a valid Google
            // account but it hasn't yet been set up for use with Picasa. In this case, we
            // re-display the credentials capture pane with an "account not set up" message.
            // In addition, we deauthenticate the session. Deauth is neccessary because we
            // did previously auth the user's account. If we get any other kind of error, we can't
            // recover, so just post it to the user
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

        if (parameters.is_to_new_album()) {
            do_create_album(parameters);
        } else {
            do_upload();
        }
    }

    private void on_album_creation_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_album_creation_complete);
        txn.network_error.disconnect(on_album_creation_error);
        
        if (!is_running())
            return;
            
        debug("EVENT: finished creating album on remote server.");

        AlbumCreationTransaction downcast_txn = (AlbumCreationTransaction) txn;
        Publishing.RESTSupport.XmlDocument response_doc;
        try {
            response_doc = Publishing.RESTSupport.XmlDocument.parse_string(
                downcast_txn.get_response(), AlbumDirectoryTransaction.validate_xml);
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
            return;
        }

        Album[] response_albums;
        try {
            response_albums = extract_albums(response_doc.get_root_node());
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
            return;
        }

        if (response_albums.length != 1) {
            host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("album " +
                "creation transaction responses must contain one and only one album directory " +
                "entry"));
            return;
        }
        parameters.convert(response_albums[0].url);

        do_upload();
    }

    private void on_album_creation_error(Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_album_creation_complete);
        bad_txn.network_error.disconnect(on_album_creation_error);
        
        if (!is_running())
            return;
            
        debug("EVENT: creating album on remote server failed; response = '%s'.",
            bad_txn.get_response());

        host.post_error(err);
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
        debug("ACTION: fetching account and album information.");

        host.install_account_fetch_wait_pane();
        host.set_service_locked(true);

        AlbumDirectoryTransaction directory_trans =
            new AlbumDirectoryTransaction(session);
        directory_trans.network_error.connect(on_initial_album_fetch_error);
        directory_trans.completed.connect(on_initial_album_fetch_complete);
        
        try {
            directory_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            // don't just post the error and stop publishing -- 404 and 403 errors are
            // recoverable
            on_initial_album_fetch_error(directory_trans, err);
        }
    }

    private void do_parse_and_display_account_information(AlbumDirectoryTransaction transaction) {
        debug("ACTION: fetching account and album information.");

        Publishing.RESTSupport.XmlDocument response_doc;
        try {
            response_doc = Publishing.RESTSupport.XmlDocument.parse_string(
                transaction.get_response(), AlbumDirectoryTransaction.validate_xml);
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
            return;
        }

        try {
            albums = extract_albums(response_doc.get_root_node());
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
            return;
        }

        do_show_publishing_options_pane();
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: showing publishing options pane.");
        
        PublishingOptionsPane opts_pane = new PublishingOptionsPane(host, username, albums, media_type);
        opts_pane.publish.connect(on_publishing_options_publish);
        opts_pane.logout.connect(on_publishing_options_logout);
        host.install_dialog_pane(opts_pane);

        host.set_service_locked(false);
    }

    private void do_create_album(PublishingParameters parameters) {
        assert(parameters.is_to_new_album());

        debug("ACTION: creating new album '%s' on remote server.", parameters.get_album_name());

        host.install_static_message_pane(_("Creating album..."));

        host.set_service_locked(true);

        AlbumCreationTransaction creation_trans = new AlbumCreationTransaction(session,
            parameters);
        creation_trans.network_error.connect(on_album_creation_error);
        creation_trans.completed.connect(on_album_creation_complete);
        try {
            creation_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }

    private void do_upload() {
        debug("ACTION: uploading media items to remote server.");

        host.set_service_locked(true);

        progress_reporter = host.serialize_publishables(parameters.get_photo_major_axis_size());
        
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
            error("PicasaPublisher: start( ): can't start; this publisher is not restartable.");

        debug("PicasaPublisher: starting interaction.");
        
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
        debug("PicasaPublisher: stop( ) invoked.");

        if (session != null)
            session.stop_transactions();

        host = null;
        running = false;
    }
}

internal struct Album {
    string name;
    string url;

    Album(string name, string url) {
        this.name = name;
        this.url = url;
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

        add_argument("accountType", "HOSTED_OR_GOOGLE");
        add_argument("Email", username);
        add_argument("Passwd", password);
        add_argument("service", "lh2");
        add_argument("source", "yorba-shotwell-" + _VERSION);
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
    }
}

internal class AlbumDirectoryTransaction : AuthenticatedTransaction {
    private const string ENDPOINT_URL = "http://picasaweb.google.com/data/feed/api/user/" +
        "default";

    public AlbumDirectoryTransaction(Session session) {
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

private class AlbumCreationTransaction : AuthenticatedTransaction {
    private const string ENDPOINT_URL = "http://picasaweb.google.com/data/feed/api/user/" +
        "default";
    private const string ALBUM_ENTRY_TEMPLATE = "<?xml version='1.0' encoding='utf-8'?><entry xmlns='http://www.w3.org/2005/Atom' xmlns:gphoto='http://schemas.google.com/photos/2007'><title type='text'>%s</title><gphoto:access>%s</gphoto:access><category scheme='http://schemas.google.com/g/2005#kind' term='http://schemas.google.com/photos/2007#album'></category></entry>";
    
    public AlbumCreationTransaction(Session session, PublishingParameters parameters) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.POST);

        string post_body = ALBUM_ENTRY_TEMPLATE.printf(Publishing.RESTSupport.decimal_entity_encode(
            parameters.get_album_name()), parameters.is_album_public() ? "public" : "private");

        set_custom_payload(post_body, "application/atom+xml");
    }
}

internal class UploadTransaction : AuthenticatedTransaction {
    private PublishingParameters parameters;
    private const string METADATA_TEMPLATE = "<entry xmlns='http://www.w3.org/2005/Atom'> <title>%s</title> %s <category scheme='http://schemas.google.com/g/2005#kind' term='http://schemas.google.com/photos/2007#photo'/> </entry>";
    private Session session;
    private string mime_type;
    private Spit.Publishing.Publishable publishable;
    private MappedFile mapped_file;

    public UploadTransaction(Session session, PublishingParameters parameters,
        Spit.Publishing.Publishable publishable) {
        base(session, parameters.get_album_feed_url(), Publishing.RESTSupport.HttpMethod.POST);
        assert(session.is_authenticated());
        this.session = session;
        this.parameters = parameters;
        this.publishable = publishable;
        this.mime_type = (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.VIDEO) ?
            "video/mpeg" : "image/jpeg";
    }

    public override void execute() throws Spit.Publishing.PublishingError {
        // create the multipart request container
        Soup.Multipart message_parts = new Soup.Multipart("multipart/related");
        
        string summary = "";
        if (publishable.get_publishing_name() != "") {
            summary = "<summary>%s</summary>".printf(
                Publishing.RESTSupport.decimal_entity_encode(publishable.get_publishing_name()));
        }

        string metadata = METADATA_TEMPLATE.printf(Publishing.RESTSupport.decimal_entity_encode(
            publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME)),
            summary);
        Soup.Buffer metadata_buffer = new Soup.Buffer(Soup.MemoryUse.COPY, metadata.data);
        message_parts.append_form_file("", "", "application/atom+xml", metadata_buffer);

        // attempt to map the binary image data from disk into memory 
        try {
            mapped_file = new MappedFile(publishable.get_serialized_file().get_path(), false);
        } catch (FileError e) {
            string msg = "Picasa: couldn't read data from %s: %s".printf(
                publishable.get_serialized_file().get_path(), e.message);
            warning("%s", msg);
            
            throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(msg);
        }
        unowned uint8[] photo_data = (uint8[]) mapped_file.get_contents();
        photo_data.length = (int) mapped_file.get_length();

        // bind the binary image data read from disk into a Soup.Buffer object so that we
        // can attach it to the multipart request, then actaully append the buffer
        // to the multipart request. Then, set the MIME type for this part.
        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.TEMPORARY, photo_data);

        message_parts.append_form_file("", publishable.get_serialized_file().get_path(), mime_type,
            bindable_data);
        // create a message that can be sent over the wire whose payload is the multipart container
        // that we've been building up
        Soup.Message outbound_message =
            soup_form_request_new_from_multipart(get_endpoint_url(), message_parts);
        outbound_message.request_headers.append("Authorization", "GoogleLogin auth=%s".printf(session.get_auth_token()));
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
    private const string INTRO_MESSAGE = _("Enter the email address and password associated with your Picasa Web Albums account.");
    private const string FAILED_RETRY_MESSAGE = _("Picasa Web Albums didn't recognize the email address and password you entered. To try again, re-enter your email address and password below.");
    private const string NOT_SET_UP_MESSAGE = _("The email address and password you entered correspond to a Google account that isn't set up for use with Picasa Web Albums. You can set up most accounts by using your browser to log into the Picasa Web Albums site at least once. To try again, re-enter your email address and password below.");
    private const string ADDITIONAL_SECURITY_MESSAGE = _("The email address and password you entered correspond to a Google account that has been tagged as requiring additional security. You can clear this tag by using your browser to log into Picasa Web Albums. To try again, re-enter your email address and password below.");
    
    private const int UNIFORM_ACTION_BUTTON_WIDTH = 102;
    private const int VERTICAL_SPACE_HEIGHT = 32;
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
        top_space.set_size_request(-1, VERTICAL_SPACE_HEIGHT);

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
                long_message_space.set_size_request(-1, VERTICAL_SPACE_HEIGHT);
            break;

            case CredentialsPane.Mode.ADDITIONAL_SECURITY:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_("Additional Security Required"),
                    ADDITIONAL_SECURITY_MESSAGE));
                Gtk.SeparatorToolItem long_message_space = new Gtk.SeparatorToolItem();
                long_message_space.set_draw(false);
                add(long_message_space);
                long_message_space.set_size_request(-1, VERTICAL_SPACE_HEIGHT);
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
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, VERTICAL_SPACE_HEIGHT);
        entry_widgets_table.attach(login_button_aligner, 1, 2, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, VERTICAL_SPACE_HEIGHT);
        entry_widgets_table_aligner.add(entry_widgets_table);
        add(entry_widgets_table_aligner);

        email_entry_label.set_mnemonic_widget(email_entry);
        password_entry_label.set_mnemonic_widget(password_entry);

        add(bottom_space);
        bottom_space.set_size_request(-1, VERTICAL_SPACE_HEIGHT);
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

    public PublishingOptionsPane(Spit.Publishing.PluginHost host, string username, Album[] albums, Spit.Publishing.Publisher.MediaType media_type) {
        wrapped = new LegacyPublishingOptionsPane(host, username, albums, media_type);
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
    private struct SizeDescription {
        string name;
        int major_axis_pixels;

        SizeDescription(string name, int major_axis_pixels) {
            this.name = name;
            this.major_axis_pixels = major_axis_pixels;
        }
    }

    private const int PACKER_VERTICAL_PADDING = 16;
    private const int PACKER_HORIZ_PADDING = 128;
    private const int INTERSTITIAL_VERTICAL_SPACING = 20;
    private const int ACTION_BUTTON_SPACING = 48;
    private const int ACTION_BUTTON_WIDTH = 128;
    private const string DEFAULT_SIZE_CONFIG_KEY = "default_size";
    private const string LAST_ALBUM_CONFIG_KEY = "last_album";
    
    private Gtk.ComboBox existing_albums_combo;
    private Gtk.Entry new_album_entry;
    private Gtk.CheckButton public_check;
    private Gtk.ComboBox size_combo;
    private Gtk.RadioButton use_existing_radio;
    private Gtk.RadioButton create_new_radio;
    private Album[] albums;
    private SizeDescription[] size_descriptions;
    private Gtk.Button publish_button;
    private string username;
    private weak Spit.Publishing.PluginHost host;

    public signal void publish(PublishingParameters parameters);
    public signal void logout();

    public LegacyPublishingOptionsPane(Spit.Publishing.PluginHost host, string username, 
        Album[] albums, Spit.Publishing.Publisher.MediaType media_type) {
        this.username = username;
        this.albums = albums;
        this.host = host;
        size_descriptions = create_size_descriptions();

        Gtk.SeparatorToolItem top_pusher = new Gtk.SeparatorToolItem();
        top_pusher.set_draw(false);
        top_pusher.set_size_request(-1, 8);
        add(top_pusher);

        Gtk.Label login_identity_label =
            new Gtk.Label(_("You are logged into Picasa Web Albums as %s.").printf(
            username));

        add(login_identity_label);

        Gtk.VBox vert_packer = new Gtk.VBox(false, 0);
        Gtk.SeparatorToolItem packer_top_padding = new Gtk.SeparatorToolItem();
        packer_top_padding.set_draw(false);
        packer_top_padding.set_size_request(-1, PACKER_VERTICAL_PADDING);

        Gtk.SeparatorToolItem identity_table_spacer = new Gtk.SeparatorToolItem();
        identity_table_spacer.set_draw(false);
        identity_table_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING);
        vert_packer.add(identity_table_spacer);

        Gtk.Table main_table = new Gtk.Table(6, 3, false);

        // Ticket #3212, part II - If we're onluy uploading video, alter the         
        // 'will appear in' message to reflect this.          
        Gtk.Label publish_to_label;

        if((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) == 0) 
            publish_to_label = new Gtk.Label(_("Videos will appear in:"));
        else
            publish_to_label = new Gtk.Label(_("Photos will appear in:"));
            
        publish_to_label.set_alignment(0.0f, 0.5f);
        main_table.attach(publish_to_label, 0, 2, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        Gtk.SeparatorToolItem suboption_indent_spacer = new Gtk.SeparatorToolItem();
        suboption_indent_spacer.set_draw(false);
        suboption_indent_spacer.set_size_request(2, -1);
        main_table.attach(suboption_indent_spacer, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        use_existing_radio = new Gtk.RadioButton.with_mnemonic(null, _("An _existing album:"));
        use_existing_radio.clicked.connect(on_use_existing_radio_clicked);
        main_table.attach(use_existing_radio, 1, 2, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        existing_albums_combo = new Gtk.ComboBox.text();
        Gtk.Alignment existing_albums_combo_frame = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        existing_albums_combo_frame.add(existing_albums_combo);
        main_table.attach(existing_albums_combo_frame, 2, 3, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        create_new_radio = new Gtk.RadioButton.with_mnemonic(use_existing_radio.get_group(),
            _("A _new album named:"));
        create_new_radio.clicked.connect(on_create_new_radio_clicked);
        main_table.attach(create_new_radio, 1, 2, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        new_album_entry = new Gtk.Entry();
        new_album_entry.changed.connect(on_new_album_entry_changed);
        main_table.attach(new_album_entry, 2, 3, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        public_check = new Gtk.CheckButton.with_mnemonic(_("L_ist album in public gallery"));
        main_table.attach(public_check, 2, 3, 3, 4,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        Gtk.SeparatorToolItem album_size_spacer = new Gtk.SeparatorToolItem();
        album_size_spacer.set_draw(false);
        album_size_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING / 2);
        main_table.attach(album_size_spacer, 2, 3, 4, 5,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        // Ticket #3212 - Only display the size chooser if we're uploading a
        // photograph, since resizing of video isn't supported.
        // 
        // If the media_type argument doesn't tell us we're getting at least
        // one photo, do not create or add these widgets.
        if((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) != 0) {
            Gtk.Label size_label = new Gtk.Label.with_mnemonic(_("Photo _size preset:"));
            size_label.set_alignment(0.0f, 0.5f);
            
            main_table.attach(size_label, 0, 2, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

            size_combo = new Gtk.ComboBox.text();
            foreach(SizeDescription desc in size_descriptions)
                size_combo.append_text(desc.name);
        
            size_combo.set_active(host.get_config_int(DEFAULT_SIZE_CONFIG_KEY, 0));
            Gtk.Alignment size_combo_frame = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        
            size_combo_frame.add(size_combo);
            main_table.attach(size_combo_frame, 2, 3, 5, 6,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

            size_label.set_mnemonic_widget(size_combo);
        }

        vert_packer.add(main_table);

        Gtk.SeparatorToolItem table_button_spacer = new Gtk.SeparatorToolItem();
        table_button_spacer.set_draw(false);
        table_button_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING);
        vert_packer.add(table_button_spacer);

        Gtk.HBox action_button_layouter = new Gtk.HBox(true, 0);

        Gtk.Button logout_button = new Gtk.Button.with_mnemonic(_("_Logout"));
        logout_button.clicked.connect(on_logout_clicked);
        logout_button.set_size_request(ACTION_BUTTON_WIDTH, -1);
        Gtk.Alignment logout_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        logout_button_aligner.add(logout_button);
        action_button_layouter.add(logout_button_aligner);
        Gtk.SeparatorToolItem button_spacer = new Gtk.SeparatorToolItem();
        button_spacer.set_draw(false);
        button_spacer.set_size_request(ACTION_BUTTON_SPACING, -1);
        action_button_layouter.add(button_spacer);
        publish_button = new Gtk.Button.with_mnemonic(_("_Publish"));
        publish_button.clicked.connect(on_publish_clicked);
        publish_button.set_size_request(ACTION_BUTTON_WIDTH, -1);
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
        host.set_config_int(DEFAULT_SIZE_CONFIG_KEY, size_combo.get_active());
        int photo_major_axis_size = size_descriptions[size_combo.get_active()].major_axis_pixels;
        string album_name;
        if (create_new_radio.get_active()) {
            album_name = new_album_entry.get_text();
            host.set_config_string(LAST_ALBUM_CONFIG_KEY, album_name);
            bool is_public = public_check.get_active();
            publish(new PublishingParameters.to_new_album(photo_major_axis_size, album_name,
                is_public));
        } else {
            album_name = albums[existing_albums_combo.get_active()].name;
            host.set_config_string(LAST_ALBUM_CONFIG_KEY, album_name);
            string album_url = albums[existing_albums_combo.get_active()].url;
            publish(new PublishingParameters.to_existing_album(photo_major_axis_size, album_url));
        }
    }

    private void on_use_existing_radio_clicked() {
        existing_albums_combo.set_sensitive(true);
        new_album_entry.set_sensitive(false);
        existing_albums_combo.grab_focus();
        update_publish_button_sensitivity();
        public_check.set_sensitive(false);
    }

    private void on_create_new_radio_clicked() {
        new_album_entry.set_sensitive(true);
        existing_albums_combo.set_sensitive(false);
        new_album_entry.grab_focus();
        update_publish_button_sensitivity();
        public_check.set_sensitive(true);
    }

    private void on_logout_clicked() {
        logout();
    }

    private void update_publish_button_sensitivity() {
        string album_name = new_album_entry.get_text();
        publish_button.set_sensitive(!(album_name.strip() == "" &&
            create_new_radio.get_active()));
    }

    private void on_new_album_entry_changed() {
        update_publish_button_sensitivity();
    }

    private SizeDescription[] create_size_descriptions() {
        SizeDescription[] result = new SizeDescription[0];

        result += SizeDescription(_("Small (640 x 480 pixels)"), 640);
        result += SizeDescription(_("Medium (1024 x 768 pixels)"), 1024);
        result += SizeDescription(_("Recommended (1600 x 1200 pixels)"), 1600);
        result += SizeDescription(_("Original Size"), PublishingParameters.ORIGINAL_SIZE);

        return result;
    }

    public void installed() {
        int default_album_id = -1;
        string last_album = host.get_config_string(LAST_ALBUM_CONFIG_KEY, "");
        for (int i = 0; i < albums.length; i++) {
            existing_albums_combo.append_text(albums[i].name);
            if (albums[i].name == last_album ||
                (albums[i].name == DEFAULT_ALBUM_NAME && default_album_id == -1))
                default_album_id = i;
        }

        if (albums.length == 0) {
            existing_albums_combo.set_sensitive(false);
            use_existing_radio.set_sensitive(false);
            create_new_radio.set_active(true);
            new_album_entry.grab_focus();
            new_album_entry.set_text(DEFAULT_ALBUM_NAME);
        } else {
            if (default_album_id >= 0) {
                use_existing_radio.set_active(true);
                existing_albums_combo.set_active(default_album_id);
                new_album_entry.set_sensitive(false);
                public_check.set_sensitive(false);
            } else {
                create_new_radio.set_active(true);
                existing_albums_combo.set_active(0);
                new_album_entry.set_text(DEFAULT_ALBUM_NAME);
                new_album_entry.grab_focus();
                public_check.set_sensitive(true);
            }
        }
        update_publish_button_sensitivity();
    }
}

internal class PublishingParameters {
    public const int ORIGINAL_SIZE = -1;
    
    private string album_name;
    private string album_url;
    private bool album_public;
    public int photo_major_axis_size;
    
    private PublishingParameters() {
    }

    public PublishingParameters.to_new_album(int photo_major_axis_size, string album_name,
        bool album_public) {
        this.photo_major_axis_size = photo_major_axis_size;
        this.album_name = album_name;
        this.album_public = album_public;
    }

    public PublishingParameters.to_existing_album(int photo_major_axis_size, string album_url) {
        this.photo_major_axis_size = photo_major_axis_size;
        this.album_url = album_url;
    }
    
    public bool is_to_new_album() {
        return (album_name != null);
    }
    
    public bool is_album_public() {
        assert(is_to_new_album());
        return album_public;
    }
    
    public string get_album_name() {
        assert(is_to_new_album());
        return album_name;
    }

    public string get_album_entry_url() {
        assert(!is_to_new_album());
        return album_url;
    }
    
    public string get_album_feed_url() {
        string entry_url = get_album_entry_url();
        string feed_url = entry_url.replace("entry", "feed");

        return feed_url;
    }

    public int get_photo_major_axis_size() {
        return photo_major_axis_size;
    }

    // converts a publish-to-new-album parameters object into a publish-to-existing-album
    // parameters object
    public void convert(string album_url) {
        assert(is_to_new_album());
        
        // debug("converting publishing parameters: album '%s' has url '%s'.", album_name, album_url);
        
        album_name = null;
        this.album_url = album_url;
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
