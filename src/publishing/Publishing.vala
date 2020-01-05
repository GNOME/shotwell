/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Publishing {

public void init() throws Error {
    string[] core_ids = new string[0];
    core_ids += "org.gnome.shotwell.publishing.flickr";
    core_ids += "org.gnome.shotwell.publishing.youtube";
    core_ids += "org.gnome.shotwell.publishing.gnome-photos";
    
    Plugins.register_extension_point(typeof(Spit.Publishing.Service), _("Publishing"),
        Resources.PUBLISH, core_ids);
}

public void terminate() {
}

}

