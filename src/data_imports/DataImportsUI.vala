/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DataImportsUI {

internal const string NO_PLUGINS_ENABLED_MESSAGE =
    _("You do not have any data imports plugins enabled.\n\nIn order to use the Import From Application functionality, you need to have at least one data imports plugin enabled. Plugins can be enabled in the Preferences dialog.");

public class ConcreteDialogPane : Spit.DataImports.DialogPane, GLib.Object {
    private Gtk.Box pane_widget;
    
    public ConcreteDialogPane() {
        pane_widget = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
    }
    
    public Gtk.Widget get_widget() {
        return pane_widget;
    }

    public Spit.DataImports.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.DataImports.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
    }

    public void on_pane_uninstalled() {
    }
}

public class StaticMessagePane : ConcreteDialogPane {
    public StaticMessagePane(string message_string) {
        Gtk.Label message_label = new Gtk.Label(message_string);
        (get_widget() as Gtk.Box).pack_start(message_label, true, true, 0);
    }
    
    public StaticMessagePane.with_pango(string msg) {
        Gtk.Label label = new Gtk.Label(null);
        label.set_markup(msg);
        label.set_line_wrap(true);
        
        (get_widget() as Gtk.Box).pack_start(label, true, true, 0);
    }
}

public class LibrarySelectionPane : ConcreteDialogPane {
    private weak Spit.DataImports.PluginHost host;
    private Spit.DataImports.ImportableLibrary? selected_library = null;
    private File? selected_file = null;
    private Gtk.Button import_button;
    private Gtk.RadioButton? file_radio = null;
    
    public LibrarySelectionPane(
        Spit.DataImports.PluginHost host,
        string welcome_message,
        Spit.DataImports.ImportableLibrary[] discovered_libraries,
        string? file_select_label
    ) {
        assert(discovered_libraries.length > 0 || on_file_selected != null);
        
        this.host = host;
        
        Gtk.Box content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        content_box.set_margin_start(30);
        content_box.set_margin_end(30);
        Gtk.Label welcome_label = new Gtk.Label(null);
        welcome_label.set_markup(welcome_message);
        welcome_label.set_line_wrap(true);
        welcome_label.set_halign(Gtk.Align.START);
        content_box.pack_start(welcome_label, true, true, 6);
        
        // margins for buttons
        int radio_margin_left = 20;
        int radio_margin_right = 20;
        int chooser_margin_left = radio_margin_left;
        int chooser_margin_right = radio_margin_right;
        
        Gtk.RadioButton lib_radio = null;
        if (discovered_libraries.length > 0) {
            chooser_margin_left = radio_margin_left + 20;
            foreach (Spit.DataImports.ImportableLibrary library in discovered_libraries) {
                string lib_radio_label = library.get_display_name();
                lib_radio = create_radio_button(
                    content_box, lib_radio, library, lib_radio_label,
                    radio_margin_left, radio_margin_right
                );
            }
            if (file_select_label != null) {
                lib_radio = create_radio_button(
                    content_box, lib_radio, null, file_select_label,
                    radio_margin_left, radio_margin_right
                );
                file_radio = lib_radio;
            }
        }
        if (file_select_label != null) {
            Gtk.FileChooserButton file_chooser = new Gtk.FileChooserButton(_("Database file:"), Gtk.FileChooserAction.OPEN);
            file_chooser.selection_changed.connect(() => {
                selected_file = file_chooser.get_file();
                if (file_radio != null)
                    file_radio.active = true;
                set_import_button_sensitivity();
            });
            file_chooser.set_margin_start(chooser_margin_left);
            file_chooser.set_margin_end(chooser_margin_right);
            content_box.pack_start(file_chooser, false, false, 6);
        }
        
        import_button = new Gtk.Button.with_mnemonic(_("_Import"));
        import_button.clicked.connect(() => {
            if (selected_library != null)
                on_library_selected(selected_library);
            else if (selected_file != null)
                on_file_selected(selected_file);
            else
                debug("LibrarySelectionPane: Library or file should be selected.");
        });
        Gtk.ButtonBox button_box = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL);
        button_box.layout_style = Gtk.ButtonBoxStyle.CENTER;
        button_box.add(import_button);
        content_box.pack_end(button_box, true, false, 6);
        
