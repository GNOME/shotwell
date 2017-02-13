/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Shotwell Pluggable Publishing API
 *
 * The Shotwell Pluggable Publishing API allows you to write plugins that upload
 * photos and videos to web services. The Shotwell distribution includes publishing
 * support for four core services: Facebook, Flickr, Picasa Web Albums, and YouTube.
 * To enable Shotwell to connect to additional services, developers like you write
 * publishing plugins, dynamically-loadable shared objects that are linked into the
 * Shotwell process at runtime. Publishing plugins are just one of several kinds of
 * plugins supported by {@link Spit}, the Shotwell Pluggable Interfaces Technology.
 */
namespace Spit.Publishing {

/**
 * The current version of the Pluggable Publishing API
 */
public const int CURRENT_INTERFACE = 0;

/**
 * Defines different kinds of errors that can occur during publishing.
 */
public errordomain PublishingError {
    /**
     * Indicates that no communications channel could be opened to the remote host.
     *
     * This error occurs, for example, when no network connection is available or
     * when a DNS lookup fails.
     */
    NO_ANSWER,

    /**
     * Indicates that a communications channel to the remote host was previously opened, but
     * the remote host can no longer be reached.
     *
     * This error occurs, for example, when the network is disconnected during a publishing
     * interaction.
     */
    COMMUNICATION_FAILED,

    /**
     * Indicates that a communications channel to the remote host was opened and
     * is active, but that messages sent to or from the remote host can't be understood.
     *
     * This error occurs, for example, when attempting to interact with a RESTful host
     * via XML-RPC.
     */
    PROTOCOL_ERROR,

    /**
     * Indicates that the remote host has received a well-formed message that has caused
     * a server-side error.
     *
     * This error occurs, for example, when the remote host receives a message that should
     * be signed but isn't.
     */
    SERVICE_ERROR,

    /**
     * Indicates that the remote host has sent the local client back a well-formed response,
     * but the response can't be understood.
     *
     * This error occurs, for example, when the remote host sends a response in an XML grammar
     * different from that expected by the local client.
     */
    MALFORMED_RESPONSE,

    /**
     * Indicates that the local client can't access a file or files in local storage.
     *
     * This error occurs, for example, when the local client attempts to read binary data
     * out of a photo or video file that doesn't exist.
     */
    LOCAL_FILE_ERROR,

    /**
     * Indicates that the remote host has rejected the session identifier used by the local
     * client as out-of-date. The local client should acquire a new session identifier.
     */
    EXPIRED_SESSION,

    /**
     * Indicates that a secure connection to the remote host cannot be
     * established. This might have various reasons such as expired
     * certificats, invalid certificates, self-signed certificates...
     */
    SSL_FAILED
}

/** 
 * Represents a connection to a publishing service.
 *
 * Developers of publishing plugins provide a class that implements this interface. At
 * any given time, only one Publisher can be running. When a publisher is running, it is
 * allowed to access the network and has exclusive use of the shared user-interface and
 * configuration services provided by the {@link PluginHost}. Publishers are created in
 * a non-running state and do not begin running until start( ) is invoked. Publishers
 * run until stop( ) is invoked.
 */
public interface Publisher : GLib.Object {
    /**
     * Describes the kinds of media a publishing service supports.
     *
     * Values can be masked together, for example: {{{(MediaType.PHOTO | MediaType.VIDEO)}}}
     * indicates that a publishing service supports the upload of both photos and videos.
     */
    public enum MediaType {
        NONE =          0,
        PHOTO =         1 << 0,
        VIDEO =         1 << 1
    }

    /**
     * Returns a {@link Service} object describing the service to which this connects.
     */
    public abstract Service get_service();

    /**
     * Makes this publisher enter the running state and endows it with exclusive access
     * to the shared services provided by the {@link PluginHost}. Through the host’s interface,
     * this publisher can install user interface panes and query configuration information.
     * Only running services should perform network operations.
     */
    public abstract void start();

    /**
     * Returns true if this publisher is in the running state; false otherwise.
     */
    public abstract bool is_running();
    
