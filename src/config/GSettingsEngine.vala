/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class GSettingsConfigurationEngine : ConfigurationEngine, GLib.Object {
    private const string ROOT_SCHEMA_NAME = "org.yorba.shotwell";
    private const string PREFS_SCHEMA_NAME = ROOT_SCHEMA_NAME + ".preferences";
    private const string UI_PREFS_SCHEMA_NAME = PREFS_SCHEMA_NAME + ".ui";
    private const string SLIDESHOW_PREFS_SCHEMA_NAME = PREFS_SCHEMA_NAME + ".slideshow";
    private const string WINDOW_PREFS_SCHEMA_NAME =  PREFS_SCHEMA_NAME + ".window";
    private const string FILES_PREFS_SCHEMA_NAME = PREFS_SCHEMA_NAME + ".files";
    private const string EDITING_PREFS_SCHEMA_NAME = PREFS_SCHEMA_NAME + ".editing";
    private const string EXPORT_PREFS_SCHEMA_NAME = PREFS_SCHEMA_NAME + ".export";
    private const string VIDEO_SCHEMA_NAME = ROOT_SCHEMA_NAME + ".video";
    private const string PRINTING_SCHEMA_NAME = ROOT_SCHEMA_NAME + ".printing";
    private const string SHARING_SCHEMA_NAME = ROOT_SCHEMA_NAME + ".sharing";
    private const string IMPORTING_SCHEMA_NAME = ROOT_SCHEMA_NAME + ".dataimports";
    private const string CROP_SCHEMA_NAME = ROOT_SCHEMA_NAME + ".crop-settings";
    private const string SYSTEM_DESKTOP_SCHEMA_NAME = "org.gnome.desktop.background";
    private const string SYSTEM_SCREENSAVER_SCHEMA_NAME = "org.gnome.desktop.screensaver";
    private const string PLUGINS_ENABLE_DISABLE_SCHEMA_NAME = ROOT_SCHEMA_NAME +
        ".plugins.enable-state";

    private string[] schema_names;
    private string[] key_names;
    private Gee.HashMap<string, Settings> settings_cache = new Gee.HashMap<string, Settings>();
    
    public GSettingsConfigurationEngine() {
        schema_names = new string[ConfigurableProperty.NUM_PROPERTIES];

        schema_names[ConfigurableProperty.AUTO_IMPORT_FROM_LIBRARY] = FILES_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.GTK_THEME_VARIANT] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.TRANSPARENT_BACKGROUND_TYPE] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.TRANSPARENT_BACKGROUND_COLOR] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.COMMIT_METADATA_TO_MASTERS] = FILES_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DESKTOP_BACKGROUND_FILE] = SYSTEM_DESKTOP_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DESKTOP_BACKGROUND_MODE] = SYSTEM_DESKTOP_SCHEMA_NAME;
        schema_names[ConfigurableProperty.SCREENSAVER_FILE] = SYSTEM_SCREENSAVER_SCHEMA_NAME;
        schema_names[ConfigurableProperty.SCREENSAVER_MODE] = SYSTEM_SCREENSAVER_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DIRECTORY_PATTERN] = FILES_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DIRECTORY_PATTERN_CUSTOM] = FILES_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DIRECT_WINDOW_HEIGHT] = WINDOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DIRECT_WINDOW_MAXIMIZE] = WINDOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DIRECT_WINDOW_WIDTH] = WINDOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_BASIC_PROPERTIES] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_EXTENDED_PROPERTIES] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_SIDEBAR] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_TOOLBAR] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_SEARCH_BAR] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_PHOTO_RATINGS] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_PHOTO_TAGS] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_PHOTO_TITLES] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_PHOTO_COMMENTS] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.DISPLAY_EVENT_COMMENTS] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EVENT_PHOTOS_SORT_ASCENDING] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EVENT_PHOTOS_SORT_BY] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EVENTS_SORT_ASCENDING] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EXPORT_CONSTRAINT] = EXPORT_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EXPORT_EXPORT_FORMAT_MODE] =  EXPORT_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EXPORT_EXPORT_METADATA] =  EXPORT_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EXPORT_PHOTO_FILE_FORMAT] =  EXPORT_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EXPORT_QUALITY] =  EXPORT_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EXPORT_SCALE] =  EXPORT_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EXTERNAL_PHOTO_APP] = EDITING_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.EXTERNAL_RAW_APP] = EDITING_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.HIDE_PHOTOS_ALREADY_IMPORTED] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.IMPORT_DIR] = FILES_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.KEEP_RELATIVITY] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LAST_CROP_HEIGHT] = CROP_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LAST_CROP_MENU_CHOICE] = CROP_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LAST_CROP_WIDTH] = CROP_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LAST_USED_SERVICE] = SHARING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LAST_USED_DATAIMPORTS_SERVICE] = IMPORTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LIBRARY_PHOTOS_SORT_ASCENDING] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LIBRARY_PHOTOS_SORT_BY] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LIBRARY_WINDOW_HEIGHT] = WINDOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LIBRARY_WINDOW_MAXIMIZE] = WINDOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.LIBRARY_WINDOW_WIDTH] = WINDOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.MODIFY_ORIGINALS] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PHOTO_THUMBNAIL_SCALE] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PIN_TOOLBAR_STATE] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_CONTENT_HEIGHT] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_CONTENT_LAYOUT] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_CONTENT_PPI] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_CONTENT_UNITS] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_CONTENT_WIDTH] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_IMAGES_PER_PAGE] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_MATCH_ASPECT_RATIO] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_PRINT_TITLES] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_SIZE_SELECTION] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.PRINTING_TITLES_FONT] = PRINTING_SCHEMA_NAME;
        schema_names[ConfigurableProperty.RAW_DEVELOPER_DEFAULT] = FILES_PREFS_SCHEMA_NAME;;
        schema_names[ConfigurableProperty.SHOW_WELCOME_DIALOG] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.SIDEBAR_POSITION] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.SLIDESHOW_DELAY] = SLIDESHOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.SLIDESHOW_TRANSITION_DELAY] = SLIDESHOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.SLIDESHOW_TRANSITION_EFFECT_ID] = SLIDESHOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.SLIDESHOW_SHOW_TITLE] = SLIDESHOW_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.USE_24_HOUR_TIME] = UI_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.USE_LOWERCASE_FILENAMES] = FILES_PREFS_SCHEMA_NAME;
        schema_names[ConfigurableProperty.VIDEO_INTERPRETER_STATE_COOKIE] = VIDEO_SCHEMA_NAME;
        
        key_names = new string[ConfigurableProperty.NUM_PROPERTIES];
        
        key_names[ConfigurableProperty.AUTO_IMPORT_FROM_LIBRARY] = "auto-import";
        key_names[ConfigurableProperty.GTK_THEME_VARIANT] = "use-dark-theme";
        key_names[ConfigurableProperty.TRANSPARENT_BACKGROUND_TYPE] = "transparent-background-type";
        key_names[ConfigurableProperty.TRANSPARENT_BACKGROUND_COLOR] = "transparent-background-color";
        key_names[ConfigurableProperty.COMMIT_METADATA_TO_MASTERS] = "commit-metadata";
        key_names[ConfigurableProperty.DESKTOP_BACKGROUND_FILE] = "picture-uri";
        key_names[ConfigurableProperty.DESKTOP_BACKGROUND_MODE] = "picture-options";
        key_names[ConfigurableProperty.SCREENSAVER_FILE] = "picture-uri";
        key_names[ConfigurableProperty.SCREENSAVER_MODE] = "picture-options";
        key_names[ConfigurableProperty.DIRECTORY_PATTERN] = "directory-pattern";
        key_names[ConfigurableProperty.DIRECTORY_PATTERN_CUSTOM] = "directory-pattern-custom";
        key_names[ConfigurableProperty.DIRECT_WINDOW_HEIGHT] = "direct-height";
        key_names[ConfigurableProperty.DIRECT_WINDOW_MAXIMIZE] = "direct-maximize";
        key_names[ConfigurableProperty.DIRECT_WINDOW_WIDTH] = "direct-width";
        key_names[ConfigurableProperty.DISPLAY_BASIC_PROPERTIES] = "display-basic-properties";
        key_names[ConfigurableProperty.DISPLAY_EXTENDED_PROPERTIES] = "display-extended-properties";
        key_names[ConfigurableProperty.DISPLAY_SIDEBAR] = "display-sidebar";
        key_names[ConfigurableProperty.DISPLAY_TOOLBAR] = "display-toolbar";
        key_names[ConfigurableProperty.DISPLAY_SEARCH_BAR] = "display-search-bar";
        key_names[ConfigurableProperty.DISPLAY_PHOTO_RATINGS] = "display-photo-ratings";
        key_names[ConfigurableProperty.DISPLAY_PHOTO_TAGS] = "display-photo-tags";
        key_names[ConfigurableProperty.DISPLAY_PHOTO_TITLES] = "display-photo-titles";
        key_names[ConfigurableProperty.DISPLAY_PHOTO_COMMENTS] = "display-photo-comments";
        key_names[ConfigurableProperty.DISPLAY_EVENT_COMMENTS] = "display-event-comments";
        key_names[ConfigurableProperty.EVENT_PHOTOS_SORT_ASCENDING] = "event-photos-sort-ascending";
        key_names[ConfigurableProperty.EVENT_PHOTOS_SORT_BY] = "event-photos-sort-by";
        key_names[ConfigurableProperty.EVENTS_SORT_ASCENDING] = "events-sort-ascending";
        key_names[ConfigurableProperty.EXPORT_CONSTRAINT] = "constraint";
        key_names[ConfigurableProperty.EXPORT_EXPORT_FORMAT_MODE] =  "export-format-mode";
        key_names[ConfigurableProperty.EXPORT_EXPORT_METADATA] =  "export-metadata";
        key_names[ConfigurableProperty.EXPORT_PHOTO_FILE_FORMAT] =  "photo-file-format";
        key_names[ConfigurableProperty.EXPORT_QUALITY] =  "quality";
        key_names[ConfigurableProperty.EXPORT_SCALE] =  "scale";
        key_names[ConfigurableProperty.EXTERNAL_PHOTO_APP] = "external-photo-editor";
        key_names[ConfigurableProperty.EXTERNAL_RAW_APP] = "external-raw-editor";
        key_names[ConfigurableProperty.HIDE_PHOTOS_ALREADY_IMPORTED] = "hide-photos-already-imported";
        key_names[ConfigurableProperty.IMPORT_DIR] = "import-dir";
        key_names[ConfigurableProperty.KEEP_RELATIVITY] = "keep-relativity";
        key_names[ConfigurableProperty.LAST_CROP_HEIGHT] = "last-crop-height";
        key_names[ConfigurableProperty.LAST_CROP_MENU_CHOICE] = "last-crop-menu-choice";
        key_names[ConfigurableProperty.LAST_CROP_WIDTH] = "last-crop-width";
        key_names[ConfigurableProperty.LAST_USED_SERVICE] = "last-used-service";
        key_names[ConfigurableProperty.LAST_USED_DATAIMPORTS_SERVICE] = "last-used-dataimports-service";
        key_names[ConfigurableProperty.LIBRARY_PHOTOS_SORT_ASCENDING] = "library-photos-sort-ascending";
        key_names[ConfigurableProperty.LIBRARY_PHOTOS_SORT_BY] = "library-photos-sort-by";
        key_names[ConfigurableProperty.LIBRARY_WINDOW_HEIGHT] = "library-height";
        key_names[ConfigurableProperty.LIBRARY_WINDOW_MAXIMIZE] = "library-maximize";
        key_names[ConfigurableProperty.LIBRARY_WINDOW_WIDTH] = "library-width";
        key_names[ConfigurableProperty.MODIFY_ORIGINALS] = "modify-originals";
        key_names[ConfigurableProperty.PHOTO_THUMBNAIL_SCALE] = "photo-thumbnail-scale";
        key_names[ConfigurableProperty.PIN_TOOLBAR_STATE] = "pin-toolbar-state";
        key_names[ConfigurableProperty.PRINTING_CONTENT_HEIGHT] = "content-height";
        key_names[ConfigurableProperty.PRINTING_CONTENT_LAYOUT] = "content-layout";
        key_names[ConfigurableProperty.PRINTING_CONTENT_PPI] = "content-ppi";
        key_names[ConfigurableProperty.PRINTING_CONTENT_UNITS] = "content-units";
        key_names[ConfigurableProperty.PRINTING_CONTENT_WIDTH] = "content-width";
        key_names[ConfigurableProperty.PRINTING_IMAGES_PER_PAGE] = "images-per-page";
        key_names[ConfigurableProperty.PRINTING_MATCH_ASPECT_RATIO] = "match-aspect-ratio";
        key_names[ConfigurableProperty.PRINTING_PRINT_TITLES] = "print-titles";
        key_names[ConfigurableProperty.PRINTING_SIZE_SELECTION] = "size-selection";
        key_names[ConfigurableProperty.PRINTING_TITLES_FONT] = "titles-font";
        key_names[ConfigurableProperty.RAW_DEVELOPER_DEFAULT] = "raw-developer-default";
        key_names[ConfigurableProperty.SHOW_WELCOME_DIALOG] = "show-welcome-dialog";
        key_names[ConfigurableProperty.SIDEBAR_POSITION] = "sidebar-position";
        key_names[ConfigurableProperty.SLIDESHOW_DELAY] = "delay";
        key_names[ConfigurableProperty.SLIDESHOW_TRANSITION_DELAY] = "transition-delay";
        key_names[ConfigurableProperty.SLIDESHOW_TRANSITION_EFFECT_ID] = "transition-effect-id";
        key_names[ConfigurableProperty.SLIDESHOW_SHOW_TITLE] = "show-title";
        key_names[ConfigurableProperty.USE_24_HOUR_TIME] = "use-24-hour-time";
        key_names[ConfigurableProperty.USE_LOWERCASE_FILENAMES] = "use-lowercase-filenames";
        key_names[ConfigurableProperty.VIDEO_INTERPRETER_STATE_COOKIE] = "interpreter-state-cookie";
    }

    private Settings get_settings(string schema) {
        if (!this.settings_cache.has_key(schema)) {
            this.settings_cache[schema] = new Settings(schema);
        }

        return this.settings_cache[schema];
    }

    private void check_key_valid(string schema, string key) throws ConfigurationError {
        var schema_source = SettingsSchemaSource.get_default ();
        var settings_scheme = schema_source.lookup (schema, true);
        if (settings_scheme == null) {
            throw new ConfigurationError.ENGINE_ERROR("schema '%s' is not installed".printf(schema));
        }

        if (!settings_scheme.has_key (key))
            throw new ConfigurationError.ENGINE_ERROR("schema '%s' does not define key '%s'".printf(
                schema, key));
    }

    private bool get_gs_bool(string schema, string key) throws ConfigurationError {
        check_key_valid(schema, key);

        Settings schema_object = get_settings(schema);

        return schema_object.get_boolean(key);
    }
    
    private void set_gs_bool(string schema, string key, bool value) throws ConfigurationError {
        check_key_valid(schema, key);

        Settings schema_object = get_settings(schema);

        schema_object.set_boolean(key, value);
    }

    private void set_gs_enum (string schema, string key, int value) throws ConfigurationError {
        check_key_valid (schema, key);

        var schema_object = get_settings (schema);
        schema_object.set_enum (key, value);
    }

    private int get_gs_enum (string schema, string key) throws ConfigurationError {
        check_key_valid (schema, key);

        var schema_object = get_settings (schema);
        return schema_object.get_enum (key);
    }

    private int get_gs_int(string schema, string key) throws ConfigurationError {
        check_key_valid(schema, key);

        Settings schema_object = get_settings(schema);

        return schema_object.get_int(key);
    }
    
    private void set_gs_int(string schema, string key, int value) throws ConfigurationError {
        check_key_valid(schema, key);

        Settings schema_object = get_settings(schema);

        schema_object.set_int(key, value);
    }

    private double get_gs_double(string schema, string key) throws ConfigurationError {
        check_key_valid(schema, key);

        Settings schema_object = get_settings(schema);

        return schema_object.get_double(key);
    }
    
    private void set_gs_double(string schema, string key, double value) throws ConfigurationError {
        check_key_valid(schema, key);

        Settings schema_object = get_settings(schema);

        schema_object.set_double(key, value);
    }

    private string get_gs_string(string schema, string key) throws ConfigurationError {
        check_key_valid(schema, key);

        Settings schema_object = get_settings(schema);

        return schema_object.get_string(key);
    }
    
    private void set_gs_string(string schema, string key, string value) throws ConfigurationError {
        check_key_valid(schema, key);

        Settings schema_object = get_settings(schema);

        schema_object.set_string(key, value);
    }
    
    private void reset_gs_to_default(string schema, string key) throws ConfigurationError {
        check_key_valid(schema, key);

        Settings schema_object = get_settings(schema);

        schema_object.reset(key);
    }

    private static string? clean_plugin_id(string id) {
        string cleaned = id.replace("/", "-");
        cleaned = cleaned.strip();
        
        return !is_string_empty(cleaned) ? cleaned : null;
    }
    
    private static string get_plugin_enable_disable_name(string id) {
        string? cleaned_id = clean_plugin_id(id);
        if (cleaned_id == null)
            cleaned_id = "default";

        cleaned_id = cleaned_id.replace("org.yorba.shotwell.", "");
        cleaned_id = cleaned_id.replace(".", "-");
        
        return cleaned_id;
    }
    
    private static string make_plugin_schema_name(string domain, string id) {
        string? cleaned_id = clean_plugin_id(id);
        if (cleaned_id == null)
            cleaned_id = "default";
        cleaned_id = cleaned_id.replace(".", "-");
        
        return "org.yorba.shotwell.%s.%s".printf(domain, cleaned_id);
    }
    
    private static string make_gsettings_key(string gconf_key) {
        return gconf_key.replace("_", "-");
    }

    public string get_name() {
        return "GSettings";
    }

    public int get_enum_property (ConfigurableProperty p) throws ConfigurationError{
        return get_gs_enum (schema_names[p], key_names[p]);
    }

    public void set_enum_property (ConfigurableProperty p, int val) throws ConfigurationError {
        set_gs_enum (schema_names[p], key_names[p], val);
        property_changed (p);
    }

    public int get_int_property(ConfigurableProperty p) throws ConfigurationError {
        return get_gs_int(schema_names[p], key_names[p]);
    }

    public void set_int_property(ConfigurableProperty p, int val) throws ConfigurationError {
        set_gs_int(schema_names[p], key_names[p], val);
        property_changed(p);
    }
    
    public string get_string_property(ConfigurableProperty p) throws ConfigurationError {
        string gs_result = get_gs_string(schema_names[p], key_names[p]);
        
        // if we're getting the desktop background file, convert the file uri we get back from
        // GSettings into a file path
        string result = gs_result;
        if (p == ConfigurableProperty.DESKTOP_BACKGROUND_FILE) {
            result = gs_result.substring(7);
        }
        
        return result;
    }
    
    public void set_string_property(ConfigurableProperty p, string val) throws ConfigurationError {
        // if we're setting the desktop background/screensaver file, convert the filename into a file URI
        string converted_val = val;
        if (p == ConfigurableProperty.DESKTOP_BACKGROUND_FILE
            || p == ConfigurableProperty.SCREENSAVER_FILE) {
            converted_val = "file://" + val;
        }

        set_gs_string(schema_names[p], key_names[p], converted_val);
        property_changed(p);
    }
    
    public bool get_bool_property(ConfigurableProperty p) throws ConfigurationError {
        return get_gs_bool(schema_names[p], key_names[p]);
    }
    
    public void set_bool_property(ConfigurableProperty p, bool val) throws ConfigurationError {
        set_gs_bool(schema_names[p], key_names[p], val);
        property_changed(p);
    }
    
    public double get_double_property(ConfigurableProperty p) throws ConfigurationError {
        return get_gs_double(schema_names[p], key_names[p]);
    }
    
    public void set_double_property(ConfigurableProperty p, double val) throws ConfigurationError {
        set_gs_double(schema_names[p], key_names[p], val);
        property_changed(p);
    }

    public bool get_plugin_bool(string domain, string id, string key, bool def) {
        string schema_name = make_plugin_schema_name(domain, id);
        
        try {
            return get_gs_bool(schema_name, make_gsettings_key(key));
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
            return def;
        }
    }
    
    public void set_plugin_bool(string domain, string id, string key, bool val) {
        string schema_name = make_plugin_schema_name(domain, id);
        
        try {
            set_gs_bool(schema_name, make_gsettings_key(key), val);
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
        }
    }

    public double get_plugin_double(string domain, string id, string key, double def) {
        string schema_name = make_plugin_schema_name(domain, id);
        
        try {
            return get_gs_double(schema_name, make_gsettings_key(key));
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
            return def;
        }
    }

    public void set_plugin_double(string domain, string id, string key, double val) {
        string schema_name = make_plugin_schema_name(domain, id);
        
        try {
            set_gs_double(schema_name, make_gsettings_key(key), val);
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
        }
    }

    public int get_plugin_int(string domain, string id, string key, int def) {
        string schema_name = make_plugin_schema_name(domain, id);
        
        try {
            return get_gs_int(schema_name, make_gsettings_key(key));
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
            return def;
        }
    }
    
    public void set_plugin_int(string domain, string id, string key, int val) {
        string schema_name = make_plugin_schema_name(domain, id);
        
        try {
            set_gs_int(schema_name, make_gsettings_key(key), val);
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
        }
    }
    
    public string? get_plugin_string(string domain, string id, string key, string? def) {
        string schema_name = make_plugin_schema_name(domain, id);
        
        try {
            return get_gs_string(schema_name, make_gsettings_key(key));
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
            return def;
        }
    }
    
    public void set_plugin_string(string domain, string id, string key, string? val) {
        string schema_name = make_plugin_schema_name(domain, id);
        
        try {
            set_gs_string(schema_name, make_gsettings_key(key), val);
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
        }
    }

    public void unset_plugin_key(string domain, string id, string key) {
        string schema_name = make_plugin_schema_name(domain, id);
        
        try {
            reset_gs_to_default(schema_name, make_gsettings_key(key));
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
        }
    }
    
    public FuzzyPropertyState is_plugin_enabled(string id) {
        string enable_disable_name = get_plugin_enable_disable_name(id);
        
        try {
            return (get_gs_bool(PLUGINS_ENABLE_DISABLE_SCHEMA_NAME, enable_disable_name)) ?
                FuzzyPropertyState.ENABLED : FuzzyPropertyState.DISABLED;
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
            return FuzzyPropertyState.UNKNOWN;
        }
    }

    public void set_plugin_enabled(string id, bool enabled) {
        string enable_disable_name = get_plugin_enable_disable_name(id);
        
        try {
            set_gs_bool(PLUGINS_ENABLE_DISABLE_SCHEMA_NAME, enable_disable_name, enabled);
        } catch (ConfigurationError err) {
            critical("GSettingsConfigurationEngine: error: %s", err.message);
        }
    }
    
    /*! @brief Migrates settings data over from old-style /apps/ paths to /org/yorba/ ones.
     *  Should only be called ONCE, during DB upgrading; otherwise, stale data may be copied
     *  over newer data by accident.
     */
    public static void run_gsettings_migrator() {
        string cmd_line = "sh " + AppDirs.get_settings_migrator_bin().get_path();

        try {
            Process.spawn_command_line_sync(cmd_line);
        } catch (Error err) {
            message("Error running shotwell-settings-migrator: %s", err.message);
        }
    }

}
