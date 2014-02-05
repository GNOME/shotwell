/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class YouTubeService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "youtube.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;

    public YouTubeService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_icon_set(resource_directory.get_child(ICON_FILENAME));
    }

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }

    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.youtube";
    }

    public unowned string get_pluggable_name() {
        return "YouTube";
    }

    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Jani Monoses, Lucas Beeler";
        info.copyright = _("Copyright 2009-2014 Yorba Foundation");
        info.translators = Resources.TRANSLATORS;
        info.version = _VERSION;
        info.website_name = Resources.WEBSITE_NAME;
        info.website_url = Resources.WEBSITE_URL;
        info.is_license_wordwrapped = false;
        info.license = Resources.LICENSE;
        info.icons = icon_pixbuf_set;
    }

    public Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host) {
        return new Publishing.YouTube.YouTubePublisher(this, host);
    }

    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return Spit.Publishing.Publisher.MediaType.VIDEO;
    }

    public void activation(bool enabled) {
    }
}

namespace Publishing.YouTube {

private const string SERVICE_WELCOME_MESSAGE =
    _("You are not currently logged into YouTube.\n\nYou must have already signed up for a Google account and set it up for use with YouTube to continue. You can set up most accounts by using your browser to log into the YouTube site at least once.");
private const string DEVELOPER_KEY =
    "AI39si5VEpzWK0z-pzo4fonEj9E4driCpEs9lK8y3HJsbbebIIRWqW3bIyGr42bjQv-N3siAfqVoM8XNmtbbp5x2gpbjiSAMTQ";
    
private enum PrivacySetting {
    PUBLIC,
    UNLISTED,
    PRIVATE
}

private class PublishingParameters {
    private PrivacySetting privacy;
    private string? channel_name;
    private string? user_name;

    public PublishingParameters() {
        this.privacy = PrivacySetting.PRIVATE;
        this.channel_name = null;
        this.user_name = null;
    }

    public PrivacySetting get_privacy() {
        return this.privacy;
    }
    
    public void set_privacy(PrivacySetting privacy) {
        this.privacy = privacy;
    }
    
    public string? get_channel_name() {
        return channel_name;
    }
    
    public void set_channel_name(string? channel_name) {
        this.channel_name = channel_name;
    }
    
    public string? get_user_name() {
        return user_name;
    }
    
    public void set_user_name(string? user_name) {
        this.user_name = user_name;
    }
}

public class YouTubePublisher : Publishing.RESTSupport.GooglePublisher {
    private class ChannelDirectoryTransaction :
        Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
        private const string ENDPOINT_URL = "http://gdata.youtube.com/feeds/users/default";

        public ChannelDirectoryTransaction(Publishing.RESTSupport.GoogleSession session) {
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
    
    private bool running;
    private string? refresh_token;
    private PublishingParameters publishing_parameters;
    private Spit.Publishing.ProgressCallback? progress_reporter;

    public YouTubePublisher(Spit.Publishing.Service service, Spit.Publishing.PluginHost host) {
        base(service, host, "https://gdata.youtube.com/");
        
        this.running = false;
        this.refresh_token = host.get_config_string("refresh_token", null);
        this.publishing_parameters = new PublishingParameters();
        this.progress_reporter = null;
    }

    public override bool is_running() {
        return running;
    }
    
    public override void start() {
        debug("YouTubePublisher: started.");
        
        if (is_running())
            return;

        running = true;
        
        if (refresh_token == null)
            do_show_service_welcome_pane();
        else
            start_oauth_flow(refresh_token);
    }
    
    public override void stop() {
        debug("YouTubePublisher: stopped.");

        running = false;

        get_session().stop_transactions();
    }
    
    private string extract_channel_name_helper(Xml.Node* document_root) throws
        Spit.Publishing.PublishingError {
        string result = "";

        Xml.Node* doc_node_iter = null;
        if (document_root->name == "feed")
            doc_node_iter = document_root->children;
        else if (document_root->name == "entry")
            doc_node_iter = document_root;
        else
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                "response root node isn't a <feed> or <entry>");

        for ( ; doc_node_iter != null; doc_node_iter = doc_node_iter->next) {
            if (doc_node_iter->name != "entry")
                continue;

            string name_val = null;
            string url_val = null;
            Xml.Node* channel_node_iter = doc_node_iter->children;
            for ( ; channel_node_iter != null; channel_node_iter = channel_node_iter->next) {
                if (channel_node_iter->name == "title") {
                    name_val = channel_node_iter->get_content();
                } else if (channel_node_iter->name == "id") {
                    // we only want nodes in the default namespace -- the feed that we get back
                    // from Google also defines <entry> child nodes named <id> in the media
                    // namespace
                    if (channel_node_iter->ns->prefix != null)
                        continue;
                    url_val = channel_node_iter->get_content();
                }
            }

            result = name_val;
            break;
        }

        debug("YouTubePublisher: extracted channel name '%s' from response XML.", result);

        return result;
    }
    
