/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

//
// LibraryMonitor uses DirectoryMonitor to track assets in the user's library directory and make
// sure they're reflected in the application.
//
// NOTE: There appears to be a bug where prior versions of Shotwell (<= 0.6.x) were not
// properly loading the file modification timestamp during import.  This was no issue
// before but becomes imperative now with file monitoring.  A "proper" algorithm is
// to reimport an entire photo if the modification time in the database is different
// than the file's, but that's Real Bad when the user first turns on monitoring, as it
// will cause a lot of reimports (think of a 10,000 photo database) and will blow away
// ALL transformations, as they are now suspect.
//
// So: If the modification time is zero and filesize is the same, simply update the
// timestamp in the database and move on.
//
// TODO: Although it seems highly unlikely that a file's timestamp could change but the file size
// has not and the file really be "changed", it *is* possible, even in the case of complex little
// animals like photo files.  We could be more liberal and treat this case as a metadata-changed
// situation (since that's a likely case).
//

public class LibraryMonitorPool {
    private static LibraryMonitorPool? instance = null;
    
    private LibraryMonitor? monitor = null;
    private uint timer_id = 0;
    
    public signal void monitor_installed(LibraryMonitor monitor);
    
    public signal void monitor_destroyed(LibraryMonitor monitor);
    
    private LibraryMonitorPool() {
    }
    
    public static void init() {
    }
    
    public static void terminate() {
        if (instance != null)
            instance.close();
        
        instance = null;
    }
    
    public static LibraryMonitorPool get_instance() {
        if (instance == null)
            instance = new LibraryMonitorPool();
        
        return instance;
    }
    
    public LibraryMonitor? get_monitor() {
        return monitor;
    }
    
    // This closes and destroys the old monitor, if any, and replaces it with the new one.
    public void replace(LibraryMonitor replacement, int start_msec_delay = 0) {
        close();
        
        monitor = replacement;
        if (start_msec_delay > 0 && timer_id == 0)
            timer_id = Timeout.add(start_msec_delay, on_start_monitor);
        
        monitor_installed(monitor);
    }
    
    private void close() {
        if (monitor == null)
            return;
        
        monitor.close();
        LibraryMonitor closed = monitor;
        monitor = null;
        
        monitor_destroyed(closed);
    }
    
    private bool on_start_monitor() {
        // can set to zero because this function always returns false
        timer_id = 0;
        
        if (monitor == null)
            return false;
        
        monitor.start_discovery();
        
        return false;
    }
}

public class LibraryMonitor : DirectoryMonitor {
    private const int FLUSH_IMPORT_QUEUE_SEC = 3;
    private const int IMPORT_ROLL_QUIET_SEC = 5 * 60;
    private const int MIN_BLACKLIST_DURATION_MSEC = 5 * 1000;
    private const int MAX_VERIFY_EXISTING_MEDIA_JOBS = 5;
    
    private class FindMoveJob : BackgroundJob {
        public File file;
        public Gee.Collection<Monitorable> candidates;
        public Monitorable? match = null;
        public Gee.ArrayList<Monitorable>? losers = null;
        public Error? err = null;
        
        public FindMoveJob(LibraryMonitor owner, File file, Gee.Collection<Monitorable> candidates) {
            base (owner, owner.on_find_move_completed, owner.cancellable, owner.on_find_move_cancelled);
            
            this.file = file;
            this.candidates = candidates;
            
            set_completion_priority(Priority.LOW);
        }
        
