/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

public errordomain PublishingError {
    NO_ANSWER,
    COMMUNICATION_FAILED,
    PROTOCOL_ERROR,
    SERVICE_ERROR,
    MALFORMED_RESPONSE
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
                return "";
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
            return HttpMethod.GET;
        }
    }
    
}

public const int ORIGINAL_SIZE = -1;

public class RESTSession {
    private string endpoint_url = null;
    private Soup.Session network_session = null;
    
    public RESTSession(string creator_endpoint_url, string? user_agent = null) {
        endpoint_url = creator_endpoint_url;
        network_session = new Soup.SessionSync();
        if (user_agent != null)
            network_session.user_agent = user_agent;
    }
    
    private static void check_response(Soup.Message message, string endpoint) throws PublishingError {
        switch (message.status_code) {
            case Soup.KnownStatusCode.OK:
            case Soup.KnownStatusCode.CREATED: // HTTP code 201 (CREATED) signals that a new
                                               // resource was created in response to a PUT or POST
                // looks good -- but check response_body.data as well, see below
            break;
            
            case Soup.KnownStatusCode.CANT_RESOLVE:
            case Soup.KnownStatusCode.CANT_RESOLVE_PROXY:
                throw new PublishingError.NO_ANSWER("Unable to resolve %s (error code %u)", endpoint,
                    message.status_code);
            
            case Soup.KnownStatusCode.CANT_CONNECT:
            case Soup.KnownStatusCode.CANT_CONNECT_PROXY:
                throw new PublishingError.NO_ANSWER("Unable to connect to %s (error code %u)", endpoint,
                    message.status_code);
            
            default:
                // status codes below 100 are used by Soup, 100 and above are defined HTTP codes
                if (message.status_code >= 100) {
                    throw new PublishingError.PROTOCOL_ERROR("Service %s returned HTTP status code %u %s",
                        endpoint, message.status_code, message.reason_phrase);
                } else {
                    throw new PublishingError.COMMUNICATION_FAILED("Failure communicating with %s (error code %u)",
                        endpoint, message.status_code);
                }
        }
        
        // All valid communication with the services involves body data in their response.  If there's
        // ever a situation where the service might return a valid response with no body data, this
        // code needs to be resolved.
        if (message.response_body.data == null || message.response_body.data.length == 0)
            throw new PublishingError.MALFORMED_RESPONSE("No response data from %s", endpoint);
    }
    
    public static void test_endpoint(string endpoint_url, string? user_agent) throws PublishingError {
        Soup.Session test_session = new Soup.SessionSync();
        if (user_agent != null)
            test_session.user_agent = user_agent;
        
        Soup.Message test_message = new Soup.Message("GET", endpoint_url);
        test_session.send_message(test_message);
        
        check_response(test_message, endpoint_url);
    }
    
    public string get_endpoint_url() {
        return endpoint_url;
    }
    
    public virtual RESTTransaction create_transaction() {
        return new RESTTransaction(this);
    }
    
    public void send_message(Soup.Message message) throws PublishingError {
        network_session.send_message(message);
        
        check_response(message, endpoint_url);
    }
}

public struct RESTArgument {
    public string key;
    public string value;

    public RESTArgument(string creator_key, string creator_val) {
        key = creator_key;
        value = creator_val;
    }

    public static int compare(void* p1, void* p2) {
        RESTArgument* arg1 = (RESTArgument*) p1;
        RESTArgument* arg2 = (RESTArgument*) p2;

        return strcmp(arg1->key, arg2->key);
    }
}

public class RESTTransaction {
    private RESTArgument[] arguments;
    private string signature_key = null;
    private string signature_value = null;
    private bool is_executed = false;
    private RESTSession parent_session = null;
    private Soup.Message active_message = null;
    private bool use_custom_payload = false;

    public RESTTransaction(RESTSession session, HttpMethod method = HttpMethod.POST) {
        parent_session = session;
        active_message = new Soup.Message(method.to_string(), parent_session.get_endpoint_url());
    }

