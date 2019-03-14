/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class MediaSourceItem : CheckerboardItem {
    private string? natural_collation_key = null;

    // preserve the same constructor arguments and semantics as CheckerboardItem so that we're
    // a drop-in replacement
    public MediaSourceItem(ThumbnailSource source, Dimensions initial_pixbuf_dim, string title, 
        string? comment, bool marked_up = false, Pango.Alignment alignment = Pango.Alignment.LEFT) {
        base(source, initial_pixbuf_dim, title, comment, marked_up, alignment);
    }

    public new void set_title(string text, bool marked_up = false,
        Pango.Alignment alignment = Pango.Alignment.LEFT) {
        base.set_title(text, marked_up, alignment);
        this.natural_collation_key = null;
    }
    
    public string get_natural_collation_key() {
        if (this.natural_collation_key == null) {
            this.natural_collation_key = NaturalCollate.collate_key(this.get_title());
        }
        return this.natural_collation_key;
    }
}

public abstract class MediaPage : CheckerboardPage {
    public const int SORT_ORDER_ASCENDING = 0;
    public const int SORT_ORDER_DESCENDING = 1;

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public const int MANUAL_STEPPING = 16;
    public const int SLIDER_STEPPING = 4;

    public enum SortBy {
        MIN = 1,
        TITLE = 1,
        EXPOSURE_DATE = 2,
        RATING = 3,
        FILENAME = 4,
        MAX = 4
    }

    protected class ZoomSliderAssembly : Gtk.ToolItem {
        private Gtk.Scale slider;
        private Gtk.Adjustment adjustment;
        
        public signal void zoom_changed();

