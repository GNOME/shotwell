/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern const string _VERSION;

namespace Publishing.RESTSupport {

// Ported from librest
// https://git.gnome.org/browse/librest/tree/rest/sha1.c?id=e412da58080eec2e771482e7e4c509b9e71477ff#n38

internal const int SHA1_HMAC_LENGTH = 20;

public string hmac_sha1(string key, string message) {
    uint8 buffer[SHA1_HMAC_LENGTH];
    size_t len = SHA1_HMAC_LENGTH;

    var mac = new Hmac (ChecksumType.SHA1, key.data);
    mac.update (message.data);
    mac.get_digest (buffer, ref len);

    return Base64.encode (buffer[0:len]);
}

public abstract class Session {
    private string? endpoint_url = null;
    private Soup.Session soup_session = null;
    private bool transactions_stopped = false;
    private Bytes? body = null;
    private Error? transport_error= null;
    private bool insecure = false;
    
    public signal void wire_message_unqueued(Soup.Message message);
    public signal void authenticated();
    public signal void authentication_failed(Spit.Publishing.PublishingError err);

    protected Session(string? endpoint_url = null) {
        this.endpoint_url = endpoint_url;
        soup_session = new Soup.Session ();
        // The trailing space is intentional to make libsoup append its version info
        soup_session.set_user_agent("Shotwell/%s ".printf(_VERSION));
        if (Environment.get_variable("SHOTWELL_SOUP_LOG") != null) {
            var logger = new Soup.Logger(Soup.LoggerLogLevel.BODY);
            logger.set_request_filter((logger, msg) => {
                var content_type = msg.get_request_headers().get_content_type(null);
                if (content_type != null && content_type == "application/octet-stream") {
                    return Soup.LoggerLogLevel.HEADERS;
                }

                return Soup.LoggerLogLevel.BODY;
            });
            soup_session.add_feature (logger);
        }
    }
    
    protected void notify_wire_message_unqueued(Soup.Message message) {
        wire_message_unqueued(message);
    }
    
    protected void notify_authenticated() {
        authenticated();
    }
    
    protected void notify_authentication_failed(Spit.Publishing.PublishingError err) {
        authentication_failed(err);
    }

    public abstract bool is_authenticated();
    
    public string? get_endpoint_url() {
        return endpoint_url;
    }
    
    public void stop_transactions() {
        transactions_stopped = true;
        soup_session.abort();
    }
    
    public bool are_transactions_stopped() {
        return transactions_stopped;
    }
    
    public async void send_wire_message_async(Soup.Message message) {
        if (are_transactions_stopped()) {
            return;
        }

        try {
            this.body = yield soup_session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
        } catch (Error error) {
            debug ("Failed to send_and_read: %s", error.message);
            this.transport_error = error;
        }
    }

    public void set_insecure () {
        this.insecure = true;
    }

    public bool get_is_insecure() {
        return this.insecure;
    }

    public Error? get_transport_error() {
        return this.transport_error;
    }

    public Bytes? get_body() {
        return this.body;
    }
}

public enum HttpMethod {
    GET,
    POST,
    PUT;

    public string to_string() {
        switch (this) {
            case HttpMethod.GET:
                return "GET";

            case HttpMethod.PUT:
                return "PUT";

            case HttpMethod.POST:
                return "POST";

            default:
                error("unrecognized HTTP method enumeration value");
        }
    }

    public static HttpMethod from_string(string str) {
        if (str == "GET") {
            return HttpMethod.GET;
        } else if (str == "PUT") {
            return HttpMethod.PUT;
        } else if (str == "POST") {
            return HttpMethod.POST;
        } else {
            error("unrecognized HTTP method name: %s", str);
        }
    }
}

public class Argument {
    public string key;
    public string value;

    public Argument(string key, string value) {
        this.key = key;
        this.value = value;
    }

    public static string serialize_for_sbs(Argument[] args) {
        return Argument.serialize_list(args, true, false, "&");
    }

    public static string serialize_for_authorization_header(Argument[] args) {
        return Argument.serialize_list(args, false, true, ", ");
    }