    private void on_service_welcome_login() {
        debug("EVENT: user clicked 'Login' in welcome pane.");

        if (!is_running())
            return;
        
        start_oauth_flow(refresh_token);
    }
    
    protected override void on_login_flow_complete() {
        debug("EVENT: OAuth login flow complete.");
        
        get_host().set_config_string("refresh_token", get_session().get_refresh_token());

        publishing_parameters.set_user_name(get_session().get_user_name());
        
        do_fetch_account_information();
    }

    private void on_initial_channel_fetch_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_initial_channel_fetch_complete);
        txn.network_error.disconnect(on_initial_channel_fetch_error);

        debug("EVENT: finished fetching account and channel information.");

        if (!is_running())
            return;

        do_parse_and_display_account_information((ChannelDirectoryTransaction) txn);
    }

    private void on_initial_channel_fetch_error(Publishing.RESTSupport.Transaction bad_txn,
        Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_initial_channel_fetch_complete);
        bad_txn.network_error.disconnect(on_initial_channel_fetch_error);

        debug("EVENT: fetching account and channel information failed; response = '%s'.",
            bad_txn.get_response());

        if (!is_running())
            return;

        get_host().post_error(err);
    }

    private void on_publishing_options_logout() {
        debug("EVENT: user clicked 'Logout' in the publishing options pane.");

        if (!is_running())
            return;

        do_logout();
    }

    private void on_publishing_options_publish() {
        debug("EVENT: user clicked 'Publish' in the publishing options pane.");

        if (!is_running())
            return;

        do_upload();
    }

    private void on_upload_status_updated(int file_number, double completed_fraction) {
        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);
        
        if (!is_running())
            return;

        progress_reporter(file_number, completed_fraction);
    }

    private void on_upload_complete(Publishing.RESTSupport.BatchUploader uploader,
        int num_published) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);
        
        debug("EVENT: uploader reports upload complete; %d items published.", num_published);

        if (!is_running())
            return;

        do_show_success_pane();
    }

    private void on_upload_error(Publishing.RESTSupport.BatchUploader uploader,
        Spit.Publishing.PublishingError err) {
        uploader.upload_complete.disconnect(on_upload_complete);
        uploader.upload_error.disconnect(on_upload_error);

        if (!is_running())
            return;

        debug("EVENT: uploader reports upload error = '%s'.", err.message);

        get_host().post_error(err);
    }

    private void do_show_service_welcome_pane() {
        debug("ACTION: showing service welcome pane.");

        get_host().install_welcome_pane(SERVICE_WELCOME_MESSAGE, on_service_welcome_login);
    }
    
    private void do_fetch_account_information() {
        debug("ACTION: fetching channel information.");

        get_host().install_account_fetch_wait_pane();
        get_host().set_service_locked(true);

        ChannelDirectoryTransaction directory_trans =
            new ChannelDirectoryTransaction(get_session());
        directory_trans.network_error.connect(on_initial_channel_fetch_error);
        directory_trans.completed.connect(on_initial_channel_fetch_complete);

        try {
            directory_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            on_initial_channel_fetch_error(directory_trans, err);
        }
    }

    private void do_parse_and_display_account_information(ChannelDirectoryTransaction transaction) {
        debug("ACTION: extracting account and channel information from body of server response");

        Publishing.RESTSupport.XmlDocument response_doc;
        try {
            response_doc = Publishing.RESTSupport.XmlDocument.parse_string(
                transaction.get_response(), ChannelDirectoryTransaction.validate_xml);
        } catch (Spit.Publishing.PublishingError err) {
            get_host().post_error(err);
            return;
        }

        try {
            publishing_parameters.set_channel_name(extract_channel_name_helper(
                response_doc.get_root_node()));
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
            builder.add_from_file(
                get_host().get_module_file().get_parent().get_child("youtube_publishing_options_pane.glade").get_path());
        } catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            get_host().post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is unavailable. Publishing to Youtube can't continue.")));
            return;
        }

        PublishingOptionsPane opts_pane = new PublishingOptionsPane(get_host(), builder,
            publishing_parameters);
        opts_pane.publish.connect(on_publishing_options_publish);
        opts_pane.logout.connect(on_publishing_options_logout);
        get_host().install_dialog_pane(opts_pane);

        get_host().set_service_locked(false);
    }

    private void do_upload() {
        debug("ACTION: uploading media items to remote server.");

        get_host().set_service_locked(true);
        get_host().install_account_fetch_wait_pane();
        

        progress_reporter = get_host().serialize_publishables(-1);

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
        refresh_token = null;
        get_host().unset_config_key("refresh_token");
          

        do_show_service_welcome_pane();
    }
}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {
    private class PrivacyDescription {
        public string description;
        public PrivacySetting privacy_setting;

        public PrivacyDescription(string description, PrivacySetting privacy_setting) {
            this.description = description;
            this.privacy_setting = privacy_setting;
        }
    }

    public signal void publish();
    public signal void logout();

    private Gtk.Box pane_widget = null;
    private Gtk.ComboBoxText privacy_combo = null;
    private Gtk.Label publish_to_label = null;
    private Gtk.Label login_identity_label = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private Gtk.Builder builder = null;
    private Gtk.Label privacy_label = null;
    private PrivacyDescription[] privacy_descriptions;
    private PublishingParameters publishing_parameters;

    public PublishingOptionsPane(Spit.Publishing.PluginHost host, Gtk.Builder builder,
        PublishingParameters publishing_parameters) {
        this.privacy_descriptions = create_privacy_descriptions();
        this.publishing_parameters = publishing_parameters;

        this.builder = builder;
        assert(builder != null);
        assert(builder.get_objects().length() > 0);

        login_identity_label = this.builder.get_object("login_identity_label") as Gtk.Label;
        privacy_combo = this.builder.get_object("privacy_combo") as Gtk.ComboBoxText;
        publish_to_label = this.builder.get_object("publish_to_label") as Gtk.Label;
        publish_button = this.builder.get_object("publish_button") as Gtk.Button;
        logout_button = this.builder.get_object("logout_button") as Gtk.Button;
        pane_widget = this.builder.get_object("youtube_pane_widget") as Gtk.Box;
        privacy_label = this.builder.get_object("privacy_label") as Gtk.Label;

        login_identity_label.set_label(_("You are logged into YouTube as %s.").printf(
            publishing_parameters.get_user_name()));
        publish_to_label.set_label(_("Videos will appear in '%s'").printf(
            publishing_parameters.get_channel_name()));

        foreach(PrivacyDescription desc in privacy_descriptions) {
            privacy_combo.append_text(desc.description);
        }

        privacy_combo.set_active(PrivacySetting.PUBLIC);
        privacy_label.set_mnemonic_widget(privacy_combo);

        logout_button.clicked.connect(on_logout_clicked);
        publish_button.clicked.connect(on_publish_clicked);
    }

    private void on_publish_clicked() {
        publishing_parameters.set_privacy(
            privacy_descriptions[privacy_combo.get_active()].privacy_setting);

        publish();
    }

    private void on_logout_clicked() {
        logout();
    }

    private void update_publish_button_sensitivity() {
        publish_button.set_sensitive(true);
    }

    private PrivacyDescription[] create_privacy_descriptions() {
        PrivacyDescription[] result = new PrivacyDescription[0];

        result += new PrivacyDescription(_("Public listed"), PrivacySetting.PUBLIC);
        result += new PrivacyDescription(_("Public unlisted"), PrivacySetting.UNLISTED);
        result += new PrivacyDescription(_("Private"), PrivacySetting.PRIVATE);

        return result;
    }

    public Gtk.Widget get_widget() {
        assert (pane_widget != null);
        return pane_widget;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        update_publish_button_sensitivity();
    }

    public void on_pane_uninstalled() {
    }
}

