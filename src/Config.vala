/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Config {
    GConf.Client client;
    protected static Config instance = null;
    public const double SLIDESHOW_DELAY_MAX = 30.0;
    public const double SLIDESHOW_DELAY_MIN = 1.0;
    public const double SLIDESHOW_DELAY_DEFAULT = 5.0;
    
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

    public bool clear_facebook_session_key() {
        return set_facebook_session_key("");
    }

    public bool set_facebook_session_key(string key) {
        try {
            client.set_string("/apps/shotwell/sharing/facebook/session_key", key);
            return true;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public string? get_facebook_session_key() {
        try {
            string stored_value = client.get_string("/apps/shotwell/sharing/facebook/session_key");
            return (stored_value != "") ? stored_value : null;
        } catch (GLib.Error err) {
            message("Unable to get GConf value.  Error message: %s", err.message);
            return null;
        }
    }

    public bool clear_facebook_session_secret() {
        return set_facebook_session_secret("");
    }

    public bool set_facebook_session_secret(string secret) {
        try {
            client.set_string("/apps/shotwell/sharing/facebook/session_secret", secret);
            return true;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public string? get_facebook_session_secret() {
        try {
            string stored_value =
                client.get_string("/apps/shotwell/sharing/facebook/session_secret");
            return (stored_value != "") ? stored_value : null;
        } catch (GLib.Error err) {
            message("Unable to get GConf value.  Error message: %s", err.message);
            return null;
        }
    }

    public bool clear_facebook_uid() {
        return set_facebook_uid("");
    }

    public bool set_facebook_uid(string uid) {
        try {
            client.set_string("/apps/shotwell/sharing/facebook/uid", uid);
            return true;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public string? get_facebook_uid() {
        try {
            string stored_value = client.get_string("/apps/shotwell/sharing/facebook/uid");
            return (stored_value != "") ? stored_value : null;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return null;
        }
    }

    public bool clear_facebook_user_name() {
        return set_facebook_user_name("");
    }

    public bool set_facebook_user_name(string user_name) {
        try {
            client.set_string("/apps/shotwell/sharing/facebook/user_name", user_name);
            return true;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public string? get_facebook_user_name() {
        try {
            string stored_value =
                client.get_string("/apps/shotwell/sharing/facebook/user_name");
            return (stored_value != "") ? stored_value : null;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return null;
        }
    }

    public bool set_display_basic_properties(bool display) {
        try {
            client.set_bool("/apps/shotwell/preferences/ui/display_basic_properties", display);
            return true;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public bool get_display_basic_properties() {
        try {
            return client.get_bool("/apps/shotwell/preferences/ui/display_basic_properties");
        } catch (GLib.Error err) {
            message("Unable to get GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public bool set_display_extended_properties(bool display) {
        try {
            client.set_bool("/apps/shotwell/preferences/ui/display_extended_properties", display);
            return true;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public bool get_display_extended_properties() {
        try {
            return client.get_bool("/apps/shotwell/preferences/ui/display_extended_properties");
        } catch (GLib.Error err) {
            message("Unable to get GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public bool set_display_photo_titles(bool display) {
        try {
            client.set_bool("/apps/shotwell/preferences/ui/display_photo_titles", display);
            return true;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public bool get_display_photo_titles() {
        try {
            return client.get_bool("/apps/shotwell/preferences/ui/display_photo_titles");
        } catch (GLib.Error err) {
            message("Unable to get GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public bool set_slideshow_delay(double delay) {
        try {
            client.set_float("/apps/shotwell/preferences/slideshow/delay", delay);
            return true;
        } catch (GLib.Error err) {
            message("Unable to set GConf value.  Error message: %s", err.message);
            return false;
        }
    }

    public double get_slideshow_delay() {
        double delay;
        try {
            delay = client.get_float("/apps/shotwell/preferences/slideshow/delay");

            if (delay == 0.0)
                delay = SLIDESHOW_DELAY_DEFAULT;
        } catch (GLib.Error err) {
            message("Unable to get GConf value.  Error message: %s", err.message);
            delay = SLIDESHOW_DELAY_DEFAULT;
        } 
        
        return delay.clamp(SLIDESHOW_DELAY_MIN, SLIDESHOW_DELAY_MAX);
    }
    
    public bool get_display_hidden_photos() {
        try {
            return client.get_bool("/apps/shotwell/preferences/ui/display_hidden_photos");
        } catch (Error err) {
            message("Unable to get GConf value: %s", err.message);
            
            return false;
        }
    }
    
    public bool set_display_hidden_photos(bool display) {
        try {
            client.set_bool("/apps/shotwell/preferences/ui/display_hidden_photos", display);
            
            return true;
        } catch (Error err) {
            message("Unable to set GConf value: %s", err.message);
            
            return false;
        }
    }
}

