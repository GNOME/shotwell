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

public enum RatingFilter {
    NO_FILTER = 0,
    REJECTED_OR_HIGHER = 1,
    UNRATED_OR_HIGHER = 2,
    ONE_OR_HIGHER = 3,
    TWO_OR_HIGHER = 4,
    THREE_OR_HIGHER = 5,
    FOUR_OR_HIGHER = 6,
    FIVE_OR_HIGHER = 7,
    REJECTED_ONLY = 8,
    UNRATED_ONLY = 9,
    ONE_ONLY = 10,
    TWO_ONLY = 11,
    THREE_ONLY = 12,
    FOUR_ONLY = 13,
    FIVE_ONLY = 14
}

public abstract class CollectionPage : CheckerboardPage {
    public const int SORT_ORDER_ASCENDING = 0;
    public const int SORT_ORDER_DESCENDING = 1;

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public const int MANUAL_STEPPING = 16;
    public const int SLIDER_STEPPING = 4;
    
    private const int FILTER_BUTTON_MARGIN = 12; // the distance between icon and edge of button
    private const float FILTER_ICON_SCALE = 0.65f; // changes the size of the filter icon
    
    // filter_icon_base_width is the width (in px) of a single filter icon such as one star or an "X"
    private const int FILTER_ICON_BASE_WIDTH = 30;
    // filter_icon_plus_width is the width (in px) of the plus icon
    private const int FILTER_ICON_PLUS_WIDTH = 20;

    public enum SortBy {
        TITLE = 1,
        EXPOSURE_DATE = 2,
        RATING = 3;
    }

    private static Gtk.Adjustment slider_adjustment = null;
    
    private Gtk.HScale slider = null;
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToolButton enhance_button = null;
    private Gtk.ToolButton slideshow_button = null;
    private Gtk.ToolButton filter_button = null;
    private Gtk.Menu filter_menu = null;
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

        // Adds one menu entry per alien database driver
        foreach (AlienDatabaseDriver driver in AlienDatabaseHandler.get_instance().get_drivers()) {
            ui.add_ui(ui.new_merge_id(), "/CollectionMenuBar/FileMenu/ImportFromAlienDbPlaceholder",
                driver.get_menu_name(),
                driver.get_action_entry().name,
                Gtk.UIManagerItemType.MENUITEM, false);
        }
        
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
        ui.add_ui(ui.new_merge_id(), "/CollectionMenuBar/FileMenu/SetBackgroundPlaceholder",
            "SetBackground", "SetBackground", Gtk.UIManagerItemType.MENUITEM, false);
#endif 
            
        bool sort_order;
        int sort_by;
        get_config_photos_sort(out sort_order, out sort_by);

        action_group.add_radio_actions(create_sort_crit_actions(), sort_by, on_sort_changed);
        action_group.add_radio_actions(create_sort_order_actions(), sort_order ?
            SORT_ORDER_ASCENDING : SORT_ORDER_DESCENDING, on_sort_changed);
        action_group.add_radio_actions(create_view_filter_actions(), get_config_rating_filter(), 
            on_view_filter_changed);

        if (ui_filename != null)
            init_load_ui(ui_filename);
        
        if (child_actions != null)
            action_group.add_actions(child_actions, this);
        
        init_ui_bind("/CollectionMenuBar");
        init_item_context_menu("/CollectionContextMenu");
        
        get_view().set_comparator(get_sort_comparator(), get_sort_comparator_predicate());
        get_view().contents_altered.connect(on_contents_altered);
        get_view().selection_group_altered.connect(on_selection_changed);
        get_view().items_visibility_changed.connect(on_contents_altered);
        get_view().items_altered.connect(on_photos_altered);
        
        get_view().freeze_notifications();
        get_view().set_property(CheckerboardItem.PROP_SHOW_TITLES, 
            Config.get_instance().get_display_photo_titles());
        get_view().set_property(Thumbnail.PROP_SHOW_TAGS, 
            Config.get_instance().get_display_photo_tags());
        get_view().set_property(Thumbnail.PROP_SIZE, scale);
        get_view().set_property(Thumbnail.PROP_SHOW_RATINGS,
            Config.get_instance().get_display_photo_ratings());
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
        rotate_button.clicked.connect(on_rotate_clockwise);
        
        toolbar.insert(rotate_button, -1);

        // enhance tool
        enhance_button = new Gtk.ToolButton.from_stock(Resources.ENHANCE);
        enhance_button.set_label(Resources.ENHANCE_LABEL);
        enhance_button.set_tooltip_text(Resources.ENHANCE_TOOLTIP);
        enhance_button.sensitive = false;
        enhance_button.is_important = true;
        enhance_button.clicked.connect(on_enhance);

        toolbar.insert(enhance_button, -1);

        // separator
        toolbar.insert(new Gtk.SeparatorToolItem(), -1);
        
        // slideshow button
        slideshow_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PLAY);
        slideshow_button.set_label(_("Slideshow"));
        slideshow_button.set_tooltip_text(_("Start a slideshow of these photos"));
        slideshow_button.set_related_action(action_group.get_action("Slideshow"));
        slideshow_button.is_important = true;
        slideshow_button.clicked.connect(on_slideshow);
        
        toolbar.insert(slideshow_button, -1);