        public override void execute() {
            // weed out any candidates that already have a backing master
            Gee.Iterator<Monitorable> iter = candidates.iterator();
            while (iter.next()) {
                if (iter.get().get_master_file().query_exists())
                    iter.remove();
            }
            
            // if no more, done
            if (candidates.size == 0)
                return;
            
            string? md5 = null;
            try {
                md5 = md5_file(file);
            } catch (Error err) {
                this.err = err;
                
                return;
            }
            
            foreach (Monitorable candidate in candidates) {
                if (candidate.get_master_md5() != md5)
                    continue;
                
                if (match != null) {
                    warning("Found more than one media match for %s: %s and %s", file.get_path(),
                        match.to_string(), candidate.to_string());
                    
                    if (losers == null)
                        losers = new Gee.ArrayList<Monitorable>();
                    
                    losers.add(candidate);
                    
                    continue;
                }
                
                match = candidate;
            }
        }
    }
    
    private class RuntimeFindMoveJob : BackgroundJob {
        public File file;
        public Gee.Collection<Monitorable> candidates;
        public Monitorable? match = null;
        public Error? err = null;
        
        public RuntimeFindMoveJob(LibraryMonitor owner, File file, Gee.Collection<Monitorable> candidates) {
            base (owner, owner.on_runtime_find_move_completed, owner.cancellable);
            
            this.file = file;
            this.candidates = candidates;
            
            set_completion_priority(Priority.LOW);
        }
        
        public override void execute() {
            string? md5 = null;
            try {
                md5 = md5_file(file);
            } catch (Error err) {
                this.err = err;
                
                return;
            }
            
            foreach (Monitorable candidate in candidates) {
                if (candidate.get_master_md5() == md5) {
                    match = candidate;
                    
                    break;
                }
            }
        }
    }
    
    private class VerifyJob {
        public Monitorable monitorable;
        public MediaMonitor monitor;
        
        public VerifyJob(Monitorable monitorable, MediaMonitor monitor) {
            this.monitorable = monitorable;
            this.monitor = monitor;
        }
    }
    
    private static Gee.HashSet<File> blacklist = new Gee.HashSet<File>(file_hash, file_equal);
    private static HashTimedQueue<File> to_unblacklist = new HashTimedQueue<File>(
        MIN_BLACKLIST_DURATION_MSEC, on_unblacklist_file, file_hash, file_equal, Priority.LOW);
    
    private Workers workers = new Workers(Workers.thread_per_cpu_minus_one(), false);
    private Cancellable cancellable = new Cancellable();
    private bool auto_import = false;
    private Gee.HashSet<File> unknown_files = null;
    private Gee.List<MediaMonitor> monitors = new Gee.ArrayList<MediaMonitor>();
    private Gee.HashMap<MediaMonitor, Gee.Set<Monitorable>> discovered = null;
    private Gee.HashSet<File> import_queue = new Gee.HashSet<File>(file_hash, file_equal);
    private Gee.HashSet<File> pending_imports = new Gee.HashSet<File>(file_hash, file_equal);
    private Gee.ArrayList<BatchImport> batch_import_queue = new Gee.ArrayList<BatchImport>();
    private BatchImportRoll current_import_roll = null;
    private time_t last_import_roll_use = 0;
    private BatchImport current_batch_import = null;
    private int checksums_completed = 0;
    private int checksums_total = 0;
    private uint import_queue_timer_id = 0;
    private Gee.Queue<VerifyJob> verify_queue = new Gee.LinkedList<VerifyJob>();
    private int outstanding_verify_jobs = 0;
    private int completed_monitorable_verifies = 0;
    private int total_monitorable_verifies = 0;
    
    public signal void auto_update_progress(int completed_files, int total_files);
    
    public signal void auto_import_preparing();
    
    public signal void auto_import_progress(uint64 completed_bytes, uint64 total_bytes);
    
    public LibraryMonitor(File root, bool recurse, bool monitoring) {
        base (root, recurse, monitoring);
        
        // synchronize with configuration system
        auto_import = Config.Facade.get_instance().get_auto_import_from_library();
        Config.Facade.get_instance().auto_import_from_library_changed.connect(on_config_changed);
        
        import_queue_timer_id = Timeout.add_seconds(FLUSH_IMPORT_QUEUE_SEC, on_flush_import_queue);
    }
    
