/* SPDX-FileCopyrightText: 2016 Software Freedom Conservancy Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later
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

