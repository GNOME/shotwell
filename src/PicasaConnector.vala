/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

namespace PicasaConnector {
private const string SERVICE_WELCOME_MESSAGE = 
    _("You are not currently logged in to Picasa Web Albums.\n\nYou must have already signed up for a Google account and set it up for use with Picasa to continue. You can set up most accounts by using your browser to login to the Picasa Web Albums site at least once.");
private const string DEFAULT_ALBUM_NAME = _("Shotwell Connect");

private enum FeedState {
    INDETERMINATE,
    EXISTS,
    DOES_NOT_EXIST
}

private struct Album {
    string name;
    string url;

    Album(string name, string url) {
        this.name = name;
        this.url = url;
    }
}

private class PublishingRequest {
    private string album_name;
    private string album_url;
    private bool album_public;
    public int photo_major_axis_size;
    
    private PublishingRequest() {
    }

    public PublishingRequest.to_new_album(int photo_major_axis_size, string album_name,
        bool album_public) {
        this.photo_major_axis_size = photo_major_axis_size;
        this.album_name = album_name;
        this.album_public = album_public;
    }

    public PublishingRequest.to_existing_album(int photo_major_axis_size, string album_url) {
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

    // converts a publish-to-new-album request into a publish-to-existing-album request
    public void convert(string album_url) {
        assert(is_to_new_album());
        album_name = null;
        this.album_url = album_url;
    }
}

public class Interactor : ServiceInteractor {
    private Session session;
    private FeedState state;

    public Interactor(PublishingDialog host) {
        base(host);
        session = new Session();
        state = FeedState.INDETERMINATE;
    }
   
    public override string get_name() {
        return "Picasa Web Albums";
    }
    
    public override void start_interaction() throws PublishingError {
        if (!session.is_authenticated()) {
            on_logout();
        } else {
            on_login_authentication_succeeded();
        }
    }

    internal void on_feed_state_determined(FeedState state) {
        this.state = state;
    }
    
    public override void cancel_interaction() {
    }

    private void on_show_login_pane_requested() {
        CredentialsCapturePane login_pane =
            new CredentialsCapturePane(this, CredentialsCapturePane.Mode.INTRO);
        login_pane.go_back += on_go_back_action_requested;
        login_pane.login += on_login_action_requested;
        get_host().set_cancel_button_mode();
        get_host().install_pane(login_pane);
        try {
            login_pane.run_interaction();
        } catch (PublishingError e) {
            get_host().on_error(e);
            return;
        }
    }

    private void on_login_action_requested(string username, string password) {
        LoginActionPane network_action_pane = new LoginActionPane(this, username, password);
        network_action_pane.authentication_failed += on_login_authentication_failed;
        network_action_pane.authentication_succeeded += on_login_authentication_succeeded;
        install_temporary_pane(network_action_pane);
        try {
            network_action_pane.run_interaction();
        } catch (PublishingError e) {
            get_host().on_error(e);
        }
    }

    private void on_go_back_action_requested() {
        LoginWelcomePane not_logged_in_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
        not_logged_in_pane.login_requested += on_show_login_pane_requested;
        get_host().set_cancel_button_mode();
        get_host().install_pane(not_logged_in_pane);
    }

    private void on_login_authentication_failed() {
        CredentialsCapturePane login_pane =
            new CredentialsCapturePane(this, CredentialsCapturePane.Mode.FAILED_RETRY);
        login_pane.go_back += on_go_back_action_requested;
        login_pane.login += on_login_action_requested;
        get_host().set_cancel_button_mode();
        get_host().unlock_service();
        get_host().install_pane(login_pane);
        try {
            login_pane.run_interaction();
        } catch (PublishingError e) {
            get_host().on_error(e);
            return;
        }
    }

    private void on_login_authentication_succeeded() {
        assert(session.is_authenticated());
        PublishingOptionsPane opts_pane = new PublishingOptionsPane(this);
        opts_pane.feed_state_determined += on_feed_state_determined;
        opts_pane.publish += on_publish;
        opts_pane.logout += on_logout;
        try {
            opts_pane.run_interaction();
        } catch (PublishingError e) {
            get_host().on_error(e);
            return;
        }
        assert(state != FeedState.INDETERMINATE); // part of the contract we have with the options
                                                  // pane is that it will determine the state of the
                                                  // authenticated user's feed when its interaction
                                                  // is run
        get_host().set_cancel_button_mode();
        get_host().unlock_service();
        if (state == FeedState.EXISTS) {
            get_host().install_pane(opts_pane);
        } else {
            CredentialsCapturePane login_pane =
                new CredentialsCapturePane(this, CredentialsCapturePane.Mode.NOT_SET_UP);
            login_pane.go_back += on_go_back_action_requested;
            login_pane.login += on_login_action_requested;
            get_host().install_pane(login_pane);
            try {
                login_pane.run_interaction();
            } catch (PublishingError e) {
                get_host().on_error(e);
                return;
            }
        }
        state = FeedState.INDETERMINATE;
    }
    
