/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Return the directory in which Shotwell is installed, or null if uninstalled.
File? get_sys_install_dir(File exec_dir) {
    // Assume that if the ui folder lives next to the binary, we run in-tree
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

async void show_file_in_filemanager(File file) throws Error {
    try {
        var portal = new Xdp.Portal.initable_new();
        var parent = Xdp.parent_new_gtk(AppWindow.get_instance());
        yield portal.open_directory(parent, file.get_uri(), Xdp.OpenUriFlags.NONE, null);
    } catch (Error e) {
        warning("Failed to launch file manager using DBus, using fall-back: %s", e.message);
        Gtk.show_uri(AppWindow.get_instance(), file.get_parent().get_uri(), Gdk.CURRENT_TIME);
    }
}

