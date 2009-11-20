/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

namespace FacebookConnector {
// this should not be changed by anyone unless they know what they're doing
public const string API_KEY = "3afe0a1888bd340254b1587025f8d1a5";
public const int MAX_PHOTO_DIMENSION = 604;

class UploadPane : PublishingDialogPane {
    private Gtk.RadioButton use_existing_radio = null;
    private Gtk.RadioButton create_new_radio = null;
    private Gtk.ComboBox existing_albums_combo = null;
    private Gtk.Entry new_album_entry = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private Session host_session = null;
    private Gtk.Label how_to_label = null;

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
    
    public signal void logout();
    public signal void publish(string target_album);
}

class NotLoggedInPane : PublishingDialogPane {
    private Gtk.Button login_button;

    public NotLoggedInPane() {
        Gtk.SeparatorToolItem top_space = new Gtk.SeparatorToolItem();
        top_space.set_draw(false);
        Gtk.SeparatorToolItem bottom_space = new Gtk.SeparatorToolItem();
        bottom_space.set_draw(false);
        add(top_space);
        top_space.set_size_request(-1, 112);

        Gtk.Label not_logged_in_label = new Gtk.Label(_("You are not currently logged in to Facebook. Click 'Login' below to login.\nIf you don't yet have a Facebook account, you can create one during the login process."));
        add(not_logged_in_label);

        login_button = new Gtk.Button();
        Gtk.HBox login_button_layouter = new Gtk.HBox(false, 8);
        Gtk.SeparatorToolItem login_button_left_padding = new Gtk.SeparatorToolItem();
        login_button_left_padding.set_draw(false);
        Gtk.SeparatorToolItem login_button_right_padding = new Gtk.SeparatorToolItem();
        login_button_right_padding.set_draw(false);
        login_button_layouter.add(login_button_left_padding);
        login_button_left_padding.set_size_request(100, -1);
        login_button_layouter.add(login_button);
        login_button_layouter.add(login_button_right_padding);
        login_button_right_padding.set_size_request(100, -1);
        login_button.set_label(_("Login"));
        login_button.clicked += on_login_clicked;
        add(login_button_layouter);
        add(bottom_space);
        bottom_space.set_size_request(-1, 112);
    }
    
    private void on_login_clicked() {
        login_requested();
    }
    
    public signal void login_requested();
}

public struct Album {
    string name;
    string id;
    
    Album(string creator_name, string creator_id) {
        name = creator_name;
        id = creator_id;
    }
}

private const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");
private const int MAX_RETRIES = 4;

private Album[] get_albums(Session session) throws PublishingError {
    Album[] result = new Album[0];

    Request albums_request = new AlbumQueryRequest(session);
    albums_request.execute();
    string response = albums_request.get_response();
    
    Xml.Doc* response_doc = validate_document(response, "photos_getAlbums_response");   
    Xml.Node* root = response_doc->get_root_element();
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

        if (name_val == null) {
            delete response_doc;
            throw new PublishingError.COMMUNICATION("can't get albums: XML document contains " +
                "an <album> entity without a <name> child");
        }
        if (aid_val == null) {
            delete response_doc;
            throw new PublishingError.COMMUNICATION("can't get albums: XML document contains " +
                "an <album> entity without an <aid> child");
        }

        result += Album(name_val, aid_val);
    }
    
    if (result.length == 0) {
        delete response_doc;
        throw new PublishingError.COMMUNICATION("can't get albums: failed to get at least one " +
            "valid album");
    }

    delete response_doc;
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
    AlbumCreationRequest creation_request =
        new AlbumCreationRequest(session, album_name);
    creation_request.execute();
    
    string response = creation_request.get_response();

    Xml.Doc* response_doc = validate_document(response, "photos_createAlbum_response");
    Xml.Node* root = response_doc->get_root_element();
    Xml.Node* doc_node_iter = root->children;
    
    string aid = null;
    for ( ; doc_node_iter != null; doc_node_iter = doc_node_iter->next) {
        if (doc_node_iter->name == "aid") {
            aid = doc_node_iter->get_content();
        }
    }
    
    if (aid == null) {
        delete response_doc;
        throw new PublishingError.COMMUNICATION("can't create album: got an XML document of " +
            "unknown kind");
    }
    
