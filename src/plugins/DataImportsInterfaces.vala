/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Shotwell Pluggable Data Imports API
 *
 * The Shotwell Pluggable Data Imports API allows you to write plugins that import
 * information from other media library databases to help migration to Shotwell.
 * The Shotwell distribution includes import support for F-Spot.
 * To enable Shotwell to import from additional libaries, developers like you write
 * data import plugins, dynamically-loadable shared objects that are linked into the
 * Shotwell process at runtime. Data import plugins are just one of several kinds of
 * plugins supported by {@link Spit}, the Shotwell Pluggable Interfaces Technology.
 */
namespace Spit.DataImports {

/**
 * The current version of the Pluggable Data Import API
 */
public const int CURRENT_INTERFACE = 0;

/**
 * The error domain for alien databases
 */
public errordomain DataImportError {
    /**
     * Indicates that the version of the external database being imported is
     * not supported by this version of the plugin.
     *
     * This occurs for example when trying to import an F-Spot database that
     * has a version that is more recent than what the current plugin supports.
     */
    UNSUPPORTED_VERSION
}

/** 
 * Represents a module that is able to import data from a specific database format.
 *
 * Developers of data import plugins provide a class that implements this interface. At
 * any given time, only one DataImporter can be running. When a data importer is running, it
 * has exclusive use of the shared user-interface and
 * configuration services provided by the {@link PluginHost}. Data importers are created in
 * a non-running state and do not begin running until start( ) is invoked. Data importers
 * run until stop( ) is invoked.
 */
public interface DataImporter : GLib.Object {
    /**
     * Returns a {@link Service} object describing the service to which this connects.
     */
    public abstract Service get_service();

    /**
     * Makes this data importer enter the running state and endows it with exclusive access
     * to the shared services provided by the {@link PluginHost}. Through the host’s interface,
     * this data importer can install user interface panes and query configuration information.
     */
    public abstract void start();

    /**
     * Returns true if this data importer is in the running state; false otherwise.
     */
    public abstract bool is_running();
    
    /**
     * Causes this data importer to enter a non-running state. This data importer should stop all
     * data access operations and cease use of the shared services provided by the {@link PluginHost}.
     */
    public abstract void stop();
    
    /**
     * Causes this data importer to enter start the import of a library.
     */
    public abstract void on_library_selected(ImportableLibrary library);
    
    /**
     * Causes this data importer to enter start the import of a library file.
     */
    public abstract void on_file_selected(File file);
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

/**
 * Represents a library of importable media items.
 *
 * Developers of data import plugins provide a class that implements this interface.
 */
public interface ImportableLibrary : GLib.Object {
    public abstract string get_display_name();
}

/**
 * Represents an importable media item such as a photo or a video file.
 *
 * Developers of data import plugins provide a class that implements this interface.
 */
public interface ImportableMediaItem : GLib.Object {
    public abstract ImportableTag[] get_tags();
    
    public abstract ImportableEvent? get_event();
    
    public abstract ImportableRating get_rating();
    
    public abstract string? get_title();
    
    public abstract string get_folder_path();
    
    public abstract string get_filename();

    public abstract time_t? get_exposure_time();
}

/**
 * Represents an importable tag.
 *
 * Developers of data import plugins provide a class that implements this interface.
 */
public interface ImportableTag : GLib.Object {
    public abstract string get_name();
    
    public abstract ImportableTag? get_parent();
}

/**
 * Represents an importable event.
 *
 * Developers of data import plugins provide a class that implements this interface.
 */
public interface ImportableEvent : GLib.Object {
    public abstract string get_name();
}

/**
 * Represents an importable rating value.
 *
 * Developers of data import plugins provide a class that implements this interface.
 * Note that the value returned by the get_value method should be a value between
 * 1 and 5, unless the rating object is unrated or rejected, in which case the
 * value is unspecified.
 */
public interface ImportableRating : GLib.Object {
    public abstract bool is_unrated();
    
    public abstract bool is_rejected();
    
    public abstract int get_value();
}

/**
 * Encapsulates a pane that can be installed in the on-screen import dialog box to
 * communicate status to and to get information from the user.
 *
 */
public interface DialogPane : GLib.Object {

    /**
     * Describes how the on-screen publishing dialog box should look and behave when an associated
     * pane is installed in the on-screen publishing dialog box.
     */
    public enum GeometryOptions {
    
        /**
         * When the associated pane is installed, the on-screen publishing dialog box will be
         * sized normally and will not allow the user to change its size.
         */
        NONE =          0,

