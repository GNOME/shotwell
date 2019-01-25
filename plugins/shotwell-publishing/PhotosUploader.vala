/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Publishing.GooglePhotos {

internal class UploadTransaction : Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    private PublishingParameters parameters;
    private Publishing.RESTSupport.GoogleSession session;
    private Spit.Publishing.Publishable publishable;
    private MappedFile mapped_file;

    public UploadTransaction(Publishing.RESTSupport.GoogleSession session,
        PublishingParameters parameters, Spit.Publishing.Publishable publishable) {
        base(session, "https://photoslibrary.googleapis.com/v1/uploads",
             Publishing.RESTSupport.HttpMethod.POST);
        assert(session.is_authenticated());

        this.session = session;
        this.parameters = parameters;
        this.publishable = publishable;
    }

    public Spit.Publishing.Publishable get_publishable() {
        return this.publishable;
    }

    public override void execute() throws Spit.Publishing.PublishingError {
        var basename = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);

        // attempt to map the binary image data from disk into memory
        try {
            mapped_file = new MappedFile(publishable.get_serialized_file().get_path(), false);
        } catch (FileError e) {
            string msg = "Google Photos: couldn't read data from %s: %s".printf(
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

        // create a message that can be sent over the wire whose payload is the multipart container
        // that we've been building up
        var outbound_message = new Soup.Message ("POST", get_endpoint_url());
        outbound_message.request_headers.append("Authorization", "Bearer " +
                                                session.get_access_token());
        outbound_message.request_headers.append("X-Goog-Upload-File-Name", basename);
        outbound_message.request_headers.append("X-Goog-Upload-Protocol", "raw");
        outbound_message.request_headers.set_content_type("application/octet-stream", null);
        outbound_message.request_body.append_buffer (bindable_data);
        set_message(outbound_message);

        // send the message and get its response
        set_is_executed(true);
        send();
    }
}

internal class Uploader : Publishing.RESTSupport.BatchUploader {
    private PublishingParameters parameters;

    public string[] upload_tokens = new string[0];
    public string[] titles = new string[0];

    public Uploader(Publishing.RESTSupport.GoogleSession session,
        Spit.Publishing.Publishable[] publishables, PublishingParameters parameters) {
        base(session, publishables);

        this.parameters = parameters;
    }

    protected override Publishing.RESTSupport.Transaction create_transaction(
        Spit.Publishing.Publishable publishable) {
        var txn = new UploadTransaction((Publishing.RESTSupport.GoogleSession) get_session(),
                                         parameters, get_current_publishable());
        txn.completed.connect(this.on_transaction_completed);

        return txn;
    }

    private void on_transaction_completed (Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect (on_transaction_completed);

        this.upload_tokens += txn.get_response();
        var title = ((UploadTransaction)txn).get_publishable().get_publishing_name();
        var publishable = ((UploadTransaction)txn).get_publishable();
        if (title == null || title == "")  {
            title = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        }
        this.titles += title;
    }
}
}
