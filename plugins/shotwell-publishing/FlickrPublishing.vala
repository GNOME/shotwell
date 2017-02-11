/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class FlickrService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "flickr.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;
    
    public FlickrService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_from_resource
                (Resources.RESOURCE_PATH + "/" + ICON_FILENAME);
    }

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.flickr";
    }
    
    public unowned string get_pluggable_name() {
        return "Flickr";
    }
    
    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Lucas Beeler";
        info.copyright = _("Copyright 2016 Software Freedom Conservancy Inc.");
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
        return new Publishing.Flickr.FlickrPublisher(this, host);
    }
    
    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO |
            Spit.Publishing.Publisher.MediaType.VIDEO);
    }
}

namespace Publishing.Flickr {

internal const string SERVICE_NAME = "Flickr";
internal const string ENDPOINT_URL = "https://api.flickr.com/services/rest";
internal const int ORIGINAL_SIZE = -1;
internal const string EXPIRED_SESSION_ERROR_CODE = "98";
internal const string ENCODE_RFC_3986_EXTRA = "!*'();:@&=+$,/?%#[] \\";

internal enum UserKind {
    PRO,
    FREE,
}

internal class VisibilitySpecification {
    public int friends_level;
    public int family_level;
    public int everyone_level;

    public VisibilitySpecification(int friends_level, int family_level, int everyone_level) {
        this.friends_level = friends_level;
        this.family_level = family_level;
        this.everyone_level = everyone_level;
    }
}

// not a struct because we want reference semantics
internal class PublishingParameters {
    public UserKind user_kind;
    public int64 quota_free_bytes;
    public int photo_major_axis_size;
    public string username;
    public VisibilitySpecification visibility_specification;

    public PublishingParameters() {
    }
}

public class FlickrPublisher : Spit.Publishing.Publisher, GLib.Object {
    private Spit.Publishing.Service service;
    private Spit.Publishing.PluginHost host;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private bool running = false;
    private bool was_started = false;
    private Session session = null;
    private PublishingOptionsPane publishing_options_pane = null;
    private Spit.Publishing.Authenticator authenticator = null;
   
    private PublishingParameters parameters = null;

    public FlickrPublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        debug("FlickrPublisher instantiated.");
        this.service = service;
        this.host = host;
        this.session = new Session();
        this.parameters = new PublishingParameters();
        this.authenticator = Publishing.Authenticator.Factory.get_instance().create("flickr", host);

        this.authenticator.authenticated.connect(on_session_authenticated);
    }
    
    ~FlickrPublisher() {
        this.authenticator.authenticated.disconnect(on_session_authenticated);
    }

    private bool get_persistent_strip_metadata() {
        return host.get_config_bool("strip_metadata", false);
    }

    private void set_persistent_strip_metadata(bool strip_metadata) {
        host.set_config_bool("strip_metadata", strip_metadata);
    }

    private void on_session_authenticated() {
        if (!is_running())
            return;

        debug("EVENT: a fully authenticated session has become available");

        var params = this.authenticator.get_authentication_parameter();
        Variant consumer_key = null;
        Variant consumer_secret = null;
        Variant auth_token = null;
        Variant auth_token_secret = null;
        Variant username = null;

        params.lookup_extended("ConsumerKey", null, out consumer_key);
        params.lookup_extended("ConsumerSecret", null, out consumer_secret);
        session.set_api_credentials(consumer_key.get_string(), consumer_secret.get_string());

        params.lookup_extended("AuthToken", null, out auth_token);
        params.lookup_extended("AuthTokenSecret", null, out auth_token_secret);
        params.lookup_extended("Username", null, out username);
        session.set_access_phase_credentials(auth_token.get_string(),
                auth_token_secret.get_string(), username.get_string());

        parameters.username = session.get_username();

        do_fetch_account_info();
    }

    private void on_account_fetch_txn_completed(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_account_fetch_txn_completed);
        txn.network_error.disconnect(on_account_fetch_txn_error);

        if (!is_running())
            return;