        (get_widget() as Gtk.Box).pack_start(content_box, true, true, 0);
        
        set_import_button_sensitivity();
    }
    
    private Gtk.RadioButton create_radio_button(
        Gtk.Box box, Gtk.RadioButton? group, Spit.DataImports.ImportableLibrary? library, string label,
        int margin_left, int margin_right
    ) {
        var button = new Gtk.RadioButton.with_label_from_widget (group, label);
        if (group == null) { // first radio button is active
            button.active = true;
            selected_library = library;
        }
        button.toggled.connect (() => {
            if (button.active) {
                this.selected_library = library;
                set_import_button_sensitivity();
            }
            
        });
        button.set_margin_start(margin_left);
        button.set_margin_end(margin_right);
        box.pack_start(button, false, false, 6);
        return button;
    }
    
    private void set_import_button_sensitivity() {
        import_button.set_sensitive(selected_library != null || selected_file != null);
    }
    
    private void on_library_selected(Spit.DataImports.ImportableLibrary library) {
        host.get_data_importer().on_library_selected(library);
    }
    
    private void on_file_selected(File file) {
        host.get_data_importer().on_file_selected(file);
    }
}

public class ProgressPane : ConcreteDialogPane {
    private Gtk.Label message_label;
    private Gtk.Label progress_label;
    private Gtk.ProgressBar progress_bar;
    
    public ProgressPane(string message) {
        Gtk.Box content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        message_label = new Gtk.Label(message);
        content_box.pack_start(message_label, true, true, 6);
        progress_bar = new Gtk.ProgressBar();
        content_box.pack_start(progress_bar, false, true, 6);
        progress_label = new Gtk.Label("");
        content_box.pack_start(progress_label, false, true, 6);
        
        (get_widget() as Gtk.Container).add(content_box);
    }
    
    public void update_progress(double progress, string? progress_message) {
        progress_bar.set_fraction(progress);
        if (progress_message != null)
            progress_label.set_label(progress_message);
        spin_event_loop();
    }
}

public class DataImportsDialog : Gtk.Dialog {
    private const int LARGE_WINDOW_WIDTH = 860;
    private const int LARGE_WINDOW_HEIGHT = 688;
    private const int COLOSSAL_WINDOW_WIDTH = 1024;
    private const int COLOSSAL_WINDOW_HEIGHT = 688;
    private const int STANDARD_WINDOW_WIDTH = 600;
    private const int STANDARD_WINDOW_HEIGHT = 510;
    private const int BORDER_REGION_WIDTH = 16;
    private const int BORDER_REGION_HEIGHT = 100;

    public const int STANDARD_CONTENT_LABEL_WIDTH = 500;
    public const int STANDARD_ACTION_BUTTON_WIDTH = 128;

    private Gtk.ComboBoxText service_selector_box;
    private Gtk.Box central_area_layouter;
    private Gtk.Button close_cancel_button;
    private Spit.DataImports.DialogPane active_pane;
    private Spit.DataImports.ConcreteDataImportsHost host;

