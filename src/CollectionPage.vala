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

public abstract class CollectionPage : MediaPage {
    private Gtk.ToolButton rotate_button = null;
    private PhotoDragAndDropHandler dnd_handler = null;
    private ExporterUI exporter = null;
    
    public CollectionPage(string page_name) {
        base (page_name);

        get_view().items_altered.connect(on_photos_altered);

        init_item_context_menu("/CollectionContextMenu");

        // set up page's toolbar (used by AppWindow for layout)
        Gtk.Toolbar toolbar = get_toolbar();
        
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock("");
        rotate_button.set_related_action(get_action("RotateClockwise"));
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        
        toolbar.insert(rotate_button, -1);

        // enhance tool
        Gtk.ToolButton enhance_button = new Gtk.ToolButton.from_stock(Resources.ENHANCE);
        enhance_button.set_related_action(get_action("Enhance"));

        toolbar.insert(enhance_button, -1);

        // separator
        toolbar.insert(new Gtk.SeparatorToolItem(), -1);
        
        // slideshow button
        Gtk.ToolButton slideshow_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PLAY);
        slideshow_button.set_related_action(get_action("Slideshow"));
        
        toolbar.insert(slideshow_button, -1);

#if !NO_PUBLISHING
        // publish button
        Gtk.ToolButton publish_button = new Gtk.ToolButton.from_stock("");
        publish_button.set_related_action(get_action("Publish"));
        publish_button.set_icon_name(Resources.PUBLISH);
        publish_button.set_label(Resources.PUBLISH_LABEL);
        
        toolbar.insert(publish_button, -1);
#endif
        
        // separator to force slider to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);

        // ratings filter button
        MediaPage.FilterButton filter_button = create_filter_button();
        connect_filter_button(filter_button);
        toolbar.insert(filter_button, -1);

        Gtk.SeparatorToolItem drawn_separator = new Gtk.SeparatorToolItem();
        drawn_separator.set_expand(false);
        drawn_separator.set_draw(true);
        
        toolbar.insert(drawn_separator, -1);
        
        // zoom slider assembly
        MediaPage.ZoomSliderAssembly zoom_slider_assembly = create_zoom_slider_assembly();
        connect_slider(zoom_slider_assembly);
        toolbar.insert(zoom_slider_assembly, -1);
        
        show_all();
        
        // enable photo drag-and-drop on our ViewCollection
        dnd_handler = new PhotoDragAndDropHandler(this);

        // watch for updates to the external app settings
        Config.get_instance().external_app_changed.connect(on_external_app_changed);
    }

    private static InjectionGroup create_file_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/FileMenu/FileExtrasPlaceholder");
        
#if !NO_PRINTING
        group.add_menu_item("Print");
        group.add_menu_item("PageSetup");
#endif

#if !NO_PUBLISHING
        group.add_separator();
        group.add_menu_item("Publish");
#endif

#if !NO_SET_BACKGROUND
        group.add_menu_item("SetBackground");