    public static string serialize_list(Argument[] args, bool encode, bool escape, string? separator) {
        var builder = new StringBuilder("");

        foreach (var arg in args) {
            builder.append(arg.to_string(escape, encode));
            builder.append(separator);
        }

        if (builder.len > 0)
            builder.truncate(builder.len - separator.length);

        return builder.str;
    }

    public static int compare(Argument arg1, Argument arg2) {
        return strcmp(arg1.key, arg2.key);
    }
    
    public static Argument[] sort(Argument[] inputArray) {
        Gee.TreeSet<Argument> sorted_args = new Gee.TreeSet<Argument>(Argument.compare);

        foreach (Argument arg in inputArray)
            sorted_args.add(arg);

        return sorted_args.to_array();
    }

    public string to_string (bool escape = false, bool encode = false) {
        return "%s=%s%s%s".printf (this.key, escape ? "\"" : "",
            encode ? GLib.Uri.escape_string(this.value) : this.value,
            escape ? "\"" : "");
    }
}

public class Transaction {
    private Argument[] arguments;
    private bool is_executed = false;
    private weak Session parent_session = null;
    private Soup.Message message = null;
    private uint bytes_written = 0;
    private ulong request_length;
    private string? endpoint_url = null;
    private bool use_custom_payload;
    
    public signal void chunk_transmitted(uint bytes_written_so_far, uint total_bytes);
    public signal void completed();

    
    public Transaction(Session parent_session, HttpMethod method = HttpMethod.POST) {
        // if our creator doesn't specify an endpoint url by using the Transaction.with_endpoint_url
        // constructor, then our parent session must have a non-null endpoint url
        assert(parent_session.get_endpoint_url() != null);
        
        this.parent_session = parent_session;

        message = new Soup.Message(method.to_string(), parent_session.get_endpoint_url());
        message.wrote_body_data.connect(on_wrote_body_data);
    }

    public Transaction.with_endpoint_url(Session parent_session, string endpoint_url,
        HttpMethod method = HttpMethod.POST) {
        this.parent_session = parent_session;
        this.endpoint_url = endpoint_url;
        message = new Soup.Message(method.to_string(), endpoint_url);
    }

    private void on_wrote_body_data(Soup.Message message, uint chunk_size) {
        bytes_written += chunk_size;
        chunk_transmitted(bytes_written, (uint)request_length);
    }

    /* Texts copied from epiphany */
    public string detailed_error_from_tls_flags (out TlsCertificate cert) {
        TlsCertificateFlags tls_errors;
        cert = this.message.get_tls_peer_certificate();
        tls_errors = this.message.get_tls_peer_certificate_errors();

        var list = new Gee.ArrayList<string> ();
        if (TlsCertificateFlags.BAD_IDENTITY in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website presented identification that belongs to a different website."));
        }

        if (TlsCertificateFlags.EXPIRED in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification is too old to trust. Check the date on your computer’s calendar."));
        }

        if (TlsCertificateFlags.UNKNOWN_CA in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification was not issued by a trusted organization."));
        }

        if (TlsCertificateFlags.GENERIC_ERROR in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification could not be processed. It may be corrupted."));
        }

        if (TlsCertificateFlags.REVOKED in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification has been revoked by the trusted organization that issued it."));
        }

        if (TlsCertificateFlags.INSECURE in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification cannot be trusted because it uses very weak encryption."));
        }

        if (TlsCertificateFlags.NOT_ACTIVATED in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification is only valid for future dates. Check the date on your computer’s calendar."));
        }

        var builder = new StringBuilder ();
        if (list.size == 1) {
            builder.append (list.get (0));
        } else {
            foreach (var entry in list) {
                builder.append_printf ("%s\n", entry);
            }
        }

        return builder.str;
  }