#if !NO_PUBLISHING
        // publish button
        publish_button = new Gtk.ToolButton.from_stock(Resources.PUBLISH);
        publish_button.set_label(Resources.PUBLISH_LABEL);
        publish_button.set_tooltip_text(Resources.PUBLISH_TOOLTIP);
        publish_button.set_sensitive(false);
        publish_button.is_important = true;
        publish_button.clicked.connect(on_publish);
        
        toolbar.insert(publish_button, -1);
#endif
        
        // separator to force slider to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);

        filter_menu = (Gtk.Menu) ui.get_widget("/FilterPopupMenu");
        filter_button = new Gtk.ToolButton(get_filter_icon(RatingFilter.UNRATED_OR_HIGHER), null);
        filter_button.clicked.connect(on_filter_button_pressed);
        filter_button.set_expand(false);

        toolbar.insert(filter_button, -1);

        Gtk.SeparatorToolItem separator2 = new Gtk.SeparatorToolItem();
        separator2.set_expand(true);
        separator2.set_draw(false);
        
        toolbar.insert(separator2, -1);
        
        // thumbnail size slider
        slider = new Gtk.HScale(slider_adjustment);
        slider.value_changed.connect(on_slider_changed);
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

        // watch for updates to the external app settings
        Config.get_instance().external_app_changed.connect(on_external_app_changed);
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
        
        // Add one action per alien database driver
        foreach (AlienDatabaseDriver driver in AlienDatabaseHandler.get_instance().get_drivers()) {
            Gtk.ActionEntry import_from_alien_db = driver.get_action_entry();
            actions += import_from_alien_db;
        }

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
        
        Gtk.ActionEntry remove_from_library = { "RemoveFromLibrary", Gtk.STOCK_REMOVE, TRANSLATABLE,
            null, TRANSLATABLE, on_remove_from_library };
        remove_from_library.label = Resources.REMOVE_FROM_LIBRARY_MENU;
        remove_from_library.tooltip = Resources.REMOVE_FROM_LIBRARY_PLURAL_TOOLTIP;
        actions += remove_from_library;
        
        Gtk.ActionEntry move_to_trash = { "MoveToTrash", "user-trash-full", TRANSLATABLE, "Delete",
            TRANSLATABLE, on_move_to_trash };
        move_to_trash.label = Resources.MOVE_TO_TRASH_MENU;
        move_to_trash.tooltip = Resources.MOVE_TO_TRASH_PLURAL_TOOLTIP;
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

        Gtk.ActionEntry hflip = { "FlipHorizontally", Resources.HFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_horizontally };
        hflip.label = Resources.HFLIP_MENU;
        hflip.tooltip = Resources.HFLIP_TOOLTIP;
        actions += hflip;
        
        Gtk.ActionEntry vflip = { "FlipVertically", Resources.VFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_vertically };
        vflip.label = Resources.VFLIP_MENU;
        vflip.tooltip = Resources.VFLIP_TOOLTIP;
        actions += vflip;

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
        
#if !NO_SET_BACKGROUND
        Gtk.ActionEntry set_background = { "SetBackground", null, TRANSLATABLE, "<Ctrl>B",
            TRANSLATABLE, on_set_background };
        set_background.label = Resources.SET_BACKGROUND_MENU;
        set_background.tooltip = Resources.SET_BACKGROUND_TOOLTIP;
        actions += set_background;
