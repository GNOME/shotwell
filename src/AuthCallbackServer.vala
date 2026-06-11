// SPDX-License-Identifier: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2026 Jens Georg <mail@jensge.org>

namespace Shotwell {
/**
 * An internal HTTP server that listens on localhost to receive OAuth
 * callback redirects from the browser.
 * */
internal class AuthCallbackServer : Object {
    private Soup.Server server;
    private Gee.HashMap<string, Spit.Publishing.AuthenticatedCallback>
        pending_auth_requests = new Gee.HashMap<string, Spit.Publishing.AuthenticatedCallback>();
    private string callback_uri;

    public AuthCallbackServer() throws Error {
        server = new Soup.Server(null);
        server.add_handler("/", on_callback);
        server.listen_local(0, Soup.ServerListenOptions.IPV4_ONLY);
        var uris = server.get_uris();
        if (uris == null || uris.data == null) {
            throw new IOError.FAILED("Failed to determine OAuth callback server port");
        }
        var port = uris.data.get_port();
        callback_uri = "http://127.0.0.1:%u/".printf(port); 
        debug("OAuth callback HTTP server listening on %s", callback_uri);
    }

    public string get_callback_uri() {
        return callback_uri;
    }

    internal void register_auth_callback(string cookie, Spit.Publishing.AuthenticatedCallback cb) {
        pending_auth_requests[cookie] = cb;
    }

    internal void unregister_auth_callback(string cookie) {
        pending_auth_requests.unset(cookie);
    }

    private void on_callback(Soup.Server server, Soup.ServerMessage msg, string path,
                             HashTable<string,string>? query) {

        if (path == "/favicon.ico") {
            msg.set_status(Soup.Status.NOT_FOUND, null);
            return;
        }

        if (path == "/shotwell-logo.svg") {
            try {
                var bytes = resources_lookup_data(
                    "/org/gnome/Shotwell/icons/shotwell.svg",
                    ResourceLookupFlags.NONE);
                msg.set_status(Soup.Status.OK, null);
                msg.set_response("image/svg+xml", Soup.MemoryUse.COPY, bytes.get_data());
                return;
            } catch (Error err) {
                warning("Failed to load icon from resources: %s", err.message);
                msg.set_status(Soup.Status.NOT_FOUND, null);
                var body = "Icon not Found".data;
                msg.set_response("text/plain", Soup.MemoryUse.COPY, body);
                return;
            }
        }

        if (query == null || query.size() == 0) {
            msg.set_status(Soup.Status.BAD_REQUEST, null);
            var body = "Missing query parameters".data;
            msg.set_response("text/plain", Soup.MemoryUse.COPY, body);
            return;
        }

        debug("Got authentication callback: %s", msg.get_uri().to_string());

        if ("sw_auth_cookie" in query) {
            var cookie = query["sw_auth_cookie"];
            // Build a Gee.Map-compatible params hashtable from the query
            var uri_params = new HashTable<string, string>(str_hash, str_equal);
            query.foreach((k, v) => { uri_params.insert(k, v); });

            if (pending_auth_requests.has_key(cookie)) {
                pending_auth_requests[cookie].authenticated(uri_params);
                LibraryWindow.get_app().present();
            } else {
                debug("No call-back registered for cookie %s, probably user cancelled", cookie);
            }
        } else if ("code" in query) {
            // Google OAuth2 callback: the authorization code is passed directly
            var uri_params = new HashTable<string, string>(str_hash, str_equal);
            query.foreach((k, v) => { uri_params.insert(k, v); });

            // For Google, we use the client ID reverse scheme as the cookie key
            var cookie = "com.googleusercontent.apps.534227538559-hvj2e8bj0vfv2f49r7gvjoq6jibfav67";
            if (pending_auth_requests.has_key(cookie)) {
                pending_auth_requests[cookie].authenticated(uri_params);
                LibraryWindow.get_app().present();
            } else {
                debug("No call-back registered for Google auth cookie, probably user cancelled");
            }
        } else {
            debug("Callback does not have recognized parameters. Not accepting");
            msg.set_status(Soup.Status.BAD_REQUEST, null);
            var body = "Unrecognized callback parameters".data;
            msg.set_response("text/plain", Soup.MemoryUse.COPY, body);
            return;
        }

        // Return a success page that the user can close

        // Pre-set with some plaintext in case loading the HTML from 
        // gresource fails
        var success_body = Resources.AUTH_CALLBACK_HEADING.data;
        try {
            var bytes = resources_lookup_data(
                "/org/gnome/Shotwell/auth-callback.html",
                ResourceLookupFlags.NONE);
            var html = (string) bytes.get_data();
            html = html.replace("{{TITLE}}", Resources.AUTH_CALLBACK_TITLE);
            html = html.replace("{{AUTH_COMPLETE_HEADING}}", Resources.AUTH_CALLBACK_HEADING);
            html = html.replace("{{AUTH_COMPLETE_BODY}}", Resources.AUTH_CALLBACK_BODY);
            html = html.replace("{{AUTH_CLOSE_PROMPT}}", Resources.AUTH_CALLBACK_CLOSE_PROMPT);
            success_body = html.data;
        } catch (Error e) {
            warning("Failed to load auth-callback resource: %s",
                e.message);
        }
        msg.set_response("text/html", Soup.MemoryUse.COPY, success_body);
    }
}
}