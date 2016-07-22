/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Bitfield values used to specify which search bar features we want.
[Flags]
public enum SearchFilterCriteria {
    NONE = 0,
    RECURSIVE,
    TEXT,
    FLAG,
    MEDIA,
    RATING,
    SAVEDSEARCH,
    ALL = 0xFFFFFFFF
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
    private Rating rating = Rating.UNRATED;
    private RatingFilter rating_filter = RatingFilter.UNRATED_OR_HIGHER;
    
    // Show flagged only if set to true.
    public bool flagged { get; set; default = false; }
    
    // Media types.
    public bool show_media_video { get; set; default = true; }
    public bool show_media_photos { get; set; default = true; }
    public bool show_media_raw { get; set; default = true; }
    
    // Search text filter.  Should only be set to lower-case.
    private string? search_filter = null;
    private string[]? search_filter_words = null;

    // Saved search filter
    public SavedSearch saved_search { get; set; default = null; }
    
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
    
    public bool has_search_filter() {
        return !is_string_empty(search_filter);
    }
    
    public unowned string? get_search_filter() {
        return search_filter;
    }
       
    public unowned string[]? get_search_filter_words() {
        return search_filter_words;
    }
    
    public void set_search_filter(string? text) {
        search_filter = !is_string_empty(text) ? text.down() : null;
        search_filter_words = search_filter != null ? search_filter.split(" ") : null;
    }
    
    public void clear_search_filter() {
        search_filter = null;
        search_filter_words = null;
    }
    
    public bool has_saved_search() {
        return saved_search != null;
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
        uint criteria = get_criteria();
        
        // Ratings filter
        if ((SearchFilterCriteria.RATING & criteria) != 0) {
            if (get_rating_allow_higher() && source.get_rating() < get_rating())
                return false;
            else if (!get_rating_allow_higher() && source.get_rating() != get_rating())
                return false;
        }
        
        // Flag state.
        if ((SearchFilterCriteria.FLAG & criteria) != 0) {
            if (flagged && source is Flaggable && !((Flaggable) source).is_flagged())
                return false;
        }
        
        // Media type.
        if (((SearchFilterCriteria.MEDIA & criteria) != 0) && filter_by_media_type()) {
            if (source is VideoSource) {
                if (!show_media_video)
                    return false;
            } else if (source is Photo) {
                Photo photo = source as Photo;
                if (photo.get_master_file_format() == PhotoFileFormat.RAW) {
                    if (photo.is_raw_developer_available(RawDeveloper.CAMERA)) {
                        if (!show_media_photos && !show_media_raw)
                            return false;
                    } else if (!show_media_raw) {
                        return false;
                    }
                } else if (!show_media_photos)
                    return false;
            }
        }
        
        // Text
        if (((SearchFilterCriteria.TEXT & criteria) != 0) && has_search_filter()) {
            unowned string? media_keywords = source.get_indexable_keywords();
            
            unowned string? event_keywords = null;
            Event? event = source.get_event();
            if (event != null)
                event_keywords = event.get_indexable_keywords();
            
            Gee.List<Tag>? tags = Tag.global.fetch_for_source(source);
            int tags_size = (tags != null) ? tags.size : 0;
 
            foreach (unowned string word in get_search_filter_words()) {
                if (media_keywords != null && media_keywords.contains(word))
                    continue;
                
                if (event_keywords != null && event_keywords.contains(word))
                    continue;
                
                if (tags_size > 0) {
                    bool found = false;
                    for (int ctr = 0; ctr < tags_size; ctr++) {
                        unowned string? tag_keywords = tags[ctr].get_indexable_keywords();
                        if (tag_keywords != null && tag_keywords.contains(word)) {
                            found = true;
                            
                            break;
                        }
                    }
                    
                    if (found)
                        continue;
                }
                
                // failed all tests (this even works if none of the Indexables have strings,
                // as they fail the implicit AND test)
                return false;
            }
        }
        
        // Saved search
        if (((SearchFilterCriteria.SAVEDSEARCH & criteria) != 0) && has_saved_search()) {
            return saved_search.predicate(source);
        }

        return true;
    }
}

public class DisabledViewFilter : SearchViewFilter {
    public override bool predicate(DataView view) {
        return true;
    }
    
    public override uint get_criteria() {
        return SearchFilterCriteria.RATING;
    }
}

public class TextAction {
    public string? value {
        get {
            return text;
        }
    }
    
    private string? text = null;
    private bool sensitive = true;
    private bool visible = true;
    
    public signal void text_changed(string? text);
    
    public signal void sensitivity_changed(bool sensitive);
    
    public signal void visibility_changed(bool visible);
    
    public TextAction(string? init = null) {
        text = init;
    }
    
    public void set_text(string? text) {
        if (this.text != text) {
            this.text = text;
            text_changed(text);
        }
    }
    
    public void clear() {
        set_text(null);
    }
    
    public bool is_sensitive() {
        return sensitive;
    }
    
    public void set_sensitive(bool sensitive) {
        if (this.sensitive != sensitive) {
            this.sensitive = sensitive;
            sensitivity_changed(sensitive);
        }
    }
    
