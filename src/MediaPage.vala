/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

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

public abstract class MediaPage : CheckerboardPage {
    private const int FILTER_BUTTON_MARGIN = 12; // the distance between icon and edge of button
    private const float FILTER_ICON_STAR_SCALE = 0.65f; // changes the size of the filter icon
    private const float FILTER_ICON_SCALE = 0.75f; // changes the size of the all photos icon
    
    // filter_icon_base_width is the width (in px) of a single filter icon such as one star or an "X"
    private const int FILTER_ICON_BASE_WIDTH = 30;
    // filter_icon_plus_width is the width (in px) of the plus icon
    private const int FILTER_ICON_PLUS_WIDTH = 20;
    
    public const int SORT_ORDER_ASCENDING = 0;
    public const int SORT_ORDER_DESCENDING = 1;

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public const int MANUAL_STEPPING = 16;
    public const int SLIDER_STEPPING = 4;

    public enum SortBy {
        TITLE = 1,
        EXPOSURE_DATE = 2,
        RATING = 3;
    }
    
    protected class FilterButton : Gtk.ToolButton {
        public Gtk.Menu filter_popup = null;
        
        public FilterButton() {
            set_icon_widget(get_filter_icon(RatingFilter.UNRATED_OR_HIGHER));
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
                
                case RatingFilter.REJECTED_ONLY:
                    filename = Resources.ICON_RATING_REJECTED;
                break;
                
                case RatingFilter.UNRATED_OR_HIGHER:
                default:
                    filename = Resources.ICON_FILTER_UNRATED_OR_BETTER;
                break;
            }
            
            return new Gtk.Image.from_pixbuf(Resources.load_icon(filename,
                get_filter_icon_size(filter)));
        }

        private int get_filter_icon_size(RatingFilter filter) {
            int icon_base = (int) (FILTER_ICON_BASE_WIDTH * FILTER_ICON_SCALE);
            int icon_star_base = (int) (FILTER_ICON_BASE_WIDTH * FILTER_ICON_STAR_SCALE);
            int icon_plus = (int) (FILTER_ICON_PLUS_WIDTH * FILTER_ICON_STAR_SCALE);
            
            switch (filter) {
                case RatingFilter.ONE_OR_HIGHER:
                    return icon_star_base + icon_plus;
                case RatingFilter.TWO_OR_HIGHER:
                    return icon_star_base * 2 + icon_plus;
                case RatingFilter.THREE_OR_HIGHER:
                    return icon_star_base * 3 + icon_plus;
                case RatingFilter.FOUR_OR_HIGHER:
                    return icon_star_base * 4 + icon_plus;
                case RatingFilter.FIVE_OR_HIGHER:
                case RatingFilter.FIVE_ONLY:
                    return icon_star_base * 5;
                case RatingFilter.REJECTED_OR_HIGHER:
                    return Resources.ICON_FILTER_REJECTED_OR_BETTER_FIXED_SIZE;
                case RatingFilter.UNRATED_OR_HIGHER:
                    return Resources.ICON_FILTER_UNRATED_OR_BETTER_FIXED_SIZE;
                default:
                    return icon_base;
            }
        }

        public void set_filter_icon(RatingFilter filter) {
            set_icon_widget(get_filter_icon(filter));
            set_size_request(get_filter_button_size(filter), -1);
            set_tooltip_text(Resources.get_rating_filter_tooltip(filter));
            show_all();
        }

