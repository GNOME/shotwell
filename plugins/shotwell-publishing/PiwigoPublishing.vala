/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class PiwigoService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "piwigo.svg";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;
    
    public PiwigoService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_from_resource
                (Resources.RESOURCE_PATH + "/" + ICON_FILENAME);
    }
    
    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.piwigo";
    }
    
    public unowned string get_pluggable_name() {
        return "Piwigo";
    }
    
    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Bruno Girin";
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
        return new Publishing.Piwigo.PiwigoPublisher(this, host);
    }
    
    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO);
    }
}

namespace Publishing.Piwigo {

internal const string SERVICE_NAME = "Piwigo";
internal const string PIWIGO_WS = "ws.php";
internal const int ORIGINAL_SIZE = -1;

internal class Category {
    public int id;
    public string name;
    public string comment;
    public string display_name;
    public string uppercats;
    public const int NO_ID = -1;

    public Category(int id, string name, string uppercats, string? comment = "") {
        this.id = id;
        this.name = name;
        this.uppercats = uppercats;
        this.comment = comment;
    }
    
    public Category.local(string name, int parent_id, string? comment = "") {
        this.id = NO_ID;
        this.name = name;
        // for new categories abuse the uppercats value for
        // the id of the new parent!
        this.uppercats = parent_id.to_string();
        this.comment = comment;
    }

    public bool is_local() {
        return this.id == NO_ID;
    }

    public static bool equal (Category self, Category other) {
        return self.id == other.id;
    }
}

internal class PermissionLevel {
    public int id;
    public string name;

    public PermissionLevel(int id, string name) {
        this.id = id;
        this.name = name;
    }
}

internal class SizeEntry {
    public int id;
    public string name;

    public SizeEntry(int id, string name) {
        this.id = id;
        this.name = name;
    }
}

internal class PublishingParameters {
    public Category category = null;
    public PermissionLevel perm_level = null;
    public SizeEntry photo_size = null;
    public bool title_as_comment = false;
    public bool no_upload_tags = false;

    public PublishingParameters() {
    }
}

public class PiwigoPublisher : Spit.Publishing.Publisher, GLib.Object {
    private Spit.Publishing.Service service;
    private Spit.Publishing.PluginHost host;
    private bool running = false;
    private bool strip_metadata = false;
    private Session session;
    private Category[] categories = null;
    private PublishingParameters parameters = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;

    public PiwigoPublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        debug("PiwigoPublisher instantiated.");
        this.service = service;
        this.host = host;
        session = new Session();
    }

    // Publisher interface implementation
    
    public Spit.Publishing.Service get_service() {
        return service;
    }
    
    public Spit.Publishing.PluginHost get_host() {
        return host;
    }

    public bool is_running() {
        return running;
    }
    
    public void start() {
        if (is_running())
            return;
        
        debug("PiwigoPublisher: starting interaction.");
        
        running = true;
        
        if (session.is_authenticated()) {
            debug("PiwigoPublisher: session is authenticated.");
            do_fetch_categories();
        } else {
            debug("PiwigoPublisher: session is not authenticated.");
            string? persistent_url = get_persistent_url();
            string? persistent_username = get_persistent_username();
            string? persistent_password = get_persistent_password();
            if (persistent_url != null && persistent_username != null && persistent_password != null)
                do_network_login(persistent_url, persistent_username,
                    persistent_password, get_remember_password());
            else
                do_show_authentication_pane();
        }
    }
    
    public void stop() {
        running = false;
    }
    
    // Session and persistent data
    
    public string? get_persistent_url() {
        return host.get_config_string("url", null);
    }
    
    private void set_persistent_url(string url) {
        host.set_config_string("url", url);
    }
    
    public string? get_persistent_username() {
        return host.get_config_string("username", null);
    }
    
    private void set_persistent_username(string username) {
        host.set_config_string("username", username);
    }
    
    public string? get_persistent_password() {
        return host.get_config_string("password", null);
    }
    
    private void set_persistent_password(string? password) {
        host.set_config_string("password", password);
    }
    
    public bool get_remember_password() {
        return host.get_config_bool("remember-password", false);
    }
    
    private void set_remember_password(bool remember_password) {
        host.set_config_bool("remember-password", remember_password);
    }
    
    public int get_last_category() {
        return host.get_config_int("last-category", -1);
    }
    
    private void set_last_category(int last_category) {
        host.set_config_int("last-category", last_category);
    }
    
    public int get_last_permission_level() {
        return host.get_config_int("last-permission-level", -1);
    }
    
    private void set_last_permission_level(int last_permission_level) {
        host.set_config_int("last-permission-level", last_permission_level);
    }
    
    public int get_last_photo_size() {
        return host.get_config_int("last-photo-size", -1);
    }
    
    private void set_last_photo_size(int last_photo_size) {
        host.set_config_int("last-photo-size", last_photo_size);
    }
    
    private bool get_last_title_as_comment() {
        return host.get_config_bool("last-title-as-comment", false);
    }
    
    private void set_last_title_as_comment(bool title_as_comment) {
        host.set_config_bool("last-title-as-comment", title_as_comment);
    }
    
    private bool get_last_no_upload_tags() {
        return host.get_config_bool("last-no-upload-tags", false);
    }
    
    private void set_last_no_upload_tags(bool no_upload_tags) {
        host.set_config_bool("last-no-upload-tags", no_upload_tags);
    }
    
    private bool get_metadata_removal_choice() {
        return host.get_config_bool("strip_metadata", false);
    }
    
    private void set_metadata_removal_choice(bool strip_metadata) {
        host.set_config_bool("strip_metadata", strip_metadata);
    }
    
    // Actions and events implementation
    
    /**
     * Action that shows the authentication pane.
     *
     * This action method shows the authentication pane. It is shown at the
     * very beginning of the interaction when no persistent parameters are found
     * or after a failed login attempt using persisted parameters. It can be
     * given a mode flag to specify whether it should be displayed in initial
     * mode or in any of the error modes that it supports.
     *
     * @param mode the mode for the authentication pane
     */
    private void do_show_authentication_pane(AuthenticationPane.Mode mode = AuthenticationPane.Mode.INTRO) {
        debug("ACTION: installing authentication pane");

        host.set_service_locked(false);
        AuthenticationPane authentication_pane =
            new AuthenticationPane(this, mode);
        authentication_pane.login.connect(on_authentication_pane_login_clicked);
        host.install_dialog_pane(authentication_pane, Spit.Publishing.PluginHost.ButtonMode.CLOSE);
        host.set_dialog_default_widget(authentication_pane.get_default_widget());
    }

