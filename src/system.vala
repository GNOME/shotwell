/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if NO_LIBUNIQUE
extern bool already_running();
#endif

#if NO_EXTENDED_POSIX
extern int number_of_processors();
#else
int number_of_processors() {
    int n = (int) ExtendedPosix.sysconf(ExtendedPosix.ConfName._SC_NPROCESSORS_ONLN) - 1;
    return n <= 0 ? 1 : n;
}
#endif

#if WINDOWS
void win_init(File exec_dir) {
    // On Windows we prepend the directory containing the Shotwell executable to the PATH.
    // This is necessary so that the gconf-d executable (which lives in ../libexec) will
    // be able to find the DLLs it needs, which are in the Shotwell executable directory.
    string path = Environment.get_variable("PATH");
    if (path == null)
        error("can't get path");
    if (!Environment.set_variable("PATH", exec_dir.get_path() + ";" + path, true))
        error("can't set path");
}

// Return the directory in which Shotwell is installed, or null if uninstalled.
File? get_sys_install_dir(File exec_dir) {
    File install_dir = File.new_for_path(
        Win32.get_package_installation_directory_of_module(null));
    return install_dir.equal(exec_dir) ? null : install_dir;
}

extern void sys_show_uri(void *screen, string uri) throws Error;

#else
// Return the directory in which Shotwell is installed, or null if uninstalled.
File? get_sys_install_dir(File exec_dir) {
    File prefix_dir = File.new_for_path(Resources.PREFIX);
    return exec_dir.has_prefix(prefix_dir) ? prefix_dir : null;
}

void sys_show_uri(Gdk.Screen screen, string uri) throws Error {
    Gtk.show_uri(screen, uri, Gdk.CURRENT_TIME);
}
#endif

