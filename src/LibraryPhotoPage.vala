// SPDX-LicenseIdentifier: LGPL-2.1-or-later
// SPDX-FileCopyrightText: Copyright 2016 Software Freedom Conservancy Inc.
// SPDX-FileCopyrightText: 2024 Jens Georg <mail@jensge.org>
//
// LibraryPhotoPage
//

public class LibraryPhotoPage : EditingHostPage {

    private class LibraryPhotoPageViewFilter : ViewFilter {
        public override bool predicate (DataView view) {
            return !((MediaSource) view.get_source()).is_trashed();
        }
    }

    private CollectionPage? return_page = null;
    private bool return_to_collection_on_release = false;
    private LibraryPhotoPageViewFilter filter = new LibraryPhotoPageViewFilter();
    
    public LibraryPhotoPage() {
        base(LibraryPhoto.global, "Photo");
        
        // monitor view to update UI elements
        get_view().items_altered.connect(on_photos_altered);
        
        // watch for photos being destroyed or altered, either here or in other pages
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
        LibraryPhoto.global.items_altered.connect(on_metadata_altered);
        
        // watch for updates to the external app settings
        Config.Facade.get_instance().external_app_changed.connect(on_external_app_changed);
        
        // Filter out trashed files.
        get_view().install_view_filter(filter);
        LibraryPhoto.global.items_unlinking.connect(on_photo_unlinking);
        LibraryPhoto.global.items_relinked.connect(on_photo_relinked);
    }
    
    ~LibraryPhotoPage() {
        LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
        LibraryPhoto.global.items_altered.disconnect(on_metadata_altered);
        Config.Facade.get_instance().external_app_changed.disconnect(on_external_app_changed);
    }
    
    public bool not_trashed_view_filter(DataView view) {
        return !((MediaSource) view.get_source()).is_trashed();
    }
    
    private void on_photo_unlinking(Gee.Collection<DataSource> unlinking) {
        filter.refresh();
    }
    
    private void on_photo_relinked(Gee.Collection<DataSource> relinked) {
        filter.refresh();
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("photo_context.ui");
        ui_filenames.add("photo.ui");
    }

    private const GLib.ActionEntry[] entries = {
        { "Export", on_export },
        { "Print", on_print },
        { "Publish", on_publish },
        { "RemoveFromLibrary", on_remove_from_library },
        { "MoveToTrash", on_move_to_trash },
        { "RotateClockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", on_rotate_counterclockwise },
        { "FlipHorizontally", on_flip_horizontally },
        { "FlipVertically", on_flip_vertically },
        { "CopyColorAdjustments", on_copy_adjustments },
        { "PasteColorAdjustments", on_paste_adjustments },
        { "Revert", on_revert },
        { "EditTitle", on_edit_title },
        { "EditComment", on_edit_comment },
        { "AdjustDateTime", on_adjust_date_time },
        { "ExternalEdit", on_external_edit },
        { "ExternalEditRAW", on_external_edit_raw },
        { "SendTo", on_send_to },
        { "SetBackground", on_set_background },
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
        { "IncreaseSize", on_increase_size },
        { "DecreaseSize", on_decrease_size },
        { "ZoomFit", snap_zoom_to_min },
        { "Zoom100", snap_zoom_to_isomorphic },
        { "Zoom200", snap_zoom_to_max },
        { "AddTags", on_add_tags },
        { "ModifyTags", on_modify_tags },
        { "Slideshow", on_slideshow },

        // Toggle actions
        { "ViewRatings", on_action_toggle, null, "false", on_display_ratings },

        // Radio actions
    };

    protected override void add_actions (GLib.ActionMap map) {
        base.add_actions (map);

        map.add_action_entries (entries, this);
        ((GLib.SimpleAction) get_action ("ViewRatings")).change_state (Config.Facade.get_instance ().get_display_photo_ratings ());
        var d = Config.Facade.get_instance().get_default_raw_developer();
        var action = new GLib.SimpleAction.stateful("RawDeveloper",
                GLib.VariantType.STRING, d == RawDeveloper.SHOTWELL ? "Shotwell" : "Camera");
        action.change_state.connect(on_raw_developer_changed);
        action.set_enabled(true);
        map.add_action(action);
    }

