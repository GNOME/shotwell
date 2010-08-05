/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

//
// LibraryMonitor uses DirectoryMonitor to track assets in the user's library directory and make
// sure they're reflected in the application.
//
// NOTE: There appears to be a bug where prior versions of Shotwell (>= 0.6.x) were not
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
    private const uint REST_MSEC_BETWEEN_IMPORT_ROLLS = 3 * 60 * 1000;
    private const uint CHECK_FOR_BATCHED_WORK_MSEC = 3 * 1000;
    
    private class ChecksumJob : BackgroundJob {
        public File file;
        public Gee.Collection<LibraryPhoto> candidates;
        public LibraryPhoto? match = null;
        public Gee.ArrayList<LibraryPhoto>? losers = null;
        public Error? err = null;
        
        public ChecksumJob(LibraryMonitor owner, File file, Gee.Collection<LibraryPhoto> candidates) {
            base (owner, owner.on_checksum_completed, owner.cancellable, owner.on_checksum_cancelled);
            
            this.file = file;
            this.candidates = candidates;
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
    
    private class ReimportMasterJob : BackgroundJob {
        public LibraryPhoto photo;
        public PhotoRow updated_row = PhotoRow();
        public bool mark_online = false;
        public Error err = null;
        
        public ReimportMasterJob(LibraryMonitor owner, LibraryPhoto photo) {
            base (owner, owner.on_master_reimported, owner.cancellable, owner.on_master_reimport_cancelled);
            
            this.photo = photo;
        }
        
        public override void execute() {
            try {
                mark_online = photo.prepare_for_reimport_master(out updated_row);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private class MonitorImportJob : BatchImportJob {
        private File file;
        private FileInfo info;
        
        public MonitorImportJob(File file, FileInfo info) {
            this.file = file;
            this.info = info;
        }
        
        public override string get_identifier() {
            return file.get_path();
        }
        
        public override bool is_directory() {
            return info.get_type() == FileType.DIRECTORY;
        }
        
        public override bool determine_file_size(out uint64 filesize, out File file_or_dir) {
            filesize = info.get_size();
            
            return true;
        }
        
        public override bool prepare(out File file_to_import, out bool copy_to_library) throws Error {
            file_to_import = file;
            copy_to_library = false;
            
            return true;
        }
    }
    
    private Workers workers = new Workers(Workers.threads_per_cpu(1), false);
    private Cancellable cancellable = new Cancellable();
    private Gee.HashSet<LibraryPhoto> discovered = new Gee.HashSet<LibraryPhoto>();
    private Gee.HashSet<File> unknown = new Gee.HashSet<File>(file_hash, file_equal);
    private Gee.HashSet<LibraryPhoto> master_reimport_pending = new Gee.HashSet<LibraryPhoto>();
    private Gee.HashSet<LibraryPhoto> mark_external_offline = new Gee.HashSet<LibraryPhoto>();
    private Gee.HashSet<LibraryPhoto> mark_external_online = new Gee.HashSet<LibraryPhoto>();
    private int checksums_outstanding = 0;
    private int verify_external_outstanding = 0;
    
    public LibraryMonitor(File root, bool recurse, bool monitoring) {
        base (root, recurse, monitoring);
    }
    
    // If modification time or filesize has changed, treat that as a full-blown modification
    // and reimport ... this is problematic if only the metadata has changed, but so be it
    // (mark online if no changes, but wait until reimport is finished to mark online in
    // that case).  See note at top as to why a matching filesize and timestamp of zero yields only
    // an update of the timestamp.
    //
    // Returns true if the photo should be marked online, false if the caller should do nothing
    // (the result will be taken care of by reimport).
    //
    // TODO: We could do an MD5 check for more accuracy.
    private bool check_master_online(LibraryPhoto photo, FileInfo info) {
        BackingPhotoState state = photo.get_master_photo_state();
        if (state.matches_file_info(info)) {
            return true;
        } else if (info.get_size() == state.filesize && state.timestamp == 0) {
            mdbg("Updating %s master file timestamp".printf(photo.to_string()));
            try {
                photo.update_master_modification_time(info);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
            
            return true;
        } else if (!master_reimport_pending.contains(photo)) {
            mdbg("Reimporting %s master file".printf(photo.to_string()));
            master_reimport_pending.add(photo);
            workers.enqueue(new ReimportMasterJob(this, photo));
            
            return false;
        }
        
        return false;
    }
    
    private void check_editable_modified(LibraryPhoto photo, FileInfo info) {
        // If photo has editable, check if it's changed as well
        // If state matches, done -- editables have no bearing on a photo's offline status.
        BackingPhotoState? state = photo.get_editable_photo_state();
        if (state == null || state.matches_file_info(info))
            return;
        
        // see note at top for why this is done
        if (info.get_size() == state.filesize && state.timestamp == 0) {
            mdbg("Updating %s editable file timestamp".printf(photo.to_string()));
            try {
                photo.update_editable_modification_time(info);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
        } else {
            // TODO: Perform in background
            mdbg("Reimporting %s editable file".printf(photo.to_string()));
            try {
                photo.reimport_editable();
            } catch (Error err) {
                warning("Unable to reimport editable for %s: %s", photo.to_string(),
                    err.message);
            }
        }
    }
    
    public override void close() {
        cancellable.cancel();
        
        base.close();
    }
    
    public override void discovery_started() {
        discovered.clear();
        unknown.clear();
        
        base.discovery_started();
    }
    
    public override void file_discovered(File file, FileInfo info) {
        // convert file to photo (if possible) and store in discovered list
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = LibraryPhoto.global.get_state_by_file(file, out state);
        if (photo == null) {
            unknown.add(file);
            
            base.file_discovered(file, info);
            
            return;
        }
        
        switch (state) {
            case LibraryPhotoSourceCollection.State.ONLINE:
            case LibraryPhotoSourceCollection.State.OFFLINE:
            case LibraryPhotoSourceCollection.State.TRASH:
                discovered.add(photo);
            break;
            
            case LibraryPhotoSourceCollection.State.EDITABLE:
                // don't store editables, but don't add them to unknown either
            break;
            
            default:
                warning("Unknown photo state %s", state.to_string());
                unknown.add(file);
            break;
        }
        
        base.file_discovered(file, info);
    }
    
    public override void discovery_completed() {
        // walk all unknown files and see if they represent moved files that are known
        // in the library
        Gee.ArrayList<LibraryPhoto> matching_masters = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<LibraryPhoto> matching_editable = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<File> adopted_unknown = new Gee.ArrayList<File>();
        foreach (File file in unknown) {
            FileInfo? info = get_file_info(file);
            if (info == null)
                continue;
            
            // make sure these are empty before calling (they're reused as accumulators)
            matching_masters.clear();
            matching_editable.clear();
            
            // get photo that match the characteristics of the file
            LibraryPhoto.global.fetch_by_matching_backing(info, matching_masters, matching_editable);
            
            // for master files, we can double-verify the match by performing an MD5 checksum match
            // (need to copy the list, since it's reused) UNLESS the photo's master file is valid
            if (matching_masters.size > 0) {
                Gee.ArrayList<LibraryPhoto> candidates = new Gee.ArrayList<LibraryPhoto>();
                candidates.add_all(matching_masters);
                
                checksums_outstanding++;
                workers.enqueue(new ChecksumJob(this, file, candidates));
            }
            
            // For editable files, we have to trust the file characteristics alone
            LibraryPhoto match = null;
            if (matching_editable.size >= 1) {
                match = matching_editable.get(0);
                if (matching_editable.size > 1) {
                    warning("Unknown file %s could be matched with %d photos; giving to %s, others are dropped",
                        file.get_path(), matching_editable.size, match.to_string());
                    for (int ctr = 1; ctr < matching_editable.size; ctr++) {
                        if (!matching_editable.get(ctr).does_editable_exist())
                            matching_editable.get(ctr).revert_to_master();
                    }
                }
            }
            
            if (match != null) {
                debug("Found moved editable file: %s matches %s", file.get_path(), match.to_string());
                match.set_editable_file(file);
                adopted_unknown.add(file);
            }
        }
        
        // remove all the unknown editables that were adopted by LibraryPhoto
        unknown.remove_all(adopted_unknown);
        
        if (checksums_outstanding == 0)
            on_all_checksums_completed();
    }
    
    private void on_checksum_completed(BackgroundJob j) {
        ChecksumJob job = (ChecksumJob) j;
        
        // if a match was found, notify the Photo of the new file and remove the file from the
        // unknown list *and* add to the discovered list
        if (job.match != null) {
            mdbg("Found moved master file: %s matches %s".printf(job.file.get_path(),
                job.match.to_string()));
            job.match.set_master_file(job.file);
            unknown.remove(job.file);
            discovered.add(job.match);
        }
        
        // if losers found with no backing master, they are marked as offline
        if (job.losers != null) {
            Marker to_offline = LibraryPhoto.global.start_marking();
            foreach (LibraryPhoto loser in job.losers) {
                if (!loser.does_master_exist()) {
                    warning("Marking offline abandoned photo %s", loser.to_string());
                    to_offline.mark(loser);
                }
            }
            
            LibraryPhoto.global.mark_offline(to_offline);
        }
        
        assert(checksums_outstanding > 0);
        if (--checksums_outstanding == 0)
            on_all_checksums_completed();
    }
    
    private void on_checksum_cancelled(BackgroundJob j) {
        assert(checksums_outstanding > 0);
        if (--checksums_outstanding == 0)
            base.discovery_completed();
    }
    
    private void on_all_checksums_completed() {
        // go through all discovered online photos and see if they've changed since last imported
        LibraryPhoto.global.freeze_notifications();
        foreach (LibraryPhoto photo in discovered) {
            FileInfo? master_info = get_file_info(photo.get_master_file());
            if (master_info == null) {
                // this indicates the file was discovered and then deleted before discovery ended
                // (still counts as offline)
                mdbg("Marking %s offline: file discovered then deleted before discovery ended".printf(
                    photo.to_string()));
                photo.mark_offline();
                
                continue;
            }
            
            if (check_master_online(photo, master_info))
                photo.mark_online();
            
            if (photo.has_editable()) {
                File? editable = photo.get_editable_file();
                assert(editable != null);
                
                FileInfo? info = get_file_info(editable);
                if (info == null) {
                    // this indicates the file had an editable but it's now deleted; simply
                    // remove from photo
                    photo.revert_to_master();
                    
                    continue;
                }
                
                check_editable_modified(photo, info);
            }
        }
        LibraryPhoto.global.thaw_notifications();
        
        // because verifying all the external photos can take some time, don't freeze notifications
        // while waiting, but collect the online/offline photos and then mark them all while
        // notifications are frozen
        mark_external_online.clear();
        mark_external_offline.clear();
        
        // go through all photos and mark as online/offline depending on discovery
        Marker to_offline = LibraryPhoto.global.start_marking();
        foreach (DataObject object in LibraryPhoto.global.get_all()) {
            LibraryPhoto photo = (LibraryPhoto) object;
            
            // only deal with photos under this monitor; external photos get a simpler verification
            if (!is_in_root(photo.get_master_file())) {
                verify_external_outstanding++;
                verify_external_photo.begin(photo, verify_external_complete);
                
                continue;
            }
            
            // Don't mark online if in discovered, the prior loop works through those issues
            if (!discovered.contains(photo)) {
                mdbg("Marking %s as offline (master backing is missing)".printf(photo.to_string()));
                to_offline.mark(photo);
            }
        }
        
        LibraryPhoto.global.mark_offline(to_offline);
        
        // go through all the offline photos and see if they're online now
        foreach (LibraryPhoto photo in LibraryPhoto.global.get_offline()) {
            verify_external_outstanding++;
            verify_external_photo.begin(photo, verify_external_complete);
        }
        
        // clear both buckets to drop all refs
        discovered.clear();
        unknown.clear();
        
        mdbg("all checksums completed");
        
        // only report discovery completed here, which keeps DirectoryMonitor from initiating
        // another one
        base.discovery_completed();
    }
    
    private async void verify_external_photo(LibraryPhoto photo) {
        File master = photo.get_master_file();
        FileInfo? master_info = null;
        try {
            master_info = yield master.query_info_async(DirectoryMonitor.SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, cancellable);
        } catch (Error err) {
            mark_external_offline.add(photo);
            
            return;
        }
        
        if (check_master_online(photo, master_info))
            mark_external_online.add(photo);
        
        File? editable = photo.get_editable_file();
        if (editable == null)
            return;
        
        FileInfo? editable_info = null;
        try {
            editable_info = yield editable.query_info_async(DirectoryMonitor.SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, cancellable);
        } catch (Error err2) {
            return;
        }
        
        check_editable_modified(photo, editable_info);
    }
    
    private void verify_external_complete() {
        assert(verify_external_outstanding > 0);
        if (--verify_external_outstanding > 0)
            return;
        
        // deal with all the photos that need to change state, with notifications frozen
        LibraryPhoto.global.freeze_notifications();
        foreach (LibraryPhoto photo in mark_external_offline)
            photo.mark_offline();
        
        foreach (LibraryPhoto photo in mark_external_online)
            photo.mark_online();
        LibraryPhoto.global.thaw_notifications();
        
        // clear to drop refs
        mark_external_offline.clear();
        mark_external_online.clear();
    }
    
    private void on_master_reimported(BackgroundJob j) {
        ReimportMasterJob job = (ReimportMasterJob) j;
        
        // no longer pending
        bool removed = master_reimport_pending.remove(job.photo);
        assert(removed);
        
        if (job.err != null) {
            critical("Unable to reimport %s due to master file changing: %s", job.photo.to_string(),
                job.err.message);
            
            return;
        }
        
        if (!job.mark_online) {
            // the prepare_for_reimport_master failed, photo is now considered offline
            job.photo.mark_offline();
            
            return;
        }
        
        try {
            job.photo.finish_reimport_master(ref job.updated_row);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // now considered online
        job.photo.mark_online();
        
        mdbg("Reimported master for %s".printf(job.photo.to_string()));
    }
    
    private void on_master_reimport_cancelled(BackgroundJob j) {
        // no longer pending
        bool removed = master_reimport_pending.remove(((ReimportMasterJob) j).photo);
        assert(removed);
    }
}

