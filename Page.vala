
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
    
    construct {
        prepIcons();
        
        button_press_event += on_click;
        AppWindow.get_main_window().key_press_event += on_key_pressed_internal;
        AppWindow.get_main_window().key_release_event += on_key_released_internal;
    }
    
    public abstract string get_menubar_path();

    public abstract Gtk.Toolbar get_toolbar();
    
    public virtual void switching_from() {
    }
    
    public virtual void switched_to() {
    }
    
    public void about_box() {
        // TODO: More thorough About box
        Gtk.show_about_dialog(AppWindow.get_main_window(),
            "version", AppWindow.VERSION,
            "comments", "a photo organizer",
            "copyright", "(c) 2009 yorba",
            "website", "http://www.yorba.org"
        );
    }

    public void set_item_sensitive(string path, bool sensitive) {
        Gtk.Widget widget = AppWindow.get_ui_manager().get_widget(path);
        widget.set_sensitive(sensitive);
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
    
    protected virtual void on_ctrl_pressed(Gdk.EventKey event) {
    }
    
    protected virtual void on_ctrl_released(Gdk.EventKey event) {
    }
    
    protected virtual void on_alt_pressed(Gdk.EventKey event) {
    }
    
    protected virtual void on_alt_released(Gdk.EventKey event) {
    }
    
    private bool on_key_pressed_internal(AppWindow aw, Gdk.EventKey event) {
        if ((event.keyval == KEY_CTRL_L) || (event.keyval == KEY_CTRL_R)) {
            on_ctrl_pressed(event);
        }
        
        if ((event.keyval == KEY_ALT_L) || (event.keyval == KEY_ALT_R)) {
            on_alt_pressed(event);
        }

        return on_key_pressed(event);
    }
    
    private bool on_key_released_internal(AppWindow aw, Gdk.EventKey event) {
        if ((event.keyval == KEY_CTRL_L) || (event.keyval == KEY_CTRL_R)) {
            on_ctrl_released(event);
        }
        
        if ((event.keyval == KEY_ALT_L) || (event.keyval == KEY_ALT_R)) {
            on_alt_released(event);
        }

        return on_key_released(event);
    }
}