    protected DataImportsDialog() {
        bool use_header = Resources.use_header_bar() == 1;
        Object(use_header_bar: Resources.use_header_bar());
        if (use_header)
            ((Gtk.HeaderBar) get_header_bar()).set_show_close_button(false);

        resizable = false;
        delete_event.connect(on_window_close);
        
        string title = _("Import From Application");
        string label = _("Import media _from:");
        
        set_title(title);

        Spit.DataImports.Service[] loaded_services = Spit.DataImports.load_services();
        
        if (loaded_services.length > 0) {
            // Install the service selector part only if there is at least one
            // service to select from
            service_selector_box = new Gtk.ComboBoxText();
            service_selector_box.set_active(0);

            // get the name of the service the user last used
            string? last_used_service = Config.Facade.get_instance().get_last_used_dataimports_service();

            int ticker = 0;
            int last_used_index = -1;
            foreach (Spit.DataImports.Service service in loaded_services) {
                string curr_service_id = service.get_id();
                if (last_used_service != null && last_used_service == curr_service_id)
                    last_used_index = ticker;

                service_selector_box.append_text(service.get_pluggable_name());
                ticker++;
            }
            if (last_used_index >= 0)
                service_selector_box.set_active(last_used_index);
            else
                service_selector_box.set_active(0);

            service_selector_box.changed.connect(on_service_changed);

            if (!use_header)
            {
                var service_selector_box_label = new Gtk.Label.with_mnemonic(label);
                service_selector_box_label.set_mnemonic_widget(service_selector_box);
                service_selector_box_label.halign = Gtk.Align.START;
                service_selector_box_label.valign = Gtk.Align.CENTER;

                /* the wrapper is not an extraneous widget -- it's necessary to prevent the service
                   selection box from growing and shrinking whenever its parent's size changes.
                   When wrapped inside a Gtk.Alignment, the Alignment grows and shrinks instead of
                   the service selection box. */
                service_selector_box.halign = Gtk.Align.END;
                service_selector_box.valign = Gtk.Align.CENTER;
                service_selector_box.hexpand = false;
                service_selector_box.vexpand = false;

                Gtk.Box service_selector_layouter = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
                service_selector_layouter.set_border_width(12);
                service_selector_layouter.add(service_selector_box_label);
                service_selector_layouter.pack_start(service_selector_box, true, true, 0);

                /* 'service area' is the selector assembly plus the horizontal rule dividing it from the
                   rest of the dialog */
                Gtk.Box service_area_layouter = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
                service_area_layouter.pack_start(service_selector_layouter, true, true, 0);
                Gtk.Separator service_central_separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
                service_area_layouter.add(service_central_separator);
                service_area_layouter.halign = Gtk.Align.FILL;
                service_area_layouter.valign = Gtk.Align.START;
                service_area_layouter.hexpand = true;
                service_area_layouter.vexpand = false;

                ((Gtk.Box) get_content_area()).pack_start(service_area_layouter, false, false, 0);
            }
        }
        
        // Intall the central area in all cases
        central_area_layouter = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        ((Gtk.Box) get_content_area()).pack_start(central_area_layouter, true, true, 0);
        

        if (use_header) {
            close_cancel_button = new Gtk.Button.with_mnemonic("_Cancel");
            close_cancel_button.set_can_default(true);
            ((Gtk.HeaderBar) get_header_bar()).pack_start(close_cancel_button);
            if (service_selector_box != null) {
                ((Gtk.HeaderBar) get_header_bar()).pack_end(service_selector_box);
            }
        }
        else {
            add_button (_("_Cancel"), Gtk.ResponseType.CANCEL);
            close_cancel_button = get_widget_for_response (Gtk.ResponseType.CANCEL) as Gtk.Button;
        }
        close_cancel_button.clicked.connect(on_close_cancel_clicked);

        set_standard_window_mode();
        
        if (loaded_services.length > 0) {
            // trigger the selected service if at least one service is available
            on_service_changed();
        } else {
            // otherwise, install a message pane advising the user what to do
            install_pane(new StaticMessagePane.with_pango(NO_PLUGINS_ENABLED_MESSAGE));
            set_close_button_mode();
        }
        
        show_all();
    }
    
    public static DataImportsDialog get_or_create_instance() {
        if (instance == null) {
            instance = new DataImportsDialog();
        }
        return instance;   
    }
    
    public static void terminate_instance() {
        if (instance != null) {
            instance.terminate();
        }
        instance = null;
    }
    
    private bool on_window_close(Gdk.EventAny evt) {
        debug("DataImportsDialog: on_window_close( ): invoked.");
        terminate();
        
        return true;
    }
    