        debug("EVENT: account fetch transaction response received over the network");
        do_parse_account_info_from_xml(txn.get_response());
    }

    private void on_account_fetch_txn_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_account_fetch_txn_completed);
        txn.network_error.disconnect(on_account_fetch_txn_error);

        if (!is_running())
            return;

        debug("EVENT: account fetch transaction caused a network error");
        host.post_error(err);
    }

    private void on_account_info_available() {
        if (!is_running())
            return;

        debug("EVENT: account information has become available");
        do_show_publishing_options_pane();
    }

    private void on_publishing_options_pane_publish(bool strip_metadata) {
        publishing_options_pane.publish.disconnect(on_publishing_options_pane_publish);
        publishing_options_pane.logout.disconnect(on_publishing_options_pane_logout);
        
        if (!is_running())
            return;

        debug("EVENT: user clicked the 'Publish' button in the publishing options pane");
        do_publish(strip_metadata);
    }

    private void on_publishing_options_pane_logout() {
        publishing_options_pane.publish.disconnect(on_publishing_options_pane_publish);
        publishing_options_pane.logout.disconnect(on_publishing_options_pane_logout);

        if (!is_running())
            return;

        debug("EVENT: user clicked the 'Logout' button in the publishing options pane");

        do_logout();
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

    private void do_fetch_account_info() {
        debug("ACTION: running network transaction to fetch account information");

        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();

        AccountInfoFetchTransaction txn = new AccountInfoFetchTransaction(session);
        txn.completed.connect(on_account_fetch_txn_completed);
        txn.network_error.connect(on_account_fetch_txn_error);

        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }

    private void do_parse_account_info_from_xml(string xml) {
        debug("ACTION: parsing account information from xml = '%s'", xml);
        try {
            Publishing.RESTSupport.XmlDocument response_doc = Transaction.parse_flickr_response(xml);
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
                throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "Unable to determine if user has free or pro account");
            
            var quota_bytes_left = int64.parse(remaining_kb_str) * 1024;

            parameters.quota_free_bytes = quota_bytes_left;
            parameters.user_kind = user_kind;

        } catch (Spit.Publishing.PublishingError err) {
            // expired session errors are recoverable, so handle it and then short-circuit return.
            // don't call post_error( ) on the plug-in host because that's intended for
            // unrecoverable errors and will halt publishing
            if (err is Spit.Publishing.PublishingError.EXPIRED_SESSION) {
                do_logout();
                return;
            }

            host.post_error(err);
            return;
        }
        
        on_account_info_available();
    }
    
    private void do_logout() {
        debug("ACTION: logging user out, deauthenticating session, and erasing stored credentials");

        if (authenticator.can_logout()) {
            authenticator.logout();
        }

        running = false;

        attempt_start();
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: displaying publishing options pane");

        host.set_service_locked(false);

        Gtk.Builder builder = new Gtk.Builder();

        try {
            // the trailing get_path() is required, since add_from_file can't cope
            // with File objects directly and expects a pathname instead.
            builder.add_from_resource(Resources.RESOURCE_PATH + "/" +
                    "flickr_publishing_options_pane.ui");
        } catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            host.post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is unavailable. Publishing to Flickr can’t continue.")));
            return;
        }

        publishing_options_pane = new PublishingOptionsPane(this, parameters,
            host.get_publishable_media_type(), builder, get_persistent_strip_metadata());
        publishing_options_pane.publish.connect(on_publishing_options_pane_publish);
        publishing_options_pane.logout.connect(on_publishing_options_pane_logout);
        host.install_dialog_pane(publishing_options_pane);
    }
    
    public static int flickr_date_time_compare_func(Spit.Publishing.Publishable a, 
        Spit.Publishing.Publishable b) {
        return a.get_exposure_date_time().compare(b.get_exposure_date_time());
    }

    private void do_publish(bool strip_metadata) {
        set_persistent_strip_metadata(strip_metadata);
        debug("ACTION: uploading media items to remote server.");

        host.set_service_locked(true);
        progress_reporter = host.serialize_publishables(parameters.photo_major_axis_size, strip_metadata);

        // Serialization is a long and potentially cancellable operation, so before we use
        // the publishables, make sure that the publishing interaction is still running. If it
        // isn't the publishing environment may be partially torn down so do a short-circuit
        // return
        if (!is_running())
            return;

        // Sort publishables in reverse-chronological order.
        Spit.Publishing.Publishable[] publishables = host.get_publishables();
        Gee.ArrayList<Spit.Publishing.Publishable> sorted_list =
            new Gee.ArrayList<Spit.Publishing.Publishable>();
        foreach (Spit.Publishing.Publishable p in publishables) {
            sorted_list.add(p);
        }
        sorted_list.sort(flickr_date_time_compare_func);
        
        Uploader uploader = new Uploader(session, sorted_list.to_array(), parameters, strip_metadata);
        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);
        uploader.upload(on_upload_status_updated);
    }

    private void do_show_success_pane() {
        debug("ACTION: showing success pane.");

        host.set_service_locked(false);
        host.install_success_pane();
    }

    internal int get_persistent_visibility() {
        return host.get_config_int("visibility", 0);
    }
    
    internal void set_persistent_visibility(int vis) {
        host.set_config_int("visibility", vis);
    }
    
    internal int get_persistent_default_size() {
        return host.get_config_int("default_size", 1);
    }
    
    internal void set_persistent_default_size(int size) {
        host.set_config_int("default_size", size);
    }

    public Spit.Publishing.Service get_service() {
        return service;
    }

    public bool is_running() {
        return running;
    }
    
    // this helper doesn't check state, merely validates and authenticates the session and installs
    // the proper panes
    private void attempt_start() {
        running = true;
        was_started = true;
        
        authenticator.authenticate();
    }
    
    public void start() {
        if (is_running())
            return;
        
        if (was_started)
            error("FlickrPublisher: start( ): can't start; this publisher is not restartable.");
        
        debug("FlickrPublisher: starting interaction.");
        
        attempt_start();
    }
    
    public void stop() {
        debug("FlickrPublisher: stop( ) invoked.");

        if (session != null)
            session.stop_transactions();

        running = false;
    }
}