    /**
     * Causes this publisher to enter a non-running state. This publisher should stop all
     * network operations and cease use of the shared services provided by the {@link PluginHost}.
     */
    public abstract void stop();
    
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
 * Encapsulates a pane that can be installed in the on-screen publishing dialog box to
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
 * Enables its caller to report to the user on the progress of a publishing operation.
 *
 * @param file_number the sequence number of media item that the publishing system is currently
 *                    working with, starting at 1. For example, if the user chooses to publish
 *                    4 photos, these photos would have sequence numbers 1, 2, 3, and 4.
 *
 * @param fraction_complete the fraction of the current publishing operation that has been
 *                          completed, from 0.0 to 1.0, inclusive.
 */
public delegate void ProgressCallback(int file_number, double fraction_complete);

/**
 * Called by the publishing system when the user clicks the 'Login' button in a service welcome
 * pane.
 */
public delegate void LoginCallback();

/**
 * Manages and provides services for publishing plugins.
 *
 * Implemented inside Shotwell, the PluginHost provides an interface through which the
 * developers of publishing plugins can query and make changes to the publishing
 * environment. For example, through the PluginHost, plugins can get a list of the photos
 * and videos to be published, install and remove user-interface panes in the publishing
 * dialog box, and request that the items to be uploaded be serialized to a temporary
 * directory on disk. Plugins can use the services of the PluginHost only when their
 * {@link Publisher} is in the running state. This ensures that non-running publishers
 * don’t destructively interfere with the actively running publisher.
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
     * Notifies the user that an unrecoverable publishing error has occurred and halts
     * the publishing process.
     *
     * @param err An error object that describes the kind of error that occurred.
     */
    public abstract void post_error(Error err);

    /**
     * Halts the publishing process.
     *
     * Calling this method stops all network activity and hides the on-screen publishing
     * dialog box.
     */
    public abstract void stop_publishing();

    /**
     * Returns a reference to the {@link Publisher} object that this is currently hosting.
     */
    public abstract Publisher get_publisher();

    /**
     * Attempts to install a pane in the on-screen publishing dialog box, making the pane visible
     * and allowing it to interact with the user.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     * 
     * @param pane the pane to install
     *
     * @param mode allows you to set the text displayed on the close/cancel button in the
     * lower-right-hand corner of the on-screen publishing dialog box when pane is installed.
     * If mode is ButtonMode.CLOSE, the button will have the title "Close." If mode is
     * ButtonMode.CANCEL, the button will be titled "Cancel." You should set mode depending on
     * whether a cancellable action is in progress. For example, if your publisher is in the
     * middle of uploading 3 of 8 videos, then mode should be ButtonMode.CANCEL. However, if
     * the publishing operation has completed and the success pane is displayed, then mode
     * should be ButtonMode.CLOSE, because all cancellable publishing actions have already
     * occurred.
     */
    public abstract void install_dialog_pane(Spit.Publishing.DialogPane pane,
        ButtonMode mode = ButtonMode.CANCEL);

    /**
     * Attempts to install a pane in the on-screen publishing dialog box that contains
     * static text.
     *
     * The text appears centered in the publishing dialog box and is drawn in
     * the system font. This is a convenience method only; similar results could be
     * achieved by manually constructing a Gtk.Label widget, wrapping it inside a
     * {@link DialogPane}, and installing it manually with a call to
     * install_dialog_pane( ). To provide visual consistency across publishing services,
     * however, always use this convenience method instead of constructing label panes when
     * you need to display static text to the user.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     * 
     * @param message the text to show in the pane
     *
     * @param mode allows you to set the text displayed on the close/cancel button in the
     * lower-right-hand corner of the on-screen publishing dialog box when pane is installed.
     * If mode is ButtonMode.CLOSE, the button will have the title "Close." If mode is
     * ButtonMode.CANCEL, the button will be titled "Cancel." You should set mode depending on
     * whether a cancellable action is in progress. For example, if your publisher is in the
     * middle of uploading 3 of 8 videos, then mode should be ButtonMode.CANCEL. However, if
     * the publishing operation has completed and the success pane is displayed, then mode
     * should be ButtonMode.CLOSE, because all cancellable publishing actions have already
     * occurred.
     */
    public abstract void install_static_message_pane(string message,
        ButtonMode mode = ButtonMode.CANCEL);

    /**
     * Works just like {@link install_static_message_pane} but allows markup to contain
     * Pango text formatting tags as well as unstyled text.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     * 
     * @param markup the text to show in the pane, marked up with Pango formatting tags.
     *
     * @param mode allows you to set the text displayed on the close/cancel button in the
     * lower-right-hand corner of the on-screen publishing dialog box when pane is installed.
     * If mode is ButtonMode.CLOSE, the button will have the title "Close." If mode is
     * ButtonMode.CANCEL, the button will be titled "Cancel." You should set mode depending on
     * whether a cancellable action is in progress. For example, if your publisher is in the
     * middle of uploading 3 of 8 videos, then mode should be ButtonMode.CANCEL. However, if
     * the publishing operation has completed and the success pane is displayed, then mode
     * should be ButtonMode.CLOSE, because all cancellable publishing actions have already
     * occurred.
     */
    public abstract void install_pango_message_pane(string markup,
        ButtonMode mode = ButtonMode.CANCEL);