    private void do_show_ssl_downgrade_pane (SessionLoginTransaction trans,
                                             string url) {
        var uri = new Soup.URI (url);
        host.set_service_locked (false);
        var ssl_pane = new SSLErrorPane (trans, uri.get_host ());
        ssl_pane.proceed.connect (() => {
            debug ("SSL: User wants us to retry with broken certificate");
            this.session = new Session ();
            this.session.set_insecure ();

            string? persistent_url = get_persistent_url();
            string? persistent_username = get_persistent_username();
            string? persistent_password = get_persistent_password();
            if (persistent_url != null && persistent_username != null && persistent_password != null)
                do_network_login(persistent_url, persistent_username,
                    persistent_password, get_remember_password());
            else
                do_show_authentication_pane();
        });
        host.install_dialog_pane (ssl_pane,
                                  Spit.Publishing.PluginHost.ButtonMode.CLOSE);
        host.set_dialog_default_widget (ssl_pane.get_default_widget ());
    }

    /**
     * Event triggered when the login button in the authentication panel is
     * clicked.
     *
     * This event is triggered when the login button in the authentication
     * panel is clicked. It then triggers a network login interaction.
     *
     * @param url the URL of the Piwigo service as entered in the dialog
     * @param username the name of the Piwigo user as entered in the dialog
     * @param password the password of the Piwigo as entered in the dialog
     */
    private void on_authentication_pane_login_clicked(
        string url, string username, string password, bool remember_password
    ) {
        debug("EVENT: on_authentication_pane_login_clicked");
        if (!running)
            return;

        do_network_login(url, username, password, remember_password);
    }
    
    /**
     * Action to perform a network login to a Piwigo service.
     *
     * This action performs a network login a Piwigo service specified by a
     * URL and using the given user name and password as credentials.
     *
     * @param url the URL of the Piwigo service; this URL will be normalised
     *     before being used
     * @param username the name of the Piwigo user used to login
     * @param password the password of the Piwigo user used to login
     */
    private void do_network_login(string url, string username, string password, bool remember_password) {
        debug("ACTION: logging in");
        host.set_service_locked(true);
        host.install_login_wait_pane();
        
        set_remember_password(remember_password);
        if (remember_password)
            set_persistent_password(password);
        else
            set_persistent_password(null);

        SessionLoginTransaction login_trans = new SessionLoginTransaction(
            session, normalise_url(url), username, password);
        login_trans.network_error.connect(on_login_network_error);
        login_trans.completed.connect(on_login_network_complete);

        try {
            login_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            if (err is Spit.Publishing.PublishingError.SSL_FAILED) {
                debug ("ERROR: SSL connection problems");
                do_show_ssl_downgrade_pane (login_trans, url);
            } else {
                debug("ERROR: do_network_login");
                do_show_error(err);
            }
        }
    }
    
    public static string normalise_url(string url) {
        string norm_url = url;

        if(!norm_url.has_suffix(".php")) {
            if(!norm_url.has_suffix("/")) {
                norm_url = norm_url + "/";
            }
            norm_url = norm_url + PIWIGO_WS;
        }

        if(!norm_url.has_prefix("http://") && !norm_url.has_prefix("https://")) {
            norm_url = "http://" + norm_url;
        }
        
        return norm_url;
    }
    
    /**
     * Event triggered when the network login action is complete and successful.
     *
     * This event is triggered on successful completion of a network login.
     * Calling this event implies that the URL, user name and password provided
     * in the authentication pane are valid and that the transaction should
     * contain a Set-Cookie header that includes the value pwg_id for that
     * user. As a result, this event will also authenticate the session and
     * persist all values so that they can be re-used during the next publishing
     * interaction.
     *
     * @param txn the received REST transaction
     */
    private void on_login_network_complete(Publishing.RESTSupport.Transaction txn) {
        debug("EVENT: on_login_network_complete");
        txn.completed.disconnect(on_login_network_complete);
        txn.network_error.disconnect(on_login_network_error);
        
        try {
            Publishing.RESTSupport.XmlDocument.parse_string(
                txn.get_response(), Transaction.validate_xml);
        } catch (Spit.Publishing.PublishingError err) {
            // Get error code first
            try {
                Publishing.RESTSupport.XmlDocument.parse_string(
                    txn.get_response(), Transaction.get_error_code);
            } catch (Spit.Publishing.PublishingError code) {
                int code_int = int.parse(code.message);
                if (code_int == 999) {
                    debug("ERROR: on_login_network_complete, code 999");
                    do_show_authentication_pane(AuthenticationPane.Mode.FAILED_RETRY_USER);
                } else {
                    debug("ERROR: on_login_network_complete");
                    do_show_error(err);
                }
            }
            return;
        }
        // Get session ID and authenticate the session
        string endpoint_url = txn.get_endpoint_url(); 
        debug("Setting endpoint URL to %s", endpoint_url);
        string pwg_id = get_pwg_id_from_transaction(txn);
        debug("Setting session pwg_id to %s", pwg_id);
        session.set_pwg_id(pwg_id);

        do_fetch_session_status(endpoint_url, pwg_id);
    }
    
    /**
     * Event triggered when a network login action fails due to a network error.
     *
     * This event triggered as a result of a network error during the login
     * transaction. As a result, it assumes that the service URL entered in the
     * authentication dialog is incorrect and re-presents the authentication
     * dialog with FAILED_RETRY_URL mode.
     *
     * @param bad_txn the received REST transaction
     * @param err the received error
     */
    private void on_login_network_error(
        Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err
    ) {
        debug("EVENT: on_login_network_error");
        bad_txn.completed.disconnect(on_login_network_complete);
        bad_txn.network_error.disconnect(on_login_network_error);

        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;

        do_show_authentication_pane(AuthenticationPane.Mode.FAILED_RETRY_URL);
    }
    
    /**
     * Action to fetch the session status for a known Piwigo user.
     *
     * This action fetches the session status for a Piwigo user for whom the
     * pwg_id is known. If triggered after a network login, it should just
     * confirm that the session is OK. It can also be triggered as the first
     * action of the interaction for users for who the pwg_id was previously
     * persisted. In this case, it will log the user in and confirm the
     * identity.
     */
    private void do_fetch_session_status(string url = "", string pwg_id = "") {
        debug("ACTION: fetching session status");
        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();
        
        if (!session.is_authenticated()) {
            SessionGetStatusTransaction status_txn = new SessionGetStatusTransaction.unauthenticated(session, url, pwg_id);
            status_txn.network_error.connect(on_session_get_status_error);
            status_txn.completed.connect(on_session_get_status_complete);

            try {
                status_txn.execute();
            } catch (Spit.Publishing.PublishingError err) {
                debug("ERROR: do_fetch_session_status, not authenticated");
                do_show_error(err);
            }
        } else {
            SessionGetStatusTransaction status_txn = new SessionGetStatusTransaction(session);
            status_txn.network_error.connect(on_session_get_status_error);
            status_txn.completed.connect(on_session_get_status_complete);

            try {
                status_txn.execute();
            } catch (Spit.Publishing.PublishingError err) {
                debug("ERROR: do_fetch_session_status, authenticated");
                do_show_error(err);
            }
        }
    }
    
