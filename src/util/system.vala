/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

int number_of_processors() {
    int n = (int) ExtendedPosix.sysconf(ExtendedPosix.ConfName._SC_NPROCESSORS_ONLN);
    return n <= 0 ? 1 : n;
}

// Return the directory in which Shotwell is installed, or null if uninstalled.
File? get_sys_install_dir(File exec_dir) {
    // guard against exec_dir being a symlink
    File exec_dir1 = exec_dir;
    try {
        exec_dir1 = File.new_for_path(
            FileUtils.read_link("/" + FileUtils.read_link(exec_dir.get_path())));
    } catch (FileError e) {
        // exec_dir is not a symlink
    }
    File prefix_dir = File.new_for_path(Resources.PREFIX);
    return exec_dir1.has_prefix(prefix_dir) ? prefix_dir : null;
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

int posix_wexitstatus(int status) {
    return (((status) & 0xff00) >> 8);
}
