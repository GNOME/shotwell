/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Publishing.GooglePhotos {
[GtkTemplate (ui = "/org/gnome/Shotwell/Publishing/google_photos_publishing_options_pane.ui")]
internal class PublishingOptionsPane : Gtk.Box, Spit.Publishing.DialogPane {
    private struct SizeDescription {
        public string name;
        public int major_axis_pixels;
    }

    private const SizeDescription size_descriptions[] = {
        { N_("Small (640 × 480 pixels)"), 640},
        { N_("Medium (1024 × 768 pixels)"), 1024 },
        { N_("Recommended (1600 × 1200 pixels)"), 1600},
        { N_("Google+ (2048 × 1536 pixels)"), 2048},
        { N_("Original Size"), PublishingParameters.ORIGINAL_SIZE }
    };

    [GtkChild]
    private Gtk.Button logout_button;
    [GtkChild]
    private Gtk.Button publish_button;
    [GtkChild]
    private Gtk.RadioButton existing_album_radio;
    [GtkChild]
    private Gtk.ComboBoxText existing_albums_combo;
    [GtkChild]
    private Gtk.ComboBoxText size_combo;
    [GtkChild]
    private Gtk.Label publish_to_label;
    [GtkChild]
    private Gtk.Label login_identity_label;
    [GtkChild]
    private Gtk.CheckButton strip_metadata_check;
    [GtkChild]
    private Gtk.RadioButton new_album_radio;
    [GtkChild]
    private Gtk.Entry new_album_entry;

    public signal void publish();
    public signal void logout();

    private PublishingParameters parameters;

    public PublishingOptionsPane(PublishingParameters parameters, bool can_logout) {
        Object();
        this.parameters = parameters;

        if (!can_logout) {
            logout_button.parent.remove(logout_button);
        }

        // populate any widgets whose contents are programmatically-generated.
        login_identity_label.set_label(_("You are logged into Google Photos as %s.").printf(
            parameters.get_user_name()));
        strip_metadata_check.set_active(parameters.get_strip_metadata());

        if((parameters.get_media_type() & Spit.Publishing.Publisher.MediaType.PHOTO) == 0) {
            publish_to_label.set_label(_("Videos will appear in:"));
            size_combo.set_visible(false);
            size_combo.set_sensitive(false);
        }
        else {
            publish_to_label.set_label(_("Photos will appear in:"));
            foreach(SizeDescription desc in size_descriptions) {
                size_combo.append_text(desc.name);
            }
            size_combo.set_visible(true);
            size_combo.set_sensitive(true);
            size_combo.set_active(parameters.get_major_axis_size_selection_id());
        }

        existing_album_radio.bind_property("active", existing_albums_combo, "sensitive", GLib.BindingFlags.SYNC_CREATE);
        new_album_radio.bind_property("active", new_album_entry, "sensitive", GLib.BindingFlags.SYNC_CREATE);

        publish_button.clicked.connect (on_publish_clicked);
        logout_button.clicked.connect (on_logout_clicked);
    }

    // DialogPane interface
    public Gtk.Widget get_widget() {
        return this;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        int default_album_id = -1;
        string last_album = parameters.get_target_album_name();

        var albums = parameters.get_albums();

        for (int i = 0; i < albums.length; i++) {
            existing_albums_combo.append_text(albums[i].name);
            // Activate last known album id. If none was chosen, either use the old default (Shotwell connect)
            // or the new "Default album" album for Google Photos
            if (albums[i].name == last_album ||
                ((albums[i].name == DEFAULT_ALBUM_NAME || albums[i].name == _("Default album")) && default_album_id == -1))
                default_album_id = i;
        }

        if (default_album_id >= 0) {
            existing_albums_combo.set_active(default_album_id);
            existing_album_radio.set_active(true);
        }

        if (albums.length == 0) {
            existing_album_radio.set_sensitive(false);
            new_album_radio.set_active(true);
        }
    }

    public void on_pane_uninstalled() {
    }

    private void on_publish_clicked() {
        // size_combo won't have been set to anything useful if this is the first time we've
        // published to Google Photos, and/or we've only published video before, so it may be negative,
        // indicating nothing was selected. Clamp it to a valid value...
        int size_combo_last_active = (size_combo.get_active() >= 0) ? size_combo.get_active() : 0;

        parameters.set_major_axis_size_selection_id(size_combo_last_active);
        parameters.set_major_axis_size_pixels(
            size_descriptions[size_combo_last_active].major_axis_pixels);
        parameters.set_strip_metadata(strip_metadata_check.get_active());

        Album[] albums = parameters.get_albums();

        if (new_album_radio.get_active()) {
            parameters.set_target_album_name(new_album_entry.get_text());
        } else {
            parameters.set_target_album_name(albums[existing_albums_combo.get_active()].name);
            parameters.set_target_album_entry_id(albums[existing_albums_combo.get_active()].id);
        }

        publish();
    }

    private void on_logout_clicked() {
        logout();
    }
 }
}