#endif
        
        Gtk.ActionEntry set_rating = { "Rate", null, TRANSLATABLE, null, null, null };
        set_rating.label = Resources.RATING_MENU;
        actions += set_rating;

        Gtk.ActionEntry increase_rating = { "IncreaseRating", null, TRANSLATABLE, 
            "greater", TRANSLATABLE, on_increase_rating };
        increase_rating.label = Resources.INCREASE_RATING_MENU;
        increase_rating.tooltip = Resources.INCREASE_RATING_TOOLTIP;
        actions += increase_rating;

        Gtk.ActionEntry decrease_rating = { "DecreaseRating", null, TRANSLATABLE, 
            "less", TRANSLATABLE, on_decrease_rating };
        decrease_rating.label = Resources.DECREASE_RATING_MENU;
        decrease_rating.tooltip = Resources.DECREASE_RATING_TOOLTIP;
        actions += decrease_rating;

        Gtk.ActionEntry rate_rejected = { "RateRejected", null, TRANSLATABLE, 
            "9", TRANSLATABLE, on_rate_rejected };
        rate_rejected.label = Resources.rating_menu(Rating.REJECTED);
        rate_rejected.tooltip = Resources.rating_tooltip(Rating.REJECTED);
        actions += rate_rejected;

        Gtk.ActionEntry rate_unrated = { "RateUnrated", null, TRANSLATABLE, 
            "0", TRANSLATABLE, on_rate_unrated };
        rate_unrated.label = Resources.rating_menu(Rating.UNRATED);
        rate_unrated.tooltip = Resources.rating_tooltip(Rating.UNRATED);
        actions += rate_unrated;

        Gtk.ActionEntry rate_one = { "RateOne", null, TRANSLATABLE, 
            "1", TRANSLATABLE, on_rate_one };
        rate_one.label = Resources.rating_menu(Rating.ONE);
        rate_one.tooltip = Resources.rating_tooltip(Rating.ONE);
        actions += rate_one;

        Gtk.ActionEntry rate_two = { "RateTwo", null, TRANSLATABLE, 
            "2", TRANSLATABLE, on_rate_two };
        rate_two.label = Resources.rating_menu(Rating.TWO);
        rate_two.tooltip = Resources.rating_tooltip(Rating.TWO);
        actions += rate_two;

        Gtk.ActionEntry rate_three = { "RateThree", null, TRANSLATABLE, 
            "3", TRANSLATABLE, on_rate_three };
        rate_three.label = Resources.rating_menu(Rating.THREE);
        rate_three.tooltip = Resources.rating_tooltip(Rating.THREE);
        actions += rate_three;

        Gtk.ActionEntry rate_four = { "RateFour", null, TRANSLATABLE, 
            "4", TRANSLATABLE, on_rate_four };
        rate_four.label = Resources.rating_menu(Rating.FOUR);
        rate_four.tooltip = Resources.rating_tooltip(Rating.FOUR);
        actions += rate_four;

        Gtk.ActionEntry rate_five = { "RateFive", null, TRANSLATABLE, 
            "5", TRANSLATABLE, on_rate_five };
        rate_five.label = Resources.rating_menu(Rating.FIVE);
        rate_five.tooltip = Resources.rating_tooltip(Rating.FIVE);
        actions += rate_five;

        Gtk.ActionEntry duplicate = { "Duplicate", null, TRANSLATABLE, "<Ctrl>D", TRANSLATABLE,
            on_duplicate_photo };
        duplicate.label = Resources.DUPLICATE_PHOTO_MENU;
        duplicate.tooltip = Resources.DUPLICATE_PHOTO_TOOLTIP;
        actions += duplicate;

        Gtk.ActionEntry edit_title = { "EditTitle", null, TRANSLATABLE, "F2", TRANSLATABLE,
            on_edit_title };
        edit_title.label = Resources.EDIT_TITLE_MENU;
        edit_title.tooltip = Resources.EDIT_TITLE_TOOLTIP;
        actions += edit_title;

        Gtk.ActionEntry adjust_date_time = { "AdjustDateTime", null, TRANSLATABLE, null,
            TRANSLATABLE, on_adjust_date_time };
        adjust_date_time.label = Resources.ADJUST_DATE_TIME_MENU;
        adjust_date_time.tooltip = Resources.ADJUST_DATE_TIME_TOOLTIP;
        actions += adjust_date_time;
        
        Gtk.ActionEntry external_edit = { "ExternalEdit", Gtk.STOCK_EDIT, TRANSLATABLE, "<Ctrl>Return",
            TRANSLATABLE, on_external_edit };
        external_edit.label = Resources.EXTERNAL_EDIT_MENU;
        external_edit.tooltip = Resources.EXTERNAL_EDIT_TOOLTIP;
        actions += external_edit;
        
        Gtk.ActionEntry edit_raw = { "ExternalEditRAW", null, TRANSLATABLE, "<Ctrl><Shift>Return", 
            TRANSLATABLE, on_external_edit_raw };
        edit_raw.label = Resources.EXTERNAL_EDIT_RAW_MENU;
        edit_raw.tooltip = Resources.EXTERNAL_EDIT_RAW_TOOLTIP;
        actions += edit_raw;
        
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

        Gtk.ActionEntry filter_photos = { "FilterPhotos", null, TRANSLATABLE, null, null, null };
        filter_photos.label = Resources.FILTER_PHOTOS_MENU;
        actions += filter_photos;

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
        
        Gtk.ToggleActionEntry ratings = { "ViewRatings", null, TRANSLATABLE, "<Ctrl><Shift>R",
            TRANSLATABLE, on_display_ratings, Config.get_instance().get_display_photo_ratings() };
        ratings.label = Resources.VIEW_RATINGS_MENU;
        ratings.tooltip = Resources.VIEW_RATINGS_TOOLTIP;
        toggle_actions += ratings;
        
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

        Gtk.RadioActionEntry by_rating = { "SortByRating", null, TRANSLATABLE, null,
            TRANSLATABLE, SortBy.RATING };
        by_rating.label = _("By _Rating");
        by_rating.tooltip = _("Sort photos by rating");
        sort_crit_actions += by_rating;

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
    
    private Gtk.RadioActionEntry[] create_view_filter_actions() {
        Gtk.RadioActionEntry[] view_filter_actions = new Gtk.RadioActionEntry[0];

        Gtk.RadioActionEntry rejected_or_higher = { "DisplayRejectedOrHigher", null, TRANSLATABLE,
            "<Ctrl><Shift>9", TRANSLATABLE, RatingFilter.REJECTED_OR_HIGHER };
        rejected_or_higher.label = Resources.DISPLAY_REJECTED_OR_HIGHER_MENU;
        rejected_or_higher.tooltip = Resources.DISPLAY_REJECTED_OR_HIGHER_TOOLTIP;
        view_filter_actions += rejected_or_higher;

        Gtk.RadioActionEntry unrated_or_higher = { "DisplayUnratedOrHigher", null, TRANSLATABLE, 
            "<Ctrl><Shift>0", TRANSLATABLE, RatingFilter.UNRATED_OR_HIGHER };
        unrated_or_higher.label = Resources.DISPLAY_UNRATED_OR_HIGHER_MENU;
        unrated_or_higher.tooltip = Resources.DISPLAY_UNRATED_OR_HIGHER_TOOLTIP;
        view_filter_actions += unrated_or_higher;

        Gtk.RadioActionEntry one_or_higher = { "DisplayOneOrHigher", null, TRANSLATABLE,
            "<Ctrl><Shift>1", TRANSLATABLE, RatingFilter.ONE_OR_HIGHER };
        one_or_higher.label = Resources.DISPLAY_ONE_OR_HIGHER_MENU;
        one_or_higher.tooltip = Resources.DISPLAY_ONE_OR_HIGHER_TOOLTIP;
        view_filter_actions += one_or_higher;

        Gtk.RadioActionEntry two_or_higher = { "DisplayTwoOrHigher", null, TRANSLATABLE,
            "<Ctrl><Shift>2", TRANSLATABLE, RatingFilter.TWO_OR_HIGHER };
        two_or_higher.label = Resources.DISPLAY_TWO_OR_HIGHER_MENU;
        two_or_higher.tooltip = Resources.DISPLAY_TWO_OR_HIGHER_TOOLTIP;
        view_filter_actions += two_or_higher;

        Gtk.RadioActionEntry three_or_higher = { "DisplayThreeOrHigher", null, TRANSLATABLE,
            "<Ctrl><Shift>3", TRANSLATABLE, RatingFilter.THREE_OR_HIGHER };
        three_or_higher.label = Resources.DISPLAY_THREE_OR_HIGHER_MENU;
        three_or_higher.tooltip = Resources.DISPLAY_THREE_OR_HIGHER_TOOLTIP;
        view_filter_actions += three_or_higher;

        Gtk.RadioActionEntry four_or_higher = { "DisplayFourOrHigher", null, TRANSLATABLE,
            "<Ctrl><Shift>4", TRANSLATABLE, RatingFilter.FOUR_OR_HIGHER };
        four_or_higher.label = Resources.DISPLAY_FOUR_OR_HIGHER_MENU;
        four_or_higher.tooltip = Resources.DISPLAY_FOUR_OR_HIGHER_TOOLTIP;
        view_filter_actions += four_or_higher;

        Gtk.RadioActionEntry five_or_higher = { "DisplayFiveOrHigher", null, TRANSLATABLE,
            "<Ctrl><Shift>5", TRANSLATABLE, RatingFilter.FIVE_OR_HIGHER };
        five_or_higher.label = Resources.DISPLAY_FIVE_OR_HIGHER_MENU;
        five_or_higher.tooltip = Resources.DISPLAY_FIVE_OR_HIGHER_TOOLTIP;
        view_filter_actions += five_or_higher;

        return view_filter_actions;
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
        set_display_ratings(Config.get_instance().get_display_photo_ratings());
        get_view().thaw_notifications();

        sync_sort();

        restore_saved_rating_view_filter();  // Set filter to current level and set menu selection
        
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
        set_action_sensitive("ExternalEdit", selected && Config.get_instance().get_external_photo_app() != "");
        set_action_sensitive("Revert", can_revert_selected());
        
#if !NO_SET_BACKGROUND
        set_action_sensitive("SetBackground", selected_count == 1);
#endif
        base.init_actions(selected_count, count);
    }

    protected override bool on_mousewheel_up(Gdk.EventScroll event) {
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            on_increase_size();
            return true;
        } else {
            return base.on_mousewheel_up(event);
        }
    }
    
    protected override bool on_mousewheel_down(Gdk.EventScroll event) {
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            on_decrease_size();
            return true;
        } else {
            return base.on_mousewheel_down(event);
        }
    }

    private void on_contents_altered() {
        set_action_sensitive("Slideshow", get_view().get_count() > 0);
    }
    
    private void on_photos_altered() {
        // since the photo can be altered externally to Shotwell now, need to make the revert
        // command available appropriately, even if the selection doesn't change
        set_action_sensitive("Revert", can_revert_selected());
    }
    
