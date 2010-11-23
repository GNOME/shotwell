/* Copyright 2010+ Evgeniy Polyakov <zbr@ioremap.net>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

namespace YandexConnector {
    private const string SERVICE_NAME = "Yandex.Fotki";
    private const string SERVICE_WELCOME_MESSAGE = _("You are not currently logged into Yandex.Fotki.");
    
    private string client_id;
    private string auth_host;
    private string service_host;
    
    private string service_url;
    
    private class YandexLoginWelcomePane : PublishingDialogPane {
        private weak Interactor interactor;
        private Gtk.Button login_button;
        private Gtk.Entry username_entry;
        
        public signal void login_requested(string text);
        
        private void on_login_clicked() {
            login_requested(username_entry.text);
        }
        
        private void on_username_changed() {
            login_button.set_sensitive(username_entry.get_text() != "");
        }
        
        public YandexLoginWelcomePane(Interactor interactor, string service_welcome_message) {
            this.interactor = interactor;
            
            Gtk.SeparatorToolItem top_space = new Gtk.SeparatorToolItem();
            top_space.set_draw(false);
            Gtk.SeparatorToolItem bottom_space = new Gtk.SeparatorToolItem();
            bottom_space.set_draw(false);
            add(top_space);
            
            Gtk.Table content_layouter = new Gtk.Table(2, 1, false);
            
            Gtk.Label not_logged_in_label = new Gtk.Label("");
            not_logged_in_label.set_use_markup(true);
            not_logged_in_label.set_markup(service_welcome_message);
            not_logged_in_label.set_line_wrap(true);
            not_logged_in_label.set_size_request(PublishingDialog.STANDARD_CONTENT_LABEL_WIDTH, -1);
            content_layouter.attach(not_logged_in_label, 0, 1, 0, 1,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 0);
            not_logged_in_label.set_size_request(PublishingDialog.STANDARD_CONTENT_LABEL_WIDTH, 112);
            not_logged_in_label.set_alignment(0.5f, 0.0f);
            
            login_button = new Gtk.Button.with_mnemonic(_("_Login"));
            login_button.set_size_request(PublishingDialog.STANDARD_ACTION_BUTTON_WIDTH, -1);
            login_button.clicked.connect(on_login_clicked);
            
            username_entry = new Gtk.Entry();
            
            Gtk.Label username_label = new Gtk.Label.with_mnemonic(_("_Username:"));
            
            username_entry.changed.connect(on_username_changed);
            string username = YandexSession.load_username();
            if (username != null)
                username_entry.set_text(username);
            username_label.set_mnemonic_widget(username_entry);
            
            Gtk.HBox hbox = new Gtk.HBox(false, 20);
            hbox.pack_start(username_label, false, true, 0);
            hbox.pack_start(username_entry, false, true, 0);
            hbox.pack_start(login_button, false, true, 0);
            
            Gtk.Alignment login_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
            login_button_aligner.add(hbox);
            
            content_layouter.attach(login_button_aligner, 0, 1, 1, 2,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 0);
            add(content_layouter);
            
            add(bottom_space);
            bottom_space.set_size_request(-1, 112);
        }
        
        public override void installed() {
            username_entry.grab_focus();
            username_entry.set_activates_default(true);
            login_button.can_default = true;
            interactor.get_host().set_default(login_button);
        }
    }
    
    public class YandexTransaction: RESTTransaction {
        public YandexTransaction.with_url(YandexSession session, string url, HttpMethod method = HttpMethod.GET) {
            base.with_endpoint_url(session, url, method);
            add_headers(session);
        }
        
        private void add_headers(YandexSession session) {
            if (session.is_authenticated()) {
                add_header("Authorization", "OAuth %s".printf(session.get_access_token()));
                add_header("Connection", "close");
            }
        }
        
         public YandexTransaction(YandexSession session, HttpMethod method = HttpMethod.GET) {
            base(session, method);
            add_headers(session);
        }

        public void add_data(string type, string data) {
            set_custom_payload(data, type);
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

    public class Interactor: ServiceInteractor {
        private WebAuthenticationPane web_auth_pane = null;
        private ProgressPane progress_pane;
        private YandexSession session = null;
        private Photo[] photos;

        public override string get_name() { 
            return SERVICE_NAME;
        }
        
        public override void cancel_interaction() {
            session.stop_transactions();
        }

        public Interactor(PublishingDialog host) {
            base (host);
        }

        internal new PublishingDialog get_host() {
            return base.get_host();
        }

        public void service_get_album_list_error(RESTTransaction t, PublishingError err) {
            warning("failed to get album list");
            t.completed.disconnect(service_get_album_list_complete);
            t.network_error.disconnect(service_get_album_list_error);
            yandex_request_web_auth();
        }

        public void service_get_album_list_complete(RESTTransaction t) {
            t.completed.disconnect(service_get_album_list_complete);
            t.network_error.disconnect(service_get_album_list_error);

            debug("service_get_album_list_complete: %s", t.get_response());

            session.save_tokens();

            parse_album_list(t.get_response());

            PublishingOptionsPane publishing_options_pane = new PublishingOptionsPane(session);

            publishing_options_pane.publish.connect(on_publish);
            publishing_options_pane.logout.connect(on_logout);
            get_host().install_pane(publishing_options_pane);
        }

        private void on_logout() {
            Config config = Config.get_instance();
            debug("Logout");
            config.unset_publishing_string("yandex", "access_token");
            config.unset_publishing_string("yandex", "refresh_token");
            config.unset_publishing_string("yandex", "username");
            start_interaction();
        }

        private void on_upload_complete(BatchUploader uploader, int num_published) {
            uploader.status_updated.disconnect(progress_pane.set_status);
            uploader.upload_complete.disconnect(on_upload_complete);
            uploader.upload_error.disconnect(on_upload_error);

            if (num_published == 0)
                post_error(new PublishingError.LOCAL_FILE_ERROR(""));

            get_host().unlock_service();
            get_host().set_close_button_mode();

            get_host().install_pane(new SuccessPane(MediaType.PHOTO));
        }
        
        private void on_upload_error(BatchUploader uploader, PublishingError err) {
            uploader.status_updated.disconnect(progress_pane.set_status);
            uploader.upload_complete.disconnect(on_upload_complete);
            uploader.upload_error.disconnect(on_upload_error);

            post_error(err);
        }

        private void start_upload() {
            debug("Publishing to %s : %s", session.get_destination_album(), session.get_destination_album_url());

            get_host().unlock_service();
            get_host().set_cancel_button_mode();

            progress_pane = new ProgressPane();
            get_host().install_pane(progress_pane);

            Uploader uploader = new Uploader(session, photos);

            uploader.status_updated.connect(progress_pane.set_status);

            uploader.upload_complete.connect(on_upload_complete);
            uploader.upload_error.connect(on_upload_error);

            uploader.upload();
        }

        private void on_publish() {
            if (session.get_destination_album_url() == null)
                create_destination_album();
            else
                start_upload();
        }

        public void service_get_album_list() {
            string url = session.get_album_list_url();

            debug("getting album list from %s", url);

            YandexTransaction t = new YandexTransaction.with_url(session, url);
            t.completed.connect(service_get_album_list_complete);
            t.network_error.connect(service_get_album_list_error);

            try {
                t.execute();
            } catch (PublishingError err) {
                post_error(err);
            }
        }

        public void service_doc_transaction_error(RESTTransaction t, PublishingError err) {
            t.completed.disconnect(service_doc_transaction_complete);
            t.network_error.disconnect(service_doc_transaction_error);
            yandex_request_web_auth();
        }

        public void service_doc_transaction_complete(RESTTransaction t) {
            t.completed.disconnect(service_doc_transaction_complete);
            t.network_error.disconnect(service_doc_transaction_error);

            debug("service_doc completed: %s", t.get_response());

            try {
                RESTXmlDocument doc = RESTXmlDocument.parse_string(t.get_response(), check_response);
                Xml.Node* root = doc.get_root_node();

                for (Xml.Node* work = root->children ; work != null; work = work->next) {
                    if (work->name != "workspace")
                        continue;
                    for (Xml.Node* c = work->children ; c != null; c = c->next) {
                        if (c->name != "collection")
                            continue;

                        if (c->get_prop("id") == "album-list") {
                            session.set_album_list_url(c->get_prop("href"));

                            service_get_album_list();
                            break;
                        }
                    }
                }
            } catch (PublishingError err) {
                post_error(err);
            }
        }

        private new string? check_response(RESTXmlDocument doc) {
            return null;
        }

        private void parse_album_entry(Xml.Node *e) throws PublishingError {
            string title = null;
            string link = null;

            for (Xml.Node* c = e->children ; c != null; c = c->next) {
                if (c->name == "title")
                    title = c->get_content();

                if ((c->name == "link") && (c->get_prop("rel") == "photos"))
                    link = c->get_prop("href");

                if (title != null && link != null) {
                    session.add_album(title, link);
                    title = null;
                    link = null;
                    break;
                }
            }
        }
        
        public void parse_album_creation(string data) {
            try {
                RESTXmlDocument doc = RESTXmlDocument.parse_string(data, check_response);
                Xml.Node *root = doc.get_root_node();

                parse_album_entry(root);
            } catch (PublishingError err) {
                post_error(err);
            }
        }

        public void parse_album_list(string data) {
            try {
                RESTXmlDocument doc = RESTXmlDocument.parse_string(data, check_response);
                Xml.Node *root = doc.get_root_node();

                for (Xml.Node *e = root->children ; e != null; e = e->next) {
                    if (e->name != "entry")
                        continue;

                    parse_album_entry(e);
                }
            } catch (PublishingError err) {
                post_error(err);
            }
        }
        
        private void on_web_auth_pane_token_check_required(string access_token, string refresh_token) {
            session.set_tokens(access_token, refresh_token);

            get_host().unlock_service();
            get_host().set_cancel_button_mode();

            YandexTransaction t = new YandexTransaction(session);
            t.completed.connect(service_doc_transaction_complete);
            t.network_error.connect(service_doc_transaction_error);
            
            try {
                t.execute();
            } catch (PublishingError err) {
                post_error(err);
            }
        }

        private void yandex_request_web_auth() {
            session.want_web_check = false;
            session.clear_cache();
            web_auth_pane = new WebAuthenticationPane(("http://%s/authorize?client_id=%s&response_type=code").printf(auth_host, client_id));
            web_auth_pane.token_check_required.connect(on_web_auth_pane_token_check_required);
            get_host().install_pane(web_auth_pane);
        }

        private void yandex_login_pane(string username) {
            session = new YandexSession(username);
            
            get_host().unlock_service();
            get_host().set_cancel_button_mode();
            get_host().set_large_window_mode();

            if (!session.is_authenticated()) {
                yandex_request_web_auth();
            } else {
                session.want_web_check = true;
                on_web_auth_pane_token_check_required(session.get_access_token(), session.get_refresh_token());
            }
        }
        
        public override void start_interaction() {
            debug("Yandex.Interactor: starting iteractor");

            photos = get_host().get_photos();

            get_host().unlock_service();

            auth_host = "oauth.yandex.ru";
            service_host = "api-fotki.yandex.ru";
            client_id = "8e3a8208aa974e8e8c8faf6dd5325b75";

            string auth = YandexSession.load_auth_host();
            if (auth != null)
                auth_host = auth;

            string service = YandexSession.load_service_host();
            if (service != null)
                service_host = service;

            string cid = YandexSession.load_client_id();
            if (cid != null)
                client_id = cid;

            service_url = ("http://%s/api/users/").printf(service_host);

            string username = YandexSession.load_username();
            if (username != null) {
                yandex_login_pane(username);
            } else {
                YandexLoginWelcomePane p = new YandexLoginWelcomePane(this, SERVICE_WELCOME_MESSAGE);
                p.login_requested.connect(yandex_login_pane);
                
                get_host().install_pane(p);
            }
        }

        private void album_creation_error(RESTTransaction t, PublishingError err) {
            t.completed.disconnect(album_creation_complete);
            t.network_error.disconnect(album_creation_error);
            yandex_request_web_auth();
        }

        private void album_creation_complete(RESTTransaction t) {
            t.completed.disconnect(album_creation_complete);
            t.network_error.disconnect(album_creation_error);

            parse_album_creation(t.get_response());

            if (session.get_destination_album_url() != null)
                start_upload();
            else
                post_error(new PublishingError.PROTOCOL_ERROR("Server did not create album"));
        }

        private void create_destination_album() {
            string album = session.get_destination_album();
            string url = "%s/albums/".printf(session.get_endpoint_url());
            string data = "<entry xmlns=\"http://www.w3.org/2005/Atom\" xmlns:f=\"yandex:fotki\"><title>%s</title></entry>".printf(album);

            YandexTransaction t = new YandexTransaction.with_url(session, url, HttpMethod.POST);

            t.add_data("application/atom+xml; charset=utf-8; type=entry", data);

            t.completed.connect(album_creation_complete);
            t.network_error.connect(album_creation_error);
            
            try {
                t.execute();
            } catch (PublishingError err) {
                post_error(err);
            }
        }
    }

    public class YandexPublishOptions {
        public bool disable_comments = false;
        public bool hide_original = false;
        public string access_type;
    }

    public class YandexSession: RESTSession {
        private string access_token = null;
        private string refresh_token = null;
        private string album_list_url = null;
        public Gee.HashMap<string, string> album_list = null;
        private string destination_album = null;
        public YandexPublishOptions options;
        private string username = null;
        public Gee.HashMap<RESTTransaction, Photo?> transactions = null;

        public bool want_web_check = false;

        public YandexSession(string username) {
            base ("%s%s/".printf(service_url, username));
            
            Config config = Config.get_instance();
            
            transactions = new Gee.HashMap<RESTTransaction, Photo?>();
            
            if (YandexSession.load_username() != username) {
                config.unset_publishing_string("yandex", "access_token");
                config.unset_publishing_string("yandex", "refresh_token");
            } else {
                access_token = config.get_publishing_string("yandex", "access_token");
                refresh_token = config.get_publishing_string("yandex", "refresh_token");
            }
            
            save_username(username);
            this.username = username;
            
            album_list = new Gee.HashMap<string, string>();
            options = new YandexPublishOptions();
        }
        
        public void set_tokens(string? access_token, string? refresh_token) {
            debug("session: setting tokens: %s %s", access_token, refresh_token);
            this.access_token = access_token;
            this.refresh_token = refresh_token;

            if ((access_token == null) || (refresh_token == null))
                save_tokens();

            save_username(username);
        }

        public string get_username() {
            return username;
        }
        
        public bool is_authenticated() {
            return access_token != null;
        }
        
        public string get_access_token() {
            assert(is_authenticated());
            return access_token;
        }
        
        public string get_refresh_token() {
            assert(is_authenticated());
            return refresh_token;
        }
        
        public void set_album_list_url(string url) {
            this.album_list_url = url;
        }
        
        public bool has_album_list_url() {
            return album_list_url != null;
        }
        
        public string get_album_list_url() {
            assert(has_album_list_url());
            return album_list_url;
        }

        public void add_album(string title, string link) {
            debug("add album: %s %s", title, link);
            album_list.set(title, link);
        }

        public void set_destination_album(string album) {
            destination_album = album;
        }
        
        public string get_destination_album_url() {
            return album_list.get(destination_album);
        }
        
        public string get_destination_album() {
            return destination_album;
        }

        public static void save_username(string username) {
            Config.get_instance().set_publishing_string("yandex", "username", username);
        }
        
        public static string? load_username() {
            return Config.get_instance().get_publishing_string("yandex", "username");
        }

        public static string? load_auth_host() {
            return Config.get_instance().get_publishing_string("yandex", "auth_host");
        }

        public static string? load_client_id() {
            return Config.get_instance().get_publishing_string("yandex", "client_id");
        }

        public static string? load_service_host() {
            return Config.get_instance().get_publishing_string("yandex", "service_host");
        }
        
        public static void clear_cache() {
            Config client = Config.get_instance();
            client.unset_publishing_string("yandex", "access_token");
            client.unset_publishing_string("yandex", "refresh_token");
            client.unset_publishing_string("yandex", "username");
        }

        public void save_tokens() {
            Config client = Config.get_instance();
            if (access_token == null) {
                client.unset_publishing_string("yandex", "access_token");
                client.unset_publishing_string("yandex", "refresh_token");
            } else {
                client.set_publishing_string("yandex", "access_token", access_token);
                client.set_publishing_string("yandex", "refresh_token", refresh_token);
            }
        }
    }

    private class Uploader: BatchUploader {
        private YandexSession session;

        public Uploader(YandexSession session, Photo[] photos) {
            base (photos);
            
            this.session = session;
        }

        protected override bool prepare_file(BatchUploader.TemporaryFileDescriptor file) {
            try {
                if (file.media is Photo) {
                    ((Photo) file.media).export(file.temp_file, Scaling.for_original(), Jpeg.Quality.MAXIMUM,
                        PhotoFileFormat.JFIF);
                }
            } catch(Error e) {
                return false;
            }

            return true;
        }

        private void on_file_uploaded(RESTTransaction txn) {
            if (session.transactions.has_key(txn)) {
                warning("Uploaded: %s", txn.get_response());
                session.transactions.unset(txn);
            } else {
                warning("Failed to match photo ID to transaction: %s", txn.get_response());
            }
        }

        protected override RESTTransaction create_transaction_for_file(BatchUploader.TemporaryFileDescriptor file) {
            RESTTransaction t = new UploadTransaction(session, file.temp_file.get_path(),
                (Photo) file.media);

            session.transactions.set(t, (Photo) file.media);
            t.completed.connect(on_file_uploaded);
            
            return t;
        }
    }

    private class UploadTransaction: YandexTransaction {
        public UploadTransaction(YandexSession session, string source_file, Photo photo) {
            base.with_url(session, session.get_destination_album_url(), HttpMethod.POST);
            
            set_custom_payload("qwe", "image/jpeg", 1);

            debug("Uploading %s '%s' -> %s : %s", source_file, photo.get_name(), session.get_destination_album(), session.get_destination_album_url());

            LibraryPhoto lphoto = LibraryPhoto.global.fetch(photo.get_photo_id());

            Gee.List<Tag>? photo_tags = Tag.global.fetch_for_source(lphoto);
            string tags = "";
            if (photo_tags != null) {
                foreach (Tag tag in photo_tags) {
                    tags += ("%s;").printf(tag.get_name());
                }

                add_header("Tags", tags);
            }
            debug("photo: '%s', tags: '%s'", photo.get_name(), tags);
            
            Soup.Multipart message_parts = new Soup.Multipart("multipart/form-data");
            if (tags != "")
                message_parts.append_form_string("tag", tags);
            message_parts.append_form_string("title", photo.get_name());
            message_parts.append_form_string("hide_original", session.options.hide_original.to_string());
            message_parts.append_form_string("disable_comments", session.options.disable_comments.to_string());
            message_parts.append_form_string("access", session.options.access_type.down());

            string photo_data;
            size_t data_length;

            try {
                FileUtils.get_contents(source_file, out photo_data, out data_length);
            } catch (FileError e) {
                error("YandexUploadTransaction: couldn't read data from file '%s'", source_file);
            }

            int image_part_num = message_parts.get_length();

            Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.COPY, photo_data, data_length);
            message_parts.append_form_file("", source_file, "image/jpeg", bindable_data);

            unowned Soup.MessageHeaders image_part_header;
            unowned Soup.Buffer image_part_body;
            message_parts.get_part(image_part_num, out image_part_header, out image_part_body);

            GLib.HashTable<string, string> result = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
            result.insert("name", "image");
            result.insert("filename", "unused");

            image_part_header.set_content_disposition("form-data", result);

            Soup.Message outbound_message = Soup.form_request_new_from_multipart(get_endpoint_url(), message_parts);
            outbound_message.request_headers.append("Authorization", ("OAuth %s").printf(session.get_access_token()));
            outbound_message.request_headers.append("Connection", "close");
            set_message(outbound_message);
        }
    }

    private class WebAuthenticationPane: PublishingDialogPane {
        private string token_str_http = ("http://%s/token").printf(auth_host);
        private string token_str_https = ("https://%s/token").printf(auth_host);

        private WebKit.WebView webview = null;
        private Gtk.ScrolledWindow webview_frame = null;
        private Gtk.Layout white_pane = null;
        private string login_url;

        private int started_token_recv = 0;

        public signal void token_check_required(string access_token, string refresh_token);

        public WebAuthenticationPane(string login_url) {
            this.login_url = login_url;

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
            webview.get_settings().enable_plugins = false;
            webview.load_finished.connect(on_load_finished);
            webview.load_started.connect(on_load_started);
            webview.navigation_requested.connect(navigation_requested);
            webview.mime_type_policy_decision_requested.connect(mime_type_policy_decision_requested);

            webview_frame.add(webview);
            white_pane.add(webview_frame);
            webview.set_size_request(853, 587);
        }

        private bool mime_type_policy_decision_requested (WebKit.WebFrame p0, WebKit.NetworkRequest p1, string p2, WebKit.WebPolicyDecision p3) {
            if (started_token_recv == 1) {
                if (p2 != "application/json") {
                    warning("Trying to get yandex token: unsupported mime type '%s'.", p2);

                    started_token_recv = 2;
                }
            }
            return true;
        }

        private WebKit.NavigationResponse navigation_requested (WebKit.WebFrame frame, WebKit.NetworkRequest req) {
            debug("Navigating to '%s', token: '%s'", req.uri, token_str_https);
            if (req.uri == token_str_https || req.uri == token_str_http)
                started_token_recv = 1;
            return WebKit.NavigationResponse.ACCEPT;
        }

        private void on_load_finished(WebKit.WebFrame frame) {
            if (started_token_recv != 1) {
                show_page();
                return;
            }

            window.set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));

            WebKit.WebDataSource data = frame.get_data_source();
            string s = data.get_data().str;
            Json.Parser p = new Json.Parser();

            try {
                p.load_from_data(s, -1);
                Json.Object root = p.get_root().get_object();

                debug("data: %s", s);
                debug("%s %s", root.get_string_member("access_token"), root.get_string_member("refresh_token"));

                token_check_required(root.get_string_member("access_token"), root.get_string_member("refresh_token"));
            } catch (Error e) {
                warning("Invalid yandex token: %s.", s);
            }
        }

        private void on_load_started(WebKit.WebFrame frame) {
            webview_frame.hide();
            window.set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
        }

        public void show_page() {
            webview_frame.show();
            window.set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
        }

        public override void installed() {
            webview.open(login_url);
        }
    }

    private class PublishingOptionsPane: PublishingDialogPane {
        private Gtk.Builder builder;
        private Gtk.Button logout_button;
        private Gtk.Button publish_button;
        private Gtk.ComboBoxEntry album_list;
        private YandexSession session;

        public signal void publish();
        public signal void logout();

        public PublishingOptionsPane(YandexSession session) {
            this.session = session;

            try {
                builder = new Gtk.Builder();
                builder.add_from_file(Resources.get_ui("yandex_publish_model.glade").get_path());
                builder.connect_signals(null);
                Gtk.Alignment align = builder.get_object("alignment") as Gtk.Alignment;

                album_list = builder.get_object ("album_list") as Gtk.ComboBoxEntry;
                foreach (string key in session.album_list.keys)
                    album_list.append_text(key);
                
                album_list.set_active(0);

                publish_button = builder.get_object("publish_button") as Gtk.Button;
                logout_button = builder.get_object("logout_button") as Gtk.Button;

                publish_button.clicked.connect(on_publish_clicked);
                logout_button.clicked.connect(on_logout_clicked);

                align.reparent(this);
            } catch (Error e) {
                warning("Could not load UI: %s", e.message);
            }
        }
        
        private void on_logout_clicked() {
            logout();
        }

        private void on_publish_clicked() {
            session.set_destination_album(album_list.get_active_text());

            Gtk.CheckButton tmp = builder.get_object("hide_original_check") as Gtk.CheckButton;
            session.options.hide_original = tmp.active;

            tmp = builder.get_object("disable_comments_check") as Gtk.CheckButton;
            session.options.disable_comments = tmp.active;

            Gtk.ComboBoxEntry access_type = builder.get_object("access_type_list") as Gtk.ComboBoxEntry;
            session.options.access_type = access_type.get_active_text();

            publish();
        }
    }
}

#endif