    private void on_logout() {
        session.deauthenticate();
        state = FeedState.INDETERMINATE;

        LoginWelcomePane not_logged_in_pane = new LoginWelcomePane(SERVICE_WELCOME_MESSAGE);
        not_logged_in_pane.login_requested += on_show_login_pane_requested;
        get_host().set_cancel_button_mode();
        get_host().install_pane(not_logged_in_pane);
        get_host().unlock_service();
    }
    
    private void on_publish(PublishingRequest request) {
        get_host().set_cancel_button_mode();
        get_host().lock_service();
        if (request.is_to_new_album()) {
            AlbumCreationPane album_creation_pane = new AlbumCreationPane(this, request);
            get_host().install_pane(album_creation_pane);
            try {
                album_creation_pane.run_interaction();
            } catch (PublishingError e) {
                get_host().on_error(e);
                return;
            }
        }
        UploadPane upload_pane = new UploadPane(get_host(), session, request);
        get_host().install_pane(upload_pane);
        try {
            upload_pane.upload();
        } catch (PublishingError e) {
            get_host().on_error(e);
            return;
        }
        SuccessPane success_pane = new SuccessPane();
        get_host().install_pane(success_pane);
        get_host().set_close_button_mode();
        get_host().unlock_service();
    }

    internal Session get_session() {
        return session;
    }

    internal new  PublishingDialog get_host() {
        return base.get_host();
    }

    public void install_temporary_pane(PublishingDialogPane pane) {
        get_host().lock_service();
        get_host().set_cancel_button_mode();
        get_host().install_pane(pane);
    }
}

private class UploadPane : UploadActionPane {
    private PublishingRequest request;
    private Session session;

    public UploadPane(PublishingDialog host, Session session, PublishingRequest request) {
        base(host);

        this.session = session;
        this.request = request;
    }

    protected override void prepare_file(UploadActionPane.TemporaryFileDescriptor file) {
        Scaling scaling = (request.get_photo_major_axis_size() == ORIGINAL_SIZE)
            ? Scaling.for_original() : Scaling.for_best_fit(request.get_photo_major_axis_size(), false);
        
        try {
            file.source_photo.export(file.temp_file, scaling, Jpeg.Quality.MAXIMUM);
        } catch (Error e) {
            error("UploadPane: can't create temporary files");
        }
    }

    protected override void upload_file(UploadActionPane.TemporaryFileDescriptor file) 
        throws PublishingError {
        PicasaUploadTransaction upload_req = new PicasaUploadTransaction(session, request,
            file.temp_file.get_path(), file.source_photo.get_name());
        upload_req.chunk_transmitted += on_chunk_transmitted;
        upload_req.execute();
        upload_req.chunk_transmitted -= on_chunk_transmitted;
    }
}

private class CredentialsCapturePane : PublishingDialogPane {
    public enum Mode {
        INTRO,
        FAILED_RETRY,
        NOT_SET_UP
    }
    private const string INTRO_MESSAGE = _("Enter the email address and password associated with your Picasa Web Albums account.");
    private const string FAILED_RETRY_MESSAGE = _("Picasa Web Albums didn't recognize the email address and password you entered. To try again, re-enter your email address and password below.");
    private const string NOT_SET_UP_MESSAGE = _("The email address and password you entered correspond to a Google account that isn't set up for use with Picasa Web Albums. You can set up most accounts by using your browser to login to the Picasa Web Albums site at least once. To try again, re-enter your email address and password below.");
    
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

    public override void run_interaction() throws PublishingError {
        email_entry.grab_focus();
        password_entry.set_activates_default(true);
        login_button.can_default = true;
        interactor.get_host().set_default(login_button);
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
}

private class LoginActionPane : StaticMessagePane {
    private const string LOGIN_WAIT_MESSAGE = _("Logging in...");

    private string username;
    private string password;
    private weak Interactor interactor;

    public signal void authentication_failed();
    public signal void authentication_succeeded();

