/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class FullscreenWindow : PageWindow {
    public const int TOOLBAR_INVOCATION_MSEC = 250;
    public const int TOOLBAR_DISMISSAL_SEC = 2;
    public const int TOOLBAR_CHECK_DISMISSAL_MSEC = 500;
    
    private Gtk.Window toolbar_window = new Gtk.Window(Gtk.WindowType.POPUP);
    private Gtk.UIManager ui = new Gtk.UIManager();
    private Gtk.ToolButton close_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_LEAVE_FULLSCREEN);
    private Gtk.ToggleToolButton pin_button = new Gtk.ToggleToolButton.from_stock(Resources.PIN_TOOLBAR);
    private bool is_toolbar_shown = false;
    private bool waiting_for_invoke = false;
    private time_t left_toolbar_time = 0;
    private bool switched_to = false;
    private bool is_toolbar_dismissal_enabled = true;

    public FullscreenWindow(Page page) {
        set_current_page(page);

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

        // add the accelerators for the hosted page as well
        Gtk.AccelGroup hosted_accel_group = page.ui.get_accel_group();
        if (hosted_accel_group != null)
            add_accel_group(hosted_accel_group);
        
        // the local accelerator group must come after host accelerator group so that they cover the
        // old accelerator group bindings
        Gtk.AccelGroup accel_group = ui.get_accel_group();
        if (accel_group != null)
            add_accel_group(accel_group);
        
        set_screen(AppWindow.get_instance().get_screen());
       	
        // Needed so fullscreen will occur on correct monitor in multi-monitor setups
        Gdk.Rectangle monitor = get_monitor_geometry();
        move(monitor.x, monitor.y);
        
        set_border_width(0);
        
        pin_button.set_label(_("Pin Toolbar"));
        pin_button.set_tooltip_text(_("Pin the toolbar open"));
        pin_button.clicked.connect(on_pin_button_state_change);
        
        // TODO: Don't stock items supply their own tooltips?
        close_button.set_tooltip_text(_("Leave fullscreen"));
        close_button.clicked.connect(on_close);
        
        Gtk.Toolbar toolbar = page.get_toolbar();
        toolbar.set_show_arrow(false);

        if (page is SlideshowPage) {
            // slideshow page doesn't own toolbar to hide it, subscribe to signal instead
            ((SlideshowPage) page).hide_toolbar.connect(hide_toolbar);
        } else {
            // only non-slideshow pages should have pin button
            toolbar.insert(pin_button, -1); 
        }

        page.set_cursor_hide_time(TOOLBAR_DISMISSAL_SEC * 1000);
        page.start_cursor_hiding();

        toolbar.insert(close_button, -1);
        
        // set up toolbar along bottom of screen
        toolbar_window.set_screen(get_screen());
        toolbar_window.set_border_width(0);
        toolbar_window.add(toolbar);
        
        toolbar_window.realize.connect(on_toolbar_realized);
        
        add(page);
        
        // need to create a Gdk.Window to set masks
        fullscreen();
        show_all();

        // capture motion events to show the toolbar
        add_events(Gdk.EventMask.POINTER_MOTION_MASK);
        
        // start off with toolbar invoked, as a clue for the user
        invoke_toolbar();
    }

    public void enable_toolbar_dismissal() {
        is_toolbar_dismissal_enabled = true;
    }
    
    public void disable_toolbar_dismissal() {
        is_toolbar_dismissal_enabled = false;
    }
    
    private void on_pin_button_state_change() {
        is_toolbar_dismissal_enabled = !pin_button.get_active();
    }

    private Gdk.Rectangle get_monitor_geometry() {
        Gdk.Rectangle monitor;

        get_screen().get_monitor_geometry(
            get_screen().get_monitor_at_window(AppWindow.get_instance().get_window()), out monitor);

        return monitor;
    }
    
    public override bool configure_event(Gdk.EventConfigure event) {
        bool result = base.configure_event(event);
        
        if (!switched_to) {
            get_current_page().switched_to();
            switched_to = true;
        }
        
        return result;
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

    public override bool key_press_event(Gdk.EventKey event) {
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
        
        AppWindow.get_instance().end_fullscreen();
    }
    
    public override void destroy() {
        Page? page = get_current_page();
        clear_current_page();
        
        if (page != null) {
            page.stop_cursor_hiding();
            page.switching_from();
        }
        
        base.destroy();
    }
    
    public override bool delete_event(Gdk.Event event) {
        on_close();
        AppWindow.get_instance().destroy();
        
        return true;
    }
    
    public override bool motion_notify_event(Gdk.EventMotion event) {
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
        get_display().get_pointer(null, null, out py, null);
        
        Gtk.Requisition req;
        toolbar_window.size_request(out req);

        return (py >= (y + height - req.height));
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
        
        // place the toolbar in the center of the monitor along the bottom edge
        Gdk.Rectangle monitor = get_monitor_geometry();
        int tx = monitor.x + (monitor.width - req.width) / 2;
        if (tx < 0)
            tx = 0;

        int ty = monitor.y + monitor.height - req.height;
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
        
        // if dismissal is disabled, keep open but keep checking
        if ((!is_toolbar_dismissal_enabled))
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
    private Page current_page = null;
    private int busy_counter = 0;
    private int keyboard_trapping = 0;
    
    protected virtual void switched_pages(Page? old_page, Page? new_page) {
    }
    
    public PageWindow() {
        // the current page needs to know when modifier keys are pressed
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK
            | Gdk.EventMask.STRUCTURE_MASK);
    }
    
    public Page? get_current_page() {
        return current_page;
    }
    
    public virtual void set_current_page(Page page) {
        if (current_page != null)
            current_page.clear_container();
        
        Page? old_page = current_page;
        current_page = page;
        current_page.set_container(this);
        
        switched_pages(old_page, page);
    }
    
    public virtual void clear_current_page() {
        if (current_page != null)
            current_page.clear_container();
        
        Page? old_page = current_page;
        current_page = null;
        
        switched_pages(old_page, null);
    }
    
    public override bool key_press_event(Gdk.EventKey event) {
        if (keyboard_trapping == 0) {
            if (current_page != null && current_page.notify_app_key_pressed(event))
                return true;
        }
        
        return (base.key_press_event != null) ? base.key_press_event(event) : false;
    }
    
    public override bool key_release_event(Gdk.EventKey event) {
       if (keyboard_trapping == 0) {
            if (current_page != null && current_page.notify_app_key_released(event))
                    return true;
        }
        
        return (base.key_release_event != null) ? base.key_release_event(event) : false;
    }

    public override bool focus_in_event(Gdk.EventFocus event) {
        if (current_page != null && current_page.notify_app_focus_in(event))
                return true;
        
        return (base.focus_in_event != null) ? base.focus_in_event(event) : false;
    }

    public override bool focus_out_event(Gdk.EventFocus event) {
        if (current_page != null && current_page.notify_app_focus_out(event))
                return true;
        
        return (base.focus_out_event != null) ? base.focus_out_event(event) : false;
    }
    
    public override bool configure_event(Gdk.EventConfigure event) {
        if (current_page != null) {
            if (current_page.notify_configure_event(event))
                return true;
        }

        return (base.configure_event != null) ? base.configure_event(event) : false;
    }

    public void set_busy_cursor() {
        if (busy_counter++ > 0)
            return;
        
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.WATCH));
        spin_event_loop();
    }
    
    public void set_normal_cursor() {
        if (busy_counter <= 0) {
            busy_counter = 0;
            return;
        } else if (--busy_counter > 0) {
            return;
        }
        
        window.set_cursor(new Gdk.Cursor(Gdk.CursorType.LEFT_PTR));
        spin_event_loop();
    }
    
    public virtual bool pause_keyboard_trapping() {
        return (keyboard_trapping++ == 0);
    }
    
    public virtual bool resume_keyboard_trapping() {
        if (keyboard_trapping <= 0)
            keyboard_trapping = 0;
        else
            return (--keyboard_trapping == 0);
        
        return false;
    }
}

