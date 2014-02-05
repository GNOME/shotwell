/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Library.FlaggedBranch : Sidebar.RootOnlyBranch {
    public FlaggedBranch() {
        base (new Library.FlaggedSidebarEntry());
        
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.flagged_contents_altered.connect(on_flagged_contents_altered);
        
        set_show_branch(get_total_flagged() != 0);
    }
    
    ~FlaggedBranch() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.flagged_contents_altered.disconnect(on_flagged_contents_altered);
    }
    
    private void on_flagged_contents_altered() {
        set_show_branch(get_total_flagged() != 0);
    }
    
    private int get_total_flagged() {
        int total = 0;
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            total += media_sources.get_flagged().size;
        
        return total;
    }
}

public class Library.FlaggedSidebarEntry : Sidebar.SimplePageEntry, Sidebar.InternalDropTargetEntry {
    public FlaggedSidebarEntry() {
    }
    
    public override string get_sidebar_name() {
        return FlaggedPage.NAME;
    }
    
    public override Icon? get_sidebar_icon() {
        return new ThemedIcon(Resources.ICON_FLAGGED_PAGE);
    }
    
    protected override Page create_page() {
        return new FlaggedPage();
    }
    
    public bool internal_drop_received(Gee.List<MediaSource> media) {
        AppWindow.get_command_manager().execute(new FlagUnflagCommand(media, true));
        
        return true;
    }
    
    public bool internal_drop_received_arbitrary(Gtk.SelectionData data) {
        return false;
    }
}

