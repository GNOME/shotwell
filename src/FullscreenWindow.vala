public class FullscreenWindow : PageWindow {
    public const int TOOLBAR_INVOCATION_MSEC = 250;
    public const int TOOLBAR_DISMISSAL_SEC = 2;
    public const int TOOLBAR_CHECK_DISMISSAL_MSEC = 500;
    
    private Gtk.Overlay overlay = new Gtk.Overlay();
    private Gtk.Box toolbar = null;
    private Gtk.Button close_button = new Gtk.Button();
    private Gtk.ToggleButton pin_button = new Gtk.ToggleButton();
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

        //set_screen(AppWindow.get_instance().get_screen());
        
        // Needed so fullscreen will occur on correct monitor in multi-monitor setups
        Gdk.Rectangle monitor = get_monitor_geometry();
        //move(monitor.x, monitor.y);
        
        //set_border_width(0);

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
        //toolbar.set_show_arrow(false);
        toolbar.valign = Gtk.Align.END;
        toolbar.halign = Gtk.Align.CENTER;
        //toolbar.expand = false;
        toolbar.opacity = Resources.TRANSIENT_WINDOW_OPACITY;

        if (page is SlideshowPage) {
            // slideshow page doesn't own toolbar to hide it, subscribe to signal instead
            ((SlideshowPage) page).hide_toolbar.connect(hide_toolbar);
        } else {
            // only non-slideshow pages should have pin button
            toolbar.append(pin_button);
        }

        page.set_cursor_hide_time(TOOLBAR_DISMISSAL_SEC * 1000);
        page.start_cursor_hiding();

        toolbar.append(close_button);
        
        set_child(overlay);
        overlay.set_child(page);
        overlay.add_overlay (toolbar);

        // call to set_default_size() saves one repaint caused by changing
        // size from default to full screen. In slideshow mode, this change
        // also causes pixbuf cache updates, so it really saves some work.
        set_default_size(monitor.width, monitor.height);
        
        // need to create a Gdk.Window to set masks
        fullscreen();
        show();

        // capture motion events to show the toolbar
        //add_events(Gdk.EventMask.POINTER_MOTION_MASK);
        
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
        #if 0
        var monitor = get_display().get_monitor_at_window(AppWindow.get_instance().get_window());
        return monitor.get_geometry();
        #endif

        return Gdk.Rectangle();
    }
    
    public override bool configure_event(int width, int height) {
        bool result = base.configure_event(width, height);
        
        if (!switched_to) {
            get_current_page().switched_to();
            switched_to = true;
        }
        
        return result;
    }

    #if 0
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
    #endif
    
    private void on_close() {
        Config.Facade.get_instance().set_pin_toolbar_state(is_toolbar_dismissal_enabled);
        hide_toolbar();
        
        AppWindow.get_instance().end_fullscreen();
    }
    
    public new void close() {
        on_close();
    }
    
    public override void dispose() {
        Page? page = get_current_page();
        clear_current_page();
        
        if (page != null) {
            page.stop_cursor_hiding();
            page.switching_from();
        }
        
        base.dispose();
    }
    
    public override bool close_request() {
        on_close();
        AppWindow.get_instance().destroy();
        
        return true;
    }
    
    #if 0
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
    #endif
    
    private bool is_pointer_in_toolbar() {
        var seat = get_display().get_default_seat();
        if (seat == null) {
            debug("No seat for display");
            
            return false;
        }
        
        #if 0
        int py;
        seat.get_pointer().get_position(null, null, out py);
        
        int wy;
        toolbar.get_window().get_geometry(null, out wy, null, null);

        return (py >= wy);
        #endif
        return false;
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
        toolbar.show();

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
