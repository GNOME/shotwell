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
            debug("Clearing the data of WebKit...");
            this.webview.get_website_data_manager().clear.begin(WebKit.WebsiteDataTypes.ALL, (GLib.TimeSpan)0);
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
            box.append (entry);

            this.webview = new WebKit.WebView ();

            this.webview.load_changed.connect (this.on_page_load_changed);
            this.webview.load_failed.connect (this.on_page_load_failed);
            this.webview.context_menu.connect ( () => { return false; });
            this.webview.decide_policy.connect (this.on_decide_policy);
            this.webview.bind_property("uri", this.entry, "text", GLib.BindingFlags.DEFAULT);
            this.webview.set_vexpand(true);
            box.append (this.webview);
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
                    this.widget.set_cursor_from_name ("progress");
                    break;
                case WebKit.LoadEvent.FINISHED:
                    this.widget.set_cursor_from_name ("default");
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
