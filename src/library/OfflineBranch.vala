/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Library.OfflineBranch : Sidebar.RootOnlyBranch {
    public OfflineBranch() {
        base (new Library.OfflineSidebarEntry());
        
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.offline_contents_altered.connect(on_offline_contents_altered);
        
        set_show_branch(get_total_offline() != 0);
    }
    
    ~OfflineBranch() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.trashcan_contents_altered.disconnect(on_offline_contents_altered);
    }
    
    private void on_offline_contents_altered() {
        set_show_branch(get_total_offline() != 0);
    }
    
    private int get_total_offline() {
        int total = 0;
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            total += media_sources.get_offline_bin_contents().size;
        
        return total;
    }
}

public class Library.OfflineSidebarEntry : Sidebar.SimplePageEntry {
    public OfflineSidebarEntry() {
    }
    
    public override string get_sidebar_name() {
        return OfflinePage.NAME;
    }
    
    public override Icon? get_sidebar_icon() {
        return new ThemedIcon(Resources.ICON_MISSING_FILES);
    }
    
    protected override Page create_page() {
        return new OfflinePage();
    }
}

