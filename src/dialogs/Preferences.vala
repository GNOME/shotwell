/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/preferences_dialog.ui")]
public class PreferencesDialog : Gtk.Dialog {
    private class PathFormat {
        public PathFormat(string name, string? pattern) {
            this.name = name;
            this.pattern = pattern;
        }
        public string name;
        public string? pattern;
    }

    private static PreferencesDialog preferences_dialog;

    [GtkChild]
    private Gtk.Switch switch_dark;

    [GtkChild]
    private Gtk.ComboBox photo_editor_combo;
    [GtkChild]
    private Gtk.ComboBox raw_editor_combo;
    private SortedList<AppInfo> external_raw_apps;
    private SortedList<AppInfo> external_photo_apps;
    [GtkChild]
    private Gtk.FileChooserButton library_dir_button;
    [GtkChild]
    private Gtk.ComboBoxText dir_pattern_combo;
    [GtkChild]
    private Gtk.Entry dir_pattern_entry;
    [GtkChild]
    private Gtk.Label dir_pattern_example;
    private bool allow_closing = false;
    private string? lib_dir = null;
    private Gee.ArrayList<PathFormat> path_formats = new Gee.ArrayList<PathFormat>();
    private GLib.DateTime example_date = new GLib.DateTime.local(2009, 3, 10, 18, 16, 11);
    [GtkChild]
    private Gtk.CheckButton lowercase;
    private Plugins.ManifestWidgetMediator plugins_mediator = new Plugins.ManifestWidgetMediator();
    [GtkChild]
    private Gtk.ComboBoxText default_raw_developer_combo;

    [GtkChild]
    private Gtk.CheckButton autoimport;
    [GtkChild]
    private Gtk.CheckButton write_metadata;
    [GtkChild]
    private Gtk.Label pattern_help;
    [GtkChild]
    private Gtk.Notebook preferences_notebook;

    [GtkChild]
    private Gtk.RadioButton transparent_checker_radio;
    [GtkChild]
    private Gtk.RadioButton transparent_solid_radio;
    [GtkChild]
    private Gtk.ColorButton transparent_solid_color;
    [GtkChild]
    private Gtk.RadioButton transparent_none_radio;

