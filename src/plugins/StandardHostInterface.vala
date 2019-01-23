/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Plugins {

public class StandardHostInterface : Object, Spit.HostInterface {
    private string config_domain;
    private string config_id;
    private File module_file;
    private Spit.PluggableInfo info;
    
    public StandardHostInterface(Spit.Pluggable pluggable, string config_domain) {
        this.config_domain = config_domain;
        config_id = parse_key(pluggable.get_id());
        module_file = get_pluggable_module_file(pluggable);
        pluggable.get_info(ref info);
    }
    
    private static string parse_key(string id) {
        // special case: legacy plugins (Web publishers moved into SPIT) have special names
        // new plugins will use their full ID
        switch (id) {
            case "org.yorba.shotwell.publishing.facebook":
                return "facebook";
            
            case "org.yorba.shotwell.publishing.flickr":
                return "flickr";
                
            case "org.yorba.shotwell.publishing.youtube":
                return "youtube";

            default:
                return id;
        }
    }
    
    public File get_module_file() {
        return module_file;
    }
    
    public bool get_config_bool(string key, bool def) {
        return Config.Facade.get_instance().get_plugin_bool(config_domain, config_id, key, def);
    }
    
    public void set_config_bool(string key, bool val) {
        Config.Facade.get_instance().set_plugin_bool(config_domain, config_id, key, val);
    }
    
    public int get_config_int(string key, int def) {
        return Config.Facade.get_instance().get_plugin_int(config_domain, config_id, key, def);
    }
    
    public void set_config_int(string key, int val) {
        Config.Facade.get_instance().set_plugin_int(config_domain, config_id, key, val);
    }
    
    public string? get_config_string(string key, string? def) {
        return Config.Facade.get_instance().get_plugin_string(config_domain, config_id, key, def);
    }
    
    public void set_config_string(string key, string? val) {
        Config.Facade.get_instance().set_plugin_string(config_domain, config_id, key, val);
    }
    
    public double get_config_double(string key, double def) {
        return Config.Facade.get_instance().get_plugin_double(config_domain, config_id, key, def);
    }
    
    public void set_config_double(string key, double val) {
        Config.Facade.get_instance().set_plugin_double(config_domain, config_id, key, val);
    }
    
    public void unset_config_key(string key) {
        Config.Facade.get_instance().unset_plugin_key(config_domain, config_id, key);
    }
}

}
