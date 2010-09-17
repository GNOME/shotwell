/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class VideosPage : CheckerboardPage {
    public class Stub : PageStub {
        public Stub() {
        }
        
        protected override Page construct_page() {
            return new VideosPage();
        }
        
        public override string get_name() {
            return _("Videos");
        }
        
        public override string? get_icon_name() {
            return "";
        }
    }
    
    private class VideoView : Thumbnail {
        public VideoView(Video video) {
            base.for_video(video);
        }
    }

    private Gtk.HScale slider = null;
    private int scale;
    private ExporterUI exporter = null;
    
    public VideosPage() {
        base (_("Videos"));
        
        init_ui("videos.ui", "/VideosMenuBar", "VideosActionGroup", create_actions(),
            create_toggle_actions());

        Gtk.Toolbar toolbar = get_toolbar();
        
        // play button
        Gtk.ToolButton play_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PLAY);
        play_button.set_related_action(action_group.get_action("PlayVideo"));
        play_button.set_label(_("Play"));
        toolbar.insert(play_button, -1);

        // separator to force slider to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // thumbnail size slider
        slider = new Gtk.HScale(CollectionPage.get_global_slider_adjustment());
        slider.value_changed.connect(on_slider_changed);
        slider.set_draw_value(false);

        Gtk.ToolItem toolitem = new Gtk.ToolItem();
        toolitem.add(slider);
        toolitem.set_expand(false);
        toolitem.set_size_request(200, -1);
        toolitem.set_tooltip_text(_("Adjust the size of the thumbnails"));
        
        toolbar.insert(toolitem, -1);

        set_thumb_size(CollectionPage.slider_to_scale(slider.get_value()));

        get_view().monitor_source_collection(Video.global, new VideoViewManager(this), null);
        get_view().selection_group_altered.connect(on_selection_altered);
        on_selection_altered();
    }

    private Gtk.ToggleActionEntry[] create_toggle_actions() {
        Gtk.ToggleActionEntry[] toggle_actions = new Gtk.ToggleActionEntry[0];
        
        Gtk.ToggleActionEntry titles = { "ViewTitle", null, TRANSLATABLE, "<Ctrl><Shift>T",
            TRANSLATABLE, on_display_titles, Config.get_instance().get_display_photo_titles() };
        titles.label = _("_Titles");
        titles.tooltip = _("Display the title of each video");
        toggle_actions += titles;
        
        return toggle_actions;
    }

    private static Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        file.label = _("_File");
        actions += file;
        
        Gtk.ActionEntry export_video = { "ExportVideo", Gtk.STOCK_SAVE_AS, TRANSLATABLE, "<Ctrl><Shift>E",
            TRANSLATABLE, on_export_video };
        export_video.label = Resources.EXPORT_MENU;
        export_video.tooltip = _("Export the selected videos to disk");
        actions += export_video;

        Gtk.ActionEntry delete_video = { "DeleteVideo", Gtk.STOCK_DELETE, TRANSLATABLE, "Delete",
            TRANSLATABLE, on_delete_video };
        delete_video.label = _("_Delete");
        delete_video.tooltip = _("Deletes the selected videos from your library and from disk");
        actions += delete_video;
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, TRANSLATABLE, on_edit_menu };
        edit.label = _("_Edit");
        actions += edit;
                
        Gtk.ActionEntry play = { "PlayVideo", Gtk.STOCK_MEDIA_PLAY, TRANSLATABLE, "<Ctrl>P",
            TRANSLATABLE, on_play_video };
        play.label = _("_Play Video");
        play.tooltip = _("Open the selected videos in the system video player");
        actions += play;
        
        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        help.label = _("_Help");
        actions += help;
        
        return actions;
    }
    
    public static Stub create_stub() {
        return new Stub();
    }

    protected override void init_actions(int selected_count, int count) {
        base.init_actions(selected_count, count);
        action_group.get_action("PlayVideo").is_important = true;
    }

    protected override void switched_to() {
        set_thumb_size(CollectionPage.slider_to_scale(slider.get_value()));

        base.switched_to();
    }

    protected override void on_item_activated(CheckerboardItem item, CheckerboardPage.Activator 
        activator, CheckerboardPage.KeyboardModifiers modifiers) {
        on_play_video();
    }

    private void on_selection_altered() {
        set_action_sensitive("PlayVideo", get_view().get_selected_count() == 1);
        
        bool export_delete_sensitive = (get_view().get_selected_count() > 0);
        set_action_sensitive("ExportVideo", export_delete_sensitive);
        set_action_sensitive("DeleteVideo", export_delete_sensitive);
    }
    
    private void on_display_titles(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_titles(display);
        
        Config.get_instance().set_display_photo_titles(display);
    }

    private void on_play_video() {
        Gee.Collection<DataSource> selected = get_view().get_selected_sources();
        if (selected.size != 1)
            return;
        
        Video video = (Video) selected.to_array()[0];
        
        string launch_uri = "file://" + video.get_filename();
        try {
            AppInfo.launch_default_for_uri(launch_uri, null);
        } catch (Error e) {
            AppWindow.error_message(_("Shotwell was unable to play the selected video:\n%s").printf(
                e.message));
        }
    }
    
    private void on_delete_video() {       
        if (!AppWindow.negate_affirm_question(_("Deleting the selected videos will remove them " +
            "from your library as well delete them from disk. Do you want to continue?"),
            _("_No"), _("_Yes")))
                return;

        Marker destroy_marker = Video.global.mark_many(get_view().get_selected_sources());
        
        Video.global.destroy_marked(destroy_marker, true);
    }
    
    private void on_export_video() {
        if (exporter != null)
            return;
        
        Gee.Collection<Video> export_list =
            (Gee.Collection<Video>) get_view().get_selected_sources();
        if (export_list.size == 0)
            return;
      
        // handle the single-video case, which is treated like a Save As file operation
        if (export_list.size == 1) {
            Video video = null;
            foreach (Video v in export_list) {
                video = v;
                break;
            }
            
            File save_as = ExportUI.choose_file(video.get_basename());
            if (save_as == null)
                return;
            
            try {
                AppWindow.get_instance().set_busy_cursor();
                video.export(save_as);
                AppWindow.get_instance().set_normal_cursor();
            } catch (Error err) {
                AppWindow.get_instance().set_normal_cursor();
                export_error_dialog(save_as, false);
            }
            
            return;
        }

        // multiple videos
        File export_dir = ExportUI.choose_dir();
        if (export_dir == null)
            return;
        
        exporter = new ExporterUI(new Exporter(export_list, export_dir, Scaling.for_original(),
            Jpeg.Quality.MAXIMUM, PhotoFileFormat.get_system_default_format()));
        exporter.export(on_export_completed);
    }
    
    private void on_export_completed() {
        exporter = null;
    }

    private void on_edit_menu() {
        decorate_undo_item("/VideosMenuBar/EditMenu/Undo");
        decorate_redo_item("/VideosMenuBar/EditMenu/Redo");
    }

    private void on_slider_changed() {
        set_thumb_size(CollectionPage.slider_to_scale(slider.get_value()));
    }

    public override CheckerboardItem? get_fullscreen_photo() {
        return null;
    }

    public void increase_thumb_size() {
        set_thumb_size(scale + CollectionPage.MANUAL_STEPPING);
    }
    
    public void decrease_thumb_size() {
        set_thumb_size(scale - CollectionPage.MANUAL_STEPPING);
    }
    
    public void set_thumb_size(int new_scale) {       
        scale = new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
        get_checkerboard_layout().set_scale(scale);
        
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SIZE, scale);
        get_view().thaw_notifications();
    }
    
    public int get_thumb_size() {
        return scale;
    }
}

public class VideoViewManager : ViewManager {
    private VideosPage host_page;
   
    public VideoViewManager(VideosPage host_page) {
        this.host_page = host_page;
    }

    public override bool include_in_view(DataSource source) {
        return true;
    }
    
    public override DataView create_view(DataSource source) {
        return new Thumbnail.for_video((Video) source, host_page.get_thumb_size());
    }
}

