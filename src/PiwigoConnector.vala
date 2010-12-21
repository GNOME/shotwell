/* Copyright 2010 Guillaume Viguier-Just <guillaume@viguierjust.com>
 * 
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace PiwigoConnector {
private const string SERVICE_NAME = "Piwigo";
private const string DEFAULT_CATEGORY_NAME = _("Shotwell Connect");
private const string CONFIG_NAME = "piwigo";
    
private struct Category {
    int id;
    string name;

    Category(int id, string name) {
        this.id = id;
        this.name = name;
    }
}
  
private class PublishingParameters {
    private string category_name;
    private int category_id = 0;
    private int level = 0;

    private PublishingParameters() {
    }

    public PublishingParameters.to_new_category(string category_name, int level) {
        this.category_name = category_name;
        this.level = level;
    }

    public PublishingParameters.to_existing_category(int category_id, int level) {
        this.category_id = category_id;
        this.level = level;
    }

    public bool is_to_new_category() {
        return (category_name != null);
    }

    public string get_category_name() {
        assert(is_to_new_category());
        return category_name;
    }

    public int get_category_id() {
        assert(!is_to_new_category());
        return category_id;
    }

    public int get_perm_level() {
        return level;
    }

    // converts a publish-to-new-category parameters object into a publish-to-existing-category
    // parameters object
    public void convert(int category_id) {
        assert(is_to_new_category());
        category_name = null;
        this.category_id = category_id;
    }

}
    
public class Capabilities : ServiceCapabilities {
    public override string get_name() {
        return SERVICE_NAME;
    }

    public override ServiceCapabilities.MediaType get_supported_media() {
        return MediaType.PHOTO;
    }

    public override ServiceInteractor factory(PublishingDialog host) {
        return new Interactor(host);
    }
}
  
public class Interactor : ServiceInteractor {
    private Session session = null;
    private bool cancelled = false;
    private const string PIWIGO_WS = "ws.php";
    private Category[] categories = null;
    private PublishingParameters parameters = null;
    private Uploader uploader = null;
    private ProgressPane progress_pane = null;
    
    public Interactor(PublishingDialog host) {
        base(host);
        session = new Session();
    }
    
    // EVENT: triggered when the user clicks "Login" in the credentials capture pane
    private void on_credentials_login(string url, string username, string password) {
        if (has_error() || cancelled)
            return;

        do_network_login(url, username, password);
    }
    
    // EVENT: triggered when an error occurs in the login transaction
    private void on_login_network_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_login_network_complete);
        bad_txn.network_error.disconnect(on_login_network_error);

        if (has_error() || cancelled)
            return;
        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;

        do_show_credentials_capture_pane(CredentialsCapturePane.Mode.FAILED_RETRY_URL);
    }
    
    // Helper method: retrieves session ID from RESTTransaction received
    private new string? get_pwg_id_from_transaction(RESTTransaction txn) {
        string cookie = txn.get_message().response_headers.get("Set-Cookie");
        if (cookie != "") {
            string tmp = cookie.rstr("pwg_id=");
            string[] values = tmp.split(";");
            string pwg_id = values[0];
            return pwg_id;
        } else {
            return "";
        }
    }
    
    // EVENT: triggered when network login is complete
    private void on_login_network_complete(RESTTransaction txn) {
        txn.completed.disconnect(on_login_network_complete);
        txn.network_error.disconnect(on_login_network_error);
        
        if (has_error() || cancelled)
            return;

        try {
            RESTXmlDocument.parse_string(txn.get_response(), Transaction.check_response);
        } catch (PublishingError err) {
            // Get error code first
            try {
                RESTXmlDocument.parse_string(txn.get_response(), Transaction.get_err_code);
            } catch (PublishingError code) {
                int code_int = code.message.to_int();
                if (code_int == 999) {
                    do_show_credentials_capture_pane(CredentialsCapturePane.Mode.FAILED_RETRY_USER);
                } else {
                    post_error(err);
                }
            }
            return;
        }

        // Get session ID
        string endpoint_url = txn.get_endpoint_url(); 
        string pwg_id = get_pwg_id_from_transaction(txn);
        session = new Session();
        session.set_pwg_id(pwg_id);

        // Fetch session status with username
        do_fetch_session_status(endpoint_url, pwg_id);
    }
    
    // EVENT: Generic network error
    private void on_network_error(RESTTransaction bad_txn, PublishingError err) {

        if (has_error() || cancelled)
            return;

        post_error(err);
    }
    
    // EVENT: session get status error
    private void on_session_get_status_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_session_get_status_complete);
        bad_txn.network_error.disconnect(on_session_get_status_error);
        on_network_error(bad_txn, err);
    }
    
    // EVENT: done fetching session status
    private void on_session_get_status_complete(RESTTransaction txn) {
        txn.completed.disconnect(on_session_get_status_complete);
        txn.network_error.disconnect(on_session_get_status_error);
        if (has_error() || cancelled)
            return;
        if (!session.is_authenticated()) {
            string endpoint_url = txn.get_endpoint_url();
            string pwg_id = session.get_pwg_id();
            // Parse the response
            try {
                RESTXmlDocument doc = RESTXmlDocument.parse_string(txn.get_response(), Transaction.check_response);
                Xml.Node* root = doc.get_root_node();
                Xml.Node* username_node;
                try {
                    username_node = doc.get_named_child(root, "username");
                    string username = username_node->get_content();
                    session.authenticate(endpoint_url, username, pwg_id);
                    do_fetch_categories();
                } catch (PublishingError err2) {
                    post_error(err2);
                    return;
                }
            } catch (PublishingError err) {
                post_error(err);
                return;
            }
        }
    }
    
    // EVENT: fetch categories error
    private void on_category_fetch_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_category_fetch_complete);
        bad_txn.network_error.disconnect(on_category_fetch_error);
        on_network_error(bad_txn, err);
    }
    
    // EVENT: fetch categories complete
    private void on_category_fetch_complete(RESTTransaction txn) {
        txn.completed.disconnect(on_category_fetch_complete);
        txn.network_error.disconnect(on_category_fetch_error);
        debug("PiwigoConnector: list of categories: %s", txn.get_response());
        if (has_error() || cancelled)
            return;
        // Empty the categories
        if (categories != null) {
            categories = null;
        }
        // Parse the response
        try {
            RESTXmlDocument doc = RESTXmlDocument.parse_string(txn.get_response(), Transaction.check_response);
            Xml.Node* root = doc.get_root_node();
            Xml.Node* categories_node = root->first_element_child();
            Xml.Node* category_node_iter = categories_node->children;
            Xml.Node* name_node;
            string name = "";
            string id_string = "";
            for ( ; category_node_iter != null; category_node_iter = category_node_iter->next) {
                name_node = doc.get_named_child(category_node_iter, "name");
                name = name_node->get_content();
                id_string = category_node_iter->get_prop("id");
                if (categories == null) {
                    categories = new Category[0];
                }
                categories += Category(id_string.to_int(), name);
            }
        } catch (PublishingError err) {
            post_error(err);
            return;
        }

        do_show_publishing_options_pane();
    }
    
    // EVENT: triggered when the user clicks "Logout" in the publishing options pane
    private void on_publishing_options_logout() {
        if (has_error() || cancelled)
            return;

        // Send logout transaction
        SessionLogoutTransaction logout_trans = new SessionLogoutTransaction(session);
        logout_trans.network_error.connect(on_logout_network_error);
        logout_trans.completed.connect(on_logout_network_complete);

        try {
            logout_trans.execute();
        } catch (PublishingError err) {
            post_error(err);
        }
    }
    
    // EVENT : triggered on logout network error
    private void on_logout_network_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_logout_network_complete);
        bad_txn.network_error.disconnect(on_logout_network_error);
        on_network_error(bad_txn, err);
    }
    
    // EVENT : triggered on logout network complete
    private void on_logout_network_complete(RESTTransaction txn) {
        txn.completed.disconnect(on_logout_network_complete);
        txn.network_error.disconnect(on_logout_network_error);
        if (has_error() || cancelled)
            return;

        txn.completed.disconnect(on_logout_network_complete);
        txn.network_error.disconnect(on_logout_network_error);

        session.deauthenticate();

        do_show_credentials_capture_pane(CredentialsCapturePane.Mode.INTRO);
    }
    
    // EVENT: triggered when the user clicks "Publish" in the publishing options pane
    private void on_publishing_options_publish(PublishingParameters parameters) {
        if (has_error() || cancelled)
            return;

        this.parameters = parameters;

        if (parameters.is_to_new_category()) {
            do_create_category(parameters);
        } else {
            do_upload();
        }
    }
    
    // EVENT: categories add error
    private void on_categories_add_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_categories_add_complete);
        bad_txn.network_error.disconnect(on_categories_add_error);
        on_network_error(bad_txn, err);
    }
    
    // EVENT: triggered when the network transaction that creates a new category is completed
    //        successfully. This event should occur only when the user is publishing to a
    //        new category.
    private void on_categories_add_complete(RESTTransaction txn) {
        txn.completed.disconnect(on_categories_add_complete);
        txn.network_error.disconnect(on_categories_add_error);

        if (has_error() || cancelled)
            return;

        // Parse the response
        try {
            RESTXmlDocument doc = RESTXmlDocument.parse_string(txn.get_response(), Transaction.check_response);
            Xml.Node* rsp = doc.get_root_node();
            Xml.Node* id_node;
            id_node = doc.get_named_child(rsp, "id");
            string id_string = id_node->get_content();
            int id = id_string.to_int();
            parameters.convert(id);
            do_upload();
        } catch (PublishingError err) {
            post_error(err);
            return;
        }
    }
    
    // EVENT: triggered when the batch uploader reports that at least one of the network
    //        transactions encapsulating uploads has completed successfully
    private void on_upload_complete(BatchUploader uploader, int num_published) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);
        uploader.status_updated.disconnect(progress_pane.set_status);
        
        // TODO: add a descriptive, translatable error message string here
        if (num_published == 0)
            post_error(new PublishingError.LOCAL_FILE_ERROR(""));

        if (has_error() || cancelled)
            return;

        do_show_success_pane();
    }
    
    // EVENT: triggered when the batch uploader reports that at least one of the network
    //        transactions encapsulating uploads has caused a network error
    private void on_upload_error(BatchUploader uploader, PublishingError err) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);
        uploader.status_updated.disconnect(progress_pane.set_status);

        if (has_error() || cancelled)
            return;

        post_error(err);
    }
    
    // ACTION: display the credentials capture pane in the publishing dialog; the credentials
    //         capture pane can be displayed in different "modes" that display different
    //         messages to the user
    private void do_show_credentials_capture_pane(CredentialsCapturePane.Mode mode) {
        CredentialsCapturePane creds_pane = new CredentialsCapturePane(this, mode);
        creds_pane.login.connect(on_credentials_login);

        get_host().unlock_service();
        get_host().set_cancel_button_mode();

        get_host().install_pane(creds_pane);
    }
    
    // ACTION: given a username and password, run a REST transaction over the network to
    //         log a user into the Picasa Web Albums service
    private void do_network_login(string url, string username, string password) {
        debug("Piwigo.Interactor: logging in");
        get_host().install_pane(new LoginWaitPane());

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        string my_url = url;

        if(!my_url.has_suffix(".php")) {
            if(!my_url.has_suffix("/")) {
                my_url = my_url + "/";
            }
            my_url = my_url + PIWIGO_WS;
        }

        if(!my_url.has_prefix("http://") && !my_url.has_prefix("https://")) {
            my_url = "http://" + my_url;
        }

        SessionLoginTransaction login_trans = new SessionLoginTransaction(session, my_url, username, password);
        login_trans.network_error.connect(on_login_network_error);
        login_trans.completed.connect(on_login_network_complete);

        try {
            login_trans.execute();
        } catch (PublishingError err) {
            post_error(err);
        }
    }
    
    // ACTION: fetches session status
    private void do_fetch_session_status(string url = "", string pwg_id = "") {
        debug("Piwigo.Interactor: fetching session status");
        if (!session.is_authenticated()) {
            SessionGetStatusTransaction status_txn = new SessionGetStatusTransaction.unauthenticated(session, url, pwg_id);
            status_txn.network_error.connect(on_session_get_status_error);
            status_txn.completed.connect(on_session_get_status_complete);

            try {
                status_txn.execute();
            } catch (PublishingError err) {
                post_error(err);
            }
        } else {
            SessionGetStatusTransaction status_txn = new SessionGetStatusTransaction(session);
            status_txn.network_error.connect(on_session_get_status_error);
            status_txn.completed.connect(on_session_get_status_complete);

            try {
                status_txn.execute();
            } catch (PublishingError err) {
                post_error(err);
            }
        }
    }
    
    // ACTION: fetches the categories
    private void do_fetch_categories() {
        debug("Piwigo.Interactor: fetching categories");
        get_host().install_pane(new AccountFetchWaitPane());

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        CategoriesGetListTransaction cat_trans = new CategoriesGetListTransaction(session);
        cat_trans.network_error.connect(on_category_fetch_error);
        cat_trans.completed.connect(on_category_fetch_complete);
        
        try {
            cat_trans.execute();
        } catch (PublishingError err) {
            post_error(err);
        }
    }
    
    // ACTION: display the publishing options pane in the publishing dialog
    private void do_show_publishing_options_pane() {
        PublishingOptionsPane opts_pane = new PublishingOptionsPane(this, categories);
        opts_pane.publish.connect(on_publishing_options_publish);
        opts_pane.logout.connect(on_publishing_options_logout);
        get_host().install_pane(opts_pane);

        get_host().unlock_service();
        get_host().set_cancel_button_mode();
    }
    
    // ACTION: run a REST transaction over the network to create a new category with the parameters
    //         specified in 'parameters'. Display a wait pane with an info message in the
    //         publishing dialog while the transaction is running. This action should only
    //         occur if 'parameters' describes a publish-to-new-category operation.
    private void do_create_category(PublishingParameters parameters) {
        assert(parameters.is_to_new_category());

        get_host().install_pane(new StaticMessagePane(_("Creating category...")));

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        CategoriesAddTransaction creation_trans = new CategoriesAddTransaction(session, parameters.get_category_name());
        creation_trans.network_error.connect(on_categories_add_error);
        creation_trans.completed.connect(on_categories_add_complete);
        
        try {
            creation_trans.execute();
        } catch (PublishingError err) {
            post_error(err);
        }
    }
    
    // ACTION: run a REST transaction over the network to upload the user's photos to the remote
    //         endpoint. Display a progress pane while the transaction is running.
    private void do_upload() {
        progress_pane = new ProgressPane();
        get_host().install_pane(progress_pane);

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        MediaSource[] photos = get_host().get_media();
        uploader = new Uploader(session, parameters, photos);

        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);
        uploader.status_updated.connect(progress_pane.set_status);

        uploader.upload();
    }
    
    // ACTION: display the success pane in the publishing dialog
    private void do_show_success_pane() {
        get_host().unlock_service();
        get_host().set_close_button_mode();

        get_host().install_pane(new SuccessPane(MediaType.PHOTO));
    }
    
    internal new PublishingDialog get_host() {
        return base.get_host();
    }
    
    public override string get_name() {
        return SERVICE_NAME;
    }
    
    internal Session get_session() {
        return session;
    }

    public override void start_interaction() {
        get_host().set_standard_window_mode();

        if (!session.is_authenticated()) {
            do_show_credentials_capture_pane(CredentialsCapturePane.Mode.INTRO);
        } else {
            do_fetch_categories();
        }
    }

    public override void cancel_interaction() {
        cancelled = true;
        session.stop_transactions();
    }
}
  
private class Uploader : BatchUploader {
    private PublishingParameters parameters;
    private Session session;

    public Uploader(Session session, PublishingParameters parameters, MediaSource[] photos) {
        base.with_media(photos);

        this.parameters = parameters;
        this.session = session;
    }

    protected override bool prepare_file(BatchUploader.TemporaryFileDescriptor file) {
        Scaling scaling = Scaling.for_original();

        try {
            ((Photo) file.media).export(file.temp_file, scaling, Jpeg.Quality.MAXIMUM, PhotoFileFormat.JFIF);
        } catch (Error e) {
            return false;
        }

        return true;
    }

    protected override RESTTransaction create_transaction_for_file(BatchUploader.TemporaryFileDescriptor file) 
        throws PublishingError {
        return new ImagesAddTransaction(session, parameters, file.temp_file.get_path(), file.media);
    }
}
  
private class CredentialsCapturePane : PublishingDialogPane {
    public enum Mode {
        INTRO,
        FAILED_RETRY_URL,
        FAILED_RETRY_USER
    }
    private const string INTRO_MESSAGE = _("Enter the username and password associated with your Piwigo account, and the URL of your Piwigo installation.");
    private const string FAILED_RETRY_URL_MESSAGE = _("No Piwigo installation was found at this URL. Please verify the URL you entered");
    private const string FAILED_RETRY_USER_MESSAGE = _("Username and/or password invalid. Please try again");

    private const int UNIFORM_ACTION_BUTTON_WIDTH = 102;

    private Gtk.Entry url_entry;
    private Gtk.Entry user_entry;
    private Gtk.Entry password_entry;
    private Gtk.Button login_button;
    private weak Interactor interactor;

    public signal void login(string url, string user, string password);

    public CredentialsCapturePane(Interactor interactor, Mode mode = Mode.INTRO) {
        this.interactor = interactor;

        Gtk.SeparatorToolItem top_space = new Gtk.SeparatorToolItem();
        top_space.set_draw(false);
        Gtk.SeparatorToolItem bottom_space = new Gtk.SeparatorToolItem();
        bottom_space.set_draw(false);
        add(top_space);
        top_space.set_size_request(-1, 40);

        Gtk.Label intro_message_label = new Gtk.Label("");
        intro_message_label.set_line_wrap(true);
        add(intro_message_label);
        intro_message_label.set_size_request(PublishingDialog.STANDARD_CONTENT_LABEL_WIDTH, -1);
        intro_message_label.set_alignment(0.5f, 0.0f);
        switch (mode) {
            case Mode.INTRO:
                intro_message_label.set_text(INTRO_MESSAGE);
                break;

            case Mode.FAILED_RETRY_URL:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                    "Invalid URL"), FAILED_RETRY_URL_MESSAGE));
                break;

            case Mode.FAILED_RETRY_USER:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                    "Unrecognized User"), FAILED_RETRY_USER_MESSAGE));
                break;
        }

        Gtk.Alignment entry_widgets_table_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        Gtk.Table entry_widgets_table = new Gtk.Table(4,2, false);
        Gtk.Label url_entry_label = new Gtk.Label.with_mnemonic(_("_URL of your Piwigo installation:"));
        url_entry_label.set_alignment(0.0f, 0.5f);
        Gtk.Label user_entry_label = new Gtk.Label.with_mnemonic(_("_Username:"));
        user_entry_label.set_alignment(0.0f, 0.5f);
        Gtk.Label password_entry_label = new Gtk.Label.with_mnemonic(_("_Password:"));
        password_entry_label.set_alignment(0.0f, 0.5f);
        url_entry = new Gtk.Entry();
        user_entry = new Gtk.Entry();
        user_entry.changed.connect(on_user_changed);
        password_entry = new Gtk.Entry();
        password_entry.set_visibility(false);
        entry_widgets_table.attach(url_entry_label, 0, 1, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(user_entry_label, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(password_entry_label, 0, 1, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(url_entry, 1, 2, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(user_entry, 1, 2, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(password_entry, 1, 2, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        login_button = new Gtk.Button.with_mnemonic(_("_Login"));
        login_button.clicked.connect(on_login_button_clicked);
        login_button.set_sensitive(false);
        Gtk.Alignment login_button_aligner = new Gtk.Alignment(1.0f, 0.5f, 0.0f, 0.0f);
        login_button_aligner.add(login_button);
        login_button.set_size_request(UNIFORM_ACTION_BUTTON_WIDTH, -1);
        entry_widgets_table.attach(login_button_aligner, 1, 2, 3, 4,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 40);
        entry_widgets_table_aligner.add(entry_widgets_table);
        add(entry_widgets_table_aligner);

        url_entry_label.set_mnemonic_widget(url_entry);
        user_entry_label.set_mnemonic_widget(user_entry);
        password_entry_label.set_mnemonic_widget(password_entry);

        add(bottom_space);
        bottom_space.set_size_request(-1, 40);
    }

    private void on_login_button_clicked() {
        login(url_entry.get_text(), user_entry.get_text(), password_entry.get_text());
    }

    private void on_user_changed() {
        login_button.set_sensitive(user_entry.get_text() != "");
    }

    public override void installed() {
        url_entry.grab_focus();
        password_entry.set_activates_default(true);
        login_button.can_default = true;
        interactor.get_host().set_default(login_button);
    }
}
  
private class PublishingOptionsPane : PublishingDialogPane {
    private struct PermsDescription {
        string name;
        int level;

        PermsDescription(string name, int level) {
            this.name = name;
            this.level = level;
        }
    }

    private const int PACKER_VERTICAL_PADDING = 16;
    private const int PACKER_HORIZ_PADDING = 128;
    private const int INTERSTITIAL_VERTICAL_SPACING = 20;
    private const int ACTION_BUTTON_SPACING = 48;

    private Gtk.ComboBox existing_categories_combo;
    private Gtk.Entry new_category_entry;
    private Gtk.ComboBox perms_combo;
    private Gtk.RadioButton use_existing_radio;
    private Gtk.RadioButton create_new_radio;
    private Interactor interactor;
    private Category[] categories;
    private PermsDescription[] perms_list;
    private Gtk.Button publish_button;

    public signal void publish(PublishingParameters parameters);
    public signal void logout();

    public PublishingOptionsPane(Interactor interactor, Category[] categories) {
        this.interactor = interactor;
        this.categories = categories;
        perms_list = create_perms_list();

        Gtk.SeparatorToolItem top_pusher = new Gtk.SeparatorToolItem();
        top_pusher.set_draw(false);
        top_pusher.set_size_request(-1, 8);
        add(top_pusher);

        Gtk.Label login_identity_label =
            new Gtk.Label(_("You are logged into Piwigo as %s.").printf(
            interactor.get_session().get_username()));

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

        Gtk.Label publish_to_label = new Gtk.Label(_("Photos will appear in:"));
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

        use_existing_radio = new Gtk.RadioButton.with_mnemonic(null, _("An _existing category:"));
        use_existing_radio.clicked.connect(on_use_existing_radio_clicked);
        main_table.attach(use_existing_radio, 1, 2, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        existing_categories_combo = new Gtk.ComboBox.text();
        Gtk.Alignment existing_categories_combo_frame = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        existing_categories_combo_frame.add(existing_categories_combo);
        main_table.attach(existing_categories_combo_frame, 2, 3, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        create_new_radio = new Gtk.RadioButton.with_mnemonic(use_existing_radio.get_group(),
            _("A _new album named:"));
        create_new_radio.clicked.connect(on_create_new_radio_clicked);
        main_table.attach(create_new_radio, 1, 2, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        new_category_entry = new Gtk.Entry();
        new_category_entry.changed.connect(on_new_category_entry_changed);
        main_table.attach(new_category_entry, 2, 3, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        Gtk.SeparatorToolItem album_size_spacer = new Gtk.SeparatorToolItem();
        album_size_spacer.set_draw(false);
        album_size_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING / 2);
        main_table.attach(album_size_spacer, 2, 3, 4, 5,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        Gtk.Label perms_label = new Gtk.Label.with_mnemonic(_("Who can see those pictures ?"));
        perms_label.set_alignment(0.0f, 0.5f);
        main_table.attach(perms_label, 0, 2, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        perms_combo = new Gtk.ComboBox.text();
        foreach(PermsDescription desc in perms_list)
            perms_combo.append_text(desc.name);
        perms_combo.set_active(0);
        Gtk.Alignment perms_combo_frame = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        perms_combo_frame.add(perms_combo);
        main_table.attach(perms_combo_frame, 2, 3, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        perms_label.set_mnemonic_widget(perms_combo);

        vert_packer.add(main_table);

        Gtk.SeparatorToolItem table_button_spacer = new Gtk.SeparatorToolItem();
        table_button_spacer.set_draw(false);
        table_button_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING);
        vert_packer.add(table_button_spacer);

        Gtk.HBox action_button_layouter = new Gtk.HBox(true, 0);

        Gtk.Button logout_button = new Gtk.Button.with_mnemonic(_("_Logout"));
        logout_button.clicked.connect(on_logout_clicked);
        logout_button.set_size_request(PublishingDialog.STANDARD_ACTION_BUTTON_WIDTH, -1);
        Gtk.Alignment logout_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        logout_button_aligner.add(logout_button);
        action_button_layouter.add(logout_button_aligner);
        Gtk.SeparatorToolItem button_spacer = new Gtk.SeparatorToolItem();
        button_spacer.set_draw(false);
        button_spacer.set_size_request(ACTION_BUTTON_SPACING, -1);
        action_button_layouter.add(button_spacer);
        publish_button = new Gtk.Button.with_mnemonic(_("_Publish"));
        publish_button.clicked.connect(on_publish_clicked);
        publish_button.set_size_request(PublishingDialog.STANDARD_ACTION_BUTTON_WIDTH, -1);
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
        int level = perms_list[perms_combo.get_active()].level;
        if (create_new_radio.get_active()) {
            string category_name = new_category_entry.get_text();
            publish(new PublishingParameters.to_new_category(category_name, level));
        } else {
            int category_id = categories[existing_categories_combo.get_active()].id;
            publish(new PublishingParameters.to_existing_category(category_id, level));
        }
    }

    private void on_use_existing_radio_clicked() {
        existing_categories_combo.set_sensitive(true);
        new_category_entry.set_sensitive(false);
        existing_categories_combo.grab_focus();
        update_publish_button_sensitivity();
    }

    private void on_create_new_radio_clicked() {
        new_category_entry.set_sensitive(true);
        existing_categories_combo.set_sensitive(false);
        new_category_entry.grab_focus();
        update_publish_button_sensitivity();
    }

    private void on_logout_clicked() {
        logout();
    }

    private void update_publish_button_sensitivity() {
        string category_name = new_category_entry.get_text();
        publish_button.set_sensitive(!(category_name.strip() == "" &&
            create_new_radio.get_active()));
    }

    private void on_new_category_entry_changed() {
        update_publish_button_sensitivity();
    }

    private PermsDescription[] create_perms_list() {
        PermsDescription[] result = new PermsDescription[0];

        result += PermsDescription(_("Everyone"), 0);
        result += PermsDescription(_("Admins, Friends, Family, Contacts"), 1);
        result += PermsDescription(_("Admins, Family, Friends"), 2);
        result += PermsDescription(_("Admins, Family"), 4);
        result += PermsDescription(_("Admins"), 8);

        return result;
    }

    public override void installed() {
        int default_category_id = -1;
        for (int i = 0; i < categories.length; i++) {
            existing_categories_combo.append_text(categories[i].name);
            if (categories[i].name == DEFAULT_CATEGORY_NAME)
                default_category_id = i;
        }

        if (categories.length == 0) {
            existing_categories_combo.set_sensitive(false);
            use_existing_radio.set_sensitive(false);
            create_new_radio.set_active(true);
            new_category_entry.grab_focus();
            new_category_entry.set_text(DEFAULT_CATEGORY_NAME);
        } else {
            if (default_category_id >= 0) {
                use_existing_radio.set_active(true);
                existing_categories_combo.set_active(default_category_id);
                new_category_entry.set_sensitive(false);
            } else {
                create_new_radio.set_active(true);
                existing_categories_combo.set_active(0);
                new_category_entry.set_text(DEFAULT_CATEGORY_NAME);
                new_category_entry.grab_focus();
            }
        }
        update_publish_button_sensitivity();
    }
}

  
  
private class Session : RESTSession {
    private string pwg_url = null;
    private string pwg_id = null;
    private string username = null;

    public Session() {
        base("");
        if (has_persistent_state())
            load_persistent_state();
    }

    private bool has_persistent_state() {
        Config config = Config.get_instance();

        return ((config.get_publishing_string(CONFIG_NAME, "url") != null) &&
            (config.get_publishing_string(CONFIG_NAME, "username") != null) &&
            (config.get_publishing_string(CONFIG_NAME, "id") != null));
    }

    private void save_persistent_state() {
        Config config = Config.get_instance();

        config.set_publishing_string(CONFIG_NAME, "url", pwg_url);
        config.set_publishing_string(CONFIG_NAME, "username", username);
        config.set_publishing_string(CONFIG_NAME, "id", pwg_id);
    }

    private void load_persistent_state() {
        Config config = Config.get_instance();

        pwg_url = config.get_publishing_string(CONFIG_NAME, "url");
        username = config.get_publishing_string(CONFIG_NAME, "username");
        pwg_id = config.get_publishing_string(CONFIG_NAME, "id");
    }

    private void clear_persistent_state() {
        Config config = Config.get_instance();

        config.set_publishing_string(CONFIG_NAME, "url", "");
        config.set_publishing_string(CONFIG_NAME, "username", "");
        config.set_publishing_string(CONFIG_NAME, "id", "");
    }

    public bool is_authenticated() {
        return (pwg_id != null && pwg_url != null && username != null);
    }

    public void authenticate(string url, string username, string id) {
        this.pwg_url = url;
        this.username = username;
        this.pwg_id = id;

        save_persistent_state();
    }

    public void deauthenticate() {
        pwg_url = null;
        username = null;
        pwg_id = null;

        clear_persistent_state();
    }

    public string get_username() {
        return username;
    }

    public string get_pwg_url() {
        return pwg_url;
    }

    public string get_pwg_id() {
        return pwg_id;
    }

    public void set_pwg_id(string id) {
        pwg_id = id;
    }
}
  
private class Transaction : RESTTransaction {
    public Transaction(Session session) {
        base(session);
        if (session.is_authenticated()) {
            add_header("Cookie", session.get_pwg_id());
        }
    }

    public Transaction.authenticated(Session session) {
        base.with_endpoint_url(session, session.get_pwg_url());
        add_header("Cookie", session.get_pwg_id());
    }

    public static new string? check_response(RESTXmlDocument doc) {
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

    public static new string? get_err_code(RESTXmlDocument doc) {
        Xml.Node* root = doc.get_root_node();
        Xml.Node* errcode;
        try {
            errcode = doc.get_named_child(root, "err");
        } catch (PublishingError err) {
            return "0";
        }
        return errcode->get_prop("code");
    }
}
  
private class SessionLoginTransaction : Transaction {
    public SessionLoginTransaction(Session session, string url, string username, string password) {
        base.with_endpoint_url(session, url);

        add_argument("method", "pwg.session.login");
        add_argument("username", username);
        add_argument("password", password);
    }
}

private class SessionGetStatusTransaction : Transaction {
    public SessionGetStatusTransaction.unauthenticated(Session session, string url, string pwg_id) {
        base.with_endpoint_url(session, url);
        add_header("Cookie", pwg_id);

        add_argument("method", "pwg.session.getStatus");
    }

    public SessionGetStatusTransaction(Session session) {
        base.authenticated(session);

        add_argument("method", "pwg.session.getStatus");
    }
}

private class CategoriesGetListTransaction : Transaction {
    public CategoriesGetListTransaction(Session session) {
        base.authenticated(session);

        add_argument("method", "pwg.categories.getList");
    }
}

private class SessionLogoutTransaction : Transaction {
    public SessionLogoutTransaction(Session session) {
        base.authenticated(session);
      
        add_argument("method", "pwg.session.logout");
    }
}

private class CategoriesAddTransaction : Transaction {
    public CategoriesAddTransaction(Session session, string category, int parent_id = 0) {
        base.authenticated(session);

        add_argument("method", "pwg.categories.add");
        add_argument("name", category);

        if (parent_id != 0) {
            add_argument("parent", parent_id.to_string());
        }
    }
}

private class ImagesAddTransaction : Transaction {
    private Session session_copy = null;
    private string source_file;
    private MediaSource media_source;
    private GLib.HashTable<string, string> binary_disposition_table = null;

    public ImagesAddTransaction(Session session, PublishingParameters parameters, string source_file, MediaSource media_source) {
        base.authenticated(session);
        this.session_copy = session;
        this.source_file = source_file;
        this.media_source = media_source;
        
        Photo photo = (Photo) media_source;
        
        LibraryPhoto lphoto = LibraryPhoto.global.fetch(photo.get_photo_id());

        Gee.List<Tag>? photo_tags = Tag.global.fetch_for_source(lphoto);
        string tags = "";
        if (photo_tags != null) {
            int i = 0;
            foreach (Tag tag in photo_tags) {
                if (i != 0) {
                    tags += ",";
                }
                tags += tag.get_name();
                i++;
            }
        }
        
        PhotoMetadata meta = photo.get_metadata();
        string author = meta.get_artist();
        
        debug("PiwigoConnector: Uploading photo %s to category id %s with perm level %s", media_source.get_name(), parameters.get_category_id().to_string(), parameters.get_perm_level().to_string());
        add_argument("method", "pwg.images.addSimple");
        add_argument("category", parameters.get_category_id().to_string());
        if (!is_string_empty(photo.get_title()))
            add_argument("name", photo.get_title());
        add_argument("level", parameters.get_perm_level().to_string());
        if (!is_string_empty(tags))
            add_argument("tags", tags);
        if (!is_string_empty(author))
            add_argument("author", author);
        
        // TODO: add description
        
        GLib.HashTable<string, string> disposition_table = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
        disposition_table.insert("filename", media_source.get_name());
        disposition_table.insert("name", "image");
        set_binary_disposition_table(disposition_table);
    }

    protected void set_binary_disposition_table(GLib.HashTable<string, string> new_disp_table) {
        binary_disposition_table = new_disp_table;
    }

    // Need to copy and paste this method to add the cookie header to the sent message.
    public override void execute() throws PublishingError {

        RESTArgument[] request_arguments = get_arguments();
        assert(request_arguments.length > 0);

        // create the multipart request container
        Soup.Multipart message_parts = new Soup.Multipart("multipart/form-data");

        // attach each REST argument as its own multipart formdata part
        foreach (RESTArgument arg in request_arguments)
            message_parts.append_form_string(arg.key, arg.value);

        // attempt to read the binary image data from disk
        string photo_data;
        size_t data_length;
        try {
            FileUtils.get_contents(source_file, out photo_data, out data_length);
        } catch (FileError e) {
            string msg = "Piwigo: couldn't ready data from %s: %s".printf(source_file,
                e.message);
            warning("%s", msg);
            
            throw new PublishingError.LOCAL_FILE_ERROR(msg);
        }

        // get the sequence number of the part that will soon become the binary image data
        // part
        int image_part_num = message_parts.get_length();

        // bind the binary image data read from disk into a Soup.Buffer object so that we
        // can attach it to the multipart request, then actaully append the buffer
        // to the multipart request. Then, set the MIME type for this part.
        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.COPY, photo_data, data_length);
        message_parts.append_form_file("", source_file, "image/jpeg", bindable_data);

        // set up the Content-Disposition header for the multipart part that contains the
        // binary image data
        unowned Soup.MessageHeaders image_part_header;
        unowned Soup.Buffer image_part_body;
        message_parts.get_part(image_part_num, out image_part_header, out image_part_body);
        image_part_header.set_content_disposition("form-data", binary_disposition_table);

        // create a message that can be sent over the wire whose payload is the multipart container
        // that we've been building up
        Soup.Message outbound_message = soup_form_request_new_from_multipart(
            get_endpoint_url(), message_parts);
        outbound_message.request_headers.append("Cookie", session_copy.get_pwg_id());
        set_message(outbound_message);

        // send the message and get its response
        set_is_executed(true);
        send();
    }
}
}