    ~LibraryMonitor() {
        Config.Facade.get_instance().auto_import_from_library_changed.disconnect(on_config_changed);
    }
    
    public override void close() {
        cancellable.cancel();
        
        foreach (MediaMonitor monitor in monitors)
            monitor.close();
        
        if (import_queue_timer_id != 0) {
            Source.remove(import_queue_timer_id);
            import_queue_timer_id = 0;
        }
        
        base.close();
    }
    
    private void add_to_discovered_list(MediaMonitor monitor, Monitorable monitorable) {
        if (!discovered.has_key(monitor))
            discovered.set(monitor, new Gee.HashSet<Monitorable>());
        
        discovered.get(monitor).add(monitorable);
    }
    
    private MediaMonitor get_monitor_for_monitorable(Monitorable monitorable) {
        foreach (MediaMonitor monitor in monitors) {
            if (monitor.get_media_source_collection().holds_type_of_source(monitorable))
                return monitor;
        }
        
        error("Unable to locate MediaMonitor for %s", monitorable.to_string());
    }
    
    public override void discovery_started() {
        foreach (MediaSourceCollection collection in MediaCollectionRegistry.get_instance().get_all())
            monitors.add(collection.create_media_monitor(workers, cancellable));
        
        foreach (MediaMonitor monitor in monitors)
            monitor.notify_discovery_started();
        
        discovered = new Gee.HashMap<MediaMonitor, Gee.Set<Monitorable>>();
        unknown_files = new Gee.HashSet<File>(file_hash, file_equal);
        
        base.discovery_started();
    }
    
    public override void file_discovered(File file, FileInfo info) {
        Monitorable? representation = null;
        MediaMonitor representing = null;
        bool ignore = false;
        foreach (MediaMonitor monitor in monitors) {
            MediaMonitor.DiscoveredFile result = monitor.notify_file_discovered(file, info,
                out representation);
            if (result == MediaMonitor.DiscoveredFile.REPRESENTED) {
                representing = monitor;
                
                break;
            } else if (result == MediaMonitor.DiscoveredFile.IGNORE) {
                // known but not to be worried about (for purposes of discovery)
                ignore = true;
                
                break;
            }
        }
        
        if (representing != null) {
            assert(representation != null && !ignore);
            add_to_discovered_list(representing, representation);
        } else if (!ignore && !Tombstone.global.matches(file) && is_supported_filetype(file)) {
            unknown_files.add(file);
        }
        
        base.file_discovered(file, info);
    }
    
    public override void discovery_completed() {
        async_discovery_completed.begin();
    }
    
    private async void async_discovery_completed() {
        // before marking anything online/offline, reimporting changed files, or auto-importing new
        // files, want to see if the unknown files are actually renamed files.  Do this by examining
        // their FileInfo and calculating their MD5 in the background ... when all this is sorted
        // out, then go on and finish the other tasks
        if (unknown_files.size == 0) {
            discovery_stage_completed();
            
            return;
        }
        
        Gee.ArrayList<Monitorable> all_candidates = new Gee.ArrayList<Monitorable>();
        Gee.ArrayList<File> adopted = new Gee.ArrayList<File>(file_equal);
        foreach (File file in unknown_files) {
            FileInfo? info = get_file_info(file);
            if (info == null)
                continue;
            
            // clear before using (reused as accumulator)
            all_candidates.clear();
            
            Gee.Collection<Monitorable>? candidates = null;
            bool associated = false;
            foreach (MediaMonitor monitor in monitors) {
                MediaMonitor.DiscoveredFile result;
                candidates = monitor.candidates_for_unknown_file(file, info, out result);
                if (result == MediaMonitor.DiscoveredFile.REPRESENTED
                    || result == MediaMonitor.DiscoveredFile.IGNORE) {
                    associated = true;
                    
                    break;
                } else if (candidates != null) {
                    all_candidates.add_all(candidates);
                }
            }
            
            if (associated) {
                adopted.add(file);
                
                continue;
            }
            
            // verify the matches with an MD5 comparison
            if (all_candidates.size > 0) {
                // copy for background thread
                Gee.ArrayList<Monitorable> job_candidates = all_candidates;
                all_candidates = new Gee.ArrayList<Monitorable>();
                
                checksums_total++;
                workers.enqueue(new FindMoveJob(this, file, job_candidates));
            }
            
            Idle.add(async_discovery_completed.callback);
            yield;
        }
        
        // remove all adopted files from the unknown list
        unknown_files.remove_all(adopted);
        
        checksums_completed = 0;
        
        if (checksums_total == 0) {
            discovery_stage_completed();
        } else {
            mdbg("%d checksum jobs initiated to verify unknown photo files".printf(checksums_total));
            auto_update_progress(checksums_completed, checksums_total);
        }
    }
    
