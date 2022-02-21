[CCode (cheader_filename = "gdk/gdkwayland.h")]
namespace Gdk.Wayland {
    [CCode (type_id = "GDK_TYPE_WAYLAND_WINDOW", type_check_function = "GDK_IS_WAYLAND_WINDOW")]
    public class Window : Gdk.Window {
        public bool export_handle (owned WindowExported callback);
    }

    [CCode (instance_pos = 2.9)]
    public delegate void WindowExported (Gdk.Window window, string handle);
}
