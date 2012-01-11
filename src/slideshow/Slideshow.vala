/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Slideshow {

public void init() throws Error {
    string[] core_ids = new string[0];
    core_ids += "org.yorba.shotwell.transitions.crumble";
    core_ids += "org.yorba.shotwell.transitions.fade";
    core_ids += "org.yorba.shotwell.transitions.slide";
    
    Plugins.register_extension_point(typeof(Spit.Transitions.Descriptor), _("Slideshow Transitions"),
        Resources.ICON_SLIDESHOW_EXTENSION_POINT, core_ids);
    TransitionEffectsManager.init();
}

public void terminate() {
    TransitionEffectsManager.terminate();
}

}

