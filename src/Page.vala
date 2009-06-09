
public class PageMarker {
    public Gtk.Widget notebook_page;
    private Gtk.TreeRowReference row = null;
    
    public PageMarker(Gtk.Widget notebook_page, Gtk.TreeModel? model = null, Gtk.TreePath? path = null ) {
        this.notebook_page = notebook_page;
        if ((model != null) && (path != null))
            this.row = new Gtk.TreeRowReference(model, path);
    }
    
    public unowned Gtk.TreeRowReference get_row() {
        return row;
    }
}

public abstract class Page : Gtk.ScrolledWindow {
    public static const uint KEY_CTRL_L = Gdk.keyval_from_name("Control_L");
    public static const uint KEY_CTRL_R = Gdk.keyval_from_name("Control_R");
    public static const uint KEY_ALT_L = Gdk.keyval_from_name("Alt_L");
    public static const uint KEY_ALT_R = Gdk.keyval_from_name("Alt_R");
    public static const uint KEY_SHIFT_L = Gdk.keyval_from_name("Shift_L");
    public static const uint KEY_SHIFT_R = Gdk.keyval_from_name("Shift_R");

    protected enum TargetType {
        URI_LIST
    }
    
    // For now, assuming all drag-and-drop source functions are providing the same set of targets
    protected const Gtk.TargetEntry[] SOURCE_TARGET_ENTRIES = {
        { "text/uri-list", Gtk.TargetFlags.OTHER_APP, TargetType.URI_LIST }
    };
    
    public Gtk.UIManager ui = new Gtk.UIManager();
    public Gtk.ActionGroup action_group = null;
    
    private Gtk.MenuBar menu_bar = null;
    private PageMarker marker = null;
    private Gdk.Rectangle last_position = Gdk.Rectangle();
    private Gtk.Widget event_source = null;
    private bool dnd_enabled = false;

    public Page() {
        set_flags(Gtk.WidgetFlags.CAN_FOCUS);
    }

    public void set_event_source(Gtk.Widget event_source) {
        assert(this.event_source == null);

        this.event_source = event_source;

        // interested in mouse button actions on the event source
        event_source.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK);
        event_source.button_press_event += on_button_pressed_internal;
        event_source.button_release_event += on_button_released_internal;
        
        // Use the app window's signals for window move/resize, esp. for resize, as this signal
        // is used to determine inner window resizes
        AppWindow.get_instance().add_events(Gdk.EventMask.STRUCTURE_MASK);
        AppWindow.get_instance().configure_event += on_configure_internal;
    }
    
    public Gtk.Widget? get_event_source() {
        return event_source;
    }
    
    public void set_marker(PageMarker marker) {
        this.marker = marker;
    }
    
    public PageMarker get_marker() {
        return marker;
    }
    
    public virtual Gtk.MenuBar get_menubar() {
        return menu_bar;
    }

    public abstract Gtk.Toolbar get_toolbar();
    
    public virtual void switching_from() {
    }
    
    public virtual void switched_to() {
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
        ui.insert_action_group(AppWindow.get_instance().get_common_action_group(), 0);
        
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
    
    protected virtual void on_resize(Gdk.Rectangle rect) {
    }
    
    private bool on_configure_internal(Gdk.EventConfigure event) {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = event.x;
        rect.y = event.y;
        rect.width = event.width;
        rect.height = event.height;
        
        if (last_position.x != rect.x || last_position.y != rect.y)
            on_move(rect);
        
        if (last_position.width != rect.width || last_position.height != rect.height)
            on_resize(rect);
        
        last_position = rect;
        
        return false;
    }
}

public abstract class CheckerboardPage : Page {
    private Gtk.Menu context_menu = null;
    private CollectionLayout layout = new CollectionLayout();
    private Gee.HashSet<LayoutItem> selected_items = new Gee.HashSet<LayoutItem>();
    private string page_name = null;
    private LayoutItem last_clicked_item = null;

    public CheckerboardPage(string page_name) {
        this.page_name = page_name;
        
        set_event_source(layout);

        add(layout);
    }
    
    public virtual string get_name() {
        return page_name;
    }
    
    public void init_context_menu(string path) {
        context_menu = (Gtk.Menu) ui.get_widget(path);
    }
    
    protected virtual void on_selection_changed(int count) {
    }
    
    public virtual Gtk.Menu? get_context_menu(LayoutItem? item) {
        return (item != null) ? context_menu : null;
    }
    
