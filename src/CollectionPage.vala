/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class CollectionViewManager : ViewManager {
    private CollectionPage page;
    
    public CollectionViewManager(CollectionPage page) {
        this.page = page;
    }
    
    public override DataView create_view(DataSource source) {
        return page.create_thumbnail((LibraryPhoto) source);
    }
}

public class CollectionPage : CheckerboardPage {
    public const int SORT_BY_MIN = 0;
    public const int SORT_BY_TITLE = 0;
    public const int SORT_BY_EXPOSURE_DATE = 1;
    public const int SORT_BY_MAX = 1;
    
    public const int SORT_ORDER_MIN = 0;
    public const int SORT_ORDER_ASCENDING = 0;
    public const int SORT_ORDER_DESCENDING = 1;
    public const int SORT_ORDER_MAX = 1;
    
    public const int DEFAULT_SORT_BY = SORT_BY_EXPOSURE_DATE;
    public const int DEFAULT_SORT_ORDER = SORT_ORDER_DESCENDING;
    
    public const int MIN_OPS_FOR_PROGRESS_WINDOW = 5;

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public const int MANUAL_STEPPING = 16;
    public const int SLIDER_STEPPING = 4;

    private class CompareTitle : Comparator<LayoutItem> {
        private bool ascending;
        
        public CompareTitle(bool ascending) {
            this.ascending = ascending;
        }
        
        public override int64 compare(LayoutItem a, LayoutItem b) {
            string titlea = ((Thumbnail) a).get_title();
            string titleb = ((Thumbnail) b).get_title();
            
            return (ascending) ? strcmp(titlea, titleb) : strcmp(titleb, titlea);
        }
    }
    
    private class CompareDate : Comparator<LayoutItem> {
        private bool ascending;
        
        public CompareDate(bool ascending) {
            this.ascending = ascending;
        }
        
        public override int64 compare(LayoutItem a, LayoutItem b) {
            time_t timea = ((Thumbnail) a).get_photo().get_exposure_time();
            time_t timeb = ((Thumbnail) b).get_photo().get_exposure_time();
            
            return (ascending) ? timea - timeb : timeb - timea;
        }
    }
    
    private static Gtk.Adjustment slider_adjustment = null;
    
    private Gtk.HScale slider = null;
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToolButton enhance_button = null;
    private Gtk.ToolButton slideshow_button = null;

#if !NO_PUBLISHING
    private Gtk.ToolButton publish_button = null;
#endif

    private int scale = Thumbnail.DEFAULT_SCALE;
    private Gee.ArrayList<File> drag_files = new Gee.ArrayList<File>();
    private Gee.ArrayList<LibraryPhoto> drag_photos = new Gee.ArrayList<LibraryPhoto>();
    private int drag_failed_item_count = 0;
    
    public CollectionPage(string page_name, string? ui_filename = null, 
        Gtk.ActionEntry[]? child_actions = null) {
        base(page_name);
        
        init_ui_start("collection.ui", "CollectionActionGroup", create_actions(),
            create_toggle_actions());
        action_group.add_radio_actions(create_sort_crit_actions(), DEFAULT_SORT_BY,
            on_sort_changed);
        action_group.add_radio_actions(create_sort_order_actions(), DEFAULT_SORT_ORDER,
            on_sort_changed);

        if (ui_filename != null)
            init_load_ui(ui_filename);
        
        if (child_actions != null)
            action_group.add_actions(child_actions, this);
        
        init_ui_bind("/CollectionMenuBar");
        init_item_context_menu("/CollectionContextMenu");
        
        get_view().set_comparator(get_sort_comparator());
        get_view().contents_altered += on_contents_altered;
        get_view().items_state_changed += on_selection_changed;
        get_view().items_visibility_changed += on_contents_altered;

        // adjustment which is shared by all sliders in the application
        if (slider_adjustment == null)
            slider_adjustment = new Gtk.Adjustment(scale_to_slider(scale), 0, 
                scale_to_slider(Thumbnail.MAX_SCALE), 1, 10, 0);
        
        // set up page's toolbar (used by AppWindow for layout)
        Gtk.Toolbar toolbar = get_toolbar();
        
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.sensitive = false;
        rotate_button.is_important = true;
        rotate_button.clicked += on_rotate_clockwise;
        
        toolbar.insert(rotate_button, -1);

        // enhance tool
        enhance_button = new Gtk.ToolButton.from_stock(Resources.ENHANCE);
        enhance_button.set_label(Resources.ENHANCE_LABEL);
        enhance_button.set_tooltip_text(Resources.ENHANCE_TOOLTIP);
        enhance_button.sensitive = false;
        enhance_button.is_important = true;
        enhance_button.clicked += on_enhance;

        toolbar.insert(enhance_button, -1);

        // separator
        toolbar.insert(new Gtk.SeparatorToolItem(), -1);
        
        // slideshow button
        slideshow_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PLAY);
        slideshow_button.set_label(_("Slideshow"));
        slideshow_button.set_tooltip_text(_("Start a slideshow of these photos"));
        slideshow_button.sensitive = false;
        slideshow_button.is_important = true;
        slideshow_button.clicked += on_slideshow;
        