    delete response_doc;
    return aid;
}

bool is_persistent_session_valid() {
    Config config = Config.get_instance();

    string session_key = config.get_facebook_session_key();
    string session_secret = config.get_facebook_session_secret();
    string uid = config.get_facebook_uid();
    string user_name = config.get_facebook_user_name();
    
    if ((session_key == null) || (session_secret == null) || (uid == null) ||
        (user_name == null))
        return false;
    else
        return true;
}

void invalidate_persistent_session() {
    Config config = Config.get_instance();
    
    config.clear_facebook_session_key();
    config.clear_facebook_session_secret();
    config.clear_facebook_uid();
    config.clear_facebook_user_name();
}

public class LoginShell : Gtk.HBox {
    private WebKit.WebView webview = null;
    private Gtk.ScrolledWindow webview_frame = null;

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
      
    public signal void login_success(Session host_session);
    public signal void login_failure();
    public signal void login_error();
}

public class Session {
    // The facebook REST endpoint will communicate with only a small set of
    // approved user agents. The web client classes in the Java JDK are part of
    // this officially blessed set, so we spoof the JDK.
    private const string USER_AGENT = "Java/1.6.0_16";
    private const string api_version = "1.0";
    private string session_key = null;
    private string uid = null;
    private string secret = null;
    private string api_key = null;
    private Soup.Session session_connection = null;
    private string user_name = null;
    
    public Session(string creator_session_key, string creator_secret, string creator_uid,
        string creator_api_key, string creator_user_name) {
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
        return api_version;
    }
    
    public Soup.Session get_connection() {
        return session_connection;
    }

    public string get_user_name() throws PublishingError {
        if (user_name == null) {
            SessionUserRequest user_info_req = new SessionUserRequest(this);
            
            user_info_req.execute();
            
            string response = user_info_req.get_response();
        
            Xml.Doc* response_doc = validate_document(response, "users_getInfo_response");
        
            Xml.Node* root = response_doc->get_root_element();
            Xml.Node* doc_node_iter = root->children;
            if (doc_node_iter == null) {
                delete response_doc;
                throw new PublishingError.COMMUNICATION("can't get user name: got an XML " +
                    "document from the server of unknown kind");
            }

            for ( ; doc_node_iter != null; doc_node_iter = doc_node_iter->next) {
                if (doc_node_iter->name != "user")
                    continue;

                Xml.Node* user_node_iter = doc_node_iter->children;
                for ( ; user_node_iter != null; user_node_iter = user_node_iter->next) {
                    if (user_node_iter->name == "name") {
                        user_name = user_node_iter->get_content();
                        delete response_doc;
                        return user_name;
                    }
                }
            }
            
            delete response_doc;
            throw new PublishingError.COMMUNICATION("can't get user name: XML document didn't " +
                "contain a <user> or <name> element");
        }

        // not a memory leak -- no need to delete response_doc here since it's not in scope
        return user_name;
    }
}

public Xml.Doc* validate_document(string text, string root_node_name) throws PublishingError {
    if ((text == null) || (text == "")) {
        throw new PublishingError.COMMUNICATION("response text is empty");
    }

    Xml.Doc* doc = Xml.Parser.parse_doc(text);
    if (doc == null) {
        throw new PublishingError.COMMUNICATION("response text isn't valid XML");
    }

    Xml.Node* root = doc->get_root_element();
    if (root == null) {
        delete doc;
        throw new PublishingError.COMMUNICATION("response text isn't valid XML");
    }
    
    if (root->name != root_node_name) {
        delete doc;
        throw new PublishingError.COMMUNICATION("response text is an XML document of " +
            "unknown kind");
    }

    Xml.Node* doc_node_iter = root->children;
    if (doc_node_iter == null) {
        delete doc;
        throw new PublishingError.COMMUNICATION("response text is an XML document of " +
            "unknown kind");
    }
    
    return doc;
}

public class Request {
    protected struct RESTArgument {
        string key;
        string value;

        public RESTArgument(string creator_key, string creator_val) {
            key = creator_key;
            value = creator_val;
        }
        
        public static int compare(void* p1, void* p2) {
            RESTArgument* arg1 = (RESTArgument*) p1;
            RESTArgument* arg2 = (RESTArgument*) p2;

            return strcmp(arg1->key, arg2->key);
        }
    }

