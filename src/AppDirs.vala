/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

class AppDirs {
    private const string DEFAULT_DATA_DIR = "shotwell";
    
    private static File exec_dir;
    private static File data_dir = null;
    private static File tmp_dir = null;
    private static File libexec_dir = null;
    
    // Because this is called prior to Debug.init(), this function cannot do any logging calls
    public static void init(string arg0) {
        File exec_file = File.new_for_path(Posix.realpath(Environment.find_program_in_path(arg0)));
        exec_dir = exec_file.get_parent();
    }
    
    // Because this *may* be called prior to Debug.init(), this function cannot do any logging
    // calls
    public static void terminate() {
    }
    
    public static File get_home_dir() {
        return File.new_for_path(Environment.get_home_dir());
    }

    public static File get_cache_dir() {
        return ((data_dir == null) ?
            File.new_for_path(Environment.get_user_cache_dir()).get_child(DEFAULT_DATA_DIR) :
            data_dir);
    }
    
    public static void try_migrate_data() {
        // Migrate the user plugin dir from .gnome2 to .local
        File user_plugin_dir = get_user_plugins_dir();
        File old_dir =
            get_home_dir().get_child(".gnome2").get_child("shotwell").get_child("plugins");

        if (old_dir.query_exists() && !user_plugin_dir.get_parent().query_exists()) {
            try {
              user_plugin_dir.get_parent().make_directory_with_parents(null);
            } catch (Error err) { }
        }

        try {
            old_dir.move(user_plugin_dir, FileCopyFlags.NONE);
        } catch (Error err) { }


        File new_dir = get_data_dir();
        old_dir = get_home_dir().get_child(".shotwell");
        if (new_dir.query_exists() || !old_dir.query_exists())
            return;

        File cache_dir = get_cache_dir();
        Posix.mode_t mask = Posix.umask(0077);
        if (!cache_dir.query_exists()) {
            try {
                cache_dir.make_directory_with_parents(null);
            } catch (Error err) {
                AppWindow.panic(_("Unable to create cache directory %s: %s").printf(cache_dir.get_path(),
                                                                                    err.message));
            }
        }
        GLib.FileUtils.rename(old_dir.get_child("thumbs").get_path(), cache_dir.get_child("thumbs").get_path());

        if (!new_dir.get_parent().query_exists()) {
            try {
              new_dir.get_parent().make_directory_with_parents(null);
            } catch (Error err) {
                AppWindow.panic(_("Unable to create data directory %s: %s").printf(new_dir.get_parent().get_path(),
                                                                                   err.message));
            }
        }
        GLib.FileUtils.rename(old_dir.get_path(), new_dir.get_path());
        GLib.FileUtils.chmod(new_dir.get_path(), 0700);

        Posix.umask(mask);
    }

    // This can only be called once, and it better be called at startup
    public static void set_data_dir(string user_data_dir) requires (!is_string_empty(user_data_dir)) {
        assert(data_dir == null);
        
        // fix up to absolute path
        string path = strip_pretty_path(user_data_dir);
        if (!Path.is_absolute(path))
            data_dir = get_home_dir().get_child(path);
        else
            data_dir = File.new_for_path(path);
        
        message("Setting private data directory to %s", data_dir.get_path());
    }
    
    public static void verify_data_dir() {
        File data_dir = get_data_dir();
        try {
            if (!data_dir.query_exists(null))
                data_dir.make_directory_with_parents(null);
        } catch (Error err) {
            AppWindow.panic(_("Unable to create data directory %s: %s").printf(data_dir.get_path(),
                err.message));
        }
    }
    
    public static void verify_cache_dir() {
        File cache_dir = get_cache_dir();
        try {
            if (!cache_dir.query_exists(null))
                cache_dir.make_directory_with_parents(null);
        } catch (Error err) {
            AppWindow.panic(_("Unable to create cache directory %s: %s").printf(cache_dir.get_path(),
                err.message));
        }
    }
    
