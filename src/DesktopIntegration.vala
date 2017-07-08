/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DesktopIntegration {

private const string SENDTO_EXEC = "nautilus-sendto";
private const string DESKTOP_SLIDESHOW_XML_FILENAME = "wallpaper.xml";

private int init_count = 0;
private bool send_to_installed = false;
private ExporterUI send_to_exporter = null;
private ExporterUI desktop_slideshow_exporter = null;
private double desktop_slideshow_transition = 0.0;
private double desktop_slideshow_duration = 0.0;

private bool set_desktop_background = false;
private bool set_screensaver = false;

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
        string content_type = ContentType.from_mime_type(mime_type);
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
            "/",
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

    // determine the mix of media in the export collection -- if it contains only
    // videos then we can use the Video.export_many( ) fast path and not have to
    // worry about ExportFormatParameters or the Export... dialog
    if (MediaSourceCollection.has_video(media) && !MediaSourceCollection.has_photo(media)) {
        send_to_exporter = Video.export_many((Gee.Collection<Video>) media,
            on_send_to_export_completed, true);
        return;
    }
    
    int scale;
    ScaleConstraint constraint;
    ExportFormatParameters export_params = ExportFormatParameters.current();
    if (!dialog.execute(out scale, out constraint, ref export_params))
        return;
    
    send_to_exporter = new ExporterUI(new Exporter.for_temp_file(media,
        Scaling.for_constraint(constraint, scale, false), export_params));
    send_to_exporter.export(on_send_to_export_completed);
}

private void on_send_to_export_completed(Exporter exporter, bool is_cancelled) {
    if (!is_cancelled)
        files_send_to(exporter.get_exported_files());
    
    send_to_exporter = null;
}

public void set_background(Photo photo, bool desktop, bool screensaver) {
    // attempt to set the wallpaper to the photo's native format, but if not writeable, go to the
    // system default
    PhotoFileFormat file_format = photo.get_best_export_file_format();
    
    File save_as = AppDirs.get_data_subdir("wallpaper").get_child(
        file_format.get_default_basename("wallpaper"));
    
    if (Config.Facade.get_instance().get_desktop_background() == save_as.get_path()) {
        save_as = AppDirs.get_data_subdir("wallpaper").get_child(
            file_format.get_default_basename("wallpaper_alt"));
    }
    
    try {
        photo.export(save_as, Scaling.for_original(), Jpeg.Quality.HIGH, file_format);
    } catch (Error err) {
        AppWindow.error_message(_("Unable to export background to %s: %s").printf(save_as.get_path(), 
            err.message));
        
        return;
    }
    
    if (desktop) {
        Config.Facade.get_instance().set_desktop_background(save_as.get_path());
    }
    if (screensaver) {
        Config.Facade.get_instance().set_screensaver(save_as.get_path());
    }
    
    GLib.FileUtils.chmod(save_as.get_parse_name(), 0644);
}

// Helper class for set_background_slideshow()
// Used to build xml file that describes background
// slideshow for Gnome
private class BackgroundSlideshowXMLBuilder {
    private File destination;
    private double duration;
    private double transition;
    private File tmp_file;
    private DataOutputStream? outs = null;
    private File? first_file = null;
    private File? last_file = null;
    
    public BackgroundSlideshowXMLBuilder(File destination, double duration, double transition) {
        this.destination = destination;
        this.duration = duration;
        this.transition = transition;
        
        tmp_file = destination.get_parent().get_child(destination.get_basename() + ".tmp");
    }
    
    public void open() throws Error {
        outs = new DataOutputStream(tmp_file.replace(null, false, FileCreateFlags.NONE, null));
        outs.put_string("<background>\n");
    }
    
    private void write_transition(File from, File to) throws Error {
        outs.put_string("  <transition>\n");
        outs.put_string("    <duration>%2.2f</duration>\n".printf(transition));
        outs.put_string("    <from>%s</from>\n".printf(Markup.escape_text(from.get_path())));
        outs.put_string("    <to>%s</to>\n".printf(Markup.escape_text(to.get_path())));
        outs.put_string("  </transition>\n");
    }
    
    private void write_static(File file) throws Error {
        outs.put_string("  <static>\n");
        outs.put_string("    <duration>%2.2f</duration>\n".printf(duration));
        outs.put_string("    <file>%s</file>\n".printf(Markup.escape_text(file.get_path())));
        outs.put_string("  </static>\n");
    }
    
    public void add_photo(File file) throws Error {
        assert(outs != null);
        
        if (first_file == null)
            first_file = file;
        
        if (last_file != null)
            write_transition(last_file, file);
        
        write_static(file);
        
        last_file = file;
    }
    
    public File? close() throws Error {
        if (outs == null)
            return null;
        
        // transition back to first file
        if (first_file != null && last_file != null)
            write_transition(last_file, first_file);
        
        outs.put_string("</background>\n");
        
        outs.close();
        outs = null;
        
        // move to destination name
        tmp_file.move(destination, FileCopyFlags.OVERWRITE);
        GLib.FileUtils.chmod(destination.get_parse_name(), 0644);
        
        return destination;
    }
}

public void set_background_slideshow(Gee.Collection<Photo> photos, double duration, double transition,
        bool desktop_background, bool screensaver) {
    if (desktop_slideshow_exporter != null)
        return;
    
    set_desktop_background = desktop_background;
    set_screensaver = screensaver;

    File wallpaper_dir = AppDirs.get_data_subdir("wallpaper");
    
    Gee.Set<string> exceptions = new Gee.HashSet<string>();
    exceptions.add(DESKTOP_SLIDESHOW_XML_FILENAME);
    try {
        delete_all_files(wallpaper_dir, exceptions);
    } catch (Error err) {
        warning("Error attempting to clear wallpaper directory: %s", err.message);
    }
    
    desktop_slideshow_duration = duration;
    desktop_slideshow_transition = transition;
    
    Exporter exporter = new Exporter(photos, wallpaper_dir,
        Scaling.to_fill_screen(AppWindow.get_instance()), ExportFormatParameters.current(),
        true);
    desktop_slideshow_exporter = new ExporterUI(exporter);
    desktop_slideshow_exporter.export(on_desktop_slideshow_exported);
}

private void on_desktop_slideshow_exported(Exporter exporter, bool is_cancelled) {
    desktop_slideshow_exporter = null;
    
    if (is_cancelled)
        return;
    
    File? xml_file = null;
    BackgroundSlideshowXMLBuilder xml_builder = new BackgroundSlideshowXMLBuilder(
        AppDirs.get_data_subdir("wallpaper").get_child(DESKTOP_SLIDESHOW_XML_FILENAME),
        desktop_slideshow_duration, desktop_slideshow_transition);
    try {
        xml_builder.open();
        
        foreach (File file in exporter.get_exported_files())
            xml_builder.add_photo(file);
        
        xml_file = xml_builder.close();
    } catch (Error err) {
        AppWindow.error_message(_("Unable to prepare desktop slideshow: %s").printf(
            err.message));
        
        return;
    }
    
    if (set_desktop_background) {
        Config.Facade.get_instance().set_desktop_background(xml_file.get_path());
    }
    if (set_screensaver) {
        Config.Facade.get_instance().set_screensaver(xml_file.get_path());
    }
}

}