internal class Transaction : Publishing.RESTSupport.Transaction {
    public Transaction(Session session, Publishing.RESTSupport.HttpMethod method =
        Publishing.RESTSupport.HttpMethod.POST) {
        base(session, method);
        
        add_argument("oauth_nonce", session.get_oauth_nonce());
        add_argument("oauth_signature_method", "HMAC-SHA1");
        add_argument("oauth_version", "1.0");
        add_argument("oauth_callback", "oob");
        add_argument("oauth_timestamp", session.get_oauth_timestamp());
        add_argument("oauth_consumer_key", session.get_consumer_key());
    }
    
    public Transaction.with_uri(Session session, string uri,
        Publishing.RESTSupport.HttpMethod method = Publishing.RESTSupport.HttpMethod.POST) {
        base.with_endpoint_url(session, uri, method);

        add_argument("oauth_nonce", session.get_oauth_nonce());
        add_argument("oauth_signature_method", "HMAC-SHA1");
        add_argument("oauth_version", "1.0");
        add_argument("oauth_callback", "oob");
        add_argument("oauth_timestamp", session.get_oauth_timestamp());
        add_argument("oauth_consumer_key", session.get_consumer_key());
    }

    public override void execute() throws Spit.Publishing.PublishingError {
        ((Session) get_parent_session()).sign_transaction(this);
        
        base.execute();
    }

    public static string? validate_xml(Publishing.RESTSupport.XmlDocument doc) {
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
        } catch (Spit.Publishing.PublishingError err) {
            return "No error code specified";
        }
        
        // this error format is mandatory, because the parse_flickr_response( ) expects error
        // messages to be in this format. If you want to change the error reporting format, you
        // need to modify parse_flickr_response( ) to parse the new format too.
        return "%s (error code %s)".printf(errcode->get_prop("msg"), errcode->get_prop("code"));
    }

    // Flickr responses have a special flavor of expired session reporting. Expired sessions
    // are reported as just another service error, so they have to be converted from
    // service errors. Always use this wrapper function to parse Flickr response XML instead
    // of the generic Publishing.RESTSupport.XmlDocument.parse_string( ) from the Yorba
    // REST support classes. While using Publishing.RESTSupport.XmlDocument.parse_string( ) won't
    // cause anything really bad to happen, it will make expired session errors unrecoverable,
    // which is annoying for users.
    public static Publishing.RESTSupport.XmlDocument parse_flickr_response(string xml)
        throws Spit.Publishing.PublishingError {
        Publishing.RESTSupport.XmlDocument? result = null;

        try {
            result = Publishing.RESTSupport.XmlDocument.parse_string(xml, validate_xml);
        } catch (Spit.Publishing.PublishingError e) {
            if (e.message.contains("(error code %s)".printf(EXPIRED_SESSION_ERROR_CODE))) {
                throw new Spit.Publishing.PublishingError.EXPIRED_SESSION(e.message);
            } else {
                throw e;
            }
        }
        
        return result;
    }
}

