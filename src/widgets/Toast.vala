// SPDX-FileCopyrightText: Jens Georg <mail@jensge.org>
// SPDX-License-Identifier: LGPL-2.1-or-later

namespace Shotwell {
    public class Toast : Object {
        public string label { get; set; }
        public string? action_name { get; set; default = ""; }
        public string? button_text {get; set; default = ""; }
        public Variant? action_target { get; set; default= null; }

        public Toast(string label, string button_text = "", string action_name = "", Variant? action_target = null) {
            Object(label: label, button_text: button_text, action_name: action_name, action_target: action_target);
        }
    }

    public class ToastOverlay : Object {
        private Gtk.Overlay overlay;
        private Gtk.Revealer revealer;
        private uint autodismiss_timeout = 0;
        public string text { set; get; }
        public string action { set; get; default="";}
        public string button_text { set; get; }
        public Variant? action_target {set; get; }

        public ToastOverlay() {
            Object();

            overlay = new Gtk.Overlay();
            overlay.set_visible(true);
            revealer = new Gtk.Revealer();
            revealer.set_halign(Gtk.Align.CENTER);
            revealer.set_valign(Gtk.Align.START);
            revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_UP);
            overlay.add_overlay(revealer);
            var frame = new Gtk.Frame(null);
            frame.add_css_class("app-notification");
            revealer.set_child(frame);
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 20);
            frame.set_child(box);
            box.set_margin_bottom(5);
            box.set_margin_top(5);
            box.set_margin_end(20);
            box.set_margin_start(20);
            var label = new Gtk.Label(null);
            label.set_hexpand(true);
            label.set_halign(Gtk.Align.START);
            this.bind_property("text", label, "label");
            box.append(label);

            var button = new Gtk.Button();
            button.set_valign(Gtk.Align.END);
            button.clicked.connect(on_action);
            this.bind_property("button_text", button, "label", GLib.BindingFlags.DEFAULT);
            this.bind_property("action", button, "visible", GLib.BindingFlags.SYNC_CREATE, (binding, from, ref to) => {
                to = from.get_string() != "";
                print("%s %s".printf(from.get_string(), (from.get_string() != "").to_string()));

                return true;
            });
            this.bind_property("action", button, "action-name");
            this.bind_property("action-target", button, "action-target");
            box.append(button);

            button = new Gtk.Button();
            button.set_valign(Gtk.Align.END);
            button.set_focus_on_click(false);
            button.set_has_frame(false);
            button.clicked.connect(on_dismissed);
            button.add_css_class("circular");
            button.add_css_class("flat");
            var image = new Gtk.Image.from_icon_name("window-close-symbolic");
            button.set_child(image);
            box.append(button);
        }

        private void on_action(Gtk.Button button) {
        }

        private void on_dismissed(Gtk.Button button) {
            revealer.reveal_child = false;
        }

        private bool on_autodismiss() {
            revealer.reveal_child = false;

            autodismiss_timeout = 0;

            return false;
        }

        public void add_toast(Toast toast) {
            // Remove previous autodismiss
            if (autodismiss_timeout != 0) {
                Source.remove(autodismiss_timeout);
            }
            autodismiss_timeout = Timeout.add_seconds(5, on_autodismiss);
            text = toast.label;
            action = toast.action_name;
            button_text = toast.button_text;
            action_target = toast.action_target;

            revealer.reveal_child = true;
        }

        public Gtk.Widget attach(Gtk.Widget parent) {
            overlay.set_child(parent);

            return overlay;
        }
    }
}