    /**
     * Event triggered when the get session status action completes successfully.
     *
     * This event being triggered confirms that the session is valid and can becyclonic enema
     * used. If the session is not fully authenticated yet, this event finalises
     * session authentication. It then triggers the fetch categories action.
     */
    private void on_session_get_status_complete(Publishing.RESTSupport.Transaction txn) {
        debug("EVENT: on_session_get_status_complete");
        txn.completed.disconnect(on_session_get_status_complete);
        txn.network_error.disconnect(on_session_get_status_error);

        if (!session.is_authenticated()) {
            string endpoint_url = txn.get_endpoint_url();
            string pwg_id = session.get_pwg_id();
            debug("Fetching session status for pwg_id %s", pwg_id);
            // Parse the response
            try {
                Publishing.RESTSupport.XmlDocument doc =
                    Publishing.RESTSupport.XmlDocument.parse_string(
                        txn.get_response(), Transaction.validate_xml);
                Xml.Node* root = doc.get_root_node();
                Xml.Node* username_node;
                try {
                    username_node = doc.get_named_child(root, "username");
                    string username = username_node->get_content();
                    debug("Returned username is %s", username);
                    session.authenticate(endpoint_url, username, pwg_id);
                    set_persistent_url(session.get_pwg_url());
                    set_persistent_username(session.get_username());
                    do_fetch_categories();
                } catch (Spit.Publishing.PublishingError err2) {
                    debug("ERROR: on_session_get_status_complete, inner");
                    do_show_error(err2);
                    return;
                }
            } catch (Spit.Publishing.PublishingError err) {
                debug("ERROR: on_session_get_status_complete, outer");
                do_show_error(err);
                return;
            }
        } else {
            // This should never happen as the session should not be
            // authenticated at that point so this call is a safeguard
            // against the interaction not happening properly.
            do_fetch_categories();
        }
    }
    
    /**
     * Event triggered when the get session status fails due to a network error.
     */
    private void on_session_get_status_error(
        Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err
    ) {
        debug("EVENT: on_session_get_status_error");
        bad_txn.completed.disconnect(on_session_get_status_complete);
        bad_txn.network_error.disconnect(on_session_get_status_error);
        on_network_error(bad_txn, err);
    }

    /**
     * Action that fetches all available categories from the Piwigo service.
     *
     * This action fetches all categories from the Piwigo service in order
     * to populate the publishing pane presented to the user.
     */
    private void do_fetch_categories() {
        debug("ACTION: fetching categories");
        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();

        CategoriesGetListTransaction cat_trans = new CategoriesGetListTransaction(session);
        cat_trans.network_error.connect(on_category_fetch_error);
        cat_trans.completed.connect(on_category_fetch_complete);
        
        try {
            cat_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            debug("ERROR: do_fetch_categories");
            do_show_error(err);
        }
    }
    
    /**
     * Event triggered when the fetch categories action completes successfully.
     *
     * This event retrieves all categories from the received transaction and
     * populates the categories list. It then triggers the display of the
     * publishing options pane.
     */
    private void on_category_fetch_complete(Publishing.RESTSupport.Transaction txn) {
        debug("EVENT: on_category_fetch_complete");
        txn.completed.disconnect(on_category_fetch_complete);
        txn.network_error.disconnect(on_category_fetch_error);
        debug("PiwigoConnector: list of categories: %s", txn.get_response());
        // Empty the categories
        if (categories != null) {
            categories = null;
        }
        // Parse the response
        try {
            Publishing.RESTSupport.XmlDocument doc =
                Publishing.RESTSupport.XmlDocument.parse_string(
                    txn.get_response(), Transaction.validate_xml);
            Xml.Node* root = doc.get_root_node();
            Xml.Node* categories_node = root->first_element_child();
            Xml.Node* category_node_iter = categories_node->children;
            Xml.Node* name_node;
            Xml.Node* uppercats_node;
            string name = "";
            string id_string = "";
            string uppercats = "";
            var id_map = new Gee.HashMap<string, string> ();

            for ( ; category_node_iter != null; category_node_iter = category_node_iter->next) {
                name_node = doc.get_named_child(category_node_iter, "name");
                name = name_node->get_content();
                uppercats_node = doc.get_named_child(category_node_iter, "uppercats");
                uppercats = (string)uppercats_node->get_content();
                id_string = category_node_iter->get_prop("id");
                id_map.set (id_string, name);

                if (categories == null) {
                    categories = new Category[0];
                }
                categories += new Category(int.parse(id_string), name, uppercats);
            }

            // compute the display name for the categories
            for(int i = 0; i < categories.length; i++) {
                string[] upcatids = categories[i].uppercats.split(",");
                var builder = new StringBuilder();
                for (int j=0; j < upcatids.length; j++) {
                    builder.append ("/ ");
                    builder.append (id_map.get (upcatids[j]));
                    builder.append (" ");
                }
                categories[i].display_name = builder.str;
            }
        } catch (Spit.Publishing.PublishingError err) {
            debug("ERROR: on_category_fetch_complete");
            do_show_error(err);
            return;
        }

        do_show_publishing_options_pane();
    }
    
    /**
     * Event triggered when the fetch categories transaction fails due to a
     * network error.
     */
    private void on_category_fetch_error(
        Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err
    ) {
        debug("EVENT: on_category_fetch_error");
        bad_txn.completed.disconnect(on_category_fetch_complete);
        bad_txn.network_error.disconnect(on_category_fetch_error);
        on_network_error(bad_txn, err);
    }
    
    /**
     * Action that shows the publishing options pane.
     *
     * This action method shows the publishing options pane.
     */
    private void do_show_publishing_options_pane() {
        debug("ACTION: installing publishing options pane");

        host.set_service_locked(false);
        PublishingOptionsPane opts_pane = new PublishingOptionsPane(
            this, categories, get_last_category(), get_last_permission_level(), get_last_photo_size(),
            get_last_title_as_comment(), get_last_no_upload_tags(), get_metadata_removal_choice());
        opts_pane.logout.connect(on_publishing_options_pane_logout_clicked);
        opts_pane.publish.connect(on_publishing_options_pane_publish_clicked);
        host.install_dialog_pane(opts_pane, Spit.Publishing.PluginHost.ButtonMode.CLOSE);
        host.set_dialog_default_widget(opts_pane.get_default_widget());
    }
    
    /**
     * Event triggered when the user clicks logout in the publishing options pane.
     */
    private void on_publishing_options_pane_logout_clicked() {
        debug("EVENT: on_publishing_options_pane_logout_clicked");
        SessionLogoutTransaction logout_trans = new SessionLogoutTransaction(session);
        logout_trans.network_error.connect(on_logout_network_error);
        logout_trans.completed.connect(on_logout_network_complete);

        try {
            logout_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            debug("ERROR: on_publishing_options_pane_logout_clicked");
            do_show_error(err);
        }
    }
    
