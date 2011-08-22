/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// This configuration engine uses GSettings for everything. But it also uses
// GConf for the desktop wallpaper settings in addition to GSettings. This is to
// make Ubuntu work as expected.
public class HybridConfigurationEngine : ConfigurationEngine, GLib.Object {
    private GConfConfigurationEngine gconf = new GConfConfigurationEngine();
    private GSettingsConfigurationEngine gsettings = new GSettingsConfigurationEngine();
    
    public HybridConfigurationEngine() {
        gconf.property_changed.connect(on_property_changed);
        gsettings.property_changed.connect(on_property_changed);
    }
    
    ~HybridConfigurationEngine() {
        gconf.property_changed.disconnect(on_property_changed);
        gsettings.property_changed.disconnect(on_property_changed);
    }
    
    public string get_name() {
        return "Hybrid";
    }

    public int get_int_property(ConfigurableProperty p) throws ConfigurationError {
        return gsettings.get_int_property(p);
    }
    
    public void set_int_property(ConfigurableProperty p, int val) throws ConfigurationError {
        gsettings.set_int_property(p, val);
    }
    
    public string get_string_property(ConfigurableProperty p) throws ConfigurationError {
        return gsettings.get_string_property(p);
    }
    
    public void set_string_property(ConfigurableProperty p, string val) throws ConfigurationError {
        gsettings.set_string_property(p, val);
        if (p == ConfigurableProperty.DESKTOP_BACKGROUND_FILE ||
            p == ConfigurableProperty.DESKTOP_BACKGROUND_MODE)
            gconf.set_string_property(p, val);
    }
    
    public bool get_bool_property(ConfigurableProperty p) throws ConfigurationError {
        return gsettings.get_bool_property(p);
    }
    
    public void set_bool_property(ConfigurableProperty p, bool val) throws ConfigurationError {
        gsettings.set_bool_property(p, val);
    }
    
    public double get_double_property(ConfigurableProperty p) throws ConfigurationError {
        return gsettings.get_double_property(p);
    }
    
    public void set_double_property(ConfigurableProperty p, double val) throws ConfigurationError {
        gsettings.set_double_property(p, val);
    }
    
    public bool get_plugin_bool(string domain, string id, string key, bool def) {
        return gsettings.get_plugin_bool(domain, id, key, def);
    }
    
    public void set_plugin_bool(string domain, string id, string key, bool val) {
        gsettings.set_plugin_bool(domain, id, key, val);
    }
    
    public double get_plugin_double(string domain, string id, string key, double def) {
        return gsettings.get_plugin_double(domain, id, key, def);
    }
    
    public void set_plugin_double(string domain, string id, string key, double val) {
        gsettings.set_plugin_double(domain, id, key, val);
    }
    
    public int get_plugin_int(string domain, string id, string key, int def) {
        return gsettings.get_plugin_int(domain, id, key, def);
    }
    
    public void set_plugin_int(string domain, string id, string key, int val) {
        gsettings.set_plugin_int(domain, id, key, val);
    }
    
    public string? get_plugin_string(string domain, string id, string key, string? def) {
        return gsettings.get_plugin_string(domain, id, key, def);
    }
    
    public void set_plugin_string(string domain, string id, string key, string? val) {
        gsettings.set_plugin_string(domain, id, key, val);
    }
    
    public void unset_plugin_key(string domain, string id, string key) {
        gsettings.unset_plugin_key(domain, id, key);
    }
    
    public FuzzyPropertyState is_plugin_enabled(string id) {
        return gsettings.is_plugin_enabled(id);
    }

    public void set_plugin_enabled(string id, bool enabled) {
        gsettings.set_plugin_enabled(id, enabled);
    }
    
    private void on_property_changed(ConfigurableProperty p) {
        property_changed(p);
    }
}

