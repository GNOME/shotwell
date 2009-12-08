/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Config {
    public const double SLIDESHOW_DELAY_MAX = 30.0;
    public const double SLIDESHOW_DELAY_MIN = 1.0;
    public const double SLIDESHOW_DELAY_DEFAULT = 5.0;
    
    private static Config instance = null;
    
    private GConf.Client client;
    
    private Config() {
        // only one may exist per-process
        assert(instance == null);

        client = GConf.Client.get_default();
        assert(client != null);
    }

    public static Config get_instance() {
        if (instance == null)
            instance = new Config();
        
        return instance;
    }
    
    private void report_get_error(string path, Error err) {
        warning("Unable to get GConf value at %s: %s", path, err.message);
    }
    
    private void report_set_error(string path, Error err) {
        warning("Unable to set GConf value at %s: %s", path, err.message);
    }
    
    private bool get_bool(string path, bool def) {
        try {
            return client.get_bool(path);
        } catch (Error err) {
            report_get_error(path, err);
            
            return def;
        }
    }
    
    private bool set_bool(string path, bool value) {
        try {
            client.set_bool(path, value);
            
            return true;
        } catch (Error err) {
            report_set_error(path, err);
            
            return false;
        }
    }
    
    private double get_double(string path, double def) {
        try {
            double value = client.get_float(path);
            
            return (value != 0.0) ? value : def;
        } catch (GLib.Error err) {
            report_get_error(path, err);
            
            return def;
        } 
    }
    
    private bool set_double(string path, double value) {
        try {
            client.set_float(path, value);
            
            return true;
        } catch (GLib.Error err) {
            report_set_error(path, err);
            
            return false;
        }
    }
    
    private string? get_string(string path, string? def = null) {
        try {
            string stored = client.get_string(path);
            
            return (stored == null || stored.length == 0) ? null : stored;
        } catch (Error err) {
            report_get_error(path, err);
            
            return def;
        }
    }

    private bool set_string(string path, string value) {
        try {
            client.set_string(path, value);
            
            return true;
        } catch (Error err) {
            report_set_error(path, err);
            
            return false;
        }
    }
    
    public bool clear_facebook_session_key() {
        return set_facebook_session_key("");
    }

    public bool set_facebook_session_key(string key) {
        return set_string("/apps/shotwell/sharing/facebook/session_key", key);
    }

    public string? get_facebook_session_key() {
        return get_string("/apps/shotwell/sharing/facebook/session_key");
    }

    public bool clear_facebook_session_secret() {
        return set_facebook_session_secret("");
    }

    public bool set_facebook_session_secret(string secret) {
        return set_string("/apps/shotwell/sharing/facebook/session_secret", secret);
    }

    public string? get_facebook_session_secret() {
        return get_string("/apps/shotwell/sharing/facebook/session_secret");
    }

    public bool clear_facebook_uid() {
        return set_facebook_uid("");
    }

    public bool set_facebook_uid(string uid) {
        return set_string("/apps/shotwell/sharing/facebook/uid", uid);
    }

    public string? get_facebook_uid() {
        return get_string("/apps/shotwell/sharing/facebook/uid");
    }

    public bool clear_facebook_user_name() {
        return set_facebook_user_name("");
    }

    public bool set_facebook_user_name(string user_name) {
        return set_string("/apps/shotwell/sharing/facebook/user_name", user_name);
    }

    public string? get_facebook_user_name() {
        return get_string("/apps/shotwell/sharing/facebook/user_name");
    }

    public bool set_display_basic_properties(bool display) {
        return set_bool("/apps/shotwell/preferences/ui/display_basic_properties", display);
    }

    public bool get_display_basic_properties() {
        return get_bool("/apps/shotwell/preferences/ui/display_basic_properties", false);
    }

    public bool set_display_extended_properties(bool display) {
        return set_bool("/apps/shotwell/preferences/ui/display_extended_properties", display);
    }

    public bool get_display_extended_properties() {
        return get_bool("/apps/shotwell/preferences/ui/display_extended_properties", false);
    }

    public bool set_display_photo_titles(bool display) {
        return set_bool("/apps/shotwell/preferences/ui/display_photo_titles", display);
    }

    public bool get_display_photo_titles() {
        return get_bool("/apps/shotwell/preferences/ui/display_photo_titles", false);
    }

    public bool set_slideshow_delay(double delay) {
        return set_double("/apps/shotwell/preferences/slideshow/delay", delay);
    }

    public double get_slideshow_delay() {
        return get_double("/apps/shotwell/preferences/slideshow/delay", SLIDESHOW_DELAY_DEFAULT).clamp(
            SLIDESHOW_DELAY_MIN, SLIDESHOW_DELAY_MAX);
    }
    
    public bool get_display_favorite_photos() {
        return get_bool("/apps/shotwell/preferences/ui/display_favorite_photos", false);
    }
    
    public bool set_display_favorite_photos(bool display) {
        return set_bool("/apps/shotwell/preferences/ui/display_favorite_photos", display);
    }
    
    public bool get_display_hidden_photos() {
        return get_bool("/apps/shotwell/preferences/ui/display_hidden_photos", false);
    }
    
    public bool set_display_hidden_photos(bool display) {
        return set_bool("/apps/shotwell/preferences/ui/display_hidden_photos", display);
    }
}

