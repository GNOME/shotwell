/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

namespace PicasaConnector {
private const string SERVICE_WELCOME_MESSAGE = 
    _("You are not currently logged into Picasa Web Albums.\n\nYou must have already signed up for a Google account and set it up for use with Picasa to continue. You can set up most accounts by using your browser to log into the Picasa Web Albums site at least once.");
private const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");

private struct Album {
    string name;
    string url;

    Album(string name, string url) {
        this.name = name;
        this.url = url;
    }
}

private class PublishingParameters : Object {
    private string album_name;
    private string album_url;
    private bool album_public;
    public int photo_major_axis_size;
    
    private PublishingParameters() {
    }

    public PublishingParameters.to_new_album(int photo_major_axis_size, string album_name,
        bool album_public) {
        this.photo_major_axis_size = photo_major_axis_size;
        this.album_name = album_name;
        this.album_public = album_public;
    }

    public PublishingParameters.to_existing_album(int photo_major_axis_size, string album_url) {
        this.photo_major_axis_size = photo_major_axis_size;
        this.album_url = album_url;
    }
    
    public bool is_to_new_album() {
        return (album_name != null);
    }
    
    public bool is_album_public() {
        assert(is_to_new_album());
        return album_public;
    }
    
    public string get_album_name() {
        assert(is_to_new_album());
        return album_name;
    }

    public string get_album_entry_url() {
        assert(!is_to_new_album());
        return album_url;
    }
    
    public string get_album_feed_url() {
        string entry_url = get_album_entry_url();
        string feed_url = entry_url.replace("entry", "feed");

        return feed_url;
    }

    public int get_photo_major_axis_size() {
        return photo_major_axis_size;
    }

    // converts a publish-to-new-album parameters object into a publish-to-existing-album
    // parameters object
    public void convert(string album_url) {
        assert(is_to_new_album());
        album_name = null;
        this.album_url = album_url;
    }
}

public class Interactor : ServiceInteractor {
    private Session session = null;
    private Album[] albums = null;
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
    private void on_token_fetch_complete(RESTTransaction txn) {
        txn.completed -= on_token_fetch_complete;
        txn.network_error -= on_token_fetch_error;

        if (has_error() || cancelled)
            return;
        if (session.is_authenticated()) // ignore these events if the session is already auth'd
            return;

        string auth_substring = txn.get_response().str("Auth=");
        auth_substring = auth_substring.chomp();
        string auth_token = auth_substring.substring(5);

        TokenFetchTransaction downcast_txn = (TokenFetchTransaction) txn;
        session.authenticate(auth_token, downcast_txn.get_username());

        do_fetch_account_information();
    }

    // EVENT: triggered when the network transaction that fetches the authentication token for
    //        the login account fails
    private void on_token_fetch_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed -= on_token_fetch_complete;
        bad_txn.network_error -= on_token_fetch_error;

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

        if (parameters.is_to_new_album()) {
            do_create_album(parameters);
        } else {
            do_upload();
        }
    }

    // EVENT: triggered when the network transaction that fetches the user's account information
    //        is completed successfully
    private void on_initial_album_fetch_complete(RESTTransaction txn) {
        txn.completed -= on_initial_album_fetch_complete;
        txn.network_error -= on_initial_album_fetch_error;

        if (has_error() || cancelled)
            return;

        do_parse_and_display_account_information((AlbumDirectoryTransaction) txn);
    }

