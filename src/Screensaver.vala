/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// TODO: implement X11 and windows-specific methods for enable/disable
#if !WINDOWS
public class Screensaver {
    private DBus.Connection conn = null;
    private dynamic DBus.Object bus = null;
    private uint32 cookie = 0;

    public Screensaver() {
        try {
            conn = DBus.Bus.get(DBus.BusType.SESSION);

            bus = conn.get_object("org.gnome.ScreenSaver", "/org/gnome/ScreenSaver",
                "org.gnome.ScreenSaver");
        } catch (DBus.Error error) {
            warning("D-Bus error: %s\n", error.message); 
        }
    }
    
    public void inhibit(string reason) {
        if (bus == null || cookie != 0)
            return;

        bus.Inhibit("Shotwell", reason, out cookie);
    }
    
    public void uninhibit() {
        if (bus == null || cookie == 0)
            return;

        bus.UnInhibit(cookie);
        cookie = 0;
    }
}
#endif
