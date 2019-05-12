public errordomain LaunchError {
    FAILED
}

/*
 * - Proxies interface access
 */
public class ExternalProxy<G> : Object, Initable {
    private G remote;
    private DBusServer server;
    private Subprocess remote_process;
    private SourceFunc saved_get_remote_callback;
    private uint startup_timeout;

    public string dbus_path { get; construct set; }
    public string remote_helper_path { get; construct set; }

    public ExternalProxy(string dbus_path, string helper_path) throws Error {
        Object(dbus_path: dbus_path, remote_helper_path : helper_path);
        init();
    }

    public bool init(Cancellable? cancellable) throws GLib.Error {
        var address = "unix:tmpdir=%s".printf(Environment.get_tmp_dir());
        var observer = new DBusAuthObserver();
        observer.authorize_authenticated_peer.connect(this.on_authorize_peer);

        server = new DBusServer.sync(address, DBusServerFlags.NONE, DBus.generate_guid(), observer, cancellable);
        server.new_connection.connect(on_new_connection);
        server.start();

        return true;
    }

    public async G get_remote() throws Error {
        if (remote == null) {
            yield launch_helper();
        } else {
            Idle.add(() => { get_remote.callback(); return false; });
            yield;
        }

        return remote;
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

    private bool on_new_connection(DBusServer server, DBusConnection connection) {
        bool retval = true;
        Source.remove(startup_timeout);
        startup_timeout = 0;

        try {
            remote = connection.get_proxy_sync(null, dbus_path, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES |
                                               DBusProxyFlags.DO_NOT_CONNECT_SIGNALS,
                                               null);
            print("==============> got remote!\n");
        } catch (Error error) {
            critical("Failed to create DBus proxy: %s", error.message);
            retval = false;
        }

        saved_get_remote_callback();

        return retval;
    }

    private async void launch_helper() throws Error {
        saved_get_remote_callback = launch_helper.callback;

        if (remote_process == null) {
            remote_process = new Subprocess(SubprocessFlags.NONE, remote_helper_path, "--address=" + server.get_client_address());
            remote_process.wait_async.begin(null, on_process_exited);
            startup_timeout = Timeout.add_seconds(2, () => {
                startup_timeout = 0;
                saved_get_remote_callback();
                critical("=====> Timeout");

                return false;
            });
        }

        yield;

        if (remote_process == null) {
            throw new LaunchError.FAILED("Failed to launch subprocess...");
        }
    }

    private void on_process_exited(Object? source, AsyncResult res) {
        try {
            remote_process.wait_async.end(res);
            remote_process = null;
        } catch (Error error) { }

        critical("Subprocess exited unexpectedly");
    }
}