    private void report_checksum_job_completed() {
        assert(checksums_completed < checksums_total);
        checksums_completed++;
        
        auto_update_progress(checksums_completed, checksums_total);
        
        if (checksums_completed == checksums_total)
            discovery_stage_completed();
    }
    
    private void on_find_move_completed(BackgroundJob j) {
        FindMoveJob job = (FindMoveJob) j;
        
        // if match was found, give file to the media and removed from both the unknown list and
        // add to the discovered list ... do NOT mark losers as offline as other jobs may discover
        // files that belong to them; discovery_stage_completed() will work this out in the end
        if (job.match != null) {
            mdbg("Found moved master file: %s matches %s".printf(job.file.get_path(),
                job.match.to_string()));
            
            MediaMonitor monitor = get_monitor_for_monitorable(job.match);
            monitor.update_master_file(job.match, job.file);
            unknown_files.remove(job.file);
            add_to_discovered_list(monitor, job.match);
        }
        
        if (job.err != null)
            warning("Unable to checksum unknown media file %s: %s", job.file.get_path(), job.err.message);
        
        report_checksum_job_completed();
    }
    
    private void on_find_move_cancelled(BackgroundJob j) {
        report_checksum_job_completed();
    }
    
    private void discovery_stage_completed() {
        foreach (MediaMonitor monitor in monitors) {
            Gee.Set<Monitorable>? monitorables = discovered.get(monitor);
            if (monitorables != null) {
                foreach (Monitorable monitorable in monitorables)
                    enqueue_verify_monitorable(monitorable, monitor);
            }
            
            foreach (DataObject object in monitor.get_media_source_collection().get_all()) {
                Monitorable monitorable = (Monitorable) object;
                
                if (monitorables != null && monitorables.contains(monitorable))
                    continue;
                
                enqueue_verify_monitorable(monitorable, monitor);
            }
            
            foreach (DataSource source in 
                monitor.get_media_source_collection().get_offline_bin().get_all()) {
                Monitorable monitorable = (Monitorable) source;
                
                if (monitorables != null && monitorables.contains(monitorable))
                    continue;
                
                enqueue_verify_monitorable(monitorable, monitor);
            }
        }
        
        // enqueue all remaining unknown photo files for import
        if (auto_import)
            enqueue_import_many(unknown_files);
        
        // release refs
        discovered = null;
        unknown_files = null;
        
        // Now that the discovery is completed, launch a scan of the tombstoned files and see if
        // they can be resurrected
        Tombstone.global.launch_scan(this, cancellable);
        
        // Only report discovery completed here, after all the other background work is done
        base.discovery_completed();
    }
    
    private void enqueue_verify_monitorable(Monitorable monitorable, MediaMonitor monitor) {
        bool offered = verify_queue.offer(new VerifyJob(monitorable, monitor));
        assert(offered);
        
        execute_next_verify_job();
    }
    
    private void execute_next_verify_job() {
        if (outstanding_verify_jobs >= MAX_VERIFY_EXISTING_MEDIA_JOBS || verify_queue.size == 0)
            return;
        
        VerifyJob? job = verify_queue.poll();
        assert(job != null);
        
        outstanding_verify_jobs++;
        verify_monitorable.begin(job.monitorable, job.monitor);
    }
    
