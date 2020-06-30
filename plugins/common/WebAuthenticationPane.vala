/* Copyright 2016 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */
using Spit.Publishing;

namespace Shotwell.Plugins.Common {
    public abstract class WebAuthenticationPane : Spit.Publishing.DialogPane, Object {
        public DialogPane.GeometryOptions preferred_geometry {
            get; construct; default = DialogPane.GeometryOptions.COLOSSAL_SIZE;
        }

        public string login_uri { owned get; construct; }
        public Error load_error { get; private set; default = null; }

        private WebKit.WebView webview;
        private Gtk.Widget widget;
        private Gtk.Entry entry;

        public void clear() {
            try {
                debug("Clearing the data of WebKit...");
                this.webview.get_website_data_manager().clear.begin(WebKit.WebsiteDataTypes.ALL, (GLib.TimeSpan)0);
            } catch (Error e) {
                // Do nothing
                message("Failed to clear data: %s", e.message);
            }
        }

        public override void constructed () {
            base.constructed ();
            var ctx = WebKit.WebContext.get_default();
            if (!ctx.get_sandbox_enabled()) {
                ctx.set_sandbox_enabled(true);
            }

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            this.widget = box;
            this.entry = new Gtk.Entry();
            this.entry.editable = false;
            this.entry.get_style_context().add_class("flat");
            this.entry.get_style_context().add_class("read-only");
            box.pack_start (entry, false, false, 6);

            this.webview = new WebKit.WebView ();
            this.webview.get_settings ().enable_plugins = false;

            this.webview.load_changed.connect (this.on_page_load_changed);
            this.webview.load_failed.connect (this.on_page_load_failed);
            this.webview.context_menu.connect ( () => { return false; });
            this.webview.decide_policy.connect (this.on_decide_policy);
            this.webview.bind_property("uri", this.entry, "text", GLib.BindingFlags.DEFAULT);
            box.pack_end (this.webview);
        }

        private bool on_decide_policy(WebKit.PolicyDecision decision, WebKit.PolicyDecisionType type) {
            switch (type) {
                case WebKit.PolicyDecisionType.NEW_WINDOW_ACTION: {
                    var navigation = (WebKit.NavigationPolicyDecision) decision;
                    var action = navigation.get_navigation_action();
                    var uri = action.get_request().uri;
                    decision.ignore();
                    AppInfo.launch_default_for_uri_async.begin(uri, null);
                    return true;
                }
                default:
                    break;
            }

            return false;
        }

        public abstract void on_page_load ();

        protected void set_cursor (Gdk.CursorType type) {
            var window = webview.get_window ();
            if (window == null)
                return;

            var display = window.get_display ();
            if (display == null)
                return;

            var cursor = new Gdk.Cursor.for_display (display, type);
            window.set_cursor (cursor);
        }

        private bool on_page_load_failed (WebKit.LoadEvent load_event, string uri, Error error) {
            // OAuth call-back scheme. Produces a load error because it is not HTTP(S)
            // Do not set the load_error, but continue the error handling
            if (uri.has_prefix ("shotwell-auth://"))
                return false;

            critical ("Failed to load uri %s: %s", uri, error.message);
            this.load_error = error;

            return false;
        }

        private void on_page_load_changed (WebKit.LoadEvent load_event) {
            switch (load_event) {
                case WebKit.LoadEvent.STARTED:
                case WebKit.LoadEvent.REDIRECTED:
                    this.set_cursor (Gdk.CursorType.WATCH);
                    break;
                case WebKit.LoadEvent.FINISHED:
                    this.set_cursor (Gdk.CursorType.LEFT_PTR);
                    this.on_page_load ();
                    break;
                default:
                    break;
            }
        }

        public WebKit.WebView get_view () {
            return this.webview;
        }

        public DialogPane.GeometryOptions get_preferred_geometry() {
            return this.preferred_geometry;
        }

        public Gtk.Widget get_widget() {
            return this.widget;
        }

        public void on_pane_installed () {
            this.get_view ().load_uri (this.login_uri);
        }

        public void on_pane_uninstalled() {
            this.clear();
        }
   }
}
