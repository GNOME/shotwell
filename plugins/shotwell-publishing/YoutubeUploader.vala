using Spit;

namespace Publishing.YouTube {
internal class UploadTransaction : Publishing.RESTSupport.GooglePublisher.AuthenticatedTransaction {
    private PublishingParameters parameters;
    private Publishing.RESTSupport.GoogleSession session;
    private Spit.Publishing.Publishable publishable;
    private MappedFile mapped_file;

    public UploadTransaction(Publishing.RESTSupport.GoogleSession session,
        PublishingParameters parameters, Spit.Publishing.Publishable publishable) {
        base(session, "https://www.googleapis.com/upload/youtube/v3/videos",
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
        // Collect parameters

        var slug = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        // Set title to publishing name, but if that's empty default to filename.
        string title = publishable.get_publishing_name();
        if (title == "") {
            title = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        }

        var builder = new Json.Builder();
        builder.begin_object();
        builder.set_member_name("snippet");
        builder.begin_object();
        builder.set_member_name("description");
        builder.add_string_value(slug);
        builder.set_member_name("title");
        builder.add_string_value(title);
        builder.end_object();
        builder.set_member_name("status");
        builder.begin_object();
        builder.set_member_name("privacyStatus");
        builder.add_string_value(parameters.get_privacy().to_string());
        builder.end_object();
        builder.end_object();

        var meta_data = Json.to_string (builder.get_root(), false);
        debug ("Parameters: %s", meta_data);
        var message_parts = new Soup.Multipart("multipart/related");
        var headers = new Soup.MessageHeaders(Soup.MessageHeadersType.MULTIPART);
        var encoding = new GLib.HashTable<string, string>(str_hash, str_equal);
        encoding.insert("encoding", "UTF-8");
        headers.set_content_type ("application/json", encoding);

        message_parts.append_part (headers, new Bytes (meta_data.data));
        headers = new Soup.MessageHeaders(Soup.MessageHeadersType.MULTIPART);
        headers.set_content_type ("application/octet-stream", null);
        headers.append("Content-Transfer-Encoding", "binary");

        MappedFile? mapped_file = null;
        try {
            mapped_file = new MappedFile(publishable.get_serialized_file().get_path(), false);
        } catch (Error e) {
            throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                _("A temporary file needed for publishing is unavailable"));
        }


        message_parts.append_part (headers, mapped_file.get_bytes());

        var outbound_message = new Soup.Message.from_multipart (get_endpoint_url() + "?part=" + GLib.Uri.escape_string ("snippet,status"), message_parts);
        outbound_message.get_request_headers().append("Authorization", "Bearer " +
                                                session.get_access_token());

        set_message(outbound_message, mapped_file.get_length() + meta_data.length);
        set_is_executed(true);
        send();

#if 0















        var basename = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        int64 mapped_file_size = -1;

        // attempt to map the binary image data from disk into memory
        try {
            mapped_file = publishable.get_serialized_file().read(null);
            var info = ((FileInputStream)mapped_file).query_info("standard::size", null);
            mapped_file_size = info.get_size();
        } catch (Error e) {
            string msg = "Google Photos: couldn't read data from %s: %s".printf(
                publishable.get_serialized_file().get_path(), e.message);
            warning("%s", msg);

            throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(msg);
        }

        // create a message that can be sent over the wire whose payload is the multipart container
        // that we've been building up
        var outbound_message = new Soup.Message ("POST", get_endpoint_url());
        outbound_message.request_headers.append("Authorization", "Bearer " +
                                                session.get_access_token());
        outbound_message.request_headers.append("X-Goog-Upload-File-Name", basename);
        outbound_message.request_headers.append("X-Goog-Upload-Protocol", "raw");
        outbound_message.request_headers.set_content_type("application/octet-stream", null);
        outbound_message.set_request_body(null, mapped_file, (ssize_t)mapped_file_size);
        set_message(outbound_message, (ulong)mapped_file_size);

        // send the message and get its response
        set_is_executed(true);
        send();
        #endif
    }

}
}
