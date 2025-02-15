/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[DBus(name = "org.gnome.Shotwell.Authenticate")]
public interface AuthenticationReceiver : Object {
    public abstract void callback(string url) throws DBusError, IOError;
}

[DBus(name = "org.gnome.Shotwell.Authenticate")]
internal class AuthenticatorReceiverApp : Gtk.Application, AuthenticationReceiver {
    private Gee.HashMap<string, Spit.Publishing.AuthenticatedCallback>
        pending_auth_requests = new Gee.HashMap<string, Spit.Publishing.AuthenticatedCallback>();

    public AuthenticatorReceiverApp() {
        Object(application_id: "org.gnome.Shotwell", flags: GLib.ApplicationFlags.HANDLES_OPEN |
            GLib.ApplicationFlags.HANDLES_COMMAND_LINE);
    }
    public override bool dbus_register(DBusConnection connection, string object_path) throws Error {
        try {
            connection.register_object(object_path, this);
        } catch (IOError e) {
            warning("Failed to register authentication helper on session connection: %s", e.message);
        }
        return true;
    }


    internal void register_auth_callback(string cookie, Spit.Publishing.AuthenticatedCallback cb) {
        pending_auth_requests[cookie] = cb;
    }

    internal void unregister_auth_callback(string cookie) {
        pending_auth_requests.unset(cookie);
    }

    public void callback(string callback_url) throws DBusError, IOError {
        try {
            var uri = Uri.parse(callback_url, UriFlags.NONE);
            debug("Got authentication callback uri: %s", callback_url);
            // See if something is waiting for a pending authentication
            var query = uri.get_query();
            if (query == null || query == "") {
                debug("Callback does not have parameters. Not accepting");

                return;
            }
            var uri_params = Uri.parse_params(uri.get_query());
            if ("sw_auth_cookie" in uri_params) {
                var cookie = uri_params["sw_auth_cookie"];
                if (pending_auth_requests.has_key(cookie)) {
                    pending_auth_requests[cookie].authenticated(uri_params);
                    LibraryWindow.get_app().present();
                } else {
                    debug("No call-back registered for cookie %s, probably user cancelled", cookie);
                }
            } else if (uri.get_scheme().has_prefix("com.googleusercontent.apps")) {
                if (pending_auth_requests.has_key(uri.get_scheme())) {
                    pending_auth_requests[uri.get_scheme()].authenticated(uri_params);
                } else {
                    debug("No call-back registered for cookie %s, probably user cancelled", uri.get_scheme());
                }
            }
        } catch (Error error) {
            warning("Got invalid authentication call-back: %s", callback_url);
        }
    }
}

public class Application {
    public interface AuthCallback : Object {
        public abstract void authenticated(HashTable<string, string> params);
    }
    private static Application instance = null;
    public static TimeZone timezone = null;
    private Gtk.Application system_app = null;
    private int system_app_run_retval = 0;
    private bool direct;
    private bool in_panic = false;

    public void set_panicking() {
        in_panic = true;
    }

    public bool is_panicking() {
        return in_panic;
    }

    public virtual signal void starting() {
    }

    public virtual signal void exiting(bool panicked) {
    }
    
    public virtual signal void init_done() {
    }

    private bool fixup_raw_thumbs = false;
    
    public void set_raw_thumbs_fix_required(bool should_fixup) {
        fixup_raw_thumbs = should_fixup;
    }

    public bool get_raw_thumbs_fix_required() {
        return fixup_raw_thumbs;
    }

    public Gtk.Application get_system_app () {
        return system_app;
    }

    private bool running = false;
    private bool exiting_fired = false;

    Gee.HashMap<string, AuthCallback> pending_auth_requests = new Gee.HashMap<string, AuthCallback>();

    private Application(bool is_direct) {
        if (is_direct) {
            // we allow multiple instances of ourself in direct mode, so DON'T
            // attempt to be unique.  We don't request any command-line handling
            // here because this is processed elsewhere, and we don't need to handle
            // command lines from remote instances, since we don't care about them.
            system_app = new Gtk.Application("org.gnome.Shotwell-Viewer", GLib.ApplicationFlags.HANDLES_OPEN |
                GLib.ApplicationFlags.NON_UNIQUE);
        } else {
            // we've been invoked in library mode; set up for uniqueness and handling
            // of incoming command lines from remote instances (needed for getting
            // storage device and camera mounts).
            system_app = new AuthenticatorReceiverApp();
        }

        // GLib will assert if we don't do this...
        try {
            system_app.register();
        } catch (Error e) {
            panic();
        }
        
        direct = is_direct;

        if (!direct) {
            system_app.command_line.connect(on_command_line);
            var action = new SimpleAction("authenticated", VariantType.STRING);
            system_app.add_action(action);
            action.activate.connect(on_authenticate_action);
        }

        system_app.activate.connect(on_activated);
        system_app.startup.connect(on_activated);
    }

    private void on_authenticate_action(SimpleAction action, Variant? parameter) {
        try {
            var uri = Uri.parse(parameter.get_string(), UriFlags.NONE);
            debug("Got authentication callback uri: %s", parameter.get_string());
            // See if something is waiting for a pending authentication
            var uri_params = Uri.parse_params(uri.get_query());
            if ("sw_auth_cookie" in uri_params) {
                var cookie = uri_params["sw_auth_cookie"];
                if (pending_auth_requests.has_key(cookie)) {
                    pending_auth_requests[cookie].authenticated(uri_params);
                } else {
                    debug("No call-back registered for cookie %s, probably user cancelled", cookie);
                }
            }
        } catch (Error error) {
            warning("Got invalid authentication call-back: %s", parameter.get_string());
        }

    }

