/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Publishing.GooglePhotos {
internal const string DEFAULT_ALBUM_NAME = N_("Shotwell Connect");
internal const int MAX_BATCH_SIZE = 50;

internal class Album {
    public string name;
    public string id;

    public Album(string name, string id) {
        this.name = name;
        this.id = id;
    }
}

internal class PublishingParameters {
    public const int ORIGINAL_SIZE = -1;

    private string? target_album_name;
    private string? target_album_id;
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
        this.target_album_id = null;
        this.major_axis_size_selection_id = 0;
        this.major_axis_size_pixels = ORIGINAL_SIZE;
        this.album_public = false;
        this.albums = null;
        this.strip_metadata = false;
        this.media_type = Spit.Publishing.Publisher.MediaType.PHOTO;
    }

    public string get_target_album_name() {
        return target_album_name;
    }

    public void set_target_album_name(string? target_album_name) {
        this.target_album_name = target_album_name;
    }

    public void set_target_album_entry_id(string target_album_id) {
        this.target_album_id = target_album_id;
    }

    public string get_target_album_entry_id() {
        return this.target_album_id;
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

private class MediaCreationTransaction : Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    private const string ENDPOINT_URL = "https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate";
    private string[] upload_tokens;
    private string[] titles;
    private string album_id;

    public MediaCreationTransaction(Publishing.RESTSupport.GoogleSession session,
                                    string[] upload_tokens,
                                    string[] titles,
                                    string album_id) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.POST);
        assert(upload_tokens.length == titles.length);
        this.upload_tokens = upload_tokens;
        this.album_id = album_id;
        this.titles = titles;
    }

    public override void execute () throws Spit.Publishing.PublishingError {
        for (var h = 0; h * MAX_BATCH_SIZE < this.upload_tokens.length; h++) {
            var offset = h * MAX_BATCH_SIZE;
            var difference = this.upload_tokens.length - offset;
            int end;

            if (difference > MAX_BATCH_SIZE) {
                end = offset + MAX_BATCH_SIZE;
            }
            else {
                end = offset + difference;
            }

            var builder = new Json.Builder();
            builder.begin_object();
            builder.set_member_name("albumId");
            builder.add_string_value(this.album_id);
            builder.set_member_name("newMediaItems");
            builder.begin_array();
            for (var i = offset; i < end; i++) {
                builder.begin_object();
                builder.set_member_name("description");
                builder.add_string_value(this.titles[i]);
                builder.set_member_name("simpleMediaItem");
                builder.begin_object();
                builder.set_member_name("uploadToken");
                builder.add_string_value(this.upload_tokens[i]);
                builder.end_object();
                builder.end_object();
            }
            builder.end_array();
            builder.end_object();
            set_custom_payload(Json.to_string (builder.get_root (), false), "application/json");

            base.execute();
        }
    }
}

private class AlbumCreationTransaction : Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    private const string ENDPOINT_URL = "https://photoslibrary.googleapis.com/v1/albums";
    private string title;

    public AlbumCreationTransaction(Publishing.RESTSupport.GoogleSession session,
                                    string title) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.POST);
        this.title = title;
    }

    public override void execute () throws Spit.Publishing.PublishingError {
        var builder = new Json.Builder();
        builder.begin_object();
        builder.set_member_name("album");
        builder.begin_object();
        builder.set_member_name("title");
        builder.add_string_value(this.title);
        builder.end_object();
        builder.end_object();
        set_custom_payload(Json.to_string (builder.get_root (), false), "application/json");

        base.execute();
    }
}