    protected void check_response(Soup.Message message) throws Spit.Publishing.PublishingError {
        var transport_error = parent_session.get_transport_error();
        if (transport_error != null) {
            if (transport_error is GLib.ResolverError) {
                throw new Spit.Publishing.PublishingError.NO_ANSWER("Unable to resolve %s (error code %u)",
                get_endpoint_url(), message.status_code);
            }
            if (transport_error is GLib.IOError) {
                throw new Spit.Publishing.PublishingError.NO_ANSWER("Unable to connect to %s (error code %u)",
                    get_endpoint_url(), message.status_code);
            }
            if (transport_error is GLib.TlsError) {
                throw new Spit.Publishing.PublishingError.SSL_FAILED ("Unable to connect to %s: Secure connection failed",
                    get_endpoint_url ());
            }

            throw new Spit.Publishing.PublishingError.NO_ANSWER("Failure communicating with %s (error code %u)",
                get_endpoint_url(), message.status_code);
        }
        switch (message.status_code) {
            case Soup.Status.OK:
            case Soup.Status.CREATED: // HTTP code 201 (CREATED) signals that a new
                                               // resource was created in response to a PUT or POST
            break;
            
            default:
                throw new Spit.Publishing.PublishingError.NO_ANSWER("Service %s returned HTTP status code %u %s",
                    get_endpoint_url(), message.status_code, message.reason_phrase);            
        }
        
        // All valid communication involves body data in the response
        var body = parent_session.get_body();
        if (body == null || body.get_size() == 0)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("No response data from %s",
                get_endpoint_url());
    }

    public Argument[] get_arguments() {
        return arguments;
    }
    
    public Argument[] get_sorted_arguments() {
        return Argument.sort(get_arguments());
    }
    
    protected void set_is_executed(bool is_executed) {
        this.is_executed = is_executed;
    }

    private bool on_accecpt_certificate(Soup.Message message, TlsCertificate cert, TlsCertificateFlags errors) {
        debug ("HTTPS connect error. Will ignore? %s", this.parent_session.get_is_insecure().to_string());
        return this.parent_session.get_is_insecure();
    }

    protected async void send_async() throws Spit.Publishing.PublishingError {
        var id = message.wrote_body_data.connect((message, chunk_size) => {
            bytes_written = chunk_size;

            chunk_transmitted(bytes_written, (uint)request_length);
        });
        message.accept_certificate.connect(on_accecpt_certificate);

        yield parent_session.send_wire_message_async(message);
        check_response(message);

        message.disconnect(id);
        message.accept_certificate.disconnect(on_accecpt_certificate);
        completed();
    }

    public HttpMethod get_method() {
        return HttpMethod.from_string(message.method);
    }

    protected virtual void add_header(string key, string value) {
        message.request_headers.append(key, value);
    }
    
    // set custom_payload to null to have this transaction send the default payload of
    // key-value pairs appended through add_argument(...) (this is how most REST requests work).
    // To send a payload other than traditional key-value pairs (such as an XML document or a JPEG
    // image) to the endpoint, set the custom_payload parameter to a non-null value. If the
    // custom_payload you specify is text data, then it's null terminated, and its length is just 
    // custom_payload.length, so you don't have to pass in a payload_length parameter in this case.
    // If, however, custom_payload is binary data (such as a JEPG), then the caller must set
    // payload_length to the byte length of the custom_payload buffer
    protected void set_custom_payload(string? custom_payload, string payload_content_type,
        ulong payload_length = 0) {
        assert (get_method() != HttpMethod.GET); // GET messages don't have payloads

        if (custom_payload == null) {
            use_custom_payload = false;
            return;
        }
        
        ulong length = (payload_length > 0) ? payload_length : custom_payload.length;
        message.set_request_body_from_bytes(payload_content_type, new Bytes (custom_payload.data[0:length]));
        this.request_length = length;

        use_custom_payload = true;
    }
    
    // When writing a specialized transaction subclass you should rarely need to
    // call this method. In general, it's better to leave the underlying Soup message
    // alone and let the Transaction class manage it for you. You should only need
    // to install a new message if your subclass has radically different behavior from
    // normal Transactions -- like multipart encoding.
    protected void set_message(Soup.Message message, ulong request_length) {
        this.message = message;
        this.request_length = request_length;
    }
    
    public bool get_is_executed() {
        return is_executed;
    }

