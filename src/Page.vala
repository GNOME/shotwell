/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class InjectionGroup {
    public class Element {
        public enum ItemType {
            MENUITEM,
            MENU,
            SEPARATOR
        }
        public string name;
        public string action;
        public string? accelerator;
        public ItemType kind;

        public Element(string name, string? action, string? accelerator, ItemType kind) {
            this.name = name;
            this.action = action != null ? action : name;
            this.accelerator = accelerator;
            this.kind = kind;
        }
    }

    private string path;
    private Gee.ArrayList<Element?> elements = new Gee.ArrayList<Element?>();
    private int separator_id = 0;

    public InjectionGroup(string path) {
        this.path = path;
    }

    public string get_path() {
        return path;
    }

    public Gee.List<Element?> get_elements() {
        return elements;
    }

    public void add_menu_item(string name, string? action = null, string? accelerator = null) {
        elements.add(new Element(name, action, accelerator, Element.ItemType.MENUITEM));
    }

    public void add_menu(string name, string? action = null) {
        elements.add(new Element(name, action, null, Element.ItemType.MENU));
    }

    public void add_separator() {
        elements.add(new Element("%d-separator".printf(separator_id++), null,
                    null,
                    Element.ItemType.SEPARATOR));
    }
}

public abstract class Page : Gtk.Box {
    private const int CONSIDER_CONFIGURE_HALTED_MSEC = 400;
    
    protected Gtk.ScrolledWindow scrolled;
    protected Gtk.Builder builder = new Gtk.Builder ();
    protected Gtk.Box toolbar;
    protected bool in_view = false;
    
    private string page_name;
    private ViewCollection view = null;
    private Gtk.Window container = null;
    private string toolbar_path;
    private Gdk.Rectangle last_position = Gdk.Rectangle();
    private weak Gtk.Widget event_source = null;
    private ulong last_configure_ms = 0;
    private bool report_move_finished = false;
    private bool report_resize_finished = false;
    private Gdk.Point last_down = Gdk.Point();
    private bool is_destroyed = false;
    private bool ctrl_pressed = false;
    private bool alt_pressed = false;
    private bool shift_pressed = false;
    private bool super_pressed = false;
    private string? last_cursor = null;
    private bool cursor_hidden = false;
    private int cursor_hide_msec = 0;
    private uint last_timeout_id = 0;
    private int cursor_hide_time_cached = 0;
    private bool are_actions_attached = false;
    private OneShotScheduler? update_actions_scheduler = null;

    // Event controllers
    private Gtk.GestureClick clicks;
    private Gtk.EventControllerMotion motion;
    private Gtk.EventControllerScroll scroll;
    
    protected Page(string page_name) {
        Object (orientation: Gtk.Orientation.HORIZONTAL);

        scrolled = new Gtk.ScrolledWindow();
        append(scrolled);
        scrolled.hexpand = true;
        scrolled.vexpand = true;
        this.page_name = page_name;
        
        view = new ViewCollection("ViewCollection for Page %s".printf(page_name));
        
        last_down = { -1, -1 };
        
        scrolled.set_can_focus(true);

        //popup_menu.connect(on_context_keypress);
        
        scrolled.realize.connect(attach_view_signals);
    }
    
    ~Page() {
#if TRACE_DTORS
        debug("DTOR: Page %s", page_name);
#endif
    }
    
    // This is called by the page controller when it has removed this page ... pages should override
    // this (or the signal) to clean up
    public override void dispose() {
        if (is_destroyed)
            return;
        
        // untie signals
        detach_event_source();
        detach_view_signals();
        view.close();
        
        // remove refs to external objects which may be pointing to the Page
        clear_container();
        
        if (toolbar != null)
            toolbar.destroy();
        
        // halt any pending callbacks
        if (update_actions_scheduler != null)
            update_actions_scheduler.cancel();
        
        is_destroyed = true;
        
        base.dispose();
        
        debug("Page %s Destroyed", get_page_name());
    }
    
    public string get_page_name() {
        return page_name;
    }
    
    public virtual void set_page_name(string page_name) {
        this.page_name = page_name;
    }
    
    public string to_string() {
        return page_name;
    }
    
    public ViewCollection get_view() {
        return view;
    }
    
    public Gtk.Window? get_container() {
        return container;
    }
    