internal class AccountInfoFetchTransaction : Transaction {
    public AccountInfoFetchTransaction(Session session) {
        base(session, Publishing.RESTSupport.HttpMethod.GET);
        add_argument("method", "flickr.people.getUploadStatus");
        add_argument("oauth_token", session.get_access_phase_token());
    }
}

private class UploadTransaction : Publishing.RESTSupport.UploadTransaction {
    private PublishingParameters parameters;
    private Session session;
    private Publishing.RESTSupport.Argument[] auth_header_fields;

    public UploadTransaction(Session session, PublishingParameters parameters,
        Spit.Publishing.Publishable publishable) {
        base.with_endpoint_url(session, publishable, "https://api.flickr.com/services/upload");

        this.parameters = parameters;
        this.session = session;
        this.auth_header_fields = new Publishing.RESTSupport.Argument[0];

        add_authorization_header_field("oauth_nonce", session.get_oauth_nonce());
        add_authorization_header_field("oauth_signature_method", "HMAC-SHA1");
        add_authorization_header_field("oauth_version", "1.0");
        add_authorization_header_field("oauth_callback", "oob");
        add_authorization_header_field("oauth_timestamp", session.get_oauth_timestamp());
        add_authorization_header_field("oauth_consumer_key", session.get_consumer_key());
        add_authorization_header_field("oauth_token", session.get_access_phase_token());
        
        add_argument("is_public", ("%d".printf(parameters.visibility_specification.everyone_level)));
        add_argument("is_friend", ("%d".printf(parameters.visibility_specification.friends_level)));
        add_argument("is_family", ("%d".printf(parameters.visibility_specification.family_level)));

        GLib.HashTable<string, string> disposition_table =
            new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
        string? filename = publishable.get_publishing_name();
        if (filename == null || filename == "")
            filename = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);

        /// TODO: This may need to be revisited to send the title separately; please see
        /// http://www.flickr.com/services/api/upload.api.html for more details.
        disposition_table.insert("filename",  Soup.URI.encode(
            publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME), null));

        disposition_table.insert("name", "photo");

        set_binary_disposition_table(disposition_table);
    }
    
    public void add_authorization_header_field(string key, string value) {
        auth_header_fields += new Publishing.RESTSupport.Argument(key, value);
    }
    
    public Publishing.RESTSupport.Argument[] get_authorization_header_fields() {
        return auth_header_fields;
    }
    
    public string get_authorization_header_string() {
        string result = "OAuth ";
        
        for (int i = 0; i < auth_header_fields.length; i++) {
            result += auth_header_fields[i].key;
            result += "=";
            result += ("\"" + auth_header_fields[i].value + "\"");
            
            if (i < auth_header_fields.length - 1)
                result += ", ";
        }
        
        return result;
    }
    
    public override void execute() throws Spit.Publishing.PublishingError {
        session.sign_transaction(this);
        
        string authorization_header = get_authorization_header_string();
        
        debug("executing upload transaction: authorization header string = '%s'",
            authorization_header);
        add_header("Authorization", authorization_header);
        
        base.execute();
    }
}

internal class Session : Publishing.RESTSupport.Session {
    private string? access_phase_token = null;
    private string? access_phase_token_secret = null;
    private string? username = null;
    private string? consumer_key = null;
    private string? consumer_secret = null;

    public Session() {
        base(ENDPOINT_URL);
    }

    public override bool is_authenticated() {
        return (access_phase_token != null && access_phase_token_secret != null &&
            username != null);
    }

    public void set_api_credentials(string consumer_key, string consumer_secret) {
        this.consumer_key = consumer_key;
        this.consumer_secret = consumer_secret;
    }
    
