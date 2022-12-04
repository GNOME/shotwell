/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Publishing.GooglePhotos {

public class Service : Object, Spit.Pluggable, Spit.Publishing.Service {
    public Service() {}

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
                                         Spit.Publishing.CURRENT_INTERFACE);
    }

    public unowned string get_id() {
        return "org.gnome.shotwell.publishing.google-photos";
    }

    public unowned string get_pluggable_name() {
        return "Google Photos";
    }

    public Spit.PluggableInfo get_info() {
        var info = new Spit.PluggableInfo();

        info.authors = "Jens Georg";
        info.copyright = _("Copyright 2019 Jens Georg <mail@jensge.org>");
        info.icon_name = "google-photos";

        return info;
    }

    public Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host) {
        return new Publishing.GooglePhotos.Publisher(this, host);
    }

    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO |
            Spit.Publishing.Publisher.MediaType.VIDEO);
    }

    public void activation(bool enabled) {
    }
}
} // namespace GooglePhotos
