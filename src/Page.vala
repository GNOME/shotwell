/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class PageLayout : Gtk.VBox {
    public Page page;
    
    public PageLayout(Page page) {
        this.page = page;
        
        set_homogeneous(false);
        set_spacing(0);
        
        pack_start(page, true, true, 0);
        if (page.get_toolbar() != null)
            pack_end(page.get_toolbar(), false, false, 0);
    }
}

public abstract class Page : Gtk.ScrolledWindow, SidebarPage {
    public const uint KEY_CTRL_L = Gdk.keyval_from_name("Control_L");
    public const uint KEY_CTRL_R = Gdk.keyval_from_name("Control_R");
    public const uint KEY_ALT_L = Gdk.keyval_from_name("Alt_L");
    public const uint KEY_ALT_R = Gdk.keyval_from_name("Alt_R");
    public const uint KEY_SHIFT_L = Gdk.keyval_from_name("Shift_L");
    public const uint KEY_SHIFT_R = Gdk.keyval_from_name("Shift_R");
    
    private const int CONSIDER_CONFIGURE_HALTED_MSEC = 400;

    protected enum TargetType {
        URI_LIST
    }
    
    // For now, assuming all drag-and-drop source functions are providing the same set of targets
    protected const Gtk.TargetEntry[] SOURCE_TARGET_ENTRIES = {
        { "text/uri-list", Gtk.TargetFlags.OTHER_APP, TargetType.URI_LIST }
    };
    
    public Gtk.UIManager ui = new Gtk.UIManager();
    public Gtk.ActionGroup action_group = null;
    public Gtk.ActionGroup common_action_group = null;
    
    private string page_name;
    private PageLayout layout = null;
    private Gtk.MenuBar menu_bar = null;
    private SidebarMarker marker = null;
    private Gdk.Rectangle last_position = Gdk.Rectangle();
    private Gtk.Widget event_source = null;
    private bool dnd_enabled = false;
    private bool in_view = false;
    private ulong last_configure_ms = 0;
    private bool report_move_finished = false;
    private bool report_resize_finished = false;
   
    public virtual signal void selection_changed(int count) {
    }
    
    public virtual signal void contents_changed(int count) {
    }
    
    public virtual signal void queryable_altered(Queryable queryable) {
    }

    public Page(string page_name) {
        this.page_name = page_name;
        
        set_flags(Gtk.WidgetFlags.CAN_FOCUS);
    }

    public string get_page_name() {
        return page_name;
    }
    
    public PageLayout get_layout() {
        // This only places the Page into a PageLayout if requested;
        // this is how a Page can live inside AppWindow's notebook or
        // on its own in another window with a separate layout.
        if (layout != null)
            return layout;
        
        assert(parent == null);
        layout = new PageLayout(this);
        
        return layout;
    }
    
    public void set_page_name(string page_name) {
        this.page_name = page_name;
    }
    