#endif
        
        return group;
    }
    
    private static InjectionGroup create_edit_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/EditMenu/EditExtrasPlaceholder");
        
        group.add_menu_item("Duplicate");
        group.add_separator();
        group.add_menu_item("RemoveFromLibrary");

        return group;
    }

    private static InjectionGroup create_view_menu_tags_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/ViewMenu/ViewExtrasTagsPlaceholder");
        
        group.add_menu_item("ViewTags");
        
        return group;
    }

    private static InjectionGroup create_view_menu_fullscreen_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/ViewMenu/ViewExtrasFullscreenSlideshowPlaceholder");
        
        group.add_menu_item("Fullscreen", "CommonFullscreen");
        group.add_separator();
        group.add_menu_item("Slideshow");
        
        return group;
    }

    private static InjectionGroup create_photos_menu_edits_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/PhotosMenu/PhotosExtrasEditsPlaceholder");
        
        group.add_menu_item("RotateClockwise");
        group.add_menu_item("RotateCounterclockwise");
        group.add_menu_item("FlipHorizontally");
        group.add_menu_item("FlipVertically");
        group.add_separator();
        group.add_menu_item("Enhance");
        group.add_menu_item("Revert");
        
        return group;
    }
  
    private static InjectionGroup create_photos_menu_date_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/PhotosMenu/PhotosExtrasDateTimePlaceholder");
        
        group.add_menu_item("AdjustDateTime");
        
        return group;
    }

    private static InjectionGroup create_photos_menu_externals_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/PhotosMenu/PhotosExtrasExternalsPlaceholder");
        
        group.add_menu_item("ExternalEdit");
        group.add_menu_item("ExternalEditRAW");
        
        return group;
    }

    private static InjectionGroup create_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/MenubarExtrasPlaceholder");
        
        group.add_menu("EventsMenu");
        group.add_menu("TagsMenu");
        
        return group;
    }

    private static InjectionGroup create_events_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/MenubarExtrasPlaceholder/EventsMenu");
        
        group.add_menu_item("NewEvent");
        group.add_menu_item("JumpToEvent");
        
        return group;
    }

    private static InjectionGroup create_tags_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/MenubarExtrasPlaceholder/TagsMenu");
        
        group.add_menu_item("AddTags");
        group.add_menu_item("ModifyTags");
        
        return group;
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("collection.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();

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
        
        Gtk.ActionEntry event = { "EventsMenu", null, TRANSLATABLE, null, null, null };
        event.label = _("Even_ts");
        actions += event;
        
        Gtk.ActionEntry remove_from_library = { "RemoveFromLibrary", Gtk.STOCK_REMOVE, TRANSLATABLE,
            "<Shift>Delete", TRANSLATABLE, on_remove_from_library };
        remove_from_library.label = Resources.REMOVE_FROM_LIBRARY_MENU;
        remove_from_library.tooltip = Resources.REMOVE_FROM_LIBRARY_PLURAL_TOOLTIP;
        actions += remove_from_library;
        
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

        Gtk.ActionEntry duplicate = { "Duplicate", null, TRANSLATABLE, "<Ctrl>D", TRANSLATABLE,
            on_duplicate_photo };
        duplicate.label = Resources.DUPLICATE_PHOTO_MENU;
        duplicate.tooltip = Resources.DUPLICATE_PHOTO_TOOLTIP;
        actions += duplicate;

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

        Gtk.ActionEntry new_event = { "NewEvent", Gtk.STOCK_NEW, TRANSLATABLE, "<Ctrl>N",
            TRANSLATABLE, on_new_event };
        new_event.label = Resources.NEW_EVENT_MENU;
        new_event.tooltip = Resources.NEW_EVENT_TOOLTIP;
        actions += new_event;
        
        Gtk.ActionEntry jump_to_event = { "JumpToEvent", null, TRANSLATABLE, null, TRANSLATABLE,
            on_jump_to_event };
        jump_to_event.label = _("View Eve_nt for Photo");
        jump_to_event.tooltip = _("Go to this photo's event");
        actions += jump_to_event;
        
        Gtk.ActionEntry tags = { "TagsMenu", null, TRANSLATABLE, null, null, null };
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
        
        return actions;
    }
    
    protected override Gtk.ToggleActionEntry[] init_collect_toggle_action_entries() {
        Gtk.ToggleActionEntry[] toggle_actions = base.init_collect_toggle_action_entries();
        
        Gtk.ToggleActionEntry tags = { "ViewTags", null, TRANSLATABLE, "<Ctrl><Shift>G",
            TRANSLATABLE, on_display_tags, Config.get_instance().get_display_photo_tags() };
        tags.label = _("Ta_gs");
        tags.tooltip = _("Display each photo's tags");
        toggle_actions += tags;
        
        return toggle_actions;
    }
    
    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();
        
        groups += create_file_menu_injectables();
        groups += create_edit_menu_injectables();
        groups += create_view_menu_tags_injectables();
        groups += create_view_menu_fullscreen_injectables();
        groups += create_photos_menu_edits_injectables();
        groups += create_photos_menu_date_injectables();
        groups += create_photos_menu_externals_injectables();
        groups += create_menu_injectables();
        groups += create_events_menu_injectables();
        groups += create_tags_menu_injectables();
        
        return groups;
    }
    
    public override void switched_to() {
        // set display options to match Configuration toggles (which can change while switched away)
        get_view().freeze_notifications();
        set_display_tags(Config.get_instance().get_display_photo_tags());
        get_view().thaw_notifications();
        
        // perform these operations before calling base method to prevent flicker
        base.switched_to();
    }
    
    protected override void update_actions(int selected_count, int count) {
        bool one_selected = selected_count == 1;
        bool has_selected = selected_count > 0;
        bool has_items = count > 0;
        
        set_action_sensitive("RemoveFromLibrary", has_selected);
        set_action_sensitive("Duplicate", has_selected);
        set_action_sensitive("ExternalEdit", 
            one_selected && !is_string_empty(Config.get_instance().get_external_photo_app()));
#if !NO_RAW
        set_action_visible("ExternalEditRAW",
            one_selected
            && ((Photo) get_view().get_selected_at(0).get_source()).get_master_file_format() == 
                PhotoFileFormat.RAW
            && !is_string_empty(Config.get_instance().get_external_raw_app()));
#endif
        set_action_sensitive("Revert", can_revert_selected());
        set_action_sensitive("Enhance", has_selected);
        set_action_important("Enhance", true);
        set_action_sensitive("JumpToEvent", can_jump_to_event());
        set_action_sensitive("RotateClockwise", has_selected);
        set_action_important("RotateClockwise", true);
        set_action_sensitive("RotateCounterclockwise", has_selected);
        set_action_important("RotateCounterclockwise", true);
        set_action_sensitive("FlipHorizontally", has_selected);
        set_action_sensitive("FlipVertically", has_selected);
        set_action_sensitive("AdjustDateTime", has_selected);
        set_action_sensitive("NewEvent", has_selected);
        set_action_sensitive("AddTags", has_selected);
        set_action_sensitive("ModifyTags", one_selected);
        set_action_sensitive("Slideshow", has_items);
        set_action_important("Slideshow", true);
        
#if !NO_SET_BACKGROUND
        set_action_sensitive("SetBackground", one_selected);
#endif
        
#if !NO_PRINTING
        set_action_sensitive("Print", one_selected);
#endif
        
#if !NO_PUBLISHING
        set_action_sensitive("Publish", has_selected);
        set_action_important("Publish", true);
#endif
        
        base.update_actions(selected_count, count);
    }

    private void on_photos_altered() {
        // since the photo can be altered externally to Shotwell now, need to make the revert
        // command available appropriately, even if the selection doesn't change
        set_action_sensitive("Revert", can_revert_selected());
        set_action_sensitive("JumpToEvent", can_jump_to_event());
    }
    
