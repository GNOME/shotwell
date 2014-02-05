/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Library.Branch : Sidebar.RootOnlyBranch {
    public Branch() {
        base (new Library.SidebarEntry());
    }
    
    public Library.MainPage get_main_page() {
        return (Library.MainPage) ((Library.SidebarEntry) get_root()).get_page();
    }
}

public class Library.SidebarEntry : Sidebar.SimplePageEntry {
    private Icon icon = new ThemedIcon(Resources.ICON_PHOTOS);
    
    public SidebarEntry() {
    }
    
    public override string get_sidebar_name() {
        return Library.MainPage.NAME;
    }
    
    public override Icon? get_sidebar_icon() {
        return icon;
    }
    
    protected override Page create_page() {
        return new Library.MainPage();
    }
}

public class Library.MainPage : CollectionPage {
    public const string NAME = _("Library");
    
    public MainPage(ProgressMonitor? monitor = null) {
        base (NAME);
        
        foreach (MediaSourceCollection sources in MediaCollectionRegistry.get_instance().get_all())
            get_view().monitor_source_collection(sources, new CollectionViewManager(this), null, null, monitor);
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.Facade.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.Facade.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

