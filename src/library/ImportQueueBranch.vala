/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Library.ImportQueueBranch : Sidebar.RootOnlyBranch {
    private Library.ImportQueueSidebarEntry entry;
    
    public ImportQueueBranch() {
        // can't pass to base() an object that was allocated in declaration; see
        // https://bugzilla.gnome.org/show_bug.cgi?id=646286
        base (new Library.ImportQueueSidebarEntry());
        
        entry = (Library.ImportQueueSidebarEntry) get_root();
        
        // only attach signals to the page when it's created
        entry.page_created.connect(on_page_created);
        entry.destroying_page.connect(on_destroying_page);
        
        // don't use entry.get_page() or get_queue_page() because (a) we don't want to
        // create the page during initialization, and (b) we know there's no import activity
        // at this moment
        set_show_branch(false);
    }
    
    ~ImportQueueBranch() {
        entry.page_created.disconnect(on_page_created);
        entry.destroying_page.disconnect(on_destroying_page);
    }
    
    public ImportQueuePage get_queue_page() {
        return (ImportQueuePage) entry.get_page();
    }
    
    private void on_page_created() {
        get_queue_page().batch_added.connect(on_batch_added_or_removed);
        get_queue_page().batch_removed.connect(on_batch_added_or_removed);
    }
    
    private void on_destroying_page() {
        get_queue_page().batch_added.disconnect(on_batch_added_or_removed);
        get_queue_page().batch_removed.disconnect(on_batch_added_or_removed);
    }
    
    private void on_batch_added_or_removed() {
        set_show_branch(get_queue_page().get_batch_count() > 0);
    }
    
    public void enqueue_and_schedule(BatchImport batch_import, bool allow_user_cancel) {
        // want to display the branch before passing to the page because this might result in the
        // page being created, and want it all hooked up in the tree prior to creating the page
        set_show_branch(true);
        get_queue_page().enqueue_and_schedule(batch_import, allow_user_cancel);
    }
}

public class Library.ImportQueueSidebarEntry : Sidebar.SimplePageEntry {
    public ImportQueueSidebarEntry() {
    }
    
    public override string get_sidebar_name() {
        return ImportQueuePage.NAME;
    }
    
    public override Icon? get_sidebar_icon() {
        return new ThemedIcon(Resources.ICON_IMPORTING);
    }
    
    protected override Page create_page() {
        return new ImportQueuePage();
    }
}

