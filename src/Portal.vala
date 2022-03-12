[DBus (name="org.freedesktop.portal.Email")]
private interface PortalEmail : DBusProxy {
    [DBus (name = "version")]
    public abstract uint version { get; }
}

public class Portal : GLib.Object {
    private static Portal portal;
    public static Portal get_instance () {
        if (portal == null){
            portal = new Portal ();
        }
        return portal;
    }

    private const string BUS_NAME = "org.freedesktop.portal.Desktop";
    private const string OBJECT_PATH = "/org/freedesktop/portal/desktop";

    private GLib.DBusConnection bus;

    public async Variant compose_email (HashTable<string, Variant> options,
      UnixFDList attachments) throws Error{
        if (bus == null){
            bus = yield Bus.get(BusType.SESSION);
        }

        options.insert ("handle_token", Portal.generate_handle());

        var options_builder = new VariantBuilder (VariantType.VARDICT);
        options.foreach ((key, val) => {
            options_builder.add ("{sv}", key, val);
        });

        PortalEmail? email = yield bus.get_proxy(BUS_NAME, OBJECT_PATH);

        var response = email.call_with_unix_fd_list_sync (
            "ComposeEmail",
            new Variant ("(sa{sv})", yield Portal.get_parent_window(), options_builder),
            DBusCallFlags.NONE,
            -1,
            attachments
        );
        return response;
    }

    private static string generate_handle () {
        return "%s_%i".printf (
            GLib.Application.get_default ().application_id.replace (".", "_").replace("-", "_"),
            Random.int_range (0, int32.MAX)
        );
    }

    private static async string get_parent_window () {
        var window = AppWindow.get_instance().get_window ();

        if (window is Gdk.Wayland.Window) {
            var handle = "wayland:";
            ((Gdk.Wayland.Window) window).export_handle ((w, h) => {
                handle += h;
                get_parent_window.callback ();
            });
            yield;
            return handle;
        } else if (window is Gdk.X11.Window) {
            return "x11:%x".printf ((uint) ((Gdk.X11.Window) window).get_xid ());
        } else {
            warning ("Could not get parent window");
            return "";
        }
    }
}
