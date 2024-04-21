public class FullscreenWindow : PageWindow {
    public const int TOOLBAR_INVOCATION_MSEC = 250;
    public const int TOOLBAR_DISMISSAL_SEC = 2 * 1000 * 1000;
    public const int TOOLBAR_CHECK_DISMISSAL_MSEC = 500;
    
    private Gtk.Overlay overlay = new Gtk.Overlay();
    private Gtk.Box toolbar = null;
    private Gtk.Button close_button = new Gtk.Button();
    private Gtk.ToggleButton pin_button = new Gtk.ToggleButton();
    private bool is_toolbar_shown = false;
    private bool waiting_for_invoke = false;
    private int64 left_toolbar_time = 0;
    private bool switched_to = false;
    private bool is_toolbar_dismissal_enabled;
    private bool pointer_in_toolbar = false;
    Gtk.Allocation toolbar_alloc;

    private const GLib.ActionEntry[] entries = {
        { "LeaveFullscreen", on_close }
    };

    public FullscreenWindow(Page page, Gdk.Monitor monitor) {
        base ();

        set_current_page(page);
        set_child(overlay);
        overlay.set_child(page);

        this.add_action_entries (entries, this);
        const string[] accels = { "F11", "Escape", null };
        Application.set_accels_for_action ("win.LeaveFullscreen", accels);

        // restore pin state
        is_toolbar_dismissal_enabled = Config.Facade.get_instance().get_pin_toolbar_state();
        

        // call to set_default_size() saves one repaint caused by changing
        // size from default to full screen. In slideshow mode, this change
        // also causes pixbuf cache updates, so it really saves some work.
        var geometry = monitor.get_geometry();
        set_default_size(geometry.width, geometry.height);
        // need to create a Gdk.Window to set masks
        fullscreen_on_monitor(monitor);
        show();

        // capture motion events to show the toolbar
        var motion = new Gtk.EventControllerMotion();
        motion.enter.connect(() => {
            pointer_in_toolbar = true;
        });
        motion.leave.connect(() => {
            pointer_in_toolbar = false;
        });
        toolbar.add_controller(motion);

        motion = new Gtk.EventControllerMotion();
        motion.motion.connect(motion_notify_event);
        page.add_controller(motion);


        var key = new Gtk.EventControllerKey();
        key.key_pressed.connect(key_press_event);
        ((Gtk.Widget)this).add_controller(key);
    }

    public void disable_toolbar_dismissal() {
        is_toolbar_dismissal_enabled = false;
    }
    
    public void update_toolbar_dismissal() {
        is_toolbar_dismissal_enabled = !pin_button.get_active();
    }

    public override bool configure_event(int width, int height) {
        bool result = base.configure_event(width, height);
        
        if (!switched_to) {
            var page = get_current_page();
            page.switched_to();
            switched_to = true;

            pin_button.set_icon_name("view-pin-symbolic");
            pin_button.set_tooltip_text(_("Pin the toolbar open"));
            pin_button.set_active(!is_toolbar_dismissal_enabled);
            pin_button.clicked.connect(update_toolbar_dismissal);
            
            close_button.set_icon_name("view-restore-symbolic");
            close_button.set_tooltip_text(_("Leave fullscreen"));
            close_button.set_action_name ("win.LeaveFullscreen");
            
            toolbar = page.get_toolbar();
            toolbar.valign = Gtk.Align.END;
            toolbar.halign = Gtk.Align.CENTER;
            toolbar.opacity = Resources.TRANSIENT_WINDOW_OPACITY;
    
            if (page is SlideshowPage) {
                // slideshow page doesn't own toolbar to hide it, subscribe to signal instead
                ((SlideshowPage) page).hide_toolbar.connect(hide_toolbar);
            } else {
                // only non-slideshow pages should have pin button
                toolbar.append(pin_button);
            }
    
            page.set_cursor_hide_time(TOOLBAR_DISMISSAL_SEC / 1000);
            page.start_cursor_hiding();
    
            toolbar.append(close_button);            
            overlay.add_overlay (toolbar);
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
        }
        
        return result;
    }

    public override bool key_press_event(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        // check for an escape/abort 
        if (Gdk.keyval_name(keyval) == "Escape") {
            on_close();
            
            return true;
        }

        if (base.key_press_event(event, keyval, keycode, modifiers))
            return true;
                
        // ... then propagate to the underlying window hidden behind this fullscreen one
        return event.forward (AppWindow.get_instance());
    }
    
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
    
    public void motion_notify_event(double x, double y) {
        if (!is_toolbar_shown) {
            // if pointer is in toolbar height range without the mouse down (i.e. in the middle of
            // an edit operation) and it stays there the necessary amount of time, invoke the
            // toolbar
            if (!waiting_for_invoke && is_pointer_in_toolbar()) {
                Timeout.add(TOOLBAR_INVOCATION_MSEC, on_check_toolbar_invocation);
                waiting_for_invoke = true;
            }
        }
    }
    
    private bool is_pointer_in_toolbar() {
        if (toolbar.visible) {
            return pointer_in_toolbar;
        }
        
        var seat = get_display().get_default_seat();
        if (seat == null) {
            debug("No seat for display");
            
            return false;
        }
        
        double py = 0;
        get_surface().get_device_position(seat.get_pointer(), null, out py, null);
        
        return py >= toolbar_alloc.y;
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
            left_toolbar_time = GLib.get_monotonic_time();
            
            return true;
        }
        
        // see if enough time has elapsed
        var now = GLib.get_monotonic_time();
        assert(now >= left_toolbar_time);

        if (now - left_toolbar_time < TOOLBAR_DISMISSAL_SEC)
            return true;
        
        hide_toolbar();
        
        return false;
    }
    
    private void hide_toolbar() {
        // Save location of toolbar before hiding
        toolbar.get_allocation(out toolbar_alloc);
        toolbar.hide();
        is_toolbar_shown = false;
    }
}
