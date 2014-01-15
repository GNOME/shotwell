/* Copyright 2012 BJA Electronics
 * Author: Jeroen Arnoldus (b.j.arnoldus@bja-electronics.nl)
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


extern string hmac_sha1(string key, string message);
public class TumblrService : Object, Spit.Pluggable, Spit.Publishing.Service {
   private const string ICON_FILENAME = "tumblr.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;
    
    public TumblrService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_icon_set(resource_directory.get_child(ICON_FILENAME));
    }

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.tumblr";
    }
    
    public unowned string get_pluggable_name() {
        return "Tumblr";
    }
    
    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Jeroen Arnoldus";
        info.copyright = _("Copyright 2012 BJA Electronics");
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
        return new Publishing.Tumblr.TumblrPublisher(this, host);
    }
    
    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO |
            Spit.Publishing.Publisher.MediaType.VIDEO);
    }
}

namespace Publishing.Tumblr {

internal const string SERVICE_NAME = "Tumblr";
internal const string ENDPOINT_URL = "http://www.tumblr.com/";
internal const string API_KEY = "NdXvXQuKVccOsCOj0H4k9HUJcbcjDBYSo2AkaHzXFECHGNuP9k";
internal const string API_SECRET = "BN0Uoig0MwbeD27OgA0IwYlp3Uvonyfsrl9pf1cnnMj1QoEUvi";
internal const string ENCODE_RFC_3986_EXTRA = "!*'();:@&=+$,/?%#[] \\";
internal const int ORIGINAL_SIZE = -1;



private class BlogEntry {
   public string blog;
   public string url;
   public BlogEntry(string creator_blog, string creator_url) {
     blog = creator_blog;
     url = creator_url;
   }
}

private class SizeEntry {
   public string title;
   public int size;

   public SizeEntry(string creator_title, int creator_size) {
     title = creator_title;
     size = creator_size;
   }
}

public class TumblrPublisher : Spit.Publishing.Publisher, GLib.Object {
    private Spit.Publishing.Service service;
    private Spit.Publishing.PluginHost host;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private bool running = false;
    private bool was_started = false;
    private Session session = null;
    private PublishingOptionsPane publishing_options_pane = null;
    private SizeEntry[] sizes = null;
    private BlogEntry[] blogs = null;
	private string username = "";

    
    private SizeEntry[] create_sizes() {
        SizeEntry[] result = new SizeEntry[0];

        result += new SizeEntry(_("500 x 375 pixels"), 500);
        result += new SizeEntry(_("1024 x 768 pixels"), 1024);
        result += new SizeEntry(_("1280 x 853 pixels"), 1280);
//Larger images make no sense for Tumblr
//        result += new SizeEntry(_("2048 x 1536 pixels"), 2048);
//        result += new SizeEntry(_("4096 x 3072 pixels"), 4096);
//        result += new SizeEntry(_("Original size"), ORIGINAL_SIZE);

        return result;
    }

    private BlogEntry[] create_blogs() {
        BlogEntry[] result = new BlogEntry[0];


        return result;
    }

    public TumblrPublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        debug("TumblrPublisher instantiated.");
        this.service = service;
        this.host = host;
        this.session = new Session();
		this.sizes = this.create_sizes();
		this.blogs = this.create_blogs();
        session.authenticated.connect(on_session_authenticated);
    }
    
    ~TumblrPublisher() {
        session.authenticated.disconnect(on_session_authenticated);
    }
    
    private void invalidate_persistent_session() {
        set_persistent_access_phase_token("");
        set_persistent_access_phase_token_secret("");
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

    private bool is_persistent_session_valid() {
        string? access_phase_token = get_persistent_access_phase_token();
        string? access_phase_token_secret = get_persistent_access_phase_token_secret();

        bool valid = ((access_phase_token != null) && (access_phase_token_secret != null));

        if (valid)
            debug("existing Tumblr session found in configuration database; using it.");
        else
            debug("no persisted Tumblr session exists.");

        return valid;
    }




    public string? get_persistent_access_phase_token() {
        return host.get_config_string("token", null);
    }
    
    private void set_persistent_access_phase_token(string? token) {
        host.set_config_string("token", token);
    } 
    
    public string? get_persistent_access_phase_token_secret() {
        return host.get_config_string("token_secret", null);
    }
    
    private void set_persistent_access_phase_token_secret(string? token_secret) {
        host.set_config_string("token_secret", token_secret);
    } 

    internal int get_persistent_default_size() {
        return host.get_config_int("default_size", 1);
    }
    
    internal void set_persistent_default_size(int size) {
        host.set_config_int("default_size", size);
    }

    internal int get_persistent_default_blog() {
        return host.get_config_int("default_blog", 0);
    }
    
    internal void set_persistent_default_blog(int blog) {
        host.set_config_int("default_blog", blog);
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

    /**
     * Event triggered when the login button in the authentication panel is
     * clicked.
     *
     * This event is triggered when the login button in the authentication
     * panel is clicked. It then triggers a network login interaction.
     *
     * @param username the name of the Tumblr user as entered in the dialog
     * @param password the password of the Tumblr as entered in the dialog
     */
    private void on_authentication_pane_login_clicked( string username, string password ) {
        debug("EVENT: on_authentication_pane_login_clicked");
        if (!running)
            return;

        do_network_login(username, password); 
    }
    
    /**
     * Action to perform a network login to a Tumblr blog.
     *
     * This action performs a network login a Tumblr blog specified the given user name and password as credentials.
     *
     * @param username the name of the Tumblr user used to login
     * @param password the password of the Tumblr user used to login
     */
    private void do_network_login(string username, string password) {
        debug("ACTION: logging in");
        host.set_service_locked(true);
        host.install_login_wait_pane();
        

        AccessTokenFetchTransaction txn = new AccessTokenFetchTransaction(session,username,password);
        txn.completed.connect(on_auth_request_txn_completed);
        txn.network_error.connect(on_auth_request_txn_error);
       
        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }
      

    private void on_auth_request_txn_completed(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_auth_request_txn_completed);
        txn.network_error.disconnect(on_auth_request_txn_error);

        if (!is_running())
            return;

        debug("EVENT: OAuth authentication request transaction completed; response = '%s'",
            txn.get_response());

        do_parse_token_info_from_auth_request(txn.get_response());
    }

    private void on_auth_request_txn_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_auth_request_txn_completed);
        txn.network_error.disconnect(on_auth_request_txn_error);

        if (!is_running())
            return;

        debug("EVENT: OAuth authentication request transaction caused a network error");
        host.post_error(err);
    }


    private void do_parse_token_info_from_auth_request(string response) {
        debug("ACTION: parsing authorization request response '%s' into token and secret", response);
        
        string? oauth_token = null;
        string? oauth_token_secret = null;
        
        string[] key_value_pairs = response.split("&");
        foreach (string pair in key_value_pairs) {
            string[] split_pair = pair.split("=");
            
            if (split_pair.length != 2)
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    _("'%s' isn't a valid response to an OAuth authentication request")));

            if (split_pair[0] == "oauth_token")
                oauth_token = split_pair[1];
            else if (split_pair[0] == "oauth_token_secret")
                oauth_token_secret = split_pair[1];
        }
        
        if (oauth_token == null || oauth_token_secret == null)
            host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                _("'%s' isn't a valid response to an OAuth authentication request")));
        
        session.set_access_phase_credentials(oauth_token, oauth_token_secret);
    }



    private void on_session_authenticated() {
        if (!is_running())
            return;

        debug("EVENT: a fully authenticated session has become available");             
        set_persistent_access_phase_token(session.get_access_phase_token());
        set_persistent_access_phase_token_secret(session.get_access_phase_token_secret());
		do_get_blogs();

}

    private void do_get_blogs() {
        debug("ACTION: obtain all blogs of the tumblr user");
        UserInfoFetchTransaction txn = new UserInfoFetchTransaction(session);
        txn.completed.connect(on_info_request_txn_completed);
        txn.network_error.connect(on_info_request_txn_error);
       
        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }


    }


    private void on_info_request_txn_completed(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_info_request_txn_completed);
        txn.network_error.disconnect(on_info_request_txn_error);

        if (!is_running())
            return;

        debug("EVENT: user info request transaction completed; response = '%s'",
            txn.get_response());
        do_parse_token_info_from_user_request(txn.get_response());
        do_show_publishing_options_pane();
    }


    private void do_parse_token_info_from_user_request(string response) {
        debug("ACTION: parsing info request response '%s' into list of available blogs", response);
        try {
			var parser = new Json.Parser();
			parser.load_from_data (response, -1);
			var root_object = parser.get_root().get_object();
			this.username = root_object.get_object_member("response").get_object_member("user").get_string_member ("name");
			debug("Got user name: %s",username);
		    foreach (var blognode in root_object.get_object_member("response").get_object_member("user").get_array_member("blogs").get_elements ()) {
		        var blog = blognode.get_object ();
				string name = blog.get_string_member ("name");
				string url = blog.get_string_member ("url").replace("http://","").replace("/","");
		        debug("Got blog name: %s and url: %s", name, url);
		        this.blogs += new BlogEntry(name,url);
		    }
		} catch (Error err) {
        	host.post_error(err);
    	}
    }

    private void on_info_request_txn_error(Publishing.RESTSupport.Transaction txn,
        Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_info_request_txn_completed);
        txn.network_error.disconnect(on_info_request_txn_error);

        if (!is_running())
            return;

        session.deauthenticate();
        invalidate_persistent_session();
        debug("EVENT: user info request transaction caused a network error");
        host.post_error(err);
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: displaying publishing options pane");
        host.set_service_locked(false);
        PublishingOptionsPane publishing_options_pane =
            new PublishingOptionsPane(this, host.get_publishable_media_type(), this.sizes, this.blogs, this.username);
        publishing_options_pane.publish.connect(on_publishing_options_pane_publish);
        publishing_options_pane.logout.connect(on_publishing_options_pane_logout);
        host.install_dialog_pane(publishing_options_pane);
    }



    private void on_publishing_options_pane_publish() {
        if (publishing_options_pane != null) {
            publishing_options_pane.publish.disconnect(on_publishing_options_pane_publish);
            publishing_options_pane.logout.disconnect(on_publishing_options_pane_logout);
        }
        
        if (!is_running())
            return;

        debug("EVENT: user clicked the 'Publish' button in the publishing options pane");
        do_publish();
    }

    private void on_publishing_options_pane_logout() {
        if (publishing_options_pane != null) {
            publishing_options_pane.publish.disconnect(on_publishing_options_pane_publish);
            publishing_options_pane.logout.disconnect(on_publishing_options_pane_logout);
        }

        if (!is_running())
            return;

        debug("EVENT: user clicked the 'Logout' button in the publishing options pane");

        do_logout();
    }

    public static int tumblr_date_time_compare_func(Spit.Publishing.Publishable a, 
        Spit.Publishing.Publishable b) {
        return a.get_exposure_date_time().compare(b.get_exposure_date_time());
    }

    private void do_publish() {
        debug("ACTION: uploading media items to remote server.");

        host.set_service_locked(true);

        progress_reporter = host.serialize_publishables(sizes[get_persistent_default_size()].size);

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
	    	debug("ACTION: add publishable");
            sorted_list.add(p);
        }
        sorted_list.sort(tumblr_date_time_compare_func);
		string blog_url = this.blogs[get_persistent_default_blog()].url;
    
        Uploader uploader = new Uploader(session, sorted_list.to_array(),blog_url);
        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);
        uploader.upload(on_upload_status_updated);
    }

    private void do_show_success_pane() {
        debug("ACTION: showing success pane.");

        host.set_service_locked(false);
        host.install_success_pane();
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


    private void do_logout() {
        debug("ACTION: logging user out, deauthenticating session, and erasing stored credentials");

        session.deauthenticate();
        invalidate_persistent_session();

        running = false;

        attempt_start();
    } 

    public void attempt_start() {
        if (is_running())
            return;
        
        debug("TumblrPublisher: starting interaction.");
        
        running = true;
        if (is_persistent_session_valid()) {
            debug("attempt start: a persistent session is available; using it");

            session.authenticate_from_persistent_credentials(get_persistent_access_phase_token(),
                get_persistent_access_phase_token_secret());
        } else {
            debug("attempt start: no persistent session available; showing login welcome pane");

            do_show_authentication_pane();
        }
    }

    public void start() {
        if (is_running())
            return;
        
        if (was_started)
            error(_("TumblrPublisher: start( ): can't start; this publisher is not restartable."));
        
        debug("TumblrPublisher: starting interaction.");
        
        attempt_start();
    }
    
    public void stop() {
        debug("TumblrPublisher: stop( ) invoked.");

//        if (session != null)
//            session.stop_transactions();

        running = false;
    }


// UI elements

/**
 * The authentication pane used when asking service URL, user name and password
 * from the user.
 */
internal class AuthenticationPane : Spit.Publishing.DialogPane, Object {
    public enum Mode {
        INTRO,
        FAILED_RETRY_USER
    }
    private static string INTRO_MESSAGE = _("Enter the username and password associated with your Tumblr account.");
    private static string FAILED_RETRY_USER_MESSAGE = _("Username and/or password invalid. Please try again");

    private Gtk.Box pane_widget = null;
    private Gtk.Builder builder;
    private Gtk.Entry username_entry;
    private Gtk.Entry password_entry;
    private Gtk.Button login_button;

    public signal void login(string user, string password);

    public AuthenticationPane(TumblrPublisher publisher, Mode mode = Mode.INTRO) {
        this.pane_widget = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

        File ui_file = publisher.get_host().get_module_file().get_parent().
            get_child("tumblr_authentication_pane.glade");
        
        try {
            builder = new Gtk.Builder();
            builder.add_from_file(ui_file.get_path());
            builder.connect_signals(null);
            Gtk.Alignment align = builder.get_object("alignment") as Gtk.Alignment;
            
            Gtk.Label message_label = builder.get_object("message_label") as Gtk.Label;
            switch (mode) {
                case Mode.INTRO:
                    message_label.set_text(INTRO_MESSAGE);
                    break;

                case Mode.FAILED_RETRY_USER:
                    message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                        "Invalid User Name or Password"), FAILED_RETRY_USER_MESSAGE));
                    break;
            }

            username_entry = builder.get_object ("username_entry") as Gtk.Entry;

            password_entry = builder.get_object ("password_entry") as Gtk.Entry;
    


            login_button = builder.get_object("login_button") as Gtk.Button;

            username_entry.changed.connect(on_user_changed);
            password_entry.changed.connect(on_password_changed);
            login_button.clicked.connect(on_login_button_clicked);

            align.reparent(pane_widget);
            publisher.get_host().set_dialog_default_widget(login_button);
        } catch (Error e) {
            warning(_("Could not load UI: %s"), e.message);
        }
    }
    
    public Gtk.Widget get_default_widget() {
        return login_button;
    }

    private void on_login_button_clicked() {
        login(username_entry.get_text(),
            password_entry.get_text());
    }


    private void on_user_changed() {
        update_login_button_sensitivity();
    }

    private void on_password_changed() {
        update_login_button_sensitivity();
    }
    
    private void update_login_button_sensitivity() {
        login_button.set_sensitive(
            !is_string_empty(username_entry.get_text()) &&
            !is_string_empty(password_entry.get_text())
        );
    }
    
    public Gtk.Widget get_widget() {
        return pane_widget;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }
    
    public void on_pane_installed() {
        username_entry.grab_focus();
        password_entry.set_activates_default(true);
        login_button.can_default = true;
        update_login_button_sensitivity();
    }
    
    public void on_pane_uninstalled() {
    }
}


