/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public interface WelcomeServiceEntry : GLib.Object {
    public abstract string get_service_name();

    public abstract void execute();
}

public class WelcomeDialog : Gtk.Dialog {
    Gtk.CheckButton hide_button;
    Gtk.CheckButton? system_pictures_import_check = null;
    Gtk.CheckButton[] external_import_checks = new Gtk.CheckButton[0];
    WelcomeServiceEntry[] external_import_entries = new WelcomeServiceEntry[0];
    Gtk.Label secondary_text;
    Gtk.Label instruction_header;
    Gtk.Box import_content;
    Gtk.Box import_action_checkbox_packer;
    Gtk.Box external_import_action_checkbox_packer;
    Spit.DataImports.WelcomeImportMetaHost import_meta_host;
    bool import_content_already_installed = false;
    bool ok_clicked = false;

    public WelcomeDialog(Gtk.Window owner) {
        Object(use_header_bar : Resources.use_header_bar());
        import_meta_host = new Spit.DataImports.WelcomeImportMetaHost(this);
        bool show_system_pictures_import = is_system_pictures_import_possible();
        Gtk.Widget ok_button = add_button(Resources.OK_LABEL, Gtk.ResponseType.CLOSE);
        set_default_response(Gtk.ResponseType.CLOSE);

        set_title(_("Welcome!"));
        set_resizable(false);
        set_type_hint(Gdk.WindowTypeHint.DIALOG);
        set_transient_for(owner);

        Gtk.Label primary_text = new Gtk.Label("");
        primary_text.set_markup(
            "<span size=\"large\" weight=\"bold\">%s</span>".printf(_("Welcome to Shotwell!")));
        primary_text.xalign = 0.0f;
        primary_text.yalign = 0.5f;
        secondary_text = new Gtk.Label("");
        secondary_text.set_markup("<span weight=\"normal\">%s</span>".printf(
            _("To get started, import photos in any of these ways:")));
        secondary_text.xalign = 0.0f;
        secondary_text.yalign = 0.5f;
        var image = new Gtk.Image.from_icon_name ("shotwell", Gtk.IconSize.DIALOG);

        Gtk.Box header_text = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        header_text.pack_start(primary_text, false, false, 5);
        header_text.pack_start(secondary_text, false, false, 0);

        Gtk.Box header_content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        header_content.pack_start(image, false, false, 0);
        header_content.pack_start(header_text, false, false, 0);

        Gtk.Label instructions = new Gtk.Label("");
        string indent_prefix = "   "; // we can't tell what the indent prefix is going to be so assume we need one

        string arrow_glyph = (get_direction() == Gtk.TextDirection.RTL) ? "◂" : "▸";

        instructions.set_markup(((indent_prefix + "&#8226; %s\n") + (indent_prefix + "&#8226; %s\n")
            + (indent_prefix + "&#8226; %s")).printf(
            _("Choose <span weight=\"bold\">File %s Import From Folder</span>").printf(arrow_glyph),
            _("Drag and drop photos onto the Shotwell window"),
            _("Connect a camera to your computer and import")));
        instructions.xalign = 0.0f;
        instructions.yalign = 0.5f;

        import_action_checkbox_packer = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);

        external_import_action_checkbox_packer = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        import_action_checkbox_packer.add(external_import_action_checkbox_packer);

        if (show_system_pictures_import) {
            system_pictures_import_check = new Gtk.CheckButton.with_mnemonic(
                _("_Import photos from your %s folder").printf(
                get_display_pathname(AppDirs.get_import_dir())));
            import_action_checkbox_packer.add(system_pictures_import_check);
            system_pictures_import_check.set_active(true);
        }

        instruction_header = new Gtk.Label(
            _("You can also import photos in any of these ways:"));
        instruction_header.xalign = 0.0f;
        instruction_header.yalign = 0.5f;
        instruction_header.set_margin_top(20);

        Gtk.Box content = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
        content.pack_start(header_content, true, true, 0);
        import_content = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        content.add(import_content);
        content.pack_start(instructions, false, false, 0);

        hide_button = new Gtk.CheckButton.with_mnemonic(_("_Don’t show this message again"));
        hide_button.set_active(true);
        content.pack_start(hide_button, false, false, 6);
        content.halign = Gtk.Align.FILL;
        content.valign = Gtk.Align.FILL;
        content.hexpand = false;
        content.vexpand = false;
        content.margin_top = 12;
        content.margin_bottom = 0;
        content.margin_start = 12;
        content.margin_end = 12;

        ((Gtk.Box) get_content_area()).pack_start(content, false, false, 0);

        ok_button.grab_focus();

        install_import_content();

        import_meta_host.start();
    }

    private void install_import_content() {
        if (
            (external_import_checks.length > 0 || system_pictures_import_check != null) &&
            (import_content_already_installed == false)
        ) {
            secondary_text.set_markup("");
            import_content.add(import_action_checkbox_packer);
            import_content.add(instruction_header);
            import_content_already_installed = true;
        }
    }

    public void install_service_entry(WelcomeServiceEntry entry) {
        debug("WelcomeDialog: Installing service entry for %s".printf(entry.get_service_name()));
        external_import_entries += entry;
        Gtk.CheckButton entry_check = new Gtk.CheckButton.with_label(
            _("Import photos from your %s library").printf(entry.get_service_name()));
        external_import_checks += entry_check;
        entry_check.set_active(true);
        external_import_action_checkbox_packer.add(entry_check);
        install_import_content();
    }

    /**
     * Connected to the 'response' signal.  This is part of a workaround
     * for the fact that run()-ning this dialog can interfere with displaying
     * images from a camera; please see #4997 for details.
     */
    private void on_dismiss(int resp) {
        if (resp == Gtk.ResponseType.CLOSE) {
            ok_clicked = true;
        }
        hide();
        Gtk.main_quit();
    }

    public bool execute(out WelcomeServiceEntry[] selected_import_entries, out bool do_system_pictures_import) {
        // it's unsafe to call run() here - it interferes with displaying
        // images from a camera - so we process the dialog ourselves.
        response.connect(on_dismiss);
        show_all();
        show();

        // this will block the thread we're in until a matching call
        // to main_quit() is encountered; this happens when either the window
        // is closed or OK is clicked.
        Gtk.main();

        // at this point, the inner main loop will have been exited.
        // we've got the response, so we don't need this signal anymore.
        response.disconnect(on_dismiss);

        bool ok = ok_clicked;
        bool show_dialog = true;

        if (ok)
            show_dialog = !hide_button.get_active();

        // Use a temporary variable as += cannot be used on parameters
        WelcomeServiceEntry[] result = new WelcomeServiceEntry[0];
        for (int i = 0; i < external_import_entries.length; i++) {
            if (external_import_checks[i].get_active() == true)
                result += external_import_entries[i];
        }
        selected_import_entries = result;
        do_system_pictures_import =
            (system_pictures_import_check != null) ? system_pictures_import_check.get_active() : false;

        destroy();

        return show_dialog;
    }

    private static bool is_system_pictures_import_possible() {
        File system_pictures = AppDirs.get_import_dir();
        if (!system_pictures.query_exists(null))
            return false;

        if (!(system_pictures.query_file_type(FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY))
            return false;

        try {
            FileEnumerator syspics_child_enum = system_pictures.enumerate_children("standard::*",
                FileQueryInfoFlags.NONE, null);
            return (syspics_child_enum.next_file(null) != null);
        } catch (Error e) {
            return false;
        }
    }
}