    public bool is_visible() {
        return visible;
    }
    
    public void set_visible(bool visible) {
        if (this.visible != visible) {
            this.visible = visible;
            visibility_changed(visible);
        }
    }
}


public class SearchFilterActions {
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
    
    public unowned TextAction text {
        get {
            assert(_text != null);
            return _text;
        }
    }
    
    private Gtk.ActionGroup action_group = new Gtk.ActionGroup("SearchFilterActionGroup");
    private SearchFilterCriteria criteria = SearchFilterCriteria.ALL;
    private TextAction? _text = null;
    private bool has_flagged = true;
    private bool has_photos = true;
    private bool has_videos = true;
    private bool has_raw = true;
    private bool can_filter_by_stars = true;
    
    public signal void flagged_toggled(bool on);
    
    public signal void photos_toggled(bool on);
    
    public signal void videos_toggled(bool on);
    
    public signal void raw_toggled(bool on);
    
    public signal void rating_changed(RatingFilter filter);
    
    public signal void text_changed(string? text);
    
    /**
     * fired when the kinds of media present in the current view change (e.g., a video becomes
     * available in the view through a new import operation or no raw photos are available in
     * the view anymore because the last one was moved to the trash)
     */
    public signal void media_context_changed(bool has_photos, bool has_videos, bool has_raw,
        bool has_flagged);
    
    // Ticket #3290 - Hide some search bar fields when they
    // cannot be used.
    // Part 1 - we use this to announce when the criteria have changed,
    // and the toolbar can listen for it and hide or show widgets accordingly.
    public signal void criteria_changed();
    
    public SearchFilterActions() {
        // the getters defined above should not be used until register() returns
        register();
        
        text.text_changed.connect(on_text_changed);
    }
    
    public Gtk.ActionGroup get_action_group() {
        return action_group;
    }
    
    public SearchFilterCriteria get_criteria() {
        return criteria;
    }
    
    public unowned Gtk.Action? get_action(string name) {
        return action_group.get_action(name);
    }
    
    public void set_action_sensitive(string name, bool sensitive) {
        Gtk.Action? action = get_action(name);
        if (action != null)
            action.sensitive = sensitive;
    }
    
    public void reset() {
        flagged.active = false;
        photos.active = false;
        raw.active = false;
        videos.active = false;
        rating.current_value = RatingFilter.UNRATED_OR_HIGHER;
        text.set_text(null);
    }
    
    public void set_sensitive_for_search_criteria(SearchFilterCriteria criteria) {
        this.criteria = criteria;
        update_sensitivities();
        
        // Announce that we've gotten a new criteria...
        criteria_changed();
    }
    
    public void monitor_page_contents(Page? old_page, Page? new_page) {
        CheckerboardPage? old_tracked_page = old_page as CheckerboardPage;
        if (old_tracked_page != null) {
            Core.ViewTracker? tracker = old_tracked_page.get_view_tracker();
            if (tracker is MediaViewTracker)
                tracker.updated.disconnect(on_media_tracker_updated);
            else if (tracker is CameraViewTracker)
                tracker.updated.disconnect(on_camera_tracker_updated);
        }
        
        CheckerboardPage? new_tracked_page = new_page as CheckerboardPage;
        if (new_tracked_page != null) {
            can_filter_by_stars = true;
            
            Core.ViewTracker? tracker = new_tracked_page.get_view_tracker();
            if (tracker is MediaViewTracker) {
                tracker.updated.connect(on_media_tracker_updated);
                on_media_tracker_updated(tracker);
                
                return;
            } else if (tracker is CameraViewTracker) {
                tracker.updated.connect(on_camera_tracker_updated);
                on_camera_tracker_updated(tracker);
                
                return;
            }
        }
        
        // go with default behavior of making none of the filters available.
        has_flagged = false;
        has_photos = false;
        has_videos = false;
        has_raw = false;
        can_filter_by_stars = false;
        
        update_sensitivities();
    }
    
    private void on_media_tracker_updated(Core.Tracker t) {
        MediaViewTracker tracker = (MediaViewTracker) t;
        
        has_flagged = tracker.all.flagged > 0;
        has_photos = tracker.all.photos > 0;
        has_videos = tracker.all.videos > 0;
        has_raw = tracker.all.raw > 0;
        
        update_sensitivities();
    }
    
    private void on_camera_tracker_updated(Core.Tracker t) {
        CameraViewTracker tracker = (CameraViewTracker) t;
        
        has_flagged = false;
        has_photos = tracker.all.photos > 0;
        has_videos = tracker.all.videos > 0;
        has_raw = tracker.all.raw > 0;

        update_sensitivities();
    }
    
