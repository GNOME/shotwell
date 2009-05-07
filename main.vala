
enum ShotwellCommand {
    // user-defined commands must be positive ints
    MOUNTED_CAMERA = 1
}

Unique.Response on_shotwell_message(Unique.App shotwell, int command, Unique.MessageData data, uint timestamp) {
    Unique.Response response = Unique.Response.OK;
    
    switch (command) {
        case ShotwellCommand.MOUNTED_CAMERA: {
            AppWindow.get_instance().mounted_camera_shell_notification(File.new_for_uri(data.get_text()));
        } break;
        
        case Unique.Command.ACTIVATE: {
            AppWindow.get_instance().present_with_time(timestamp);
        } break;
        
        default: {
            // should be Unique.Response.PASSTHROUGH, but value isn't bound in vapi
            response = (Unique.Response) 4;
        } break;
    }
    
    return response;
}

void main(string[] args) {
    // init GTK
    Gtk.init(ref args);
    
    // set up GLib environment
    GLib.Environment.set_application_name(AppWindow.TITLE);
    
    // examine command-line arguments for camera mounts
    // (everything else is ignored for now)
    string[] mounts = new string[0];
    for (int ctr = 1; ctr < args.length; ctr++) {
        if (args[ctr].has_prefix("gphoto2://"))
            mounts += args[ctr];
    }
    
    // single-instance app
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
        
        return;
    }

    // initialize app-wide stuff
    AppWindow.init(args);
    DatabaseTable.init();
    ThumbnailCache.init();
    
    // create main application window
    AppWindow app_window = new AppWindow();
    
    // report mount points
    foreach (string mount in mounts)
        app_window.mounted_camera_shell_notification(File.new_for_uri(mount));
    
    // throw it all on the display
    app_window.show_all();

    // event loop
    Gtk.main();
}

