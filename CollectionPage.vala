
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
    
    private class CompareName : Comparator<LayoutItem> {
        public override int64 compare(LayoutItem a, LayoutItem b) {
            string namea = ((Thumbnail) a).get_title();
            string nameb = ((Thumbnail) b).get_title();
            
            return strcmp(namea, nameb);
        }
    }
    
    private class ReverseCompareName : Comparator<LayoutItem> {
        public override int64 compare(LayoutItem a, LayoutItem b) {
            string namea = ((Thumbnail) a).get_title();
            string nameb = ((Thumbnail) b).get_title();
            
            return strcmp(nameb, namea);
        }
    }
    
    private class CompareDate : Comparator<LayoutItem> {
        public override int64 compare(LayoutItem a, LayoutItem b) {
            time_t timea = ((Thumbnail) a).get_photo().get_exposure_time();
            time_t timeb = ((Thumbnail) b).get_photo().get_exposure_time();
            
            return timea - timeb;
        }
    }
    
    private class ReverseCompareDate : Comparator<LayoutItem> {
        public override int64 compare(LayoutItem a, LayoutItem b) {
            time_t timea = ((Thumbnail) a).get_photo().get_exposure_time();
            time_t timeb = ((Thumbnail) b).get_photo().get_exposure_time();
            
            return timeb - timea;
        }
    }
    
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.HScale slider = null;
    private Gtk.ToolButton rotate_button = null;
    private int scale = Thumbnail.DEFAULT_SCALE;
    private bool improval_scheduled = false;
    private bool in_view = false;
    private bool reschedule_improval = false;
    private Gee.ArrayList<File> drag_items = new Gee.ArrayList<File>();

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, on_file_menu },
        { "Export", null, "_Export", "<Ctrl>E", "Export selected photos to disk", on_export },

        { "EditMenu", null, "_Edit", null, null, on_edit_menu },
        { "SelectAll", Gtk.STOCK_SELECT_ALL, "Select _All", "<Ctrl>A", "Select all the photos in the library", on_select_all },
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove },
        
        { "PhotosMenu", null, "_Photos", null, null, on_photos_menu },
        { "IncreaseSize", Gtk.STOCK_ZOOM_IN, "Zoom _In", "bracketright", "Increase the magnification of the thumbnails", on_increase_size },
        { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, "Zoom _Out", "bracketleft", "Decrease the magnification of the thumbnails", on_decrease_size },
        { "RotateClockwise", Resources.STOCK_CLOCKWISE, "Rotate _Right", "<Ctrl>R", "Rotate the selected photos clockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", Resources.STOCK_COUNTERCLOCKWISE, "Rotate _Left", "<Ctrl><Shift>R", "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", null, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", on_mirror },
        { "Revert", Gtk.STOCK_REVERT_TO_SAVED, "Re_vert to Original", null, "Revert to original photo", on_revert },
        
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
        rotate_button = new Gtk.ToolButton.from_stock(Resources.STOCK_CLOCKWISE);
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
        slider = new Gtk.HScale.with_range(0, scale_to_slider(Thumbnail.MAX_SCALE), 1);
        slider.set_value(scale_to_slider(scale));
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

        enable_drag_source(Gdk.DragAction.COPY);
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
    
    public override void returning_from_fullscreen() {
        refresh();
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
    
    protected override bool on_context_invoked(Gtk.Menu context_menu) {
        bool selected = (get_selected_count() > 0);
        bool revert_possible = can_revert_selected();
        
        set_item_sensitive("/CollectionContextMenu/ContextRemove", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRotateClockwise", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRotateCounterclockwise", selected);
        set_item_sensitive("/CollectionContextMenu/ContextMirror", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRevert", selected && revert_possible);
        
        return true;
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
    
    protected override void on_resize(Gdk.Rectangle rect) {
        // this schedules thumbnail improvement whenever the window size changes (and new thumbnails
        // may be exposed), therefore, uninterested in window position move
        schedule_thumbnail_improval();
    }
    
    private override void drag_begin(Gdk.DragContext context) {
        if (get_selected_count() == 0)
            return;
        
        drag_items.clear();

        // because drag_data_get may be called multiple times in a single drag, prepare all the exported
        // files first
        Gdk.Pixbuf icon = null;
        foreach (LayoutItem item in get_selected()) {
            Photo photo = ((Thumbnail) item).get_photo();
            
            File file = null;
            try {
                file = photo.generate_exportable();
            } catch (Error err) {
                error("%s", err.message);
            }
            
            drag_items.add(file);
            
            // set up icon using the "first" photo, although Sets are not ordered
            if (icon == null)
                icon = photo.get_thumbnail(ThumbnailCache.MEDIUM_SCALE);
            
            debug("Prepared %s for export", file.get_path());
        }
        
        assert(icon != null);
        Gtk.drag_source_set_icon_pixbuf(get_event_source(), icon);
    }
    
    private override void drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint target_type, uint time) {
        assert(target_type == TargetType.URI_LIST);
        
        if (drag_items.size == 0)
            return;
        
        // prepare list of uris
        string[] uris = new string[drag_items.size];
        int ctr = 0;
        foreach (File file in drag_items)
            uris[ctr++] = file.get_uri();
        
        selection_data.set_uris(uris);
    }
    
    private override void drag_end(Gdk.DragContext context) {
        drag_items.clear();
    }
    
    private override bool source_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        debug("Drag failed: %d", (int) drag_result);
        
        drag_items.clear();
        
        return false;
    }
    
    public void add_photo(Photo photo) {
        // search for duplicates
        if (get_thumbnail_for_photo(photo) != null)
            return;
        
        photo.removed += on_photo_removed;
        photo.thumbnail_altered += on_thumbnail_altered;
        
        Thumbnail thumbnail = new Thumbnail(photo, scale);
        thumbnail.display_title(display_titles());
        
        add_item(thumbnail);
    }
    
    private void on_photo_removed(Photo photo) {
        Thumbnail found = get_thumbnail_for_photo(photo);
        if (found != null)
            remove_item(found);
    }
    
    private void on_thumbnail_altered(Photo photo) {
        // the thumbnail is only going to reload a low-quality interp, so schedule improval
        schedule_thumbnail_improval();
        
        // since the geometry might have changed, refresh the layout
        if (in_view)
            refresh();
    }
    
    private Thumbnail? get_thumbnail_for_photo(Photo photo) {
        foreach (LayoutItem item in get_items()) {
            Thumbnail thumbnail = (Thumbnail) item;
            if (thumbnail.get_photo().equals(photo))
                return thumbnail;
        }
        
        return null;
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
    
    public void set_thumb_size(int new_scale) {
        assert(new_scale >= Thumbnail.MIN_SCALE);
        assert(new_scale <= Thumbnail.MAX_SCALE);
        
        scale = new_scale;
        
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
    
    private void on_file_menu() {
        set_item_sensitive("/CollectionMenuBar/FileMenu/Export", get_selected_count() > 0);
    }
    
    private void on_export() {
        Gee.ArrayList<Photo> export_list = new Gee.ArrayList<Photo>();
        foreach (LayoutItem item in get_selected())
            export_list.add(((Thumbnail) item).get_photo());

        if (export_list.size == 0)
            return;
            
        ExportDialog export_dialog = new ExportDialog(export_list.size);
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        if (!export_dialog.execute(out scale, out constraint, out quality))
            return;

        // handle the single-photo case
        if (export_list.size == 1) {
            Photo photo = export_list.get(0);
            
            File save_as = ExportUI.choose_file(photo.get_file());
            if (save_as == null)
                return;
                
            spin_event_loop();
            
            try {
                photo.export(save_as, scale, constraint, quality);
            } catch (Error err) {
                AppWindow.error_message("Unable to export photo %s: %s".printf(
                    photo.get_file().get_path(), err.message));
            }
            
            return;
        }

        // multiple photos
        File export_dir = ExportUI.choose_dir();
        if (export_dir == null)
            return;
        
        AppWindow.get_instance().set_busy_cursor();
        
        foreach (Photo photo in export_list) {
            File save_as = export_dir.get_child(photo.get_file().get_basename());
            if (save_as.query_exists(null)) {
                if (!ExportUI.query_overwrite(save_as))
                    continue;
            }
            
            spin_event_loop();

            try {
                photo.export(save_as, scale, constraint, quality);
            } catch (Error err) {
                AppWindow.error_message("Unable to export photo %s: %s".printf(save_as.get_path(),
                    err.message));
            }
        }
        
        AppWindow.get_instance().set_normal_cursor();
    }

    private void on_edit_menu() {
        set_item_sensitive("/CollectionMenuBar/EditMenu/SelectAll", get_count() > 0);
        set_item_sensitive("/CollectionMenuBar/EditMenu/Remove", get_selected_count() > 0);
    }
    
    private void on_select_all() {
        select_all();
    }
    
    private bool can_revert_selected() {
        foreach (LayoutItem item in get_selected()) {
            Photo photo = ((Thumbnail) item).get_photo();
            if (photo.has_transformations())
                return true;
        }
        
        return false;
    }
    
    protected virtual void on_photos_menu() {
        bool selected = (get_selected_count() > 0);
        bool revert_possible = can_revert_selected();
        
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/IncreaseSize", scale < Thumbnail.MAX_SCALE);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/DecreaseSize", scale > Thumbnail.MIN_SCALE);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateClockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateCounterclockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Mirror", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Revert", selected && revert_possible);
    }

    private void on_increase_size() {
        increase_thumb_size();
        slider.set_value(scale_to_slider(scale));
    }

    private void on_decrease_size() {
        decrease_thumb_size();
        slider.set_value(scale_to_slider(scale));
    }

    private void on_remove() {
        // iterate over selected photos and remove them from entire system .. this will result
        // in on_photo_removed being called, which we don't want in this case is because it will
        // remove from the list while iterating, so disconnect the signals and do the work here
        foreach (LayoutItem item in get_selected()) {
            Photo photo = ((Thumbnail) item).get_photo();
            photo.removed -= on_photo_removed;
            photo.thumbnail_altered -= on_thumbnail_altered;
            
            photo.remove();
        }
        
        // now remove from page, outside of iterator
        remove_selected();
        
        refresh();
    }
    
    private void do_rotations(Gee.Iterable<LayoutItem> c, Rotation rotation) {
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
        do_rotations(get_selected(), Rotation.CLOCKWISE);
    }
    
    private void on_rotate_counterclockwise() {
        do_rotations(get_selected(), Rotation.COUNTERCLOCKWISE);
    }
    
    private void on_mirror() {
        do_rotations(get_selected(), Rotation.MIRROR);
    }
    
    private void on_revert() {
        bool revert_performed = false;
        foreach (LayoutItem item in get_selected()) {
            Photo photo = ((Thumbnail) item).get_photo();
            photo.remove_all_transformations();
            
            revert_performed = true;
        }
        
        // geometry could change
        if (revert_performed)
            refresh();
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
    
    private static double scale_to_slider(int value) {
        assert(value >= Thumbnail.MIN_SCALE);
        assert(value <= Thumbnail.MAX_SCALE);
        
        return (double) ((value - Thumbnail.MIN_SCALE) / SLIDER_STEPPING);
    }
    
    private static int slider_to_scale(double value) {
        int res = ((int) (value * SLIDER_STEPPING)) + Thumbnail.MIN_SCALE;

        assert(res >= Thumbnail.MIN_SCALE);
        assert(res <= Thumbnail.MAX_SCALE);
        
        return res;
    }
    
    private void on_slider_changed() {
        set_thumb_size(slider_to_scale(slider.get_value()));
    }
    
    private override bool on_ctrl_pressed(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.STOCK_COUNTERCLOCKWISE);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.STOCK_CLOCKWISE);
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
    
    private void on_sort_changed() {
        Comparator<LayoutItem> cmp = null;
        switch (get_sort_criteria()) {
            case SORT_BY_NAME:
                if (get_sort_order() == SORT_ORDER_ASCENDING)
                    cmp = new CompareName();
                else
                    cmp = new ReverseCompareName();
            break;
            
            case SORT_BY_EXPOSURE_DATE:
                if (get_sort_order() == SORT_ORDER_ASCENDING)
                    cmp = new CompareDate();
                else
                    cmp = new ReverseCompareDate();
            break;
            
            default:
                error("Unknown sort criteria: %d", get_sort_criteria());
            break;
        }
        
        if (cmp == null)
            return;
        
        set_layout_comparator(cmp);
        refresh();
    }
}

