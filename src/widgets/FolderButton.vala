// SPDX-FileCopyrightText: Jens Georg <mail@jensge.org>
// SPDX-License-Identifier: LGPL-2.1-or-later

namespace Shotwell {
    // Simple button that shows a folder chooser when clicked
    public class FolderButton : Gtk.Button {
        public File folder {get; set; default = null;}
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