    public uint get_status_code() {
        assert(get_is_executed());
        return message.status_code;
    }

    private GLib.Uri? prepare_rest_message() {
        //  REST POST requests must transmit at least one argument
        if (get_method() == HttpMethod.POST)
            assert(arguments.length > 0);

        // concatenate the REST arguments array into an HTTP formdata string
        var formdata_string = new StringBuilder("");
        for (int i = 0; i < arguments.length; i++) {
            formdata_string.append(arguments[i].to_string());
            if (i < arguments.length - 1)
                formdata_string.append("&");
        }
        
        // for GET requests with arguments, append the formdata string to the endpoint url after a
        // query divider ('?') -- but make sure to save the old (caller-specified) endpoint URL
        // and restore it after the GET so that the underlying Soup message remains consistent
        GLib.Uri? old_url = null;
        string url_with_query = null;
        if (get_method() == HttpMethod.GET && arguments.length > 0) {
            old_url = message.get_uri();
            url_with_query = get_endpoint_url() + "?" + formdata_string.str;
            try {
                message.set_uri(GLib.Uri.parse(url_with_query, GLib.UriFlags.ENCODED));
            } catch (Error err) {
                error ("Invalid uri for service: %s", err.message);
            }
        } else {
            message.set_request_body_from_bytes("application/x-www-form-urlencoded", StringBuilder.free_to_bytes((owned)formdata_string));
        }

        is_executed = true;

        return old_url;
    }

    public virtual async void execute_async() throws Spit.Publishing.PublishingError {
        // if a custom payload is being used, we don't need to perform the tasks that are necessary
        // to prepare a traditional key-value pair REST request; Instead (since we don't
        // know anything about the custom payload), we just put it on the wire and return
        if (use_custom_payload) {
            is_executed = true;
            yield send_async();

            return;
        }

        var old_url = prepare_rest_message();
         
        try {
            debug("sending message to URI = '%s'", message.get_uri().to_string());
            yield send_async();
        } finally {
            // if old_url is non-null, then restore it
            if (old_url != null)
                message.set_uri(old_url);
        }
    }

    public string get_response() {
        assert(get_is_executed());
        return parent_session.get_body() == null ? "" : (string) parent_session.get_body().get_data();
    }
    
    public unowned Soup.MessageHeaders get_response_headers() {
        assert(get_is_executed());
        return message.response_headers;
    }

    public Soup.Message get_message() {
        assert(get_is_executed());
        return message;
    }
   
    public void add_argument(string name, string value) {
        arguments += new Argument(name, value);
    }

    public void set_argument(string name, string value) {
        foreach (var arg in arguments) {
            if (arg.key == name) {
                arg.value = value;

                return;
            }
        }

        add_argument(name, value);
    }
    
    public string? get_endpoint_url() {
        return (endpoint_url != null) ? endpoint_url : parent_session.get_endpoint_url();
    }
    
    public Session get_parent_session() {
        return parent_session;
    }
}

public class UploadTransaction : Transaction {
    protected GLib.HashTable<string, string> binary_disposition_table = null;
    protected Spit.Publishing.Publishable publishable = null;
    protected string mime_type;
    protected Gee.HashMap<string, string> message_headers = null;

    public UploadTransaction(Session session, Spit.Publishing.Publishable publishable) {
        base (session);
        this.publishable = publishable;
        this.mime_type = media_type_to_mime_type(publishable.get_media_type());

        binary_disposition_table = create_default_binary_disposition_table();
        
        message_headers = new Gee.HashMap<string, string>();
    }
    
    public UploadTransaction.with_endpoint_url(Session session,
        Spit.Publishing.Publishable publishable, string endpoint_url) {
        base.with_endpoint_url(session, endpoint_url);
        this.publishable = publishable;
        this.mime_type = media_type_to_mime_type(publishable.get_media_type());

        binary_disposition_table = create_default_binary_disposition_table();
        
        message_headers = new Gee.HashMap<string, string>();
    }
    
    protected override void add_header(string key, string value) {
        message_headers.set(key, value);
    }
    
