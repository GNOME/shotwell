/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// Bitfield values used to specify which search bar features we want.
[Flags]
public enum SearchFilterCriteria {
    NONE,
    RECURSIVE,
    TEXT,
    FLAG,
    MEDIA,
    RATING;
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

 // Handles filtering via rating and text.
public abstract class SearchViewFilter : ViewFilter {
    // If this is true, allow the current rating or higher.
    private bool rating_allow_higher = true;
    
    // Rating to filter by.
    private Rating rating = Rating.REJECTED;
    private RatingFilter rating_filter = RatingFilter.REJECTED_OR_HIGHER;
    
    // Show flagged only if set to true.
    public bool flagged { get; set; default = false; }
    
    // Media types.
    public bool show_media_video { get; set; default = true; }
    public bool show_media_photos { get; set; default = true; }
    public bool show_media_raw { get; set; default = true; }
    
    // Search text filter.  Should only be set to lower-case.
    private string? search_filter = null;
    
    // Returns a bitmask of SearchFilterCriteria.
    // IMPORTANT: There is no signal on this, changing this value after the
    // view filter is installed will NOT update the GUI.
    public abstract uint get_criteria();
    
    public void set_rating_filter(RatingFilter rf) {
        rating_filter = rf;
        switch (rating_filter) {
            case RatingFilter.REJECTED_ONLY:
                rating = Rating.REJECTED;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.REJECTED_OR_HIGHER:
                rating = Rating.REJECTED;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.ONE_OR_HIGHER:
                rating = Rating.ONE;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.ONE_ONLY:
                rating = Rating.ONE;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.TWO_OR_HIGHER:
                rating = Rating.TWO;
                rating_allow_higher = true;
            break;
            
             case RatingFilter.TWO_ONLY:
                rating = Rating.TWO;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.THREE_OR_HIGHER:
                rating = Rating.THREE;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.THREE_ONLY:
                rating = Rating.THREE;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.FOUR_OR_HIGHER:
                rating = Rating.FOUR;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.FOUR_ONLY:
                rating = Rating.FOUR;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.FIVE_OR_HIGHER:
                rating = Rating.FIVE;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.FIVE_ONLY:
                rating = Rating.FIVE;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.UNRATED_OR_HIGHER:
            default:
                rating = Rating.UNRATED;
                rating_allow_higher = true;
            break;
        }
    }
    
    public string? get_search_filter() {
        return search_filter;
    }
    
    public void set_search_filter(string text) {
        search_filter = text.down();
    }
    
    public void clear_search_filter() {
        search_filter = null;
    }
    
    public bool get_rating_allow_higher() {
        return rating_allow_higher;
    }
    
    public Rating get_rating() {
        return rating;
    }
    
    public bool filter_by_media_type() {
        return ((show_media_video || show_media_photos || show_media_raw) && 
            !(show_media_video && show_media_photos && show_media_raw));
    }
    
}

// This class provides a default predicate implementation used for CollectionPage
// as well as Trash and Offline.
public abstract class DefaultSearchViewFilter : SearchViewFilter {
    public override bool predicate(DataView view) {
        MediaSource source = ((Thumbnail) view).get_media_source();
        // Ratings filter
        if ((bool) (SearchFilterCriteria.RATING & get_criteria())) {
            if (get_rating_allow_higher() && source.get_rating() < get_rating())
                return false;
            else if (!get_rating_allow_higher() && source.get_rating() != get_rating())
                return false;
        }
        
        // Flag state.
        if ((bool) (SearchFilterCriteria.FLAG & get_criteria())) {
            if (flagged && source is Flaggable && !((Flaggable) source).is_flagged())
                return false;
        }
        
        // Media type.
        if ((bool) (SearchFilterCriteria.MEDIA & get_criteria()) && filter_by_media_type()) {
            if (source is VideoSource) {
                if (!show_media_video)
                    return false;
            } else if (source is Photo) {
                if (((Photo) source).get_master_file_format() == PhotoFileFormat.RAW) {
                    if (!show_media_photos && !show_media_raw)
                        return false;
                } else if (!show_media_photos)
                    return false;
            }
        }
        
        // Text filter.
        if (((bool) (SearchFilterCriteria.TEXT & get_criteria())) && 
            !is_string_empty(get_search_filter())) {
            string title = source.get_title() != null ? source.get_title().down() : "";
            if (title.contains(get_search_filter()))
                return true;
            
            if (source.get_basename().down().contains(get_search_filter()))
                return true;
            
            if (source.get_event() != null && source.get_event().get_raw_name() != null &&
                source.get_event().get_raw_name().down().contains(get_search_filter()))
                return true;
            
            Gee.List<Tag>? tags = Tag.global.fetch_for_source(source);
            if (null != tags) {
                foreach (Tag tag in tags) {
                    if (tag.get_name().down().contains(get_search_filter()))
                        return true;
                }
            }
            return false;
        }
        
        return true;
    }
}

public class SearchFilterActions {
    private static SearchFilterActions? instance = null;
    