#if !NO_PRINTING
    private void on_print() {
        if (get_view().get_selected_count() == 1)
            PrintManager.get_instance().spool_photo((Photo) get_view().get_selected_at(0).get_source());
    }

    private void on_page_setup() {
        PrintManager.get_instance().do_page_setup();
    }
#endif
    
    private void on_selection_changed() {
        int selected_count = get_view().get_selected_count();
        bool has_selected = selected_count > 0;
        
        rotate_button.sensitive = has_selected;
#if !NO_PUBLISHING
        publish_button.set_sensitive(has_selected);
#endif
        enhance_button.sensitive = has_selected;
        
        set_action_sensitive("ExternalEdit", selected_count == 1 && Config.get_instance().get_external_photo_app() != "");
        set_action_sensitive("Revert", can_revert_selected());
        set_action_sensitive("RemoveFromLibrary", has_selected);
        set_action_sensitive("MoveToTrash", has_selected);
        set_action_sensitive("Duplicate", has_selected);
        update_rating_sensitivities();
        
#if !NO_SET_BACKGROUND
        set_action_sensitive("SetBackground", selected_count == 1);
#endif
    }
    
    private void update_rating_sensitivities() {
        set_action_sensitive("RateRejected", can_rate_selected(Rating.REJECTED));
        set_action_sensitive("RateUnrated", can_rate_selected(Rating.UNRATED));
        set_action_sensitive("RateOne", can_rate_selected(Rating.ONE));
        set_action_sensitive("RateTwo", can_rate_selected(Rating.TWO));
        set_action_sensitive("RateThree", can_rate_selected(Rating.THREE));
        set_action_sensitive("RateFour", can_rate_selected(Rating.FOUR));
        set_action_sensitive("RateFive", can_rate_selected(Rating.FIVE));
        set_action_sensitive("IncreaseRating", can_increase_selected_rating());
        set_action_sensitive("DecreaseRating", can_decrease_selected_rating());
    }

    private void on_external_app_changed() {
        int selected_count = get_view().get_selected_count();
        
        set_action_sensitive("ExternalEdit", selected_count == 1 && Config.get_instance().get_external_photo_app() != "");
    }
    
    private void on_filter_button_pressed() {
        filter_menu.popup(null, null, position_popup, 0, Gtk.get_current_event_time());
    }
    
    private void position_popup(Gtk.Menu menu, out int x, out int y, out bool push_in) {
        menu.realize();
        int rx, ry;
        get_container().get_child().window.get_root_origin(out rx, out ry);
        
        x = rx + filter_button.allocation.x;
        y = ry + get_menubar().allocation.height + get_toolbar().allocation.y 
            - menu.allocation.height;
        push_in = false;
    }
    
    // see #2020
    // doubel clcik = switch to photo page
    // Super + double click = open in external editor
    // Enter = switch to PhotoPage
    // Ctrl + Enter = open in external editor (handled with accelerators)
    // Shift + Ctrl + Enter = open in external RAW editor (handled with accelerators)
    protected override void on_item_activated(CheckerboardItem item, CheckerboardPage.Activator 
        activator, CheckerboardPage.KeyboardModifiers modifiers) {
        Thumbnail thumbnail = (Thumbnail) item;

        // switch to full-page view or open in external editor
        debug("activating %s", thumbnail.get_photo().to_string());

        if (activator == CheckerboardPage.Activator.MOUSE) {
            if (modifiers.super_pressed)
                on_external_edit();
            else
                LibraryWindow.get_app().switch_to_photo_page(this, thumbnail.get_photo());
        } else if (activator == CheckerboardPage.Activator.KEYBOARD) {
            if (!modifiers.shift_pressed && !modifiers.ctrl_pressed)
                LibraryWindow.get_app().switch_to_photo_page(this, thumbnail.get_photo());
        }
    }

    protected override bool on_context_invoked() {
        bool one_selected = get_view().get_selected_count() == 1;
        bool selected = get_view().get_selected_count() > 0;
        bool revert_possible = can_revert_selected();
#if !NO_RAW
        bool is_single_raw = one_selected && 
            ((Photo) get_view().get_selected_at(0).get_source()).get_master_file_format() == 
            PhotoFileFormat.RAW;
#endif
        
        set_item_sensitive("/CollectionContextMenu/ContextMoveToTrash", selected);
        set_item_sensitive("/CollectionContextMenu/ContextEnhance", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRevert", selected && revert_possible);
        set_item_sensitive("/CollectionContextMenu/ContextModifyTags", one_selected);
        set_item_sensitive("/CollectionContextMenu/ContextEditTitle", one_selected);
        
#if !NO_RAW
        if (is_single_raw)
            set_item_visible("/CollectionContextMenu/ContextExternalEditRAW", Config.get_instance().get_external_raw_app() != "");
        else
            set_item_hidden("/CollectionContextMenu/ContextExternalEditRAW");
#endif
        
        return base.on_context_invoked();
    }
    
    public override string? get_icon_name() {
        return Resources.ICON_PHOTOS;
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

            case "period":
                on_increase_rating();
            break;
            
            case "comma":
                on_decrease_rating();
            break;

            case "KP_1":
                on_rate_one();
            break;
            
            case "KP_2":
                on_rate_two();
            break;

            case "KP_3":
                on_rate_three();
            break;
        
            case "KP_4":
                on_rate_four();
            break;

            case "KP_5":
                on_rate_five();
            break;

            case "KP_0":
                on_rate_unrated();
            break;

            case "KP_9":
                on_rate_rejected();
            break;
            
            case "exclam":
                if (get_ctrl_pressed())
                    set_rating_view_filter(RatingFilter.ONE_OR_HIGHER);
            break;

            case "at":
                if (get_ctrl_pressed())
                    set_rating_view_filter(RatingFilter.TWO_OR_HIGHER);
            break;

            case "numbersign":
                if (get_ctrl_pressed())
                    set_rating_view_filter(RatingFilter.THREE_OR_HIGHER);
            break;

            case "dollar":
                if (get_ctrl_pressed())
                    set_rating_view_filter(RatingFilter.FOUR_OR_HIGHER);
            break;

            case "percent":
                if (get_ctrl_pressed())
                    set_rating_view_filter(RatingFilter.FIVE_OR_HIGHER);
            break;

            case "parenright":
                if (get_ctrl_pressed())
                    set_rating_view_filter(RatingFilter.UNRATED_OR_HIGHER);
            break;

            case "parenleft":
                if (get_ctrl_pressed())
                    set_rating_view_filter(RatingFilter.REJECTED_OR_HIGHER);
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
    }

    private void on_events_menu() {
        set_item_sensitive("/CollectionMenuBar/EventsMenu/NewEvent", get_view().get_selected_count() > 0);
    }
    
    protected virtual void on_tags_menu() {
        set_item_sensitive("/CollectionMenuBar/TagsMenu/AddTags", get_view().get_selected_count() > 0);
        set_item_sensitive("/CollectionMenuBar/TagsMenu/ModifyTags", get_view().get_selected_count() == 1);
    }
    
    private bool can_revert_selected() {
        foreach (DataView view in get_view().get_selected()) {
            LibraryPhoto photo = ((Thumbnail) view).get_photo();
            if (photo.has_transformations() || photo.has_editable())
                return true;
        }
        
        return false;
    }
    
    private bool can_revert_editable_selected() {
        foreach (DataView view in get_view().get_selected()) {
            LibraryPhoto photo = ((Thumbnail) view).get_photo();
            if (photo.has_editable())
                return true;
        }
        
        return false;
    }

    private bool can_rate_selected(Rating rating) {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_photo().get_rating() != rating)
                return true;
        }
        
        return false;
    }

    private bool can_increase_selected_rating() {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_photo().get_rating().can_increase())
                return true;
        }
        
        return false;
    }

    private bool can_decrease_selected_rating() {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_photo().get_rating().can_decrease())
                return true;
        }
        
        return false;
    }

    
    protected virtual void on_photos_menu() {
        bool selected = (get_view().get_selected_count() > 0);
        bool one_selected = get_view().get_selected_count() == 1;
#if !NO_RAW
        bool is_single_raw = one_selected &&
            ((Photo) get_view().get_selected_at(0).get_source()).get_master_file_format() == 
            PhotoFileFormat.RAW;
#endif
        
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateClockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateCounterclockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/FlipHorizontally", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/FlipVertically", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Enhance", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/AdjustDateTime", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/EditTitle", one_selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Rate", selected);
        
