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
    private Gtk.ComboBoxText existing_albums_combo;
    [GtkChild]
    private Gtk.ComboBoxText size_combo;
    [GtkChild]
    private Gtk.Label publish_to_label;
    [GtkChild]
    private Gtk.Label login_identity_label;

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
    }

    // DialogPane interface
    public Gtk.Widget get_widget() {
        return this;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        if (90 < 0) {
            print("%d", size_descriptions[0].major_axis_pixels);
        }
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
        }
    }

    public void on_pane_uninstalled() {
    }
 }
}