    public RESTTransaction.with_endpoint_url(RESTSession session, string endpoint_url,
        HttpMethod method = HttpMethod.POST) {
        parent_session = session;
        active_message = new Soup.Message(method.to_string(), endpoint_url);
    }

    protected void set_signature_key(string sig_key) {
        signature_key = sig_key;
    }
    
    protected void set_signature_value(string sig_val) {
        signature_value = sig_val;
    }

    protected string get_signature_key() {
        return signature_key;
    }

    protected string get_signature_value() {
        return signature_value;
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

        active_message.set_request(payload_content_type, Soup.MemoryUse.COPY, custom_payload,
                (payload_length > 0) ? payload_length : custom_payload.length);

        use_custom_payload = true;
    }

    protected RESTArgument[] get_arguments() {
        return arguments;
    }

    protected RESTArgument[] get_sorted_arguments() {
        RESTArgument[] sorted_array = new RESTArgument[0];

        foreach (RESTArgument arg in arguments)
            sorted_array += arg;

        qsort(sorted_array, sorted_array.length, sizeof(RESTArgument), RESTArgument.compare);

        return sorted_array;
    }

    protected virtual void sign() {
        signature_key = "";
        signature_value = "";
    }
    
    protected bool get_is_signed() {
        return ((signature_key != null) && (signature_value != null));
    }

    protected void set_is_executed(bool new_is_executed) {
        is_executed = new_is_executed;
    }

    protected Soup.Message get_active_message() {
        return active_message;
    }

    // When writing a specialized transaction subclass you should rarely need to
    // call this method. In general, it's better to leave the active_message alone and let
    // the RESTTransaction class manage it for you. You should only need to install a
    // a new active_message if your subclass has radically different behavior from
    // normal RESTTransactions -- like multipart encoding.
    protected void set_active_message(Soup.Message active_message) {
        this.active_message = active_message;
    }

    protected HttpMethod get_method() {
        return HttpMethod.from_string(active_message.method);
    }

    protected void add_header(string key, string value) {
        active_message.request_headers.append(key, value);
    }

    public bool get_is_executed() {
        return is_executed;
    }

    public uint get_status_code() {
        assert(get_is_executed());
        return active_message.status_code;
    }
    
    public virtual void execute() throws PublishingError {
        // if a custom payload is being used, we don't need to peform the tasks that are necessary
        // to sign and encode a traditional key-value pair REST request; Instead (since we don't
        // know anything about the custom payload, we just put it on the wire and return)
        if (use_custom_payload) {
            is_executed = true;
            parent_session.send_message(active_message);

            return;
        } else {
            // not a custom payload, so do the traditional REST key-value pair encoding and
            // make sure that it's signed
            sign();

            // before they can be executed, traditional requests must be signed
            assert(get_is_signed());

            // traditional REST POST requests must transmit at least one argument
            if (get_method() == HttpMethod.POST)
                assert(arguments.length > 0);

            // concatenate the REST arguments array into an HTTP formdata string
            string formdata_string = "";
            foreach (RESTArgument arg in arguments)
                formdata_string = formdata_string + ("%s=%s&".printf(arg.key, arg.value));

            // append the signature key-value pair to the formdata string and percent-encode the
            // whole string, but only if the key isn't the null string
            if (signature_key != "") {
                formdata_string = formdata_string + ("%s=%s".printf(signature_key, signature_value));
                formdata_string = Soup.URI.encode(formdata_string, null);
            }

            // for GET requests with arguments, append the formdata string to the endpoint url after a
            // query divider ('?') -- but make sure to save the old (caller-specified) endpoint URL
            // and restore it after the GET so that the active_message remains consistent
            string old_url = null;
            string url_with_query = null;
            if (get_method() == HttpMethod.GET && arguments.length > 0) {
                old_url = active_message.get_uri().to_string(false);
                url_with_query = get_endpoint_url() + "?" + formdata_string;
                active_message.set_uri(new Soup.URI(url_with_query));
            }

            active_message.set_request("application/x-www-form-urlencoded", Soup.MemoryUse.COPY,
                formdata_string, formdata_string.length);
            is_executed = true;
            parent_session.send_message(active_message);

            // if old_url is non-null, then restore it
            if (old_url != null)
                active_message.set_uri(new Soup.URI(old_url));
        }
      }
      
