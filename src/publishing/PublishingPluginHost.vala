/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Spit.Publishing {

public class PublishingHost : Spit.Publishing.PublishingInteractor, GLib.Object {
    private PublishingDialog dialog = null;
    private Spit.Publishing.PublishingDialogPane current_pane = null;
    private Spit.Publishing.Publisher active_publisher = null;
    private Publishable[] publishables = null;
    private LoginCallback current_login_callback = null;
    
    public PublishingHost(PublishingDialog dialog, Publishable[] publishables) {
        this.dialog = dialog;
        this.publishables = publishables;
    }
    
    private void on_login_clicked() {
        if (current_login_callback != null)
            current_login_callback();
    }
    
    public void set_active_publisher(Spit.Publishing.Publisher active_publisher) {
        this.active_publisher = active_publisher;
    }

    public void install_dialog_pane(Spit.Publishing.PublishingDialogPane pane) {
        debug("PublishingPluginHost: install_dialog_pane( ): invoked.");

        if (active_publisher == null || (!active_publisher.is_running()))
            return;

        if (current_pane != null)
            current_pane.on_pane_uninstalled();

        dialog.install_pane(pane.get_widget());
        
        Spit.Publishing.PublishingDialogPane.GeometryOptions geometry_options =
            pane.get_preferred_geometry();
        if ((geometry_options & PublishingDialogPane.GeometryOptions.EXTENDED_SIZE) != 0)
            dialog.set_large_window_mode();
        else
            dialog.set_standard_window_mode();

        if ((geometry_options & PublishingDialogPane.GeometryOptions.RESIZABLE) != 0)
            dialog.set_free_sizable_window_mode();
        else
            dialog.clear_free_sizable_window_mode();
        
        current_pane = pane;
        
        pane.on_pane_installed();
    }
	
    public void post_error(Error err) {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;

        string msg = _("Publishing to %s can't continue because an error occurred:").printf(
            active_publisher.get_user_visible_name());
        msg += GLib.Markup.printf_escaped("\n\n\t<i>%s</i>\n\n", err.message);
        msg += _("To try publishing to another service, select one from the above menu.");
        
        dialog.show_pango_error_message(msg);

        active_publisher.stop();
    }

    public void stop_publishing() {
        debug("PublishingHost.stop_publishing( ): invoked.");
        
        if (active_publisher.is_running())
            active_publisher.stop();

        active_publisher = null;
        dialog = null;
    }

    public void install_static_message_pane(string message) {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;

        dialog.install_pane(new StaticMessagePane(message));
    }
    
    public void install_pango_message_pane(string markup) {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;
        
        dialog.install_pane(new StaticMessagePane.with_pango(markup));
    }
    
    public void install_success_pane(Spit.Publishing.Publisher.MediaType media_type) {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;
        
        dialog.install_pane(new SuccessPane(media_type));
    }
    
    public void install_account_fetch_wait_pane() {
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;
        
        dialog.install_pane(new AccountFetchWaitPane());
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

        dialog.install_pane(login_pane);
    }
	
    public void set_service_locked(bool locked) {
        if (locked)
            dialog.lock_service();
        else
            dialog.unlock_service();
    }
    
    public void set_button_mode(Spit.Publishing.PublishingInteractor.ButtonMode mode) {
        if (mode == Spit.Publishing.PublishingInteractor.ButtonMode.CLOSE)
            dialog.set_close_button_mode();
        else if (mode == Spit.Publishing.PublishingInteractor.ButtonMode.CANCEL)
            dialog.set_cancel_button_mode();
        else
            error("unrecognized button mode enumeration value");
    }

    public void set_dialog_default_widget(Gtk.Widget widget) {
        widget.can_default = true;
        dialog.set_default(widget);
    }

    public ProgressCallback install_progress_pane() {
        ProgressPane progress_pane = new ProgressPane();
        
        if (current_pane != null)
            current_pane.on_pane_uninstalled();
        current_pane = null;
         
        dialog.install_pane(progress_pane);

        return progress_pane.set_status;
    }
    
    public Spit.Publishing.Publisher.MediaType get_publishable_media_type() {
        return dialog.get_media_type();
    }
    
    public int get_config_int(string key, int default_value) {
        return Config.get_instance().get_publishing_int(active_publisher.get_service_name(),
            key, default_value);
    }
    
    public string? get_config_string(string key, string? default_value) {
        return Config.get_instance().get_publishing_string(active_publisher.get_service_name(),
            key, default_value);
    }
    
    public bool get_config_bool(string key, bool default_value) {
        return Config.get_instance().get_publishing_bool(active_publisher.get_service_name(),
            key, default_value);
    }
    
    public double get_config_double(string key, double default_value) {
        return Config.get_instance().get_publishing_double(active_publisher.get_service_name(),
            key, default_value);
    }
    
    public void set_config_int(string key, int value) {
        Config.get_instance().set_publishing_int(active_publisher.get_service_name(), key, value);
    }
    
    public void set_config_string(string key, string value) {
        Config.get_instance().set_publishing_string(active_publisher.get_service_name(), key,
            value);
    }
    
    public void set_config_bool(string key, bool value) {
        Config.get_instance().set_publishing_bool(active_publisher.get_service_name(), key, value);
    }
    
    public void set_config_double(string key, double value) {
        Config.get_instance().set_publishing_double(active_publisher.get_service_name(), key,
            value);
    }
    
    public Publishable[] get_publishables() {
        return publishables;
    }
}

}

