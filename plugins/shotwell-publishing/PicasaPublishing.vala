/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class PicasaService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "picasa.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;
    
    public PicasaService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set =
                Resources.load_from_resource(Resources.RESOURCE_PATH + "/" + ICON_FILENAME);
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
        info.copyright = _("Copyright 2016 Software Freedom Conservancy Inc.");
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

internal const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");

public class PicasaPublisher : Publishing.RESTSupport.GooglePublisher {
    private const string DEFAULT_ALBUM_FEED_URL = "https://picasaweb.google.com/data/feed/api/user/default/albumid/default";
    private bool running;
    private Spit.Publishing.ProgressCallback progress_reporter;
    private PublishingParameters publishing_parameters;
    private Spit.Publishing.Authenticator authenticator;

    public PicasaPublisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host) {
        base(service, host, "https://picasaweb.google.com/data/");
        
        this.publishing_parameters = new PublishingParameters();
        load_parameters_from_configuration_system(publishing_parameters);
        
        Spit.Publishing.Publisher.MediaType media_type = Spit.Publishing.Publisher.MediaType.NONE;
        foreach(Spit.Publishing.Publishable p in host.get_publishables())
            media_type |= p.get_media_type();
        publishing_parameters.set_media_type(media_type);
        
        this.progress_reporter = null;
    }

    private Album[] extract_albums_helper(Xml.Node* document_root)
        throws Spit.Publishing.PublishingError {
        Album[] result = new Album[0];

        Xml.Node* doc_node_iter = null;
        if (document_root->name == "feed")
            doc_node_iter = document_root->children;
        else if (document_root->name == "entry")
            doc_node_iter = document_root;
        else
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("response root node " +
                "isn't a <feed> or <entry>");

        // Add album that will push to the default feed for all the new users
        result += new Album(_("Default album"), DEFAULT_ALBUM_FEED_URL);

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

            // If default album is present in the result list, just skip it because we added it on top anyway
            if (url_val == DEFAULT_ALBUM_FEED_URL) {
                continue;
            }

            result += new Album(name_val, url_val);
        }

        return result;
    }

    private void load_parameters_from_configuration_system(PublishingParameters parameters) {
        parameters.set_major_axis_size_selection_id(get_host().get_config_int("default-size", 0));
        parameters.set_strip_metadata(get_host().get_config_bool("strip-metadata", false));
        parameters.set_target_album_name(get_host().get_config_string("last-album", null));
    }
    
    private void save_parameters_to_configuration_system(PublishingParameters parameters) {
        get_host().set_config_int("default-size", parameters.get_major_axis_size_selection_id());
        get_host().set_config_bool("strip_metadata", parameters.get_strip_metadata());
        get_host().set_config_string("last-album", parameters.get_target_album_name());
    }

    protected override void on_login_flow_complete() {
        debug("EVENT: OAuth login flow complete.");


        publishing_parameters.set_user_name(get_session().get_user_name());
        
        do_fetch_account_information();
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

        if (bad_txn.get_status_code() == 403 || bad_txn.get_status_code() == 404) {
            do_logout();
        } else {
            // If we get any other kind of error, we can't recover, so just post it to the user
            get_host().post_error(err);
        }
    }

    private void on_publishing_options_logout() {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Logout' in the publishing options pane.");

        do_logout();
    }

    private void on_publishing_options_publish() {
        if (!is_running())
            return;
            
        debug("EVENT: user clicked 'Publish' in the publishing options pane.");

        save_parameters_to_configuration_system(publishing_parameters);

        do_upload();
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

        get_host().post_error(err);
    }

    private void do_fetch_account_information() {
        debug("ACTION: fetching account and album information.");

        get_host().install_account_fetch_wait_pane();
        get_host().set_service_locked(true);

        AlbumDirectoryTransaction directory_trans =
            new AlbumDirectoryTransaction(get_session());
        directory_trans.network_error.connect(on_initial_album_fetch_error);
        directory_trans.completed.connect(on_initial_album_fetch_complete);
        
        try {
            directory_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            // don't post the error here -- some errors are recoverable so let's let the error
            // handler function sort out whether the error is recoverable or not. If the error
            // isn't recoverable, the error handler will post the error to the host
            on_initial_album_fetch_error(directory_trans, err);
        }
    }
    
    private void do_parse_and_display_account_information(AlbumDirectoryTransaction transaction) {
        debug("ACTION: parsing account and album information from server response XML");

        Publishing.RESTSupport.XmlDocument response_doc;
        try {
            response_doc = Publishing.RESTSupport.XmlDocument.parse_string(
                transaction.get_response(), AlbumDirectoryTransaction.validate_xml);
        } catch (Spit.Publishing.PublishingError err) {
            get_host().post_error(err);
            return;
        }

        try {
            publishing_parameters.set_albums(extract_albums_helper(response_doc.get_root_node()));
        } catch (Spit.Publishing.PublishingError err) {
            get_host().post_error(err);
            return;
        }

        do_show_publishing_options_pane();
    }
    
    private void do_show_publishing_options_pane() {
        debug("ACTION: showing publishing options pane.");
        Gtk.Builder builder = new Gtk.Builder();

        try {
            builder.add_from_resource(Resources.RESOURCE_PATH + "/" + "picasa_publishing_options_pane.ui");
        } catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            get_host().post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is unavailable. Publishing to Picasa can’t continue.")));
            return;
        }

        var opts_pane = new PublishingOptionsPane(builder, publishing_parameters, this.authenticator.can_logout());
        opts_pane.publish.connect(on_publishing_options_publish);
        opts_pane.logout.connect(on_publishing_options_logout);
        get_host().install_dialog_pane(opts_pane);

        get_host().set_service_locked(false);
    }

    private void do_upload() {       
        debug("ACTION: uploading media items to remote server.");

        get_host().set_service_locked(true);

        progress_reporter = get_host().serialize_publishables(
            publishing_parameters.get_major_axis_size_pixels(),
            publishing_parameters.get_strip_metadata());
        
        // Serialization is a long and potentially cancellable operation, so before we use
        // the publishables, make sure that the publishing interaction is still running. If it
        // isn't the publishing environment may be partially torn down so do a short-circuit
        // return
        if (!is_running())
            return;
            
        Spit.Publishing.Publishable[] publishables = get_host().get_publishables();
        Uploader uploader = new Uploader(get_session(), publishables, publishing_parameters);

        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);

        uploader.upload(on_upload_status_updated);
    }

    private void do_show_success_pane() {
        debug("ACTION: showing success pane.");

        get_host().set_service_locked(false);
        get_host().install_success_pane();
    }

    protected override void do_logout() {
        debug("ACTION: logging out user.");
        get_session().deauthenticate();

        if (this.authenticator.can_logout()) {
            this.authenticator.logout();
            this.authenticator.authenticate();
        }
    }

    public override bool is_running() {
        return running;
    }
    
    public override void start() {
        debug("PicasaPublisher: start( ) invoked.");
        
        if (is_running())
            return;

        running = true;

        this.authenticator.authenticate();
    }

    public override void stop() {
        debug("PicasaPublisher: stop( ) invoked.");

        get_session().stop_transactions();

        running = false;
    }

    protected override Spit.Publishing.Authenticator get_authenticator() {
        if (this.authenticator == null) {
            this.authenticator = Publishing.Authenticator.Factory.get_instance().create("picasa", get_host());
        }

        return this.authenticator;
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

internal class AlbumDirectoryTransaction :
    Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    private const string ENDPOINT_URL = "https://picasaweb.google.com/data/feed/api/user/" +
        "default";

    public AlbumDirectoryTransaction(Publishing.RESTSupport.GoogleSession session) {
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

internal class UploadTransaction :
    Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    private PublishingParameters parameters;
    private const string METADATA_TEMPLATE = "<?xml version=\"1.0\" ?><atom:entry xmlns:atom='http://www.w3.org/2005/Atom' xmlns:mrss='http://search.yahoo.com/mrss/'> <atom:title>%s</atom:title> %s <atom:category scheme='http://schemas.google.com/g/2005#kind' term='http://schemas.google.com/photos/2007#photo'/> %s </atom:entry>";
    private Publishing.RESTSupport.GoogleSession session;
    private string mime_type;
    private Spit.Publishing.Publishable publishable;
    private MappedFile mapped_file;

    public UploadTransaction(Publishing.RESTSupport.GoogleSession session,
        PublishingParameters parameters, Spit.Publishing.Publishable publishable) {
        base(session, parameters.get_target_album_feed_url(),
            Publishing.RESTSupport.HttpMethod.POST);
        assert(session.is_authenticated());
        this.session = session;
        this.parameters = parameters;
        this.publishable = publishable;
        if (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.VIDEO) {
            try {
                var info = this.publishable.get_serialized_file().query_info(FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
                this.mime_type = ContentType.get_mime_type(info.get_content_type());
            } catch (Error err) {
                this.mime_type = "video/mpeg";
            }
        } else {
            this.mime_type = "image/jpeg";
        }
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

            keywords_string = Publishing.RESTSupport.decimal_entity_encode(keywords_string);
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
            Soup.Form.request_new_from_multipart(get_endpoint_url(), message_parts);
        outbound_message.request_headers.append("Authorization", "Bearer " +
            session.get_access_token());
        set_message(outbound_message);

        // send the message and get its response
        set_is_executed(true);
        send();
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
    private Gtk.ComboBoxText existing_albums_combo = null;
    private Gtk.CheckButton public_check = null;
    private Gtk.ComboBoxText size_combo = null;
    private Gtk.CheckButton strip_metadata_check = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private SizeDescription[] size_descriptions;
    private PublishingParameters parameters;

    public signal void publish();
    public signal void logout();

    public PublishingOptionsPane(Gtk.Builder builder, PublishingParameters parameters, bool can_logout) {
        size_descriptions = create_size_descriptions();

        this.builder = builder;
        assert(builder != null);
        assert(builder.get_objects().length() > 0);
        
        this.parameters = parameters;

        // pull in all widgets from builder.
        pane_widget = (Gtk.Box) builder.get_object("picasa_pane_widget");
        login_identity_label = (Gtk.Label) builder.get_object("login_identity_label");
        publish_to_label = (Gtk.Label) builder.get_object("publish_to_label");
        existing_albums_combo = (Gtk.ComboBoxText) builder.get_object("existing_albums_combo");
        public_check = (Gtk.CheckButton) builder.get_object("public_check");
        size_combo = (Gtk.ComboBoxText) builder.get_object("size_combo");
        strip_metadata_check = (Gtk.CheckButton) this.builder.get_object("strip_metadata_check");
        publish_button = (Gtk.Button) builder.get_object("publish_button");
        logout_button = (Gtk.Button) builder.get_object("logout_button");

        if (!can_logout) {
            logout_button.parent.remove(logout_button);
        }

        // populate any widgets whose contents are programmatically-generated.
        login_identity_label.set_label(_("You are logged into Picasa Web Albums as %s.").printf(
            parameters.get_user_name()));
        strip_metadata_check.set_active(parameters.get_strip_metadata());


        if((parameters.get_media_type() & Spit.Publishing.Publisher.MediaType.PHOTO) == 0) {
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
            size_combo.set_active(parameters.get_major_axis_size_selection_id());
        }

        // connect all signals.
        logout_button.clicked.connect(on_logout_clicked);
        publish_button.clicked.connect(on_publish_clicked);
    }

    private void on_publish_clicked() {
        // size_combo won't have been set to anything useful if this is the first time we've
        // published to Picasa, and/or we've only published video before, so it may be negative,
        // indicating nothing was selected. Clamp it to a valid value...
        int size_combo_last_active = (size_combo.get_active() >= 0) ? size_combo.get_active() : 0;
        
        parameters.set_major_axis_size_selection_id(size_combo_last_active);
        parameters.set_major_axis_size_pixels(
            size_descriptions[size_combo_last_active].major_axis_pixels);
        parameters.set_strip_metadata(strip_metadata_check.get_active());
        
        Album[] albums = parameters.get_albums();

        parameters.set_target_album_name(albums[existing_albums_combo.get_active()].name);
        parameters.set_target_album_entry_url(albums[existing_albums_combo.get_active()].url);
        publish();
    }

    private void on_logout_clicked() {
        logout();
    }

    private SizeDescription[] create_size_descriptions() {
        SizeDescription[] result = new SizeDescription[0];

        result += new SizeDescription(_("Small (640 × 480 pixels)"), 640);
        result += new SizeDescription(_("Medium (1024 × 768 pixels)"), 1024);
        result += new SizeDescription(_("Recommended (1600 × 1200 pixels)"), 1600);
        result += new SizeDescription(_("Google+ (2048 × 1536 pixels)"), 2048);
        result += new SizeDescription(_("Original Size"), PublishingParameters.ORIGINAL_SIZE);

        return result;
    }

    public void installed() {
        int default_album_id = -1;
        string last_album = parameters.get_target_album_name();
        
        Album[] albums = parameters.get_albums();
        
        for (int i = 0; i < albums.length; i++) {
            existing_albums_combo.append_text(albums[i].name);
            // Activate last known album id. If none was chosen, either use the old default (Shotwell connect)
            // or the new "Default album" album for Google Photos
            if (albums[i].name == last_album ||
                ((albums[i].name == DEFAULT_ALBUM_NAME || albums[i].name == _("Default album")) && default_album_id == -1))
                default_album_id = i;
        }

        if (default_album_id >= 0) {
            existing_albums_combo.set_active(default_album_id);
        }
    }

    public Gtk.Widget get_widget() {
        return pane_widget;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }
    
    public void on_pane_installed() {
        installed();
    }
    
    public void on_pane_uninstalled() {
    }
}

internal class PublishingParameters {
    public const int ORIGINAL_SIZE = -1;
    
    private string? target_album_name;
    private string? target_album_url;
    private bool album_public;
    private bool strip_metadata;
    private int major_axis_size_pixels;
    private int major_axis_size_selection_id;
    private string user_name;
    private Album[] albums;
    private Spit.Publishing.Publisher.MediaType media_type;

    public PublishingParameters() {
        this.user_name = "[unknown]";
        this.target_album_name = null;
        this.major_axis_size_selection_id = 0;
        this.major_axis_size_pixels = ORIGINAL_SIZE;
        this.target_album_url = null;
        this.album_public = false;
        this.albums = null;
        this.strip_metadata = false;
        this.media_type = Spit.Publishing.Publisher.MediaType.PHOTO;
    }
    
    public string get_target_album_name() {
        return target_album_name;
    }
    
    public void set_target_album_name(string target_album_name) {
        this.target_album_name = target_album_name;
    }
    
    public void set_target_album_entry_url(string target_album_url) {
        this.target_album_url = target_album_url;
    }

    public string get_target_album_entry_url() {
        return target_album_url;
    }
    
    public string get_target_album_feed_url() {
        string entry_url = get_target_album_entry_url();
        string feed_url = entry_url.replace("entry", "feed");

        return feed_url;
    }
    
    public string get_user_name() {
        return user_name;
    }
    
    public void set_user_name(string user_name) {
        this.user_name = user_name;
    }
    
    public Album[] get_albums() {
        return albums;
    }
    
    public void set_albums(Album[] albums) {
        this.albums = albums;
    }
    
    public void set_major_axis_size_pixels(int pixels) {
        this.major_axis_size_pixels = pixels;
    }
        
    public int get_major_axis_size_pixels() {
        return major_axis_size_pixels;
    }
    
    public void set_major_axis_size_selection_id(int selection_id) {
        this.major_axis_size_selection_id = selection_id;
    }
    
    public int get_major_axis_size_selection_id() {
        return major_axis_size_selection_id;
    }
    
    public void set_strip_metadata(bool strip_metadata) {
        this.strip_metadata = strip_metadata;
    }
    
    public bool get_strip_metadata() {
        return strip_metadata;
    }
    
    public void set_media_type(Spit.Publishing.Publisher.MediaType media_type) {
        this.media_type = media_type;
    }
    
    public Spit.Publishing.Publisher.MediaType get_media_type() {
        return media_type;
    }
}

internal class Uploader : Publishing.RESTSupport.BatchUploader {
    private PublishingParameters parameters;

    public Uploader(Publishing.RESTSupport.GoogleSession session,
        Spit.Publishing.Publishable[] publishables, PublishingParameters parameters) {
        base(session, publishables);
        
        this.parameters = parameters;
    }
    
    protected override Publishing.RESTSupport.Transaction create_transaction(
        Spit.Publishing.Publishable publishable) {
        return new UploadTransaction((Publishing.RESTSupport.GoogleSession) get_session(),
            parameters, get_current_publishable());
    }
}

}

