/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public errordomain ConfigurationError {
    SCHEMA_NOT_AVAILABLE,
    KEY_NOT_WRITEABLE,
    KEY_NOT_AVAILABLE
}

private class GSettingsAdapter {
    public static string DESKTOP_BACKGROUND_SCHEMA_NAME = "org.gnome.desktop.background";
    public static string DESKTOP_BACKGROUND_URI_KEY_NAME = "picture-uri";
    public static string DESKTOP_BACKGROUND_MODE_KEY_NAME = "picture-options";

    private static GSettingsAdapter instance = null;

    private Gee.Set<string> available_schemas;
    
    private GSettingsAdapter() {
        this.available_schemas = new Gee.HashSet<string>();

        foreach (string current_schema in Settings.list_schemas())
            available_schemas.add(current_schema);
    }
    
    public static GSettingsAdapter get_instance() {
        if (instance == null)
            instance = new GSettingsAdapter();

        return instance;
    }
    
    public bool is_schema_available(string schema_name) {
        return available_schemas.contains(schema_name);
    }
    
    public bool does_schema_have_key(string schema, string key) throws ConfigurationError {
        if (!is_schema_available(schema))
            throw new ConfigurationError.SCHEMA_NOT_AVAILABLE("schema '%s' is not available".printf(
                schema));
        
        Settings settings = new Settings(schema);
        
        foreach(string current_key in settings.list_keys())
            if (current_key == key)
                return true;

        return false;
    }
    
    public void set_string(string schema, string key, string value) throws ConfigurationError {
        if (!is_schema_available(schema))
            throw new ConfigurationError.SCHEMA_NOT_AVAILABLE("schema '%s' is not available".printf(
                schema));

        Settings settings = new Settings(schema);
        

        bool success = settings.set_string(key, value);
        if (!success)
            throw new ConfigurationError.KEY_NOT_WRITEABLE("key '%s' is not writeable".printf(
                key));
    }
    
    public string get_string(string schema, string key) throws ConfigurationError {
        if (!does_schema_have_key(schema, key))
            throw new ConfigurationError.KEY_NOT_AVAILABLE(("key '%s' in schema '%s' is not " +
                "available").printf(key, schema));

        Settings settings = new Settings(schema);       

        return settings.get_string(key);
    }
}

private class GConfAdapter {
    public const string DESKTOP_BACKGROUND_DIRECTORY = "/desktop/gnome/background";
    public const string DESKTOP_BACKGROUND_FILE_PATH = "/desktop/gnome/background/picture_filename";
    public const string DESKTOP_BACKGROUND_MODE_PATH = "/desktop/gnome/background/picture_options";
}

public class Config {
    public const string PATH_SHOTWELL = "/apps/shotwell";
    public const string PATH_SHOTWELL_PREFS = PATH_SHOTWELL + "/preferences";
    
    public const string BOOL_COMMIT_METADATA_TO_MASTERS = PATH_SHOTWELL_PREFS + "/files/commit_metadata";
    public const string BOOL_AUTO_IMPORT_FROM_LIBRARY = PATH_SHOTWELL_PREFS + "/files/auto_import";
    public const string STRING_IMPORT_DIRECTORY = PATH_SHOTWELL_PREFS + "/files/import_dir";
    public const string STRING_BG_COLOR = PATH_SHOTWELL_PREFS + "/ui/background_color";
    public const string BOOL_SORT_EVENTS_ASCENDING = PATH_SHOTWELL_PREFS + "/ui/events_sort_ascending";
    
    public const double SLIDESHOW_DELAY_MAX = 30.0;
    public const double SLIDESHOW_DELAY_MIN = 1.0;
    public const double SLIDESHOW_DELAY_DEFAULT = 3.0;
    public const double SLIDESHOW_TRANSITION_DELAY_MAX = 1.0;
    public const double SLIDESHOW_TRANSITION_DELAY_MIN = 0.1;
    public const double SLIDESHOW_TRANSITION_DELAY_DEFAULT = 0.3;
    public const int WIDTH_DEFAULT = 1024;
    public const int HEIGHT_DEFAULT = 768;
    public const int SIDEBAR_MIN_POSITION = 180;
    public const int SIDEBAR_MAX_POSITION = 1000;
    public const string DEFAULT_BG_COLOR = "#444";
    public const int NO_VIDEO_INTERPRETER_STATE = -1;
    
