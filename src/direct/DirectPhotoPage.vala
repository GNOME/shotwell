/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class DirectPhotoPage : EditingHostPage {
    private File initial_file;
    private DirectViewCollection? view_controller = null;
    private File current_save_dir;
    private bool drop_if_dirty = false;
    private bool in_shutdown = false;
    
    public DirectPhotoPage(File file) {
        base (DirectPhoto.global, file.get_basename());
        
        if (!check_editable_file(file)) {
            
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

    private const GLib.ActionEntry[] entries = {
        { "Save", on_save },
        { "SaveAs", on_save_as },
        { "SendTo", on_send_to },
        { "Print", on_print },
        { "PrevPhoto", on_previous_photo },
        { "NextPhoto", on_next_photo },
        { "RotateClockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", on_rotate_counterclockwise },
        { "FlipHorizontally", on_flip_horizontally },
        { "FlipVertically", on_flip_vertically },
        { "Revert", on_revert },
        { "AdjustDateTime", on_adjust_date_time },
        { "SetBackground", on_set_background },
        { "IncreaseSize", on_increase_size },
        { "DecreaseSize", on_decrease_size },
        { "ZoomFit", snap_zoom_to_min },
        { "Zoom100", snap_zoom_to_isomorphic },
        { "Zoom200", snap_zoom_to_max }
    };

    protected override void add_actions (GLib.ActionMap map) {
        base.add_actions (map);

        map.add_action_entries (entries, this);
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
        
        InjectionGroup bg_group = new InjectionGroup("SetBackgroundPlaceholder");
        bg_group.add_menu_item(_("Set as _Desktop Background"), "SetBackground", "<Primary>b");
        
        groups += bg_group;
        
        return groups;
    }
    
    private static bool check_editable_file(File file) {
        if (!FileUtils.test(file.get_path(), FileTest.EXISTS))
            AppWindow.error_message(_("%s does not exist.").printf(file.get_path()), AppWindow.get_instance(), true);
        else if (!FileUtils.test(file.get_path(), FileTest.IS_REGULAR))
            AppWindow.error_message(_("%s is not a file.").printf(file.get_path()), AppWindow.get_instance(), true);
        else if (!PhotoFileFormat.is_file_supported(file))
            AppWindow.error_message(_("%s does not support the file format of\n%s.").printf(
                Resources.APP_TITLE, file.get_path()), AppWindow.get_instance(), true);
        else
            return true;
        
        return false;
    }
    
    public override void realize() {
        if (base.realize != null)
            base.realize();
        
        DirectPhoto? photo = DirectPhoto.global.get_file_source(initial_file);
        
        if (photo != null) {
            display_mirror_of(view_controller, photo);
        } else {
            AppWindow.panic(_("Unable to open photo %s. Sorry.").printf(initial_file.get_path()));
        }

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

    protected override bool on_context_buttonpress(Gtk.EventController event, double x, double y) {
        popup_context_menu(get_context_menu(), x, y);

        return true;
    }

    private Gtk.PopoverMenu context_menu;

    private Gtk.PopoverMenu get_context_menu() {
        if (context_menu == null) {
            context_menu = get_popover_menu_from_builder (this.builder, "DirectContextMenu", this);
        }

        return this.context_menu;
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
    
    protected override bool on_double_click(Gtk.EventController event, double x, double y) {
        FullscreenWindow? fs = get_container() as FullscreenWindow;
        if (fs != null) {
            fs.close();
            
            return true;
        } else {
            var direct_window = get_container() as DirectWindow;
            if (direct_window != null) {
                direct_window.do_fullscreen();

                return true;
            }
        }
        
        return base.on_double_click(event, x, y);
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
            //set_action_sensitive("Crop", EditingTools.CropTool.is_available(get_photo(), Scaling.for_original()));
            //set_action_sensitive("RedEye", EditingTools.RedeyeTool.is_available(get_photo(), 
            //    Scaling.for_original()));
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
    
    private async bool check_ok_to_close_photo(Photo? photo, bool notify = true) {
        // Means we failed to load the photo for some reason. Do not block
        // shutdown
        if (photo == null) {
            return true;
        }

        if (!photo.has_alterations()) {
            return true;
        }
        
        if (drop_if_dirty) {
            // need to remove transformations, or else they stick around in memory (reappearing
            // if the user opens the file again)
            photo.remove_all_transformations(notify);
            
            return true;
        }

        // Check if we can write the target format
        bool is_writeable = get_photo().get_file_format().can_write();
        var file = photo.get_file();
        try {
           var info = yield file.query_info_async(FileAttribute.ACCESS_CAN_WRITE, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
           is_writeable = is_writeable && info.get_attribute_boolean(FileAttribute.ACCESS_CAN_WRITE);
        } catch (Error error) {
            critical("Failed to get writeable status: %s", error.message);
        }
        
        string save_option = is_writeable ? _("_Save") : _("_Save a Copy");

        var dialog = new Gtk.AlertDialog(_("Lose changes to %s?"), photo.get_basename());
        dialog.set_buttons({save_option, _("Close _without Saving")});
        int result = -1;
        try {
            result = yield dialog.choose(AppWindow.get_instance(), null);
        } catch (Error error) {
            critical("Failed to get an answer from dialog: %s", error.message);
        }

        if (result == -1) {
            in_shutdown = false;
            return false;
        }

        if (result == 0) {
            if (is_writeable)
                save(photo.get_file(), 0, ScaleConstraint.ORIGINAL, Jpeg.Quality.HIGH,
                    get_photo().get_file_format());
            else
                yield save_as();
        }
        
        if (result == 1) {
            photo.remove_all_transformations(notify);
        }

        return true;
    }
    
    public async bool check_quit() {
        in_shutdown = true;
        return yield check_ok_to_close_photo(get_photo(), false);
    }
    
    protected async override bool confirm_replace_photo(Photo? old_photo, Photo new_photo) {
        return (old_photo != null) ? yield check_ok_to_close_photo(old_photo) : true;
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

        if (in_shutdown) return;

        // Fetch the DirectPhoto and reimport.
        DirectPhoto photo;
        DirectPhoto.global.fetch(dest, out photo, true);

        if (!get_photo().equals(photo)) {
            DirectView tmp_view = new DirectView(photo);
            view_controller.add(tmp_view);
        }

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
        save_as.begin();
    }

    private async void save_as() {
        ExportDialog export_dialog = new ExportDialog(_("Save As"));
        
        ExportFormatParameters? export_params = ExportFormatParameters.last();

        export_params = yield export_dialog.execute(export_params);
        if (export_params == null) {
            return;
        }

        string filename = get_photo().get_export_basename_for_parameters(export_params);
        PhotoFileFormat effective_export_format =
            get_photo().get_export_format_for_parameters(export_params);

        string[] output_format_extensions =
            effective_export_format.get_properties().get_known_extensions();
        Gtk.FileFilter output_format_filter = new Gtk.FileFilter();
        output_format_filter.set_filter_name(_("Supported image formats"));
        foreach(string extension in output_format_extensions) {
            string uppercase_extension = extension.up();
            output_format_filter.add_pattern("*." + extension);
            output_format_filter.add_pattern("*." + uppercase_extension);
        }

        Gtk.FileFilter all_files = new Gtk.FileFilter();
        all_files.add_pattern("*");
        all_files.set_filter_name(_("All files"));

        var save_as_dialog = new Gtk.FileDialog();
        save_as_dialog.set_accept_label(Resources.OK_LABEL);
        var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
        filters.append(output_format_filter);
        filters.append(all_files);
        save_as_dialog.set_filters(filters);

        save_as_dialog.set_initial_name(filename);
        save_as_dialog.set_initial_folder(current_save_dir);

        try {
            var file = yield save_as_dialog.save(AppWindow.get_instance(), null);
            if (file == null) {
                return;
            }
            // flag to prevent asking user about losing changes to the old file (since they'll be
            // loaded right into the new one)
            drop_if_dirty = true;
            save(file, export_params.scale, export_params.constraint, export_params.quality,
                effective_export_format, export_params.mode == ExportFormatMode.UNMODIFIED, 
                export_params.export_metadata);
            drop_if_dirty = false;

            current_save_dir = file.get_parent();
        } catch (Error error) {
            critical("Failed: %s", error.message);
        }
    }
    
    private void on_send_to() {
        if (has_photo())
            DesktopIntegration.send_to.begin((Gee.Collection<Photo>) get_view().get_selected_sources());
    }
    
    protected override bool on_app_key_pressed(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        bool handled = true;
        string? format = null;
        
        switch (Gdk.keyval_name(keyval)) {
            case "bracketright":
                activate_action("win.RotateClockwise", format);
            break;
            
            case "bracketleft":
                activate_action("win.RotateCounterclockwise", format);
            break;
            
            default:
                handled = false;
            break;
        }
        
        return handled ? true : base.on_app_key_pressed(event, keyval, keycode, modifiers);
    }
    
    private void on_print() {
        if (get_view().get_selected_count() > 0) {
            PrintManager.get_instance().spool_photo(
                (Gee.Collection<Photo>) get_view().get_selected_sources_of_type(typeof(Photo)));
        }
    }
    
    private void on_dphoto_can_rotate_changed(bool should_allow_rotation) {
        // since this signal handler can be called from a background thread (gah, don't get me
        // started...), chain to the "enable-rotate" signal in the foreground thread, as it's
        // tied to UI elements
        Idle.add(() => {
            set_action_sensitive("RotateClockwise", should_allow_rotation);
            set_action_sensitive("RotateCounterclockwise", should_allow_rotation);
                
            return false;
        });
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
        base.init_collect_ui_filenames(ui_filenames);
        ui_filenames.add("direct_context.ui");
    }
}