    /**
     * Event triggered when the logout action completes successfully.
     *
     * This event de-authenticates the session and shows the authentication
     * pane again.
     */
    private void on_logout_network_complete(Publishing.RESTSupport.Transaction txn) {
        debug("EVENT: on_logout_network_complete");
        txn.completed.disconnect(on_logout_network_complete);
        txn.network_error.disconnect(on_logout_network_error);

        session.deauthenticate();

        do_show_authentication_pane(AuthenticationPane.Mode.INTRO);
    }
    
    /**
     * Event triggered when the logout action fails due to a network error.
     */
    private void on_logout_network_error(
        Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err
    ) {
        debug("EVENT: on_logout_network_error");
        bad_txn.completed.disconnect(on_logout_network_complete);
        bad_txn.network_error.disconnect(on_logout_network_error);
        on_network_error(bad_txn, err);
    }
    
    /**
     * Event triggered when the user clicks publish in the publishing options pane.
     *
     * This event first saves the parameters so that they can re-used later.
     * If the publishing parameters indicate that the user wants to create a new
     * category, the create category action is called. Otherwise, the upload
     * action is called.
     *
     * @param parameters the publishing parameters
     */
    private void on_publishing_options_pane_publish_clicked(PublishingParameters parameters,
        bool strip_metadata) {
        debug("EVENT: on_publishing_options_pane_publish_clicked");
        this.parameters = parameters;
        this.strip_metadata = strip_metadata;

        if (parameters.category.is_local()) {
            do_create_category(parameters.category);
        } else {
            do_upload(this.strip_metadata);
        }
    }
    
    /**
     * Action that creates a new category in the Piwigo library.
     *
     * This actions runs a REST transaction to create a new category in the
     * Piwigo library. It displays a wait pane with an information message
     * while the transaction is running. This action should only be called with
     * a local cateogory, i.e. one that does not exist on the server and does
     * not yet have an ID.
     *
     * @param category the new category to create on the server
     */
    private void do_create_category(Category category) {
        debug("ACTION: creating a new category: %s".printf(category.name));
        assert(category.is_local());

        host.set_service_locked(true);
        host.install_static_message_pane(_("Creating album %s…").printf(category.name));

        CategoriesAddTransaction creation_trans = new CategoriesAddTransaction(
            session, category.name.strip(), int.parse(category.uppercats), category.comment);
        creation_trans.network_error.connect(on_category_add_error);
        creation_trans.completed.connect(on_category_add_complete);
        
        try {
            creation_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            debug("ERROR: do_create_category");
            do_show_error(err);
        }
    }
    
    /**
     * Event triggered when the add category action completes successfully.
     *
     * This event parses the ID assigned to new category out of the received
     * transaction and assigns that ID to the category currently held in
     * the publishing parameters. It then calls the upload action.
     */
    private void on_category_add_complete(Publishing.RESTSupport.Transaction txn) {
        debug("EVENT: on_category_add_complete");
        txn.completed.disconnect(on_category_add_complete);
        txn.network_error.disconnect(on_category_add_error);

        // Parse the response
        try {
            Publishing.RESTSupport.XmlDocument doc =
                Publishing.RESTSupport.XmlDocument.parse_string(
                    txn.get_response(), Transaction.validate_xml);
            Xml.Node* rsp = doc.get_root_node();
            Xml.Node* id_node;
            id_node = doc.get_named_child(rsp, "id");
            string id_string = id_node->get_content();
            int id = int.parse(id_string);
            parameters.category.id = id;
            do_upload(strip_metadata);
        } catch (Spit.Publishing.PublishingError err) {
            debug("ERROR: on_category_add_complete");
            do_show_error(err);
        }
    }
    
    /**
     * Event triggered when the add category action fails due to a network error.
     */
    private void on_category_add_error(
        Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err
    ) {
        debug("EVENT: on_category_add_error");
        bad_txn.completed.disconnect(on_category_add_complete);
        bad_txn.network_error.disconnect(on_category_add_error);
        on_network_error(bad_txn, err);
    }
    
    /**
     * Upload action: the big one, the one we've been waiting for!
     */
    private void do_upload(bool strip_metadata) {
        this.strip_metadata = strip_metadata;
        debug("ACTION: uploading pictures");
        
        host.set_service_locked(true);
        // Save last category, permission level and size for next use
        set_last_category(parameters.category.id);
        set_last_permission_level(parameters.perm_level.id);
        set_last_photo_size(parameters.photo_size.id);
        set_last_title_as_comment(parameters.title_as_comment);
        set_last_no_upload_tags(parameters.no_upload_tags);
        set_metadata_removal_choice(strip_metadata);

        progress_reporter = host.serialize_publishables(parameters.photo_size.id, this.strip_metadata);
        Spit.Publishing.Publishable[] publishables = host.get_publishables();
        
        Uploader uploader = new Uploader(session, publishables, parameters);
        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);
        uploader.upload(on_upload_status_updated);
    }
    
    /**
     * Event triggered when the batch uploader reports that at least one of the
     * network transactions encapsulating uploads has completed successfully
     */
    private void on_upload_complete(Publishing.RESTSupport.BatchUploader uploader, int num_published) {
        debug("EVENT: on_upload_complete");
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);
        
        // TODO: should a message be displayed to the user if num_published is zero?

        if (!is_running())
            return;

        do_show_success_pane();
    }
    
    /**
     * Event triggered when the batch uploader reports that at least one of the
     * network transactions encapsulating uploads has caused a network error
     */
    private void on_upload_error(
        Publishing.RESTSupport.BatchUploader uploader,
        Spit.Publishing.PublishingError err
    ) {
        debug("EVENT: on_upload_error");
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        do_show_error(err);
    }
    
    /**
     * Event triggered when upload progresses and the status needs to be updated.
     */
    private void on_upload_status_updated(int file_number, double completed_fraction) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);

        progress_reporter(file_number, completed_fraction);
    }
    
    /**
     * Action to display the success pane in the publishing dialog.
     */
    private void do_show_success_pane() {
        debug("ACTION: installing success pane");

        host.set_service_locked(false);
        host.install_success_pane();
    }
    
    /**
     * Helper event to handle network errors.
     */
    private void on_network_error(
        Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err
    ) {
        debug("EVENT: on_network_error");
        do_show_error(err);
    }
    
    /**
     * Action to display an error to the user.
     */
    private void do_show_error(Spit.Publishing.PublishingError e) {
        debug("ACTION: do_show_error");
        string error_type = "UNKNOWN";
        if (e is Spit.Publishing.PublishingError.NO_ANSWER) {
            do_show_authentication_pane(AuthenticationPane.Mode.FAILED_RETRY_URL);
            return;
        } else if(e is Spit.Publishing.PublishingError.COMMUNICATION_FAILED) {
            error_type = "COMMUNICATION_FAILED";
        } else if(e is Spit.Publishing.PublishingError.PROTOCOL_ERROR) {
            error_type = "PROTOCOL_ERROR";
        } else if(e is Spit.Publishing.PublishingError.SERVICE_ERROR) {
            error_type = "SERVICE_ERROR";
        } else if(e is Spit.Publishing.PublishingError.MALFORMED_RESPONSE) {
            error_type = "MALFORMED_RESPONSE";
        } else if(e is Spit.Publishing.PublishingError.LOCAL_FILE_ERROR) {
            error_type = "LOCAL_FILE_ERROR";
        } else if(e is Spit.Publishing.PublishingError.EXPIRED_SESSION) {
            error_type = "EXPIRED_SESSION";
        } else if (e is Spit.Publishing.PublishingError.SSL_FAILED) {
            error_type = "SECURE_CONNECTION_FAILED";
        }
        
        debug("Unhandled error: type=%s; message='%s'".printf(error_type, e.message));
        do_show_error_message(_("An error message occurred when publishing to Piwigo. Please try again."));
    }
    
    /**
     * Action to display an error message to the user.
     */
    private void do_show_error_message(string message) {
        debug("ACTION: do_show_error_message");
        host.install_static_message_pane(message,
                Spit.Publishing.PluginHost.ButtonMode.CLOSE);
    }
    
    // Helper methods
    
    /**
     * Retrieves session ID from a REST Transaction received
     *
     * This helper method extracts the pwg_id out of the Set-Cookie header if
     * present in the received transaction.
     *
     * @param txn the received transaction
     * @return the value of pwg_id if present or null if not found
     */
    private string? get_pwg_id_from_transaction(Publishing.RESTSupport.Transaction txn) {
        string? pwg_id = null;

        foreach (var cookie in Soup.cookies_from_response(txn.get_message())) {
            if (cookie.get_name() == "pwg_id") {
                // Collect all ids, last one is the one to use. First one is
                // for Guest apparently
                pwg_id = cookie.get_value();
                debug ("Found pwg_id %s", pwg_id);
            }
        }

        return pwg_id;
    }
}

