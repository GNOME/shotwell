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

string get_nautilus_install_location() {
    return Environment.find_program_in_path("nautilus");
}

void sys_show_uri(Gdk.Screen screen, string uri) throws Error {
    Gtk.show_uri(screen, uri, Gdk.CURRENT_TIME);
}

void show_file_in_nautilus(string filename) throws Error {
    GLib.Process.spawn_command_line_async(get_nautilus_install_location() + " " + filename);
}

