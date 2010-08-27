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
    private class ReimportMasterJob : BackgroundJob {
        public LibraryPhoto photo;
        public PhotoRow updated_row = PhotoRow();
        public PhotoMetadata? metadata = null;
        public bool mark_online = false;
        public Error err = null;
        
        public ReimportMasterJob(LibraryMonitor owner, LibraryPhoto photo) {
            base (owner, owner.on_master_reimported, new Cancellable(),
                owner.on_master_reimport_cancelled);
            
            this.photo = photo;
        }
        
        public override void execute() {
            try {
                mark_online = photo.prepare_for_reimport_master(out updated_row, out metadata);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private class ReimportEditableJob : BackgroundJob {
        public LibraryPhoto photo;
        public BackingPhotoState state = BackingPhotoState();
        public PhotoMetadata? metadata = null;
        public bool success = false;
        public Error err = null;
        
        public ReimportEditableJob(LibraryMonitor owner, LibraryPhoto photo) {
            base (owner, owner.on_editable_reimported, new Cancellable(),
                owner.on_editable_reimport_cancelled);
            
            this.photo = photo;
        }
        
        public override void execute() {
            try {
                success = photo.prepare_for_reimport_editable(out state, out metadata);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private Workers workers = new Workers(Workers.thread_per_cpu_minus_one(), false);
    private Cancellable cancellable = new Cancellable();
    private Gee.HashSet<LibraryPhoto> discovered = null;
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
    
    public LibraryMonitor(File root, bool recurse, bool monitoring) {
        base (root, recurse, monitoring);
        
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
        
        base.discovery_started();
    }
    
    public override void file_discovered(File file, FileInfo info) {
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
        }
        
        base.file_discovered(file, info);
    }
    
    public override void discovery_completed() {
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
        foreach (LibraryPhoto photo in LibraryPhoto.global.get_offline())
            verify_external_photo.begin(photo);
        
        // release refs
        discovered = null;
        
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
    
    // If modification time or filesize has changed, treat that as a full-blown modification
    // and reimport ... this is problematic if only the metadata has changed, but so be it.
    // See note at top as to why a matching filesize and timestamp of zero yields only
    // an update of the timestamp.
    //
    // TODO: We could do an MD5 check for more accuracy.
    private void check_for_master_changes(LibraryPhoto photo, FileInfo info) {
        BackingPhotoState state = photo.get_master_photo_state();
        if (state.matches_file_info(info))
            return;
        
        if (info.get_size() == state.filesize && state.timestamp == 0)
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
        
        // see note at top for why this is done
        if (info.get_size() == state.filesize && state.timestamp == 0)
            enqueue_update_editable_timestamp(photo, info);
        else
            enqueue_reimport_editable(photo);
     }
     
     private bool on_flush_pending_queues() {
        if (cancellable.is_cancelled())
            return false;
        
        Timer timer = new Timer();
        
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
        
        double elapsed = timer.elapsed();
        if (elapsed > 0.001)
            mdbg("Total pending queue time: %lf".printf(elapsed));
        
        return true;
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
            job.photo.finish_reimport_master(ref job.updated_row, job.metadata);
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
            job.photo.finish_reimport_editable(job.state, job.metadata);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        mdbg("Reimported editable for %s".printf(job.photo.to_string()));
    }
    
    private void on_editable_reimport_cancelled(BackgroundJob j) {
        bool removed = editable_reimport_pending.unset(((ReimportEditableJob) j).photo);
        assert(removed);
    }
}

