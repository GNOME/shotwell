/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if USE_LEGACY_CONFIG_SYSTEM

public class GConfConfigurationEngine : ConfigurationEngine, GLib.Object {
    private const string PATH_SHOTWELL = "/apps/shotwell";
    private const string PATH_SHOTWELL_PREFS = PATH_SHOTWELL + "/preferences";
    
    private string[] property_paths;
    private GConf.Client client;
    
    public GConfConfigurationEngine() {
        client = GConf.Client.get_default();

        property_paths = new string[ConfigurableProperty.NUM_PROPERTIES];

        property_paths[ConfigurableProperty.AUTO_IMPORT_FROM_LIBRARY] =
            PATH_SHOTWELL_PREFS + "/files/auto_import";

        property_paths[ConfigurableProperty.BG_COLOR_NAME] =
            "/apps/shotwell/preferences/ui/background_color";

        property_paths[ConfigurableProperty.COMMIT_METADATA_TO_MASTERS] =
            PATH_SHOTWELL_PREFS + "/files/commit_metadata";

        property_paths[ConfigurableProperty.DESKTOP_BACKGROUND_FILE] =
            "/desktop/gnome/background/picture_filename";

        property_paths[ConfigurableProperty.DESKTOP_BACKGROUND_MODE] =
            "/desktop/gnome/background/picture_options";

        property_paths[ConfigurableProperty.DIRECTORY_PATTERN] =
            PATH_SHOTWELL_PREFS + "/files/directory_pattern";

        property_paths[ConfigurableProperty.DIRECTORY_PATTERN_CUSTOM] =
            PATH_SHOTWELL_PREFS + "/files/directory_pattern_custom";

        property_paths[ConfigurableProperty.DIRECT_WINDOW_HEIGHT] =
            PATH_SHOTWELL_PREFS + "/window/direct_height";

        property_paths[ConfigurableProperty.DIRECT_WINDOW_MAXIMIZE] =
            PATH_SHOTWELL_PREFS + "/window/direct_maximize";

        property_paths[ConfigurableProperty.DIRECT_WINDOW_WIDTH] =
            PATH_SHOTWELL_PREFS + "/window/direct_width";

        property_paths[ConfigurableProperty.DISPLAY_BASIC_PROPERTIES] =
            PATH_SHOTWELL_PREFS + "/ui/display_basic_properties";

        property_paths[ConfigurableProperty.DISPLAY_EXTENDED_PROPERTIES] =
            PATH_SHOTWELL_PREFS + "/ui/display_extended_properties";

        property_paths[ConfigurableProperty.DISPLAY_PHOTO_RATINGS] =
            PATH_SHOTWELL_PREFS + "/ui/display_photo_ratings";

        property_paths[ConfigurableProperty.DISPLAY_PHOTO_TAGS] =
            PATH_SHOTWELL_PREFS + "/ui/display_photo_tags";
            
        property_paths[ConfigurableProperty.DISPLAY_PHOTO_TITLES] =
            PATH_SHOTWELL_PREFS + "/ui/display_photo_titles";

        property_paths[ConfigurableProperty.EVENT_PHOTOS_SORT_ASCENDING] =
            PATH_SHOTWELL_PREFS + "/ui/event_photos_sort_ascending";

        property_paths[ConfigurableProperty.EVENT_PHOTOS_SORT_BY] =
            PATH_SHOTWELL_PREFS + "/ui/event_photos_sort_by";

        property_paths[ConfigurableProperty.EVENTS_SORT_ASCENDING] =
            PATH_SHOTWELL_PREFS + "/ui/events_sort_ascending";

        property_paths[ConfigurableProperty.EXTERNAL_PHOTO_APP] =
            PATH_SHOTWELL_PREFS + "/editing/external_photo_editor";

        property_paths[ConfigurableProperty.EXTERNAL_RAW_APP] =
            PATH_SHOTWELL_PREFS + "/editing/external_raw_editor";

        property_paths[ConfigurableProperty.IMPORT_DIR] =
            PATH_SHOTWELL_PREFS + "/files/import_dir";

        property_paths[ConfigurableProperty.KEEP_RELATIVITY] =
            PATH_SHOTWELL_PREFS + "/ui/keep_relativity";

        property_paths[ConfigurableProperty.LAST_USED_SERVICE] =
            "/apps/shotwell/sharing/last_used_service";

        property_paths[ConfigurableProperty.LIBRARY_PHOTOS_SORT_ASCENDING] =
            PATH_SHOTWELL_PREFS + "/ui/library_photos_sort_ascending";

        property_paths[ConfigurableProperty.LIBRARY_PHOTOS_SORT_BY] =
            PATH_SHOTWELL_PREFS + "/ui/library_photos_sort_by";

        property_paths[ConfigurableProperty.LIBRARY_WINDOW_HEIGHT] =
            PATH_SHOTWELL_PREFS + "/window/library_height";

        property_paths[ConfigurableProperty.LIBRARY_WINDOW_MAXIMIZE] =
            PATH_SHOTWELL_PREFS + "/window/library_maximize";

        property_paths[ConfigurableProperty.LIBRARY_WINDOW_WIDTH] =
            PATH_SHOTWELL_PREFS + "/window/library_width";

        property_paths[ConfigurableProperty.MODIFY_ORIGINALS] =
            PATH_SHOTWELL_PREFS + "/ui/modify_originals";

        property_paths[ConfigurableProperty.PHOTO_THUMBNAIL_SCALE] =
            PATH_SHOTWELL_PREFS + "/ui/photo_thumbnail_scale";

        property_paths[ConfigurableProperty.PRINTING_CONTENT_HEIGHT] =
            "/apps/shotwell/printing/content_height";

        property_paths[ConfigurableProperty.PRINTING_CONTENT_LAYOUT] =
            "/apps/shotwell/printing/content_layout";

        property_paths[ConfigurableProperty.PRINTING_CONTENT_PPI] =
            "/apps/shotwell/printing/content_ppi";

        property_paths[ConfigurableProperty.PRINTING_CONTENT_UNITS] =
            "/apps/shotwell/printing/content_units";

        property_paths[ConfigurableProperty.PRINTING_CONTENT_WIDTH] =
            "/apps/shotwell/printing/content_width";

        property_paths[ConfigurableProperty.PRINTING_IMAGES_PER_PAGE] =
            "/apps/shotwell/printing/image_per_page_selection";

        property_paths[ConfigurableProperty.PRINTING_MATCH_ASPECT_RATIO] =
            "/apps/shotwell/printing/match_aspect_ratio";

        property_paths[ConfigurableProperty.PRINTING_PRINT_TITLES] =
            "/apps/shotwell/printing/print_titles";

        property_paths[ConfigurableProperty.PRINTING_SIZE_SELECTION] =
            "/apps/shotwell/printing/size_selection";

        property_paths[ConfigurableProperty.PRINTING_TITLES_FONT] =
            "/apps/shotwell/printing/print_titles_font";

        property_paths[ConfigurableProperty.RAW_DEVELOPER_DEFAULT] =
            PATH_SHOTWELL_PREFS + "/files/raw_developer_default";

        property_paths[ConfigurableProperty.SHOW_WELCOME_DIALOG] =
            PATH_SHOTWELL_PREFS + "/ui/show_welcome_dialog";

        property_paths[ConfigurableProperty.SIDEBAR_POSITION] =
            PATH_SHOTWELL_PREFS + "/window/pane_position";

        property_paths[ConfigurableProperty.SLIDESHOW_DELAY] =
            PATH_SHOTWELL_PREFS + "/slideshow/delay";

        property_paths[ConfigurableProperty.SLIDESHOW_TRANSITION_DELAY] =
            PATH_SHOTWELL_PREFS + "/slideshow_transition/delay";

        property_paths[ConfigurableProperty.SLIDESHOW_TRANSITION_EFFECT_ID] =
            PATH_SHOTWELL_PREFS + "/slideshow_transition/name";

        property_paths[ConfigurableProperty.USE_24_HOUR_TIME] =
            PATH_SHOTWELL_PREFS + "/ui/twentyfour_hr_time";

        property_paths[ConfigurableProperty.USE_LOWERCASE_FILENAMES] =
            PATH_SHOTWELL_PREFS + "/files/user_lowercase_filenames";

        property_paths[ConfigurableProperty.VIDEO_INTERPRETER_STATE_COOKIE] =
            "/apps/shotwell/video/interpreter_state_cookie";
    }

