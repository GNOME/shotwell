/* Copyright 2016 Software Freedom Conservancy Inc.
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

public abstract class CollectionPage : MediaPage {
    private const double DESKTOP_SLIDESHOW_TRANSITION_SEC = 2.0;
    
    protected class CollectionSearchViewFilter : DefaultSearchViewFilter {
        public override uint get_criteria() {
            return SearchFilterCriteria.TEXT | SearchFilterCriteria.FLAG | 
                SearchFilterCriteria.MEDIA | SearchFilterCriteria.RATING | SearchFilterCriteria.SAVEDSEARCH;
        }
    }
    
    private ExporterUI exporter = null;
    private CollectionSearchViewFilter search_filter = new CollectionSearchViewFilter();
    
    protected CollectionPage(string page_name) {
        base (page_name);
        
        get_view().items_altered.connect(on_photos_altered);
        
        init_item_context_menu("CollectionContextMenu");
        init_toolbar("CollectionToolbar");
        
        show_all();

        // watch for updates to the external app settings
        Config.Facade.get_instance().external_app_changed.connect(on_external_app_changed);
    }

    public override Gtk.Toolbar get_toolbar() {
        if (toolbar == null) {
            base.get_toolbar();

            // separator to force slider to right side of toolbar
            Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
            separator.set_expand(true);
            separator.set_draw(false);
            get_toolbar().insert(separator, -1);

            Gtk.SeparatorToolItem drawn_separator = new Gtk.SeparatorToolItem();
            drawn_separator.set_expand(false);
            drawn_separator.set_draw(true);
            
            get_toolbar().insert(drawn_separator, -1);
            
            // zoom slider assembly
            MediaPage.ZoomSliderAssembly zoom_slider_assembly = create_zoom_slider_assembly();
            connect_slider(zoom_slider_assembly);
            get_toolbar().insert(zoom_slider_assembly, -1);

            Gtk.ToolButton? rotate_button = this.builder.get_object ("ToolRotate") as Gtk.ToolButton;
            unowned Gtk.BindingSet binding_set = Gtk.BindingSet.by_class(rotate_button.get_class());
            Gtk.BindingEntry.add_signal(binding_set, Gdk.Key.KP_Space, Gdk.ModifierType.CONTROL_MASK, "clicked", 0);
            Gtk.BindingEntry.add_signal(binding_set, Gdk.Key.space, Gdk.ModifierType.CONTROL_MASK, "clicked", 0);

        }
        
        return toolbar;
    }
    
    private static InjectionGroup create_file_menu_injectables() {
        InjectionGroup group = new InjectionGroup("FileExtrasPlaceholder");
        
        group.add_menu_item(_("_Print"), "Print", "<Primary>p");
        group.add_separator();
        group.add_menu_item(_("_Publish"), "Publish", "<Primary><Shift>p");
        group.add_menu_item(_("Send _To…"), "SendTo");
        group.add_menu_item(_("Set as _Desktop Background"), "SetBackground", "<Primary>b");
        
        return group;
    }
    
    private static InjectionGroup create_edit_menu_injectables() {
        InjectionGroup group = new InjectionGroup("EditExtrasPlaceholder");
        
        group.add_menu_item(_("_Duplicate"), "Duplicate", "<Primary>D");

        return group;
    }

    private static InjectionGroup create_view_menu_fullscreen_injectables() {
        InjectionGroup group = new InjectionGroup("ViewExtrasFullscreenSlideshowPlaceholder");
        
        group.add_menu_item(_("Fullscreen"), "CommonFullscreen", "F11");
        group.add_separator();
        group.add_menu_item(_("S_lideshow"), "Slideshow", "F5");
        
        return group;
    }

    private static InjectionGroup create_photos_menu_edits_injectables() {
        InjectionGroup group = new InjectionGroup("PhotosExtrasEditsPlaceholder");
        
        group.add_menu_item(_("Rotate _Right"),
                            "RotateClockwise",
                            "<Primary>r");
        group.add_menu_item(_("Rotate _Left"),
                            "RotateCounterclockwise",
                            "<Primary><Shift>r");
        group.add_menu_item(_("Flip Hori_zontally"), "FlipHorizontally");
        group.add_menu_item(_("Flip Verti_cally"), "FlipVertically");
        group.add_separator();
        group.add_menu_item(_("_Enhance"), "Enhance");
        group.add_menu_item(_("Re_vert to Original"), "Revert");
        group.add_separator();
        group.add_menu_item(_("_Copy Color Adjustments"),
                            "CopyColorAdjustments",
                            "<Primary><Shift>c");
        group.add_menu_item(_("_Paste Color Adjustments"),
                            "PasteColorAdjustments",
                            "<Primary><Shift>v");
        
        return group;
    }
  
    private static InjectionGroup create_photos_menu_date_injectables() {
        InjectionGroup group = new InjectionGroup("PhotosExtrasDateTimePlaceholder");
        
        group.add_menu_item(_("Adjust Date and Time…"), "AdjustDateTime", "F4");
        
        return group;
    }

    private static InjectionGroup create_photos_menu_externals_injectables() {
        InjectionGroup group = new InjectionGroup("PhotosExtrasExternalsPlaceholder");
        
        group.add_menu_item(_("Open With E_xternal Editor"),
                            "ExternalEdit",
                            "<Primary>Return");
        group.add_menu_item(_("Open With RA_W Editor"),
                            "ExternalEditRAW",
                            "<Primary><Shift>Return");
        group.add_menu_item(_("_Play"), "PlayVideo", "<Primary>Y");
        
        return group;
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("collection.ui");
    }

    private const GLib.ActionEntry[] entries = {
        { "Print", on_print },
        { "Publish", on_publish },
        { "RotateClockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", on_rotate_counterclockwise },
        { "FlipHorizontally", on_flip_horizontally },
        { "FlipVertically", on_flip_vertically },
        { "Enhance", on_enhance },
        { "CopyColorAdjustments", on_copy_adjustments },
        { "PasteColorAdjustments", on_paste_adjustments },
        { "Revert", on_revert },
        { "SetBackground", on_set_background },
        { "Duplicate", on_duplicate_photo },
        { "AdjustDateTime", on_adjust_date_time },
        { "ExternalEdit", on_external_edit },
        { "ExternalEditRAW", on_external_edit_raw },
        { "Slideshow", on_slideshow }
    };

    protected override void add_actions (GLib.ActionMap map) {
        base.add_actions (map);

        map.add_action_entries (entries, this);
    }

    protected override void remove_actions(GLib.ActionMap map) {
        base.remove_actions(map);
        foreach (var entry in entries) {
            map.remove_action(entry.name);
        }
    }

    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();
        
        groups += create_file_menu_injectables();
        groups += create_edit_menu_injectables();
        groups += create_view_menu_fullscreen_injectables();
        groups += create_photos_menu_edits_injectables();
        groups += create_photos_menu_date_injectables();
        groups += create_photos_menu_externals_injectables();
        
        return groups;
    }
    
    private bool selection_has_video() {
        return MediaSourceCollection.has_video((Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }
    
    private bool page_has_photo() {
        return MediaSourceCollection.has_photo((Gee.Collection<MediaSource>) get_view().get_sources());
    }
    
    private bool selection_has_photo() {
        return MediaSourceCollection.has_photo((Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }
    
    protected override void init_actions(int selected_count, int count) {
        base.init_actions(selected_count, count);
        
        set_action_sensitive("RotateClockwise", true);
        set_action_sensitive("RotateCounterclockwise", true);
        set_action_sensitive("Enhance", true);
        set_action_sensitive("Publish", true);
    }
    
    protected override void update_actions(int selected_count, int count) {
        //FIXME: Hack. Otherwise it will disable actions that just have been enabled by photo page
        if (AppWindow.get_instance().get_current_page() != this) {
            return;
        }

        base.update_actions(selected_count, count);

        bool one_selected = selected_count == 1;
        bool has_selected = selected_count > 0;

        bool primary_is_video = false;
        if (has_selected)
            if (get_view().get_selected_at(0).get_source() is Video)
                primary_is_video = true;

        bool selection_has_videos = selection_has_video();
        bool page_has_photos = page_has_photo();
        
        // don't allow duplication of the selection if it contains a video -- videos are huge and
        // and they're not editable anyway, so there seems to be no use case for duplicating them
        set_action_sensitive("Duplicate", has_selected && (!selection_has_videos));
        set_action_sensitive("ExternalEdit", 
            (!primary_is_video) && one_selected && !is_string_empty(Config.Facade.get_instance().get_external_photo_app()));
        set_action_sensitive("ExternalEditRAW",
            one_selected && (!primary_is_video)
            && ((Photo) get_view().get_selected_at(0).get_source()).get_master_file_format() == 
                PhotoFileFormat.RAW
            && !is_string_empty(Config.Facade.get_instance().get_external_raw_app()));
        set_action_sensitive("Revert", (!selection_has_videos) && can_revert_selected());
        set_action_sensitive("Enhance", (!selection_has_videos) && has_selected);
        set_action_sensitive("CopyColorAdjustments", (!selection_has_videos) && one_selected &&
            ((Photo) get_view().get_selected_at(0).get_source()).has_color_adjustments());
        set_action_sensitive("PasteColorAdjustments", (!selection_has_videos) && has_selected &&
            PixelTransformationBundle.has_copied_color_adjustments());
        set_action_sensitive("RotateClockwise", (!selection_has_videos) && has_selected);
        set_action_sensitive("RotateCounterclockwise", (!selection_has_videos) && has_selected);
        set_action_sensitive("FlipHorizontally", (!selection_has_videos) && has_selected);
        set_action_sensitive("FlipVertically", (!selection_has_videos) && has_selected);
        
        // Allow changing of exposure time, even if there's a video in the current
        // selection.
        set_action_sensitive("AdjustDateTime", has_selected);
        
        set_action_sensitive("NewEvent", has_selected);
        set_action_sensitive("AddTags", has_selected);
        set_action_sensitive("ModifyTags", one_selected);
        set_action_sensitive("Slideshow", page_has_photos && (!primary_is_video));
        set_action_sensitive("Print", (!selection_has_videos) && has_selected);
        set_action_sensitive("Publish", has_selected);
        
        set_action_sensitive("SetBackground", (!selection_has_videos) && has_selected );
        if (has_selected) {
            debug ("Setting action label for SetBackground...");
            var label = one_selected
                    ? Resources.SET_BACKGROUND_MENU
                    : Resources.SET_BACKGROUND_SLIDESHOW_MENU;
            this.update_menu_item_label ("SetBackground", label);
        }
    }

    private void on_photos_altered(Gee.Map<DataObject, Alteration> altered) {
        // only check for revert if the media object is a photo and its image has changed in some 
        // way and it's in the selection
        foreach (DataObject object in altered.keys) {
            DataView view = (DataView) object;
            
            if (!view.is_selected() || !altered.get(view).has_subject("image"))
            continue;
            
            LibraryPhoto? photo = view.get_source() as LibraryPhoto;
            if (photo == null)
                continue;
            
            // since the photo can be altered externally to Shotwell now, need to make the revert
            // command available appropriately, even if the selection doesn't change
            set_action_sensitive("Revert", can_revert_selected());
            set_action_sensitive("CopyColorAdjustments", photo.has_color_adjustments());
            
            break;
        }
    }
    
    private void on_print() {
        if (get_view().get_selected_count() > 0) {
            PrintManager.get_instance().spool_photo(
                (Gee.Collection<Photo>) get_view().get_selected_sources_of_type(typeof(Photo)));
        }
    }
    
    private void on_external_app_changed() {
        int selected_count = get_view().get_selected_count();
        
        set_action_sensitive("ExternalEdit", selected_count == 1 && Config.Facade.get_instance().get_external_photo_app() != "");
    }
    
    // see #2020
    // double click = switch to photo page
    // Super + double click = open in external editor
    // Enter = switch to PhotoPage
    // Ctrl + Enter = open in external editor (handled with accelerators)
    // Shift + Ctrl + Enter = open in external RAW editor (handled with accelerators)
    protected override void on_item_activated(CheckerboardItem item, CheckerboardPage.Activator 
        activator, CheckerboardPage.KeyboardModifiers modifiers) {
        Thumbnail thumbnail = (Thumbnail) item;

        // none of the fancy Super, Ctrl, Shift, etc., keyboard accelerators apply to videos,
        // since they can't be RAW files or be opened in an external editor, etc., so if this is
        // a video, just play it and do a short-circuit return
        if (thumbnail.get_media_source() is Video) {
            on_play_video();
            return;
        }
        
        LibraryPhoto? photo = thumbnail.get_media_source() as LibraryPhoto;
        if (photo == null)
            return;
        
        // switch to full-page view or open in external editor
        debug("activating %s", photo.to_string());

        if (activator == CheckerboardPage.Activator.MOUSE) {
            if (modifiers.super_pressed)
                on_external_edit();
            else
                LibraryWindow.get_app().switch_to_photo_page(this, photo);
        } else if (activator == CheckerboardPage.Activator.KEYBOARD) {
            if (!modifiers.shift_pressed && !modifiers.ctrl_pressed)
                LibraryWindow.get_app().switch_to_photo_page(this, photo);
        }
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
            
            case "bracketright":
                activate_action("RotateClockwise");
            break;
            
            case "bracketleft":
                activate_action("RotateCounterclockwise");
            break;
            
            default:
                handled = false;
            break;
        }
        
        return handled ? true : base.on_app_key_pressed(event);
    }

    protected override void on_export() {
        if (exporter != null)
            return;
        
        Gee.Collection<MediaSource> export_list =
            (Gee.Collection<MediaSource>) get_view().get_selected_sources();
        if (export_list.size == 0)
            return;

        bool has_some_photos = selection_has_photo();
        bool has_some_videos = selection_has_video();
        assert(has_some_photos || has_some_videos);
               
        // if we don't have any photos, then everything is a video, so skip displaying the Export
        // dialog and go right to the video export operation
        if (!has_some_photos) {
            exporter = Video.export_many((Gee.Collection<Video>) export_list, on_export_completed);
            return;
        }

        string title = null;
        if (has_some_videos)
            title = ngettext("Export Photo/Video", "Export Photos/Videos", export_list.size);
        else
            title = ngettext("Export Photo", "Export Photos", export_list.size);
        ExportDialog export_dialog = new ExportDialog(title);

        // Setting up the parameters object requires a bit of thinking about what the user wants.
        // If the selection contains only photos, then we do what we've done in previous versions
        // of Shotwell -- we use whatever settings the user selected on his last export operation
        // (the thinking here being that if you've been exporting small PNGs for your blog
        // for the last n export operations, then it's likely that for your (n + 1)-th export
        // operation you'll also be exporting a small PNG for your blog). However, if the selection
        // contains any videos, then we set the parameters to the "Current" operating mode, since
        // videos can't be saved as PNGs (or any other specific photo format).
        ExportFormatParameters export_params = (has_some_videos) ? ExportFormatParameters.current() :
            ExportFormatParameters.last();

        int scale;
        ScaleConstraint constraint;
        if (!export_dialog.execute(out scale, out constraint, ref export_params))
            return;
        
        Scaling scaling = Scaling.for_constraint(constraint, scale, false);
        
        // handle the single-photo case, which is treated like a Save As file operation
        if (export_list.size == 1) {
            LibraryPhoto photo = null;
            foreach (LibraryPhoto p in (Gee.Collection<LibraryPhoto>) export_list) {
                photo = p;
                break;
            }
            
            File save_as =
                ExportUI.choose_file(photo.get_export_basename_for_parameters(export_params));
            if (save_as == null)
                return;
            
            try {
                AppWindow.get_instance().set_busy_cursor();
                photo.export(save_as, scaling, export_params.quality,
                    photo.get_export_format_for_parameters(export_params), export_params.mode ==
                    ExportFormatMode.UNMODIFIED, export_params.export_metadata);
                AppWindow.get_instance().set_normal_cursor();
            } catch (Error err) {
                AppWindow.get_instance().set_normal_cursor();
                export_error_dialog(save_as, false);
            }
            
            return;
        }

        // multiple photos or videos
        File export_dir = ExportUI.choose_dir(title);
        if (export_dir == null)
            return;
        
        exporter = new ExporterUI(new Exporter(export_list, export_dir, scaling, export_params));
        exporter.export(on_export_completed);
    }
    
    private void on_export_completed() {
        exporter = null;
    }
    
    private bool can_revert_selected() {
        foreach (DataSource source in get_view().get_selected_sources()) {
            LibraryPhoto? photo = source as LibraryPhoto;
            if (photo != null && (photo.has_transformations() || photo.has_editable()))
                return true;
        }
        
        return false;
    }
    
    private bool can_revert_editable_selected() {
        foreach (DataSource source in get_view().get_selected_sources()) {
            LibraryPhoto? photo = source as LibraryPhoto;
            if (photo != null && photo.has_editable())
                return true;
        }
        
        return false;
    }
   
    private void on_rotate_clockwise() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(), 
            Rotation.CLOCKWISE, Resources.ROTATE_CW_FULL_LABEL, Resources.ROTATE_CW_TOOLTIP,
            _("Rotating"), _("Undoing Rotate"));
        get_command_manager().execute(command);
    }

    private void on_publish() {
        if (get_view().get_selected_count() > 0)
            PublishingUI.PublishingDialog.go(
                (Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }

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
            Rotation.MIRROR, Resources.HFLIP_LABEL, "", _("Flipping Horizontally"),
            _("Undoing Flip Horizontally"));
        get_command_manager().execute(command);
    }
    
    private void on_flip_vertically() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(),
            Rotation.UPSIDE_DOWN, Resources.VFLIP_LABEL, "", _("Flipping Vertically"),
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
    
    public void on_copy_adjustments() {
        if (get_view().get_selected_count() != 1)
            return;
        Photo photo = (Photo) get_view().get_selected_at(0).get_source();
        PixelTransformationBundle.set_copied_color_adjustments(photo.get_color_adjustments());
        set_action_sensitive("PasteColorAdjustments", true);
    }
    
    public void on_paste_adjustments() {
        PixelTransformationBundle? copied_adjustments = PixelTransformationBundle.get_copied_color_adjustments();
        if (get_view().get_selected_count() == 0 || copied_adjustments == null)
            return;
        
        AdjustColorsMultipleCommand command = new AdjustColorsMultipleCommand(get_view().get_selected(),
            copied_adjustments, Resources.PASTE_ADJUSTMENTS_LABEL, Resources.PASTE_ADJUSTMENTS_TOOLTIP);
        get_command_manager().execute(command);
    }
    
    private void on_enhance() {
        if (get_view().get_selected_count() == 0)
            return;
        
        EnhanceMultipleCommand command = new EnhanceMultipleCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
    
    private void on_duplicate_photo() {
        if (get_view().get_selected_count() == 0)
            return;
        
        DuplicateMultiplePhotosCommand command = new DuplicateMultiplePhotosCommand(
            get_view().get_selected());
        get_command_manager().execute(command);
    }

    private void on_adjust_date_time() {
        if (get_view().get_selected_count() == 0)
            return;

        bool selected_has_videos = false;
        bool only_videos_selected = true;
        
        foreach (DataView dv in get_view().get_selected()) {
            if (dv.get_source() is Video)
                selected_has_videos = true;
            else
                only_videos_selected = false;
        }

        Dateable photo_source = (Dateable) get_view().get_selected_at(0).get_source();

        AdjustDateTimeDialog dialog = new AdjustDateTimeDialog(photo_source,
            get_view().get_selected_count(), true, selected_has_videos, only_videos_selected);

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
            open_external_editor_error_dialog(err, photo);
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
            photo.open_with_raw_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            AppWindow.error_message(Resources.launch_editor_failed(err));
        }
    }
    
    public void on_set_background() {
        Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        MediaSourceCollection.filter_media((Gee.Collection<MediaSource>) get_view().get_selected_sources(),
            photos, null);
        
        bool desktop, screensaver;
        if (photos.size == 1) {
            SetBackgroundPhotoDialog dialog = new SetBackgroundPhotoDialog();
            if (dialog.execute(out desktop, out screensaver)) {
                AppWindow.get_instance().set_busy_cursor();
                DesktopIntegration.set_background(photos[0], desktop, screensaver);
                AppWindow.get_instance().set_normal_cursor();
            }
        } else if (photos.size > 1) {
            SetBackgroundSlideshowDialog dialog = new SetBackgroundSlideshowDialog();
            int delay;
            if (dialog.execute(out delay, out desktop, out screensaver)) {
                AppWindow.get_instance().set_busy_cursor();
                DesktopIntegration.set_background_slideshow(photos, delay,
                    DESKTOP_SLIDESHOW_TRANSITION_SEC, desktop, screensaver);
                AppWindow.get_instance().set_normal_cursor();
            }
        }
    }
    
    private void on_slideshow() {
        if (get_view().get_count() == 0)
            return;
        
        // use first selected photo, else use first photo
        Gee.List<DataSource>? sources = (get_view().get_selected_count() > 0)
            ? get_view().get_selected_sources_of_type(typeof(LibraryPhoto))
            : get_view().get_sources_of_type(typeof(LibraryPhoto));
        if (sources == null || sources.size == 0)
            return;
        
        Thumbnail? thumbnail = (Thumbnail?) get_view().get_view_for_source(sources[0]);
        if (thumbnail == null)
            return;
        
        LibraryPhoto? photo = thumbnail.get_media_source() as LibraryPhoto;
        if (photo == null)
            return;
        
        AppWindow.get_instance().go_fullscreen(new SlideshowPage(LibraryPhoto.global, get_view(),
            photo));
    }
    
    protected override bool on_ctrl_pressed(Gdk.EventKey? event) {
        Gtk.ToolButton? rotate_button = this.builder.get_object ("ToolRotate") as Gtk.ToolButton;
        if (rotate_button != null) {
            rotate_button.set_action_name ("win.RotateCounterclockwise");
            rotate_button.set_icon_name (Resources.COUNTERCLOCKWISE);
            rotate_button.set_tooltip_text (Resources.ROTATE_CCW_TOOLTIP);
        }

        return base.on_ctrl_pressed(event);
    }
    
    protected override bool on_ctrl_released(Gdk.EventKey? event) {
        Gtk.ToolButton? rotate_button = this.builder.get_object ("ToolRotate") as Gtk.ToolButton;
        if (rotate_button != null) {
            rotate_button.set_action_name ("win.RotateClockwise");
            rotate_button.set_icon_name (Resources.CLOCKWISE);
            rotate_button.set_tooltip_text (Resources.ROTATE_CW_TOOLTIP);
        }

        return base.on_ctrl_released(event);
    }
    
    public override SearchViewFilter get_search_view_filter() {
        return search_filter;
    }
}