    public unowned Gtk.ToggleAction? flagged {
        get {
            return get_action("CommonDisplayFlagged") as Gtk.ToggleAction;
        }
    }
    
    public unowned Gtk.ToggleAction? photos {
        get {
            return get_action("CommonDisplayPhotos") as Gtk.ToggleAction;
        }
    }
    
    public unowned Gtk.ToggleAction? videos {
        get {
            return get_action("CommonDisplayVideos") as Gtk.ToggleAction;
        }
    }
    
    public unowned Gtk.ToggleAction? raw {
        get {
            return get_action("CommonDisplayRaw") as Gtk.ToggleAction;
        }
    }
    
    public unowned Gtk.RadioAction? rating {
        get {
            return get_action("CommonDisplayUnratedOrHigher") as Gtk.RadioAction;
        }
    }
    
    private Gtk.ActionGroup action_group = new Gtk.ActionGroup("SearchFilterActionGroup");
    
    public signal void flagged_toggled(bool on);
    
    public signal void photos_toggled(bool on);
    
    public signal void videos_toggled(bool on);
    
    public signal void raw_toggled(bool on);
    
    public signal void rating_changed(RatingFilter filter);
    
    private SearchFilterActions() {
        // the getters defined above should not be used until register() returns
        register();
        
        flagged.toggled.connect(on_flagged_value_toggled);
        photos.toggled.connect(on_photos_value_toggled);
        videos.toggled.connect(on_videos_value_toggled);
        raw.toggled.connect(on_raw_value_toggled);
        rating.changed.connect(on_rating_value_changed);
    }
    
    public static SearchFilterActions get_instance() {
        if (instance == null)
            instance = new SearchFilterActions();
        
        return instance;
    }
    
    public Gtk.ActionGroup get_action_group() {
        return action_group;
    }
    
    public unowned Gtk.Action? get_action(string name) {
        return action_group.get_action(name);
    }
    
    public void set_action_sensitive(string name, bool sensitive) {
        Gtk.Action? action = get_action(name);
        if (action != null)
            action.sensitive = sensitive;
    }
    
    public void set_sensitive_for_search_criteria(uint criteria) {
        set_action_sensitive("CommonDisplayFlagged", (SearchFilterCriteria.FLAG & criteria) != 0);
        
        bool allow_media = (SearchFilterCriteria.MEDIA & criteria) != 0;
        set_action_sensitive("CommonDisplayVideos", allow_media);
        set_action_sensitive("CommonDisplayPhotos", allow_media);
        set_action_sensitive("CommonDisplayRaw", allow_media);
        
        bool allow_ratings = (SearchFilterCriteria.RATING & criteria) != 0;
        set_action_sensitive("CommonDisplayRejectedOnly", allow_ratings);
        set_action_sensitive("CommonDisplayRejectedOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayUnratedOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayOneOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayTwoOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayThreeOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayFourOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayFiveOrHigher", allow_ratings);
    }
    
    private static void on_flagged_value_toggled(Gtk.ToggleAction action) {
        Config.get_instance().set_search_flagged(action.active);
    }
    
    private static void on_photos_value_toggled(Gtk.ToggleAction action) {
        Config.get_instance().set_show_media_photos(action.active);
    }
    
    private static void on_videos_value_toggled(Gtk.ToggleAction action) {
        Config.get_instance().set_show_media_video(action.active);
    }
    
    private static void on_raw_value_toggled(Gtk.ToggleAction action) {
        Config.get_instance().set_show_media_raw(action.active);
    }
    
    private static void on_rating_value_changed(Gtk.RadioAction action, Gtk.RadioAction current) {
        Config.get_instance().set_photo_rating_filter((RatingFilter) current.current_value);
    }
    
