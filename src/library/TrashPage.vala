/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class TrashPage : CheckerboardPage {
    public const string NAME = _("Trash");
    
    private class TrashView : Thumbnail {
        public TrashView(MediaSource source) {
            base (source);
            
            assert(source.is_trashed());
        }
    }
    
    private class TrashSearchViewFilter : DefaultSearchViewFilter {
        public override uint get_criteria() {
            return SearchFilterCriteria.TEXT | SearchFilterCriteria.FLAG | 
                SearchFilterCriteria.MEDIA | SearchFilterCriteria.RATING | SearchFilterCriteria.SAVEDSEARCH;
        }
    }
    
    private TrashSearchViewFilter search_filter = new TrashSearchViewFilter();
    private MediaViewTracker tracker;
    
    public TrashPage() {
        base (NAME);
        
        init_item_context_menu("TrashContextMenu");
        init_page_context_menu("TrashPageMenu");
        init_toolbar("TrashToolbar");
        
        tracker = new MediaViewTracker(get_view());
        
        // monitor trashcans and initialize view with all items in them
        LibraryPhoto.global.trashcan_contents_altered.connect(on_trashcan_contents_altered);
        Video.global.trashcan_contents_altered.connect(on_trashcan_contents_altered);
        on_trashcan_contents_altered(LibraryPhoto.global.get_trashcan_contents(), null);
        on_trashcan_contents_altered(Video.global.get_trashcan_contents(), null);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("trash.ui");
    }

    private const GLib.ActionEntry[] entries = {
        { "Delete", on_delete },
        { "Restore", on_restore }
    };

    protected override void add_actions(GLib.ActionMap map) {
        base.add_actions(map);

        map.add_action_entries (entries, this);
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
        bool has_selected = selected_count > 0;
        
        set_action_sensitive("Delete", has_selected);
        set_action_sensitive("Restore", has_selected);
        set_common_action_important("CommonEmptyTrash", true);
        
        base.update_actions(selected_count, count);
    }
    
    private void on_trashcan_contents_altered(Gee.Collection<MediaSource>? added,
        Gee.Collection<MediaSource>? removed) {
        if (added != null) {
            foreach (MediaSource source in added)
                get_view().add(new TrashView(source));
        }
        
        if (removed != null) {
            Marker marker = get_view().start_marking();
            foreach (MediaSource source in removed)
                marker.mark(get_view().get_view_for_source(source));
            get_view().remove_marked(marker);
        }
    }
    
    private void on_restore() {
        if (get_view().get_selected_count() == 0)
            return;
        
        get_command_manager().execute(new TrashUntrashPhotosCommand(
            (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources(), false));
    }
    
    protected override string get_view_empty_message() {
        return _("Trash is empty");
    }
    
    private void on_delete() {
        remove_from_app((Gee.Collection<MediaSource>) get_view().get_selected_sources(), _("Delete"), 
            (get_view().get_selected_count() == 1) ? ("Deleting a Photo") : _("Deleting Photos"));
    }
    
    public override SearchViewFilter get_search_view_filter() {
        return search_filter;
    }
}

