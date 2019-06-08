using Gst;
using Gst.PbUtils;

static string address;
static string uri;
static MainLoop loop;

const OptionEntry[] options = {
    { "address", 'a', 0, OptionArg.STRING, ref address, "ADDRESS of private bus", "ADDRESS" },
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
                critical ("Extraction timed out on %s", file.get_uri ());
            } else if (result == Gst.PbUtils.DiscovererResult.MISSING_PLUGINS) {
                critical ("Plugins are missing for extraction of file %s",
                       file.get_uri ());
            }

            throw error;
        }

        print ("Before return!");

        return info.get_duration();
    }

    public async string[] read_metadata(string uri) throws Error {
        string[] return_values = { null, null, null, null };
        var file = File.new_for_uri(uri);
        var path = file.get_path();

        if (path != null) {
            uri = Filename.to_uri(path);
        }

        var quicktime = new QuickTimeMetadataLoader(File.new_for_uri(uri));
        if (quicktime.is_supported()) {
            return_values[0] = quicktime.get_creation_date_time().to_string();
            return_values[1] = quicktime.get_title();
            Idle.add(() => { read_metadata.callback(); return false; });
            yield;
            return return_values;
        }

        var avi = new AVIMetadataLoader(File.new_for_uri(uri));
        if (avi.is_supported()) {
            return_values[0] = avi.get_creation_date_time().to_string();
            return_values[1] = avi.get_title();
            Idle.add(() => { read_metadata.callback(); return false; });
            yield;
            return return_values;
        }

        Idle.add(() => { read_metadata.callback(); return false; });
        yield;
        throw new IOError.NOT_SUPPORTED("File %s is not a supported video format", file.get_path());
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
    option_context.add_group(Gst.init_get_option_group());

    try {
        option_context.parse (ref args);

        if (address == null && uri == null) {
            error("Must either provide --uri or --address");
        }

        if (address != null) {
            critical("=> Creating new connection");
            var observer = new DBusAuthObserver();
            observer.authorize_authenticated_peer.connect(on_authorize_peer);
            var connection = new DBusConnection.for_address_sync(address, DBusConnectionFlags.NONE, //AUTHENTICATION_CLIENT,
                    observer, null);

            critical("=> Registering object");
            connection.register_object ("/org/gnome/Shotwell/VideoMetadata1", new MetadataReader());

        }

        loop = new MainLoop(null, false);
        loop.run();

    } catch (Error error) {
        critical("Failed to parse options: %s", error.message);

        return 1;
    }

    return 0;
}
