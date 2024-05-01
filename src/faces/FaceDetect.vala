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

// DBus face_detect_proxy definition
public struct FaceRect {
    public double x;
    public double y;
    public double width;
    public double height;
    public double[] vec;
}

[DBus (name = "org.gnome.Shotwell.Faces1")]
public interface FaceDetectInterface : DBusProxy {
    public abstract async FaceRect[] detect_faces(string inputName, string cascadeName, double scale, bool infer, Cancellable? cancellable)
        throws IOError, DBusError;
    public abstract bool load_net(string netFile)
        throws IOError, DBusError;
    public abstract void terminate() throws IOError, DBusError;
}

// Class to communicate with facedetect process over DBus
public class FaceDetect {
    public const string DBUS_NAME = "org.gnome.Shotwell.Faces1";
    public const string DBUS_PATH = "/org/gnome/shotwell/faces";
    public static bool connected = false;
    public static string net_file;
    public const string ERROR_MESSAGE = "Unable to connect to facedetect service";
    
    public static FaceDetectInterface face_detect_proxy;

#if FACEDETECT_BUS_PRIVATE
    private static GLib.DBusServer dbus_server;
    private static Subprocess process;
#endif

    public static void create_face_detect_proxy(DBusConnection connection, string bus_name, string owner) {
        if (bus_name == DBUS_NAME) {
            message("Dbus name %s available", bus_name);

            try {
                // Service file should automatically run the facedetect binary
                face_detect_proxy = Bus.get_proxy_sync (BusType.SESSION, DBUS_NAME, DBUS_PATH);
                face_detect_proxy.load_net(net_file);
                connected = true;
            } catch(IOError e) {
                AppWindow.error_message(ERROR_MESSAGE);
            } catch(DBusError e) {
                AppWindow.error_message(ERROR_MESSAGE);
            }
        }
    }

    public static void interface_gone(DBusConnection connection, string bus_name) {
        message("Dbus name %s gone", bus_name);
        connected = false;
        face_detect_proxy = null;
    }

#if FACEDETECT_BUS_PRIVATE
    private static bool on_new_connection(DBusServer server, DBusConnection connection) {
        try {
            face_detect_proxy = connection.get_proxy_sync(null, DBUS_PATH,
                                                  DBusProxyFlags.DO_NOT_LOAD_PROPERTIES
                                                  | DBusProxyFlags.DO_NOT_CONNECT_SIGNALS,
                                                  null);
            Idle.add(() => {
                try {
                    face_detect_proxy.load_net(net_file);
                    connected = true;
                } catch (Error error) {
                    critical("Failed to call load_net: %s", error.message);
                    AppWindow.error_message(ERROR_MESSAGE);
                }
                return false;
            });

            return true;
        } catch (Error error) {
            critical("Failed to create face_detect_proxy for face detect: %s", error.message);
            AppWindow.error_message(ERROR_MESSAGE);

            return false;
        }
    }
#endif
    
    public static void init(string net_file) {
        FaceDetect.net_file = net_file;
#if FACEDETECT_BUS_PRIVATE
        var address = "unix:tmpdir=%s".printf(Environment.get_tmp_dir());
        var observer = new DBusAuthObserver();
        observer.authorize_authenticated_peer.connect((stream, credentials) => {
            debug("Observer trying to authorize for %s", credentials.to_string());
            if (credentials == null)
                return false;

            try {
                if (!credentials.is_same_user(new Credentials()))
                    return false;
                return true;
            } catch (Error error) {
                return false;
            }
        });

        try {
            dbus_server = new GLib.DBusServer.sync(address, DBusServerFlags.NONE, DBus.generate_guid(), observer, null);
            dbus_server.new_connection.connect(on_new_connection);
            dbus_server.start();
            process = new Subprocess(SubprocessFlags.NONE, AppDirs.get_facedetect_bin().get_path(),
            "--address=" + dbus_server.get_client_address());

        } catch (Error error) {
            warning("Failed to create private DBus server: %s", error.message);
            AppWindow.error_message(ERROR_MESSAGE);
        }
#else
        Bus.watch_name(BusType.SESSION, DBUS_NAME, BusNameWatcherFlags.NONE,
                       create_face_detect_proxy, interface_gone);
#endif
    }

}