    protected virtual void on_item_activated(LayoutItem item) {
    }
    
    protected virtual bool on_context_invoked(Gtk.Menu context_menu) {
        return true;
    }
    
    public abstract LayoutItem? get_fullscreen_photo();
    
    public void refresh() {
        show_all();
        layout.refresh();
    }
    
    public void set_page_message(string message) {
        layout.set_message(message);
    }
    
    public void set_refresh_on_resize(bool refresh_on_resize) {
        layout.set_refresh_on_resize(refresh_on_resize);
    }
    
    public void set_layout_comparator(Comparator<LayoutItem> cmp) {
        layout.set_comparator(cmp);
    }
    
    public LayoutItem? get_item_at(double x, double y) {
        return layout.get_item_at(x, y);
    }
    
    public Gee.Iterable<LayoutItem> get_items() {
        return layout.items;
    }
    
    public Gee.Iterable<LayoutItem> get_selected() {
        return selected_items;
    }
    
    public void add_item(LayoutItem item) {
        layout.add_item(item);
    }
    
    public void remove_item(LayoutItem item) {
        selected_items.remove(item);
        layout.remove_item(item);
    }
    
    public int remove_selected() {
        int count = selected_items.size;
        
        foreach (LayoutItem item in selected_items)
            layout.remove_item(item);
        
        selected_items.clear();
        
        return count;
    }
    
    public int remove_all() {
        int count = layout.items.size;
        
        layout.clear();
        selected_items.clear();
        
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
            on_selection_changed(selected_items.size);
    }

    public void unselect_all() {
        if (selected_items.size == 0)
            return;

        foreach (LayoutItem item in selected_items) {
            assert(item.is_selected());
            item.unselect();
        }
        
        selected_items.clear();
        
        on_selection_changed(0);
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
            on_selection_changed(1);
    }

    public void select(LayoutItem item) {
        assert(layout.items.index_of(item) >= 0);
        
        if (!item.is_selected()) {
            item.select();
            selected_items.add(item);

            on_selection_changed(selected_items.size);
        }
    }
    
    public void unselect(LayoutItem item) {
        assert(layout.items.index_of(item) >= 0);
        
        if (item.is_selected()) {
            item.unselect();
            selected_items.remove(item);
            
            on_selection_changed(selected_items.size);
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
        
        on_selection_changed(selected_items.size);
    }

    public int get_selected_count() {
        return selected_items.size;
    }
    
    private override bool on_left_click(Gdk.EventButton event) {
        // only interested in single-click and double-clicks for now
        if ((event.type != Gdk.EventType.BUTTON_PRESS) && (event.type != Gdk.EventType.2BUTTON_PRESS))
            return false;
        
        // mask out the modifiers we're interested in
        uint state = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
        
        // use clicks for multiple selection and activation only; single selects are handled by
        // button release, to allow for multiple items to be selected then dragged
        LayoutItem item = get_item_at(event.x, event.y);
        if (item != null) {
            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    toggle_select(item);
                break;
                
                case Gdk.ModifierType.SHIFT_MASK:
                    // TODO
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
        if (!is_dnd_enabled())
            return false;

        return selected_items.size == 0;
    }
    
    private override bool on_left_released(Gdk.EventButton event) {
        // only interested in non-modified button releases
        if ((event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) != 0)
            return false;
            
        LayoutItem item = get_item_at(event.x, event.y);
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
    
    private override bool on_right_click(Gdk.EventButton event) {
        // only interested in single-clicks for now
        if (event.type != Gdk.EventType.BUTTON_PRESS)
            return false;
        
        LayoutItem item = get_item_at(event.x, event.y);
        if (item != null) {
            // TODO: Enable context menus for multiple and single selections
            unselect_all();
            select(item);
        }
            
        Gtk.Menu context_menu = get_context_menu(item);
        if (context_menu == null)
            return false;
            
        if (!on_context_invoked(context_menu))
            return false;
            
        context_menu.popup(null, null, null, event.button, event.time);

        return true;
    }
    
    public LayoutItem? get_next_item(LayoutItem current) {
        if (layout.items.size == 0)
            return null;
        
        int index = layout.items.index_of(current);

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
        
        int index = layout.items.index_of(current);
        
        // although items may be added while the page is away, not handling situations where an active
        // item is removed
        assert(index >= 0);

        index--;
        if (index < 0)
            index = (layout.items.size - 1);
        
        return layout.items.get(index);
    }
}