#if !NO_RAW
        if (is_single_raw)
            set_item_visible("/CollectionMenuBar/PhotosMenu/ExternalEditRAW", Config.get_instance().get_external_raw_app() != "");
        else
            set_item_hidden("/CollectionMenuBar/PhotosMenu/ExternalEditRAW");
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
        remove_photos_from_library((Gee.Collection<LibraryPhoto>) get_view().get_selected_sources());
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
    
    private void on_flip_horizontally() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(),
            Rotation.MIRROR, Resources.HFLIP_LABEL, Resources.HFLIP_TOOLTIP, _("Flipping Horizontally"),
            _("Undoing Flip Horizontally"));
        get_command_manager().execute(command);
    }
    
    private void on_flip_vertically() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(),
            Rotation.UPSIDE_DOWN, Resources.VFLIP_LABEL, Resources.VFLIP_TOOLTIP, _("Flipping Vertically"),
            _("Undoing Flip Vertically"));
        get_command_manager().execute(command);
    }
    
    private void on_revert() {
        if (get_view().get_selected_count() == 0)
            return;
        
        if (can_revert_editable_selected()) {
            if (!revert_editable_dialog(AppWindow.get_instance(),
                (Gee.Collection<Photo>) get_view().get_selected_sources())) {
                return;
            }
            
            foreach (DataObject object in get_view().get_selected_sources())
                ((Photo) object).revert_to_master();
        }
        
        RevertMultipleCommand command = new RevertMultipleCommand(get_view().get_selected());
        get_command_manager().execute(command);
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

    private void on_increase_rating() {
        if (get_view().get_selected_count() == 0)
            return;
        
        SetRatingCommand command = new SetRatingCommand.inc_dec(get_view().get_selected(), true);
        get_command_manager().execute(command);

        update_rating_sensitivities();
    }

    private void on_decrease_rating() {
        if (get_view().get_selected_count() == 0)
            return;
        
        SetRatingCommand command = new SetRatingCommand.inc_dec(get_view().get_selected(), false);
        get_command_manager().execute(command);

        update_rating_sensitivities();
    }

    private void on_set_rating(Rating rating) {
        if (get_view().get_selected_count() == 0)
            return;
        
        SetRatingCommand command = new SetRatingCommand(get_view().get_selected(), rating);
        get_command_manager().execute(command);

        update_rating_sensitivities();
    }

    private void on_rate_rejected() {
        on_set_rating(Rating.REJECTED);
    }
    
    private void on_rate_unrated() {
        on_set_rating(Rating.UNRATED);
    }

    private void on_rate_one() {
        on_set_rating(Rating.ONE);
    }

    private void on_rate_two() {
        on_set_rating(Rating.TWO);
    }

    private void on_rate_three() {
        on_set_rating(Rating.THREE);
    }

    private void on_rate_four() {
        on_set_rating(Rating.FOUR);
    }

    private void on_rate_five() {
        on_set_rating(Rating.FIVE);
    }
    
    private void on_duplicate_photo() {
        if (get_view().get_selected_count() == 0)
            return;
        
        DuplicateMultiplePhotosCommand command = new DuplicateMultiplePhotosCommand(
            get_view().get_selected());
        get_command_manager().execute(command);
    }

    private void on_edit_title() {
        // only edit one title at a time
        if (get_view().get_selected_count() != 1)
            return;
        
        LibraryPhoto item = (LibraryPhoto) get_view().get_selected_at(0).get_source();
        
        EditTitleDialog edit_title_dialog = new EditTitleDialog(item.get_title());
        string? new_title = edit_title_dialog.execute();
        if (new_title == null)
            return;
        
        EditTitleCommand command = new EditTitleCommand(item, new_title);
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
#if !NO_RAW
        if (photo.get_master_file_format() != PhotoFileFormat.RAW)
            return;
#endif        

        try {
            AppWindow.get_instance().set_busy_cursor();
            photo.open_master_with_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            AppWindow.error_message(Resources.launch_editor_failed(err));
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

    private void set_rating_view_filter_menu(RatingFilter filter) {
        Gtk.ToggleAction action;
        
        switch (filter) {
            case RatingFilter.UNRATED_OR_HIGHER:
                action = (Gtk.ToggleAction) action_group.get_action("DisplayUnratedOrHigher");
            break;
            case RatingFilter.ONE_OR_HIGHER:
                action = (Gtk.ToggleAction) action_group.get_action("DisplayOneOrHigher");
            break;
            case RatingFilter.TWO_OR_HIGHER:
                action = (Gtk.ToggleAction) action_group.get_action("DisplayTwoOrHigher");
            break;
            case RatingFilter.THREE_OR_HIGHER:
                action = (Gtk.ToggleAction) action_group.get_action("DisplayThreeOrHigher");
                break;
            case RatingFilter.FOUR_OR_HIGHER:
                action = (Gtk.ToggleAction) action_group.get_action("DisplayFourOrHigher");
                break;
            case RatingFilter.FIVE_OR_HIGHER:
                action = (Gtk.ToggleAction) action_group.get_action("DisplayFiveOrHigher");
            break;
            case RatingFilter.REJECTED_OR_HIGHER:
            default:
                action = (Gtk.ToggleAction) action_group.get_action("DisplayRejectedOrHigher");
            break;
        }
        
        action.set_active(true);
    }

    private void on_view_filter_changed() {
        RatingFilter filter = get_filter_criteria();
        install_rating_filter(filter);
        set_filter_icon(filter);
        set_config_rating_filter(filter);
    }

    private void set_rating_view_filter(RatingFilter filter) {
        set_rating_view_filter_menu(filter);
        install_rating_filter(filter);
        set_filter_icon(filter);
        set_config_rating_filter(filter);
    }

    private void restore_saved_rating_view_filter() {
        RatingFilter filter = get_config_rating_filter();
        set_rating_view_filter_menu(filter);
        set_filter_icon(filter);
        install_rating_filter(filter);
    }

    private void install_rating_filter(RatingFilter filter) {
        switch (filter) {
            case RatingFilter.REJECTED_OR_HIGHER:
                use_rating_or_higher_filter(Rating.REJECTED);
            break;
            case RatingFilter.ONE_OR_HIGHER:
                use_rating_or_higher_filter(Rating.ONE);
            break;
            case RatingFilter.TWO_OR_HIGHER:
                use_rating_or_higher_filter(Rating.TWO);
            break;
            case RatingFilter.THREE_OR_HIGHER:
                use_rating_or_higher_filter(Rating.THREE);
            break;
            case RatingFilter.FOUR_OR_HIGHER:
                use_rating_or_higher_filter(Rating.FOUR);
            break;
            case RatingFilter.FIVE_OR_HIGHER:
                use_rating_or_higher_filter(Rating.FIVE);
            break;
            case RatingFilter.UNRATED_OR_HIGHER:
            default:
                use_rating_or_higher_filter(Rating.UNRATED);
            break;
        }
    }

    private int get_filter_button_size(RatingFilter filter) {
        return get_filter_icon_size(filter) + 2 * FILTER_BUTTON_MARGIN;
    }

    private int get_filter_icon_size(RatingFilter filter) {
        int icon_base = (int)(FILTER_ICON_BASE_WIDTH * FILTER_ICON_SCALE);
        int icon_plus = (int)(FILTER_ICON_PLUS_WIDTH * FILTER_ICON_SCALE);
        
        switch (filter) {
            case RatingFilter.ONE_OR_HIGHER:
                return icon_base + icon_plus;
            case RatingFilter.TWO_OR_HIGHER:
                return icon_base * 2 + icon_plus;
            case RatingFilter.THREE_OR_HIGHER:
                return icon_base * 3 + icon_plus;
            case RatingFilter.FOUR_OR_HIGHER:
                return icon_base * 4 + icon_plus;
            case RatingFilter.FIVE_OR_HIGHER:
            case RatingFilter.FIVE_ONLY:
                return icon_base * 5;
            case RatingFilter.REJECTED_OR_HIGHER:
                return icon_base * 2;
            case RatingFilter.UNRATED_OR_HIGHER:
            default:
                return icon_base;
        }
    }
    
    private Gtk.Widget get_filter_icon(RatingFilter filter) {
        string filename = null;

        switch (filter) {
            case RatingFilter.ONE_OR_HIGHER:
                filename = Resources.ICON_FILTER_ONE_OR_BETTER;
            break;
            
            case RatingFilter.TWO_OR_HIGHER:
                filename = Resources.ICON_FILTER_TWO_OR_BETTER;
            break;
            
            case RatingFilter.THREE_OR_HIGHER:
                filename = Resources.ICON_FILTER_THREE_OR_BETTER;
            break;
            
            case RatingFilter.FOUR_OR_HIGHER:
                filename = Resources.ICON_FILTER_FOUR_OR_BETTER;
            break;
            
            case RatingFilter.FIVE_OR_HIGHER:
                filename = Resources.ICON_FILTER_FIVE;
            break;
            
            case RatingFilter.REJECTED_OR_HIGHER:
                filename = Resources.ICON_FILTER_REJECTED_OR_BETTER;
            break;

            case RatingFilter.UNRATED_OR_HIGHER:
            default:
                filename = Resources.ICON_FILTER_UNRATED_OR_BETTER;
            break;
        }
        
        return new Gtk.Image.from_pixbuf(Resources.load_icon(filename, get_filter_icon_size(filter)));
    }
    
    private void set_filter_icon(RatingFilter filter) {
        filter_button.set_icon_widget(get_filter_icon(filter));
        filter_button.set_size_request(get_filter_button_size(filter), -1);
        filter_button.set_tooltip_text(Resources.get_rating_filter_tooltip(filter));
        filter_button.show_all();
    }

    private void use_rating_or_higher_filter(Rating rating) {        
        get_view().install_view_filter(get_rating_or_higher_view_filter(rating));
    }

    private ViewFilter get_rating_or_higher_view_filter(Rating rating) {
        switch (rating) {
            case Rating.UNRATED:
                return unrated_or_higher_filter;
            case Rating.ONE:
                return one_or_higher_filter;
            case Rating.TWO:
                return two_or_higher_filter;
            case Rating.THREE:
                return three_or_higher_filter;
            case Rating.FOUR:
                return four_or_higher_filter;
            case Rating.FIVE:
                return five_or_higher_filter;
            case Rating.REJECTED:
            default:
                return rejected_or_higher_filter;
        }
    }

    private bool rejected_or_higher_filter(DataView view) {
        return ((Thumbnail) view).get_photo().get_rating() >= Rating.REJECTED;
    }

    private bool unrated_or_higher_filter(DataView view) {
        return ((Thumbnail) view).get_photo().get_rating() >= Rating.UNRATED;
    }

    private bool one_or_higher_filter(DataView view) {
        return ((Thumbnail) view).get_photo().get_rating() >= Rating.ONE;
    }

    private bool two_or_higher_filter(DataView view) {
        return ((Thumbnail) view).get_photo().get_rating() >= Rating.TWO;
    }

    private bool three_or_higher_filter(DataView view) {
        return ((Thumbnail) view).get_photo().get_rating() >= Rating.THREE;
    }

    private bool four_or_higher_filter(DataView view) {
        return ((Thumbnail) view).get_photo().get_rating() >= Rating.FOUR;
    }

    private bool five_or_higher_filter(DataView view) {
        return ((Thumbnail) view).get_photo().get_rating() >= Rating.FIVE;
    }

    private RatingFilter get_filter_criteria() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/CollectionMenuBar/ViewMenu/FilterPhotos/DisplayRejectedOrHigher");
        assert(action != null);
        
        RatingFilter filter = (RatingFilter) action.get_current_value();

        return filter;
    }

    private void set_config_rating_filter(RatingFilter filter) {
        if (Config.get_instance().set_photo_rating_filter(filter) == false)
            warning("Unable to write rating filter settings to config");
    }

    private RatingFilter get_config_rating_filter() {
        return Config.get_instance().get_photo_rating_filter();
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
    
    private void on_display_ratings(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_ratings(display);
        
        Config.get_instance().set_display_photo_ratings(display);
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
        rotate_button.clicked.disconnect(on_rotate_clockwise);
        rotate_button.clicked.connect(on_rotate_counterclockwise);
        
        return base.on_ctrl_pressed(event);
    }
    
    private override bool on_ctrl_released(Gdk.EventKey? event) {
        rotate_button.set_stock_id(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.clicked.disconnect(on_rotate_counterclockwise);
        rotate_button.clicked.connect(on_rotate_clockwise);
        
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
        get_view().set_comparator(get_sort_comparator(), get_sort_comparator_predicate());

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
            
            case SortBy.RATING:
                if (is_sort_ascending())
                    return Thumbnail.rating_ascending_comparator;
                else
                    return Thumbnail.rating_descending_comparator;
            
            default:
                error("Unknown sort criteria: %s", get_sort_criteria().to_string());
        }
    }
    
    private ComparatorPredicate get_sort_comparator_predicate() {
        switch (get_sort_criteria()) {
            case SortBy.TITLE:
                return Thumbnail.title_comparator_predicate;
            
            case SortBy.EXPOSURE_DATE:
                return Thumbnail.exposure_time_comparator_predicate;
            
            case SortBy.RATING:
                return Thumbnail.rating_comparator_predicate;
            
            default:
                error("Unknown sort criteria: %s", get_sort_criteria().to_string());
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
    
    private void set_display_ratings(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SHOW_RATINGS, display);
        get_view().thaw_notifications();
        
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewRatings");
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
            case SortBy.RATING:
                path = "/CollectionMenuBar/ViewMenu/SortPhotos/SortByRating";
                break;
            default:
                error("Unknown sort criteria: %d", sort_by);
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
            get_view().set_comparator(get_sort_comparator(), get_sort_comparator_predicate());
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

