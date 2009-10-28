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
// Return the directory in which Shotwell is installed, or null if uninstalled.
File? get_install_dir(File exec_dir) {
    File install_dir = File.new_for_path(
        Win32.get_package_installation_directory_of_module(null));
    return install_dir.equal(exec_dir) ? null : install_dir;
}
#else
// Return the directory in which Shotwell is installed, or null if uninstalled.
File? get_install_dir(File exec_dir) {
    File prefix_dir = File.new_for_path(Resources.PREFIX);
    return exec_dir.has_prefix(prefix_dir) ? prefix_dir : null;
}
#endif

