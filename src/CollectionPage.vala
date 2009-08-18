/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

class SlideshowPage : SinglePhotoPage {
    public const int DELAY_SEC = 3;
    
    private const int CHECK_ADVANCE_MSEC = 250;
    
    private CheckerboardPage controller;
    private Thumbnail thumbnail;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton play_pause_button;
    private Timer timer = new Timer();
    private bool playing = true;
    private bool exiting = false;
    
    public SlideshowPage(CheckerboardPage controller, Thumbnail start) {
        base("Slideshow");
        
        this.controller = controller;
        this.thumbnail = start;
        
        set_default_interp(QUALITY_INTERP);
        
        // add toolbar buttons
        Gtk.ToolButton previous_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
        previous_button.set_label("Back");
        previous_button.set_tooltip_text("Go to the previous photo");
        previous_button.clicked += on_previous_manual;
        
        toolbar.insert(previous_button, -1);
        
        play_pause_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PAUSE);
        play_pause_button.set_label("Pause");
        play_pause_button.set_tooltip_text("Pause the slideshow");
        play_pause_button.clicked += on_play_pause;
        
        toolbar.insert(play_pause_button, -1);
        
        Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
        next_button.set_label("Next");
        next_button.set_tooltip_text("Go to the next photo");
        next_button.clicked += on_next_manual;
        
        toolbar.insert(next_button, -1);
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void switched_to() {
        base.switched_to();

        set_pixbuf(thumbnail.get_photo().get_pixbuf(TransformablePhoto.SCREEN));

        Timeout.add(CHECK_ADVANCE_MSEC, auto_advance);
        timer.start();
    }
    
    public override void switching_from() {
        base.switching_from();

        exiting = true;
    }
    
    private void on_play_pause() {
        if (playing) {
            play_pause_button.set_stock_id(Gtk.STOCK_MEDIA_PLAY);
            play_pause_button.set_label("Play");
            play_pause_button.set_tooltip_text("Continue the slideshow");
        } else {
            play_pause_button.set_stock_id(Gtk.STOCK_MEDIA_PAUSE);
            play_pause_button.set_label("Pause");
            play_pause_button.set_tooltip_text("Pause the slideshow");
        }
        
        playing = !playing;
        
        // reset the timer
        timer.start();
    }
    
    private void on_previous_manual() {
        manual_advance((Thumbnail) controller.get_previous_item(thumbnail));
    }
    
    private void on_next_automatic() {
        thumbnail = (Thumbnail) controller.get_next_item(thumbnail);
        
        set_pixbuf(thumbnail.get_photo().get_pixbuf(TransformablePhoto.SCREEN));
        
        // reset the timer
        timer.start();
    }
    
    private void on_next_manual() {
        manual_advance((Thumbnail) controller.get_next_item(thumbnail));
    }
    
    private void manual_advance(Thumbnail thumbnail) {
        this.thumbnail = thumbnail;
        
        // start with blown-up preview
        set_pixbuf(thumbnail.get_photo().get_preview_pixbuf(TransformablePhoto.SCREEN));
        
        // schedule improvement to real photo
        Idle.add(on_improvement);
        
        // reset the advance timer
        timer.start();
    }
    
    private bool on_improvement() {
        set_pixbuf(thumbnail.get_photo().get_pixbuf(TransformablePhoto.SCREEN));
        
        return false;
    }
    
    private bool auto_advance() {
        if (exiting)
            return false;
        
        if (!playing)
            return true;
        
        if ((int) timer.elapsed() < DELAY_SEC)
            return true;
        
        on_next_automatic();
        
        return true;
    }
    
    private override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "space":
                on_play_pause();
            break;
            
            case "Left":
            case "KP_Left":
                on_previous_manual();
            break;
            
            case "Right":
            case "KP_Right":
                on_next_manual();
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled)
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : true;
    }

    public override int get_queryable_count() {
        return 1;
    }

    public override int get_selected_queryable_count() {
        return get_queryable_count();
    }

    public override Gee.Iterable<Queryable>? get_queryables() {
        Gee.ArrayList<LibraryPhoto> photo_array_list = new Gee.ArrayList<LibraryPhoto>();
        photo_array_list.add(thumbnail.get_photo());
        return photo_array_list;
    }

    public override Gee.Iterable<Queryable>? get_selected_queryables() {
        return get_queryables();
    }
}

public class CollectionPage : CheckerboardPage {
    public const int SORT_BY_MIN = 0;
    public const int SORT_BY_NAME = 0;
    public const int SORT_BY_EXPOSURE_DATE = 1;
    public const int SORT_BY_MAX = 1;
    