    // EVENT: triggered when the network transaction that creates a new album is completed
    //        successfully. This event should occur only when the user is publishing to a
    //        new album.
    private void on_album_creation_complete(RESTTransaction txn) {
        txn.completed -= on_album_creation_complete;
        txn.network_error -= on_album_creation_error;

        if (has_error() || cancelled)
            return;

        AlbumCreationTransaction downcast_txn = (AlbumCreationTransaction) txn;
        RESTXmlDocument response_doc;
        try {
            response_doc = RESTXmlDocument.parse_string(
                downcast_txn.get_response(), AlbumCreationTransaction.check_response);
        } catch (PublishingError err) {
            post_error(err);
            return;
        }

        Album[] response_albums;
        try {
            response_albums = extract_albums(response_doc.get_root_node());
        } catch (PublishingError err) {
            post_error(err);
            return;
        }

        if (response_albums.length != 1) {
            post_error(new PublishingError.MALFORMED_RESPONSE("album creation transaction " +
                "responses must contain one and only one album directory entry"));
            return;
        }
        parameters.convert(response_albums[0].url);

        do_upload();
    }

    // EVENT: triggered when the network transaction that creates a new album fails
    private void on_album_creation_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed -= on_album_creation_complete;
        bad_txn.network_error -= on_album_creation_error;

        if (has_error() || cancelled)
            return;