internal class UploadTransaction : Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    private const string ENDPOINT_URL = "http://uploads.gdata.youtube.com/feeds/api/users/default/uploads";
    private const string UNLISTED_XML = "<yt:accessControl action='list' permission='denied'/>";
    private const string PRIVATE_XML = "<yt:private/>";
    private const string METADATA_TEMPLATE ="""<?xml version='1.0'?>
                                                <entry xmlns='http://www.w3.org/2005/Atom'
                                                xmlns:media='http://search.yahoo.com/mrss/'
                                                xmlns:yt='http://gdata.youtube.com/schemas/2007'>
                                                <media:group>
                                                    <media:title type='plain'>%s</media:title>
                                                    <media:category
                                                    scheme='http://gdata.youtube.com/schemas/2007/categories.cat'>People
                                                    </media:category>
                                                    %s
                                                </media:group>
                                                    %s
                                                </entry>""";
    private PublishingParameters parameters;
    private Publishing.RESTSupport.GoogleSession session;
    private Spit.Publishing.Publishable publishable;

    public UploadTransaction(Publishing.RESTSupport.GoogleSession session,
        PublishingParameters parameters, Spit.Publishing.Publishable publishable) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.POST);
        assert(session.is_authenticated());
        this.session = session;
        this.parameters = parameters;
        this.publishable = publishable;
    }

    public override void execute() throws Spit.Publishing.PublishingError {
        // create the multipart request container
        Soup.Multipart message_parts = new Soup.Multipart("multipart/related");

        string unlisted_video =
            (parameters.get_privacy() == PrivacySetting.UNLISTED) ? UNLISTED_XML : "";

        string private_video =
            (parameters.get_privacy() == PrivacySetting.PRIVATE) ? PRIVATE_XML : "";

        // Set title to publishing name, but if that's empty default to filename.
        string title = publishable.get_publishing_name();
        if (title == "") {
            title = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        }

        string metadata = METADATA_TEMPLATE.printf(Publishing.RESTSupport.decimal_entity_encode(title),
            private_video, unlisted_video);
        Soup.Buffer metadata_buffer = new Soup.Buffer(Soup.MemoryUse.COPY, metadata.data);
        message_parts.append_form_file("", "", "application/atom+xml", metadata_buffer);

        // attempt to read the binary video data from disk
        string video_data;
        size_t data_length;
        try {
            FileUtils.get_contents(publishable.get_serialized_file().get_path(), out video_data,
                out data_length);
        } catch (FileError e) {
            string msg = "YouTube: couldn't read data from %s: %s".printf(
                publishable.get_serialized_file().get_path(), e.message);
            warning("%s", msg);

            throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(msg);
        }

        // bind the binary video data read from disk into a Soup.Buffer object so that we
        // can attach it to the multipart request, then actaully append the buffer
        // to the multipart request. Then, set the MIME type for this part.
        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.COPY,
            video_data.data[0:data_length]);

        message_parts.append_form_file("", publishable.get_serialized_file().get_path(),
            "video/mpeg", bindable_data);
        // create a message that can be sent over the wire whose payload is the multipart container
        // that we've been building up
        Soup.Message outbound_message =
            soup_form_request_new_from_multipart(get_endpoint_url(), message_parts);
        outbound_message.request_headers.append("X-GData-Key", "key=%s".printf(DEVELOPER_KEY));
        outbound_message.request_headers.append("Slug",
            publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME));
        outbound_message.request_headers.append("Authorization", "Bearer " +
            session.get_access_token());
        set_message(outbound_message);

        // send the message and get its response
        set_is_executed(true);
        send();
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

