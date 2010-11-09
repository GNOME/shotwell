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

public class LibraryMonitor : DirectoryMonitor {
    private const int FLUSH_PENDING_UPDATES_SEC = 2;
    private const int FLUSH_IMPORT_QUEUE_SEC = 5;
    private const int IMPORT_ROLL_QUIET_SEC = 5 * 60;
    private const int MAX_REIMPORT_JOBS_PER_CYCLE = 20;
    private const int MAX_REVERTS_PER_CYCLE = 5;
    private const int MIN_BLACKLIST_DURATION_MSEC = 5 * 1000;
    
    private class PhotoUpdates {
        public LibraryPhoto photo;
        public bool reimport_master = false;
        public File? master_file = null;
        public bool master_file_info_altered = false;
        public FileInfo? master_file_info = null;
        public bool master_in_alteration = false;
        public bool reimport_editable = false;
        public File? editable_file = null;
        public bool editable_file_info_altered = false;
        public FileInfo? editable_file_info = null;
        public bool editable_in_alteration = false;
        public bool revert_to_master = false;
        
        private bool online = false;
        private bool offline = false;
        
        public PhotoUpdates(LibraryPhoto photo) {
            this.photo = photo;
        }
        
        public void mark_offline() {
            online = false;
            offline = true;
        }
        
        public void mark_online() {
            online = true;
            offline = false;
        }
        
        public void reset_online_offline() {
            online = false;
            offline = false;
        }
        
        public bool set_offline() {
            return offline;
        }
        
        public bool set_online() {
            return online;
        }
        
        public bool is_all_updated() {
            return reimport_master == false
                && master_file == null
                && master_file_info_altered == false
                && master_file_info == null
                && master_in_alteration == false
                && reimport_editable == false
                && editable_file == null
                && editable_file_info_altered == false
                && editable_file_info == null
                && editable_in_alteration == false
                && revert_to_master == false
                && online == false
                && offline == false;
        }
    }
    
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
    
    private static Gee.HashSet<File> blacklist = new Gee.HashSet<File>(file_hash, file_equal);
    private static HashTimedQueue<File> to_unblacklist = new HashTimedQueue<File>(
        MIN_BLACKLIST_DURATION_MSEC, on_unblacklist_file, file_hash, file_equal, Priority.LOW);
    
    private Workers workers = new Workers(Workers.thread_per_cpu_minus_one(), false);
    private Cancellable cancellable = new Cancellable();
    private Gee.HashSet<LibraryPhoto> discovered = null;
    private Gee.HashSet<File> unknown_photo_files = null;
    private Gee.HashMap<LibraryPhoto, PhotoUpdates> pending_updates = new Gee.HashMap<LibraryPhoto,
        PhotoUpdates>();
    private Gee.HashMap<LibraryPhoto, ReimportMasterJob> master_reimport_pending = new Gee.HashMap<
        LibraryPhoto, ReimportMasterJob>();
    private Gee.HashMap<LibraryPhoto, ReimportEditableJob> editable_reimport_pending =
        new Gee.HashMap<LibraryPhoto, ReimportEditableJob>();
    private Gee.HashSet<Video> detected_videos = new Gee.HashSet<Video>();
    private Gee.HashSet<Video> videos_to_mark_offline = new Gee.HashSet<Video>();
    private Gee.HashSet<Video> videos_to_mark_online = new Gee.HashSet<Video>();
    private Gee.HashSet<Video> videos_to_check_interpretable = new Gee.HashSet<Video>();
    private Gee.HashSet<File> import_queue = new Gee.HashSet<File>(file_hash, file_equal);
    private Gee.HashSet<File> pending_imports = new Gee.HashSet<File>(file_hash, file_equal);
    private Gee.ArrayList<BatchImport> batch_import_queue = new Gee.ArrayList<BatchImport>();
    private BatchImportRoll current_import_roll = null;
    private time_t last_import_roll_use = 0;
    private BatchImport current_batch_import = null;
    private int checksums_completed = 0;
    private int checksums_total = 0;
    private uint pending_updates_timer_id = 0;
    private uint import_queue_timer_id = 0;
    
    public signal void auto_update_progress(int completed_files, int total_files);
    