    private void on_service_changed() {
        debug("DataImportsDialog: on_service_changed invoked.");
        string service_name = service_selector_box.get_active_text();
        
        Spit.DataImports.Service? selected_service = null;
        Spit.DataImports.Service[] services = Spit.DataImports.load_all_services();
        foreach (Spit.DataImports.Service service in services) {
            if (service.get_pluggable_name() == service_name) {
                selected_service = service;
                break;
            }
        }
        assert(selected_service != null);

        Config.Facade.get_instance().set_last_used_dataimports_service(selected_service.get_id());

        host = new Spit.DataImports.ConcreteDataImportsHost(selected_service, this);
        host.start_importing();
    }
    
    private void on_close_cancel_clicked() {
        debug("DataImportsDialog: on_close_cancel_clicked( ): invoked.");
        
        terminate();
    }
    
    private void terminate() {
        debug("DataImportsDialog: terminate( ): invoked.");

        if (host != null) {
            host.stop_importing();
            host = null;
        }

        hide();
        destroy();
        instance = null;
    }
    
    private void set_large_window_mode() {
        set_size_request(LARGE_WINDOW_WIDTH, LARGE_WINDOW_HEIGHT);
        central_area_layouter.set_size_request(LARGE_WINDOW_WIDTH - BORDER_REGION_WIDTH,
            LARGE_WINDOW_HEIGHT - BORDER_REGION_HEIGHT);
        resizable = false;
    }
    
    private void set_colossal_window_mode() {
        set_size_request(COLOSSAL_WINDOW_WIDTH, COLOSSAL_WINDOW_HEIGHT);
        central_area_layouter.set_size_request(COLOSSAL_WINDOW_WIDTH - BORDER_REGION_WIDTH,
            COLOSSAL_WINDOW_HEIGHT - BORDER_REGION_HEIGHT);
        resizable = false;
    }

    private void set_standard_window_mode() {
        set_size_request(STANDARD_WINDOW_WIDTH, STANDARD_WINDOW_HEIGHT);
        central_area_layouter.set_size_request(STANDARD_WINDOW_WIDTH - BORDER_REGION_WIDTH,
            STANDARD_WINDOW_HEIGHT - BORDER_REGION_HEIGHT);
        resizable = false;
    }

    private void set_free_sizable_window_mode() {
        resizable = true;
    }

    private void clear_free_sizable_window_mode() {
        resizable = false;
    }

    public Spit.DataImports.DialogPane get_active_pane() {
        return active_pane;
    }

    public void set_close_button_mode() {
        close_cancel_button.set_label(_("_Close"));
        set_default(close_cancel_button);
    }

    public void set_cancel_button_mode() {
        close_cancel_button.set_label(_("_Cancel"));
    }

    public void lock_service() {
        service_selector_box.set_sensitive(false);
    }

    public void unlock_service() {
        service_selector_box.set_sensitive(true);
    }
    
    public void install_pane(Spit.DataImports.DialogPane pane) {
        debug("DataImportsDialog: install_pane( ): invoked.");

        if (active_pane != null) {
            debug("DataImportsDialog: install_pane( ): a pane is already installed; removing it.");

            active_pane.on_pane_uninstalled();
            central_area_layouter.remove(active_pane.get_widget());
        }

        central_area_layouter.pack_start(pane.get_widget(), true, true, 0);
        show_all();

        Spit.DataImports.DialogPane.GeometryOptions geometry_options =
            pane.get_preferred_geometry();
        if ((geometry_options & Spit.Publishing.DialogPane.GeometryOptions.EXTENDED_SIZE) != 0)
            set_large_window_mode();
        else if ((geometry_options & Spit.Publishing.DialogPane.GeometryOptions.COLOSSAL_SIZE) != 0)
            set_colossal_window_mode();
        else
            set_standard_window_mode();

        if ((geometry_options & Spit.Publishing.DialogPane.GeometryOptions.RESIZABLE) != 0)
            set_free_sizable_window_mode();
        else
            clear_free_sizable_window_mode();

        active_pane = pane;
        pane.on_pane_installed();
    }
    
    private static DataImportsDialog? instance;
}

}