    private Session host_session;
    private string method;
    private RESTArgument[] arguments = new RESTArgument[0];
    private string signed_encoding = null;
    private string call_id = null;
    private string signature = null;
    private bool is_executed = false;
    private string response = null;

    public Request(Session creator_session, string creator_method) {
        host_session = creator_session;
        method = creator_method;
    }

    public void add_argument(string key, string value) {
        assert(!is_executed);

        RESTArgument arg = RESTArgument(key, value);
        arguments += arg;
    }
    
    protected RESTArgument[] get_arguments() {
        return arguments;
    }

    public virtual string execute() {
        assert(!is_executed);

        Soup.Message post_req = new Soup.Message("POST", "http://api.facebook.com/restserver.php");

        string body_text = get_signed_encoding();
        post_req.set_request("application/x-www-form-urlencoded", Soup.MemoryUse.COPY,
            body_text, body_text.length);

        host_session.get_connection().send_message(post_req);

        response = post_req.response_body.data;
        is_executed = true;

        return response;
    }

    protected RESTArgument[] get_sorted_arg_array() {
        RESTArgument[] encoding_array = new RESTArgument[0];

        // We distinguish two kinds of arguments passed to the Facebook web API via
        // REST. The first kind of arguments, called "universal arguments" are
        // required by all calls to facebook API. The second kind of arguments,
        // "call-specific arguments" are unique to a specific call. For example,
        // calls to notifications.send require a comma-separated list of user ids
        // (the users to send the notifications to) whereas calls to photos.get
        // require an album id.
        
        // set up the universal arguments
        encoding_array += RESTArgument("api_key", host_session.get_api_key());
        encoding_array += RESTArgument("session_key", host_session.get_session_key());
        encoding_array += RESTArgument("v", host_session.get_api_version());
        encoding_array += RESTArgument("call_id", get_call_id());
        encoding_array += RESTArgument("method", method);
        
        // add any call-specific arguments previously added by the user
        foreach (RESTArgument arg in arguments)
            encoding_array += arg;

        // sort the arguments -- this is necessary to properly compute a digital
        // signature for the request
        qsort(encoding_array, encoding_array.length, sizeof(RESTArgument), RESTArgument.compare);
        
        return encoding_array;
    }

    private string get_encoded_form() {
        RESTArgument[] encoding_array = get_sorted_arg_array();

        // concatenate the elements of the arg array into a HTTP POST formdata string
        int last = encoding_array.length - 1;
        string formdata_string = "";
        for (int i = 0; i < last; i++)
            formdata_string = formdata_string + ("%s=%s&".printf(encoding_array[i].key,
                encoding_array[i].value));
        formdata_string = formdata_string + ("%s=%s".printf(encoding_array[last].key,
                encoding_array[last].value));

        return formdata_string;
    }
   
    private string get_signed_encoding() {
        if (signed_encoding == null) {           
            signed_encoding = (get_encoded_form() + ("&sig=%s".printf(get_signature())));
        }
        return signed_encoding;
    }
    
    protected string get_signature() {
        if (signature == null) {
            string encoded_form = get_encoded_form();
            string hashable_form = encoded_form.replace("&", "");         
            string secret = host_session.get_session_secret();

            signature = Checksum.compute_for_string(ChecksumType.MD5, (hashable_form + secret));
        }
        return signature;
    }
    
    protected string get_call_id() {
        if (call_id == null)
            call_id = host_session.get_next_call_id();
        
        return call_id;
    }
    
    protected Session get_host_session() {
        return host_session;
    }

    protected void set_is_executed(bool val) {
        is_executed = val;
    }
    
    protected void set_response(string resp) {
        response = resp;
    }

    public bool get_is_executed() {
        return is_executed;
    }

    public string get_response() {
        assert(is_executed);
        
        return response;
    }
}

public class PhotoUploadRequest : Request {
    private string source_file = null;

    public PhotoUploadRequest(Session host_session, string creator_target_album,
        string creator_source_file) {
        base(host_session, "photos.upload");
        
        add_argument("aid", creator_target_album);

        source_file = creator_source_file;
    }