    protected override void remove_actions(GLib.ActionMap map) {
        base.remove_actions(map);
        map.remove_action_entries(entries);
    }

    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();

        InjectionGroup print_group = new InjectionGroup("PrintPlaceholder");
        print_group.add_menu_item(_("_Print"), "Print", "<Primary>p");
        
        groups += print_group;
        
        InjectionGroup publish_group = new InjectionGroup("PublishPlaceholder");
        publish_group.add_menu_item(_("_Publish"), "Publish", "<Primary><Shift>p");
        
        groups += publish_group;
        
        InjectionGroup bg_group = new InjectionGroup("SetBackgroundPlaceholder");
        bg_group.add_menu_item(_("Set as _Desktop Background"), "SetBackground", "<Primary>b");
        
        groups += bg_group;
        
        return groups;
    }
    
    private void on_display_ratings(GLib.SimpleAction action, Variant? value) {
        bool display = value.get_boolean ();
        
        set_display_ratings(display);
        
        Config.Facade.get_instance().set_display_photo_ratings(display);
        action.set_state (value);
    }


    private void set_display_ratings(bool display) {
        var action = get_action("ViewRatings") as GLib.SimpleAction;
        if (action != null)
            action.set_enabled(display);
    }
    
    protected override void update_actions(int selected_count, int count) {
        bool multiple = get_view().get_count() > 1;
        bool rotate_possible = has_photo() ? is_rotate_available(get_photo()) : false;
        bool is_raw = has_photo() && get_photo().get_master_file_format() == PhotoFileFormat.RAW;
        
        set_action_sensitive("ExternalEdit",
            has_photo() && Config.Facade.get_instance().get_external_photo_app() != "");
        
        set_action_sensitive("Revert", has_photo() ?
            (get_photo().has_transformations() || get_photo().has_editable()) : false);
        
        if (has_photo() && !get_photo_missing()) {
            update_rating_menu_item_sensitivity();
            update_development_menu_item_sensitivity();
        }
        
        set_action_sensitive("SetBackground", has_photo());
        
        set_action_sensitive("CopyColorAdjustments", (has_photo() && get_photo().has_color_adjustments()));
        set_action_sensitive("PasteColorAdjustments", PixelTransformationBundle.has_copied_color_adjustments());
        
        set_action_sensitive("PrevPhoto", multiple);
        set_action_sensitive("NextPhoto", multiple);
        set_action_sensitive("RotateClockwise", rotate_possible);
        set_action_sensitive("RotateCounterclockwise", rotate_possible);
        set_action_sensitive("FlipHorizontally", rotate_possible);
        set_action_sensitive("FlipVertically", rotate_possible);

        if (has_photo()) {
            set_action_sensitive("Crop", EditingTools.CropTool.is_available(get_photo(), Scaling.for_original()));
            set_action_sensitive("RedEye", EditingTools.RedeyeTool.is_available(get_photo(), 
                Scaling.for_original()));
        }
                 
        update_flag_action();
        
        set_action_sensitive("ExternalEditRAW",
            is_raw && Config.Facade.get_instance().get_external_raw_app() != "");
        
        base.update_actions(selected_count, count);
    }
    
    private void on_photos_altered() {
        set_action_sensitive("Revert", has_photo() ?
            (get_photo().has_transformations() || get_photo().has_editable()) : false);
        update_flag_action();
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
    
    void switch_developer(RawDeveloper rd) {
        var command = new SetRawDeveloperCommand(get_view().get_selected(), rd);
        get_command_manager().execute(command);

        update_development_menu_item_sensitivity();
    }

    protected virtual void developer_changed(RawDeveloper rd) {
        if (get_view().get_selected_count() != 1)
            return;
        
        Photo? photo = get_view().get_selected().get(0).get_source() as Photo;
        if (photo == null || rd.is_equivalent(photo.get_raw_developer()))
            return;
        
        // Check if any photo has edits
        // Display warning only when edits could be destroyed
        if (!photo.has_transformations()) {
            switch_developer(rd);
        } else {
            Dialogs.confirm_warn_developer_changed.begin(1, (source, res) => {
                if (Dialogs.confirm_warn_developer_changed.end(res)) {
                    switch_developer(rd);
                }
            });
        }
    }
    
    private void update_flag_action() {
        set_action_sensitive ("Flag", has_photo());
    }
    
    // Displays a photo from a specific CollectionPage.  When the user exits this view,
    // they will be sent back to the return_page. The optional view parameters is for using
    // a ViewCollection other than the one inside return_page; this is necessary if the 
    // view and return_page have different filters.
    public void display_for_collection(CollectionPage return_page, Photo photo, 
        ViewCollection? view = null) {
        this.return_page = return_page;
        //return_page.destroy.connect(on_page_destroyed);
        //TODO
        
        display_copy_of(view != null ? view : return_page.get_view(), photo);
    }
    
    public void on_page_destroyed() {
        // The parent page was removed, so drop the reference to the page and
        // its view collection.
        return_page = null;
        unset_view_collection();
    }
    
    public CollectionPage? get_controller_page() {
        return return_page;
    }

    public override void switched_to() {
        // since LibraryPhotoPages often rest in the background, their stored photo can be deleted by 
        // another page. this checks to make sure a display photo has been established before the
        // switched_to call.
        assert(get_photo() != null);
        
        base.switched_to();
        
        update_zoom_menu_item_sensitivity();
        update_rating_menu_item_sensitivity();
        
        set_display_ratings(Config.Facade.get_instance().get_display_photo_ratings());
    }


    public override void switching_from() {
        base.switching_from();
        foreach (var entry in entries) {
            AppWindow.get_instance().remove_action(entry.name);
        }
    }
    
    protected override Gdk.Pixbuf? get_bottom_left_trinket(int scale) {
        if (!has_photo() || !Config.Facade.get_instance().get_display_photo_ratings())
            return null;
        
        return Resources.get_rating_trinket(((LibraryPhoto) get_photo()).get_rating(), scale);
    }
    
    protected override Gdk.Pixbuf? get_top_right_trinket(int scale) {
        if (!has_photo() || !((LibraryPhoto) get_photo()).is_flagged())
            return null;
        
        return Resources.get_flagged_trinket(scale);
    }
    
    private void on_slideshow() {
        LibraryPhoto? photo = (LibraryPhoto?) get_photo();
        if (photo == null)
            return;
        
        AppWindow.get_instance().go_fullscreen(new SlideshowPage(LibraryPhoto.global, get_view(),
            photo));
    }
    
    private void update_zoom_menu_item_sensitivity() {
        set_action_sensitive("IncreaseSize", !get_zoom_state().is_max() && !get_photo_missing());
        set_action_sensitive("DecreaseSize", !get_zoom_state().is_default() && !get_photo_missing());
    }

    protected override void on_increase_size() {
        base.on_increase_size();
        
        update_zoom_menu_item_sensitivity();
    }
    
    protected override void on_decrease_size() {
        base.on_decrease_size();

        update_zoom_menu_item_sensitivity();
    }

    protected override void update_ui(bool missing) {
        bool sensitivity = !missing;
        
        set_action_sensitive("SendTo", sensitivity);
        set_action_sensitive("Publish", sensitivity);
        set_action_sensitive("Print", sensitivity);
        set_action_sensitive("CommonJumpToFile", sensitivity);
        
        set_action_sensitive("CommonUndo", sensitivity);
        set_action_sensitive("CommonRedo", sensitivity);
        
        set_action_sensitive("IncreaseSize", sensitivity);
        set_action_sensitive("DecreaseSize", sensitivity);
        set_action_sensitive("ZoomFit", sensitivity);
        set_action_sensitive("Zoom100", sensitivity);
        set_action_sensitive("Zoom200", sensitivity);
        set_action_sensitive("Slideshow", sensitivity);
        
        set_action_sensitive("RotateClockwise", sensitivity);
        set_action_sensitive("RotateCounterclockwise", sensitivity);
        set_action_sensitive("FlipHorizontally", sensitivity);
        set_action_sensitive("FlipVertically", sensitivity);
        set_action_sensitive("Enhance", sensitivity);
        set_action_sensitive("Crop", sensitivity);
        set_action_sensitive("RedEye", sensitivity);
        set_action_sensitive("Adjust", sensitivity);
        set_action_sensitive("EditTitle", sensitivity);
        set_action_sensitive("AdjustDateTime", sensitivity);
        set_action_sensitive("ExternalEdit", sensitivity);
        set_action_sensitive("ExternalEditRAW", sensitivity);
        set_action_sensitive("Revert", sensitivity);
        
        set_action_sensitive("Rate", sensitivity);
        set_action_sensitive("Flag", sensitivity);
        set_action_sensitive("AddTags", sensitivity);
        set_action_sensitive("ModifyTags", sensitivity);
        
        set_action_sensitive("SetBackground", sensitivity);
        
        base.update_ui(missing);
    }
    
    protected override void notify_photo_backing_missing(Photo photo, bool missing) {
        if (missing)
            ((LibraryPhoto) photo).mark_offline();
        else
            ((LibraryPhoto) photo).mark_online();
        
        base.notify_photo_backing_missing(photo, missing);
    }
    
    public override bool key_press_event(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if (base.key_press_event(event, keyval, keycode, modifiers))
            return true;

        bool handled = true;
        string? format = null;
        switch (Gdk.keyval_name(keyval)) {
            case "Escape":
            case "Return":
            case "KP_Enter":
                if (!(get_container() is FullscreenWindow))
                    return_to_collection();
            break;
            
            case "Delete":
                // although bound as an accelerator in the menu, accelerators are currently
                // unavailable in fullscreen mode (a variant of #324), so we do this manually
                // here
                activate_action("win.MoveToTrash", format);
            break;

            case "period":
            case "greater":
                activate_action("win.IncreaseRating", format);
            break;
            
            case "comma":
            case "less":
                activate_action("win.DecreaseRating", format);
            break;

            case "KP_1":
                activate_action("win.RateOne", format);
            break;
            
            case "KP_2":
                activate_action("win.RateTwo", format);
            break;

            case "KP_3":
                activate_action("win.RateThree", format);
            break;
        
            case "KP_4":
                activate_action("win.RateFour", format);
            break;

            case "KP_5":
                activate_action("win.RateFive", format);
            break;

            case "KP_0":
                activate_action("win.RateUnrated", format);
            break;

            case "KP_9":
                activate_action("win.RateRejected", format);
            break;
            
            case "bracketright":
                activate_action("win.RotateClockwise", format);
            break;
            
            case "bracketleft":
                activate_action("win.RotateCounterclockwise", format);
            break;
            
            case "slash":
                activate_action("win.Flag", format);
            break;
            
            default:
                handled = false;
            break;
        }
        
        return handled;
    }

    protected override bool on_double_click(Gtk.EventController event, double x, double y) {
        FullscreenWindow? fs = get_container() as FullscreenWindow;
        if (fs == null)
            return_to_collection_on_release = true;
        else
            fs.close();
        
        return true;
    }
    
    protected override bool on_left_released(Gtk.EventController event, int press, double x, double y) {
        if (return_to_collection_on_release) {
            return_to_collection_on_release = false;
            return_to_collection();
            
            return true;
        }
        
        return base.on_left_released(event, press, x, y);
    }

    private Gtk.PopoverMenu context_menu;

    private Gtk.PopoverMenu get_context_menu() {
        if (context_menu == null) {
            context_menu = get_popover_menu_from_builder (this.builder, "PhotoContextMenu", this);
        }

        return this.context_menu;
    }
    
    protected override bool on_context_buttonpress(Gtk.EventController event, double x, double y) {
        popup_context_menu(get_context_menu(), x, y);

        return true;
    }

    protected override bool on_context_keypress() {
        //popup_context_menu(get_context_menu());
        
        return true;
    }

    private void return_to_collection() {
        // Return to the previous page if it exists.
        if (null != return_page)
            LibraryWindow.get_app().switch_to_page(return_page);
        else
            LibraryWindow.get_app().switch_to_library_page();
    }
    
    private void on_remove_from_library() {
        LibraryPhoto photo = (LibraryPhoto) get_photo();
        
        Gee.Collection<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        photos.add(photo);
        
        remove_from_app.begin(photos, GLib.dpgettext2(null, "Dialog Title", "Remove From Library"),
            GLib.dpgettext2(null, "Dialog Title", "Removing Photo From Library"));
    }
    
    private void on_move_to_trash() {        
        if (!has_photo())
            return;
        
        // Temporarily prevent the application from switching pages if we're viewing
        // the current photo from within an Event page.  This is needed because the act of 
        // trashing images from an Event causes it to be renamed, which causes it to change 
        // positions in the sidebar, and the selection moves with it, causing the app to
        // inappropriately switch to the Event page. 
        if (return_page is EventPage) {
            LibraryWindow.get_app().set_page_switching_enabled(false);
        }
        
        LibraryPhoto photo = (LibraryPhoto) get_photo();
        
        Gee.Collection<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        photos.add(photo);
        
        // move on to next photo before executing
        on_next_photo();
        
        // this indicates there is only one photo in the controller, or about to be zero, so switch 
        // to the library page, which is guaranteed to be there when this disappears
        if (photo.equals(get_photo())) {
            // If this is the last photo in an Event, then trashing it
            // _should_ cause us to switch pages, so re-enable it here. 
            LibraryWindow.get_app().set_page_switching_enabled(true);
            
            if (get_container() is FullscreenWindow)
                ((FullscreenWindow) get_container()).close();

            LibraryWindow.get_app().switch_to_library_page();
        }

        get_command_manager().execute(new TrashUntrashPhotosCommand(photos, true));
        LibraryWindow.get_app().set_page_switching_enabled(true);
    }
    
    private void on_flag_unflag() {
        if (has_photo()) {
            var photo_list = new Gee.ArrayList<MediaSource>();
            photo_list.add(get_photo());
            get_command_manager().execute(new FlagUnflagCommand(photo_list,
                !((LibraryPhoto) get_photo()).is_flagged()));
        }
    }
    
    private void on_photo_destroyed(DataSource source) {
        on_photo_removed((LibraryPhoto) source);
    }
    
    private void on_photo_removed(LibraryPhoto photo) {
        // only interested in current photo
        if (photo == null || !photo.equals(get_photo()))
            return;
        
        // move on to the next one in the collection
        on_next_photo();
        
        ViewCollection view = get_view();
        view.remove_marked(view.mark(view.get_view_for_source(photo)));
        if (photo.equals(get_photo())) {
            // this indicates there is only one photo in the controller, or now zero, so switch 
            // to the Photos page, which is guaranteed to be there
            LibraryWindow.get_app().switch_to_library_page();
        }
    }

    private void on_print() {
        if (get_view().get_selected_count() > 0) {
            PrintManager.get_instance().spool_photo(
                (Gee.Collection<Photo>) get_view().get_selected_sources_of_type(typeof(Photo)));
        }
    }

    private void on_external_app_changed() {
        set_action_sensitive("ExternalEdit", has_photo() && 
            Config.Facade.get_instance().get_external_photo_app() != "");
    }
    
    private void on_external_edit() {
        if (!has_photo())
            return;
        
        try {
            AppWindow.get_instance().set_busy_cursor();
            get_photo().open_with_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            open_external_editor_error_dialog(err, get_photo());
        }

    }

    private void on_external_edit_raw() {
        if (!has_photo())
            return;
        
        if (get_photo().get_master_file_format() != PhotoFileFormat.RAW)
            return;
        
        try {
            AppWindow.get_instance().set_busy_cursor();
            get_photo().open_with_raw_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            AppWindow.error_message(Resources.launch_editor_failed(err));
        }
    }
    
    private void on_send_to() {
        if (has_photo())
            DesktopIntegration.send_to.begin((Gee.Collection<Photo>) get_view().get_selected_sources());
    }
    
    private void on_export() {
        do_export.begin();
    }
    
    private async void do_export() {
        if (!has_photo())
            return;
        
        ExportDialog export_dialog = new ExportDialog(GLib.dpgettext2(null, "Dialog Title", "Export Photo"));
        
        ExportFormatParameters? export_params = ExportFormatParameters.last();
        export_params = yield export_dialog.execute(export_params);
        if (export_params == null) {
            return;
        }
        
        File save_as =
            yield ExportUI.choose_file(get_photo().get_export_basename_for_parameters(export_params));

        if (save_as == null)
            return;
        
        Scaling scaling = Scaling.for_constraint(export_params.constraint, export_params.scale, false);
        
        try {
            get_photo().export(save_as, scaling, export_params.quality,
                get_photo().get_export_format_for_parameters(export_params),
                export_params.mode == ExportFormatMode.UNMODIFIED, export_params.export_metadata);
        } catch (Error err) {
            AppWindow.error_message(_("Unable to export %s: %s").printf(save_as.get_path(), err.message));
        }
    }
    
    private void on_publish() {
        if (get_view().get_count() > 0)
            PublishingUI.PublishingDialog.go(
                (Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }
    
    private void on_increase_rating() {
        if (!has_photo() || get_photo_missing())
            return;
        
        SetRatingSingleCommand command = new SetRatingSingleCommand.inc_dec(get_photo(), true);
        get_command_manager().execute(command);
    
        update_rating_menu_item_sensitivity();
    }

    private void on_decrease_rating() {
        if (!has_photo() || get_photo_missing())
            return;
        
        SetRatingSingleCommand command = new SetRatingSingleCommand.inc_dec(get_photo(), false);
        get_command_manager().execute(command);

        update_rating_menu_item_sensitivity();
    }

    private void on_set_rating(Rating rating) {
        if (!has_photo() || get_photo_missing())
            return;
        
        SetRatingSingleCommand command = new SetRatingSingleCommand(get_photo(), rating);
        get_command_manager().execute(command);
        
        update_rating_menu_item_sensitivity();
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

    private void update_rating_menu_item_sensitivity() {
        set_action_sensitive("RateRejected", get_photo().get_rating() != Rating.REJECTED);
        set_action_sensitive("RateUnrated", get_photo().get_rating() != Rating.UNRATED);
        set_action_sensitive("RateOne", get_photo().get_rating() != Rating.ONE);
        set_action_sensitive("RateTwo", get_photo().get_rating() != Rating.TWO);
        set_action_sensitive("RateThree", get_photo().get_rating() != Rating.THREE);
        set_action_sensitive("RateFour", get_photo().get_rating() != Rating.FOUR);
        set_action_sensitive("RateFive", get_photo().get_rating() != Rating.FIVE);
        set_action_sensitive("IncreaseRating", get_photo().get_rating().can_increase());
        set_action_sensitive("DecreaseRating", get_photo().get_rating().can_decrease());
    }
    
    private void update_development_menu_item_sensitivity() {
        PhotoFileFormat format = get_photo().get_master_file_format() ;
        set_action_sensitive("RawDeveloper", format == PhotoFileFormat.RAW);
        
        if (format == PhotoFileFormat.RAW) {
            // FIXME: Only enable radio actions that are actually possible..
            // Set active developer in menu.
            switch (get_photo().get_raw_developer()) {
                case RawDeveloper.SHOTWELL:
                    get_action ("RawDeveloper").change_state ("Shotwell");
                    break;
                
                case RawDeveloper.CAMERA:
                case RawDeveloper.EMBEDDED:
                    get_action ("RawDeveloper").change_state ("Camera");
                    break;
                
                default:
                    assert_not_reached();
            }
        }
    }

    private void on_metadata_altered(Gee.Map<DataObject, Alteration> map) {
        if (map.has_key(get_photo()) && map.get(get_photo()).has_subject("metadata"))
            repaint();
    }

    private void on_add_tags() {
        AddTagsDialog dialog = new AddTagsDialog();
        dialog.execute.begin((source, res) => {
            string[]? names = dialog.execute.end(res);
            if (names != null) {
                get_command_manager().execute(new AddTagsCommand(
                    HierarchicalTagIndex.get_global_index().get_paths_for_names_array(names), 
                    (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources()));
            }
            });
    }

    private void on_modify_tags() {
        LibraryPhoto photo = (LibraryPhoto) get_view().get_selected_at(0).get_source();
        
        ModifyTagsDialog dialog = new ModifyTagsDialog(photo);
        dialog.execute.begin((source, res) => {
            var new_tags = dialog.execute.end(res);
            if (new_tags == null)
                return;
        
            get_command_manager().execute(new ModifyTagsCommand(photo, new_tags));
        });
    }
    
    protected override void insert_faces_button() {
        var faces_button = (Gtk.Button) builder.get_object("FacesButton");
        if (faces_button != null) {
            faces_button.show();
        }
    }
}

