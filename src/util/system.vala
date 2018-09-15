/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Return the directory in which Shotwell is installed, or null if uninstalled.
File? get_sys_install_dir(File exec_dir) {
    // Assume that if the ui folder lives next to the binary, we runn in-tree
    File child = exec_dir.get_child("ui");

    if (!FileUtils.test(child.get_path(), FileTest.IS_DIR | FileTest.EXISTS)) {
        // If not, let's see if we are in "src" dir - meson out-of-tree build
        if (exec_dir.get_basename() == "src") {
            return null;
        }

        return File.new_for_path(Resources.PREFIX);
    }

    return null;
}

[DBus (name = "org.freedesktop.FileManager1")]
public interface org.freedesktop.FileManager1 : Object {
    public const string NAME = "org.freedesktop.FileManager1";
    public const string PATH = "/org/freedesktop/FileManager1";

    public abstract async void show_folders(string[] uris, string startup_id) throws IOError, DBusError;
    public abstract async void show_items(string[] uris, string startup_id) throws IOError, DBusError;
    public abstract async void show_item_properties(string[] uris, string startup_id) throws IOError, DBusError;
}

async void show_file_in_filemanager(File file) throws Error {
    try {
        org.freedesktop.FileManager1? manager = yield Bus.get_proxy (BusType.SESSION,
                                                                     org.freedesktop.FileManager1.NAME,
                                                                     org.freedesktop.FileManager1.PATH,
                                                                     DBusProxyFlags.DO_NOT_LOAD_PROPERTIES |
                                                                     DBusProxyFlags.DO_NOT_CONNECT_SIGNALS);
        var id = "%s_%s_%d_%s".printf(Environment.get_prgname(), Environment.get_host_name(),
                                      Posix.getpid(), TimeVal().to_iso8601());
        yield manager.show_items({file.get_uri()}, id);
    } catch (Error e) {
        warning("Failed to launch file manager using DBus, using fall-back: %s", e.message);
        Gtk.show_uri_on_window(AppWindow.get_instance(), file.get_parent().get_uri(), Gdk.CURRENT_TIME);
    }
}

