/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace PublishingUI {

public class ConcreteDialogPane : Spit.Publishing.DialogPane, GLib.Object {
    private Gtk.VBox pane_widget;
    
    public ConcreteDialogPane() {
        pane_widget = new Gtk.VBox(false, 8);
    }
    
    public Gtk.Widget get_widget() {
        return pane_widget;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
    }

    public void on_pane_uninstalled() {
    }
}

public class StaticMessagePane : ConcreteDialogPane {
    public StaticMessagePane(string message_string) {
        Gtk.Label message_label = new Gtk.Label(message_string);
        (get_widget() as Gtk.Container).add(message_label);
    }
    
    public StaticMessagePane.with_pango(string msg) {
        Gtk.Label label = new Gtk.Label(null);
        label.set_markup(msg);
        
        (get_widget() as Gtk.Container).add(label);
    }
}

public class LoginWelcomePane : ConcreteDialogPane {
    private Gtk.Button login_button;

    public signal void login_requested();

    public LoginWelcomePane(string service_welcome_message) {
        Gtk.Table content_layouter = new Gtk.Table(2, 1, false);

        Gtk.Alignment label_wrapper = new Gtk.Alignment(0.5f, 1.0f, 0.0f, 0.0f);

        Gtk.Label not_logged_in_label = new Gtk.Label("");
        not_logged_in_label.set_use_markup(true);
        not_logged_in_label.set_markup(service_welcome_message);
        not_logged_in_label.set_line_wrap(true);
        not_logged_in_label.set_size_request(PublishingDialog.STANDARD_CONTENT_LABEL_WIDTH, -1);

        label_wrapper.add(not_logged_in_label);

        content_layouter.attach(label_wrapper, 0, 1, 0, 1,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 0);
        not_logged_in_label.set_size_request(PublishingDialog.STANDARD_CONTENT_LABEL_WIDTH, 150);
        not_logged_in_label.set_alignment(0.5f, 0.0f);

        login_button = new Gtk.Button.with_mnemonic(_("_Login"));
        Gtk.Alignment login_button_aligner =
            new Gtk.Alignment(0.5f, 0.25f, 0.0f, 0.0f);      
        login_button_aligner.add(login_button);
        login_button.set_size_request(PublishingDialog.STANDARD_ACTION_BUTTON_WIDTH, -1);
        login_button.clicked.connect(on_login_clicked);

        content_layouter.attach(login_button_aligner, 0, 1, 1, 2,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
            Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL, 6, 0);

        (get_widget() as Gtk.Container).add(content_layouter);
    }

    private void on_login_clicked() {
        login_requested();
    }
}

public class ProgressPane : ConcreteDialogPane {
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
        
        (get_widget() as Gtk.Container).add(top_padding);
        (get_widget() as Gtk.Container).add(progress_bar_wrapper);
        (get_widget() as Gtk.Container).add(secondary_text);
        (get_widget() as Gtk.Container).add(bottom_padding);
    }

    public void set_text(string text) {
        progress_bar.set_text(text);
    }

    public void set_progress(double progress) {
        progress_bar.set_fraction(progress);
    }

    public void set_status(string status_text, double progress) {
        if (status_text != progress_bar.get_text())
            progress_bar.set_text(status_text);

        set_progress(progress);
    }
}

public class SuccessPane : StaticMessagePane {
    public SuccessPane(Spit.Publishing.Publisher.MediaType published_media, int num_uploaded = 1) {
        string? message_string = null;

        // Here, we check whether more than one item is being uploaded, and if so, display
        // an alternate message.
        if(num_uploaded > 1) {
            if (published_media == (Spit.Publishing.Publisher.MediaType.PHOTO | Spit.Publishing.Publisher.MediaType.VIDEO))
                message_string = _("The selected photos/videos were successfully published.");
            else if (published_media == Spit.Publishing.Publisher.MediaType.VIDEO)
                message_string = _("The selected videos were successfully published.");
            else
                message_string = _("The selected photos were successfully published.");
        } else {
            if (published_media == Spit.Publishing.Publisher.MediaType.VIDEO)
                message_string = _("The selected video was successfully published.");
            else
                message_string = _("The selected photo was successfully published.");
        }
        base(message_string);
    }
}