    private async void verify_monitorable(Monitorable monitorable, MediaMonitor monitor) {
        File[] files = new File[1];
        files[0] = monitor.get_master_file(monitorable);
        
        File[]? aux_files = monitor.get_auxilliary_backing_files(monitorable);
        if (aux_files != null) {
            foreach (File aux_file in aux_files)
                files += aux_file;
        }
        
        for (int ctr = 0; ctr < files.length; ctr++) {
            File file = files[ctr];
            
            FileInfo? info = get_file_info(file);
            if (info == null) {
                try {
                    info = yield file.query_info_async(SUPPLIED_ATTRIBUTES, FILE_INFO_FLAGS,
                        DEFAULT_PRIORITY, cancellable);
                } catch (Error err) {
                    // ignore, this happens when file is not found
                }
            }
            
            // if master file, control online/offline state
            if (ctr == 0) {
                if (info != null && monitor.is_offline(monitorable))
                    monitor.update_online(monitorable);
                else if (info == null && !monitor.is_offline(monitorable))
                    monitor.update_offline(monitorable);
            }
            
            monitor.update_backing_file_info(monitorable, file, info);
        }
        
        completed_monitorable_verifies++;
        auto_update_progress(completed_monitorable_verifies, total_monitorable_verifies);
        
        Idle.add(verify_monitorable.callback, DEFAULT_PRIORITY);
        yield;
        
        // finished, move on to the next job in the queue
        assert(outstanding_verify_jobs > 0);
        outstanding_verify_jobs--;
        
        execute_next_verify_job();
    }
    
    private void on_config_changed() {
        bool value = Config.Facade.get_instance().get_auto_import_from_library();
        
        if (auto_import == value)
            return;
        
        auto_import = value;
        if (auto_import) {
            if (!CommandlineOptions.no_runtime_monitoring)
                import_unrepresented_files();
        } else {
            cancel_batch_imports();
        }
    }
    
    private void enqueue_import(File file) {
        if (!pending_imports.contains(file) && is_supported_filetype(file) && !is_blacklisted(file))
            import_queue.add(file);
    }
    
    private void enqueue_import_many(Gee.Collection<File> files) {
        foreach (File file in files)
            enqueue_import(file);
    }
    
    private void remove_queued_import(File file) {
        import_queue.remove(file);
    }
    
    private bool on_flush_import_queue() {
        if (cancellable.is_cancelled())
            return false;
        
        if (import_queue.size == 0)
            return true;
        
        // if currently importing, wait for it to finish before starting next one; this maximizes
        // the number of items submitted each time
        if (current_batch_import != null)
            return true;
        
        mdbg("Auto-importing %d files".printf(import_queue.size));
        
        // If no import roll, or it's been over IMPORT_ROLL_QUIET_SEC since using the last one,
        // create a new one.  This allows for multiple files to come in back-to-back and be
        // imported on the same roll.
        time_t now = (time_t) now_sec();
        if (current_import_roll == null || (now - last_import_roll_use) >= IMPORT_ROLL_QUIET_SEC)
            current_import_roll = new BatchImportRoll();
        last_import_roll_use = now;
        
        Gee.ArrayList<BatchImportJob> jobs = new Gee.ArrayList<BatchImportJob>();
        foreach (File file in import_queue) {
            if (is_blacklisted(file))
                continue;
            
            jobs.add(new FileImportJob(file, false, true));
            pending_imports.add(file);
        }
        
        import_queue.clear();
        
        BatchImport importer = new BatchImport(jobs, "LibraryMonitor autoimport",
            null, null, null, null, current_import_roll);
        importer.set_untrash_duplicates(false);
        importer.set_mark_duplicates_online(false);
        batch_import_queue.add(importer);
        
        schedule_next_batch_import();
        
        return true;
    }
    