// AppWindow is the parent window for most windows in Shotwell (FullscreenWindow is the exception).
// There are multiple types of AppWindows (LibraryWindow, DirectWindow) for different tasks, but only 
// one AppWindow may exist per process.  Thus, if the user closes an AppWindow, the program exits.
//
// AppWindow also offers support for going into fullscreen mode.  It handles the interface
// notifications Page is expecting when switching back and forth.
public abstract class AppWindow : PageWindow {
    public const int DND_ICON_SCALE = 128;
    
    protected static AppWindow instance = null;
    
    private static FullscreenWindow fullscreen_window = null;
    private static CommandManager command_manager = null;

    protected bool maximized = false;
    protected Dimensions dimensions;
    protected int pos_x = 0;
    protected int pos_y = 0;
    
    public AppWindow() {
        // although there are multiple AppWindow types, only one may exist per-process
        assert(instance == null);
        instance = this;

        title = Resources.APP_TITLE;
        set_default_icon(Resources.get_icon(Resources.ICON_APP));

        // restore previous size and maximization state
        if (this is LibraryWindow) {
            Config.get_instance().get_library_window_state(out maximized, out dimensions);
        } else {
            assert(this is DirectWindow);
            Config.get_instance().get_direct_window_state(out maximized, out dimensions);
        }

        set_default_size(dimensions.width, dimensions.height);

        if (maximized)
            maximize();

        assert(command_manager == null);
        command_manager = new CommandManager();
        command_manager.altered.connect(on_command_manager_altered);
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
        fullscreen.label = _("Fulls_creen");
        fullscreen.tooltip = _("Use Shotwell at fullscreen");
        actions += fullscreen;

        Gtk.ActionEntry help_contents = { "CommonHelpContents", Gtk.STOCK_HELP,
            TRANSLATABLE, "F1", TRANSLATABLE, on_help_contents };
        help_contents.label = _("_Contents");
        help_contents.tooltip = _("More information on Shotwell");
        actions += help_contents;
        
        Gtk.ActionEntry users_guide = { "CommonUsersGuide", null, TRANSLATABLE, null,
            TRANSLATABLE, on_users_guide };
        users_guide.label = _("_User Manual");
        // TODO: tooltip (when strings not frozen)
        actions += users_guide;
        
        Gtk.ActionEntry undo = { "CommonUndo", Gtk.STOCK_UNDO, TRANSLATABLE, "<Ctrl>Z",
            TRANSLATABLE, on_undo };
        undo.label = Resources.UNDO_MENU;
        undo.tooltip = Resources.UNDO_TOOLTIP;
        actions += undo;
        
        Gtk.ActionEntry redo = { "CommonRedo", Gtk.STOCK_REDO, TRANSLATABLE, "<Ctrl><Shift>Z",
            TRANSLATABLE, on_redo };
        redo.label = Resources.REDO_MENU;
        redo.tooltip = Resources.REDO_TOOLTIP;
        actions += redo;

        Gtk.ActionEntry jump_to_file = { "CommonJumpToFile", Gtk.STOCK_JUMP_TO, TRANSLATABLE, 
            "<Ctrl><Shift>M", TRANSLATABLE, on_jump_to_file };
        jump_to_file.label = Resources.JUMP_TO_FILE_MENU;
        jump_to_file.tooltip = Resources.JUMP_TO_FILE_TOOLTIP;
        actions += jump_to_file;
        
        Gtk.ActionEntry select_all = { "CommonSelectAll", Gtk.STOCK_SELECT_ALL, TRANSLATABLE,
            "<Ctrl>A", TRANSLATABLE, on_select_all };
        select_all.label = Resources.SELECT_ALL_MENU;
        select_all.tooltip = Resources.SELECT_ALL_TOOLTIP;
        actions += select_all;
        
        return actions;
    }
    
