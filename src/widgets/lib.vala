namespace Shotwell.Widgets {
    /// Registers all custom widgets with the type system
    /// so they can be used in Gtk.Builder
    public static void init() {
        typeof (Shotwell.FolderButton).ensure();
        typeof (Shotwell.SettingsGroup).ensure();
    }
}
