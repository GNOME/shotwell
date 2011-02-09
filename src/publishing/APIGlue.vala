/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */
namespace Publishing.Glue {

public class PublisherWrapperInteractor : ServiceInteractor, Spit.Publishing.Publisher {
    private Spit.Publishing.Publisher wrapped;
    private Spit.Publishing.PublishingInteractor new_api_interactor;
    private weak PublishingDialog old_api_dialog;
    
    public PublisherWrapperInteractor(Spit.Publishing.Publisher wrapped,
        Spit.Publishing.PublishingInteractor new_api_interactor, PublishingDialog old_api_dialog) {
        
        base(old_api_dialog);
        this.wrapped = wrapped;
        this.new_api_interactor = new_api_interactor;
        this.old_api_dialog = old_api_dialog;
    }
    
    public string get_service_name() {
        return wrapped.get_service_name();
    }
    
    public string get_user_visible_name() {
        return wrapped.get_user_visible_name();
    }
    
    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return wrapped.get_supported_media();
    }
    
    public void start(Spit.Publishing.PublishingInteractor interactor) {
        if (interactor is Spit.Publishing.PublishingHost)
            ((Spit.Publishing.PublishingHost) interactor).set_active_publisher(wrapped);
                
        wrapped.start(interactor);
    }
    
    public void stop() {
        debug("PublisherWrapperInteractor: stop( ) invoked.");

        old_api_dialog = null;
        new_api_interactor.stop_publishing();

        wrapped = null;
        new_api_interactor = null;
    }
    
    public bool is_running() {
        if (wrapped == null)
            return false;
        else
            return wrapped.is_running();
    }
    
    public override string get_name() {
        return get_user_visible_name();
    }
    
    public override void start_interaction() {
        debug("PublisherWrapperInteractor: start_interaction( ): invoked.");
        start(new_api_interactor);
    }
    
    public override void cancel_interaction() {
        debug("PublisherWrapperInteractor: cancel_interaction( ): invoked.");
        stop();
    }
}

public class DialogInteractorWrapper : PublishingDialog, Spit.Publishing.PublishingInteractor {
    Spit.Publishing.PublishingInteractor plugin_host;
    Spit.Publishing.Publishable[] publishables;
    
    public DialogInteractorWrapper(Gee.Collection<MediaSource> to_publish) {
        base(to_publish);
        
        publishables = new Spit.Publishing.Publishable[0];
        
        foreach (MediaSource current_media_item in to_publish)
            publishables += new MediaSourcePublishableWrapper(current_media_item);
    }
    
    public void set_plugin_host(Spit.Publishing.PublishingInteractor plugin_host) {
        this.plugin_host = plugin_host;
    }

    public void install_dialog_pane(Spit.Publishing.PublishingDialogPane pane) {
        debug("DialogInteractorWrapper: install_pane( ): invoked.");

        plugin_host.install_dialog_pane(pane);
    }
	
    public void post_error(Error err) {
        debug("DialogInteractorWrapper.post_error( ): err = '%s'.", err.message);

        plugin_host.post_error(err);
    }

    public void stop_publishing() {
        debug("DialogInteractorWrapper.stop_publishing( ): invoked.");
        
        plugin_host.stop_publishing();
    }

    public void install_static_message_pane(string message) {
        plugin_host.install_static_message_pane(message);
    }
    
    public void install_pango_message_pane(string markup) {
        plugin_host.install_pango_message_pane(markup);
    }
    
    public void install_success_pane(Spit.Publishing.Publisher.MediaType media_type) {
        plugin_host.install_success_pane(media_type);
    }
    
    public void install_account_fetch_wait_pane() {
        plugin_host.install_account_fetch_wait_pane();
    }
    
    public void install_login_wait_pane() {
        plugin_host.install_login_wait_pane();
    }
    