// The uploader

internal class Uploader : Publishing.RESTSupport.BatchUploader {
    private PublishingParameters parameters;

    public Uploader(Session session, Spit.Publishing.Publishable[] publishables,
        PublishingParameters parameters) {
        base(session, publishables);
        
        this.parameters = parameters;
    }

    protected override Publishing.RESTSupport.Transaction create_transaction(
        Spit.Publishing.Publishable publishable) {
        return new ImagesAddTransaction((Session) get_session(), parameters,
            publishable);
    }
}

// UI elements

internal class SSLErrorPane : Shotwell.Plugins.Common.BuilderPane {

    public signal void proceed ();
    public string host { owned get; construct; }
    public TlsCertificate? cert { private get; construct; }
    public string error_text { owned get; construct; }

    public SSLErrorPane (SessionLoginTransaction transaction,
                         string host) {
        TlsCertificate cert;
        var text = transaction.detailed_error_from_tls_flags (out cert);
        Object (resource_path : Resources.RESOURCE_PATH +
                                "/piwigo_ssl_failure_pane.ui",
                default_id: "default",
                cert : cert,
                error_text : text,
                host : host);
    }

    public override void constructed () {
        base.constructed ();

        var label = this.get_builder ().get_object ("main_text") as Gtk.Label;
        // %s is the host name that we tried to connect to
        label.set_text (_("This does not look like the real <b>%s</b>. Attackers might be trying to steal or alter information going to or from this site (for example, private messages, credit card information, or passwords).").printf (host));
        label.use_markup = true;

        label = this.get_builder ().get_object ("ssl_errors") as Gtk.Label;
        label.set_text (error_text);

        var info = this.get_builder ().get_object ("default") as Gtk.Button;
        if (cert != null) {
            info.clicked.connect (() => {
                var simple_cert = new Gcr.SimpleCertificate (cert.certificate.data);
                var widget = new Gcr.CertificateWidget (simple_cert);
                bool use_header = true;
                Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header);
                var flags = (Gtk.DialogFlags) 0;
                if (use_header) {
                    flags |= Gtk.DialogFlags.USE_HEADER_BAR;
                }

                var dialog = new Gtk.Dialog.with_buttons (
                                _("Certificate of %s").printf (host),
                                null,
                                flags,
                                _("_OK"), Gtk.ResponseType.OK);
                dialog.get_content_area ().add (widget);
                dialog.set_default_response (Gtk.ResponseType.OK);
                dialog.set_default_size (640, -1);
                dialog.show_all ();
                dialog.run ();
                dialog.destroy ();
            });
        } else {
            info.get_parent().remove(info);
        }

        var proceed = this.get_builder ().get_object ("proceed_button") as Gtk.Button;
        proceed.clicked.connect (() => { this.proceed (); });
    }
}

/**
 * The authentication pane used when asking service URL, user name and password
 * from the user.
 */
internal class AuthenticationPane : Shotwell.Plugins.Common.BuilderPane {
    public enum Mode {
        INTRO,
        FAILED_RETRY_URL,
        FAILED_RETRY_USER
    }

    public Mode mode { get; construct; }
    public unowned PiwigoPublisher publisher { get; construct; }

    private static string INTRO_MESSAGE = _("Enter the URL of your Piwigo photo library as well as the username and password associated with your Piwigo account for that library.");
    private static string FAILED_RETRY_URL_MESSAGE = _("Shotwell cannot contact your Piwigo photo library. Please verify the URL you entered");
    private static string FAILED_RETRY_USER_MESSAGE = _("Username and/or password invalid. Please try again");

    private Gtk.Entry url_entry;
    private Gtk.Entry username_entry;
    private Gtk.Entry password_entry;
    private Gtk.Switch remember_password_checkbutton;
    private Gtk.Button login_button;

    public signal void login(string url, string user, string password, bool remember_password);

    public AuthenticationPane (PiwigoPublisher publisher, Mode mode = Mode.INTRO) {
        Object (resource_path : Resources.RESOURCE_PATH +
                                "/piwigo_authentication_pane.ui",
                connect_signals : true,
                default_id : "login_button",
                mode : mode,
                publisher : publisher);
    }

