/* SPDX-FileCopyrightText: 2016 Software Freedom Conservancy Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

public class Screensaver {
    private uint32 cookie = 0;
    
    public Screensaver() {
    }
    
    public void inhibit(string reason) {
        if (cookie != 0)
            return;

        cookie = Application.get_instance().inhibit(
            Gtk.ApplicationInhibitFlags.IDLE | Gtk.ApplicationInhibitFlags.SUSPEND, reason);
    }
    
    public void uninhibit() {
        if (cookie == 0)
            return;
        
        Application.get_instance().uninhibit(cookie);
        cookie = 0;
    }
}