        public ZoomSliderAssembly() {
            Gtk.Box zoom_group = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

            Gtk.Image zoom_out = new Gtk.Image.from_icon_name("image-zoom-out-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
            Gtk.EventBox zoom_out_box = new Gtk.EventBox();
            zoom_out_box.set_above_child(true);
            zoom_out_box.set_visible_window(false);
            zoom_out_box.add(zoom_out);
            zoom_out_box.button_press_event.connect(on_zoom_out_pressed);
            
            zoom_group.pack_start(zoom_out_box, false, false, 0);

            // virgin ZoomSliderAssemblies are created such that they have whatever value is
            // persisted in the configuration system for the photo thumbnail scale
            int persisted_scale = Config.Facade.get_instance().get_photo_thumbnail_scale();
            adjustment = new Gtk.Adjustment(ZoomSliderAssembly.scale_to_slider(persisted_scale), 0,
                ZoomSliderAssembly.scale_to_slider(Thumbnail.MAX_SCALE), 1, 10, 0);

            slider = new Gtk.Scale(Gtk.Orientation.HORIZONTAL, adjustment);
            slider.value_changed.connect(on_slider_changed);
            slider.set_draw_value(false);
            slider.set_size_request(200, -1);
            slider.set_tooltip_text(_("Adjust the size of the thumbnails"));

            zoom_group.pack_start(slider, false, false, 0);

            Gtk.Image zoom_in = new Gtk.Image.from_icon_name("image-zoom-in-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
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
        
        public void set_scale(int scale) {
            if (get_scale() == scale)
                return;

            slider.set_value(scale_to_slider(scale));
        }
    }
    
    private ZoomSliderAssembly? connected_slider = null;
    private DragAndDropHandler dnd_handler = null;
    private MediaViewTracker tracker;
    
    protected MediaPage(string page_name) {
        base (page_name);
        
        tracker = new MediaViewTracker(get_view());
        
        get_view().items_altered.connect(on_media_altered);

        get_view().freeze_notifications();
        get_view().set_property(CheckerboardItem.PROP_SHOW_TITLES, 
            Config.Facade.get_instance().get_display_photo_titles());
        get_view().set_property(CheckerboardItem.PROP_SHOW_COMMENTS, 
            Config.Facade.get_instance().get_display_photo_comments());
        get_view().set_property(Thumbnail.PROP_SHOW_TAGS, 
            Config.Facade.get_instance().get_display_photo_tags());
        get_view().set_property(Thumbnail.PROP_SIZE, get_thumb_size());
        get_view().set_property(Thumbnail.PROP_SHOW_RATINGS,
            Config.Facade.get_instance().get_display_photo_ratings());
        get_view().thaw_notifications();

        // enable drag-and-drop export of media
        dnd_handler = new DragAndDropHandler(this);
    }
   
    private static int compute_zoom_scale_increase(int current_scale) {
        int new_scale = current_scale + MANUAL_STEPPING;
        return new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
    }
    
    private static int compute_zoom_scale_decrease(int current_scale) {
        int new_scale = current_scale - MANUAL_STEPPING;
        return new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("media.ui");
    }

    private const GLib.ActionEntry[] entries = {
        { "Export", on_export },
        { "SendTo", on_send_to },
        { "SendToContextMenu", on_send_to },
        { "RemoveFromLibrary", on_remove_from_library },
        { "MoveToTrash", on_move_to_trash },
        { "NewEvent", on_new_event },
        { "AddTags", on_add_tags },
        { "ModifyTags", on_modify_tags },
        { "IncreaseSize", on_increase_size },
        { "DecreaseSize", on_decrease_size },
        { "Flag", on_flag_unflag },
        { "IncreaseRating", on_increase_rating },
        { "DecreaseRating", on_decrease_rating },
        { "RateRejected", on_rate_rejected },
        { "RateUnrated", on_rate_unrated },
        { "RateOne", on_rate_one },
        { "RateTwo", on_rate_two },
        { "RateThree", on_rate_three },
        { "RateFour", on_rate_four },
        { "RateFive", on_rate_five },
        { "EditTitle", on_edit_title },
        { "EditComment", on_edit_comment },
        { "PlayVideo", on_play_video },

        // Toggle actions
        { "ViewTitle", on_action_toggle, null, "false", on_display_titles },
        { "ViewComment", on_action_toggle, null, "false", on_display_comments },
        { "ViewRatings", on_action_toggle, null, "false", on_display_ratings },
        { "ViewTags", on_action_toggle, null, "false", on_display_tags },

        // Radio actions
        { "SortBy", on_action_radio, "s", "'1'", on_sort_changed },
        { "Sort", on_action_radio, "s", "'ascending'", on_sort_changed },
    };

    protected override void add_actions (GLib.ActionMap map) {
        base.add_actions (map);

        bool sort_order;
        int sort_by;
        get_config_photos_sort(out sort_order, out sort_by);

        map.add_action_entries (entries, this);
        get_action ("ViewTitle").change_state (Config.Facade.get_instance ().get_display_photo_titles ());
        get_action ("ViewComment").change_state (Config.Facade.get_instance ().get_display_photo_comments ());
        get_action ("ViewRatings").change_state (Config.Facade.get_instance ().get_display_photo_ratings ());
        get_action ("ViewTags").change_state (Config.Facade.get_instance ().get_display_photo_tags ());
        get_action ("SortBy").change_state ("%d".printf (sort_by));
        get_action ("Sort").change_state (sort_order ? "ascending" : "descending");

        var d = Config.Facade.get_instance().get_default_raw_developer();
        var action = new GLib.SimpleAction.stateful("RawDeveloper",
                GLib.VariantType.STRING, d == RawDeveloper.SHOTWELL ? "Shotwell" : "Camera");
        action.change_state.connect(on_raw_developer_changed);
        action.set_enabled(true);
        map.add_action(action);
    }

    protected override void remove_actions(GLib.ActionMap map) {
        base.remove_actions(map);
        foreach (var entry in entries) {
            map.remove_action(entry.name);
        }
    }

    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("Export", selected_count > 0);
        set_action_sensitive("EditTitle", selected_count > 0);
        set_action_sensitive("EditComment", selected_count > 0);
        set_action_sensitive("IncreaseSize", get_thumb_size() < Thumbnail.MAX_SCALE);
        set_action_sensitive("DecreaseSize", get_thumb_size() > Thumbnail.MIN_SCALE);
        set_action_sensitive("RemoveFromLibrary", selected_count > 0);
        set_action_sensitive("MoveToTrash", selected_count > 0);
        
        if (DesktopIntegration.is_send_to_installed())
            set_action_sensitive("SendTo", selected_count > 0);
        else
            set_action_sensitive("SendTo", false);
        
        set_action_sensitive("Rate", selected_count > 0);
        update_rating_sensitivities();
        
        update_development_menu_item_sensitivity();
        
        set_action_sensitive("PlayVideo", selected_count == 1
            && get_view().get_selected_source_at(0) is Video);
        
        update_flag_action(selected_count);
        
        base.update_actions(selected_count, count);
    }
    
    private void on_media_altered(Gee.Map<DataObject, Alteration> altered) {
        foreach (DataObject object in altered.keys) {
            if (altered.get(object).has_detail("metadata", "flagged")) {
                update_flag_action(get_view().get_selected_count());
                
                break;
            }
        }
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
    
    private void update_development_menu_item_sensitivity() {
        if (get_view().get_selected().size == 0) {
            set_action_sensitive("RawDeveloper", false);
            return;
        }
        
        // Collect some stats about what's selected.
        bool is_raw = false;    // True if any RAW photos are selected
        foreach (DataView view in get_view().get_selected()) {
            Photo? photo = ((Thumbnail) view).get_media_source() as Photo;
            if (photo != null && photo.get_master_file_format() == PhotoFileFormat.RAW) {
                is_raw = true;

                break;
            }
        }
        
        // Enable/disable menu.
        set_action_sensitive("RawDeveloper", is_raw);
    }
    
    private void update_flag_action(int selected_count) {
        set_action_sensitive("Flag", selected_count > 0);
    }
    
    public override Core.ViewTracker? get_view_tracker() {
        return tracker;
    }

    public void set_display_ratings(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SHOW_RATINGS, display);
        get_view().thaw_notifications();

        this.set_action_active ("ViewRatings", display);
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
                activate_action("IncreaseSize");
            break;
            
            case "minus":
            case "underscore":
            case "KP_Subtract":
                activate_action("DecreaseSize");
            break;
            
            case "period":
                activate_action("IncreaseRating");
            break;
            
            case "comma":
                activate_action("DecreaseRating");
            break;
            
            case "KP_1":
                activate_action("RateOne");
            break;
            
            case "KP_2":
                activate_action("RateTwo");
            break;
            
            case "KP_3":
                activate_action("RateThree");
            break;
            
            case "KP_4":
                activate_action("RateFour");
            break;
            
            case "KP_5":
                activate_action("RateFive");
            break;
            
            case "KP_0":
                activate_action("RateUnrated");
            break;
            
            case "KP_9":
                activate_action("RateRejected");
            break;
            
            case "slash":
                activate_action("Flag");
            break;
            
            default:
                handled = false;
            break;
        }
        
        return handled ? true : base.on_app_key_pressed(event);
    }