        post_error(err);
    }

    // EVENT: triggered when the network transaction that fetches the user's account information
    //        fails
    private void on_initial_album_fetch_error(RESTTransaction bad_txn, PublishingError err) {
        bad_txn.completed -= on_initial_album_fetch_complete;
        bad_txn.network_error -= on_initial_album_fetch_error;

        if (has_error() || cancelled)
            return;

        // if we get a 404 error (resource not found) on the initial album fetch, then the
        // user's album feed doesn't exist -- this occurs when the user has a valid Google
        // account but it hasn't yet been set up for use with Picasa. In this case, we
        // re-display the credentials capture pane with an "account not set up" message.
        // In addition, we deauthenticate the session. Deauth is neccessary because we
        // did previously auth the user's account. If we get any other kind of error, we can't
        // recover, so just post it to the user
        if (bad_txn.get_status_code() == 404) {
            session.deauthenticate();
            do_show_credentials_capture_pane(CredentialsCapturePane.Mode.NOT_SET_UP);
        } else {
            post_error(err);
        }
    }

    // EVENT: triggered when the batch uploader reports that all of the network transactions
    //        encapsulating uploads have completed successfully
    private void on_upload_complete(BatchUploader uploader) {
        uploader.upload_complete -= on_upload_complete;
        uploader.upload_error -= on_upload_error;
        uploader.status_updated -= progress_pane.set_status;

        if (has_error() || cancelled)
            return;

        do_show_success_pane();
    }

    // EVENT: triggered when the batch uploader reports that at least one of the network
    //        transactions encapsulating uploads has caused a network error
    private void on_upload_error(BatchUploader uploader, PublishingError err) {
        uploader.upload_complete -= on_upload_complete;
        uploader.upload_error -= on_upload_error;
        uploader.status_updated -= progress_pane.set_status;

        if (has_error() || cancelled)
            return;

        post_error(err);
    }

    // ACTION: display the service welcome pane in the publishing dialog
    private void do_show_service_welcome_pane() {
        LoginWelcomePane service_welcome_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
        service_welcome_pane.login_requested += on_service_welcome_login;

        get_host().unlock_service();
        get_host().set_cancel_button_mode();

        get_host().install_pane(service_welcome_pane);
    }

    // ACTION: display the credentials capture pane in the publishing dialog; the credentials
    //         capture pane can be displayed in different "modes" that display different
    //         messages to the user
    private void do_show_credentials_capture_pane(CredentialsCapturePane.Mode mode) {
        CredentialsCapturePane creds_pane = new CredentialsCapturePane(this, mode);
        creds_pane.go_back += on_credentials_go_back;
        creds_pane.login += on_credentials_login;

        get_host().unlock_service();
        get_host().set_cancel_button_mode();

        get_host().install_pane(creds_pane);
    }

    // ACTION: given a username and password, run a REST transaction over the network to
    //         log a user into the Picasa Web Albums service
    private void do_network_login(string username, string password) {
        get_host().install_pane(new LoginWaitPane());

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        TokenFetchTransaction fetch_trans = new TokenFetchTransaction(session, username, password);
        fetch_trans.network_error += on_token_fetch_error;
        fetch_trans.completed += on_token_fetch_complete;

        fetch_trans.execute();
    }

    // ACTION: run a REST transaction over the network to fetch the user's account information
    //         (e.g. the names of the user's albums and their corresponding REST URLs). While
    //         the network transaction is running, display a wait pane with an info message in
    //         the publishing dialog.
    private void do_fetch_account_information() {
        get_host().install_pane(new AccountFetchWaitPane());

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        AlbumDirectoryTransaction directory_trans =
            new AlbumDirectoryTransaction(session);
        directory_trans.network_error += on_initial_album_fetch_error;
        directory_trans.completed += on_initial_album_fetch_complete;
        directory_trans.execute();
    }

    // ACTION: display the publishing options pane in the publishing dialog
    private void do_show_publishing_options_pane() {
        PublishingOptionsPane opts_pane = new PublishingOptionsPane(this, albums);
        opts_pane.publish += on_publishing_options_publish;
        opts_pane.logout += on_publishing_options_logout;
        get_host().install_pane(opts_pane);

        get_host().unlock_service();
        get_host().set_cancel_button_mode();
    }

    // ACTION: run a REST transaction over the network to create a new album with the parameters
    //         specified in 'parameters'. Display a wait pane with an info message in the
    //         publishing dialog while the transaction is running. This action should only
    //         occur if 'parameters' describes a publish-to-new-album operation.
    private void do_create_album(PublishingParameters parameters) {
        assert(parameters.is_to_new_album());

        get_host().install_pane(new StaticMessagePane(_("Creating album...")));

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        AlbumCreationTransaction creation_trans = new AlbumCreationTransaction(session,
            parameters);
        creation_trans.network_error += on_album_creation_error;
        creation_trans.completed += on_album_creation_complete;
        creation_trans.execute();
    }

    // ACTION: run a REST transaction over the network to upload the user's photos to the remote
    //         endpoint. Display a progress pane while the transaction is running.
    private void do_upload() {
        progress_pane = new ProgressPane();
        get_host().install_pane(progress_pane);

        get_host().lock_service();
        get_host().set_cancel_button_mode();

        TransformablePhoto[] photos = get_host().get_photos();
        uploader = new Uploader(session, parameters, photos);

        uploader.upload_complete += on_upload_complete;
        uploader.upload_error += on_upload_error;
        uploader.status_updated += progress_pane.set_status;

        uploader.upload();
    }

    // ACTION: the response body of 'transaction' is an XML document that describes the user's
    //         Picasa Web Albums account (e.g. the names of the user's albums and their
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
            albums = extract_albums(response_doc.get_root_node());
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
        return "Picasa Web Albums";
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

    public Uploader(Session session, PublishingParameters parameters, TransformablePhoto[] photos) {
        base(photos);

        this.parameters = parameters;
        this.session = session;
    }

    protected override void prepare_file(BatchUploader.TemporaryFileDescriptor file) {
        Scaling scaling = (parameters.get_photo_major_axis_size() == ORIGINAL_SIZE)
            ? Scaling.for_original() : Scaling.for_best_fit(parameters.get_photo_major_axis_size(),
            false);
        
        try {
            file.source_photo.export(file.temp_file, scaling, Jpeg.Quality.MAXIMUM);
        } catch (Error e) {
            error("UploadPane: can't create temporary files");
        }
    }

    protected override RESTTransaction create_transaction_for_file(
        BatchUploader.TemporaryFileDescriptor file) {
        return new PicasaUploadTransaction(session, parameters, file.temp_file.get_path(),
            file.source_photo.get_name());
    }
}

