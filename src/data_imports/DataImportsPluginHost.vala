/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Spit.DataImports {

private class CoreImporter {
    private weak Spit.DataImports.PluginHost host;
    public int imported_items_count = 0;
    public BatchImportRoll? current_import_roll = null;
    
    public CoreImporter(Spit.DataImports.PluginHost host) {
        this.host = host;
    }
    
    public void prepare_media_items_for_import(
        ImportableMediaItem[] items,
        double progress,
        double host_progress_delta = 0.0,
        string? progress_message = null
    ) {
        host.update_import_progress_pane(progress, progress_message);
        //
        SortedList<DataImportJob> jobs =
            new SortedList<DataImportJob>(import_job_comparator);
        Gee.ArrayList<DataImportJob> already_imported =
            new Gee.ArrayList<DataImportJob>();
        Gee.ArrayList<DataImportJob> failed =
            new Gee.ArrayList<DataImportJob>();
        
        int item_idx = 0;
        double item_progress_delta = host_progress_delta / items.length;
        foreach (ImportableMediaItem src_item in items) {
            DataImportSource import_source = new DataImportSource(src_item);
            
            if (!import_source.was_backing_file_found()) {
                message("Skipping import of %s: backing file not found", 
                    import_source.get_filename());
                failed.add(new DataImportJob(import_source));
                
                continue;
            }
            
            if (import_source.is_already_imported()) {
                message("Skipping import of %s: checksum detected in library", 
                    import_source.get_filename());
                already_imported.add(new DataImportJob(import_source));
                
                continue;
            }
            
            jobs.add(new DataImportJob(import_source));
            item_idx++;
            host.update_import_progress_pane(progress + item_idx * item_progress_delta);
        }
        
        if (jobs.size > 0) {
            // If there it no current import roll, create one to ensure that all
            // imported items end up in the same roll even if this method is called
            // several times
            if (current_import_roll == null)
                current_import_roll = new BatchImportRoll();
            string db_name = _("%s Database").printf(host.get_data_importer().get_service().get_pluggable_name());
            BatchImport batch_import = new BatchImport(jobs, db_name, data_import_reporter,
                failed, already_imported, null, current_import_roll);
            
            LibraryWindow.get_app().enqueue_batch_import(batch_import, true);
            imported_items_count += jobs.size;
        }
        
        host.update_import_progress_pane(progress + host_progress_delta);
    }
    
    public void finalize_import() {
        // Send an empty job to the queue to mark the end of the import
        string db_name = _("%s Database").printf(host.get_data_importer().get_service().get_pluggable_name());
        BatchImport batch_import = new BatchImport(
            new Gee.ArrayList<BatchImportJob>(), db_name, data_import_reporter, null, null, null, current_import_roll
        );
        LibraryWindow.get_app().enqueue_batch_import(batch_import, true);
        current_import_roll = null;
    }
}

public class ConcreteDataImportsHost : Plugins.StandardHostInterface,
    Spit.DataImports.PluginHost {
    
    private Spit.DataImports.DataImporter active_importer = null;
    private weak DataImportsUI.DataImportsDialog dialog = null;
    private DataImportsUI.ProgressPane? progress_pane = null;
    private bool importing_halted = false;
    private CoreImporter core_importer;
    
    public ConcreteDataImportsHost(Service service, DataImportsUI.DataImportsDialog dialog) {
        base(service, "data_imports");
        this.dialog = dialog;
        
        this.active_importer = service.create_data_importer(this);
        this.core_importer = new CoreImporter(this);
    }
    
    public DataImporter get_data_importer() {
        return active_importer;
    }
    
    public void start_importing() {
        if (get_data_importer().is_running())
            return;

        debug("ConcreteDataImportsHost.start_importing( ): invoked.");
        
        get_data_importer().start();
    }

    public void stop_importing() {
        debug("ConcreteDataImportsHost.stop_importing( ): invoked.");
        
        if (get_data_importer().is_running())
            get_data_importer().stop();

        clean_up();

        importing_halted = true;
    }
    
    private void clean_up() {
        progress_pane = null;
    }
    
    public void set_button_mode(Spit.DataImports.PluginHost.ButtonMode mode) {
        if (mode == Spit.DataImports.PluginHost.ButtonMode.CLOSE)
            dialog.set_close_button_mode();
        else if (mode == Spit.DataImports.PluginHost.ButtonMode.CANCEL)
            dialog.set_cancel_button_mode();
        else
            error("unrecognized button mode enumeration value");
    }
    
    // Pane handling methods
    
    public void post_error(Error err) {
        post_error_message(err.message);
    }
    
    public void post_error_message(string message) {
        string msg = _("Importing from %s can’t continue because an error occurred:").printf(
            active_importer.get_service().get_pluggable_name());
        msg += GLib.Markup.printf_escaped("\n\n<i>%s</i>\n\n", message);
        msg += _("To try importing from another service, select one from the above menu.");
        
        dialog.install_pane(new DataImportsUI.StaticMessagePane.with_pango(msg));
        dialog.set_close_button_mode();
        dialog.unlock_service();

        get_data_importer().stop();
        
        // post_error_message( ) tells the active_importer to stop importing and displays a
        // non-removable error pane that effectively ends the publishing interaction,
        // so no problem calling clean_up( ) here.
        clean_up();
    }
    
    public void install_dialog_pane(Spit.DataImports.DialogPane pane,
        Spit.DataImports.PluginHost.ButtonMode button_mode = Spit.DataImports.PluginHost.ButtonMode.CANCEL) {
        debug("DataImports.PluginHost: install_dialog_pane( ): invoked.");

        if (get_data_importer() == null || (!get_data_importer().is_running()))
            return;

        dialog.install_pane(pane);
        
        set_button_mode(button_mode);
    }

    public void install_static_message_pane(string message,
        Spit.DataImports.PluginHost.ButtonMode button_mode = Spit.DataImports.PluginHost.ButtonMode.CANCEL) {
        
        set_button_mode(button_mode);

        dialog.install_pane(new DataImportsUI.StaticMessagePane.with_pango(message));
    }
        
    public void install_library_selection_pane(
        string welcome_message,
        ImportableLibrary[] discovered_libraries,
        string? file_select_label
    ) {
        if (discovered_libraries.length == 0 && file_select_label == null)
            post_error_message("Libraries or file option needed");
        else
            dialog.install_pane(new DataImportsUI.LibrarySelectionPane(
                this,
                welcome_message,
                discovered_libraries,
                file_select_label
            ));
        set_button_mode(Spit.DataImports.PluginHost.ButtonMode.CLOSE);
    }
    
    public void install_import_progress_pane(
        string message
    ) {
        progress_pane = new DataImportsUI.ProgressPane(message);
        dialog.install_pane(progress_pane);
        set_button_mode(Spit.DataImports.PluginHost.ButtonMode.CANCEL);
        // initialize the import
        core_importer.imported_items_count = 0;
        core_importer.current_import_roll = null;
    }
    
    public void update_import_progress_pane(
        double progress,
        string? progress_message = null
    ) {
        if (progress_pane != null) {
            progress_pane.update_progress(progress, progress_message);
        }
    }
    
    public void prepare_media_items_for_import(
        ImportableMediaItem[] items,
        double progress,
        double host_progress_delta = 0.0,
        string? progress_message = null
    ) {
        core_importer.prepare_media_items_for_import(items, progress, host_progress_delta, progress_message);
    }
    
    public void finalize_import(
        ImportedItemsCountCallback report_imported_items_count,
        string? finalize_message = null
    ) {
        update_import_progress_pane(1.0, finalize_message);
        set_button_mode(Spit.DataImports.PluginHost.ButtonMode.CLOSE);
        core_importer.finalize_import();
        report_imported_items_count(core_importer.imported_items_count);
        if (core_importer.imported_items_count > 0)
            LibraryWindow.get_app().switch_to_import_queue_page();
    }
}

public class WelcomeDataImportsHost : Plugins.StandardHostInterface,
    Spit.DataImports.PluginHost {
    
    private weak WelcomeImportMetaHost meta_host;
    private Spit.DataImports.DataImporter active_importer = null;
    private bool importing_halted = false;
    private CoreImporter core_importer;
    
    public WelcomeDataImportsHost(Service service, WelcomeImportMetaHost meta_host) {
        base(service, "data_imports");
        
        this.active_importer = service.create_data_importer(this);
        this.core_importer = new CoreImporter(this);
        this.meta_host = meta_host;
    }
    
    public DataImporter get_data_importer() {
        return active_importer;
    }
    
    public void start_importing() {
        if (get_data_importer().is_running())
            return;

        debug("WelcomeDataImportsHost.start_importing( ): invoked.");
        
        get_data_importer().start();
    }

    public void stop_importing() {
        debug("WelcomeDataImportsHost.stop_importing( ): invoked.");
        
        if (get_data_importer().is_running())
            get_data_importer().stop();

        clean_up();

        importing_halted = true;
    }
    
    private void clean_up() {
    }
    
    // Pane handling methods
    
    public void post_error(Error err) {
        post_error_message(err.message);
    }
    
    public void post_error_message(string message) {
        string msg = _("Importing from %s can’t continue because an error occurred:").printf(
            active_importer.get_service().get_pluggable_name());
        
        debug(msg);

        get_data_importer().stop();
        
        // post_error_message( ) tells the active_importer to stop importing and displays a
        // non-removable error pane that effectively ends the publishing interaction,
        // so no problem calling clean_up( ) here.
        clean_up();
    }
    
    public void install_dialog_pane(Spit.DataImports.DialogPane pane,
        Spit.DataImports.PluginHost.ButtonMode button_mode = Spit.DataImports.PluginHost.ButtonMode.CANCEL) {
        // do nothing
    }
        
    public void install_static_message_pane(string message,
        Spit.DataImports.PluginHost.ButtonMode button_mode = Spit.DataImports.PluginHost.ButtonMode.CANCEL) {
        // do nothing
    }
        
    public void install_library_selection_pane(
        string welcome_message,
        ImportableLibrary[] discovered_libraries,
        string? file_select_label
    ) {
        debug("WelcomeDataImportsHost: Installing library selection pane for %s".printf(get_data_importer().get_service().get_pluggable_name()));
        if (discovered_libraries.length > 0) {
            meta_host.install_service_entry(new WelcomeImportServiceEntry(
                this,
                get_data_importer().get_service().get_pluggable_name(),
                discovered_libraries
            ));
        }
    }
    
    public void install_import_progress_pane(
        string message
    ) {
        // empty implementation
    }
    
    public void update_import_progress_pane(
        double progress,
        string? progress_message = null
    ) {
        // empty implementation
    }
    
    public void prepare_media_items_for_import(
        ImportableMediaItem[] items,
        double progress,
        double host_progress_delta = 0.0,
        string? progress_message = null
    ) {
        core_importer.prepare_media_items_for_import(items, progress, host_progress_delta, progress_message);
    }
    
    public void finalize_import(
        ImportedItemsCountCallback report_imported_items_count,
        string? finalize_message = null
    ) {
        core_importer.finalize_import();
        report_imported_items_count(core_importer.imported_items_count);
        meta_host.finalize_import(this);
    }
}


//public delegate void WelcomeImporterCallback();

public class WelcomeImportServiceEntry : GLib.Object, WelcomeServiceEntry {
    private string pluggable_name;
    private ImportableLibrary[] discovered_libraries;
    private Spit.DataImports.PluginHost host;
    
    public WelcomeImportServiceEntry(
        Spit.DataImports.PluginHost host,
        string pluggable_name, ImportableLibrary[] discovered_libraries) {
        
        this.host = host;
        this.pluggable_name = pluggable_name;
        this.discovered_libraries = discovered_libraries;
    }
    
    public string get_service_name() {
        return pluggable_name;
    }
    
    public void execute() {
        foreach (ImportableLibrary library in discovered_libraries) {
            host.get_data_importer().on_library_selected(library);
        }
    }
}

public class WelcomeImportMetaHost : GLib.Object {
    private WelcomeDialog dialog;
    
    public WelcomeImportMetaHost(WelcomeDialog dialog) {
        this.dialog = dialog;
    }
    
    public void start() {
        Service[] services = load_all_services();
        foreach (Service service in services) {
            WelcomeDataImportsHost host = new WelcomeDataImportsHost(service, this);
            host.start_importing();
        }
    }
    
    public void finalize_import(WelcomeDataImportsHost host) {
        host.stop_importing();
    }
    
    public void install_service_entry(WelcomeServiceEntry entry) {
        debug("WelcomeImportMetaHost: Installing service entry for %s".printf(entry.get_service_name()));
        dialog.install_service_entry(entry);
    }
}

public static Spit.DataImports.Service[] load_all_services() {
    return load_services(true);
}

public static Spit.DataImports.Service[] load_services(bool load_all = false) {
    Spit.DataImports.Service[] loaded_services = new Spit.DataImports.Service[0];
    
    // load publishing services from plug-ins
    Gee.Collection<Spit.Pluggable> pluggables = Plugins.get_pluggables_for_type(
        typeof(Spit.DataImports.Service), null, load_all);
        // TODO: include sorting function to ensure consistent order
        
    debug("DataImportsDialog: discovered %d pluggable data import services.", pluggables.size);

    foreach (Spit.Pluggable pluggable in pluggables) {
        int pluggable_interface = pluggable.get_pluggable_interface(
            Spit.DataImports.CURRENT_INTERFACE, Spit.DataImports.CURRENT_INTERFACE);
        if (pluggable_interface != Spit.DataImports.CURRENT_INTERFACE) {
            warning("Unable to load data import plugin %s: reported interface %d.",
                Plugins.get_pluggable_module_id(pluggable), pluggable_interface);
            
            continue;
        }
        
        Spit.DataImports.Service service =
            (Spit.DataImports.Service) pluggable;

        debug("DataImportsDialog: discovered pluggable data import service '%s'.",
            service.get_pluggable_name());
        
        loaded_services += service;
    }
    
    // Sort import services by name.
    // TODO: extract to a function to sort it on initial request
    Posix.qsort(loaded_services, loaded_services.length, sizeof(Spit.DataImports.Service), 
        (a, b) => {return utf8_cs_compare((*((Spit.DataImports.Service**) a))->get_pluggable_name(), 
            (*((Spit.DataImports.Service**) b))->get_pluggable_name());
    });
    
    return loaded_services;
}

private ImportManifest? meta_manifest = null;

private void data_import_reporter(ImportManifest manifest, BatchImportRoll import_roll) {
    if (manifest.all.size > 0) {
        if (meta_manifest == null)
            meta_manifest = new ImportManifest();
        foreach (BatchImportResult result in manifest.all) {
            meta_manifest.add_result(result);
        }
    } else {
        DataImportsUI.DataImportsDialog.terminate_instance();
        ImportUI.report_manifest(meta_manifest, true);
        meta_manifest = null;
    }
}

private int64 import_job_comparator(void *a, void *b) {
    return ((DataImportJob *) a)->get_exposure_time()
        - ((DataImportJob *) b)->get_exposure_time();
}

}