    public void sign_transaction(Publishing.RESTSupport.Transaction txn) {
        string http_method = txn.get_method().to_string();
        
        debug("signing transaction with parameters:");
        debug("HTTP method = " + http_method);

        Publishing.RESTSupport.Argument[] base_string_arguments = txn.get_arguments();

        UploadTransaction? upload_txn = txn as UploadTransaction;
        if (upload_txn != null) {
            debug("this transaction is an UploadTransaction; including Authorization header " +
                "fields in signature base string");
            
            Publishing.RESTSupport.Argument[] auth_header_args =
                upload_txn.get_authorization_header_fields();

            foreach (Publishing.RESTSupport.Argument arg in auth_header_args)
                base_string_arguments += arg;
        }
        
        Publishing.RESTSupport.Argument[] sorted_args =
            Publishing.RESTSupport.Argument.sort(base_string_arguments);
        
        string arguments_string = "";
        for (int i = 0; i < sorted_args.length; i++) {
            arguments_string += (sorted_args[i].key + "=" + sorted_args[i].value);
            if (i < sorted_args.length - 1)
                arguments_string += "&";
        }

        string? signing_key = null;
        if (access_phase_token_secret != null) {
            debug("access phase token secret available; using it as signing key");

            signing_key = consumer_secret + "&" + access_phase_token_secret;
        } else {
            debug("neither access phase nor request phase token secrets available; using API " +
                "key as signing key");

            signing_key = consumer_secret + "&";
        }
        
        string signature_base_string = http_method + "&" + Soup.URI.encode(
            txn.get_endpoint_url(), ENCODE_RFC_3986_EXTRA) + "&" +
            Soup.URI.encode(arguments_string, ENCODE_RFC_3986_EXTRA);

        debug("signature base string = '%s'", signature_base_string);
        
        debug("signing key = '%s'", signing_key);

        // compute the signature
        string signature = RESTSupport.hmac_sha1(signing_key, signature_base_string);
        signature = Soup.URI.encode(signature, ENCODE_RFC_3986_EXTRA);

        debug("signature = '%s'", signature);

        if (upload_txn != null)
            upload_txn.add_authorization_header_field("oauth_signature", signature);
        else
            txn.add_argument("oauth_signature", signature);
    }
    
    public void set_access_phase_credentials(string token, string secret, string username) {
        this.access_phase_token = token;
        this.access_phase_token_secret = secret;
        this.username = username;
        
        authenticated();
    }

    public string get_oauth_nonce() {
        TimeVal currtime = TimeVal();
        currtime.get_current_time();
        
        return Checksum.compute_for_string(ChecksumType.MD5, currtime.tv_sec.to_string() +
            currtime.tv_usec.to_string());
    }
    
    public string get_oauth_timestamp() {
        return GLib.get_real_time().to_string().substring(0, 10);
    }

    public string get_consumer_key() {
        assert(consumer_key != null);
        return consumer_key;
    }

    public string get_access_phase_token() {
        assert(access_phase_token != null);
        return access_phase_token;
    }
    