    private void register() {
        Gtk.RadioActionEntry[] view_filter_actions = new Gtk.RadioActionEntry[0];
        
        Gtk.RadioActionEntry rejected_only = { "CommonDisplayRejectedOnly", null, TRANSLATABLE,
            "<Ctrl>8", TRANSLATABLE, RatingFilter.REJECTED_ONLY };
        rejected_only.label = Resources.DISPLAY_REJECTED_ONLY_MENU;
        rejected_only.tooltip = Resources.DISPLAY_REJECTED_ONLY_TOOLTIP;
        view_filter_actions += rejected_only;
        
        Gtk.RadioActionEntry rejected_or_higher = { "CommonDisplayRejectedOrHigher", null, TRANSLATABLE,
            "<Ctrl>9", TRANSLATABLE, RatingFilter.REJECTED_OR_HIGHER };
        rejected_or_higher.label = Resources.DISPLAY_REJECTED_OR_HIGHER_MENU;
        rejected_or_higher.tooltip = Resources.DISPLAY_REJECTED_OR_HIGHER_TOOLTIP;
        view_filter_actions += rejected_or_higher;
        
        Gtk.RadioActionEntry unrated_or_higher = { "CommonDisplayUnratedOrHigher", null, TRANSLATABLE, 
            "<Ctrl>0", TRANSLATABLE, RatingFilter.UNRATED_OR_HIGHER };
        unrated_or_higher.label = Resources.DISPLAY_UNRATED_OR_HIGHER_MENU;
        unrated_or_higher.tooltip = Resources.DISPLAY_UNRATED_OR_HIGHER_TOOLTIP;
        view_filter_actions += unrated_or_higher;
        
        Gtk.RadioActionEntry one_or_higher = { "CommonDisplayOneOrHigher", null, TRANSLATABLE,
            "<Ctrl>1", TRANSLATABLE, RatingFilter.ONE_OR_HIGHER };
        one_or_higher.label = Resources.DISPLAY_ONE_OR_HIGHER_MENU;
        one_or_higher.tooltip = Resources.DISPLAY_ONE_OR_HIGHER_TOOLTIP;
        view_filter_actions += one_or_higher;
        
        Gtk.RadioActionEntry two_or_higher = { "CommonDisplayTwoOrHigher", null, TRANSLATABLE,
            "<Ctrl>2", TRANSLATABLE, RatingFilter.TWO_OR_HIGHER };
        two_or_higher.label = Resources.DISPLAY_TWO_OR_HIGHER_MENU;
        two_or_higher.tooltip = Resources.DISPLAY_TWO_OR_HIGHER_TOOLTIP;
        view_filter_actions += two_or_higher;
        
        Gtk.RadioActionEntry three_or_higher = { "CommonDisplayThreeOrHigher", null, TRANSLATABLE,
            "<Ctrl>3", TRANSLATABLE, RatingFilter.THREE_OR_HIGHER };
        three_or_higher.label = Resources.DISPLAY_THREE_OR_HIGHER_MENU;
        three_or_higher.tooltip = Resources.DISPLAY_THREE_OR_HIGHER_TOOLTIP;
        view_filter_actions += three_or_higher;
        
        Gtk.RadioActionEntry four_or_higher = { "CommonDisplayFourOrHigher", null, TRANSLATABLE,
            "<Ctrl>4", TRANSLATABLE, RatingFilter.FOUR_OR_HIGHER };
        four_or_higher.label = Resources.DISPLAY_FOUR_OR_HIGHER_MENU;
        four_or_higher.tooltip = Resources.DISPLAY_FOUR_OR_HIGHER_TOOLTIP;
        view_filter_actions += four_or_higher;
        
        Gtk.RadioActionEntry five_or_higher = { "CommonDisplayFiveOrHigher", null, TRANSLATABLE,
            "<Ctrl>5", TRANSLATABLE, RatingFilter.FIVE_OR_HIGHER };
        five_or_higher.label = Resources.DISPLAY_FIVE_OR_HIGHER_MENU;
        five_or_higher.tooltip = Resources.DISPLAY_FIVE_OR_HIGHER_TOOLTIP;
        view_filter_actions += five_or_higher;
        
        action_group.add_radio_actions(view_filter_actions, Config.get_instance().get_photo_rating_filter(),
            on_rating_changed);
        
        Gtk.ToggleActionEntry[] toggle_actions = new Gtk.ToggleActionEntry[0];
        
        Gtk.ToggleActionEntry flagged_action = { "CommonDisplayFlagged", Resources.ICON_FLAGGED_PAGE,
            TRANSLATABLE, null, TRANSLATABLE, on_flagged_toggled, Config.get_instance().get_search_flagged() };
        flagged_action.label = _("Flagged");
        flagged_action.tooltip = _("Display flagged media");
        toggle_actions += flagged_action;
        
        Gtk.ToggleActionEntry photos_action = { "CommonDisplayPhotos", Resources.ICON_SINGLE_PHOTO,
            TRANSLATABLE, null, TRANSLATABLE, on_photos_toggled, Config.get_instance().get_show_media_photos() };
        photos_action.label = _("Photos");
        photos_action.tooltip = _("Display photos");
        toggle_actions += photos_action;
        
        Gtk.ToggleActionEntry videos_action = { "CommonDisplayVideos", Resources.ICON_VIDEOS_PAGE,
            TRANSLATABLE, null, TRANSLATABLE, on_videos_toggled, Config.get_instance().get_show_media_video() };
        videos_action.label = _("Videos");
        videos_action.tooltip = _("Display videos");
        toggle_actions += videos_action;
        
        Gtk.ToggleActionEntry raw_action = { "CommonDisplayRaw", Resources.ICON_CAMERAS, TRANSLATABLE,
            null, TRANSLATABLE, on_raw_toggled, Config.get_instance().get_show_media_raw() };
        raw_action.label = _("RAW Photos");
        raw_action.tooltip = _("Display RAW photos");
        toggle_actions += raw_action;
        
        action_group.add_toggle_actions(toggle_actions, this);
    }
    
