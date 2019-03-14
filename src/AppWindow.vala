/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class FullscreenWindow : PageWindow {
    public const int TOOLBAR_INVOCATION_MSEC = 250;
    public const int TOOLBAR_DISMISSAL_SEC = 2;
    public const int TOOLBAR_CHECK_DISMISSAL_MSEC = 500;
    
    private Gtk.Overlay overlay = new Gtk.Overlay();
    private Gtk.Toolbar toolbar = null;
    private Gtk.ToolButton close_button = new Gtk.ToolButton(null, null);
    private Gtk.ToggleToolButton pin_button = new Gtk.ToggleToolButton();
    private bool is_toolbar_shown = false;
    private bool waiting_for_invoke = false;
    private time_t left_toolbar_time = 0;
    private bool switched_to = false;
    private bool is_toolbar_dismissal_enabled;

    private const GLib.ActionEntry[] entries = {
        { "LeaveFullscreen", on_close }
    };

    public FullscreenWindow(Page page) {
        base ();

        set_current_page(page);

        this.add_action_entries (entries, this);
        const string[] accels = { "F11", null };
        Application.set_accels_for_action ("win.LeaveFullscreen", accels);

        set_screen(AppWindow.get_instance().get_screen());
        
        // Needed so fullscreen will occur on correct monitor in multi-monitor setups
        Gdk.Rectangle monitor = get_monitor_geometry();
        move(monitor.x, monitor.y);
        
        set_border_width(0);

        // restore pin state
        is_toolbar_dismissal_enabled = Config.Facade.get_instance().get_pin_toolbar_state();
        
        pin_button.set_icon_name("view-pin-symbolic");
        pin_button.set_label(_("Pin Toolbar"));
        pin_button.set_tooltip_text(_("Pin the toolbar open"));
        pin_button.set_active(!is_toolbar_dismissal_enabled);
        pin_button.clicked.connect(update_toolbar_dismissal);
        
        close_button.set_icon_name("view-restore-symbolic");
        close_button.set_tooltip_text(_("Leave fullscreen"));
        close_button.set_action_name ("win.LeaveFullscreen");
        
        toolbar = page.get_toolbar();
        toolbar.set_show_arrow(false);
        toolbar.valign = Gtk.Align.END;
        toolbar.halign = Gtk.Align.CENTER;
        toolbar.expand = false;
        toolbar.opacity = Resources.TRANSIENT_WINDOW_OPACITY;

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
        
        add(overlay);
        overlay.add(page);
        overlay.add_overlay (toolbar);

        // call to set_default_size() saves one repaint caused by changing
        // size from default to full screen. In slideshow mode, this change
        // also causes pixbuf cache updates, so it really saves some work.
        set_default_size(monitor.width, monitor.height);
        
        // need to create a Gdk.Window to set masks
        fullscreen();
        show_all();

        // capture motion events to show the toolbar
        add_events(Gdk.EventMask.POINTER_MOTION_MASK);
        
        // If toolbar is enabled in "normal" ui OR was pinned in
        // fullscreen, start off with toolbar invoked, as a clue for the
        // user. Otherwise leave hidden unless activated by mouse over
        if (Config.Facade.get_instance().get_display_toolbar() ||
            !is_toolbar_dismissal_enabled) {
            invoke_toolbar();
        } else {
            hide_toolbar();
        }

        // Toolbar steals keyboard focus from page, put it back again
        page.grab_focus ();

        // Do not show menubar in fullscreen
        set_show_menubar (false);
    }

    public void disable_toolbar_dismissal() {
        is_toolbar_dismissal_enabled = false;
    }
    
    public void update_toolbar_dismissal() {
        is_toolbar_dismissal_enabled = !pin_button.get_active();
    }

    private Gdk.Rectangle get_monitor_geometry() {
        var monitor = get_display().get_monitor_at_window(AppWindow.get_instance().get_window());
        return monitor.get_geometry();
    }
    
    public override bool configure_event(Gdk.EventConfigure event) {
        bool result = base.configure_event(event);
        
        if (!switched_to) {
            get_current_page().switched_to();
            switched_to = true;
        }
        
        return result;
    }

    public override bool key_press_event(Gdk.EventKey event) {
        // check for an escape/abort 
        if (Gdk.keyval_name(event.keyval) == "Escape") {
            on_close();
            
            return true;
        }
        
        // propagate to this (fullscreen) window respecting "stop propagation" result...
        if (base.key_press_event != null && base.key_press_event(event))
            return true;
        
        // ... then propagate to the underlying window hidden behind this fullscreen one
        return AppWindow.get_instance().key_press_event(event);
    }
    
    private void on_close() {
        Config.Facade.get_instance().set_pin_toolbar_state(is_toolbar_dismissal_enabled);
        hide_toolbar();
        
        AppWindow.get_instance().end_fullscreen();
    }
    
    public new void close() {
        on_close();
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
    
    public override bool delete_event(Gdk.EventAny event) {
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
        var seat = get_display().get_default_seat();
        if (seat == null) {
            debug("No seat for display");
            
            return false;
        }
        
        int py;
        seat.get_pointer().get_position(null, null, out py);
        
        int wy;
        toolbar.get_window().get_geometry(null, out wy, null, null);

        return (py >= wy);
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
    
    private void invoke_toolbar() {
        toolbar.show_all();

        is_toolbar_shown = true;
        
        Timeout.add(TOOLBAR_CHECK_DISMISSAL_MSEC, on_check_toolbar_dismissal);
    }
    
    private bool on_check_toolbar_dismissal() {
        if (!is_toolbar_shown)
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
        toolbar.hide();
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
public abstract class PageWindow : Gtk.ApplicationWindow {
    private Page current_page = null;
    private int busy_counter = 0;
    
    protected virtual void switched_pages(Page? old_page, Page? new_page) {
    }
    
    protected PageWindow() {
        Object (application: Application.get_instance().get_system_app ());

        // the current page needs to know when modifier keys are pressed
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK
            | Gdk.EventMask.STRUCTURE_MASK);
        set_show_menubar (true);
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
        if (get_focus() is Gtk.Entry && get_focus().key_press_event(event))
            return true;
        
        if (current_page != null && current_page.notify_app_key_pressed(event))
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : false;
    }
    
    public override bool key_release_event(Gdk.EventKey event) {
        if (get_focus() is Gtk.Entry && get_focus().key_release_event(event))
            return true;
       
        if (current_page != null && current_page.notify_app_key_released(event))
                return true;
        
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

        var display = get_window ().get_display ();
        var cursor = new Gdk.Cursor.for_display (display, Gdk.CursorType.WATCH);
        get_window().set_cursor (cursor);
        spin_event_loop();
    }
    
    public void set_normal_cursor() {
        if (busy_counter <= 0) {
            busy_counter = 0;
            return;
        } else if (--busy_counter > 0) {
            return;
        }
        
        var display = get_window ().get_display ();
        var cursor = new Gdk.Cursor.for_display (display, Gdk.CursorType.LEFT_PTR);
        get_window().set_cursor (cursor);
        spin_event_loop();
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
    
    // the AppWindow maintains its own UI manager because the first UIManager an action group is
    // added to is the one that claims its accelerators
    protected bool maximized = false;
    protected Dimensions dimensions;
    protected int pos_x = 0;
    protected int pos_y = 0;
    
    protected AppWindow() {
        base();

        // although there are multiple AppWindow types, only one may exist per-process
        assert(instance == null);
        instance = this;

        title = Resources.APP_TITLE;
        set_default_icon_name("shotwell");

        // restore previous size and maximization state
        if (this is LibraryWindow) {
            Config.Facade.get_instance().get_library_window_state(out maximized, out dimensions);
        } else {
            assert(this is DirectWindow);
            Config.Facade.get_instance().get_direct_window_state(out maximized, out dimensions);
        }

        set_default_size(dimensions.width, dimensions.height);

        if (maximized)
            maximize();

        assert(command_manager == null);
        command_manager = new CommandManager();
        command_manager.altered.connect(on_command_manager_altered);
        
        // Because the first UIManager to associated with an ActionGroup claims the accelerators,
        // need to create the AppWindow's ActionGroup early on and add it to an application-wide
        // UIManager.  In order to activate those accelerators, we need to create a dummy UI string
        // that lists all the common actions.  We build it on-the-fly from the actions associated
        // with each ActionGroup while we're adding the groups to the UIManager.

        add_actions ();
        
        Gtk.CssProvider provider = new Gtk.CssProvider();
        provider.load_from_resource("/org/gnome/Shotwell/misc/org.gnome.Shotwell.css");
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    private const GLib.ActionEntry[] common_actions = {
        { "CommonAbout", on_about },
        { "CommonQuit", on_quit },
        { "CommonFullscreen", on_fullscreen },
        { "CommonHelpContents", on_help_contents },
        { "CommonHelpFAQ", on_help_faq },
        { "CommonHelpReportProblem", on_help_report_problem },
        { "CommonUndo", on_undo },
        { "CommonRedo", on_redo },
        { "CommonJumpToFile", on_jump_to_file },
        { "CommonSelectAll", on_select_all },
        { "CommonSelectNone", on_select_none }
    };

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

    public static Gtk.Builder create_builder(string glade_filename = "shotwell.ui", void *user = null) {
        Gtk.Builder builder = new Gtk.Builder();
        try {
            builder.add_from_resource(Resources.get_ui(glade_filename));
        } catch(GLib.Error error) {
            warning("Unable to create Gtk.Builder: %s\n", error.message);
        }
        
        builder.connect_signals(user);
        
        return builder;
    }
    
    public static void error_message(string message, Gtk.Window? parent = null) {
        error_message_with_title(Resources.APP_TITLE, message, parent);
    }
    
    public static void error_message_with_title(string title, string message, Gtk.Window? parent = null, bool should_escape = true) {
        // Per the Gnome HIG (http://library.gnome.org/devel/hig-book/2.32/windows-alert.html.en),            
        // alert-style dialogs mustn't have titles; we use the title as the primary text, and the
        // existing message as the secondary text.
        Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", build_alert_body_text(title, message, should_escape));
            
        // Occasionally, with_markup doesn't actually do anything, but set_markup always works.
        dialog.set_markup(build_alert_body_text(title, message, should_escape));

        dialog.use_markup = true;
        dialog.run();
        dialog.destroy();
    }
    
    public static bool negate_affirm_question(string message, string negative, string affirmative,
        string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", build_alert_body_text(title, message));

        dialog.set_markup(build_alert_body_text(title, message));
        dialog.add_buttons(negative, Gtk.ResponseType.NO, affirmative, Gtk.ResponseType.YES);
        dialog.set_urgency_hint(true);
        
        bool response = (dialog.run() == Gtk.ResponseType.YES);

        dialog.destroy();
        
        return response;
    }

    public static Gtk.ResponseType negate_affirm_cancel_question(string message, string negative,
        string affirmative, string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", build_alert_body_text(title, message));

        dialog.add_buttons(negative, Gtk.ResponseType.NO, affirmative, Gtk.ResponseType.YES,
            _("_Cancel"), Gtk.ResponseType.CANCEL);
        
        // Occasionally, with_markup doesn't actually enable markup, but set_markup always works.
        dialog.set_markup(build_alert_body_text(title, message));
        dialog.use_markup = true;

        int response = dialog.run();
        
        dialog.destroy();
        
        return (Gtk.ResponseType) response;
    }
    
    public static Gtk.ResponseType affirm_cancel_question(string message, string affirmative,
        string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", message);
        // Occasionally, with_markup doesn't actually enable markup...? Force the issue.
        dialog.set_markup(message);
        dialog.use_markup = true;
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
        panic(_("A fatal error occurred when accessing Shotwell’s library. Shotwell cannot continue.\n\n%s").printf(
            err.message));
    }
    
    public static void panic(string msg) {
        critical(msg);
        error_message(msg);
        
        Application.get_instance().panic();
    }
    
    public abstract string get_app_role();

    protected void on_about() {
        const string[] artists = { "Celler Schloss created by Hajotthu, CC BY-SA 3.0, https://commons.wikimedia.org/wiki/File:Celler_Schloss_April_2010.jpg#file", null };
        Gtk.show_about_dialog(this,
            "version", Resources.APP_VERSION + " \u2013 “Celle”",
            "comments", get_app_role(),
            "copyright", Resources.COPYRIGHT,
            "website", Resources.HOME_URL,
            "license", Resources.LICENSE,
            "website-label", _("Visit the Shotwell web site"),
            "authors", Resources.AUTHORS,
            "logo", Resources.get_icon(Resources.ICON_ABOUT_LOGO, -1),
            "artists", artists,
            "translator-credits", _("translator-credits"),
            null
        );
    }

    private void on_help_contents() {
        try {
            Resources.launch_help(this);
        } catch (Error err) {
            error_message(_("Unable to display help: %s").printf(err.message));
        }
    }

    private void on_help_report_problem() {
        try {
            show_uri(Resources.BUG_DB_URL);
        } catch (Error err) {
            error_message(_("Unable to navigate to bug database: %s").printf(err.message));
        }
    }
    
    private void on_help_faq() {
        try {
            show_uri(Resources.FAQ_URL);
        } catch (Error err) {
            error_message(_("Unable to display FAQ: %s").printf(err.message));
        }
    }
    
    protected virtual void on_quit() {
        Application.get_instance().exit();
    }

    protected void on_jump_to_file() {
        if (get_current_page().get_view().get_selected_count() != 1)
            return;

        MediaSource? media = get_current_page().get_view().get_selected_at(0).get_source()
            as MediaSource;
        if (media == null)
            return;
        
        try {
           AppWindow.get_instance().show_file_uri(media.get_master_file());
        } catch (Error err) {
            AppWindow.error_message(Resources.jump_to_file_failed(err));
        }
    }
    
    protected override void destroy() {
        on_quit();
    }
    
    public void show_file_uri(File file) throws Error {
        show_file_in_filemanager.begin(file);
    }
    
    public void show_uri(string url) throws Error {
        Gtk.show_uri_on_window(this, url, Gdk.CURRENT_TIME);
    }
    
    protected virtual void add_actions () {
        this.add_action_entries (AppWindow.common_actions, this);
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
    
    public GLib.Action? get_common_action(string name) {
        return lookup_action (name);
    }
    
    public void set_common_action_sensitive(string name, bool sensitive) {
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action != null)
            action.set_enabled (sensitive);
    }
    
    public void set_common_action_important(string name, bool important) {
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action != null)
            action.set_enabled (sensitive);
    }
    
    public void set_common_action_visible(string name, bool visible) {
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action != null)
            action.set_enabled (sensitive);
    }
    
    protected override void switched_pages(Page? old_page, Page? new_page) {
        update_common_action_availability(old_page, new_page);
        
        if (old_page != null) {
            old_page.get_view().contents_altered.disconnect(on_update_common_actions);
            old_page.get_view().selection_group_altered.disconnect(on_update_common_actions);
            old_page.get_view().items_state_changed.disconnect(on_update_common_actions);
        }
        
        if (new_page != null) {
            new_page.get_view().contents_altered.connect(on_update_common_actions);
            new_page.get_view().selection_group_altered.connect(on_update_common_actions);
            new_page.get_view().items_state_changed.connect(on_update_common_actions);
            
            update_common_actions(new_page, new_page.get_view().get_selected_count(),
                new_page.get_view().get_count());
        }
        
        base.switched_pages(old_page, new_page);
    }
    
    // This is called when a Page is switched out and certain common actions are simply
    // unavailable for the new one.  This is different than update_common_actions() in that that
    // call is made when state within the Page has changed.
    protected virtual void update_common_action_availability(Page? old_page, Page? new_page) {
        bool is_checkerboard = new_page is CheckerboardPage;
        
        set_common_action_sensitive("CommonSelectAll", is_checkerboard);
        set_common_action_sensitive("CommonSelectNone", is_checkerboard);
    }
    
    // This is a counterpart to Page.update_actions(), but for common Gtk.Actions
    // NOTE: Although CommonFullscreen is declared here, it's implementation is up to the subclasses,
    // therefore they need to update its action.
    protected virtual void update_common_actions(Page page, int selected_count, int count) {
        if (page is CheckerboardPage)
            set_common_action_sensitive("CommonSelectAll", count > 0);
        set_common_action_sensitive("CommonJumpToFile", selected_count == 1);
        
        decorate_undo_action();
        decorate_redo_action();
    }
    
    private void on_update_common_actions() {
        Page? page = get_current_page();
        if (page != null)
            update_common_actions(page, page.get_view().get_selected_count(), page.get_view().get_count());
    }

    public void update_menu_item_label (string id,
                                         string new_label) {
        var bar = this.get_current_page().get_menubar() as GLib.Menu;

        if (bar == null) {
            return;
        }

        var items = bar.get_n_items ();
        for (var i = 0; i< items; i++) {
            var model = bar.get_item_link (i, GLib.Menu.LINK_SUBMENU);
            if (bar == null) {
                continue;
            }

            var model_items = model.get_n_items ();
            for (var j = 0; j < model_items; j++) {
                var subsection = model.get_item_link (j, GLib.Menu.LINK_SECTION);

                if (subsection == null)
                    continue;

                // Recurse into submenus
                var sub_items = subsection.get_n_items ();
                for (var k = 0; k < sub_items; k++) {
                    var it = subsection.iterate_item_attributes (k);
                    while (it.next ()) {
                        if ((it.get_name() == "id" && it.get_value ().get_string () == id) ||
                            (it.get_name() == "action" && it.get_value().get_string().has_suffix("." + id))) {
                            var md = subsection as GLib.Menu;
                            var m = new GLib.MenuItem.from_model (subsection, k);
                            m.set_label (new_label);
                            md.remove (k);
                            md.insert_item (k, m);

                            return;
                        }
                    }
                }
            }
        }
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
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action == null) {
            return;
        }

        string label = prefix;

        if (desc != null) {
            label += " " + desc.get_name();
            action.set_enabled(true);
        } else {
            label = prefix;
            action.set_enabled(false);
        }
        this.update_menu_item_label(name, label);
    }
    
    public void decorate_undo_action() {
        decorate_command_manager_action("CommonUndo", Resources.UNDO_MENU, "",
            get_command_manager().get_undo_description());
    }
    
    public void decorate_redo_action() {
        decorate_command_manager_action("CommonRedo", Resources.REDO_MENU, "",
            get_command_manager().get_redo_description());
    }
    
    private void on_undo() {
        command_manager.undo();
    }
    
    private void on_redo() {
        command_manager.redo();
    }
    
    private void on_select_all() {
        Page? page = get_current_page() as CheckerboardPage;
        if (page != null)
            page.get_view().select_all();
    }
    
    private void on_select_none() {
        Page? page = get_current_page() as CheckerboardPage;
        if (page != null)
            page.get_view().unselect_all();
    }
    
    public override bool configure_event(Gdk.EventConfigure event) {
        maximized = (get_window().get_state() == Gdk.WindowState.MAXIMIZED);

        if (!maximized)
            get_size(out dimensions.width, out dimensions.height);

        return base.configure_event(event);
    }
    
}