    public string get_username() {
        assert(is_authenticated());
        return username;
    }
}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {
    private class SizeEntry {
        public string title;
        public int size;

        public SizeEntry(string creator_title, int creator_size) {
            title = creator_title;
            size = creator_size;
        }
    }

    private class VisibilityEntry {
        public VisibilitySpecification specification;
        public string title;

        public VisibilityEntry(string creator_title, VisibilitySpecification creator_specification) {
            specification = creator_specification;
            title = creator_title;
        }
    }

    private Gtk.Builder builder;
    private Gtk.Box pane_widget = null;
    private Gtk.Label visibility_label = null;
    private Gtk.Label upload_info_label = null;
    private Gtk.Label size_label = null;
    private Gtk.Button logout_button = null;
    private Gtk.Button publish_button = null;
    private Gtk.ComboBoxText visibility_combo = null;
    private Gtk.ComboBoxText size_combo = null;
    private Gtk.CheckButton strip_metadata_check = null;
    private VisibilityEntry[] visibilities = null;
    private SizeEntry[] sizes = null;
    private PublishingParameters parameters = null;
    private FlickrPublisher publisher = null;
    private Spit.Publishing.Publisher.MediaType media_type;

    public signal void publish(bool strip_metadata);
    public signal void logout();

    public PublishingOptionsPane(FlickrPublisher publisher, PublishingParameters parameters,
        Spit.Publishing.Publisher.MediaType media_type, Gtk.Builder builder, bool strip_metadata) {
        this.builder = builder;
        assert(builder != null);
        assert(builder.get_objects().length() > 0);
        
        // pull in the necessary widgets from the glade file
        pane_widget = (Gtk.Box) this.builder.get_object("flickr_pane");
        visibility_label = (Gtk.Label) this.builder.get_object("visibility_label");
        upload_info_label = (Gtk.Label) this.builder.get_object("upload_info_label");
        logout_button = (Gtk.Button) this.builder.get_object("logout_button");
        publish_button = (Gtk.Button) this.builder.get_object("publish_button");
        visibility_combo = (Gtk.ComboBoxText) this.builder.get_object("visibility_combo");
        size_combo = (Gtk.ComboBoxText) this.builder.get_object("size_combo");
        size_label = (Gtk.Label) this.builder.get_object("size_label");
        strip_metadata_check = (Gtk.CheckButton) this.builder.get_object("strip_metadata_check");

        this.parameters = parameters;
        this.publisher = publisher;
        this.media_type = media_type;

        visibilities = create_visibilities();
        sizes = create_sizes();

        string upload_label_text = _("You are logged into Flickr as %s.\n\n").printf(parameters.username);
        if (parameters.user_kind == UserKind.FREE) {
            upload_label_text += _("Your free Flickr account limits how much data you can upload per month.\nThis month you have %s remaining in your upload quota.").printf(GLib.format_size(parameters.quota_free_bytes, FormatSizeFlags.LONG_FORMAT | FormatSizeFlags.IEC_UNITS));
        } else {
            upload_label_text += _("Your Flickr Pro account entitles you to unlimited uploads.");
        }

        upload_info_label.set_label(upload_label_text);

        string visibility_label_text = _("Photos _visible to:");
        if ((media_type == Spit.Publishing.Publisher.MediaType.VIDEO)) {
            visibility_label_text = _("Videos _visible to:");
        } else if ((media_type == (Spit.Publishing.Publisher.MediaType.PHOTO |
                                   Spit.Publishing.Publisher.MediaType.VIDEO))) {
            visibility_label_text = _("Photos and videos _visible to:");
        }
        
        visibility_label.set_label(visibility_label_text);

        populate_visibility_combo();
        visibility_combo.changed.connect(on_visibility_changed);

        if ((media_type != Spit.Publishing.Publisher.MediaType.VIDEO)) {
            populate_size_combo();
            size_combo.changed.connect(on_size_changed);
        } else {
            // publishing -only- video - don't let the user manipulate the photo size choices.
            size_combo.set_sensitive(false);
            size_label.set_sensitive(false);
        }
        
        strip_metadata_check.set_active(strip_metadata);

        logout_button.clicked.connect(on_logout_clicked);
        publish_button.clicked.connect(on_publish_clicked);
    }

    private void on_logout_clicked() {
        logout();
    }

    private void on_publish_clicked() {
        parameters.visibility_specification =
            visibilities[visibility_combo.get_active()].specification;

        if ((media_type & Spit.Publishing.Publisher.MediaType.PHOTO) != 0)
            parameters.photo_major_axis_size = sizes[size_combo.get_active()].size;

        publish(strip_metadata_check.get_active());
    }

    private VisibilityEntry[] create_visibilities() {
        VisibilityEntry[] result = new VisibilityEntry[0];

        result += new VisibilityEntry(_("Everyone"), new VisibilitySpecification(1, 1, 1));
        result += new VisibilityEntry(_("Friends & family only"), new VisibilitySpecification(1, 1, 0));
        result += new VisibilityEntry(_("Family only"), new VisibilitySpecification(0, 1, 0));
        result += new VisibilityEntry(_("Friends only"), new VisibilitySpecification(1, 0, 0));
        result += new VisibilityEntry(_("Just me"), new VisibilitySpecification(0, 0, 0));

        return result;
    }

    private void populate_visibility_combo() {
        if (visibilities == null)
            visibilities = create_visibilities();

        foreach (VisibilityEntry v in visibilities)
            visibility_combo.append_text(v.title);

        visibility_combo.set_active(publisher.get_persistent_visibility());
    }

    private SizeEntry[] create_sizes() {
        SizeEntry[] result = new SizeEntry[0];

        result += new SizeEntry(_("500 × 375 pixels"), 500);
        result += new SizeEntry(_("1024 × 768 pixels"), 1024);
        result += new SizeEntry(_("2048 × 1536 pixels"), 2048);
        result += new SizeEntry(_("4096 × 3072 pixels"), 4096);
        result += new SizeEntry(_("Original size"), ORIGINAL_SIZE);

        return result;
    }

    private void populate_size_combo() {
        if (sizes == null)
            sizes = create_sizes();

        foreach (SizeEntry e in sizes)
            size_combo.append_text(e.title);

        size_combo.set_active(publisher.get_persistent_default_size());
    }

    private void on_size_changed() {
        publisher.set_persistent_default_size(size_combo.get_active());
    }

    private void on_visibility_changed() {
        publisher.set_persistent_visibility(visibility_combo.get_active());
    }
    
    protected void notify_publish() {
        publish(strip_metadata_check.get_active());
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
        publish.connect(notify_publish);
        logout.connect(notify_logout);
    }
    
    public void on_pane_uninstalled() {
        publish.disconnect(notify_publish);
        logout.disconnect(notify_logout);
    }
}

