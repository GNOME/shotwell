/* Copyright 2016 Software Freedom Conservancy Inc.
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
    
    private weak PublishingUI.PublishingDialog dialog = null;
    private Spit.Publishing.Publisher active_publisher = null;
    private Publishable[] publishables = null;
    private unowned LoginCallback current_login_callback = null;
    private bool publishing_halted = false;
    private Spit.Publishing.Publisher.MediaType media_type =
        Spit.Publishing.Publisher.MediaType.NONE;
    
    public ConcretePublishingHost(Service service, PublishingUI.PublishingDialog dialog,
        Publishable[] publishables) {
        base(service, "sharing");
        this.dialog = dialog;
        this.publishables = publishables;
        
        foreach (Publishable curr_publishable in publishables)
            this.media_type |= curr_publishable.get_media_type();
        
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
        if (!(dialog.get_active_pane() is PublishingUI.ProgressPane))
            return;

        PublishingUI.ProgressPane pane = (PublishingUI.ProgressPane) dialog.get_active_pane();
        
        string status_string = UPLOAD_STATUS_DESCRIPTION.printf(file_number,
            publishables.length);
        double status_fraction = STATUS_PREPARATION_FRACTION + (STATUS_UPLOAD_FRACTION *
            fraction_complete);
        
        pane.set_status(status_string, status_fraction);
    }

    private void install_progress_pane() {
        PublishingUI.ProgressPane progress_pane = new PublishingUI.ProgressPane();
        
        dialog.install_pane(progress_pane);
        set_button_mode(Spit.Publishing.PluginHost.ButtonMode.CANCEL);
    }

    public void install_dialog_pane(Spit.Publishing.DialogPane pane,
        Spit.Publishing.PluginHost.ButtonMode button_mode) {
        debug("Publishing.PluginHost: install_dialog_pane( ): invoked.");

        if (active_publisher == null || (!active_publisher.is_running()))
            return;

        dialog.install_pane(pane);
        
        set_button_mode(button_mode);
    }
    
    public void post_error(Error err) {
        string msg = _("Publishing to %s can’t continue because an error occurred:").printf(
            active_publisher.get_service().get_pluggable_name());
        msg += GLib.Markup.printf_escaped("\n\n<i>%s</i>\n\n", err.message);
        msg += _("To try publishing to another service, select one from the above menu.");
        
        dialog.install_pane(new PublishingUI.StaticMessagePane(msg, true));
        dialog.set_close_button_mode();
        dialog.unlock_service();

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

        publishing_halted = true;
    }
    
    public void start_publishing() {
        if (active_publisher.is_running())
            return;

        debug("ConcretePublishingHost.start_publishing( ): invoked.");
        
        active_publisher.start();
    }

    public Publisher get_publisher() {
        return active_publisher;
    }

    public void install_static_message_pane(string message,
        Spit.Publishing.PluginHost.ButtonMode button_mode) {

        set_button_mode(button_mode);

        dialog.install_pane(new PublishingUI.StaticMessagePane(message));
    }
    
    public void install_pango_message_pane(string markup,
        Spit.Publishing.PluginHost.ButtonMode button_mode) {
        set_button_mode(button_mode);

        dialog.install_pane(new PublishingUI.StaticMessagePane(markup, true));
    }
    
    public void install_success_pane() {
        dialog.install_pane(new PublishingUI.SuccessPane(get_publishable_media_type(),
            publishables.length));
        dialog.set_close_button_mode();

        // the success pane is a terminal pane; once it's installed, the publishing
        // interaction is considered over, so clean up
        clean_up();
    }
    
    public void install_account_fetch_wait_pane() {
        dialog.install_pane(new PublishingUI.AccountFetchWaitPane());
        set_button_mode(Spit.Publishing.PluginHost.ButtonMode.CANCEL);
    }
    
    public void install_login_wait_pane() {
        dialog.install_pane(new PublishingUI.LoginWaitPane());
    }
    
    public void install_welcome_pane(string welcome_message, LoginCallback login_clicked_callback) {
        PublishingUI.LoginWelcomePane login_pane =
            new PublishingUI.LoginWelcomePane(welcome_message);
        current_login_callback = login_clicked_callback;
        login_pane.login_requested.connect(on_login_clicked);

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
        return media_type;
    }

    public Publishable[] get_publishables() {
        return publishables;
    }
    
    public Spit.Publishing.ProgressCallback? serialize_publishables(int content_major_axis,
        bool strip_metadata = false) {
        install_progress_pane();
        PublishingUI.ProgressPane progress_pane =
            (PublishingUI.ProgressPane) dialog.get_active_pane();

        // spin the event loop right after installing the progress_pane so that the progress_pane
        // will appear and let the user know that something is going on while file serialization
        // takes place
        spin_event_loop();

        int i = 0;
        foreach (Spit.Publishing.Publishable publishable in publishables) {
            if (publishing_halted || !active_publisher.is_running())
                return null;

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