      public string get_response() {
          assert(get_is_executed());
          return (string) active_message.response_body.data;
      }
   
    public void add_argument(string name, string value) {
        // if a request has already been signed, it's an error to add further arguments to it
        assert(!get_is_signed());

        arguments += RESTArgument(name, value);
    }
    
    public string get_endpoint_url() {
        return active_message.get_uri().to_string(false);
    }
    
    public RESTSession get_parent_session() {
        return parent_session;
    }
}

public abstract class PhotoUploadTransaction : RESTTransaction {
    private string source_file;
    private Soup.Message in_transmission = null;
    private int in_transmission_bytes_written = 0;
    private GLib.HashTable<string, string> binary_disposition_table = null;
    private string special_endpoint_url = null;
    private TransformablePhoto source_photo = null;

    public signal void chunk_transmitted(int transmitted_bytes, int total_bytes);

    public PhotoUploadTransaction(RESTSession session, string source_file,
        TransformablePhoto source_photo) {
        base(session);

        this.source_file = source_file;
        this.source_photo = source_photo;
        binary_disposition_table = create_default_binary_disposition_table();
    }

    public override void execute() throws PublishingError {
        sign();

        // before they can be executed, photo upload requests must be signed and must
        // contain at least one argument
        assert(get_is_signed());

        RESTArgument[] request_arguments = get_arguments();
        assert(request_arguments.length > 0);

        // create the multipart request container
        Soup.Multipart message_parts = new Soup.Multipart("multipart/form-data");

        // attach each REST argument as its own multipart formdata part
        foreach (RESTArgument arg in request_arguments)
            message_parts.append_form_string(arg.key, arg.value);
        
        // append the signature key-value pair to the formdata string
        message_parts.append_form_string(get_signature_key(), get_signature_value());

        // attempt to read the binary image data from disk
        string photo_data;
        ulong data_length;
        try {
            FileUtils.get_contents(source_file, out photo_data, out data_length);
        } catch (FileError e) {
            error("PhotoUploadTransaction: couldn't read data from file '%s'", source_file);
        }

        // get the sequence number of the part that will soon become the binary image data
        // part
        int image_part_num = message_parts.get_length();

        // bind the binary image data read from disk into a Soup.Buffer object so that we
        // can attach it to the multipart request, then actaully append the buffer
        // to the multipart request. Then, set the MIME type for this part.
        Soup.Buffer bindable_data = new Soup.Buffer(Soup.MemoryUse.COPY, photo_data, data_length);
        message_parts.append_form_file("", source_file, "image/jpeg", bindable_data);

        // set up the Content-Disposition header for the multipart part that contains the
        // binary image data
        unowned Soup.MessageHeaders image_part_header;
        unowned Soup.Buffer image_part_body;
        message_parts.get_part(image_part_num, out image_part_header, out image_part_body);
        image_part_header.set_content_disposition("form-data", binary_disposition_table);

        // create a message that can be sent over the wire whose payload is the multipart container
        // that we've been building up
        Soup.Message outbound_message =
            Soup.form_request_new_from_multipart((special_endpoint_url == null) ?
            get_parent_session().get_endpoint_url() : special_endpoint_url, message_parts);
        set_active_message(outbound_message);
        
        // send the message and get its response
        outbound_message.wrote_body_data += on_wrote_body_data;
        in_transmission = outbound_message;
        in_transmission_bytes_written = 0;
        get_parent_session().send_message(outbound_message);
        in_transmission = null;
        outbound_message.wrote_body_data -= on_wrote_body_data;

        set_is_executed(true);
    }