    private void schedule_next_batch_import() {
        if (current_batch_import != null || batch_import_queue.size == 0)
            return;
        
        current_batch_import = batch_import_queue[0];
        current_batch_import.preparing.connect(on_import_preparing);
        current_batch_import.progress.connect(on_import_progress);
        current_batch_import.import_complete.connect(on_import_complete);
        current_batch_import.schedule();
    }
    
    private void discard_current_batch_import() {
        assert(current_batch_import != null);
        
        bool removed = batch_import_queue.remove(current_batch_import);
        assert(removed);
        current_batch_import.preparing.disconnect(on_import_preparing);
        current_batch_import.progress.disconnect(on_import_progress);
        current_batch_import.import_complete.disconnect(on_import_complete);
        current_batch_import = null;
        
        // a "proper" way to do this would be a complex data structure that stores the association
        // of every file to its BatchImport and removes it from the pending_imports Set when
        // the BatchImport completes, cancelled or not (the removal using manifest.all in
        // on_import_completed doesn't catch files not imported due to cancellation) ... but, since
        // individual BatchImports can't be cancelled, only all of them, this works
        if (batch_import_queue.size == 0)
            pending_imports.clear();
    }
    
    private void cancel_batch_imports() {
        // clear everything queued up (that is not the current batch import)
        int ctr = 0;
        while (ctr < batch_import_queue.size) {
            if (batch_import_queue[ctr] == current_batch_import) {
                ctr++;
                
                continue;
            }
            
            batch_import_queue.remove(batch_import_queue[ctr]);
        }
        
        // cancel the current import and remove it when the completion is called
        if (current_batch_import != null)
            current_batch_import.user_halt();
        
        // remove all pending so if a new import comes in, it won't be skipped
        pending_imports.clear();
    }
    
    private void on_import_preparing() {
        auto_import_preparing();
    }
    
    private void on_import_progress(uint64 completed_bytes, uint64 total_bytes) {
        auto_import_progress(completed_bytes, total_bytes);
    }
    
