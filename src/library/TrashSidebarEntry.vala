/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Library.TrashSidebarEntry : Sidebar.SimplePageEntry, Sidebar.InternalDropTargetEntry {
    
    public TrashSidebarEntry() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.trashcan_contents_altered.connect(on_trashcan_contents_altered);
    }
    
    ~TrashSidebarEntry() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.trashcan_contents_altered.disconnect(on_trashcan_contents_altered);
    }
    
    internal static void init() {
    }
    
    internal static void terminate() {
    }
    
    public override string get_sidebar_name() {
        return TrashPage.NAME;
    }
    
    public override string? get_sidebar_icon() {
        return get_current_icon();
    }
    
    private static string get_current_icon() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all()) {
            if (media_sources.get_trashcan_count() > 0)
                return Resources.ICON_TRASH_FULL;
        }
        
        return Resources.ICON_TRASH_EMPTY;
    }
    
    public bool internal_drop_received(Gee.List<MediaSource> media) {
        AppWindow.get_command_manager().execute(new TrashUntrashPhotosCommand(media, true));
        
        return true;
    }

    public bool internal_drop_received_arbitrary(Gtk.SelectionData data) {
        return false;
    }

    protected override Page create_page() {
        return new TrashPage();
    }
    
    private void on_trashcan_contents_altered() {
        sidebar_icon_changed(get_current_icon());
    }
}


