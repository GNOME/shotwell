/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Library.OfflineSidebarEntry : Library.HideablePageEntry {
    public OfflineSidebarEntry() {
        
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.offline_contents_altered.connect(on_offline_contents_altered);
        
        visible = (get_total_offline() != 0);
    }

    ~OfflineSidebarEntry() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.trashcan_contents_altered.disconnect(on_offline_contents_altered);
    }
    
    private void on_offline_contents_altered() {
        visible = (get_total_offline() != 0);
    }
    
    private int get_total_offline() {
        int total = 0;
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            total += media_sources.get_offline_bin_contents().size;
        
        return total;
    }
    
    public override string get_sidebar_name() {
        return OfflinePage.NAME;
    }
    
    public override string? get_sidebar_icon() {
        return Resources.ICON_MISSING_FILES;
    }
    
    protected override Page create_page() {
        return new OfflinePage();
    }
}