    private void update_sensitivities() {
        flagged.set_stock_id(((SearchFilterCriteria.FLAG & criteria) != 0 && has_flagged) ?
            Resources.ICON_FILTER_FLAGGED : Resources.ICON_FILTER_FLAGGED_DISABLED);
        
        bool allow_media = (SearchFilterCriteria.MEDIA & criteria) != 0;
        videos.set_stock_id((allow_media && has_videos) ?
             Resources.ICON_FILTER_VIDEOS :  Resources.ICON_FILTER_VIDEOS_DISABLED);
        photos.set_stock_id((allow_media && has_photos) ?
             Resources.ICON_FILTER_PHOTOS :  Resources.ICON_FILTER_PHOTOS_DISABLED);
        raw.set_stock_id((allow_media && has_raw) ?
             Resources.ICON_FILTER_RAW :  Resources.ICON_FILTER_RAW_DISABLED);
        
        bool allow_ratings = (SearchFilterCriteria.RATING & criteria) != 0;
        set_action_sensitive("CommonDisplayRejectedOnly", allow_ratings & can_filter_by_stars);
        set_action_sensitive("CommonDisplayRejectedOrHigher", allow_ratings & can_filter_by_stars);
        set_action_sensitive("CommonDisplayUnratedOrHigher", allow_ratings & can_filter_by_stars);
        set_action_sensitive("CommonDisplayOneOrHigher", allow_ratings & can_filter_by_stars);
        set_action_sensitive("CommonDisplayTwoOrHigher", allow_ratings & can_filter_by_stars);
        set_action_sensitive("CommonDisplayThreeOrHigher", allow_ratings & can_filter_by_stars);
        set_action_sensitive("CommonDisplayFourOrHigher", allow_ratings & can_filter_by_stars);
        set_action_sensitive("CommonDisplayFiveOrHigher", allow_ratings & can_filter_by_stars);
        
        // Ticket #3343 - Don't disable the text field, even
        // when no searchable items are available.
        text.set_sensitive(true);
        
        media_context_changed(has_photos, has_videos, has_raw, has_flagged);
    }
    
    private void on_text_changed(TextAction action, string? text) {
        text_changed(text);
    }
    
    private void register() {
        _text = new TextAction();
        
        Gtk.RadioActionEntry[] view_filter_actions = new Gtk.RadioActionEntry[0];
        
        Gtk.RadioActionEntry rejected_only = { "CommonDisplayRejectedOnly", null, TRANSLATABLE,
            "<Ctrl>8", TRANSLATABLE, RatingFilter.REJECTED_ONLY };
        rejected_only.label = Resources.DISPLAY_REJECTED_ONLY_MENU;
        rejected_only.tooltip = Resources.DISPLAY_REJECTED_ONLY_TOOLTIP;
        view_filter_actions += rejected_only;
        
        Gtk.RadioActionEntry rejected_or_higher = { "CommonDisplayRejectedOrHigher", null, TRANSLATABLE,
            "<Ctrl>9", TRANSLATABLE, RatingFilter.REJECTED_OR_HIGHER };
        rejected_or_higher.label = Resources.DISPLAY_REJECTED_OR_HIGHER_MENU;
        rejected_or_higher.tooltip = GLib.dpgettext2 (null, "Tooltip",
                Resources.DISPLAY_REJECTED_OR_HIGHER_TOOLTIP);
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
        
        action_group.add_radio_actions(view_filter_actions, RatingFilter.UNRATED_OR_HIGHER,
            on_rating_changed);
        
        Gtk.ToggleActionEntry[] toggle_actions = new Gtk.ToggleActionEntry[0];
        
        Gtk.ToggleActionEntry flagged_action = { "CommonDisplayFlagged", Resources.ICON_FILTER_FLAGGED,
            TRANSLATABLE, null, TRANSLATABLE, on_flagged_toggled, false };
        flagged_action.label = _("Flagged");
        flagged_action.tooltip = _("Flagged");
        toggle_actions += flagged_action;
        
        Gtk.ToggleActionEntry photos_action = { "CommonDisplayPhotos", Resources.ICON_FILTER_PHOTOS,
            TRANSLATABLE, null, TRANSLATABLE, on_photos_toggled, false };
        photos_action.label = _("Photos");
        photos_action.tooltip = _("Photos");
        toggle_actions += photos_action;
        
        Gtk.ToggleActionEntry videos_action = { "CommonDisplayVideos", Resources.ICON_FILTER_VIDEOS,
            TRANSLATABLE, null, TRANSLATABLE, on_videos_toggled, false };
        videos_action.label = _("Videos");
        videos_action.tooltip = _("Videos");
        toggle_actions += videos_action;
        
        Gtk.ToggleActionEntry raw_action = { "CommonDisplayRaw", Resources.ICON_FILTER_RAW, TRANSLATABLE,
            null, TRANSLATABLE, on_raw_toggled, false };
        raw_action.label = _("RAW Photos");
        raw_action.tooltip = _("RAW photos");
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
    
    public bool get_has_photos() {
        return has_photos;
    }
    
    public bool get_has_videos() {
        return has_videos;
    }
    
    public bool get_has_raw() {
        return has_raw;
    }
    
    public bool get_has_flagged() {
        return has_flagged;
    }
}

public class SearchFilterToolbar : Gtk.Revealer {
    private Gtk.Toolbar toolbar;
    private const int FILTER_BUTTON_MARGIN = 12; // the distance between icon and edge of button
    private const float FILTER_ICON_STAR_SCALE = 0.65f; // changes the size of the filter icon
    private const float FILTER_ICON_SCALE = 0.75f; // changes the size of the all photos icon
    
