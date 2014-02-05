/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Library.TrashBranch : Sidebar.RootOnlyBranch {
    public TrashBranch() {
        base (new Library.TrashSidebarEntry());
    }
}

public class Library.TrashSidebarEntry : Sidebar.SimplePageEntry, Sidebar.InternalDropTargetEntry {
    private static Icon? full_icon = null;
    private static Icon? empty_icon = null;
    
    public TrashSidebarEntry() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.trashcan_contents_altered.connect(on_trashcan_contents_altered);
    }
    
    ~TrashSidebarEntry() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.trashcan_contents_altered.disconnect(on_trashcan_contents_altered);
    }
    
    internal static void init() {
        full_icon = new ThemedIcon(Resources.ICON_TRASH_FULL);
        empty_icon = new ThemedIcon(Resources.ICON_TRASH_EMPTY);
    }
    
    internal static void terminate() {
        full_icon = null;
        empty_icon = null;
    }
    
    public override string get_sidebar_name() {
        return TrashPage.NAME;
    }
    
    public override Icon? get_sidebar_icon() {
        return get_current_icon();
    }
    
    private static Icon get_current_icon() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all()) {
            if (media_sources.get_trashcan_count() > 0)
                return full_icon;
        }
        
        return empty_icon;
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


