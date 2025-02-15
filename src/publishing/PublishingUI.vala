/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace PublishingUI {

public class PublishingDialog : Gtk.Dialog {
    private const int LARGE_WINDOW_WIDTH = 860;
    private const int LARGE_WINDOW_HEIGHT = 688;
    private const int COLOSSAL_WINDOW_WIDTH = 1024;
    private const int COLOSSAL_WINDOW_HEIGHT = 688;
    private const int STANDARD_WINDOW_WIDTH = 632;
    private const int STANDARD_WINDOW_HEIGHT = 540;
    private const int BORDER_REGION_WIDTH = 16;
    private const int BORDER_REGION_HEIGHT = 100;

    public const int STANDARD_CONTENT_LABEL_WIDTH = 500;
    public const int STANDARD_ACTION_BUTTON_WIDTH = 128;

    private static PublishingDialog active_instance = null;
    
    private Gtk.ListStore service_selector_box_model;
    private Gtk.ComboBox service_selector_box;
    private Gtk.Box central_area_layouter;
    private Gtk.Button close_cancel_button;
    private Spit.Publishing.DialogPane active_pane;
    private Spit.Publishing.Publishable[] publishables;
    private Spit.Publishing.ConcretePublishingHost host;
    private Spit.PluggableInfo info;

    protected PublishingDialog(Gee.Collection<MediaSource> to_publish) {
        assert(to_publish.size > 0);

        bool use_header = Resources.use_header_bar() == 1;
        Object(use_header_bar: Resources.use_header_bar());
        if (use_header) {
            ((Gtk.HeaderBar) get_header_bar()).set_show_title_buttons(false);
        } else {
            get_content_area().set_spacing(6);
        }

        resizable = false;
        modal = true;
        set_transient_for(AppWindow.get_instance());
        close_request.connect(on_window_close);

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
            title = _("Publish Photos");
            label = _("Publish photos _to:");
        } else if (!has_photos && has_videos) {
            title = _("Publish Videos");
            label = _("Publish videos _to");
        } else {
            title = _("Publish Photos and Videos");
            label = _("Publish photos and videos _to");
        }
        set_title(title);

        service_selector_box_model = new Gtk.ListStore(3, typeof(string), typeof(string),
            typeof(Spit.Publishing.Account));
        service_selector_box = new Gtk.ComboBox.with_model(service_selector_box_model);

        Gtk.CellRendererPixbuf renderer_pix = new Gtk.CellRendererPixbuf();
        service_selector_box.pack_start(renderer_pix,true);
        service_selector_box.add_attribute(renderer_pix, "icon-name", 0);

        Gtk.CellRendererText renderer_text = new Gtk.CellRendererText();
        service_selector_box.pack_start(renderer_text,true);
        service_selector_box.add_attribute(renderer_text, "text", 1);

        service_selector_box.set_active(0);

        // get the name of the service the user last used
        string? last_used_service = Config.Facade.get_instance().get_last_used_service();

        Spit.Publishing.Service[] loaded_services = load_services(has_photos, has_videos);

        Gtk.TreeIter iter;

        foreach (Spit.Publishing.Service service in loaded_services) {
            string curr_service_id = service.get_id();

            info = service.get_info();

            var accounts = service.get_accounts(Shotwell.ProfileManager.get_instance().id());

            foreach (var account in accounts) {
                service_selector_box_model.append(out iter);

                var account_name = account.display_name();
                var display_name = service.get_pluggable_name() + (account_name == "" ? "" : "/" + account_name);

                service_selector_box_model.set(iter, 0, info.icon_name, 1, display_name, 2, account);

                if (last_used_service == null) {
                    service_selector_box.set_active_iter(iter);
                    last_used_service = service.get_id();
                } else if (last_used_service == curr_service_id) {
                    service_selector_box.set_active_iter(iter);
                }
            }
        }

        service_selector_box.changed.connect(on_service_changed);
        
        if (!use_header)
        {
            var service_selector_box_label = new Gtk.Label.with_mnemonic(label);
            service_selector_box_label.set_mnemonic_widget(service_selector_box);
            service_selector_box_label.halign = Gtk.Align.START;
            service_selector_box_label.valign = Gtk.Align.CENTER;

            /* the wrapper is not an extraneous widget -- it's necessary to prevent the service
               selection box from growing and shrinking whenever its parent's size changes.
               When wrapped inside a Gtk.Alignment, the Alignment grows and shrinks instead of
               the service selection box. */
            service_selector_box.halign = Gtk.Align.END;
            service_selector_box.valign = Gtk.Align.CENTER;
            service_selector_box.hexpand = false;
            service_selector_box.vexpand = false;

            Gtk.Box service_selector_layouter = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            service_selector_layouter.hexpand = true;
            service_selector_layouter.append(service_selector_box_label);
            service_selector_layouter.prepend(service_selector_box);

            /* 'service area' is the selector assembly plus the horizontal rule dividing it from the
               rest of the dialog */
            Gtk.Box service_area_layouter = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            service_area_layouter.append(service_selector_layouter);
            service_area_layouter.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
            service_area_layouter.halign = Gtk.Align.FILL;
            service_area_layouter.valign = Gtk.Align.START;
            service_area_layouter.hexpand = true;
            service_area_layouter.vexpand = false;

            get_content_area().prepend(service_area_layouter);
        }

        central_area_layouter = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

        get_content_area().prepend(central_area_layouter);
        
        if (use_header) {
            close_cancel_button = new Gtk.Button.with_mnemonic("_Cancel");

            ((Gtk.HeaderBar) get_header_bar()).pack_start(close_cancel_button);
            ((Gtk.HeaderBar) get_header_bar()).pack_end(service_selector_box);
        }
        else {
            add_button (_("_Cancel"), Gtk.ResponseType.CANCEL);
            close_cancel_button = get_widget_for_response (Gtk.ResponseType.CANCEL) as Gtk.Button;
        }
        close_cancel_button.clicked.connect(on_close_cancel_clicked);

        set_standard_window_mode();
        
        show();
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

    // FIXME: This comment is no longer valid, I think.
    // Because of this bug: https://bugzilla.gnome.org/show_bug.cgi?id=717505, we use some
    // extreme measures. The bug occurs because, in some cases, when publishing is started
    // asynchronous network transactions are performed. The mechanism inside libsoup that we
    // use to perform asynchronous network transactions isn't based on threads but is instead
    // based on the GLib event loop. So whenever we run a network transaction, the GLib event
    // loop gets spun. One consequence of this is that PublishingDialog.go( ) can be called
    // multiple times. Note that since events are processed sequentially, PublishingDialog.go()
    // is never called re-entrantly. It just gets called twice back-to-back in quick
    // succession. So use a timer to do a short circuit return if this call to go( ) follows
    // immediately on the heels of another call to go( )
    private static Timer since_last_start = null;
    private static bool elapsed_is_valid = false;
    public static void go(Gee.Collection<MediaSource> to_publish) {
        if (active_instance != null)
            return;

        if (since_last_start == null) {
            // GLib.Timers start themselves automatically when they're created, so stop our
            // new timer and reset it to zero 'til were ready to start timing. 
            since_last_start = new Timer();
            since_last_start.stop();
            since_last_start.reset();
            elapsed_is_valid = false;
        } else {
            double elapsed = since_last_start.elapsed();
            if ((elapsed < 0.05) && (elapsed_is_valid))
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
            AppWindow.error_message_with_title.begin(_("Unable to publish"),
                _("Shotwell cannot publish the selected items because you do not have a compatible publishing plugin enabled. To correct this, choose Edit %s Preferences and enable one or more of the publishing plugins on the Plugins tab.").printf("▸"),
                AppWindow.get_instance(), false);

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
        elapsed_is_valid = true;
    }
    
    private bool on_window_close() {
        host.stop_publishing();
        host = null;
        hide();
        destroy();
        
        return true;
    }

    private void on_service_changed() {
        Gtk.TreeIter iter;
        bool have_active_iter = false;
        have_active_iter = service_selector_box.get_active_iter(out iter);
        
        // this occurs when the user removes the last active publisher
        if (!have_active_iter) {
            // default to the first in the list (as good as any)
            service_selector_box.set_active(0);
            
            // and get active again
            service_selector_box.get_active_iter(out iter);
        }
        
        Value service_name_val;
        Value account_val;
        service_selector_box_model.get_value(iter, 1, out service_name_val);
        service_selector_box_model.get_value(iter, 2, out account_val);
        
        string service_name = (string) service_name_val;
        var service_account = (Spit.Publishing.Account) account_val;
       
        Spit.Publishing.Service? selected_service = null;
        Spit.Publishing.Service[] services = load_all_services();
        foreach (Spit.Publishing.Service service in services) {
             if (service_name.has_prefix(service.get_pluggable_name())) {
                selected_service = service;
                break;
            }
        }
        assert(selected_service != null);

        Config.Facade.get_instance().set_last_used_service(selected_service.get_id());

        host = new Spit.Publishing.ConcretePublishingHost(selected_service, this, publishables, service_account);
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
    
    private void set_colossal_window_mode() {
        set_size_request(COLOSSAL_WINDOW_WIDTH, COLOSSAL_WINDOW_HEIGHT);
        central_area_layouter.set_size_request(COLOSSAL_WINDOW_WIDTH - BORDER_REGION_WIDTH,
            COLOSSAL_WINDOW_HEIGHT - BORDER_REGION_HEIGHT);
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
        set_default_widget(close_cancel_button);
    }

    public void set_cancel_button_mode() {
        close_cancel_button.set_label(_("_Cancel"));
        set_default_widget(null);
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
            active_pane.get_widget().unparent();
            //central_area_layouter.remove(active_pane.get_widget());
        }

        central_area_layouter.prepend(pane.get_widget());
        show();

        Spit.Publishing.DialogPane.GeometryOptions geometry_options =
            pane.get_preferred_geometry();
        if ((geometry_options & Spit.Publishing.DialogPane.GeometryOptions.EXTENDED_SIZE) != 0)
            set_large_window_mode();
        else if ((geometry_options & Spit.Publishing.DialogPane.GeometryOptions.COLOSSAL_SIZE) != 0)
            set_colossal_window_mode();
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

        int result = 0; //base.run();
        
        host = null;
        
        return result;
    }
}

}

