/* Copyright 2010+ Evgeniy Polyakov <zbr@ioremap.net>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class YandexService : Object, Spit.Pluggable, Spit.Publishing.Service {
    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface, Spit.Publishing.CURRENT_INTERFACE);
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.yandex-fotki";
    }
    
    public unowned string get_pluggable_name() {
        return "Yandex.Fotki";
    }
    
    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Evgeniy Polyakov <zbr@ioremap.net>";
        info.copyright = _("Copyright 2010+ Evgeniy Polyakov <zbr@ioremap.net>");
        info.translators = Resources.TRANSLATORS;
        info.version = _VERSION;
        info.website_name = _("Visit the Yandex.Fotki web site");
        info.website_url = "https://fotki.yandex.ru/";
        info.is_license_wordwrapped = false;
        info.license = Resources.LICENSE;
    }
    
    public Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host) {
        return new Publishing.Yandex.YandexPublisher(this, host);
    }

    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO);
    }
    
    public void activation(bool enabled) {
    }
}

namespace Publishing.Yandex {

internal const string SERVICE_NAME = "Yandex.Fotki";

private const string client_id = "52be4756dee3438792c831a75d7cd360";

internal class Transaction: Publishing.RESTSupport.Transaction {
    public Transaction.with_url(Session session, string url, Publishing.RESTSupport.HttpMethod method = Publishing.RESTSupport.HttpMethod.GET) {
        base.with_endpoint_url(session, url, method);
        add_headers();
    }
    
    private void add_headers() {
        if (((Session) get_parent_session()).is_authenticated()) {
            add_header("Authorization", "OAuth %s".printf(((Session) get_parent_session()).get_auth_token()));
            add_header("Connection", "close");
        }
    }
    
     public Transaction(Session session, Publishing.RESTSupport.HttpMethod method = Publishing.RESTSupport.HttpMethod.GET) {
        base(session, method);
        add_headers();
    }

    public void add_data(string type, string data) {
        set_custom_payload(data, type);
    }
}

internal class Session : Publishing.RESTSupport.Session {
    private string? auth_token = null;

    public Session() {
    }

    public override bool is_authenticated() {
        return (auth_token != null);
    }

    public void deauthenticate() {
        auth_token = null;
    }
    
    public void set_auth_token(string token) {
        this.auth_token = token;
    }

    public string? get_auth_token() {
        return auth_token;
    }
}

internal class WebAuthPane : Shotwell.Plugins.Common.WebAuthenticationPane {
    private Regex re;

    public signal void login_succeeded(string success_url);
    public signal void login_failed();

    public WebAuthPane(string login_url) {
        Object (login_uri : login_url,
                preferred_geometry :
                Spit.Publishing.DialogPane.GeometryOptions.RESIZABLE);
    }

    public override void constructed () {
        try {
            this.re = new Regex("(.*)#access_token=([a-zA-Z0-9]*)&");
        } catch (RegexError e) {
            assert_not_reached ();
        }

        this.get_view ().decide_policy.connect (on_decide_policy);
    }

    public override void on_page_load () { }

    private bool on_decide_policy (WebKit.PolicyDecision decision,
                                   WebKit.PolicyDecisionType type) {
        switch (type) {
            case WebKit.PolicyDecisionType.NAVIGATION_ACTION:
                WebKit.NavigationPolicyDecision n_decision = (WebKit.NavigationPolicyDecision) decision;
                WebKit.NavigationAction action = n_decision.navigation_action;
                string uri = action.get_request().uri;
                debug("Navigating to '%s'", uri);

                MatchInfo info = null;

                if (re.match(uri, 0, out info)) {
                    string access_token = info.fetch_all()[2];

                    debug("Load completed: %s", access_token);
                    this.set_cursor (Gdk.CursorType.LEFT_PTR);
                    if (access_token != null) {
                        login_succeeded(access_token);
                        decision.ignore();
                        break;
                    } else
                        login_failed();
                }
                decision.use();
                break;
            case WebKit.PolicyDecisionType.RESPONSE:
                decision.use();
                break;
            default:
                return false;
        }
        return true;
    }
}

internal class PublishOptions {
    public bool disable_comments = false;
    public bool hide_original = false;
    public string access_type;

    public string destination_album = null;
    public string destination_album_url = null;
}

internal class PublishingOptionsPane: Spit.Publishing.DialogPane, GLib.Object {
    private Gtk.Box box;
    private Gtk.Builder builder;
    private Gtk.Button logout_button;
    private Gtk.Button publish_button;
    private Gtk.ComboBoxText album_list;

    private weak PublishOptions options;

    public signal void publish();
    public signal void logout();

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }
    public void on_pane_installed() {
    }
    public void on_pane_uninstalled() {
    }
    public Gtk.Widget get_widget() {
        return box;
    }

    public PublishingOptionsPane(PublishOptions options, Gee.HashMap<string, string> list,
        Spit.Publishing.PluginHost host) {
        this.options = options;

        box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        
        try {
            builder = new Gtk.Builder();
            builder.add_from_resource (Resources.RESOURCE_PATH + "/yandex_publish_model.ui");

            builder.connect_signals(null);
            var content = builder.get_object ("content") as Gtk.Widget;

            album_list = builder.get_object ("album_list") as Gtk.ComboBoxText;
            foreach (string key in list.keys)
                album_list.append_text(key);
            
            album_list.set_active(0);

            publish_button = builder.get_object("publish_button") as Gtk.Button;
            logout_button = builder.get_object("logout_button") as Gtk.Button;

            publish_button.clicked.connect(on_publish_clicked);
            logout_button.clicked.connect(on_logout_clicked);

            content.parent.remove (content);
            box.pack_start (content, true, true, 0);
        } catch (Error e) {
            warning("Could not load UI: %s", e.message);
        }
    }
    
    private void on_logout_clicked() {
        logout();
    }

    private void on_publish_clicked() {
        options.destination_album = album_list.get_active_text();

        Gtk.CheckButton tmp = builder.get_object("hide_original_check") as Gtk.CheckButton;
        options.hide_original = tmp.active;

        tmp = builder.get_object("disable_comments_check") as Gtk.CheckButton;
        options.disable_comments = tmp.active;

        Gtk.ComboBoxText access_type = builder.get_object("access_type_list") as Gtk.ComboBoxText;
        options.access_type = access_type.get_active_text();

        publish();
    }
}

private class Uploader: Publishing.RESTSupport.BatchUploader {
    private weak PublishOptions options;

    public Uploader(Session session, PublishOptions options, Spit.Publishing.Publishable[] photos) {
        base(session, photos);
        
        this.options = options;
    }

    protected override Publishing.RESTSupport.Transaction create_transaction(Spit.Publishing.Publishable publishable) {
        debug("create transaction");
        return new UploadTransaction(((Session) get_session()), options, get_current_publishable());
    }
}

private class UploadTransaction: Transaction {
    public UploadTransaction(Session session, PublishOptions options, Spit.Publishing.Publishable photo) {
        base.with_url(session, options.destination_album_url, Publishing.RESTSupport.HttpMethod.POST);
        
        set_custom_payload("qwe", "image/jpeg", 1);

        debug("Uploading '%s' -> %s : %s", photo.get_publishing_name(), options.destination_album, options.destination_album_url);

        Soup.Multipart message_parts = new Soup.Multipart("multipart/form-data");
        message_parts.append_form_string("title", photo.get_publishing_name());
        message_parts.append_form_string("hide_original", options.hide_original.to_string());
        message_parts.append_form_string("disable_comments", options.disable_comments.to_string());
        message_parts.append_form_string("access", options.access_type.down());

        string photo_data;
        size_t data_length;

        try {
            FileUtils.get_contents(photo.get_serialized_file().get_path(), out photo_data, out data_length);
        } catch (GLib.FileError e) {
            critical("Failed to read data file '%s': %s", photo.get_serialized_file().get_path(), e.message);
        }

        int image_part_num = message_parts.get_length();

        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.COPY, photo_data.data[0:data_length]);
        message_parts.append_form_file("", photo.get_serialized_file().get_path(), "image/jpeg", bindable_data);

        unowned Soup.MessageHeaders image_part_header;
        unowned Soup.Buffer image_part_body;
        message_parts.get_part(image_part_num, out image_part_header, out image_part_body);

        GLib.HashTable<string, string> result = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
        result.insert("name", "image");
        result.insert("filename", "unused");

        image_part_header.set_content_disposition("form-data", result);

        Soup.Message outbound_message = Soup.Form.request_new_from_multipart(get_endpoint_url(), message_parts);
        outbound_message.request_headers.append("Authorization", ("OAuth %s").printf(session.get_auth_token()));
        outbound_message.request_headers.append("Connection", "close");
        set_message(outbound_message);
    }
}

public class YandexPublisher : Spit.Publishing.Publisher, GLib.Object {
    private weak Spit.Publishing.PluginHost host = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private weak Spit.Publishing.Service service = null;

    private string service_url = null;

    private Gee.HashMap<string, string> album_list = null;
    private PublishOptions options;

    private bool running = false;

    private WebAuthPane web_auth_pane = null;

    private Session session;

    public YandexPublisher(Spit.Publishing.Service service, Spit.Publishing.PluginHost host) {
        this.service = service;
        this.host = host;
        this.session = new Session();
        this.album_list = new Gee.HashMap<string, string>();
        this.options = new PublishOptions();
    }

    internal string? get_persistent_auth_token() {
        return host.get_config_string("auth_token", null);
    }
    
    internal void set_persistent_auth_token(string auth_token) {
        host.set_config_string("auth_token", auth_token);
    }

    internal void invalidate_persistent_session() {
        host.unset_config_key("auth_token");
    }
    
    internal bool is_persistent_session_available() {
        return (get_persistent_auth_token() != null);
    }

    public bool is_running() {
        return running;
    }
    
    public Spit.Publishing.Service get_service() {
        return service;
    }

    private new string? check_response(Publishing.RESTSupport.XmlDocument doc) {
        return null;
    }

    private void parse_album_entry(Xml.Node *e) throws Spit.Publishing.PublishingError {
        string title = null;
        string link = null;

        for (Xml.Node* c = e->children ; c != null; c = c->next) {
            if (c->name == "title")
                title = c->get_content();

            if ((c->name == "link") && (c->get_prop("rel") == "photos"))
                link = c->get_prop("href");

            if (title != null && link != null) {
                debug("Added album: '%s', link: %s", title, link);
                album_list.set(title, link);
                title = null;
                link = null;
                break;
            }
        }
    }
    
    public void parse_album_creation(string data) throws Spit.Publishing.PublishingError {
        Publishing.RESTSupport.XmlDocument doc = Publishing.RESTSupport.XmlDocument.parse_string(data, check_response);
        Xml.Node *root = doc.get_root_node();

        parse_album_entry(root);
    }

    public void parse_album_list(string data) throws Spit.Publishing.PublishingError {
        Publishing.RESTSupport.XmlDocument doc = Publishing.RESTSupport.XmlDocument.parse_string(data, check_response);
        Xml.Node *root = doc.get_root_node();

        for (Xml.Node *e = root->children ; e != null; e = e->next) {
            if (e->name != "entry")
                continue;

            parse_album_entry(e);
        }
    }

    private void album_creation_error(Publishing.RESTSupport.Transaction t, Spit.Publishing.PublishingError err) {
        t.completed.disconnect(album_creation_complete);
        t.network_error.disconnect(album_creation_error);

        warning("Album creation error: %s", err.message);
    }

    private void album_creation_complete(Publishing.RESTSupport.Transaction t) {
        t.completed.disconnect(album_creation_complete);
        t.network_error.disconnect(album_creation_error);

        try {
            parse_album_creation(t.get_response());
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
            return;
        }

        if (album_list.get(options.destination_album) != null)
            start_upload();
        else
            host.post_error(new Spit.Publishing.PublishingError.PROTOCOL_ERROR("Server did not create album"));
    }

    private void create_destination_album() {
        string album = options.destination_album;
        string data = "<entry xmlns=\"http://www.w3.org/2005/Atom\" xmlns:f=\"yandex:fotki\"><title>%s</title></entry>".printf(album);

        Transaction t = new Transaction.with_url(session, service_url, Publishing.RESTSupport.HttpMethod.POST);

        t.add_data("application/atom+xml; charset=utf-8; type=entry", data);

        t.completed.connect(album_creation_complete);
        t.network_error.connect(album_creation_error);
        
        try {
            t.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }

    private void on_upload_complete(Publishing.RESTSupport.BatchUploader uploader, int num_published) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        if (num_published == 0)
            host.post_error(new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(""));

        host.set_service_locked(false);

        host.install_success_pane();
    }
    
    private void on_upload_error(Publishing.RESTSupport.BatchUploader uploader, Spit.Publishing.PublishingError err) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        warning("Photo upload error: %s", err.message);
    }

    private void on_upload_status_updated(int file_number, double completed_fraction) {
        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);

        progress_reporter(file_number, completed_fraction);
    }

    private void start_upload() {
        host.set_service_locked(true);

        progress_reporter = host.serialize_publishables(0);

        options.destination_album_url = album_list.get(options.destination_album);
        Spit.Publishing.Publishable[] publishables = host.get_publishables();
        Uploader uploader = new Uploader(session, options, publishables);

        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);
        uploader.upload(on_upload_status_updated);
    }

    private void on_logout() {
        if (!is_running())
            return;

        session.deauthenticate();
        invalidate_persistent_session();

        running = false;

        start();
    }

    private void on_publish() {
        debug("Going to publish to '%s' : %s", options.destination_album, album_list.get(options.destination_album));
        if (album_list.get(options.destination_album) == null)
            create_destination_album();
        else
            start_upload();
    }

    public void service_get_album_list_error(Publishing.RESTSupport.Transaction t, Spit.Publishing.PublishingError err) {
        t.completed.disconnect(service_get_album_list_complete);
        t.network_error.disconnect(service_get_album_list_error);

        invalidate_persistent_session();
        warning("Failed to get album list: %s", err.message);
    }

    public void service_get_album_list_complete(Publishing.RESTSupport.Transaction t) {
        t.completed.disconnect(service_get_album_list_complete);
        t.network_error.disconnect(service_get_album_list_error);

        debug("service_get_album_list_complete: %s", t.get_response());
        try {
            parse_album_list(t.get_response());
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }

        PublishingOptionsPane publishing_options_pane = new PublishingOptionsPane(options, album_list,
            host);

        publishing_options_pane.publish.connect(on_publish);
        publishing_options_pane.logout.connect(on_logout);
        host.install_dialog_pane(publishing_options_pane);
    }

    public void service_get_album_list(string url) {
        service_url = url;

        Transaction t = new Transaction.with_url(session, url);
        t.completed.connect(service_get_album_list_complete);
        t.network_error.connect(service_get_album_list_error);

        try {
            t.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }

    public void fetch_account_error(Publishing.RESTSupport.Transaction t, Spit.Publishing.PublishingError err) {
        t.completed.disconnect(fetch_account_complete);
        t.network_error.disconnect(fetch_account_error);

        warning("Failed to fetch account info: %s", err.message);
    }

    public void fetch_account_complete(Publishing.RESTSupport.Transaction t) {
        t.completed.disconnect(fetch_account_complete);
        t.network_error.disconnect(fetch_account_error);

        debug("account info: %s", t.get_response());
        try {
            Publishing.RESTSupport.XmlDocument doc = Publishing.RESTSupport.XmlDocument.parse_string(t.get_response(), check_response);
            Xml.Node* root = doc.get_root_node();

            for (Xml.Node* work = root->children ; work != null; work = work->next) {
                if (work->name != "workspace")
                    continue;
                for (Xml.Node* c = work->children ; c != null; c = c->next) {
                    if (c->name != "collection")
                        continue;

                    if (c->get_prop("id") == "album-list") {
                        string url = c->get_prop("href");

                        set_persistent_auth_token(session.get_auth_token());
                        service_get_album_list(url);
                        break;
                    }
                }
            }
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }

    public void fetch_account_information(string auth_token) {
        session.set_auth_token(auth_token);

        Transaction t = new Transaction.with_url(session, "https://api-fotki.yandex.ru/api/me/");
        t.completed.connect(fetch_account_complete);
        t.network_error.connect(fetch_account_error);

        try {
            t.execute();
        } catch (Spit.Publishing.PublishingError err) {
            host.post_error(err);
        }
    }

    private void web_auth_login_succeeded(string access_token) {
        debug("login succeeded with token %s", access_token);

        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();

        fetch_account_information(access_token);
    }

    private void web_auth_login_failed() {
        debug("login failed");
    }

    private void start_web_auth() {
        host.set_service_locked(false);

        web_auth_pane = new WebAuthPane(("https://oauth.yandex.ru/authorize?client_id=%s&response_type=token").printf(client_id));
        web_auth_pane.login_succeeded.connect(web_auth_login_succeeded);
        web_auth_pane.login_failed.connect(web_auth_login_failed);

        host.install_dialog_pane(web_auth_pane, Spit.Publishing.PluginHost.ButtonMode.CANCEL);
    }

    private void show_welcome_page() {
        host.install_welcome_pane(_("You are not currently logged into Yandex.Fotki."),
            start_web_auth);
    }

    public void start() {
        if (is_running())
            return;

        if (host == null)
            error("YandexPublisher: start( ): can't start; this publisher is not restartable.");

        debug("YandexPublisher: starting interaction.");
        
        running = true;

        if (is_persistent_session_available()) {
            session.set_auth_token(get_persistent_auth_token());

            fetch_account_information(get_persistent_auth_token());
        } else {
            show_welcome_page();
        }
    }

    public void stop() {
        debug("YandexPublisher: stop( ) invoked.");

        host = null;
        running = false;
    }
}

}