private class AlbumDirectoryTransaction : Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    private const string ENDPOINT_URL = "https://photoslibrary.googleapis.com/v1/albums";
    private Album[] albums = new Album[0];

    public AlbumDirectoryTransaction(Publishing.RESTSupport.GoogleSession session) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.GET);
        this.completed.connect(on_internal_continue_pagination);
    }

    public Album[] get_albums() {
        return this.albums;
    }

    private void on_internal_continue_pagination() {
        try {
            debug(this.get_response());
            var json = Json.from_string (this.get_response());
            var object = json.get_object ();
            if (!object.has_member ("albums")) {
                return;
            }

            var pagination_token_node = object.get_member ("nextPageToken");
            var response_albums = object.get_member ("albums").get_array();
            response_albums.foreach_element( (a, b, element) => {
                var album = element.get_object();
                var title = album.get_member("title");
                var is_writable = album.get_member("isWriteable");
                if (title != null && is_writable != null && is_writable.get_boolean())
                    albums += new Album(title.get_string(), album.get_string_member("id"));
            });

            if (pagination_token_node != null) {
                this.set_argument ("pageToken", pagination_token_node.get_string ());
                Signal.stop_emission_by_name (this, "completed");
                Idle.add(() => {
                    try {
                        this.execute();
                    } catch (Spit.Publishing.PublishingError error) {
                        this.network_error(error);
                    }

                    return false;
                });
            }
        } catch (Error error) {
            critical ("Got error %s while trying to parse response, delegating", error.message);
            this.network_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(error.message));
        }
    }
}

public class Publisher : Publishing.RESTSupport.GooglePublisher {
    private Spit.Publishing.Authenticator authenticator;
    private bool running = false;
    private PublishingParameters publishing_parameters;
    private Spit.Publishing.ProgressCallback progress_reporter;