    private void on_import_complete(BatchImport batch_import, ImportManifest manifest,
        BatchImportRoll import_roll) {
        assert(batch_import == current_batch_import);
        
        mdbg("auto-import batch completed %d".printf(manifest.all.size));
        auto_import_progress(0, 0);
        
        foreach (BatchImportResult result in manifest.all) {
            // don't verify the pending_imports file is removed, it can be removed if the import
            // was cancelled
            if (result.file != null)
                pending_imports.remove(result.file);
        }
        
        if (manifest.already_imported.size > 0) {
            Gee.ArrayList<TombstonedFile> to_tombstone = new Gee.ArrayList<TombstonedFile>();
            foreach (BatchImportResult result in manifest.already_imported) {
                FileInfo? info = get_file_info(result.file);
                if (info == null) {
                    warning("Unable to get info for duplicate file %s", result.file.get_path());
                    
                    continue;
                }
                
                to_tombstone.add(new TombstonedFile(result.file, info.get_size(), null));
            }
            
            try {
                Tombstone.entomb_many_files(to_tombstone, Tombstone.Reason.AUTO_DETECTED_DUPLICATE);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
        }
        
        mdbg("%d files remain pending for auto-import".printf(pending_imports.size));
        
        discard_current_batch_import();
        schedule_next_batch_import();
    }
    
    //
    // Real-time monitoring & auto-import
    //
    
    // USE WITH CARE.  Because changes to the photo's state will not be updated as its backing
    // file(s) change, it's possible for the library to diverge with what's on disk while the
    // media source is blacklisted.  If the media source is removed from the blacklist and
    // unexpected state changes occur (such as file-altered being detected but not the file-create),
    // the change will either be dropped on the floor or the state of the library will be
    // indeterminate.
    //
    // Use of this method should be avoided at all costs (otherwise the point of the real-time
    // monitor is negated).
    public static void blacklist_file(File file, string reason) {
        mdbg("[%s] Blacklisting %s".printf(reason, file.get_path()));
        lock (blacklist) {
            blacklist.add(file);
        }
    }
    
    public static void unblacklist_file(File file) {
        // don't want to immediately remove the blacklisted file because the monitoring events
        // can come in much later
        lock (blacklist) {
            if (blacklist.contains(file) && !to_unblacklist.contains(file))
                to_unblacklist.enqueue(file);
        }
    }
    
    private static void on_unblacklist_file(File file) {
        bool removed;
        lock (blacklist) {
            removed = blacklist.remove(file);
        }
        
        if (removed)
            mdbg("Blacklist for %s removed".printf(file.get_path()));
        else
            warning("File %s was not blacklisted but unblacklisted", file.get_path());
    }
    
    public static bool is_blacklisted(File file) {
        lock (blacklist) {
            return blacklist.contains(file);
        }
    }
    
    private bool is_supported_filetype(File file) {
        return MediaCollectionRegistry.get_instance().get_collection_for_file(file) != null;
    }
    
    // NOTE: This only works when runtime monitoring is enabled.  Otherwise, DirectoryMonitor will
    // not be tracking files.
    private void import_unrepresented_files() {
        if (!auto_import)
            return;
        
        Gee.ArrayList<File> to_import = null;
        foreach (File file in get_files()) {
            FileInfo? info = get_file_info(file);
            if (info == null || info.get_file_type() != FileType.REGULAR)
                continue;
            
            if (pending_imports.contains(file))
                continue;
            
            if (Tombstone.global.matches(file))
                continue;
            
            bool represented = false;
            foreach (MediaMonitor monitor in monitors) {
                if (monitor.is_file_represented(file)) {
                    represented = true;
                    
                    break;
                }
            }
            
            if (represented)
                continue;
            
            if (!is_supported_filetype(file))
                continue;
            
            if (to_import == null)
                to_import = new Gee.ArrayList<File>(file_equal);
            
            to_import.add(file);
        }
        
        if (to_import != null)
            enqueue_import_many(to_import);
    }
    
    // It's possible for the monitor to miss a file create but report other activities, which we
    // can use to pick up new files
    private void runtime_unknown_file_discovered(File file) {
        if (auto_import && is_supported_filetype(file) && !Tombstone.global.matches(file)) {
            mdbg("Unknown file %s discovered, enqueuing for import".printf(file.get_path()));
            enqueue_import(file);
        }
    }
    
    protected override void notify_file_created(File file, FileInfo info) {
        if (is_blacklisted(file)) {
            base.notify_file_created(file, info);
            
            return;
        }
        
        bool known = false;
        foreach (MediaMonitor monitor in monitors) {
            if (monitor.notify_file_created(file, info)) {
                known = true;
                
                break;
            }
        }
        
        if (!known) {
            // attempt to match the new file with a Monitorable that is offline
            Gee.HashSet<Monitorable> all_candidates = null;
            foreach (MediaMonitor monitor in monitors) {
                MediaMonitor.DiscoveredFile result;
                Gee.Collection<Monitorable>? candidates = monitor.candidates_for_unknown_file(file,
                    info, out result);
                if (result == MediaMonitor.DiscoveredFile.REPRESENTED ||
                    result == MediaMonitor.DiscoveredFile.IGNORE) {
                    mdbg("%s %s created file %s".printf(monitor.to_string(), result.to_string(),
                        file.get_path()));
                    
                    known = true;
                    
                    break;
                } else if (candidates != null && candidates.size > 0) {
                    mdbg("%s suggests %d candidates for created file %s".printf(monitor.to_string(),
                        candidates.size, file.get_path()));
                    
                    if (all_candidates == null)
                        all_candidates = new Gee.HashSet<Monitorable>();
                    
                    foreach (Monitorable candidate in candidates) {
                        if (monitor.is_offline(candidate))
                            all_candidates.add(candidate);
                    }
                }
            }
            
            if (!known && all_candidates != null && all_candidates.size > 0) {
                mdbg("%d candidates for created file %s being checksummed".printf(all_candidates.size,
                    file.get_path()));
                
                workers.enqueue(new RuntimeFindMoveJob(this, file, all_candidates));
                // mark as known to avoid adding file for possible import
                known = true;
            }
        }
        
        if (!known)
            runtime_unknown_file_discovered(file);
        
        base.notify_file_created(file, info);
    }
    
    private void on_runtime_find_move_completed(BackgroundJob j) {
        RuntimeFindMoveJob job = (RuntimeFindMoveJob) j;
        
        if (job.err != null) {
            critical("Error attempting to find a match at runtime for %s: %s", job.file.get_path(),
                job.err.message);
        }
        
        if (job.match != null) {
            MediaMonitor monitor = get_monitor_for_monitorable(job.match);
            monitor.update_master_file(job.match, job.file);
            monitor.update_online(job.match);
        } else {
            // no match found, mark file for possible import
            runtime_unknown_file_discovered(job.file);
        }
    }
    
    protected override void notify_file_moved(File old_file, File new_file, FileInfo new_info) {
        if (is_blacklisted(old_file) || is_blacklisted(new_file)) {
            base.notify_file_moved(old_file, new_file, new_info);
            
            return;
        }
        
        bool known = false;
        foreach (MediaMonitor monitor in monitors) {
            if (monitor.notify_file_moved(old_file, new_file, new_info)) {
                known = true;
                
                break;
            }
        }
        
        if (!known)
            runtime_unknown_file_discovered(new_file);
        
        base.notify_file_moved(old_file, new_file, new_info);
    }
    
    protected override void notify_file_altered(File file) {
        if (is_blacklisted(file)) {
            base.notify_file_altered(file);
            
            return;
        }
        
        bool known = false;
        foreach (MediaMonitor monitor in monitors) {
            if (monitor.notify_file_altered(file)) {
                known = true;
                
                break;
            }
        }
        
        if (!known)
            runtime_unknown_file_discovered(file);
        
        base.notify_file_altered(file);
    }
    
    protected override void notify_file_attributes_altered(File file) {
        if (is_blacklisted(file)) {
            base.notify_file_attributes_altered(file);
            
            return;
        }
        
        bool known = false;
        foreach (MediaMonitor monitor in monitors) {
            if (monitor.notify_file_attributes_altered(file)) {
                known = true;
                
                break;
            }
        }
        
        if (!known)
            runtime_unknown_file_discovered(file);
        
        base.notify_file_attributes_altered(file);
    }
    
    protected override void notify_file_alteration_completed(File file, FileInfo info) {
        if (is_blacklisted(file)) {
            base.notify_file_alteration_completed(file, info);
            
            return;
        }
        
        bool known = false;
        foreach (MediaMonitor monitor in monitors) {
            if (monitor.notify_file_alteration_completed(file, info)) {
                known = true;
                
                break;
            }
        }
        
        if (!known)
            runtime_unknown_file_discovered(file);
        
        base.notify_file_alteration_completed(file, info);
    }
    
    protected override void notify_file_deleted(File file) {
        if (is_blacklisted(file)) {
            base.notify_file_deleted(file);
            
            return;
        }
        
        bool known = false;
        foreach (MediaMonitor monitor in monitors) {
            if (monitor.notify_file_deleted(file)) {
                known = true;
                
                break;
            }
        }
        
        if (!known) {
            // ressurrect tombstone if deleted
            Tombstone? tombstone = Tombstone.global.locate(file);
            if (tombstone != null) {
                debug("Resurrecting tombstoned file %s", file.get_path());
                Tombstone.global.resurrect(tombstone);
            }
            
            // remove from import queue
            remove_queued_import(file);
        }
        
        base.notify_file_deleted(file);
    }
}