    private const uint BLACK_THRESHOLD = 40000;
    private const string DARK_SELECTED_COLOR = "#0AD";
    private const string LIGHT_SELECTED_COLOR = "#2DF";
    private const string DARK_UNSELECTED_COLOR = "#000";
    private const string LIGHT_UNSELECTED_COLOR = "#FFF";
    private const string DARK_BORDER_COLOR = "#666";
    private const string LIGHT_BORDER_COLOR = "#AAA";
    private const string DARK_UNFOCUSED_SELECTED_COLOR = "#6fc4dd";
    private const string LIGHT_UNFOCUSED_SELECTED_COLOR = "#99efff";
    
    private string bg_color = null;
    private string selected_color = null;
    private string unselected_color = null;
    private string unfocused_selected_color = null;
    private string border_color = null;
    
    private static Config instance = null;
    
    private GConf.Client client;
    private GSettingsAdapter gsettings;
    private Gee.Map<string, bool> bool_defaults = new Gee.HashMap<string, bool>();
    
    public signal void colors_changed();
    
    public signal void external_app_changed();
    
    public signal void bool_changed(string path, bool value);
    
    public signal void string_changed(string path, string value);
    
    private Config() {
        client = GConf.Client.get_default();
        assert(client != null);

        gsettings = GSettingsAdapter.get_instance();
        
        // register values
        register_bool(BOOL_COMMIT_METADATA_TO_MASTERS, false);
        register_bool(BOOL_AUTO_IMPORT_FROM_LIBRARY, false);
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
    
    private bool unset(string path) {
        try {
            return client.unset(path);
        } catch (Error err) {
            report_get_error(path, err);
            return false;
        }
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
            
            bool_changed(path, value);
            
            return true;
        } catch (Error err) {
            report_set_error(path, err);
            
            return false;
        }
    }
    
    private bool is_registered_bool(string path) {
        return bool_defaults.has_key(path);
    }
    
    private bool get_registered_bool(string path) {
        assert(is_registered_bool(path));
        
        return get_bool(path, bool_defaults.get(path));
    }
    