    public override void constructed () {
        base.constructed ();

        var builder = this.get_builder ();
        var message_label = builder.get_object("message_label") as Gtk.Label;
        switch (mode) {
            case Mode.INTRO:
                message_label.set_text(INTRO_MESSAGE);
                break;

            case Mode.FAILED_RETRY_URL:
                message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                    "Invalid URL"), FAILED_RETRY_URL_MESSAGE));
                break;

            case Mode.FAILED_RETRY_USER:
                message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                    "Invalid User Name or Password"), FAILED_RETRY_USER_MESSAGE));
                break;
        }

        url_entry = builder.get_object ("url_entry") as Gtk.Entry;
        string? persistent_url = publisher.get_persistent_url();
        if (persistent_url != null) {
            url_entry.set_text(persistent_url);
        }
        username_entry = builder.get_object ("username_entry") as Gtk.Entry;
        string? persistent_username = publisher.get_persistent_username();
        if (persistent_username != null) {
            username_entry.set_text(persistent_username);
        }
        password_entry = builder.get_object ("password_entry") as Gtk.Entry;
        string? persistent_password = publisher.get_persistent_password();
        if (persistent_password != null) {
            password_entry.set_text(persistent_password);
        }
        remember_password_checkbutton =
            builder.get_object ("remember_password_checkbutton") as Gtk.Switch;
        remember_password_checkbutton.set_active(publisher.get_remember_password());

        login_button = builder.get_object("login_button") as Gtk.Button;

        username_entry.changed.connect(on_user_changed);
        url_entry.changed.connect(on_url_changed);
        password_entry.changed.connect(on_password_changed);
        login_button.clicked.connect(on_login_button_clicked);

        publisher.get_host().set_dialog_default_widget(login_button);
    }

    private void on_login_button_clicked() {
        login(url_entry.get_text(), username_entry.get_text(),
            password_entry.get_text(), remember_password_checkbutton.get_active());
    }

    private void on_url_changed() {
        update_login_button_sensitivity();
    }

    private void on_user_changed() {
        update_login_button_sensitivity();
    }

    private void on_password_changed() {
        update_login_button_sensitivity();
    }
    
    private void update_login_button_sensitivity() {
        login_button.set_sensitive(url_entry.text_length != 0 &&
                                   username_entry.text_length != 0 &&
                                   password_entry.text_length != 0);
    }
    
    public override void on_pane_installed() {
        base.on_pane_installed ();

        url_entry.grab_focus();
        password_entry.set_activates_default(true);
        login_button.can_default = true;
        update_login_button_sensitivity();
    }
}

/**
 * The publishing options pane.
 */
internal class PublishingOptionsPane : Shotwell.Plugins.Common.BuilderPane {

    private static string DEFAULT_CATEGORY_NAME = _("Shotwell Connect");

    private Gtk.RadioButton use_existing_radio;
    private Gtk.RadioButton create_new_radio;
    private Gtk.ComboBoxText existing_categories_combo;
    private Gtk.Entry new_category_entry;
    private Gtk.Label within_existing_label;
    private Gtk.ComboBoxText within_existing_combo;
    private Gtk.ComboBoxText perms_combo;
    private Gtk.ComboBoxText size_combo;
    private Gtk.CheckButton strip_metadata_check = null;
    private Gtk.CheckButton title_as_comment_check = null;
    private Gtk.CheckButton no_upload_tags_check = null;
    private Gtk.Button logout_button;
    private Gtk.Button publish_button;
    private Gtk.TextView album_comment;
    private Gtk.Label album_comment_label;

    private PermissionLevel[] perm_levels;
    private SizeEntry[] photo_sizes;

    public int last_category { private get; construct; }
    public int last_permission_level { private get; construct; }
    public int last_photo_size { private get; construct; }
    public bool last_title_as_comment { private get; construct; }
    public bool last_no_upload_tags { private get; construct; }
    public bool strip_metadata_enabled { private get; construct; }
    public Gee.List<Category> existing_categories { private get; construct; }
    public string default_comment { private get; construct; }

    public signal void publish(PublishingParameters parameters, bool strip_metadata);
    public signal void logout();

    public PublishingOptionsPane(PiwigoPublisher publisher,
                                 Category[] categories,
                                 int last_category,
                                 int last_permission_level,
                                 int last_photo_size,
                                 bool last_title_as_comment,
                                 bool last_no_upload_tags,
                                 bool strip_metadata_enabled) {
        Object (resource_path : Resources.RESOURCE_PATH +
                                "/piwigo_publishing_options_pane.ui",
                connect_signals : true,
                default_id : "publish_button",
                last_category : last_category,
                last_permission_level : last_permission_level,
                last_photo_size : last_photo_size,
                last_title_as_comment : last_title_as_comment,
                last_no_upload_tags : last_no_upload_tags,
                strip_metadata_enabled : strip_metadata_enabled,
                existing_categories : new Gee.ArrayList<Category>.wrap (categories,
                                                          Category.equal),
                default_comment : get_common_comment_if_possible (publisher));
    }

    public override void constructed () {
        base.constructed ();
        var builder = this.get_builder ();

        use_existing_radio = builder.get_object("use_existing_radio") as Gtk.RadioButton;
        create_new_radio = builder.get_object("create_new_radio") as Gtk.RadioButton;
        existing_categories_combo = builder.get_object("existing_categories_combo") as Gtk.ComboBoxText;
        new_category_entry = builder.get_object ("new_category_entry") as Gtk.Entry;
        within_existing_label = builder.get_object ("within_existing_label") as Gtk.Label;
        within_existing_combo = builder.get_object ("within_existing_combo") as Gtk.ComboBoxText;

        album_comment = builder.get_object ("album_comment") as Gtk.TextView;
        album_comment.buffer = new Gtk.TextBuffer(null);
        album_comment_label = builder.get_object ("album_comment_label") as Gtk.Label;

        perms_combo = builder.get_object("perms_combo") as Gtk.ComboBoxText;
        size_combo = builder.get_object("size_combo") as Gtk.ComboBoxText;

        strip_metadata_check = builder.get_object("strip_metadata_check") as Gtk.CheckButton;
        strip_metadata_check.set_active(strip_metadata_enabled);

        title_as_comment_check = builder.get_object("title_as_comment_check") as Gtk.CheckButton;
        title_as_comment_check.set_active(last_title_as_comment);

        no_upload_tags_check = builder.get_object("no_upload_tags_check") as Gtk.CheckButton;
        no_upload_tags_check.set_active(last_no_upload_tags);

        logout_button = builder.get_object("logout_button") as Gtk.Button;
        logout_button.clicked.connect(on_logout_button_clicked);

        publish_button = builder.get_object("publish_button") as Gtk.Button;
        publish_button.clicked.connect(on_publish_button_clicked);

        use_existing_radio.clicked.connect(on_use_existing_radio_clicked);
        create_new_radio.clicked.connect(on_create_new_radio_clicked);
        new_category_entry.changed.connect(on_new_category_entry_changed);
        within_existing_combo.changed.connect(on_existing_combo_changed);

        this.perm_levels = create_perm_levels();
        this.photo_sizes = create_sizes();
        this.album_comment.buffer.set_text(this.default_comment);
    }

