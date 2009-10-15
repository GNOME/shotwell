/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class FullscreenWindow : PageWindow {
    public const int TOOLBAR_INVOCATION_MSEC = 250;
    public const int TOOLBAR_DISMISSAL_SEC = 2;
    public const int TOOLBAR_CHECK_DISMISSAL_MSEC = 500;
    
    private Gdk.ModifierType ANY_BUTTON_MASK = 
        Gdk.ModifierType.BUTTON1_MASK | Gdk.ModifierType.BUTTON2_MASK | Gdk.ModifierType.BUTTON3_MASK;

    private Gtk.Window toolbar_window = new Gtk.Window(Gtk.WindowType.POPUP);
    private Gtk.UIManager ui = new Gtk.UIManager();
    private Gtk.ToolButton close_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_LEAVE_FULLSCREEN);
    private Gtk.ToggleToolButton pin_button = new Gtk.ToggleToolButton.from_stock(Resources.PIN_TOOLBAR);
    private bool is_toolbar_shown = false;
    private bool waiting_for_invoke = false;
    private time_t left_toolbar_time = 0;

    public FullscreenWindow(Page page) {
        current_page = page;

        File ui_file = Resources.get_ui("fullscreen.ui");

        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error err) {
            error("Error loading UI file %s: %s", ui_file.get_path(), err.message);
        }
        
        Gtk.ActionGroup action_group = new Gtk.ActionGroup("FullscreenActionGroup");
        action_group.add_actions(create_actions(), this);
        ui.insert_action_group(action_group, 0);
        ui.ensure_update();

        Gtk.AccelGroup accel_group = ui.get_accel_group();
        if (accel_group != null)
            add_accel_group(accel_group);
        
        set_screen(AppWindow.get_instance().get_screen());
        set_border_width(0);
        
        pin_button.set_label("Pin Toolbar");
        pin_button.set_tooltip_text("Pin the toolbar open");
        
        // TODO: Don't stock items supply their own tooltips?
        close_button.set_tooltip_text("Leave fullscreen");
        close_button.clicked += on_close;
        
        Gtk.Toolbar toolbar = current_page.get_toolbar();
        toolbar.set_show_arrow(false);

        if (page is SlideshowPage) {
            // slideshow page doesn't own toolbar to hide it, subscribe to signal instead
            ((SlideshowPage) current_page).hide_toolbar += hide_toolbar;
        } else {
            // only non-slideshow pages should have pin button
            toolbar.insert(pin_button, -1); 
        }

        toolbar.insert(close_button, -1);
        
        // set up toolbar along bottom of screen
        toolbar_window.set_screen(get_screen());
        toolbar_window.set_border_width(0);
        toolbar_window.add(toolbar);
        
        toolbar_window.realize += on_toolbar_realized;
        
        add(current_page);
        
        // need to create a Gdk.Window to set masks
        fullscreen();
        show_all();
        
        // capture motion events to show the toolbar
        add_events(Gdk.EventMask.POINTER_MOTION_MASK);
        
        // start off with toolbar invoked, as a clue for the user
        invoke_toolbar();
    }

    private override void realize() {
        base.realize();

        current_page.switched_to();
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry leave_fullscreen = { "LeaveFullscreen", Gtk.STOCK_LEAVE_FULLSCREEN,
            TRANSLATABLE, "F11", TRANSLATABLE, on_close };
        leave_fullscreen.label = _("Leave _Fullscreen");
        leave_fullscreen.tooltip = _("Leave fullscreen");
        actions += leave_fullscreen;

        return actions;
    }

    private override bool key_press_event(Gdk.EventKey event) {
        // check for an escape/abort 
        if (Gdk.keyval_name(event.keyval) == "Escape") {
            on_close();
            
            return true;
        }

       // ...then let the base class take over
       return (base.key_press_event != null) ? base.key_press_event(event) : false;
    }

    
    private void on_close() {
        hide_toolbar();
        toolbar_window = null;
        
        current_page.switching_from();
        
        AppWindow.get_instance().end_fullscreen();
    }
    
    private override bool motion_notify_event(Gdk.EventMotion event) {
        if (!is_toolbar_shown) {
            // if pointer is in toolbar height range without the mouse down (i.e. in the middle of
            // an edit operation) and it stays there the necessary amount of time, invoke the
            // toolbar
            if (!waiting_for_invoke && is_pointer_in_toolbar()) {
                Timeout.add(TOOLBAR_INVOCATION_MSEC, on_check_toolbar_invocation);
                waiting_for_invoke = true;
            }
        }
        
        return (base.motion_notify_event != null) ? base.motion_notify_event(event) : false;
    }
    
    private bool is_pointer_in_toolbar() {
        int y, height;
        window.get_geometry(null, out y, null, out height, null);

        int py;
        Gdk.ModifierType mask;
        get_display().get_pointer(null, null, out py, out mask);
        
        Gtk.Requisition req;
        toolbar_window.size_request(out req);

        return ((mask & ANY_BUTTON_MASK) == 0) && (py >= (y + height - req.height));
    }
    
    private bool on_check_toolbar_invocation() {
        waiting_for_invoke = false;
        
        if (is_toolbar_shown)
            return false;
        
        if (!is_pointer_in_toolbar())
            return false;
        
        invoke_toolbar();
        
        return false;
    }
    
    private void on_toolbar_realized() {
        Gtk.Requisition req;
        toolbar_window.size_request(out req);
        
        // place the toolbar in the center of the screen along the bottom edge
        Gdk.Screen screen = toolbar_window.get_screen();
        int tx = (screen.get_width() - req.width) / 2;
        if (tx < 0)
            tx = 0;

        int ty = screen.get_height() - req.height;
        if (ty < 0)
            ty = 0;
            
        toolbar_window.move(tx, ty);
        toolbar_window.set_opacity(Resources.TRANSIENT_WINDOW_OPACITY);
    }

    private void invoke_toolbar() {
        toolbar_window.show_all();

        is_toolbar_shown = true;
        
        Timeout.add(TOOLBAR_CHECK_DISMISSAL_MSEC, on_check_toolbar_dismissal);
    }
    
    private bool on_check_toolbar_dismissal() {
        if (!is_toolbar_shown)
            return false;
        
        if (toolbar_window == null)
            return false;
        
        // if pinned, keep open but keep checking
        if (pin_button.get_active())
            return true;
        
        // if the pointer is in toolbar range, keep it alive, but keep checking
        if (is_pointer_in_toolbar()) {
            left_toolbar_time = 0;

            return true;
        }
        
        // if this is the first time noticed, start the timer and keep checking
        if (left_toolbar_time == 0) {
            left_toolbar_time = time_t();
            
            return true;
        }
        
        // see if enough time has elapsed
        time_t now = time_t();
        assert(now >= left_toolbar_time);

        if (now - left_toolbar_time < TOOLBAR_DISMISSAL_SEC)
            return true;
        
        hide_toolbar();
        
        return false;
    }
    
    private void hide_toolbar() {
        toolbar_window.hide();
        is_toolbar_shown = false;
    }
}