    public void install_welcome_pane(string welcome_message,
        Spit.Publishing.LoginCallback on_login_clicked) {
        plugin_host.install_welcome_pane(welcome_message, on_login_clicked);
    }
	
    public void set_service_locked(bool locked) {
        plugin_host.set_service_locked(locked);
    }
    
    public void set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode mode) {
        plugin_host.set_button_mode(mode);
    }

    public void set_dialog_default_widget(Gtk.Widget widget) {
        plugin_host.set_dialog_default_widget(widget);
    }
    
    public Spit.Publishing.Publisher.MediaType get_publishable_media_type() {
        return plugin_host.get_publishable_media_type();
    }
    
    public int get_config_int(string key, int default_value) {
        return plugin_host.get_config_int(key, default_value);
    }
    
    public string? get_config_string(string key, string? default_value) {
        return plugin_host.get_config_string(key, default_value);
    }
    
    public bool get_config_bool(string key, bool default_value) {
        return plugin_host.get_config_bool(key, default_value);
    }
    
    public double get_config_double(string key, double default_value) {
        return plugin_host.get_config_double(key, default_value);
    }
    
    public void set_config_int(string key, int value) {
        plugin_host.set_config_int(key, value);
    }
    
    public void set_config_string(string key, string value) {
        plugin_host.set_config_string(key, value);
    }
    
    public void set_config_bool(string key, bool value) {
        plugin_host.set_config_bool(key, value);
    }
    
    public void set_config_double(string key, double value) {
        plugin_host.set_config_double(key, value);
    }
    
    public Spit.Publishing.Publishable[] get_publishables() {
        return publishables;
    }
    
    public Spit.Publishing.ProgressCallback? serialize_publishables(int content_major_axis,
        bool strip_metadata = false) {
        return plugin_host.serialize_publishables(content_major_axis, strip_metadata);
    }
}

public class MediaSourcePublishableWrapper : Spit.Publishing.Publishable, GLib.Object {
    private static int name_ticker = 0;

    private MediaSource wrapped;
    private GLib.File? serialized_file = null;
    
    public MediaSourcePublishableWrapper(MediaSource to_wrap) {
        wrapped = to_wrap;
    }
    
    public void clean_up() {
        if (serialized_file == null)
            return;

        debug("cleaning up temporary publishing file '%s'.", serialized_file.get_path());

        try {
            serialized_file.delete(null);
        } catch (Error err) {
            warning("couldn't delete temporary publishing file '%s'.", serialized_file.get_path());
        }

        serialized_file = null;
    }

    public GLib.File serialize_for_publishing(int content_major_axis,
        bool strip_metadata = false) throws Spit.Publishing.PublishingError {

        if (wrapped is LibraryPhoto) {
            LibraryPhoto photo = (LibraryPhoto) wrapped;

            GLib.File to_file =
                AppDirs.get_temp_dir().get_child("publishing-%d.jpg".printf(name_ticker++));

            debug("writing photo '%s' to temporary file '%s' for publishing.",
                photo.get_source_id(), to_file.get_path());
            try {
                photo.export(to_file, Scaling.for_best_fit(content_major_axis, false),
                    Jpeg.Quality.HIGH, PhotoFileFormat.JFIF);
            } catch (Error err) {
                throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    "unable to serialize photo '%s' for publishing.", photo.get_name());
            }

            serialized_file = to_file;
        } else if (wrapped is Video) {
            Video video = (Video) wrapped;

            string basename;
            string extension;
            disassemble_filename(video.get_file().get_basename(), out basename, out extension);

            GLib.File to_file =
                GLib.File.new_for_path("publishing-%d.%s".printf(name_ticker++, extension));

            debug("writing video '%s' to temporary file '%s' for publishing.",
                video.get_source_id(), to_file.get_path());
            try {
                video.export(to_file);
            } catch (Error err) {
                throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    "unable to serialize video '%s' for publishing.", video.get_name());
            }

