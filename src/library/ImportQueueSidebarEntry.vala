/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Library.ImportQueueSidebarEntry : Library.HideablePageEntry {
    public ImportQueueSidebarEntry() {
        // only attach signals to the page when it's created
        page_created.connect(on_page_created);
        destroying_page.connect(on_destroying_page);
        
        // don't use entry.get_page() or get_queue_page() because (a) we don't want to
        // create the page during initialization, and (b) we know there's no import activity
        // at this moment
        visible = false;
    }
    
    public override string get_sidebar_name() {
        return ImportQueuePage.NAME;
    }
    
    public override string? get_sidebar_icon() {
        return Resources.ICON_IMPORTING;
    }
    
    protected override Page create_page() {
        return new ImportQueuePage();
    }

    private ImportQueuePage get_queue_page() {
        return get_page() as ImportQueuePage;
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
        visible = (get_queue_page().get_batch_count() > 0);
    }
    
    public void enqueue_and_schedule(BatchImport batch_import, bool allow_user_cancel) {
        // want to display the branch before passing to the page because this might result in the
        // page being created, and want it all hooked up in the tree prior to creating the page
        visible = true;
        get_queue_page().enqueue_and_schedule(batch_import, allow_user_cancel);
    }
}

