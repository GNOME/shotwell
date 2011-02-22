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

    private SearchBox search_box;
    private Gtk.ToggleToolButton flagged;
    private RatingFilterButton rating_button;
    private Gtk.ToggleToolButton media_video;
    private Gtk.ToggleToolButton media_photos;
    private Gtk.ToggleToolButton media_raw;
    
    private SearchViewFilter? search_filter = null;
    public Gtk.UIManager ui = new Gtk.UIManager();
    private Gtk.ActionGroup action_group;

    // Called when any search filters have changed.
    public virtual signal void changed() {
    }

    public SearchFilterToolbar() {
        set_name("search-filter-toolbar");
        set_icon_size(Gtk.IconSize.SMALL_TOOLBAR);
        register_actions();
        
        File ui_file = Resources.get_ui("search_bar.ui");
        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error err) {
            AppWindow.error_message(_("Error loading UI file %s: %s").printf(
                ui_file.get_path(), err.message));
            Application.get_instance().panic();
        }
        
        // Separator to right-align toolbar items.
        Gtk.SeparatorToolItem separator_align = new Gtk.SeparatorToolItem();
        separator_align.set_expand(true);
        separator_align.set_draw(false);
        insert(separator_align, -1);
        
        // Rating filter.
        rating_button = new RatingFilterButton();
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
        flagged = new Gtk.ToggleToolButton.from_stock(Resources.ICON_FLAGGED_PAGE);
        flagged.toggled.connect(on_flag_toggle);
        flagged.tooltip_text = _("Toggle flagged-only");
        insert(flagged, -1);
        
        // Separator.
        Gtk.SeparatorToolItem separator_2 = new Gtk.SeparatorToolItem();
        separator_2.set_expand(false);
        separator_2.set_draw(true);
        insert(separator_2, -1);
        
        // Media type buttons.
        media_photos = new Gtk.ToggleToolButton.from_stock(Resources.ICON_SINGLE_PHOTO);
        media_photos.toggled.connect(on_photos_toggle);
        media_photos.tooltip_text = _("Toggle photos");
        insert(media_photos, -1);
        
        media_video = new Gtk.ToggleToolButton.from_stock(Resources.ICON_VIDEOS_PAGE);
        media_video.toggled.connect(on_video_toggle);
        media_video.tooltip_text = _("Toggle video");
        insert(media_video, -1);
        
        media_raw = new Gtk.ToggleToolButton.from_stock(Resources.ICON_CAMERAS);
        media_raw.toggled.connect(on_raw_toggle);
        media_raw.tooltip_text = _("Toggle raw");
        insert(media_raw, -1);
        
        // Separator.
        Gtk.SeparatorToolItem separator_3 = new Gtk.SeparatorToolItem();
        separator_3.set_expand(false);
        separator_3.set_draw(true);
        insert(separator_3, -1);
        
        // Search box.
        search_box = new SearchBox();
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
    }
    
    private void register_actions() {
        action_group = new Gtk.ActionGroup("FilterPopupMenu");
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
        
        action_group.add_radio_actions(view_filter_actions, Config.get_instance().get_photo_rating_filter(),
            on_rating_filter_changed);
        
        ui.insert_action_group(action_group, 0);
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
    
    private void on_flag_toggle() {
        update();
    }
    
    private void on_video_toggle() {
        update();
    }
    
    private void on_photos_toggle() {
        update();
    }
    
    private void on_raw_toggle() {
        update();
    }
    
    private void on_search_changed() {
        update();
    }
    
    public bool get_flagged() {
        return flagged.active;
    }
    
    public void set_flagged(bool f) {
        flagged.active = f;
    }
    
    public bool get_toggle_media_video() {
        return media_video.active;
    }
    
    public void set_toggle_media_video(bool m) {
        media_video.active = m;
    }
    
    public bool get_toggle_media_photos() {
        return media_photos.active;
    }
    
    public void set_toggle_media_photos(bool m) {
        media_photos.active = m;
    }
    
    public bool get_toggle_media_raw() {
        return media_raw.active;
    }
    
    public void set_toggle_media_raw(bool m) {
        media_raw.active = m;
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
        
        // Enable/disable toolbar features.
        // TODO: recursive
        // SearchFilterCriteria.RECURSIVE & search_fitler.get_criteria()
        search_box.sensitive = (bool) (SearchFilterCriteria.TEXT & search_filter.get_criteria());
        flagged.sensitive = (bool) (SearchFilterCriteria.FLAG & search_filter.get_criteria());
        media_video.sensitive = media_photos.sensitive = media_raw.sensitive = 
            (bool) (SearchFilterCriteria.MEDIA & search_filter.get_criteria());
        rating_button.sensitive = (bool) (SearchFilterCriteria.RATING & search_filter.get_criteria());
        
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
        search_filter.flagged = get_flagged();
        search_filter.show_media_video = get_toggle_media_video();
        search_filter.show_media_photos = get_toggle_media_photos();
        search_filter.show_media_raw = get_toggle_media_raw();
        
        RatingFilter filter = get_rating_filter();
        search_filter.set_rating_filter(filter);
        rating_button.set_filter_icon(filter);
        
        // Save and send update to view collection.
        save_search_filter();
        search_filter.refresh();
    }
    
    // Reset all controls to default state
    public void reset() {
        clear_search_text();
        set_flagged(false);
        set_toggle_media_photos(false);
        set_toggle_media_raw(false);
        set_toggle_media_video(false);
        set_rating_filter(RatingFilter.UNRATED_OR_HIGHER);
    }
    
    // Saves settings.
    private void save_search_filter() {
        Config.get_instance().set_search_text(get_search_text());
        Config.get_instance().set_search_flagged(get_flagged());
        Config.get_instance().set_show_media_video(get_toggle_media_video());
        Config.get_instance().set_show_media_photos(get_toggle_media_photos());
        Config.get_instance().set_show_media_raw(get_toggle_media_raw());
    }
    
    // Loads saved settings.
    private void restore_saved_search_filter() {
        string? search = Config.get_instance().get_search_text();
        if (null != search) {
            set_search_text(search);
        } else {
            clear_search_text();
        }
        
        set_flagged(Config.get_instance().get_search_flagged());
        set_rating_view_filter_menu(Config.get_instance().get_photo_rating_filter());
        set_toggle_media_video(Config.get_instance().get_show_media_video());
        set_toggle_media_photos(Config.get_instance().get_show_media_photos());
        set_toggle_media_raw(Config.get_instance().get_show_media_raw());
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
    
    protected void on_rating_filter_changed() {
        update();
    }
    
    protected RatingFilter get_rating_filter() {
        // any member of the group knows the current value
        Gtk.RadioAction? action = ui.get_action("/FilterPopupMenu/DisplayRejectedOrHigher")
            as Gtk.RadioAction;
        assert(action != null);
        
        return (RatingFilter) action.get_current_value();
    }
    
    public void set_rating_filter(RatingFilter filter) {
        // any member of the group knows the current value
        Gtk.RadioAction? action = ui.get_action("/FilterPopupMenu/DisplayRejectedOrHigher")
            as Gtk.RadioAction;
        assert(action != null);
        
        action.set_current_value(filter);
    }
    
    public void take_focus() {
        search_box.get_focus();
    }
}