    private PermissionLevel[] create_perm_levels() {
        PermissionLevel[] result = new PermissionLevel[0];

        result += new PermissionLevel(0, _("Everyone"));
        result += new PermissionLevel(1, _("Admins, Family, Friends, Contacts"));
        result += new PermissionLevel(2, _("Admins, Family, Friends"));
        result += new PermissionLevel(4, _("Admins, Family"));
        result += new PermissionLevel(8, _("Admins"));

        return result;
    }

    private SizeEntry[] create_sizes() {
        SizeEntry[] result = new SizeEntry[0];

        result += new SizeEntry(500, _("500 × 375 pixels"));
        result += new SizeEntry(1024, _("1024 × 768 pixels"));
        result += new SizeEntry(2048, _("2048 × 1536 pixels"));
        result += new SizeEntry(4096, _("4096 × 3072 pixels"));
        result += new SizeEntry(ORIGINAL_SIZE, _("Original size"));

        return result;
    }

    private void on_logout_button_clicked() {
        logout();
    }

    private void on_publish_button_clicked() {
        PublishingParameters params = new PublishingParameters();
        params.perm_level = perm_levels[perms_combo.get_active()];
        params.photo_size = photo_sizes[size_combo.get_active()];
        params.title_as_comment = title_as_comment_check.get_active();
        params.no_upload_tags = no_upload_tags_check.get_active();
        if (create_new_radio.get_active()) {
            string uploadcomment = album_comment.buffer.text.strip();
            int a = within_existing_combo.get_active();
            if (a == 0) {
                params.category = new Category.local(new_category_entry.get_text(), 0, uploadcomment);
            } else {
                // the list in existing_categories and in the within_existing_combo are shifted
                // by 1, since we add the root
                a--;
                params.category = new Category.local(new_category_entry.get_text(),
                    existing_categories[a].id, uploadcomment);
            }
        } else {
            params.category = existing_categories[existing_categories_combo.get_active()];
        }
        publish(params, strip_metadata_check.get_active());
    }
    
    // UI interaction
    private void on_use_existing_radio_clicked() {
        existing_categories_combo.set_sensitive(true);
        new_category_entry.set_sensitive(false);
        within_existing_label.set_sensitive(false);
        within_existing_combo.set_sensitive(false);
        existing_categories_combo.grab_focus();
        album_comment_label.set_sensitive(false);
        album_comment.set_sensitive(false);
        update_publish_button_sensitivity();
    }

    private void on_create_new_radio_clicked() {
        new_category_entry.set_sensitive(true);
        within_existing_label.set_sensitive(true);
        within_existing_combo.set_sensitive(true);
        album_comment_label.set_sensitive(true);
        album_comment.set_sensitive(true);
        existing_categories_combo.set_sensitive(false);
        new_category_entry.grab_focus();
        update_publish_button_sensitivity();
    }

    private void on_new_category_entry_changed() {
        update_publish_button_sensitivity();
    }

    private void on_existing_combo_changed() {
        update_publish_button_sensitivity();
    }

    private void update_publish_button_sensitivity() {
        string category_name = new_category_entry.get_text().strip();
        int a = within_existing_combo.get_active();
        string search_name;
        if (a <= 0) {
            search_name = "/ " + category_name;
        } else {
            a--;
            search_name = existing_categories[a].display_name + "/ " + category_name;
        }
        publish_button.set_sensitive(
            !(
                create_new_radio.get_active() &&
                (
                    category_name == "" ||
                    category_already_exists(search_name)
                )
            )
        );
    }

    public override void on_pane_installed() {
        base.on_pane_installed ();

        create_categories_combo();
        create_within_categories_combo();
        create_permissions_combo();
        create_size_combo();

        publish_button.can_default = true;
        update_publish_button_sensitivity();
    }

    private static string get_common_comment_if_possible(PiwigoPublisher publisher) {
        // we have to determine whether all the publishing items
        // belong to the same event
        Spit.Publishing.Publishable[] publishables = publisher.get_host().get_publishables();
        string common = "";
        bool isfirst = true;
        if (publishables != null) {
            foreach (Spit.Publishing.Publishable pub in publishables) {
                string? cur = pub.get_param_string(
                    Spit.Publishing.Publishable.PARAM_STRING_EVENTCOMMENT);
                if (cur == null) {
                    continue;
                }

                if (isfirst) {
                    common = cur;
                    isfirst = false;
                } else {
                    if (cur != common) {
                        common = "";
                        break;
                    }
                }
            }
        }
        debug("PiwigoConnector: found common event comment %s\n", common);
        return common;
    }

    private void create_categories_combo() {
        foreach (Category cat in existing_categories) {
            existing_categories_combo.append_text(cat.display_name);
        }
        if (existing_categories.is_empty) {
            // if no existing categories, disable the option to choose one
            existing_categories_combo.set_sensitive(false);
            use_existing_radio.set_sensitive(false);
            create_new_radio.set_active(true);
            album_comment.set_sensitive(true);
            album_comment_label.set_sensitive(true);
            new_category_entry.grab_focus();
        } else {
            int last_category_index = find_category_index(last_category);
            existing_categories_combo.set_active(last_category_index);
            new_category_entry.set_sensitive(false);
            album_comment.set_sensitive(false);
            album_comment_label.set_sensitive(false);
        }
        if (!category_already_exists(DEFAULT_CATEGORY_NAME))
            new_category_entry.set_text(DEFAULT_CATEGORY_NAME);
    }

    private void create_within_categories_combo() {
        // root menu
        within_existing_combo.append_text("/ ");
        foreach (Category cat in existing_categories) {
            within_existing_combo.append_text(cat.display_name);
        }
        // by default select root album as target
        within_existing_label.set_sensitive(false);
        within_existing_combo.set_active(0);
        within_existing_combo.set_sensitive(false);
    }
    
    private void create_permissions_combo() {
        foreach (PermissionLevel perm in perm_levels) {
            perms_combo.append_text(perm.name);
        }
        int last_permission_level_index = find_permission_level_index(last_permission_level);
        if (last_permission_level_index < 0) {
            perms_combo.set_active(0);
        } else {
            perms_combo.set_active(last_permission_level_index);
        }
    }
    
    private void create_size_combo() {
        foreach (SizeEntry size in photo_sizes) {
            size_combo.append_text(size.name);
        }
        int last_size_index = find_size_index(last_photo_size);
        if (last_size_index < 0) {
            size_combo.set_active(find_size_index(ORIGINAL_SIZE));
        } else {
            size_combo.set_active(last_size_index);
        }
    }

    private int find_category_index(int category_id) {
        int result = 0;
        for(int i = 0; i < existing_categories.size; i++) {
            if (existing_categories[i].id == category_id) {
                result = i;
                break;
            }
        }
        return result;
    }
    
    private int find_permission_level_index(int permission_level_id) {
        int result = -1;
        for(int i = 0; i < perm_levels.length; i++) {
            if (perm_levels[i].id == permission_level_id) {
                result = i;
                break;
            }
        }
        return result;
    }
    