    /**
     * Attempts to install a pane in the on-screen publishing dialog box notifying the user
     * that his or her publishing operation completed successfully.
     * 
     * The text displayed depends on the type of media the current publishing service
     * supports. To provide visual consistency across publishing services and to allow
     * Shotwell to handle internationalization, always use this convenience method; don’t
     * contruct and install success panes manually.
     *
     * If an error has posted, the {@link PluginHost} will not honor
     * this request.
     */
    public abstract void install_success_pane();

    /**
     * Attempts to install a pane displaying the static text “Fetching account information...”
     * in the on-screen publishing dialog box, making it visible to the user.
     *
     * This is a convenience method only; similar results could be achieved by calling
     * {@link install_static_message_pane} with an appropriate text argument. To provide
     * visual consistency across publishing services and to allow Shotwell to handle
     * internationalization, however, you should always use this convenience method whenever
     * you need to tell the user that you’re querying account information over the network.
     * Queries such as this are almost always performed immediately after the user has logged
     * in to the remote service.
     * 
     * If an error has posted, the {@link PluginHost} will not honor this request.
     */
    public abstract void install_account_fetch_wait_pane();


    /**
     * Works just like {@link install_account_fetch_wait_pane} but displays the static text
     * “Logging in...“
     * 
     * As with {@link install_account_fetch_wait_pane}, this is a convenience method, but
     * you should you use it provide to visual consistency and to let Shotwell handle
     * internationalization. See the description of {@link install_account_fetch_wait_pane}
     * for more information.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     */
    public abstract void install_login_wait_pane();

    /**
     * Attempts to install a pane displaying the text 'welcome_message' above a push
     * button labeled “Login” in the on-screen publishing dialog box, making it visible to the
     * user.
     *
     * When the user clicks the “Login” button, you’ll be notified of the user’s action through
     * the callback 'on_login_clicked'. Every Publisher should provide a welcome pane to
     * introduce the service and explain service-specific features or restrictions. To provide
     * visual consistency across publishing services and to allow Shotwell to handle
     * internationalization, always use this convenience method; don’t contruct and install
     * welcome panes manually.
     *
     * If an error has posted, the {@link PluginHost} will not honor this request.
     *
     * @param welcome_message the text to be displayed above a push button labeled “Login”
     * in the on-screen publishing dialog box.
     *
     * @param on_login_clicked specifies the callback that is invoked when the user clicks
     * the “Login” button.
     */
    public abstract void install_welcome_pane(string welcome_message,
        LoginCallback on_login_clicked);

    /**
     * Toggles whether the service selector combo box in the upper-right-hand corner of the
     * on-screen publishing dialog box is sensitive to input.
     *
     * Publishers should make the service selector box insensitive to input when they are performing
     * non-interruptible file or network operations, since switching to another publishing
     * service will halt whatever service is currently running. Under certain circumstances,
     * the {@link PluginHost} may not honor this request.
     *
     * @param is_locked when is_locked is true, the service selector combo box is made insensitive.
     * It appears greyed out and the user is prevented from switching to another publishing service.
     * When is_locked is false, the combo box is sensitive, allowing the user to freely switch
     * from the current service to another service. 
     */
    public abstract void set_service_locked(bool is_locked);

    /**
     * Makes the designated widget the default widget for the publishing dialog.
     *
     * After a call to this method, the designated widget will be activated whenever the user
     * presses the [ENTER] key anywhere in the on-screen publishing dialog box. Under certain
     * circumstances, the {@link PluginHost} may not honor this request.
     *
     * @param widget a reference to the widget to designate as the default widget for the
     *               publishing dialog.
     */
    public abstract void set_dialog_default_widget(Gtk.Widget widget);

    /**
     * Returns an array of the publishable media items that the user has selected for upload to the
     * remote service.
     */
    public abstract Publishable[] get_publishables();

