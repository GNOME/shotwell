/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

namespace FlickrConnector {

private const int ORIGINAL_SIZE = -1;
private const string SERVICE_WELCOME_MESSAGE = 
    _("You are not currently logged in to Flickr.\n\nYou must have already signed up for a Flickr account to complete the login process. During login you will have to specifically authorize Shotwell Connect to link to your Flickr account.");
private const string RESTART_ERROR_MESSAGE = 
    _("You have already logged in and out of Flickr during this Shotwell session.\nTo continue publishing to Flickr, quit and restart Shotwell, then try publishing again.");

public enum UserKind {
    PRO,
    FREE
}

public struct VisibilitySpecification {
    public int friends_level;
    public int family_level;
    public int everyone_level;

    VisibilitySpecification(int creator_friends_lev, int creator_fam_lev,
        int creator_everyone_lev) {
        friends_level = creator_friends_lev;
        family_level = creator_fam_lev;
        everyone_level = creator_everyone_lev;
    }
}

public class FlickrSession : RESTSession {
    private const string ENDPOINT_URL = "http://api.flickr.com/services/rest";
    private const string API_KEY = "60dd96d4a2ad04888b09c9e18d82c26f";
    private const string API_SECRET = "d0960565e03547c1";

    private string username = null;
    private string auth_token = null;

    public FlickrSession() {
        base(ENDPOINT_URL);
    }

    public FlickrSession.with_authentication(string creator_auth_token, string creator_username) {
        base(ENDPOINT_URL);
        auth_token = creator_auth_token;
        username = creator_username;
    }

    public override RESTTransaction create_transaction() {
        FlickrTransaction result = new FlickrTransaction(this);
        result.add_argument("api_key", get_api_key());
        
        return result;
    }

    public string get_api_key() {
        return API_KEY;
    }

    public string get_api_secret() {
        return API_SECRET;
    }

    public bool is_authenticated() {
        return ((username != null) && (auth_token != null));
    }

    public string get_username() {
        assert(is_authenticated());

        return username;
    }

    public string get_auth_token() {
        assert(is_authenticated());

        return auth_token;
    }
}

public class FlickrTransaction : RESTTransaction {
    public const string SIGNATURE_KEY = "api_sig";

    public FlickrTransaction(FlickrSession creator_session) {
        base(creator_session);
    }
    
    protected override void sign() {
        string sig = generate_signature(get_sorted_arguments(),
            ((FlickrSession) get_parent_session()).get_api_secret());

        set_signature_key(SIGNATURE_KEY);
        set_signature_value(sig);
    }

    public static string generate_signature(RESTArgument[] sorted_args, string api_secret) {
        string hash_string = "";
        foreach (RESTArgument arg in sorted_args)
            hash_string = hash_string + ("%s%s".printf(arg.key, arg.value));

        return Checksum.compute_for_string(ChecksumType.MD5, api_secret + hash_string);
    }
}

public class FlickrUploadTransaction : PhotoUploadTransaction {
    private const string UPLOAD_ENDPOINT_URL = "http://api.flickr.com/services/upload";

    private VisibilitySpecification visibility_spec;

    public FlickrUploadTransaction(FlickrSession creator_session, string creator_source_file,
        VisibilitySpecification creator_vis_spec, TransformablePhoto creator_source_photo) {
        base(creator_session, creator_source_file, creator_source_photo);

        visibility_spec = creator_vis_spec;

        add_argument("api_key", creator_session.get_api_key());
        add_argument("auth_token", creator_session.get_auth_token());
        add_argument("is_public", ("%d".printf(creator_vis_spec.everyone_level)));
        add_argument("is_friend", ("%d".printf(creator_vis_spec.friends_level)));
        add_argument("is_family", ("%d".printf(creator_vis_spec.family_level)));

        GLib.HashTable<string, string> disposition_table =
            new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
        disposition_table.insert("filename", creator_source_photo.get_name());
        disposition_table.insert("name", "photo");
        set_binary_disposition_table(disposition_table);

        set_special_endpoint_url(UPLOAD_ENDPOINT_URL);
    }