    public override void switched_to() {
        base.switched_to();
        
        // set display options to match Configuration toggles (which can change while switched away)
        get_view().freeze_notifications();
        set_display_titles(Config.Facade.get_instance().get_display_photo_titles());
        set_display_comments(Config.Facade.get_instance().get_display_photo_comments());
        set_display_ratings(Config.Facade.get_instance().get_display_photo_ratings());
        set_display_tags(Config.Facade.get_instance().get_display_photo_tags());
        get_view().thaw_notifications();

        // Update cursor position to match the selection that potentially moved while the user
        // navigated in SinglePhotoPage
        if (get_view().get_selected_count() > 0) {
            CheckerboardItem? selected = (CheckerboardItem?) get_view().get_selected_at(0);
            if (selected != null)
                cursor_to_item(selected);
        }

        sync_sort();
    }
    
    public override void switching_from() {
        disconnect_slider();

        base.switching_from();
    }

    protected void connect_slider(ZoomSliderAssembly slider) {
        connected_slider = slider;
        connected_slider.zoom_changed.connect(on_zoom_changed);
        load_persistent_thumbnail_scale();
    }
    
    private void save_persistent_thumbnail_scale() {
        if (connected_slider == null)
            return;
            
        Config.Facade.get_instance().set_photo_thumbnail_scale(connected_slider.get_scale());
    }
    