    private void on_rating_changed(Gtk.Action action, Gtk.Action current) {
        rating_changed((RatingFilter) ((Gtk.RadioAction) current).get_current_value());
    }
    
    private void on_flagged_toggled(Gtk.Action action) {
        flagged_toggled(((Gtk.ToggleAction) action).active);
    }
    
    private void on_photos_toggled(Gtk.Action action) {
        photos_toggled(((Gtk.ToggleAction) action).active);
    }
    
    private void on_videos_toggled(Gtk.Action action) {
        videos_toggled(((Gtk.ToggleAction) action).active);
    }
    
    private void on_raw_toggled(Gtk.Action action) {
        raw_toggled(((Gtk.ToggleAction) action).active);
    }
}

public class SearchFilterToolbar : Gtk.Toolbar {
    private const int FILTER_BUTTON_MARGIN = 12; // the distance between icon and edge of button
    private const float FILTER_ICON_STAR_SCALE = 0.65f; // changes the size of the filter icon
    private const float FILTER_ICON_SCALE = 0.75f; // changes the size of the all photos icon
    
    // filter_icon_base_width is the width (in px) of a single filter icon such as one star or an "X"
    private const int FILTER_ICON_BASE_WIDTH = 30;
    // filter_icon_plus_width is the width (in px) of the plus icon
    private const int FILTER_ICON_PLUS_WIDTH = 20;

    // Text search box.
    protected class SearchBox : Gtk.ToolItem {
        public signal void text_changed();
    
        private Gtk.Entry entry = new Gtk.Entry();

        public SearchBox() {
            entry.primary_icon_stock = Gtk.STOCK_FIND;
            entry.primary_icon_activatable = false;
            entry.secondary_icon_stock = Gtk.STOCK_CLEAR;
            entry.secondary_icon_activatable = true;
            entry.width_chars = 23;
            entry.focus_in_event.connect(on_editing_started);
            entry.focus_out_event.connect(on_editing_canceled);
            entry.changed.connect(on_text_changed);
            entry.icon_release.connect(on_icon_release);
            entry.key_press_event.connect(on_escape_key); 
            add(entry);
        }
        
        ~SearchBox() {
            entry.focus_in_event.disconnect(on_editing_started);
            entry.focus_out_event.disconnect(on_editing_canceled);
            entry.changed.disconnect(on_text_changed);
            entry.icon_release.disconnect(on_icon_release);
            entry.key_press_event.disconnect(on_escape_key);
        }
        
        private void on_text_changed() {
            text_changed();
        }
        
        private void on_icon_release(Gtk.EntryIconPosition pos, Gdk.Event event) {
            if (Gtk.EntryIconPosition.SECONDARY == pos) {
                clear();
            }
        }
        
        public string get_text() {
            return entry.text;
        }
        
        public void set_text(string t) {
            entry.text = t;
        }
        
