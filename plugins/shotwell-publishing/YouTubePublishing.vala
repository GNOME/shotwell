/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class YouTubeService : Object, Spit.Pluggable, Spit.Publishing.Service {
    private const string ICON_FILENAME = "youtube.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;

    public YouTubeService(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_from_resource
                (Resources.RESOURCE_PATH + "/" + ICON_FILENAME);
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
        return new Publishing.YouTube.YouTubePublisher(this, host);
    }

    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return Spit.Publishing.Publisher.MediaType.VIDEO;
    }

    public void activation(bool enabled) {
    }
}

namespace Publishing.YouTube {

private const string DEVELOPER_KEY =
    "AIzaSyB6hLnm0n5j8Y6Bkvh9bz3i8ADM2bJdYeY";
    
private enum PrivacySetting {
    PUBLIC,
    UNLISTED,
    PRIVATE
}

private class PublishingParameters {
    private PrivacySetting privacy;
    private string? user_name;

    public PublishingParameters() {
        this.privacy = PrivacySetting.PRIVATE;
        this.user_name = null;
    }

    public PrivacySetting get_privacy() {
        return this.privacy;
    }
    
    public void set_privacy(PrivacySetting privacy) {
        this.privacy = privacy;
    }
    
    public string? get_user_name() {
        return user_name;
    }
    
    public void set_user_name(string? user_name) {
        this.user_name = user_name;
    }
}

internal class YouTubeAuthorizer : GData.Authorizer, Object {
    private RESTSupport.GoogleSession session;
    private Spit.Publishing.Authenticator authenticator;

    public YouTubeAuthorizer(RESTSupport.GoogleSession session, Spit.Publishing.Authenticator authenticator) {
        this.session = session;
        this.authenticator = authenticator;
    }

    public bool is_authorized_for_domain(GData.AuthorizationDomain domain) {
        return domain.scope.has_suffix ("auth/youtube");
    }

    public void process_request(GData.AuthorizationDomain? domain,
                                Soup.Message message) {
        if (domain == null) {
            return;
        }

        var header = "Bearer %s".printf(session.get_access_token());
        message.request_headers.replace("Authorization", header);
    }

    public bool refresh_authorization (GLib.Cancellable? cancellable = null) throws GLib.Error {
        this.authenticator.refresh();
        return true;
    }
}

public class YouTubePublisher : Publishing.RESTSupport.GooglePublisher {
    private bool running;
    private PublishingParameters publishing_parameters;
    private Spit.Publishing.ProgressCallback? progress_reporter;
    private Spit.Publishing.Authenticator authenticator;
    private GData.YouTubeService youtube_service;

    public YouTubePublisher(Spit.Publishing.Service service, Spit.Publishing.PluginHost host) {
        base(service, host, "https://gdata.youtube.com/");

        this.running = false;
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

        this.authenticator.authenticate();
    }

    public override void stop() {
        debug("YouTubePublisher: stopped.");

        running = false;

        get_session().stop_transactions();
    }

    protected override void on_login_flow_complete() {
        debug("EVENT: OAuth login flow complete.");
        
        publishing_parameters.set_user_name(get_session().get_user_name());
        
        this.youtube_service = new GData.YouTubeService(DEVELOPER_KEY,
                new YouTubeAuthorizer(get_session(), this.authenticator));
        do_show_publishing_options_pane();
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

    private void do_show_publishing_options_pane() {
        debug("ACTION: showing publishing options pane.");

        Gtk.Builder builder = new Gtk.Builder();

        try {
            builder.add_from_resource (Resources.RESOURCE_PATH +
                    "/youtube_publishing_options_pane.ui");
        } catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            get_host().post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is unavailable. Publishing to YouTube can’t continue.")));
            return;
        }

        PublishingOptionsPane opts_pane = new PublishingOptionsPane(authenticator, get_host(), builder, publishing_parameters);
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
        Uploader uploader = new Uploader(this.youtube_service, get_session(), publishables, publishing_parameters);

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

        if (this.authenticator.can_logout()) {
            this.authenticator.logout();
            this.authenticator.authenticate();
        }
    }