// PageWindow is a Gtk.Window with essential functions for hosting a Page.  There may be more than
// one PageWindow in the system, and closing one does not imply exiting the application.
//
// PageWindow offers support for hosting a single Page; multiple Pages must be handled by the
// subclass.  A subclass should set current_page to the user-visible Page for it to receive
// various notifications.  It is the responsibility of the subclass to notify Pages when they're
// switched to and from, and other aspects of the Page interface.
public abstract class PageWindow : Gtk.Window {
    protected Page current_page = null;
    
    public PageWindow() {
        // the current page needs to know when modifier keys are pressed
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK
            | Gdk.EventMask.STRUCTURE_MASK);
    }
    
    private override bool key_press_event(Gdk.EventKey event) {
        if (current_page != null && event.is_modifier == 1) {
            if (current_page.notify_modifier_pressed(event))
                return true;
        }
        
        return (base.key_press_event != null) ? base.key_press_event(event) : false;
    }
    
    private override bool key_release_event(Gdk.EventKey event) {
        if (current_page != null && event.is_modifier == 1) {
            if (current_page.notify_modifier_released(event))
                return true;
        }
        
        return (base.key_release_event != null) ? base.key_release_event(event) : false;
    }
    
    private override bool configure_event(Gdk.EventConfigure event) {
        if (current_page != null) {
            if (current_page.notify_configure_event(event))
                return true;
        }
        
        return (base.configure_event != null) ? base.configure_event(event) : false;
    }

    public void set_busy_cursor() {
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
        spin_event_loop();
    }
    
    public void set_normal_cursor() {
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.ARROW));
        spin_event_loop();
    }
}