    /**
     * Writes all of the publishable media items that the user has selected for upload to the
     * remote service to a temporary directory on a local disk.
     *
     * You should call this method immediately before sending the publishable media items to the
     * remote service over the network. Because serializing several megabytes of data is a
     * potentially lengthy operation, calling this method installs an activity status pane in
     * the on-screen publishing dialog box. The activity status pane displays a progress bar along
     * with a string of informational text.
     *
     * Because sending items over the network to the remote service is also a potentially lengthy
     * operation, you should leave the activity status pane installed in the on-screen publishing
     * dialog box until this task is finished. Periodically during the sending process, you should
     * report to the user on the progress of his or her upload. You can do this by invoking the
     * returned {@link ProgressCallback} delegate.
     *
     * After calling this method, the activity status pane that this method installs remains
     * displayed in the on-screen publishing dialog box until you install a new pane.
     *
     * @param content_major_axis when serializing publishable media items that are photos,
     *                           ensure that neither the width nor the height of the serialized
     *                           photo is greater than content_major_axis pixels. The value of
     *                           this parameter has no effect on video publishables.
     *
     * @param strip_metadata when serializing publishable media items that are photos, if
     *                       strip_metadata is true, all EXIF, IPTC, and XMP metadata will be
     *                       removed from the serialized file. If strip_metadata is false, all
     *                       metadata will be left intact. The value of this parameter has no
     *                       effect on video publishables.
     */
    public abstract ProgressCallback? serialize_publishables(int content_major_axis,
        bool strip_metadata = false);

    /**
     * Returns a {@link Publisher.MediaType} bitfield describing which kinds of media are present
     * in the set of publishable media items that the user has selected for upload to the remote
     * service.
     */
    public abstract Spit.Publishing.Publisher.MediaType get_publishable_media_type();
    
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
 * Describes an underlying media item (such as a photo or a video) that your plugin
 * uploads to a remote publishing service.
 */
public interface Publishable : GLib.Object {

    public const string PARAM_STRING_BASENAME    = "basename";
    public const string PARAM_STRING_TITLE       = "title";
    public const string PARAM_STRING_COMMENT     = "comment";
    public const string PARAM_STRING_EVENTCOMMENT= "eventcomment";

    /**
     * Returns a handle to the file on disk to which this publishable's data has been
     * serialized.
     *
     * You should use this file handle to read into memory the binary data you will send over
     * the network to the remote publishing service when this publishable is uploaded.
     */
    public abstract GLib.File? get_serialized_file();

    /**
     * Returns a name that can be used to identify this publishable to the remote service.
     * If the publishing host cannot derive a sensible name, this method will
     * return an empty string. Plugins should be able to handle that situation
     * and provide a fallback value. One possible option for a fallback is:
     * get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME)
     */
    public abstract string get_publishing_name();

    /**
     * Returns a string value from the publishable corresponding with the parameter name 
     * provided, or null if there is no value for this name.
     */
    public abstract string? get_param_string(string name);

    /**
     * Returns an array of strings that should be used to tag or mark this publishable on the
     * remote service, or null if this publishable has no tags or markings.
     */
    public abstract string[] get_publishing_keywords();

    /**
     * Returns the kind of media item this publishable encapsulates.
     */
    public abstract Spit.Publishing.Publisher.MediaType get_media_type();
    
    /**
     * Returns the creation timestamp on the file.
     */
    public abstract GLib.DateTime get_exposure_date_time();
    
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
 * Describes the features and capabilities of a remote publishing service.
 *
 * Developers of publishing plugins provide a class that implements this interface.
 */
public interface Service : Object, Spit.Pluggable {
    /**
     * A factory method that instantiates and returns a new {@link Publisher} object that
     * encapsulates a connection to the remote publishing service that this Service describes.
     */
    public abstract Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host);

    /**
     * Returns the kinds of media that this service can work with.
     */
    public abstract Spit.Publishing.Publisher.MediaType get_supported_media();
    
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

public interface Authenticator : Object {
    public signal void authenticated();
    public signal void authentication_failed();

    public abstract void authenticate();
    public abstract bool can_logout();
    public abstract void logout();
    public abstract void refresh();

    public abstract GLib.HashTable<string, Variant> get_authentication_parameter();
}

public interface AuthenticatorFactory : Object {
    // By contract, every AuthenticatorFactory implementation needs to have a
    // static get_instance() method. Unfortunately this is not expressable in
    // Vala.

    public abstract Gee.List<string> get_available_authenticators();
    public abstract Authenticator? create(string provider,
            Spit.Publishing.PluginHost host);
}

}