internal class Uploader : Publishing.RESTSupport.BatchUploader {
    private PublishingParameters parameters;
    private bool strip_metadata;

    public Uploader(Session session, Spit.Publishing.Publishable[] publishables,
        PublishingParameters parameters, bool strip_metadata) {
        base(session, publishables);
        
        this.parameters = parameters;
        this.strip_metadata = strip_metadata;
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
        
        // Flickr internationalization issues only affect IPTC tags; XMP, being an XML
        // grammar and using standard XML internationalization mechanisms, doesn't need any i18n
        // massaging before upload, so if the publishable doesn't have any IPTC metadata, then
        // just do a short-circuit return
        if (!publishable_metadata.has_iptc())
            return;

        if (publishable_metadata.has_tag("Iptc.Application2.Caption"))
            publishable_metadata.set_tag_string("Iptc.Application2.Caption",
                Publishing.RESTSupport.asciify_string(publishable_metadata.get_tag_string(
                "Iptc.Application2.Caption")));

        if (publishable_metadata.has_tag("Iptc.Application2.Headline"))
            publishable_metadata.set_tag_string("Iptc.Application2.Headline",
                Publishing.RESTSupport.asciify_string(publishable_metadata.get_tag_string(
                "Iptc.Application2.Headline")));

        if (publishable_metadata.has_tag("Iptc.Application2.Keywords")) {
            Gee.Set<string> keyword_set = new Gee.HashSet<string>();
            string[] iptc_keywords = publishable_metadata.get_tag_multiple("Iptc.Application2.Keywords");
            if (iptc_keywords != null)
                foreach (string keyword in iptc_keywords)
                    keyword_set.add(keyword);

            string[] xmp_keywords = publishable_metadata.get_tag_multiple("Xmp.dc.subject");
            if (xmp_keywords != null)
                foreach (string keyword in xmp_keywords)
                    keyword_set.add(keyword);

            string[] all_keywords = keyword_set.to_array();
            // append a null pointer to the end of all_keywords -- this is a necessary workaround
            // for http://trac.yorba.org/ticket/3264. See also http://trac.yorba.org/ticket/3257,
            // which describes the user-visible behavior seen in the Flickr Connector as a result
            // of the former bug.
            all_keywords += null;

            string[] no_keywords = new string[1];
            // append a null pointer to the end of no_keywords -- this is a necessary workaround
            // for http://trac.yorba.org/ticket/3264. See also http://trac.yorba.org/ticket/3257,
            // which describes the user-visible behavior seen in the Flickr Connector as a result
            // of the former bug.
            no_keywords[0] = null;
            
            publishable_metadata.set_tag_multiple("Xmp.dc.subject", all_keywords);
            publishable_metadata.set_tag_multiple("Iptc.Application2.Keywords", no_keywords);

            try {
                publishable_metadata.save_file(publishable.get_serialized_file().get_path());
            } catch (GLib.Error err) {
                warning("couldn't write metadata to file '%s' for upload preprocessing.",
                    publishable.get_serialized_file().get_path());
            }
        }
    }
    
    protected override Publishing.RESTSupport.Transaction create_transaction(
        Spit.Publishing.Publishable publishable) {
        preprocess_publishable(get_current_publishable());
        return new UploadTransaction((Session) get_session(), parameters,
            get_current_publishable());
    }
}

}