        private int get_filter_button_size(RatingFilter filter) {
            return get_filter_icon_size(filter) + 2 * FILTER_BUTTON_MARGIN;
        }
    }

    protected class ZoomSliderAssembly : Gtk.ToolItem {
        public static Gtk.Adjustment global_slider_adjustment = null;

        private Gtk.HScale slider;
        
        public signal void zoom_changed();

        public ZoomSliderAssembly() {
            Gtk.HBox zoom_group = new Gtk.HBox(false, 0);

            Gtk.Image zoom_out = new Gtk.Image.from_pixbuf(Resources.load_icon(
                Resources.ICON_ZOOM_OUT, Resources.ICON_ZOOM_SCALE));
            Gtk.EventBox zoom_out_box = new Gtk.EventBox();
            zoom_out_box.set_above_child(true);
            zoom_out_box.set_visible_window(false);
            zoom_out_box.add(zoom_out);
            zoom_out_box.button_press_event.connect(on_zoom_out_pressed);
            
            zoom_group.pack_start(zoom_out_box, false, false, 0);

            // triggers lazy init of the global slider adjustment if it hasn't already been init'd
            get_global_thumbnail_scale();

            slider = new Gtk.HScale(global_slider_adjustment);
            slider.value_changed.connect(on_slider_changed);
            slider.set_draw_value(false);
            slider.set_size_request(200, -1);
            slider.set_tooltip_text(_("Adjust the size of the thumbnails"));

            zoom_group.pack_start(slider, false, false, 0);

            Gtk.Image zoom_in = new Gtk.Image.from_pixbuf(Resources.load_icon(
                Resources.ICON_ZOOM_IN, Resources.ICON_ZOOM_SCALE));
            Gtk.EventBox zoom_in_box = new Gtk.EventBox();
            zoom_in_box.set_above_child(true);
            zoom_in_box.set_visible_window(false);
            zoom_in_box.add(zoom_in);
            zoom_in_box.button_press_event.connect(on_zoom_in_pressed);

            zoom_group.pack_start(zoom_in_box, false, false, 0);

            add(zoom_group);
        }
        
        public static double scale_to_slider(int value) {
            assert(value >= Thumbnail.MIN_SCALE);
            assert(value <= Thumbnail.MAX_SCALE);
            
            return (double) ((value - Thumbnail.MIN_SCALE) / SLIDER_STEPPING);
        }

        public static int slider_to_scale(double value) {
            int res = ((int) (value * SLIDER_STEPPING)) + Thumbnail.MIN_SCALE;

            assert(res >= Thumbnail.MIN_SCALE);
            assert(res <= Thumbnail.MAX_SCALE);
            
            return res;
        }

        private bool on_zoom_out_pressed(Gdk.EventButton event) {
            snap_to_min();
            return true;
        }
        
        private bool on_zoom_in_pressed(Gdk.EventButton event) {
            snap_to_max();
            return true;
        }
        
        private void on_slider_changed() {
            zoom_changed();
        }
        
        public void snap_to_min() {
            slider.set_value(scale_to_slider(Thumbnail.MIN_SCALE));
        }

        public void snap_to_max() {
            slider.set_value(scale_to_slider(Thumbnail.MAX_SCALE));
        }
        
        public void increase_step() {
            int new_scale = compute_zoom_scale_increase(get_scale());

            if (get_scale() == new_scale)
                return;

            slider.set_value(scale_to_slider(new_scale));
        }
        
        public void decrease_step() {
            int new_scale = compute_zoom_scale_decrease(get_scale());

            if (get_scale() == new_scale)
                return;
            
            slider.set_value(scale_to_slider(new_scale));
        }
        
        public int get_scale() {
            return slider_to_scale(slider.get_value());
        }
    }
    
    private ZoomSliderAssembly? connected_slider = null;
    private FilterButton? connected_filter_button = null;

    public MediaPage(string page_name) {
        base (page_name);

        // Adds one menu entry per alien database driver
        AlienDatabaseHandler.get_instance().add_menu_entries(
            ui, "/MediaMenuBar/FileMenu/ImportFromAlienDbPlaceholder"
        );

        get_view().set_comparator(get_sort_comparator(), get_sort_comparator_predicate());
        get_view().items_altered.connect(on_media_altered);

        get_view().freeze_notifications();
        get_view().set_property(CheckerboardItem.PROP_SHOW_TITLES, 
            Config.get_instance().get_display_photo_titles());
        get_view().set_property(Thumbnail.PROP_SHOW_TAGS, 
            Config.get_instance().get_display_photo_tags());
        get_view().set_property(Thumbnail.PROP_SIZE, get_thumb_size());
        get_view().set_property(Thumbnail.PROP_SHOW_RATINGS,
            Config.get_instance().get_display_photo_ratings());
        get_view().thaw_notifications();
    }
    
    private static void set_global_thumbnail_scale(int new_scale) {
        if (get_global_thumbnail_scale() == new_scale)
            return;

        ZoomSliderAssembly.global_slider_adjustment.set_value(
            ZoomSliderAssembly.scale_to_slider(new_scale));
    }
   
    private static int compute_zoom_scale_increase(int current_scale) {
        int new_scale = current_scale + MANUAL_STEPPING;
        return new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
    }
    
    private static int compute_zoom_scale_decrease(int current_scale) {
        int new_scale = current_scale - MANUAL_STEPPING;
        return new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
    }
    
    protected override string? get_menubar_path() {
        return "/MediaMenuBar";
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("media.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, null };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry export = { "Export", Gtk.STOCK_SAVE_AS, TRANSLATABLE, "<Ctrl><Shift>E",
            TRANSLATABLE, on_export };
        export.label = Resources.EXPORT_MENU;
        export.tooltip = Resources.EXPORT_TOOLTIP;
        export.tooltip = _("Export the selected items to disk");
        actions += export;
       
        Gtk.ActionEntry send_to = { "SendTo", "document-send", TRANSLATABLE, null, 
            TRANSLATABLE, on_send_to };
        send_to.label = Resources.SEND_TO_MENU;
        send_to.tooltip = Resources.SEND_TO_TOOLTIP;
        actions += send_to;
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, null };
        edit.label = _("_Edit");
        actions += edit;
        
        Gtk.ActionEntry move_to_trash = { "MoveToTrash", "user-trash-full", TRANSLATABLE, "Delete",
            TRANSLATABLE, on_move_to_trash };
        move_to_trash.label = Resources.MOVE_TO_TRASH_MENU;
        move_to_trash.tooltip = Resources.MOVE_TO_TRASH_PLURAL_TOOLTIP;
        actions += move_to_trash;
        
        Gtk.ActionEntry photos = { "PhotosMenu", null, TRANSLATABLE, null, null, null };
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
        
        Gtk.ActionEntry flag = { "Flag", null, TRANSLATABLE, "<Ctrl>F", TRANSLATABLE, on_flag_unflag };
        flag.label = Resources.FLAG_MENU;
        flag.tooltip = Resources.FLAG_TOOLTIP;
        actions += flag;
        
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

        Gtk.ActionEntry edit_title = { "EditTitle", null, TRANSLATABLE, "F2", TRANSLATABLE,
            on_edit_title };
        edit_title.label = Resources.EDIT_TITLE_MENU;
        edit_title.tooltip = Resources.EDIT_TITLE_TOOLTIP;
        actions += edit_title;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, null };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry sort_photos = { "SortPhotos", null, TRANSLATABLE, null, null, null };
        sort_photos.label = _("Sort _Photos");
        actions += sort_photos;

        Gtk.ActionEntry filter_photos = { "FilterPhotos", null, TRANSLATABLE, null, null, null };
        filter_photos.label = Resources.FILTER_PHOTOS_MENU;
        actions += filter_photos;
        
        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        Gtk.ActionEntry play = { "PlayVideo", Gtk.STOCK_MEDIA_PLAY, TRANSLATABLE, "<Ctrl>Y",
            TRANSLATABLE, on_play_video };
        play.label = _("_Play Video");
        play.tooltip = _("Open the selected videos in the system video player");
        actions += play;

        return actions;
    }
    
    protected override Gtk.ToggleActionEntry[] init_collect_toggle_action_entries() {
        Gtk.ToggleActionEntry[] toggle_actions = base.init_collect_toggle_action_entries();
        
        Gtk.ToggleActionEntry titles = { "ViewTitle", null, TRANSLATABLE, "<Ctrl><Shift>T",
            TRANSLATABLE, on_display_titles, Config.get_instance().get_display_photo_titles() };
        titles.label = _("_Titles");
        titles.tooltip = _("Display the title of each photo");
        toggle_actions += titles;
        
        Gtk.ToggleActionEntry ratings = { "ViewRatings", null, TRANSLATABLE, "<Ctrl><Shift>R",
            TRANSLATABLE, on_display_ratings, Config.get_instance().get_display_photo_ratings() };
        ratings.label = Resources.VIEW_RATINGS_MENU;
        ratings.tooltip = Resources.VIEW_RATINGS_TOOLTIP;
        toggle_actions += ratings;
        
        return toggle_actions;
    }
    
    protected override void register_radio_actions(Gtk.ActionGroup action_group) {
        bool sort_order;
        int sort_by;
        get_config_photos_sort(out sort_order, out sort_by);
        
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
        
        action_group.add_radio_actions(sort_crit_actions, sort_by, on_sort_changed);
        
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
        
        action_group.add_radio_actions(sort_order_actions,
            sort_order ? SORT_ORDER_ASCENDING : SORT_ORDER_DESCENDING, on_sort_changed);
        
        Gtk.RadioActionEntry[] view_filter_actions = new Gtk.RadioActionEntry[0];
        
        Gtk.RadioActionEntry rejected_only = { "DisplayRejectedOnly", null, TRANSLATABLE,
            "<Ctrl>8", TRANSLATABLE, RatingFilter.REJECTED_ONLY };
        rejected_only.label = Resources.DISPLAY_REJECTED_ONLY_MENU;
        rejected_only.tooltip = Resources.DISPLAY_REJECTED_ONLY_TOOLTIP;
        view_filter_actions += rejected_only;
        
        Gtk.RadioActionEntry rejected_or_higher = { "DisplayRejectedOrHigher", null, TRANSLATABLE,
            "<Ctrl>9", TRANSLATABLE, RatingFilter.REJECTED_OR_HIGHER };
        rejected_or_higher.label = Resources.DISPLAY_REJECTED_OR_HIGHER_MENU;
        rejected_or_higher.tooltip = Resources.DISPLAY_REJECTED_OR_HIGHER_TOOLTIP;
        view_filter_actions += rejected_or_higher;
        
        Gtk.RadioActionEntry unrated_or_higher = { "DisplayUnratedOrHigher", null, TRANSLATABLE, 
            "<Ctrl>0", TRANSLATABLE, RatingFilter.UNRATED_OR_HIGHER };
        unrated_or_higher.label = Resources.DISPLAY_UNRATED_OR_HIGHER_MENU;
        unrated_or_higher.tooltip = Resources.DISPLAY_UNRATED_OR_HIGHER_TOOLTIP;
        view_filter_actions += unrated_or_higher;
        
        Gtk.RadioActionEntry one_or_higher = { "DisplayOneOrHigher", null, TRANSLATABLE,
            "<Ctrl>1", TRANSLATABLE, RatingFilter.ONE_OR_HIGHER };
        one_or_higher.label = Resources.DISPLAY_ONE_OR_HIGHER_MENU;
        one_or_higher.tooltip = Resources.DISPLAY_ONE_OR_HIGHER_TOOLTIP;
        view_filter_actions += one_or_higher;
        
        Gtk.RadioActionEntry two_or_higher = { "DisplayTwoOrHigher", null, TRANSLATABLE,
            "<Ctrl>2", TRANSLATABLE, RatingFilter.TWO_OR_HIGHER };
        two_or_higher.label = Resources.DISPLAY_TWO_OR_HIGHER_MENU;
        two_or_higher.tooltip = Resources.DISPLAY_TWO_OR_HIGHER_TOOLTIP;
        view_filter_actions += two_or_higher;
        
        Gtk.RadioActionEntry three_or_higher = { "DisplayThreeOrHigher", null, TRANSLATABLE,
            "<Ctrl>3", TRANSLATABLE, RatingFilter.THREE_OR_HIGHER };
        three_or_higher.label = Resources.DISPLAY_THREE_OR_HIGHER_MENU;
        three_or_higher.tooltip = Resources.DISPLAY_THREE_OR_HIGHER_TOOLTIP;
        view_filter_actions += three_or_higher;
        
        Gtk.RadioActionEntry four_or_higher = { "DisplayFourOrHigher", null, TRANSLATABLE,
            "<Ctrl>4", TRANSLATABLE, RatingFilter.FOUR_OR_HIGHER };
        four_or_higher.label = Resources.DISPLAY_FOUR_OR_HIGHER_MENU;
        four_or_higher.tooltip = Resources.DISPLAY_FOUR_OR_HIGHER_TOOLTIP;
        view_filter_actions += four_or_higher;
        
        Gtk.RadioActionEntry five_or_higher = { "DisplayFiveOrHigher", null, TRANSLATABLE,
            "<Ctrl>5", TRANSLATABLE, RatingFilter.FIVE_OR_HIGHER };
        five_or_higher.label = Resources.DISPLAY_FIVE_OR_HIGHER_MENU;
        five_or_higher.tooltip = Resources.DISPLAY_FIVE_OR_HIGHER_TOOLTIP;
        view_filter_actions += five_or_higher;
        
        action_group.add_radio_actions(view_filter_actions, get_config_rating_filter(),
            on_view_filter_changed);
        
        base.register_radio_actions(action_group);
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("Export", selected_count > 0);
        set_action_sensitive("EditTitle", selected_count == 1);
        set_action_sensitive("IncreaseSize", get_thumb_size() < Thumbnail.MAX_SCALE);
        set_action_sensitive("DecreaseSize", get_thumb_size() > Thumbnail.MIN_SCALE);
        set_action_sensitive("MoveToTrash", selected_count > 0);
        
        if (DesktopIntegration.is_send_to_installed())
            set_action_sensitive("SendTo", selected_count > 0);
        else
            set_action_visible("SendTo", false);
        
        set_action_sensitive("Rate", selected_count > 0);
        update_rating_sensitivities();
        
        set_action_sensitive("PlayVideo", selected_count == 1
            && get_view().get_selected_source_at(0) is Video);
        
        update_flag_action(selected_count);
        
        base.update_actions(selected_count, count);
    }
    
    private void on_media_altered() {
        update_flag_action(get_view().get_selected_count());
    }
    
    private void position_filter_popup(Gtk.Menu menu, out int x, out int y, out bool push_in) {
        assert(connected_filter_button != null);

        menu.realize();
        int rx, ry;
        get_container().get_child().window.get_root_origin(out rx, out ry);
        
        x = rx + connected_filter_button.allocation.x;
        y = ry + get_menubar().allocation.height + get_toolbar().allocation.y 
            - menu.allocation.height;
        push_in = false;
    }
    
    private void on_filter_button_clicked() {
        assert(connected_filter_button != null);
        
        connected_filter_button.filter_popup.popup(null, null, position_filter_popup, 0,
            Gtk.get_current_event_time());
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
    
    private void update_flag_action(int selected_count) {
        set_action_sensitive("Flag", selected_count > 0);
        
        string flag_label = Resources.FLAG_MENU;
        string flag_tooltip = Resources.FLAG_TOOLTIP;
        if (selected_count > 0) {
            bool all_flagged = true;
            foreach (DataSource source in get_view().get_selected_sources()) {
                Flaggable? flaggable = source as Flaggable;
                if (flaggable != null && !flaggable.is_flagged()) {
                    all_flagged = false;
                    
                    break;
                }
            }
            
            if (all_flagged) {
                flag_label = Resources.UNFLAG_MENU;
                flag_tooltip = Resources.UNFLAG_TOOLTIP;
            }
        }
        
        Gtk.Action? flag_action = get_action("Flag");
        if (flag_action != null) {
            flag_action.label = flag_label;
            flag_action.tooltip = flag_tooltip;
        }
    }
    
    public void set_display_ratings(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SHOW_RATINGS, display);
        get_view().thaw_notifications();
        
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewRatings");
        if (action != null)
            action.set_active(display);
    }

    private bool can_rate_selected(Rating rating) {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_media_source().get_rating() != rating)
                return true;
        }

        return false;
    }

    private bool can_increase_selected_rating() {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_media_source().get_rating().can_increase())
                return true;
        }

        return false;
    }

    private bool can_decrease_selected_rating() {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_media_source().get_rating().can_decrease())
                return true;
        }
        
        return false;
    }
    
    public ZoomSliderAssembly create_zoom_slider_assembly() {
        return new ZoomSliderAssembly();
    }

    public FilterButton create_filter_button() {
        FilterButton result = new FilterButton();

        result.filter_popup = (Gtk.Menu) ui.get_widget("/FilterPopupMenu");
        result.set_expand(false);

        return result;
    }
    
    public static int get_global_thumbnail_scale() {
        if (ZoomSliderAssembly.global_slider_adjustment == null) {
            int persisted_scale = Config.get_instance().get_photo_thumbnail_scale();
            ZoomSliderAssembly.global_slider_adjustment = new Gtk.Adjustment(
                ZoomSliderAssembly.scale_to_slider(persisted_scale), 0,
                ZoomSliderAssembly.scale_to_slider(Thumbnail.MAX_SCALE), 1, 10, 0);
        }

        return ZoomSliderAssembly.slider_to_scale(ZoomSliderAssembly.global_slider_adjustment.get_value());
    }

    protected override bool on_mousewheel_up(Gdk.EventScroll event) {
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            increase_zoom_level();
            return true;
        } else {
            return base.on_mousewheel_up(event);
        }
    }

    protected override bool on_mousewheel_down(Gdk.EventScroll event) {
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            decrease_zoom_level();
            return true;
        } else {
            return base.on_mousewheel_down(event);
        }
    }

    protected virtual void on_view_filter_changed() {
        RatingFilter filter = get_filter_criteria();
        install_rating_filter(filter);
        if (connected_filter_button != null) {
            connected_filter_button.set_filter_icon(filter);
        }
        set_config_rating_filter(filter);
    }

    protected RatingFilter get_filter_criteria() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/MediaMenuBar/ViewMenu/FilterPhotos/DisplayRejectedOrHigher");
        assert(action != null);
        
        RatingFilter filter = (RatingFilter) action.get_current_value();

        return filter;
    }
    
    private void on_send_to() {
        DesktopIntegration.send_to((Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }
    
    protected void on_play_video() {
        if (get_view().get_selected_count() != 1)
            return;
        
        Video? video = get_view().get_selected_at(0).get_source() as Video;
        if (video == null)
            return;
        
        try {
            AppInfo.launch_default_for_uri(video.get_file().get_uri(), null);
        } catch (Error e) {
            AppWindow.error_message(_("Shotwell was unable to play the selected video:\n%s").printf(
                e.message));
        }
    }

    protected override bool on_app_key_pressed(Gdk.EventKey event) {
        bool handled = true;
        
        switch (Gdk.keyval_name(event.keyval)) {
            case "equal":
            case "plus":
            case "KP_Add":
                increase_zoom_level();
            break;
            
            case "minus":
            case "underscore":
            case "KP_Subtract":
                decrease_zoom_level();
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
            
            case "asterisk":
                if (get_ctrl_pressed())
                    set_rating_view_filter(RatingFilter.REJECTED_ONLY);
            break;
            
            default:
                handled = false;
            break;
        }
        
        return handled ? true : base.on_app_key_pressed(event);
    }

    public override void switched_to() {
        base.switched_to();
        
        // the global thumbnail scale could've changed while another page was displayed, so
        // make sure that this page's thumb size matches the global thumbnail scale
        if (get_global_thumbnail_scale() != get_thumb_size())
            set_thumb_size(get_global_thumbnail_scale());

        // set display options to match Configuration toggles (which can change while switched away)
        get_view().freeze_notifications();
        set_display_titles(Config.get_instance().get_display_photo_titles());
        set_display_ratings(Config.get_instance().get_display_photo_ratings());
        get_view().thaw_notifications();

        restore_saved_rating_view_filter();  // Set filter to current level and set menu selection

        sync_sort();
    }

    protected void connect_slider(ZoomSliderAssembly slider) {
        connected_slider = slider;
        connected_slider.zoom_changed.connect(on_zoom_changed);
    }

    protected void connect_filter_button(FilterButton button) {
        connected_filter_button = button;
        
        connected_filter_button.clicked.connect(on_filter_button_clicked);
    }
    
    protected void disconnect_slider() {
        if (connected_slider == null)
            return;
        
        connected_slider.zoom_changed.disconnect(on_zoom_changed);
        connected_slider = null;
    }
    
    protected void disconnect_filter_button() {
        connected_filter_button.clicked.disconnect(on_filter_button_clicked);

        connected_filter_button = null;
    }

    protected virtual void on_zoom_changed() {
        if (connected_slider != null)
            set_thumb_size(connected_slider.get_scale());
    }
    
    protected abstract void on_export();

    protected virtual void on_increase_size() {
        increase_zoom_level();
    }

    protected virtual void on_decrease_size() {
        decrease_zoom_level();
    }
    
    private void on_flag_unflag() {
        if (get_view().get_selected_count() == 0)
            return;
        
        Gee.Collection<DataSource> sources = get_view().get_selected_sources();
        
        // If all are flagged, then unflag, otherwise flag
        bool flag = false;
        foreach (DataSource source in sources) {
            Flaggable? flaggable = source as Flaggable;
            if (flaggable != null && !flaggable.is_flagged()) {
                flag = true;
                
                break;
            }
        }
        
        get_command_manager().execute(new FlagUnflagCommand(sources, flag));
    }
    
    protected virtual void on_increase_rating() {
        if (get_view().get_selected_count() == 0)
            return;
        
        SetRatingCommand command = new SetRatingCommand.inc_dec(get_view().get_selected(), true);
        get_command_manager().execute(command);

        update_rating_sensitivities();
    }

    protected virtual void on_decrease_rating() {
        if (get_view().get_selected_count() == 0)
            return;
        
        SetRatingCommand command = new SetRatingCommand.inc_dec(get_view().get_selected(), false);
        get_command_manager().execute(command);

        update_rating_sensitivities();
    }

    protected virtual void on_set_rating(Rating rating) {
        if (get_view().get_selected_count() == 0)
            return;
        
        SetRatingCommand command = new SetRatingCommand(get_view().get_selected(), rating);
        get_command_manager().execute(command);

        update_rating_sensitivities();
    }

    protected virtual void on_rate_rejected() {
        on_set_rating(Rating.REJECTED);
    }
    
    protected virtual void on_rate_unrated() {
        on_set_rating(Rating.UNRATED);
    }

    protected virtual void on_rate_one() {
        on_set_rating(Rating.ONE);
    }

    protected virtual void on_rate_two() {
        on_set_rating(Rating.TWO);
    }

    protected virtual void on_rate_three() {
        on_set_rating(Rating.THREE);
    }

    protected virtual void on_rate_four() {
        on_set_rating(Rating.FOUR);
    }

    protected virtual void on_rate_five() {
        on_set_rating(Rating.FIVE);
    }

    protected virtual void on_move_to_trash() {
        if (get_view().get_selected_count() > 0) {
            get_command_manager().execute(new TrashUntrashPhotosCommand(
                (Gee.Collection<MediaSource>) get_view().get_selected_sources(), true));
        }
    }

    protected virtual void on_edit_title() {
        // only edit one title at a time
        if (get_view().get_selected_count() != 1)
            return;

        MediaSource item = (MediaSource) get_view().get_selected_at(0).get_source();
        
        EditTitleDialog edit_title_dialog = new EditTitleDialog(item.get_title());
        string? new_title = edit_title_dialog.execute();
        if (new_title == null)
            return;
        
        EditTitleCommand command = new EditTitleCommand(item, new_title);
        get_command_manager().execute(command);
    }

    protected virtual void on_display_titles(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_titles(display);
        
        Config.get_instance().set_display_photo_titles(display);
    }

    protected virtual void on_display_ratings(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_ratings(display);
        
        Config.get_instance().set_display_photo_ratings(display);
    }

    protected abstract void get_config_photos_sort(out bool sort_order, out int sort_by);

    protected abstract void set_config_photos_sort(bool sort_order, int sort_by);

    protected virtual void on_sort_changed() {
        get_view().set_comparator(get_sort_comparator(), get_sort_comparator_predicate());

        set_config_photos_sort(get_sort_order() == SORT_ORDER_ASCENDING, get_sort_criteria());
    }

    protected override void set_display_titles(bool display) {
        base.set_display_titles(display);
    
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewTitle");
        if (action != null)
            action.set_active(display);
    }

    protected int get_sort_criteria() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/MediaMenuBar/ViewMenu/SortPhotos/SortByTitle");
        assert(action != null);
        
        int value = action.get_current_value();

        return value;
    }
    
    protected int get_sort_order() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/MediaMenuBar/ViewMenu/SortPhotos/SortAscending");
        assert(action != null);
        
        int value = action.get_current_value();
        
        return value;
    }
    
    protected bool is_sort_ascending() {
        return get_sort_order() == SORT_ORDER_ASCENDING;
    }
       
    protected Comparator get_sort_comparator() {
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
    
    protected ComparatorPredicate get_sort_comparator_predicate() {
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
          
    protected string get_sortby_path(int sort_by) {
        string path = "";

        switch(sort_by) {
            case SortBy.TITLE:
                path = "/MediaMenuBar/ViewMenu/SortPhotos/SortByTitle";
                break;
            case SortBy.EXPOSURE_DATE:
                path = "/MediaMenuBar/ViewMenu/SortPhotos/SortByExposureDate";
                break;
            case SortBy.RATING:
                path = "/MediaMenuBar/ViewMenu/SortPhotos/SortByRating";
                break;
            default:
                error("Unknown sort criteria: %d", sort_by);
        }

        return path;
    }

    protected void sync_sort() {
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
            (Gtk.RadioAction) ui.get_action("/MediaMenuBar/ViewMenu/SortPhotos/SortAscending");

        int sort_order_int = sort_order ? SORT_ORDER_ASCENDING : SORT_ORDER_DESCENDING;
        if (ascending_action != null && ascending_action.get_current_value() != sort_order_int) {
            ascending_action.set_current_value(sort_order_int);
            resort_needed = true;
        }

        if (resort_needed)
            get_view().set_comparator(get_sort_comparator(), get_sort_comparator_predicate());
    }

    private void restore_saved_rating_view_filter() {
        RatingFilter filter = get_config_rating_filter();
        set_rating_view_filter_menu(filter);
        if (connected_filter_button != null) {
            connected_filter_button.set_filter_icon(filter);
        }
        install_rating_filter(filter);
    }

    private RatingFilter get_config_rating_filter() {
        return Config.get_instance().get_photo_rating_filter();
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
            
            case RatingFilter.REJECTED_ONLY:
                action = (Gtk.ToggleAction) action_group.get_action("DisplayRejectedOnly");
            break;
            
            case RatingFilter.REJECTED_OR_HIGHER:
            default:
                action = (Gtk.ToggleAction) action_group.get_action("DisplayRejectedOrHigher");
            break;
        }
        
        action.set_active(true);
    }

    private void set_rating_view_filter(RatingFilter filter) {
        set_rating_view_filter_menu(filter);
        install_rating_filter(filter);
        if (connected_filter_button != null) {
            connected_filter_button.set_filter_icon(filter);
        }
        set_config_rating_filter(filter);
    }
    
    // This is one of those situations where lambdas would be beneficial, in that we could install
    // ViewFilters that use the parameterized rating for comparison; the following pages of code
    // could greatly be simplified.  However, ViewCollection.install_view_filter() checks to see
    // if the supplied ViewFilter == the installed one, and if so, exits quietly; this simple
    // optimization can save a lot of work.
    //
    // That comparison in Vala is a simple comparison of function pointers, which always succeed
    // with lambdas no matter how they're parameterized.  Rather than give up this optimization,
    // coding this the "old-fashioned" way.  In the future, if we're willing to avoid that check.
    // it may be worthwhile here (and elsewhere) to use lambdas.
    private void install_rating_filter(RatingFilter filter) {
        switch (filter) {
            case RatingFilter.REJECTED_ONLY:
                use_exact_rating_filter(Rating.REJECTED);
            break;
            
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
    
    private bool higher_filter(DataView view, Rating rating) {
        return ((Thumbnail) view).get_media_source().get_rating() >= rating;
    }
    
    private bool rejected_or_higher_filter(DataView view) {
        return higher_filter(view, Rating.REJECTED);
    }

    private bool unrated_or_higher_filter(DataView view) {
        return higher_filter(view, Rating.UNRATED);
    }

    private bool one_or_higher_filter(DataView view) {
        return higher_filter(view, Rating.ONE);
    }

    private bool two_or_higher_filter(DataView view) {
        return higher_filter(view, Rating.TWO);
    }

    private bool three_or_higher_filter(DataView view) {
        return higher_filter(view, Rating.THREE);
    }

    private bool four_or_higher_filter(DataView view) {
        return higher_filter(view, Rating.FOUR);
    }

    private bool five_or_higher_filter(DataView view) {
        return higher_filter(view, Rating.FIVE);
    }
    
    private void use_exact_rating_filter(Rating rating) {
        get_view().install_view_filter(get_exact_rating_view_filter(rating));
    }
    
    private ViewFilter get_exact_rating_view_filter(Rating rating) {
        switch (rating) {
            case Rating.ONE:
                return one_filter;
            
            case Rating.TWO:
                return two_filter;
            
            case Rating.THREE:
                return three_filter;
            
            case Rating.FOUR:
                return four_filter;
            
            case Rating.FIVE:
                return five_filter;
            
            case Rating.REJECTED:
                return rejected_filter;
            
            case Rating.UNRATED:
            default:
                return unrated_filter;
        }
    }
    
    private bool exact_filter(DataView view, Rating rating) {
        return ((Thumbnail) view).get_media_source().get_rating() == rating;
    }
    
    private bool rejected_filter(DataView view) {
        return exact_filter(view, Rating.REJECTED);
    }
    
    private bool unrated_filter(DataView view) {
        return exact_filter(view, Rating.UNRATED);
    }
    
    private bool one_filter(DataView view) {
        return exact_filter(view, Rating.ONE);
    }
    
    private bool two_filter(DataView view) {
        return exact_filter(view, Rating.TWO);
    }
    
    private bool three_filter(DataView view) {
        return exact_filter(view, Rating.THREE);
    }
    
    private bool four_filter(DataView view) {
        return exact_filter(view, Rating.FOUR);
    }
    
    private bool five_filter(DataView view) {
        return exact_filter(view, Rating.FIVE);
    }
    
    private void set_config_rating_filter(RatingFilter filter) {
        if (!Config.get_instance().set_photo_rating_filter(filter))
            warning("Unable to write rating filter settings to config");
    }

    public override void destroy() {
        disconnect_slider();
        
        base.destroy();
    }

    public void increase_zoom_level() {
        if (connected_slider != null) {
            connected_slider.increase_step();
        } else {
            int new_scale = compute_zoom_scale_increase(get_thumb_size());
            set_global_thumbnail_scale(new_scale);
            set_thumb_size(new_scale);
        }
    }

    public void decrease_zoom_level() {
        if (connected_slider != null) {
            connected_slider.decrease_step();
        } else {
            int new_scale = compute_zoom_scale_decrease(get_thumb_size());
            set_global_thumbnail_scale(new_scale);
            set_thumb_size(new_scale);
        }
    }

    public virtual DataView create_thumbnail(DataSource source) {
        return new Thumbnail((MediaSource) source, get_thumb_size());
    }

    // this is a view-level operation on this page only; it does not affect the persistent global
    // thumbnail scale
    public void set_thumb_size(int new_scale) {
        if (get_thumb_size() == new_scale || !is_in_view())
            return;
        
        new_scale = new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
        get_checkerboard_layout().set_scale(new_scale);
        
        // when doing mass operations on LayoutItems, freeze individual notifications
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SIZE, new_scale);
        get_view().thaw_notifications();
        
        set_action_sensitive("IncreaseSize", new_scale < Thumbnail.MAX_SCALE);
        set_action_sensitive("DecreaseSize", new_scale > Thumbnail.MIN_SCALE);
    }

    public int get_thumb_size() {
        if (get_checkerboard_layout().get_scale() <= 0)
            get_checkerboard_layout().set_scale(Config.get_instance().get_photo_thumbnail_scale());
            
        return get_checkerboard_layout().get_scale();
    }
}