    /**
     * @brief Returns the build directory if not installed yet, or a path
     * to where any helper applets we need will live if installed.
     */
    public static File get_libexec_dir() {
        if (libexec_dir == null) {
            if (get_install_dir() == null) {
                // not installed yet - use wherever we were run from
                libexec_dir = get_exec_dir();
            } else {
                libexec_dir = File.new_for_path(Resources.LIBEXECDIR);
            }
        }

        return libexec_dir;
    }

    // Return the directory in which Shotwell is installed, or null if uninstalled.
    public static File? get_install_dir() {
        return get_sys_install_dir(exec_dir);
    }
    
    public static File get_data_dir() {
        return (data_dir == null) ? File.new_for_path(Environment.get_user_data_dir()).get_child(DEFAULT_DATA_DIR) : data_dir;
    }
    
    // The "import directory" is the same as the library directory, and are often used
    // interchangeably throughout the code.
    public static File get_import_dir() {
        string path = Config.Facade.get_instance().get_import_dir();
        if (!is_string_empty(path)) {
            // tilde -> home directory
            path = strip_pretty_path(path);
            
            // if non-empty and relative, make it relative to the user's home directory
            if (!Path.is_absolute(path)) 
                return get_home_dir().get_child(path);
            
            // non-empty and absolute, it's golden
            return File.new_for_path(path);
        }
        
        // Empty path, use XDG Pictures directory
        path = Environment.get_user_special_dir(UserDirectory.PICTURES);
        if (!is_string_empty(path))
            return File.new_for_path(path);
        
        // If XDG yarfed, use ~/Pictures
        return get_home_dir().get_child(_("Pictures"));
    }
    
    // Library folder + photo folder, based on user's preferred directory pattern.
    public static File get_baked_import_dir(time_t tm) {
        string? pattern = Config.Facade.get_instance().get_directory_pattern();
        if (is_string_empty(pattern))
            pattern = Config.Facade.get_instance().get_directory_pattern_custom();
        if (is_string_empty(pattern))
            pattern = "%Y" + Path.DIR_SEPARATOR_S + "%m" + Path.DIR_SEPARATOR_S + "%d"; // default
            
        DateTime date = new DateTime.from_unix_local(tm);
        return File.new_for_path(get_import_dir().get_path() + Path.DIR_SEPARATOR_S + date.format(pattern));
    }
    
    // Returns true if the File is in or is equal to the library/import directory.
    public static bool is_in_import_dir(File file) {
        File import_dir = get_import_dir();
        
        return file.has_prefix(import_dir) || file.equal(import_dir);
    }

    public static void set_import_dir(string path) {
        Config.Facade.get_instance().set_import_dir(path);
    }
    
    public static File get_exec_dir() {
        return exec_dir;
    }
    
    public static File get_temp_dir() {
        if (tmp_dir == null) {
            tmp_dir = File.new_for_path(DirUtils.mkdtemp (Environment.get_tmp_dir() + "/shotwell-XXXXXX"));
            
            try {
                if (!tmp_dir.query_exists(null))
                    tmp_dir.make_directory_with_parents(null);
            } catch (Error err) {
                AppWindow.panic(_("Unable to create temporary directory %s: %s").printf(
                    tmp_dir.get_path(), err.message));
            }
        }
        
        return tmp_dir;
    }
    
    public static File get_data_subdir(string name, string? subname = null) {
        File subdir = get_data_dir().get_child(name);
        if (subname != null)
            subdir = subdir.get_child(subname);

        try {
            if (!subdir.query_exists(null))
                subdir.make_directory_with_parents(null);
        } catch (Error err) {
            AppWindow.panic(_("Unable to create data subdirectory %s: %s").printf(subdir.get_path(),
                err.message));
        }
        
        return subdir;
    }