    private int find_size_index(int size_id) {
        int result = -1;
        for(int i = 0; i < photo_sizes.length; i++) {
            if (photo_sizes[i].id == size_id) {
                result = i;
                break;
            }
        }
        return result;
    }
    
    private bool category_already_exists(string category_name) {
        bool result = false;
        foreach(Category category in existing_categories) {
            if (category.display_name.strip() == category_name) {
                result = true;
                break;
            }
        }
        return result;
    }
}

// REST support classes

/**
 * Session class that keeps track of the authentication status and of the
 * user token pwg_id.
 */
internal class Session : Publishing.RESTSupport.Session {
    private string? pwg_url = null;
    private string? pwg_id = null;
    private string? username = null;

    public Session() {
        base("");
    }

    public override bool is_authenticated() {
        return (pwg_id != null && pwg_url != null && username != null);
    }

    public void authenticate(string url, string username, string id) {
        this.pwg_url = url;
        this.username = username;
        this.pwg_id = id;
    }

    public void deauthenticate() {
        pwg_url = null;
        pwg_id = null;
        username = null;
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

/**
 * Generic REST transaction class.
 *
 * This class implements the generic logic for all REST transactions used
 * by the Piwigo publishing plugin. In particular, it ensures that if the
 * session has been authenticated, the pwg_id token is included in the
 * transaction header.
 */
internal class Transaction : Publishing.RESTSupport.Transaction {
    public Transaction(Session session) {
        base(session);
        if (session.is_authenticated()) {
            add_header("Cookie", "pwg_id=".concat(session.get_pwg_id()));
        }
    }

    public Transaction.authenticated(Session session) {
        base.with_endpoint_url(session, session.get_pwg_url());
        add_header("Cookie", "pwg_id=".concat(session.get_pwg_id()));
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
        
        return "%s (error code %s)".printf(errcode->get_prop("msg"), errcode->get_prop("code"));
    }

    public static new string? get_error_code(Publishing.RESTSupport.XmlDocument doc) {
        Xml.Node* root = doc.get_root_node();
        Xml.Node* errcode;
        try {
            errcode = doc.get_named_child(root, "err");
        } catch (Spit.Publishing.PublishingError err) {
            return "0";
        }
        return errcode->get_prop("code");
    }
}

/**
 * Transaction used to implement the network login interaction.
 */
internal class SessionLoginTransaction : Transaction {
    public SessionLoginTransaction(Session session, string url, string username, string password) {
        base.with_endpoint_url(session, url);

        add_argument("method", "pwg.session.login");
        add_argument("username", Uri.escape_string(username));
        add_argument("password", Uri.escape_string(password));
    }

    public SessionLoginTransaction.from_other (Session session, Transaction other) {
        base.with_endpoint_url (session, other.get_endpoint_url ());

        foreach (var argument in other.get_arguments ()) {
            add_argument (argument.key, argument.value);
        }
    }
}

/**
 * Transaction used to implement the get status interaction.
 */
internal class SessionGetStatusTransaction : Transaction {
    public SessionGetStatusTransaction.unauthenticated(Session session, string url, string pwg_id) {
        base.with_endpoint_url(session, url);
        add_header("Cookie", "pwg_id=".concat(session.get_pwg_id()));

        add_argument("method", "pwg.session.getStatus");
    }

    public SessionGetStatusTransaction(Session session) {
        base.authenticated(session);

        add_argument("method", "pwg.session.getStatus");
    }
}

/**
 * Transaction used to implement the fetch categories interaction.
 */
private class CategoriesGetListTransaction : Transaction {
    public CategoriesGetListTransaction(Session session) {
        base.authenticated(session);
        
        add_argument("method", "pwg.categories.getList");
        add_argument("recursive", "true");
    }
}

private class SessionLogoutTransaction : Transaction {
    public SessionLogoutTransaction(Session session) {
        base.authenticated(session);
      
        add_argument("method", "pwg.session.logout");
    }
}

private class CategoriesAddTransaction : Transaction {
    public CategoriesAddTransaction(Session session, string category, int parent_id = 0, string? comment = "") {
        base.authenticated(session);

        add_argument("method", "pwg.categories.add");
        add_argument("name", category);

        if (parent_id != 0) {
            add_argument("parent", parent_id.to_string());
        }

        if (comment != "") {
            add_argument("comment", comment);
        }
    }
}

private class ImagesAddTransaction : Publishing.RESTSupport.UploadTransaction {
    private PublishingParameters parameters = null;

    public ImagesAddTransaction(Session session, PublishingParameters parameters, Spit.Publishing.Publishable publishable) {
        base.with_endpoint_url(session, publishable, session.get_pwg_url());
        if (session.is_authenticated()) {
            add_header("Cookie", "pwg_id=".concat(session.get_pwg_id()));
        }
        this.parameters = parameters;

        string[] keywords = publishable.get_publishing_keywords();
        string tags = "";
        if (keywords != null) {
            tags = string.joinv (",", keywords);
        }
        
        debug("PiwigoConnector: Uploading photo %s to category id %d with perm level %d",
            publishable.get_serialized_file().get_basename(),
            parameters.category.id, parameters.perm_level.id);
        string name = publishable.get_publishing_name();
        string comment = publishable.get_param_string(
            Spit.Publishing.Publishable.PARAM_STRING_COMMENT);
        if (name == null || name == "") {
            name = publishable.get_param_string(
                Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
            add_argument("name", name);
            if (comment != null && comment != "") {
                add_argument("comment", comment);
            }
        } else {
            // name is set
            if (comment != null && comment != "") {
                add_argument("name", name);
                add_argument("comment", comment);
            } else {
                // name is set, comment is unset
                // for backward compatibility with people having used 
                // the title as comment field, keep this option
                if (parameters.title_as_comment) {
                    add_argument("comment", name);
                } else {
                    add_argument("name", name);
                }
            }
        }
        add_argument("method", "pwg.images.addSimple");
        add_argument("category", parameters.category.id.to_string());
        add_argument("level", parameters.perm_level.id.to_string());
        if (!parameters.no_upload_tags)
            if (tags != "")
                add_argument("tags", tags);
        // TODO: update the Publishable interface so that it gives access to
        // the image's meta-data where the author (artist) is kept
        /*if (!is_string_empty(author))
            add_argument("author", author);*/
        
        // TODO: implement description in APIGlue
        /*if (!is_string_empty(publishable.get_publishing_description()))
            add_argument("comment", publishable.get_publishing_description());*/

        GLib.HashTable<string, string> disposition_table =
            new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
        var basename = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        if (!basename.down().has_suffix(".jpeg") &&
            !basename.down().has_suffix(".jpg")) {
            basename += ".jpg";
        }
        disposition_table.insert("filename",  Soup.URI.encode(basename, null));
        disposition_table.insert("name", "image");

        set_binary_disposition_table(disposition_table);
    }
}

} // namespace