    private PreferencesDialog() {
        Object (use_header_bar: Resources.use_header_bar());

        set_parent_window(AppWindow.get_instance().get_parent_window());
        set_transient_for(AppWindow.get_instance());
        delete_event.connect(on_delete);
        response.connect(on_close);

        transparent_checker_radio.toggled.connect(on_radio_changed);
        transparent_solid_radio.toggled.connect(on_radio_changed);
        transparent_none_radio.toggled.connect(on_radio_changed);

        transparent_solid_radio.bind_property("active",
                                              transparent_solid_color,
                                              "sensitive");

        Gdk.RGBA color = Gdk.RGBA();
        color.parse(Config.Facade.get_instance().get_transparent_background_color());
        (transparent_solid_color as Gtk.ColorChooser).rgba = color;
        transparent_solid_color.color_set.connect(on_color_changed);

        switch (Config.Facade.get_instance().get_transparent_background_type()) {
            case "checkered":
                transparent_checker_radio.active = true;
            break;
            case "solid":
                transparent_solid_radio.active = true;
            break;
            default:
                transparent_none_radio.active = true;
            break;
        }

        // Ticket #3162 - Move dir pattern blurb into Gnome help.
        // Because specifying a particular snippet of the help requires
        // us to know where its located, we can't hardcode a URL anymore;
        // instead, we ask for the help path, and if we find it, we tell
        // yelp to read from there, otherwise, we read from system-wide.
        string help_path = Resources.get_help_path();

        if (help_path == null) {
            // We're installed system-wide, so use the system help.
            pattern_help.set_markup("<a href=\"" + Resources.DIR_PATTERN_URI_SYSWIDE + "\">" + _("(Help)") + "</a>");
        } else {
            // We're being run from the build directory; we'll have to handle clicks to this
            // link manually ourselves, due to a limitation of help: URIs.
            pattern_help.set_markup("<a href=\"dummy:\">" + _("(Help)") + "</a>");
            pattern_help.activate_link.connect(on_local_pattern_help);
        }

        add_to_dir_formats(_("Year%sMonth%sDay").printf(Path.DIR_SEPARATOR_S, Path.DIR_SEPARATOR_S),
            "%Y" + Path.DIR_SEPARATOR_S + "%m" + Path.DIR_SEPARATOR_S + "%d");
        add_to_dir_formats(_("Year%sMonth").printf(Path.DIR_SEPARATOR_S), "%Y" +
            Path.DIR_SEPARATOR_S + "%m");
        add_to_dir_formats(_("Year%sMonth-Day").printf(Path.DIR_SEPARATOR_S),
            "%Y" + Path.DIR_SEPARATOR_S + "%m-%d");
        add_to_dir_formats(_("Year-Month-Day"), "%Y-%m-%d");
        add_to_dir_formats(_("Custom"), null); // Custom must always be last.
        dir_pattern_combo.changed.connect(on_dir_pattern_combo_changed);
        dir_pattern_entry.changed.connect(on_dir_pattern_entry_changed);

        lowercase.toggled.connect(on_lowercase_toggled);

        (preferences_notebook.get_nth_page (2) as Gtk.Container).add (plugins_mediator);

        populate_preference_options();

        photo_editor_combo.changed.connect(on_photo_editor_changed);
        raw_editor_combo.changed.connect(on_raw_editor_changed);

        autoimport.set_active(Config.Facade.get_instance().get_auto_import_from_library());

        write_metadata.set_active(Config.Facade.get_instance().get_commit_metadata_to_masters());

        default_raw_developer_combo.append_text(RawDeveloper.CAMERA.get_label());
        default_raw_developer_combo.append_text(RawDeveloper.SHOTWELL.get_label());
        set_raw_developer_combo(Config.Facade.get_instance().get_default_raw_developer());
        default_raw_developer_combo.changed.connect(on_default_raw_developer_changed);
        switch_dark.active = Gtk.Settings.get_default().gtk_application_prefer_dark_theme;
        switch_dark.notify["active"].connect(on_theme_variant_changed);
    }

    public void populate_preference_options() {
        populate_app_combo_box(photo_editor_combo, PhotoFileFormat.get_editable_mime_types(),
            Config.Facade.get_instance().get_external_photo_app(), out external_photo_apps);

        populate_app_combo_box(raw_editor_combo, PhotoFileFormat.RAW.get_mime_types(),
            Config.Facade.get_instance().get_external_raw_app(), out external_raw_apps);

        setup_dir_pattern(dir_pattern_combo, dir_pattern_entry);

        lowercase.set_active(Config.Facade.get_instance().get_use_lowercase_filenames());
    }

    private void on_theme_variant_changed(GLib.Object o, GLib.ParamSpec ps) {
        var config = Config.Facade.get_instance();
        config.set_gtk_theme_variant(switch_dark.active);

        Gtk.Settings.get_default().gtk_application_prefer_dark_theme = switch_dark.active;
    }

    private void on_radio_changed() {
        var config = Config.Facade.get_instance();

        if (transparent_checker_radio.active) {
            config.set_transparent_background_type("checkered");
        } else if (transparent_solid_radio.active) {
            config.set_transparent_background_type("solid");
        } else {
            config.set_transparent_background_type("none");
        }
    }

    private void on_color_changed() {
        var color = (transparent_solid_color as Gtk.ColorChooser).rgba.to_string();
        Config.Facade.get_instance().set_transparent_background_color(color);
    }

    // Ticket #3162, part II - if we're not yet installed, then we have to manually launch
    // the help viewer and specify the full path to the subsection we want...
    private bool on_local_pattern_help(string ignore) {
        try {
            Resources.launch_help(AppWindow.get_instance(), "other-files.page");
        } catch (Error e) {
            message("Unable to launch help: %s", e.message);
        }
        return true;
    }

