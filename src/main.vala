/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

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

private Timer startup_timer = null;

void library_exec(string[] mounts) {
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

    // init modules library relies on
    DatabaseTable.init(AppWindow.get_data_subdir("data").get_child("photo.db"));
    ThumbnailCache.init();
    LibraryPhoto.init();
    Event.init();

    // validate the databases prior to using them
    message("Verifying databases ...");
    string app_version;
    if (verify_databases(out app_version)) {
        // create main library application window
        LibraryWindow library_window = new LibraryWindow();
        
        // report mount points
        foreach (string mount in mounts)
            library_window.mounted_camera_shell_notification(mount);

        library_window.show_all();
        
        debug("%lf seconds to Gtk.main()", startup_timer.elapsed());
        
        Gtk.main();
    } else {
        string errormsg = _("The database for your photo library is not compatible with this version of Shotwell.  It appears it was created by Shotwell %s.  Please use that version or later.");
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(null, Gtk.DialogFlags.MODAL, 
            Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, errormsg, app_version);
        dialog.title = Resources.APP_TITLE;
        dialog.run();
        dialog.destroy();
    }
    
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

void main(string[] args) {
    // init GTK
    Gtk.init(ref args);
    
    // init internationalization with the default system locale
    InternationalSupport.init(Resources.APP_GETTEXT_PACKAGE);
    
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
        if (LibraryWindow.is_mount_uri_supported(args[ctr]))
            mounts += args[ctr];
        else if (filename == null && !args[ctr].contains("://"))
            filename = args[ctr];
    }
    
    // in both the case of running as the library or an editor, AppWindow and Resources are always
    // initialized
    AppWindow.init(args);
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
    AppWindow.terminate();
    Debug.terminate();
}