private class CredentialsCapturePane : PublishingDialogPane {
    public enum Mode {
        INTRO,
        FAILED_RETRY,
        NOT_SET_UP,
        ADDITIONAL_SECURITY
    }
    private const string INTRO_MESSAGE = _("Enter the email address and password associated with your Picasa Web Albums account.");
    private const string FAILED_RETRY_MESSAGE = _("Picasa Web Albums didn't recognize the email address and password you entered. To try again, re-enter your email address and password below.");
    private const string NOT_SET_UP_MESSAGE = _("The email address and password you entered correspond to a Google account that isn't set up for use with Picasa Web Albums. You can set up most accounts by using your browser to log into the Picasa Web Albums site at least once. To try again, re-enter your email address and password below.");
    private const string ADDITIONAL_SECURITY_MESSAGE = _("The email address and password you entered correspond to a Google account that has been tagged as requiring additional security. You can clear this tag by using your browser to log into Picasa Web Albums. To try again, re-enter your email address and password below.");
    
    private const int UNIFORM_ACTION_BUTTON_WIDTH = 92;

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
        email_entry.changed += on_email_changed;
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
        go_back_button.clicked += on_go_back_button_clicked;
        Gtk.Alignment go_back_button_aligner = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        go_back_button_aligner.add(go_back_button);
        go_back_button.set_size_request(UNIFORM_ACTION_BUTTON_WIDTH, -1);
        login_button = new Gtk.Button.with_mnemonic(_("_Login"));
        login_button.clicked += on_login_button_clicked;
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
    private struct SizeDescription {
        string name;
        int major_axis_pixels;

        SizeDescription(string name, int major_axis_pixels) {
            this.name = name;
            this.major_axis_pixels = major_axis_pixels;
        }
    }

    private const int PACKER_VERTICAL_PADDING = 16;
    private const int PACKER_HORIZ_PADDING = 128;
    private const int INTERSTITIAL_VERTICAL_SPACING = 20;
    private const int ACTION_BUTTON_SPACING = 48;

    private Gtk.ComboBox existing_albums_combo;
    private Gtk.Entry new_album_entry;
    private Gtk.CheckButton public_check;
    private Gtk.ComboBox size_combo;
    private Gtk.RadioButton use_existing_radio;
    private Gtk.RadioButton create_new_radio;
    private Interactor interactor;
    private Album[] albums;
    private SizeDescription[] size_descriptions;
    private Gtk.Button publish_button;

    public signal void publish(PublishingParameters parameters);
    public signal void logout();

    public PublishingOptionsPane(Interactor interactor, Album[] albums) {
        this.interactor = interactor;
        this.albums = albums;
        size_descriptions = create_size_descriptions();

        Gtk.SeparatorToolItem top_pusher = new Gtk.SeparatorToolItem();
        top_pusher.set_draw(false);
        top_pusher.set_size_request(-1, 8);
        add(top_pusher);

        Gtk.Label login_identity_label =
            new Gtk.Label(_("You are logged into Picasa Web Albums as %s.").printf(
            interactor.get_session().get_username()));

        add(login_identity_label);

        Gtk.HBox horiz_packer = new Gtk.HBox(false, 0);
        Gtk.SeparatorToolItem packer_left_padding = new Gtk.SeparatorToolItem();
        packer_left_padding.set_draw(false);
        packer_left_padding.set_size_request(PACKER_HORIZ_PADDING, -1);
        horiz_packer.add(packer_left_padding);

        Gtk.VBox vert_packer = new Gtk.VBox(false, 0);
        Gtk.SeparatorToolItem packer_top_padding = new Gtk.SeparatorToolItem();
        packer_top_padding.set_draw(false);
        packer_top_padding.set_size_request(-1, PACKER_VERTICAL_PADDING);

        Gtk.SeparatorToolItem identity_table_spacer = new Gtk.SeparatorToolItem();
        identity_table_spacer.set_draw(false);
        identity_table_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING);
        vert_packer.add(identity_table_spacer);

        Gtk.Table main_table = new Gtk.Table(6, 3, false);