    protected override void sign() {
        string sig = FlickrTransaction.generate_signature(get_sorted_arguments(),
            ((FlickrSession) get_parent_session()).get_api_secret());

        set_signature_key(FlickrTransaction.SIGNATURE_KEY);
        set_signature_value(sig);
    }
}

public class Interactor : ServiceInteractor {
    private const string TEMP_FILE_PREFIX = "publishing-";
    private const double PREPARATION_PHASE_FRACTION = 0.3;
    private const double UPLOAD_PHASE_FRACTION = 0.7;

    private FlickrSession session = null;
    private string login_frob = null;
    private string login_url = null;
    private LoginShell login_shell = null;
    private bool user_cancelled = false;
    private FlickrUploadActionPane action_pane;

    public Interactor(PublishingDialog host) {
        base(host);
        
        if (is_persistent_session_valid()) {
            Config config = Config.get_instance();
            session = new FlickrSession.with_authentication(config.get_flickr_auth_token(),
                config.get_flickr_username());
        } else {
            session = new FlickrSession();
        }
    }
    
    public override string get_name() {
        return "Flickr";
    }

    public override void start_interaction() throws PublishingError {
        if (is_persistent_session_valid()) {
            UserKind user_kind;
            int free_kb;
            
            get_upload_info(session, out user_kind, out free_kb);

            UploadPane upload_pane = new UploadPane(this, session.get_username(), user_kind,
                free_kb);
            get_host().install_pane(upload_pane);
            get_host().set_cancel_button_mode();
        } else {
            if (LoginShell.get_is_cache_dirty()) {
                get_host().on_error_message(RESTART_ERROR_MESSAGE);
            } else {
                LoginWelcomePane not_logged_in_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
                not_logged_in_pane.login_requested += on_login_requested;
                get_host().install_pane(not_logged_in_pane);
                get_host().set_cancel_button_mode();
            }
        }
    }

    public override void cancel_interaction() {
        if (action_pane != null)
            action_pane.cancel_upload();
    }
    
    private void on_login_requested() {
        try {
            create_login_info(session, out login_frob, out login_url);
        } catch (PublishingError e) {
            get_host().on_error(e);
            return;
        }

        login_shell = new LoginShell(this);

        get_host().set_large_window_mode();
        get_host().install_pane(login_shell);
        get_host().set_cancel_button_mode();

        login_shell.load_login_page();
    }
    
    public string get_login_frob() {
        return login_frob;
    }
    
    public string get_login_url() {
        return login_url;
    }
    
    public FlickrSession get_session() {
        return session;
    }
    
    public void notify_login_completed(string auth_token, string username) {
        Config config = Config.get_instance();
        config.set_flickr_auth_token(auth_token);
        config.set_flickr_username(username);

        get_host().set_standard_window_mode();

        session = new FlickrSession.with_authentication(auth_token, username);

        UserKind user_kind;
        int free_kb;
        try {
            get_upload_info(session, out user_kind, out free_kb);
        } catch (PublishingError e) {
            get_host().on_error(e);
            return;
        }

        get_host().install_pane(new UploadPane(this, session.get_username(), user_kind, free_kb));
        get_host().set_cancel_button_mode();
    }

    public void notify_logout() {
        invalidate_persistent_session();

        if (LoginShell.get_is_cache_dirty()) {
            get_host().on_error_message(RESTART_ERROR_MESSAGE);
        } else {
                LoginWelcomePane not_logged_in_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
                not_logged_in_pane.login_requested += on_login_requested;
                get_host().install_pane(not_logged_in_pane);
                get_host().set_cancel_button_mode();
        }
    }

    public void notify_error(PublishingError e) {
        get_host().on_error(e);
    }

