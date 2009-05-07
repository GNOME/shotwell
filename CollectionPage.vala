
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
    public static const int SLIDER_STEPPING = 2;

    private static const int IMPROVAL_PRIORITY = Priority.LOW;
    private static const int IMPROVAL_DELAY_MS = 250;
    
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.HScale slider = null;
    private Gtk.ToolButton rotate_button = null;
    private int scale = Thumbnail.DEFAULT_SCALE;
    private bool improval_scheduled = false;
    private bool in_view = false;
    private int last_width = 0;
    private int last_height = 0;
    private bool reschedule_improval = false;

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
    
    public CollectionPage(string? ui_filename = null, Gtk.ActionEntry[]? child_actions = null) {
        base("Photos");
        
        init_ui_start("collection.ui", "CollectionActionGroup", ACTIONS, TOGGLE_ACTIONS);
        action_group.add_radio_actions(SORT_CRIT_ACTIONS, SORT_BY_NAME, on_sort_changed);
        action_group.add_radio_actions(SORT_ORDER_ACTIONS, SORT_ORDER_ASCENDING, on_sort_changed);

        if (ui_filename != null)
            init_load_ui(ui_filename);
        
        if (child_actions != null)
            action_group.add_actions(child_actions, this);
        
        init_ui_bind("/CollectionMenuBar");
        init_context_menu("/CollectionContextMenu");
        
        set_layout_comparator(new CompareName());
        
        // set up page's toolbar (used by AppWindow for layout)
        //
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(STOCK_CLOCKWISE);
        rotate_button.label = "Rotate";
        rotate_button.sensitive = false;
        rotate_button.clicked += on_rotate_clockwise;
        
        toolbar.insert(rotate_button, -1);
        
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
        
        // turn this off until we're switched to
        set_refresh_on_resize(false);

        refresh();

        show_all();

        schedule_thumbnail_improval();
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void switching_from() {
        in_view = false;
        set_refresh_on_resize(false);
    }
    
    public override void switched_to() {
        in_view = true;
        set_refresh_on_resize(true);
        
        // need to refresh the layout in case any of the thumbnail dimensions were altered while we
        // were gone
        refresh();
        
        // schedule improvement in case any new photos were added
        schedule_thumbnail_improval();
    }
    
    protected override void on_selection_changed(int count) {
        rotate_button.sensitive = (count > 0);
    }
    
    protected override void on_item_activated(LayoutItem item) {
        Thumbnail thumbnail = (Thumbnail) item;
        
        // switch to full-page view
        debug("switching to %s", thumbnail.get_photo().to_string());

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
        foreach (LayoutItem item in iter)
            return item;
        
        return null;
    }
    
    protected override bool on_resize(Gdk.Rectangle rect) {
        // this schedules thumbnail improvement whenever the window size changes (and new thumbnails
        // may be exposed), therefore, uninterested in window position move
        if ((last_width != rect.width) || (last_height != rect.height)) {
            last_width = rect.width;
            last_height = rect.height;

            schedule_thumbnail_improval();
        }
        
        return false;
    }

    public void add_photo(Photo photo) {
        photo.removed += on_photo_removed;
        photo.altered += on_photo_altered;
        
        Thumbnail thumbnail = new Thumbnail(photo, scale);
        thumbnail.display_title(display_titles());
        
        add_item(thumbnail);
    }
    
    private void on_photo_removed(Photo photo) {
        debug("%s on_photo_removed", get_name());
        
        Thumbnail found = null;
        foreach (LayoutItem item in get_items()) {
            Thumbnail thumbnail = (Thumbnail) item;
            if (thumbnail.get_photo().equals(photo)) {
                found = thumbnail;
                
                break;
            }
        }
        
        // have to remove outside of iterator
        if (found != null) {
            debug("Removing %s from %s", photo.to_string(), get_name());
            remove_item(found);
        }
    }
    
    private void on_photo_altered(Photo photo) {
        debug("on_photo_altered");
        
        // the thumbnail is only going to reload a low-quality interp, so schedule improval
        schedule_thumbnail_improval();
        
        // since the geometry might have changed, refresh the layout
        if (in_view)
            refresh();
    }
    
    public int increase_thumb_size() {
        if (scale == Thumbnail.MAX_SCALE)
            return scale;
        
        scale += MANUAL_STEPPING;
        if (scale > Thumbnail.MAX_SCALE)
            scale = Thumbnail.MAX_SCALE;
        
        set_thumb_size(scale);
        
        return scale;
    }
    
    public int decrease_thumb_size() {
        if (scale == Thumbnail.MIN_SCALE)
            return scale;
        
        scale -= MANUAL_STEPPING;
        if (scale < Thumbnail.MIN_SCALE)
            scale = Thumbnail.MIN_SCALE;
        
        set_thumb_size(scale);

        return scale;
    }
    
    public void set_thumb_size(int newScale) {
        assert(newScale >= Thumbnail.MIN_SCALE);
        assert(newScale <= Thumbnail.MAX_SCALE);
        
        scale = newScale;
        
        foreach (LayoutItem item in get_items())
            ((Thumbnail) item).resize(scale);
        
        refresh();
        
        schedule_thumbnail_improval();
    }
    
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
            if (thumbnail.is_exposed())
                thumbnail.paint_high_quality();
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
        // iterate over selected photos and remove them from entire system .. this will result
        // in them being removed from this view in on_photo_removed
        foreach (LayoutItem item in get_selected())
            ((Thumbnail) item).get_photo().remove();
        
        refresh();
    }
    
    private void do_rotations(Gee.Iterable<LayoutItem> c, Photo.Rotation rotation) {
        bool rotation_performed = false;
        foreach (LayoutItem item in c) {
            Photo photo = ((Thumbnail) item).get_photo();
            photo.rotate(rotation);
            
            rotation_performed = true;
        }
        
        // geometry could've changed
        if (rotation_performed)
            refresh();
    }

    private void on_rotate_clockwise() {
        do_rotations(get_selected(), Photo.Rotation.CLOCKWISE);
    }
    
    private void on_rotate_counterclockwise() {
        do_rotations(get_selected(), Photo.Rotation.COUNTERCLOCKWISE);
    }
    
    private void on_mirror() {
        do_rotations(get_selected(), Photo.Rotation.MIRROR);
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
        
        foreach (LayoutItem item in get_items())
            item.display_title(display);
        
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
        rotate_button.set_stock_id(STOCK_COUNTERCLOCKWISE);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotate_button.set_stock_id(STOCK_CLOCKWISE);
        rotate_button.clicked -= on_rotate_counterclockwise;
        rotate_button.clicked += on_rotate_clockwise;
        
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
            return ((Thumbnail) a).get_photo().get_exposure_time() - ((Thumbnail) b).get_photo().get_exposure_time();
        }
    }
    
    private class ReverseCompareDate : Comparator<LayoutItem> {
        public override int64 compare(LayoutItem a, LayoutItem b) {
            return ((Thumbnail) b).get_photo().get_exposure_time() - ((Thumbnail) a).get_photo().get_exposure_time();
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

