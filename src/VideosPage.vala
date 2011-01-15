/* Copyright 2010-2011 Yorba Foundation
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
        
        public override GLib.Icon? get_icon() {
            return new GLib.ThemedIcon(Resources.ICON_VIDEOS_PAGE);
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
        
        init_item_context_menu("/VideoContextMenu");
        
        // Update "Photo" labels to "Video"
        action_group.get_action("PhotosMenu").set_label(_("Vi_deos"));
        action_group.get_action("FilterPhotos").set_label(_("_Filter Videos"));
        action_group.get_action("SortPhotos").set_label(_("Sort _Videos"));
        action_group.get_action("DisplayUnratedOrHigher").set_label(_("_All Videos"));
        set_common_action_label("CommonJumpToEvent", _("View Eve_nt for Video"));
        
        Gtk.Toolbar toolbar = get_toolbar();
        
        // play button
        Gtk.ToolButton play_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PLAY);
        play_button.set_related_action(get_action("PlayVideo"));
        play_button.set_label(_("Play"));
        toolbar.insert(play_button, -1);

        // publish button
        Gtk.ToolButton publish_button = new Gtk.ToolButton.from_stock("");
        publish_button.set_related_action(action_group.get_action("Publish"));
        publish_button.set_icon_name(Resources.PUBLISH);
        publish_button.set_label(Resources.PUBLISH_LABEL);
        toolbar.insert(publish_button, -1);

        // separator to force slider to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // Search box.
        MediaPage.SearchBox search_box = create_search_box();
        connect_search_box(search_box);
        toolbar.insert(search_box, -1);

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
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("video.ui");
    }
    
    private static InjectionGroup create_file_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/FileMenu/FileExtrasPlaceholder");
        
        group.add_separator();
        group.add_menu_item("Publish");
        group.add_menu_item("SendTo");
        
        return group;
    }
    
    private static InjectionGroup create_videos_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/PhotosMenu/PhotosExtrasExternalsPlaceholder");
        
        group.add_menu_item("PlayVideo");
        
        return group;
    }

    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();

        Gtk.ActionEntry publish = { "Publish", Resources.PUBLISH, TRANSLATABLE, "<Ctrl><Shift>P",
            TRANSLATABLE, on_publish };
        publish.label = Resources.PUBLISH_MENU;
        publish.tooltip = Resources.PUBLISH_TOOLTIP;
        actions += publish;

        return actions;
    }

    private void on_publish() {
        if (get_view().get_selected_count() > 0)
            PublishingDialog.go((Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }

    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();
        
        groups += create_file_menu_injectables();
        groups += create_videos_menu_injectables();
        
        return groups;
    }
    
    public static Stub create_stub() {
        return new Stub();
    }
    
    protected override void init_actions(int selected_count, int count) {
        set_action_important("PlayVideo", true);
        set_action_important("Publish", true);
        
        base.init_actions(selected_count, count);
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("Publish", selected_count >= 1);
        
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
    
    protected override void on_export() {
        if (exporter != null)
            return;
        
        Gee.Collection<Video> export_list =
            (Gee.Collection<Video>) get_view().get_selected_sources();
        if (export_list.size == 0)
            return;
      
        exporter = Video.export_many(export_list, on_export_completed);
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

