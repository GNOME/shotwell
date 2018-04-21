/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public errordomain ConfigurationError {
    PROPERTY_HAS_NO_VALUE,
    /**
      * the underlying configuration engine reported an error; the error is
      * specific to the configuration engine in use (e.g., GSettings)
      * and is usually meaningless to client code */
    ENGINE_ERROR,
}

public enum FuzzyPropertyState {
    ENABLED,
    DISABLED,
    UNKNOWN
}

public enum ConfigurableProperty {   
    AUTO_IMPORT_FROM_LIBRARY = 0,
    GTK_THEME_VARIANT,
    TRANSPARENT_BACKGROUND_TYPE,
    TRANSPARENT_BACKGROUND_COLOR,
    COMMIT_METADATA_TO_MASTERS,
    DESKTOP_BACKGROUND_FILE,
    DESKTOP_BACKGROUND_MODE,
    SCREENSAVER_FILE,
    SCREENSAVER_MODE,
    DIRECTORY_PATTERN,
    DIRECTORY_PATTERN_CUSTOM,
    DIRECT_WINDOW_HEIGHT,
    DIRECT_WINDOW_MAXIMIZE,
    DIRECT_WINDOW_WIDTH,
    DISPLAY_BASIC_PROPERTIES,
    DISPLAY_EVENT_COMMENTS,
    DISPLAY_EXTENDED_PROPERTIES,
    DISPLAY_SIDEBAR,
    DISPLAY_TOOLBAR,
    DISPLAY_SEARCH_BAR,
    DISPLAY_PHOTO_RATINGS,
    DISPLAY_PHOTO_TAGS,
    DISPLAY_PHOTO_TITLES,
    DISPLAY_PHOTO_COMMENTS,
    EVENT_PHOTOS_SORT_ASCENDING,
    EVENT_PHOTOS_SORT_BY,
    EVENTS_SORT_ASCENDING,
    EXPORT_CONSTRAINT,
    EXPORT_EXPORT_FORMAT_MODE,
    EXPORT_EXPORT_METADATA,
    EXPORT_PHOTO_FILE_FORMAT,
    EXPORT_QUALITY,
    EXPORT_SCALE,
    EXTERNAL_PHOTO_APP,
    EXTERNAL_RAW_APP,
    HIDE_PHOTOS_ALREADY_IMPORTED,
    IMPORT_DIR,
    KEEP_RELATIVITY,
    LAST_CROP_HEIGHT,
    LAST_CROP_MENU_CHOICE,
    LAST_CROP_WIDTH,
    LAST_USED_SERVICE,
    LAST_USED_DATAIMPORTS_SERVICE,
    LIBRARY_PHOTOS_SORT_ASCENDING,
    LIBRARY_PHOTOS_SORT_BY,
    LIBRARY_WINDOW_HEIGHT,
    LIBRARY_WINDOW_MAXIMIZE,
    LIBRARY_WINDOW_WIDTH,
    MODIFY_ORIGINALS,
    PHOTO_THUMBNAIL_SCALE,
    PIN_TOOLBAR_STATE,
    PRINTING_CONTENT_HEIGHT,
    PRINTING_CONTENT_LAYOUT,
    PRINTING_CONTENT_PPI,
    PRINTING_CONTENT_UNITS,
    PRINTING_CONTENT_WIDTH,
    PRINTING_IMAGES_PER_PAGE,
    PRINTING_MATCH_ASPECT_RATIO,
    PRINTING_PRINT_TITLES,
    PRINTING_SIZE_SELECTION,
    PRINTING_TITLES_FONT,
    RAW_DEVELOPER_DEFAULT,
    SHOW_WELCOME_DIALOG,
    SIDEBAR_POSITION,
    SLIDESHOW_DELAY,
    SLIDESHOW_TRANSITION_DELAY,
    SLIDESHOW_TRANSITION_EFFECT_ID,
    SLIDESHOW_SHOW_TITLE,
    USE_24_HOUR_TIME,
    USE_LOWERCASE_FILENAMES,
    VIDEO_INTERPRETER_STATE_COOKIE,
    
    
    NUM_PROPERTIES;