    public static void ensure_writable(File dir) {
        if (dir.query_exists(null)) {
            try {
                FileInfo info = dir.query_info(FileAttribute.UNIX_MODE, FileQueryInfoFlags.NONE);
                uint32 mode = info.get_attribute_uint32(FileAttribute.UNIX_MODE) | 0700;
                if (!dir.set_attribute_uint32(FileAttribute.UNIX_MODE, mode, FileQueryInfoFlags.NONE)) {
                    AppWindow.panic(_("Could not make directory %s writable").printf(dir.get_path()));
                }
            } catch (Error err) {
                AppWindow.panic(_("Could not make directory %s writable: %s").printf(dir.get_path(), err.message));
            }
        }
    }

    public static File get_cache_subdir(string name, string? subname = null) {
        File subdir = get_cache_dir().get_child(name);
        ensure_writable(subdir);
        if (subname != null)
            subdir = subdir.get_child(subname);

        try {
            if (!subdir.query_exists(null))
                subdir.make_directory_with_parents(null);
        } catch (Error err) {
            AppWindow.panic(_("Unable to create data subdirectory %s: %s").printf(subdir.get_path(),
                err.message));
        }
        ensure_writable(subdir);
        return subdir;
    }
    
#if ENABLE_FACES
    public static File get_resources_dir() {
        File? install_dir = get_install_dir();
        
        return (install_dir != null) ? install_dir.get_child("share").get_child("shotwell")
            : get_exec_dir();
    }
#endif
    
    public static File get_lib_dir() {
        File? install_dir = get_install_dir();

        // Running from source tree
        if (install_dir == null) {
            // Meson build
            if (get_exec_dir().get_path().has_suffix("src")) {
                return get_exec_dir().get_parent();
            }

            return get_exec_dir();
        }
        
        return install_dir.get_child(Resources.LIB).get_child("shotwell");
    }
    
    public static File get_system_plugins_dir() {
        return get_lib_dir().get_child("plugins");
    }
    
    public static File get_user_plugins_dir() {
        return get_data_dir().get_child("plugins");
    }
    
    public static File? get_log_file() {
        if (Environment.get_variable("SHOTWELL_LOG_FILE") != null) {
            if (Environment.get_variable("SHOTWELL_LOG_FILE") == ":console:") {
                return null;
            } else {
                return File.new_for_path(Environment.get_variable("SHOTWELL_LOG_FILE"));
            }
        } else {
            return File.new_for_path(Environment.get_user_cache_dir()).
                get_child("shotwell").get_child("shotwell.log");
        }
    }
    
    public static File get_thumbnailer_bin() {
        const string filename = "shotwell-video-thumbnailer";
        File f = AppDirs.get_libexec_dir().get_child("thumbnailer").get_child (filename);
        if (!f.query_exists()) {
            // If we're running installed.
            f = AppDirs.get_libexec_dir () .get_child ("shotwell").get_child (filename);
        }

        if (!f.query_exists()) {
            f = AppDirs.get_libexec_dir().get_parent().get_child("thumbnailer").get_child(filename);
        }

        return f;
    }

    public static File get_settings_migrator_bin() {
        const string filename = "shotwell-settings-migrator";
        File f = AppDirs.get_libexec_dir().get_child ("settings-migrator").get_child (filename);
        if (!f.query_exists()) {
            // If we're running installed.
            f = AppDirs.get_libexec_dir () .get_child ("shotwell").get_child (filename);
        }
        return f;
    }

#if ENABLE_FACES
    public static File get_facedetect_bin() {
        const string filename = "shotwell-facedetect";
        File f = AppDirs.get_libexec_dir().get_parent().get_child("facedetect").get_child (filename);
        if (!f.query_exists()) {
            f = AppDirs.get_libexec_dir().get_child("shotwell").get_child(filename);
        }
        return f;
    }
    
    public static File get_haarcascade_file() {
        File f = File.new_for_path(AppDirs.get_exec_dir().get_parent().get_parent().get_child("facedetect").get_child("facedetect-haarcascade.xml").get_path());
        if (f.query_exists()) {//testing meson builddir
            return f;
        }
        return get_resources_dir().get_child("facedetect-haarcascade.xml");
    }
#endif

}

