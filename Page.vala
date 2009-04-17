
public abstract class Page : Gtk.ScrolledWindow {
    public static const uint KEY_CTRL_L = Gdk.keyval_from_name("Control_L");
    public static const uint KEY_CTRL_R = Gdk.keyval_from_name("Control_R");
    public static const uint KEY_ALT_L = Gdk.keyval_from_name("Alt_L");
    public static const uint KEY_ALT_R = Gdk.keyval_from_name("Alt_R");
    
    public static const string STOCK_CLOCKWISE = "shotwell-rotate-clockwise";
    public static const string STOCK_COUNTERCLOCKWISE = "shotwell-rotate-counterclockwise";
    
    public static const Gdk.Color BG_COLOR = parse_color("#777");

    private static Gtk.IconFactory factory = null;
    
    private static void addStockIcon(File file, string stockID) {
        debug("Adding icon %s", file.get_path());
        
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }
        
        Gtk.IconSet iconSet = new Gtk.IconSet.from_pixbuf(pixbuf);
        factory.add(stockID, iconSet);
    }
    
    private static void prepIcons() {
        if (factory != null)
            return;
        
        factory = new Gtk.IconFactory();
        
        File icons = AppWindow.get_exec_dir().get_child("icons");
        
        addStockIcon(icons.get_child("object-rotate-right.svg"), STOCK_CLOCKWISE);
        addStockIcon(icons.get_child("object-rotate-left.svg"), STOCK_COUNTERCLOCKWISE);
        
        factory.add_default();
    }
    
    public Gtk.UIManager ui = new Gtk.UIManager();
    public Gtk.ActionGroup actionGroup = null;
    public Gtk.MenuBar menuBar = null;
    
    private Gtk.TreeRowReference row = null;
    
    construct {
        prepIcons();
        
        button_press_event += on_click;
        AppWindow.get_main_window().key_press_event += on_key_pressed_internal;
        AppWindow.get_main_window().key_release_event += on_key_released_internal;
        AppWindow.get_main_window().configure_event += on_configure;
    }
    
    public void set_tree_row(Gtk.TreeModel model, Gtk.TreeIter iter) {
        row = new Gtk.TreeRowReference(model, model.get_path(iter));
    }
    
    public unowned Gtk.TreeRowReference get_tree_row() {
        return row;
    }
    
    public virtual Gtk.MenuBar get_menubar() {
        return menuBar;
    }

    public abstract Gtk.Toolbar get_toolbar();
    
    public virtual void switching_from() {
    }
    
    public virtual void switched_to() {
    }
    
    public void set_item_sensitive(string path, bool sensitive) {
        ui.get_widget(path).sensitive = sensitive;
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
    
    protected void init_ui(string uiFilename, string menuBarPath, string actionGroupName, 
        Gtk.ActionEntry[] entries) {
        File uiFile = AppWindow.get_exec_dir().get_child(uiFilename);

        try {
            ui.add_ui_from_file(uiFile.get_path());
        } catch (Error gle) {
            error("Error loading UI file %s: %s", uiFilename, gle.message);
        }
        
        actionGroup = new Gtk.ActionGroup(actionGroupName);
        actionGroup.add_actions(entries, this);

        ui.insert_action_group(actionGroup, 0);
        ui.insert_action_group(AppWindow.get_main_window().get_common_action_group(), 0);
        
        if (menuBarPath != null)
            menuBar = (Gtk.MenuBar) ui.get_widget(menuBarPath);

        ui.ensure_update();
    }
    
    private bool on_click(Page p, Gdk.EventButton event) {
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

    protected virtual bool on_key_pressed(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_key_released(Gdk.EventKey event) {
        return false;
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
    
    protected virtual bool on_resize(Gdk.Rectangle rect) {
        return false;
    }
    
    private bool on_key_pressed_internal(AppWindow aw, Gdk.EventKey event) {
        if ((event.keyval == KEY_CTRL_L) || (event.keyval == KEY_CTRL_R)) {
            return on_ctrl_pressed(event);
        }
        
        if ((event.keyval == KEY_ALT_L) || (event.keyval == KEY_ALT_R)) {
            return on_alt_pressed(event);
        }

        return on_key_pressed(event);
    }
    
    private bool on_key_released_internal(AppWindow aw, Gdk.EventKey event) {
        if ((event.keyval == KEY_CTRL_L) || (event.keyval == KEY_CTRL_R)) {
            return on_ctrl_released(event);
        }
        
        if ((event.keyval == KEY_ALT_L) || (event.keyval == KEY_ALT_R)) {
            return on_alt_released(event);
        }

        return on_key_released(event);
    }
    
    private bool on_configure(AppWindow aw, Gdk.EventConfigure event) {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = event.x;
        rect.y = event.y;
        rect.width = event.width;
        rect.height = event.height;
        
        return on_resize(rect);
    }
}

public abstract class CheckerboardPage : Page {
    private Gtk.Menu contextMenu = null;
    private CollectionLayout layout = new CollectionLayout();
    private Gee.ArrayList<LayoutItem> items = new Gee.ArrayList<LayoutItem>();
    private Gee.HashSet<LayoutItem> selectedItems = new Gee.HashSet<LayoutItem>();
    
    construct {
        add(layout);
    }
    
    protected void init_context_menu(string path) {
        contextMenu = (Gtk.Menu) ui.get_widget(path);
    }
    
    protected virtual void on_selection_changed(int count) {
    }
    
    public virtual Gtk.Menu get_context_menu(LayoutItem item) {
        return contextMenu;
    }
    
    public virtual void on_item_activated(LayoutItem item) {
    }
    
    public void refresh() {
        layout.refresh();
    }
    
    public LayoutItem? get_item_at(double x, double y) {
        return layout.get_item_at(x, y);
    }
    
    public Gee.Iterable<LayoutItem> get_items() {
        return items;
    }
    
    public Gee.Iterable<LayoutItem> get_selected() {
        return selectedItems;
    }
    
    public void add_item(LayoutItem item) {
        items.add(item);
        layout.append(item);
    }
    
    public void remove_item(LayoutItem item) {
        items.remove(item);
        layout.remove_item(item);
    }
    
    public int remove_selected() {
        int count = selectedItems.size;
        
        foreach (LayoutItem item in selectedItems) {
            layout.remove_item(item);
            items.remove(item);
        }
        
        selectedItems.clear();
        
        return count;
    }
    
    public int remove_all() {
        int count = items.size;
        
        layout.clear();
        items.clear();
        selectedItems.clear();
        
        return count;
    }
    
    public int get_count() {
        return items.size;
    }
    
    public void select_all() {
        foreach (LayoutItem item in items) {
            selectedItems.add(item);
            item.select();
        }
        
        on_selection_changed(selectedItems.size);
    }

    public void unselect_all() {
        foreach (LayoutItem item in selectedItems) {
            assert(item.is_selected());
            item.unselect();
        }
        
        selectedItems.clear();
        
        on_selection_changed(0);
    }

    public void select(LayoutItem item) {
        assert(items.index_of(item) >= 0);
        
        item.select();
        selectedItems.add(item);
        
        on_selection_changed(selectedItems.size);
    }
    
    public void unselect(LayoutItem item) {
        assert(items.index_of(item) >= 0);
        
        item.unselect();
        selectedItems.remove(item);
        
        on_selection_changed(selectedItems.size);
    }

    public void toggle_select(LayoutItem item) {
        if (item.toggle_select()) {
            // now selected
            selectedItems.add(item);
        } else {
            // now unselected
            selectedItems.remove(item);
        }
        
        on_selection_changed(selectedItems.size);
    }

    public int get_selected_count() {
        return selectedItems.size;
    }

    private override bool on_left_click(Gdk.EventButton event) {
        // only interested in single-click and double-clicks for now
        if ((event.type != Gdk.EventType.BUTTON_PRESS) 
            && (event.type != Gdk.EventType.2BUTTON_PRESS)) {
            return false;
        }
        
        // mask out the modifiers we're interested in
        uint state = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
        
        LayoutItem item = get_item_at(event.x, event.y);
        if (item != null) {
            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK: {
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    toggle_select(item);
                } break;
                
                case Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                default: {
                    if (event.type == Gdk.EventType.2BUTTON_PRESS) {
                        on_item_activated(item);
                    } else {
                        // a "raw" single-click deselects all thumbnails and selects the single chosen
                        unselect_all();
                        select(item);
                    }
                } break;
            }
        } else {
            // user clicked on "dead" area
            unselect_all();
        }

        return true;
    }
    
    private override bool on_right_click(Gdk.EventButton event) {
        // only interested in single-clicks for now
        if (event.type != Gdk.EventType.BUTTON_PRESS) {
            return false;
        }
        
        LayoutItem item = get_item_at(event.x, event.y);
        if (item != null) {
            // TODO: Enable context menus for multiple and single selections
            unselect_all();
            select(item);
        }
            
        Gtk.Menu contextMenu = get_context_menu(item);
        if (contextMenu != null) {
            contextMenu.popup(null, null, null, event.button, event.time);

            return true;
        }
            
        return false;
    }
    
    public LayoutItem? get_next_item(LayoutItem current) {
        if (items.size == 0)
            return null;
        
        int index = items.index_of(current);

        // although items may be added while the page is away, not handling situations where an active
        // item is removed
        assert(index >= 0);

        index++;
        if (index >= items.size)
            index = 0;
        
        return items.get(index);
    }
    
    public LayoutItem? get_previous_item(LayoutItem current) {
        if (items.size == 0)
            return null;
        
        int index = items.index_of(current);
        
        // although items may be added while the page is away, not handling situations where an active
        // item is removed
        assert(index >= 0);

        index--;
        if (index < 0)
            index = (items.size - 1);
        
        return items.get(index);
    }
}
