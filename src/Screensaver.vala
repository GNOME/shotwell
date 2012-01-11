/* Copyright 2009-2012 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

[DBus (name="org.gnome.ScreenSaver")]
interface ScreensaverControl : Object {
    public abstract void Inhibit(string app, string reason, out uint32 cookie) throws IOError;
    
    public abstract void UnInhibit(uint32 cookie) throws IOError;
}

public class Screensaver {
    private ScreensaverControl? ctrl = null;
    private uint32 cookie = 0;
    
    public Screensaver() {
        try {
            ctrl = Bus.get_proxy_sync(BusType.SESSION, "org.gnome.ScreenSaver",
                "/org/gnome/ScreenSaver");
        } catch (IOError ioe) {
            warning("Unable to obtain connection to screensaver control: %s", ioe.message);
        }
    }
    
    public void inhibit(string reason) {
        if (ctrl == null || cookie != 0)
            return;
        
        try {
            ctrl.Inhibit("Shotwell", reason, out cookie);
        } catch (IOError ioe) {
            warning("Unable to inhibit screensaver: %s", ioe.message);
        }
    }
    
    public void uninhibit() {
        if (ctrl == null || cookie == 0)
            return;
        
        try {
            ctrl.UnInhibit(cookie);
        } catch (IOError ioe) {
            warning("Unable to uninhibit screensaver: %s", ioe.message);
        }
        
        cookie = 0;
    }
}