    private static string media_type_to_mime_type(Spit.Publishing.Publisher.MediaType media_type) {
        if (media_type == Spit.Publishing.Publisher.MediaType.PHOTO)
            return "image/jpeg";
        else if (media_type == Spit.Publishing.Publisher.MediaType.VIDEO)
            return "video/mpeg";
        else
            error("UploadTransaction: unknown media type %s.", media_type.to_string());
    }

    private GLib.HashTable<string, string> create_default_binary_disposition_table() {
        GLib.HashTable<string, string> result =
            new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);

        result.insert("filename", GLib.Uri.escape_string(publishable.get_serialized_file().get_basename(),
            null));

        return result;
    }

    protected void set_binary_disposition_table(GLib.HashTable<string, string> new_disp_table) {
        binary_disposition_table = new_disp_table;
    }

    private void prepare_execution() throws Spit.Publishing.PublishingError {
        Argument[] request_arguments = get_arguments();
        assert(request_arguments.length > 0);

        Soup.Multipart message_parts = new Soup.Multipart("multipart/form-data");

        foreach (Argument arg in request_arguments)
            message_parts.append_form_string(arg.key, arg.value);

        MappedFile? mapped_file = null;
        try {
            mapped_file = new MappedFile(publishable.get_serialized_file().get_path(), false);
        } catch (Error e) {
            throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                _("A temporary file needed for publishing is unavailable"));
        }

        message_parts.append_form_file("", publishable.get_serialized_file().get_path(), mime_type,
            mapped_file.get_bytes());

        unowned Soup.MessageHeaders image_part_header;
        unowned Bytes image_part_body;
        int payload_part_num = message_parts.get_length() - 1;
        message_parts.get_part(payload_part_num, out image_part_header, out image_part_body);
        debug ("Image part header %p", image_part_header);
        image_part_header.set_content_disposition("form-data", binary_disposition_table);

        var outbound_message = new Soup.Message.from_multipart(get_endpoint_url(), message_parts);

        Gee.MapIterator<string, string> i = message_headers.map_iterator();
        bool cont = i.next();
        while(cont) {
            outbound_message.request_headers.append(i.get_key(), i.get_value());
            cont = i.next();
        }
        set_message(outbound_message, mapped_file.get_length());
        
        set_is_executed(true);
    }

    public override async void execute_async() throws Spit.Publishing.PublishingError {
        prepare_execution();
        yield send_async();
    }
}

public class XmlDocument {
    // Returns non-null string if an error condition is discovered in the XML (such as a well-known 
    // node).  The string is used when generating a PublishingError exception.  This delegate does
    // not need to check for general-case malformed XML.
    public delegate string? CheckForErrorResponse(XmlDocument doc);
    
    private Xml.Doc* document;

    private XmlDocument(Xml.Doc* doc) {
        document = doc;
    }

    ~XmlDocument() {
        delete document;
    }

    public Xml.Node* get_root_node() {
        return document->get_root_element();
    }

    public Xml.Node* get_named_child(Xml.Node* parent, string child_name)
        throws Spit.Publishing.PublishingError {
        Xml.Node* doc_node_iter = parent->children;
    
        for ( ; doc_node_iter != null; doc_node_iter = doc_node_iter->next) {
            if (doc_node_iter->name == child_name)
                return doc_node_iter;
        }

        throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Can't find XML node %s",
            child_name);
    }

    public string get_property_value(Xml.Node* node, string property_key)
        throws Spit.Publishing.PublishingError {  
        string value_string = node->get_prop(property_key);
        if (value_string == null)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Can't find XML " +
                "property %s on node %s", property_key, node->name);

        return value_string;
    }

    public static XmlDocument parse_string(string? input_string,
        CheckForErrorResponse check_for_error_response) throws Spit.Publishing.PublishingError {
        if (input_string == null || input_string.length == 0)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Empty XML string");

        // Does this even start and end with the right characters?
        if (!input_string.chug().chomp().has_prefix("<") ||
            !input_string.chug().chomp().has_suffix(">")) {
            // Didn't start or end with a < or > and can't be parsed as XML - treat as malformed.
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Unable to parse XML " +
                "document");
        }

        // Don't want blanks to be included as text nodes, and want the XML parser to tolerate
        // tolerable XML
        Xml.Doc* doc = Xml.Parser.read_memory(input_string, (int) input_string.length, null, null,
            Xml.ParserOption.NOBLANKS | Xml.ParserOption.RECOVER);
        if (doc == null)
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Unable to parse XML " +
                "document");

        // Since 'doc' is the top level, if it has no children, something is wrong
        // with the XML; we cannot continue normally here.
        if (doc->children == null) {
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE("Unable to parse XML " +
                "document");
        }
        
        XmlDocument rest_doc = new XmlDocument(doc);

        string? result = check_for_error_response(rest_doc);
        if (result != null)
            throw new Spit.Publishing.PublishingError.SERVICE_ERROR("%s", result);
        
        return rest_doc;
    }
}

