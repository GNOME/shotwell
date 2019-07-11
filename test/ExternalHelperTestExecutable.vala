static string address;
static string uri;
static MainLoop loop;

const OptionEntry[] options = {
    { "address", 'a', 0, OptionArg.STRING, ref address, "ADDRESS of private bus", "ADDRESS" },
    { null }
};

[DBus (name = "org.gnome.Shotwell.ExternalHelperTest1")]
internal class TestInterface : GLib.Object {
    public async uint64 get_uint64(uint64 in_value) throws Error {
        Idle.add (() => {
            get_uint64.callback();
            return false;
        });

        yield;

        return in_value + 10;
    }

    public async void terminate() throws Error {
        loop.quit();
    }
}

private bool on_authorize_peer(DBusAuthObserver observer, IOStream stream, Credentials? credentials) {
    critical("helper: Observer trying to authorize for %s", credentials.to_string());

    if (credentials == null) {
        critical ("Invalid credentials");
        return false;
    }

    try {
        if (!credentials.is_same_user(new Credentials())) {
        critical ("different user");
            return false;
        }

        return true;
    } catch (Error error) {
        critical ("Error %s", error.message);
        return false;
    }
}

int main(string[] args) {
    var option_context = new OptionContext("- shotwell video metadata reader helper binary");
    option_context.set_help_enabled(true);
    option_context.add_main_entries(options, null);

    try {
        option_context.parse (ref args);

        if (address == null && uri == null) {
            error("Must either provide --uri or --address");
        }

        if (address != null) {
            critical("=> Creating new connection");
            var observer = new DBusAuthObserver();
            observer.authorize_authenticated_peer.connect(on_authorize_peer);
            var connection = new DBusConnection.for_address_sync(address, DBusConnectionFlags.AUTHENTICATION_CLIENT,
                    observer, null);

            critical("=> Registering object");
            connection.register_object ("/org/gnome/Shotwell/ExternalHelperTest1", new TestInterface());

        }

        loop = new MainLoop(null, false);
        loop.run();

    } catch (Error error) {
        critical("Failed to parse options: %s", error.message);

        return 1;
    }

    return 0;
}
