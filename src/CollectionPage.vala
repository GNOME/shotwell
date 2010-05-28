/* Copyright 2009-2010 Yorba Foundation
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
        return page.create_thumbnail(source);
    }
}

public abstract class CollectionPage : CheckerboardPage {
    public const int SORT_ORDER_ASCENDING = 0;
    public const int SORT_ORDER_DESCENDING = 1;

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public const int MANUAL_STEPPING = 16;
    public const int SLIDER_STEPPING = 4;

    public enum SortBy {
        TITLE = 1,
        EXPOSURE_DATE = 2;
    }

    private static Gtk.Adjustment slider_adjustment = null;
    
    private Gtk.HScale slider = null;
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToolButton enhance_button = null;
    private Gtk.ToolButton slideshow_button = null;
    private PhotoDragAndDropHandler dnd_handler = null;
#if !NO_PUBLISHING
    private Gtk.ToolButton publish_button = null;
#endif
    private int scale = Thumbnail.DEFAULT_SCALE;
    private PhotoExporterUI exporter = null;
    
    public CollectionPage(string page_name, string? ui_filename = null, 
        Gtk.ActionEntry[]? child_actions = null) {
        base(page_name);
        
        init_ui_start("collection.ui", "CollectionActionGroup", create_actions(),
            create_toggle_actions());

#if !NO_PRINTING
        ui.add_ui(ui.new_merge_id(), "/CollectionMenuBar/FileMenu/PrintPlaceholder", "PageSetup",
            "PageSetup", Gtk.UIManagerItemType.MENUITEM, false);
        ui.add_ui(ui.new_merge_id(), "/CollectionMenuBar/FileMenu/PrintPlaceholder", "Print",
            "Print", Gtk.UIManagerItemType.MENUITEM, false);
#endif

#if !NO_PUBLISHING
        ui.add_ui(ui.new_merge_id(), "/CollectionMenuBar/FileMenu/PublishPlaceholder", "Publish",
            "Publish", Gtk.UIManagerItemType.MENUITEM, false);
#endif

#if !NO_SET_BACKGROUND
        ui.add_ui(ui.new_merge_id(), "/CollectionMenuBar/PhotosMenu/SetBackgroundPlaceholder", "SetBackground",
            "SetBackground", Gtk.UIManagerItemType.MENUITEM, false);
        ui.add_ui(ui.new_merge_id(), "/CollectionContextMenu/ContextSetBackgroundPlaceholder", "SetBackground",
            "SetBackground", Gtk.UIManagerItemType.MENUITEM, false);
#endif 
            
        bool sort_order;
        int sort_by;
        get_config_photos_sort(out sort_order, out sort_by);

        action_group.add_radio_actions(create_sort_crit_actions(), sort_by, on_sort_changed);
        action_group.add_radio_actions(create_sort_order_actions(), sort_order ?
            SORT_ORDER_ASCENDING : SORT_ORDER_DESCENDING, on_sort_changed);

        if (ui_filename != null)
            init_load_ui(ui_filename);
        
        if (child_actions != null)
            action_group.add_actions(child_actions, this);
        
        init_ui_bind("/CollectionMenuBar");
        init_item_context_menu("/CollectionContextMenu");
        
        get_view().set_comparator(get_sort_comparator());
        get_view().contents_altered += on_contents_altered;
        get_view().selection_group_altered += on_selection_changed;
        get_view().items_visibility_changed += on_contents_altered;
        get_view().items_altered += on_photos_altered;
        
        get_view().freeze_notifications();
        get_view().set_property(CheckerboardItem.PROP_SHOW_TITLES, 
            Config.get_instance().get_display_photo_titles());
        get_view().set_property(Thumbnail.PROP_SHOW_TAGS, 
            Config.get_instance().get_display_photo_tags());
        get_view().set_property(Thumbnail.PROP_SIZE, scale);
        get_view().thaw_notifications();
        
        // adjustment which is shared by all sliders in the application
        scale = Config.get_instance().get_photo_thumbnail_scale();
        if (slider_adjustment == null) {
            slider_adjustment = new Gtk.Adjustment(scale_to_slider(scale), 0,
                scale_to_slider(Thumbnail.MAX_SCALE), 1, 10, 0);
        }
        
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
        publish_button.set_label(Resources.PUBLISH_LABEL);
        publish_button.set_tooltip_text(Resources.PUBLISH_TOOLTIP);
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
        
        show_all();
        
        // enable photo drag-and-drop on our ViewCollection
        dnd_handler = new PhotoDragAndDropHandler(this);
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, on_file_menu };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry export = { "Export", Gtk.STOCK_SAVE_AS, TRANSLATABLE, "<Ctrl><Shift>E",
            TRANSLATABLE, on_export };
        export.label = Resources.EXPORT_MENU;
        export.tooltip = Resources.EXPORT_TOOLTIP;
        export.tooltip = _("Export selected photos to disk");
        actions += export;

#if !NO_PRINTING
        Gtk.ActionEntry page_setup = { "PageSetup", Gtk.STOCK_PAGE_SETUP, TRANSLATABLE, null,
            TRANSLATABLE, on_page_setup };
        page_setup.label = Resources.PAGE_SETUP_MENU;
        page_setup.tooltip = Resources.PAGE_SETUP_TOOLTIP;
        actions += page_setup;

        Gtk.ActionEntry print = { "Print", Gtk.STOCK_PRINT, TRANSLATABLE, "<Ctrl>P",
            TRANSLATABLE, on_print };
        print.label = Resources.PRINT_MENU;
        print.tooltip = Resources.PRINT_TOOLTIP;
        actions += print;
#endif        
        
#if !NO_PUBLISHING
        Gtk.ActionEntry publish = { "Publish", Resources.PUBLISH, TRANSLATABLE, "<Ctrl><Shift>P",
            TRANSLATABLE, on_publish };
        publish.label = Resources.PUBLISH_MENU;
        publish.tooltip = Resources.PUBLISH_TOOLTIP;
        actions += publish;
#endif
        
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
        
        Gtk.ActionEntry remove_from_library = { "RemoveFromLibrary", Gtk.STOCK_REMOVE, TRANSLATABLE, null,
            TRANSLATABLE, on_remove_from_library };
        remove_from_library.label = Resources.REMOVE_FROM_LIBRARY_MENU;
        remove_from_library.tooltip = _("Remove the selected photos from the library");
        actions += remove_from_library;
        
        Gtk.ActionEntry move_to_trash = { "MoveToTrash", Gtk.STOCK_DELETE, TRANSLATABLE, "Delete",
            TRANSLATABLE, on_move_to_trash };
        move_to_trash.label = Resources.MOVE_TO_TRASH_MENU;
        move_to_trash.tooltip = _("Move the selected photos to the trash");
        actions += move_to_trash;
        
        Gtk.ActionEntry photos = { "PhotosMenu", null, TRANSLATABLE, null, null,
            on_photos_menu };
        photos.label = _("_Photos");
        actions += photos;
        
        Gtk.ActionEntry increase_size = { "IncreaseSize", Gtk.STOCK_ZOOM_IN, TRANSLATABLE,
            "<Ctrl>plus", TRANSLATABLE, on_increase_size };
        increase_size.label = _("Zoom _In");
        increase_size.tooltip = _("Increase the magnification of the thumbnails");
        actions += increase_size;

        Gtk.ActionEntry decrease_size = { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, TRANSLATABLE,
            "<Ctrl>minus", TRANSLATABLE, on_decrease_size };
        decrease_size.label = _("Zoom _Out");
        decrease_size.tooltip = _("Decrease the magnification of the thumbnails");
        actions += decrease_size;

        Gtk.ActionEntry rotate_right = { "RotateClockwise", Resources.CLOCKWISE,
            TRANSLATABLE, "bracketright", TRANSLATABLE, on_rotate_clockwise };
        rotate_right.label = Resources.ROTATE_CW_MENU;
        rotate_right.tooltip = Resources.ROTATE_CW_TOOLTIP;
        actions += rotate_right;

        Gtk.ActionEntry rotate_left = { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE,
            TRANSLATABLE, "bracketleft", TRANSLATABLE, on_rotate_counterclockwise };
        rotate_left.label = Resources.ROTATE_CCW_MENU;
        rotate_left.tooltip = Resources.ROTATE_CCW_TOOLTIP;
        actions += rotate_left;

        Gtk.ActionEntry mirror = { "Mirror", Resources.MIRROR, TRANSLATABLE, null,
            TRANSLATABLE, on_mirror };
        mirror.label = Resources.MIRROR_MENU;
        mirror.tooltip = Resources.MIRROR_TOOLTIP;
        actions += mirror;
        
        Gtk.ActionEntry flip = { "Flip", Resources.FLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip };
        flip.label = Resources.FLIP_MENU;
        flip.tooltip = Resources.FLIP_TOOLTIP;
        actions += flip;

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
        
        Gtk.ActionEntry revert_editable = { "RevertEditable", null, TRANSLATABLE, null,
            TRANSLATABLE, on_revert_editable };
        revert_editable.label = Resources.REVERT_EDITABLE_MENU;
        revert_editable.tooltip = Resources.REVERT_EDITABLE_TOOLTIP;
        actions += revert_editable;
        
#if !NO_SET_BACKGROUND
        Gtk.ActionEntry set_background = { "SetBackground", null, TRANSLATABLE, "<Ctrl>B",
            TRANSLATABLE, on_set_background };
        set_background.label = Resources.SET_BACKGROUND_MENU;
        set_background.tooltip = Resources.SET_BACKGROUND_TOOLTIP;
        actions += set_background;
#endif

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

        Gtk.ActionEntry rename = { "PhotoRename", null, TRANSLATABLE, "F2", TRANSLATABLE,
            on_rename };
        rename.label = Resources.RENAME_PHOTO_MENU;
        rename.tooltip = Resources.RENAME_PHOTO_TOOLTIP;
        actions += rename;

        Gtk.ActionEntry adjust_date_time = { "AdjustDateTime", null, TRANSLATABLE, null,
            TRANSLATABLE, on_adjust_date_time };
        adjust_date_time.label = Resources.ADJUST_DATE_TIME_MENU;
        adjust_date_time.tooltip = Resources.ADJUST_DATE_TIME_TOOLTIP;
        actions += adjust_date_time;
        
        Gtk.ActionEntry external_edit = { "ExternalEdit", Gtk.STOCK_EDIT, TRANSLATABLE, null,
            TRANSLATABLE, on_external_edit };
        external_edit.label = Resources.EXTERNAL_EDIT_MENU;
        external_edit.tooltip = Resources.EXTERNAL_EDIT_TOOLTIP;
        actions += external_edit;
        
        Gtk.ActionEntry edit_raw = { "ExternalEditRAW", null, TRANSLATABLE, null, TRANSLATABLE,
            on_external_edit_raw };
        edit_raw.label = Resources.EXTERNAL_EDIT_RAW_MENU;
        edit_raw.tooltip = Resources.EXTERNAL_EDIT_RAW_TOOLTIP;
        actions += edit_raw;
        
        Gtk.ActionEntry jump_to_file = { "JumpToFile", Gtk.STOCK_JUMP_TO, TRANSLATABLE, null, 
            TRANSLATABLE, on_jump_to_file };
        jump_to_file.label = Resources.JUMP_TO_FILE_MENU;
        jump_to_file.tooltip = Resources.JUMP_TO_FILE_TOOLTIP;
        actions += jump_to_file;
        
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
        
        Gtk.ActionEntry tags = { "TagsMenu", null, TRANSLATABLE, null, null, on_tags_menu };
        tags.label = _("Ta_gs");
        actions += tags;
        
        Gtk.ActionEntry add_tags = { "AddTags", null, TRANSLATABLE, "<Ctrl>T", TRANSLATABLE, 
            on_add_tags };
        add_tags.label = Resources.ADD_TAGS_MENU;
        add_tags.tooltip = Resources.ADD_TAGS_TOOLTIP;
        actions += add_tags;
        
        Gtk.ActionEntry modify_tags = { "ModifyTags", null, TRANSLATABLE, "<Ctrl>M", TRANSLATABLE, 
            on_modify_tags };
        modify_tags.label = Resources.MODIFY_TAGS_MENU;
        modify_tags.tooltip = Resources.MODIFY_TAGS_TOOLTIP;
        actions += modify_tags;
        
        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;
        
        return actions;
    }
    
    private Gtk.ToggleActionEntry[] create_toggle_actions() {
        Gtk.ToggleActionEntry[] toggle_actions = new Gtk.ToggleActionEntry[0];
        
        Gtk.ToggleActionEntry favorites = { "ViewFavorites", null, TRANSLATABLE, "<Ctrl><Shift>F",
            TRANSLATABLE, on_display_only_favorites, Config.get_instance().get_display_favorite_photos() };
        favorites.label = _("Only Fa_vorites");
        favorites.tooltip = _("Show only your favorite photos");
        toggle_actions += favorites;

        Gtk.ToggleActionEntry titles = { "ViewTitle", null, TRANSLATABLE, "<Ctrl><Shift>T",
            TRANSLATABLE, on_display_titles, Config.get_instance().get_display_photo_titles() };
        titles.label = _("_Titles");
        titles.tooltip = _("Display the title of each photo");
        toggle_actions += titles;
        
        Gtk.ToggleActionEntry tags = { "ViewTags", null, TRANSLATABLE, "<Ctrl><Shift>G",
            TRANSLATABLE, on_display_tags, Config.get_instance().get_display_photo_tags() };
        tags.label = _("Ta_gs");
        tags.tooltip = _("Display each photo's tags");
        toggle_actions += tags;
        
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
            SortBy.TITLE };
        by_title.label = _("By _Title");
        by_title.tooltip = _("Sort photos by title");
        sort_crit_actions += by_title;

        Gtk.RadioActionEntry by_date = { "SortByExposureDate", null, TRANSLATABLE, null,
            TRANSLATABLE, SortBy.EXPOSURE_DATE };
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
    public virtual DataView create_thumbnail(DataSource source) {
        LibraryPhoto photo = (LibraryPhoto) source;
        Thumbnail thumbnail = new Thumbnail(photo, scale);
        
        return thumbnail;
    }
    
    public override void switched_to() {
        // set display options to match Configuration toggles (which can change while switched away)
        get_view().freeze_notifications();
        set_display_titles(Config.get_instance().get_display_photo_titles());
        set_display_tags(Config.get_instance().get_display_photo_tags());
        get_view().thaw_notifications();

        sync_sort();

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
    
    protected override void init_actions(int selected_count, int count) {
        bool selected = selected_count > 0;
        
        set_action_sensitive("RemoveFromLibrary", selected);
        set_action_sensitive("MoveToTrash", selected);
        set_action_sensitive("Duplicate", selected);
        set_action_sensitive("ExternalEdit", selected);
        set_action_hidden("ExternalEditRAW");
        set_action_sensitive("RevertEditable", can_revert_editable_selected());
        set_action_sensitive("JumpToFile", selected_count == 1);
        
        base.init_actions(selected_count, count);
    }
    
    private void on_contents_altered() {
        set_action_sensitive("Slideshow", get_view().get_count() > 0);
    }
    
    private void on_photos_altered() {
        // since the photo can be altered externally to Shotwell now, need to make the revert
        // command available appropriately, even if the selection doesn't change
        set_action_sensitive("RevertEditable", can_revert_editable_selected());
    }
    
#if !NO_PRINTING
    private void on_print() {
        if (get_view().get_selected_count() != 1)
            return;

        TransformablePhoto target_photo = (TransformablePhoto)
            ((SortedList<DataView>) get_view().get_selected()).get_at(0).get_source();
        PrintManager.get_instance().spool_photo(target_photo);
    }

    private void on_page_setup() {
        PrintManager.get_instance().do_page_setup();
    }
#endif
    
    private void on_selection_changed() {
        int selected_count = get_view().get_selected_count();
        bool has_selected = selected_count > 0;
        bool is_single_raw = selected_count == 1 
            && ((Photo) get_view().get_selected_at(0).get_source()).get_master_file_format() == PhotoFileFormat.RAW;
        
        rotate_button.sensitive = has_selected;
#if !NO_PUBLISHING
        publish_button.set_sensitive(has_selected);
#endif
        enhance_button.sensitive = has_selected;
        
        set_action_sensitive("ExternalEdit", selected_count == 1);
        if (is_single_raw)
            set_action_visible("ExternalEditRAW", true);
        else
            set_action_hidden("ExternalEditRAW");
        set_action_sensitive("RevertEditable", can_revert_editable_selected());
        set_action_sensitive("JumpToFile", selected_count == 1);
        
        set_action_sensitive("RemoveFromLibrary", has_selected);
        set_action_sensitive("MoveToTrash", has_selected);
        set_action_sensitive("Duplicate", has_selected);
    }
    
    protected override void on_item_activated(CheckerboardItem item) {
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

    protected override bool on_context_invoked() {
        bool one_selected = get_view().get_selected_count() == 1;
        bool selected = get_view().get_selected_count() > 0;
        bool revert_possible = can_revert_selected();
        
        set_item_sensitive("/CollectionContextMenu/ContextMoveToTrash", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRotateClockwise", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRotateCounterclockwise", selected);
        set_item_sensitive("/CollectionContextMenu/ContextEnhance", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRevert", selected && revert_possible);
        set_hide_item_sensitive("/CollectionContextMenu/ContextHideUnhide", selected);
        set_favorite_item_sensitive("/CollectionContextMenu/ContextFavoriteUnfavorite", selected);
        set_item_sensitive("/CollectionContextMenu/ContextModifyTags", one_selected);
        set_item_sensitive("/CollectionContextMenu/ContextPhotoRename", one_selected);

#if !NO_SET_BACKGROUND
        set_item_sensitive("/CollectionContextMenu/ContextSetBackgroundPlaceholder/SetBackground",
            get_view().get_selected_count() == 1);
#endif 

        return base.on_context_invoked();
    }
    
    public override CheckerboardItem? get_fullscreen_photo() {
        // use first selected item; if no selection, use first item
        if (get_view().get_selected_count() > 0)
            return (CheckerboardItem?) get_view().get_selected_at(0);
        else if (get_view().get_count() > 0)
            return (CheckerboardItem?) get_view().get_at(0);
        else
            return null;
    }
    
    protected override bool on_app_key_pressed(Gdk.EventKey event) {
        bool handled = true;
        
        switch (Gdk.keyval_name(event.keyval)) {
            case "Page_Up":
            case "KP_Page_Up":
            case "Page_Down":
            case "KP_Page_Down":
            case "Home":
            case "KP_Home":
            case "End":
            case "KP_End":
                key_press_event(event);
            break;
            
            case "equal":
            case "plus":
            case "KP_Add":
                on_increase_size();
            break;
            
            case "minus":
            case "underscore":
            case "KP_Subtract":
                on_decrease_size();
            break;
            
            default:
                handled = false;
            break;
        }
        
        return handled ? true : base.on_app_key_pressed(event);
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
        
        // when doing mass operations on LayoutItems, freeze individual notifications
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SIZE, scale);
        get_view().thaw_notifications();
    }
    
    private void on_file_menu() {
        int count = get_view().get_selected_count();
        
#if !NO_PRINTING
        set_item_sensitive("/CollectionMenuBar/FileMenu/PrintPlaceholder/Print", count == 1);
#endif    
    
        set_item_sensitive("/CollectionMenuBar/FileMenu/Export", count > 0);

#if !NO_PUBLISHING
        set_item_sensitive("/CollectionMenuBar/FileMenu/PublishPlaceholder/Publish", count > 0);
#endif
    }
    
    private void on_export() {
        if (exporter != null)
            return;
        
        Gee.Collection<LibraryPhoto> export_list =
            (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources();
        if (export_list.size == 0)
            return;

        string title = ngettext("Export Photo", "Export Photos", export_list.size);
        ExportDialog export_dialog = new ExportDialog(title);

        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        PhotoFileFormat format =
            ((Gee.ArrayList<TransformablePhoto>) export_list).get(0).get_file_format();
        if (!export_dialog.execute(out scale, out constraint, out quality, ref format))
            return;
        
        Scaling scaling = Scaling.for_constraint(constraint, scale, false);
        
        // handle the single-photo case, which is treated like a Save As file operation
        if (export_list.size == 1) {
            LibraryPhoto photo = null;
            foreach (LibraryPhoto p in export_list) {
                photo = p;
                break;
            }
            
            File save_as = ExportUI.choose_file(photo.get_export_basename(format));
            if (save_as == null)
                return;
            
            try {
                AppWindow.get_instance().set_busy_cursor();
                photo.export(save_as, scaling, quality, format);
                AppWindow.get_instance().set_normal_cursor();
            } catch (Error err) {
                AppWindow.get_instance().set_normal_cursor();
                export_error_dialog(save_as, false);
            }
            
            return;
        }

        // multiple photos
        File export_dir = ExportUI.choose_dir();
        if (export_dir == null)
            return;
        
        exporter = new PhotoExporterUI(new PhotoExporter(export_list, export_dir,
            scaling, quality, format));
        exporter.export(on_export_completed);
    }
    
    private void on_export_completed() {
        exporter = null;
    }
    
    private void on_edit_menu() {
        decorate_undo_item("/CollectionMenuBar/EditMenu/Undo");
        decorate_redo_item("/CollectionMenuBar/EditMenu/Redo");
        set_item_sensitive("/CollectionMenuBar/EditMenu/SelectAll", get_view().get_count() > 0);
    }

    private void on_events_menu() {
        set_item_sensitive("/CollectionMenuBar/EventsMenu/NewEvent", get_view().get_selected_count() > 0);
    }
    
    protected virtual void on_tags_menu() {
        set_item_sensitive("/CollectionMenuBar/TagsMenu/AddTags", get_view().get_selected_count() > 0);
        set_item_sensitive("/CollectionMenuBar/TagsMenu/ModifyTags", get_view().get_selected_count() == 1);
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
    
    private bool can_revert_editable_selected() {
        foreach (DataView view in get_view().get_selected()) {
            if (((Photo) view.get_source()).has_editable())
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
        bool one_selected = get_view().get_selected_count() == 1;
        bool revert_possible = can_revert_selected();
        
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateClockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateCounterclockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Mirror", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Flip", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Enhance", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Revert", selected && revert_possible);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Slideshow", get_view().get_count() > 0);
        set_hide_item_sensitive("/CollectionMenuBar/PhotosMenu/HideUnhide", selected);
        set_favorite_item_sensitive("/CollectionMenuBar/PhotosMenu/FavoriteUnfavorite", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/AdjustDateTime", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/PhotoRename", one_selected);

#if !NO_SET_BACKGROUND
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/SetBackgroundPlaceholder/SetBackground",
            one_selected);
#endif 
    }
    
    private void on_increase_size() {
        increase_thumb_size();
        slider.set_value(scale_to_slider(scale));
    }

    private void on_decrease_size() {
        decrease_thumb_size();
        slider.set_value(scale_to_slider(scale));
    }
    
    private void on_remove_from_library() {
        remove_from_app((Gee.Collection<LibraryPhoto>) get_view().get_selected_sources(), 
            _("Remove From Library"), ngettext("Removing Photo From Library", "Removing Photos From Library", 
            get_view().get_selected_count()));
    }
    
    private void on_move_to_trash() {
        if (get_view().get_selected_count() > 0) {
            get_command_manager().execute(new TrashUntrashPhotosCommand(
                (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources(), true));
        }
    }
    
    private void on_rotate_clockwise() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(), 
            Rotation.CLOCKWISE, Resources.ROTATE_CW_FULL_LABEL, Resources.ROTATE_CW_TOOLTIP,
            _("Rotating"), _("Undoing Rotate"));
        get_command_manager().execute(command);
    }

#if !NO_PUBLISHING
    private void on_publish() {
        if (get_view().get_selected_count() == 0)
            return;
        
        PublishingDialog publishing_dialog = new PublishingDialog(get_view().get_selected());
        publishing_dialog.run();
    }
#endif

    private void on_rotate_counterclockwise() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(), 
            Rotation.COUNTERCLOCKWISE, Resources.ROTATE_CCW_FULL_LABEL, Resources.ROTATE_CCW_TOOLTIP,
            _("Rotating"), _("Undoing Rotate"));
        get_command_manager().execute(command);
    }
    
    private void on_mirror() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(),
            Rotation.MIRROR, Resources.MIRROR_LABEL, Resources.MIRROR_TOOLTIP, _("Mirroring"),
            _("Undoing Mirror"));
        get_command_manager().execute(command);
    }
    
    private void on_flip() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(),
            Rotation.UPSIDE_DOWN, Resources.FLIP_LABEL, Resources.FLIP_TOOLTIP, _("Flipping"),
            _("Undoing Flip"));
        get_command_manager().execute(command);
    }
    
    private void on_revert() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RevertMultipleCommand command = new RevertMultipleCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
    
    private void on_revert_editable() {
        if (get_view().get_selected_count() == 0 || !can_revert_editable_selected())
            return;
        
        if (!revert_editable_dialog(AppWindow.get_instance(),
            (Gee.Collection<Photo>) get_view().get_selected_sources())) {
            return;
        }
        
        foreach (DataObject object in get_view().get_selected_sources())
            ((Photo) object).revert_to_master();
    }
    
    private void on_enhance() {
        if (get_view().get_selected_count() == 0)
            return;
        
        EnhanceMultipleCommand command = new EnhanceMultipleCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
    
    private void on_modify_tags() {
        if (get_view().get_selected_count() != 1)
            return;
        
        LibraryPhoto photo = (LibraryPhoto) get_view().get_selected_at(0).get_source();
        
        ModifyTagsDialog dialog = new ModifyTagsDialog(photo);
        Gee.ArrayList<Tag>? new_tags = dialog.execute();
        
        if (new_tags == null)
            return;
        
        get_command_manager().execute(new ModifyTagsCommand(photo, new_tags));
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

    private void on_rename() {
        // only rename one at a time
        if (get_view().get_selected_count() != 1)
            return;
        
        LibraryPhoto item = (LibraryPhoto) get_view().get_selected_at(0).get_source();
        
        PhotoRenameDialog rename_dialog = new PhotoRenameDialog(item.get_title());
        string? new_name = rename_dialog.execute();
        if (new_name == null)
            return;
        
        RenamePhotoCommand command = new RenamePhotoCommand(item, new_name);
        get_command_manager().execute(command);
    }

    private void on_adjust_date_time() {
        if (get_view().get_selected_count() == 0)
            return;

        PhotoSource photo_source = (PhotoSource) get_view().get_selected_at(0).get_source();

        AdjustDateTimeDialog dialog = new AdjustDateTimeDialog(photo_source,
            get_view().get_selected_count());

        int64 time_shift;
        bool keep_relativity, modify_originals;
        if (dialog.execute(out time_shift, out keep_relativity, out modify_originals)) {
            AdjustDateTimePhotosCommand command = new AdjustDateTimePhotosCommand(
                get_view().get_selected(), time_shift, keep_relativity, modify_originals);
            get_command_manager().execute(command);
        }
    }
    
    private void on_external_edit() {
        if (get_view().get_selected_count() != 1)
            return;
        
        Photo photo = (Photo) get_view().get_selected_at(0).get_source();
        try {
            AppWindow.get_instance().set_busy_cursor();
            photo.open_with_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            AppWindow.error_message(Resources.launch_editor_failed(err));
        }
    }
    
    private void on_external_edit_raw() {
        if (get_view().get_selected_count() != 1)
            return;
        
        Photo photo = (Photo) get_view().get_selected_at(0).get_source();
        if (photo.get_master_file_format() != PhotoFileFormat.RAW)
            return;
        
        try {
            AppWindow.get_instance().set_busy_cursor();
            photo.open_master_with_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            AppWindow.error_message(Resources.launch_editor_failed(err));
        }
    }
    
    private void on_jump_to_file() {
        if (get_view().get_selected_count() != 1)
            return;
        
        LibraryPhoto photo = (LibraryPhoto) get_view().get_selected_at(0).get_source();
        try {
            AppWindow.get_instance().show_file_uri(photo.get_master_file().get_parent());
        } catch (Error err) {
            AppWindow.error_message(Resources.jump_to_file_failed(err));
        }
    }
    
#if !NO_SET_BACKGROUND
    public void on_set_background() {
        if (get_view().get_selected_count() != 1)
            return;
        
        TransformablePhoto photo = (TransformablePhoto) get_view().get_selected_at(0).get_source();
        if (photo == null)
            return;
        
        AppWindow.get_instance().set_busy_cursor();
        set_desktop_background(photo);
        AppWindow.get_instance().set_normal_cursor();
    }
#endif

    private void on_slideshow() {
        if (get_view().get_count() == 0)
            return;
        
        Thumbnail thumbnail = (Thumbnail) get_fullscreen_photo();
        if (thumbnail == null)
            return;
        
        AppWindow.get_instance().go_fullscreen(new SlideshowPage(LibraryPhoto.global, get_view(),
            thumbnail.get_photo()));
    }

    private void on_view_menu() {
        set_item_sensitive("/CollectionMenuBar/ViewMenu/IncreaseSize", scale < Thumbnail.MAX_SCALE);
        set_item_sensitive("/CollectionMenuBar/ViewMenu/DecreaseSize", scale > Thumbnail.MIN_SCALE);
        set_item_sensitive("/CollectionMenuBar/ViewMenu/Fullscreen", get_view().get_count() > 0);
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
    
    private void on_display_tags(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_tags(display);
        
        Config.get_instance().set_display_photo_tags(display);
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

        return value;
    }
    
    private int get_sort_order() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/CollectionMenuBar/ViewMenu/SortPhotos/SortAscending");
        assert(action != null);
        
        int value = action.get_current_value();
        
        return value;
    }
    
    private bool is_sort_ascending() {
        return get_sort_order() == SORT_ORDER_ASCENDING;
    }
    
    private void on_sort_changed() {
        get_view().set_comparator(get_sort_comparator());

        set_config_photos_sort(get_sort_order() == SORT_ORDER_ASCENDING, get_sort_criteria());
    }
    
    private Comparator get_sort_comparator() {
        switch (get_sort_criteria()) {
            case SortBy.TITLE:
                if (is_sort_ascending())
                    return Thumbnail.title_ascending_comparator;
                else
                    return Thumbnail.title_descending_comparator;
            
            case SortBy.EXPOSURE_DATE:
                if (is_sort_ascending())
                    return Thumbnail.exposure_time_ascending_comparator;
                else
                    return Thumbnail.exposure_time_desending_comparator;
            
            default:
                error("Unknown sort criteria: %d", get_sort_criteria());
                
                return Thumbnail.title_ascending_comparator;
        }
    }

    private override void set_display_titles(bool display) {
        base.set_display_titles(display);
    
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewTitle");
        if (action != null)
            action.set_active(display);
    }
    
    private void set_display_tags(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SHOW_TAGS, display);
        get_view().thaw_notifications();
        
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewTags");
        if (action != null)
            action.set_active(display);
    }

    protected abstract void get_config_photos_sort(out bool sort_order, out int sort_by);

    protected abstract void set_config_photos_sort(bool sort_order, int sort_by);

    private string get_sortby_path(int sort_by) {
        string path = "";

        switch(sort_by) {
            case SortBy.TITLE:
                path = "/CollectionMenuBar/ViewMenu/SortPhotos/SortByTitle";
                break;
            case SortBy.EXPOSURE_DATE:
                path = "/CollectionMenuBar/ViewMenu/SortPhotos/SortByExposureDate";
                break;
            default:
                error("Unknown sort criteria: %d", sort_by);
                break;
        }

        return path;
    }

    private void sync_sort() {
        bool sort_order;
        int sort_by;
        get_config_photos_sort(out sort_order, out sort_by);

        string path = get_sortby_path(sort_by);

        bool resort_needed = false;

        Gtk.RadioAction sort_by_action = (Gtk.RadioAction) ui.get_action(path);
        if (sort_by_action != null && sort_by_action.get_current_value() != sort_by) {
            sort_by_action.set_current_value(sort_by);
            resort_needed = true;
        }

        Gtk.RadioAction ascending_action = 
            (Gtk.RadioAction) ui.get_action("/CollectionMenuBar/ViewMenu/SortPhotos/SortAscending");

        int sort_order_int = sort_order ? SORT_ORDER_ASCENDING : SORT_ORDER_DESCENDING;
        if (ascending_action != null && ascending_action.get_current_value() != sort_order_int) {
            ascending_action.set_current_value(sort_order_int);
            resort_needed = true;
        }

        if (resort_needed)
            get_view().set_comparator(get_sort_comparator());
    }
    
    private void on_new_event() {
        if (get_view().get_selected_count() > 0)
            get_command_manager().execute(new NewEventCommand(get_view().get_selected()));
    }
    
    private void on_add_tags() {
        if (get_view().get_selected_count() == 0)
            return;
        
        AddTagsDialog dialog = new AddTagsDialog();
        string[]? names = dialog.execute();
        if (names != null) {
            get_command_manager().execute(new AddTagsCommand(names, 
                (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources()));
        }
    }

    public static int get_photo_thumbnail_scale() {
        return slider_to_scale(slider_adjustment.get_value());
    }
}

public class LibraryPage : CollectionPage {
    public LibraryPage(ProgressMonitor? monitor = null) {
        base(_("Photos"));
        
        get_view().freeze_notifications();
        get_view().monitor_source_collection(LibraryPhoto.global, new CollectionViewManager(this),
            (Gee.Iterable<DataSource>) LibraryPhoto.global.get_all(), monitor);
        get_view().thaw_notifications();
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