    public void notify_publish(int major_axis_size, VisibilitySpecification vis_spec) {
        get_host().lock_service();

        action_pane = new FlickrUploadActionPane(get_host(), session, vis_spec, major_axis_size);
        get_host().install_pane(action_pane);
        get_host().set_cancel_button_mode();

        try {
            action_pane.upload();
        } catch (PublishingError err) {
            get_host().on_error(err);
            
            return;
        }

        if (user_cancelled)
            return;
        
        get_host().unlock_service();
        get_host().on_success();

        action_pane = null;
    }
}

class FlickrUploadActionPane : UploadActionPane {
    private VisibilitySpecification vis_spec;
    private int major_axis_size;
    private FlickrSession session;
    
    public FlickrUploadActionPane(PublishingDialog host, FlickrSession session,
        VisibilitySpecification vis_spec, int major_axis_size) {
        base(host);

        this.vis_spec = vis_spec;
        this.major_axis_size = major_axis_size;
        this.session = session;
    }

    protected override void prepare_file(UploadActionPane.TemporaryFileDescriptor file) {
        try {
            if (major_axis_size == ORIGINAL_SIZE) {
                file.source_photo.export(file.temp_file, major_axis_size, ScaleConstraint.ORIGINAL,
                    Jpeg.Quality.MAXIMUM);
            } else {
                file.source_photo.export(file.temp_file, major_axis_size,
                    ScaleConstraint.DIMENSIONS, Jpeg.Quality.MAXIMUM);
            }
        } catch (Error e) {
            error("FlickrUploadPane: can't create temporary files");
        }
    }

    protected override void upload_file(UploadActionPane.TemporaryFileDescriptor file) 
        throws PublishingError {
        FlickrUploadTransaction upload_req = new FlickrUploadTransaction(session,
            file.temp_file.get_path(), vis_spec, file.source_photo);
        upload_req.chunk_transmitted += on_chunk_transmitted;
        upload_req.execute();
        upload_req.chunk_transmitted -= on_chunk_transmitted;
    }
}

class UploadPane : PublishingDialogPane {
    private struct SizeEntry {
        string title;
        int size;

        SizeEntry(string creator_title, int creator_size) {
            title = creator_title;
            size = creator_size;
        }
    }

    private struct VisibilityEntry {
        VisibilitySpecification specification;
        string title;

        VisibilityEntry(string creator_title, VisibilitySpecification creator_specification) {
            specification = creator_specification;
            title = creator_title;
        }
    }

    private Gtk.Button logout_button = null;
    private Gtk.Button publish_button = null;
    private Gtk.ComboBox visibility_combo = null;
    private Gtk.ComboBox size_combo = null;
    private VisibilityEntry[] visibilities = null;
    private SizeEntry[] sizes = null;
    private Interactor parent_interactor = null;