    private void load_persistent_thumbnail_scale() {
        if (connected_slider == null)
            return;

        int persistent_scale = Config.Facade.get_instance().get_photo_thumbnail_scale();

        connected_slider.set_scale(persistent_scale);
        set_thumb_size(persistent_scale);
    }
    
    protected void disconnect_slider() {
        if (connected_slider == null)
            return;
        
        connected_slider.zoom_changed.disconnect(on_zoom_changed);
        connected_slider = null;
    }

    protected virtual void on_zoom_changed() {
        if (connected_slider != null)
            set_thumb_size(connected_slider.get_scale());

        save_persistent_thumbnail_scale();
    }
    
    protected abstract void on_export();

    protected virtual void on_increase_size() {
        increase_zoom_level();
    }

    protected virtual void on_decrease_size() {
        decrease_zoom_level();
    }

    private void on_add_tags() {
        if (get_view().get_selected_count() == 0)
            return;
        
        AddTagsDialog dialog = new AddTagsDialog();
        string[]? names = dialog.execute();
        
        if (names != null) {
            get_command_manager().execute(new AddTagsCommand(
                HierarchicalTagIndex.get_global_index().get_paths_for_names_array(names),
                (Gee.Collection<MediaSource>) get_view().get_selected_sources()));
        }
    }

    private void on_modify_tags() {
        if (get_view().get_selected_count() != 1)
            return;
        
        MediaSource media = (MediaSource) get_view().get_selected_at(0).get_source();
        
        ModifyTagsDialog dialog = new ModifyTagsDialog(media);
        Gee.ArrayList<Tag>? new_tags = dialog.execute();
        
        if (new_tags == null)
            return;
        
        get_command_manager().execute(new ModifyTagsCommand(media, new_tags));
    }

    private void set_display_tags(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SHOW_TAGS, display);
        get_view().thaw_notifications();

        this.set_action_active ("ViewTags", display);
    }

    private void on_new_event() {
        if (get_view().get_selected_count() > 0)
            get_command_manager().execute(new NewEventCommand(get_view().get_selected()));
    }
    
