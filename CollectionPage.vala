
public class CollectionPage : CheckerboardPage {
    public static const int SORT_BY_MIN = 0;
    public static const int SORT_BY_NAME = 0;
    public static const int SORT_BY_EXPOSURE_DATE = 1;
    public static const int SORT_BY_MAX = 1;
    
    public static const int SORT_ORDER_MIN = 0;
    public static const int SORT_ORDER_ASCENDING = 0;
    public static const int SORT_ORDER_DESCENDING = 1;
    public static const int SORT_ORDER_MAX = 1;

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public static const int MANUAL_STEPPING = 16;
    public static const int SLIDER_STEPPING = 1;

    private static const int IMPROVAL_PRIORITY = Priority.LOW;
    private static const int IMPROVAL_DELAY_MS = 250;
    
    private PhotoTable photo_table = new PhotoTable();
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.HScale slider = null;
    private Gtk.ToolButton rotateButton = null;
    private int scale = Thumbnail.DEFAULT_SCALE;
    private bool improval_scheduled = false;
    private bool in_view = false;

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, null },

        { "EditMenu", null, "_Edit", null, null, on_edit_menu },
        { "SelectAll", Gtk.STOCK_SELECT_ALL, "Select _All", "<Ctrl>A", "Select all the photos in the library", on_select_all },
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove },
        
        { "PhotosMenu", null, "_Photos", null, null, on_photos_menu },
        { "IncreaseSize", Gtk.STOCK_ZOOM_IN, "Zoom _in", "KP_Add", "Increase the magnification of the thumbnails", on_increase_size },
        { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, "Zoom _out", "KP_Subtract", "Decrease the magnification of the thumbnails", on_decrease_size },
        { "RotateClockwise", STOCK_CLOCKWISE, "Rotate c_lockwise", "<Ctrl>R", "Rotate the selected photos clockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", STOCK_COUNTERCLOCKWISE, "Rotate c_ounterclockwise", "<Ctrl><Shift>R", "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", null, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", on_mirror },
        
        { "ViewMenu", null, "_View", null, null, on_view_menu },
        { "SortPhotos", null, "_Sort Photos", null, null, null },
        
        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    private const Gtk.ToggleActionEntry[] TOGGLE_ACTIONS = {
        { "ViewTitle", null, "_Titles", "<Ctrl><Shift>T", "Display the title of each photo", on_display_titles, true }
    };
    
    private const Gtk.RadioActionEntry[] SORT_CRIT_ACTIONS = {
        { "SortByName", null, "By _Name", null, "Sort photos by name", SORT_BY_NAME },
        { "SortByExposureDate", null, "By Exposure _Date", null, "Sort photos by exposure date", SORT_BY_EXPOSURE_DATE }
    };
    
    private const Gtk.RadioActionEntry[] SORT_ORDER_ACTIONS = {
        { "SortAscending", null, "_Ascending", null, "Sort photos in an ascending order", SORT_ORDER_ASCENDING },
        { "SortDescending", null, "D_escending", null, "Sort photos in a descending order", SORT_ORDER_DESCENDING }
    };
    
    public CollectionPage(PhotoID[] photos, string? ui_filename = null, Gtk.ActionEntry[]? child_actions = null) {
        init_ui_start("collection.ui", "CollectionActionGroup", ACTIONS, TOGGLE_ACTIONS);
        actionGroup.add_radio_actions(SORT_CRIT_ACTIONS, SORT_BY_NAME, on_sort_changed);
        actionGroup.add_radio_actions(SORT_ORDER_ACTIONS, SORT_ORDER_ASCENDING, on_sort_changed);

        if (ui_filename != null)
            init_load_ui(ui_filename);
        
        if (child_actions != null)
            actionGroup.add_actions(child_actions, this);
        
        init_ui_bind("/CollectionMenuBar");
        init_context_menu("/CollectionContextMenu");
        
        set_layout_comparator(new CompareName());
        
        // set up page's toolbar (used by AppWindow for layout)
        //
        // rotate tool
        rotateButton = new Gtk.ToolButton.from_stock(STOCK_CLOCKWISE);
        rotateButton.label = "Rotate Clockwise";
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
        
        // this schedules thumbnail improvement whenever the window is scrolled (and new
        // thumbnails may be exposed)
        get_hadjustment().value_changed += schedule_thumbnail_improval;
        get_vadjustment().value_changed += schedule_thumbnail_improval;
        
        // load photos into view
        foreach (PhotoID photo_id in photos) {
            add_photo(photo_id);
        }

        refresh();
        
        show_all();

        schedule_thumbnail_improval();
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void switching_from() {
        in_view = false;
    }
    
    public override void switched_to() {
        in_view = true;
        
        // need to refresh the layout in case any of the thumbnail dimensions were altered while we
        // were gone
        refresh();
        
        // schedule improvement in case any new photos were added
        schedule_thumbnail_improval();
    }
    
    protected override void on_selection_changed(int count) {
        rotateButton.sensitive = (count > 0);
    }
    
    protected override void on_item_activated(LayoutItem item) {
        Thumbnail thumbnail = (Thumbnail) item;
        
        // switch to full-page view
        debug("switching to %s [%lld]", thumbnail.get_file().get_path(),
            thumbnail.get_photo_id().id);

        AppWindow.get_instance().switch_to_photo_page(this, thumbnail);
    }
    
    public override LayoutItem? get_fullscreen_photo() {
        Gee.Iterable<LayoutItem> iter = null;
        
        // if no selection, use the first item
        if (get_selected_count() > 0) {
            iter = get_selected();
        } else {
            iter = get_items();
        }
        
        // use the first item of the selected collection to start things off
        foreach (LayoutItem item in iter) {
            return item;
        }
        
        return null;
    }
    
    private int lastWidth = 0;
    private int lastHeight = 0;

    protected override bool on_resize(Gdk.Rectangle rect) {
        // this schedules thumbnail improvement whenever the window size changes (and new thumbnails
        // may be exposed), therefore, uninterested in window position move
        if ((lastWidth != rect.width) || (lastHeight != rect.height)) {
            lastWidth = rect.width;
            lastHeight = rect.height;

            schedule_thumbnail_improval();
        }
        
        return false;
    }

    public void add_photo(PhotoID photoID) {
        Thumbnail thumbnail = new Thumbnail(photoID, scale);
        thumbnail.display_title(display_titles());
        
        add_item(thumbnail);
    }
    
    public bool remove_photo(PhotoID photo_id) {
        Thumbnail found = null;
        foreach (LayoutItem item in get_items()) {
            Thumbnail thumbnail = (Thumbnail) item;
            if (thumbnail.get_photo_id().id == photo_id.id) {
                found = thumbnail;
                
                break;
            }
        }
        
        if (found != null)
            remove_item(found);
        
        return (found != null);
    }
    
    public void report_backing_changed(PhotoID photo_id) {
        foreach (LayoutItem item in get_items()) {
            Thumbnail thumbnail = (Thumbnail) item;
            if (thumbnail.get_photo_id().id == photo_id.id) {
                thumbnail.on_backing_changed();
                
                break;
            }
        }
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
        
        foreach (LayoutItem item in get_items()) {
            ((Thumbnail) item).resize(scale);
        }
        
        refresh();
        
        schedule_thumbnail_improval();
    }
    
    private bool reschedule_improval = false;

    private void schedule_thumbnail_improval() {
        // don't bother if not in view
        if (!in_view)
            return;
            
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

        foreach (LayoutItem item in get_items()) {
            Thumbnail thumbnail = (Thumbnail) item;
            if (thumbnail.is_exposed()) {
                thumbnail.paint_high_quality();
            }
        }
        
        improval_scheduled = false;
        
        debug("improve_thumbnail_quality");
        
        return false;
    }

    private void on_edit_menu() {
        set_item_sensitive("/CollectionMenuBar/EditMenu/SelectAll", get_count() > 0);
        set_item_sensitive("/CollectionMenuBar/EditMenu/Remove", get_selected_count() > 0);
    }
    
    private void on_select_all() {
        select_all();
    }
    
    protected virtual void on_photos_menu() {
        bool selected = (get_selected_count() > 0);
        
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/IncreaseSize", scale < Thumbnail.MAX_SCALE);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/DecreaseSize", scale > Thumbnail.MIN_SCALE);
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

    private void on_remove() {
        // iterate over selected and remove them from cache and databases
        foreach (LayoutItem item in get_selected()) {
            Thumbnail thumbnail = (Thumbnail) item;
            AppWindow.get_instance().remove_photo(thumbnail.get_photo_id(), this);
        }
        
        remove_selected();

        refresh();
    }
    
    private delegate Exif.Orientation RotationFunc(Exif.Orientation orientation);
    
    private void do_rotations(string desc, Gee.Iterable<LayoutItem> c, RotationFunc rotate) {
        bool rotationPerformed = false;
        foreach (LayoutItem item in c) {
            Thumbnail thumbnail = (Thumbnail) item;

            File file = thumbnail.get_file();
            PhotoExif exif = PhotoExif.create(file);
            
            Exif.Orientation orientation = exif.get_orientation();
            Exif.Orientation rotated = rotate(orientation);

            debug("Rotating %s %s from %s to %s", desc, thumbnail.get_file().get_path(),
                orientation.get_description(), rotated.get_description());
            
            // update file itself
            exif.set_orientation(rotated);
            
            // TODO: Write this in background
            try {
                exif.commit();
            } catch (Error err) {
                error("%s", err.message);
            }
            
            // update database
            photo_table.set_orientation(thumbnail.get_photo_id(), rotated);
            
            // update everyone who cares (including this thumbnail)
            AppWindow.get_instance().report_backing_changed(thumbnail.get_photo_id());

            rotationPerformed = true;
        }
        
        if (rotationPerformed) {
            schedule_thumbnail_improval();
            refresh();
        }
    }

    private void on_rotate_clockwise() {
        do_rotations("clockwise", get_selected(), (orientation) => {
            return orientation.rotate_clockwise();
        });
    }
    
    private void on_rotate_counterclockwise() {
        do_rotations("counterclockwise", get_selected(), (orientation) => {
            return orientation.rotate_counterclockwise();
        });
    }
    
    private void on_mirror() {
        do_rotations("mirror", get_selected(), (orientation) => {
            return orientation.flip_left_to_right();
        });
    }
    
    private void on_view_menu() {
        set_item_sensitive("/CollectionMenuBar/ViewMenu/Fullscreen", get_count() > 0);
    }
    
    private bool display_titles() {
        Gtk.ToggleAction action = (Gtk.ToggleAction) ui.get_action("/CollectionMenuBar/ViewMenu/ViewTitle");
        
        return action.get_active();
    }
    
    private void on_display_titles(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        foreach (LayoutItem item in get_items()) {
            item.display_title(display);
        }
        
        refresh();
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
    
    private int get_sort_criteria() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action("/CollectionMenuBar/ViewMenu/SortPhotos/SortByName");
        assert(action != null);
        
        int value = action.get_current_value();
        assert(value >= SORT_BY_MIN);
        assert(value <= SORT_BY_MAX);
        
        return value;
    }
    
    private int get_sort_order() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action("/CollectionMenuBar/ViewMenu/SortPhotos/SortAscending");
        assert(action != null);
        
        int value = action.get_current_value();
        assert(value >= SORT_ORDER_MIN);
        assert(value <= SORT_ORDER_MAX);
        
        return value;
    }
    
    private class CompareName : Comparator<LayoutItem> {
        public override int64 compare(LayoutItem a, LayoutItem b) {
            return strcmp(((Thumbnail) a).get_name(), ((Thumbnail) b).get_name());
        }
    }
    
    private class ReverseCompareName : Comparator<LayoutItem> {
        public override int64 compare(LayoutItem a, LayoutItem b) {
            return strcmp(((Thumbnail) b).get_name(), ((Thumbnail) a).get_name());
        }
    }
    
    private class CompareDate : Comparator<LayoutItem> {
        public override int64 compare(LayoutItem a, LayoutItem b) {
            return ((Thumbnail) a).get_exposure_time() - ((Thumbnail) b).get_exposure_time();
        }
    }
    
    private class ReverseCompareDate : Comparator<LayoutItem> {
        public override int64 compare(LayoutItem a, LayoutItem b) {
            return ((Thumbnail) b).get_exposure_time() - ((Thumbnail) a).get_exposure_time();
        }
    }

    private void on_sort_changed() {
        Comparator<LayoutItem> cmp = null;
        switch (get_sort_criteria()) {
            case SORT_BY_NAME: {
                if (get_sort_order() == SORT_ORDER_ASCENDING) {
                    cmp = new CompareName();
                } else {
                    cmp = new ReverseCompareName();
                }
            } break;
            
            case SORT_BY_EXPOSURE_DATE: {
                if (get_sort_order() == SORT_ORDER_ASCENDING) {
                    cmp = new CompareDate();
                } else {
                    cmp = new ReverseCompareDate();
                }
            } break;
        }
        
        if (cmp == null)
            return;
        
        set_layout_comparator(cmp);
        refresh();
    }
}