    // filter_icon_base_width is the width (in px) of a single filter icon such as one star or an "X"
    private const int FILTER_ICON_BASE_WIDTH = 30;
    // filter_icon_plus_width is the width (in px) of the plus icon
    private const int FILTER_ICON_PLUS_WIDTH = 20;
    
    private class LabelToolItem : Gtk.ToolItem {
        private Gtk.Label label;
        
        public LabelToolItem(string s, int left_padding = 0, int right_padding = 0) {
            label = new Gtk.Label(s);
            if (left_padding != 0 || right_padding != 0) {
                Gtk.Alignment alignment = new Gtk.Alignment(0, 0.5f, 0, 0);
                alignment.add(label);
                alignment.left_padding = left_padding;
                alignment.right_padding = right_padding;
                add(alignment);
            } else {
                add(label);
            }
        }
    }
    
    private class ToggleActionToolButton : Gtk.ToolItem {
        private Gtk.ToggleButton button;
        private Gtk.ToggleAction action;

        public ToggleActionToolButton(Gtk.ToggleAction action) {
            this.action = action;
            button = new Gtk.ToggleButton();
            button.set_can_focus(false);
            button.set_active(action.active);
            button.clicked.connect(on_button_activate);
            button.set_has_tooltip(true);
            button.set_relief(Gtk.ReliefStyle.NONE);
            button.set_margin_start(2);
            
            this.add(button);
        }
        
        ~ToggleActionToolButton() {
            button.clicked.disconnect(on_button_activate);
        }
        
        private void on_button_activate() {
            action.activate();
        }
        
        public void set_icon_name(string icon_name) {
            Gtk.Image? image = null;
            button.set_always_show_image(true);
            if (icon_name.contains("disabled"))
                image = new Gtk.Image.from_stock(icon_name, Gtk.IconSize.SMALL_TOOLBAR);
            else
                image = new Gtk.Image.from_icon_name(icon_name, Gtk.IconSize.SMALL_TOOLBAR);
            image.set_margin_end(6);
            button.set_image(image);
        }

        public void set_label(string label) {
            button.set_label(label);
        }

    }
    
    // Ticket #3260 - Add a 'close' context menu to
    // the searchbar.
    // The close menu. Populated below in the constructor.
    private Gtk.Menu close_menu = new Gtk.Menu();
    private Gtk.MenuItem close_item = new Gtk.MenuItem();

    // Text search box.
    protected class SearchBox : Gtk.ToolItem {
        private Gtk.SearchEntry search_entry;
        private TextAction action;
        
        public SearchBox(TextAction action) {
            this.action = action;
            search_entry = new Gtk.SearchEntry();
            
            search_entry.width_chars = 23;
            search_entry.key_press_event.connect(on_escape_key); 
            add(search_entry);
            
            set_nullable_text(action.value);
            
            action.text_changed.connect(on_action_text_changed);
            action.sensitivity_changed.connect(on_sensitivity_changed);
            action.visibility_changed.connect(on_visibility_changed);
            
            search_entry.buffer.deleted_text.connect(on_entry_changed);
            search_entry.buffer.inserted_text.connect(on_entry_changed);
        }
        
        ~SearchBox() {
            action.text_changed.disconnect(on_action_text_changed);
            action.sensitivity_changed.disconnect(on_sensitivity_changed);
            action.visibility_changed.disconnect(on_visibility_changed);
            
            search_entry.buffer.deleted_text.disconnect(on_entry_changed);
            search_entry.buffer.inserted_text.disconnect(on_entry_changed);
        }
        
        public void get_focus() {
            search_entry.has_focus = true;
        }
        
        // Ticket #3124 - user should be able to clear 
        // the search textbox by typing 'Esc'. 
        private bool on_escape_key(Gdk.EventKey e) { 
            if(Gdk.keyval_name(e.keyval) == "Escape")
                action.clear();
            
           // Continue processing this event, since the 
           // text entry functionality needs to see it too. 
            return false; 
        }
        
        private void on_action_text_changed(string? text) {
            search_entry.buffer.deleted_text.disconnect(on_entry_changed);
            search_entry.buffer.inserted_text.disconnect(on_entry_changed);
            set_nullable_text(text);
            search_entry.buffer.deleted_text.connect(on_entry_changed);
            search_entry.buffer.inserted_text.connect(on_entry_changed);
        }
        
        private void on_entry_changed() {
            action.text_changed.disconnect(on_action_text_changed);
            action.set_text(search_entry.get_text());
            action.text_changed.connect(on_action_text_changed);
        }
        
        private void on_sensitivity_changed(bool sensitive) {
            this.sensitive = sensitive;
        }
        
        private void on_visibility_changed(bool visible) {
            ((Gtk.Widget) this).visible = visible;
        }
        
        private void set_nullable_text(string? text) {
            search_entry.set_text(text != null ? text : "");
        }
    }
    
    // Handles ratings filters.
    protected class RatingFilterButton : Gtk.ToolItem {
        public Gtk.Menu filter_popup = null;
        public Gtk.Button button;
        
        public signal void clicked();
        