    protected abstract void on_fullscreen();
    
    public static bool has_instance() {
        return instance != null;
    }
    
    public static AppWindow get_instance() {
        return instance;
    }

    public static FullscreenWindow get_fullscreen() {
        return fullscreen_window;
    }

    public static Gtk.Builder create_builder() {
        Gtk.Builder builder = new Gtk.Builder();
        try {
            builder.add_from_file(AppDirs.get_resources_dir().get_child("ui").get_child(
                "shotwell.glade").get_path());
        } catch(GLib.Error error) {
            warning("Unable to create Gtk.Builder: %s\n", error.message);
        }

        builder.connect_signals(null);

        return builder;
    }
    
    public static void error_message(string message, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", message);
        dialog.title = Resources.APP_TITLE;
        dialog.run();
        dialog.destroy();
    }
    
    public static bool negate_affirm_question(string message, string negative, string affirmative,
        string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", message);
        dialog.title = (title != null) ? title : Resources.APP_TITLE;
        dialog.add_buttons(negative, Gtk.ResponseType.NO, affirmative, Gtk.ResponseType.YES);
        
        bool response = (dialog.run() == Gtk.ResponseType.YES);
        
        dialog.destroy();
        
        return response;
    }

    public static Gtk.ResponseType negate_affirm_cancel_question(string message, string negative,
        string affirmative, string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", message);
        dialog.title = (title != null) ? title : Resources.APP_TITLE;
        dialog.add_buttons(negative, Gtk.ResponseType.NO, affirmative, Gtk.ResponseType.YES,
            _("_Cancel"), Gtk.ResponseType.CANCEL);
        
        int response = dialog.run();
        
        dialog.destroy();
        
        return (Gtk.ResponseType) response;
    }
    
