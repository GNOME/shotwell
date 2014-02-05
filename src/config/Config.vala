/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* This file is the master unit file for the Config unit.  It should be edited to include
 * whatever code is deemed necessary.
 *
 * The init() and terminate() methods are mandatory.
 *
 * If the unit needs to be configured prior to initialization, add the proper parameters to
 * the preconfigure() method, implement it, and ensure in init() that it's been called.
 */

namespace Config {

public class Facade : ConfigurationFacade {
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

    private const double BLACK_THRESHOLD = 0.61;
    private const string DARK_SELECTED_COLOR = "#0AD";
    private const string LIGHT_SELECTED_COLOR = "#2DF";
    private const string DARK_UNSELECTED_COLOR = "#000";
    private const string LIGHT_UNSELECTED_COLOR = "#FFF";
    private const string DARK_BORDER_COLOR = "#999";
    private const string LIGHT_BORDER_COLOR = "#AAA";
    private const string DARK_UNFOCUSED_SELECTED_COLOR = "#6fc4dd";
    private const string LIGHT_UNFOCUSED_SELECTED_COLOR = "#99efff";
    
    private string bg_color = null;
    private string selected_color = null;
    private string unselected_color = null;
    private string unfocused_selected_color = null;
    private string border_color = null;
    
    private static Facade instance = null;

    public signal void colors_changed();

    private Facade() {
        base(new GSettingsConfigurationEngine());

        bg_color_name_changed.connect(on_color_name_changed);
    }
    
    public static Facade get_instance() {
        if (instance == null)
            instance = new Facade();
        
        return instance;
    }
    
    private void on_color_name_changed() {
        colors_changed();
    }

    private void set_text_colors(Gdk.RGBA bg_color) {
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

    private void get_colors() {
        bg_color = base.get_bg_color_name();
        
        if (!is_color_parsable(bg_color))
            bg_color = DEFAULT_BG_COLOR;

        set_text_colors(parse_color(bg_color));
    }

    public Gdk.RGBA get_bg_color() {
        if (is_string_empty(bg_color))
            get_colors();

        return parse_color(bg_color);
    }

    public Gdk.RGBA get_selected_color(bool in_focus = true) {
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
    
    public Gdk.RGBA get_unselected_color() {
        if (is_string_empty(unselected_color))
            get_colors();

        return parse_color(unselected_color);
    }

    public Gdk.RGBA get_border_color() {
        if (is_string_empty(border_color))
            get_colors();

        return parse_color(border_color);
    }
    
    public void set_bg_color(Gdk.RGBA color) {
        uint8 col_tmp = (uint8) (color.red * 255.0);
        
        bg_color = "#%02X%02X%02X".printf(col_tmp, col_tmp, col_tmp);
        set_bg_color_name(bg_color);
        
        set_text_colors(color);
    }
    
    public void commit_bg_color() {
        base.set_bg_color_name(bg_color);
    }
}

// preconfigure may be deleted if not used.
public void preconfigure() {
}

public void init() throws Error {
}

public void terminate() {
}

}