// AppWindow is the parent window for most windows in Shotwell (FullscreenWindow is the exception).
// There are multiple types of AppWindows (LibraryWindow, EditWindow) for different tasks, but only 
// one AppWindow may exist per process.  Thus, if the user closes an AppWindow, the program exits.
//
// AppWindow also offers support for going into fullscreen mode.  It handles the interface
// notifications Page is expecting when switching back and forth.
public abstract class AppWindow : PageWindow {
    public const int DND_ICON_SCALE = 128;
    
    private const string DATA_DIR = ".shotwell";

    public static Gdk.Color BG_COLOR = parse_color("#444");

    protected static AppWindow instance = null;
    
    private static string[] args = null;
    private static bool user_quit = false;
    private static FullscreenWindow fullscreen_window = null;

    public AppWindow() {
        // although there are multiple AppWindow types, only one may exist per-process
        assert(instance == null);
        instance = this;

        title = Resources.APP_TITLE;
        set_default_size(1024, 768);
        set_default_icon(Resources.get_icon(Resources.ICON_APP));

        // this permits the AboutDialog to properly load an URL
        Gtk.AboutDialog.set_url_hook(on_about_link);
        Gtk.AboutDialog.set_email_hook(on_about_link);
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry quit = { "CommonQuit", Gtk.STOCK_QUIT, TRANSLATABLE, "<Ctrl>Q",
            TRANSLATABLE, on_quit };
        quit.label = _("_Quit");
        quit.tooltip = _("Quit Shotwell");
        actions += quit;

        Gtk.ActionEntry about = { "CommonAbout", Gtk.STOCK_ABOUT, TRANSLATABLE, null,
            TRANSLATABLE, on_about };
        about.label = _("_About");
        about.tooltip = _("About Shotwell");
        actions += about;

        Gtk.ActionEntry fullscreen = { "CommonFullscreen", Gtk.STOCK_FULLSCREEN,
            TRANSLATABLE, "F11", TRANSLATABLE, on_fullscreen };
        fullscreen.label = _("_Fullscreen");
        fullscreen.tooltip = _("Use Shotwell at fullscreen");
        actions += fullscreen;

        Gtk.ActionEntry help_contents = { "CommonHelpContents", Gtk.STOCK_HELP,
            TRANSLATABLE, "F1", TRANSLATABLE, on_help_contents };
        help_contents.label = _("_Contents");
        help_contents.tooltip = _("More informaton on Shotwell");
        actions += help_contents;
        
        return actions;
    }
    
    protected abstract void on_fullscreen();