        public void clear() {
            entry.set_text("");
        }
        
        private bool on_editing_started(Gdk.EventFocus event) {
            // Prevent window from stealing our keystrokes.
            AppWindow.get_instance().pause_keyboard_trapping();
            return false;
        }
        
        private bool on_editing_canceled(Gdk.EventFocus event) {
            AppWindow.get_instance().resume_keyboard_trapping();
            return false;
        }
        
        public void get_focus() {
            entry.has_focus = true;
        }
        
        // Ticket #3124 - user should be able to clear 
        // the search textbox by typing 'Esc'. 
        private bool on_escape_key(Gdk.EventKey e) { 
            if(Gdk.keyval_name(e.keyval) == "Escape") { 
                this.clear(); 
			} 
 		             
			// Continue processing this event, since the 
			// text entry functionality needs to see it too. 
			return false; 
		}          
    }
    
    // Handles ratings filters.
    protected class RatingFilterButton : Gtk.ToolButton {
        public Gtk.Menu filter_popup = null;
        
        public RatingFilterButton() {
            set_icon_widget(get_filter_icon(RatingFilter.UNRATED_OR_HIGHER));
            set_homogeneous(false);
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
                case RatingFilter.REJECTED_ONLY:
                    return icon_plus;
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
    
    // Used to disable the toolbar.
    private class DisabledViewFilter : SearchViewFilter {
        public override bool predicate(DataView view) {
            return true;
        }
        
        public override uint get_criteria() {
            return SearchFilterCriteria.NONE;
        }
    }
    
    public Gtk.UIManager ui = new Gtk.UIManager();
    
    private SearchBox search_box = new SearchBox();
    private RatingFilterButton rating_button = new RatingFilterButton();
    private SearchViewFilter? search_filter = null;
    private SearchFilterActions actions = SearchFilterActions.get_instance();
    
    public SearchFilterToolbar() {
        set_name("search-filter-toolbar");
        set_icon_size(Gtk.IconSize.SMALL_TOOLBAR);
        
        File ui_file = Resources.get_ui("search_bar.ui");
        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error err) {
            AppWindow.panic(_("Error loading UI file %s: %s").printf(
                ui_file.get_path(), err.message));
        }
        
        ui.insert_action_group(actions.get_action_group(), 0);
        
        // Separator to right-align toolbar items.
        Gtk.SeparatorToolItem separator_align = new Gtk.SeparatorToolItem();
        separator_align.set_expand(true);
        separator_align.set_draw(false);
        insert(separator_align, -1);
        
        // Rating filter.
        rating_button.filter_popup = (Gtk.Menu) ui.get_widget("/FilterPopupMenu");
        rating_button.set_expand(false);
        rating_button.clicked.connect(on_filter_button_clicked);
        insert(rating_button, -1);
        
        // Separator.
        Gtk.SeparatorToolItem separator_1 = new Gtk.SeparatorToolItem();
        separator_1.set_expand(false);
        separator_1.set_draw(true);
        insert(separator_1, -1);
        
        // Flagged-only.
        Gtk.ToggleToolButton flagged = new Gtk.ToggleToolButton();
        flagged.set_related_action(actions.flagged);
        insert(flagged, -1);
        
        // Separator.
        Gtk.SeparatorToolItem separator_2 = new Gtk.SeparatorToolItem();
        separator_2.set_expand(false);
        separator_2.set_draw(true);
        insert(separator_2, -1);
        
        // Media type buttons.
        Gtk.ToggleToolButton media_photos = new Gtk.ToggleToolButton();
        media_photos.set_related_action(actions.photos);
        insert(media_photos, -1);
        
        Gtk.ToggleToolButton media_video = new Gtk.ToggleToolButton();
        media_video.set_related_action(actions.videos);
        insert(media_video, -1);
        
        Gtk.ToggleToolButton media_raw = new Gtk.ToggleToolButton();
        media_raw.set_related_action(actions.raw);
        insert(media_raw, -1);
        
        // Separator.
        Gtk.SeparatorToolItem separator_3 = new Gtk.SeparatorToolItem();
        separator_3.set_expand(false);
        separator_3.set_draw(true);
        insert(separator_3, -1);
        
        // Search box.
        search_box.text_changed.connect(on_search_changed);
        insert(search_box, -1);
        
        // Load settings.
        restore_saved_search_filter();
        
        // Set background color of toolbar.
        
        string toolbar_style = """
            style "search-filter-toolbar-style"
            {
                GtkToolbar::shadow-type = GTK_SHADOW_IN
                
                color["search_background"] = "%s"
                
                bg[NORMAL] = @search_background
                bg[PRELIGHT] = shade(1.02, @search_background)
                bg[ACTIVE] = shade(0.85, @search_background)
            }

            widget_class "*<SearchFilterToolbar>*" style "search-filter-toolbar-style"
        """.printf(Config.get_instance().get_bg_color().to_string());
        Gtk.rc_parse_string(toolbar_style);
        
        // hook up signals to actions to be notified when they change
        actions.flagged_toggled.connect(on_flagged_toggled);
        actions.photos_toggled.connect(on_photos_toggled);
        actions.videos_toggled.connect(on_videos_toggled);
        actions.raw_toggled.connect(on_raw_toggled);
        actions.rating_changed.connect(on_rating_changed);
    }
    