/* Encoding strings in XML decimal encoding is a relatively esoteric operation. Most web services
   prefer to have non-ASCII character entities encoded using "symbolic encoding," where common
   entities are encoded in short, symbolic names (e.g. "ñ" -> &ntilde;). Picasa Web Albums,
   however, doesn't like symbolic encoding, and instead wants non-ASCII entities encoded directly
   as their Unicode code point numbers (e.g. "ñ" -> &241;). */
public string decimal_entity_encode(string source) {
    StringBuilder encoded_str_builder = new StringBuilder();
    string current_char = source;
    while (true) {
        int current_char_value = (int) (current_char.get_char_validated());
        
        // null character signals end of string
        if (current_char_value < 1)
            break;
        
        // no need to escape ASCII characters except the ampersand, greater-than sign and less-than
        // signs, which are special in the world of XML
        if ((current_char_value < 128) && (current_char_value != '&') && (current_char_value != '<') &&
            (current_char_value != '>'))
            encoded_str_builder.append_unichar(current_char.get_char_validated());
        else
            encoded_str_builder.append("&#%d;".printf(current_char_value));

        current_char = current_char.next_char();
    }
    
    return encoded_str_builder.str;
}

public abstract class BatchUploader {
    private int current_file = 0;
    private Spit.Publishing.Publishable[] publishables = null;
    private Session session = null;
	private unowned Spit.Publishing.ProgressCallback? status_updated = null;

    public signal void upload_complete(int num_photos_published);
    public signal void upload_error(Spit.Publishing.PublishingError err);

    protected BatchUploader(Session session, Spit.Publishing.Publishable[] publishables) {
        this.publishables = publishables;
        this.session = session;
    }

    private async void send_files_async() throws Spit.Publishing.PublishingError {
        current_file = 0;
        foreach (Spit.Publishing.Publishable publishable in publishables) {
            GLib.File? file = publishable.get_serialized_file();
            
            // if the current publishable hasn't been serialized, then skip it
            if (file == null) {
                current_file++;
                continue;
            }

            double fraction_complete = ((double) current_file) / publishables.length;
                if (status_updated != null)
                    status_updated(current_file + 1, fraction_complete);

            Transaction txn = create_transaction(publishables[current_file]);
           
            txn.chunk_transmitted.connect(on_chunk_transmitted);
            
            yield txn.execute_async();
                
            txn.chunk_transmitted.disconnect(on_chunk_transmitted);           
                        
            current_file++;
        }
    }

    private void on_chunk_transmitted(uint bytes_written_so_far, uint total_bytes) {
        double file_span = 1.0 / publishables.length;
        double this_file_fraction_complete = ((double) bytes_written_so_far) / total_bytes;
        double fraction_complete = (current_file * file_span) + (this_file_fraction_complete *
            file_span);

		if (status_updated != null)
	        status_updated(current_file + 1, fraction_complete);
    }
    
    protected Session get_session() {
        return session;
    }
    
    protected Spit.Publishing.Publishable get_current_publishable() {
        return publishables[current_file];
    }
    
    protected abstract Transaction create_transaction(Spit.Publishing.Publishable publishable);

