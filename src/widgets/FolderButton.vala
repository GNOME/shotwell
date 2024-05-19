// SPDX-FileCopyrightText: Jens Georg <mail@jensge.org>
// SPDX-License-Identifier: LGPL-2.1-or-later

namespace Shotwell {
    // Simple button that shows a folder chooser when clicked
    public class FolderButton : Gtk.Button {
        private File _folder;
        public File folder {
            get {
                return _folder;
            }
            set {
                _folder = value;
                this.notify_property("path");
            }
        }
        public string path {
            owned get {
                return folder.get_path();
            }
            set {
                folder = File.new_for_path(value);
            }
        }
        public string title {get; construct; default = null;}

        public FolderButton(File folder, string title) {
            Object(hexpand: false, vexpand: false, halign : Gtk.Align.FILL, icon_name: "folder-symbolic", folder: folder, title: title);
        }

        public override void clicked() {
            var dialog = new Gtk.FileDialog();
            dialog.set_accept_label(_("_OK"));
            dialog.set_initial_folder(folder);
            dialog.set_modal(true);
            dialog.set_title(title);
            var window = (Gtk.Window)get_ancestor(typeof(Gtk.Window));
            dialog.select_folder.begin(window, null, (obj, res) => {
                try {
                    folder = dialog.select_folder.end(res);
                } catch (Error error) {
                    debug("Failed to chose folder: %s", error.message);
                }
            });
        }
    }
}