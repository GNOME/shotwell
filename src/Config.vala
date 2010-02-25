/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Config {
    public const double SLIDESHOW_DELAY_MAX = 30.0;
    public const double SLIDESHOW_DELAY_MIN = 1.0;
    public const double SLIDESHOW_DELAY_DEFAULT = 5.0;
    public const int WIDTH_DEFAULT = 1024;
    public const int HEIGHT_DEFAULT = 768;
    public const int SIDEBAR_MIN_POSITION = 180;
    public const int SIDEBAR_MAX_POSITION = 1000;
    
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
            if (client.get(path) == null)
                return def;
            
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
    
    private int get_int(string path, int def) {
        try {
            if (client.get(path) == null)
                return def;
            
            int value = client.get_int(path);
            
            return (value != 0.0) ? value : def;
        } catch (GLib.Error err) {
            report_get_error(path, err);
            
            return def;
        } 
    }
    
    private bool set_int(string path, int value) {
        try {
            client.set_int(path, value);
            
            return true;
        } catch (GLib.Error err) {
            report_set_error(path, err);
            
            return false;
        }
    }
    
    private double get_double(string path, double def) {
        try {
            if (client.get(path) == null)
                return def;
            
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
            if (client.get(path) == null)
                return def;
            
            string stored = client.get_string(path);
            
            return is_string_empty(stored) ? null : stored;
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

    public bool clear_flickr_auth_token() {
        return set_flickr_auth_token("");
    }

    public bool set_flickr_auth_token(string token) {
    	return set_string("/apps/shotwell/sharing/flickr/auth_token", token);
    }

    public string? get_flickr_auth_token() {
            string stored_value = get_string("/apps/shotwell/sharing/flickr/auth_token");
            return (stored_value != "") ? stored_value : null;
    }

    public bool clear_flickr_username() {
        return set_flickr_username("");
    }

    public bool set_flickr_username(string username) {
		return set_string("/apps/shotwell/sharing/flickr/username", username);
    }

    public string? get_flickr_username() {
        string stored_value = get_string("/apps/shotwell/sharing/flickr/username");
        return (stored_value != "") ? stored_value : null;
    }

    public bool set_flickr_default_size(int sizecode) {
        return set_int("/apps/shotwell/sharing/flickr/default_size", sizecode + 1);
    }

    public int get_flickr_default_size() {
        return get_int("/apps/shotwell/sharing/flickr/default_size", 2) - 1;
    }

    public bool set_flickr_visibility(int viscode) {
        return set_int("/apps/shotwell/sharing/flickr/visibility", viscode + 1);
    }

    public int get_flickr_visibility() {
        return get_int("/apps/shotwell/sharing/flickr/visibility", 1) - 1;
    }

    public bool set_default_service(int service_code) {
        return set_int("/apps/shotwell/sharing/default_service", service_code + 1);
    }

    public int get_default_service() {
        return get_int("/apps/shotwell/sharing/default_service", 1) - 1;
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

    public bool set_picasa_user_name(string user_name) {
        return set_string("/apps/shotwell/sharing/picasa/user_name", user_name);
    }

    public string? get_picasa_user_name() {
        return get_string("/apps/shotwell/sharing/picasa/user_name");
    }

    public bool set_picasa_auth_token(string auth_token) {
        return set_string("/apps/shotwell/sharing/picasa/auth_token", auth_token);
    }

    public bool set_picasa_default_size(int default_size) {
        return set_int("/apps/shotwell/sharing/picasa/default_size", default_size + 1);
    }

    public int get_picasa_default_size() {
        return get_int("/apps/shotwell/sharing/picasa/default_size", 3) - 1;
    }

    public string? get_picasa_auth_token() {
        return get_string("/apps/shotwell/sharing/picasa/auth_token");
    }

    public bool set_printing_content_layout(int layout_code) {
        return set_int("/apps/shotwell/printing/content_layout", layout_code + 1);
    }

    public int get_printing_content_layout() {
        return get_int("/apps/shotwell/printing/content_layout", 1) - 1;
    }

    public bool set_printing_content_ppi(int content_ppi) {
        return set_int("/apps/shotwell/printing/content_ppi", content_ppi);
    }

    public int get_printing_content_ppi() {
        return get_int("/apps/shotwell/printing/content_ppi", 600);
    }

    public bool set_printing_content_width(double content_width) {
        return set_double("/apps/shotwell/printing/content_width", content_width);
    }

    public double get_printing_content_width() {
        return get_double("/apps/shotwell/printing/content_width", 7.0);
    }

    public bool set_printing_content_height(double content_height) {
        return set_double("/apps/shotwell/printing/content_height", content_height);
    }

    public double get_printing_content_height() {
        return get_double("/apps/shotwell/printing/content_height", 5.0);
    }

    public bool set_printing_content_units(int units_code) {
        return set_int("/apps/shotwell/printing/content_units", units_code + 1);
    }

    public int get_printing_content_units() {
        return get_int("/apps/shotwell/printing/content_units", 1) - 1;
    }

    public bool set_printing_size_selection(int size_code) {
        return set_int("/apps/shotwell/printing/size_selection", size_code + 1);
    }

    public int get_printing_size_selection() {
        return get_int("/apps/shotwell/printing/size_selection", 1) - 1;
    }

    public bool set_printing_match_aspect_ratio(bool match_aspect_ratio) {
        return set_bool("/apps/shotwell/printing/match_aspect_ratio", match_aspect_ratio);
    }

    public bool get_printing_match_aspect_ratio() {
        return get_bool("/apps/shotwell/printing/match_aspect_ratio", true);
    }

    public bool set_display_basic_properties(bool display) {
        return set_bool("/apps/shotwell/preferences/ui/display_basic_properties", display);
    }

    public bool get_display_basic_properties() {
        return get_bool("/apps/shotwell/preferences/ui/display_basic_properties", true);
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
    
    public bool get_display_photo_tags() {
        return get_bool("/apps/shotwell/preferences/ui/display_photo_tags", true);
    }
    
    public bool set_display_photo_tags(bool display) {
        return set_bool("/apps/shotwell/preferences/ui/display_photo_tags", display);
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

    public void get_library_window_state(out bool maximize, out Dimensions dimensions) {
        maximize = get_bool("/apps/shotwell/preferences/window/library_maximize", false);
        dimensions = Dimensions(get_int("/apps/shotwell/preferences/window/library_width", WIDTH_DEFAULT),
            get_int("/apps/shotwell/preferences/window/library_height", HEIGHT_DEFAULT));

    }

    public bool set_library_window_state(bool maximize, Dimensions dimensions) {
        return set_bool("/apps/shotwell/preferences/window/library_maximize", maximize)
            && set_int("/apps/shotwell/preferences/window/library_width", dimensions.width)
            && set_int("/apps/shotwell/preferences/window/library_height", dimensions.height);
    }

    public void get_direct_window_state(out bool maximize, out Dimensions dimensions) {
        maximize = get_bool("/apps/shotwell/preferences/window/direct_maximize", false);
        dimensions = Dimensions(get_int("/apps/shotwell/preferences/window/direct_width", WIDTH_DEFAULT),
            get_int("/apps/shotwell/preferences/window/direct_height", HEIGHT_DEFAULT));

    }

    public bool set_direct_window_state(bool maximize, Dimensions dimensions) {
        return set_bool("/apps/shotwell/preferences/window/direct_maximize", maximize)
            && set_int("/apps/shotwell/preferences/window/direct_width", dimensions.width)
            && set_int("/apps/shotwell/preferences/window/direct_height", dimensions.height);
    }

    public int get_sidebar_position() {
        return get_int("/apps/shotwell/preferences/window/pane_position", SIDEBAR_MIN_POSITION).clamp(SIDEBAR_MIN_POSITION, SIDEBAR_MAX_POSITION);
    }
    
    public bool set_sidebar_position(int position) {
        return set_int("/apps/shotwell/preferences/window/pane_position", position);
    }

    public bool get_events_sort_ascending() {
        return get_bool("/apps/shotwell/preferences/ui/events_sort_ascending", false);
    }
    
    public bool set_events_sort_ascending(bool sort) {
        return set_bool("/apps/shotwell/preferences/ui/events_sort_ascending", sort);
    }

    public void get_library_photos_sort(out bool sort_order, out int sort_by) {
        sort_order = get_bool("/apps/shotwell/preferences/ui/library_photos_sort_ascending", false);
        sort_by = get_int("/apps/shotwell/preferences/ui/library_photos_sort_by", CollectionPage.SortBy.EXPOSURE_DATE);
    }
    
    public bool set_library_photos_sort(bool sort_order, int sort_by) {
        return set_bool("/apps/shotwell/preferences/ui/library_photos_sort_ascending", sort_order) &&
             set_int("/apps/shotwell/preferences/ui/library_photos_sort_by", sort_by);
    }

    public void get_event_photos_sort(out bool sort_order, out int sort_by) {
        sort_order = get_bool("/apps/shotwell/preferences/ui/event_photos_sort_ascending", true);
        sort_by = get_int("/apps/shotwell/preferences/ui/event_photos_sort_by", CollectionPage.SortBy.EXPOSURE_DATE);
    }
    
    public bool set_event_photos_sort(bool sort_order, int sort_by) {
        return set_bool("/apps/shotwell/preferences/ui/event_photos_sort_ascending", sort_order) &&
             set_int("/apps/shotwell/preferences/ui/event_photos_sort_by", sort_by);
    }

    public bool get_24_hr_time() {
        return get_bool("/apps/shotwell/preferences/ui/twentyfour_hr_time", false);
    }
    
    public bool set_24_hr_time(bool twentyfour_hr_time) {
        return set_bool("/apps/shotwell/preferences/ui/twentyfour_hr_time", twentyfour_hr_time);
    }

    public bool get_keep_relativity() {
        return get_bool("/apps/shotwell/preferences/ui/keep_relativity", true);
    }
    
    public bool set_keep_relativity(bool keep_relativity) {
        return set_bool("/apps/shotwell/preferences/ui/keep_relativity", keep_relativity);
    }

    public bool get_modify_originals() {
        return get_bool("/apps/shotwell/preferences/ui/modify_originals", false);
    }
    
    public bool set_modify_originals(bool modify_originals) {
        return set_bool("/apps/shotwell/preferences/ui/modify_originals", modify_originals);
    }

    public string get_background() {
        return get_string("/desktop/gnome/background/picture_filename", null);
    }

    public bool set_background(string filename) {
        set_string("/desktop/gnome/background/picture_options", "zoom");
        return set_string("/desktop/gnome/background/picture_filename", filename);
    }
    
    public bool get_show_welcome_dialog() {
        return get_bool("/apps/shotwell/preferences/ui/show_welcome_dialog", true);
    }
    
    public bool set_show_welcome_dialog(bool show) {
        return set_bool("/apps/shotwell/preferences/ui/show_welcome_dialog", show);
    }
}