    public LoginActionPane(Interactor interactor, string username, string password) {
        base(LOGIN_WAIT_MESSAGE);
        this.interactor = interactor;
        this.username = username;
        this.password = password;
    }

    public override void run_interaction() throws PublishingError {
        Session session = interactor.get_session();
        TokenFetchTransaction fetch_trans = new TokenFetchTransaction(session, username, password);

        try {
            fetch_trans.execute();
        } catch (PublishingError err) {
            if (fetch_trans.get_status_code() == 403) { // HTTP error 403 is invalid authentication
                authentication_failed();
                return;
            }
            else {
                throw err;
            }
        }

        string auth_substring = fetch_trans.get_response().str("Auth=");
        auth_substring = auth_substring.chomp();
        string auth_token = auth_substring.substring(5);

        session.authenticate(auth_token, username);

        authentication_succeeded();
    }
}

private class AlbumCreationPane : StaticMessagePane {
    private const string CREATE_WAIT_MESSAGE = _("Creating album...");

    private weak Interactor interactor;
    private PublishingRequest request;

    public AlbumCreationPane(Interactor interactor, PublishingRequest request) {
        base(CREATE_WAIT_MESSAGE);
        assert(request.is_to_new_album());
        this.request = request;
        this.interactor = interactor;
    }

    public override void run_interaction() throws PublishingError {
        Session session = interactor.get_session();
        AlbumCreationTransaction creation_trans = new AlbumCreationTransaction(session, request);
        creation_trans.execute();

        RESTXmlDocument response_doc = RESTXmlDocument.parse_string(creation_trans.get_response(),
            AlbumCreationTransaction.check_response);
        Album[] response_albums = extract_albums(response_doc.get_root_node());
        if (response_albums.length != 1)
            throw new PublishingError.MALFORMED_RESPONSE("album creation transaction " +
                "responses must contain one and only one album directory entry");
        request.convert(response_albums[0].url);
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

    private const int PACKER_VERTICAL_PADDING = 32;
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
    private Album[] albums_cache = null;
    private SizeDescription[] size_descriptions;
    private Gtk.Button publish_button;

    public signal void feed_state_determined(FeedState state);
    public signal void publish(PublishingRequest request);
    public signal void logout();

    public PublishingOptionsPane(Interactor interactor) {
        this.interactor = interactor;
        size_descriptions = create_size_descriptions();

        Gtk.HBox horiz_packer = new Gtk.HBox(false, 0);
        Gtk.SeparatorToolItem packer_left_padding = new Gtk.SeparatorToolItem();
        packer_left_padding.set_draw(false);
        packer_left_padding.set_size_request(PACKER_HORIZ_PADDING, -1);
        horiz_packer.add(packer_left_padding);

        Gtk.VBox vert_packer = new Gtk.VBox(false, 0);
        Gtk.SeparatorToolItem packer_top_padding = new Gtk.SeparatorToolItem();
        packer_top_padding.set_draw(false);
        packer_top_padding.set_size_request(-1, PACKER_VERTICAL_PADDING);
        vert_packer.add(packer_top_padding);

        Gtk.Label login_identity_label =
            new Gtk.Label(_("You are logged in to Picasa Web Albums as %s").printf(
            interactor.get_session().get_username()));

        vert_packer.add(login_identity_label);

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
        packer_bottom_padding.set_size_request(-1, PACKER_VERTICAL_PADDING);
        vert_packer.add(packer_bottom_padding);

        horiz_packer.add(vert_packer);

        Gtk.SeparatorToolItem packer_right_padding = new Gtk.SeparatorToolItem();
        packer_right_padding.set_draw(false);
        packer_right_padding.set_size_request(PACKER_HORIZ_PADDING, -1);
        horiz_packer.add(packer_right_padding);

        add(horiz_packer);
    }

    public override void run_interaction() throws PublishingError {
        StaticMessagePane wait_notification_pane =
            new StaticMessagePane(_("Fetching account information..."));
        interactor.install_temporary_pane(wait_notification_pane);

        AlbumDirectoryTransaction directory_trans =
            new AlbumDirectoryTransaction(interactor.get_session());
        directory_trans.execute();
        if (directory_trans.get_status_code() == 404) {
            // if we get a 404 error here, we were able to complete Google federated
            // login (so the user has a valid Google account), but his account hasn't been
            // associated with a Picasa feed because the user hasn't yet used Picasa with his
            // account. We can't proceed, so signal the Interactor that we've determined that
            // no feed exists for this user
            feed_state_determined(FeedState.DOES_NOT_EXIST);
        } else {
            feed_state_determined(FeedState.EXISTS);
        }

        RESTXmlDocument response_doc = RESTXmlDocument.parse_string(directory_trans.get_response(),
            AlbumDirectoryTransaction.check_response);

        Album[] albums = extract_albums(response_doc.get_root_node());
        albums_cache = albums;
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
            } else {
                create_new_radio.set_active(true);
                existing_albums_combo.set_active(0);
                new_album_entry.set_text(DEFAULT_ALBUM_NAME);
                new_album_entry.grab_focus();
            }
        }
        update_publish_button_sensitivity();
    }

