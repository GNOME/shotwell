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
        public bool insecure { get; set; default = false; }
        public bool allow_insecure {get; set; default = false; }
        public TlsCertificate accepted_certificate {get; set; default = null; }

        private WebKit.WebView webview;
        private Gtk.Widget widget;
        private Gtk.Entry entry;

        public void clear() {
            debug("Clearing the data of WebKit...");
            this.webview.get_website_data_manager().clear.begin(WebKit.WebsiteDataTypes.ALL, (GLib.TimeSpan)0);
        }

        public override void constructed () {
            base.constructed ();
            debug("WebPane with login uri %s", this.login_uri);
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

            this.webview.load_changed.connect (this.on_page_load_changed);
            this.webview.load_failed.connect (this.on_page_load_failed);
            this.webview.context_menu.connect ( () => { return false; });
            this.webview.decide_policy.connect (this.on_decide_policy);
            this.webview.load_failed_with_tls_errors.connect ((view, uri, certificate, errors) => {
                if (!allow_insecure) {
                    return false;
                }

                Uri parsed_uri;

                try {
                    parsed_uri = GLib.Uri.parse (uri, UriFlags.NONE);
                } catch (Error err) {
                    assert_not_reached();
                }

                if (!this.insecure) {
                    var pane = new SslCertificatePane.plain (certificate, errors, parsed_uri.get_host());
                    var widget = pane.get_widget();
                    this.webview.hide();
                    box.pack_end (widget);
                    widget.show_all();
                    pane.proceed.connect(() => {
                        accept_certificate(certificate, parsed_uri.get_host(), uri);
                        widget.hide();
                        this.webview.show_all();
                        pane = null;
                    });

                    return true;
                }

                if (certificate.is_same(accepted_certificate)) {
                    accept_certificate(certificate, parsed_uri.get_host(), uri);
                    return true;
                }

                // TODO: Certificate changed from the one the user accetped elsewhere
                return false;
            });
            this.webview.bind_property("uri", this.entry, "text", GLib.BindingFlags.DEFAULT);
            box.pack_end (this.webview);
        }

        private void accept_certificate(TlsCertificate certificate, string host, string uri) {
            this.insecure = true;
            this.accepted_certificate = certificate;
            var web_ctx = WebKit.WebContext.get_default ();
            web_ctx.allow_tls_certificate_for_host (certificate, host);

            Idle.add(() =>{
                this.webview.load_uri (uri);
                return false;
            });
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
            
            if (uri.contains("shotwell-auth")) {
                return false;
            }

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
                case WebKit.LoadEvent.COMMITTED: {
                    TlsCertificate cert;
                    TlsCertificateFlags flags;

                    if (this.webview.get_tls_info (out cert, out flags) && (flags != (TlsCertificateFlags)0)) {
                        this.entry.set_icon_from_icon_name (Gtk.EntryIconPosition.PRIMARY, "channel-insecure-symbolic");
                        this.entry.set_icon_tooltip_text (Gtk.EntryIconPosition.PRIMARY, _("The connection uses a certificate that has problems, but you choose to accept it anyway"));
                    }
                } break;
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
