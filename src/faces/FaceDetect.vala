/**
 * Face detection and recognition functions
 * Copyright 2018 Narendra A (narendra_m_a(at)yahoo(dot)com)
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// DBus interface definition
public struct FaceRect {
    public double x;
    public double y;
    public double width;
    public double height;
}

[DBus (name = "org.gnome.Shotwell.Faces1")]
public interface FaceDetectInterface : Object {
    public abstract FaceRect[] detect_faces(string inputName, string cascadeName, double scale)
        throws IOError, DBusError;
    public abstract bool load_net(string netFile)
        throws IOError, DBusError;
    public abstract bool face_to_vec(string inputName)
        throws IOError, DBusError;
    public abstract void terminate() throws IOError, DBusError;
}

// Class to communicate with facedetect process over DBus
public class FaceDetect {
    public const string DBUS_NAME = "org.gnome.shotwell.faces";
    public const string DBUS_PATH = "/org/gnome/shotwell/faces";
    public static bool connected = false;
    public static string net_file;
    
    public static FaceDetectInterface interface;

    public static void create_interface(DBusConnection connection, string bus_name, string owner) {
        message("Dbus name %s available", bus_name);
        if (bus_name == DBUS_NAME) {
            try {
                interface = Bus.get_proxy_sync (BusType.SESSION, DBUS_NAME, DBUS_PATH);
                interface.load_net(net_file);
                connected = true;
            } catch(IOError e) {
            } catch(DBusError e) {
            }
        }
    }

    public static void interface_gone(DBusConnection connection, string bus_name) {
        message("Dbus name %s gone", bus_name);
        connected = false;
    }
    
    public static void init(string net_file) {
        FaceDetect.net_file = net_file;
        Bus.watch_name(BusType.SESSION, DBUS_NAME, BusNameWatcherFlags.NONE,
                       create_interface, interface_gone);
    }
}