    public UploadPane(Interactor creator_parent_interactor, string username, UserKind user_kind,
        int remaining_kb) {
        visibilities = create_visibilities();
        sizes = create_sizes();
        parent_interactor = creator_parent_interactor;

        string upload_label_text = _("You are logged into Flickr as %s.\n\n").printf(username);
        if (user_kind == UserKind.FREE) {
            int remaining_mb = remaining_kb / 1024;
            upload_label_text += _("Your free Flickr account limits how much data you can " +
                "upload per month.\nThis month, you have %d megabytes remaining in your upload " +
                "quota.").printf(remaining_mb);
        } else {
            upload_label_text += _("Your Flickr Pro account entitles you to unlimited uploads.");
        }

        Gtk.SeparatorToolItem top_space = new Gtk.SeparatorToolItem();
        top_space.set_draw(false);
        Gtk.SeparatorToolItem bottom_space = new Gtk.SeparatorToolItem();
        bottom_space.set_draw(false);
        add(top_space);
        top_space.set_size_request(-1, 32);

        Gtk.Label upload_info_label = new Gtk.Label(upload_label_text);
        add(upload_info_label);

        Gtk.SeparatorToolItem upload_combos_spacer = new Gtk.SeparatorToolItem();
        upload_combos_spacer.set_draw(false);
        add(upload_combos_spacer);
        upload_combos_spacer.set_size_request(-1, 32);

        Gtk.HBox combos_layouter_padder = new Gtk.HBox(false, 8);
        Gtk.SeparatorToolItem combos_left_padding = new Gtk.SeparatorToolItem();
        combos_left_padding.set_draw(false);
        Gtk.SeparatorToolItem combos_right_padding = new Gtk.SeparatorToolItem();
        combos_right_padding.set_draw(false);
        Gtk.Table combos_layouter = new Gtk.Table(2, 2, false);
        combos_layouter.set_row_spacing(0, 12);
        Gtk.Label visibility_label = new Gtk.Label.with_mnemonic(_("Photos _visible to:"));
        Gtk.Label size_label = new Gtk.Label.with_mnemonic(_("Photo _size:"));
        visibility_combo = create_visibility_combo();
        visibility_combo.changed += on_visibility_changed;
        visibility_label.set_mnemonic_widget(visibility_combo);
        size_combo = create_size_combo();
        size_label.set_mnemonic_widget(size_combo);
        size_combo.changed += on_size_changed;
        Gtk.Alignment vis_label_aligner = new Gtk.Alignment(0.0f, 0.5f, 0, 0);
        vis_label_aligner.add(visibility_label);
        Gtk.Alignment size_label_aligner = new Gtk.Alignment(0.0f, 0.5f, 0, 0);
        size_label_aligner.add(size_label);
        combos_layouter.attach_defaults(vis_label_aligner, 0, 1, 0, 1);
        combos_layouter.attach_defaults(visibility_combo, 1, 2, 0, 1);
        combos_layouter.attach_defaults(size_label_aligner, 0, 1, 1, 2);
        combos_layouter.attach_defaults(size_combo, 1, 2, 1, 2);
        combos_layouter_padder.add(combos_left_padding);
        combos_layouter_padder.add(combos_layouter);
        combos_layouter_padder.add(combos_right_padding);
        add(combos_layouter_padder);

        Gtk.SeparatorToolItem combos_buttons_spacer = new Gtk.SeparatorToolItem();
        combos_buttons_spacer.set_draw(false);
        add(combos_buttons_spacer);
        combos_buttons_spacer.set_size_request(-1, 32);

        logout_button = new Gtk.Button.with_mnemonic(_("_Logout"));
        logout_button.clicked += on_logout_clicked;
        publish_button = new Gtk.Button.with_mnemonic(_("_Publish"));
        publish_button.clicked += on_publish_clicked;
        Gtk.HBox button_layouter = new Gtk.HBox(false, 8);
        Gtk.SeparatorToolItem buttons_left_padding = new Gtk.SeparatorToolItem();
        buttons_left_padding.set_draw(false);
        Gtk.SeparatorToolItem buttons_right_padding = new Gtk.SeparatorToolItem();
        buttons_right_padding.set_draw(false);
        Gtk.SeparatorToolItem buttons_interspacing = new Gtk.SeparatorToolItem();
        buttons_interspacing.set_draw(false);
        button_layouter.add(buttons_left_padding);
        button_layouter.add(logout_button);
        button_layouter.add(buttons_interspacing);
        button_layouter.add(publish_button);
        button_layouter.add(buttons_right_padding);
        add(button_layouter);

        add(bottom_space);
        bottom_space.set_size_request(-1, 32);
    }

    private void on_logout_clicked() {
        parent_interactor.notify_logout();
    }

    private void on_publish_clicked() {
        VisibilitySpecification visibility_spec =
            visibilities[visibility_combo.get_active()].specification;
        int major_axis_size = sizes[size_combo.get_active()].size;

        parent_interactor.notify_publish(major_axis_size, visibility_spec);
    }

    private VisibilityEntry[] create_visibilities() {
        VisibilityEntry[] result = new VisibilityEntry[0];

        result += VisibilityEntry(_("Everyone"), VisibilitySpecification(1, 1, 1));
        result += VisibilityEntry(_("Friends & family only"), VisibilitySpecification(1, 1, 0));
        result += VisibilityEntry(_("Just me"), VisibilitySpecification(0, 0, 0));

        return result;
    }