    public void set_binary_disposition_table(GLib.HashTable<string, string> new_disp_table) {
        binary_disposition_table = new_disp_table;
    }

    private void on_wrote_body_data(Soup.Buffer written_data) {
        in_transmission_bytes_written += (int) written_data.length;
        chunk_transmitted(in_transmission_bytes_written, (int) in_transmission.request_body.length);
    }

    private GLib.HashTable<string, string> create_default_binary_disposition_table() {
        GLib.HashTable<string, string> result =
            new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);

        result.insert("filename", source_photo.get_name());

        return result;
    }

    public void set_special_endpoint_url(string endpoint_url) {
        special_endpoint_url = endpoint_url;
    }

    protected string get_source_file() {
        return source_file;
    }
}

public abstract class PublishingDialogPane : Gtk.VBox {
    public virtual void run_interaction() throws PublishingError {
        show_all();
    }
}

public class StaticMessagePane : PublishingDialogPane {
    public StaticMessagePane(string message_string) {
        Gtk.Label message_label = new Gtk.Label(message_string);
        add(message_label);
    }
    
    public StaticMessagePane.with_pango(string msg) {
        Gtk.Label label = new Gtk.Label(null);
        label.set_markup(msg);
        
        add(label);
    }
}

public class LoginWelcomePane : PublishingDialogPane {
    private Gtk.Button login_button;

    public signal void login_requested();

    public LoginWelcomePane(string service_welcome_message) {
        Gtk.SeparatorToolItem top_space = new Gtk.SeparatorToolItem();
        top_space.set_draw(false);
        Gtk.SeparatorToolItem bottom_space = new Gtk.SeparatorToolItem();
        bottom_space.set_draw(false);
        add(top_space);
        top_space.set_size_request(-1, 140);

        Gtk.Table content_layouter = new Gtk.Table(2, 1, false);

        Gtk.Label not_logged_in_label = new Gtk.Label(service_welcome_message);
        not_logged_in_label.set_line_wrap(true);
        not_logged_in_label.set_size_request(PublishingDialog.STANDARD_CONTENT_LABEL_WIDTH, -1);
        content_layouter.attach(not_logged_in_label, 0, 1, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 0);
        not_logged_in_label.set_size_request(PublishingDialog.STANDARD_CONTENT_LABEL_WIDTH, 112);
        not_logged_in_label.set_alignment(0.5f, 0.0f);

        login_button = new Gtk.Button.with_mnemonic(_("_Login"));
        Gtk.Alignment login_button_aligner =
            new Gtk.Alignment(0.5f, 0.5f, 0.0f, 0.0f);      
        login_button_aligner.add(login_button);
        login_button.set_size_request(80, -1);
        login_button.clicked += on_login_clicked;

        content_layouter.attach(login_button_aligner, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 0);
        add(content_layouter);
        add(bottom_space);
        bottom_space.set_size_request(-1, 112);
    }
    
    private void on_login_clicked() {
        login_requested();
    }
}
public class ProgressPane : PublishingDialogPane {
    private Gtk.ProgressBar progress_bar;
    private Gtk.Label secondary_text;

    public ProgressPane() {
        progress_bar = new Gtk.ProgressBar();
        secondary_text = new Gtk.Label("");
        
        Gtk.HBox progress_bar_wrapper = new Gtk.HBox(false, 0);
        Gtk.SeparatorToolItem left_padding = new Gtk.SeparatorToolItem();
        left_padding.set_size_request(10, -1);
        left_padding.set_draw(false);
        Gtk.SeparatorToolItem right_padding = new Gtk.SeparatorToolItem();
        right_padding.set_size_request(10, -1);
        right_padding.set_draw(false);
        progress_bar_wrapper.add(left_padding);
        progress_bar_wrapper.add(progress_bar);
        progress_bar_wrapper.add(right_padding);

        Gtk.SeparatorToolItem top_padding = new Gtk.SeparatorToolItem();
        top_padding.set_size_request(-1, 100);
        top_padding.set_draw(false);
        Gtk.SeparatorToolItem bottom_padding = new Gtk.SeparatorToolItem();
        bottom_padding.set_size_request(-1, 100);
        bottom_padding.set_draw(false);
        
        add(top_padding);
        add(progress_bar_wrapper);
        add(secondary_text);
        add(bottom_padding);
    }