    public override string execute() {
        assert(!get_is_executed());

        // Photo upload requests are formatted as HTTP 1.1 multipart POST requests.
        // Uploading a single photo requires n parts. Of these n parts, the first
        // (n - 1) of them are plain text-valued parts encoding metadata, and the
        // last n-th part is binary-encoded part containing the actual image
        // bytes.

        // create the multipart request container
        Soup.Multipart message_parts = new Soup.Multipart("multipart/form-data");

        // loop through the array of call arguments and attach each one to the
        // multipart request object as a separate, text-valued metadata part.
        // Together, all the arguments constitute the first (n - 1) parts of
        // the total n parts of the multipart request.
        Request.RESTArgument[] arg_array = get_sorted_arg_array();
        string sig = get_signature();
        arg_array += Request.RESTArgument("sig", sig);
        foreach (Request.RESTArgument arg in arg_array)
            message_parts.append_form_string(arg.key, arg.value);
        
        // iterate through all the (n - 1) text-valued metadata parts attached
        // above and set their "Content-Type" headers to "text/plain". This is
        // necessary to prevent the Facebook REST endpoint from incorrectly
        // interpreting these text-valued parts as binary image data. It's not
        // clear why libsoup doesn't do this automatically.
        int num_parts = message_parts.get_length();
        unowned Soup.MessageHeaders current_header;
        unowned Soup.Buffer current_body;
        for (int i = 0; i < num_parts; i++) {
            message_parts.get_part(i, out current_header, out current_body);
            current_header.append("Content-Type", "text/plain");
        }

        // attempt to read the binary image data from disk
        string photo_data;
        ulong data_length;
        try {
            FileUtils.get_contents(source_file, out photo_data, out data_length);
        } catch (FileError e) {
            error("PhotoUploadRequest: couldn't read date from file '%s'", source_file);
        }

        // bind the binary image data read from disk into a Soup.Buffer object so that we
        // can attach it to the multipart request, then actaully append the buffer
        // to the multipart request. Note that when the buffer is appended, the MIME type
        // must be set simply to "image" (NOT "image/jpeg" or even "image/*") even though
        // this isn't entirely Kosher as per the W3C specs. We engage in this weirdness
        // because the Facebook REST endpoint expects it. The Facebook endpoint doesn't use
        // MIME to determine the type of image being uploaded. Instead, it parses the
        // "filename" field of the "Content-Disposition" header in the image part and determines
        // the type from that (e.g. if the filename field ends in "jpg" then the image is JPEG).
        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.COPY, photo_data, data_length);
        message_parts.append_form_file("", source_file, "image", bindable_data);

        // because the Facebook REST endpoint uses the Content-Disposition header to determine
        // the type of image being uploaded, it is very finicky about which key-value pairs are
        // present in the Content-Disposition header. Notably, libsoup by default includes the
        // "name" control key in the Content-Disposition header (as per W3C specs), but the
        // Facebook endpoint doesn't like this and issues an "Error 324" in this case. To
        // prevent this behavior, we have to inject a new Content-Disposition header
        // that does not contain a "name" key into the multipart request part that
        // packages the image data.
        message_parts.get_part(num_parts, out current_header, out current_body);
        GLib.HashTable<string, string> disposition_table =
            new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
        disposition_table.insert("filename", source_file);
        current_header.set_content_disposition("form-data", disposition_table);

        Soup.Message outbound_message =
            Soup.form_request_new_from_multipart("http://api.facebook.com/restserver.php",
            message_parts);
        
        // set the MIME version on the outbound request. It's not clear why libsoup doesn't
        // do this automatically.
        outbound_message.request_headers.append("MIME-version", "1.0");

        get_host_session().get_connection().send_message(outbound_message);

        set_response(outbound_message.response_body.data);
        set_is_executed(true);

        return get_response();
    }
}

public class AlbumQueryRequest : Request {
    public AlbumQueryRequest(Session host_session) {
        base(host_session, "photos.getAlbums");
    }
}

public class AlbumCreationRequest : Request {
    public AlbumCreationRequest(Session host_session, string album_name) {
        base(host_session, "photos.createAlbum");
        add_argument("name", album_name);
    }
}

public class SessionUserRequest : Request {
    public SessionUserRequest(Session host_session) {
        base(host_session, "users.getInfo");
        add_argument("uids", host_session.get_user_id());
        add_argument("fields", "name");
    }
}
}

#endif
