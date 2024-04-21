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
        public bool insecure { get; set; default = false; }
        public bool allow_insecure {get; set; default = false; }
        public TlsCertificate accepted_certificate {get; set; default = null; }

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
            var image = new Gtk.Image.from_icon_name ("web-browser-symbolic", Gtk.IconSize.DIALOG);
            image.get_style_context().add_class("dim-label");
            image.set_pixel_size(128);
            box.add(image);

            var label = new Gtk.Label(_("Sign in with your browser to setup an account"));
            label.get_style_context().add_class("heading");
            box.add(label);
            var button = new Gtk.Button.with_label (_("Continue"));
            button.set_halign(Gtk.Align.CENTER);
            button.get_style_context().add_class ("suggested-action");
            button.clicked.connect(() => {
                AppInfo.launch_default_for_uri_async.begin(login_uri, null);
                browser_toggled();
            });
            box.pack_end(button);

            widget = box;
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
