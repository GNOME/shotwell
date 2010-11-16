/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace DesktopIntegration {

private const string SENDTO_EXEC = "nautilus-sendto";

private int init_count = 0;
private bool send_to_installed = false;
private ExporterUI send_to_exporter = null;

public void init() {
    if (init_count++ != 0)
        return;
    
    send_to_installed = Environment.find_program_in_path(SENDTO_EXEC) != null;
}

public void terminate() {
    if (--init_count == 0)
        return;
}

public AppInfo? get_default_app_for_mime_types(string[] mime_types, 
    Gee.ArrayList<string> preferred_apps) {
    SortedList<AppInfo> external_apps = get_apps_for_mime_types(mime_types);
    
    foreach (string preferred_app in preferred_apps) {
        foreach (AppInfo external_app in external_apps) {
            if (external_app.get_name().contains(preferred_app))
                return external_app;
        }
    }
    
    return null;
}

// compare the app names, case insensitive
public static int64 app_info_comparator(void *a, void *b) {
    return ((AppInfo) a).get_name().down().collate(((AppInfo) b).get_name().down());
}

public SortedList<AppInfo> get_apps_for_mime_types(string[] mime_types) {
        SortedList<AppInfo> external_apps = new SortedList<AppInfo>(app_info_comparator);
        
        if (mime_types.length == 0)
            return external_apps;
        
        // 3 loops because SortedList.contains() wasn't paying nicely with AppInfo,
        // probably because it has a special equality function
        foreach (string mime_type in mime_types) {
            string content_type = g_content_type_from_mime_type(mime_type);
            if (content_type == null)
                break;
            
            foreach (AppInfo external_app in 
                AppInfo.get_all_for_type(content_type)) {
                bool already_contains = false;
                
                foreach (AppInfo app in external_apps) {
                    if (app.get_name() == external_app.get_name()) {
                        already_contains = true;
                        break;
                    }
                }
                
                // dont add Shotwell to app list
                if (!already_contains && !external_app.get_name().contains(Resources.APP_TITLE))
                    external_apps.add(external_app);
            }
        }

        return external_apps;
}

public string? get_app_open_command(AppInfo app_info) {
    string? str = app_info.get_commandline();

    return str != null ? str : app_info.get_executable();
}

public bool is_send_to_installed() {
    return send_to_installed;
}

public void files_send_to(File[] files) {
    if (files.length == 0)
        return;
    
    string[] argv = new string[files.length + 1];
    argv[0] = SENDTO_EXEC;
    
    for (int ctr = 0; ctr < files.length; ctr++)
        argv[ctr + 1] = files[ctr].get_path();
    
    try {
        AppWindow.get_instance().set_busy_cursor();
        
        Pid child_pid;
        Process.spawn_async(
            get_root_directory(),
            argv,
            null, // environment
            SpawnFlags.SEARCH_PATH,
            null, // child setup
            out child_pid);
        
        AppWindow.get_instance().set_normal_cursor();
    } catch (Error err) {
        AppWindow.get_instance().set_normal_cursor();
        AppWindow.error_message(_("Unable to launch Nautilus Send-To: %s").printf(err.message));
    }
}

public void send_to(Gee.Collection<MediaSource> media) {
    if (media.size == 0 || send_to_exporter != null)
        return;
    
    ExportDialog dialog = new ExportDialog(_("Send To"));
    
    int scale;
    ScaleConstraint constraint;
    ExportFormatParameters export_params = ExportFormatParameters.current();
    if (!dialog.execute(out scale, out constraint, ref export_params))
        return;
    
    send_to_exporter = new ExporterUI(new Exporter.for_temp_file(media,
        Scaling.for_constraint(constraint, scale, false), export_params, true));
    send_to_exporter.export(on_send_to_export_completed);
}

private void on_send_to_export_completed(Exporter exporter) {
    files_send_to(exporter.get_exported_files());
    send_to_exporter = null;
}

#if !NO_SET_BACKGROUND
public void set_background(Photo photo) {
    // attempt to set the wallpaper to the photo's native format, but if not writeable, go to the
    // system default
    PhotoFileFormat file_format = photo.get_best_export_file_format();
    
    File save_as = AppDirs.get_data_subdir("wallpaper").get_child(
        file_format.get_default_basename("wallpaper"));
    
    if (Config.get_instance().get_background() == save_as.get_path()) {
        save_as = AppDirs.get_data_subdir("wallpaper").get_child(
            file_format.get_default_basename("wallpaper_alt"));
    }
    
    try {
        photo.export(save_as, Scaling.for_original(), Jpeg.Quality.MAXIMUM, file_format);
    } catch (Error err) {
        AppWindow.error_message(_("Unable to export background to %s: %s").printf(save_as.get_path(), 
            err.message));
        
        return;
    }
    
    Config.get_instance().set_background(save_as.get_path());
    
    GLib.FileUtils.chmod(save_as.get_parse_name(), 0644);
}
#endif

}
