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
    // SCOPE: photoslibrary.appendonly
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

    public override async void execute_async () throws Spit.Publishing.PublishingError {
        var builder = new Json.Builder();
        builder.begin_object();
        builder.set_member_name("albumId");
        builder.add_string_value(this.album_id);
        builder.set_member_name("newMediaItems");
        builder.begin_array();
        for (var i = 0; i < this.upload_tokens.length; i++) {
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

        yield base.execute_async();
    }
}

private class AlbumCreationTransaction : Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    // SCOPE: photoslibrary.appendonly
    private const string ENDPOINT_URL = "https://photoslibrary.googleapis.com/v1/albums";
    private string title;

    public AlbumCreationTransaction(Publishing.RESTSupport.GoogleSession session,
                                    string title) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.POST);
        this.title = title;
    }

    public override async void execute_async() throws Spit.Publishing.PublishingError {
        var builder = new Json.Builder();
        builder.begin_object();
        builder.set_member_name("album");
        builder.begin_object();
        builder.set_member_name("title");
        builder.add_string_value(this.title);
        builder.end_object();
        builder.end_object();
        set_custom_payload(Json.to_string (builder.get_root (), false), "application/json");

        yield base.execute_async();
    }
}

private class AlbumDirectoryTransaction : Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    // SCOPE: photoslibrary.readonly.appcreateddata
    private const string ENDPOINT_URL = "https://photoslibrary.googleapis.com/v1/albums";

    public AlbumDirectoryTransaction(Publishing.RESTSupport.GoogleSession session, string? token) {
        base(session, ENDPOINT_URL, Publishing.RESTSupport.HttpMethod.GET);

        if (token != null) {
            add_argument("pageToken", token);
        }
    }
}

public class Publisher : Publishing.RESTSupport.GooglePublisher {
    private Spit.Publishing.Authenticator authenticator;
    private bool running = false;
    private PublishingParameters publishing_parameters;
    private Spit.Publishing.ProgressCallback progress_reporter;
    private size_t creation_offset = 0;

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
        do_publishing_process.begin();
    }

    private async void do_publishing_process() {
        debug("EVENT: OAuth login flow complete.");
        this.publishing_parameters.set_user_name (this.authenticator.get_authentication_parameter()["UserName"].get_string());

        get_host().install_account_fetch_wait_pane();
        get_host().set_service_locked(true);
        var albums = new Album[0];

        AlbumDirectoryTransaction txn = new AlbumDirectoryTransaction(get_session(), null);
        try {
            string? pagination_token = null;
            do {
                yield txn.execute_async();

                if (!is_running())
                    return;


                var json = Json.from_string (txn.get_response());
                var object = json.get_object ();
                // Work-around for Google sometimes sending an empty JSON object '{}' instead of 
                // not setting the nextPageToken on the previous page
                if (object.get_size() == 0) {
                    break;
                }
                
                if (!object.has_member ("albums")) {
                    throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Album fetch did not contain expected data");
                }
    
                if (object.has_member("nextPageToken")) {
                    pagination_token = object.get_member ("nextPageToken").get_string();
                } else {
                    pagination_token = null;
                }

                var response_albums = object.get_member ("albums").get_array();
                response_albums.foreach_element( (a, b, element) => {
                    var album = element.get_object();
                    var title = album.get_member("title");
                    var is_writable = album.get_member("isWriteable");
                    if (title != null && is_writable != null && is_writable.get_boolean())
                        albums += new Album(title.get_string(), album.get_string_member("id"));
                });
        
                if (pagination_token != null) {
                    debug("Not finished fetching all albums, getting more... %s", pagination_token);
                    txn = new AlbumDirectoryTransaction(get_session(), pagination_token);
                }
            } while (pagination_token != null);

            debug("EVENT: finished fetching album information.");
            this.publishing_parameters.set_albums(albums);

            show_publishing_options_pane();
        } catch (Error err) {
            debug("EVENT: fetching album information failed; response = '%s'.",
            txn.get_response());

            if (txn.get_status_code() == 403) {
                debug("Lacking permission to download album list, showing publishing options anyway");
                show_publishing_options_pane();
            } else if (txn.get_status_code() == 404) {
                do_logout();
            } else {
                // If we get any other kind of error, we can't recover, so just post it to the user
                get_host().post_error(err);
            }
        }
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
            do_upload.begin();
        } else {
            do_create_album.begin();
        }
    }

    private async void do_create_album() {
        debug("ACTION: Creating album");
        assert(publishing_parameters.get_target_album_entry_id () == null);

        get_host().set_service_locked(true);

        var txn = new AlbumCreationTransaction(get_session(), publishing_parameters.get_target_album_name());

        try {
            yield txn.execute_async();

            if (!is_running())
                return;

            debug("EVENT: finished creating album information: %s", txn.get_response());

            var node = Json.from_string(txn.get_response());
            var object = node.get_object();
            publishing_parameters.set_target_album_entry_id (object.get_string_member ("id"));

            yield do_upload();    
        } catch (Error err) {
            debug("EVENT: creating album failed; status = '%u', response = '%s'.", txn.get_status_code(),
            txn.get_response());

            if (txn.get_status_code() == 403) {
                get_host().install_static_message_pane(_("Could not create album, Shotwell is lacking permission to do so. Please re-authenticate and grant Shotwell the required permission to create new media and albums"),
                    Spit.Publishing.PluginHost.ButtonMode.CLOSE);
            } else if (txn.get_status_code() == 404) {
                do_logout();
            } else {
                // If we get any other kind of error, we can't recover, so just post it to the user
                get_host().post_error(err);
            }
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

    private async void do_upload() {
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

        try {
            yield uploader.upload_async(on_upload_status_updated);
            yield do_media_creation_batch(uploader);
        } catch (Error err) {
            if (!is_running())
                return;

            debug("EVENT: uploader reports upload error = '%s'.", err.message);

            get_host().post_error(err);
        }
    }

    private void on_upload_status_updated(int file_number, double completed_fraction) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);

        progress_reporter(file_number, completed_fraction);
    }

    private async void do_media_creation_batch(Publishing.RESTSupport.BatchUploader uploader) {
        var u = (Uploader) uploader;

        while (creation_offset < u.upload_tokens.length) {
            var end = creation_offset + MAX_BATCH_SIZE < u.upload_tokens.length ? 
                        creation_offset + MAX_BATCH_SIZE : u.upload_tokens.length;
            
            var txn = new MediaCreationTransaction(get_session(),
                                                u.upload_tokens[creation_offset:end],
                                                u.titles[creation_offset:end],
                                                publishing_parameters.get_target_album_entry_id());

            creation_offset = end;
            try {
                yield txn.execute_async();
                if (!is_running())
                    return;
        
                debug("EVENT: Media creation reports success.");
        
                get_host().set_service_locked(false);
                get_host().install_success_pane();
            } catch (Spit.Publishing.PublishingError err) {
                if (!is_running())
                    return;
    
                debug("EVENT: Media creation reports error: %s", err.message);
                
                get_host().post_error(err);
            }
        }
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