    public void set_status_text(string text) {
        progress_bar.set_text(text);
    }

    public void set_progress(double progress) {
        progress_bar.set_fraction(progress);
    }
}

public abstract class UploadActionPane : ProgressPane {
    private const string TEMP_FILE_PREFIX = "publishing-";
    private const double PREPARATION_PHASE_FRACTION = 0.3;
    private const double UPLOAD_PHASE_FRACTION = 0.7;
    private int num_files;
    private int current_file_num;
    private bool user_cancelled = false;
    private PublishingDialog host;

    public struct TemporaryFileDescriptor {
        public File temp_file;
        public TransformablePhoto source_photo;

        public TemporaryFileDescriptor() {
            temp_file = null;
            source_photo = null;
        }

        public TemporaryFileDescriptor.with_members(TransformablePhoto source_photo,
            File temp_file) {
            this.source_photo = source_photo;
            this.temp_file = temp_file;
        }
    }

    public UploadActionPane(PublishingDialog host) {
        this.host = host;
    }

    public void upload() throws PublishingError {
        set_status_text(_("Preparing photos for upload"));
        spin_event_loop();

        num_files = host.get_target_collection_size();
        
        TemporaryFileDescriptor[] temp_files = prepare_files();
        
        try {
            if (!user_cancelled && temp_files.length > 0)
                send_files(temp_files);
        } finally {
            foreach (TemporaryFileDescriptor temp in temp_files) {
                try {
                    debug("Deleting temp %s", temp.temp_file.get_path());
                    temp.temp_file.delete(null);
                } catch (Error e) {
                    // if deleting temporary files generates an exception, just print a warning
                    // message -- temp directory clean-up will be done on launch or at exit or
                    // both
                    warning("UploadActionPane: deleting temporary files failed.");
                }
            }
        }
    }
    
    private TemporaryFileDescriptor[] prepare_files() {
        File temp_dir = AppDirs.get_temp_dir();
        
        current_file_num = 0;
        TemporaryFileDescriptor[] temp_files = new TemporaryFileDescriptor[0];
        foreach (DataView view in host.get_target_collection()) {
            if (user_cancelled) {
                break;
            }

            TransformablePhoto photo = (TransformablePhoto) view.get_source();
            File current_temp_file = temp_dir.get_child(TEMP_FILE_PREFIX +
                ("%d".printf(current_file_num)) + ".jpg");
            TemporaryFileDescriptor current_descriptor =
                TemporaryFileDescriptor.with_members(photo, current_temp_file);

            prepare_file(current_descriptor);

            current_file_num++;
            temp_files += current_descriptor;
            
            double phase_fraction_complete = ((double) current_file_num) / ((double) num_files);
            double fraction_complete = phase_fraction_complete * PREPARATION_PHASE_FRACTION;
            set_progress(fraction_complete);

            spin_event_loop();
        }
        
        return temp_files;
    }
    
    private void send_files(TemporaryFileDescriptor[] temp_files) throws PublishingError {
        current_file_num = 0;
        foreach (TemporaryFileDescriptor current_descriptor in temp_files) {
            if (user_cancelled) {
                return;
            }

            set_status_text(_("Uploading photo %d of %d").printf(current_file_num + 1,
                num_files));
            spin_event_loop();
            
            upload_file(current_descriptor);
            
            current_file_num++;
        }
    }