    private void populate_app_combo_box(Gtk.ComboBox combo_box, string[] mime_types,
        string current_app_executable, out SortedList<AppInfo> external_apps) {
        // get list of all applications for the given mime types
        assert(mime_types.length != 0);
        external_apps = DesktopIntegration.get_apps_for_mime_types(mime_types);

        if (external_apps.size == 0)
            return;

        // populate application ComboBox with app names and icons
        Gtk.CellRendererPixbuf pixbuf_renderer = new Gtk.CellRendererPixbuf();
        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
        combo_box.clear();
        combo_box.pack_start(pixbuf_renderer, false);
        combo_box.pack_start(text_renderer, false);
        combo_box.add_attribute(pixbuf_renderer, "pixbuf", 0);
        combo_box.add_attribute(text_renderer, "text", 1);

        // TODO: need more space between icons and text
        Gtk.ListStore combo_store = new Gtk.ListStore(2, typeof(Gdk.Pixbuf), typeof(string));
        Gtk.TreeIter iter;

        int current_app = -1;

        foreach (AppInfo app in external_apps) {
            combo_store.append(out iter);

            Icon app_icon = app.get_icon();
            try {
                if (app_icon is FileIcon) {
                    combo_store.set_value(iter, 0, scale_pixbuf(new Gdk.Pixbuf.from_file(
                        ((FileIcon) app_icon).get_file().get_path()), Resources.DEFAULT_ICON_SCALE,
                        Gdk.InterpType.BILINEAR, false));
                } else if (app_icon is ThemedIcon) {
                    Gdk.Pixbuf icon_pixbuf =
                        Gtk.IconTheme.get_default().load_icon(((ThemedIcon) app_icon).get_names()[0],
                        Resources.DEFAULT_ICON_SCALE, Gtk.IconLookupFlags.FORCE_SIZE);

                    combo_store.set_value(iter, 0, icon_pixbuf);
                }
            } catch (GLib.Error error) {
                warning("Error loading icon pixbuf: " + error.message);
            }

            combo_store.set_value(iter, 1, app.get_name());

            if (app.get_commandline() == current_app_executable)
                current_app = external_apps.index_of(app);
        }

        // TODO: allow users to choose unlisted applications like Nautilus's "Open with -> Other Application..."

        combo_box.set_model(combo_store);

        if (current_app != -1)
            combo_box.set_active(current_app);
    }

    private void setup_dir_pattern(Gtk.ComboBox combo_box, Gtk.Entry entry) {
        string? pattern = Config.Facade.get_instance().get_directory_pattern();
        bool found = false;
        if (null != pattern) {
            // Locate pre-built text.
            int i = 0;
            foreach (PathFormat pf in path_formats) {
                if (pf.pattern == pattern) {
                    combo_box.set_active(i);
                    found = true;
                    break;
                }
                i++;
            }
        } else {
            // Custom path.
            string? s = Config.Facade.get_instance().get_directory_pattern_custom();
            if (!is_string_empty(s)) {
                combo_box.set_active(path_formats.size - 1); // Assume "custom" is last.
                found = true;
            }
        }

        if (!found) {
            combo_box.set_active(0);
        }

        on_dir_pattern_combo_changed();
    }

    public static void show_preferences() {
        if (preferences_dialog == null)
            preferences_dialog = new PreferencesDialog();

        preferences_dialog.populate_preference_options();
        preferences_dialog.show_all();
        preferences_dialog.library_dir_button.set_current_folder(AppDirs.get_import_dir().get_path());

        // Ticket #3001: Cause the dialog to become active if the user chooses 'Preferences'
        // from the menus a second time.
        preferences_dialog.present();
    }

    // For items that should only be committed when the dialog is closed, not as soon as the change
    // is made.
    private void commit_on_close() {
        Config.Facade.get_instance().set_auto_import_from_library(autoimport.active);
        Config.Facade.get_instance().set_commit_metadata_to_masters(write_metadata.active);

        if (lib_dir != null)
            AppDirs.set_import_dir(lib_dir);

        PathFormat pf = path_formats.get(dir_pattern_combo.get_active());
        if (null == pf.pattern) {
            Config.Facade.get_instance().set_directory_pattern_custom(dir_pattern_entry.text);
            Config.Facade.get_instance().set_directory_pattern(null);
        } else {
            Config.Facade.get_instance().set_directory_pattern(pf.pattern);
        }
    }