/**
 * The publishing options pane.
 */


internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {



    private Gtk.Builder builder;
    private Gtk.Box pane_widget = null;
    private Gtk.Label upload_info_label = null;
    private Gtk.Label size_label = null;
    private Gtk.Label blog_label = null;
    private Gtk.Button logout_button = null;
    private Gtk.Button publish_button = null;
    private Gtk.ComboBoxText size_combo = null;
    private Gtk.ComboBoxText blog_combo = null;
    private SizeEntry[] sizes = null;
    private BlogEntry[] blogs = null;
	private string username = "";
    private TumblrPublisher publisher = null;
    private Spit.Publishing.Publisher.MediaType media_type;

    public signal void publish();
    public signal void logout();

    public PublishingOptionsPane(TumblrPublisher publisher, Spit.Publishing.Publisher.MediaType media_type, SizeEntry[] sizes, BlogEntry[] blogs, string username) {

        this.pane_widget = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		this.username = username;
		this.publisher = publisher;
		this.media_type = media_type;
		this.sizes = sizes;
		this.blogs=blogs;
        File ui_file = publisher.get_host().get_module_file().get_parent().
            get_child("tumblr_publishing_options_pane.glade");
        
        try {
			builder = new Gtk.Builder();
			builder.add_from_file(ui_file.get_path());
			builder.connect_signals(null);

			// pull in the necessary widgets from the glade file
			pane_widget = (Gtk.Box) this.builder.get_object("tumblr_pane");
			upload_info_label = (Gtk.Label) this.builder.get_object("upload_info_label");
			logout_button = (Gtk.Button) this.builder.get_object("logout_button");
			publish_button = (Gtk.Button) this.builder.get_object("publish_button");
			size_combo = (Gtk.ComboBoxText) this.builder.get_object("size_combo");
			size_label = (Gtk.Label) this.builder.get_object("size_label");
			blog_combo = (Gtk.ComboBoxText) this.builder.get_object("blog_combo");
			blog_label = (Gtk.Label) this.builder.get_object("blog_label");


			string upload_label_text = _("You are logged into Tumblr as %s.\n\n").printf(this.username);
			upload_info_label.set_label(upload_label_text);

			populate_blog_combo();
			blog_combo.changed.connect(on_blog_changed);

			if ((media_type != Spit.Publishing.Publisher.MediaType.VIDEO)) {
				populate_size_combo();
				size_combo.changed.connect(on_size_changed);
			} else {
			// publishing -only- video - don't let the user manipulate the photo size choices.
				size_combo.set_sensitive(false);
				size_label.set_sensitive(false);
			}

			logout_button.clicked.connect(on_logout_clicked);
			publish_button.clicked.connect(on_publish_clicked);
        } catch (Error e) {
			warning(_("Could not load UI: %s"), e.message);
        }
    }





    private void on_logout_clicked() {
        logout();
    }

    private void on_publish_clicked() {


        publish();
    }


    private void populate_blog_combo() {
        if (blogs != null) {
          foreach (BlogEntry b in blogs)
            blog_combo.append_text(b.blog);
          blog_combo.set_active(publisher.get_persistent_default_blog());
		}
    }

    private void on_blog_changed() {
        publisher.set_persistent_default_blog(blog_combo.get_active());
    }

    private void populate_size_combo() {
        if (sizes != null) {
          foreach (SizeEntry e in sizes)
            size_combo.append_text(e.title);
          size_combo.set_active(publisher.get_persistent_default_size());
		}
    }

    private void on_size_changed() {
        publisher.set_persistent_default_size(size_combo.get_active());
    }


    protected void notify_publish() {
        publish();
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


// REST support classes
internal class Transaction : Publishing.RESTSupport.Transaction {
    public Transaction(Session session, Publishing.RESTSupport.HttpMethod method =
        Publishing.RESTSupport.HttpMethod.POST) {
        base(session, method);
        
    }

    public Transaction.with_uri(Session session, string uri,
        Publishing.RESTSupport.HttpMethod method = Publishing.RESTSupport.HttpMethod.POST) {
        base.with_endpoint_url(session, uri, method);

        add_argument("oauth_nonce", session.get_oauth_nonce());
        add_argument("oauth_signature_method", "HMAC-SHA1");
        add_argument("oauth_version", "1.0");
        add_argument("oauth_timestamp", session.get_oauth_timestamp());
        add_argument("oauth_consumer_key", API_KEY);
		if (session.get_access_phase_token() != null) {
            add_argument("oauth_token", session.get_access_phase_token());
        }
    } 

    public override void execute() throws Spit.Publishing.PublishingError {
        ((Session) get_parent_session()).sign_transaction(this);
        
        base.execute();
    }

}


internal class AccessTokenFetchTransaction : Transaction {
    public AccessTokenFetchTransaction(Session session, string username, string password) {
        base.with_uri(session, "https://www.tumblr.com/oauth/access_token",
            Publishing.RESTSupport.HttpMethod.POST);
        add_argument("x_auth_username", Soup.URI.encode(username, ENCODE_RFC_3986_EXTRA));
        add_argument("x_auth_password", password);
        add_argument("x_auth_mode", "client_auth");
    }
}

internal class UserInfoFetchTransaction : Transaction {
    public UserInfoFetchTransaction(Session session) {
        base.with_uri(session, "http://api.tumblr.com/v2/user/info",
            Publishing.RESTSupport.HttpMethod.POST);
    }
}


internal class UploadTransaction : Publishing.RESTSupport.UploadTransaction {
    private Session session;
    private Publishing.RESTSupport.Argument[] auth_header_fields;


//Workaround for Soup.URI.encode() to support binary data (i.e. string with \0) 
    private string encode( uint8[] data ){
	var s = new StringBuilder();
	char[] bytes = new char[2];
	bytes[1] = 0;
        foreach( var byte in data )
        {
	   if(byte == 0) {
                s.append( "%00" );
	   } else { 
		bytes[0] = (char)byte;
		s.append( Soup.URI.encode((string) bytes, ENCODE_RFC_3986_EXTRA) );
	   }
        }
	return s.str;
    }


    public UploadTransaction(Session session,Spit.Publishing.Publishable publishable, string blog_url)  {
		debug("Init upload transaction");
        base.with_endpoint_url(session, publishable,"http://api.tumblr.com/v2/blog/%s/post".printf(blog_url) );
        this.session = session;

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
        add_authorization_header_field("oauth_nonce", session.get_oauth_nonce());
        add_authorization_header_field("oauth_signature_method", "HMAC-SHA1");
        add_authorization_header_field("oauth_version", "1.0");
        add_authorization_header_field("oauth_timestamp", session.get_oauth_timestamp());
        add_authorization_header_field("oauth_consumer_key", API_KEY);
        add_authorization_header_field("oauth_token", session.get_access_phase_token());


        string payload;
        size_t payload_length;
        try {
            FileUtils.get_contents(base.publishable.get_serialized_file().get_path(), out payload,
		            out payload_length);

			string reqdata = this.encode(payload.data[0:payload_length]);



			add_argument("data[0]", reqdata);
			add_argument("type", "photo");
			string[] keywords = base.publishable.get_publishing_keywords();
			string tags = "";
			if (keywords != null) {
				foreach (string tag in keywords) {
				if (!is_string_empty(tags)) {
					tags += ",";
				}
				tags += tag;
				}
			}
			add_argument("tags", Soup.URI.encode(tags, ENCODE_RFC_3986_EXTRA));

        } catch (FileError e) {
            throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                _("A temporary file needed for publishing is unavailable"));

		}


        session.sign_transaction(this);
        
        string authorization_header = get_authorization_header_string();
        
        debug("executing upload transaction: authorization header string = '%s'",
            authorization_header);
        add_header("Authorization", authorization_header);
        
        Publishing.RESTSupport.Argument[] request_arguments = get_arguments();
        assert(request_arguments.length > 0);

		string request_data = "";
		for (int i = 0; i < request_arguments.length; i++) {
		        request_data += (request_arguments[i].key + "=" + request_arguments[i].value);
		        if (i < request_arguments.length - 1)
		            request_data += "&";
		 }
        Soup.Message outbound_message = new Soup.Message( "POST", get_endpoint_url());
		outbound_message.set_request("application/x-www-form-urlencoded", Soup.MemoryUse.COPY, request_data.data);

        // TODO: there must be a better way to iterate over a map
        Gee.MapIterator<string, string> i = base.message_headers.map_iterator();
        bool cont = i.next();
        while(cont) {
            outbound_message.request_headers.append(i.get_key(), i.get_value());
            cont = i.next();
        }
        set_message(outbound_message);
    
        set_is_executed(true);

        send();
    }
}



internal class Uploader : Publishing.RESTSupport.BatchUploader {
	private string blog_url = "";
    public Uploader(Session session, Spit.Publishing.Publishable[] publishables, string blog_url) {
        base(session, publishables);
		this.blog_url=blog_url;

    }
    

    protected override Publishing.RESTSupport.Transaction create_transaction(
        Spit.Publishing.Publishable publishable) {
		debug("Create upload transaction");
        return new UploadTransaction((Session) get_session(), get_current_publishable(), this.blog_url);

    }
}

/**
 * Session class that keeps track of the authentication status and of the
 * user token tumblr.
 */
internal class Session : Publishing.RESTSupport.Session {
    private string? access_phase_token = null;
    private string? access_phase_token_secret = null;


    public Session() {
        base(ENDPOINT_URL);
    }

    public override bool is_authenticated() {
        return (access_phase_token != null && access_phase_token_secret != null);
    }

    public void authenticate_from_persistent_credentials(string token, string secret) {
        this.access_phase_token = token;
        this.access_phase_token_secret = secret;

        
        authenticated();
    }
    
    public void deauthenticate() {
        access_phase_token = null;
        access_phase_token_secret = null;
    } 
    
    public void sign_transaction(Publishing.RESTSupport.Transaction txn) {
        string http_method = txn.get_method().to_string();
        
        debug("signing transaction with parameters:");
        debug("HTTP method = " + http_method);
		string? signing_key = null;
        if (access_phase_token_secret != null) {
            debug("access phase token secret available; using it as signing key");

            signing_key = API_SECRET + "&" + this.get_access_phase_token_secret();
        } else {
            debug("Access phase token secret not available; using API " +
                "key as signing key");

            signing_key = API_SECRET + "&";
        }


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


        string signature_base_string = http_method + "&" + Soup.URI.encode(
            txn.get_endpoint_url(), ENCODE_RFC_3986_EXTRA) + "&" +
            Soup.URI.encode(arguments_string, ENCODE_RFC_3986_EXTRA);

        debug("signature base string = '%s'", signature_base_string);
        debug("signing key = '%s'", signing_key);

        // compute the signature
        string signature = hmac_sha1(signing_key, signature_base_string);
        debug("signature = '%s'", signature);
        signature = Soup.URI.encode(signature, ENCODE_RFC_3986_EXTRA);

        debug("signature after RFC encode = '%s'", signature);

        if (upload_txn != null)
            upload_txn.add_authorization_header_field("oauth_signature", signature);
        else
            txn.add_argument("oauth_signature", signature);


    }
    
    public void set_access_phase_credentials(string token, string secret) {
        this.access_phase_token = token;
        this.access_phase_token_secret = secret;

        
        authenticated();
    } 

    public string get_access_phase_token() {
        return access_phase_token;
    }


    public string get_access_phase_token_secret() {
        return access_phase_token_secret;
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

}


} //class TumblrPublisher

} //namespace Publishing.Tumblr

