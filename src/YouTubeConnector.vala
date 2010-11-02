/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

#if !NO_PUBLISHING

namespace YouTubeConnector {
private const string SERVICE_NAME = "YouTube";
private const string SERVICE_WELCOME_MESSAGE =
    _("You are not currently logged into YouTube.\n\nYou must have already signed up for a Google account and set it up for use with YouTube to continue. You can set up most accounts by using your browser to log into the YouTube site at least once.");
private const string DEVELOPER_KEY =
    "AI39si5VEpzWK0z-pzo4fonEj9E4driCpEs9lK8y3HJsbbebIIRWqW3bIyGr42bjQv-N3siAfqVoM8XNmtbbp5x2gpbjiSAMTQ";

private enum PrivacySetting {
    VIDEO_PUBLIC,
    VIDEO_UNLISTED,
    VIDEO_PRIVATE
}

private class PublishingParameters {
    private PrivacySetting privacy_setting;

    public PublishingParameters(PrivacySetting privacy_setting) {
        this.privacy_setting = privacy_setting;
    }

    public PrivacySetting get_privacy_setting() {
        return this.privacy_setting;
    }
}

public class Capabilities : ServiceCapabilities {
    public override string get_name() {
        return SERVICE_NAME;
    }
    
    public override ServiceCapabilities.MediaType get_supported_media() {
        return MediaType.VIDEO;
    }
    
    public override ServiceInteractor factory(PublishingDialog host) {
        return new Interactor(host);
    }
}

public class Interactor : ServiceInteractor {
    private Session session = null;
    private string channel_name = null;
    private PublishingParameters parameters = null;
    private Uploader uploader = null;
    private bool cancelled = false;
    private ProgressPane progress_pane = null;

    public Interactor(PublishingDialog host) {
        base(host);
        session = new Session();
    }

    // EVENT: triggered when the user clicks the "Go Back" button in the credentials capture pane
    private void on_credentials_go_back() {
        // ignore all events if the user has cancelled or we have and error situation
        if (has_error() || cancelled)
            return;

        do_show_service_welcome_pane();
    }

    // EVENT: triggered when the network transaction that fetches the authentication token for
    //        the login account is completed successfully
    //        the response body contains the Auth and YouTubeUser fields
    private void on_token_fetch_complete(RESTTransaction txn) {
        txn.completed.disconnect(on_token_fetch_complete);
        txn.network_error.disconnect(on_token_fetch_error);

        if (has_error() || cancelled)
            return;
        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;

        string auth_substring = txn.get_response().str("Auth=");
        auth_substring = auth_substring.split("\n")[0];
        string auth_token = auth_substring.substring(5);

        TokenFetchTransaction downcast_txn = (TokenFetchTransaction) txn;
        session.authenticate(auth_token, downcast_txn.get_username());

        do_fetch_account_information();
    }

    // EVENT: triggered when the network transaction that fetches the authentication token for
    //        the login account fails
    private void on_token_fetch_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_token_fetch_complete);
        bad_txn.network_error.disconnect(on_token_fetch_error);

        if (has_error() || cancelled)
            return;
        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;

