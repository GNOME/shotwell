/*
 * Vala Bindings for ige-mac-integration 0.8.2
 *
 * http://developer.imendio.com/projects/gtk-macosx/integration
 */

[CCode (cprefix = "Ige", lower_case_cprefix = "ige_")]
namespace Ige {

	[Compact]
	[CCode (cheader_filename = "ige-mac-integration.h")]
	public class MacMenuGroup {
	}

	[CCode (cheader_filename = "ige-mac-integration.h")]
	namespace MacMenu {
		public static void set_menu_bar (Gtk.MenuShell menu_shell);
		public static void set_quit_menu_item (Gtk.MenuItem menu_item);
		public static Ige.MacMenuGroup add_app_menu_group ();
		public static void add_app_menu_item (Ige.MacMenuGroup group, Gtk.MenuItem menu_item, string? label = null);
		public static bool handle_menu_event (Gdk.EventKey event);
		public static void set_global_key_handler_enabled (bool enabled);
		public static void connect_window_key_handler (Gtk.Window window);
	}

	[CCode (cheader_filename = "ige-mac-integration.h")]
	public class MacDock : GLib.Object {
		[CCode (has_construct_function = false)]
		public MacDock ();
		public static Ige.MacDock get_default ();
		public void set_icon_from_pixbuf (Gdk.Pixbuf? pixbuf);
		public void set_icon_from_resource (Ige.MacBundle bundle, string name, string type, string subdir);
		public void set_overlay_from_pixbuf (Gdk.Pixbuf pixbuf);
		public void set_overlay_from_resource (Ige.MacBundle bundle, string name, string type, string subdir);
		public Ige.MacAttentionRequest attention_request (Ige.MacAttentionType type);
		public void attention_cancel (Ige.MacAttentionRequest request);
		public signal void clicked ();
		public signal void open_documents ();
		public signal void quit_activate ();
	}

	[Compact]
	[CCode (cheader_filename = "ige-mac-integration.h")]
	public class MacAttentionRequest {
	}

	[CCode (cprefix = "IGE_MAC_ATTENTION_", cheader_filename = "ige-mac-integration.h")]
	public enum MacAttentionType {
		CRITICAL,
		INFO
	}

	[CCode (cheader_filename = "ige-mac-integration.h")]
	public class MacBundle : GLib.Object {
		[CCode (has_construct_function = false)]
		public MacBundle ();
		public static Ige.MacBundle get_default ();
		public void setup_environment ();
		public string get_id ();
		public string get_path ();
		public bool is_app_bundle ();
		public string get_localedir ();
		public string get_datadir ();
		public string get_resource_path (string name, string type, string subdir);
	}
}