    public const int SORT_ORDER_MIN = 0;
    public const int SORT_ORDER_ASCENDING = 0;
    public const int SORT_ORDER_DESCENDING = 1;
    public const int SORT_ORDER_MAX = 1;
    
    public const int DEFAULT_SORT_BY = SORT_BY_EXPOSURE_DATE;
    public const int DEFAULT_SORT_ORDER = SORT_ORDER_DESCENDING;

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public const int MANUAL_STEPPING = 16;
    public const int SLIDER_STEPPING = 2;

    private const int IMPROVAL_PRIORITY = Priority.LOW;
    private const int IMPROVAL_DELAY_MS = 250;
    
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
    
    private class InternalPhotoCollection : Object, PhotoCollection {
        private CollectionPage page;
        
        public InternalPhotoCollection(CollectionPage page) {
            this.page = page;
        }
        
        public int get_count() {
            return page.get_count();
        }
        
        public PhotoBase? get_first_photo() {
            Thumbnail? thumbnail = (Thumbnail) page.get_first_item();
            
            return (thumbnail != null) ? thumbnail.get_photo() : null;
        }
        
        public PhotoBase? get_last_photo() {
            Thumbnail? thumbnail = (Thumbnail) page.get_last_item();
            
            return (thumbnail != null) ? thumbnail.get_photo() : null;
        }
        
        public PhotoBase? get_next_photo(PhotoBase current) {
            Thumbnail? thumbnail = page.get_thumbnail_for_photo((LibraryPhoto) current);
            if (thumbnail == null)
                return null;

            thumbnail = (Thumbnail) page.get_next_item(thumbnail);
            
            return (thumbnail != null) ? thumbnail.get_photo() : null;
        }
        
        public PhotoBase? get_previous_photo(PhotoBase current) {
            Thumbnail? thumbnail = page.get_thumbnail_for_photo((LibraryPhoto) current);
            if (thumbnail == null)
                return null;
            
            thumbnail = (Thumbnail) page.get_previous_item(thumbnail);
            
            return (thumbnail != null) ? thumbnail.get_photo() : null;
        }
    }
    
