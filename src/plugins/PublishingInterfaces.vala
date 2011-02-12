/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Spit.Publishing {

public const int CURRENT_API_VERSION = 0;

public errordomain PublishingError {
    NO_ANSWER,
    COMMUNICATION_FAILED,
    PROTOCOL_ERROR,
    SERVICE_ERROR,
    MALFORMED_RESPONSE,
    LOCAL_FILE_ERROR,
    EXPIRED_SESSION
}

public interface Publisher : GLib.Object {
    public enum MediaType {
        NONE =          0,
        PHOTO =         1 << 0,
        VIDEO =         1 << 1
    }
    
    public abstract Service get_service();
    
    public abstract MediaType get_supported_media();
    
    public abstract void start();
    
    public abstract bool is_running();
    
    /* plugins must relinquish their host reference when stop( ) is called */
    public abstract void stop();
    
    //
    // For future expansion.
    //
    public virtual void reserved0() {}
    public virtual void reserved1() {}
    public virtual void reserved2() {}
    public virtual void reserved3() {}
    public virtual void reserved4() {}
    public virtual void reserved5() {}
    public virtual void reserved6() {}
    public virtual void reserved7() {}
}

public interface DialogPane : GLib.Object {
    public enum GeometryOptions {
        NONE =          0,
        EXTENDED_SIZE = 1 << 0,
        RESIZABLE =     1 << 1;
    }
    
    public abstract Gtk.Widget get_widget();
    
	/* the publishing dialog may give you what you want; then again, it may not ;-) */
    public abstract GeometryOptions get_preferred_geometry();
    
    public abstract void on_pane_installed();
    
    public abstract void on_pane_uninstalled();
    
    //
    // For future expansion.
    //
    public virtual void reserved0() {}
    public virtual void reserved1() {}
    public virtual void reserved2() {}
    public virtual void reserved3() {}
    public virtual void reserved4() {}
    public virtual void reserved5() {}
    public virtual void reserved6() {}
    public virtual void reserved7() {}
}

/* fraction_complete should be between 0.0 and 1.0 inclusive */
public delegate void ProgressCallback(int file_number, double fraction_complete);

public delegate void LoginCallback();

public interface PluginHost : GLib.Object, Spit.HostInterface {
    public enum ButtonMode {
        CLOSE = 0,
        CANCEL = 1
    }
	
    public abstract void post_error(Error err);
    
    public abstract void stop_publishing();
    
    public abstract Publisher get_publisher();

    public abstract void install_dialog_pane(Spit.Publishing.DialogPane pane,
        ButtonMode mode = ButtonMode.CANCEL);
    
    public abstract void install_static_message_pane(string message,
        ButtonMode mode = ButtonMode.CANCEL);
    
    public abstract void install_pango_message_pane(string markup,
        ButtonMode mode = ButtonMode.CANCEL);
    
    public abstract void install_success_pane();
    
    public abstract void install_account_fetch_wait_pane();
    
    public abstract void install_login_wait_pane();
    
    public abstract void install_welcome_pane(string welcome_message,
        LoginCallback on_login_clicked);
    
    public abstract void set_service_locked(bool locked);
    
    public abstract void set_dialog_default_widget(Gtk.Widget widget);
    
    public abstract Publishable[] get_publishables();
    
    public abstract ProgressCallback? serialize_publishables(int content_major_axis,
        bool strip_metadata = false);
    
    public abstract Spit.Publishing.Publisher.MediaType get_publishable_media_type();
    
    //
    // For future expansion.
    //
    public virtual void reserved0() {}
    public virtual void reserved1() {}
    public virtual void reserved2() {}
    public virtual void reserved3() {}
    public virtual void reserved4() {}
    public virtual void reserved5() {}
    public virtual void reserved6() {}
    public virtual void reserved7() {}
}

public interface Publishable : GLib.Object {
    public abstract GLib.File? get_serialized_file();

    public abstract string get_publishing_name();

    public abstract string? get_publishing_description();

    public abstract string[] get_publishing_keywords();

    public abstract Spit.Publishing.Publisher.MediaType get_media_type();
    
    //
    // For future expansion.
    //
    public virtual void reserved0() {}
    public virtual void reserved1() {}
    public virtual void reserved2() {}
    public virtual void reserved3() {}
    public virtual void reserved4() {}
    public virtual void reserved5() {}
    public virtual void reserved6() {}
    public virtual void reserved7() {}
}

public interface Service : Object, Spit.Pluggable {
    public abstract Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host);
    
    //
    // For future expansion.
    //
    public virtual void reserved0() {}
    public virtual void reserved1() {}
    public virtual void reserved2() {}
    public virtual void reserved3() {}
    public virtual void reserved4() {}
    public virtual void reserved5() {}
    public virtual void reserved6() {}
    public virtual void reserved7() {}
}

}

