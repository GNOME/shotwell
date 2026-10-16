/* Copyright 2016 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */
using Spit.Publishing;

namespace Shotwell.Plugins.Common {
    public class ExternalWebPane : Spit.Publishing.DialogPane, Object {
        public DialogPane.GeometryOptions preferred_geometry {
            get; construct; default = DialogPane.GeometryOptions.COLOSSAL_SIZE;
        }
        public string login_uri { owned get; construct; }
        public Gtk.Widget widget;

        private Gtk.Label error_label;

        public ExternalWebPane(string uri) {
            Object(login_uri: uri);
        }

        public signal void browser_toggled();

        public override void constructed () {
            base.constructed ();
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18);
            box.set_halign(Gtk.Align.CENTER);
            box.hexpand = true;
            box.set_valign(Gtk.Align.CENTER);
            box.vexpand = true;
            var image = new Gtk.Image.from_icon_name ("web-browser-symbolic");
            image.add_css_class("dim-label");
            image.set_pixel_size(128);
            box.append(image);

            var label = new Gtk.Label(_("Sign in with your browser to setup an account"));
            label.add_css_class("heading");
            box.append(label);

            error_label = new Gtk.Label(_("Unable to open the web browser. Please open the following address manually:"));
            error_label.add_css_class("error");
            error_label.set_wrap(true);
            error_label.set_justify(Gtk.Justification.CENTER);
            error_label.set_visible(false);
            box.append(error_label);

            var button = new Gtk.Button.with_label (_("Continue"));
            button.set_halign(Gtk.Align.CENTER);
            button.add_css_class("suggested-actoin");
            button.clicked.connect(() => {
                launch_login_uri.begin();
                browser_toggled();
            });
            box.append(button);

            widget = box;
        }

        private async void launch_login_uri() {
            try {
                yield AppInfo.launch_default_for_uri_async(login_uri, null);
                error_label.set_visible(false);
            } catch (Error err) {
                warning("Unable to open browser for %s: %s", login_uri, err.message);
                error_label.set_text(_("Unable to open the web browser. Please open the following address manually: %s").printf(login_uri));
                error_label.set_visible(true);
            }
        }

        public DialogPane.GeometryOptions get_preferred_geometry() {
            return this.preferred_geometry;
        }

        public Gtk.Widget get_widget() {
            return this.widget;
        }

        public void on_pane_installed () {
        }

        public void on_pane_uninstalled() {
        }        
    }
}