    public Publisher(Spit.Publishing.Service service,
                     Spit.Publishing.PluginHost host) {
        base(service, host, "https://www.googleapis.com/auth/photoslibrary");

        this.publishing_parameters = new PublishingParameters();
        load_parameters_from_configuration_system(publishing_parameters);

        var media_type = Spit.Publishing.Publisher.MediaType.NONE;
        foreach(Spit.Publishing.Publishable p in host.get_publishables())
            media_type |= p.get_media_type();

        publishing_parameters.set_media_type(media_type);
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
        this.publishing_parameters.set_user_name (this.authenticator.get_authentication_parameter()["UserName"].get_string());

        get_host().install_account_fetch_wait_pane();
        get_host().set_service_locked(true);

        AlbumDirectoryTransaction txn = new AlbumDirectoryTransaction(get_session());
        txn.completed.connect(on_initial_album_fetch_complete);
        txn.network_error.connect(on_initial_album_fetch_error);

        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError error) {
            on_initial_album_fetch_error(txn, error);
        }
    }

    private void on_initial_album_fetch_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_initial_album_fetch_complete);
        txn.network_error.disconnect(on_initial_album_fetch_error);

        if (!is_running())
            return;

        debug("EVENT: finished fetching album information.");

        display_account_information((AlbumDirectoryTransaction)txn);
    }

    private void on_initial_album_fetch_error(Publishing.RESTSupport.Transaction txn,
                                              Spit.Publishing.PublishingError error) {
        txn.completed.disconnect(on_initial_album_fetch_complete);
        txn.network_error.disconnect(on_initial_album_fetch_error);

        if (!is_running())
            return;

        debug("EVENT: fetching album information failed; response = '%s'.",
              txn.get_response());

        if (txn.get_status_code() == 403 || txn.get_status_code() == 404) {
            do_logout();
        } else {
            // If we get any other kind of error, we can't recover, so just post it to the user
            get_host().post_error(error);
        }
    }

    private void display_account_information(AlbumDirectoryTransaction txn) {
        debug("ACTION: parsing album information");
        this.publishing_parameters.set_albums(txn.get_albums());

        show_publishing_options_pane();
    }

    private void show_publishing_options_pane() {
        debug("ACTION: showing publishing options pane.");

        var opts_pane = new PublishingOptionsPane(this.publishing_parameters, this.authenticator.can_logout());
        opts_pane.publish.connect(on_publishing_options_publish);
        opts_pane.logout.connect(on_publishing_options_logout);
        get_host().install_dialog_pane(opts_pane);

        get_host().set_service_locked(false);
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

        if (publishing_parameters.get_target_album_entry_id () != null) {
            do_upload();
        } else {
            do_create_album();
        }
    }

    private void do_create_album() {
        debug("ACTION: Creating album");
        assert(publishing_parameters.get_target_album_entry_id () == null);

        get_host().set_service_locked(true);

        var txn = new AlbumCreationTransaction(get_session(), publishing_parameters.get_target_album_name());
        txn.completed.connect(on_album_create_complete);
        txn.network_error.connect(on_album_create_error);

        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError error) {
            on_album_create_error(txn, error);
        }
    }

    private void on_album_create_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_album_create_complete);
        txn.network_error.disconnect(on_album_create_error);

        if (!is_running())
            return;

        debug("EVENT: finished creating album information: %s", txn.get_response());

        try {
            var node = Json.from_string(txn.get_response());
            var object = node.get_object();
            publishing_parameters.set_target_album_entry_id (object.get_string_member ("id"));

            do_upload();
        } catch (Error error) {
            on_album_create_error(txn, new Spit.Publishing.PublishingError.MALFORMED_RESPONSE (error.message));
        }
    }

    private void on_album_create_error(Publishing.RESTSupport.Transaction txn,
                                       Spit.Publishing.PublishingError error) {
        txn.completed.disconnect(on_initial_album_fetch_complete);
        txn.network_error.disconnect(on_initial_album_fetch_error);

        if (!is_running())
            return;

        debug("EVENT: creating album failed; response = '%s'.",
              txn.get_response());

        if (txn.get_status_code() == 403 || txn.get_status_code() == 404) {
            do_logout();
        } else {
            // If we get any other kind of error, we can't recover, so just post it to the user
            get_host().post_error(error);
        }
    }

    protected override void do_logout() {
        debug("ACTION: logging out user.");
        get_session().deauthenticate();

        if (this.authenticator.can_logout()) {
            this.authenticator.logout();
            this.authenticator.authenticate();
        }
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

        var txn = new MediaCreationTransaction(get_session(),
                                               ((Uploader) uploader).upload_tokens,
                                               ((Uploader) uploader).titles,
                                               publishing_parameters.get_target_album_entry_id());

        txn.completed.connect(on_media_creation_complete);
        txn.network_error.connect(on_media_creation_error);

        try {
            txn.execute();
        } catch (Spit.Publishing.PublishingError error) {
            on_media_creation_error(txn, error);
        }
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

    private void on_media_creation_complete(Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_media_creation_complete);
        txn.network_error.disconnect(on_media_creation_error);

        if (!is_running())
            return;

        debug("EVENT: Media creation reports success.");

        get_host().set_service_locked(false);
        get_host().install_success_pane();
    }

    private void on_media_creation_error(Publishing.RESTSupport.Transaction txn,
                                         Spit.Publishing.PublishingError err) {
        txn.completed.disconnect(on_media_creation_complete);
        txn.network_error.disconnect(on_media_creation_error);

        if (!is_running())
            return;

        debug("EVENT: Media creation reports error: %s", err.message);

        get_host().post_error(err);
    }

    public override bool is_running() {
        return running;
    }

    public override void start() {
        debug("GooglePhotos.Publisher: start() invoked.");

        if (is_running())
            return;

        running = true;

        this.authenticator.authenticate();
    }

    public override void stop() {
        debug("GooglePhotos.Publisher: stop() invoked.");

        get_session().stop_transactions();

        running = false;
    }

    protected override Spit.Publishing.Authenticator get_authenticator() {
        if (this.authenticator == null) {
            this.authenticator = Publishing.Authenticator.Factory.get_instance().create("google-photos", get_host());
        }

        return this.authenticator;
    }
}
} // namespace Publishing.GooglePhotos