    public static void register_auth_callback(string cookie, Spit.Publishing.AuthenticatedCallback cb) {
        var instance = get_instance();
        if (!instance.direct) {
            ((AuthenticatorReceiverApp)instance.system_app).register_auth_callback(cookie, cb);
        }
    }

    public static void unregister_auth_callback(string cookie) {
        var instance = get_instance();
        if (!instance.direct) {
            ((AuthenticatorReceiverApp)instance.system_app).unregister_auth_callback(cookie);
        }
    }

    public static double get_scale() {
        var instance = get_instance().system_app;
        unowned GLib.List<Gtk.Window> windows = instance.get_windows();

        if (windows == null)
            return 1.0;

        return windows.data.get_scale_factor();
    }

    /**
     * @brief This is a helper for library mode that should only be
     * called if we've gotten a camera mount and are _not_ the primary
     * instance.
     */
    public static void send_to_primary_instance(string[]? argv) {
        get_instance().system_app.run(argv);
    }
    
    /**
     * @brief A helper for library mode that tells the primary
     * instance to bring its window to the foreground.  This
     * should only be called if we are _not_ the primary instance.
     */
    public static void present_primary_instance() {
        get_instance().system_app.activate();
    }

    public static bool get_is_remote() {
        return get_instance().system_app.get_is_remote();
    }
    
    public static bool get_is_direct() {
        return get_instance().direct;
    }

    public static void set_accels_for_action (string action, string[] accel) {
        get_instance().system_app.set_accels_for_action (action, accel);
    }

    /**
     * @brief Signal handler for GApplication's 'activate' signal.
     *
     * The most likely scenario for this to be fired is if the user
     * either tried to run us twice in library mode, or we've just gotten
     * a camera/removable-storage mount; in either case, the remote instance
     * will trigger this and exit, and we'll need to bring the window back up...
     */
    public static void on_activated() {
        get_instance();

        LibraryWindow lw = AppWindow.get_instance() as LibraryWindow;
        if ((lw != null) && (!get_is_direct())) {
            LibraryWindow.get_app().present();
        }
    }

    /**
     * @brief Signal handler for GApplication's 'command-line' signal.
     *
     * Gets fired whenever a remote instance tries to run, usually
     * with an incoming camera connection.
     *
     * @note This does _not_ get called in direct-edit mode.
     */
    public static int on_command_line(ApplicationCommandLine acl) {
        string[]? argv = acl.get_arguments();

        if (argv != null) {
            foreach (string s in argv) {
                LibraryWindow lw = AppWindow.get_instance() as LibraryWindow;
                if (lw != null) {
                    lw.mounted_camera_shell_notification(s, false);
                }
            }
        }
        on_activated();
        return 0;
    }

    /**
     * @brief Initializes the Shotwell application object and prepares
     * it for use.
     *
     * @param is_direct Whether the application was invoked in direct
     * or in library mode; defaults to FALSE, that is, library mode.
     *
     * @note This MUST be called prior to calling get_instance(), as the
     * application needs to know what mode it was brought up in; failure to
     * call this first will lead to an assertion.
     */
    public static void init(bool is_direct = false) {
        if (instance == null)
            instance = new Application(is_direct);
    }

    public static void terminate() {
        get_instance().exit();
    }

    public static Application get_instance() {
        assert (instance != null);

        return instance;
    }

    public void start(string[]? argv = null) {
        if (running)
            return;

        running = true;

        starting();

        assert(AppWindow.get_instance() != null);
        system_app.add_window(AppWindow.get_instance());
        system_app_run_retval = system_app.run(argv);

        if (!direct) {
            system_app.command_line.disconnect(on_command_line);
        }

        system_app.activate.disconnect(on_activated);
        system_app.startup.disconnect(on_activated);

        running = false;
    }

    public void exit() {
        // only fire this once, but thanks to terminate(), it will be fired at least once (even
        // if start() is not called and "starting" is not fired)
        if (exiting_fired || !running)
            return;

        exiting_fired = true;

        exiting(false);
    }

    // This will fire the exiting signal with panicked set to true, but only if exit() hasn't
    // already been called.  This call will immediately halt the application.
    public void panic() {
        if (!exiting_fired) {
            exiting_fired = true;
            exiting(true);
        }
        Posix.exit(1);
    }

    /**
     * @brief Allows the caller to ask for some part of the desktop session's functionality to
     * be prevented from running; wrapper for Gtk.Application.inhibit().
     *
     * @note The return value is a 'cookie' that needs to be passed to 'uninhibit' to turn
     * off a requested inhibition and should be saved by the caller.
     */ 
    public uint inhibit(Gtk.ApplicationInhibitFlags what, string? reason="none given") {
        return system_app.inhibit(AppWindow.get_instance(), what, reason);
    }

    /**
     * @brief Turns off a previously-requested inhibition. Wrapper for
     * Gtk.Application.uninhibit().
     */
    public void uninhibit(uint cookie) {
        system_app.uninhibit(cookie);
    }

    public int get_run_return_value() {
        return system_app_run_retval;
    }
}