        public RatingFilterButton() {
            button = new Gtk.Button();
            button.set_image(get_filter_icon(RatingFilter.UNRATED_OR_HIGHER));
            button.set_can_focus(false);
            button.set_relief(Gtk.ReliefStyle.NONE);
            button.set_margin_start(2);

            button.clicked.connect(on_clicked);
            
            set_homogeneous(false);
            
            this.add(button);
        }
        
        ~RatingFilterButton() {
            button.clicked.disconnect(on_clicked);
        }
        
        private void on_clicked() {
            clicked();
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
            
            Gtk.Image image = new Gtk.Image.from_pixbuf(Resources.load_icon(filename,
                get_filter_icon_size(filter)));
            image.set_margin_end(6);

            return image;
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
            button.set_always_show_image(true);
            button.set_image(get_filter_icon(filter));
            set_size_request(get_filter_button_size(filter), -1);
            set_tooltip_text(Resources.get_rating_filter_tooltip(filter));
            set_has_tooltip(true);
            show_all();
        }

        private int get_filter_button_size(RatingFilter filter) {
            return get_filter_icon_size(filter) + 2 * FILTER_BUTTON_MARGIN;
        }

        public void set_label(string label) {
            button.set_label(label);
        }

    }

    protected class SavedSearchFilterButton : Gtk.ToolItem {
        public SavedSearchPopover filter_popup = null;
        public Gtk.ToggleButton button;

        public signal void clicked();

        public SavedSearchFilterButton() {
            button = new Gtk.ToggleButton();
            button.set_always_show_image(true);

            Gtk.Image? image = new Gtk.Image.from_icon_name("find", Gtk.IconSize.SMALL_TOOLBAR);
            image.set_margin_end(6);
            button.set_image(image);
            button.set_can_focus(false);

            button.clicked.connect(on_clicked);

            restyle();

            set_homogeneous(false);

            this.add(button);
        }

        ~SavedSearchFilterButton() {
            button.clicked.disconnect(on_clicked);
        }

        private void on_clicked() {
            clicked();
        }

        public void set_active(bool active) {
            button.set_active(active);
        }

        public void set_label(string label) {
            button.set_label(label);
        }

        public void restyle() {
			button.set_size_request(24, 24);
			button.relief = Gtk.ReliefStyle.NONE;
        }
    }

    protected class SavedSearchPopover {
        private Gtk.Popover popover = null;
        private Gtk.ListBox list_box = null;
        private DataButton[] edit_buttons = null;
        private DataButton[] delete_buttons = null;
        Gtk.Button add = null;

        public signal void search_activated(SavedSearch search);
        public signal void edit_clicked(SavedSearch search);
        public signal void delete_clicked(SavedSearch search);
        public signal void add_clicked();

        public signal void closed();

        private class DataButton : Gtk.Bin {
            private Gtk.Button button = null;
            public SavedSearch search { get; private set; }

            public signal void clicked(SavedSearch search);

            public DataButton(SavedSearch search, string name) {
                button = new Gtk.Button.from_icon_name(name, Gtk.IconSize.SMALL_TOOLBAR);
                this.search = search;
                this.add(button);

                restyle();

                button.clicked.connect(on_click);
            }

            ~DataButton() {
                button.clicked.disconnect(on_click);
            }

            public void restyle() {
                button.set_size_request(24, 24);
                button.relief = Gtk.ReliefStyle.NONE;
            }

            private void on_click() {
                clicked(this.search);
            }
        }

        public SavedSearchPopover(Gtk.Widget relative_to) {
            popover = new Gtk.Popover(relative_to);
            popover.closed.connect(on_popover_closed);
            list_box = new Gtk.ListBox();
            edit_buttons = new DataButton[0];
            delete_buttons = new DataButton[0];

            foreach (SavedSearch search in SavedSearchTable.get_instance().get_all()) {
                Gtk.Box row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 1);
                row.set_homogeneous(false);
                Gtk.Label label = new Gtk.Label(search.get_name());
                label.halign = Gtk.Align.START;
                row.pack_start(label, true, true, 3);

                DataButton delete_button = new DataButton(search, "edit-delete-symbolic");
                row.pack_end(delete_button, false, false);
                delete_button.clicked.connect(on_delete_click);
                delete_buttons += delete_button;

                DataButton edit_button = new DataButton(search, "text-editor-symbolic");
                row.pack_end(edit_button, false, false);
                edit_button.clicked.connect(on_edit_click);
                edit_buttons += edit_button;

                list_box.insert(row, -1);
            }
            add = new Gtk.Button.from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON);
            add.clicked.connect(on_add_click);
            list_box.insert(add, -1);
            list_box.row_activated.connect(on_activate_row);
            list_box.selection_mode = Gtk.SelectionMode.NONE;
            popover.add(list_box);

            restyle();
        }

        ~SavedSearchPopover() {
            foreach (DataButton button in edit_buttons) button.clicked.disconnect(on_edit_click);
            foreach (DataButton button in delete_buttons) button.clicked.disconnect(on_delete_click);
            add.clicked.disconnect(on_add_click);
            list_box.row_activated.disconnect(on_activate_row);
            popover.closed.disconnect(on_popover_closed);
        }

