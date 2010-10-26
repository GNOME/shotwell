/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Config {
    public const double SLIDESHOW_DELAY_MAX = 30.0;
    public const double SLIDESHOW_DELAY_MIN = 1.0;
    public const double SLIDESHOW_DELAY_DEFAULT = 3.0;
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
    
    public signal void colors_changed();
    public signal void external_app_changed();
    
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

    public bool set_picasa_default_size(int default_size) {
        return set_int("/apps/shotwell/sharing/picasa/default_size", default_size + 1);
    }

    public int get_picasa_default_size() {
        return get_int("/apps/shotwell/sharing/picasa/default_size", 3) - 1;
    }

    public string? get_publishing_string(string id, string key) {
        return get_string(_("/apps/shotwell/sharing/%s/%s").printf(id, key));
    }

    public void set_publishing_string(string id, string key, string value) {
        set_string(_("/apps/shotwell/sharing/%s/%s").printf(id, key), value);
    }
    
    public void unset_publishing_string(string id, string key) {
	try {
		client.recursive_unset(_("/apps/shotwell/sharing/%s/%s").printf(id, key), GConf.UnsetFlags.NAMES);
	} catch (GLib.Error err) {
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

    public RatingFilter get_photo_rating_filter() {
        return (RatingFilter)(get_int("/apps/shotwell/preferences/ui/photo_rating_filter", 
            RatingFilter.UNRATED_OR_HIGHER));
    }

    public bool set_photo_rating_filter(RatingFilter filter) {
        return set_int("/apps/shotwell/preferences/ui/photo_rating_filter", filter);
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
        sort_by = get_int("/apps/shotwell/preferences/ui/library_photos_sort_by", MediaPage.SortBy.EXPOSURE_DATE);
    }
    
    public bool set_library_photos_sort(bool sort_order, int sort_by) {
        return set_bool("/apps/shotwell/preferences/ui/library_photos_sort_ascending", sort_order) &&
             set_int("/apps/shotwell/preferences/ui/library_photos_sort_by", sort_by);
    }

    public void get_event_photos_sort(out bool sort_order, out int sort_by) {
        sort_order = get_bool("/apps/shotwell/preferences/ui/event_photos_sort_ascending", true);
        sort_by = get_int("/apps/shotwell/preferences/ui/event_photos_sort_by", MediaPage.SortBy.EXPOSURE_DATE);
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

#if !NO_SET_BACKGROUND
    public string get_background() {
        return get_string("/desktop/gnome/background/picture_filename", null);
    }

    public bool set_background(string filename) {
        if (!set_string("/desktop/gnome/background/picture_options", "zoom"))
            return false;
        return set_string("/desktop/gnome/background/picture_filename", filename);
    }
#endif
    
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
        return set_string("/apps/shotwell/preferences/ui/background_color", bg_color);
    }

    public string get_import_dir() {
        return get_string("/apps/shotwell/preferences/files/import_dir", null);
    }
    
    public void set_import_dir(string import_dir) {
        set_string("/apps/shotwell/preferences/files/import_dir", import_dir);
    }
    
    public string get_external_photo_app() {
        string external_app = get_string("/apps/shotwell/preferences/editing/external_photo_editor", "");
        
        if (!is_string_empty(external_app))
            return external_app;
        
        Gee.ArrayList<string> preferred_apps = new Gee.ArrayList<string>();
        preferred_apps.add("GIMP");
        
        AppInfo? app = get_default_app_for_mime_types(PhotoFileFormat.get_editable_mime_types(), preferred_apps);
        return (app != null) ? get_app_open_command(app) : "";            
    }
    
    public void set_external_photo_app(string external_photo_app) {
        set_string("/apps/shotwell/preferences/editing/external_photo_editor",
            external_photo_app);
        external_app_changed();
    }

#if !NO_RAW
    public string get_external_raw_app() {
        string external_app = get_string("/apps/shotwell/preferences/editing/external_raw_editor", "");
        
        if (!is_string_empty(external_app))
            return external_app;
        
        Gee.ArrayList<string> preferred_apps = new Gee.ArrayList<string>();
        preferred_apps.add("UFRaw");
        
        AppInfo? app = get_default_app_for_mime_types(PhotoFileFormat.RAW.get_mime_types(), preferred_apps);
        return (app != null) ? get_app_open_command(app) : "";  
    }
#endif

    public void set_external_raw_app(string external_raw_app) {
        set_string("/apps/shotwell/preferences/editing/external_raw_editor", external_raw_app);
        external_app_changed();
    }
}