    public string to_string() {
        switch (this) {
            case AUTO_IMPORT_FROM_LIBRARY:
                return "AUTO_IMPORT_FROM_LIBRARY";
                
            case GTK_THEME_VARIANT:
                return "GTK_THEME_VARIANT";

            case TRANSPARENT_BACKGROUND_TYPE:
                return "TRANSPARENT_BACKGROUND_TYPE";

            case TRANSPARENT_BACKGROUND_COLOR:
                return "TRANSPARENT_BACKGROUND_COLOR";
                
            case COMMIT_METADATA_TO_MASTERS:
                return "COMMIT_METADATA_TO_MASTERS";
                
            case DESKTOP_BACKGROUND_FILE:
                return "DESKTOP_BACKGROUND_FILE";
                
            case DESKTOP_BACKGROUND_MODE:
                return "DESKTOP_BACKGROUND_MODE";
                
            case SCREENSAVER_FILE:
                return "SCREENSAVER_FILE";
                
            case SCREENSAVER_MODE:
                return "SCREENSAVER_MODE";
                
            case DIRECTORY_PATTERN:
                return "DIRECTORY_PATTERN";
                
            case DIRECTORY_PATTERN_CUSTOM:
                return "DIRECTORY_PATTERN_CUSTOM";
                
            case DIRECT_WINDOW_HEIGHT:
                return "DIRECT_WINDOW_HEIGHT";
                
            case DIRECT_WINDOW_MAXIMIZE:
                return "DIRECT_WINDOW_MAXIMIZE";
                
            case DIRECT_WINDOW_WIDTH:
                return "DIRECT_WINDOW_WIDTH";
                
            case DISPLAY_BASIC_PROPERTIES:
                return "DISPLAY_BASIC_PROPERTIES";
                
            case DISPLAY_EXTENDED_PROPERTIES:
                return "DISPLAY_EXTENDED_PROPERTIES";
                
            case DISPLAY_SIDEBAR:
                return "DISPLAY_SIDEBAR";

            case DISPLAY_TOOLBAR:
                return "DISPLAY_TOOLBAR";
                
            case DISPLAY_SEARCH_BAR:
                return "DISPLAY_SEARCH_BAR";
                
            case DISPLAY_PHOTO_RATINGS:
                return "DISPLAY_PHOTO_RATINGS";
                
            case DISPLAY_PHOTO_TAGS:
                return "DISPLAY_PHOTO_TAGS";
                
            case DISPLAY_PHOTO_TITLES:
                return "DISPLAY_PHOTO_TITLES";
                
            case DISPLAY_PHOTO_COMMENTS:
                return "DISPLAY_PHOTO_COMMENTS";
                
            case DISPLAY_EVENT_COMMENTS:
                return "DISPLAY_EVENT_COMMENTS";
                
            case EVENT_PHOTOS_SORT_ASCENDING:
                return "EVENT_PHOTOS_SORT_ASCENDING";
                
            case EVENT_PHOTOS_SORT_BY:
                return "EVENT_PHOTOS_SORT_BY";
                
            case EVENTS_SORT_ASCENDING:
                return "EVENTS_SORT_ASCENDING";
                
            case EXPORT_CONSTRAINT:
                return "EXPORT_CONSTRAINT";

            case EXPORT_EXPORT_FORMAT_MODE:
                return "EXPORT_EXPORT_FORMAT_MODE";

            case EXPORT_EXPORT_METADATA:
                return "EXPORT_EXPORT_METADATA";

            case EXPORT_PHOTO_FILE_FORMAT:
                return "EXPORT_PHOTO_FILE_FORMAT";

            case EXPORT_QUALITY:
                return "EXPORT_QUALITY";

            case EXPORT_SCALE:
                return "EXPORT_SCALE";

            case EXTERNAL_PHOTO_APP:
                return "EXTERNAL_PHOTO_APP";
                
            case EXTERNAL_RAW_APP:
                return "EXTERNAL_RAW_APP";
            
            case HIDE_PHOTOS_ALREADY_IMPORTED:
                return "HIDE_PHOTOS_ALREADY_IMPORTED";
                
            case IMPORT_DIR:
                return "IMPORT_DIR";
                
            case KEEP_RELATIVITY:
                return "KEEP_RELATIVITY";

            case LAST_CROP_HEIGHT:
                return "LAST_CROP_HEIGHT";

            case LAST_CROP_MENU_CHOICE:
                return "LAST_CROP_MENU_CHOICE";

            case LAST_CROP_WIDTH:
                return "LAST_CROP_WIDTH";

            case LAST_USED_SERVICE:
                return "LAST_USED_SERVICE";
                
            case LAST_USED_DATAIMPORTS_SERVICE:
                return "LAST_USED_DATAIMPORTS_SERVICE";
                
            case LIBRARY_PHOTOS_SORT_ASCENDING:
                return "LIBRARY_PHOTOS_SORT_ASCENDING";
                
            case LIBRARY_PHOTOS_SORT_BY:
                return "LIBRARY_PHOTOS_SORT_BY";
                
            case LIBRARY_WINDOW_HEIGHT:
                return "LIBRARY_WINDOW_HEIGHT";
                
            case LIBRARY_WINDOW_MAXIMIZE:
                return "LIBRARY_WINDOW_MAXIMIZE";
                
            case LIBRARY_WINDOW_WIDTH:
                return "LIBRARY_WINDOW_WIDTH";
                
            case MODIFY_ORIGINALS:
                return "MODIFY_ORIGINALS";
                
            case PHOTO_THUMBNAIL_SCALE:
                return "PHOTO_THUMBNAIL_SCALE";
                
            case PIN_TOOLBAR_STATE:
                return "PIN_TOOLBAR_STATE";
                
            case PRINTING_CONTENT_HEIGHT:
                return "PRINTING_CONTENT_HEIGHT";

            case PRINTING_CONTENT_LAYOUT:
                return "PRINTING_CONTENT_LAYOUT";

            case PRINTING_CONTENT_PPI:
                return "PRINTING_CONTENT_PPI";
                
            case PRINTING_CONTENT_UNITS:
                return "PRINTING_CONTENT_UNITS";
                
            case PRINTING_CONTENT_WIDTH:
                return "PRINTING_CONTENT_WIDTH";
                
            case PRINTING_IMAGES_PER_PAGE:
                return "PRINTING_IMAGES_PER_PAGE";
                
            case PRINTING_MATCH_ASPECT_RATIO:
                return "PRINTING_MATCH_ASPECT_RATIO";
                
            case PRINTING_PRINT_TITLES:
                return "PRINTING_PRINT_TITLES";
                
            case PRINTING_SIZE_SELECTION:
                return "PRINTING_SIZE_SELECTION";
                
            case PRINTING_TITLES_FONT:
                return "PRINTING_TITLES_FONT";
                
            case RAW_DEVELOPER_DEFAULT:
                return "RAW_DEVELOPER_DEFAULT";
                
            case SHOW_WELCOME_DIALOG:
                return "SHOW_WELCOME_DIALOG";
                
            case SIDEBAR_POSITION:
                return "SIDEBAR_POSITION";
                
            case SLIDESHOW_DELAY:
                return "SLIDESHOW_DELAY";
                
            case SLIDESHOW_TRANSITION_DELAY:
                return "SLIDESHOW_TRANSITION_DELAY";
                
            case SLIDESHOW_TRANSITION_EFFECT_ID:
                return "SLIDESHOW_TRANSITION_EFFECT_ID";
            
            case SLIDESHOW_SHOW_TITLE:
                return "SLIDESHOW_SHOW_TITLE";
                
            case USE_24_HOUR_TIME:
                return "USE_24_HOUR_TIME";
                
            case USE_LOWERCASE_FILENAMES:
                return "USE_LOWERCASE_FILENAMES";
                
            case VIDEO_INTERPRETER_STATE_COOKIE:
                return "VIDEO_INTERPRETER_STATE_COOKIE";

            default:
                error("unknown ConfigurableProperty enumeration value");
        }
    }
}