    private bool on_delete() {
        if (!get_allow_closing())
            return true;

        commit_on_close();
        return hide_on_delete(); //prevent widgets from getting destroyed
    }

    private void on_close() {
        if (!get_allow_closing())
            return;

        hide();
        commit_on_close();
    }

    private void on_dir_pattern_combo_changed() {
        PathFormat pf = path_formats.get(dir_pattern_combo.get_active());
        if (null == pf.pattern) {
            // Custom format.
            string? dir_pattern = Config.Facade.get_instance().get_directory_pattern_custom();
            if (is_string_empty(dir_pattern))
                dir_pattern = "";
            dir_pattern_entry.set_text(dir_pattern);
            dir_pattern_entry.editable = true;
            dir_pattern_entry.sensitive = true;
        } else {
            dir_pattern_entry.set_text(pf.pattern);
            dir_pattern_entry.editable = false;
            dir_pattern_entry.sensitive = false;
        }
    }

    private void on_dir_pattern_entry_changed() {
         string example = example_date.format(dir_pattern_entry.text);
         if (is_string_empty(example) && !is_string_empty(dir_pattern_entry.text)) {
            // Invalid pattern.
            dir_pattern_example.set_text(_("Invalid pattern"));
            dir_pattern_entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, "dialog-error");
            dir_pattern_entry.set_icon_activatable(Gtk.EntryIconPosition.SECONDARY, false);
            set_allow_closing(false);
         } else {
            // Valid pattern.
            dir_pattern_example.set_text(example);
            dir_pattern_entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, null);
            set_allow_closing(true);
         }
    }

    private void set_allow_closing(bool allow) {
        set_deletable(allow);
        allow_closing = allow;
    }

    private bool get_allow_closing() {
        return allow_closing;
    }

    private void on_photo_editor_changed() {
        int photo_app_choice_index = (photo_editor_combo.get_active() < external_photo_apps.size) ?
            photo_editor_combo.get_active() : external_photo_apps.size;

        AppInfo app = external_photo_apps.get_at(photo_app_choice_index);

        Config.Facade.get_instance().set_external_photo_app(DesktopIntegration.get_app_open_command(app));

        debug("setting external photo editor to: %s", DesktopIntegration.get_app_open_command(app));
    }

    private void on_raw_editor_changed() {
        int raw_app_choice_index = (raw_editor_combo.get_active() < external_raw_apps.size) ?
            raw_editor_combo.get_active() : external_raw_apps.size;

        AppInfo app = external_raw_apps.get_at(raw_app_choice_index);

        Config.Facade.get_instance().set_external_raw_app(app.get_commandline());

        debug("setting external raw editor to: %s", app.get_commandline());
    }

    private RawDeveloper raw_developer_from_combo() {
        if (default_raw_developer_combo.get_active() == 0)
            return RawDeveloper.CAMERA;
        return RawDeveloper.SHOTWELL;
    }

    private void set_raw_developer_combo(RawDeveloper d) {
        if (d == RawDeveloper.CAMERA)
            default_raw_developer_combo.set_active(0);
        else
            default_raw_developer_combo.set_active(1);
    }

    private void on_default_raw_developer_changed() {
        Config.Facade.get_instance().set_default_raw_developer(raw_developer_from_combo());
    }

    private void on_current_folder_changed() {
        lib_dir = library_dir_button.get_filename();
    }

    public override bool map_event(Gdk.EventAny event) {
        var result = base.map_event(event);
        // Set the signal for the lib dir button after the dialog is displayed,
        // because the FileChooserButton has a nasty habit of selecting a
        // different folder when displayed if the provided path doesn't exist.
        // See ticket #3000 for more info.
        library_dir_button.current_folder_changed.connect(on_current_folder_changed);

        return result;
    }

    private void add_to_dir_formats(string name, string? pattern) {
        PathFormat pf = new PathFormat(name, pattern);
        path_formats.add(pf);
        dir_pattern_combo.append_text(name);
    }

    private void on_lowercase_toggled() {
        Config.Facade.get_instance().set_use_lowercase_filenames(lowercase.get_active());
    }
}
