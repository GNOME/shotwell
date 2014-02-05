/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class DirectPhotoPage : EditingHostPage {
    private File initial_file;
    private DirectViewCollection? view_controller = null;
    private File current_save_dir;
    private bool drop_if_dirty = false;
    
    public DirectPhotoPage(File file) {
        base (DirectPhoto.global, file.get_basename());
        
        if (!check_editable_file(file)) {
            Application.get_instance().panic();
            
            return;
        }
        
        initial_file = file;
        view_controller = new DirectViewCollection();
        current_save_dir = file.get_parent();
        
        DirectPhoto.global.items_altered.connect(on_photos_altered);
        
        get_view().selection_group_altered.connect(on_selection_group_altered);
    }
    
    ~DirectPhotoPage() {
        DirectPhoto.global.items_altered.disconnect(on_photos_altered);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("direct_context.ui");
        ui_filenames.add("direct.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, null };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry save = { "Save", Gtk.Stock.SAVE, TRANSLATABLE, "<Ctrl>S", TRANSLATABLE,
            on_save };
        save.label = _("_Save");
        save.tooltip = _("Save photo");
        actions += save;

        Gtk.ActionEntry save_as = { "SaveAs", Gtk.Stock.SAVE_AS, TRANSLATABLE,
            "<Ctrl><Shift>S", TRANSLATABLE, on_save_as };
        save_as.label = _("Save _As...");
        save_as.tooltip = _("Save photo with a different name");
        actions += save_as;
        
        Gtk.ActionEntry send_to = { "SendTo", "document-send", TRANSLATABLE, null,
            TRANSLATABLE, on_send_to };
        send_to.label = Resources.SEND_TO_MENU;
        actions += send_to;

        Gtk.ActionEntry print = { "Print", Gtk.Stock.PRINT, TRANSLATABLE, "<Ctrl>P",
            TRANSLATABLE, on_print };
        print.label = Resources.PRINT_MENU;
        print.tooltip = _("Print the photo to a printer connected to your computer");
        actions += print;
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, null };
        edit.label = _("_Edit");
        actions += edit;

        Gtk.ActionEntry photo = { "PhotoMenu", null, "", null, null, null };
        photo.label = _("_Photo");
        actions += photo;
        
        Gtk.ActionEntry tools = { "Tools", null, TRANSLATABLE, null, null, null };
        tools.label = _("T_ools");
        actions += tools;
        
        Gtk.ActionEntry prev = { "PrevPhoto", Gtk.Stock.GO_BACK, TRANSLATABLE, null,
            TRANSLATABLE, on_previous_photo };
        prev.label = _("_Previous Photo");
        prev.tooltip = _("Previous Photo");
        actions += prev;

        Gtk.ActionEntry next = { "NextPhoto", Gtk.Stock.GO_FORWARD, TRANSLATABLE, null,
            TRANSLATABLE, on_next_photo };
        next.label = _("_Next Photo");
        next.tooltip = _("Next Photo");
        actions += next;

        Gtk.ActionEntry rotate_right = { "RotateClockwise", Resources.CLOCKWISE,
            TRANSLATABLE, "<Ctrl>R", TRANSLATABLE, on_rotate_clockwise };
        rotate_right.label = Resources.ROTATE_CW_MENU;
        rotate_right.tooltip = Resources.ROTATE_CCW_TOOLTIP;
        actions += rotate_right;

        Gtk.ActionEntry rotate_left = { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE,
            TRANSLATABLE, "<Ctrl><Shift>R", TRANSLATABLE, on_rotate_counterclockwise };
        rotate_left.label = Resources.ROTATE_CCW_MENU;
        rotate_left.tooltip = Resources.ROTATE_CCW_TOOLTIP;
        actions += rotate_left;

        Gtk.ActionEntry hflip = { "FlipHorizontally", Resources.HFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_horizontally };
        hflip.label = Resources.HFLIP_MENU;
        actions += hflip;
        
        Gtk.ActionEntry vflip = { "FlipVertically", Resources.VFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_vertically };
        vflip.label = Resources.VFLIP_MENU;
        actions += vflip;
        
        Gtk.ActionEntry enhance = { "Enhance", Resources.ENHANCE, TRANSLATABLE, "<Ctrl>E",
            TRANSLATABLE, on_enhance };
        enhance.label = Resources.ENHANCE_MENU;
        enhance.tooltip = Resources.ENHANCE_TOOLTIP;
        actions += enhance;
        
        Gtk.ActionEntry crop = { "Crop", Resources.CROP, TRANSLATABLE, "<Ctrl>O",
            TRANSLATABLE, toggle_crop };
        crop.label = Resources.CROP_MENU;
        crop.tooltip = Resources.CROP_TOOLTIP;
        actions += crop;
        
        Gtk.ActionEntry straighten = { "Straighten", Gtk.Stock.REFRESH, TRANSLATABLE, "<Ctrl>A",
            TRANSLATABLE, toggle_straighten };
        straighten.label = Resources.STRAIGHTEN_MENU;
        straighten.tooltip = Resources.STRAIGHTEN_TOOLTIP;
        actions += straighten;
        
        Gtk.ActionEntry red_eye = { "RedEye", Resources.REDEYE, TRANSLATABLE, "<Ctrl>Y",
            TRANSLATABLE, toggle_redeye };
        red_eye.label = Resources.RED_EYE_MENU;
        red_eye.tooltip = Resources.RED_EYE_TOOLTIP;
        actions += red_eye;
        
        Gtk.ActionEntry adjust = { "Adjust", Resources.ADJUST, TRANSLATABLE, "<Ctrl>D",
            TRANSLATABLE, toggle_adjust };
        adjust.label = Resources.ADJUST_MENU;
        adjust.tooltip = Resources.ADJUST_TOOLTIP;
        actions += adjust;
        
        Gtk.ActionEntry revert = { "Revert", Gtk.Stock.REVERT_TO_SAVED, TRANSLATABLE,
            null, TRANSLATABLE, on_revert };
        revert.label = Resources.REVERT_MENU;
        actions += revert;

        Gtk.ActionEntry adjust_date_time = { "AdjustDateTime", null, TRANSLATABLE, null,
            TRANSLATABLE, on_adjust_date_time };
        adjust_date_time.label = Resources.ADJUST_DATE_TIME_MENU;
        actions += adjust_date_time;
        
        Gtk.ActionEntry set_background = { "SetBackground", null, TRANSLATABLE, "<Ctrl>B",
            TRANSLATABLE, on_set_background };
        set_background.label = Resources.SET_BACKGROUND_MENU;
        set_background.tooltip = Resources.SET_BACKGROUND_TOOLTIP;
        actions += set_background;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, null };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        Gtk.ActionEntry increase_size = { "IncreaseSize", Gtk.Stock.ZOOM_IN, TRANSLATABLE,
            "<Ctrl>plus", TRANSLATABLE, on_increase_size };
        increase_size.label = _("Zoom _In");
        increase_size.tooltip = _("Increase the magnification of the photo");
        actions += increase_size;

        Gtk.ActionEntry decrease_size = { "DecreaseSize", Gtk.Stock.ZOOM_OUT, TRANSLATABLE,
            "<Ctrl>minus", TRANSLATABLE, on_decrease_size };
        decrease_size.label = _("Zoom _Out");
        decrease_size.tooltip = _("Decrease the magnification of the photo");
        actions += decrease_size;

        Gtk.ActionEntry best_fit = { "ZoomFit", Gtk.Stock.ZOOM_FIT, TRANSLATABLE,
            "<Ctrl>0", TRANSLATABLE, snap_zoom_to_min };
        best_fit.label = _("Fit to _Page");
        best_fit.tooltip = _("Zoom the photo to fit on the screen");
        actions += best_fit;

        Gtk.ActionEntry actual_size = { "Zoom100", Gtk.Stock.ZOOM_100, TRANSLATABLE,
            "<Ctrl>1", TRANSLATABLE, snap_zoom_to_isomorphic };
        /// xgettext:no-c-format
        actual_size.label = _("Zoom _100%");
        /// xgettext:no-c-format
        actual_size.tooltip = _("Zoom the photo to 100% magnification");
        actions += actual_size;
        
        Gtk.ActionEntry max_size = { "Zoom200", null, TRANSLATABLE,
            "<Ctrl>2", TRANSLATABLE, snap_zoom_to_max };
        /// xgettext:no-c-format
        max_size.label = _("Zoom _200%");
        /// xgettext:no-c-format
        max_size.tooltip = _("Zoom the photo to 200% magnification");
        actions += max_size;

        return actions;
    }
    
    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();
        
        InjectionGroup print_group = new InjectionGroup("/MenuBar/FileMenu/PrintPlaceholder");
        print_group.add_menu_item("Print");
        
        groups += print_group;
        
        InjectionGroup bg_group = new InjectionGroup("/MenuBar/FileMenu/SetBackgroundPlaceholder");
        bg_group.add_menu_item("SetBackground");
        
        groups += bg_group;
        
        return groups;
    }
    
    private static bool check_editable_file(File file) {
        if (!FileUtils.test(file.get_path(), FileTest.EXISTS))
            AppWindow.error_message(_("%s does not exist.").printf(file.get_path()));
        else if (!FileUtils.test(file.get_path(), FileTest.IS_REGULAR))
            AppWindow.error_message(_("%s is not a file.").printf(file.get_path()));
        else if (!PhotoFileFormat.is_file_supported(file))
            AppWindow.error_message(_("%s does not support the file format of\n%s.").printf(
                Resources.APP_TITLE, file.get_path()));
        else
            return true;
        
        return false;
    }
    
    public override void realize() {
        if (base.realize != null)
            base.realize();
        
        DirectPhoto? photo = DirectPhoto.global.get_file_source(initial_file);
        
        display_mirror_of(view_controller, photo);
        initial_file = null;
    }
    
    protected override void photo_changing(Photo new_photo) {
        if (get_photo() != null) {
            DirectPhoto tmp = get_photo() as DirectPhoto;
            
            if (tmp != null) {
                tmp.can_rotate_changed.disconnect(on_dphoto_can_rotate_changed);
            }
        }

        ((DirectPhoto) new_photo).demand_load();
        
        DirectPhoto tmp = new_photo as DirectPhoto;
        
        if (tmp != null) {
            tmp.can_rotate_changed.connect(on_dphoto_can_rotate_changed);
        }        
    }
    
    public File get_current_file() {
        return get_photo().get_file();
    }

    protected override bool on_context_buttonpress(Gdk.EventButton event) {
        Gtk.Menu context_menu = (Gtk.Menu) ui.get_widget("/DirectContextMenu");
        popup_context_menu(context_menu, event);

        return true;
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
    
    private void on_photos_altered(Gee.Map<DataObject, Alteration> map) {
        bool contains = false;
        if (has_photo()) {
            Photo photo = get_photo();
            foreach (DataObject object in map.keys) {
                if (((Photo) object) == photo) {
                    contains = true;
                    
                    break;
                }
            }
        }
        
        bool sensitive = has_photo() && !get_photo_missing();
        if (sensitive)
            sensitive = contains;
        
        set_action_sensitive("Save", sensitive && get_photo().get_file_format().can_write());
        set_action_sensitive("Revert", sensitive);
    }
    
    private void on_selection_group_altered() {
        // On EditingHostPage, the displayed photo is always selected, so this signal is fired
        // whenever a new photo is displayed (which even happens on an in-place save; the changes
        // are written and a new DirectPhoto is loaded into its place).
        //
        // In every case, reset the CommandManager, as the command stack is not valid against this
        // new file.
        get_command_manager().reset();
    }
    
    protected override bool on_double_click(Gdk.EventButton event) {
        AppWindow.get_instance().end_fullscreen();
        
        return base.on_double_click(event);
    }    
    
    protected override void update_ui(bool missing) {
        bool sensitivity = !missing;
        
        set_action_sensitive("Save", sensitivity);
        set_action_sensitive("SaveAs", sensitivity);
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
        
        set_action_sensitive("RotateClockwise", sensitivity);
        set_action_sensitive("RotateCounterclockwise", sensitivity);
        set_action_sensitive("FlipHorizontally", sensitivity);
        set_action_sensitive("FlipVertically", sensitivity);
        set_action_sensitive("Enhance", sensitivity);
        set_action_sensitive("Crop", sensitivity);
        set_action_sensitive("Straighten", sensitivity);
        set_action_sensitive("RedEye", sensitivity);
        set_action_sensitive("Adjust", sensitivity);
        set_action_sensitive("Revert", sensitivity);
        set_action_sensitive("AdjustDateTime", sensitivity);
        set_action_sensitive("Fullscreen", sensitivity);
        
        set_action_sensitive("SetBackground", has_photo() && !get_photo_missing());
        
        base.update_ui(missing);
    }
    
    protected override void update_actions(int selected_count, int count) {
        bool multiple = get_view().get_count() > 1;
        bool revert_possible = has_photo() ? get_photo().has_transformations() 
            && !get_photo_missing() : false;
        bool rotate_possible = has_photo() ? is_rotate_available(get_photo()) : false;
        bool enhance_possible = has_photo() ? is_enhance_available(get_photo()) : false;
        
        set_action_sensitive("PrevPhoto", multiple);
        set_action_sensitive("NextPhoto", multiple);
        set_action_sensitive("RotateClockwise", rotate_possible);
        set_action_sensitive("RotateCounterclockwise", rotate_possible);
        set_action_sensitive("FlipHorizontally", rotate_possible);
        set_action_sensitive("FlipVertically", rotate_possible);
        set_action_sensitive("Revert", revert_possible);
        set_action_sensitive("Enhance", enhance_possible);
        
        set_action_sensitive("SetBackground", has_photo());
        
        if (has_photo()) {
            set_action_sensitive("Crop", EditingTools.CropTool.is_available(get_photo(), Scaling.for_original()));
            set_action_sensitive("RedEye", EditingTools.RedeyeTool.is_available(get_photo(), 
                Scaling.for_original()));
        }

        // can't write to raws, and trapping the output JPEG here is tricky,
        // so don't allow date/time changes here.
        if (get_photo() != null) {
            set_action_sensitive("AdjustDateTime", (get_photo().get_file_format() != PhotoFileFormat.RAW));
        } else {
            set_action_sensitive("AdjustDateTime", false);
        }
                
        base.update_actions(selected_count, count);
    }
    
    private bool check_ok_to_close_photo(Photo photo) {
        if (!photo.has_alterations())
            return true;
        
        if (drop_if_dirty) {
            // need to remove transformations, or else they stick around in memory (reappearing
            // if the user opens the file again)
            photo.remove_all_transformations();
            
            return true;
        }

        bool is_writeable = get_photo().get_file_format().can_write();
        string save_option = is_writeable ? _("_Save") : _("_Save a Copy");

        Gtk.ResponseType response = AppWindow.negate_affirm_cancel_question(
            _("Lose changes to %s?").printf(photo.get_basename()), save_option,
            _("Close _without Saving"));

        if (response == Gtk.ResponseType.YES)
            photo.remove_all_transformations();
        else if (response == Gtk.ResponseType.NO) {
            if (is_writeable)
                save(photo.get_file(), 0, ScaleConstraint.ORIGINAL, Jpeg.Quality.HIGH,
                    get_photo().get_file_format());
            else
                on_save_as();
        } else if ((response == Gtk.ResponseType.CANCEL) || (response == Gtk.ResponseType.DELETE_EVENT) ||
            (response == Gtk.ResponseType.CLOSE)) {
            return false;
        }

        return true;
    }
    
    public bool check_quit() {
        return check_ok_to_close_photo(get_photo());
    }
    
    protected override bool confirm_replace_photo(Photo? old_photo, Photo new_photo) {
        return (old_photo != null) ? check_ok_to_close_photo(old_photo) : true;
    }

    private void save(File dest, int scale, ScaleConstraint constraint, Jpeg.Quality quality,
        PhotoFileFormat format, bool copy_unmodified = false, bool save_metadata = true) {
        Scaling scaling = Scaling.for_constraint(constraint, scale, false);
        
        try {
            get_photo().export(dest, scaling, quality, format, copy_unmodified, save_metadata);
        } catch (Error err) {
            AppWindow.error_message(_("Error while saving to %s: %s").printf(dest.get_path(),
                err.message));

            return;
        }

        // Fetch the DirectPhoto and reimport.
        DirectPhoto photo;
        DirectPhoto.global.fetch(dest, out photo, true);

        DirectView tmp_view = new DirectView(photo);
        view_controller.add(tmp_view);

        DirectPhoto.global.reimport_photo(photo);
        display_mirror_of(view_controller, photo);
    }

    private void on_save() {
        if (!get_photo().has_alterations() || !get_photo().get_file_format().can_write() || 
            get_photo_missing())
            return;

        // save full-sized version right on top of the current file
        save(get_photo().get_file(), 0, ScaleConstraint.ORIGINAL, Jpeg.Quality.HIGH,
            get_photo().get_file_format());
    }
    
    private void on_save_as() {
        ExportDialog export_dialog = new ExportDialog(_("Save As"));
        
        int scale;
        ScaleConstraint constraint;
        ExportFormatParameters export_params = ExportFormatParameters.last();
        if (!export_dialog.execute(out scale, out constraint, ref export_params))
            return;

        string filename = get_photo().get_export_basename_for_parameters(export_params);
        PhotoFileFormat effective_export_format =
            get_photo().get_export_format_for_parameters(export_params);

        string[] output_format_extensions =
            effective_export_format.get_properties().get_known_extensions();
        Gtk.FileFilter output_format_filter = new Gtk.FileFilter();
        foreach(string extension in output_format_extensions) {
            string uppercase_extension = extension.up();
            output_format_filter.add_pattern("*." + extension);
            output_format_filter.add_pattern("*." + uppercase_extension);
        }

        Gtk.FileChooserDialog save_as_dialog = new Gtk.FileChooserDialog(_("Save As"), 
            AppWindow.get_instance(), Gtk.FileChooserAction.SAVE, Gtk.Stock.CANCEL, 
            Gtk.ResponseType.CANCEL, Gtk.Stock.OK, Gtk.ResponseType.OK);
        save_as_dialog.set_select_multiple(false);
        save_as_dialog.set_current_name(filename);
        save_as_dialog.set_current_folder(current_save_dir.get_path());
        save_as_dialog.add_filter(output_format_filter);
        save_as_dialog.set_do_overwrite_confirmation(true);
        save_as_dialog.set_local_only(false);
        
        int response = save_as_dialog.run();
        if (response == Gtk.ResponseType.OK) {
            // flag to prevent asking user about losing changes to the old file (since they'll be
            // loaded right into the new one)
            drop_if_dirty = true;
            save(File.new_for_uri(save_as_dialog.get_uri()), scale, constraint, export_params.quality,
                effective_export_format, export_params.mode == ExportFormatMode.UNMODIFIED, 
                export_params.export_metadata);
            drop_if_dirty = false;

            current_save_dir = File.new_for_path(save_as_dialog.get_current_folder());
        }
        
        save_as_dialog.destroy();
    }
    
    private void on_send_to() {
        if (has_photo())
            DesktopIntegration.send_to((Gee.Collection<Photo>) get_view().get_selected_sources());
    }
    
    protected override bool on_app_key_pressed(Gdk.EventKey event) {
        bool handled = true;
        
        switch (Gdk.keyval_name(event.keyval)) {
            case "bracketright":
                activate_action("RotateClockwise");
            break;
            
            case "bracketleft":
                activate_action("RotateClockwise");
            break;
            
            default:
                handled = false;
            break;
        }
        
        return handled ? true : base.on_app_key_pressed(event);
    }
    
    private void on_print() {
        if (get_view().get_selected_count() > 0) {
            PrintManager.get_instance().spool_photo(
                (Gee.Collection<Photo>) get_view().get_selected_sources_of_type(typeof(Photo)));
        }
    }
    
    private void on_dphoto_can_rotate_changed(bool should_allow_rotation) {
        enable_rotate(should_allow_rotation);
    }   
    
    protected override DataView create_photo_view(DataSource source) {
        return new DirectView((DirectPhoto) source);
    }
}

public class DirectFullscreenPhotoPage : DirectPhotoPage {
    public DirectFullscreenPhotoPage(File file) {
        base(file);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        // We intentionally avoid calling the base class implementation since we don't want
        // direct.ui.
        ui_filenames.add("direct_context.ui");
    }
}
