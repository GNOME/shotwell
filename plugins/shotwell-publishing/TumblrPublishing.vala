/* Copyright 2012 BJA Electronics
 * Author: Jeroen Arnoldus (b.j.arnoldus@bja-electronics.nl)
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class TumblrService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "tumblr.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;

    public TumblrService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set =
                Resources.load_from_resource(Resources.RESOURCE_PATH + "/" +
                        ICON_FILENAME);
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
    internal const string ENDPOINT_URL = "https://www.tumblr.com/";
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
        private Publishing.RESTSupport.OAuth1.Session session = null;
        private PublishingOptionsPane publishing_options_pane = null;
        private SizeEntry[] sizes = null;
        private BlogEntry[] blogs = null;
        private string username = "";
        private Spit.Publishing.Authenticator authenticator;


        private SizeEntry[] create_sizes() {
            SizeEntry[] result = new SizeEntry[0];

            result += new SizeEntry(_("500 × 375 pixels"), 500);
            result += new SizeEntry(_("1024 × 768 pixels"), 1024);
            result += new SizeEntry(_("1280 × 853 pixels"), 1280);
            //Larger images make no sense for Tumblr
            //        result += new SizeEntry(_("2048 × 1536 pixels"), 2048);
            //        result += new SizeEntry(_("4096 × 3072 pixels"), 4096);
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
            this.session = new Publishing.RESTSupport.OAuth1.Session(ENDPOINT_URL);
            this.sizes = this.create_sizes();
            this.blogs = this.create_blogs();

            this.authenticator = Publishing.Authenticator.Factory.get_instance().create("tumblr", host);
            this.authenticator.authenticated.connect(on_authenticator_authenticated);
        }

        ~TumblrPublisher() {
            this.authenticator.authenticated.disconnect(on_authenticator_authenticated);
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

        private void on_authenticator_authenticated() {
            if (!is_running())
                return;

            debug("EVENT: a fully authenticated session has become available");

            var params = this.authenticator.get_authentication_parameter();
            Variant consumer_key = null;
            Variant consumer_secret = null;
            Variant auth_token = null;
            Variant auth_token_secret = null;

            params.lookup_extended("ConsumerKey", null, out consumer_key);
            params.lookup_extended("ConsumerSecret", null, out consumer_secret);
            session.set_api_credentials(consumer_key.get_string(), consumer_secret.get_string());

            params.lookup_extended("AuthToken", null, out auth_token);
            params.lookup_extended("AuthTokenSecret", null, out auth_token_secret);
            session.set_access_phase_credentials(auth_token.get_string(),
                    auth_token_secret.get_string(), "");


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
                    string url = blog.get_string_member ("url").replace("http://","").replace("https://", "").replace("/","");
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
            //invalidate_persistent_session();
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

            if (this.authenticator.can_logout()) {
                this.authenticator.logout();
            }

            running = false;

            attempt_start();
        }

        public void attempt_start() {
            if (is_running())
                return;

            debug("TumblrPublisher: starting interaction.");

            running = true;
            this.authenticator.authenticate();
        }

        public void start() {
            if (is_running())
                return;

            if (was_started)
                error(_("TumblrPublisher: start( ): can’t start; this publisher is not restartable."));

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

                try {
                    builder = new Gtk.Builder();
                    builder.add_from_resource (Resources.RESOURCE_PATH +
                            "/tumblr_publishing_options_pane.ui");
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

        internal class UserInfoFetchTransaction : Publishing.RESTSupport.OAuth1.Transaction {
            public UserInfoFetchTransaction(Publishing.RESTSupport.OAuth1.Session session) {
                base.with_uri(session, "https://api.tumblr.com/v2/user/info",
                        Publishing.RESTSupport.HttpMethod.POST);
            }
        }

        internal class UploadTransaction : Publishing.RESTSupport.OAuth1.UploadTransaction {
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


            public UploadTransaction(Publishing.RESTSupport.OAuth1.Session session,Spit.Publishing.Publishable publishable, string blog_url)  {
                debug("Init upload transaction");
                base(session, publishable,"https://api.tumblr.com/v2/blog/%s/post".printf(blog_url) );

            }

            public override void execute() throws Spit.Publishing.PublishingError {
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
                        tags = string.joinv (",", keywords);
                    }
                    add_argument("tags", Soup.URI.encode(tags, ENCODE_RFC_3986_EXTRA));

                } catch (FileError e) {
                    throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                            _("A temporary file needed for publishing is unavailable"));

                }

                this.authorize();

                Publishing.RESTSupport.Argument[] request_arguments = get_arguments();
                assert(request_arguments.length > 0);

                var request_data = Publishing.RESTSupport.Argument.serialize_list(request_arguments);

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
            public Uploader(Publishing.RESTSupport.OAuth1.Session session, Spit.Publishing.Publishable[] publishables, string blog_url) {
                base(session, publishables);
                this.blog_url=blog_url;

            }


            protected override Publishing.RESTSupport.Transaction create_transaction(
                    Spit.Publishing.Publishable publishable) {
                debug("Create upload transaction");
                return new UploadTransaction((Publishing.RESTSupport.OAuth1.Session) get_session(), get_current_publishable(), this.blog_url);

            }
        }

    } //class TumblrPublisher

} //namespace Publishing.Tumblr
