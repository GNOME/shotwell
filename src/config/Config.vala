/* Copyright 2016 Software Freedom Conservancy Inc.
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
    public const int WIDTH_DEFAULT = 1024;
    public const int HEIGHT_DEFAULT = 768;
    public const int SIDEBAR_MIN_POSITION = 180;
    public const int SIDEBAR_MAX_POSITION = 1000;
    public const int NO_VIDEO_INTERPRETER_STATE = -1;


    private static Facade instance = null;

    public signal void colors_changed();

    private Facade() {
        base(new GSettingsConfigurationEngine());

        transparent_background_type_changed.connect(on_color_name_changed);
        transparent_background_color_changed.connect(on_color_name_changed);
    }
    
    public static Facade get_instance() {
        if (instance == null)
            instance = new Facade();
        
        return instance;
    }
    
    private void on_color_name_changed() {
        colors_changed();
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