    private Gtk.ComboBox create_visibility_combo() {
        Gtk.ComboBox result = new Gtk.ComboBox.text();

        if (visibilities == null)
            visibilities = create_visibilities();

        foreach (VisibilityEntry v in visibilities)
            result.append_text(v.title);

        Config config = Config.get_instance();
        result.set_active(config.get_flickr_visibility());

        return result;
    }

    private SizeEntry[] create_sizes() {
        SizeEntry[] result = new SizeEntry[0];

        result += SizeEntry(_("Medium (500 x 375 pixels)"), 500);
        result += SizeEntry(_("Large (1024 x 768 pixels)"), 1024);
        result += SizeEntry(_("Original size"), ORIGINAL_SIZE);

        return result;
    }

    private Gtk.ComboBox create_size_combo() {
        Gtk.ComboBox result = new Gtk.ComboBox.text();

        if (sizes == null)
            sizes = create_sizes();

        foreach (SizeEntry e in sizes)
            result.append_text(e.title);

        Config config = Config.get_instance();
        result.set_active(config.get_flickr_default_size());

        return result;
    }

    private void on_size_changed() {
        Config config = Config.get_instance();
        config.set_flickr_default_size(size_combo.get_active());
    }

    private void on_visibility_changed() {
        Config config = Config.get_instance();
        config.set_flickr_visibility(visibility_combo.get_active());
    }
}

private string? check_for_error_response(RESTXmlDocument doc) {
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
    } catch (PublishingError err) {
        return "No error code specified";
    }
    
    return "%s (error code %s)".printf(errcode->get_prop("msg"), errcode->get_prop("code"));
}

public void create_login_info(FlickrSession session, out string out_frob,
    out string out_login_url) throws PublishingError {
    RESTTransaction frob_transaction = session.create_transaction();
    frob_transaction.add_argument("method", "flickr.auth.getFrob");
   
    frob_transaction.execute();
    
    RESTXmlDocument response_doc = RESTXmlDocument.parse_string(frob_transaction.get_response(),
        check_for_error_response);

    Xml.Node* response_doc_root = response_doc.get_root_node();

    Xml.Node* frob_node = response_doc.get_named_child(response_doc_root, "frob");
    
    string frob = frob_node->get_content();

    if (frob == null)
        throw new PublishingError.MALFORMED_RESPONSE("No frob returned in request");
        
    string hash_string = session.get_api_secret() + "api_key%s".printf(session.get_api_key()) +
        "frob%s".printf(frob) + "permswrite";
    string sig = Checksum.compute_for_string(ChecksumType.MD5, hash_string);
    string login_url =
        "http://flickr.com/services/auth/?api_key=%s&perms=%s&frob=%s&api_sig=%s".printf(
        session.get_api_key(), "write", frob, sig);

    out_frob = frob;
    out_login_url = login_url;
}

public bool get_auth_info(FlickrSession session, string frob, out string? token, out string? username)
    throws PublishingError {
    RESTTransaction auth_transaction = session.create_transaction();
    auth_transaction.add_argument("method", "flickr.auth.getToken");
    auth_transaction.add_argument("frob", frob);

    auth_transaction.execute();

    RESTXmlDocument response_doc = null;
    try {
        response_doc = RESTXmlDocument.parse_string(auth_transaction.get_response(),
            check_for_error_response);
    } catch (PublishingError err) {
        // if this is a service error, return false, as that's what's being asked of this
        // function
        if (err is PublishingError.SERVICE_ERROR)
            return false;
        
        throw err;
    }
   
    Xml.Node* response_doc_root = response_doc.get_root_node();

    // search through the top-level child nodes looking for a node named '<auth>':
    // all authentication information is packaged within this node
    Xml.Node* auth_node = response_doc.get_named_child(response_doc_root, "auth");

    // search through the children of the '<auth>' node looking for the '<token>' and '<user>'
    // nodes
    Xml.Node* token_node = response_doc.get_named_child(auth_node, "token");
    Xml.Node* user_node = response_doc.get_named_child(auth_node, "user");

    token = token_node->children->content;
    username = response_doc.get_property_value(user_node, "username");
    return true;
}

