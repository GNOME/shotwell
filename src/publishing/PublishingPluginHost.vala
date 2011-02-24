/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Spit.Publishing {

public class ConcretePublishingHost : Plugins.StandardHostInterface,
    Spit.Publishing.PluginHost {
    private const string PREPARE_STATUS_DESCRIPTION = _("Preparing for upload");
    private const string UPLOAD_STATUS_DESCRIPTION = _("Uploading %d of %d");
    private const double STATUS_PREPARATION_FRACTION = 0.3;
    private const double STATUS_UPLOAD_FRACTION = 0.7;
    
    private PublishingDialog dialog = null;
    private Spit.Publishing.DialogPane current_pane = null;
    private Spit.Publishing.Publisher active_publisher = null;
    private Publishable[] publishables = null;
    private LoginCallback current_login_callback = null;
    
    public ConcretePublishingHost(Service service, PublishingDialog dialog,
        Publishable[] publishables) {
        base(service, "sharing");
        this.dialog = dialog;
        this.publishables = publishables;
        this.active_publisher = service.create_publisher(this);
    }
    
    private void on_login_clicked() {
        if (current_login_callback != null)
            current_login_callback();
    }
    
    private void clean_up() {
        foreach (Publishable publishable in publishables)
            ((global::Publishing.Glue.MediaSourcePublishableWrapper) publishable).clean_up();
    }
    
    private void report_plugin_upload_progress(int file_number, double fraction_complete) {
        // if the currently installed pane isn't the progress pane, do nothing
        if (!(dialog.get_active_pane() is ProgressPane))
            return;

        ProgressPane pane = (ProgressPane) dialog.get_active_pane();
        
        string status_string = UPLOAD_STATUS_DESCRIPTION.printf(file_number,
            publishables.length);
        double status_fraction = STATUS_PREPARATION_FRACTION + (STATUS_UPLOAD_FRACTION *
            fraction_complete);
        
        pane.set_status(status_string, status_fraction);
    }

    private void install_progress_pane() {
        ProgressPane progress_pane = new ProgressPane();
        
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;
         
        dialog.install_pane(progress_pane);
        set_button_mode(Spit.Publishing.PluginHost.ButtonMode.CANCEL);
    }

    public void install_dialog_pane(Spit.Publishing.DialogPane pane,
        Spit.Publishing.PluginHost.ButtonMode button_mode) {
        debug("Publishing.PluginHost: install_dialog_pane( ): invoked.");

        if (active_publisher == null || (!active_publisher.is_running()))
            return;

        if (current_pane != null)
            current_pane.on_pane_uninstalled();

        dialog.install_pane(pane.get_widget());
        
        Spit.Publishing.DialogPane.GeometryOptions geometry_options =
            pane.get_preferred_geometry();
        if ((geometry_options & DialogPane.GeometryOptions.EXTENDED_SIZE) != 0)
            dialog.set_large_window_mode();
        else
            dialog.set_standard_window_mode();

        if ((geometry_options & DialogPane.GeometryOptions.RESIZABLE) != 0)
            dialog.set_free_sizable_window_mode();
        else
            dialog.clear_free_sizable_window_mode();
        
        set_button_mode(button_mode);
        
        current_pane = pane;
        
        pane.on_pane_installed();
    }
    
    public void post_error(Error err) {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;

        string msg = _("Publishing to %s can't continue because an error occurred:").printf(
            active_publisher.get_service().get_pluggable_name());
        msg += GLib.Markup.printf_escaped("\n\n\t<i>%s</i>\n\n", err.message);
        msg += _("To try publishing to another service, select one from the above menu.");
        
        dialog.show_pango_error_message(msg);

        active_publisher.stop();
        
        // post_error( ) tells the active_publisher to stop publishing and displays a
        // non-removable error pane that effectively ends the publishing interaction,
        // so no problem calling clean_up( ) here.
        clean_up();
    }

    public void stop_publishing() {
        debug("ConcretePublishingHost.stop_publishing( ): invoked.");
        
        if (active_publisher.is_running())
            active_publisher.stop();

        clean_up();

        dialog = null;
    }

    public Publisher get_publisher() {
        return active_publisher;
    }

    public void install_static_message_pane(string message,
        Spit.Publishing.PluginHost.ButtonMode button_mode) {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;

        set_button_mode(button_mode);

        dialog.install_pane(new StaticMessagePane(message));
    }
    
    public void install_pango_message_pane(string markup,
        Spit.Publishing.PluginHost.ButtonMode button_mode) {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;

        set_button_mode(button_mode);

        dialog.install_pane(new StaticMessagePane.with_pango(markup));
    }
    
    public void install_success_pane() {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;
        
        dialog.install_pane(new SuccessPane(get_publishable_media_type(), publishables.length));
        dialog.set_close_button_mode();

        // the success pane is a terminal pane; once it's installed, the publishing
        // interaction is considered over, so clean up
        clean_up();
    }
    
    public void install_account_fetch_wait_pane() {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;
        
        dialog.install_pane(new AccountFetchWaitPane());
        set_button_mode(Spit.Publishing.PluginHost.ButtonMode.CANCEL);
    }
    
    public void install_login_wait_pane() {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;
        
        dialog.install_pane(new LoginWaitPane());
    }
    
    public void install_welcome_pane(string welcome_message, LoginCallback login_clicked_callback) {
        LoginWelcomePane login_pane = new LoginWelcomePane(welcome_message);
        current_login_callback = login_clicked_callback;
        login_pane.login_requested.connect(on_login_clicked);

        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;

        set_button_mode(Spit.Publishing.PluginHost.ButtonMode.CLOSE);

        dialog.install_pane(login_pane);
    }
    
    public void set_service_locked(bool locked) {
        if (locked)
            dialog.lock_service();
        else
            dialog.unlock_service();
    }
    
    public void set_button_mode(Spit.Publishing.PluginHost.ButtonMode mode) {
        if (mode == Spit.Publishing.PluginHost.ButtonMode.CLOSE)
            dialog.set_close_button_mode();
        else if (mode == Spit.Publishing.PluginHost.ButtonMode.CANCEL)
            dialog.set_cancel_button_mode();
        else
            error("unrecognized button mode enumeration value");
    }

    public void set_dialog_default_widget(Gtk.Widget widget) {
        widget.can_default = true;
        dialog.set_default(widget);
    }
    
    public Spit.Publishing.Publisher.MediaType get_publishable_media_type() {
        return dialog.get_media_type();
    }

    public Publishable[] get_publishables() {
        return publishables;
    }
    
    public Spit.Publishing.ProgressCallback? serialize_publishables(int content_major_axis,
        bool strip_metadata = false) {
        install_progress_pane();
        ProgressPane progress_pane = (ProgressPane) dialog.get_active_pane();
        
        // spin the event loop right after installing the progress_pane so that the progress_pane
        // will appear and let the user know that something is going on while file serialization
        // takes place
        spin_event_loop();

        int i = 0;
        foreach (Spit.Publishing.Publishable publishable in publishables) {
            try {
                global::Publishing.Glue.MediaSourcePublishableWrapper wrapper =
                    (global::Publishing.Glue.MediaSourcePublishableWrapper) publishable;
                wrapper.serialize_for_publishing(content_major_axis, strip_metadata);
            } catch (Spit.Publishing.PublishingError err) {
                post_error(err);
                return null;
            }

            double phase_fraction_complete = ((double) (i + 1)) / ((double) publishables.length);
            double fraction_complete = phase_fraction_complete * STATUS_PREPARATION_FRACTION;
            
            debug("serialize_publishables( ): fraction_complete = %f.", fraction_complete);
            
            progress_pane.set_status(PREPARE_STATUS_DESCRIPTION, fraction_complete);
            
            spin_event_loop();

            i++;
        }
        
        return report_plugin_upload_progress;
    }
}

}