    protected abstract void prepare_file(TemporaryFileDescriptor file);
    
    protected abstract void upload_file(TemporaryFileDescriptor file) throws PublishingError;

    protected void on_chunk_transmitted(int transmitted_bytes, int total_bytes) {
        if (!user_cancelled) {
            double file_span = UPLOAD_PHASE_FRACTION / ((double) num_files);
            double this_file_fraction_complete = ((double) transmitted_bytes) / ((double) total_bytes);
            double fraction_complete = PREPARATION_PHASE_FRACTION +
                (((double) current_file_num) * file_span) +
                (this_file_fraction_complete * file_span);
            set_progress(fraction_complete);
            spin_event_loop();
        }
    }

    protected PublishingDialog get_host() {
        return host;
    }

    public void cancel_upload() {
        user_cancelled = true;
    }

    public bool get_user_cancelled() {
        return user_cancelled;
    }
}

public class SuccessPane : PublishingDialogPane {
    public SuccessPane() {
        Gtk.Label success_label = new Gtk.Label(_("The selected photos were successfully published."));
        add(success_label);
    }
}

public class PublishingDialog : Gtk.Dialog {
    private const int LARGE_WINDOW_WIDTH = 860;
    private const int LARGE_WINDOW_HEIGHT = 688;
    private const int STANDARD_WINDOW_WIDTH = 600;
    private const int STANDARD_WINDOW_HEIGHT = 510;
    private const int BORDER_REGION_WIDTH = 16;
    private const int BORDER_REGION_HEIGHT = 100;
    public const int STANDARD_CONTENT_LABEL_WIDTH = 500;

    private static PublishingDialog active_instance = null;
    
    private Gtk.ComboBox service_selector_box;
    private Gtk.Label service_selector_box_label;
    private Gtk.VBox central_area_layouter;
    private Gtk.Button close_cancel_button;
    private Gee.Iterable<DataView> target_collection;
    private int num_items;
    private PublishingDialogPane active_pane;
    private ServiceInteractor interactor;

    public PublishingDialog(Gee.Iterable<DataView> to_publish, int publish_num_items) {
        active_instance = this;

        set_title(_("Publish Photos"));
        resizable = false;
        delete_event += on_window_close;

        target_collection = to_publish;
        num_items = publish_num_items;

        service_selector_box = new Gtk.ComboBox.text();
        service_selector_box.set_active(0);
        service_selector_box_label = new Gtk.Label.with_mnemonic(_("Publish photos _to:"));
        service_selector_box_label.set_mnemonic_widget(service_selector_box);
        service_selector_box_label.set_alignment(0.0f, 0.5f);
        
        foreach (string service_name in ServiceFactory.get_instance().get_manifest())
            service_selector_box.append_text(service_name);
        service_selector_box.changed += on_service_changed;

        Gtk.HBox service_selector_layouter = new Gtk.HBox(false, 8);
        service_selector_layouter.set_border_width(12);
        service_selector_layouter.add(service_selector_box_label);
        service_selector_layouter.add(service_selector_box);
        
        central_area_layouter = new Gtk.VBox(false, 8);

        Gtk.HSeparator service_central_separator = new Gtk.HSeparator();

        vbox.add(service_selector_layouter);
        vbox.add(service_central_separator);
        vbox.add(central_area_layouter);
        service_selector_layouter.show_all();
        central_area_layouter.show_all();
        service_central_separator.show_all();
        
        close_cancel_button = new Gtk.Button.with_mnemonic("_Cancel");
        close_cancel_button.clicked += on_close_cancel_clicked;
        action_area.add(close_cancel_button);
        close_cancel_button.show_all();

        set_standard_window_mode();

        Config config = Config.get_instance();
        service_selector_box.set_active(config.get_default_service());

        interactor = ServiceFactory.get_instance().create_interactor(this,
            service_selector_box.get_active_text());
        try {
            interactor.start_interaction();
        } catch (PublishingError e) {
            on_error(e);
        }
    }

