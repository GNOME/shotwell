/* Copyright 2009-2010 Yorba Foundation
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
// NOTE: Current implementation is only to check all photos at initialization, with no auto-import
// and no realtime monitoring (http://trac.yorba.org/ticket/2302).  Auto-import and realtime
// monitoring will be added later.
//

public class LibraryMonitor : DirectoryMonitor {
    private const int IMPORT_ROLL_QUIET_SEC = 5 * 60;
    
    private class ReimportMasterJob : BackgroundJob {
        public LibraryPhoto photo;
        public Photo.ReimportMasterState reimport_state = null;
        public bool mark_online = false;
        public Error err = null;
        
        public ReimportMasterJob(LibraryMonitor owner, LibraryPhoto photo) {
            base (owner, owner.on_master_reimported, new Cancellable(),
                owner.on_master_reimport_cancelled);
            
            this.photo = photo;
        }
        
        public override void execute() {
            try {
                mark_online = photo.prepare_for_reimport_master(out reimport_state);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private class ReimportEditableJob : BackgroundJob {
        public LibraryPhoto photo;
        public Photo.ReimportEditableState state = null;
        public bool success = false;
        public Error err = null;
        
        public ReimportEditableJob(LibraryMonitor owner, LibraryPhoto photo) {
            base (owner, owner.on_editable_reimported, new Cancellable(),
                owner.on_editable_reimport_cancelled);
            
            this.photo = photo;
        }
        
        public override void execute() {
            try {
                success = photo.prepare_for_reimport_editable(out state);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private class FindMoveJob : BackgroundJob {
        public File file;
        public Gee.Collection<LibraryPhoto> candidates;
        public LibraryPhoto? match = null;
        public Gee.ArrayList<LibraryPhoto>? losers = null;
        public Error? err = null;
        
        public FindMoveJob(LibraryMonitor owner, File file, Gee.Collection<LibraryPhoto> candidates) {
            base (owner, owner.on_find_move_completed, owner.cancellable, owner.on_find_move_cancelled);
            
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
            
            foreach (LibraryPhoto candidate in candidates) {
                if (candidate.get_master_md5() != md5)
                    continue;
                
                // if candidate's backing master exists, let it be
                if (candidate.does_master_exist())
                    continue;
                
                if (match != null) {
                    warning("Found more than one photo match for %s: %s and %s", file.get_path(),
                        match.to_string(), candidate.to_string());
                    
                    if (losers == null)
                        losers = new Gee.ArrayList<LibraryPhoto>();
                    
                    losers.add(candidate);
                    
                    continue;
                }
                
                match = candidate;
            }
        }
    }
    
    private class ChecksumJob : BackgroundJob {
        public File file;
        public string? md5 = null;
        public Error? err = null;
        
        public ChecksumJob(LibraryMonitor owner, File file) {
            base (owner, owner.on_checksum_completed, owner.cancellable, owner.on_checksum_cancelled);
            
            this.file = file;
            
            set_completion_priority(Priority.LOW);
        }
        
        public override void execute() {
            try {
                md5 = md5_file(file);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private Workers workers = new Workers(Workers.thread_per_cpu_minus_one(), false);
    private Cancellable cancellable = new Cancellable();
    private Gee.HashSet<LibraryPhoto> discovered = null;
    private Gee.HashSet<File> unknown_photo_files = null;
    private Gee.HashSet<LibraryPhoto> master_reimport_queue = new Gee.HashSet<LibraryPhoto>();
    private Gee.HashMap<LibraryPhoto, ReimportMasterJob> master_reimport_pending = new Gee.HashMap<
        LibraryPhoto, ReimportMasterJob>();
    private Gee.HashSet<LibraryPhoto> editable_reimport_queue = new Gee.HashSet<LibraryPhoto>();
    private Gee.HashMap<LibraryPhoto, ReimportEditableJob> editable_reimport_pending =
        new Gee.HashMap<LibraryPhoto, ReimportEditableJob>();
    private Gee.HashMap<LibraryPhoto, FileInfo> master_update_timestamp_queue = new Gee.HashMap<
        LibraryPhoto, FileInfo>();
    private Gee.HashMap<LibraryPhoto, FileInfo> editable_update_timestamp_queue = new Gee.HashMap<
        LibraryPhoto, FileInfo>();
    private Gee.HashSet<LibraryPhoto> revert_to_master_queue = new Gee.HashSet<LibraryPhoto>();
    private Gee.HashSet<LibraryPhoto> offline_queue = new Gee.HashSet<LibraryPhoto>();
    private Gee.HashSet<LibraryPhoto> online_queue = new Gee.HashSet<LibraryPhoto>();
    private Gee.HashSet<Video> detected_videos = new Gee.HashSet<Video>();
    private Gee.HashSet<Video> videos_to_mark_offline = new Gee.HashSet<Video>();
    private Gee.HashSet<Video> videos_to_mark_online = new Gee.HashSet<Video>();
    private Gee.HashSet<Video> videos_to_check_interpretable = new Gee.HashSet<Video>();
    private Gee.HashSet<File> import_queue = new Gee.HashSet<File>(file_hash, file_equal);
    private BatchImportRoll current_import_roll = null;
    private time_t last_import_roll_use = 0;
    private Gee.HashSet<File> pending_imports = new Gee.HashSet<File>(file_hash, file_equal);
    private BatchImport current_batch_import = null;
    private Gee.ArrayList<BatchImport> batch_import_queue = new Gee.ArrayList<BatchImport>();
    private int checksums_completed = 0;
    private int checksums_total = 0;
    
    public LibraryMonitor(File root, bool recurse, bool monitoring) {
        base (root, recurse, monitoring);
        
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
        LibraryPhoto.global.unlinked_destroyed.connect(on_photo_destroyed);
        
        Timeout.add_seconds(1, on_flush_pending_queues);
    }
    
    public override void close() {
        cancellable.cancel();
        
        foreach (ReimportMasterJob job in master_reimport_pending.values)
            job.cancel();
        
        foreach (ReimportEditableJob job in editable_reimport_pending.values)
            job.cancel();
        
        base.close();
    }
    
    public override void discovery_started() {
        discovered = new Gee.HashSet<LibraryPhoto>();
        unknown_photo_files = new Gee.HashSet<File>(file_hash, file_equal);
        
        base.discovery_started();
    }
    
    public override void file_discovered(File file, FileInfo info) {
        if (VideoReader.is_supported_video_file(file)) {
            Video? video = Video.global.get_by_file(file);
            
            if (video != null) {
                detected_videos.add(video);
            }

            // if this is a video file, then propogate the call to our superclass and do a
            // short-circuit return -- none of the photo shenanigans below apply to video
            base.file_discovered(file, info);
            return;
        }

        // convert file to photo (if possible) and store in discovered list
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = LibraryPhoto.global.get_state_by_file(file, out state);
        if (photo != null) {
            switch (state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    discovered.add(photo);
                break;
                
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.EDITABLE:
                default:
                    // ignored ... trash always stays in trash, offline or not, and editables are
                    // simply attached to online/offline photos
                break;
            }
        } else if (Photo.is_file_supported(file) && !Tombstone.global.matches(file, null)) {
            // only auto-import if it looks like a photo file and it's not been tombstoned
            // (not doing MD5 check at this point, they will be checked later)
            unknown_photo_files.add(file);
        }
        
        base.file_discovered(file, info);
    }
    
    public override void discovery_completed() {
        // before marking anything online/offline, reimporting changed files, or auto-importing new
        // files, want to see if the unknown files are actually renamed files.  Do this by examining
        // their FileInfo and calculating their MD5 in the background ... when all this is sorted
        // out, then go on and finish the other tasks
        if (unknown_photo_files.size == 0) {
            discovery_stage_completed();
            
            return;
        }
        
        Gee.ArrayList<LibraryPhoto> matching_masters = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<LibraryPhoto> matching_editables = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<File> adopted = new Gee.ArrayList<File>(file_equal);
        foreach (File file in unknown_photo_files) {
            FileInfo? info = get_file_info(file);
            if (info == null)
                continue;
            
            // clear these before using (they're reused as accumulators)
            matching_masters.clear();
            matching_editables.clear();
            
            // get photo(s) that match the characteristics of this file
            LibraryPhoto.global.fetch_by_matching_backing(info, matching_masters, matching_editables);
            
            // verify the match with an MD5 comparison
            if (matching_masters.size > 0) {
                // copy for background thread
                Gee.ArrayList<LibraryPhoto> candidates = matching_masters;
                matching_masters = new Gee.ArrayList<LibraryPhoto>();
                
                checksums_total++;
                workers.enqueue(new FindMoveJob(this, file, candidates));
                
                continue;
            }
            
            // for editable files, trust file characteristics alone
            LibraryPhoto match = null;
            if (matching_editables.size > 0) {
                match = matching_editables[0];
                if (matching_editables.size > 1) {
                    warning("Unknown file %s could be matched with %d photos; giving to %s, dropping others",
                        file.get_path(), matching_editables.size, match.to_string());
                    for (int ctr = 1; ctr < matching_editables.size; ctr++) {
                        if (!matching_editables[ctr].does_editable_exist())
                            matching_editables[ctr].revert_to_master();
                    }
                }
            }
            
            if (match != null) {
                match.set_editable_file(file);
                adopted.add(file);
            }
        }
        
        // remove all adopted files from the unknown list
        unknown_photo_files.remove_all(adopted);
        
        // After the checksumming is complete, the only use of the unknown photo files is for
        // auto-import, so don't bother checksumming the remainder for duplicates/tombstones unless
        // going to do that work
        if (startup_auto_import && LibraryPhoto.global.get_count() > 0
            && Tombstone.global.get_count() > 0) {
            foreach (File file in unknown_photo_files) {
                checksums_total++;
                workers.enqueue(new ChecksumJob(this, file));
            }
        }
        
        checksums_completed = 0;
        
        if (checksums_total == 0) {
            discovery_stage_completed();
        } else {
            mdbg("%d checksum jobs initiated to verify unknown photo files".printf(checksums_total));
            LibraryWindow.update_background_progress_bar(_("Updating library..."),
                checksums_completed, checksums_total);
        }
    }
    
    private void report_checksum_job_completed() {
        assert(checksums_completed < checksums_total);
        checksums_completed++;
        
        LibraryWindow.update_background_progress_bar(_("Updating library..."),
            checksums_completed, checksums_total);
        
        if (checksums_completed == checksums_total) {
            LibraryWindow.clear_background_progress_bar();
            discovery_stage_completed();
        }
    }
    
    private void on_find_move_completed(BackgroundJob j) {
        FindMoveJob job = (FindMoveJob) j;
        
        // if match was found, give file to the photo and removed from both the unknown list and
        // add to the discovered list ... do NOT mark losers as offline as other jobs may discover
        // files that belong to them; discovery_stage_completed() will work this out in the end
        if (job.match != null) {
            mdbg("Found moved master file: %s matches %s".printf(job.file.get_path(),
                job.match.to_string()));
            job.match.set_master_file(job.file);
            unknown_photo_files.remove(job.file);
            discovered.add(job.match);
        }
        
        if (job.err != null)
            warning("Unable to checksum unknown photo file %s: %s", job.file.get_path(), job.err.message);
        
        report_checksum_job_completed();
    }
    
    private void on_find_move_cancelled(BackgroundJob j) {
        report_checksum_job_completed();
    }
    
    private void on_checksum_completed(BackgroundJob j) {
        ChecksumJob job = (ChecksumJob) j;
        
        if (job.err != null) {
            warning("Unable to checksum %s to verify tombstone; treating as new file: %s",
                job.file.get_path(), job.err.message);
        }
        
        if (job.md5 != null) {
            Tombstone? tombstone = Tombstone.global.locate(job.file, job.md5);
            
            // if tombstoned or a duplicate of what's already in the library, drop it
            if (tombstone != null || Photo.is_duplicate(null, null, job.md5, PhotoFileFormat.UNKNOWN)) {
                mdbg("Skipping auto-import of duplicate file %s".printf(job.file.get_path()));
                unknown_photo_files.remove(job.file);
            }
            
            // if tombstoned, update tombstone if its backing file has moved
            if (tombstone != null && get_file_info(tombstone.get_file()) == null)
                tombstone.move(job.file);
        }
        
        report_checksum_job_completed();
    }
    
    private void on_checksum_cancelled(BackgroundJob j) {
        report_checksum_job_completed();
    }
    
    private void discovery_stage_completed() {
        foreach (Video video in detected_videos) {
            FileInfo? video_file_info = get_file_info(video.get_file());
            
            if (video_file_info != null && video.is_offline()) {
                videos_to_mark_online.add(video);
            } else if (video_file_info == null && !video.is_offline()) {
                videos_to_mark_offline.add(video);
            }
        }
        
        foreach (DataObject object in Video.global.get_all()) {
            Video video = (Video) object;
            FileInfo? video_file_info = get_file_info(video.get_file());
            
            if ((video_file_info != null) && (!video.is_offline())) {
                if (Video.has_interpreter_state_changed())
                    videos_to_check_interpretable.add(video);
            } else if (video_file_info == null && !video.is_offline()) {
                videos_to_mark_offline.add(video);
            }
        }

        // go through all discovered online photos and see if they're online
        foreach (LibraryPhoto photo in discovered) {
            FileInfo? master_info = get_file_info(photo.get_master_file());
            if (master_info != null && photo.is_offline()) {
                enqueue_online(photo);
            } else if (master_info == null && !photo.is_offline()) {
                // this indicates the file was discovered and then deleted before discovery ended
                // (still counts as offline)
                enqueue_offline(photo);
            }
        }
        
        // go through all known photos and mark offline if not in discovered list
        foreach (DataObject object in LibraryPhoto.global.get_all()) {
            LibraryPhoto photo = (LibraryPhoto) object;
            
            // only deal with photos under this monitor; external photos get a simpler verification
            if (!is_in_root(photo.get_master_file())) {
                verify_external_photo.begin(photo);
                
                continue;
            }
            
            // Don't mark online if in discovered, the prior loop works through those issues
            if (!discovered.contains(photo)) {
                enqueue_offline(photo);
                
                continue;
            }
            
            FileInfo? master_info = get_file_info(photo.get_master_file());
            assert(master_info != null);
            
            // if the photo is not offline and not to be marked offline, or does not
            // exist within the library directory (the following check happens in
            // verify_external_photo), check if anything about the photo is out-of-data,
            // and update it now
            if (!photo.is_offline() && !is_offline_pending(photo))
                check_for_master_changes(photo, master_info);
            
            File? editable_file = photo.get_editable_file();
            if (editable_file != null) {
                FileInfo? editable_info = get_file_info(editable_file);
                if (editable_info != null) {
                    check_for_editable_changes(photo, editable_info);
                } else {
                    critical("Unable to retrieve file information for editable %s",
                        editable_file.get_path());
                    
                    enqueue_revert_to_master(photo);
                }
            }
        }
        
        // go through all the offline photos and see if they're online now
        foreach (MediaSource source in LibraryPhoto.global.get_offline_bin_contents())
            verify_external_photo.begin((LibraryPhoto) source);
        
        // enqueue all remaining unknown photo files for import
        if (startup_auto_import)
            enqueue_import_many(unknown_photo_files);
        
        // release refs
        discovered = null;
        unknown_photo_files = null;
        
        // Now that the discovery is completed, launch a scan of the tombstoned files and see if
        // they can be resurrected
        Tombstone.global.launch_scan(this, cancellable);
        
        // Only report discovery completed here, after all the other background work is done
        base.discovery_completed();
    }
    
    private async void verify_external_photo(LibraryPhoto photo) {
        bool is_offline = photo.is_offline();
        
        File master = photo.get_master_file();
        FileInfo? master_info = null;
        try {
            // interested in nothing more than if the file exists
            master_info = yield master.query_info_async(SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, DEFAULT_PRIORITY, cancellable);
            if (master_info != null && is_offline)
                enqueue_online(photo);
            else if (master_info == null && !is_offline)
                enqueue_offline(photo);
        } catch (Error err) {
            if (!is_offline)
                enqueue_offline(photo);
        }
        
        // if not offline and not to-be-marked offline, see if anything has changed externally
        // and update if necessary
        if (master_info != null && !is_offline && !is_offline_pending(photo))
            check_for_master_changes(photo, master_info);
        
        if (!is_offline && !is_offline_pending(photo)) {
            File? editable = photo.get_editable_file();
            if (editable != null) {
                string errmsg = null;
                try {
                    FileInfo? editable_info = yield editable.query_info_async(SUPPLIED_ATTRIBUTES,
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS, DEFAULT_PRIORITY, cancellable);
                    if (editable_info != null)
                        check_for_editable_changes(photo, editable_info);
                    else
                        errmsg = "query_info_async returned null";
                } catch (Error err2) {
                    errmsg = err2.message;
                }
                
                if (errmsg != null) {
                    critical("Unable to fetch file info for external %s: %s", editable.get_path(),
                        errmsg);
                    
                    enqueue_revert_to_master(photo);
                }
            }
        }
    }
    
    private void on_photo_destroyed(DataSource source) {
        LibraryPhoto photo = (LibraryPhoto) source;
        
        // remove from all queues and cancel any pending operations
        master_reimport_queue.remove(photo);
        if (master_reimport_pending.has_key(photo))
            master_reimport_pending.get(photo).cancel();
        editable_reimport_queue.remove(photo);
        if (editable_reimport_pending.has_key(photo))
            editable_reimport_pending.get(photo).cancel();
        master_update_timestamp_queue.unset(photo);
        editable_update_timestamp_queue.unset(photo);
        revert_to_master_queue.remove(photo);
        offline_queue.remove(photo);
        online_queue.remove(photo);
        import_queue.remove(photo.get_master_file());
    }
    
    private void enqueue_reimport_master(LibraryPhoto photo) {
        // this supercedes updating the master modification time
        master_update_timestamp_queue.unset(photo);
        
        // if one is pending, cancel it for this one
        if (master_reimport_pending.has_key(photo))
            master_reimport_pending.get(photo).cancel();
        
        master_reimport_queue.add(photo);
    }
    
    private void enqueue_update_master_timestamp(LibraryPhoto photo, FileInfo info) {
        // don't bother in lieu of a reimport
        if (master_reimport_pending.has_key(photo) || master_reimport_queue.contains(photo))
            return;
        
        // add or replace existing
        master_update_timestamp_queue.set(photo, info);
    }
    
    private void enqueue_reimport_editable(LibraryPhoto photo) {
        // this supercedes updating the editable modification time
        editable_update_timestamp_queue.unset(photo);
        
        // if one is pending, cancel it for this one
        if (editable_reimport_pending.has_key(photo))
            editable_reimport_pending.get(photo).cancel();
        
        editable_reimport_queue.add(photo);
    }
    
    private void enqueue_update_editable_timestamp(LibraryPhoto photo, FileInfo info) {
        // don't bother in lieu of a reimport
        if (editable_reimport_pending.has_key(photo) || editable_reimport_queue.contains(photo))
            return;
        
        // add or replace existing
        editable_update_timestamp_queue.set(photo, info);
    }
    
    private void enqueue_revert_to_master(LibraryPhoto photo) {
        // remove all features regarding editables
        editable_reimport_queue.remove(photo);
        editable_update_timestamp_queue.unset(photo);
        if (editable_reimport_pending.has_key(photo))
            editable_reimport_pending.get(photo).cancel();
        
        revert_to_master_queue.add(photo);
    }
    
    private void enqueue_offline(LibraryPhoto photo) {
        // this kills all sorts of things
        if (master_reimport_pending.has_key(photo))
            master_reimport_pending.get(photo).cancel();
        master_reimport_queue.remove(photo);
        if (editable_reimport_pending.has_key(photo))
            editable_reimport_pending.get(photo).cancel();
        editable_reimport_queue.remove(photo);
        master_update_timestamp_queue.unset(photo);
        editable_update_timestamp_queue.unset(photo);
        online_queue.remove(photo);
        
        offline_queue.add(photo);
    }
    
    private void enqueue_online(LibraryPhoto photo) {
        // this doesn't kill most of the other queues, but probably not a good idea to be doing
        // any of that to an offline photo until it's marked online
        offline_queue.remove(photo);
        
        online_queue.add(photo);
    }
    
    private bool is_offline_pending(LibraryPhoto photo) {
        return offline_queue.contains(photo);
    }
    
    private void enqueue_import_many(Gee.Collection<File> files) {
        foreach (File file in files) {
            if (!pending_imports.contains(file))
                import_queue.add(file);
        }
    }
    
    // If filesize has changed, treat that as a full-blown modification
    // and reimport ... this is problematic if only the metadata has changed, but so be it.
    //
    // TODO: We could do an MD5 check for more accuracy.
    private void check_for_master_changes(LibraryPhoto photo, FileInfo info) {
        BackingPhotoState state = photo.get_master_photo_state();
        if (state.matches_file_info(info))
            return;
        
        if (state.is_touched(info))
            enqueue_update_master_timestamp(photo, info);
        else
            enqueue_reimport_master(photo);
    }
    
    private void check_for_editable_changes(LibraryPhoto photo, FileInfo info) {
        // If photo has editable, check if it's changed as well
        // If state matches, done -- editables have no bearing on a photo's offline status.
        BackingPhotoState? state = photo.get_editable_photo_state();
        if (state == null || state.matches_file_info(info))
            return;
        
        if (state.is_touched(info))
            enqueue_update_editable_timestamp(photo, info);
        else
            enqueue_reimport_editable(photo);
     }

    private void post_process_videos() {
        Video.global.freeze_notifications();

        foreach (Video video in videos_to_mark_offline) {
            video.mark_offline();
        }
        videos_to_mark_offline.clear();

        foreach (Video video in videos_to_mark_online) {
            video.mark_online();
            video.check_is_interpretable();
        }
        videos_to_mark_online.clear();
        // right now, videos will regenerate their thumbnails if they're not interpretable as
        // they come online, serially and sequentially. Because video thumbnail regeneration is
        // expensive, we might choose to do this in parallel. If this happens, it's extremely
        // important that notify_offline_thumbs_regenerated() be called only after all
        // regeneration activity has completed.
        Video.notify_offline_thumbs_regenerated();

        foreach (Video video in videos_to_check_interpretable) {
            video.check_is_interpretable();
        }
        videos_to_check_interpretable.clear();
        Video.notify_normal_thumbs_regenerated();

        Video.global.thaw_notifications();
    }
     
     private bool on_flush_pending_queues() {
        if (cancellable.is_cancelled())
            return false;
        
        Timer timer = new Timer();
        
        post_process_videos();

        LibraryPhoto.global.freeze_notifications();
        
        if (master_update_timestamp_queue.size > 0) {
            mdbg("Updating %d master files timestamps".printf(master_update_timestamp_queue.size));
            
            try {
                Photo.update_many_master_timestamps(master_update_timestamp_queue);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
            
            master_update_timestamp_queue.clear();
        }
        
        if (master_reimport_queue.size > 0) {
            mdbg("Reimporting %d masters".printf(master_reimport_queue.size));
            
            foreach (LibraryPhoto photo in master_reimport_queue) {
                assert(!master_reimport_pending.has_key(photo));
                
                ReimportMasterJob job = new ReimportMasterJob(this, photo);
                master_reimport_pending.set(photo, job);
                workers.enqueue(job);
            }
            
            master_reimport_queue.clear();
        }
        
        if (editable_update_timestamp_queue.size > 0) {
            mdbg("Updating %d editable files timestamps".printf(editable_update_timestamp_queue.size));
            
            try {
                Photo.update_many_editable_timestamps(editable_update_timestamp_queue);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
            
            editable_update_timestamp_queue.clear();
        }
        
        if (editable_reimport_queue.size > 0) {
            mdbg("Reimporting %d editables".printf(editable_reimport_queue.size));
            
            foreach (LibraryPhoto photo in editable_reimport_queue) {
                assert(!editable_reimport_pending.has_key(photo));
                
                ReimportEditableJob job = new ReimportEditableJob(this, photo);
                editable_reimport_pending.set(photo, job);
                workers.enqueue(job);
            }
            
            editable_reimport_queue.clear();
        }
        
        if (revert_to_master_queue.size > 0) {
            mdbg("Reverting %d photos to master".printf(revert_to_master_queue.size));
            
            foreach (LibraryPhoto photo in revert_to_master_queue)
                photo.revert_to_master();
            
            revert_to_master_queue.clear();
        }
        
        if (offline_queue.size > 0 || online_queue.size > 0) {
            mdbg("Marking %d photos as online, %d offline".printf(online_queue.size,
                offline_queue.size));
            
            try {
                LibraryPhoto.mark_many_online_offline(online_queue, offline_queue);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
            
            online_queue.clear();
            offline_queue.clear();
        }
        
        LibraryPhoto.global.thaw_notifications();
        
        if (import_queue.size > 0) {
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
                jobs.add(new FileImportJob(file, false));
                pending_imports.add(file);
            }
            
            import_queue.clear();
            
            BatchImport importer = new BatchImport(jobs, "LibraryMonitor autoimport",
                null, null, null, cancellable, current_import_roll);
            batch_import_queue.add(importer);
            
            schedule_next_batch_import();
        }
        
        double elapsed = timer.elapsed();
        if (elapsed > 0.001)
            mdbg("Total pending queue time: %lf".printf(elapsed));
        
        return true;
    }
    
    private void schedule_next_batch_import() {
        assert(current_batch_import == null);
        
        if (batch_import_queue.size == 0)
            return;
        
        current_batch_import = batch_import_queue[0];
        current_batch_import.progress.connect(on_import_progress);
        current_batch_import.import_complete.connect(on_import_complete);
        current_batch_import.schedule();
    }
    
    private void discard_current_batch_import() {
        assert(current_batch_import != null);
        
        bool removed = batch_import_queue.remove(current_batch_import);
        assert(removed);
        current_batch_import.progress.disconnect(on_import_progress);
        current_batch_import.import_complete.disconnect(on_import_complete);
        current_batch_import = null;
    }
    
    private void on_master_reimported(BackgroundJob j) {
        ReimportMasterJob job = (ReimportMasterJob) j;
        
        // no longer pending
        bool removed = master_reimport_pending.unset(job.photo);
        assert(removed);
        
        if (job.err != null) {
            critical("Unable to reimport %s due to master file changing: %s", job.photo.to_string(),
                job.err.message);
            
            enqueue_offline(job.photo);
            
            return;
        }
        
        if (!job.mark_online) {
            // the prepare_for_reimport_master failed, photo is now considered offline
            enqueue_offline(job.photo);
            
            return;
        }
        
        try {
            job.photo.finish_reimport_master(job.reimport_state);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // now considered online
        if (job.photo.is_offline())
            enqueue_online(job.photo);
        
        mdbg("Reimported master for %s".printf(job.photo.to_string()));
    }
    
    private void on_master_reimport_cancelled(BackgroundJob j) {
        bool removed = master_reimport_pending.unset(((ReimportMasterJob) j).photo);
        assert(removed);
    }
     
     private void on_editable_reimported(BackgroundJob j) {
        ReimportEditableJob job = (ReimportEditableJob) j;
        
        // no longer pending
        bool removed = editable_reimport_pending.unset(job.photo);
        assert(removed);
        
        if (job.err != null) {
            critical("Unable to reimport editable %s: %s", job.photo.to_string(), job.err.message);
            
            return;
        }
        
        try {
            job.photo.finish_reimport_editable(job.state);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        mdbg("Reimported editable for %s".printf(job.photo.to_string()));
    }
    
    private void on_editable_reimport_cancelled(BackgroundJob j) {
        bool removed = editable_reimport_pending.unset(((ReimportEditableJob) j).photo);
        assert(removed);
    }
    
    private void on_import_progress(uint64 completed_bytes, uint64 total_bytes) {
        LibraryWindow.update_background_progress_bar(_("Auto-importing..."),
            completed_bytes, total_bytes);
    }
    
    private void on_import_complete(BatchImport batch_import, ImportManifest manifest,
        BatchImportRoll import_roll) {
        assert(batch_import == current_batch_import);
        
        mdbg("auto-import batch completed %d".printf(manifest.all.size));
        
        LibraryWindow.clear_background_progress_bar();
        
        foreach (BatchImportResult result in manifest.all) {
            if (result.file != null)
                pending_imports.remove(result.file);
        }
        
        mdbg("%d files remain pending for auto-import".printf(pending_imports.size));
        
        discard_current_batch_import();
        schedule_next_batch_import();
    }
}

