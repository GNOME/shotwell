/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Slideshow {

public void init() throws Error {
    string[] core_ids = new string[0];
    core_ids += "org.gnome.shotwell.transitions.crumble";
    core_ids += "org.gnome.shotwell.transitions.fade";
    core_ids += "org.gnome.shotwell.transitions.slide";
    core_ids += "org.gnome.shotwell.transitions.blinds";
    core_ids += "org.gnome.shotwell.transitions.circle";
    core_ids += "org.gnome.shotwell.transitions.circles";
    core_ids += "org.gnome.shotwell.transitions.clock";
    core_ids += "org.gnome.shotwell.transitions.stripes";
    core_ids += "org.gnome.shotwell.transitions.squares";
    core_ids += "org.gnome.shotwell.transitions.chess";
    
    Plugins.register_extension_point(typeof(Spit.Transitions.Descriptor), _("Slideshow Transitions"),
        Resources.ICON_SLIDESHOW_EXTENSION_POINT, core_ids);
    TransitionEffectsManager.init();
}

public void terminate() {
    TransitionEffectsManager.terminate();
}

}

namespace Slideshow {

private static bool _entry_initialized = false;

public void init_entry() throws Error {
    if (_entry_initialized)
        return;
    _entry_initialized = true;

    Unit.init_entry(); Plugins.init_entry();

    Slideshow.init();
}

public void terminate_entry() {


    Slideshow.terminate();

    Unit.terminate_entry(); Plugins.terminate_entry();
}

}