public interface ConfigurationEngine : GLib.Object {
    public signal void property_changed(ConfigurableProperty p);

    public abstract string get_name();

    public abstract int get_int_property(ConfigurableProperty p) throws ConfigurationError;
    public abstract void set_int_property(ConfigurableProperty p, int val) throws ConfigurationError;
    
    public abstract int get_enum_property(ConfigurableProperty p) throws ConfigurationError;
    public abstract void set_enum_property(ConfigurableProperty p, int val) throws ConfigurationError;

    public abstract string get_string_property(ConfigurableProperty p) throws ConfigurationError;
    public abstract void set_string_property(ConfigurableProperty p, string val) throws ConfigurationError;
    
    public abstract bool get_bool_property(ConfigurableProperty p) throws ConfigurationError;
    public abstract void set_bool_property(ConfigurableProperty p, bool val) throws ConfigurationError;
    
    public abstract double get_double_property(ConfigurableProperty p) throws ConfigurationError;
    public abstract void set_double_property(ConfigurableProperty p, double val) throws ConfigurationError;
    
    public abstract bool get_plugin_bool(string domain, string id, string key, bool def);   
    public abstract void set_plugin_bool(string domain, string id, string key, bool val);
    public abstract double get_plugin_double(string domain, string id, string key, double def);
    public abstract void set_plugin_double(string domain, string id, string key, double val);
    public abstract int get_plugin_int(string domain, string id, string key, int def);
    public abstract void set_plugin_int(string domain, string id, string key, int val);
    public abstract string? get_plugin_string(string domain, string id, string key, string? def);
    public abstract void set_plugin_string(string domain, string id, string key, string? val);
    public abstract void unset_plugin_key(string domain, string id, string key);
    
    public abstract FuzzyPropertyState is_plugin_enabled(string id);
    public abstract void set_plugin_enabled(string id, bool enabled);
}

public abstract class ConfigurationFacade : Object {
    private ConfigurationEngine engine;

    public signal void auto_import_from_library_changed();
    public signal void bg_color_name_changed();
    public signal void transparent_background_type_changed();
    public signal void transparent_background_color_changed();
    public signal void commit_metadata_to_masters_changed();
    public signal void events_sort_ascending_changed();
    public signal void external_app_changed();
    public signal void import_directory_changed();
    
    protected ConfigurationFacade(ConfigurationEngine engine) {
        this.engine = engine;

        engine.property_changed.connect(on_property_changed);
    }

    private void on_property_changed(ConfigurableProperty p) {
        debug ("ConfigurationFacade: engine reports property '%s' changed.", p.to_string());

        switch (p) {
            case ConfigurableProperty.AUTO_IMPORT_FROM_LIBRARY:
                auto_import_from_library_changed();
            break;
            
            case ConfigurableProperty.GTK_THEME_VARIANT:
                bg_color_name_changed();
            break;

            case ConfigurableProperty.TRANSPARENT_BACKGROUND_TYPE:
                transparent_background_type_changed();
            break;

            case ConfigurableProperty.TRANSPARENT_BACKGROUND_COLOR:
                transparent_background_color_changed();
            break;
            
            case ConfigurableProperty.COMMIT_METADATA_TO_MASTERS:
                commit_metadata_to_masters_changed();
            break;

            case ConfigurableProperty.EVENTS_SORT_ASCENDING:
                events_sort_ascending_changed();
            break;
            
            case ConfigurableProperty.EXTERNAL_PHOTO_APP:
            case ConfigurableProperty.EXTERNAL_RAW_APP:
                external_app_changed();
            break;
            
            case ConfigurableProperty.IMPORT_DIR:
                import_directory_changed();
            break;
        }
    }