        toolbar.insert(slideshow_button, -1);

#if !NO_PUBLISHING
        // publish button
        publish_button = new Gtk.ToolButton.from_stock(Resources.PUBLISH);
        publish_button.set_label(_("Publish"));
        publish_button.set_tooltip_text(_("Publish the selected photos to various websites"));
        publish_button.set_sensitive(false);
        publish_button.is_important = true;
        publish_button.clicked += on_publish;
        
        toolbar.insert(publish_button, -1);
#endif
        
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
        toolitem.set_tooltip_text(_("Adjust the size of the thumbnails"));
        
        toolbar.insert(toolitem, -1);
        
        // initialize scale from slider (since the scale adjustment may be modified from default)
        scale = slider_to_scale(slider.get_value());

        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        show_all();

        enable_drag_source(Gdk.DragAction.COPY);
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, on_file_menu };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry export = { "Export", Gtk.STOCK_SAVE_AS, TRANSLATABLE, "<Ctrl><Shift>E",
            TRANSLATABLE, on_export };
        export.label = _("_Export Photos...");
        export.tooltip = _("Export selected photos to disk");
        actions += export;

        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, on_edit_menu };
        edit.label = _("_Edit");
        actions += edit;
        
        Gtk.ActionEntry event = { "EventsMenu", null, TRANSLATABLE, null, null, on_events_menu };
        event.label = _("Even_ts");
        actions += event;

        Gtk.ActionEntry select_all = { "SelectAll", Gtk.STOCK_SELECT_ALL, TRANSLATABLE,
            "<Ctrl>A", TRANSLATABLE, on_select_all };
        select_all.label = _("Select _All");
        select_all.tooltip = _("Select all the photos in the library");
        actions += select_all;

        Gtk.ActionEntry remove = { "Remove", Gtk.STOCK_DELETE, TRANSLATABLE, "Delete",
            TRANSLATABLE, on_remove };
        remove.label = _("Re_move");
        remove.tooltip = _("Remove the selected photos from the library");
        actions += remove;

        Gtk.ActionEntry photos = { "PhotosMenu", null, TRANSLATABLE, null, null,
            on_photos_menu };
        photos.label = _("_Photos");
        actions += photos;

        Gtk.ActionEntry increase_size = { "IncreaseSize", Gtk.STOCK_ZOOM_IN, TRANSLATABLE,
            "bracketright", TRANSLATABLE, on_increase_size };
        increase_size.label = _("Zoom _In");
        increase_size.tooltip = _("Increase the magnification of the thumbnails");
        actions += increase_size;

        Gtk.ActionEntry decrease_size = { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, TRANSLATABLE,
            "bracketleft", TRANSLATABLE, on_decrease_size };
        decrease_size.label = _("Zoom _Out");
        decrease_size.tooltip = _("Decrease the magnification of the thumbnails");
        actions += decrease_size;

        Gtk.ActionEntry rotate_right = { "RotateClockwise", Resources.CLOCKWISE,
            TRANSLATABLE, "<Ctrl>R", TRANSLATABLE, on_rotate_clockwise };
        rotate_right.label = Resources.ROTATE_CW_MENU;
        rotate_right.tooltip = Resources.ROTATE_CW_TOOLTIP;
        actions += rotate_right;

        Gtk.ActionEntry rotate_left = { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE,
            TRANSLATABLE, "<Ctrl><Shift>R", TRANSLATABLE, on_rotate_counterclockwise };
        rotate_left.label = Resources.ROTATE_CCW_MENU;
        rotate_left.tooltip = Resources.ROTATE_CCW_TOOLTIP;
        actions += rotate_left;

        Gtk.ActionEntry mirror = { "Mirror", Resources.MIRROR, TRANSLATABLE, null,
            TRANSLATABLE, on_mirror };
        mirror.label = Resources.MIRROR_MENU;
        mirror.tooltip = Resources.MIRROR_TOOLTIP;
        actions += mirror;

        Gtk.ActionEntry enhance = { "Enhance", Resources.ENHANCE, TRANSLATABLE, "<Ctrl>E",
            TRANSLATABLE, on_enhance };
        enhance.label = Resources.ENHANCE_MENU;
        enhance.tooltip = Resources.ENHANCE_TOOLTIP;
        actions += enhance;

        Gtk.ActionEntry revert = { "Revert", Gtk.STOCK_REVERT_TO_SAVED, TRANSLATABLE, null,
            TRANSLATABLE, on_revert };
        revert.label = Resources.REVERT_MENU;
        revert.tooltip = Resources.REVERT_TOOLTIP;
        actions += revert;
        
        Gtk.ActionEntry favorite = { "FavoriteUnfavorite", Resources.FAVORITE, TRANSLATABLE, 
            "<Ctrl>F", TRANSLATABLE, on_favorite_unfavorite };
        favorite.label = Resources.FAVORITE_MENU;
        favorite.tooltip = Resources.FAVORITE_TOOLTIP;
        actions += favorite;
        
        Gtk.ActionEntry hide_unhide = { "HideUnhide", Resources.HIDDEN, TRANSLATABLE, "<Ctrl>H",
            TRANSLATABLE, on_hide_unhide };
        hide_unhide.label = Resources.HIDE_MENU;
        hide_unhide.tooltip = Resources.HIDE_TOOLTIP;
        actions += hide_unhide;
        
        Gtk.ActionEntry duplicate = { "Duplicate", null, TRANSLATABLE, "<Ctrl>D", TRANSLATABLE,
            on_duplicate_photo };
        duplicate.label = Resources.DUPLICATE_PHOTO_MENU;
        duplicate.tooltip = Resources.DUPLICATE_PHOTO_TOOLTIP;
        actions += duplicate;

        Gtk.ActionEntry slideshow = { "Slideshow", Gtk.STOCK_MEDIA_PLAY, TRANSLATABLE, "F5",
            TRANSLATABLE, on_slideshow };
        slideshow.label = _("_Slideshow");
        slideshow.tooltip = _("Play a slideshow");
        actions += slideshow;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, on_view_menu };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry sort_photos = { "SortPhotos", null, TRANSLATABLE, null, null, null };
        sort_photos.label = _("Sort _Photos");
        actions += sort_photos;

        Gtk.ActionEntry new_event = { "NewEvent", Gtk.STOCK_NEW, TRANSLATABLE, "<Ctrl>N",
            TRANSLATABLE, on_new_event };
        new_event.label = Resources.NEW_EVENT_MENU;
        new_event.tooltip = Resources.NEW_EVENT_TOOLTIP;
        actions += new_event;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;
        
        return actions;
    }
    
    private Gtk.ToggleActionEntry[] create_toggle_actions() {
        Gtk.ToggleActionEntry[] toggle_actions = new Gtk.ToggleActionEntry[0];
        
        Gtk.ToggleActionEntry favorites = { "ViewFavorites", null, TRANSLATABLE, "<Ctrl><Shift>F",
            TRANSLATABLE, on_display_only_favorites, Config.get_instance().get_display_favorite_photos() };
        favorites.label = _("Only _Favorites");
        favorites.tooltip = _("Show only your favorite photos");
        toggle_actions += favorites;

        Gtk.ToggleActionEntry titles = { "ViewTitle", null, TRANSLATABLE, "<Ctrl><Shift>T",
            TRANSLATABLE, on_display_titles, Config.get_instance().get_display_photo_titles() };
        titles.label = _("_Titles");
        titles.tooltip = _("Display the title of each photo");
        toggle_actions += titles;

        Gtk.ToggleActionEntry hidden = { "ViewHidden", null, TRANSLATABLE, "<Ctrl><Shift>H",
            TRANSLATABLE, on_display_hidden_photos, Config.get_instance().get_display_hidden_photos() };
        hidden.label = _("_Hidden Photos");
        hidden.tooltip = _("Show hidden photos");
        toggle_actions += hidden;

        return toggle_actions;
    }
    
    private Gtk.RadioActionEntry[] create_sort_crit_actions() {
        Gtk.RadioActionEntry[] sort_crit_actions = new Gtk.RadioActionEntry[0];

        Gtk.RadioActionEntry by_title = { "SortByTitle", null, TRANSLATABLE, null, TRANSLATABLE,
            SORT_BY_TITLE };
        by_title.label = _("By _Title");
        by_title.tooltip = _("Sort photos by title");
        sort_crit_actions += by_title;

        Gtk.RadioActionEntry by_date = { "SortByExposureDate", null, TRANSLATABLE, null,
            TRANSLATABLE, SORT_BY_EXPOSURE_DATE };
        by_date.label = _("By Exposure _Date");
        by_date.tooltip = _("Sort photos by exposure date");
        sort_crit_actions += by_date;

        return sort_crit_actions;
    }
    
    private Gtk.RadioActionEntry[] create_sort_order_actions() {
        Gtk.RadioActionEntry[] sort_order_actions = new Gtk.RadioActionEntry[0];

        Gtk.RadioActionEntry ascending = { "SortAscending", Gtk.STOCK_SORT_ASCENDING,
            TRANSLATABLE, null, TRANSLATABLE, SORT_ORDER_ASCENDING };
        ascending.label = _("_Ascending");
        ascending.tooltip = _("Sort photos in an ascending order");
        sort_order_actions += ascending;

        Gtk.RadioActionEntry descending = { "SortDescending", Gtk.STOCK_SORT_DESCENDING,
            TRANSLATABLE, null, TRANSLATABLE, SORT_ORDER_DESCENDING };
        descending.label = _("D_escending");
        descending.tooltip = _("Sort photos in a descending order");
        sort_order_actions += descending;

        return sort_order_actions;
    }

    // This method is called by CollectionViewManager to create thumbnails for the DataSource 
    // (Photo) objects.
    public virtual Thumbnail create_thumbnail(LibraryPhoto photo) {
        Thumbnail thumbnail = new Thumbnail(photo, scale);
        thumbnail.display_title(display_titles());
        
        return thumbnail;
    }
    
    public override void switched_to() {
        // set display options to match Configuration toggles (which can change while switched away)
        set_display_titles(Config.get_instance().get_display_photo_titles());
        if (Config.get_instance().get_display_favorite_photos())
            use_favorite_photo_filter(true);
        else
            use_hidden_photo_filter(Config.get_instance().get_display_hidden_photos());
        
        // perform these operations before calling base method to prevent flicker
        base.switched_to();
        
        // if the thumbnails were resized while viewing another page, resize the ones on this page
        // now
        int current_scale = slider_to_scale(slider.get_value());
        if (scale != current_scale)
            set_thumb_size(current_scale);
    }
    
    private void on_contents_altered() {
        slideshow_button.sensitive = get_view().get_count() > 0;
    }
    
    private void on_selection_changed(Gee.Iterable<DataView> items) {
        rotate_button.sensitive = get_view().get_selected_count() > 0;
#if !NO_PUBLISHING
        publish_button.set_sensitive(get_view().get_selected_count() > 0);
#endif
        enhance_button.sensitive = get_view().get_selected_count() > 0;
    }
    
    protected override void on_item_activated(LayoutItem item) {
        Thumbnail thumbnail = (Thumbnail) item;
        
        // switch to full-page view
        debug("switching to %s", thumbnail.get_photo().to_string());

        LibraryWindow.get_app().switch_to_photo_page(this, thumbnail);
    }
    
    private void set_favorite_item_sensitive(string path, bool selected) {
        // Favorite/Unfavorite menu item depends on several conditions
        Gtk.MenuItem favorite_menu_item = (Gtk.MenuItem) ui.get_widget(path);
        assert(favorite_menu_item != null);
        
        if (!selected) {
            favorite_menu_item.set_label(Resources.FAVORITE_MENU);
            favorite_menu_item.sensitive = false;
        } else if (can_favorite_selected()) {
            favorite_menu_item.set_label(Resources.FAVORITE_MENU);
            favorite_menu_item.sensitive = true;
        } else {
            favorite_menu_item.set_label(Resources.UNFAVORITE_MENU);
            favorite_menu_item.sensitive = true;
        }
    }

    private void set_hide_item_sensitive(string path, bool selected) {
        // Hide/Unhide menu item depends on several conditions
        Gtk.MenuItem hide_menu_item = (Gtk.MenuItem) ui.get_widget(path);
        assert(hide_menu_item != null);
        
        if (!selected) {
            hide_menu_item.set_label(Resources.HIDE_MENU);
            hide_menu_item.sensitive = false;
        } else if (can_hide_selected()) {
            hide_menu_item.set_label(Resources.HIDE_MENU);
            hide_menu_item.sensitive = true;
        } else {
            hide_menu_item.set_label(Resources.UNHIDE_MENU);
            hide_menu_item.sensitive = true;
        }
    }

    protected override bool on_context_invoked(Gtk.Menu context_menu) {
        bool selected = get_view().get_selected_count() > 0;
        bool revert_possible = can_revert_selected();
        
        set_item_sensitive("/CollectionContextMenu/ContextDuplicate", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRemove", selected);
        set_item_sensitive("/CollectionContextMenu/ContextNewEvent", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRotateClockwise", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRotateCounterclockwise", selected);
        set_item_sensitive("/CollectionContextMenu/ContextEnhance", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRevert", selected && revert_possible);
        set_hide_item_sensitive("/CollectionContextMenu/ContextHideUnhide", selected);
        set_favorite_item_sensitive("/CollectionContextMenu/ContextFavoriteUnfavorite", selected);

        return true;
    }
    
    public override LayoutItem? get_fullscreen_photo() {
        // use first selected item; if no selection, use first item
        if (get_view().get_selected_count() > 0)
            return (LayoutItem?) get_view().get_selected_at(0);
        else if (get_view().get_count() > 0)
            return (LayoutItem?) get_view().get_at(0);
        else
            return null;
    }
    
    private override void drag_begin(Gdk.DragContext context) {
        if (get_view().get_selected_count() == 0)
            return;
        
        drag_files.clear();
        drag_photos.clear();

        // because drag_data_get may be called multiple times in a single drag, prepare all the exported
        // files first
        Gdk.Pixbuf icon = null;
        drag_failed_item_count = 0;
        foreach (DataView view in get_view().get_selected()) {
            LibraryPhoto photo = ((Thumbnail) view).get_photo();

            drag_photos.add(photo);

            File file = null;
            try {
                file = photo.generate_exportable();
                drag_files.add(file);
            } catch (Error err) {
                drag_failed_item_count++;
                warning("%s", err.message);
            }
            
            try {
                // set up icon using the first photo
                if (icon == null) {
                    icon = photo.get_preview_pixbuf(Scaling.for_best_fit(
                        AppWindow.DND_ICON_SCALE, true));
                }
            } catch (Error err) {
                warning("%s", err.message);
            }

            if (file != null)
                debug("Prepared %s for export", file.get_path());
        }
        
        if (icon != null)
            Gtk.drag_source_set_icon_pixbuf(get_event_source(), icon);
    }
    
    private override void drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint target_type, uint time) {
        if (target_type == TargetType.URI_LIST) {
            if (drag_files.size == 0)
                return;
            
            // prepare list of uris
            string[] uris = new string[drag_files.size];
            int ctr = 0;
            foreach (File file in drag_files)
                uris[ctr++] = file.get_uri();
            
            selection_data.set_uris(uris);
        } else {
            assert(target_type == TargetType.PHOTO_LIST);

            if (drag_photos.size == 0)
                return;
           
            selection_data.set(Gdk.Atom.intern_static_string("PhotoID"), (int) sizeof(int64),
                serialize_photo_ids(drag_photos));
        }
    }
    
    private override void drag_end(Gdk.DragContext context) {
        drag_files.clear();
        drag_photos.clear();

        if (drag_failed_item_count > 0) {
            Idle.add(report_drag_failed);
        }
    }

    private bool report_drag_failed() {
        AppWindow.error_message(drag_failed_item_count == 1 ? _("A photo source file is missing.") : 
            _("%d photo source files missing.").printf(drag_failed_item_count));
        drag_failed_item_count = 0;

        return false;
    }
    
    private override bool source_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        debug("Drag failed: %d", (int) drag_result);
        
        drag_files.clear();
        drag_photos.clear();
        
        foreach (DataView view in get_view().get_selected())
            ((Thumbnail) view).get_photo().export_failed();
        
        return false;
    }
    
    public void increase_thumb_size() {
        set_thumb_size(scale + MANUAL_STEPPING);
    }
    
    public void decrease_thumb_size() {
        set_thumb_size(scale - MANUAL_STEPPING);
    }
    
    public void set_thumb_size(int new_scale) {
        if (scale == new_scale || !is_in_view())
            return;
        
        scale = new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
        get_checkerboard_layout().set_scale(scale);
        
        ViewCollection view = get_view();

        // when doing mass operations on LayoutItems, freeze individual notifications
        view.freeze_view_notifications();
        view.freeze_geometry_notifications();
        
        foreach(DataObject photo in view.get_all_unfiltered())
            ((Thumbnail) photo).resize(scale);
        
        view.thaw_geometry_notifications(true);
        view.thaw_view_notifications(true);
    }
    
    private void on_file_menu() {
        set_item_sensitive("/CollectionMenuBar/FileMenu/Export", get_view().get_selected_count() > 0);
    }
    
    private void on_export() {
        Gee.ArrayList<LibraryPhoto> export_list = new Gee.ArrayList<LibraryPhoto>();
        foreach (DataView view in get_view().get_selected())
            export_list.add(((Thumbnail) view).get_photo());

        if (export_list.size == 0)
            return;

        ExportDialog export_dialog = null;
        if (export_list.size == 1)
            export_dialog = new ExportDialog(_("Export Photo"));
        else
            export_dialog = new ExportDialog(_("Export Photos"));
        
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
                AppWindow.error_message(_("Unable to export photo %s: %s").printf(
                    photo.get_file().get_path(), err.message));
            }
            
            return;
        }

        // multiple photos
        File export_dir = ExportUI.choose_dir();
        if (export_dir == null)
            return;
        
        AppWindow.get_instance().set_busy_cursor();
        
        int count = 0;
        int total = export_list.size;
        
        Cancellable cancellable = null;
        ProgressDialog progress = null;
        if (total >= MIN_OPS_FOR_PROGRESS_WINDOW) {
            cancellable = new Cancellable();
            progress = new ProgressDialog(AppWindow.get_instance(), _("Exporting..."), cancellable);
        }
        
        foreach (LibraryPhoto photo in export_list) {
            File save_as = export_dir.get_child(photo.get_file().get_basename());
            if (save_as.query_exists(null)) {
                if (!ExportUI.query_overwrite(save_as))
                    continue;
            }
            
            try {
                photo.export(save_as, scale, constraint, quality);
            } catch (Error err) {
                AppWindow.error_message(_("Unable to export photo %s: %s").printf(save_as.get_path(),
                    err.message));
            }
            
            if (progress != null) {
                progress.set_fraction(++count, total);
                spin_event_loop();
                
                if (cancellable.is_cancelled())
                    break;
            }
        }
        
        if (progress != null)
            progress.close();
        
        AppWindow.get_instance().set_normal_cursor();
    }

    private void on_edit_menu() {
        bool selected = get_view().get_selected_count() > 0;
        
        decorate_undo_item("/CollectionMenuBar/EditMenu/Undo");
        decorate_redo_item("/CollectionMenuBar/EditMenu/Redo");
        set_item_sensitive("/CollectionMenuBar/EditMenu/SelectAll", get_view().get_count() > 0);
        set_item_sensitive("/CollectionMenuBar/EditMenu/Remove", selected);
        set_item_sensitive("/CollectionMenuBar/EditMenu/Duplicate", selected);
    }

    private void on_events_menu() {
        set_item_sensitive("/CollectionMenuBar/EventsMenu/NewEvent", get_view().get_selected_count() > 0);
    }
    
    private void on_select_all() {
        get_view().select_all();
    }
    
    private bool can_revert_selected() {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_photo().has_transformations())
                return true;
        }
        
        return false;
    }
    
    private bool can_favorite_selected() {
        foreach (DataView view in get_view().get_selected()) {
            if (!((Thumbnail) view).get_photo().is_favorite())
                return true;
        }
        
        return false;
    }
    
    private bool can_hide_selected() {
        foreach (DataView view in get_view().get_selected()) {
            if(!((Thumbnail) view).get_photo().is_hidden())
                return true;
        }
        
        return false;
    }

    protected virtual void on_photos_menu() {
        bool selected = (get_view().get_selected_count() > 0);
        bool revert_possible = can_revert_selected();
        
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateClockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateCounterclockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Mirror", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Enhance", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Revert", selected && revert_possible);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Slideshow", get_view().get_count() > 0);
        set_hide_item_sensitive("/CollectionMenuBar/PhotosMenu/HideUnhide", selected);
        set_favorite_item_sensitive("/CollectionMenuBar/PhotosMenu/FavoriteUnfavorite", selected);
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
        if (get_view().get_selected_count() == 0)
            return;
        
        Gtk.ResponseType result = remove_photos_dialog(get_page_window(), 
            get_view().get_selected_count() == 1);
        if (result != Gtk.ResponseType.YES && result != Gtk.ResponseType.NO)
            return;
        
        // mark all the sources for the selected view items and destroy them ... note that simply
        // removing the view items does not work here; the source items (i.e. the Photo objects)
        // must be destroyed, which will remove the view items from this view (and all others)
        Marker marker = LibraryPhoto.global.start_marking();
        foreach (DataView view in get_view().get_selected()) {
            LibraryPhoto photo = ((Thumbnail) view).get_photo();
            
            if (result == Gtk.ResponseType.YES)
                photo.delete_original_on_destroy();
            
            marker.mark(photo);
        }
        
        AppWindow.get_instance().set_busy_cursor();
        
        Cancellable cancellable = null;
        ProgressDialog progress = null;
        if (marker.get_count() >= MIN_OPS_FOR_PROGRESS_WINDOW) {
            cancellable = new Cancellable();
            progress = new ProgressDialog(AppWindow.get_instance(), _("Removing..."), cancellable);
        }
        
        // valac complains about passing an argument for a delegate using ternary operator:
        // https://bugzilla.gnome.org/show_bug.cgi?id=599349
        if (progress != null)
            LibraryPhoto.global.destroy_marked(marker, progress.monitor);
        else
            LibraryPhoto.global.destroy_marked(marker);
        
        if (progress != null)
            progress.close();
        
        AppWindow.get_instance().set_normal_cursor();
    }
    
    private void on_rotate_clockwise() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(), 
            Rotation.CLOCKWISE, Resources.ROTATE_CW_FULL_LABEL, Resources.ROTATE_CW_TOOLTIP,
            _("Rotating..."), _("Undoing Rotate..."));
        get_command_manager().execute(command);
    }