    public async int upload_async(Spit.Publishing.ProgressCallback? status_updated = null)  throws Spit.Publishing.PublishingError {
        this.status_updated = status_updated;

        if (publishables.length > 0)
           yield send_files_async();

        return current_file;
    }
}

// Remove diacritics in a string, yielding ASCII.  If the given string is in
// a character set not based on Latin letters (e.g. Cyrillic), the result
// may be empty.
public string asciify_string(string s) {
    string t = s.normalize();  // default normalization yields a maximally decomposed form
    
    StringBuilder b = new StringBuilder();
    for (unowned string u = t; u.get_char() != 0 ; u = u.next_char()) {
        unichar c = u.get_char();
        if ((int) c < 128)
            b.append_unichar(c);
    }
    
    return b.str;
}

public abstract class GoogleSession : Session {
    public abstract string get_user_name();
    public abstract string get_access_token();
    public abstract void deauthenticate();
}

public abstract class GooglePublisher : Object, Spit.Publishing.Publisher {
    private const string OAUTH_CLIENT_ID = "1073902228337-gm4uf5etk25s0hnnm0g7uv2tm2bm1j0b.apps.googleusercontent.com";
    private const string OAUTH_CLIENT_SECRET = "_kA4RZz72xqed4DqfO7xMmMN";
    
    private class GoogleSessionImpl : GoogleSession {
        public string? access_token;
        public string? user_name;
        public string? refresh_token;
        
        public GoogleSessionImpl() {
            this.access_token = null;
            this.user_name = null;
            this.refresh_token = null;
        }
        
        public override bool is_authenticated() {
            return (access_token != null);
        }
        
        public override string get_user_name() {
            assert (user_name != null);
            return user_name;
        }
        
        public override string get_access_token() {
            assert(is_authenticated());
            return access_token;
        }
        
        public override void deauthenticate() {
            access_token = null;
            user_name = null;
            refresh_token = null;
        }
    }
    
    public class AuthenticatedTransaction : Publishing.RESTSupport.Transaction {
        private AuthenticatedTransaction.with_endpoint_url(GoogleSession session,
            string endpoint_url, Publishing.RESTSupport.HttpMethod method) {
            base.with_endpoint_url(session, endpoint_url, method);
        }

        public AuthenticatedTransaction(GoogleSession session, string endpoint_url,
            Publishing.RESTSupport.HttpMethod method) {
            base.with_endpoint_url(session, endpoint_url, method);
            assert(session.is_authenticated());

            add_header("Authorization", "Bearer " + session.get_access_token());
        }
    }

    private string scope;
    private GoogleSessionImpl session;
    private weak Spit.Publishing.PluginHost host;
    private weak Spit.Publishing.Service service;
    private Spit.Publishing.Authenticator authenticator;
    
    protected GooglePublisher(Spit.Publishing.Service service, Spit.Publishing.PluginHost host,
        string scope) {
        this.scope = scope;
        this.session = new GoogleSessionImpl();
        this.service = service;
        this.host = host;
        this.authenticator = this.get_authenticator();
        this.authenticator.authenticated.connect(on_authenticator_authenticated);
    }

    protected abstract Spit.Publishing.Authenticator get_authenticator();

    protected unowned Spit.Publishing.PluginHost get_host() {
        return host;
    }

    protected GoogleSession get_session() {
        return session;
    }

    protected abstract void on_login_flow_complete();
    
    protected abstract void do_logout();
    
    public abstract bool is_running();
    
    public abstract void start();
    
    public abstract void stop();
    
    public Spit.Publishing.Service get_service() {
        return service;
    }

    private void on_authenticator_authenticated() {
        var params = this.authenticator.get_authentication_parameter();
        Variant refresh_token = null;
        Variant access_token = null;
        Variant user_name = null;

        params.lookup_extended("RefreshToken", null, out refresh_token);
        params.lookup_extended("AccessToken", null, out access_token);
        params.lookup_extended("UserName", null, out user_name);

        this.session.refresh_token = refresh_token.get_string();
        this.session.access_token = access_token.get_string();
        this.session.user_name = user_name.get_string();

        this.on_login_flow_complete();
    }
}

}