        /**
         * If this bit is set, when the associated pane is installed, the on-screen publishing
         * dialog box will grow to a larger size.
         */
        EXTENDED_SIZE = 1 << 0,

        /**
         * If this bit is set, when the associated pane is installed, the on-screen publishing
         * dialog box will allow the user to change its size.
         */
        RESIZABLE =     1 << 1,

        /**
         * If this bit is set, when the associated pane is installed, the on-screen publishing
         * dialog box will grow to accommodate a full-width 1024 pixel web page. If both
         * EXTENDED_SIZE and COLOSSAL_SIZE are set, EXTENDED_SIZE takes precedence.
         */
        COLOSSAL_SIZE = 1 << 2;
    }

    /**
     * Returns the Gtk.Widget that is this pane's on-screen representation.
     */
    public abstract Gtk.Widget get_widget();
    
    /**
     * Returns a {@link GeometryOptions} bitfield describing how the on-screen publishing dialog
     * box should look and behave when this pane is installed.
     */
    public abstract GeometryOptions get_preferred_geometry();

    /**
     * Invoked automatically by Shotwell when this pane has been installed into the on-screen
     * publishing dialog box and become visible to the user.
     */
    public abstract void on_pane_installed();

    /**
     * Invoked automatically by Shotwell when this pane has been removed from the on-screen
     * publishing dialog box and is no longer visible to the user.
     */
    public abstract void on_pane_uninstalled();
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

/**
 * Called by the data imports system at the end of an import batch to report
 * to the plugin the number of items that were really imported. This enables
 * the plugin to display a final message to the user. However, the plugin
 * should not rely on this callback being called in order to clean up.
 */
public delegate void ImportedItemsCountCallback(int imported_items_count);

/**
 * Manages and provides services for data import plugins.
 *
 * Implemented inside Shotwell, the PluginHost provides an interface through which the
 * developers of data import plugins can query and make changes to the import
 * environment. Plugins can use the services of the PluginHost only when their
 * {@link DataImporter} is in the running state. This ensures that non-running data importers
 * don’t destructively interfere with the actively running importer.
 */
public interface PluginHost : GLib.Object, Spit.HostInterface {

    /**
     * Specifies the label text on the push button control that appears in the
     * lower-right-hand corner of the on-screen publishing dialog box.
     */
    public enum ButtonMode {
        CLOSE = 0,
        CANCEL = 1
    }
    
    /**
     * Notifies the user that an unrecoverable import error has occurred and halts
     * the import process.
     *
     * @param err An error object that describes the kind of error that occurred.
     */
    public abstract void post_error(Error err);

    /**
     * Notifies the user that an unrecoverable import error has occurred and halts
     * the import process.
     *
     * @param msg A message that describes the kind of error that occurred.
     */
    public abstract void post_error_message(string msg);

    /**
     * Starts the import process.
     *
     * Calling this method starts the import activity for this host.
     */
    public abstract void start_importing();

    /**
     * Halts the import process.
     *
     * Calling this method stops all import activity and hides the on-screen import
     * dialog box.
     */
    public abstract void stop_importing();

    /**
     * Returns a reference to the {@link DataImporter} object that this is currently hosting.
     */
    public abstract DataImporter get_data_importer();

    /**
     * Attempts to install a pane in the on-screen data import dialog box, making the pane visible
     * and allowing it to interact with the user.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     * 
     * @param pane the pane to install
     *
     * @param mode allows you to set the text displayed on the close/cancel button in the
     * lower-right-hand corner of the on-screen data import dialog box when pane is installed.
     * If mode is ButtonMode.CLOSE, the button will have the title "Close." If mode is
     * ButtonMode.CANCEL, the button will be titled "Cancel." You should set mode depending on
     * whether a cancellable action is in progress. For example, if your importer is in the
     * middle of processing 3 of 8 videos, then mode should be ButtonMode.CANCEL. However, if
     * the processing operation has completed and the success pane is displayed, then mode
     * should be ButtonMode.CLOSE, because all cancellable actions have already
     * occurred.
     */
    public abstract void install_dialog_pane(Spit.DataImports.DialogPane pane,
        ButtonMode mode = ButtonMode.CANCEL);