#if !NO_PUBLISHING
    private void on_publish() {
        PublishingDialog publishing_dialog = new PublishingDialog(get_view().get_selected(),
            get_view().get_selected_count());
        publishing_dialog.run();
    }
#endif

    private void on_rotate_counterclockwise() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(), 
            Rotation.COUNTERCLOCKWISE, Resources.ROTATE_CCW_FULL_LABEL, Resources.ROTATE_CCW_TOOLTIP,
            _("Rotating..."), _("Undoing Rotate"));
        get_command_manager().execute(command);
    }
    
    private void on_mirror() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(),
            Rotation.MIRROR, Resources.MIRROR_LABEL, Resources.MIRROR_TOOLTIP, _("Mirroring..."),
            _("Undoing Mirror..."));
        get_command_manager().execute(command);
    }
    
    private void on_revert() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RevertMultipleCommand command = new RevertMultipleCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
    
    private void on_enhance() {
        if (get_view().get_selected_count() == 0)
            return;
        
        EnhanceMultipleCommand command = new EnhanceMultipleCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
    
    private void on_favorite_unfavorite() {
        if (get_view().get_selected_count() == 0)
            return;
        
        FavoriteUnfavoriteCommand command = new FavoriteUnfavoriteCommand(get_view().get_selected(),
            can_favorite_selected());
        get_command_manager().execute(command);
    }
    
    private void on_hide_unhide() {
        if (get_view().get_selected_count() == 0)
            return;
        
        HideUnhideCommand command = new HideUnhideCommand(get_view().get_selected(), can_hide_selected());
        get_command_manager().execute(command);
    }
    
    private void on_duplicate_photo() {
        if (get_view().get_selected_count() == 0)
            return;
        
        DuplicateMultiplePhotosCommand command = new DuplicateMultiplePhotosCommand(
            get_view().get_selected());
        get_command_manager().execute(command);
    }

    private void on_slideshow() {
        if (get_view().get_count() == 0)
            return;
        
        Thumbnail thumbnail = (Thumbnail) get_fullscreen_photo();
        if (thumbnail == null)
            return;
        
        AppWindow.get_instance().go_fullscreen(new SlideshowPage(get_view(), thumbnail));
    }

    private void on_view_menu() {
        set_item_sensitive("/CollectionMenuBar/ViewMenu/IncreaseSize", scale < Thumbnail.MAX_SCALE);
        set_item_sensitive("/CollectionMenuBar/ViewMenu/DecreaseSize", scale > Thumbnail.MIN_SCALE);
        set_item_sensitive("/CollectionMenuBar/ViewMenu/Fullscreen", get_view().get_count() > 0);
    }
    
    private bool display_titles() {
        Gtk.ToggleAction action = (Gtk.ToggleAction) ui.get_action("/CollectionMenuBar/ViewMenu/ViewTitle");
        
        return action.get_active();
    }
    
    private void on_display_only_favorites(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        use_favorite_photo_filter(display);
        
        Config.get_instance().set_display_favorite_photos(display);
    }
    
    private void on_display_titles(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_titles(display);
        
        Config.get_instance().set_display_photo_titles(display);
    }
    
    private void on_display_hidden_photos(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        use_hidden_photo_filter(display);
        
        Config.get_instance().set_display_hidden_photos(display);
    }
    
    private void use_favorite_photo_filter(bool display) {
        Gtk.ToggleAction hidden_action = (Gtk.ToggleAction) action_group.get_action("ViewHidden");
        
        // Clear View Hidden if enabled
        if (display && hidden_action != null)
            hidden_action.set_active(false);
        
        // install appropriate ViewFilter for current options
        if (display)
            get_view().install_view_filter(favorite_photo_filter);
        else if (hidden_action != null && !hidden_action.active)
            get_view().install_view_filter(hidden_photo_filter);
        else
            get_view().reset_view_filter();
        
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewFavorite");
        if (action != null)
            action.set_active(display);
    }
    
    private bool favorite_photo_filter(DataView view) {
        return ((Thumbnail) view).get_photo().is_favorite();
    }
    
    private void use_hidden_photo_filter(bool display) {
        // Clear View Favorites if enabled
        if (display) {
            Gtk.ToggleAction favorites_action = (Gtk.ToggleAction) action_group.get_action("ViewFavorites");
            if (favorites_action != null)
                favorites_action.set_active(false);
        }
        
        if (display)
            get_view().reset_view_filter();
        else
            get_view().install_view_filter(hidden_photo_filter);
        
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewHidden");
        if (action != null)
            action.set_active(display);
    }
    
    private bool hidden_photo_filter(DataView view) {
        return !((Thumbnail) view).get_photo().is_hidden();
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
    
    private override bool on_ctrl_pressed(Gdk.EventKey? event) {
        rotate_button.set_stock_id(Resources.COUNTERCLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CCW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CCW_TOOLTIP);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return base.on_ctrl_pressed(event);
    }
    
    private override bool on_ctrl_released(Gdk.EventKey? event) {
        rotate_button.set_stock_id(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.clicked -= on_rotate_counterclockwise;
        rotate_button.clicked += on_rotate_clockwise;
        
        return base.on_ctrl_released(event);
    }
    
    private int get_sort_criteria() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/CollectionMenuBar/ViewMenu/SortPhotos/SortByTitle");
        assert(action != null);
        
        int value = action.get_current_value();
        assert(value >= SORT_BY_MIN);
        assert(value <= SORT_BY_MAX);
        
        return value;
    }
    
    private int get_sort_order() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/CollectionMenuBar/ViewMenu/SortPhotos/SortAscending");
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
        get_view().set_comparator(get_sort_comparator());
    }
    
    private Comparator<LayoutItem> get_sort_comparator() {
        switch (get_sort_criteria()) {
            case SORT_BY_TITLE:
                return new CompareTitle(is_sort_ascending());
            
            case SORT_BY_EXPOSURE_DATE:
                return new CompareDate(is_sort_ascending());
            
            default:
                error("Unknown sort criteria: %d", get_sort_criteria());
                
                return new CompareTitle(true);
        }
    }

    private override void set_display_titles(bool display) {
        base.set_display_titles(display);
    
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewTitle");
        if (action != null)
            action.set_active(display);
    }
    
    private void on_new_event() {
        NewEventCommand command = new NewEventCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
}

public class LibraryPage : CollectionPage {
    public LibraryPage() {
        base(_("Photos"));
        
        get_view().monitor_source_collection(LibraryPhoto.global, new CollectionViewManager(this));
    }
}