    public void set_event_source(Gtk.Widget event_source) {
        assert(this.event_source == null);

        this.event_source = event_source;
        event_source.set_flags(Gtk.WidgetFlags.CAN_FOCUS);

        // interested in mouse button and motion events on the event source
        event_source.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.POINTER_MOTION_HINT_MASK
            | Gdk.EventMask.BUTTON_MOTION_MASK);
        event_source.button_press_event += on_button_pressed_internal;
        event_source.button_release_event += on_button_released_internal;
        event_source.motion_notify_event += on_motion_internal;
    }
    
    public Gtk.Widget? get_event_source() {
        return event_source;
    }
    
    public string get_sidebar_text() {
        return page_name;
    }
    
    public void set_marker(SidebarMarker marker) {
        this.marker = marker;
    }
    
    public SidebarMarker? get_marker() {
        return marker;
    }
    
    public void clear_marker() {
        marker = null;
    }
    
    public virtual Gtk.MenuBar get_menubar() {
        return menu_bar;
    }

    public abstract Gtk.Toolbar get_toolbar();
    
    public virtual void switching_from() {
        in_view = false;
    }
    
    public virtual void switched_to() {
        in_view = true;
    }
    
    public bool is_in_view() {
        return in_view;
    }
    
    public virtual void switching_to_fullscreen() {
    }
    
    public virtual void returning_from_fullscreen() {
    }
    
    public void set_item_sensitive(string path, bool sensitive) {
        ui.get_widget(path).sensitive = sensitive;
    }
    
    protected void init_ui(string ui_filename, string? menubar_path, string action_group_name, 
        Gtk.ActionEntry[]? entries = null, Gtk.ToggleActionEntry[]? toggle_entries = null) {
        init_ui_start(ui_filename, action_group_name, entries, toggle_entries);
        init_ui_bind(menubar_path);
    }
    
    protected void init_load_ui(string ui_filename) {
        File ui_file = Resources.get_ui(ui_filename);

        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error gle) {
            error("Error loading UI file %s: %s", ui_file.get_path(), gle.message);
        }
    }
    
    protected void init_ui_start(string ui_filename, string action_group_name,
        Gtk.ActionEntry[]? entries = null, Gtk.ToggleActionEntry[]? toggle_entries = null) {
        init_load_ui(ui_filename);

        action_group = new Gtk.ActionGroup(action_group_name);
        if (entries != null)
            action_group.add_actions(entries, this);
        if (toggle_entries != null)
            action_group.add_toggle_actions(toggle_entries, this);
    }
    
    protected void init_ui_bind(string? menubar_path) {
        ui.insert_action_group(action_group, 0);
        
        common_action_group = new Gtk.ActionGroup("CommonActionGroup");
        AppWindow.get_instance().add_common_actions(common_action_group);
        ui.insert_action_group(common_action_group, 0);
        
        if (menubar_path != null)
            menu_bar = (Gtk.MenuBar) ui.get_widget(menubar_path);

        ui.ensure_update();
    }
    
    // This method enables drag-and-drop on the event source and routes its events through this
    // object
    public void enable_drag_source(Gdk.DragAction actions) {
        if (dnd_enabled)
            return;
            
        assert(event_source != null);
        
        Gtk.drag_source_set(event_source, Gdk.ModifierType.BUTTON1_MASK, SOURCE_TARGET_ENTRIES, actions);
        event_source.drag_begin += on_drag_begin;
        event_source.drag_data_get += on_drag_data_get;
        event_source.drag_data_delete += on_drag_data_delete;
        event_source.drag_end += on_drag_end;
        event_source.drag_failed += on_drag_failed;
        
        dnd_enabled = true;
    }
    
    public void disable_drag_source() {
        if (!dnd_enabled)
            return;

        assert(event_source != null);
        
        event_source.drag_begin -= on_drag_begin;
        event_source.drag_data_get -= on_drag_data_get;
        event_source.drag_data_delete -= on_drag_data_delete;
        event_source.drag_end -= on_drag_end;
        event_source.drag_failed -= on_drag_failed;
        Gtk.drag_source_unset(event_source);
        
        dnd_enabled = false;
    }
    
    public bool is_dnd_enabled() {
        return dnd_enabled;
    }
    
    private void on_drag_begin(Gdk.DragContext context) {
        drag_begin(context);
    }
    
    private void on_drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint info, uint time) {
        drag_data_get(context, selection_data, info, time);
    }
    
    private void on_drag_data_delete(Gdk.DragContext context) {
        drag_data_delete(context);
    }
    
    private void on_drag_end(Gdk.DragContext context) {
        drag_end(context);
    }
    
    // wierdly, Gtk 2.16.1 doesn't supply a drag_failed virtual method in the GtkWidget impl ...
    // Vala binds to it, but it's not available in gtkwidget.h, and so gcc complains.  Have to
    // makeshift one for now.
    public virtual bool source_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        return false;
    }
    
    private bool on_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        return source_drag_failed(context, drag_result);
    }
    
    protected virtual bool on_left_click(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_middle_click(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_right_click(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_left_released(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_middle_released(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_right_released(Gdk.EventButton event) {
        return false;
    }
    
    private bool on_button_pressed_internal(Gdk.EventButton event) {
        switch (event.button) {
            case 1:
                if (event_source != null)
                    event_source.grab_focus();
                
                return on_left_click(event);

            case 2:
                return on_middle_click(event);
            
            case 3:
                return on_right_click(event);
            
            default:
                return false;
        }
    }
    
    private bool on_button_released_internal(Gdk.EventButton event) {
        switch (event.button) {
            case 1:
                return on_left_released(event);
            
            case 2:
                return on_middle_released(event);
            
            case 3:
                return on_right_released(event);
            
            default:
                return false;
        }
    }

    protected virtual bool on_ctrl_pressed(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_ctrl_released(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_alt_pressed(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_alt_released(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_shift_pressed(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_shift_released(Gdk.EventKey event) {
        return false;
    }
    
    public bool notify_modifier_pressed(Gdk.EventKey event) {
        // can't use a switch statement here due to this bug:
        // http://bugzilla.gnome.org/show_bug.cgi?id=585292
        if (event.keyval == KEY_CTRL_L || event.keyval == KEY_CTRL_R)
            return on_ctrl_pressed(event);
        
        if (event.keyval == KEY_ALT_L || event.keyval == KEY_ALT_R)
            return on_alt_pressed(event);
        
        if (event.keyval == KEY_SHIFT_L || event.keyval == KEY_SHIFT_R)
            return on_shift_pressed(event);
        
        return false;
    }

    public bool notify_modifier_released(Gdk.EventKey event) {
        // can't use a switch statement here due to this bug:
        // http://bugzilla.gnome.org/show_bug.cgi?id=585292
        if (event.keyval == KEY_CTRL_L || event.keyval == KEY_CTRL_R)
            return on_ctrl_released(event);
        
        if (event.keyval == KEY_ALT_L || event.keyval == KEY_ALT_R)
            return on_alt_released(event);
        
        if (event.keyval == KEY_SHIFT_L || event.keyval == KEY_SHIFT_R)
            return on_shift_released(event);
        
        return false;
    }
    
    protected virtual void on_move(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_move_start(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_move_finished(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_resize(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_resize_start(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_resize_finished(Gdk.Rectangle rect) {
    }
    
    protected virtual bool on_configure(Gdk.EventConfigure event, Gdk.Rectangle rect) {
        return false;
    }
    
    public bool notify_configure_event(Gdk.EventConfigure event) {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = event.x;
        rect.y = event.y;
        rect.width = event.width;
        rect.height = event.height;
        
        if (last_position.x != rect.x || last_position.y != rect.y)
            on_move(rect);
        
        if (last_position.width != rect.width || last_position.height != rect.height)
            on_resize(rect);
        
        // special case events, to report when a configure first starts (and appears to end)
        if (last_configure_ms == 0) {
            if (last_position.x != rect.x || last_position.y != rect.y) {
                on_move_start(rect);
                report_move_finished = true;
            }
            
            if (last_position.width != rect.width || last_position.height != rect.height) {
                on_resize_start(rect);
                report_resize_finished = true;
            }

            // need to check more often then the timeout, otherwise it could be up to twice the
            // wait time before it's noticed
            Timeout.add(CONSIDER_CONFIGURE_HALTED_MSEC / 8, check_configure_halted);
        }

        last_position = rect;
        last_configure_ms = now_ms();

        return on_configure(event, rect);
    }
    
    private bool check_configure_halted() {
        if ((now_ms() - last_configure_ms) < CONSIDER_CONFIGURE_HALTED_MSEC)
            return true;
            
        if (report_move_finished)
            on_move_finished((Gdk.Rectangle) allocation);
        
        if (report_resize_finished)
            on_resize_finished((Gdk.Rectangle) allocation);
        
        last_configure_ms = 0;
        report_move_finished = false;
        report_resize_finished = false;
        
        return false;
    }
    
    protected virtual bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        return false;
    }
    
    private bool on_motion_internal(Gdk.EventMotion event) {
        int x, y;
        Gdk.ModifierType mask;
        if (event.is_hint) {
            event_source.window.get_pointer(out x, out y, out mask);
        } else {
            x = (int) event.x;
            y = (int) event.y;
            mask = event.state;
        }
        
        return on_motion(event, x, y, mask);
    }

    public abstract int get_queryable_count();

    public abstract Gee.Iterable<Queryable>? get_queryables();

    public abstract int get_selected_queryable_count();

    public abstract Gee.Iterable<Queryable>? get_selected_queryables();

    public virtual Gtk.Menu? get_page_context_menu() {
        return null;
    }
}

public abstract class CheckerboardPage : Page {
    private const int AUTOSCROLL_PIXELS = 50;
    private const int AUTOSCROLL_TICKS_MSEC = 50;
    
    private Gtk.Menu item_context_menu = null;
    private Gtk.Menu page_context_menu = null;
    private CollectionLayout layout = new CollectionLayout();
    private Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    private Gee.HashSet<LayoutItem> selected_items = new Gee.HashSet<LayoutItem>();
    private LayoutItem last_clicked_item = null;
    private LayoutItem highlighted = null;

    // for drag selection
    private bool drag_select = false;
    private bool autoscroll_scheduled = false;

    public CheckerboardPage(string page_name) {
        base(page_name);
        
        set_event_source(layout);

        set_border_width(0);
        set_shadow_type(Gtk.ShadowType.NONE);
        
        viewport.set_border_width(0);
        viewport.set_shadow_type(Gtk.ShadowType.NONE);
        
        viewport.add(layout);
        
        // want to set_adjustments before adding to ScrolledWindow to let our signal handlers
        // run first ... otherwise, the thumbnails draw late
        layout.set_adjustments(get_hadjustment(), get_vadjustment());

        add(viewport);
    }
    
    public void init_item_context_menu(string path) {
        item_context_menu = (Gtk.Menu) ui.get_widget(path);
    }

    public void init_page_context_menu(string path) {
        page_context_menu = (Gtk.Menu) ui.get_widget(path);
    }
   
    public Gtk.Menu? get_context_menu() {
        // show page context menu if nothing is selected
        return (get_selected_count() != 0) ? item_context_menu : page_context_menu;
    }

    public override Gtk.Menu? get_page_context_menu() {
        return page_context_menu;
    }
    
    protected virtual void on_item_activated(LayoutItem item) {
    }
    
    protected virtual bool on_context_invoked(Gtk.Menu context_menu) {
        return true;
    }
    
    public override void switching_from() {
        layout.set_in_view(false);
        
        base.switching_from();
    }
    
    public override void switched_to() {
        layout.set_in_view(true);
        
        base.switched_to();
    }
    
    public abstract LayoutItem? get_fullscreen_photo();
    
    public void refresh() {
        layout.refresh();
        layout.queue_draw();
    }
    
    public void set_page_message(string message) {
        layout.set_message(message);
    }
    
    public void set_layout_comparator(Comparator<LayoutItem> cmp) {
        layout.set_comparator(cmp);
    }
    
    public LayoutItem? get_item_at_pixel(double x, double y) {
        return layout.get_item_at_pixel(x, y);
    }
    
    public Gee.Iterable<LayoutItem> get_items() {
        return layout.items;
    }
   
    public Gee.Iterable<LayoutItem> get_selected() {
        return selected_items;
    }

    public override int get_queryable_count() {
        return get_count();
    }

    public override Gee.Iterable<Queryable>? get_queryables() {
        return get_items();
    }

    public override int get_selected_queryable_count() {
        return get_selected_count();
    }

    public override Gee.Iterable<Queryable>? get_selected_queryables() {
        return get_selected();
    }    

    public void add_item(LayoutItem item) {
        layout.add_item(item);
        contents_changed(layout.items.size);
    }
    
    public void remove_item(LayoutItem item) {
        int count = layout.items.size;
        int selected_count = selected_items.size;

        selected_items.remove(item);
        layout.remove_item(item);
        
        if (count != layout.items.size)
            contents_changed(layout.items.size);

        if (selected_count != selected_items.size) {
            selection_changed(selected_items.size);
        }
    }
    
    public int remove_selected() {
        int count = layout.items.size;
        int selected_count = selected_items.size;
        
        foreach (LayoutItem item in selected_items)
            layout.remove_item(item);
        
        selected_items.clear();
        
        if (count != layout.items.size)
            contents_changed(layout.items.size);

        if (selected_count != selected_items.size) {
            selection_changed(selected_items.size);
        }
        
        return selected_count;
    }
    
    public int remove_all() {
        int count = layout.items.size;
        int selection_count = selected_items.size;
        
        layout.clear();
        selected_items.clear();
        
        if (count != layout.items.size)
            contents_changed(layout.items.size);
        
        if (selection_count != selected_items.size) {
            selection_changed(selected_items.size);
        }

        return count;
    }
    
    public int get_count() {
        return layout.items.size;
    }
    
    public void select_all() {
        bool changed = false;
        foreach (LayoutItem item in layout.items) {
            if (!item.is_selected()) {
                selected_items.add(item);
                item.select();
                changed = true;
            }
        }
        
        if (changed)
            selection_changed(selected_items.size);
    }

    public void unselect_all() {
        if (selected_items.size == 0)
            return;

        foreach (LayoutItem item in selected_items) {
            assert(item.is_selected());
            item.unselect();
        }
        
        selected_items.clear();
        
        selection_changed(0);
    }
    
    public void unselect_all_but(LayoutItem exception) {
        assert(exception.is_selected());
        
        if (selected_items.size == 0)
            return;
        
        bool changed = false;
        foreach (LayoutItem item in selected_items) {
            assert(item.is_selected());
            if (item != exception) {
                item.unselect();
                changed = true;
            }
        }
        
        selected_items.clear();
        selected_items.add(exception);

        if (changed)
            selection_changed(1);
    }

    public void select(LayoutItem item) {
        assert(layout.items.contains(item));
        
        if (!item.is_selected()) {
            item.select();
            selected_items.add(item);

            selection_changed(selected_items.size);
        }
    }
    
    public void unselect(LayoutItem item) {
        assert(layout.items.contains(item));
        
        if (item.is_selected()) {
            item.unselect();
            selected_items.remove(item);
            
            selection_changed(selected_items.size);
        }
    }

    public void toggle_select(LayoutItem item) {
        if (item.toggle_select()) {
            // now selected
            selected_items.add(item);
        } else {
            // now unselected
            selected_items.remove(item);
        }
        
        selection_changed(selected_items.size);
    }
    
    public int get_selected_count() {
        return selected_items.size;
    }

    protected override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "Up":
            case "KP_Up":
                move_cursor(CompassPoint.NORTH);
            break;
            
            case "Down":
            case "KP_Down":
                move_cursor(CompassPoint.SOUTH);
            break;
            
            case "Left":
            case "KP_Left":
                move_cursor(CompassPoint.WEST);
            break;
            
            case "Right":
            case "KP_Right":
                move_cursor(CompassPoint.EAST);
            break;
            
            case "Home":
            case "KP_Home":
                LayoutItem first = get_first_item();
                if (first != null)
                    cursor_to_item(first);
            break;
            
            case "End":
            case "KP_End":
                LayoutItem last = get_last_item();
                if (last != null)
                    cursor_to_item(last);
            break;
            
            case "Return":
            case "KP_Enter":
                if (get_selected_count() == 1) {
                    foreach (LayoutItem item in get_selected()) {
                        on_item_activated(item);
                        
                        break;
                    }
                } else {
                    handled = false;
                }
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled)
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : true;
    }
    
    protected override bool on_left_click(Gdk.EventButton event) {
        // only interested in single-click and double-clicks for now
        if ((event.type != Gdk.EventType.BUTTON_PRESS) && (event.type != Gdk.EventType.2BUTTON_PRESS))
            return false;
        
        // mask out the modifiers we're interested in
        uint state = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
        
        // use clicks for multiple selection and activation only; single selects are handled by
        // button release, to allow for multiple items to be selected then dragged
        LayoutItem item = get_item_at_pixel(event.x, event.y);
        if (item != null) {
            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    toggle_select(item);
                break;
                
                case Gdk.ModifierType.SHIFT_MASK:
                    Box selected_box;
                    if (!get_selected_box(out selected_box))
                        break;
                    
                    Gdk.Point point = Gdk.Point();
                    point.x = item.get_column();
                    point.y = item.get_row();
                    
                    Box new_selected_box = selected_box.rubber_band(point);
                    
                    select_all_in_box(new_selected_box);
                break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                default:
                    if (event.type == Gdk.EventType.2BUTTON_PRESS)
                        on_item_activated(item);
                    else {
                        // if user has selected multiple items and is preparing for a drag, don't
                        // want to unselect immediately, otherwise, let the released handler deal
                        // with it
                        if (get_selected_count() == 1)
                            unselect_all();
                        select(item);
                    }
                break;
            }
        } else {
            // user clicked on "dead" area
            unselect_all();
        }
        
        last_clicked_item = item;

        // need to determine if the signal should be passed to the DnD handlers
        // Return true to block the DnD handler, false otherwise

        if (item == null) {
            drag_select = true;
            layout.set_drag_select_origin((int) event.x, (int) event.y);

            return true;
        }

        return selected_items.size == 0;
    }
    
    protected override bool on_left_released(Gdk.EventButton event) {
        // if drag-selecting, stop here and do nothing else
        if (drag_select) {
            drag_select = false;
            layout.clear_drag_select();

            return true;
        }
        
        // only interested in non-modified button releases
        if ((event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) != 0)
            return false;
            
        LayoutItem item = get_item_at_pixel(event.x, event.y);
        if (item == null) {
            // released button on "dead" area
            return true;
        }
        
        if (last_clicked_item != item) {
            // user released mouse button after moving it off the initial item, or moved from dead
            // space onto one.  either way, unselect everything
            unselect_all();
        } else {
            // the idea is, if a user single-clicks on an item with no modifiers, then all other items
            // should be deselected, however, if they single-click in order to drag one or more items,
            // they should remain selected, hence performing this here rather than on_left_click
            // (item may not be selected if an unimplemented modifier key was used)
            if (item.is_selected())
                unselect_all_but(item);
        }

        return true;
    }
    
    protected override bool on_right_click(Gdk.EventButton event) {
        // only interested in single-clicks for now
        if (event.type != Gdk.EventType.BUTTON_PRESS)
            return false;
        
        // get what's right-clicked upon
        LayoutItem item = get_item_at_pixel(event.x, event.y);
        if (item != null) {
            // mask out the modifiers we're interested in
            switch (event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // chosen item is toggled
                    toggle_select(item);
                break;
                
                case Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                default:
                    // if the item is already selected, proceed; if item is not selected, a bare right
                    // click unselects everything else but it
                    if (!item.is_selected()) {
                        unselect_all();
                        select(item);
                    }
                break;
            }
        } else {
            // clicked in "dead" space, unselect everything
            unselect_all();
        }
       
        Gtk.Menu context_menu = get_context_menu();
        if (context_menu == null)
            return false;

        if (!on_context_invoked(context_menu))
            return false;

        context_menu.popup(null, null, null, event.button, event.time);

        return true;
    }
    
    protected virtual bool on_mouse_over(LayoutItem? item, int x, int y, Gdk.ModifierType mask) {
        // if hovering over the last hovered item, or both are null (nothing highlighted and
        // hovering over empty space), do nothing
        if (item == highlighted)
            return true;
        
        // either something new is highlighted or now hovering over empty space, so dim old item
        if (highlighted != null) {
            highlighted.unbrighten();
            highlighted = null;
        }
        
        // if over empty space, done
        if (item == null)
            return true;
        
        // brighten the new item
        item.brighten();
        highlighted = item;
        
        return true;
    }
    
    protected override bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        // report what item the mouse is hovering over
        if (!on_mouse_over(get_item_at_pixel(x, y), x, y, mask))
            return false;
        
        // go no further if not drag-selecting
        if (!drag_select)
            return false;
        
        // set the new endpoint of the drag selection
        layout.set_drag_select_endpoint(x, y);
        
        updated_selection_band();

        // if out of bounds, schedule a check to auto-scroll the viewport
        if (!autoscroll_scheduled 
            && get_adjustment_relation(get_vadjustment(), y) != AdjustmentRelation.IN_RANGE) {
            Timeout.add(AUTOSCROLL_TICKS_MSEC, selection_autoscroll);
            autoscroll_scheduled = true;
        }

        return true;
    }
    
    private void updated_selection_band() {
        assert(drag_select);
        
        // get all items inside the selection
        Gee.List<LayoutItem>? intersection = layout.items_in_selection_band();
        if (intersection == null)
            return;

        // deselect everything not in the intersection ... needs to be done outside the iterator
        Gee.ArrayList<LayoutItem> outside = new Gee.ArrayList<LayoutItem>();
        foreach (LayoutItem item in selected_items) {
            if (!intersection.contains(item))
                outside.add(item);
        }
        
        foreach (LayoutItem item in outside)
            unselect(item);
        
        // select everything in the intersection
        foreach (LayoutItem item in intersection)
            select(item);
    }
    
    private bool selection_autoscroll() {
        if (!drag_select) { 
            autoscroll_scheduled = false;
            
            return false;
        }
        
        // as the viewport never scrolls horizontally, only interested in vertical
        Gtk.Adjustment vadj = get_vadjustment();

        int x, y;
        Gdk.ModifierType mask;
        layout.window.get_pointer(out x, out y, out mask);
        
        int new_value = (int) vadj.get_value();
        switch (get_adjustment_relation(vadj, y)) {
            case AdjustmentRelation.BELOW:
                // pointer above window, scroll up
                new_value -= AUTOSCROLL_PIXELS;
                layout.set_drag_select_endpoint(x, new_value);
            break;
            
            case AdjustmentRelation.ABOVE:
                // pointer below window, scroll down, extend selection to bottom of page
                new_value += AUTOSCROLL_PIXELS;
                layout.set_drag_select_endpoint(x, new_value + (int) vadj.get_page_size());
            break;
            
            case AdjustmentRelation.IN_RANGE:
                autoscroll_scheduled = false;
                
                return false;
            
            default:
                warn_if_reached();
            break;
        }
        
        vadj.set_value(new_value);
        
        updated_selection_band();
        
        return true;
    }
    
    public LayoutItem? get_first_item() {
        return (layout.items.size != 0) ? layout.items.get(0) : null;
    }
    
    public LayoutItem? get_last_item() {
        return (layout.items.size != 0) ? layout.items.get(layout.items.size - 1) : null;
    }
    
    public LayoutItem? get_next_item(LayoutItem current) {
        if (layout.items.size == 0)
            return null;
        
        int index = layout.items.locate(current);

        // although items may be added while the page is away, not handling situations where an active
        // item is removed
        assert(index >= 0);

        index++;
        if (index >= layout.items.size)
            index = 0;
        
        return layout.items.get(index);
    }
    
    public LayoutItem? get_previous_item(LayoutItem current) {
        if (layout.items.size == 0)
            return null;
        
        int index = layout.items.locate(current);
        
        // although items may be added while the page is away, not handling situations where an active
        // item is removed
        assert(index >= 0);

        index--;
        if (index < 0)
            index = (layout.items.size - 1);
        
        return layout.items.get(index);
    }
    
    public void cursor_to_item(LayoutItem item) {
        assert(layout.items.contains(item));
        
        unselect_all();
        select(item);

        // if item is in any way out of view, scroll to it
        Gtk.Adjustment vadj = get_vadjustment();
        if (get_adjustment_relation(vadj, item.allocation.y) == AdjustmentRelation.IN_RANGE
            && (get_adjustment_relation(vadj, item.allocation.y + item.allocation.height) == AdjustmentRelation.IN_RANGE))
            return;

        // scroll to see the new item
        int top = 0;
        if (item.allocation.y < vadj.get_value()) {
            top = item.allocation.y;
            top -= CollectionLayout.ROW_GUTTER_PADDING / 2;
        } else {
            top = item.allocation.y + item.allocation.height - (int) vadj.get_page_size();
            top += CollectionLayout.ROW_GUTTER_PADDING / 2;
        }
        
        vadj.set_value(top);
    }
    
    public void move_cursor(CompassPoint point) {
        // if nothing is selected, simply select the first and exit
        if (selected_items.size == 0) {
            cursor_to_item(layout.items.get(0));
            
            return;
        }
        
        // find the "first" selected item, which for now is the topmost, leftmost item in the layout
        // TODO: Revisit if this is the right choice.
        int first_col = int.MAX;
        int first_row = int.MAX;
        foreach (LayoutItem selected in selected_items) {
            first_col = int.min(selected.get_column(), first_col);
            first_row = int.min(selected.get_row(), first_row);
        }
        
        LayoutItem item = layout.get_item_at_coordinate(first_col, first_row);
        assert(item != null);
        
        // if more than one selected, select the first without moving, to not surprise the user
        if (selected_items.size > 1) {
            cursor_to_item(item);
            
            return;
        }
        
        item = layout.get_item_relative_to(item, point);
        if (item != null)
            cursor_to_item(item);
   }
   
    public bool get_selected_box(out Box selected_box) {
        if (selected_items.size == 0)
            return false;
            
        int left = int.MAX;
        int top = int.MAX;
        int right = int.MIN;
        int bottom = int.MIN;
        foreach (LayoutItem selected in selected_items) {
            left = int.min(selected.get_column(), left);
            top = int.min(selected.get_row(), top);
            right = int.max(selected.get_column(), right);
            bottom = int.max(selected.get_row(), bottom);
        }
        
        selected_box = Box(left, top, right, bottom);
        
        return true;
    }
   
    public void select_all_in_box(Box box) {
        Gdk.Point point = Gdk.Point();
        foreach (LayoutItem item in layout.items) {
            point.x = item.get_column();
            point.y = item.get_row();
            if (box.contains(point))
                select(item);
        }
    }
}

public abstract class SinglePhotoPage : Page {
    public const Gdk.InterpType FAST_INTERP = Gdk.InterpType.NEAREST;
    public const Gdk.InterpType QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    public enum UpdateReason {
        NEW_PIXBUF,
        QUALITY_IMPROVEMENT,
        RESIZED_CANVAS
    }
    
    protected Gdk.GC canvas_gc = null;
    protected Gtk.DrawingArea canvas = new Gtk.DrawingArea();
    protected Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    
    private Gdk.Pixmap pixmap = null;
    private Dimensions pixmap_dim = Dimensions();
    private Gdk.Pixbuf unscaled = null;
    private Gdk.Pixbuf scaled = null;
    private Gdk.Rectangle scaled_pos = Gdk.Rectangle();
    private Gdk.InterpType default_interp = FAST_INTERP;
    private Gdk.InterpType interp = FAST_INTERP;
    private SinglePhotoPage improval_scheduled = null;
    private bool reschedule_improval = false;
    
    public SinglePhotoPage(string page_name) {
        base(page_name);
        
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        viewport.set_shadow_type(Gtk.ShadowType.NONE);
        viewport.set_border_width(0);
        viewport.add(canvas);
        
        add(viewport);
        
        // turn off double-buffering because all painting happens in pixmap, and is sent to the window
        // wholesale in on_canvas_expose
        canvas.set_double_buffered(false);
        canvas.add_events(Gdk.EventMask.EXPOSURE_MASK | Gdk.EventMask.STRUCTURE_MASK 
            | Gdk.EventMask.SUBSTRUCTURE_MASK);
        
        viewport.size_allocate += on_viewport_resize;
        canvas.expose_event += on_canvas_exposed;
        
        set_event_source(canvas);
    }
    
    public Gdk.InterpType set_default_interp(Gdk.InterpType default_interp) {
        Gdk.InterpType old = this.default_interp;
        this.default_interp = default_interp;
        
        return old;
    }
    
    public void set_pixbuf(Gdk.Pixbuf unscaled, bool use_improvement = true) {
        this.unscaled = unscaled;
        scaled = null;
        
        // need to make sure this has happened
        canvas.realize();
        
        repaint(use_improvement ? default_interp : QUALITY_INTERP);
    }
    
    public Gdk.Drawable? get_drawable() {
        return pixmap;
    }
    
    public Dimensions get_drawable_dim() {
        return pixmap_dim;
    }
    
    public Scaling get_canvas_scaling() {
        return Scaling.for_widget(viewport);
    }

    public Gdk.Pixbuf? get_unscaled_pixbuf() {
        return unscaled;
    }
    
    public Gdk.Pixbuf? get_scaled_pixbuf() {
        return scaled;
    }
    
    // Returns a rectangle describing the pixbuf in relation to the canvas
    public Gdk.Rectangle get_scaled_pixbuf_position() {
        return scaled_pos;
    }
    
    public bool is_inside_pixbuf(int x, int y) {
        return coord_in_rectangle(x, y, scaled_pos);
    }
    
    public void invalidate(Gdk.Rectangle rect) {
        if (canvas.window != null)
            canvas.window.invalidate_rect(rect, false);
    }
    
    public void invalidate_all() {
        if (canvas.window != null)
            canvas.window.invalidate_rect(null, false);
    }
    
    private void on_viewport_resize() {
        repaint(default_interp);
    }
    
    private bool on_canvas_exposed(Gdk.EventExpose event) {
        // to avoid multiple exposes
        if (event.count > 0)
            return false;
        
        // draw pixmap onto canvas unless it's not been instantiated, in which case draw black
        // (so either old image or contents of another page is not left on screen)
        if (pixmap != null) {
            canvas.window.draw_drawable(canvas_gc, pixmap, event.area.x, event.area.y, event.area.x, 
                event.area.y, event.area.width, event.area.height);
        } else {
            canvas.window.draw_rectangle(canvas.style.black_gc, true, event.area.x, event.area.y,
                event.area.width, event.area.height);
        }

        return true;
    }
    
    protected virtual void new_drawable(Gdk.GC default_gc, Gdk.Drawable drawable) {
    }
    
    protected virtual void updated_pixbuf(Gdk.Pixbuf pixbuf, UpdateReason reason, Dimensions old_dim) {
    }
    
    protected virtual void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        drawable.draw_pixbuf(gc, scaled, 0, 0, scaled_pos.x, scaled_pos.y, -1, -1, 
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    public void default_repaint() {
        repaint(default_interp);
    }
    
    public void repaint(Gdk.InterpType repaint_interp) {
        // no image or window, no painting
        if (unscaled == null || canvas.window == null)
            return;
        
        int width = viewport.allocation.width;
        int height = viewport.allocation.height;
        
        if (width <= 0 || height <= 0)
            return;
            
        bool new_pixbuf = (scaled == null);
        
        // save if reporting an image being rescaled
        Dimensions old_scaled_dim = Dimensions.for_rectangle(scaled_pos);

        // attempt to reuse pixmap
        if (pixmap_dim.width != width || pixmap_dim.height != height)
            pixmap = null;
        
        // if necessary, create a pixmap as large as the entire viewport
        bool new_pixmap = false;
        if (pixmap == null) {
            init_pixmap(width, height);
            new_pixmap = true;
        } else if (repaint_interp == FAST_INTERP && interp == QUALITY_INTERP) {
            // block calls where the pixmap is not being regenerated and the caller is asking for
            // a lower interp
            repaint_interp = QUALITY_INTERP;
        }
        
        if (new_pixbuf || new_pixmap) {
            // determine size of pixbuf that will fit on the canvas
            Dimensions scaled_dim = Dimensions.for_pixbuf(unscaled).get_scaled_proportional(pixmap_dim);
            
            assert(width >= scaled_dim.width);
            assert(height >= scaled_dim.height);

            // center pixbuf on the canvas
            scaled_pos.x = (width - scaled_dim.width) / 2;
            scaled_pos.y = (height - scaled_dim.height) / 2;
            scaled_pos.width = scaled_dim.width;
            scaled_pos.height = scaled_dim.height;

            // draw background
            pixmap.draw_rectangle(canvas.style.black_gc, true, 0, 0, width, height);
        }
        
        // rescale if canvas rescaled or better quality is requested
        if (scaled == null || interp != repaint_interp) {
            scaled = resize_pixbuf(unscaled, Dimensions.for_rectangle(scaled_pos), repaint_interp);
            
            UpdateReason reason = UpdateReason.RESIZED_CANVAS;
            if (new_pixbuf) 
                reason = UpdateReason.NEW_PIXBUF;
            else if (interp == FAST_INTERP && repaint_interp == QUALITY_INTERP)
                reason = UpdateReason.QUALITY_IMPROVEMENT;
            
            interp = repaint_interp;

            updated_pixbuf(scaled, reason, old_scaled_dim);
        }
        
        paint(canvas_gc, pixmap);

        // invalidate everything
        invalidate_all();
        
        // schedule improvement if low-quality pixbuf was used
        if (interp != QUALITY_INTERP)
            schedule_improval();
    }
    
    private void init_pixmap(int width, int height) {
        assert(unscaled != null);
        assert(canvas.window != null);
        
        pixmap = new Gdk.Pixmap(canvas.window, width, height, -1);
        pixmap_dim = Dimensions(width, height);
        
        // need a new pixbuf to fit this scale
        scaled = null;

        // GC for drawing on the pixmap
        canvas_gc = canvas.style.fg_gc[(int) Gtk.StateType.NORMAL];

        // resize canvas for the pixmap (that is, the entire viewport)
        canvas.set_size_request(width, height);

        new_drawable(canvas_gc, pixmap);
    }

    private void schedule_improval() {
        if (improval_scheduled != null) {
            reschedule_improval = true;
            
            return;
        }
        
        Idle.add(image_improval);
        
        // because Idle doesn't maintain a ref to this, need to maintain one ourself
        // (in case the page is destroyed between schedules)
        improval_scheduled = this;
    }
    
    private bool image_improval() {
        if (reschedule_improval) {
            reschedule_improval = false;
            
            return true;
        }
        
        repaint(QUALITY_INTERP);
        
        // do not touch self after clearing this
        improval_scheduled = null;
        
        return false;
    }
}