    protected ConfigurationEngine get_engine() {
        return engine;
    }

    protected void on_configuration_error(ConfigurationError err) {
        if (err is ConfigurationError.PROPERTY_HAS_NO_VALUE) {
            message("configuration engine '%s' reports PROPERTY_HAS_NO_VALUE error: %s",
                engine.get_name(), err.message);
        }
        else if (err is ConfigurationError.ENGINE_ERROR) {
            critical("configuration engine '%s' reports ENGINE_ERROR: %s",
                engine.get_name(), err.message);
        } else {
            critical("configuration engine '%s' reports unknown error: %s",
                engine.get_name(), err.message);
        }
    }

    //
    // auto import from library
    //
    public virtual bool get_auto_import_from_library() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.AUTO_IMPORT_FROM_LIBRARY);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_auto_import_from_library(bool auto_import) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.AUTO_IMPORT_FROM_LIBRARY,
                auto_import);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    //
    // GTK theme variant
    //
    public virtual bool get_gtk_theme_variant() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.GTK_THEME_VARIANT);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return true;
        }
    }
    
    public virtual void set_gtk_theme_variant(bool dark) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.GTK_THEME_VARIANT, dark);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    //
    // transparent background type
    //
    public virtual string get_transparent_background_type() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.TRANSPARENT_BACKGROUND_TYPE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return "checkered";
        }
    }

    public virtual void set_transparent_background_type(string type) {
        try {
            get_engine().set_string_property(ConfigurableProperty.TRANSPARENT_BACKGROUND_TYPE, type);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    //
    // transparent background color
    //
    public virtual string get_transparent_background_color() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.TRANSPARENT_BACKGROUND_COLOR);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return "#444";
        }
    }

    public virtual void set_transparent_background_color(string color_name) {
        try {
            get_engine().set_string_property(ConfigurableProperty.TRANSPARENT_BACKGROUND_COLOR, color_name);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    //
    // commit metadata to masters
    //
    public virtual bool get_commit_metadata_to_masters() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.COMMIT_METADATA_TO_MASTERS);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_commit_metadata_to_masters(bool commit_metadata) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.COMMIT_METADATA_TO_MASTERS,
                commit_metadata);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    //
    // desktop background
    //
    public virtual string get_desktop_background() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.DESKTOP_BACKGROUND_FILE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return "";
        }
    }

    public virtual void set_desktop_background(string filename) {
        try {
            get_engine().set_string_property(ConfigurableProperty.DESKTOP_BACKGROUND_FILE,
                filename);
            get_engine().set_string_property(ConfigurableProperty.DESKTOP_BACKGROUND_MODE,
                "zoom");
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // screensaver background
    //
    public virtual string get_screensaver() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.SCREENSAVER_FILE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return "";
        }
    }

    public virtual void set_screensaver(string filename) {
        try {
            get_engine().set_string_property(ConfigurableProperty.SCREENSAVER_FILE,
                filename);
            get_engine().set_string_property(ConfigurableProperty.SCREENSAVER_MODE,
                "zoom");
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // directory pattern
    //
    public virtual string? get_directory_pattern() {
        try {
            string s = get_engine().get_string_property(ConfigurableProperty.DIRECTORY_PATTERN);
            return (s == "") ? null : s;
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return "";
        }
    }
    
    public virtual void set_directory_pattern(string? s) {
        try {
            if (s == null)
                s = "";

            get_engine().set_string_property(ConfigurableProperty.DIRECTORY_PATTERN, s);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // directory pattern custom
    //
    public virtual string get_directory_pattern_custom() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.DIRECTORY_PATTERN_CUSTOM);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return "";
        }
    }
    
    public virtual void set_directory_pattern_custom(string s) {
        try {
            get_engine().set_string_property(ConfigurableProperty.DIRECTORY_PATTERN_CUSTOM, s);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // direct window state
    //
    public virtual void get_direct_window_state(out bool maximize, out Dimensions dimensions) {
        maximize = false;
        dimensions = Dimensions(1024, 768);
        try {
            maximize = get_engine().get_bool_property(ConfigurableProperty.DIRECT_WINDOW_MAXIMIZE);
            int w = get_engine().get_int_property(ConfigurableProperty.DIRECT_WINDOW_WIDTH);
            int h = get_engine().get_int_property(ConfigurableProperty.DIRECT_WINDOW_HEIGHT);
            dimensions = Dimensions(w, h);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    
    public virtual void set_direct_window_state(bool maximize, Dimensions dimensions) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DIRECT_WINDOW_MAXIMIZE, maximize);
            get_engine().set_int_property(ConfigurableProperty.DIRECT_WINDOW_WIDTH,
                dimensions.width);
            get_engine().set_int_property(ConfigurableProperty.DIRECT_WINDOW_HEIGHT,
                dimensions.height);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // display basic properties
    //
    public virtual bool get_display_basic_properties() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_BASIC_PROPERTIES);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return true;
        }
    }
      
    public virtual void set_display_basic_properties(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_BASIC_PROPERTIES, display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // display extended properties
    //
    public virtual bool get_display_extended_properties() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_EXTENDED_PROPERTIES);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_display_extended_properties(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_EXTENDED_PROPERTIES,
                display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // display sidebar
    //
    public virtual bool get_display_sidebar() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_SIDEBAR);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_display_sidebar(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_SIDEBAR, display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    

    //
    // display toolbar
    //
    public virtual bool get_display_toolbar() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_TOOLBAR);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }

    public virtual void set_display_toolbar(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_TOOLBAR, display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // display search & filter toolbar
    //
    public virtual bool get_display_search_bar() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_SEARCH_BAR);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_display_search_bar(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_SEARCH_BAR, display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // display photo ratings
    //
    public virtual bool get_display_photo_ratings() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_PHOTO_RATINGS);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return true;
        }
    }
    
    public virtual void set_display_photo_ratings(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_PHOTO_RATINGS, display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // display photo tags
    //
    public virtual bool get_display_photo_tags() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_PHOTO_TAGS);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return true;
        }
    }
    
    public virtual void set_display_photo_tags(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_PHOTO_TAGS, display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // display photo titles
    //
    public virtual bool get_display_photo_titles() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_PHOTO_TITLES);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_display_photo_titles(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_PHOTO_TITLES, display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // display photo comments
    //
    public virtual bool get_display_photo_comments() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_PHOTO_COMMENTS);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_display_photo_comments(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_PHOTO_COMMENTS, display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // display event comments
    //
    public virtual bool get_display_event_comments() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.DISPLAY_EVENT_COMMENTS);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_display_event_comments(bool display) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.DISPLAY_EVENT_COMMENTS, display);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // event photos sort
    //
    public virtual void get_event_photos_sort(out bool sort_order, out int sort_by) {
        sort_order = false;
        sort_by = 2;
        try {
            sort_order = get_engine().get_bool_property(
                ConfigurableProperty.EVENT_PHOTOS_SORT_ASCENDING);
            sort_by = get_engine().get_int_property(ConfigurableProperty.EVENT_PHOTOS_SORT_BY);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    public virtual void set_event_photos_sort(bool sort_order, int sort_by) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.EVENT_PHOTOS_SORT_ASCENDING,
                sort_order);
            get_engine().set_int_property(ConfigurableProperty.EVENT_PHOTOS_SORT_BY,
                sort_by);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // events sort ascending
    //
    public virtual bool get_events_sort_ascending() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.EVENTS_SORT_ASCENDING);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_events_sort_ascending(bool sort) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.EVENTS_SORT_ASCENDING, sort);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    //
    // external photo app
    //
    public virtual string get_external_photo_app() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.EXTERNAL_PHOTO_APP);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return "";
        }
    }

    public virtual void set_external_photo_app(string external_photo_app) {
        try {
            get_engine().set_string_property(ConfigurableProperty.EXTERNAL_PHOTO_APP,
                external_photo_app);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    //
    // external raw app
    //
    public virtual string get_external_raw_app() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.EXTERNAL_RAW_APP);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return "";
        }
    }

    public virtual void set_external_raw_app(string external_raw_app) {
        try {
            get_engine().set_string_property(ConfigurableProperty.EXTERNAL_RAW_APP,
                external_raw_app);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    //
    // export dialog settings
    //
    public virtual ScaleConstraint get_export_constraint() {
        try {
            return (ScaleConstraint) get_engine().get_enum_property(ConfigurableProperty.EXPORT_CONSTRAINT);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0;
        }
    }

    public virtual void set_export_constraint(ScaleConstraint constraint) {
        try {
            get_engine().set_enum_property(ConfigurableProperty.EXPORT_CONSTRAINT, ( (int) constraint));
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    public virtual ExportFormatMode get_export_export_format_mode() {
        try {
            return (ExportFormatMode) get_engine().get_enum_property(ConfigurableProperty.EXPORT_EXPORT_FORMAT_MODE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0;
        }
    }

    public virtual void set_export_export_format_mode(ExportFormatMode export_format_mode) {
        try {
            get_engine().set_enum_property(ConfigurableProperty.EXPORT_EXPORT_FORMAT_MODE, ( (int) export_format_mode ));
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    public virtual bool get_export_export_metadata() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.EXPORT_EXPORT_METADATA);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }

    public virtual void set_export_export_metadata(bool export_metadata) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.EXPORT_EXPORT_METADATA, export_metadata);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    public virtual PhotoFileFormat get_export_photo_file_format() {
        try {
            return PhotoFileFormat.unserialize( get_engine().get_enum_property(ConfigurableProperty.EXPORT_PHOTO_FILE_FORMAT) );
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0;
        }
    }

    public virtual void set_export_photo_file_format(PhotoFileFormat photo_file_format) {
        try {
            get_engine().set_enum_property(ConfigurableProperty.EXPORT_PHOTO_FILE_FORMAT, photo_file_format.serialize());
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    public virtual Jpeg.Quality get_export_quality() {
        try {
            return (Jpeg.Quality) get_engine().get_enum_property(ConfigurableProperty.EXPORT_QUALITY);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0;
        }
    }

    public virtual void set_export_quality(Jpeg.Quality quality) {
        try {
            get_engine().set_enum_property(ConfigurableProperty.EXPORT_QUALITY, ( (int) quality ));
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    public virtual int get_export_scale() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.EXPORT_SCALE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0;
        }
    }

    public virtual void set_export_scale(int scale) {
        try {
            get_engine().set_int_property(ConfigurableProperty.EXPORT_SCALE, scale);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }

    //
    // Default RAW developer.
    //
    public virtual RawDeveloper get_default_raw_developer() {
        try {
            return RawDeveloper.from_string(get_engine().get_string_property(
                ConfigurableProperty.RAW_DEVELOPER_DEFAULT));
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            
            return RawDeveloper.CAMERA;
        }
    }
    
    public virtual void set_default_raw_developer(RawDeveloper d) {
        try {
            get_engine().set_string_property(ConfigurableProperty.RAW_DEVELOPER_DEFAULT,
                d.to_string());
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return;
        }
    }
    
    //
    // hide photos already imported
    //
    public virtual bool get_hide_photos_already_imported() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.HIDE_PHOTOS_ALREADY_IMPORTED);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            
            return true;
        }
    }
    
    public virtual void set_hide_photos_already_imported(bool hide_imported) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.HIDE_PHOTOS_ALREADY_IMPORTED, hide_imported);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    
    //
    // import dir
    //
    public virtual string get_import_dir() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.IMPORT_DIR);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return "";
        }
    }

    public virtual void set_import_dir(string import_dir) {
        try {
            get_engine().set_string_property(ConfigurableProperty.IMPORT_DIR, import_dir);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    
    //
    // keep relativity
    //
    public virtual bool get_keep_relativity() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.KEEP_RELATIVITY);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return true;
        }
    }

    public virtual void set_keep_relativity(bool keep_relativity) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.KEEP_RELATIVITY, keep_relativity);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    
    //
    // pin toolbar state
    //
    public virtual bool get_pin_toolbar_state() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.PIN_TOOLBAR_STATE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return false;
        }
    }

    public virtual void set_pin_toolbar_state(bool state) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.PIN_TOOLBAR_STATE, state);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    
    //
    // last crop height
    //
    public virtual int get_last_crop_height() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.LAST_CROP_HEIGHT);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return 1;
        }
    }

    public virtual void set_last_crop_height(int choice) {
        try {
            get_engine().set_int_property(ConfigurableProperty.LAST_CROP_HEIGHT, choice);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // last crop menu choice
    //
    public virtual int get_last_crop_menu_choice() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.LAST_CROP_MENU_CHOICE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            // in the event we can't get a reasonable value from the configuration engine, we
            // return the empty string since it won't match the name of any existing publishing
            // service -- this will cause the publishing subsystem to select the first service
            // loaded that supports the user's media type
            return 0;
        }
    }

    public virtual void set_last_crop_menu_choice(int choice) {
        try {
            get_engine().set_int_property(ConfigurableProperty.LAST_CROP_MENU_CHOICE, choice);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // last crop width
    //
    public virtual int get_last_crop_width() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.LAST_CROP_WIDTH);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return 1;
        }
    }

    public virtual void set_last_crop_width(int choice) {
        try {
            get_engine().set_int_property(ConfigurableProperty.LAST_CROP_WIDTH, choice);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // last used service
    //
    public virtual string get_last_used_service() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.LAST_USED_SERVICE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            // in the event we can't get a reasonable value from the configuration engine, we
            // return the empty string since it won't match the name of any existing publishing
            // service -- this will cause the publishing subsystem to select the first service
            // loaded that supports the user's media type
            return "";
        }
    }
    
    public virtual void set_last_used_service(string service_name) {
        try {
            get_engine().set_string_property(ConfigurableProperty.LAST_USED_SERVICE, service_name);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // last used import service
    //
    public virtual string get_last_used_dataimports_service() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.LAST_USED_DATAIMPORTS_SERVICE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            // in the event we can't get a reasonable value from the configuration engine, we
            // return the empty string since it won't match the name of any existing import
            // service -- this will cause the import subsystem to select the first service
            // loaded
            return "";
        }
    }
    
    public virtual void set_last_used_dataimports_service(string service_name) {
        try {
            get_engine().set_string_property(ConfigurableProperty.LAST_USED_DATAIMPORTS_SERVICE, service_name);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // library photos sort
    //
    public virtual void get_library_photos_sort(out bool sort_order, out int sort_by) {
        sort_order = false;
        sort_by = 2;
        try {
            sort_order = get_engine().get_bool_property(
                ConfigurableProperty.LIBRARY_PHOTOS_SORT_ASCENDING);
            sort_by = get_engine().get_int_property(ConfigurableProperty.LIBRARY_PHOTOS_SORT_BY);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    public virtual void set_library_photos_sort(bool sort_order, int sort_by) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.LIBRARY_PHOTOS_SORT_ASCENDING,
                sort_order);
            get_engine().set_int_property(ConfigurableProperty.LIBRARY_PHOTOS_SORT_BY,
                sort_by);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // library window state
    //
    public virtual void get_library_window_state(out bool maximize, out Dimensions dimensions) {
        maximize = false;
        dimensions = Dimensions(1024, 768);
        try {
            maximize = get_engine().get_bool_property(ConfigurableProperty.LIBRARY_WINDOW_MAXIMIZE);
            int w = get_engine().get_int_property(ConfigurableProperty.LIBRARY_WINDOW_WIDTH);
            int h = get_engine().get_int_property(ConfigurableProperty.LIBRARY_WINDOW_HEIGHT);
            dimensions = Dimensions(w, h);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    public virtual void set_library_window_state(bool maximize, Dimensions dimensions) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.LIBRARY_WINDOW_MAXIMIZE, maximize);
            get_engine().set_int_property(ConfigurableProperty.LIBRARY_WINDOW_WIDTH,
                dimensions.width);
            get_engine().set_int_property(ConfigurableProperty.LIBRARY_WINDOW_HEIGHT,
                dimensions.height);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // modify originals
    //
    public virtual bool get_modify_originals() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.MODIFY_ORIGINALS);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            // if we can't get a reasonable value from the configuration engine, don't modify
            // originals
            return false;
        }
    }
    
    public virtual void set_modify_originals(bool modify_originals) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.MODIFY_ORIGINALS, modify_originals);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // photo thumbnail scale
    //
    public virtual int get_photo_thumbnail_scale() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.PHOTO_THUMBNAIL_SCALE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
            return Thumbnail.DEFAULT_SCALE;
        }
    }

    public virtual void set_photo_thumbnail_scale(int scale) {
        try {
            get_engine().set_int_property(ConfigurableProperty.PHOTO_THUMBNAIL_SCALE, scale);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // printing content height
    //
    public virtual double get_printing_content_height() {
        try {
            return get_engine().get_double_property(ConfigurableProperty.PRINTING_CONTENT_HEIGHT);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 5.0;
        }
    }

    public virtual void set_printing_content_height(double content_height) {
        try {
            get_engine().set_double_property(ConfigurableProperty.PRINTING_CONTENT_HEIGHT,
                content_height);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // printing content layout
    //
    public virtual int get_printing_content_layout() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.PRINTING_CONTENT_LAYOUT) - 1;
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0;
        }
    }

    public virtual void set_printing_content_layout(int layout_code) {
        try {
            get_engine().set_int_property(ConfigurableProperty.PRINTING_CONTENT_LAYOUT,
                layout_code + 1);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // printing content ppi
    //
    public virtual int get_printing_content_ppi() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.PRINTING_CONTENT_PPI);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 600;
        }
    }
    
    public virtual void set_printing_content_ppi(int content_ppi) {
        try {
            get_engine().set_int_property(ConfigurableProperty.PRINTING_CONTENT_PPI, content_ppi);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // printing content units
    //
    public virtual int get_printing_content_units() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.PRINTING_CONTENT_UNITS) - 1;
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0;
        }
    }
    
    public virtual void set_printing_content_units(int units_code) {
        try {
            get_engine().set_int_property(ConfigurableProperty.PRINTING_CONTENT_UNITS,
                units_code + 1);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // printing content width
    //
    public virtual double get_printing_content_width() {
        try {
            return get_engine().get_double_property(ConfigurableProperty.PRINTING_CONTENT_WIDTH);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 7.0;
        }
    }
    
    public virtual void set_printing_content_width(double content_width) {
        try {
            get_engine().set_double_property(ConfigurableProperty.PRINTING_CONTENT_WIDTH,
                content_width);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    
    //
    // printing images per page
    //
    public virtual int get_printing_images_per_page() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.PRINTING_IMAGES_PER_PAGE) - 1;
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0;
        }
    }
    
    public virtual void set_printing_images_per_page(int images_per_page_code) {
        try {
            get_engine().set_int_property(ConfigurableProperty.PRINTING_IMAGES_PER_PAGE,
                images_per_page_code + 1);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // printing match aspect ratio
    //
    public virtual bool get_printing_match_aspect_ratio() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.PRINTING_MATCH_ASPECT_RATIO);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return true;
        }
    }
    
    public virtual void set_printing_match_aspect_ratio(bool match_aspect_ratio) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.PRINTING_MATCH_ASPECT_RATIO,
                match_aspect_ratio);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // printing print titles
    //
    public virtual bool get_printing_print_titles() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.PRINTING_PRINT_TITLES);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_printing_print_titles(bool print_titles) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.PRINTING_PRINT_TITLES,
                print_titles);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // printing size selection
    //
    public virtual int get_printing_size_selection() {
        try {
            var val = get_engine().get_int_property(ConfigurableProperty.PRINTING_SIZE_SELECTION) - 1;
            if (val == -2) {
                if (Resources.get_default_measurement_unit() == Resources.UnitSystem.IMPERIAL) {
                    val = 2;
                } else {
                    val = 10;
                }
            }

            return val;
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0;
        }
    }
    
    public virtual void set_printing_size_selection(int size_code) {
        try {
            get_engine().set_int_property(ConfigurableProperty.PRINTING_SIZE_SELECTION,
                size_code + 1);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // printing titles font
    //
    public virtual string get_printing_titles_font() {
        try {
            return get_engine().get_string_property(ConfigurableProperty.PRINTING_TITLES_FONT);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            // in the event we can't get a reasonable value from the configuration engine, just
            // use the system default Sans Serif font
            return "Sans Bold 12";
        }
    }
    
    public virtual void set_printing_titles_font(string font_name) {
        try {
            get_engine().set_string_property(ConfigurableProperty.PRINTING_TITLES_FONT, font_name);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // show welcome dialog
    //
    public virtual bool get_show_welcome_dialog() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.SHOW_WELCOME_DIALOG);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return true;
        }
    }

    public virtual void set_show_welcome_dialog(bool show) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.SHOW_WELCOME_DIALOG,
                show);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // sidebar position
    //
    public virtual int get_sidebar_position() {
        try {
            return get_engine().get_int_property(ConfigurableProperty.SIDEBAR_POSITION);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 180;
        }
    }
    
    public virtual void set_sidebar_position(int position) {
        try {
            get_engine().set_int_property(ConfigurableProperty.SIDEBAR_POSITION, position);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // slideshow delay
    //
    public virtual double get_slideshow_delay() {
        try {
            return get_engine().get_double_property(ConfigurableProperty.SLIDESHOW_DELAY);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 3.0;
        }
    }
    
    public virtual void set_slideshow_delay(double delay) {
        try {
            get_engine().set_double_property(ConfigurableProperty.SLIDESHOW_DELAY, delay);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // slideshow transition delay
    //
    public virtual double get_slideshow_transition_delay() {
        try {
            return get_engine().get_double_property(
                ConfigurableProperty.SLIDESHOW_TRANSITION_DELAY);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return 0.3;
        }
    }
    
    public virtual void set_slideshow_transition_delay(double delay) {
        try {
            get_engine().set_double_property(ConfigurableProperty.SLIDESHOW_TRANSITION_DELAY,
                delay);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    
    //
    // slideshow transition effect id
    //
    public virtual string get_slideshow_transition_effect_id() {
        try {
            return get_engine().get_string_property(
                ConfigurableProperty.SLIDESHOW_TRANSITION_EFFECT_ID);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            // in the event we can't get a reasonable value from the configuration engine, use
            // the null transition effect
            return TransitionEffectsManager.NULL_EFFECT_ID;
        }
    }
    
    public virtual void set_slideshow_transition_effect_id(string id) {
        try {
            get_engine().set_string_property(ConfigurableProperty.SLIDESHOW_TRANSITION_EFFECT_ID,
                id);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    
    //
    // Slideshow show title
    //
    public virtual bool get_slideshow_show_title() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.SLIDESHOW_SHOW_TITLE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_slideshow_show_title(bool show_title) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.SLIDESHOW_SHOW_TITLE, show_title);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }
    
    //
    // use 24 hour time
    //
    public virtual bool get_use_24_hour_time() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.USE_24_HOUR_TIME);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            // if we can't get a reasonable value from the configuration system, then use the
            // operating system default for the user's country and region.
            return is_string_empty(Time.local(0).format("%p"));
        }
    }
    
    public virtual void set_use_24_hour_time(bool use_24_hour_time) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.USE_24_HOUR_TIME, use_24_hour_time);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // use lowercase filenames
    //
    public virtual bool get_use_lowercase_filenames() {
        try {
            return get_engine().get_bool_property(ConfigurableProperty.USE_LOWERCASE_FILENAMES);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return false;
        }
    }
    
    public virtual void set_use_lowercase_filenames(bool b) {
        try {
            get_engine().set_bool_property(ConfigurableProperty.USE_LOWERCASE_FILENAMES, b);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // video interpreter state cookie
    //
    public virtual int get_video_interpreter_state_cookie() {
        try {
            return get_engine().get_int_property(
                ConfigurableProperty.VIDEO_INTERPRETER_STATE_COOKIE);
        } catch (ConfigurationError err) {
            on_configuration_error(err);

            return -1;
        }
    }

    public virtual void set_video_interpreter_state_cookie(int state_cookie) {
        try {
            get_engine().set_int_property(ConfigurableProperty.VIDEO_INTERPRETER_STATE_COOKIE,
                state_cookie);
        } catch (ConfigurationError err) {
            on_configuration_error(err);
        }
    }

    //
    // allow plugins to get & set arbitrary properties
    //
    public virtual bool get_plugin_bool(string domain, string id, string key, bool def) {
        return get_engine().get_plugin_bool(domain, id, key, def);
    }
    
    public virtual void set_plugin_bool(string domain, string id, string key, bool val) {
        get_engine().set_plugin_bool(domain, id, key, val);
    }
    
    public virtual double get_plugin_double(string domain, string id, string key, double def) {
        return get_engine().get_plugin_double(domain, id, key, def);
    }
    
    public virtual void set_plugin_double(string domain, string id, string key, double val) {
        get_engine().set_plugin_double(domain, id, key, val);
    }
    
    public virtual int get_plugin_int(string domain, string id, string key, int def) {
        return get_engine().get_plugin_int(domain, id, key, def);
    }
    
    public virtual void set_plugin_int(string domain, string id, string key, int val) {
        get_engine().set_plugin_int(domain, id, key, val);
    }
    
    public virtual string? get_plugin_string(string domain, string id, string key, string? def) {
        string? result = get_engine().get_plugin_string(domain, id, key, def);
        return (result == "") ? null : result;
    }
    
    public virtual void set_plugin_string(string domain, string id, string key, string? val) {
        if (val == null)
            val = "";

        get_engine().set_plugin_string(domain, id, key, val);
    }
    
    public virtual void unset_plugin_key(string domain, string id, string key) {
        get_engine().unset_plugin_key(domain, id, key);
    }

    //
    // enable & disable plugins
    //
    public virtual FuzzyPropertyState is_plugin_enabled(string id) {
        return get_engine().is_plugin_enabled(id);
    }
    
    public virtual void set_plugin_enabled(string id, bool enabled) {
        get_engine().set_plugin_enabled(id, enabled);
    }
}
