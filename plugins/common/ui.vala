/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


Gtk.Widget gtk_vspacer(int pixels) {
    Gtk.Box b = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
    b.set_size_request(-1, pixels);
    return b;   
}
