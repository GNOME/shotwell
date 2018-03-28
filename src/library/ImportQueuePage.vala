/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ImportQueuePage : SinglePhotoPage {
    public const string NAME = _("Importing…");
    
    private Gee.ArrayList<BatchImport> queue = new Gee.ArrayList<BatchImport>();
    private Gee.HashSet<BatchImport> cancel_unallowed = new Gee.HashSet<BatchImport>();
    private BatchImport current_batch = null;
    private Gtk.ProgressBar progress_bar = new Gtk.ProgressBar();
    private bool stopped = false;

#if UNITY_SUPPORT
    UnityProgressBar uniprobar = UnityProgressBar.get_instance();
#endif
    
    public signal void batch_added(BatchImport batch_import);
    
    public signal void batch_removed(BatchImport batch_import);
    
    public ImportQueuePage() {
        base (NAME, false);
        
        // Set up toolbar
        Gtk.Toolbar toolbar = get_toolbar();
        
        // Stop button
        Gtk.ToolButton stop_button = new Gtk.ToolButton(null, null);
        stop_button.set_icon_name("process-stop-symbolic");
        stop_button.set_action_name ("win.Stop");
        
        toolbar.insert(stop_button, -1);

        // separator to force progress bar to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // Progress bar
        Gtk.ToolItem progress_item = new Gtk.ToolItem();
        progress_item.set_expand(true);
        progress_item.add(progress_bar);
        progress_bar.set_show_text(true);
        
        toolbar.insert(progress_item, -1);
#if UNITY_SUPPORT
        //UnityProgressBar: try to draw progress bar
        uniprobar.set_visible(true);
#endif
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        ui_filenames.add("import_queue.ui");
        
        base.init_collect_ui_filenames(ui_filenames);
    }

    private const GLib.ActionEntry[] entries = {
        {"Stop", on_stop }
    };

    protected override void add_actions (GLib.ActionMap map) {
        base.add_actions(map);

        map.add_action_entries(entries, this);
    }

    protected override void remove_actions(GLib.ActionMap map) {
        base.remove_actions(map);
        foreach (var entry in entries) {
            map.remove_action(entry.name);
        }
    }

    public void enqueue_and_schedule(BatchImport batch_import, bool allow_user_cancel) {
        assert(!queue.contains(batch_import));
        
        batch_import.starting.connect(on_starting);
        batch_import.preparing.connect(on_preparing);
        batch_import.progress.connect(on_progress);
        batch_import.imported.connect(on_imported);
        batch_import.import_complete.connect(on_import_complete);
        batch_import.fatal_error.connect(on_fatal_error);
        
        if (!allow_user_cancel)
            cancel_unallowed.add(batch_import);
        
        queue.add(batch_import);
        batch_added(batch_import);
        
        if (queue.size == 1)
            batch_import.schedule();
        
        update_stop_action();
    }
    
    public int get_batch_count() {
        return queue.size;
    }
    
    private void update_stop_action() {
        set_action_sensitive("Stop", !cancel_unallowed.contains(current_batch) && queue.size > 0);
    }
    
    private void on_stop() {
        update_stop_action();
        
        if (queue.size == 0)
            return;
        
        AppWindow.get_instance().set_busy_cursor();
        stopped = true;
        
        // mark all as halted and let each signal failure
        foreach (BatchImport batch_import in queue)
            batch_import.user_halt();
    }
    
    private void on_starting(BatchImport batch_import) {
        update_stop_action();
        current_batch = batch_import;
    }
    
    private void on_preparing() {
        progress_bar.set_text(_("Preparing to import…"));
        progress_bar.pulse();
    }
    
    private void on_progress(uint64 completed_bytes, uint64 total_bytes) {
        double pct = (completed_bytes <= total_bytes) ? (double) completed_bytes / (double) total_bytes
            : 0.0;
        progress_bar.set_fraction(pct);
#if UNITY_SUPPORT
        //UnityProgressBar: set progress
        uniprobar.set_progress(pct);
#endif
    }
    
    private void on_imported(ThumbnailSource source, Gdk.Pixbuf pixbuf, int to_follow) {
        // only interested in updating the display for the last of the bunch
        if (to_follow > 0 || !is_in_view())
            return;
        
        set_pixbuf(pixbuf, Dimensions.for_pixbuf(pixbuf));
        
        // set the singleton collection to this item
        get_view().clear();
        (source is LibraryPhoto) ? get_view().add(new PhotoView(source as LibraryPhoto)) :
            get_view().add(new VideoView(source as Video));
        
        progress_bar.set_ellipsize(Pango.EllipsizeMode.MIDDLE);
        progress_bar.set_text(_("Imported %s").printf(source.get_name()));
    }
    
    private void on_import_complete(BatchImport batch_import, ImportManifest manifest,
        BatchImportRoll import_roll) {
        assert(batch_import == current_batch);
        current_batch = null;
        
        assert(queue.size > 0);
        assert(queue.get(0) == batch_import);
        
        bool removed = queue.remove(batch_import);
        assert(removed);
        
        // fail quietly if cancel was allowed
        cancel_unallowed.remove(batch_import);
        
        // strip signal handlers
        batch_import.starting.disconnect(on_starting);
        batch_import.preparing.disconnect(on_preparing);
        batch_import.progress.disconnect(on_progress);
        batch_import.imported.disconnect(on_imported);
        batch_import.import_complete.disconnect(on_import_complete);
        batch_import.fatal_error.disconnect(on_fatal_error);
        
        // schedule next if available
        if (queue.size > 0) {
            queue.get(0).schedule();
        } else {
            // reset UI
            progress_bar.set_ellipsize(Pango.EllipsizeMode.NONE);
            progress_bar.set_text("");
            progress_bar.set_fraction(0.0);
#if UNITY_SUPPORT
            //UnityProgressBar: reset
            uniprobar.reset();
#endif

            // blank the display
            blank_display();
            
            // reset cursor if cancelled
            if (stopped)
                AppWindow.get_instance().set_normal_cursor();
            
            stopped = false;
        }
        
        update_stop_action();
        
        // report the batch has been removed from the queue after everything else is set
        batch_removed(batch_import);
    }
    
    private void on_fatal_error(ImportResult result, string message) {
        AppWindow.error_message(message);
    }
}