        Gtk.Label publish_to_label = new Gtk.Label(_("Photos will appear in:"));
        publish_to_label.set_alignment(0.0f, 0.5f);
        main_table.attach(publish_to_label, 0, 2, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        Gtk.SeparatorToolItem suboption_indent_spacer = new Gtk.SeparatorToolItem();
        suboption_indent_spacer.set_draw(false);
        suboption_indent_spacer.set_size_request(2, -1);
        main_table.attach(suboption_indent_spacer, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        use_existing_radio = new Gtk.RadioButton.with_mnemonic(null, _("An _existing album:"));
        use_existing_radio.clicked += on_use_existing_radio_clicked;
        main_table.attach(use_existing_radio, 1, 2, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        existing_albums_combo = new Gtk.ComboBox.text();
        Gtk.Alignment existing_albums_combo_frame = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        existing_albums_combo_frame.add(existing_albums_combo);
        main_table.attach(existing_albums_combo_frame, 2, 3, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        create_new_radio = new Gtk.RadioButton.with_mnemonic(use_existing_radio.get_group(),
            _("A _new album named:"));
        create_new_radio.clicked += on_create_new_radio_clicked;
        main_table.attach(create_new_radio, 1, 2, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        new_album_entry = new Gtk.Entry();
        new_album_entry.changed += on_new_album_entry_changed;
        main_table.attach(new_album_entry, 2, 3, 2, 3,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        public_check = new Gtk.CheckButton.with_mnemonic(_("L_ist album in public gallery"));
        main_table.attach(public_check, 2, 3, 3, 4,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        Gtk.SeparatorToolItem album_size_spacer = new Gtk.SeparatorToolItem();
        album_size_spacer.set_draw(false);
        album_size_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING / 2);
        main_table.attach(album_size_spacer, 2, 3, 4, 5,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        Gtk.Label size_label = new Gtk.Label.with_mnemonic(_("Photo _size preset:"));
        size_label.set_alignment(0.0f, 0.5f);
        main_table.attach(size_label, 0, 2, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        size_combo = new Gtk.ComboBox.text();
        foreach(SizeDescription desc in size_descriptions)
            size_combo.append_text(desc.name);
        size_combo.set_active(Config.get_instance().get_picasa_default_size());
        Gtk.Alignment size_combo_frame = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        size_combo_frame.add(size_combo);
        main_table.attach(size_combo_frame, 2, 3, 5, 6,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 4, 4);

        size_label.set_mnemonic_widget(size_combo);

        vert_packer.add(main_table);

        Gtk.SeparatorToolItem table_button_spacer = new Gtk.SeparatorToolItem();
        table_button_spacer.set_draw(false);
        table_button_spacer.set_size_request(-1, INTERSTITIAL_VERTICAL_SPACING);
        vert_packer.add(table_button_spacer);

        Gtk.HBox action_button_layouter = new Gtk.HBox(true, 0);
        Gtk.SeparatorToolItem buttons_left_padding = new Gtk.SeparatorToolItem();
        buttons_left_padding.set_draw(false);
        buttons_left_padding.set_size_request(ACTION_BUTTON_SPACING, -1);
        action_button_layouter.add(buttons_left_padding);
        Gtk.Button logout_button = new Gtk.Button.with_mnemonic(_("_Logout"));
        logout_button.clicked += on_logout_clicked;
        logout_button.set_size_request(100, -1);
        Gtk.Alignment logout_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        logout_button_aligner.add(logout_button);
        action_button_layouter.add(logout_button_aligner);
        Gtk.SeparatorToolItem button_spacer = new Gtk.SeparatorToolItem();
        button_spacer.set_draw(false);
        button_spacer.set_size_request(ACTION_BUTTON_SPACING, -1);
        action_button_layouter.add(button_spacer);
        publish_button = new Gtk.Button.with_mnemonic(_("_Publish"));
        publish_button.clicked += on_publish_clicked;
        publish_button.set_size_request(100, -1);
        Gtk.Alignment publish_button_aligner = new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);
        publish_button_aligner.add(publish_button);
        action_button_layouter.add(publish_button_aligner);
        Gtk.SeparatorToolItem buttons_right_padding = new Gtk.SeparatorToolItem();
        buttons_right_padding.set_draw(false);
        buttons_right_padding.set_size_request(ACTION_BUTTON_SPACING, -1);
        action_button_layouter.add(buttons_right_padding);

        vert_packer.add(action_button_layouter);

        Gtk.SeparatorToolItem packer_bottom_padding = new Gtk.SeparatorToolItem();
        packer_bottom_padding.set_draw(false);
        packer_bottom_padding.set_size_request(-1, 2 * PACKER_VERTICAL_PADDING);
        vert_packer.add(packer_bottom_padding);

        horiz_packer.add(vert_packer);

        Gtk.SeparatorToolItem packer_right_padding = new Gtk.SeparatorToolItem();
        packer_right_padding.set_draw(false);
        packer_right_padding.set_size_request(PACKER_HORIZ_PADDING, -1);
        horiz_packer.add(packer_right_padding);

        add(horiz_packer);
    }

    private void on_publish_clicked() {
        Config.get_instance().set_picasa_default_size(size_combo.get_active());            
        int photo_major_axis_size = size_descriptions[size_combo.get_active()].major_axis_pixels;
        if (create_new_radio.get_active()) {
            string album_name = new_album_entry.get_text();
            bool is_public = public_check.get_active();
            publish(new PublishingParameters.to_new_album(photo_major_axis_size, album_name,
                is_public));
        } else {
            string album_url = albums[existing_albums_combo.get_active()].url;
            publish(new PublishingParameters.to_existing_album(photo_major_axis_size, album_url));
        }
    }

    private void on_use_existing_radio_clicked() {
        existing_albums_combo.set_sensitive(true);
        new_album_entry.set_sensitive(false);
        existing_albums_combo.grab_focus();
        update_publish_button_sensitivity();
        public_check.set_sensitive(false);
    }

    private void on_create_new_radio_clicked() {
        new_album_entry.set_sensitive(true);
        existing_albums_combo.set_sensitive(false);
        new_album_entry.grab_focus();
        update_publish_button_sensitivity();
        public_check.set_sensitive(true);
    }

    private void on_logout_clicked() {
        logout();
    }

    private void update_publish_button_sensitivity() {
        publish_button.set_sensitive(!(new_album_entry.get_text() == "" &&
            create_new_radio.get_active()));
    }

    private void on_new_album_entry_changed() {
        update_publish_button_sensitivity();
    }

    private SizeDescription[] create_size_descriptions() {
        SizeDescription[] result = new SizeDescription[0];

        result += SizeDescription(_("Small (640 x 480 pixels)"), 640);
        result += SizeDescription(_("Medium (1024 x 768 pixels)"), 1024);
        result += SizeDescription(_("Recommended (1600 x 1200 pixels)"), 1600);
        result += SizeDescription(_("Original Size"), ORIGINAL_SIZE);

        return result;
    }

    public override void installed() {
        int default_album_id = -1;
        for (int i = 0; i < albums.length; i++) {
            existing_albums_combo.append_text(albums[i].name);
            if (albums[i].name == DEFAULT_ALBUM_NAME)
                default_album_id = i;
        }

        if (albums.length == 0) {
            existing_albums_combo.set_sensitive(false);
            use_existing_radio.set_sensitive(false);
            create_new_radio.set_active(true);
            new_album_entry.grab_focus();
            new_album_entry.set_text(DEFAULT_ALBUM_NAME);
        } else {
            if (default_album_id >= 0) {
                use_existing_radio.set_active(true);
                existing_albums_combo.set_active(default_album_id);
                new_album_entry.set_sensitive(false);
                public_check.set_sensitive(false);
            } else {
                create_new_radio.set_active(true);
                existing_albums_combo.set_active(0);
                new_album_entry.set_text(DEFAULT_ALBUM_NAME);
                new_album_entry.grab_focus();
                public_check.set_sensitive(true);
            }
        }
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

        return ((config.get_picasa_user_name() != null) &&
                (config.get_picasa_auth_token() != null));
    }
    
    private void save_persistent_state() {
        Config config = Config.get_instance();

        config.set_picasa_user_name(username);
        config.set_picasa_auth_token(auth_token);
    }

    private void load_persistent_state() {
        Config config = Config.get_instance();

        username = config.get_picasa_user_name();
        auth_token = config.get_picasa_auth_token();
    }
    
    private void clear_persistent_state() {
        Config config = Config.get_instance();

        config.set_picasa_user_name("");
        config.set_picasa_auth_token("");
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
    private const string ENDPOINT_URL = "https://www.google.com/accounts/ClientLogin";
    private string username;

    public TokenFetchTransaction(Session session, string username, string password) {
        base.with_endpoint_url(session, ENDPOINT_URL);

        this.username = username;

        add_argument("accountType", "HOSTED_OR_GOOGLE");
        add_argument("Email", username);
        add_argument("Passwd", password);
        add_argument("service", "lh2");
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
    private AuthenticatedTransaction.with_endpoint_url(Session session, string endpoint_url,
        HttpMethod method) {
        base.with_endpoint_url(session, endpoint_url, method);
    }

    public AuthenticatedTransaction(Session session, string endpoint_url, HttpMethod method) {
        base.with_endpoint_url(session, endpoint_url, method);
        assert(session.is_authenticated());

        add_header("Authorization", "GoogleLogin auth=%s".printf(session.get_auth_token()));
    }
}

private class AlbumDirectoryTransaction : AuthenticatedTransaction {
    private const string ENDPOINT_URL = "http://picasaweb.google.com/data/feed/api/user/" +
        "default";

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

private class AlbumCreationTransaction : AuthenticatedTransaction {
    private const string ENDPOINT_URL = "http://picasaweb.google.com/data/feed/api/user/" +
        "default";
    private const string ALBUM_ENTRY_TEMPLATE = "<entry xmlns='http://www.w3.org/2005/Atom' xmlns:gphoto='http://schemas.google.com/photos/2007'><title type='text'>%s</title><gphoto:access>%s</gphoto:access><category scheme='http://schemas.google.com/g/2005#kind' term='http://schemas.google.com/photos/2007#album'></category></entry>";
    
    public AlbumCreationTransaction(Session session, PublishingParameters parameters) {
        base(session, ENDPOINT_URL, HttpMethod.POST);

        string post_body = ALBUM_ENTRY_TEMPLATE.printf(parameters.get_album_name(),
            parameters.is_album_public() ? "public" : "private");
        set_custom_payload(post_body, "application/atom+xml");
    }

    public new static string? check_response(RESTXmlDocument doc) {
        // The album creation response uses the same schema as the album directory response
        return AlbumDirectoryTransaction.check_response(doc);
    }
}

private class PicasaUploadTransaction : AuthenticatedTransaction {
    private PublishingParameters parameters;
    private string source_file;
    private string photo_name;

    public PicasaUploadTransaction(Session session, PublishingParameters parameters, string source_file,
        string photo_name) {
        base(session, parameters.get_album_feed_url(), HttpMethod.POST);
        assert(session.is_authenticated());
        this.parameters = parameters;
        this.source_file = source_file;
        this.photo_name = photo_name;

        add_header("Slug", photo_name);

        string photo_data;
        size_t data_length;
        try {
            FileUtils.get_contents(source_file, out photo_data, out data_length);
        } catch (FileError e) {
            error("PicasaUploadTransaction: couldn't read data from file '%s'", source_file);
        }

        set_custom_payload(photo_data, "image/jpeg", data_length);
    }
}

private Album[] extract_albums(Xml.Node* document_root) throws PublishingError {
    Album[] result = new Album[0];

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

        result += Album(name_val, url_val);
    }

    return result;
}

}

#endif

