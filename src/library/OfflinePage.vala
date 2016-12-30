/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class OfflinePage : CheckerboardPage {
    public const string NAME = _("Missing Files");
    
    private class OfflineView : Thumbnail {
        public OfflineView(MediaSource source) {
            base (source);
            
            assert(source.is_offline());
        }
    }
    
    private class OfflineSearchViewFilter : DefaultSearchViewFilter {
        public override uint get_criteria() {
            return SearchFilterCriteria.TEXT | SearchFilterCriteria.FLAG | 
                SearchFilterCriteria.MEDIA | SearchFilterCriteria.RATING | SearchFilterCriteria.SAVEDSEARCH;
        }
    }
    
    private OfflineSearchViewFilter search_filter = new OfflineSearchViewFilter();
    private MediaViewTracker tracker;
    
    public OfflinePage() {
        base (NAME);
        
        init_item_context_menu("OfflineContextMenu");
        init_toolbar("OfflineToolbar");
        
        tracker = new MediaViewTracker(get_view());
        
        // monitor offline and initialize view with all items in it
        LibraryPhoto.global.offline_contents_altered.connect(on_offline_contents_altered);
        Video.global.offline_contents_altered.connect(on_offline_contents_altered);
        
        on_offline_contents_altered(LibraryPhoto.global.get_offline_bin_contents(), null);
        on_offline_contents_altered(Video.global.get_offline_bin_contents(), null);
    }
    
    ~OfflinePage() {
        LibraryPhoto.global.offline_contents_altered.disconnect(on_offline_contents_altered);
        Video.global.offline_contents_altered.disconnect(on_offline_contents_altered);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("offline.ui");
    }

    private const GLib.ActionEntry[] entries = {
        { "RemoveFromLibrary", on_remove_from_library }
    };

    protected override void add_actions (GLib.ActionMap map) {
        base.add_actions(map);

        map.add_action_entries(entries, this);
    }

    protected override void remove_actions(GLib.ActionMap map) {
        base.remove_actions(map);
        foreach (var entry in entries) {
            map.remove_action(entry.name);
        }
    }

    public override Core.ViewTracker? get_view_tracker() {
        return tracker;
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("RemoveFromLibrary", selected_count > 0);

        base.update_actions(selected_count, count);
    }
    
    private void on_offline_contents_altered(Gee.Collection<MediaSource>? added,
        Gee.Collection<MediaSource>? removed) {
        if (added != null) {
            foreach (MediaSource source in added)
                get_view().add(new OfflineView(source));
        }
        
        if (removed != null) {
            Marker marker = get_view().start_marking();
            foreach (MediaSource source in removed)
                marker.mark(get_view().get_view_for_source(source));
            get_view().remove_marked(marker);
        }
    }
    
    private void on_remove_from_library() {
        Gee.Collection<MediaSource> sources =
            (Gee.Collection<MediaSource>) get_view().get_selected_sources();
        if (sources.size == 0)
            return;
        
        if (!remove_offline_dialog(AppWindow.get_instance(), sources.size))
            return;
        
        AppWindow.get_instance().set_busy_cursor();
        
        ProgressDialog progress = null;
        if (sources.size >= 20)
            progress = new ProgressDialog(AppWindow.get_instance(), _("Deleting…"));

        Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<Video> videos = new Gee.ArrayList<Video>();
        MediaSourceCollection.filter_media(sources, photos, videos);

        if (progress != null) {
            LibraryPhoto.global.remove_from_app(photos, false, progress.monitor);
            Video.global.remove_from_app(videos, false, progress.monitor);
        } else {
            LibraryPhoto.global.remove_from_app(photos, false);
            Video.global.remove_from_app(videos, false);
        }
        
        if (progress != null)
            progress.close();
        
        AppWindow.get_instance().set_normal_cursor();
    }
    
    public override SearchViewFilter get_search_view_filter() {
        return search_filter;
    }
}

