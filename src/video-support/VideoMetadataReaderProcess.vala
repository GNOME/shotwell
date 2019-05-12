using Gst;
using Gst.PbUtils;

static string address;
static MainLoop loop;

const OptionEntry[] options = {
    { "address", 'a', 0, OptionArg.STRING, ref address, "Address of private bus", "ADDRESS" },
    { null }
};


[DBus (name = "org.gnome.Shotwell.VideoMetadata1")]
internal class MetadataReader : GLib.Object {
    private Gst.PbUtils.Discoverer discoverer;

    public MetadataReader() throws Error {
        setup_reader();
    }

    public async uint64 get_duration(string uri) throws Error {
        print("=> Request for uri %s\n", uri);
        Error error = null;
        Gst.PbUtils.DiscovererInfo? info = null;

        var id = discoverer.discovered.connect (
            (_info, _error) => {
                info = _info;
                error = _error;
                get_duration.callback ();
        });

        var file = File.new_for_uri(uri);
        var path = file.get_path();

        if (path != null) {
            uri = Filename.to_uri(path);
        }

        print("Before discover\n");
        discoverer.discover_uri_async (uri);
        yield;
        discoverer.disconnect (id);
        print("After discover\n");

        if (error != null) {
            // Re-create discoverer, in error case it tends to get really
            // slow.
            setup_reader();

            var result = info.get_result ();
            if (result == Gst.PbUtils.DiscovererResult.TIMEOUT) {
                debug ("Extraction timed out on %s", file.get_uri ());
            } else if (result == Gst.PbUtils.DiscovererResult.MISSING_PLUGINS) {
                debug ("Plugins are missing for extraction of file %s",
                       file.get_uri ());
            }

            throw error;
        }

        return info.get_duration();
    }

    private void setup_reader() throws Error {
        discoverer = new Gst.PbUtils.Discoverer (Gst.SECOND * 5);
        discoverer.start();
    }

    public async void terminate() throws Error {
        loop.quit();
    }
}

private bool on_authorize_peer(DBusAuthObserver observer, IOStream stream, Credentials? credentials) {
    debug("Observer trying to authorize for %s", credentials.to_string());

    if (credentials == null) {
        return false;
    }

    try {
        if (!credentials.is_same_user(new Credentials())) {
            return false;
        }

        return true;
    } catch (Error error) {
        return false;
    }
}

int main(string[] args) {
    var option_context = new OptionContext("- shotwell video metadata reader helper binary");
    option_context.set_help_enabled(true);
    option_context.add_main_entries(options, null);
    option_context.add_group(Gst.init_get_option_group());

    try {
        option_context.parse (ref args);

        var observer = new DBusAuthObserver();
        observer.authorize_authenticated_peer.connect(on_authorize_peer);
        var connection = new DBusConnection.for_address_sync(address, DBusConnectionFlags.AUTHENTICATION_CLIENT,
                                                         observer, null);
        connection.register_object ("/org/gnome/Shotwell/VideoMetadata1", new MetadataReader());

        loop = new MainLoop(null, false);
        loop.run();

    } catch (Error error) {
        critical("Failed to parse options: %s", error.message);

        return 1;
    }

    return 0;
}
