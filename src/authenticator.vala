// SPDX-License-Identifer: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2022 Jens Georg <mail@jensge.org>

[DBus(name = "org.gnome.Shotwell.Authenticate")]
public interface AuthenticationReceiver : Object {
    public abstract void callback(string url) throws DBusError, IOError;
}

static int main(string[] args) {
    AuthenticationReceiver receiver;

    if (args.length != 2)  {
        print("Usage: %s <callback-uri>\n", args[0]);
        return 1;
    }

    try {
        var uri = Uri.parse(args[1], UriFlags.NONE);
        var scheme = uri.get_scheme();

        if (scheme != "shotwell-oauth2" && !scheme.has_prefix("com.googleusercontent.apps")) {
            critical("Invalid scheme in callback URI \"%s\"", args[1]);
            return 1;
        }
    } catch (Error e) {
        critical("Invalid uri: \"%s\": %s", args[1], e.message);
        return 1;
    }

    try {
        receiver = Bus.get_proxy_sync (BusType.SESSION, "org.gnome.Shotwell", "/org/gnome/Shotwell");
        receiver.callback(args[1]);
    } catch (Error e) {
        critical("Could not connect to remote shotwell instance: %s", e.message);

        return 1;
    }

    return 0;
}