    public static void init(string[] args) {
        AppWindow.args = args;

        File data_dir = get_data_dir();
        try {
            if (data_dir.query_exists(null) == false) {
                if (!data_dir.make_directory_with_parents(null))
                    error("Unable to create data directory %s", data_dir.get_path());
            } 
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    public static void terminate() {
    }
    
    public static AppWindow get_instance() {
        return instance;
    }

    public static FullscreenWindow get_fullscreen() {
        return fullscreen_window;
    }
    
    public static string[] get_commandline_args() {
        return args;
    }
    
    public static GLib.File get_exec_file() {
        return File.new_for_path(Environment.find_program_in_path(args[0]));
    }

    public static File get_exec_dir() {
        return get_exec_file().get_parent();
    }
    
    public static File get_data_dir() {
        return File.new_for_path(Environment.get_home_dir()).get_child(DATA_DIR);
    }
    
    public static File get_photos_dir() {
        string path = Environment.get_user_special_dir(UserDirectory.PICTURES);
        if (path != null)
            return File.new_for_path(path);
        
        return File.new_for_path(Environment.get_home_dir()).get_child(_("Pictures"));
    }
    
    // Not using system temp directory for a couple of reasons: Temp files are often generated for
    // drag-and-drop and the temporary filename is the name transferred to the destination, and so
    // it's possible for various instances to generate same-name temp files.  Also, the file may
    // need to remain available after it's closed by Shotwell.  Vala bindings
    // guarantee temp files by returning an OutputStream, but that's not how the temp files are
    // generated in Shotwell many times
    //
    // TODO: At startup, clean out temp directory of old files.
    public static File get_temp_dir() {
        // Because multiple instances of the app can run at the same time, place temp files in
        // subdir named after process ID
        File tmp_dir = get_data_subdir("tmp").get_child("%d".printf((int) Posix.getpid()));
        if (!tmp_dir.query_exists(null)) {
            if (!tmp_dir.make_directory_with_parents(null))
                error("Unable to create temporary directory %s", tmp_dir.get_path());
        }
        
        return tmp_dir;
    }
    
    public static File get_data_subdir(string name, string? subname = null) {
        File subdir = get_data_dir().get_child(name);
        if (subname != null)
            subdir = subdir.get_child(subname);

        try {
            if (subdir.query_exists(null) == false) {
                if (!subdir.make_directory_with_parents(null))
                    error("Unable to create data subdirectory %s", subdir.get_path());
            }
        } catch (Error err) {
            error("%s", err.message);
        }
        
        return subdir;
    }
    
    public static File get_resources_dir() {
        File exec_dir = get_exec_dir();
        File prefix_dir = File.new_for_path(Resources.PREFIX);

        // if running in the prefix'd path, the app has been installed and is running from there;
        // use its installed resources; otherwise running locally, so use local resources
        if (exec_dir.has_prefix(prefix_dir))
            return prefix_dir.get_child("share").get_child("shotwell");
        else
            return AppWindow.get_exec_dir();
    }

    public static void error_message(string message) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(get_instance(), Gtk.DialogFlags.MODAL, 
            Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", message);
        dialog.title = Resources.APP_TITLE;
        dialog.run();
        dialog.destroy();
    }
    
    public static bool yes_no_question(string message, string? title = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(get_instance(), Gtk.DialogFlags.MODAL,
            Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, "%s", message);
        dialog.title = (title != null) ? title : Resources.APP_TITLE;
        
        bool yes = (dialog.run() == Gtk.ResponseType.YES);
        
        dialog.destroy();
        
        return yes;
    }

    public static bool has_user_quit() {
        return user_quit;
    }
    
    public abstract string get_app_role();

    protected void on_about() {
        Gtk.show_about_dialog(this,
            "version", Resources.APP_VERSION,
            "comments", get_app_role(),
            "copyright", Resources.COPYRIGHT,
            "website", Resources.YORBA_URL,
            "license", Resources.LICENSE,
            "website-label", _("Visit the Yorba web site"),
            "authors", Resources.AUTHORS,
            "logo", Resources.get_icon(Resources.ICON_ABOUT_LOGO, -1)
        );
    }
    
    // This callback needs to be installed for the links to be active in the About dialog.  However,
    // this callback doesn't actually have to do anything in order to activate the URL.
    private void on_about_link(Gtk.AboutDialog about_dialog, string url) {
    }
    
    private void on_help_contents() {
        open_link(Resources.HELP_URL);
    }
    
    protected virtual void on_quit() {
        user_quit = true;
        Gtk.main_quit();
    }
    
    private override void destroy() {
        on_quit();
    }

    public void open_link(string url) {
        try {
            Gtk.show_uri(window.get_screen(), url, Gdk.CURRENT_TIME);
        } catch (Error err) {
            critical("Unable to load URL: %s", err.message);
        }
    }
    
    public virtual void add_common_actions(Gtk.ActionGroup action_group) {
        action_group.add_actions(create_actions(), this);
    }

    public void go_fullscreen(FullscreenWindow fsw) {
        // if already fullscreen, use that
        if (fullscreen_window != null) {
            fullscreen_window.present();
            
            return;
        }
        
        if (current_page != null)
            current_page.switching_to_fullscreen();
        
        fullscreen_window = fsw;
        fullscreen_window.present();
        hide();
    }
    
    public void end_fullscreen() {
        if (fullscreen_window == null)
            return;
        
        show_all();
        
        fullscreen_window.hide();
        fullscreen_window = null;
        
        if (current_page != null)
            current_page.returning_from_fullscreen();
        
        present();
    }
}