    public void install_pane(PublishingDialogPane pane) {
        if (active_pane != null)
            central_area_layouter.remove(active_pane);

        central_area_layouter.add(pane);
        central_area_layouter.show_all();
        spin_event_loop();

        active_pane = pane;
    }

    public void set_large_window_mode() {
        set_size_request(LARGE_WINDOW_WIDTH, LARGE_WINDOW_HEIGHT);
        central_area_layouter.set_size_request(LARGE_WINDOW_WIDTH - BORDER_REGION_WIDTH,
            LARGE_WINDOW_HEIGHT - BORDER_REGION_HEIGHT);
    }

    public void set_standard_window_mode() {
        set_size_request(STANDARD_WINDOW_WIDTH, STANDARD_WINDOW_HEIGHT);
        central_area_layouter.set_size_request(STANDARD_WINDOW_WIDTH - BORDER_REGION_WIDTH,
            STANDARD_WINDOW_HEIGHT - BORDER_REGION_HEIGHT);
    }

    public void set_close_button_mode() {
        close_cancel_button.set_label(_("_Close"));
    }

    public void set_cancel_button_mode() {
        close_cancel_button.set_label(_("_Cancel"));
    }

    public void lock_service() {
        service_selector_box.set_sensitive(false);
    }

    public void unlock_service() {
        service_selector_box.set_sensitive(true);
    }

    private void on_close_cancel_clicked() {
        if (interactor != null)
            interactor.cancel_interaction();

        hide();
        destroy();
    }

    private bool on_window_close(Gdk.Event evt) {
        hide();
        destroy();

        return true;
    }

    public void on_error(PublishingError err) {
        string name = interactor.get_name();
        
        warning("%s publishing error: %s", name, err.message);
        
        string msg = null;
        if (err is PublishingError.NO_ANSWER) {
            msg = _("Publishing to %s can't continue because the service could not be contacted.").printf(
                name);
        } else if (err is PublishingError.COMMUNICATION_FAILED) {
            msg = _("Publishing to %s can't continue because communication with the service failed.").printf(
                name);
        } else if (err is PublishingError.PROTOCOL_ERROR) {
            msg = _("Publishing to %s can't continue due to a protocol error.").printf(name);
        } else if (err is PublishingError.SERVICE_ERROR) {
            msg = _("Publishing to %s can't continue because the service returned an error.").printf(name);
        } else if (err is PublishingError.MALFORMED_RESPONSE) {
            msg = _("Publishing to %s can't continue because the service returned a bad response.").printf(
                name);
        } else {
            msg = _("Publishing to %s can't continue because an error occurred.").printf(name);
        }
        
        msg += GLib.Markup.printf_escaped("\n\n\t<i>%s</i>\n\n", err.message);
        msg += _("To try publishing to another service, select one from the above menu.");
        
        on_pango_error_message(msg);
    }
    
    public void on_error_message(string msg) {
        install_pane(new StaticMessagePane(msg));
        set_close_button_mode();
        unlock_service();
    }
    
    public void on_pango_error_message(string msg) {
        install_pane(new StaticMessagePane.with_pango(msg));
        set_close_button_mode();
        unlock_service();
    }
    
    public void on_success() {
        install_pane(new SuccessPane());
        set_close_button_mode();
        lock_service();
    }
    
    private void on_service_changed() {
        Config config = Config.get_instance();
        config.set_default_service(service_selector_box.get_active());
        interactor = ServiceFactory.get_instance().create_interactor(this,
            service_selector_box.get_active_text());
        try {
            interactor.start_interaction();
        } catch (PublishingError e) {
            on_error(e);
        }
    }
    
    public Gee.Iterable<DataView> get_target_collection() {
        return target_collection;
    }

    public int get_target_collection_size() {
        return num_items;
    }

    public static PublishingDialog get_active_instance() {
        return active_instance;
    }

    public ServiceInteractor get_interactor() {
        return interactor;
    }
}