    protected override Spit.Publishing.Authenticator get_authenticator() {
        if (this.authenticator == null) {
            this.authenticator =
                Publishing.Authenticator.Factory.get_instance().create("youtube", get_host());
        }

        return this.authenticator;
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
    private Gtk.Label login_identity_label = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;
    private Gtk.Builder builder = null;
    private Gtk.Label privacy_label = null;
    private PrivacyDescription[] privacy_descriptions;
    private PublishingParameters publishing_parameters;

    public PublishingOptionsPane(Spit.Publishing.Authenticator authenticator,
                                 Spit.Publishing.PluginHost host,
                                 Gtk.Builder builder,
                                 PublishingParameters publishing_parameters) {
        this.privacy_descriptions = create_privacy_descriptions();
        this.publishing_parameters = publishing_parameters;

        this.builder = builder;
        assert(builder != null);
        assert(builder.get_objects().length() > 0);

        login_identity_label = this.builder.get_object("login_identity_label") as Gtk.Label;
        privacy_combo = this.builder.get_object("privacy_combo") as Gtk.ComboBoxText;
        publish_button = this.builder.get_object("publish_button") as Gtk.Button;
        logout_button = this.builder.get_object("logout_button") as Gtk.Button;
        pane_widget = this.builder.get_object("youtube_pane_widget") as Gtk.Box;
        privacy_label = this.builder.get_object("privacy_label") as Gtk.Label;

        if (!authenticator.can_logout()) {
            logout_button.parent.remove(logout_button);
        }

        login_identity_label.set_label(_("You are logged into YouTube as %s.").printf(
            publishing_parameters.get_user_name()));

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
    private const string ENDPOINT_URL = "https://uploads.gdata.youtube.com/feeds/api/users/default/uploads";
    private PublishingParameters parameters;
    private Publishing.RESTSupport.GoogleSession session;
    private Spit.Publishing.Publishable publishable;
    private GData.YouTubeService youtube_service;

    public UploadTransaction(GData.YouTubeService youtube_service, Publishing.RESTSupport.GoogleSession session,
        PublishingParameters parameters, Spit.Publishing.Publishable publishable) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.POST);
        assert(session.is_authenticated());
        this.session = session;
        this.parameters = parameters;
        this.publishable = publishable;
        this.youtube_service = youtube_service;
    }

    public override void execute() throws Spit.Publishing.PublishingError {
        var video = new GData.YouTubeVideo(null);

        var slug = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        // Set title to publishing name, but if that's empty default to filename.
        string title = publishable.get_publishing_name();
        if (title == "") {
            title = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        }
        video.title = title;

        video.is_private = (parameters.get_privacy() == PrivacySetting.PRIVATE);

        if (parameters.get_privacy() == PrivacySetting.UNLISTED) {
            video.set_access_control("list", GData.YouTubePermission.DENIED);
        } else if (!video.is_private) {
            video.set_access_control("list", GData.YouTubePermission.ALLOWED);
        }

        var file = publishable.get_serialized_file();

        try {
            var info = file.query_info(FileAttribute.STANDARD_CONTENT_TYPE + "," +
                                       FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
            var upload_stream = this.youtube_service.upload_video(video, slug,
                    info.get_content_type());
            var input_stream = file.read();

            // Yuck...
            var loop = new MainLoop(null, false);
            this.splice_with_progress.begin(info, input_stream, upload_stream, (obj, res) => {
                try {
                    this.splice_with_progress.end(res);
                } catch (Error error) {
                    critical("Failed to upload: %s", error.message);
                }
                loop.quit();
            });
            loop.run();
            video = this.youtube_service.finish_video_upload(upload_stream);
        } catch (Error error) {
            critical("Upload failed: %s", error.message);
        }
    }

    private async void splice_with_progress(GLib.FileInfo info, GLib.InputStream input, GLib.OutputStream output) throws Error {
        var total_bytes = info.get_size();
        var bytes_to_write = total_bytes;
        uint8 buffer[8192];

        while (bytes_to_write > 0) {
            var bytes_read = yield input.read_async(buffer);
            if (bytes_read == 0)
                break;

            var bytes_written = yield output.write_async(buffer[0:bytes_read]);
            bytes_to_write -= bytes_written;
            chunk_transmitted((int)(total_bytes - bytes_to_write), (int) total_bytes);
        }

        yield output.close_async();
        yield input.close_async();
    }
}

internal class Uploader : Publishing.RESTSupport.BatchUploader {
    private PublishingParameters parameters;
    private GData.YouTubeService youtube_service;

    public Uploader(GData.YouTubeService youtube_service, Publishing.RESTSupport.GoogleSession session,
        Spit.Publishing.Publishable[] publishables, PublishingParameters parameters) {
        base(session, publishables);

        this.parameters = parameters;
        this.youtube_service = youtube_service;
    }

    protected override Publishing.RESTSupport.Transaction create_transaction(
        Spit.Publishing.Publishable publishable) {
        return new UploadTransaction(this.youtube_service, (Publishing.RESTSupport.GoogleSession) get_session(),
            parameters, get_current_publishable());
    }
}

}

