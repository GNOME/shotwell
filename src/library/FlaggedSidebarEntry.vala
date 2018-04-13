/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Library.FlaggedSidebarEntry : Library.HideablePageEntry, Sidebar.InternalDropTargetEntry {
    public FlaggedSidebarEntry() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.flagged_contents_altered.connect(on_flagged_contents_altered);
        
        visible = (get_total_flagged() != 0);
    }
    
    ~FlaggedSidebarEntry() {
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            media_sources.flagged_contents_altered.disconnect(on_flagged_contents_altered);
    } 
       
    public override string get_sidebar_name() {
        return FlaggedPage.NAME;
    }
    
    public override string? get_sidebar_icon() {
        return "filter-flagged-symbolic";
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

    private void on_flagged_contents_altered() {
        visible = (get_total_flagged() != 0);
    }
    
    private int get_total_flagged() {
        int total = 0;
        foreach (MediaSourceCollection media_sources in MediaCollectionRegistry.get_instance().get_all())
            total += media_sources.get_flagged().size;
        
        return total;
    }
}