public class AccountFetchWaitPane : StaticMessagePane {
    public AccountFetchWaitPane() {
        base(_("Fetching account information..."));
    }
}

public class LoginWaitPane : StaticMessagePane {
    public LoginWaitPane() {
        base(_("Logging in..."));
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
    public const int STANDARD_ACTION_BUTTON_WIDTH = 128;

    private static PublishingDialog active_instance = null;
    
    private Gtk.ComboBox service_selector_box;
    private Gtk.Label service_selector_box_label;
    private Gtk.VBox central_area_layouter;
    private Gtk.Button close_cancel_button;
    private Spit.Publishing.DialogPane active_pane;
    private Spit.Publishing.Publishable[] publishables;
    private Spit.Publishing.ConcretePublishingHost host;

    protected PublishingDialog(Gee.Collection<MediaSource> to_publish) {
        assert(to_publish.size > 0);

        resizable = false;
        delete_event.connect(on_window_close);
        
        publishables = new Spit.Publishing.Publishable[0];
        bool has_photos = false;
        bool has_videos = false;
        foreach (MediaSource media in to_publish) {
            Spit.Publishing.Publishable publishable =
                new Publishing.Glue.MediaSourcePublishableWrapper(media);
            if (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.PHOTO)
                has_photos = true;
            else if (publishable.get_media_type() == Spit.Publishing.Publisher.MediaType.VIDEO)
                has_videos = true;
            else
                assert_not_reached();
            
            publishables += publishable;
        }

        string title = null;
        string label = null;
        
        if (has_photos && !has_videos) {
            title = null;_("Publish Photos");
            label = _("Publish photos _to:");
        } else if (!has_photos && has_videos) {
            title = _("Publish Videos");
            label = _("Publish videos _to");
        } else {
            title = _("Publish Photos and Videos");
            label = _("Publish photos and videos _to");
        }
        set_title(title);

        service_selector_box = new Gtk.ComboBox.text();
        service_selector_box.set_active(0);
        service_selector_box_label = new Gtk.Label.with_mnemonic(label);
        service_selector_box_label.set_mnemonic_widget(service_selector_box);
        service_selector_box_label.set_alignment(0.0f, 0.5f);

        // get the name of the service the user last used
        string? last_used_service = Config.Facade.get_instance().get_last_used_service();

        Spit.Publishing.Service[] loaded_services = load_services(has_photos, has_videos);
        int ticker = 0;
        int last_used_index = -1;
        foreach (Spit.Publishing.Service service in loaded_services) {
            string curr_service_id = service.get_id();
            if (last_used_service != null && last_used_service == curr_service_id)
                last_used_index = ticker;

            service_selector_box.append_text(service.get_pluggable_name());
            ticker++;
        }
        if (last_used_index >= 0)
            service_selector_box.set_active(last_used_index);
        else
            service_selector_box.set_active(0);

        service_selector_box.changed.connect(on_service_changed);

        /* the wrapper is not an extraneous widget -- it's necessary to prevent the service
           selection box from growing and shrinking whenever its parent's size changes.
           When wrapped inside a Gtk.Alignment, the Alignment grows and shrinks instead of
           the service selection box. */
        Gtk.Alignment service_selector_box_wrapper = new Gtk.Alignment(1.0f, 0.5f, 0.0f, 0.0f);
        service_selector_box_wrapper.add(service_selector_box);

        Gtk.HBox service_selector_layouter = new Gtk.HBox(false, 8);
        service_selector_layouter.set_border_width(12);
        service_selector_layouter.add(service_selector_box_label);
        service_selector_layouter.add(service_selector_box_wrapper);
        
        /* 'service area' is the selector assembly plus the horizontal rule dividing it from the
           rest of the dialog */
        Gtk.VBox service_area_layouter = new Gtk.VBox(false, 0);
        service_area_layouter.add(service_selector_layouter);
        Gtk.HSeparator service_central_separator = new Gtk.HSeparator();
        service_area_layouter.add(service_central_separator);

        Gtk.Alignment service_area_wrapper = new Gtk.Alignment(0.0f, 0.0f, 1.0f, 0.0f);
        service_area_wrapper.add(service_area_layouter);
        
        central_area_layouter = new Gtk.VBox(false, 0);

        vbox.pack_start(service_area_wrapper, false, false, 0);
        vbox.pack_start(central_area_layouter, true, true, 0);
        
        close_cancel_button = new Gtk.Button.with_mnemonic("_Cancel");
        close_cancel_button.set_can_default(true);
        close_cancel_button.clicked.connect(on_close_cancel_clicked);
        action_area.add(close_cancel_button);

        set_standard_window_mode();
        
        show_all();
    }
    
    private static Spit.Publishing.Service[] load_all_services() {
        Spit.Publishing.Service[] loaded_services = new Spit.Publishing.Service[0];
        
        // load publishing services from plug-ins
        Gee.Collection<Spit.Pluggable> pluggables = Plugins.get_pluggables_for_type(
            typeof(Spit.Publishing.Service));
            
        debug("PublisingDialog: discovered %d pluggable publishing services.", pluggables.size);

        foreach (Spit.Pluggable pluggable in pluggables) {
            int pluggable_interface = pluggable.get_pluggable_interface(
                Spit.Publishing.CURRENT_INTERFACE, Spit.Publishing.CURRENT_INTERFACE);
            if (pluggable_interface != Spit.Publishing.CURRENT_INTERFACE) {
                warning("Unable to load publisher %s: reported interface %d.",
                    Plugins.get_pluggable_module_id(pluggable), pluggable_interface);
                
                continue;
            }
            
            Spit.Publishing.Service service =
                (Spit.Publishing.Service) pluggable;

            debug("PublishingDialog: discovered pluggable publishing service '%s'.",
                service.get_pluggable_name());
            
            loaded_services += service;
        }
        
        // Sort publishing services by name.
        Posix.qsort(loaded_services, loaded_services.length, sizeof(Spit.Publishing.Service), 
            (a, b) => {return utf8_cs_compare((*((Spit.Publishing.Service**) a))->get_pluggable_name(), 
                (*((Spit.Publishing.Service**) b))->get_pluggable_name());
        });
        
        return loaded_services;
    }
    
    private static Spit.Publishing.Service[] load_services(bool has_photos, bool has_videos) {
        assert (has_photos || has_videos);
        
        Spit.Publishing.Service[] filtered_services = new Spit.Publishing.Service[0];        
        Spit.Publishing.Service[] all_services = load_all_services();

        foreach (Spit.Publishing.Service service in all_services) {
            
            if (has_photos && !has_videos) {
                if ((service.get_supported_media() & Spit.Publishing.Publisher.MediaType.PHOTO) != 0)
                    filtered_services += service;
            } else if (!has_photos && has_videos) {
                if ((service.get_supported_media() & Spit.Publishing.Publisher.MediaType.VIDEO) != 0)
                    filtered_services += service;
            } else {
                if (((service.get_supported_media() & Spit.Publishing.Publisher.MediaType.PHOTO) != 0) &&
                    ((service.get_supported_media() & Spit.Publishing.Publisher.MediaType.VIDEO) != 0))
                    filtered_services += service;
            }
        }
        
        return filtered_services;
    }

    // Because of this bug: http://trac.yorba.org/ticket/3623, we use some extreme measures. The
    // bug occurs because, in some cases, when publishing is started asynchronous network 
    // transactions are performed. The mechanism inside libsoup that we use to perform asynchronous
    // network transactions isn't based on threads but is instead based on the GLib event loop. So
    // whenever we run a network transaction, the GLib event loop gets spun. One consequence of
    // this is that PublishingDialog.go( ) can be called multiple times. Note that since events
    // are processed sequentially, PublishingDialog.go( ) is never called re-entrantly. It just
    // gets called twice back-to-back in quick succession. So use a timer to do a short circuit
    // return if this call to go( ) follows immediately on the heels of another call to go( ).
    private static Timer since_last_start = null;
    public static void go(Gee.Collection<MediaSource> to_publish) {
        if (active_instance != null)
            return;
        
        if (since_last_start == null) {
			// GLib.Timers start themselves automatically when they're created, so stop our
            // new timer and reset it to zero 'til were ready to start timing. 
            since_last_start = new Timer();
            since_last_start.stop();
            since_last_start.reset();
        } else {
            double elapsed = since_last_start.elapsed();
            if (elapsed < 0.05)
                return;
        }

        Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<Video> videos = new Gee.ArrayList<Video>();
        MediaSourceCollection.filter_media(to_publish, photos, videos);
        
        Spit.Publishing.Service[] avail_services =
            load_services((photos.size > 0), (videos.size > 0));
        
        if (avail_services.length == 0) {
            // There are no enabled publishing services that accept this media type,
            // warn the user.
            AppWindow.error_message_with_title(_("Unable to publish"),
                _("Shotwell cannot publish the selected items because you do not have a compatible publishing plugin enabled. To correct this, choose <b>Edit %s Preferences</b> and enable one or more of the publishing plugins on the <b>Plugin</b> tab.").printf("▸"));
                    
            return;                
        }
        
        // If we get down here, it means that at least one publishing service 
        // was found that could accept this type of media, so continue normally.

        debug("PublishingDialog.go( )");
        
        active_instance = new PublishingDialog(to_publish);
        
        active_instance.run();

        active_instance = null;

        // start timing just before we return
        since_last_start.start();
    }
    
    private bool on_window_close(Gdk.Event evt) {
        host.stop_publishing();
        host = null;
        hide();
        destroy();
        
        return true;
    }

    private void on_service_changed() {
        string service_name = service_selector_box.get_active_text();
        
        Spit.Publishing.Service? selected_service = null;
        Spit.Publishing.Service[] services = load_all_services();
        foreach (Spit.Publishing.Service service in services) {
            if (service.get_pluggable_name() == service_name) {
                selected_service = service;
                break;
            }
        }
        assert(selected_service != null);

        Config.Facade.get_instance().set_last_used_service(selected_service.get_id());

        host = new Spit.Publishing.ConcretePublishingHost(selected_service, this, publishables);
        host.start_publishing();
    }
    
    private void on_close_cancel_clicked() {
        debug("PublishingDialog: on_close_cancel_clicked( ): invoked.");
        
        host.stop_publishing();
        host = null;
        hide();
        destroy();
    }
    
    private void set_large_window_mode() {
        set_size_request(LARGE_WINDOW_WIDTH, LARGE_WINDOW_HEIGHT);
        central_area_layouter.set_size_request(LARGE_WINDOW_WIDTH - BORDER_REGION_WIDTH,
            LARGE_WINDOW_HEIGHT - BORDER_REGION_HEIGHT);
        resizable = false;
    }

    private void set_standard_window_mode() {
        set_size_request(STANDARD_WINDOW_WIDTH, STANDARD_WINDOW_HEIGHT);
        central_area_layouter.set_size_request(STANDARD_WINDOW_WIDTH - BORDER_REGION_WIDTH,
            STANDARD_WINDOW_HEIGHT - BORDER_REGION_HEIGHT);
        resizable = false;
    }

    private void set_free_sizable_window_mode() {
        resizable = true;
    }

    private void clear_free_sizable_window_mode() {
        resizable = false;
    }

    public Spit.Publishing.DialogPane get_active_pane() {
        return active_pane;
    }

    public void set_close_button_mode() {
        close_cancel_button.set_label(_("_Close"));
        set_default(close_cancel_button);
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
    
    public void install_pane(Spit.Publishing.DialogPane pane) {
        debug("PublishingDialog: install_pane( ): invoked.");

        if (active_pane != null) {
            debug("PublishingDialog: install_pane( ): a pane is already installed; removing it.");

            active_pane.on_pane_uninstalled();
            central_area_layouter.remove(active_pane.get_widget());
        }

        central_area_layouter.add(pane.get_widget());
        show_all();

        Spit.Publishing.DialogPane.GeometryOptions geometry_options =
            pane.get_preferred_geometry();
        if ((geometry_options & Spit.Publishing.DialogPane.GeometryOptions.EXTENDED_SIZE) != 0)
            set_large_window_mode();
        else
            set_standard_window_mode();

        if ((geometry_options & Spit.Publishing.DialogPane.GeometryOptions.RESIZABLE) != 0)
            set_free_sizable_window_mode();
        else
            clear_free_sizable_window_mode();

        active_pane = pane;
        pane.on_pane_installed();
    }
    
    public new int run() {
        on_service_changed();

        int result = base.run();
        
        host = null;
        
        return result;
    }
}

}