    public signal void auto_import_preparing();
    
    public signal void auto_import_progress(uint64 completed_bytes, uint64 total_bytes);
    
    public LibraryMonitor(File root, bool recurse, bool monitoring) {
        base (root, recurse, monitoring);
        
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
        LibraryPhoto.global.unlinked_destroyed.connect(on_photo_destroyed);
        
        pending_updates_timer_id = Timeout.add_seconds(FLUSH_PENDING_UPDATES_SEC,
            on_flush_pending_updates);
        import_queue_timer_id = Timeout.add_seconds(FLUSH_IMPORT_QUEUE_SEC, on_flush_import_queue);
    }
    
    public override void close() {
        cancellable.cancel();
        
        foreach (ReimportMasterJob job in master_reimport_pending.values)
            job.cancel();
        
        foreach (ReimportEditableJob job in editable_reimport_pending.values)
            job.cancel();
        
        if (pending_updates_timer_id != 0) {
            Source.remove(pending_updates_timer_id);
            pending_updates_timer_id = 0;
        }
        
        if (import_queue_timer_id != 0) {
            Source.remove(import_queue_timer_id);
            import_queue_timer_id = 0;
        }
        
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
                update_editable_file(match, file);
                adopted.add(file);
            }
        }
        
        // remove all adopted files from the unknown list
        unknown_photo_files.remove_all(adopted);
        
        // After the checksumming is complete, the only use of the unknown photo files is for
        // auto-import, so don't bother checksumming the remainder for duplicates/tombstones unless
        // going to do that work
        if (CommandlineOptions.startup_auto_import && LibraryPhoto.global.get_count() > 0
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
        
        // if match was found, give file to the photo and removed from both the unknown list and
        // add to the discovered list ... do NOT mark losers as offline as other jobs may discover
        // files that belong to them; discovery_stage_completed() will work this out in the end
        if (job.match != null) {
            mdbg("Found moved master file: %s matches %s".printf(job.file.get_path(),
                job.match.to_string()));
            update_master_file(job.match, job.file);
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
            
            // if not in the monitored directory, it must be detected on its own
            if (!is_in_root(video.get_file())) {
                verify_external_video.begin(video);
                
                continue;
            }
            
            FileInfo? video_file_info = get_file_info(video.get_file());
            
            if ((video_file_info != null) && (!video.is_offline())) {
                if (Video.has_interpreter_state_changed())
                    videos_to_check_interpretable.add(video);
            } else if (video_file_info == null && !video.is_offline()) {
                videos_to_mark_offline.add(video);
            }
        }
        
        foreach (MediaSource media in Video.global.get_offline_bin_contents())
            verify_external_video.begin((Video) media);
        
        // go through all discovered online photos and see if they're online
        foreach (LibraryPhoto photo in discovered) {
            FileInfo? master_info = get_file_info(get_master_file(photo));
            if (master_info != null && is_offline(photo)) {
                update_photo_online(photo);
            } else if (master_info == null && is_online(photo)) {
                // this indicates the file was discovered and then deleted before discovery ended
                // (still counts as offline)
                update_photo_offline(photo);
            }
        }
        
        // go through all known photos and mark offline if not in discovered list
        foreach (DataObject object in LibraryPhoto.global.get_all()) {
            LibraryPhoto photo = (LibraryPhoto) object;
            
            // only deal with photos under this monitor; external photos get a simpler verification
            if (!is_in_root(get_master_file(photo))) {
                verify_external_photo.begin(photo);
                
                continue;
            }
            
            // Don't mark online if in discovered, the prior loop works through those issues
            if (!discovered.contains(photo)) {
                update_photo_offline(photo);
                
                continue;
            }
            
            FileInfo? master_info = get_file_info(get_master_file(photo));
            if (master_info == null) {
                update_photo_offline(photo);
                
                continue;
            }
            
            // if the photo is not offline and not to be marked offline, or does not
            // exist within the library directory (the following check happens in
            // verify_external_photo), check if anything about the photo is out-of-data,
            // and update it now
            if (is_online(photo))
                check_for_master_changes(photo, master_info);
            
            File? editable_file = get_editable_file(photo);
            if (editable_file != null) {
                FileInfo? editable_info = get_file_info(editable_file);
                if (editable_info != null) {
                    check_for_editable_changes(photo, editable_info);
                } else {
                    critical("Unable to retrieve file information for editable %s",
                        editable_file.get_path());
                    
                    update_revert_to_master(photo);
                }
            }
        }
        
        // go through all the offline photos and see if they're online now
        foreach (MediaSource source in LibraryPhoto.global.get_offline_bin_contents())
            verify_external_photo.begin((LibraryPhoto) source);
        
        // enqueue all remaining unknown photo files for import
        if (CommandlineOptions.startup_auto_import)
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
        File master = get_master_file(photo);
        FileInfo? master_info = null;
        try {
            // interested in nothing more than if the file exists
            master_info = yield master.query_info_async(SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, DEFAULT_PRIORITY, cancellable);
            if (master_info != null && is_offline(photo))
                update_photo_online(photo);
            else if (master_info == null && is_online(photo))
                update_photo_offline(photo);
        } catch (Error err) {
            if (is_online(photo))
                update_photo_offline(photo);
        }
        
        // if not offline and not to-be-marked offline, see if anything has changed externally
        // and update if necessary
        if (master_info != null && is_online(photo))
            check_for_master_changes(photo, master_info);
        
        if (is_online(photo)) {
            File? editable = get_editable_file(photo);
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
                    
                    update_revert_to_master(photo);
                }
            }
        }
    }
    
    private async void verify_external_video(Video video) {
        bool is_offline = video.is_offline();
        
        try {
            // only interested if file exists
            File file = video.get_file();
            FileInfo? info = yield file.query_info_async(SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, DEFAULT_PRIORITY, cancellable);
            if (info != null && is_offline)
                videos_to_mark_online.add(video);
            else if (info == null && !is_offline)
                videos_to_mark_offline.add(video);
        } catch (Error err) {
            if (!is_offline)
                videos_to_mark_offline.add(video);
        }
    }
    
    private void on_photo_destroyed(DataSource source) {
        remove_updates((LibraryPhoto) source);
    }
    
    private void remove_updates(LibraryPhoto photo) {
        pending_updates.unset(photo);
    }
    
    private PhotoUpdates fetch_updates(LibraryPhoto photo) {
        PhotoUpdates? updates = pending_updates.get(photo);
        if (updates != null)
            return updates;
        
        updates = new PhotoUpdates(photo);
        pending_updates.set(photo, updates);
        
        return updates;
    }
    
    // Code within LibraryMonitor will want to use these getters to retrieve information about the
    // LibraryPhoto that may not have already been committed to the database (which happens in
    // scheduled bursts).
    
    private bool is_online(LibraryPhoto photo) {
        PhotoUpdates? updates = pending_updates.get(photo);
        
        return (updates != null) ? updates.set_online() : !photo.is_offline();
    }
    
    private bool is_offline(LibraryPhoto photo) {
        PhotoUpdates? updates = pending_updates.get(photo);
        
        return (updates != null) ? updates.set_offline() : photo.is_offline();
    }
    
    private File get_master_file(LibraryPhoto photo) {
        PhotoUpdates? updates = pending_updates.get(photo);
        
        return (updates != null && updates.master_file != null) ? updates.master_file
            : photo.get_master_file();
    }
    
    private File? get_editable_file(LibraryPhoto photo) {
        PhotoUpdates? updates = pending_updates.get(photo);
        
        return (updates != null && updates.editable_file != null) ? updates.editable_file
            : photo.get_editable_file();
    }
    
    private LibraryPhoto? get_photo_state_by_file(File file, out LibraryPhotoSourceCollection.State state) {
        File? real_file = null;
        if (pending_updates.size > 0) {
            foreach (PhotoUpdates updates in pending_updates.values) {
                if (updates.master_file != null && updates.master_file.equal(file)) {
                    real_file = updates.photo.get_master_file();
                    
                    break;
                }
                
                if (updates.editable_file != null && updates.editable_file.equal(file)) {
                    real_file = updates.photo.get_editable_file();
                    
                    // if the photo's "real" editable file is null, then this file hasn't been
                    // associated with it (yet) so fake the call
                    if (real_file == null) {
                        state = LibraryPhotoSourceCollection.State.EDITABLE;
                        
                        return updates.photo;
                    }
                    
                    break;
                }
            }
        }
        
        return LibraryPhoto.global.get_state_by_file((real_file != null) ? real_file : file,
            out state);
    }
    
    // Code within LibraryMonitor should use these update methods to schedule changes to Photos.
    
    private void update_reimport_master(LibraryPhoto photo) {
        PhotoUpdates updates = fetch_updates(photo);
        
        updates.reimport_master = true;
        updates.mark_online();
        
        // cancel outstanding reimport
        if (master_reimport_pending.has_key(photo))
            master_reimport_pending.get(photo).cancel();
    }
    
    private void update_master_file(LibraryPhoto photo, File file) {
        // if the new file refers to an existing LibraryPhoto, need to 
        PhotoUpdates updates = fetch_updates(photo);
        
        updates.master_file = file;
        updates.mark_online();
    }
    
    private void update_master_file_info_altered(LibraryPhoto photo) {
        PhotoUpdates updates = fetch_updates(photo);
        
        updates.master_file_info_altered = true;
        updates.mark_online();
    }
    
    private void update_master_file_in_alteration(LibraryPhoto photo, bool in_alteration) {
        fetch_updates(photo).master_in_alteration = in_alteration;
    }
    
    private void update_master_file_alterations_completed(LibraryPhoto photo, FileInfo info) {
        PhotoUpdates updates = fetch_updates(photo);
        
        if (updates.master_file_info_altered)
            updates.master_file_info = info;
        updates.mark_online();
    }
    
    private void update_reimport_editable(LibraryPhoto photo) {
        PhotoUpdates updates = fetch_updates(photo);
        
        // if reverting or going offline, don't bother
        if (updates.revert_to_master || updates.set_offline())
            return;
        
        updates.reimport_editable = true;
        
        // cancel outstanding reimport
        if (editable_reimport_pending.has_key(photo))
            editable_reimport_pending.get(photo).cancel();
    }
    
    private void update_editable_file(LibraryPhoto photo, File file) {
        PhotoUpdates updates = fetch_updates(photo);
        
        // if reverting, don't bother
        if (!updates.revert_to_master)
            updates.editable_file = file;
    }
    
    private void update_editable_file_info_altered(LibraryPhoto photo) {
        PhotoUpdates updates = fetch_updates(photo);
        
        // if reverting, don't bother
        if (!updates.revert_to_master)
            updates.editable_file_info_altered = true;
    }
    
    private void update_editable_file_in_alteration(LibraryPhoto photo, bool in_alteration) {
        fetch_updates(photo).editable_in_alteration = in_alteration;
    }
    
    private void update_editable_file_alterations_completed(LibraryPhoto photo, FileInfo info) {
        PhotoUpdates updates = fetch_updates(photo);
        
        if (!updates.revert_to_master && updates.editable_file_info_altered)
            updates.editable_file_info = info;
    }
    
    private void update_revert_to_master(LibraryPhoto photo) {
        PhotoUpdates updates = fetch_updates(photo);
        
        updates.revert_to_master = true;
        
        // this means nothing any longer
        updates.reimport_editable = false;
        updates.editable_file = null;
        updates.editable_file_info = null;
    }
    
    private void update_photo_online(LibraryPhoto photo) {
        fetch_updates(photo).mark_online();
    }
    
    private void update_photo_offline(LibraryPhoto photo) {
        PhotoUpdates updates = fetch_updates(photo);
        
        updates.mark_offline();
        
        // this means nothing any longer
        updates.reimport_master = false;
        updates.master_file_info_altered = false;
        updates.master_file_info = null;
        updates.master_in_alteration = false;
        updates.reimport_editable = false;
    }
    
    private void enqueue_import(File file) {
        if (!pending_imports.contains(file))
            import_queue.add(file);
    }
    
    private void enqueue_import_many(Gee.Collection<File> files) {
        foreach (File file in files) {
            if (!pending_imports.contains(file))
                import_queue.add(file);
        }
    }
    
    private void remove_queued_import(File file) {
        import_queue.remove(file);
    }
    
    // If filesize has changed, treat that as a full-blown modification
    // and reimport ... this is problematic if only the metadata has changed, but so be it.
    //
    // TODO: We could do an MD5 check for more accuracy.
    private void check_for_master_changes(LibraryPhoto photo, FileInfo info) {
        BackingPhotoState state = photo.get_master_photo_state();
        if (state.matches_file_info(info))
            return;
        
        if (state.is_touched(info)) {
            update_master_file_info_altered(photo);
            update_master_file_alterations_completed(photo, info);
        } else {
            update_reimport_master(photo);
        }
    }
    
    private void check_for_editable_changes(LibraryPhoto photo, FileInfo info) {
        // If photo has editable, check if it's changed as well
        // If state matches, done -- editables have no bearing on a photo's offline status.
        BackingPhotoState? state = photo.get_editable_photo_state();
        if (state == null || state.matches_file_info(info))
            return;
        
        if (state.is_touched(info)) {
            update_editable_file_info_altered(photo);
            update_editable_file_alterations_completed(photo, info);
        } else {
            update_reimport_editable(photo);
        }
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
    
    private bool on_flush_pending_updates() {
        if (cancellable.is_cancelled())
            return false;
        
        Timer timer = new Timer();
        
        post_process_videos();
        
        Gee.Map<LibraryPhoto, File> set_master_file = null;
        Gee.Map<LibraryPhoto, FileInfo> set_master_file_info = null;
        Gee.Map<LibraryPhoto, File> set_editable_file = null;
        Gee.Map<LibraryPhoto, FileInfo> set_editable_file_info = null;
        Gee.ArrayList<LibraryPhoto> revert_to_master = null;
        Gee.ArrayList<LibraryPhoto> to_offline = null;
        Gee.ArrayList<LibraryPhoto> to_online = null;
        Gee.ArrayList<LibraryPhoto> to_remove = null;
        Gee.ArrayList<LibraryPhoto> reimport_master = null;
        Gee.ArrayList<LibraryPhoto> reimport_editable = null;
        int reimport_job_count = 0;
        
        foreach (PhotoUpdates updates in pending_updates.values) {
            // for sanity, simply skip any photo that is in the middle of alterations, whether its
            // master or editable
            if (updates.master_in_alteration || updates.editable_in_alteration)
                continue;
            
            // perform "instant" tasks first, that is, those that don't require a callback
            if (updates.master_file != null) {
                if (set_master_file == null)
                    set_master_file = new Gee.HashMap<LibraryPhoto, File>();
                
                set_master_file.set(updates.photo, updates.master_file);
                updates.master_file = null;
            }
            
            if (updates.master_file_info != null) {
                if (set_master_file_info == null)
                    set_master_file_info = new Gee.HashMap<LibraryPhoto, FileInfo>();
                
                set_master_file_info.set(updates.photo, updates.master_file_info);
                updates.master_file_info_altered = false;
                updates.master_file_info = null;
            }
            
            if (updates.editable_file != null) {
                if (set_editable_file == null)
                    set_editable_file = new Gee.HashMap<LibraryPhoto, File>();
                
                set_editable_file.set(updates.photo, updates.editable_file);
                updates.editable_file = null;
            }
            
            if (updates.editable_file_info != null) {
                if (set_editable_file_info == null)
                    set_editable_file_info = new Gee.HashMap<LibraryPhoto, FileInfo>();
                
                set_editable_file_info.set(updates.photo, updates.editable_file_info);
                updates.editable_file_info_altered = false;
                updates.editable_file_info = null;
            }
            
            if (updates.revert_to_master) {
                if (revert_to_master == null)
                    revert_to_master = new Gee.ArrayList<LibraryPhoto>();
                
                if (revert_to_master.size < MAX_REVERTS_PER_CYCLE) {
                    revert_to_master.add(updates.photo);
                    updates.revert_to_master = false;
                }
            }
            
            if (updates.set_offline()) {
                if (to_offline == null)
                    to_offline = new Gee.ArrayList<LibraryPhoto>();
                
                to_offline.add(updates.photo);
                updates.reset_online_offline();
            }
            
            if (updates.set_online()) {
                if (to_online == null)
                    to_online = new Gee.ArrayList<LibraryPhoto>();
                
                to_online.add(updates.photo);
                updates.reset_online_offline();
            }
            
            if (updates.reimport_master && reimport_job_count < MAX_REIMPORT_JOBS_PER_CYCLE) {
                if (reimport_master == null)
                    reimport_master = new Gee.ArrayList<LibraryPhoto>();
                
                reimport_master.add(updates.photo);
                updates.reimport_master = false;
                reimport_job_count++;
            }
            
            if (updates.reimport_editable && reimport_job_count < MAX_REIMPORT_JOBS_PER_CYCLE) {
                if (reimport_editable == null)
                    reimport_editable = new Gee.ArrayList<LibraryPhoto>();
                
                reimport_editable.add(updates.photo);
                updates.reimport_editable = false;
                reimport_job_count++;
            }
            
            if (updates.is_all_updated()) {
                if (to_remove == null)
                    to_remove = new Gee.ArrayList<LibraryPhoto>();
                
                to_remove.add(updates.photo);
            }
        }
        
        if (to_remove != null) {
            foreach (LibraryPhoto photo in to_remove)
                remove_updates(photo);
        }
        
        LibraryPhoto.global.freeze_notifications();
        
        if (set_master_file != null) {
            mdbg("Changing master file of %d photos".printf(set_master_file.size));
            
            try {
                Photo.set_many_master_file(set_master_file);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
        }
        
        if (set_master_file_info != null) {
            mdbg("Updating %d master files timestamps".printf(set_master_file_info.size));
            
            try {
                Photo.update_many_master_timestamps(set_master_file_info);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
        }
        
        if (set_editable_file != null) {
            mdbg("Changing editable file of %d photos".printf(set_editable_file.size));
            
            try {
                Photo.set_many_editable_file(set_editable_file);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
        }
        
        if (set_editable_file_info != null) {
            mdbg("Updating %d editable files timestamps".printf(set_editable_file_info.size));
            
            try {
                Photo.update_many_editable_timestamps(set_editable_file_info);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
        }
        
        if (revert_to_master != null) {
            mdbg("Reverting %d photos to master".printf(revert_to_master.size));
            
            foreach (LibraryPhoto photo in revert_to_master)
                photo.revert_to_master();
        }
        
        if (to_offline != null || to_online != null) {
            mdbg("Marking %d photos as online, %d offline".printf(
                (to_online != null) ? to_online.size : 0,
                (to_offline != null) ? to_offline.size : 0));
            
            try {
                LibraryPhoto.mark_many_online_offline(to_online, to_offline);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
        }
        
        LibraryPhoto.global.thaw_notifications();
        
        //
        // Now that the metadata has been updated, deal with imports and reimports
        //
        
        if (reimport_master != null) {
            mdbg("Reimporting %d masters".printf(reimport_master.size));
            
            foreach (LibraryPhoto photo in reimport_master) {
                assert(!master_reimport_pending.has_key(photo));
                
                ReimportMasterJob job = new ReimportMasterJob(this, photo);
                master_reimport_pending.set(photo, job);
                workers.enqueue(job);
            }
        }
        
        if (reimport_editable != null) {
            mdbg("Reimporting %d editables".printf(reimport_editable.size));
            
            foreach (LibraryPhoto photo in reimport_editable) {
                assert(!editable_reimport_pending.has_key(photo));
                
                ReimportEditableJob job = new ReimportEditableJob(this, photo);
                editable_reimport_pending.set(photo, job);
                workers.enqueue(job);
            }
        }
        
        double elapsed = timer.elapsed();
        if (elapsed > 0.01)
            mdbg("Total pending queue time: %lf".printf(elapsed));
        
        return true;
    }
    
    private bool on_flush_import_queue() {
        if (cancellable.is_cancelled())
            return false;
        
        if (import_queue.size == 0)
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
            jobs.add(new FileImportJob(file, false));
            pending_imports.add(file);
        }
        
        import_queue.clear();
        
        BatchImport importer = new BatchImport(jobs, "LibraryMonitor autoimport",
            null, null, null, cancellable, current_import_roll);
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
    }
    
    private void on_master_reimported(BackgroundJob j) {
        ReimportMasterJob job = (ReimportMasterJob) j;
        
        // no longer pending
        bool removed = master_reimport_pending.unset(job.photo);
        assert(removed);
        
        if (job.err != null) {
            critical("Unable to reimport %s due to master file changing: %s", job.photo.to_string(),
                job.err.message);
            
            update_photo_offline(job.photo);
            
            return;
        }
        
        if (!job.mark_online) {
            // the prepare_for_reimport_master failed, photo is now considered offline
            update_photo_offline(job.photo);
            
            return;
        }
        
        try {
            job.photo.finish_reimport_master(job.reimport_state);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // now considered online
        if (job.photo.is_offline())
            update_photo_online(job.photo);
        
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
            if (result.file != null)
                pending_imports.remove(result.file);
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
    //
    // These methods are currently not thread-safe.
    public static void blacklist_file(File file) {
        mdbg("Blacklisting %s".printf(file.get_path()));
        blacklist.add(file);
    }
    
    public static void unblacklist_file(File file) {
        // don't want to immediately remove the blacklisted file because the monitoring events
        // can come in much later
        if (blacklist.contains(file) && !to_unblacklist.contains(file))
            to_unblacklist.enqueue(file);
    }
    
    private static void on_unblacklist_file(File file) {
        if (blacklist.remove(file))
            mdbg("Blacklist for %s removed".printf(file.get_path()));
        else
            warning("File %s was not blacklisted but unblacklisted", file.get_path());
    }
    
    public static bool is_blacklisted(File file) {
        return blacklist.contains(file);
    }
    
    // It's possible for the monitor to miss a file create but report other activities, which we
    // can use to pick up new files
    private void runtime_unknown_file_discovered(File file) {
        if (CommandlineOptions.runtime_import && Photo.is_file_supported(file)
            && !Tombstone.global.matches(file, null)) {
            enqueue_import(file);
        }
    }
    
    protected override void notify_file_created(File file, FileInfo info) {
        if (is_blacklisted(file)) {
            base.notify_file_created(file, info);
            
            return;
        }
        
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo != null) {
            switch (state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    // do nothing, although this is unexpected
                    warning("File %s created in %s state", file.get_path(), state.to_string());
                break;
                
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    mdbg("Will mark %s online".printf(photo.to_string()));
                    update_photo_online(photo);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", state.to_string());
            }
        } else {
            runtime_unknown_file_discovered(file);
        }
        
        base.notify_file_created(file, info);
    }
    
    protected override void notify_file_moved(File old_file, File new_file, FileInfo new_info) {
        if (is_blacklisted(old_file) || is_blacklisted(new_file)) {
            base.notify_file_moved(old_file, new_file, new_info);
            
            return;
        }
        
        LibraryPhotoSourceCollection.State old_state;
        LibraryPhoto? old_photo = get_photo_state_by_file(old_file, out old_state);
        
        LibraryPhotoSourceCollection.State new_state;
        LibraryPhoto? new_photo = get_photo_state_by_file(new_file, out new_state);
        
        // Four possibilities:
        //
        // 1. Moving an existing photo file to a location where no photo is represented
        //    Operation: have the Photo object move with the file.
        // 2. Moving a file with no representative photo to a location where a photo is represented
        //    (i.e. is offline).  Operation: Update the photo (backing has changed).
        // 3. Moving a file with no representative photo to a location with no representative
        //    photo.  Operation: Enqueue for import (if appropriate).
        // 4. Move a file with a representative photo to a location where a photo is represented
        //    Operation: Mark the old photo as offline (or drop editable) and update new photo
        //    (the backing has changed).
        
        if (old_photo != null && new_photo == null) {
            // 1.
            switch (old_state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    mdbg("Will set new master file for %s to %s".printf(old_photo.to_string(),
                        new_file.get_path()));
                    update_master_file(old_photo, new_file);
                break;
                
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    mdbg("Will set new editable file for %s to %s".printf(old_photo.to_string(),
                        new_file.get_path()));
                    update_editable_file(old_photo, new_file);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", old_state.to_string());
            }
        } else if (old_photo == null && new_photo != null) {
            // 2.
            switch (new_state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    mdbg("Will reimport master file for %s".printf(new_photo.to_string()));
                    update_reimport_master(new_photo);
                break;
                
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    mdbg("Will reimport editable file for %s".printf(new_photo.to_string()));
                    update_reimport_editable(new_photo);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", new_state.to_string());
            }
        } else if (old_photo == null && new_photo == null) {
            // 3.
            runtime_unknown_file_discovered(new_file);
        } else {
            assert(old_photo != null && new_photo != null);
            // 4.
            switch (old_state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                    mdbg("Will mark offline %s".printf(old_photo.to_string()));
                    update_photo_offline(old_photo);
                break;
                
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    // do nothing
                break;
                
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    mdbg("Will revert %s to master".printf(old_photo.to_string()));
                    update_revert_to_master(old_photo);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", old_state.to_string());
            }
            
            switch (new_state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    mdbg("Will reimport master file for %s".printf(new_photo.to_string()));
                    update_reimport_master(new_photo);
                break;
                
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    mdbg("Will reimport editable file for %s".printf(new_photo.to_string()));
                    update_reimport_editable(new_photo);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", new_state.to_string());
            }
        }
        
        base.notify_file_moved(old_file, new_file, new_info);
    }
    
    protected override void notify_file_altered(File file) {
        if (is_blacklisted(file)) {
            base.notify_file_altered(file);
            
            return;
        }
        
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo != null) {
            switch (state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                case LibraryPhotoSourceCollection.State.TRASH:
                    mdbg("Will reimport master for %s".printf(photo.to_string()));
                    update_reimport_master(photo);
                    update_master_file_in_alteration(photo, true);
                break;
                
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    mdbg("Will reimport editable for %s".printf(photo.to_string()));
                    update_reimport_editable(photo);
                    update_editable_file_in_alteration(photo, true);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", state.to_string());
            }
        } else {
            runtime_unknown_file_discovered(file);
        }
        
        base.notify_file_altered(file);
    }
    
    protected override void notify_file_attributes_altered(File file) {
        if (is_blacklisted(file)) {
            base.notify_file_attributes_altered(file);
            
            return;
        }
        
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo != null) {
            switch (state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                case LibraryPhotoSourceCollection.State.TRASH:
                    mdbg("Will update master file info for %s".printf(photo.to_string()));
                    update_master_file_info_altered(photo);
                    update_master_file_in_alteration(photo, true);
                break;
                
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    // do nothing, but unexpected
                    warning("File %s attributes altered in %s state", file.get_path(),
                        state.to_string());
                    update_master_file_in_alteration(photo, true);
                break;
                
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    mdbg("Will update editable file info for %s".printf(photo.to_string()));
                    update_editable_file_info_altered(photo);
                    update_editable_file_in_alteration(photo, true);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", state.to_string());
            }
        } else {
            runtime_unknown_file_discovered(file);
        }
        
        base.notify_file_attributes_altered(file);
    }
    
    protected override void notify_file_alteration_completed(File file, FileInfo info) {
        if (is_blacklisted(file)) {
            base.notify_file_alteration_completed(file, info);
            
            return;
        }
        
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo != null) {
            switch (state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    update_master_file_alterations_completed(photo, info);
                break;
                
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    update_editable_file_alterations_completed(photo, info);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", state.to_string());
            }
        } else {
            runtime_unknown_file_discovered(file);
        }
        
        base.notify_file_alteration_completed(file, info);
    }
    
    protected override void notify_file_deleted(File file) {
        if (is_blacklisted(file)) {
            base.notify_file_deleted(file);
            
            return;
        }
        
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo != null) {
            switch (state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                    mdbg("Will mark %s offline".printf(photo.to_string()));
                    update_photo_offline(photo);
                    update_master_file_in_alteration(photo, false);
                break;
                
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    // do nothing / already knew this
                    update_master_file_in_alteration(photo, false);
                break;
                
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    mdbg("Will revert %s to master".printf(photo.to_string()));
                    update_revert_to_master(photo);
                    update_editable_file_in_alteration(photo, false);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", state.to_string());
            }
        } else {
            // ressurrect tombstone if deleted
            Tombstone? tombstone = Tombstone.global.locate(file, null);
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