        public void restyle() {
            add.relief = Gtk.ReliefStyle.NONE;
            foreach (DataButton button in edit_buttons) button.restyle();
            foreach (DataButton button in delete_buttons) button.restyle();
        }

        private bool is_search_row(Gtk.ListBoxRow? row) {
            if (row == null) return false;
            if (row.get_children().last().data is Gtk.Button) return false;
            return true;
        }

        private SavedSearch get_search(Gtk.ListBoxRow row) {
            DataButton button = (row.get_children().first().data as Gtk.Box).get_children().last().data as DataButton;
            return button.search;
        }

        private void on_activate_row(Gtk.ListBoxRow? row) {
            if (is_search_row(row))
                search_activated(get_search(row));
            popover.hide();
        }

        private void on_edit_click(SavedSearch search) {
            edit_clicked(search);
        }

        private void on_delete_click(SavedSearch search) {
            delete_clicked(search);
        }

        private void on_add_click() {
            add_clicked();
        }

        private void on_popover_closed() {
            closed();
        }

        public void show_all() {
            popover.show_all();
        }

        public void hide() {
            popover.hide();
        }
    }
    
    public Gtk.UIManager ui = new Gtk.UIManager();
    
    private SearchFilterActions actions;
    private SavedSearch saved_search = null;
    private SearchBox search_box;
    private RatingFilterButton rating_button = new RatingFilterButton();
    private SavedSearchFilterButton saved_search_button = new SavedSearchFilterButton();
    private bool elide_showing_again = false;
    private SearchViewFilter? search_filter = null;
    private LabelToolItem label_type;
    private ToggleActionToolButton toolbtn_photos;
    private ToggleActionToolButton toolbtn_videos;
    private ToggleActionToolButton toolbtn_raw;
    private ToggleActionToolButton toolbtn_flag;
    private Gtk.SeparatorToolItem sepr_mediatype_flagged;
    private Gtk.SeparatorToolItem sepr_flagged_rating;
    private Gtk.SeparatorToolItem sepr_rating_saved;
    
    public SearchFilterToolbar(SearchFilterActions actions) {
        this.actions = actions;
        toolbar = new Gtk.Toolbar();
        actions.media_context_changed.connect(on_media_context_changed);
        search_box = new SearchBox(actions.text);
        
        toolbar.set_name("search-filter-toolbar");
        toolbar.set_icon_size(Gtk.IconSize.SMALL_TOOLBAR);
        
        File ui_file = Resources.get_ui("search_bar.ui");
        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error err) {
            AppWindow.panic(_("Error loading UI file %s: %s").printf(
                ui_file.get_path(), err.message));
        }
        
        ui.insert_action_group(actions.get_action_group(), 0);
        
        // Ticket #3260 - Add a 'close' context menu to
        // the searchbar.
        // Prepare the close menu for use, but don't
        // display it yet; we'll connect it to secondary
        // click later on.
        close_item.set_label(_("Close"));
        close_item.show();
        close_item.activate.connect(on_context_menu_close_chosen);
        close_menu.append(close_item);
       
        // Type label and toggles
        label_type = new LabelToolItem(_("Type"), 10, 5);
        toolbar.insert(label_type, -1);
        
        toolbtn_photos = new ToggleActionToolButton(actions.photos);
        toolbtn_photos.set_tooltip_text(actions.get_action_group().get_action("CommonDisplayPhotos").tooltip);
        
        toolbtn_videos = new ToggleActionToolButton(actions.videos);
        toolbtn_videos.set_tooltip_text(actions.get_action_group().get_action("CommonDisplayVideos").tooltip);
        
        toolbtn_raw = new ToggleActionToolButton(actions.raw);
        toolbtn_raw.set_tooltip_text(actions.get_action_group().get_action("CommonDisplayRaw").tooltip);
        
        toolbar.insert(toolbtn_photos, -1);
        toolbar.insert(toolbtn_videos, -1);
        toolbar.insert(toolbtn_raw, -1);
        
        // separator
        sepr_mediatype_flagged = new Gtk.SeparatorToolItem();
        toolbar.insert(sepr_mediatype_flagged, -1);
        
        // Flagged button
        
        toolbtn_flag = new ToggleActionToolButton(actions.flagged);
        toolbtn_flag.set_label(_("Flagged"));
        toolbtn_flag.set_tooltip_text(actions.get_action_group().get_action("CommonDisplayFlagged").tooltip);
        
        toolbar.insert(toolbtn_flag, -1);
        
        // separator
        sepr_flagged_rating = new Gtk.SeparatorToolItem();
        toolbar.insert(sepr_flagged_rating, -1);
        
        // Rating button
        rating_button.filter_popup = (Gtk.Menu) ui.get_widget("/FilterPopupMenu");
        rating_button.set_label(_("Rating"));
        rating_button.set_expand(false);
        rating_button.clicked.connect(on_filter_button_clicked);
        toolbar.insert(rating_button, -1);
        
        // separator
        sepr_rating_saved = new Gtk.SeparatorToolItem();
        toolbar.insert(sepr_rating_saved, -1);

        // Saved search button
        saved_search_button.set_expand(false);
		saved_search_button.set_label(_("Saved Search"));
        saved_search_button.set_tooltip_text(_("Use a saved search to filter items in the current view"));
        saved_search_button.clicked.connect(on_saved_search_button_clicked);
        toolbar.insert(saved_search_button, -1);

        // Separator to right-align the text box
        Gtk.SeparatorToolItem separator_align = new Gtk.SeparatorToolItem();
        separator_align.set_expand(true);
        separator_align.set_draw(false);
        toolbar.insert(separator_align, -1);
        
        // Search box.
        toolbar.insert(search_box, -1);

        add(toolbar);
        
        // hook up signals to actions to be notified when they change
        actions.flagged_toggled.connect(on_flagged_toggled);
        actions.photos_toggled.connect(on_photos_toggled);
        actions.videos_toggled.connect(on_videos_toggled);
        actions.raw_toggled.connect(on_raw_toggled);
        actions.rating_changed.connect(on_rating_changed);
        actions.text_changed.connect(on_search_text_changed);
        actions.criteria_changed.connect(on_criteria_changed);
        
        // #3260 part II Hook up close menu.
        toolbar.popup_context_menu.connect(on_context_menu_requested);
        
        on_media_context_changed(actions.get_has_photos(), actions.get_has_videos(),
            actions.get_has_raw(), actions.get_has_flagged());
    }
    
    ~SearchFilterToolbar() {
        
        actions.media_context_changed.disconnect(on_media_context_changed);

        actions.flagged_toggled.disconnect(on_flagged_toggled);
        actions.photos_toggled.disconnect(on_photos_toggled);
        actions.videos_toggled.disconnect(on_videos_toggled);
        actions.raw_toggled.disconnect(on_raw_toggled);
        actions.rating_changed.disconnect(on_rating_changed);
        actions.text_changed.disconnect(on_search_text_changed);
        actions.criteria_changed.disconnect(on_criteria_changed);
        
        toolbar.popup_context_menu.disconnect(on_context_menu_requested); 
    }
    
    private void on_media_context_changed(bool has_photos, bool has_videos, bool has_raw,
        bool has_flagged) {
        if (has_photos)
            toolbtn_photos.set_icon_name(Resources.ICON_FILTER_PHOTOS);
        else
            toolbtn_photos.set_icon_name(Resources.ICON_FILTER_PHOTOS_DISABLED);

        if (has_videos)
            toolbtn_videos.set_icon_name(Resources.ICON_FILTER_VIDEOS);
        else
            toolbtn_videos.set_icon_name(Resources.ICON_FILTER_VIDEOS_DISABLED);

        if (has_raw)
            toolbtn_raw.set_icon_name(Resources.ICON_FILTER_RAW);
        else
            toolbtn_raw.set_icon_name(Resources.ICON_FILTER_RAW_DISABLED);

        if (has_flagged)
            toolbtn_flag.set_icon_name(Resources.ICON_FILTER_FLAGGED);
        else
            toolbtn_flag.set_icon_name(Resources.ICON_FILTER_FLAGGED_DISABLED);
    }
    
    // Ticket #3260 part IV - display the context menu on secondary click
    private bool on_context_menu_requested(int x, int y, int button) { 
        close_menu.popup(null, null, null, button, Gtk.get_current_event_time()); 
        return false;
    }
    
    // Ticket #3260 part III - this runs whenever 'close'
    // is chosen in the context menu.
    private void on_context_menu_close_chosen() { 
        AppWindow aw = LibraryWindow.get_app();        
        
        // Try to obtain the action for toggling the searchbar.  If
        // it's null, then we're probably in direct edit mode, and 
        // shouldn't do anything anyway.
        Gtk.ToggleAction searchbar_toggle = aw.get_common_action("CommonDisplaySearchbar") as Gtk.ToggleAction;
        
        // Could we find the appropriate action?
        if(searchbar_toggle != null) {
            // Yes, hide the search bar.
            searchbar_toggle.set_active(false);
        }
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
    
    private void on_search_text_changed() {
        update();
    }

    private void on_rating_changed() {
        AppWindow aw = LibraryWindow.get_app();

        if (aw == null)
            return;

        Gtk.ToggleAction searchbar_toggle = aw.get_common_action("CommonDisplaySearchbar") as Gtk.ToggleAction;
        if(searchbar_toggle != null)
            searchbar_toggle.set_active(true);

        update();
    }

    // Ticket #3290, part II - listen for criteria change signals,
    // and show or hide widgets based on the criteria we just 
    // changed to.
    private void on_criteria_changed() {
        update();
    }
    
    public void set_view_filter(SearchViewFilter search_filter) {
        if (search_filter == this.search_filter)
            return;
        
        this.search_filter = search_filter;
        
        // Enable/disable toolbar features depending on what the filter offers
        actions.set_sensitive_for_search_criteria((SearchFilterCriteria) search_filter.get_criteria());
        rating_button.sensitive = (SearchFilterCriteria.RATING & search_filter.get_criteria()) != 0;
        
        update();
    }
    
    public void unset_view_filter() {
        set_view_filter(new DisabledViewFilter());
    }
    
    // Forces an update of the search filter.
    public void update() {
        if (null == search_filter) {
            // Search bar isn't being shown, need to toggle it.
            LibraryWindow.get_app().show_search_bar(true);
        }
        
        assert(null != search_filter);
        
        search_filter.set_search_filter(actions.text.value);
        search_filter.flagged = actions.flagged.active;
        search_filter.show_media_video = actions.videos.active;
        search_filter.show_media_photos = actions.photos.active;
        search_filter.show_media_raw = actions.raw.active;
        
        RatingFilter filter = (RatingFilter) actions.rating.current_value;
        search_filter.set_rating_filter(filter);
        rating_button.set_filter_icon(filter);

        search_filter.saved_search = saved_search;
        
        // Ticket #3290, part III - check the current criteria
        // and show or hide widgets as needed.
        SearchFilterCriteria criteria = actions.get_criteria();
        
        search_box.visible = ((criteria & SearchFilterCriteria.TEXT) != 0);

        rating_button.visible = ((criteria & SearchFilterCriteria.RATING) != 0);
        
        toolbtn_flag.visible = ((criteria & SearchFilterCriteria.FLAG) != 0);
        
        label_type.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0);
        toolbtn_photos.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0); 
        toolbtn_videos.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0);
        toolbtn_raw.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0);

        saved_search_button.visible = ((criteria & SearchFilterCriteria.SAVEDSEARCH) != 0);

        // Ticket #3290, part IV - ensure that the separators
        // are shown and/or hidden as needed.
        sepr_mediatype_flagged.visible = (label_type.visible && toolbtn_flag.visible);

        sepr_flagged_rating.visible = ((label_type.visible && rating_button.visible) ||
            (toolbtn_flag.visible && rating_button.visible));

        // Send update to view collection.
        search_filter.refresh();
    }
    
    private void position_filter_popup(Gtk.Menu menu, out int x, out int y, out bool push_in) {
        menu.realize();
        int rx, ry;
        rating_button.get_window().get_root_origin(out rx, out ry);
        
        Gtk.Allocation rating_button_allocation;
        rating_button.get_allocation(out rating_button_allocation);
        
        Gtk.Allocation menubar_allocation;
        AppWindow.get_instance().get_current_page().get_menubar().get_allocation(out menubar_allocation);
        
        int sidebar_w = Config.Facade.get_instance().get_sidebar_position();
        
        x = rx + rating_button_allocation.x + sidebar_w;
        y = ry + rating_button_allocation.y + rating_button_allocation.height +
                menubar_allocation.height;

        push_in = false;
    }
    
    private void on_filter_button_clicked() {
        rating_button.filter_popup.popup(null, null, position_filter_popup, 0,
            Gtk.get_current_event_time());
    }

    private void on_savedsearch_selected(SavedSearch saved_search) {
        this.saved_search = saved_search;
        update();
    }

    private void disable_savedsearch() {
        this.saved_search = null;
        update();
    }
    
    private void edit_dialog(SavedSearch search) {
        saved_search_button.filter_popup.hide();
        SavedSearchDialog ssd = new SavedSearchDialog.edit_existing(search);
        ssd.show();
    }

    private void delete_dialog(SavedSearch search) {
        saved_search_button.filter_popup.hide();
        if (Dialogs.confirm_delete_saved_search(search))
            AppWindow.get_command_manager().execute(new DeleteSavedSearchCommand(search));
    }

    private void add_dialog() {
        saved_search_button.filter_popup.hide();
        (new SavedSearchDialog()).show();
    }

    private void on_popover_closed() {
        // set_active emits clicked, so have a flag to not actually do anything
        elide_showing_again = true;
        saved_search_button.set_active(saved_search != null);
        saved_search_button.filter_popup.hide();
    }

    private void on_saved_search_button_clicked() {
        if (elide_showing_again && saved_search == null) {
        } else if (saved_search != null) {
            saved_search = null;
            saved_search_button.set_active(false);
            disable_savedsearch();
        } else {
            if (saved_search_button.filter_popup != null) {
                saved_search_button.filter_popup.edit_clicked.disconnect(edit_dialog);
                saved_search_button.filter_popup.search_activated.disconnect(on_savedsearch_selected);
                saved_search_button.filter_popup.delete_clicked.disconnect(delete_dialog);
                saved_search_button.filter_popup.add_clicked.disconnect(add_dialog);
                saved_search_button.filter_popup.closed.disconnect(on_popover_closed);
            }
            saved_search_button.filter_popup = new SavedSearchPopover(saved_search_button);
            saved_search_button.filter_popup.edit_clicked.connect(edit_dialog);
            saved_search_button.filter_popup.search_activated.connect(on_savedsearch_selected);
            saved_search_button.filter_popup.delete_clicked.connect(delete_dialog);
            saved_search_button.filter_popup.add_clicked.connect(add_dialog);
            saved_search_button.filter_popup.closed.connect(on_popover_closed);

            saved_search_button.filter_popup.show_all();
        }
        elide_showing_again = false;
    }

    public void take_focus() {
        search_box.get_focus();
    }
}