            serialized_file = to_file;
        } else {
            error("MediaSourcePublishableWrapper.serialize_for_publishing( ): unknown media type.");
        }

		return serialized_file;
    }

    public string get_publishing_name() {
        return wrapped.get_name();
    }

    public string get_publishing_description() {
        return "";
    }

    public string[] get_publishing_keywords() {
        string[] result = new string[0];
        
        Gee.Collection<Tag>? tagset = Tag.global.fetch_sorted_for_source(wrapped);
        if (tagset != null) {
            foreach (Tag tag in tagset) {
                result += tag.get_name();
            }
        }
        
        return result;
    }

    public Spit.Publishing.Publisher.MediaType get_media_type() {
        if (wrapped is LibraryPhoto)
            return Spit.Publishing.Publisher.MediaType.PHOTO;
        else if (wrapped is Video)
            return Spit.Publishing.Publisher.MediaType.VIDEO;
        else
            return Spit.Publishing.Publisher.MediaType.NONE;
    }
    
    public GLib.File? get_serialized_file() {
        return serialized_file;
    }
}

public class GlueFactory {
    private static GlueFactory instance = null;
    private Spit.Publishing.PublishingHost publishing_host = null;
    
    private GlueFactory() {
    }
    
    public static GlueFactory get_instance() {
        if (instance == null)
            instance = new GlueFactory();

        return instance;
    }
    
    public ServiceInteractor create_publisher(string service_name) {
        // the entire reason for the GlueFactory are the complicated requirements and
        // creation sequences for publishing glue classes
        
        // verify that the active PublishingDialog instance is not just a vanilla
        // PublishingDialog but an instance of a specialized glue subclass
        PublishingDialog active_dialog = PublishingDialog.get_active_instance();
        if (!(active_dialog is DialogInteractorWrapper))
            error("GlueFactory: active publishing dialog isn't a DialogInteractorWrapper; glue " +
                "can't work.");

        if (service_name != "facebook")
            error("GlueFactory: unsupported service name");

        Spit.Publishing.Publishable[] publishables =
            ((DialogInteractorWrapper) active_dialog).get_publishables();
        debug("GlueFactory: setting up adapters to publish %d items.", publishables.length);
        publishing_host = new Spit.Publishing.PublishingHost(active_dialog, publishables);

        ((DialogInteractorWrapper) active_dialog).set_plugin_host(publishing_host);

        // load publishing services from plug-ins
        Gee.Collection<Spit.Pluggable> pluggables = Plugins.get_pluggables_for_type(
            typeof(Spit.Publishing.PublishingService));
            
        debug("Publising API Glue: discovered %d pluggable publishing services.", pluggables.size);

        Spit.Publishing.PublishingService? facebook_service = null;
        foreach (Spit.Pluggable pluggable in pluggables) {
            int pluggable_interface = pluggable.get_pluggable_interface(
                Spit.Publishing.CURRENT_API_VERSION, Spit.Publishing.CURRENT_API_VERSION);
            if (pluggable_interface != Spit.Publishing.CURRENT_API_VERSION) {
                warning("Unable to load publisher %s: reported interface %d",
                    Plugins.get_pluggable_module_id(pluggable), pluggable_interface);
                
                continue;
            }
            
            Spit.Publishing.PublishingService service =
                (Spit.Publishing.PublishingService) pluggable;
            debug("Publishing API Glue: discovered pluggable publishing service '%s'.",
                service.get_pluggable_name());
            if (service.get_id() == "org.yorba.shotwell.publishing.facebook")
                facebook_service = service;
        }
        
        if (facebook_service == null)
            error("Publishing API Glue: required service 'Facebook' wasn't found.'");
        
        Spit.Publishing.Publisher real_publisher = facebook_service.create_publisher();
        
        ServiceInteractor publisher_wrapper = new PublisherWrapperInteractor(real_publisher,
            publishing_host, active_dialog);

        active_dialog = null;

        return publisher_wrapper;
    }
}

}

