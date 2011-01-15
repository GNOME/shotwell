/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Using Shotwell.Plugins namespace (rather than Plugins) for the benefit of external plugins
// and C code (so the interfaces will be seen as shotwell_plugins_publisher_get_name, etc.)
namespace Shotwell.Plugins {

public interface Publisher {
    public enum MediaType {
        NONE =          0,
        PHOTO =         1 << 0,
        VIDEO =         1 << 1
    }
    
    public abstract string get_service_name();
    
    public abstract string get_user_visible_name();
    
    public abstract MediaType get_supported_media();
    
    public abstract void start(PublishingInteractor interactor);
    
    /* plugins must relinquish their interactor reference when stop( ) is called */
    public abstract void stop();
}

public interface PublishingDialogPane {
    public enum GeometryOptions {
        NONE =          0,
        EXTENDED_SIZE = 1 << 0,
        RESIZABLE =     1 << 1;
    }
    
    public abstract Gtk.Widget get_widget();
    
	/* the publishing dialog may give you what you want; then again, it may not ;-) */
    public abstract GeometryOptions get_preferred_geometry();
    
    public abstract void on_pane_installed();
    
    public abstract void on_pane_uninstalled();
}

/* completed fraction is between 0.0 and 1.0 inclusive; status text is displayed as text on the
   progress bar */
public delegate void ProgressCallback(string status_text, double completed_fraction);

public delegate void LoginCallback();

public interface PublishingInteractor {
    public enum ButtonMode {
        CLOSE,
        CANCEL
    }

    public abstract void install_dialog_pane(PublishingDialogPane pane); 
	
    public abstract void post_error(Error err);
    
    public abstract void install_static_message_pane(string message);
    
    public abstract void install_pango_message_pane(string markup);
    
    public abstract void install_success_pane();
    
    public abstract void install_account_fetch_wait_pane();
    
    public abstract void install_login_wait_pane();
    
    public abstract LoginCallback install_login_pane(string welcome_message);
	
    public abstract void set_service_locked(bool locked);
    
    public abstract void set_button_mode(ButtonMode mode);
    
    public abstract ProgressCallback install_progress_pane();
    
    public abstract int get_config_int(string key, int default_value);
    
    public abstract string? get_config_string(string key, string? default_value);
    
    public abstract bool get_config_bool(string key, bool default_value);
    
    public abstract double get_config_double(string key, double default_value);
    
    public abstract void set_config_int(string key, int value);
    
    public abstract void set_config_string(string key, string value);
    
    public abstract void set_config_bool(string key, bool value);
    
    public abstract void set_config_double(string key, double value);
}

}