    private static Gtk.Adjustment slider_adjustment = null;
    
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.HScale slider = null;
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToolButton slideshow_button = null;
    private int scale = Thumbnail.DEFAULT_SCALE;
    private bool improval_scheduled = false;
    private bool reschedule_improval = false;
    private Gee.ArrayList<File> drag_items = new Gee.ArrayList<File>();
    private bool thumbs_resized = false;

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, on_file_menu },
        { "Export", Gtk.STOCK_SAVE_AS, "_Export Photos...", "<Ctrl>E", "Export selected photos to disk", on_export },

        { "EditMenu", null, "_Edit", null, null, on_edit_menu },
        { "SelectAll", Gtk.STOCK_SELECT_ALL, "Select _All", "<Ctrl>A", "Select all the photos in the library", on_select_all },
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove },
        
        { "PhotosMenu", null, "_Photos", null, null, on_photos_menu },
        { "IncreaseSize", Gtk.STOCK_ZOOM_IN, "Zoom _In", "bracketright", "Increase the magnification of the thumbnails", on_increase_size },
        { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, "Zoom _Out", "bracketleft", "Decrease the magnification of the thumbnails", on_decrease_size },
        { "RotateClockwise", Resources.CLOCKWISE, "Rotate _Right", "<Ctrl>R", "Rotate the selected photos clockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE, "Rotate _Left", "<Ctrl><Shift>R", "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", Resources.MIRROR, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", on_mirror },
        { "Revert", Gtk.STOCK_REVERT_TO_SAVED, "Re_vert to Original", null, "Revert to original photo", on_revert },
        { "Slideshow", Gtk.STOCK_MEDIA_PLAY, "_Slideshow", "F5", "Play a slideshow", on_slideshow },
        
        { "ViewMenu", null, "_View", null, null, on_view_menu },
        { "SortPhotos", null, "Sort _Photos", null, null, null },
        
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
        { "SortAscending", Gtk.STOCK_SORT_ASCENDING, "_Ascending", null, "Sort photos in an ascending order", SORT_ORDER_ASCENDING },
        { "SortDescending", Gtk.STOCK_SORT_DESCENDING, "D_escending", null, "Sort photos in a descending order", SORT_ORDER_DESCENDING }
    };
    
    public CollectionPage(string? page_name = null, string? ui_filename = null, 
        Gtk.ActionEntry[]? child_actions = null) {
        base(page_name != null ? page_name : "Photos");
        
        init_ui_start("collection.ui", "CollectionActionGroup", ACTIONS, TOGGLE_ACTIONS);
        action_group.add_radio_actions(SORT_CRIT_ACTIONS, DEFAULT_SORT_BY, on_sort_changed);
        action_group.add_radio_actions(SORT_ORDER_ACTIONS, DEFAULT_SORT_ORDER, on_sort_changed);

        if (ui_filename != null)
            init_load_ui(ui_filename);
        
        if (child_actions != null)
            action_group.add_actions(child_actions, this);
        
        init_ui_bind("/CollectionMenuBar");
        init_context_menu("/CollectionContextMenu");
        
        set_layout_comparator(get_sort_comparator());
        
        // adjustment which is shared by all sliders in the application
        if (slider_adjustment == null)
            slider_adjustment = new Gtk.Adjustment(scale_to_slider(scale), 0, 
                scale_to_slider(Thumbnail.MAX_SCALE), 1, 10, 0);
        
        // set up page's toolbar (used by AppWindow for layout)
        //
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CLOCKWISE_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CLOCKWISE_TOOLTIP);
        rotate_button.sensitive = false;
        rotate_button.clicked += on_rotate_clockwise;
        
        toolbar.insert(rotate_button, -1);
        
        // slideshow button
        slideshow_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PLAY);
        slideshow_button.set_label("Slideshow");
        slideshow_button.set_tooltip_text("Start a slideshow of these photos");
        slideshow_button.sensitive = false;
        slideshow_button.clicked += on_slideshow;
        
        toolbar.insert(slideshow_button, -1);
        
        // separator to force slider to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // thumbnail size slider
        slider = new Gtk.HScale(slider_adjustment);
        slider.value_changed += on_slider_changed;
        slider.set_draw_value(false);

        Gtk.ToolItem toolitem = new Gtk.ToolItem();
        toolitem.add(slider);
        toolitem.set_expand(false);
        toolitem.set_size_request(200, -1);
        toolitem.set_tooltip_text("Adjust the size of the thumbnails");
        
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
        base.switching_from();

        set_refresh_on_resize(false);
    }
    
    public override void switched_to() {
        base.switched_to();

        set_refresh_on_resize(true);
        
        // if the thumbnails were resized while viewing another page, resize the ones on this page
        // now ... set_thumb_size does the refresh and thumbnail improval, so don't schedule if
        // going this route
        if (thumbs_resized) {
            set_thumb_size(slider_to_scale(slider.get_value()));
            thumbs_resized = false;
        } else {
            // need to refresh the layout in case any of the thumbnail dimensions were altered while we
            // were gone
            refresh();
            
            // schedule improvement in case any new photos were added
            schedule_thumbnail_improval();
        }
    }
    
    public override void returning_from_fullscreen() {
        refresh();
        
        base.returning_from_fullscreen();
    }
    
    protected override void on_selection_changed(int count) {
        rotate_button.sensitive = (count > 0);
    }
    
    protected override void on_item_activated(LayoutItem item) {
        Thumbnail thumbnail = (Thumbnail) item;
        
        // switch to full-page view
        debug("switching to %s", thumbnail.get_photo().to_string());

        LibraryWindow.get_app().switch_to_photo_page(this, thumbnail);
    }
    
    public override Gtk.Menu? get_context_menu() {
        // don't show a context menu if nothing is selected
        return (get_selected_count() != 0) ? base.get_context_menu() : null;
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
    
    public PhotoCollection get_photo_collection() {
        return new InternalPhotoCollection(this);
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
            LibraryPhoto photo = ((Thumbnail) item).get_photo();
            
            File file = null;
            try {
                file = photo.generate_exportable();
            } catch (Error err) {
                error("%s", err.message);
            }
            
            drag_items.add(file);
            
            // set up icon using the "first" photo, although Sets are not ordered
            if (icon == null)
                icon = photo.get_preview_pixbuf(AppWindow.DND_ICON_SCALE);
            
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
        
        foreach (LayoutItem item in get_selected()) {
            ((Thumbnail) item).get_photo().export_failed();
        }
        
        return false;
    }
    
    public void add_photo(LibraryPhoto photo) {
        // search for duplicates
        if (get_thumbnail_for_photo(photo) != null)
            return;
        
        photo.removed += on_photo_removed;
        photo.thumbnail_altered += on_thumbnail_altered;
        
        Thumbnail thumbnail = new Thumbnail(photo, scale);
        thumbnail.display_title(display_titles());
        
        add_item(thumbnail);
        
        slideshow_button.sensitive = true;
    }
    
    private void on_photo_removed(LibraryPhoto photo) {
        Thumbnail found = get_thumbnail_for_photo(photo);
        if (found != null)
            remove_item(found);
        
        slideshow_button.sensitive = (get_count() > 0);
    }
    
    private void on_thumbnail_altered(LibraryPhoto photo) {
        // TODO: use a different signal: e.g. contents_changed or photo_altered
        notify_selection_changed(get_selected_queryable_count());        

        // the thumbnail is only going to reload a low-quality interp, so schedule improval
        schedule_thumbnail_improval();
        
        // since the geometry might have changed, refresh the layout
        if (is_in_view())
            refresh();
    }
    
    private Thumbnail? get_thumbnail_for_photo(LibraryPhoto photo) {
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
        
        if (is_in_view()) {
            refresh();
            schedule_thumbnail_improval();
        }
    }
    
    private void schedule_thumbnail_improval() {
        // don't bother if not in view
        if (!is_in_view())
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
        Gee.ArrayList<LibraryPhoto> export_list = new Gee.ArrayList<LibraryPhoto>();
        foreach (LayoutItem item in get_selected())
            export_list.add(((Thumbnail) item).get_photo());

        if (export_list.size == 0)
            return;

        ExportDialog export_dialog = new ExportDialog(
            "Export Photo%s".printf(export_list.size > 1 ? "s" : ""));
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        if (!export_dialog.execute(out scale, out constraint, out quality))
            return;

        // handle the single-photo case
        if (export_list.size == 1) {
            LibraryPhoto photo = export_list.get(0);
            
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
        
        foreach (LibraryPhoto photo in export_list) {
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
            LibraryPhoto photo = ((Thumbnail) item).get_photo();
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
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Slideshow", get_count() > 0);
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
        if (get_selected_count() == 0)
            return;

        Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(), Gtk.DialogFlags.MODAL,
            Gtk.MessageType.WARNING, Gtk.ButtonsType.CANCEL,
            "If you remove these photos from your library you will lose all edits you've made to "
            + "them.  Shotwell can also delete the files from your drive.\n\nThis action cannot be undone.");
        dialog.add_button(Gtk.STOCK_DELETE, Gtk.ResponseType.NO);
        dialog.add_button("Keep files", Gtk.ResponseType.YES);
        dialog.title = "Remove photos?";

        Gtk.ResponseType result = (Gtk.ResponseType) dialog.run();
        
        dialog.destroy();
        
        if (result != Gtk.ResponseType.YES && result != Gtk.ResponseType.NO)
            return;
            
        // iterate over selected photos and remove them from entire system .. this will result
        // in on_photo_removed being called, which we don't want in this case is because it will
        // remove from the list while iterating, so disconnect the signals and do the work here
        foreach (LayoutItem item in get_selected()) {
            LibraryPhoto photo = ((Thumbnail) item).get_photo();
            photo.removed -= on_photo_removed;
            photo.thumbnail_altered -= on_thumbnail_altered;
            
            photo.remove(result == Gtk.ResponseType.NO);
        }
        
        // now remove from page, outside of iterator
        remove_selected();
        
        refresh();
    }
    
    private void do_rotations(Gee.Iterable<LayoutItem> c, Rotation rotation) {
        bool rotation_performed = false;
        foreach (LayoutItem item in c) {
            LibraryPhoto photo = ((Thumbnail) item).get_photo();
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
            LibraryPhoto photo = ((Thumbnail) item).get_photo();
            photo.remove_all_transformations();
            
            revert_performed = true;
        }
        
        // geometry could change
        if (revert_performed)
            refresh();
    }
    
    private void on_slideshow() {
        if (get_count() == 0)
            return;
            
        AppWindow.get_instance().go_fullscreen(new FullscreenWindow(new SlideshowPage(this,
            (Thumbnail) get_first_item())));
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
        if (!is_in_view()) {
            thumbs_resized = true;
            
            return;
        }
        
        set_thumb_size(slider_to_scale(slider.get_value()));
    }
    
    private override bool on_ctrl_pressed(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.COUNTERCLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_COUNTERCLOCKWISE_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_COUNTERCLOCKWISE_TOOLTIP);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CLOCKWISE_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CLOCKWISE_TOOLTIP);
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
    
    private bool is_sort_ascending() {
        return get_sort_order() == SORT_ORDER_ASCENDING;
    }
    
    private void on_sort_changed() {
        set_layout_comparator(get_sort_comparator());
        refresh();
    }
    
    private Comparator<LayoutItem> get_sort_comparator() {
        switch (get_sort_criteria()) {
            case SORT_BY_NAME:
                if (is_sort_ascending())
                    return new CompareName();
                else
                    return new ReverseCompareName();
            
            case SORT_BY_EXPOSURE_DATE:
                if (is_sort_ascending())
                    return new CompareDate();
                else
                    return new ReverseCompareDate();
            
            default:
                error("Unknown sort criteria: %d", get_sort_criteria());
                
                return new CompareName();
        }
    }
}