    public virtual void set_container(Gtk.Window container) {
        assert(this.container == null);
        
        this.container = container;
    }
    
    public virtual void clear_container() {
        container = null;
    }
    
    public void set_event_source(Gtk.Widget event_source) {
        assert(this.event_source == null);

        this.event_source = event_source;
        event_source.focusable = true;

        clicks = new Gtk.GestureClick();
        clicks.set_name ("CheckerboardPage click source");
        clicks.set_button (0); // Listen to all buttons
        clicks.set_exclusive (true); // TODO: Need to be true or false?
        clicks.pressed.connect (on_button_pressed_internal);
        clicks.released.connect (on_button_released_internal);
        event_source.add_controller (clicks);

        motion = new Gtk.EventControllerMotion ();
        motion.set_name ("CheckerboardPage motion source");
        motion.motion.connect(on_motion_internal);
        motion.leave.connect(on_leave_notify_event);
        event_source.add_controller (motion);

        scroll = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.BOTH_AXES
            | Gtk.EventControllerScrollFlags.DISCRETE);
        scroll.scroll.connect(on_mousewheel_internal);
        event_source.add_controller(scroll);
    }
    
    private void detach_event_source() {
        if (event_source == null)
            return;

        event_source.remove_controller (clicks);
        clicks = null;
        event_source.remove_controller (motion);
        motion = null;
        event_source.remove_controller (scroll);
        scroll = null;
        event_source = null;
    }
    
    public Gtk.Widget? get_event_source() {
        return event_source;
    }

    private bool menubar_injected = false;
    public GLib.MenuModel get_menubar() {
        var model = builder.get_object ("MenuBar") as GLib.Menu;
        if (model == null) {
            return new GLib.Menu();
        }

        if (!menubar_injected) {
            // Collect injected UI elements and add them to the UI manager
            InjectionGroup[] injection_groups = init_collect_injection_groups();
            foreach (InjectionGroup group in injection_groups) {
                var items = model.get_n_items ();
                for (int i = 0; i < items; i++) {
                    var submenu = model.get_item_link (i, GLib.Menu.LINK_SUBMENU);

                    var section = this.find_extension_point (submenu,
                                                             group.get_path ());

                    if (section == null) {
                        continue;
                    }

                    foreach (var element in group.get_elements ()) {
                        var menu = section as GLib.Menu;
                        switch (element.kind) {
                            case InjectionGroup.Element.ItemType.MENUITEM:
                                var item = new GLib.MenuItem (element.name,
                                                              "win." + element.action);
                                if (element.accelerator != null) {
                                    item.set_attribute ("accel",
                                                        "s",
                                                        element.accelerator);
                                }

                                menu.append_item (item);
                                break;
                            default:
                                break;
                        }
                    }
                }
            }

            this.menubar_injected = true;
        }

        return model;
    }

    public virtual Gtk.Box get_toolbar() {
        if (toolbar == null) {
            toolbar = toolbar_path == null ? new Gtk.Box(Gtk.Orientation.HORIZONTAL, 9) :
                                             builder.get_object (toolbar_path)
                                             as Gtk.Box;
            toolbar.add_css_class("bottom-toolbar");  // for elementary theme
            toolbar.add_css_class("toolbar");
        }
        return toolbar;
    }
    
    public virtual Gtk.PopoverMenu? get_page_context_menu() {
        return null;
    }
    
    public virtual void switching_from() {
        in_view = false;
        //remove_actions(AppWindow.get_instance());
        var map = get_container() as GLib.ActionMap;
        if (map != null) {
            remove_actions(map);
        }
        if (toolbar_path != null)
            toolbar = null;
    }
    
    public virtual void switched_to() {
        in_view = true;
        add_ui();
        var map = get_container() as GLib.ActionMap;
        if (map != null) {
            add_actions(map);
        }
        int selected_count = get_view().get_selected_count();
        int count = get_view().get_count();
        init_actions(selected_count, count);
        update_actions(selected_count, count);
        update_modifiers();
    }
    
    public virtual void ready() {
    }
    
    public bool is_in_view() {
        return in_view;
    }
    
    public virtual void switching_to_fullscreen(FullscreenWindow fsw) {
        remove_actions(AppWindow.get_instance());
    }
    
    public virtual void returning_from_fullscreen(FullscreenWindow fsw) {
        add_actions(AppWindow.get_instance());
        switched_to();
    }

    public GLib.Action? get_action (string name) {
        GLib.ActionMap? map = null;
        if (container is FullscreenWindow) {
            map = container as GLib.ActionMap;
        } else {
            map = AppWindow.get_instance () as GLib.ActionMap;
        }

        if (map != null) {
            return map.lookup_action(name);
        }

        return null;
    }
    
    public void set_action_sensitive(string name, bool sensitive) {
        GLib.SimpleAction? action = get_action(name) as GLib.SimpleAction;
        if (action != null)
            action.set_enabled (sensitive);
    }
    
    public void set_action_details(string name, string? label, string? tooltip, bool sensitive) {
        GLib.SimpleAction? action = get_action(name) as GLib.SimpleAction;

        if (action == null)
            return;

        if (label != null)
            this.update_menu_item_label (name, label);

        action.set_enabled (sensitive);
    }
   
    public GLib.Action? get_common_action(string name, bool log_warning = true) {
        var action = get_action (name);

        if (action != null)
            return action;
        
        if (log_warning)
            warning("Page %s: Unable to locate common action %s", get_page_name(), name);
        
        return null;
    }
    
    public void set_common_action_sensitive(string name, bool sensitive) {
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action != null)
            action.set_enabled (sensitive);
    }

    public void set_common_action_label(string name, string label) {
        debug ("Trying to set common action label for %s", name);
    }
    
    public void set_common_action_important(string name, bool important) {
        debug ("Setting action to important: %s", name);
    }
    
    public void activate_common_action(string name) {
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action != null)
            action.activate(null);
    }
    
    public bool get_ctrl_pressed() {
        return ctrl_pressed;
    }
    
    public bool get_alt_pressed() {
        return alt_pressed;
    }
    
    public bool get_shift_pressed() {
        return shift_pressed;
    }
    
    public bool get_super_pressed() {
        return super_pressed;
    }

     protected void set_action_active (string name, bool active) {
        var action = get_action (name) as GLib.SimpleAction;
        if (action != null) {
            action.set_state (active);
        }
    }

    private bool get_modifiers(out bool ctrl, out bool alt, out bool shift, out bool super) {
        if (AppWindow.get_instance().get_surface() == null) {
            ctrl = false;
            alt = false;
            shift = false;
            super = false;
            
            return false;
        }
        
        double x, y;
        Gdk.ModifierType mask;
        var seat = Gdk.Display.get_default().get_default_seat();
        AppWindow.get_instance().get_surface().get_device_position(seat.get_pointer(), out x, out y, out mask);

        ctrl = (mask & Gdk.ModifierType.CONTROL_MASK) != 0;
        alt = (mask & Gdk.ModifierType.ALT_MASK) != 0;
        shift = (mask & Gdk.ModifierType.SHIFT_MASK) != 0;
        super = (mask & Gdk.ModifierType.SUPER_MASK) != 0; // not SUPER_MASK
        
        return true;
    }

    private void update_modifiers() {
        bool ctrl_currently_pressed, alt_currently_pressed, shift_currently_pressed,
            super_currently_pressed;
        if (!get_modifiers(out ctrl_currently_pressed, out alt_currently_pressed,
            out shift_currently_pressed, out super_currently_pressed)) {
            return;
        }
        
        if (ctrl_pressed && !ctrl_currently_pressed)
            on_ctrl_released();
        else if (!ctrl_pressed && ctrl_currently_pressed)
            on_ctrl_pressed();

        if (alt_pressed && !alt_currently_pressed)
            on_alt_released();
        else if (!alt_pressed && alt_currently_pressed)
            on_alt_pressed();

        if (shift_pressed && !shift_currently_pressed)
            on_shift_released();
        else if (!shift_pressed && shift_currently_pressed)
            on_shift_pressed();

        if(super_pressed && !super_currently_pressed)
            on_super_released();
        else if (!super_pressed && super_currently_pressed)
            on_super_pressed();
        
        ctrl_pressed = ctrl_currently_pressed;
        alt_pressed = alt_currently_pressed;
        shift_pressed = shift_currently_pressed;
        super_pressed = super_currently_pressed;
    }
    
    public PageWindow? get_page_window() {
        Gtk.Widget p = parent;
        while (p != null) {
            if (p is PageWindow)
                return (PageWindow) p;
            
            p = p.parent;
        }
        
        return null;
    }
    
    public CommandManager get_command_manager() {
        return AppWindow.get_command_manager();
    }

    protected virtual void add_actions (GLib.ActionMap map) { }
    protected virtual void remove_actions (GLib.ActionMap map) { }

    protected void on_action_toggle (GLib.Action action, Variant? value) {
        Variant new_state = ! (bool) action.get_state ();
        action.change_state (new_state);
    }

    protected void on_action_radio (GLib.Action action, Variant? value) {
        action.change_state (value);
    }

    private void add_ui() {
        // Collect all UI filenames and load them into the UI manager
        Gee.List<string> ui_filenames = new Gee.ArrayList<string>();
        init_collect_ui_filenames(ui_filenames);
        if (ui_filenames.size == 0)
            message("No UI file specified for %s", get_page_name());
        
        foreach (string ui_filename in ui_filenames)
            init_load_ui(ui_filename);

        //ui.insert_action_group(action_group, 0);
    }

    public void init_toolbar(string path) {
        toolbar_path = path;
    }
   
    // Called from "realize"
    private void attach_view_signals() {
        if (are_actions_attached)
            return;
        
        // initialize the Gtk.Actions according to current state
        int selected_count = get_view().get_selected_count();
        int count = get_view().get_count();
        init_actions(selected_count, count);
        update_actions(selected_count, count);
        
        // monitor state changes to update actions
        get_view().items_state_changed.connect(on_update_actions);
        get_view().selection_group_altered.connect(on_update_actions);
        get_view().items_visibility_changed.connect(on_update_actions);
        get_view().contents_altered.connect(on_update_actions);
        
        are_actions_attached = true;
    }
    
    // Called from destroy()
    private void detach_view_signals() {
        if (!are_actions_attached)
            return;
        
        get_view().items_state_changed.disconnect(on_update_actions);
        get_view().selection_group_altered.disconnect(on_update_actions);
        get_view().items_visibility_changed.disconnect(on_update_actions);
        get_view().contents_altered.disconnect(on_update_actions);
        
        are_actions_attached = false;
    }
    
    private void on_update_actions() {
        if (update_actions_scheduler == null) {
            update_actions_scheduler = new OneShotScheduler(
                "Update actions scheduler for %s".printf(get_page_name()),
                on_update_actions_on_idle);
        }
        
        update_actions_scheduler.at_priority_idle(Priority.LOW);
    }
    
    private void on_update_actions_on_idle() {
        if (is_destroyed)
            return;

        if (!this.in_view)
            return;
        
        update_actions(get_view().get_selected_count(), get_view().get_count());
    }
    
    private void init_load_ui(string ui_filename) {
        var ui_resource = Resources.get_ui(ui_filename);
        try {
            builder.add_from_resource(ui_resource);
            this.menubar_injected = false;
        } catch (Error err) {
            AppWindow.panic("Error loading UI resource %s: %s".printf(
                ui_resource, err.message));
        }
    }
    
    // This is called during add_ui() to collect all the UI files to be loaded into the UI
    // manager.  Because order is important here, call the base method *first*, then add the
    // classes' filename.
    protected virtual void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
    }

    // This is called during add_ui() to collect all Page.InjectedUIElements for the page.  They
    // should be added to the MultiSet using the injection path as the key.
    protected virtual InjectionGroup[] init_collect_injection_groups() {
        return new InjectionGroup[0];
    }
    
    // This is called during "map" allowing for Gtk.Actions to be updated at
    // initialization time.
    protected virtual void init_actions(int selected_count, int count) {
    }
    
    // This is called during "map" and during ViewCollection selection, visibility,
    // and collection content altered events.  This can be used to both initialize Gtk.Actions and
    // update them when selection or visibility has been altered.
    protected virtual void update_actions(int selected_count, int count) {
    }
    
    // Use this function rather than GDK or GTK's get_pointer, especially if called during a 
    // button-down mouse drag (i.e. a window grab).
    //
    // For more information, see: https://bugzilla.gnome.org/show_bug.cgi?id=599937
    public bool get_event_source_pointer(out double x, out double y, out Gdk.ModifierType mask) {
        if (event_source == null) {
            x = 0;
            y = 0;
            mask = 0;
            
            return false;
        }
        
        var seat = Gdk.Display.get_default().get_default_seat();
        double win_x, win_y;
        event_source.get_native().get_surface().get_device_position(seat.get_pointer(), out win_x, out win_y, out mask);
        event_source.get_native().translate_coordinates(event_source, win_x, win_y, out x, out y);
        
        if (last_down.x < 0 || last_down.y < 0)
            return true;
            
        // check for bogus values inside a drag which goes outside the window
        // caused by (most likely) X windows signed 16-bit int overflow and fixup
        // (https://bugzilla.gnome.org/show_bug.cgi?id=599937)
        
        if ((x - last_down.x).abs() >= 0x7FFF)
            x += 0xFFFF;
        
        if ((y - last_down.y).abs() >= 0x7FFF)
            y += 0xFFFF;
        
        return true;
    }
    
    protected virtual bool on_left_click(Gtk.EventController event, int press, double x, double y) {
        return false;
    }
    
    protected virtual bool on_middle_click(Gtk.EventController event, int press, double x, double y) {
        return false;
    }
    
    protected virtual bool on_right_click(Gtk.EventController event, int press, double x, double y) {
        return false;
    }
    
    protected virtual bool on_left_released(Gtk.EventController event, int press, double x, double y) {
        return false;
    }
    
    protected virtual bool on_middle_released(Gtk.EventController event, int press, double x, double y) {
        return false;
    }
    
    protected virtual bool on_right_released(Gtk.EventController event, int press, double x, double y) {
        return false;
    }
    
    private void on_button_pressed_internal(Gtk.GestureClick gesture, int press, double x, double y) {
        var sequence = gesture.get_current_sequence ();
        var event = gesture.get_last_event (sequence);

        bool result = false;

        switch (gesture.get_current_button()) {
            case 1:
                if (event_source != null)
                    event_source.grab_focus();
                
                // stash location of mouse down for drag fixups
                last_down.x = (int) x;
                last_down.y = (int) y;
                
                result = on_left_click(gesture, press, x, y);
                break;

            case 2:
                result = on_middle_click(gesture, press, x, y);
                break;
            
            case 3:
                result = on_right_click(gesture, press, x, y);
                break;
            
            default:
                break;
        }

        if (result) {
            gesture.set_sequence_state (sequence, Gtk.EventSequenceState.CLAIMED);
        }
    }
    
    private void on_button_released_internal(Gtk.GestureClick gesture, int press, double x, double y) {
        var sequence = gesture.get_current_sequence ();
        var event = gesture.get_last_event (sequence);

        bool result = false;

        switch (gesture.get_current_button()) {
            case 1:
                if (event_source != null)
                    event_source.grab_focus();
                
                // stash location of mouse down for drag fixups
                last_down.x = -1;
                last_down.y = -1;
                
                result = on_left_released(gesture, press, x, y);
                break;

            case 2:
                result = on_middle_released(gesture, press, x, y);
                break;
            
            case 3:
                result = on_right_released(gesture, press, x, y);
                break;
            
            default:
                break;
        }

        if (result) {
            gesture.set_sequence_state (sequence, Gtk.EventSequenceState.CLAIMED);
        }
    }

    protected virtual bool on_ctrl_pressed() {
        return false;
    }
    
    protected virtual bool on_ctrl_released() {
        return false;
    }
    
    protected virtual bool on_alt_pressed() {
        return false;
    }
    
    protected virtual bool on_alt_released() {
        return false;
    }
    
    protected virtual bool on_shift_pressed() {
        return false;
    }
    
    protected virtual bool on_shift_released() {
        return false;
    }

    protected virtual bool on_super_pressed() {
        return false;
    }
    
    protected virtual bool on_super_released() {
        return false;
    }
    
    protected virtual bool on_app_key_pressed(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        return false;
    }
    
    protected virtual bool on_app_key_released(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        return false;
    }
    
    public bool notify_app_key_pressed(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        bool ctrl_currently_pressed, alt_currently_pressed, shift_currently_pressed,
            super_currently_pressed;
        get_modifiers(out ctrl_currently_pressed, out alt_currently_pressed,
            out shift_currently_pressed, out super_currently_pressed);

        switch (Gdk.keyval_name(keyval)) {
            case "Control_L":
            case "Control_R":
                if (!ctrl_currently_pressed || ctrl_pressed)
                    return false;

                ctrl_pressed = true;
                
                return on_ctrl_pressed();

            case "Meta_L":
            case "Meta_R":
            case "Alt_L":
            case "Alt_R":
                if (!alt_currently_pressed || alt_pressed)
                    return false;

                alt_pressed = true;
                
                return on_alt_pressed();
            
            case "Shift_L":
            case "Shift_R":
                if (!shift_currently_pressed || shift_pressed)
                    return false;

                shift_pressed = true;
                
                return on_shift_pressed();
            
            case "Super_L":
            case "Super_R":
                if (!super_currently_pressed || super_pressed)
                    return false;
                
                super_pressed = true;
                
                return on_super_pressed();
        }
        
        return on_app_key_pressed(event, keyval, keycode, modifiers);
    }
    
    public bool notify_app_key_released(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        bool ctrl_currently_pressed, alt_currently_pressed, shift_currently_pressed,
            super_currently_pressed;
        get_modifiers(out ctrl_currently_pressed, out alt_currently_pressed,
            out shift_currently_pressed, out super_currently_pressed);

        switch (Gdk.keyval_name(keyval)) {
            case "Control_L":
            case "Control_R":
                if (ctrl_currently_pressed || !ctrl_pressed)
                    return false;

                ctrl_pressed = false;
                
                return on_ctrl_released();
            
            case "Meta_L":
            case "Meta_R":
            case "Alt_L":
            case "Alt_R":
                if (alt_currently_pressed || !alt_pressed)
                    return false;

                alt_pressed = false;
                
                return on_alt_released();
            
            case "Shift_L":
            case "Shift_R":
                if (shift_currently_pressed || !shift_pressed)
                    return false;

                shift_pressed = false;
                
                return on_shift_released();

            case "Super_L":
            case "Super_R":
                if (super_currently_pressed || !super_pressed)
                    return false;

                super_pressed = false;
                
                return on_super_released();
        }
        
        return on_app_key_released(event, keyval, keycode, modifiers);
    }

    public void notify_app_focus_in() {
        update_modifiers();
    }
    
    protected virtual void on_resize(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_resize_start(Gdk.Rectangle rect) {
    }

    protected virtual void on_resize_finished(Gdk.Rectangle rect) {
    }

    protected virtual bool on_configure(Gdk.Rectangle rect) {
        return false;
    }

    public bool notify_configure_event(int width, int height) {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = 0;
        rect.y = 0;
        rect.width = width;
        rect.height = height;
        
        // special case events, to report when a configure first starts (and appears to end)
        if (last_configure_ms == 0) {            
            if (last_position.width != rect.width || last_position.height != rect.height) {
                on_resize_start(rect);
                report_resize_finished = true;
            }

            // need to check more often then the timeout, otherwise it could be up to twice the
            // wait time before it's noticed
            Timeout.add(CONSIDER_CONFIGURE_HALTED_MSEC / 8, check_configure_halted);
        }
                
        if (last_position.width != rect.width || last_position.height != rect.height)
            on_resize(rect);
        
        last_position = rect;
        last_configure_ms = now_ms();

        return on_configure(rect);
    }

    private bool check_configure_halted() {
        if (is_destroyed)
            return false;

        if ((now_ms() - last_configure_ms) < CONSIDER_CONFIGURE_HALTED_MSEC)
            return true;
        
        Gtk.Allocation allocation;
        get_allocation(out allocation);
                
        if (report_resize_finished)
            on_resize_finished((Gdk.Rectangle) allocation);
        
        last_configure_ms = 0;
        report_move_finished = false;
        report_resize_finished = false;
        
        return false;
    }
    
    protected virtual bool on_motion(Gtk.EventControllerMotion event, double x, double y, Gdk.ModifierType mask) {
        check_cursor_hiding();

        return false;
    }
    
    protected virtual void on_leave_notify_event(Gtk.EventControllerMotion controller) {
        // Do nothing
    }

    private void on_motion_internal(Gtk.EventControllerMotion controller, double x, double y) {
        on_motion(controller, x, y, controller.get_current_event_state());
        // todo: stop propagation?
    }

    private bool on_mousewheel_internal(Gtk.EventControllerScroll event, double dx, double dy) {
        if (dy < 0) {
            return on_mousewheel_up(event);
        } else if (dy > 0) {
            return on_mousewheel_down(event);
        } else if (dx < 0) {
            return on_mousewheel_left(event);
        } else if (dx > 0) {
            return on_mousewheel_right(event);
        }
        return false;
    }
    
    protected virtual bool on_mousewheel_up(Gtk.EventControllerScroll event) {
        return false;
    }
    
    protected virtual bool on_mousewheel_down(Gtk.EventControllerScroll event) {
        return false;
    }
    
    protected virtual bool on_mousewheel_left(Gtk.EventControllerScroll event) {
        return false;
    }
    
    protected virtual bool on_mousewheel_right(Gtk.EventControllerScroll event) {
        return false;
    }
    
    protected virtual bool on_context_keypress() {
        return false;
    }
    
    protected virtual bool on_context_buttonpress(Gtk.EventController event, double x, double y) {
        return false;
    }
    

    protected virtual bool on_context_invoked() {
        return true;
    }

    protected bool popup_context_menu(Gtk.PopoverMenu? context_menu, double x, double y) {

        if (context_menu == null || !on_context_invoked())
            return false;

        context_menu.set_pointing_to ({(int)x, (int)y, 1, 1});
        context_menu.popup();

        return true;
    }

    public void set_cursor_hide_time(int hide_time) {
        cursor_hide_msec = hide_time;
    }

    public void start_cursor_hiding() {
        check_cursor_hiding();
    }

    public void stop_cursor_hiding() {
        if (last_timeout_id != 0) {
            Source.remove(last_timeout_id);
            last_timeout_id = 0;
        }
    }

    public void suspend_cursor_hiding() {
        cursor_hide_time_cached = cursor_hide_msec;

        if (last_timeout_id != 0) {
            Source.remove(last_timeout_id);
            last_timeout_id = 0;
        }

        cursor_hide_msec = 0;
    }

    public void restore_cursor_hiding() {
        cursor_hide_msec = cursor_hide_time_cached;
        check_cursor_hiding();
    }

    // Use this method to set the cursor for a page, NOT window.set_cursor(...)
    protected virtual void set_page_cursor(string? cursor_type) {
        last_cursor = cursor_type;

        if (!cursor_hidden && event_source != null) {
            event_source.set_cursor_from_name (cursor_type);
        }
    }

    private void check_cursor_hiding() {
        if (cursor_hidden) {
            cursor_hidden = false;
            set_page_cursor(last_cursor);
        }

        if (cursor_hide_msec != 0) {
            if (last_timeout_id != 0)
                Source.remove(last_timeout_id);
            last_timeout_id = Timeout.add(cursor_hide_msec, on_hide_cursor);
        }
    }

    private bool on_hide_cursor() {
        cursor_hidden = true;

        if (event_source != null) {
            event_source.set_cursor_from_name ("none");
        }

        // We remove the timeout so reset the id
        last_timeout_id = 0;

        return false;
    }

    protected void update_menu_item_label (string id,
                                         string new_label) {
        AppWindow.get_instance().update_menu_item_label (id, new_label);
    }

    protected GLib.MenuModel? find_extension_point (GLib.MenuModel model,
                                                    string extension_point) {
        var items = model.get_n_items ();
        GLib.MenuModel? section = null;

        for (int i = 0; i < items && section == null; i++) {
            string? name = null;
            model.get_item_attribute (i, "id", "s", out name);
            if (name == extension_point) {
                section = model.get_item_link (i, GLib.Menu.LINK_SECTION);
            } else {
                var subsection = model.get_item_link (i, GLib.Menu.LINK_SECTION);

                if (subsection == null)
                    continue;

                // Recurse into submenus
                var sub_items = subsection.get_n_items ();
                for (int j = 0; j < sub_items && section == null; j++) {
                    var submenu = subsection.get_item_link
                                                (j, GLib.Menu.LINK_SUBMENU);
                    if (submenu != null) {
                        section = this.find_extension_point (submenu,
                                                             extension_point);
                    }
                }
            }
        }

        return section;
    }

}

