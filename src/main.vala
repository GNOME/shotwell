/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_LIBUNIQUE

enum ShotwellCommand {
    // user-defined commands must be positive ints
    MOUNTED_CAMERA = 1
}

Unique.Response on_shotwell_message(Unique.App shotwell, int command, Unique.MessageData data, 
    uint timestamp) {
    Unique.Response response = Unique.Response.OK;
    
    switch (command) {
        case ShotwellCommand.MOUNTED_CAMERA:
            LibraryWindow.get_app().mounted_camera_shell_notification(data.get_text());
        break;
        
        case Unique.Command.ACTIVATE:
            LibraryWindow.get_app().present_with_time(timestamp);
        break;
        
        default:
            // should be Unique.Response.PASSTHROUGH, but value isn't bound in vapi
            response = (Unique.Response) 4;
        break;
    }
    
    return response;
}
#endif

private Timer startup_timer = null;

void library_exec(string[] mounts) {
#if NO_LIBUNIQUE
    if (already_running())
        return;
#else
    // the library is single-instance; editing windows are one-process-per
    Unique.App shotwell = new Unique.App("org.yorba.shotwell", null);
    shotwell.add_command("MOUNTED_CAMERA", (int) ShotwellCommand.MOUNTED_CAMERA);
    shotwell.message_received += on_shotwell_message;

    if (shotwell.is_running) {
        // send attached cameras & activate the window
        foreach (string mount in mounts) {
            Unique.MessageData data = new Unique.MessageData();
            data.set_text(mount, -1);
        
            shotwell.send_message((int) ShotwellCommand.MOUNTED_CAMERA, data);
        }
        
        shotwell.send_message((int) Unique.Command.ACTIVATE, null);
        
        // notified running app; this one exits
        return;
    }
#endif

    // initialize DatabaseTable before verification
    DatabaseTable.init(AppDirs.get_data_subdir("data").get_child("photo.db"));

    // validate the databases prior to using them
    message("Verifying databases ...");
    string errormsg = null;
    string app_version;
    DatabaseVerifyResult result = verify_database(out app_version);
    switch (result) {
        case DatabaseVerifyResult.OK:
            // do nothing; no problems
        break;
        
        case DatabaseVerifyResult.FUTURE_VERSION:
            errormsg = _("Your photo library is not compatible with this version of Shotwell.  It appears it was created by Shotwell %s.  This version is %s.  Please use the latest version of Shotwell.").printf(
                app_version, Resources.APP_VERSION);
        break;
        
        case DatabaseVerifyResult.UPGRADE_ERROR:
            errormsg = _("Shotwell was unable to upgrade your photo library from version %s to %s.  For more information please check the Shotwell Wiki at %s").printf(
                app_version, Resources.APP_VERSION, Resources.HELP_URL);
        break;
        
        case DatabaseVerifyResult.NO_UPGRADE_AVAILABLE:
            errormsg = _("Your photo library is not compatible with this version of Shotwell.  It appears it was created by Shotwell %s.  This version is %s.  Please clear your library by deleting %s and re-import your photos.").printf(
                app_version, Resources.APP_VERSION, AppDirs.get_data_dir().get_path());
        break;
        
        default:
            errormsg = _("Unknown error attempting to verify Shotwell's database: %d").printf(
                (int) result);
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
    
    ProgressDialog progress_dialog = null;
    AggregateProgressMonitor aggregate_monitor = null;
    ProgressMonitor monitor = null;
    
    if (!no_startup_progress) {
        // only throw up a startup progress dialog if over a reasonable amount of objects ... multiplying
        // photos by two because there's two heavy-duty operations on them: creating the LibraryPhoto
        // objects and then populating the initial page with them.
        uint64 grand_total = (PhotoTable.get_instance().get_count() * 2) + EventTable.get_instance().get_count();
        if (grand_total > 20000) {
            progress_dialog = new ProgressDialog(null, _("Loading Shotwell..."));
            progress_dialog.update_display_every(300);
            spin_event_loop();
            
            aggregate_monitor = new AggregateProgressMonitor(grand_total, progress_dialog.monitor);
            monitor = aggregate_monitor.monitor;
        }
    }
    
    ThumbnailCache.init();
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("LibraryPhoto.init");
    LibraryPhoto.init(monitor);
    if (aggregate_monitor != null)
        aggregate_monitor.next_step("Event.init");
    Event.init(monitor);
    Tag.init();
    
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

#if !NO_CAMERA    
    // report mount points
    foreach (string mount in mounts)
        library_window.mounted_camera_shell_notification(mount);
#endif

    library_window.show_all();
    
    if (Config.get_instance().get_show_welcome_dialog() &&
        LibraryPhoto.global.get_count() == 0) {
        WelcomeDialog welcome = new WelcomeDialog(library_window);
        Config.get_instance().set_show_welcome_dialog(welcome.execute());
    } else {
        Config.get_instance().set_show_welcome_dialog(false);
    }

    debug("%lf seconds to Gtk.main()", startup_timer.elapsed());
    
    Gtk.main();
    
    Tag.terminate();
    Event.terminate();
    LibraryPhoto.terminate();
    ThumbnailCache.terminate();

    DatabaseTable.terminate();
}

void editing_exec(string filename) {
    // init modules direct-editing relies on
    DatabaseTable.init(null);
    DirectPhoto.init();
    
    DirectWindow direct_window = new DirectWindow(File.new_for_commandline_arg(filename));
    direct_window.show_all();
    
    debug("%lf seconds to Gtk.main()", startup_timer.elapsed());
    
    Gtk.main();
    
    DirectPhoto.terminate();
    DatabaseTable.terminate();
}

bool no_startup_progress = false;

const OptionEntry[] options = {
     { "no-startup-progress", 0, 0, OptionArg.NONE, &no_startup_progress,
       N_("Don't display startup progress meter"), null },
     { null }
};

void main(string[] args) {
    AppDirs.init(args[0]);
#if WINDOWS
    win_init(AppDirs.get_exec_dir());
#endif

    // init GTK (valac has already called g_threads_init())
    try {
        Gtk.init_with_args(ref args, _("[FILE]"), (OptionEntry []) options, Resources.APP_GETTEXT_PACKAGE);
    } catch (Error e) { error(e.message); }
    
    // init internationalization with the default system locale
    InternationalSupport.init(Resources.APP_GETTEXT_PACKAGE, args);
    
    startup_timer = new Timer();
    startup_timer.start();
    
    // init debug prior to anything else (except Gtk, which it relies on)
    Debug.init();
    
    // set up GLib environment
    GLib.Environment.set_application_name(Resources.APP_TITLE);
    
    // walk command-line arguments for camera mounts or filename for direct editing ... only one
    // filename supported for now, so take the first one and drop the rest ... note that URIs for
    // filenames are currently not permitted, to differentiate between mount points
    string[] mounts = new string[0];
    string filename = null;

    for (int ctr = 1; ctr < args.length; ctr++) {
        string arg = args[ctr];
        
        if (LibraryWindow.is_mount_uri_supported(arg)) {
            mounts += arg;
        } else if (filename == null && !arg.contains("://")) {
            filename = arg;
        }
    }
    
    // in both the case of running as the library or an editor, Resources is always
    // initialized
    Resources.init();
    
    // since it's possible for a mount name to be passed that's not supported (and hence an empty
    // mount list), or for nothing to be on the command-line at all, only go to direct editing if a
    // filename is spec'd
    if (filename == null)
        library_exec(mounts);
    else
        editing_exec(filename);
    
    // terminate mode-inspecific modules
    Resources.terminate();
    Debug.terminate();
    AppDirs.terminate();
}

