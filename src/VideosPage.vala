/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class VideosPage : MediaPage {
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
            base(video);
        }
    }

    private ExporterUI exporter = null;
    
    public VideosPage() {
        base (_("Videos"));
        
        // Update "Photo" labels to "Video"
        action_group.get_action("PhotosMenu").set_label(_("Vi_deos"));
        action_group.get_action("FilterPhotos").set_label(_("_Filter Videos"));
        action_group.get_action("SortPhotos").set_label(_("Sort _Videos"));
        action_group.get_action("DisplayUnratedOrHigher").set_label(_("_All Videos"));
        
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

        get_view().monitor_source_collection(Video.global, new VideoViewManager(this), null);
    }

    private static InjectionGroup create_edit_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/EditMenu/EditExtrasPlaceholder");
        
        group.add_separator();
        group.add_menu_item("DeleteVideo");
        
        return group;
    }

    private static InjectionGroup create_videos_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/PhotosMenu/PhotosExtrasExternalsPlaceholder");
        
        group.add_menu_item("PlayVideo");
        
        return group;
    }

    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry delete_video = { "DeleteVideo", Gtk.STOCK_DELETE, TRANSLATABLE, "Delete",
            TRANSLATABLE, on_delete_video };
        delete_video.label = _("_Delete");
        delete_video.tooltip = _("Deletes the selected videos from your library and from disk");
        actions += delete_video;

        Gtk.ActionEntry play = { "PlayVideo", Gtk.STOCK_MEDIA_PLAY, TRANSLATABLE, "<Ctrl>P",
            TRANSLATABLE, on_play_video };
        play.label = _("_Play Video");
        play.tooltip = _("Open the selected videos in the system video player");
        actions += play;

        return actions;
    }
    
    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();
        
        groups += create_edit_menu_injectables();
        groups += create_videos_menu_injectables();
        
        return groups;
    }
    
    public static Stub create_stub() {
        return new Stub();
    }

    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("PlayVideo", selected_count == 1);
        set_action_important("PlayVideo", true);
        set_action_sensitive("DeleteVideo", selected_count > 0);
        
        base.update_actions(selected_count, count);
    }

    protected override void on_item_activated(CheckerboardItem item, CheckerboardPage.Activator 
        activator, CheckerboardPage.KeyboardModifiers modifiers) {
        on_play_video();
    }

    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_library_photos_sort(sort_order, sort_by);
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
    
    protected override void on_export() {
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
    
    public override CheckerboardItem? get_fullscreen_photo() {
        return null;
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
        return new Thumbnail((Video) source, host_page.get_thumb_size());
    }
}