        // HTTP error 403 is invalid authentication -- if we get this error during token fetch
        // then we can just show the login screen again with a retry message; if we get any error
        // other than 403 though, we can't recover from it, so just post the error to the user
        if (bad_txn.get_status_code() == 403) {
            if (bad_txn.get_response().contains("CaptchaRequired"))
                do_show_credentials_capture_pane(CredentialsCapturePane.Mode.ADDITIONAL_SECURITY);
            else
                do_show_credentials_capture_pane(CredentialsCapturePane.Mode.FAILED_RETRY);
        }
        else {
            post_error(err);
        }
    }

    // EVENT: triggered when the user clicks "Login" in the credentials capture pane
    private void on_credentials_login(string username, string password) {
        if (has_error() || cancelled)
            return;

        do_network_login(username, password);
    }

    // EVENT: triggered when the user clicks "Login" in the service welcome pane
    private void on_service_welcome_login() {
        if (has_error() || cancelled)
            return;

        do_show_credentials_capture_pane(CredentialsCapturePane.Mode.INTRO);
    }

    // EVENT: triggered when the user clicks "Logout" in the publishing options pane
    private void on_publishing_options_logout() {
        if (has_error() || cancelled)
            return;

        session.deauthenticate();

        do_show_service_welcome_pane();
    }

    // EVENT: triggered when the user clicks "Publish" in the publishing options pane
    private void on_publishing_options_publish(PublishingParameters parameters) {
        if (has_error() || cancelled)
            return;

        this.parameters = parameters;

        do_upload();
    }

    // EVENT: triggered when the network transaction that fetches the user's account information
    //        is completed successfully
    private void on_initial_album_fetch_complete(RESTTransaction txn) {
        txn.completed.disconnect(on_initial_album_fetch_complete);
        txn.network_error.disconnect(on_initial_album_fetch_error);

        if (has_error() || cancelled)
            return;

        do_parse_and_display_account_information((AlbumDirectoryTransaction) txn);
    }

    // EVENT: triggered when the network transaction that fetches the user's account information
    //        fails
    private void on_initial_album_fetch_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed.disconnect(on_initial_album_fetch_complete);
        bad_txn.network_error.disconnect(on_initial_album_fetch_error);

        if (has_error() || cancelled)
            return;

        if (bad_txn.get_status_code() == 404) {
            // if we get a 404 error (resource not found) on the initial album fetch, then the
            // user's album feed doesn't exist -- this occurs when the user has a valid Google
            // account but it hasn't yet been set up for use with YouTube. In this case, we
            // re-display the credentials capture pane with an "account not set up" message.
            // In addition, we deauthenticate the session. Deauth is neccessary because we
            // did previously auth the user's account. If we get any other kind of error, we can't
            // recover, so just post it to the user
            session.deauthenticate();
            do_show_credentials_capture_pane(CredentialsCapturePane.Mode.NOT_SET_UP);
        } else if (bad_txn.get_status_code() == 403 || bad_txn.get_status_code() == 401) {
            // if we get a 403 error (authentication failed) or 401 (token expired) then we need
            // to return to the login screen because the user's auth token is no longer valid and
            // he or she needs to login again to obtain a new one
            session.deauthenticate();
            do_show_credentials_capture_pane(CredentialsCapturePane.Mode.INTRO);
        } else {
            post_error(err);
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

    // ACTION: display the service welcome pane in the publishing dialog
    private void do_show_service_welcome_pane() {
        LoginWelcomePane service_welcome_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
        service_welcome_pane.login_requested.connect(on_service_welcome_login);

        get_host().unlock_service();
        get_host().set_cancel_button_mode();

        get_host().install_pane(service_welcome_pane);
    }

    // ACTION: display the credentials capture pane in the publishing dialog; the credentials
    //         capture pane can be displayed in different "modes" that display different
    //         messages to the user
    private void do_show_credentials_capture_pane(CredentialsCapturePane.Mode mode) {
        CredentialsCapturePane creds_pane = new CredentialsCapturePane(this, mode);
        creds_pane.go_back.connect(on_credentials_go_back);
        creds_pane.login.connect(on_credentials_login);

        get_host().unlock_service();
        get_host().set_cancel_button_mode();

        get_host().install_pane(creds_pane);
    }

    // ACTION: given a username and password, run a REST transaction over the network to
    //         log a user into the YouTube service
    private void do_network_login(string username, string password) {
        get_host().install_pane(new LoginWaitPane());

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        TokenFetchTransaction fetch_trans = new TokenFetchTransaction(session, username, password);
        fetch_trans.network_error.connect(on_token_fetch_error);
        fetch_trans.completed.connect(on_token_fetch_complete);

        fetch_trans.execute();
    }

    // ACTION: run a REST transaction over the network to fetch the user's account information
    //         While  the network transaction is running, display a wait pane with an info message
    //         in the publishing dialog.
    private void do_fetch_account_information() {
        get_host().install_pane(new AccountFetchWaitPane());

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        AlbumDirectoryTransaction directory_trans =
            new AlbumDirectoryTransaction(session);
        directory_trans.network_error.connect(on_initial_album_fetch_error);
        directory_trans.completed.connect(on_initial_album_fetch_complete);
        directory_trans.execute();
    }

    // ACTION: display the publishing options pane in the publishing dialog
    private void do_show_publishing_options_pane() {
        PublishingOptionsPane opts_pane = new PublishingOptionsPane(this, channel_name);
        opts_pane.publish.connect(on_publishing_options_publish);
        opts_pane.logout.connect(on_publishing_options_logout);
        get_host().install_pane(opts_pane);

        get_host().unlock_service();
        get_host().set_cancel_button_mode();
    }


    // ACTION: run a REST transaction over the network to upload the user's videos to the remote
    //         endpoint. Display a progress pane while the transaction is running.
    private void do_upload() {
        progress_pane = new ProgressPane();
        get_host().install_pane(progress_pane);

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        Video[] videos = get_host().get_videos();
        uploader = new Uploader(session, parameters, videos);

        uploader.upload_complete.connect(on_upload_complete);
        uploader.upload_error.connect(on_upload_error);
        uploader.status_updated.connect(progress_pane.set_status);

        uploader.upload();
    }

    // ACTION: the response body of 'transaction' is an XML document that describes the user's
    //         YouTube account (e.g. the names of the user's albums and their
    //         REST URLs). Parse the response body of 'transaction' and display the publishing
    //         options pane with its widgets populated such that they reflect the user's
    //         account info
    private void do_parse_and_display_account_information(AlbumDirectoryTransaction transaction) {
        RESTXmlDocument response_doc;
        try {
            response_doc = RESTXmlDocument.parse_string(transaction.get_response(),
                AlbumDirectoryTransaction.check_response);
        } catch (PublishingError err) {
            post_error(err);
            return;
        }

        try {
            channel_name = extract_albums(response_doc.get_root_node());
        } catch (PublishingError err) {
            post_error(err);
            return;
        }

        do_show_publishing_options_pane();
    }

    // ACTION: display the success pane in the publishing dialog
    private void do_show_success_pane() {
        get_host().unlock_service();
        get_host().set_close_button_mode();

        get_host().install_pane(new SuccessPane());
    }

    internal Session get_session() {
        return session;
    }

    internal new PublishingDialog get_host() {
        return base.get_host();
    }

    public override string get_name() {
        return SERVICE_NAME;
    }

    public override void start_interaction() {
        get_host().set_standard_window_mode();

        if (!session.is_authenticated()) {
            do_show_service_welcome_pane();
        } else {
            do_fetch_account_information();
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

    public Uploader(Session session, PublishingParameters parameters, Video[] videos) {
        base.with_media((MediaSource[])videos);

        this.parameters = parameters;
        this.session = session;
    }

    protected override RESTTransaction create_transaction_for_file(
        BatchUploader.TemporaryFileDescriptor file) {
        return new VideoUploadTransaction(session, file.source_video, parameters.get_privacy_setting());
    }

    protected override bool prepare_file(BatchUploader.TemporaryFileDescriptor file) {
        return true;
    }
}

private class CredentialsCapturePane : PublishingDialogPane {
    public enum Mode {
        INTRO,
        FAILED_RETRY,
        NOT_SET_UP,
        ADDITIONAL_SECURITY
    }
    private const string INTRO_MESSAGE = _("Enter the email address and password associated with your YouTube account.");
    private const string FAILED_RETRY_MESSAGE = _("YouTube didn't recognize the email address and password you entered. To try again, re-enter your email address and password below.");
    private const string NOT_SET_UP_MESSAGE = _("The email address and password you entered correspond to a Google account that isn't set up for use with YouTube. You can set up most accounts by using your browser to log into the YouTube site at least once. To try again, re-enter your email address and password below.");
    private const string ADDITIONAL_SECURITY_MESSAGE = _("The email address and password you entered correspond to a Google account that has been tagged as requiring additional security. You can clear this tag by using your browser to log into YouTube. To try again, re-enter your email address and password below.");
    
    private const int UNIFORM_ACTION_BUTTON_WIDTH = 102;

    private Gtk.Entry email_entry;
    private Gtk.Entry password_entry;
    private Gtk.Button login_button;
    private Gtk.Button go_back_button;
    private weak Interactor interactor;

    public signal void go_back();
    public signal void login(string email, string password);

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

            case Mode.FAILED_RETRY:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                    "Unrecognized User"), FAILED_RETRY_MESSAGE));
            break;

            case Mode.NOT_SET_UP:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_("Account Not Ready"),
                    NOT_SET_UP_MESSAGE));
                Gtk.SeparatorToolItem long_message_space = new Gtk.SeparatorToolItem();
                long_message_space.set_draw(false);
                add(long_message_space);
                long_message_space.set_size_request(-1, 40);
            break;

            case Mode.ADDITIONAL_SECURITY:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_("Additional Security Required"),
                    ADDITIONAL_SECURITY_MESSAGE));
                Gtk.SeparatorToolItem long_message_space = new Gtk.SeparatorToolItem();
                long_message_space.set_draw(false);
                add(long_message_space);
                long_message_space.set_size_request(-1, 40);
            break;
        }

        Gtk.Alignment entry_widgets_table_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        Gtk.Table entry_widgets_table = new Gtk.Table(3,2, false);
        Gtk.Label email_entry_label = new Gtk.Label.with_mnemonic(_("_Email address:"));
        email_entry_label.set_alignment(0.0f, 0.5f);
        Gtk.Label password_entry_label = new Gtk.Label.with_mnemonic(_("_Password:"));
        password_entry_label.set_alignment(0.0f, 0.5f);
        email_entry = new Gtk.Entry();
        email_entry.changed.connect(on_email_changed);
        password_entry = new Gtk.Entry();
        password_entry.set_visibility(false);
        entry_widgets_table.attach(email_entry_label, 0, 1, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(password_entry_label, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(email_entry, 1, 2, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        entry_widgets_table.attach(password_entry, 1, 2, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 6);
        go_back_button = new Gtk.Button.with_mnemonic(_("Go _Back"));
        go_back_button.clicked.connect(on_go_back_button_clicked);
        Gtk.Alignment go_back_button_aligner = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        go_back_button_aligner.add(go_back_button);
        go_back_button.set_size_request(UNIFORM_ACTION_BUTTON_WIDTH, -1);
        login_button = new Gtk.Button.with_mnemonic(_("_Login"));
        login_button.clicked.connect(on_login_button_clicked);
        login_button.set_sensitive(false);
        Gtk.Alignment login_button_aligner = new Gtk.Alignment(1.0f, 0.5f, 0.0f, 0.0f);
        login_button_aligner.add(login_button);
        login_button.set_size_request(UNIFORM_ACTION_BUTTON_WIDTH, -1);
        entry_widgets_table.attach(go_back_button_aligner, 0, 1, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 40);
        entry_widgets_table.attach(login_button_aligner, 1, 2, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 40);
        entry_widgets_table_aligner.add(entry_widgets_table);
        add(entry_widgets_table_aligner);

        email_entry_label.set_mnemonic_widget(email_entry);
        password_entry_label.set_mnemonic_widget(password_entry);

        add(bottom_space);
        bottom_space.set_size_request(-1, 40);
    }

    private void on_login_button_clicked() {
        login(email_entry.get_text(), password_entry.get_text());
    }

    private void on_go_back_button_clicked() {
        go_back();
    }

    private void on_email_changed() {
        login_button.set_sensitive(email_entry.get_text() != "");
    }

    public override void installed() {
        email_entry.grab_focus();
        password_entry.set_activates_default(true);
        login_button.can_default = true;
        interactor.get_host().set_default(login_button);
    }
}

private class PublishingOptionsPane : PublishingDialogPane {
    private struct PrivacyDescription {
        private string description;
        private PrivacySetting privacy_setting;

        PrivacyDescription(string description, PrivacySetting privacy_setting) {
            this.description = description;
            this.privacy_setting = privacy_setting;
        }
    }

    private const int PACKER_VERTICAL_PADDING = 16;
    private const int PACKER_HORIZ_PADDING = 128;
    private const int INTERSTITIAL_VERTICAL_SPACING = 20;
    private const int ACTION_BUTTON_SPACING = 48;

    private Gtk.ComboBox privacy_combo;
    private Interactor interactor;
    private string channel_name;
    private PrivacyDescription[] privacy_descriptions;
    private Gtk.Button publish_button;

    public signal void publish(PublishingParameters parameters);
    public signal void logout();

    public PublishingOptionsPane(Interactor interactor, string channel_name) {
        this.interactor = interactor;
        this.channel_name = channel_name;
        this.privacy_descriptions = create_privacy_descriptions();

        Gtk.SeparatorToolItem top_pusher = new Gtk.SeparatorToolItem();
        top_pusher.set_draw(false);
        top_pusher.set_size_request(-1, 8);
        add(top_pusher);

        Gtk.Label login_identity_label =
            new Gtk.Label(_("You are logged into YouTube as %s.").printf(
            interactor.get_session().get_username()));

        add(login_identity_label);

        Gtk.Label publish_to_label =
            new Gtk.Label(_("Videos will appear in %s").printf(channel_name));

        add(publish_to_label);

        Gtk.VBox vert_packer = new Gtk.VBox(false, 0);
        Gtk.SeparatorToolItem packer_top_padding = new Gtk.SeparatorToolItem();
        packer_top_padding.set_draw(false);
        packer_top_padding.set_size_request(-1, PACKER_VERTICAL_PADDING);

        Gtk.SeparatorToolItem identity_table_spacer = new Gtk.SeparatorToolItem();
        identity_table_spacer.set_draw(false);
        identity_table_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING);
        vert_packer.add(identity_table_spacer);

        Gtk.Table main_table = new Gtk.Table(6, 3, false);

        Gtk.SeparatorToolItem suboption_indent_spacer = new Gtk.SeparatorToolItem();
        suboption_indent_spacer.set_draw(false);
        suboption_indent_spacer.set_size_request(2, -1);
        main_table.attach(suboption_indent_spacer, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        Gtk.Label privacy_label = new Gtk.Label.with_mnemonic(_("Video privacy _setting:"));
        privacy_label.set_alignment(0.0f, 0.5f);
        main_table.attach(privacy_label, 0, 2, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        privacy_combo = new Gtk.ComboBox.text();
        foreach(PrivacyDescription desc in privacy_descriptions)
            privacy_combo.append_text(desc.description);
        privacy_combo.set_active(PrivacySetting.VIDEO_PUBLIC);
        Gtk.Alignment privacy_combo_frame = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        privacy_combo_frame.add(privacy_combo);
        main_table.attach(privacy_combo_frame, 2, 3, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        privacy_label.set_mnemonic_widget(privacy_combo);

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
        PrivacySetting privacy_setting = privacy_descriptions[privacy_combo.get_active()].privacy_setting;

        publish(new PublishingParameters(privacy_setting));
    }

    private void on_logout_clicked() {
        logout();
    }

    private void update_publish_button_sensitivity() {
        publish_button.set_sensitive(true);
    }

    private PrivacyDescription[] create_privacy_descriptions() {
        PrivacyDescription[] result = new PrivacyDescription[0];

        result += PrivacyDescription(_("Public listed"), PrivacySetting.VIDEO_PUBLIC);
        result += PrivacyDescription(_("Public unlisted"), PrivacySetting.VIDEO_UNLISTED);
        result += PrivacyDescription(_("Private"), PrivacySetting.VIDEO_PRIVATE);

        return result;
    }


    public override void installed() {
        update_publish_button_sensitivity();
    }
}

private class Session : RESTSession {
    private string auth_token = null;
    private string username = null;

    public Session() {
        base("");
        if (has_persistent_state())
            load_persistent_state();
    }

    private bool has_persistent_state() {
        Config config = Config.get_instance();

        return ((config.get_publishing_string("youtube", "user_name") != null) &&
                (config.get_publishing_string("youtube", "auth_token") != null));
    }

    private void save_persistent_state() {
        Config config = Config.get_instance();

        config.set_publishing_string("youtube", "user_name", username);
        config.set_publishing_string("youtube", "auth_token", auth_token);
    }

    private void load_persistent_state() {
        Config config = Config.get_instance();

        username = config.get_publishing_string("youtube", "user_name");
        auth_token = config.get_publishing_string("youtube", "auth_token");
    }

    private void clear_persistent_state() {
        Config config = Config.get_instance();

        config.set_publishing_string("youtube", "user_name", "");
        config.set_publishing_string("youtube", "auth_token", "");
    }

    public bool is_authenticated() {
        return (auth_token != null);
    }

    public void authenticate(string auth_token, string username) {
        this.auth_token = auth_token;
        this.username = username;

        save_persistent_state();
    }

    public void deauthenticate() {
        auth_token = null;
        username = null;

        clear_persistent_state();
    }

    public string get_username() {
        return username;
    }

    public string get_auth_token() {
        return auth_token;
    }
}

private class TokenFetchTransaction : RESTTransaction {
    private const string ENDPOINT_URL = "https://www.google.com/youtube/accounts/ClientLogin";
    private string username;

    public TokenFetchTransaction(Session session, string username, string password) {
        base.with_endpoint_url(session, ENDPOINT_URL);

        this.username = username;
        add_header("Content-Type", "application/x-www-form-urlencoded");
        add_argument("Email", username);
        add_argument("Passwd", password);
        add_argument("service", "youtube");
    }

    protected override void sign() {
        set_signature_key("source");
        set_signature_value("yorba-shotwell-" + Resources.APP_VERSION);
    }

    public string get_username() {
        return username;
    }
}

private class AuthenticatedTransaction : RESTTransaction {
    public AuthenticatedTransaction(Session session, string endpoint_url, HttpMethod method) {
        base.with_endpoint_url(session, endpoint_url, method);
        assert(session.is_authenticated());

        add_header("Authorization", "GoogleLogin auth=%s".printf(session.get_auth_token()));
        add_header("X-GData-Key", "key=%s".printf(DEVELOPER_KEY));
    }
}

private class AlbumDirectoryTransaction : AuthenticatedTransaction {
    private const string ENDPOINT_URL = "http://gdata.youtube.com/feeds/users/default";

    public AlbumDirectoryTransaction(Session session) {
        base(session, ENDPOINT_URL, HttpMethod.GET);
    }

    public static new string? check_response(RESTXmlDocument doc) {
        Xml.Node* document_root = doc.get_root_node();
        if ((document_root->name == "feed") || (document_root->name == "entry"))
            return null;
        else
            return "response root node isn't a <feed> or <entry>";
    }
}

private class VideoUploadTransaction : AuthenticatedTransaction {
    private const string ENDPOINT_URL = "http://uploads.gdata.youtube.com/feeds/api/users/default/uploads";
    private const string VIDEO_UNLISTED_XML = "<yt:accessControl action='list' permission='denied'/>";
    private const string VIDEO_PRIVATE_XML = "<yt:private/>";
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
    private string source_file;
    private Video source_video = null;
    private Session session;
    private PrivacySetting privacy_setting;

    public VideoUploadTransaction(Session session, Video source_video, PrivacySetting privacy_setting) {
        base(session, ENDPOINT_URL, HttpMethod.POST);

        this.source_file = source_video.get_file().get_path();
        this.source_video = source_video;
        this.session = session;
        this.privacy_setting = privacy_setting;
        add_header("Slug", source_video.get_name());
    }

    public override void execute() {
        sign();

        // before they can be executed, video upload requests must be signed and must
        // contain at least one argument
        assert(get_is_signed());

        // create the multipart request container
        Soup.Multipart message_parts = new Soup.Multipart("multipart/related");

        string unlisted_video =
            (privacy_setting == PrivacySetting.VIDEO_UNLISTED) ? VIDEO_UNLISTED_XML : "";

        string private_video =
            (privacy_setting == PrivacySetting.VIDEO_PRIVATE) ? VIDEO_PRIVATE_XML : "";

        string metadata = METADATA_TEMPLATE.printf(source_video.get_name(), private_video, unlisted_video);
        Soup.Buffer metadata_buffer = new Soup.Buffer(Soup.MemoryUse.COPY, metadata, metadata.length);
        message_parts.append_form_file("", "", "application/atom+xml", metadata_buffer);

        // attempt to read the binary image data from disk
        string video_data;
        size_t data_length;
        try {
            FileUtils.get_contents(source_file, out video_data, out data_length);
        } catch (FileError e) {
            error("VideoUploadTransaction: couldn't read data from file '%s'", source_file);
        }

        // bind the binary image data read from disk into a Soup.Buffer object so that we
        // can attach it to the multipart request, then actaully append the buffer
        // to the multipart request. Then, set the MIME type for this part.
        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.COPY, video_data, data_length);
        // TODO: put the actual mime-type of the video here even though YouTube probably
        // figures out the format anyway
        message_parts.append_form_file("", source_file, "video/mpg", bindable_data);

        // create a message that can be sent over the wire whose payload is the multipart container
        // that we've been building up
        Soup.Message outbound_message =
            Soup.form_request_new_from_multipart(get_endpoint_url(), message_parts);
        outbound_message.request_headers.append("Authorization", "GoogleLogin auth=%s".printf(session.get_auth_token()));
        outbound_message.request_headers.append("X-GData-Key", "key=%s".printf(DEVELOPER_KEY));
        outbound_message.request_headers.append("Slug", source_video.get_name());
        set_message(outbound_message);

        // send the message and get its response
        set_is_executed(true);
        send();
    }
}

private string extract_albums(Xml.Node* document_root) throws PublishingError {
    string result = "";

    Xml.Node* doc_node_iter = null;
    if (document_root->name == "feed")
        doc_node_iter = document_root->children;
    else if (document_root->name == "entry")
        doc_node_iter = document_root;
    else
        throw new PublishingError.MALFORMED_RESPONSE("response root node isn't a <feed> or <entry>");

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

        result = name_val;
        break;
    }

    return result;
}

}

#endif