    private void on_publish_clicked() {
        Config.get_instance().set_picasa_default_size(size_combo.get_active());            
        int photo_major_axis_size = size_descriptions[size_combo.get_active()].major_axis_pixels;
        if (create_new_radio.get_active()) {
            string album_name = new_album_entry.get_text();
            bool is_public = public_check.get_active();
            publish(new PublishingRequest.to_new_album(photo_major_axis_size, album_name,
                is_public));
        } else {
            string album_url = albums_cache[existing_albums_combo.get_active()].url;
            publish(new PublishingRequest.to_existing_album(photo_major_axis_size, album_url));
        }
    }

    private void on_use_existing_radio_clicked() {
        existing_albums_combo.set_sensitive(true);
        new_album_entry.set_sensitive(false);
        existing_albums_combo.grab_focus();
        update_publish_button_sensitivity();
    }

    private void on_create_new_radio_clicked() {
        new_album_entry.set_sensitive(true);
        existing_albums_combo.set_sensitive(false);
        new_album_entry.grab_focus();
        update_publish_button_sensitivity();
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
}

private class Session : RESTSession {
    private string auth_token = null;
    private string username = null;

    public Session() {
        base("");
        if (has_persistent_state())
            load_persistent_state();
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

    public override RESTTransaction create_transaction() {
        error("PicasaWeb sessions don't support creating generic child transactions");
        return new TokenFetchTransaction(this, "", "");
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
}

private class TokenFetchTransaction : RESTTransaction {
    private const string ENDPOINT_URL = "https://www.google.com/accounts/ClientLogin";

    public TokenFetchTransaction(Session session, string username, string password) {
        base.with_endpoint_url(session, ENDPOINT_URL);

        add_argument("accountType", "HOSTED_OR_GOOGLE");
        add_argument("Email", username);
        add_argument("Passwd", password);
        add_argument("service", "lh2");
    }

    protected override void sign() {
        set_signature_key("source");
        set_signature_value("yorba-shotwell-" + Resources.APP_VERSION);
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

    public static string? check_response(RESTXmlDocument doc) {
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
    
    public AlbumCreationTransaction(Session session, PublishingRequest request) {
        base(session, ENDPOINT_URL, HttpMethod.POST);

        string post_body = ALBUM_ENTRY_TEMPLATE.printf(request.get_album_name(),
            request.is_album_public() ? "public" : "private");
        set_custom_payload(post_body, "application/atom+xml");
    }

    public static string? check_response(RESTXmlDocument doc) {
        // The album creation response uses the same schema as the album directory response
        return AlbumDirectoryTransaction.check_response(doc);
    }
}

private class PicasaUploadTransaction : AuthenticatedTransaction {
    private PublishingRequest request;
    private string source_file;
    private string photo_name;
    private int bytes_written = 0;

    public signal void chunk_transmitted(int transmitted_bytes, int total_bytes);

    public PicasaUploadTransaction(Session session, PublishingRequest request, string source_file,
        string photo_name) {
        base(session, request.get_album_feed_url(), HttpMethod.POST);
        assert(session.is_authenticated());
        this.request = request;
        this.source_file = source_file;
        this.photo_name = photo_name;

        add_header("Slug", photo_name);

        string photo_data;
        ulong data_length;
        try {
            FileUtils.get_contents(source_file, out photo_data, out data_length);
        } catch (FileError e) {
            error("PicasaUploadTransaction: couldn't read data from file '%s'", source_file);
        }

        set_custom_payload(photo_data, "image/jpeg", data_length);
        get_active_message().wrote_body_data += on_wrote_body_data;
    }

    private void on_wrote_body_data(Soup.Buffer written_data) {
        bytes_written += (int) written_data.length;
        chunk_transmitted(bytes_written, (int) get_active_message().request_body.length);
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

