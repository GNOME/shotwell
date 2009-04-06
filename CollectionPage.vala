
public class CollectionPage : Gtk.ScrolledWindow {
    public static const int THUMB_X_PADDING = 20;
    public static const int THUMB_Y_PADDING = 20;
    public static const string BG_COLOR = "#777";

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public static const int MANUAL_STEPPING = 16;
    public static const int SLIDER_STEPPING = 1;

    private static const int IMPROVAL_PRIORITY = Priority.LOW;
    private static const int IMPROVAL_DELAY_MS = 500;
    
    private static Gtk.IconFactory factory = null;
    private static const string STOCK_CLOCKWISE = "shotwell-rotate-clockwise";
    private static const string STOCK_COUNTERCLOCKWISE = "shotwell-rotate-counterclockwise";
    
    private static void addStockIcon(File file, string stockID) {
        debug("Adding icon %s", file.get_path());
        
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }
        
        debug("%d %d", pixbuf.width, pixbuf.height);
        
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
    
    private PhotoTable photoTable = new PhotoTable();
    private CollectionLayout layout = new CollectionLayout();
    private Gtk.ActionGroup mainActionGroup = new Gtk.ActionGroup("CollectionActionGroup");
    private Gtk.ActionGroup contextActionGroup = new Gtk.ActionGroup("CollectionContextActionGroup");
    private Gtk.MenuBar menubar = null;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.HScale slider = null;
    private Gtk.ToolButton rotateButton = null;
    private Gee.ArrayList<Thumbnail> thumbnailList = new Gee.ArrayList<Thumbnail>();
    private Gee.HashSet<Thumbnail> selectedList = new Gee.HashSet<Thumbnail>();
    private int scale = Thumbnail.DEFAULT_SCALE;
    private bool improval_scheduled = false;

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "File", null, "_File", null, null, null },
        { "Quit", Gtk.STOCK_QUIT, "_Quit", null, "Quit the program", Gtk.main_quit },
        
        { "Edit", null, "_Edit", null, null, on_edit_menu },
        { "SelectAll", Gtk.STOCK_SELECT_ALL, "Select _All", "<Ctrl>A", "Select all the photos in the library", on_select_all },
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove },
        
        { "Photos", null, "_Photos", null, null, on_photos_menu },
        { "IncreaseSize", Gtk.STOCK_ZOOM_IN, "Zoom _in", "KP_Add", "Increase the magnification of the thumbnails", on_increase_size },
        { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, "Zoom _out", "KP_Subtract", "Decrease the magnification of the thumbnails", on_decrease_size },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, "_About", null, "About this application", on_about }
    };
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] RIGHT_CLICK_ACTIONS = {
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove },
        { "RotateClockwise", STOCK_CLOCKWISE, "Rotate c_lockwise", "<Ctrl>R", "Rotate the selected photos clockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", STOCK_COUNTERCLOCKWISE, "Rotate c_ounterclockwise", "<Ctrl><Shift>R", "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", null, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", on_mirror }
    };
    
    construct {
        prepIcons();
        
        // set up action group
        mainActionGroup.add_actions(ACTIONS, this);
        AppWindow.get_ui_manager().insert_action_group(mainActionGroup, 0);
        
        contextActionGroup.add_actions(RIGHT_CLICK_ACTIONS, this);
        AppWindow.get_ui_manager().insert_action_group(contextActionGroup, 0);

        // this page's menu bar
        menubar = (Gtk.MenuBar) AppWindow.get_ui_manager().get_widget("/CollectionMenuBar");
        
        // set up page's toolbar (used by AppWindow for layout)
        //
        // rotate tool
        rotateButton = new Gtk.ToolButton.from_stock(STOCK_CLOCKWISE);
        rotateButton.sensitive = false;
        rotateButton.clicked += on_rotate_clockwise;
        
        toolbar.insert(rotateButton, -1);
        
        // separator to force slider to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // thumbnail size slider
        slider = new Gtk.HScale.with_range(0, scaleToSlider(Thumbnail.MAX_SCALE), 1);
        slider.set_value(scaleToSlider(scale));
        slider.value_changed += on_slider_changed;
        slider.set_draw_value(false);

        Gtk.ToolItem toolitem = new Gtk.ToolItem();
        toolitem.add(slider);
        toolitem.set_expand(false);
        toolitem.set_size_request(200, -1);
        
        toolbar.insert(toolitem, -1);
        
        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        AppWindow.get_main_window().key_press_event += on_key_pressed;
        AppWindow.get_main_window().key_release_event += on_key_released;
        
        // this schedules thumbnail improvement whenever the window size changes (and new thumbnails
        // may be exposed)
        size_allocate += schedule_thumbnail_improval;
        
        // this schedules thumbnail improvement whenever the window is scrolled (and new
        // thumbnails may be exposed)
        get_hadjustment().value_changed += schedule_thumbnail_improval;
        get_vadjustment().value_changed += schedule_thumbnail_improval;
        
        add(layout);
        
        button_press_event += on_click;
        
        File[] photoFiles = photoTable.get_photo_files();
        foreach (File file in photoFiles) {
            PhotoID photoID = photoTable.get_id(file);
            add_photo(photoID, file);
        }
        
        layout.refresh();
        
        schedule_thumbnail_improval();

        show_all();
    }
    
    public Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public Gtk.MenuBar get_menubar() {
        return menubar;
    }
    
    public Gtk.ActionGroup get_action_group() {
        return mainActionGroup;
    }
    
    public void begin_adding() {
    }
    
    public void add_photo(PhotoID photoID, File file) {
        Thumbnail thumbnail = new Thumbnail(photoID, file, scale);
        
        thumbnailList.add(thumbnail);
        
        layout.append(thumbnail);
    }
    
    public void end_adding() {
        layout.refresh();
    }
    
    public int get_count() {
        return thumbnailList.size;
    }

    public void select_all() {
        foreach (Thumbnail thumbnail in thumbnailList) {
            selectedList.add(thumbnail);
            thumbnail.select();
        }
        
        rotateButton.sensitive = true;
    }
    
    public void unselect_all() {
        foreach (Thumbnail thumbnail in selectedList) {
            assert(thumbnail.is_selected());
            thumbnail.unselect();
        }
        
        selectedList = new Gee.HashSet<Thumbnail>();
        
        rotateButton.sensitive = false;
    }
    
    public Thumbnail[] get_selected() {
        Thumbnail[] thumbnails = new Thumbnail[selectedList.size];
        
        int ctr = 0;
        foreach (Thumbnail thumbnail in selectedList) {
            assert(thumbnail.is_selected());
            thumbnails[ctr++] = thumbnail;
        }
        
        return thumbnails;
    }
    
    public void select(Thumbnail thumbnail) {
        thumbnail.select();
        selectedList.add(thumbnail);
        
        rotateButton.sensitive = true;
    }
    
    public void unselect(Thumbnail thumbnail) {
        thumbnail.unselect();
        selectedList.remove(thumbnail);
        
        rotateButton.sensitive = (selectedList.size != 0);
    }
    
    public void toggle_select(Thumbnail thumbnail) {
        if (thumbnail.toggle_select()) {
            // now selected
            selectedList.add(thumbnail);
        } else {
            // now unselected
            selectedList.remove(thumbnail);
        }
        
        rotateButton.sensitive = (selectedList.size != 0);
    }

    public int get_selected_count() {
        return selectedList.size;
    }
    
    public int increase_thumb_size() {
        if (scale == Thumbnail.MAX_SCALE)
            return scale;
        
        scale += MANUAL_STEPPING;
        if (scale > Thumbnail.MAX_SCALE) {
            scale = Thumbnail.MAX_SCALE;
        }
        
        set_thumb_size(scale);
        
        return scale;
    }
    
    public int decrease_thumb_size() {
        if (scale == Thumbnail.MIN_SCALE)
            return scale;
        
        scale -= MANUAL_STEPPING;
        if (scale < Thumbnail.MIN_SCALE) {
            scale = Thumbnail.MIN_SCALE;
        }
        
        set_thumb_size(scale);

        return scale;
    }
    
    public void set_thumb_size(int newScale) {
        assert(newScale >= Thumbnail.MIN_SCALE);
        assert(newScale <= Thumbnail.MAX_SCALE);
        
        scale = newScale;
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            thumbnail.resize(scale);
        }
        
        layout.refresh();
        
        schedule_thumbnail_improval();
    }
    
    private bool reschedule_improval = false;

    private void schedule_thumbnail_improval() {
        if (improval_scheduled == false) {
            improval_scheduled = true;
            Timeout.add_full(IMPROVAL_PRIORITY, IMPROVAL_DELAY_MS, improve_thumbnail_quality);
        } else {
            reschedule_improval = true;
        }
    }
    
    private bool improve_thumbnail_quality() {
        if (reschedule_improval) {
            debug("rescheduled improval");
            reschedule_improval = false;
            
            return true;
        }

        foreach (Thumbnail thumbnail in thumbnailList) {
            if (thumbnail.is_exposed()) {
                thumbnail.paint_high_quality();
            }
        }
        
        improval_scheduled = false;
        
        debug("improve_thumbnail_quality");
        
        return false;
    }

    private void on_about() {
        AppWindow.get_main_window().about_box();
    }
    
    private void set_item_sensitive(string path, bool sensitive) {
        Gtk.Widget widget = AppWindow.get_ui_manager().get_widget(path);
        widget.set_sensitive(sensitive);
    }
    
    private void on_edit_menu() {
        set_item_sensitive("/CollectionMenuBar/EditMenu/EditSelectAll", get_count() > 0);
        set_item_sensitive("/CollectionMenuBar/EditMenu/EditRemove", get_selected_count() > 0);
    }
    
    private void on_select_all() {
        select_all();
    }
    
    private void on_photos_menu() {
        bool selected = (get_selected_count() > 0);
        
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/PhotosIncreaseSize", scale < Thumbnail.MAX_SCALE);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/PhotosDecreaseSize", scale > Thumbnail.MIN_SCALE);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateClockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateCounterclockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Mirror", selected);
    }

    private void on_increase_size() {
        increase_thumb_size();
        slider.set_value(scaleToSlider(scale));
    }

    private void on_decrease_size() {
        decrease_thumb_size();
        slider.set_value(scaleToSlider(scale));
    }

    private bool on_click(CollectionPage c, Gdk.EventButton event) {
        switch (event.button) {
            case 1:
                return on_left_click(event);
            
            case 3:
                return on_right_click(event);
            
            default:
                return false;
        }
    }
        
    private bool on_left_click(Gdk.EventButton event) {
        // only interested in single-clicks presses for now
        if ((event.type != Gdk.EventType.BUTTON_PRESS) 
            && (event.type != Gdk.EventType.2BUTTON_PRESS)) {
            return false;
        }
        
        // mask out the modifiers we're interested in
        uint state = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
        
        Thumbnail thumbnail = layout.get_thumbnail_at(event.x, event.y);
        if (thumbnail != null) {
            message("clicked on %s", thumbnail.get_file().get_basename());
            
            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK: {
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    toggle_select(thumbnail);
                } break;
                
                case Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                default: {
                    if (event.type == Gdk.EventType.2BUTTON_PRESS) {
                        /*
                        // switch to full-page view
                        debug("switching to %s [%d]", thumbnail.get_file().get_path(),
                            thumbnail.get_photo_id().id);
                        AppWindow.get_main_window().switch_to_photo_page(thumbnail.get_photo_id());
                        */
                    } else {
                        // a "raw" single-click deselects all thumbnails and selects the single chosen
                        unselect_all();
                        select(thumbnail);
                    }
                } break;
            }
        } else {
            // user clicked on "dead" area
            unselect_all();
        }

        return true;
    }
    
    private bool on_right_click(Gdk.EventButton event) {
        // only interested in single-clicks for now
        if (event.type != Gdk.EventType.BUTTON_PRESS) {
            return false;
        }
        
        Thumbnail thumbnail = layout.get_thumbnail_at(event.x, event.y);
        if (thumbnail != null) {
            // this counts as a select with all others de-selected
            unselect_all();
            select(thumbnail);

            Gtk.Menu contextMenu = (Gtk.Menu) AppWindow.get_ui_manager().get_widget("/CollectionContextMenu");
            contextMenu.popup(null, null, null, event.button, event.time);
            
            return true;
        }
            
        return false;
    }
    
    private void on_remove() {
        // get a full list of the selected thumbnails, then iterate over that, as you can't remove
        // from a list you're iterating over
        Thumbnail[] thumbnails = get_selected();
        foreach (Thumbnail thumbnail in thumbnails) {
            thumbnailList.remove(thumbnail);
            selectedList.remove(thumbnail);

            ThumbnailCache.remove(thumbnail.get_photo_id());
            photoTable.remove(thumbnail.get_photo_id());
            
            layout.remove_thumbnail(thumbnail);
        }
        
        assert(selectedList.size == 0);
        rotateButton.sensitive = false;
        
        layout.refresh();
    }
    
    private delegate Exif.Orientation RotationFunc(Exif.Orientation orientation);
    
    private void do_rotations(string desc, Gee.Collection<Thumbnail> c, RotationFunc func) {
        foreach (Thumbnail thumbnail in c) {
            Exif.Orientation orientation = thumbnail.get_orientation();
            Exif.Orientation rotated = func(orientation);
            debug("Rotating %s %s from %s to %s", desc, thumbnail.get_file().get_path(),
                orientation.get_description(), rotated.get_description());
            thumbnail.set_orientation(rotated);
        }
        
        if (c.size > 0) {
            schedule_thumbnail_improval();
            layout.refresh();
        }
    }

    private void on_rotate_clockwise() {
        do_rotations("clockwise", selectedList, (orientation) => {
            return orientation.rotate_clockwise();
        });
    }
    
    private void on_rotate_counterclockwise() {
        do_rotations("counterclockwise", selectedList, (orientation) => {
            return orientation.rotate_counterclockwise();
        });
    }
    
    private void on_mirror() {
        do_rotations("mirror", selectedList, (orientation) => {
            return orientation.flip_left_to_right();
        });
    }
    
    private double scaleToSlider(int value) {
        assert(value >= Thumbnail.MIN_SCALE);
        assert(value <= Thumbnail.MAX_SCALE);
        
        return (double) ((value - Thumbnail.MIN_SCALE) / SLIDER_STEPPING);
    }
    
    private int sliderToScale(double value) {
        int res = ((int) (value * SLIDER_STEPPING)) + Thumbnail.MIN_SCALE;

        assert(res >= Thumbnail.MIN_SCALE);
        assert(res <= Thumbnail.MAX_SCALE);
        
        return res;
    }
    
    private void on_slider_changed() {
        set_thumb_size(sliderToScale(slider.get_value()));
    }
    
    private static const uint KEY_CTRL_L = Gdk.keyval_from_name("Control_L");
    private static const uint KEY_CTRL_R = Gdk.keyval_from_name("Control_R");
    private static const uint KEY_ALT_L = Gdk.keyval_from_name("Alt_L");
    private static const uint KEY_ALT_R = Gdk.keyval_from_name("Alt_R");

    private bool on_key_pressed(AppWindow aw, Gdk.EventKey event) {
        if ((event.keyval == KEY_CTRL_L) || (event.keyval == KEY_CTRL_R)) {
            rotateButton.set_stock_id(STOCK_COUNTERCLOCKWISE);
            rotateButton.clicked -= on_rotate_clockwise;
            rotateButton.clicked += on_rotate_counterclockwise;
        }

        return false;
    }
    
    private bool on_key_released(AppWindow aw, Gdk.EventKey event) {
        if ((event.keyval == KEY_CTRL_L) || (event.keyval == KEY_CTRL_R)) {
            rotateButton.set_stock_id(STOCK_CLOCKWISE);
            rotateButton.clicked -= on_rotate_counterclockwise;
            rotateButton.clicked += on_rotate_clockwise;
        }

        return false;
    }
}