    public static Gtk.ResponseType affirm_cancel_question(string message, string affirmative,
        string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, message);
        dialog.title = (title != null) ? title : Resources.APP_TITLE;
        dialog.add_buttons(affirmative, Gtk.ResponseType.YES, _("_Cancel"),
            Gtk.ResponseType.CANCEL);
        
        int response = dialog.run();
        
        dialog.destroy();
        
        return (Gtk.ResponseType) response;
    }
    
    public static Gtk.ResponseType negate_affirm_all_cancel_question(string message, 
        string negative, string affirmative, string affirmative_all, string? title = null,
        Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", message);
        dialog.title = (title != null) ? title : Resources.APP_TITLE;
        dialog.add_buttons(negative, Gtk.ResponseType.NO, affirmative, Gtk.ResponseType.YES,
            affirmative_all, Gtk.ResponseType.APPLY,  _("_Cancel"), Gtk.ResponseType.CANCEL);
        
        int response = dialog.run();
        
        dialog.destroy();
        
        return (Gtk.ResponseType) response;
    }
    
    public static void database_error(DatabaseError err) {
        panic(_("A fatal error occurred when accessing Shotwell's library.  Shotwell cannot continue.\n\n%s").printf(
            err.message));
    }
    
    public static void panic(string msg) {
        critical(msg);
        error_message(msg);
        
        Application.get_instance().panic();
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
            "logo", Resources.get_icon(Resources.ICON_ABOUT_LOGO, -1),
            "translator-credits", _("translator-credits"),
            null
        );
    }

    private void on_help_contents() {
        try {
            Resources.launch_help(get_screen());
        } catch (Error err) {
            error_message(_("Unable to display help: %s").printf(err.message));
        }
    }
    
    private void on_users_guide() {
        try {
            show_uri(Resources.get_users_guide_url());
        } catch (Error err) {
            error_message(_("Unable to display help: %s").printf(err.message));
        }
    }
    
    protected virtual void on_quit() {
        Application.get_instance().exit();
    }

    protected void on_jump_to_file() {
        if (get_current_page().get_view().get_selected_count() != 1)
            return;

        Photo photo = (Photo) get_current_page().get_view().get_selected_at(0).get_source();
        try {
            AppWindow.get_instance().show_file_uri(photo.get_master_file().get_parent());
        } catch (Error err) {
            AppWindow.error_message(Resources.jump_to_file_failed(err));
        }
    }
    
    protected override void destroy() {
        on_quit();
    }
    
    public void show_file_uri(File file) throws Error {
        show_uri(file.get_uri());
    }
    
    public void show_uri(string url) throws Error {
        sys_show_uri(window.get_screen(), url);
    }
    
    public virtual void add_common_actions(Gtk.ActionGroup action_group) {
        action_group.add_actions(create_actions(), this);
    }

    public void go_fullscreen(Page page) {
        // if already fullscreen, use that
        if (fullscreen_window != null) {
            fullscreen_window.present();
            
            return;
        }

        get_position(out pos_x, out pos_y);
        hide();
        
        FullscreenWindow fsw = new FullscreenWindow(page);
        
        if (get_current_page() != null)
            get_current_page().switching_to_fullscreen(fsw);
        
        fullscreen_window = fsw;
        fullscreen_window.present();
    }
    
    public void end_fullscreen() {
        if (fullscreen_window == null)
            return;
        
        move(pos_x, pos_y);

        show_all();
        
        if (get_current_page() != null)
            get_current_page().returning_from_fullscreen(fullscreen_window);
        
        fullscreen_window.hide();
        fullscreen_window.destroy();
        fullscreen_window = null;
        
        present();
    }
    
    public Gtk.Action? get_common_action(string name) {
        Page? page = get_current_page();
        if (page == null) {
            warning("No page to set action %s", name);
            
            return null;
        }
        
        return page.get_common_action(name);
    }
    
    public void set_common_action_sensitive(string name, bool sensitive) {
        Page? page = get_current_page();
        if (page == null) {
            warning("No page to set action %s", name);
            
            return;
        }
        
        page.set_common_action_sensitive(name, sensitive);
    }
    
    protected override void switched_pages(Page? old_page, Page? new_page) {
        if (old_page != null) {
            old_page.get_view().contents_altered.disconnect(on_update_actions);
            old_page.get_view().selection_group_altered.disconnect(on_update_actions);
            old_page.get_view().items_state_changed.disconnect(on_update_actions);
        }
        
        if (new_page != null) {
            new_page.get_view().contents_altered.connect(on_update_actions);
            new_page.get_view().selection_group_altered.connect(on_update_actions);
            new_page.get_view().items_state_changed.connect(on_update_actions);
            
            update_actions(new_page.get_view().get_selected_count(), new_page.get_view().get_count());
        }
        
        base.switched_pages(old_page, new_page);
    }
    
    // This is a counterpart to Page.update_actions(), but for common Gtk.Actions
    protected virtual void update_actions(int selected_count, int count) {
        bool primary_select_is_video = false;
        if (selected_count > 0 && get_current_page() != null)
            primary_select_is_video = get_current_page().get_view().get_selected_at(0).get_source()
                is Video;
            
        set_common_action_sensitive("CommonSelectAll", count > 0);
        set_common_action_sensitive("CommonJumpToFile", selected_count == 1);
        set_common_action_sensitive("CommonFullscreen", (count > 0) && (!primary_select_is_video));

        decorate_undo_action();
        decorate_redo_action();
    }
    
    private void on_update_actions() {
        Page? page = get_current_page();
        if (page != null)
            update_actions(page.get_view().get_selected_count(), page.get_view().get_count());
    }
    
    public static CommandManager get_command_manager() {
        return command_manager;
    }
    
    private void on_command_manager_altered() {
        decorate_undo_action();
        decorate_redo_action();
    }
    
    private void decorate_command_manager_action(string name, string prefix,
        string default_explanation, CommandDescription? desc) {
        Gtk.Action? action = get_common_action(name);
        if (action == null)
            return;
        
        if (desc != null) {
            action.label = "%s %s".printf(prefix, desc.get_name());
            action.tooltip = desc.get_explanation();
            action.sensitive = true;
        } else {
            action.label = prefix;
            action.tooltip = default_explanation;
            action.sensitive = false;
        }
    }
    
    public void decorate_undo_action() {
        decorate_command_manager_action("CommonUndo", Resources.UNDO_MENU, Resources.UNDO_TOOLTIP,
            get_command_manager().get_undo_description());
    }
    
    public void decorate_redo_action() {
        decorate_command_manager_action("CommonRedo", Resources.REDO_MENU, Resources.REDO_TOOLTIP,
            get_command_manager().get_redo_description());
    }
    
    private void on_undo() {
        command_manager.undo();
    }
    
    private void on_redo() {
        command_manager.redo();
    }
    
    private void on_select_all() {
        Page? page = get_current_page();
        if (page != null)
            page.get_view().select_all();
    }
    
    public override bool configure_event(Gdk.EventConfigure event) {
        if (window.get_state() == Gdk.WindowState.MAXIMIZED)
            maximized = !maximized;

        if (!maximized)
            get_size(out dimensions.width, out dimensions.height);

        return base.configure_event(event);
    }
}