    private void on_flag_unflag() {
        if (get_view().get_selected_count() == 0)
            return;
        
        Gee.Collection<MediaSource> sources =
            (Gee.Collection<MediaSource>) get_view().get_selected_sources_of_type(typeof(MediaSource));
        
        // If all are flagged, then unflag, otherwise flag
        bool flag = false;
        foreach (MediaSource source in sources) {
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

    private void on_remove_from_library() {
        remove_photos_from_library((Gee.Collection<LibraryPhoto>) get_view().get_selected_sources());
    }

    protected virtual void on_move_to_trash() {
        CheckerboardItem? restore_point = null;

        if (cursor != null) {
            restore_point = get_view().get_next(cursor) as CheckerboardItem;
        }

        var sources = get_view().get_selected_sources();

        if ((restore_point != null) && (get_view().contains(restore_point))) {
            set_cursor(restore_point);
        }

        if (get_view().get_selected_count() > 0) {
            get_command_manager().execute(new TrashUntrashPhotosCommand(
                (Gee.Collection<MediaSource>) sources, true));
        }

    }

    protected virtual void on_edit_title() {
        if (get_view().get_selected_count() == 0)
            return;
        
        Gee.List<MediaSource> media_sources = (Gee.List<MediaSource>) get_view().get_selected_sources();
        
        EditTitleDialog edit_title_dialog = new EditTitleDialog(media_sources[0].get_title());
        string? new_title = edit_title_dialog.execute();
        if (new_title != null)
            get_command_manager().execute(new EditMultipleTitlesCommand(media_sources, new_title));
    }

    protected virtual void on_edit_comment() {
        if (get_view().get_selected_count() == 0)
            return;
        
        Gee.List<MediaSource> media_sources = (Gee.List<MediaSource>) get_view().get_selected_sources();
        
        EditCommentDialog edit_comment_dialog = new EditCommentDialog(media_sources[0].get_comment());
        string? new_comment = edit_comment_dialog.execute();
        if (new_comment != null)
            get_command_manager().execute(new EditMultipleCommentsCommand(media_sources, new_comment));
    }

    protected virtual void on_display_titles(GLib.SimpleAction action, Variant? value) {
        bool display = value.get_boolean ();
        
        set_display_titles(display);
        
        Config.Facade.get_instance().set_display_photo_titles(display);
        action.set_state (value);
    }

    protected virtual void on_display_comments(GLib.SimpleAction action, Variant? value) {
        bool display = value.get_boolean ();
        
        set_display_comments(display);
        
        Config.Facade.get_instance().set_display_photo_comments(display);
        action.set_state (value);
    }

    protected virtual void on_display_ratings(GLib.SimpleAction action, Variant? value) {
        bool display = value.get_boolean ();
        
        set_display_ratings(display);
        
        Config.Facade.get_instance().set_display_photo_ratings(display);
        action.set_state (value);
    }

    protected virtual void on_display_tags(GLib.SimpleAction action, Variant? value) {
        bool display = value.get_boolean ();
        
        set_display_tags(display);
        
        Config.Facade.get_instance().set_display_photo_tags(display);
        action.set_state (value);
    }

    protected abstract void get_config_photos_sort(out bool sort_order, out int sort_by);

    protected abstract void set_config_photos_sort(bool sort_order, int sort_by);

    public virtual void on_sort_changed(GLib.SimpleAction action, Variant? value) {
        action.set_state (value);

        int sort_by = get_menu_sort_by();
        bool sort_order = get_menu_sort_order();
        
        set_view_comparator(sort_by, sort_order);
        set_config_photos_sort(sort_order, sort_by);
    }
    
    private void on_raw_developer_changed(GLib.SimpleAction action,
                                          Variant? value) {
        RawDeveloper developer = RawDeveloper.SHOTWELL;

        switch (value.get_string ()) {
            case "Shotwell":
                developer = RawDeveloper.SHOTWELL;
                break;
            case "Camera":
                developer = RawDeveloper.CAMERA;
                break;
            default:
                break;
        }

        developer_changed(developer);

        action.set_state (value);
    }

    protected virtual void developer_changed(RawDeveloper rd) {
        if (get_view().get_selected_count() == 0)
            return;
        
        // Check if any photo has edits

        // Display warning only when edits could be destroyed
        bool need_warn = false;

        // Make a list of all photos that need their developer changed.
        Gee.ArrayList<DataView> to_set = new Gee.ArrayList<DataView>();
        foreach (DataView view in get_view().get_selected()) {
            Photo? p = view.get_source() as Photo;
            if (p != null && (!rd.is_equivalent(p.get_raw_developer()))) {
                to_set.add(view);
                
                if (p.has_transformations()) {
                    need_warn = true;
                }
            }
        }
        
        if (!need_warn || Dialogs.confirm_warn_developer_changed(to_set.size)) {
            SetRawDeveloperCommand command = new SetRawDeveloperCommand(to_set, rd);
            get_command_manager().execute(command);

            update_development_menu_item_sensitivity();
        }
    }

    protected override void set_display_titles(bool display) {
        base.set_display_titles(display);

        this.set_action_active ("ViewTitle", display);
    }

    protected override void set_display_comments(bool display) {
        base.set_display_comments(display);
    
        this.set_action_active ("ViewComment", display);
    }

    private GLib.Action sort_by_title_action() {
        var action = get_action ("SortBy");
        assert(action != null);
        return action;
    }

    private GLib.Action sort_ascending_action() {
        var action = get_action ("Sort");
        assert(action != null);
        return action;
    }

    protected int get_menu_sort_by() {
        // any member of the group knows the current value
        return int.parse (sort_by_title_action().get_state().get_string ());
    }
    
    protected void set_menu_sort_by(int val) {
        var sort = "%d".printf (val);
        sort_by_title_action().change_state (sort);
    }
    
    protected bool get_menu_sort_order() {
        // any member of the group knows the current value
        return sort_ascending_action().get_state ().get_string () == "ascending";
    }
    
    protected void set_menu_sort_order(bool ascending) {
        sort_ascending_action().change_state (ascending ? "ascending" : "descending");
    }
    
    void set_view_comparator(int sort_by, bool ascending) {
        Comparator comparator;
        ComparatorPredicate predicate;
        
        switch (sort_by) {
            case SortBy.TITLE:
                if (ascending)
                    comparator = Thumbnail.title_ascending_comparator;
                else comparator = Thumbnail.title_descending_comparator;
                predicate = Thumbnail.title_comparator_predicate;
                break;
            
            case SortBy.EXPOSURE_DATE:
                if (ascending)
                    comparator = Thumbnail.exposure_time_ascending_comparator;
                else comparator = Thumbnail.exposure_time_desending_comparator;
                predicate = Thumbnail.exposure_time_comparator_predicate;
                break;
            
            case SortBy.RATING:
                if (ascending)
                    comparator = Thumbnail.rating_ascending_comparator;
                else comparator = Thumbnail.rating_descending_comparator;
                predicate = Thumbnail.rating_comparator_predicate;
                break;
            
            case SortBy.FILENAME:
                if (ascending)
                    comparator = Thumbnail.filename_ascending_comparator;
                else comparator = Thumbnail.filename_descending_comparator;
                predicate = Thumbnail.filename_comparator_predicate;
                break;

            default:
                debug("Unknown sort criteria: %s", get_menu_sort_by().to_string());
                comparator = Thumbnail.title_descending_comparator;
                predicate = Thumbnail.title_comparator_predicate;
                break;
        }
        
        get_view().set_comparator(comparator, predicate);
    }

    protected void sync_sort() {
        // It used to be that the config and UI could both agree on what 
        // sort order and criteria were selected, but the sorting wouldn't
        // match them, due to the current view's comparator not actually 
        // being set to match, and since there was a check to see if the 
        // config and UI matched that would frequently succeed in this case,
        // the sorting was often wrong until the user went in and changed 
        // it.  Because there is no tidy way to query the current view's 
        // comparator, we now set it any time we even think the sorting 
        // might have changed to force them to always stay in sync.
        //
        // Although this means we pay for a re-sort every time, in practice,
        // this isn't terribly expensive - it _might_ take as long as .5 sec.
        // with a media page containing over 15000 items on a modern CPU.
        
        bool sort_ascending;
        int sort_by;
        get_config_photos_sort(out sort_ascending, out sort_by);
        
        set_menu_sort_by(sort_by);
        set_menu_sort_order(sort_ascending);
        
        set_view_comparator(sort_by, sort_ascending);
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
            save_persistent_thumbnail_scale();
            set_thumb_size(new_scale);
        }
    }

    public void decrease_zoom_level() {
        if (connected_slider != null) {
            connected_slider.decrease_step();
        } else {
            int new_scale = compute_zoom_scale_decrease(get_thumb_size());
            save_persistent_thumbnail_scale();
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
            get_checkerboard_layout().set_scale(Config.Facade.get_instance().get_photo_thumbnail_scale());
            
        return get_checkerboard_layout().get_scale();
    }
}

