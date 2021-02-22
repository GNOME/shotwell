/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/message_pane.ui")]
private class PageMessagePane : Gtk.Box {
    [GtkChild]
    public unowned Gtk.Label label;

    [GtkChild]
    public unowned Gtk.Image icon_image;

    public PageMessagePane() {
        Object();
    }
}