    private void register_bool(string path, bool def) {
        bool_defaults.set(path, def);
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
            
            string_changed(path, value);
            
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

    public bool set_last_used_service(string service_name) {
        return set_string("/apps/shotwell/sharing/last_used_service", service_name);
    }

    public string get_last_used_service() {
        return get_string("/apps/shotwell/sharing/last_used_service");
    }

    public bool set_picasa_default_size(int default_size) {
        return set_int("/apps/shotwell/sharing/picasa/default_size", default_size + 1);
    }

    public int get_picasa_default_size() {
        return get_int("/apps/shotwell/sharing/picasa/default_size", 3) - 1;
    }
    
    public static string? clean_plugin_id(string id) {
        string cleaned = id.replace("/", "_");
        cleaned = cleaned.strip();
        
        return !is_string_empty(cleaned) ? cleaned : null;
    }
    
    private static string make_plugin_path(string domain, string id, string key) {
        string? cleaned_id = clean_plugin_id(id);
        if (cleaned_id == null)
            cleaned_id = "default";
        
        return "%s/%s/%s/%s".printf(PATH_SHOTWELL, domain, cleaned_id, key);
    }
    
    public bool get_plugin_bool(string domain, string id, string key, bool def) {
        return get_bool(make_plugin_path(domain, id, key), def);
    }
    
    public void set_plugin_bool(string domain, string id, string key, bool val) {
        set_bool(make_plugin_path(domain, id, key), val);
    }
    
    public int get_plugin_int(string domain, string id, string key, int def) {
        return get_int(make_plugin_path(domain, id, key), def);
    }
    
    public void set_plugin_int(string domain, string id, string key, int val) {
        set_int(make_plugin_path(domain, id, key), val);
    }
    
    public string? get_plugin_string(string domain, string id, string key, string? def) {
        return get_string(make_plugin_path(domain, id, key), def);
    }
    
    public void set_plugin_string(string domain, string id, string key, string? val) {
        set_string(make_plugin_path(domain, id, key), val);
    }
    
    public double get_plugin_double(string domain, string id, string key, double def) {
        return get_double(make_plugin_path(domain, id, key), def);
    }
    
    public void set_plugin_double(string domain, string id, string key, double val) {
        set_double(make_plugin_path(domain, id, key), val);
    }
    
    public void unset_plugin_key(string domain, string id, string key) {
        unset(make_plugin_path(domain, id, key));
    }
    
    public bool is_plugin_enabled(string id, bool def) {
        return get_bool("/apps/shotwell/plugins/%s/enabled".printf(clean_plugin_id(id)), def);
    }
    
    public void set_plugin_enabled(string id, bool enabled) {
        set_bool("/apps/shotwell/plugins/%s/enabled".printf(clean_plugin_id(id)), enabled);
    }
    
    public string? get_publishing_string(string domain, string key, string? default_value = null) {
        return get_string("/apps/shotwell/sharing/%s/%s".printf(domain, key), default_value);
    }

    public void set_publishing_string(string domain, string key, string value) {
        set_string("/apps/shotwell/sharing/%s/%s".printf(domain, key), value);
    }

    public int get_publishing_int(string domain, string key, int default_value = -1) {
        return get_int("/apps/shotwell/sharing/%s/%s".printf(domain, key), default_value);
    }

    public void set_publishing_int(string domain, string key, int value) {
        set_int("/apps/shotwell/sharing/%s/%s".printf(domain, key), value);
    }

    public bool get_publishing_bool(string domain, string key, bool default_value = false) {
        return get_bool("/apps/shotwell/sharing/%s/%s".printf(domain, key), default_value);
    }

    public void set_publishing_bool(string domain, string key, bool value) {
        set_bool("/apps/shotwell/sharing/%s/%s".printf(domain, key), value);
    }

    public double get_publishing_double(string domain, string key, double default_value = 0.0) {
        return get_double("/apps/shotwell/sharing/%s/%s".printf(domain, key), default_value);
    }

    public void set_publishing_double(string domain, string key, double value) {
        set_double("/apps/shotwell/sharing/%s/%s".printf(domain, key), value);
    }

    public void unset_publishing_string(string domain, string key) {
        string path = "/apps/shotwell/sharing/%s/%s".printf(domain, key);
        try {
            client.recursive_unset(path, GConf.UnsetFlags.NAMES);
        } catch (GLib.Error err) {
            warning("Unable to unset GConf value at %s: %s", path, err.message);
        }
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

    public bool set_image_per_page_selection(int image_per_page) {
        return set_int("/apps/shotwell/printing/image_per_page_selection", image_per_page + 1);
    }

    public int get_image_per_page_selection() {
        return get_int("/apps/shotwell/printing/image_per_page_selection", 1) - 1;
    }

    public bool set_printing_match_aspect_ratio(bool match_aspect_ratio) {
        return set_bool("/apps/shotwell/printing/match_aspect_ratio", match_aspect_ratio);
    }

    public bool get_printing_match_aspect_ratio() {
        return get_bool("/apps/shotwell/printing/match_aspect_ratio", true);
    }

    public bool set_printing_print_titles(bool print_titles) {
        return set_bool("/apps/shotwell/printing/print_titles", print_titles);
    }

    public bool get_printing_print_titles() {
        return get_bool("/apps/shotwell/printing/print_titles", true);
    }

    public bool set_printing_print_titles_font(string font_name) {
        return set_string("/apps/shotwell/printing/print_titles_font", font_name);
    }

    public string get_printing_print_titles_font() {
        return get_string("/apps/shotwell/printing/print_titles_font", "Sans Bold 12");
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

    public bool get_display_photo_ratings() {
        return get_bool("/apps/shotwell/preferences/ui/display_photo_ratings", true);
    }
    
    public bool set_display_photo_ratings(bool display) {
        return set_bool("/apps/shotwell/preferences/ui/display_photo_ratings", display);
    }
    
    public bool set_slideshow_delay(double delay) {
        return set_double("/apps/shotwell/preferences/slideshow/delay", delay);
    }

    public double get_slideshow_delay() {
        return get_double("/apps/shotwell/preferences/slideshow/delay", SLIDESHOW_DELAY_DEFAULT).clamp(
            SLIDESHOW_DELAY_MIN, SLIDESHOW_DELAY_MAX);
    }
    
    public bool set_slideshow_transition_delay(double delay) {
        return set_double("/apps/shotwell/preferences/slideshow_transition/delay", delay);
    }

    public double get_slideshow_transition_delay() {
        return get_double("/apps/shotwell/preferences/slideshow_transition/delay", SLIDESHOW_TRANSITION_DELAY_DEFAULT).clamp(
            SLIDESHOW_TRANSITION_DELAY_MIN, SLIDESHOW_TRANSITION_DELAY_MAX);
    }
    
    public bool set_slideshow_transition_effect_id(string id) {
        return set_string("/apps/shotwell/preferences/slideshow_transition/name", id);
    }
    
    public string get_slideshow_transition_effect_id() {
        return get_string("/apps/shotwell/preferences/slideshow_transition/name", TransitionEffectsManager.NULL_EFFECT_ID);
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
        return get_bool(BOOL_SORT_EVENTS_ASCENDING, false);
    }
    
    public bool set_events_sort_ascending(bool sort) {
        return set_bool(BOOL_SORT_EVENTS_ASCENDING, sort);
    }

    public void get_library_photos_sort(out bool sort_order, out int sort_by) {
        sort_order = get_bool("/apps/shotwell/preferences/ui/library_photos_sort_ascending", false);
        sort_by = get_int("/apps/shotwell/preferences/ui/library_photos_sort_by", MediaPage.SortBy.EXPOSURE_DATE);
        sort_by = sort_by.clamp(MediaPage.SortBy.MIN, MediaPage.SortBy.MAX);
    }
    
    public bool set_library_photos_sort(bool sort_order, int sort_by) {
        return set_bool("/apps/shotwell/preferences/ui/library_photos_sort_ascending", sort_order) &&
             set_int("/apps/shotwell/preferences/ui/library_photos_sort_by", sort_by);
    }

    public void get_event_photos_sort(out bool sort_order, out int sort_by) {
        sort_order = get_bool("/apps/shotwell/preferences/ui/event_photos_sort_ascending", true);
        sort_by = get_int("/apps/shotwell/preferences/ui/event_photos_sort_by", MediaPage.SortBy.EXPOSURE_DATE);
        sort_by = sort_by.clamp(MediaPage.SortBy.MIN, MediaPage.SortBy.MAX);
    }
    
    public bool set_event_photos_sort(bool sort_order, int sort_by) {
        return set_bool("/apps/shotwell/preferences/ui/event_photos_sort_ascending", sort_order) &&
             set_int("/apps/shotwell/preferences/ui/event_photos_sort_by", sort_by);
    }

    public bool get_24_hr_time() {
        return get_bool("/apps/shotwell/preferences/ui/twentyfour_hr_time",
            is_twentyfour_hr_time_system());
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

    public bool set_video_interpreter_state_cookie(int state_cookie) {
        return set_int("/apps/shotwell/video/interpreter_state_cookie", state_cookie);
    }

    public int get_video_interpreter_state_cookie() {
        return get_int("/apps/shotwell/video/interpreter_state_cookie", NO_VIDEO_INTERPRETER_STATE);
    }

    public string get_background() {
        string? from_gsettings = null;
        string? from_gconf = null;

        // get the background filename from GSettings if the schema and key we need are
        // available
        try {
            if (gsettings.does_schema_have_key(GSettingsAdapter.DESKTOP_BACKGROUND_SCHEMA_NAME,
                GSettingsAdapter.DESKTOP_BACKGROUND_URI_KEY_NAME)) {
                string background_uri = gsettings.get_string(
                    GSettingsAdapter.DESKTOP_BACKGROUND_SCHEMA_NAME,
                    GSettingsAdapter.DESKTOP_BACKGROUND_URI_KEY_NAME);

                // the key could exist but just have a null value, so check for this so we
                // don't segafault when we try to process the value
                if (background_uri != null) {
                    // GSettings gives us back a URI and what we need to return is a filename,
                    // so strip off the leading "file://" part of the URI to get a filename.
                    // This might seem brittle but let's face it: the file URI format is 
                    // going to be the same for a long, long time
                    from_gsettings = background_uri.substring(7, -1);
                }
            }
        } catch (ConfigurationError err) {
            // this is just a debug, not a warning because even if GSettings fails to get a
            // value, GConf might still succeed
            debug("couldn't get desktop background URI via GSettings: " + err.message + ".");
        }

        // get the background filename from GConf if the key exists -- this is easier because
        // GConf still deals in filenames (which is what Shotwell wants) instead of URIs
        from_gconf = get_string(GConfAdapter.DESKTOP_BACKGROUND_FILE_PATH, null);
        
        if (from_gsettings != null)
            debug("got desktop background filename '%s' from GSettings.", from_gsettings);
        if (from_gconf != null)
            debug("got desktop background filename '%s' from GConf.", from_gconf);
        
        // prefer GSettings since it's the way of the future
        return (from_gsettings != null) ? from_gsettings : from_gconf;
    }

    public bool set_background(string filename) {
        bool gconf_failed = false;
        bool gsettings_failed = false;
        
        // write into GSettings if the schema we need is available
        if (gsettings.is_schema_available(GSettingsAdapter.DESKTOP_BACKGROUND_SCHEMA_NAME)) {
            try {
                gsettings.set_string(GSettingsAdapter.DESKTOP_BACKGROUND_SCHEMA_NAME,
                    GSettingsAdapter.DESKTOP_BACKGROUND_URI_KEY_NAME, "file://" + filename);
                gsettings.set_string(GSettingsAdapter.DESKTOP_BACKGROUND_SCHEMA_NAME,
                    GSettingsAdapter.DESKTOP_BACKGROUND_MODE_KEY_NAME, "zoom");
            } catch (ConfigurationError err) {
                // this is a warning because the schema we want to use is available but we
                // can't write the key -- this shouldn't happen
                warning("couldn't set desktop background URI via GSettings: " + err.message + ".");
                gsettings_failed = true;
            }
        } else {
            debug("GSettings desktop background schema isn't available; will not write " +
                "configuration to GSettings.");
            gsettings_failed = true;
        }

        // write into GConf if the directory for the key exists
        try {
            if (client.dir_exists(GConfAdapter.DESKTOP_BACKGROUND_DIRECTORY)) {
                gconf_failed = !set_string(GConfAdapter.DESKTOP_BACKGROUND_FILE_PATH, filename);
                gconf_failed = gconf_failed && !set_string(GConfAdapter.DESKTOP_BACKGROUND_MODE_PATH,
                    "zoom");
                
                // this is a warning because the directory we want to use exists but we
                // can't write the key into it -- this shouldn't happen
                if (gconf_failed)
                    warning("couldn't set desktop background via GConf.");
            } else {
                debug("GConf desktop background directory doesn't exist; will not write " +
                    "configuration to GConf.");
                gconf_failed = true;
            }
        } catch (Error e) {
            gconf_failed = true;
            report_set_error(GConfAdapter.DESKTOP_BACKGROUND_DIRECTORY, e);
        }

        return gconf_failed && gsettings_failed;
    }
    
    public bool get_show_welcome_dialog() {
        return get_bool("/apps/shotwell/preferences/ui/show_welcome_dialog", true);
    }
    
    public bool set_show_welcome_dialog(bool show) {
        return set_bool("/apps/shotwell/preferences/ui/show_welcome_dialog", show);
    }

    public bool set_photo_thumbnail_scale(int scale) {
        return set_int("/apps/shotwell/preferences/ui/photo_thumbnail_scale", scale);
    }

    public int get_photo_thumbnail_scale() {
        return get_int("/apps/shotwell/preferences/ui/photo_thumbnail_scale",
            Thumbnail.DEFAULT_SCALE).clamp(
            Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
    }

    private void get_colors() {
        bg_color = get_string("/apps/shotwell/preferences/ui/background_color", DEFAULT_BG_COLOR);
        
        if (!is_color_parsable(bg_color))
            bg_color = DEFAULT_BG_COLOR;

        set_text_colors(parse_color(bg_color));
    }

    public Gdk.Color get_bg_color() {
        if (is_string_empty(bg_color))
            get_colors();

        return parse_color(bg_color);
    }

    public Gdk.Color get_selected_color(bool in_focus = true) {
        if (in_focus) {
            if (is_string_empty(selected_color))
                get_colors();

            return parse_color(selected_color);
        } else {
            if (is_string_empty(unfocused_selected_color))
                get_colors();

            return parse_color(unfocused_selected_color);
        }
    }
    
    public Gdk.Color get_unselected_color() {
        if (is_string_empty(unselected_color))
            get_colors();

        return parse_color(unselected_color);
    }

    public Gdk.Color get_border_color() {
        if (is_string_empty(border_color))
            get_colors();

        return parse_color(border_color);
    }

    private void set_text_colors(Gdk.Color bg_color) {
        // since bg color is greyscale, we only need to compare the red value to the threshold,
        // which determines whether the background is dark enough to need light text and selection
        // colors or vice versa
        if (bg_color.red > BLACK_THRESHOLD) {
            selected_color = DARK_SELECTED_COLOR;
            unselected_color = DARK_UNSELECTED_COLOR;
            unfocused_selected_color = DARK_UNFOCUSED_SELECTED_COLOR;
            border_color = DARK_BORDER_COLOR;
        } else {
            selected_color = LIGHT_SELECTED_COLOR;
            unselected_color = LIGHT_UNSELECTED_COLOR;
            unfocused_selected_color = LIGHT_UNFOCUSED_SELECTED_COLOR;
            border_color = LIGHT_BORDER_COLOR;
        }
    }
    
    public void set_bg_color(Gdk.Color color) {
        bg_color = color.to_string();

        set_text_colors(color);

        colors_changed();
    }
    
    public bool commit_bg_color() {
        return set_string(STRING_BG_COLOR, bg_color);
    }

    public string get_import_dir() {
        return get_string(STRING_IMPORT_DIRECTORY, null);
    }
    
    public void set_import_dir(string import_dir) {
        set_string(STRING_IMPORT_DIRECTORY, import_dir);
    }
    
    public string get_external_photo_app() {
        string external_app = get_string("/apps/shotwell/preferences/editing/external_photo_editor", "");
        
        if (!is_string_empty(external_app))
            return external_app;
        
        Gee.ArrayList<string> preferred_apps = new Gee.ArrayList<string>();
        preferred_apps.add("GIMP");
        
        AppInfo? app = DesktopIntegration.get_default_app_for_mime_types(
            PhotoFileFormat.get_editable_mime_types(), preferred_apps);
        
        return (app != null) ? DesktopIntegration.get_app_open_command(app) : "";
    }
    
    public void set_external_photo_app(string external_photo_app) {
        set_string("/apps/shotwell/preferences/editing/external_photo_editor",
            external_photo_app);
        external_app_changed();
    }

    public string get_external_raw_app() {
        string external_app = get_string("/apps/shotwell/preferences/editing/external_raw_editor", "");
        
        if (!is_string_empty(external_app))
            return external_app;
        
        Gee.ArrayList<string> preferred_apps = new Gee.ArrayList<string>();
        preferred_apps.add("UFRaw");
        
        AppInfo? app = DesktopIntegration.get_default_app_for_mime_types(
            PhotoFileFormat.RAW.get_mime_types(), preferred_apps);
        
        return (app != null) ? DesktopIntegration.get_app_open_command(app) : "";
    }

    public void set_external_raw_app(string external_raw_app) {
        set_string("/apps/shotwell/preferences/editing/external_raw_editor", external_raw_app);
        external_app_changed();
    }
    
    public bool get_auto_import_from_library() {
        return get_registered_bool(BOOL_AUTO_IMPORT_FROM_LIBRARY);
    }
    
    public void set_auto_import_from_library(bool auto_import) {
        set_bool(BOOL_AUTO_IMPORT_FROM_LIBRARY, auto_import);
    }
    
    public bool get_commit_metadata_to_masters() {
        return get_registered_bool(BOOL_COMMIT_METADATA_TO_MASTERS);
    }
    
    public void set_commit_metadata_to_masters(bool commit_metadata) {
        set_bool(BOOL_COMMIT_METADATA_TO_MASTERS, commit_metadata);
    }
    
    public string? get_directory_pattern() {
        return (get_string(PATH_SHOTWELL_PREFS + "/files/directory_pattern", null));
    }

    public bool set_directory_pattern(string s) {
        return set_string(PATH_SHOTWELL_PREFS + "/files/directory_pattern", s);
    }
    
    public bool unset_directory_pattern() {
        return unset(PATH_SHOTWELL_PREFS + "/files/directory_pattern");
    }
    
    public string get_directory_pattern_custom() {
        return (get_string(PATH_SHOTWELL_PREFS + "/files/directory_pattern_custom", ""));
    }

    public bool set_directory_pattern_custom(string s) {
        return set_string(PATH_SHOTWELL_PREFS + "/files/directory_pattern_custom", s);
    }
    
    public bool get_use_lowercase_filenames() {
        return get_bool(PATH_SHOTWELL_PREFS + "/files/user_lowercase_filenames", false);
    }
    
    public void set_use_lowercase_filenames(bool b) {
        set_bool(PATH_SHOTWELL_PREFS + "/files/user_lowercase_filenames", b);
    }
}
