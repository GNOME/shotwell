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
    
    public abstract string get_name();
    
    public abstract string get_user_name();
    
    public abstract MediaType get_supported_media();
    
    public abstract void start(PublishInteractor interactor);
    
    public abstract void cancelled();
}

public interface PublisherPane {
    public enum Size {
        NORMAL,
        EXTENDED
    }
    
    public abstract Gtk.Widget get_pane();
    
    public abstract Size get_pane_size();
    
    public abstract void on_pane_installed();
    
    public abstract void on_pane_uninstalled();
}

public delegate void ProgressCallback(double completed, double total);

public interface PublishInteractor {
    public abstract void install_pane(PublisherPane pane);
    
    public abstract void install_login_pane();
    
    public abstract void install_error_pane();
    
    public abstract ProgressCallback install_progress_pane();
    
    public abstract void create_rest_session(string endpoint, string? user_agent = null);
    
    public abstract void parse_xml_stream(DataInputStream ins);
    
    public abstract void parse_xml_string(string xml);
    
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
