/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

enum ShotwellCommand {
    // user-defined commands must be positive ints
    MOUNTED_CAMERA = 1
}

private Timer startup_timer = null;
private bool was_already_running = false;

void library_exec(string[] mounts) {
    was_already_running = Application.get_is_remote();
    
    if (was_already_running) {
        // Send attached cameras out to the primary instance.
        // The primary instance will get a 'command-line' signal with mounts[]
        // as an argument, and an 'activate', which will present the window.
        //
        // This will also take care of killing us when it sees that another
        // instance was already registered.
        Application.present_primary_instance();
        Application.send_to_primary_instance(mounts);
        return;
    }
    
    // preconfigure units
    Db.preconfigure(AppDirs.get_data_subdir("data").get_child("photo.db"));
    
    // initialize units
    try {
        Library.app_init();
    } catch (Error err) {
        AppWindow.panic(err.message);
        
        return;
    }
    
    // validate the databases prior to using them
    message("Verifying database…");
    string errormsg = null;
    string app_version;
    int schema_version;
    Db.VerifyResult result = Db.verify_database(out app_version, out schema_version);
    switch (result) {
        case Db.VerifyResult.OK:
            // do nothing; no problems
        break;
        
        case Db.VerifyResult.FUTURE_VERSION:
            errormsg = _("Your photo library is not compatible with this version of Shotwell. It appears it was created by Shotwell %s (schema %d). This version is %s (schema %d). Please use the latest version of Shotwell.").printf(
                app_version, schema_version, Resources.APP_VERSION, DatabaseTable.SCHEMA_VERSION);
        break;
        
        case Db.VerifyResult.UPGRADE_ERROR:
            errormsg = _("Shotwell was unable to upgrade your photo library from version %s (schema %d) to %s (schema %d). For more information please check the Shotwell Wiki at %s").printf(
                app_version, schema_version, Resources.APP_VERSION, DatabaseTable.SCHEMA_VERSION,
                Resources.HOME_URL);
        break;
        
        case Db.VerifyResult.NO_UPGRADE_AVAILABLE:
            errormsg = _("Your photo library is not compatible with this version of Shotwell. It appears it was created by Shotwell %s (schema %d). This version is %s (schema %d). Please clear your library by deleting %s and re-import your photos.").printf(
                app_version, schema_version, Resources.APP_VERSION, DatabaseTable.SCHEMA_VERSION,
                AppDirs.get_data_dir().get_path());
        break;
        
        default:
            errormsg = _("Unknown error attempting to verify Shotwell’s database: %s").printf(
                result.to_string());
        break;
    }
    
    if (errormsg != null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(null, Gtk.DialogFlags.MODAL, 
            Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", errormsg);
        dialog.title = Resources.APP_TITLE;
        dialog.run();
        dialog.destroy();
        
        DatabaseTable.terminate();
        
        return;
    }
    
    Upgrades.init();
    
    ProgressDialog progress_dialog = null;
    AggregateProgressMonitor aggregate_monitor = null;
    ProgressMonitor monitor = null;
    
    if (!CommandlineOptions.no_startup_progress) {
        // only throw up a startup progress dialog if over a reasonable amount of objects ... multiplying
        // photos by two because there's two heavy-duty operations on them: creating the LibraryPhoto
        // objects and then populating the initial page with them.
        uint64 grand_total = PhotoTable.get_instance().get_row_count()
            + EventTable.get_instance().get_row_count()
            + TagTable.get_instance().get_row_count()
            + VideoTable.get_instance().get_row_count()
#if ENABLE_FACES               
            + FaceTable.get_instance().get_row_count()
            + FaceLocationTable.get_instance().get_row_count()
#endif
            + Upgrades.get_instance().get_step_count();
        if (grand_total > 5000) {
            progress_dialog = new ProgressDialog(null, _("Loading Shotwell"));
            progress_dialog.update_display_every(100);
            progress_dialog.set_minimum_on_screen_time_msec(250);
            try {
                progress_dialog.icon = new Gdk.Pixbuf.from_resource("/org/gnome/Shotwell/icons/shotwell.svg");
            } catch (Error err) {
                debug("Warning - could not load application icon for loading window: %s", err.message);
            }
            
            aggregate_monitor = new AggregateProgressMonitor(grand_total, progress_dialog.monitor);
            monitor = aggregate_monitor.monitor;
        }
    }
    
    ThumbnailCache.init();
    Tombstone.init();

    LibraryFiles.select_copy_function();
    
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("LibraryPhoto.init");
    LibraryPhoto.init(monitor);
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("Video.init");
    Video.init(monitor);
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("Upgrades.execute");
    Upgrades.get_instance().execute();
    
    LibraryMonitorPool.init();
    MediaCollectionRegistry.init();
    MediaCollectionRegistry registry = MediaCollectionRegistry.get_instance();
    registry.register_collection(LibraryPhoto.global);
    registry.register_collection(Video.global);
    
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("Event.init");
    Event.init(monitor);
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("Tag.init");
    Tag.init(monitor);
#if ENABLE_FACES       
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("FaceLocation.init");
    FaceLocation.init(monitor);
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("Face.init");
    Face.init(monitor);
#endif
    
    MetadataWriter.init();
    DesktopIntegration.init();
    
    Application.get_instance().init_done();
    
    // create main library application window
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("LibraryWindow");
    LibraryWindow library_window = new LibraryWindow(monitor);
    
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("done");
    
    // destroy and tear down everything ... no need for them to stick around the lifetime of the
    // application
    
    monitor = null;
    aggregate_monitor = null;
    if (progress_dialog != null)
        progress_dialog.destroy();
    progress_dialog = null;

    // report mount points
    foreach (string mount in mounts)
        library_window.mounted_camera_shell_notification(mount, true);

    library_window.show_all();

    WelcomeServiceEntry[] selected_import_entries = new WelcomeServiceEntry[0];
    if (Config.Facade.get_instance().get_show_welcome_dialog() &&
        LibraryPhoto.global.get_count() == 0) {
        WelcomeDialog welcome = new WelcomeDialog(library_window);
        Config.Facade.get_instance().set_show_welcome_dialog(welcome.execute(out selected_import_entries,
            out do_system_pictures_import));
    } else {
        Config.Facade.get_instance().set_show_welcome_dialog(false);
    }
    
    if (selected_import_entries.length > 0) {
        do_external_import = true;
        foreach (WelcomeServiceEntry entry in selected_import_entries)
            entry.execute();
    } 
    if (do_system_pictures_import) {
        /*  Do the system import even if other plugins have run as some plugins may not
            as some plugins may not import pictures from the system folder.
         */
        run_system_pictures_import();
    }
    
    debug("%lf seconds to Gtk.main()", startup_timer.elapsed());
    
    Application.get_instance().start();
    
    DesktopIntegration.terminate();
    MetadataWriter.terminate();
    Tag.terminate();
    Event.terminate();
    LibraryPhoto.terminate();
    MediaCollectionRegistry.terminate();
    LibraryMonitorPool.terminate();
    Tombstone.terminate();
    ThumbnailCache.terminate();
    Video.terminate();
#if ENABLE_FACES       
    Face.terminate();
    FaceLocation.terminate();
#endif

    Library.app_terminate();
}

private bool do_system_pictures_import = false;
private bool do_external_import = false;

public void run_system_pictures_import(ImportManifest? external_exclusion_manifest = null) {
    if (!do_system_pictures_import)
        return;

    Gee.ArrayList<FileImportJob> jobs = new Gee.ArrayList<FileImportJob>();
    jobs.add(new FileImportJob(AppDirs.get_import_dir(), false, true));
    
    LibraryWindow library_window = (LibraryWindow) AppWindow.get_instance();
    
    BatchImport batch_import = new BatchImport(jobs, "startup_import",
        report_system_pictures_import, null, null, null, null, external_exclusion_manifest);
    library_window.enqueue_batch_import(batch_import, true);

    library_window.switch_to_import_queue_page();
}

private void report_system_pictures_import(ImportManifest manifest, BatchImportRoll import_roll) {
    /* Don't report the manifest to the user if exteral import was done and the entire manifest
       is empty. An empty manifest in this case results from files that were already imported
       in the external import phase being skipped. Note that we are testing against manifest.all,
       not manifest.success; manifest.all is zero when no files were enqueued for import in the
       first place and the only way this happens is if all files were skipped -- even failed
       files are counted in manifest.all */
    if (do_external_import && (manifest.all.size == 0))
        return;

    ImportUI.report_manifest(manifest, true);
}

void editing_exec(string filename, bool fullscreen) {
    File initial_file = File.new_for_commandline_arg(filename);
    
    // preconfigure units
    Direct.preconfigure(initial_file);
    Db.preconfigure(null);
    
    // initialize units for direct-edit mode
    try {
        Direct.app_init();
    } catch (Error err) {
        AppWindow.panic(err.message);
        
        return;
    }
    
    // init modules direct-editing relies on
    DesktopIntegration.init();
    
    // TODO: At some point in the future, to support mixed-media in direct-edit mode, we will
    //       refactor DirectPhotoSourceCollection to be a MediaSourceCollection. At that point,
    //       we'll need to register DirectPhoto.global with the MediaCollectionRegistry
    
    DirectWindow direct_window = new DirectWindow(initial_file);
    direct_window.show_all();
    
    debug("%lf seconds to Gtk.main()", startup_timer.elapsed());

    if (fullscreen) {
        var action = direct_window.get_common_action("CommonFullscreen");
        if (action != null) {
            action.activate(null);
        }
    }
    
    Application.get_instance().start();

    DesktopIntegration.terminate();
    
    // terminate units for direct-edit mode
    Direct.app_terminate();
}

namespace CommandlineOptions {

bool no_startup_progress = false;
string data_dir = null;
bool show_version = false;
bool no_runtime_monitoring = false;
bool fullscreen = false;

private OptionEntry[]? entries = null;

public OptionEntry[] get_options() {
    if (entries != null)
        return entries;
    
    OptionEntry datadir = { "datadir", 'd', 0, OptionArg.FILENAME, &data_dir,
        _("Path to Shotwell’s private data"), _("DIRECTORY") };
    entries += datadir;
    
    OptionEntry no_monitoring = { "no-runtime-monitoring", 0, 0, OptionArg.NONE, &no_runtime_monitoring,
        _("Do not monitor library directory at runtime for changes"), null };
    entries += no_monitoring;
    
    OptionEntry no_startup = { "no-startup-progress", 0, 0, OptionArg.NONE, &no_startup_progress,
        _("Don’t display startup progress meter"), null };
    entries += no_startup;
    
    OptionEntry version = { "version", 'V', 0, OptionArg.NONE, &show_version, 
        _("Show the application’s version"), null };
    entries += version;

    OptionEntry fullscreen = { "fullscreen", 'f', 0, OptionArg.NONE,
        &fullscreen, _("Start the application in fullscreen mode"), null };
    entries += fullscreen;
    
    OptionEntry terminator = { null, 0, 0, 0, null, null, null };
    entries += terminator;
    
    return entries;
}

}

void main(string[] args) {
    // Call AppDirs init *before* calling Gtk.init_with_args, as it will strip the
    // exec file from the array
    AppDirs.init(args[0]);

    // This has to be done before the AppWindow is created in order to ensure the XMP
    // parser is initialized in a thread-safe fashion; please see 
    // http://redmine.yorba.org/issues/4120 for details.
    GExiv2.initialize();
    GExiv2.log_use_glib_logging();

    // Set GExiv2 log level to DEBUG, filtering will be done through Shotwell
    // logging mechanisms
    GExiv2.log_set_level(GExiv2.LogLevel.DEBUG);

    // following the GIO programming guidelines at http://developer.gnome.org/gio/2.26/ch03.html,
    // set the GSETTINGS_SCHEMA_DIR environment variable to allow us to load GSettings schemas from 
    // the build directory. this allows us to access local GSettings schemas without having to
    // muck with the user's XDG_... directories, which is seriously frowned upon
    if (AppDirs.get_install_dir() == null) {
        GLib.Environment.set_variable("GSETTINGS_SCHEMA_DIR", AppDirs.get_lib_dir().get_path() +
            "/misc", true);
    }
    
    // init GTK (valac has already called g_threads_init())
    try {
        Gtk.init_with_args(ref args, _("[FILE]"), CommandlineOptions.get_options(),
            Resources.APP_GETTEXT_PACKAGE);

        var use_dark = Config.Facade.get_instance().get_gtk_theme_variant();
        Gtk.Settings.get_default().gtk_application_prefer_dark_theme = use_dark;
    } catch (Error e) {
        print(e.message + "\n");
        print(_("Run “%s --help” to see a full list of available command line options.\n"), args[0]);
        AppDirs.terminate();
        return;
    }

    if (CommandlineOptions.show_version) {
        if (Resources.GIT_VERSION != null)
            print("%s %s (%s)\n", Resources.APP_TITLE, Resources.APP_VERSION, Resources.GIT_VERSION);
        else
            print("%s %s\n", Resources.APP_TITLE, Resources.APP_VERSION);

        AppDirs.terminate();
        
        return;
    }
    
    // init debug prior to anything else (except Gtk, which it relies on, and AppDirs, which needs
    // to be set ASAP) ... since we need to know what mode we're in, examine the command-line
    // first
    
    // walk command-line arguments for camera mounts or filename for direct editing ... only one
    // filename supported for now, so take the first one and drop the rest ... note that URIs for
    // filenames are currently not permitted, to differentiate between mount points
    string[] mounts = new string[0];
    string filename = null;

    for (int ctr = 1; ctr < args.length; ctr++) {
        string arg = args[ctr];
        
        if (LibraryWindow.is_mount_uri_supported(arg)) {
            mounts += arg;
        } else if (is_string_empty(filename) && !arg.contains("://")) {
            filename = arg;
        }
    }
    
    Debug.init(is_string_empty(filename) ? Debug.LIBRARY_PREFIX : Debug.VIEWER_PREFIX);

    if (Resources.GIT_VERSION != null)
        message("Shotwell %s %s (%s)",
            is_string_empty(filename) ? Resources.APP_LIBRARY_ROLE : Resources.APP_DIRECT_ROLE,
            Resources.APP_VERSION, Resources.GIT_VERSION);
    else
        message("Shotwell %s %s",
            is_string_empty(filename) ? Resources.APP_LIBRARY_ROLE : Resources.APP_DIRECT_ROLE,
            Resources.APP_VERSION);
    debug ("Shotwell is running in timezone %s", new
           DateTime.now_local().get_timezone_abbreviation ());
        
    // Have a filename here?  If so, configure ourselves for direct
    // mode, otherwise, default to library mode.
    Application.init(!is_string_empty(filename));
    
    // set custom data directory if it's been supplied
    if (CommandlineOptions.data_dir != null)
        AppDirs.set_data_dir(CommandlineOptions.data_dir);
    else
        AppDirs.try_migrate_data();
    
    // Verify the private data directory before continuing
    AppDirs.verify_data_dir();
    AppDirs.verify_cache_dir();
    
    // init internationalization with the default system locale
    InternationalSupport.init(Resources.APP_GETTEXT_PACKAGE, args);
    
    startup_timer = new Timer();
    startup_timer.start();
    
    // set up GLib environment
    GLib.Environment.set_application_name(Resources.APP_TITLE);
    
    // in both the case of running as the library or an editor, Resources is always
    // initialized
    Resources.init();
    
    // since it's possible for a mount name to be passed that's not supported (and hence an empty
    // mount list), or for nothing to be on the command-line at all, only go to direct editing if a
    // filename is spec'd
    if (is_string_empty(filename))
        library_exec(mounts);
    else
        editing_exec(filename, CommandlineOptions.fullscreen);
    
    // terminate mode-inspecific modules
    Resources.terminate();
    Application.terminate();
    Debug.terminate();
    AppDirs.terminate();

    // Back up db on successful run so we have something to roll back to if
    // it gets corrupted in the next session.  Don't do this if another shotwell
    // is open or if we're in direct mode.
    if (is_string_empty(filename) && !was_already_running) {
        string orig_path = AppDirs.get_data_subdir("data").get_child("photo.db").get_path();
        string backup_path = orig_path + ".bak";
        try {
            File src = File.new_for_commandline_arg(orig_path);
            File dest = File.new_for_commandline_arg(backup_path);
            src.copy(dest,
                     FileCopyFlags.OVERWRITE |
                     FileCopyFlags.ALL_METADATA);
        } catch(Error error) {
            warning("Failed to create backup file of database: %s",
                    error.message);
        }
        Posix.sync();
    }
}

