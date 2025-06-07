/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class YouTubeService : Object, Spit.Pluggable, Spit.Publishing.Service {
    public YouTubeService() {
    }

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }

    public unowned string get_id() {
        return "org.gnome.shotwell.publishing.youtube";
    }

    public unowned string get_pluggable_name() {
        return "YouTube";
    }

    public Spit.PluggableInfo get_info() {
        var info = new Spit.PluggableInfo();
        info.authors = "Jani Monoses, Lucas Beeler, Jens Georg";
        info.copyright = _("Copyright 2016 Software Freedom Conservancy Inc.\nCopyright 2022 Jens Georg <mail@jensge.org>");
        info.icon_name = "youtube";

        return info;
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

private enum PrivacySetting {
    PUBLIC,
    UNLISTED,
    PRIVATE;

    public string to_string() {
        switch (this) {
            case PUBLIC:
                return "public";
            case UNLISTED:
                return "unlisted";
            case PRIVATE:
                return "private";
            default:
                assert_not_reached();
        }
    }
}

internal class PublishingParameters {
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

public class YouTubePublisher : Publishing.RESTSupport.GooglePublisher {
    private bool running;
    private PublishingParameters publishing_parameters;
    private Spit.Publishing.ProgressCallback? progress_reporter;
    private Spit.Publishing.Authenticator authenticator;

    public YouTubePublisher(Spit.Publishing.Service service, Spit.Publishing.PluginHost host) {
        base(service, host, "https://www.googleapis.com/upload/youtube/v3/videos");

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

        do_upload.begin();
    }

    private void on_upload_status_updated(int file_number, double completed_fraction) {
        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);
        
        if (!is_running())
            return;

        progress_reporter(file_number, completed_fraction);
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

    private async void do_upload() {
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

        try {
            var num_published = yield uploader.upload_async(on_upload_status_updated);
            debug("EVENT: uploader reports upload complete; %d items published.", num_published);

            if (!is_running())
                return;
    
            do_show_success_pane();
        } catch (Error err) {
            if (!is_running())
                return;

            debug("EVENT: uploader reports upload error = '%s'.", err.message);

            get_host().post_error(err);
        }
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
            logout_button.unparent();
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

        result += new PrivacyDescription(_("Public"), PrivacySetting.PUBLIC);
        result += new PrivacyDescription(_("Private"), PrivacySetting.PRIVATE);
        result += new PrivacyDescription(_("unlisted"), PrivacySetting.UNLISTED);

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