public abstract class ServiceInteractor {
    private PublishingDialog host;

    public ServiceInteractor(PublishingDialog creator_host) {
        host = creator_host;
    }

    protected PublishingDialog get_host() {
        return host;
    }
    
    public abstract string get_name();
    
    public abstract void start_interaction() throws PublishingError;
    
    public abstract void cancel_interaction();
}

// TODO: in the future, when we support an arbitrary number of services potentially
//       developed by third parties, the ServiceFactory will support dynamic
//       registration of services at runtime. For right now, with only two services,
//       we just bake the services into the factory. Whatever we do in the future,
//       however, only this ServiceFactory class will have to change; all of its
//       clients will still see the same interface no matter how it's implemented
//       internally.
public class ServiceFactory {
    private static ServiceFactory instance = null;   

    private ServiceFactory() {
    }
    
    public static ServiceFactory get_instance() {
        if (instance == null)
            instance = new ServiceFactory();
        
        return instance;
    }
    
    public string[] get_manifest() {
        string[] result = new string[0];

        result += "Facebook";
        result += "Flickr";
        result += "Picasa Web Albums";

        return result;
    }
    
    public ServiceInteractor? create_interactor(PublishingDialog host, string service_name) {
        if (service_name == "Facebook") {
            return new FacebookConnector.Interactor(host);
        } else if (service_name == "Flickr") {
            return new FlickrConnector.Interactor(host);
        } else if (service_name == "Picasa Web Albums") {
            return new PicasaConnector.Interactor(host);
        } else {
            error("ServiceInteractor: unsupported service '%s'", service_name);
            return null;
        }
    }
}

public class RESTXmlDocument {
    // Returns non-null string if an error condition is discovered in the XML (such as a well-known 
    // node).  The string is used when generating a PublishingError exception.  This delegate does
    // not need to check for general-case malformed XML.
    public delegate string? CheckForErrorResponse(RESTXmlDocument doc);
    
    private Xml.Doc* document;

    private RESTXmlDocument(Xml.Doc* doc) {
        document = doc;
    }

    ~RESTXmlDocument() {
        delete document;
    }

    public Xml.Node* get_root_node() {
        return document->get_root_element();
    }

    public Xml.Node* get_named_child(Xml.Node* parent, string child_name) throws PublishingError {
        Xml.Node* doc_node_iter = parent->children;
    
        for ( ; doc_node_iter != null; doc_node_iter = doc_node_iter->next) {
            if (doc_node_iter->name == child_name)
                return doc_node_iter;
        }

        throw new PublishingError.MALFORMED_RESPONSE("Can't find XML node %s", child_name);
    }

    public string get_property_value(Xml.Node* node, string property_key) throws PublishingError {  
        string value_string = node->get_prop(property_key);
        if (value_string == null)
            throw new PublishingError.MALFORMED_RESPONSE("Can't find XML property %s on node %s",
                property_key, node->name);

        return value_string;
    }

    public static RESTXmlDocument parse_string(string? input_string, CheckForErrorResponse check_for_error_response) 
        throws PublishingError {
        if (input_string == null || input_string.length == 0)
            throw new PublishingError.MALFORMED_RESPONSE("Empty XML string");
        
        // Don't want blanks to be included as text nodes, and want the XML parser to tolerate
        // tolerable XML
        Xml.Doc* doc = Xml.Parser.read_memory(input_string, (int) input_string.length, null, null,
            Xml.ParserOption.NOBLANKS | Xml.ParserOption.RECOVER);
        if (doc == null)
            throw new PublishingError.MALFORMED_RESPONSE("Unable to parse XML document");
        
        RESTXmlDocument rest_doc = new RESTXmlDocument(doc);
        
        string? result = check_for_error_response(rest_doc);
        if (result != null)
            throw new PublishingError.SERVICE_ERROR("%s", result);
        
        return rest_doc;
    }
}

#endif