    /**
     * Attempts to install a pane in the on-screen data import dialog box that contains
     * static text.
     *
     * The text appears centered in the data import dialog box and is drawn in
     * the system font. This is a convenience method only; similar results could be
     * achieved by manually constructing a Gtk.Label widget, wrapping it inside a
     * {@link DialogPane}, and installing it manually with a call to
     * install_dialog_pane( ). To provide visual consistency across data import services,
     * however, always use this convenience method instead of constructing label panes when
     * you need to display static text to the user.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     * 
     * @param message the text to show in the pane
     *
     * @param mode allows you to set the text displayed on the close/cancel button in the
     * lower-right-hand corner of the on-screen data import dialog box when pane is installed.
     * If mode is ButtonMode.CLOSE, the button will have the title "Close." If mode is
     * ButtonMode.CANCEL, the button will be titled "Cancel." You should set mode depending on
     * whether a cancellable action is in progress. For example, if your importer is in the
     * middle of processing 3 of 8 videos, then mode should be ButtonMode.CANCEL. However, if
     * the processing operation has completed and the success pane is displayed, then mode
     * should be ButtonMode.CLOSE, because all cancellable actions have already
     * occurred.
     */
    public abstract void install_static_message_pane(string message,
        ButtonMode mode = ButtonMode.CANCEL);
    
    /**
     * Attempts to install a library selection pane that presents a list of
     * discovered libraries to the user.
     *
     * When the user clicks the “OK” button, you’ll be notified of the user’s action through
     * the 'on_library_selected' callback if a discovered library was selected or through
     * the 'on_file_selected' callback if a file was selected.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     *
     * @param welcome_message the text to be displayed above the list of discovered
     * libraries.
     *
     * @param discovered_libraries the list of importable libraries that the plugin
     * has discovered in well known locations.
     *
     * @param file_select_label the label to display for the file selection
     * option. If this label is null, the
     * user will not be presented with a file selection option.
     */
    public abstract void install_library_selection_pane(
        string welcome_message,
        ImportableLibrary[] discovered_libraries,
        string? file_select_label
    );
    
    /**
     * Attempts to install a progress pane that provides the user with feedback
     * on import preparation.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     *
     * @param message the text to be displayed above the progress bar.
     */
    public abstract void install_import_progress_pane(
        string message
    );
    
    /**
     * Update the progress bar installed by install_import_progress_pane.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     *
     * @param progress a value between 0.0 and 1.0 identifying progress for the
     * plugin.
     *
     * @param progress_label the text to be displayed below the progress bar. If that
     * parameter is null, the message will be left unchanged.
     */
    public abstract void update_import_progress_pane(
        double progress,
        string? progress_message = null
    );
    
    /**
     * Sends an importable media item to the host in order to prepare it for import
     * and update the progress bar installed by install_import_progress_pane.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     *
     * @param item the importable media item to prepare for import.
     *
     * @param progress a value between 0.0 and 1.0 identifying progress for the
     * plugin.
     *
     * @param host_progress_delta the amount of progress the host should update
     * the progress bar during import preparation. Plugins should ensure that
     * a proportion of progress for each media item is set aside for the host
     * in oder to ensure a smoother update to the progress bar.
     *
     * @param progress_message the text to be displayed below the progress bar. If that
     * parameter is null, the message will be left unchanged.
     */
    public abstract void prepare_media_items_for_import(
        ImportableMediaItem[] items,
        double progress,
        double host_progress_delta = 0.0,
        string? progress_message = null
    );
    
    /**
     * Finalize the import sequence for the plugin. This tells the host that
     * all media items have been processed and that the plugin has finished all
     * import work. Once this method has been called, all resources used by the
     * plugin for import should be released and the plugin should be back to the
     * state it had just after running the start method. The host will then display
     * the final message and show progress as fully complete. In a standard import
     * scenario, the user is expected to click the Close button to dismiss the
     * dialog. On first run, the host may call the LibrarySelectedCallback again
     * to import another library handled by the same plugin.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     *
     * @param finalize_message the text to be displayed below the progress bar. If that
     * parameter is null, the message will be left unchanged.
     */
    public abstract void finalize_import(
        ImportedItemsCountCallback report_imported_items_count,
        string? finalize_message = null
    );
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

/**
 * Describes the features and capabilities of a data import service.
 *
 * Developers of data import plugins provide a class that implements this interface.
 */
public interface Service : Object, Spit.Pluggable {
    /**
     * A factory method that instantiates and returns a new {@link DataImporter} object
     * that this Service describes.
     */
    public abstract Spit.DataImports.DataImporter create_data_importer(Spit.DataImports.PluginHost host);

    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

}