    private static string? clean_plugin_id(string id) {
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

    private bool get_gconf_bool(string path) throws ConfigurationError {
        GConf.Value? val = null;
        try {
            val = client.get(path);
        } catch (Error err) {
            throw new ConfigurationError.ENGINE_ERROR(err.message);
        }
        if (val == null)
            throw new ConfigurationError.PROPERTY_HAS_NO_VALUE(("GConfConfigurationManager: " +
                "path = '%s'.").printf(path));
        
        return val.get_bool();
    }
    
    private void set_gconf_bool(string path, bool value) throws ConfigurationError {
        try {
            client.set_bool(path, value);
        } catch (Error err) {
            throw new ConfigurationError.ENGINE_ERROR(err.message);
        }
    }
    
    private int get_gconf_int(string path) throws ConfigurationError {
        GConf.Value? val = null;
        try {
            val = client.get(path);
        } catch (GLib.Error err) {
            throw new ConfigurationError.ENGINE_ERROR(err.message);
        }
        if (val == null)
            throw new ConfigurationError.PROPERTY_HAS_NO_VALUE(("GConfConfigurationManager: " +
                "path = '%s'.").printf(path));
        
        return val.get_int();
    }
    
    private void set_gconf_int(string path, int value) throws ConfigurationError {
        try {
            client.set_int(path, value);
        } catch (GLib.Error err) {
            throw new ConfigurationError.ENGINE_ERROR(err.message);
        }
    }
    
    private double get_gconf_double(string path) throws ConfigurationError {
        GConf.Value? val = null;
        try {
            val = client.get(path);
        } catch (GLib.Error err) {
            throw new ConfigurationError.ENGINE_ERROR(err.message);
        }
        if (val == null)
            throw new ConfigurationError.PROPERTY_HAS_NO_VALUE(("GConfConfigurationManager: " +
                "path = '%s'.").printf(path));
        
        return val.get_float();
    }
    
    private void set_gconf_double(string path, double value) throws ConfigurationError {
        try {
            client.set_float(path, value);
        } catch (GLib.Error err) {
            throw new ConfigurationError.ENGINE_ERROR(err.message);
        }
    }
    
    private string get_gconf_string(string path) throws ConfigurationError {
        GConf.Value? val = null;
        try {
            val = client.get(path);
        } catch (Error err) {
            throw new ConfigurationError.ENGINE_ERROR(err.message);
        }
        if (val == null)
            throw new ConfigurationError.PROPERTY_HAS_NO_VALUE(("GConfConfigurationManager: " +
                "path = '%s'.").printf(path));
        
        return val.get_string();
    }

    private void set_gconf_string(string path, string value) throws ConfigurationError {
        try {
            client.set_string(path, value);
        } catch (Error err) {
            throw new ConfigurationError.ENGINE_ERROR(err.message);
        }
    }
    
    public string get_name() {
        return "GConf";
    }

    public int get_int_property(ConfigurableProperty p) throws ConfigurationError {
        return get_gconf_int(property_paths[p]);
    }
    
    public void set_int_property(ConfigurableProperty p, int val) throws ConfigurationError {
        set_gconf_int(property_paths[p], val);
        
        property_changed(p);
    }
    
    public string get_string_property(ConfigurableProperty p) throws ConfigurationError {
        return get_gconf_string(property_paths[p]);
    }
    
    public void set_string_property(ConfigurableProperty p, string val) throws ConfigurationError {
        set_gconf_string(property_paths[p], val);

        property_changed(p);
    }
    
    public bool get_bool_property(ConfigurableProperty p) throws ConfigurationError {
        return get_gconf_bool(property_paths[p]);
    }
    
    public void set_bool_property(ConfigurableProperty p, bool val) throws ConfigurationError {
        set_gconf_bool(property_paths[p], val);

        property_changed(p);
    }
    
    public double get_double_property(ConfigurableProperty p) throws ConfigurationError {
        return get_gconf_double(property_paths[p]);
    }
    
    public void set_double_property(ConfigurableProperty p, double val) throws ConfigurationError {
        set_gconf_double(property_paths[p], val);

        property_changed(p);
    }
    
    public bool get_plugin_bool(string domain, string id, string key, bool def) {
        try {
            return get_gconf_bool(make_plugin_path(domain, id, key));
        } catch (ConfigurationError err) {
            return def;
        }
    }
    
    public void set_plugin_bool(string domain, string id, string key, bool val) {
        try {
            set_gconf_bool(make_plugin_path(domain, id, key), val);
        } catch (ConfigurationError err) {
            critical("configuration system '%s': couldn't set bool value for plugin property with ( " +
                "domain = '%s', id = '%s', key = '%s' ): " + err.message, domain, id, key);
        }
    }
    
    public double get_plugin_double(string domain, string id, string key, double def) {
        try {
            return get_gconf_double(make_plugin_path(domain, id, key));
        } catch (ConfigurationError err) {
            return def;
        }
    }
    
    public void set_plugin_double(string domain, string id, string key, double val) {
        try {
            set_gconf_double(make_plugin_path(domain, id, key), val);
        } catch (ConfigurationError err) {
            critical("configuration system '%s': couldn't set double value for plugin property with ( " +
                "domain = '%s', id = '%s', key = '%s' ): " + err.message, domain, id, key);
        }
    }
    
    public int get_plugin_int(string domain, string id, string key, int def) {
        try {
            return get_gconf_int(make_plugin_path(domain, id, key));
        } catch (ConfigurationError err) {
            return def;
        }
    }
    
    public void set_plugin_int(string domain, string id, string key, int val) {
        try {
            set_gconf_int(make_plugin_path(domain, id, key), val);
        } catch (ConfigurationError err) {
            critical("configuration system '%s': couldn't set int value for plugin property with ( " +
                "domain = '%s', id = '%s', key = '%s' ): " + err.message, domain, id, key);
        }
    }
    
    public string? get_plugin_string(string domain, string id, string key, string? def) {
        try {
            return get_gconf_string(make_plugin_path(domain, id, key));
        } catch (ConfigurationError err) {
            return def;
        }
    }
    
    public void set_plugin_string(string domain, string id, string key, string? val) {
        try {
            set_gconf_string(make_plugin_path(domain, id, key), val);
        } catch (ConfigurationError err) {
            critical("configuration system '%s': couldn't set string value for plugin property with ( " +
                "domain = '%s', id = '%s', key = '%s' ): " + err.message, domain, id, key);
        }
    }
    
    public void unset_plugin_key(string domain, string id, string key) {
        try {
            client.unset(make_plugin_path(domain, id, key));
        } catch (Error err) {
            critical("configuration system '%s': couldn't unset plugin property with ( " +
                "domain = '%s', id = '%s', key = '%s' ): " + err.message, domain, id, key);
        }
    }
    
    public FuzzyPropertyState is_plugin_enabled(string id) {
        try {
            bool is_enabled =
                get_gconf_bool("/apps/shotwell/plugins/%s/enabled".printf(clean_plugin_id(id)));
            return (is_enabled) ? FuzzyPropertyState.ENABLED : FuzzyPropertyState.DISABLED;
        } catch (ConfigurationError err) {
            return FuzzyPropertyState.UNKNOWN;
        }
    }

    public void set_plugin_enabled(string id, bool enabled) {
        try {
            set_gconf_bool("/apps/shotwell/plugins/%s/enabled".printf(clean_plugin_id(id)),
                enabled);
        } catch (ConfigurationError err) {
            critical("configuration system '%s': couldn't enable/disable plugin with id = " +
                "'%s': " + err.message, id);
        }
    }
}

#endif

