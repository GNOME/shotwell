/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Config {
    GConf.Client client;
    protected static Config instance = null;
    public const double SLIDESHOW_DELAY_MAX = 30;
    public const double SLIDESHOW_DELAY_MIN = 1;
    public const double SLIDESHOW_DELAY_DEFAULT = 5;
    
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
        } catch (GLib.Error err) {
            message("Unable to get GConf value.  Error message: %s", err.message);
            delay = SLIDESHOW_DELAY_DEFAULT;
        } 
        
        return delay.clamp(SLIDESHOW_DELAY_MIN, SLIDESHOW_DELAY_MAX);
    }
    
}
