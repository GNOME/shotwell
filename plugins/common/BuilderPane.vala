/* Copyright 2016 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */
using Spit.Publishing;

namespace Shotwell.Plugins.Common {
    public abstract class BuilderPane : Spit.Publishing.DialogPane, Object {
        public DialogPane.GeometryOptions preferred_geometry {
            get; construct; default = DialogPane.GeometryOptions.NONE;
        }
        public string resource_path { owned get; construct; }
        public bool connect_signals { get; construct; default = false; }
        public string default_id {
            owned get; construct; default = "default";
        }

        private Gtk.Builder builder;
        private Gtk.Widget content;

        public override void constructed () {
            base.constructed ();

            debug ("Adding new builder from path %s", resource_path);

            this.builder = new Gtk.Builder.from_resource (resource_path);
            if (this.connect_signals) {
                this.builder.connect_signals (null);
            }

            this.content = this.builder.get_object ("content") as Gtk.Widget;

            // Just to be sure, if we still use old-style Builder files
            if (this.content.parent != null) {
                this.content.parent.remove (this.content);
            }
        }

        public DialogPane.GeometryOptions get_preferred_geometry () {
            return this.preferred_geometry;
        }

        public Gtk.Widget get_widget () {
            return this.content;
        }

        public Gtk.Builder get_builder () {
            return this.builder;
        }

        public virtual Gtk.Widget get_default_widget () {
            return this.get_builder ().get_object (this.default_id) as Gtk.Widget;
        }

        public virtual void on_pane_installed () {}

        public virtual void on_pane_uninstalled () {}
    }
}