#if !NO_PRINTING
    private void on_print() {
        if (get_view().get_selected_count() == 1)
            PrintManager.get_instance().spool_photo((Photo) get_view().get_selected_at(0).get_source());
    }

    protected void on_page_setup() {
        PrintManager.get_instance().do_page_setup();
    }
#endif
    
    private void on_external_app_changed() {
        int selected_count = get_view().get_selected_count();
        
        set_action_sensitive("ExternalEdit", selected_count == 1 && Config.get_instance().get_external_photo_app() != "");
    }
    
    // see #2020
    // double clcik = switch to photo page
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

            default:
                handled = false;
            break;
        }
        
        return handled ? true : base.on_app_key_pressed(event);
    }

    protected override void on_export() {
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
            ((Gee.ArrayList<Photo>) export_list).get(0).get_file_format();
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
        
        exporter = new ExporterUI(new Exporter(export_list, export_dir,
            scaling, quality, format));
        exporter.export(on_export_completed);
    }
    
    private void on_export_completed() {
        exporter = null;
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
   
    private void on_remove_from_library() {
        remove_photos_from_library((Gee.Collection<LibraryPhoto>) get_view().get_selected_sources());
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
        
        PublishingDialog.go(get_view().get_selected());
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
        
        Photo photo = (Photo) get_view().get_selected_at(0).get_source();
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

    private void on_display_tags(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_tags(display);
        
        Config.get_instance().set_display_photo_tags(display);
    }
            
    protected override bool on_ctrl_pressed(Gdk.EventKey? event) {
        rotate_button.set_related_action(get_action("RotateCounterclockwise"));
        rotate_button.set_label(Resources.ROTATE_CCW_LABEL);
        
        return base.on_ctrl_pressed(event);
    }
    
    protected override bool on_ctrl_released(Gdk.EventKey? event) {
        rotate_button.set_related_action(get_action("RotateClockwise"));
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        
        return base.on_ctrl_released(event);
    }
    
    private void set_display_tags(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SHOW_TAGS, display);
        get_view().thaw_notifications();
        
        Gtk.ToggleAction action = (Gtk.ToggleAction) action_group.get_action("ViewTags");
        if (action != null)
            action.set_active(display);
    }
   
    private void on_new_event() {
        if (get_view().get_selected_count() > 0)
            get_command_manager().execute(new NewEventCommand(get_view().get_selected()));
    }
    
    private bool can_jump_to_event() {
        if (get_view().get_selected_count() != 1)
            return false;
        
        return ((Photo) get_view().get_selected_at(0).get_source()).get_event() != null;
    }
    
    private void on_jump_to_event() {
        if (get_view().get_selected_count() != 1)
            return;
        
        Event? event = ((Photo) get_view().get_selected_at(0).get_source()).get_event();
        if (event != null)
            LibraryWindow.get_app().switch_to_event(event);
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
}

public class LibraryPage : CollectionPage {
    public LibraryPage(ProgressMonitor? monitor = null) {
        base(_("Photos"));
        
        get_view().freeze_notifications();
        get_view().monitor_source_collection(LibraryPhoto.global, new CollectionViewManager(this),
            null, (Gee.Collection<DataSource>) LibraryPhoto.global.get_all(), monitor);
        get_view().thaw_notifications();
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

