/* Copyright 2009-2013 Yorba Foundation
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
    
    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Lucas Beeler";
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
    _("You are not currently logged into Picasa Web Albums.\n\nClick Login to log into Picasa Web Albums in your Web browser. You will have to authorize Shotwell Connect to link to your Picasa Web Albums account.");
internal const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");
internal const string OAUTH_CLIENT_ID = "1073902228337-gm4uf5etk25s0hnnm0g7uv2tm2bm1j0b.apps.googleusercontent.com";
internal const string OAUTH_CLIENT_SECRET = "_kA4RZz72xqed4DqfO7xMmMN";

public class PicasaPublisher : Spit.Publishing.Publisher, GLib.Object {
    private weak Spit.Publishing.PluginHost host = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private weak Spit.Publishing.Service service = null;
    private bool running = false;
    private bool strip_metadata = false;
    private Session session;
    private string username = "[unknown]";
    private Album[] albums = null;
    private PublishingParameters parameters = null;
    private Spit.Publishing.Publisher.MediaType media_type =
        Spit.Publishing.Publisher.MediaType.NONE;

    public PicasaPublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        this.service = service;
        this.host = host;
        this.session = new Session();
        
        foreach(Spit.Publishing.Publishable p in host.get_publishables())
            media_type |= p.get_media_type();
    }
    
    private string get_user_authorization_url() {
        return "https://accounts.google.com/o/oauth2/auth?" +
            "response_type=code&" +
            "client_id=" + OAUTH_CLIENT_ID + "&" +
            "redirect_uri=" + Soup.URI.encode("urn:ietf:wg:oauth:2.0:oob", null) + "&" +
            "scope=" + Soup.URI.encode("http://picasaweb.google.com/data/", null) + "+" +
            Soup.URI.encode("https://www.googleapis.com/auth/userinfo.profile", null) + "&" +
            "state=connect&" +
            "access_type=offline&" +
            "approval_prompt=force";
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

            result += new Album(name_val, url_val);
        }

        return result;
    }
    
    internal string? get_persistent_refresh_token() {
        return host.get_config_string("refresh_token", null);
    }
   
    internal void set_persistent_refresh_token(string token) {
        host.set_config_string("refresh_token", token);
    }

    internal bool get_persistent_strip_metadata() {
        return host.get_config_bool("strip_metadata", false);
    }
    
    internal void set_persistent_strip_metadata(bool strip_metadata) {
        host.set_config_bool("strip_metadata", strip_metadata);
    }    

    internal void invalidate_persistent_session() {
        debug("invalidating persisted Picasa Web Albums session.");

        host.unset_config_key("refresh_token");
    }
    
    internal bool is_persistent_session_available() {
        return get_persistent_refresh_token() != null;
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

        do_launch_browser_for_authorization();
    }
    
    private void on_auth_code_entry_pane_proceed(AuthCodeEntryPane sender, string code) {
        debug("EVENT: user clicked 'Continue' in authorization code entry pane.");
        
        sender.proceed.disconnect(on_auth_code_entry_pane_proceed);
        
        do_get_access_tokens(code);
    }
    
    private void on_browser_launched() {
        debug("EVENT: system web browser launched to solicit user authorization.");
        
        do_show_auth_code_entry_pane();
    }
    
    private void on_get_access_tokens_completed(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_get_access_tokens_completed);
        txn.network_error.disconnect(on_get_access_tokens_error);

        debug("EVENT: network transaction to exchange authorization code for access tokens " +
            "completed successfully.");

        do_extract_tokens(txn.get_response());
    }
    
    private void on_get_access_tokens_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_get_access_tokens_completed);
        txn.network_error.disconnect(on_get_access_tokens_error);

        debug("EVENT: network transaction to exchange authorization code for access tokens " +
            "failed; response = '%s'", txn.get_response());
    }
    
    private void on_refresh_token_available(string token) {
        debug("EVENT: an OAuth refresh token has become available.");
        
        do_save_refresh_token_to_configuration_system(token);
    }
    
    private void on_access_token_available(string token) {
        debug("EVENT: an OAuth access token has become available.");
        
        do_authenticate_session(token);
    }
    
    private void on_not_set_up_pane_proceed(NotSetUpMessagePane sender) {
        debug("EVENT: user clicked 'Continue' in Account Not Set Up Message Pane.");
        
        sender.proceed.disconnect(on_not_set_up_pane_proceed);
    
        do_launch_browser_for_authorization();
    }
    
    private void on_refresh_access_token_transaction_completed(Publishing.RESTSupport.Transaction
        txn) {
        txn.completed.disconnect(on_refresh_access_token_transaction_completed);
        txn.network_error.disconnect(on_refresh_access_token_transaction_error);
        
        if (!is_running())
            return;

        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;

        debug("EVENT: refresh access token transaction completed successfully.");
        
        do_extract_tokens(txn.get_response());
    }
    
    private void on_refresh_access_token_transaction_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_refresh_access_token_transaction_completed);
        txn.network_error.disconnect(on_refresh_access_token_transaction_error);
        
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

        debug("EVENT: refresh access token transaction caused a network error.");
        
        host.post_error(err);       
    }

    private void on_session_authenticated() {
        session.authenticated.disconnect(on_session_authenticated);

        if (!is_running())
            return;

        debug("EVENT: an authenticated session has become available.");
        
        do_fetch_username();
    }
    
    private void on_fetch_username_transaction_completed(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_fetch_username_transaction_completed);
        txn.network_error.disconnect(on_fetch_username_transaction_error);
        
        debug("EVENT: username fetch transaction completed successfully.");

        do_extract_username(txn.get_response());
        do_fetch_account_information();
    }
    
    private void on_fetch_username_transaction_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_fetch_username_transaction_completed);
        txn.network_error.disconnect(on_fetch_username_transaction_error);

        debug("EVENT: username fetch transaction caused a network error");
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
            // display an informational pane with an "account not set up" message. In addition, we
            // deauthenticate the session. Deauth is necessary because we must've previously auth'd
            // the user's account to even be able to query the album feed.
            session.deauthenticate();
            do_show_not_set_up_pane();
        } else {
            // If we get any other kind of error, we can't recover, so just post it to the user
            host.post_error(err);
        }
    }

    private void on_publishing_options_logout() {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Logout' in the publishing options pane.");

        do_logout();
    }

    private void on_publishing_options_publish(PublishingParameters parameters, 
        bool strip_metadata) {
        if (!is_running())
            return;
            
        this.strip_metadata = strip_metadata;
                
        debug("EVENT: user clicked 'Publish' in the publishing options pane.");

        this.parameters = parameters;

        if (parameters.is_to_new_album()) {
            do_create_album(parameters);
        } else {
            do_upload(this.strip_metadata);
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

        do_upload(this.strip_metadata);
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
    
    private void do_logout() {
        debug("ACTION: logging out user.");
        
        session.deauthenticate();
        invalidate_persistent_session();

        do_show_service_welcome_pane();
    }
    
    private void do_launch_browser_for_authorization() {
        string auth_url = get_user_authorization_url();
        
        debug("ACTION: launching external web browser to get user authorization; " +
            "authorization URL = '%s'", auth_url);

        try {
            Process.spawn_command_line_async("xdg-open " + auth_url);
        } catch (SpawnError e) {
            host.post_error(new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                _("couldn't launch system web browser to complete Picasa Web Albums login")));
            return;
        }
        
        on_browser_launched();
    }
    
    private void do_show_auth_code_entry_pane() {
        debug("ACTION: showing OAuth authorization code entry pane.");
        
        Gtk.Builder builder = new Gtk.Builder();
        
        try {
            builder.add_from_file(host.get_module_file().get_parent().get_child(
                "picasa_auth_code_entry_pane.glade").get_path());
        } catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            host.post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is unavailable. Publishing to Picasa Web Albums can't continue.")));
            return;        
        }
        
        AuthCodeEntryPane pane = new AuthCodeEntryPane(builder);
        pane.proceed.connect(on_auth_code_entry_pane_proceed);
        host.install_dialog_pane(pane);
    }
    
    private void do_get_access_tokens(string code) {
        debug("ACTION: exchanging OAuth authorization code '%s' for access token.", code);
        
        GetAccessTokensTransaction txn = new GetAccessTokensTransaction(session, code);
        txn.completed.connect(on_get_access_tokens_completed);
        txn.network_error.connect(on_get_access_tokens_error);
        
        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
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
    
    private void do_save_refresh_token_to_configuration_system(string token) {
        debug("ACTION: saving OAuth refresh token to configuration system");
        
        set_persistent_refresh_token(token);
    }
    
    private void do_refresh_session(string refresh_token) {
        debug("ACTION: using OAuth refresh token to refresh session.");
        
        host.install_login_wait_pane();
        
        RefreshAccessTokenTransaction txn = new RefreshAccessTokenTransaction(session, refresh_token);
        
        txn.completed.connect(on_refresh_access_token_transaction_completed);
        txn.network_error.connect(on_refresh_access_token_transaction_error);
        
        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            // don't post an error to the host -- let the error handler signal connected above
            // handle the problem
        }
    }
    
    private void do_authenticate_session(string token) {
        debug("ACTION: authenticating session.");
        
        session.authenticated.connect(on_session_authenticated);
        session.authenticate(token);
    }
    
    private void do_show_not_set_up_pane() {
        debug("ACTION: showing account not set up message pane");
        
        Gtk.Builder builder = new Gtk.Builder();
        
        try {
            builder.add_from_file(host.get_module_file().get_parent().get_child(
                "picasa_not_set_up_pane.glade").get_path());
        } catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            host.post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is unavailable. Publishing to Picasa Web Albums can't continue.")));
            return;        
        }
        
        NotSetUpMessagePane pane = new NotSetUpMessagePane(builder);
        pane.proceed.connect(on_not_set_up_pane_proceed);
        host.install_dialog_pane(pane);
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
            // don't just post the error and stop publishing -- 404 errors are recoverable
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
        Gtk.Builder builder = new Gtk.Builder();

        try {
            // the trailing get_path() is required, since add_from_file can't cope
            // with File objects directly and expects a pathname instead.
            builder.add_from_file(
                host.get_module_file().get_parent().
                get_child("picasa_publishing_options_pane.glade").get_path());
        } catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            host.post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is unavailable. Publishing to Picasa can't continue.")));
            return;
        }

        PublishingOptionsPane opts_pane = new PublishingOptionsPane(host, username, albums, media_type, builder,
            get_persistent_strip_metadata());
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

    private void do_upload(bool strip_metadata) {
        set_persistent_strip_metadata(strip_metadata);        
        
        debug("ACTION: uploading media items to remote server.");

        host.set_service_locked(true);

        progress_reporter = host.serialize_publishables(parameters.get_photo_major_axis_size(), 
            strip_metadata);
        
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
            do_refresh_session(get_persistent_refresh_token());
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

internal class Album {
    public string name;
    public string url;

    public Album(string name, string url) {
        this.name = name;
        this.url = url;
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
    private const string METADATA_TEMPLATE = "<?xml version=\"1.0\" ?><atom:entry xmlns:atom='http://www.w3.org/2005/Atom' xmlns:mrss='http://search.yahoo.com/mrss/'> <atom:title>%s</atom:title> %s <atom:category scheme='http://schemas.google.com/g/2005#kind' term='http://schemas.google.com/photos/2007#photo'/> %s </atom:entry>";
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
            summary = "<atom:summary>%s</atom:summary>".printf(
                Publishing.RESTSupport.decimal_entity_encode(publishable.get_publishing_name()));
        }

        string[] keywords = publishable.get_publishing_keywords();
        string keywords_string = "";
        if (keywords.length > 0) {
		    for (int i = 0; i < keywords.length; i++) {
                string[] tmp;

                if (keywords[i].has_prefix("/"))
                    tmp = keywords[i].substring(1).split("/");
		        else
                    tmp = keywords[i].split("/"); 

                if (keywords_string.length > 0)
                    keywords_string = string.join(", ", keywords_string, string.joinv(", ", tmp));
                else
                    keywords_string = string.joinv(", ", tmp);
            }

            keywords_string = "<mrss:group><mrss:keywords>%s</mrss:keywords></mrss:group>".printf(keywords_string);
        }
        
        string metadata = METADATA_TEMPLATE.printf(Publishing.RESTSupport.decimal_entity_encode(
            publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME)),
            summary, keywords_string);
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
        outbound_message.request_headers.append("Authorization", "Bearer " +
            session.get_auth_token());
        set_message(outbound_message);

        // send the message and get its response
        set_is_executed(true);
        send();
    }
}

internal class AuthCodeEntryPane : Spit.Publishing.DialogPane, GLib.Object {
    private Gtk.Box pane_widget = null;
    private Gtk.Button continue_button = null;
    private Gtk.Entry entry = null;
    private Gtk.Label entry_caption = null;
    private Gtk.Label explanatory_text = null;

    public signal void proceed(AuthCodeEntryPane sender, string authorization_code);

    public AuthCodeEntryPane(Gtk.Builder builder) {
        assert(builder != null);
        assert(builder.get_objects().length() > 0);        
        
        explanatory_text = builder.get_object("explanatory_text") as Gtk.Label;
        entry_caption = builder.get_object("entry_caption") as Gtk.Label;
        entry = builder.get_object("entry") as Gtk.Entry;
        continue_button = builder.get_object("continue_button") as Gtk.Button;
        
        pane_widget = builder.get_object("pane_widget") as Gtk.Box;
        
        pane_widget.show_all();
        
        on_entry_contents_changed();
    }
    
    private void on_continue_clicked() {
        proceed(this, entry.get_text());
    }
    
    private void on_entry_contents_changed() {
        continue_button.set_sensitive(entry.text_length > 0);
    }

    public Gtk.Widget get_widget() {
        return pane_widget;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        continue_button.clicked.connect(on_continue_clicked);
        entry.changed.connect(on_entry_contents_changed);
    }

    public void on_pane_uninstalled() {
        continue_button.clicked.disconnect(on_continue_clicked);
        entry.changed.disconnect(on_entry_contents_changed);
    }
}

internal class NotSetUpMessagePane : Spit.Publishing.DialogPane, GLib.Object {
    private Gtk.Box pane_widget = null;
    private Gtk.Button continue_button = null;
    
    public signal void proceed(NotSetUpMessagePane sender);

    public NotSetUpMessagePane(Gtk.Builder builder) {
        assert(builder != null);
        assert(builder.get_objects().length() > 0);
        
        continue_button = builder.get_object("continue_button") as Gtk.Button;
        pane_widget = builder.get_object("pane_widget") as Gtk.Box;
        
        pane_widget.show_all();
    }
    
    private void on_continue_clicked() {
        proceed(this);
    }

    public Gtk.Widget get_widget() {
        return pane_widget;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        continue_button.clicked.connect(on_continue_clicked);
    }

    public void on_pane_uninstalled() {
        continue_button.clicked.disconnect(on_continue_clicked);
    }
}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {
    private class SizeDescription {
        public string name;
        public int major_axis_pixels;

        public SizeDescription(string name, int major_axis_pixels) {
            this.name = name;
            this.major_axis_pixels = major_axis_pixels;
        }
    }

    private const string DEFAULT_SIZE_CONFIG_KEY = "default_size";
    private const string LAST_ALBUM_CONFIG_KEY = "last_album";
    
    private Gtk.Builder builder = null;
    
    private Gtk.Box pane_widget = null;
    private Gtk.Label login_identity_label = null;
    private Gtk.Label publish_to_label = null;
    private Gtk.RadioButton use_existing_radio = null;
    private Gtk.ComboBoxText existing_albums_combo = null;
    private Gtk.RadioButton create_new_radio = null;
    private Gtk.Entry new_album_entry = null;
    private Gtk.CheckButton public_check = null;
    private Gtk.ComboBoxText size_combo = null;
    private Gtk.CheckButton strip_metadata_check = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    
    private Album[] albums;
    private SizeDescription[] size_descriptions;
    private string username;
    private weak Spit.Publishing.PluginHost host;

    public signal void publish(PublishingParameters parameters, bool strip_metadata);
    public signal void logout();

    public PublishingOptionsPane(Spit.Publishing.PluginHost host, string username, 
        Album[] albums, Spit.Publishing.Publisher.MediaType media_type, Gtk.Builder builder,
        bool strip_metadata) {
        this.username = username;
        this.albums = albums;
        this.host = host;
        size_descriptions = create_size_descriptions();

        this.builder = builder;
        assert(builder != null);
        assert(builder.get_objects().length() > 0);

        // pull in all widgets from builder.
        pane_widget = (Gtk.Box) builder.get_object("picasa_pane_widget");
        login_identity_label = (Gtk.Label) builder.get_object("login_identity_label");
        publish_to_label = (Gtk.Label) builder.get_object("publish_to_label");
        use_existing_radio = (Gtk.RadioButton) builder.get_object("use_existing_radio");
        existing_albums_combo = (Gtk.ComboBoxText) builder.get_object("existing_albums_combo");
        create_new_radio = (Gtk.RadioButton) builder.get_object("create_new_radio");
        new_album_entry = (Gtk.Entry) builder.get_object("new_album_entry");
        public_check = (Gtk.CheckButton) builder.get_object("public_check");
        size_combo = (Gtk.ComboBoxText) builder.get_object("size_combo");
        strip_metadata_check = (Gtk.CheckButton) this.builder.get_object("strip_metadata_check");
        publish_button = (Gtk.Button) builder.get_object("publish_button");
        logout_button = (Gtk.Button) builder.get_object("logout_button");

        // populate any widgets whose contents are programmatically-generated.
        login_identity_label.set_label(_("You are logged into Picasa Web Albums as %s.").printf(username));
        strip_metadata_check.set_active(strip_metadata);


        if((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) == 0) {
            publish_to_label.set_label(_("Videos will appear in:"));
            size_combo.set_visible(false);
            size_combo.set_sensitive(false);
        }
        else {
            publish_to_label.set_label(_("Photos will appear in:"));
            foreach(SizeDescription desc in size_descriptions) {
                size_combo.append_text(desc.name);
            }
            size_combo.set_visible(true);
            size_combo.set_sensitive(true);
            size_combo.set_active(host.get_config_int(DEFAULT_SIZE_CONFIG_KEY, 0));
        }

        // connect all signals.
        use_existing_radio.clicked.connect(on_use_existing_radio_clicked);
        create_new_radio.clicked.connect(on_create_new_radio_clicked);
        new_album_entry.changed.connect(on_new_album_entry_changed);
        logout_button.clicked.connect(on_logout_clicked);
        publish_button.clicked.connect(on_publish_clicked);
    }

    private void on_publish_clicked() {
        // size_combo won't have been set to anything useful if this is the first time we've
        // published to Picasa, and/or we've only published video before, so it may be negative,
        // indicating nothing was selected. Clamp it to a valid value...
        int size_combo_last_active = (size_combo.get_active() >= 0) ? size_combo.get_active() : 0;
        
        host.set_config_int(DEFAULT_SIZE_CONFIG_KEY, size_combo_last_active);
        int photo_major_axis_size = size_descriptions[size_combo_last_active].major_axis_pixels;
        string album_name;
        if (create_new_radio.get_active()) {
            album_name = new_album_entry.get_text();
            host.set_config_string(LAST_ALBUM_CONFIG_KEY, album_name);
            bool is_public = public_check.get_active();
            publish(new PublishingParameters.to_new_album(photo_major_axis_size, album_name,
                is_public), strip_metadata_check.get_active());
        } else {
            album_name = albums[existing_albums_combo.get_active()].name;
            host.set_config_string(LAST_ALBUM_CONFIG_KEY, album_name);
            string album_url = albums[existing_albums_combo.get_active()].url;
            publish(new PublishingParameters.to_existing_album(photo_major_axis_size, album_url), strip_metadata_check.get_active());
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

        result += new SizeDescription(_("Small (640 x 480 pixels)"), 640);
        result += new SizeDescription(_("Medium (1024 x 768 pixels)"), 1024);
        result += new SizeDescription(_("Recommended (1600 x 1200 pixels)"), 1600);
        result += new SizeDescription(_("Google+ (2048 x 1536 pixels)"), 2048);
        result += new SizeDescription(_("Original Size"), PublishingParameters.ORIGINAL_SIZE);

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
    
    protected void notify_publish(PublishingParameters parameters) {
        publish(parameters, strip_metadata_check.get_active());
    }
    
    protected void notify_logout() {
        logout();
    }

    public Gtk.Widget get_widget() {
        return pane_widget;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }
    
    public void on_pane_installed() {
        installed();
         
        publish.connect(notify_publish);
        logout.connect(notify_logout);
    }
    
    public void on_pane_uninstalled() {
        publish.disconnect(notify_publish);
        logout.disconnect(notify_logout);
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