public void get_upload_info(FlickrSession session, out UserKind user_kind, out int quota_kb_left)
    throws PublishingError {
    assert(session.is_authenticated());

    RESTTransaction info_transaction = session.create_transaction();
    info_transaction.add_argument("method", "flickr.people.getUploadStatus");
    info_transaction.add_argument("auth_token", session.get_auth_token());
    
    info_transaction.execute();

    RESTXmlDocument response_doc =
        RESTXmlDocument.parse_string(info_transaction.get_response(), check_for_error_response);
    Xml.Node* root_node = response_doc.get_root_node();

    Xml.Node* user_node = response_doc.get_named_child(root_node, "user");

    string is_pro_str = response_doc.get_property_value(user_node, "ispro");

    Xml.Node* bandwidth_node = response_doc.get_named_child(user_node, "bandwidth");

    string remaining_kb_str = response_doc.get_property_value(bandwidth_node, "remainingkb");

    if (is_pro_str == "0")
        user_kind = UserKind.FREE;
    else if (is_pro_str == "1")
        user_kind = UserKind.PRO;
    else
        throw new PublishingError.MALFORMED_RESPONSE("Unable to determine if user has free or pro account");
    
    quota_kb_left = remaining_kb_str.to_int();
}

public class LoginShell : PublishingDialogPane {
    private WebKit.WebView webview = null;
    private Gtk.ScrolledWindow webview_frame = null;
    private Interactor parent_interactor = null;
    private Gtk.Layout white_pane = null;
    private static bool is_cache_dirty = false;

    public signal void login_success(FlickrSession host_session);
    public signal void login_failure();
    public signal void login_error();

    public LoginShell(Interactor creator_parent_interactor) {
        parent_interactor = creator_parent_interactor;

        Gdk.Color white_color;
        Gdk.Color.parse("white", out white_color);
        Gtk.Adjustment layout_pane_adjustment = new Gtk.Adjustment(0.5, 0.0, 1.0, 0.01, 0.1, 0.1);
        white_pane = new Gtk.Layout(layout_pane_adjustment, layout_pane_adjustment);
        white_pane.modify_bg(Gtk.StateType.NORMAL, white_color);
        add(white_pane);

        webview_frame = new Gtk.ScrolledWindow(null, null);
        webview_frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN);
        webview_frame.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        webview = new WebKit.WebView();
        webview.load_finished += on_page_load;
        webview.load_started += on_load_started;

        webview_frame.add(webview);
        white_pane.add(webview_frame);
        webview.set_size_request(853, 587);
    }
    
    public void load_login_page() {
        webview.open(parent_interactor.get_login_url());
    }
    
    private void on_page_load(WebKit.WebFrame origin_frame) {
        white_pane.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.ARROW));
        string token;
        string username;
        bool got_auth_info = false;
        try {
            got_auth_info = get_auth_info(parent_interactor.get_session(),
                parent_interactor.get_login_frob(), out token, out username);
        } catch (PublishingError e) {
            parent_interactor.notify_error(e);
            
            return;
        }
        
        if (got_auth_info) {
            is_cache_dirty = true;
            parent_interactor.notify_login_completed(token, username);
        } else {
            webview_frame.show();
        }
    }
    
    private void on_load_started(WebKit.WebFrame frame) {
        webview_frame.hide();
        white_pane.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
    }

    public static bool get_is_cache_dirty() {
        return is_cache_dirty;
    }
}

void invalidate_persistent_session() {
    Config config = Config.get_instance();
    
    config.clear_flickr_auth_token();
    config.clear_flickr_username();
}

bool is_persistent_session_valid() {
    Config config = Config.get_instance();

    string auth_token = config.get_flickr_auth_token();
    string username = config.get_flickr_username();
    
    return ((auth_token != null) && (username != null));
}
}

#endif

