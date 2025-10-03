/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Resources {

[CCode (cname = "PLUGIN_RESOURCE_PATH")]
public extern const string RESOURCE_PATH;

public const string WEBSITE_NAME = _("Visit the Shotwell home page");
public const string WEBSITE_URL = "https://wiki.gnome.org/Apps/Shotwell";

public const string LICENSE = """
Shotwell is free software; you can redistribute it and/or modify it under the 
terms of the GNU Lesser General Public License as published by the Free 
Software Foundation; either version 2.1 of the License, or (at your option) 
any later version.

Shotwell is distributed in the hope that it will be useful, but WITHOUT 
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for 
more details.

You should have received a copy of the GNU Lesser General Public License 
along with Shotwell; if not, write to the Free Software Foundation, Inc., 
51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
""";

public const string TRANSLATORS = _("translator-credits");

public Gdk.Pixbuf[]? load_from_resource (string resource_path) {
    Gdk.Pixbuf? icon = null;
    try {
        debug ("Loading icon from %s", resource_path);
        icon = new Gdk.Pixbuf.from_resource_at_scale (resource_path, -1, 24, true);
    } catch (Error error) {
        warning ("Couldn't load icon set from %s: %s", resource_path, error.message);
    }

    if (icon != null) {
        Gdk.Pixbuf[] icon_pixbuf_set = new Gdk.Pixbuf[0];
        icon_pixbuf_set += icon;
        return icon_pixbuf_set;
    }

    return null;
}

}
