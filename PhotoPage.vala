
public class PhotoPage : Page {
    public static const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.BILINEAR;
    public static const int IMAGE_BORDER = 4;
    
    private Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton rotateButton = null;
    private Gtk.ToolButton prevButton = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
    private Gtk.ToolButton nextButton = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
    private Gtk.Image image = new Gtk.Image();
    private LayoutItem item = null;
    private Gdk.Pixbuf original = null;
    private Exif.Orientation orientation;
    private Gdk.Pixbuf rotated = null;
    private Dimensions rotatedDim;
    private CheckerboardPage controller = null;

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, null },

        { "PhotoMenu", null, "_Photo", null, null, null },
        { "PrevPhoto", Gtk.STOCK_GO_BACK, "_Previous Photo", null, "Previous Photo", on_previous_photo },
        { "NextPhoto", Gtk.STOCK_GO_FORWARD, "_Next Photo", null, "Next Photo", on_next_photo },
        { "RotateClockwise", STOCK_CLOCKWISE, "Rotate c_lockwise", "<Ctrl>R", "Rotate the selected photos clockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", STOCK_COUNTERCLOCKWISE, "Rotate c_ounterclockwise", "<Ctrl><Shift>R", "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", null, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", on_mirror },

        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    construct {
        init_ui("photo.ui", "/PhotoMenuBar", "PhotoActionGroup", ACTIONS);

        // set up page's toolbar (used by AppWindow for layout)
        //
        // rotate tool
        rotateButton = new Gtk.ToolButton.from_stock(STOCK_CLOCKWISE);
        rotateButton.label = "Rotate Clockwise";
        rotateButton.clicked += on_rotate_clockwise;
        toolbar.insert(rotateButton, -1);
        
        // separator to force next/prev buttons to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // previous button
        prevButton.clicked += on_previous_photo;
        toolbar.insert(prevButton, -1);
        
        // next button
        nextButton.clicked += on_next_photo;
        toolbar.insert(nextButton, -1);
        
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        viewport.add(image);
        viewport.modify_bg(Gtk.StateType.NORMAL, AppWindow.BG_COLOR);
        
        add(viewport);
        
        expose_event += on_expose;
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public void display(CheckerboardPage controller, LayoutItem item) {
        this.controller = controller;
        this.item = item;

        update_display();
        update_sensitivity();
    }
    
    private void update_display() {
        if (item == null) {
            // TODO: Display error message
            return;
        }
        
        orientation = item.get_orientation();
        original = item.get_full_pixbuf();
        if (original == null)
            return;

        rotated = rotate_to_exif(original, orientation);
        rotatedDim = Dimensions.for_pixbuf(rotated);
        
        repaint(true);
    }

    private int lastWidth = 0;
    private int lastHeight = 0;
    
    private bool repaint(bool force = false) {
        int width = viewport.allocation.width - IMAGE_BORDER;
        int height = viewport.allocation.height - IMAGE_BORDER;

        if (width <= 0 || height <= 0)
            return false;

        if (!force && width == lastWidth && height == lastHeight)
            return false;

        lastWidth = width;
        lastHeight = height;
        
        Dimensions viewDim = Dimensions(width, height);
        Dimensions scaled = get_scaled_dimensions_for_view(rotatedDim, viewDim);
        Gdk.Pixbuf pixbuf = rotated.scale_simple(scaled.width, scaled.height, DEFAULT_INTERP);

        image.set_from_pixbuf(pixbuf);
        
        return true;
    }
    
    private override bool on_left_click(Gdk.EventButton event) {
        if (event.type == Gdk.EventType.2BUTTON_PRESS) {
            AppWindow.get_main_window().switch_to_page(controller);
            
            return true;
        }
        
        return false;
    }

    private bool on_expose(PhotoPage p, Gdk.EventExpose event) {
        return repaint();
    }
    
    private void set_orientation(Exif.Orientation newOrientation) {
        orientation = newOrientation;
        rotated = rotate_to_exif(original, orientation);
        rotatedDim = Dimensions.for_pixbuf(rotated);
        
        item.set_orientation(orientation);

        repaint(true);
    }
    
    private void on_rotate_clockwise() {
        set_orientation(orientation.rotate_clockwise());
    }
    
    private void on_rotate_counterclockwise() {
        set_orientation(orientation.rotate_counterclockwise());
    }
    
    private void on_mirror() {
        set_orientation(orientation.flip_left_to_right());
    }

    private override bool on_ctrl_pressed(Gdk.EventKey event) {
        rotateButton.set_stock_id(STOCK_COUNTERCLOCKWISE);
        rotateButton.label = "Rotate Counterclockwise";
        rotateButton.clicked -= on_rotate_clockwise;
        rotateButton.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotateButton.set_stock_id(STOCK_CLOCKWISE);
        rotateButton.label = "Rotate Clockwise";
        rotateButton.clicked -= on_rotate_counterclockwise;
        rotateButton.clicked += on_rotate_clockwise;
        
        return false;
    }
    
    private void on_next_photo() {
        this.item = controller.get_next_item(item);
        update_display();
    }
    
    private void on_previous_photo() {
        this.item = controller.get_previous_item(item);
        update_display();
    }
    
    private void update_sensitivity() {
        assert(controller != null);
        
        bool multiple = (controller.get_count() > 1);
        
        prevButton.sensitive = multiple;
        nextButton.sensitive = multiple;
        
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/NextPhoto", multiple);
    }
}