    ~SearchFilterToolbar() {
        actions.flagged_toggled.disconnect(on_flagged_toggled);
        actions.photos_toggled.disconnect(on_photos_toggled);
        actions.videos_toggled.disconnect(on_videos_toggled);
        actions.raw_toggled.disconnect(on_raw_toggled);
        actions.rating_changed.disconnect(on_rating_changed);
    }
    
    private void on_flagged_toggled() {
        update();
    }
    
    private void on_videos_toggled() {
        update();
    }
    
    private void on_photos_toggled() {
        update();
    }
    
    private void on_raw_toggled() {
        update();
    }
    
    private void on_search_changed() {
        update();
    }
    
    private void on_rating_changed() {
        update();
    }
    
    public string get_search_text() {
        return search_box.get_text();
    }
    
    public void set_search_text(string text) {
        search_box.set_text(text);
    }
    
    public void clear_search_text() {
        search_box.clear();
    }
    
    public void set_view_filter(SearchViewFilter search_filter) {
        this.search_filter = search_filter;
        
        // Enable/disable toolbar features depending on what the filter offers
        actions.set_sensitive_for_search_criteria(search_filter.get_criteria());
        search_box.sensitive = (SearchFilterCriteria.TEXT & search_filter.get_criteria()) != 0;
        rating_button.sensitive = (SearchFilterCriteria.RATING & search_filter.get_criteria()) != 0;
        
        update();
    }
    
    public void unset_view_filter() {
        set_view_filter(new DisabledViewFilter());
    }
    
    // Forces an update of the search filter.
    public void update() {
        if (null == search_filter) 
            return;
        
        search_filter.set_search_filter(get_search_text());
        search_filter.flagged = actions.flagged.active;
        search_filter.show_media_video = actions.videos.active;
        search_filter.show_media_photos = actions.photos.active;
        search_filter.show_media_raw = actions.raw.active;
        
        RatingFilter filter = (RatingFilter) actions.rating.current_value;
        search_filter.set_rating_filter(filter);
        rating_button.set_filter_icon(filter);
        
        // Save and send update to view collection.
        save_search_filter();
        search_filter.refresh();
    }
    
    // Reset all controls to default state
    public void reset() {
        clear_search_text();
        actions.flagged.active = false;
        actions.photos.active = false;
        actions.raw.active = false;
        actions.videos.active = false;
        actions.rating.current_value = RatingFilter.UNRATED_OR_HIGHER;
    }
    
    // Saves settings.
    private void save_search_filter() {
        Config.get_instance().set_search_text(get_search_text());
    }
    
    // Loads saved settings.
    private void restore_saved_search_filter() {
        string? search = Config.get_instance().get_search_text();
        if (null != search) {
            set_search_text(search);
        } else {
            clear_search_text();
        }
    }
    
    private void position_filter_popup(Gtk.Menu menu, out int x, out int y, out bool push_in) {
        menu.realize();
        int rx, ry;
        AppWindow.get_instance().window.get_root_origin(out rx, out ry);
        
        x = rx + rating_button.allocation.x;
        y = ry + rating_button.allocation.y + rating_button.allocation.height +
            AppWindow.get_instance().get_current_page().get_menubar().allocation.height;

        push_in = false;
    }
    
    private void on_filter_button_clicked() {
        rating_button.filter_popup.popup(null, null, position_filter_popup, 0,
            Gtk.get_current_event_time());
    }
    
    public void take_focus() {
        search_box.get_focus();
    }
}

