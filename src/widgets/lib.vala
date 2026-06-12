namespace Shotwell.Widgets {
    /// Registers all custom widgets with the type system
    /// so they can be used in Gtk.Builder
    public static void init() {
        typeof (Shotwell.FolderButton).ensure();
        typeof (Shotwell.SettingsGroup).ensure();
    }
}

// FIXME: Those living here is not the ideal place. Need to find something better

public bool bind_string_to_bool(GLib.Binding binding, GLib.Value from, ref GLib.Value to) {
    to = from.get_string() != null && from.get_string() != "";
    return true;
}

public bool bind_file_to_path(GLib.Binding binding, GLib.Value from, ref GLib.Value to) {
    var src = from.get_object();
    if (src != null) {
        var file = (File)src;
        to = file.get_path();
    }
    return true;
}
