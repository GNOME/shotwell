/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class PhotoUpdates : MonitorableUpdates {
    public LibraryPhoto photo;
    
    public bool reimport_master = false;
    public bool reimport_editable = false;
    public bool reimport_raw_developments = false;
    public File? editable_file = null;
    public bool editable_file_info_altered = false;
    public bool raw_developer_file_info_altered = false;
    public FileInfo? editable_file_info = null;
    public bool editable_in_alteration = false;
    public bool raw_development_in_alteration = false;
    public bool revert_to_master = false;
    public Gee.Collection<File> developer_files = new Gee.ArrayList<File>();
    
    public PhotoUpdates(LibraryPhoto photo) {
        base (photo);
        
        this.photo = photo;
    }
    
    public override void mark_offline() {
        base.mark_offline();
        
        reimport_master = false;
        reimport_editable = false;
        reimport_raw_developments = false;
    }
    
    public bool is_reimport_master() {
        return reimport_master;
    }
    
    public bool is_reimport_editable() {
        return reimport_editable;
    }
    
    public File? get_editable_file() {
        return editable_file;
    }
    
    public FileInfo? get_editable_file_info() {
        return editable_file_info;
    }
    
    public Gee.Collection<File> get_raw_developer_files() {
        return developer_files;
    }
    
    public override bool is_in_alteration() {
        return base.is_in_alteration() || editable_in_alteration;
    }
    
    public bool is_revert_to_master() {
        return revert_to_master;
    }
    
    public virtual void set_editable_file(File? file) {
        // if reverting, don't bother
        if (file != null && revert_to_master)
            return;
        
        editable_file = file;
    }
    
    public virtual void set_editable_file_info(FileInfo? info) {
        // if reverting, don't bother
        if (info != null && revert_to_master)
            return;
        
        editable_file_info = info;
        if (info == null)
            editable_file_info_altered = false;
    }
    
    public virtual void set_editable_file_info_altered(bool altered) {
        // if reverting, don't bother
        if (altered && revert_to_master)
            return;
        
        editable_file_info_altered = altered;
    }
    
    public virtual void set_editable_in_alteration(bool in_alteration) {
        editable_in_alteration = in_alteration;
    }
    
    public virtual void set_raw_development_in_alteration(bool in_alteration) {
        raw_development_in_alteration = in_alteration;
    }
    
    public virtual void set_raw_developer_file_info_altered(bool altered) {
        raw_developer_file_info_altered = altered;
    }
    
    public virtual void set_revert_to_master(bool revert) {
        if (revert) {
            // this means nothing any longer
            reimport_editable = false;
            editable_file = null;
            editable_file_info = null;
        }
        
        revert_to_master = revert;
    }
    
    public virtual void add_raw_developer_file(File file) {
        developer_files.add(file);
    }
    
    public virtual void clear_raw_developer_files() {
        developer_files.clear();
    }
    
    public virtual void set_reimport_master(bool reimport) {
        reimport_master = reimport;
        
        if (reimport)
            mark_online();
    }
    
    public virtual void set_reimport_editable(bool reimport) {
        // if reverting or going offline, don't bother
        if (reimport && (revert_to_master || is_set_offline()))
            return;
        
        reimport_editable = reimport;
    }
    
    public virtual void set_reimport_raw_developments(bool reimport) {
        reimport_raw_developments = reimport;
        
        if (reimport)
            mark_online();
    }
    
    public override bool is_all_updated() {
        return base.is_all_updated()
            && reimport_master == false
            && reimport_editable == false
            && editable_file == null
            && editable_file_info_altered == false
            && editable_file_info == null
            && editable_in_alteration == false
            && developer_files.size == 0
            && raw_developer_file_info_altered == false
            && revert_to_master == false;
    }
}

private class PhotoMonitor : MediaMonitor {
    private const int MAX_REIMPORT_JOBS_PER_CYCLE = 20;
    private const int MAX_REVERTS_PER_CYCLE = 5;
    
    private class ReimportMasterJob : BackgroundJob {
        public LibraryPhoto photo;
        public Photo.ReimportMasterState reimport_state = null;
        public bool mark_online = false;
        public Error err = null;
        
        public ReimportMasterJob(PhotoMonitor owner, LibraryPhoto photo) {
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
        
        public ReimportEditableJob(PhotoMonitor owner, LibraryPhoto photo) {
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
    
    private class ReimportRawDevelopmentJob : BackgroundJob {
        public LibraryPhoto photo;
        public Photo.ReimportRawDevelopmentState state = null;
        public bool success = false;
        public Error err = null;
        
        public ReimportRawDevelopmentJob(PhotoMonitor owner, LibraryPhoto photo) {
            base (owner, owner.on_raw_development_reimported, new Cancellable(),
                owner.on_raw_development_reimport_cancelled);
            
            this.photo = photo;
        }
        
        public override void execute() {
            try {
                success = photo.prepare_for_reimport_raw_development(out state);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private Workers workers;
    private Gee.ArrayList<LibraryPhoto> matched_editables = new Gee.ArrayList<LibraryPhoto>();
    private Gee.ArrayList<LibraryPhoto> matched_developments = new Gee.ArrayList<LibraryPhoto>();
    private Gee.HashMap<LibraryPhoto, ReimportMasterJob> master_reimport_pending = new Gee.HashMap<
        LibraryPhoto, ReimportMasterJob>();
    private Gee.HashMap<LibraryPhoto, ReimportEditableJob> editable_reimport_pending =
        new Gee.HashMap<LibraryPhoto, ReimportEditableJob>();
    private Gee.HashMap<LibraryPhoto, ReimportRawDevelopmentJob> raw_developments_reimport_pending =
        new Gee.HashMap<LibraryPhoto, ReimportRawDevelopmentJob>();
    
    public PhotoMonitor(Workers workers, Cancellable cancellable) {
        base (LibraryPhoto.global, cancellable);
        
        this.workers = workers;
    }
    
    protected override MonitorableUpdates create_updates(Monitorable monitorable) {
        assert(monitorable is LibraryPhoto);
        
        return new PhotoUpdates((LibraryPhoto) monitorable);
    }
    
    public override MediaSourceCollection get_media_source_collection() {
        return LibraryPhoto.global;
    }
    
    public override bool is_file_represented(File file) {
        LibraryPhotoSourceCollection.State state;
        return get_photo_state_by_file(file, out state) != null;
    }
    
    public override void close() {
        foreach (ReimportMasterJob job in master_reimport_pending.values)
            job.cancel();
        
        foreach (ReimportEditableJob job in editable_reimport_pending.values)
            job.cancel();
        
        foreach (ReimportRawDevelopmentJob job in raw_developments_reimport_pending.values)
            job.cancel();
        
        base.close();
    }
    
    private void cancel_reimports(LibraryPhoto photo) {
        ReimportMasterJob? master_job = master_reimport_pending.get(photo);
        if (master_job != null)
            master_job.cancel();
        
        ReimportEditableJob? editable_job = editable_reimport_pending.get(photo);
        if (editable_job != null)
            editable_job.cancel();
    }
    
    public override MediaMonitor.DiscoveredFile notify_file_discovered(File file, FileInfo info,
        out Monitorable monitorable) {
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo == null) {
            monitorable = null;
            
            return MediaMonitor.DiscoveredFile.UNKNOWN;
        }

        switch (state) {
            case LibraryPhotoSourceCollection.State.ONLINE:
            case LibraryPhotoSourceCollection.State.OFFLINE:
                monitorable = photo;
                
                return MediaMonitor.DiscoveredFile.REPRESENTED;
            
            case LibraryPhotoSourceCollection.State.TRASH:
            case LibraryPhotoSourceCollection.State.EDITABLE:
            case LibraryPhotoSourceCollection.State.DEVELOPER:
            default:
                // ignored ... trash always stays in trash, offline or not, and editables are
                // simply attached to online/offline photos
                monitorable = null;
                
                return MediaMonitor.DiscoveredFile.IGNORE;
        }
    }
    
    public override Gee.Collection<Monitorable>? candidates_for_unknown_file(File file, FileInfo info,
        out MediaMonitor.DiscoveredFile result) {
        // reset with each call
        matched_editables.clear();
        matched_developments.clear();
        
        Gee.Collection<LibraryPhoto> matched_masters = new Gee.ArrayList<LibraryPhoto>();
        LibraryPhoto.global.fetch_by_matching_backing(info, matched_masters, matched_editables, 
            matched_developments);
        if (matched_masters.size > 0) {
            result = MediaMonitor.DiscoveredFile.UNKNOWN;
            
            return matched_masters;
        }
        
        if (matched_editables.size == 0 && matched_developments.size == 0) {
            result = MediaMonitor.DiscoveredFile.UNKNOWN;
            
            return null;
        }
        
        // for editable files and raw developments, trust file characteristics alone
        if (matched_editables.size > 0) {
            LibraryPhoto match = matched_editables[0];
            if (matched_editables.size > 1) {
                warning("Unknown file %s could be matched with %d photos; giving to %s, dropping others",
                    file.get_path(), matched_editables.size, match.to_string());
                for (int ctr = 1; ctr < matched_editables.size; ctr++) {
                    if (!matched_editables[ctr].does_editable_exist())
                        matched_editables[ctr].revert_to_master();
                }
            }
            
            update_editable_file(match, file);
        }
        
        if (matched_developments.size > 0) {
            LibraryPhoto match_raw = matched_developments[0];
            if (matched_developments.size > 1) {
                warning("Unknown file %s could be matched with %d photos; giving to %s, dropping others",
                    file.get_path(), matched_developments.size, match_raw.to_string());
            }
            
            update_raw_development_file(match_raw, file);
        }
        
        result = MediaMonitor.DiscoveredFile.IGNORE;
        
        return null;
    }
    
    public override File[]? get_auxilliary_backing_files(Monitorable monitorable) {
        LibraryPhoto photo = (LibraryPhoto) monitorable;
        File[] files =  new File[0];
        
        // Editable.
        if (photo.has_editable())
            files += photo.get_editable_file();
        
        // Raw developments.
        Gee.Collection<File>? raw_files = photo.get_raw_developer_files();
        if (raw_files != null)
            foreach (File f in raw_files)
                files += f;
        
        // Return null if no files.
        return files.length > 0 ? files : null;
    }
    
    public override void update_backing_file_info(Monitorable monitorable, File file, FileInfo? info) {
        LibraryPhoto photo = (LibraryPhoto) monitorable;
        
        if (get_master_file(photo).equal(file))
            check_for_master_changes(photo, info);
        else if (get_editable_file(photo) != null && get_editable_file(photo).equal(file))
            check_for_editable_changes(photo, info);
        else if (get_raw_development_files(photo) != null) {
            foreach (File f in get_raw_development_files(photo)) {
                if (f.equal(file))
                    check_for_raw_development_changes(photo, info);
            }
        }
    }
    
    public override void notify_discovery_completing() {
        matched_editables.clear();
    }
    
    // If filesize has changed, treat that as a full-blown modification
    // and reimport ... this is problematic if only the metadata has changed, but so be it.
    //
    // TODO: We could do an MD5 check for more accuracy.
    private void check_for_master_changes(LibraryPhoto photo, FileInfo? info) {
        // if not present, offline state is already taken care of by LibraryMonitor
        if (info == null)
            return;
        
        BackingPhotoRow state = photo.get_master_photo_row();
        if (state.matches_file_info(info))
            return;
        
        if (state.is_touched(info)) {
            update_master_file_info_altered(photo);
            update_master_file_alterations_completed(photo, info);
        } else {
            update_reimport_master(photo);
        }
    }
    
    private void check_for_editable_changes(LibraryPhoto photo, FileInfo? info) {
        if (info == null) {
            update_revert_to_master(photo);
            
            return;
        }
        
        // If state matches, done -- editables have no bearing on a photo's offline status.
        BackingPhotoRow? state = photo.get_editable_photo_row();
        if (state == null || state.matches_file_info(info))
            return;
        
        if (state.is_touched(info)) {
            update_editable_file_info_altered(photo);
            update_editable_file_alterations_completed(photo, info);
        } else {
            update_reimport_editable(photo);
        }
    }
    
    private void check_for_raw_development_changes(LibraryPhoto photo, FileInfo? info) {
        if (info == null) {
            // Switch back to default for safety.
            photo.set_raw_developer(RawDeveloper.SHOTWELL);
            
            return;
        }
        
        Gee.Collection<BackingPhotoRow>? rows = photo.get_raw_development_photo_rows();
        if (rows == null)
            return;
        
        // Look through all possible rows, if we find a file with a matching name or info,
        // assume we found our man.
        foreach (BackingPhotoRow row in rows) {
            if (row.matches_file_info(info))
                return;
            if (info.get_name() == row.filepath) {
                if (row.is_touched(info)) {
                    update_raw_development_file_info_altered(photo);
                    update_raw_development_file_alterations_completed(photo);
                } else {
                    update_reimport_raw_developments(photo);
                }
                
                break;
            }
        }
    }
    
    public override bool notify_file_created(File file, FileInfo info) {
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo == null)
            return false;
            
        switch (state) {
            case LibraryPhotoSourceCollection.State.ONLINE:
            case LibraryPhotoSourceCollection.State.TRASH:
            case LibraryPhotoSourceCollection.State.EDITABLE:
            case LibraryPhotoSourceCollection.State.DEVELOPER:
                // do nothing, although this is unexpected
                warning("File %s created in %s state", file.get_path(), state.to_string());
            break;
            
            case LibraryPhotoSourceCollection.State.OFFLINE:
                mdbg("Will mark %s online".printf(photo.to_string()));
                update_online(photo);
            break;
            
            default:
                error("Unknown LibraryPhoto collection state %s", state.to_string());
        }
        
        return true;
    }
    
    public override bool notify_file_moved(File old_file, File new_file, FileInfo info) {
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
                
                case LibraryPhotoSourceCollection.State.DEVELOPER:
                    mdbg("Will set new raw development file for %s to %s".printf(old_photo.to_string(),
                        new_file.get_path()));
                    update_raw_development_file(old_photo, new_file);
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
                
                case LibraryPhotoSourceCollection.State.DEVELOPER:
                    mdbg("Will reimport raw development file for %s".printf(new_photo.to_string()));
                    update_reimport_raw_developments(new_photo);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", new_state.to_string());
            }
        } else if (old_photo == null && new_photo == null) {
            // 3.
            return false;
        } else {
            assert(old_photo != null && new_photo != null);
            // 4.
            switch (old_state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                    mdbg("Will mark offline %s".printf(old_photo.to_string()));
                    update_offline(old_photo);
                break;
                
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    // do nothing
                break;
                
                case LibraryPhotoSourceCollection.State.EDITABLE:
                    mdbg("Will revert %s to master".printf(old_photo.to_string()));
                    update_revert_to_master(old_photo);
                break;
                
                case LibraryPhotoSourceCollection.State.DEVELOPER:
                    // do nothing
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
                
                case LibraryPhotoSourceCollection.State.DEVELOPER:
                    mdbg("Will reimport raw development file for %s".printf(new_photo.to_string()));
                    update_reimport_raw_developments(new_photo);
                break;
                
                default:
                    error("Unknown LibraryPhoto collection state %s", new_state.to_string());
            }
        }
        
        return true;
    }
    
    public override bool notify_file_altered(File file) {
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo == null)
            return false;
        
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
            
            case LibraryPhotoSourceCollection.State.DEVELOPER:
                mdbg("Will reimport raw development for %s".printf(photo.to_string()));
                update_reimport_raw_developments(photo);
                update_raw_development_file_in_alteration(photo, true);
            break;
            
            default:
                error("Unknown LibraryPhoto collection state %s", state.to_string());
        }
        
        return true;
    }
    
    public override bool notify_file_attributes_altered(File file) {
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo == null)
            return false;
        
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
            
            case LibraryPhotoSourceCollection.State.DEVELOPER:
                mdbg("Will update raw development file info for %s".printf(photo.to_string()));
                update_raw_development_file_info_altered(photo);
                update_raw_development_file_in_alteration(photo, true);
            break;
            
            default:
                error("Unknown LibraryPhoto collection state %s", state.to_string());
        }
        
        return true;
    }
    
    public override bool notify_file_alteration_completed(File file, FileInfo info) {
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo == null)
            return false;
        
        switch (state) {
            case LibraryPhotoSourceCollection.State.ONLINE:
            case LibraryPhotoSourceCollection.State.TRASH:
            case LibraryPhotoSourceCollection.State.OFFLINE:
                update_master_file_alterations_completed(photo, info);
            break;
            
            case LibraryPhotoSourceCollection.State.EDITABLE:
                update_editable_file_alterations_completed(photo, info);
            break;
            
            case LibraryPhotoSourceCollection.State.DEVELOPER:
                update_raw_development_file_alterations_completed(photo);
            break;
            
            default:
                error("Unknown LibraryPhoto collection state %s", state.to_string());
        }
        
        return true;
    }
    
    public override bool notify_file_deleted(File file) {
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = get_photo_state_by_file(file, out state);
        if (photo == null)
            return false;
        
        switch (state) {
            case LibraryPhotoSourceCollection.State.ONLINE:
                mdbg("Will mark %s offline".printf(photo.to_string()));
                update_offline(photo);
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
            
            case LibraryPhotoSourceCollection.State.DEVELOPER:
                mdbg("Will revert %s to master".printf(photo.to_string()));
                update_revert_to_master(photo);
                update_editable_file_in_alteration(photo, false);
                update_raw_development_file_in_alteration(photo, false);
            break;
            
            default:
                error("Unknown LibraryPhoto collection state %s", state.to_string());
        }
        
        return true;
    }
    
    protected override void on_media_source_destroyed(DataSource source) {
        base.on_media_source_destroyed(source);
        
        cancel_reimports((LibraryPhoto) source);
    }
    
    private LibraryPhoto? get_photo_state_by_file(File file, out LibraryPhotoSourceCollection.State state) {
        File? real_file = null;
        if (has_pending_updates()) {
            foreach (Monitorable monitorable in get_monitorables()) {
                LibraryPhoto photo = (LibraryPhoto) monitorable;
                
                PhotoUpdates? updates = get_existing_photo_updates(photo);
                if (updates == null)
                    continue;
                
                if (updates.get_master_file() != null && updates.get_master_file().equal(file)) {
                    real_file = photo.get_master_file();
                    
                    break;
                }
                
                if (updates.get_editable_file() != null && updates.get_editable_file().equal(file)) {
                    real_file = photo.get_editable_file();
                    
                    // if the photo's "real" editable file is null, then this file hasn't been
                    // associated with it (yet) so fake the call
                    if (real_file == null) {
                        state = LibraryPhotoSourceCollection.State.EDITABLE;
                        
                        return photo;
                    }
                    
                    break;
                }
                
                if (updates.get_raw_developer_files() != null) {
                    bool found = false;
                    foreach (File raw in updates.get_raw_developer_files()) {
                        if (raw.equal(file)) {
                            found = true;
                            
                            break;
                        }
                    }
                
                    if (found) {
                        Gee.Collection<File>? developed = photo.get_raw_developer_files();
                        if (developed != null) {
                            foreach (File f in developed) {
                                if (f.equal(file)) {
                                    real_file = f;
                                    state = LibraryPhotoSourceCollection.State.DEVELOPER;
                                    
                                    break;
                                }
                            }
                            
                        }
                        
                        break;
                    }
                }
            }
        }
        
        return LibraryPhoto.global.get_state_by_file(real_file ?? file, out state);
    }
    
    public PhotoUpdates fetch_photo_updates(LibraryPhoto photo) {
        return (PhotoUpdates) fetch_updates(photo);
    }
    
    public PhotoUpdates? get_existing_photo_updates(LibraryPhoto photo) {
        return get_existing_updates(photo) as PhotoUpdates;
    }
    
    public void update_reimport_master(LibraryPhoto photo) {
        fetch_photo_updates(photo).set_reimport_master(true);
        
        // cancel outstanding reimport
        if (master_reimport_pending.has_key(photo))
            master_reimport_pending.get(photo).cancel();
    }
    
    public void update_reimport_editable(LibraryPhoto photo) {
        fetch_photo_updates(photo).set_reimport_editable(true);
        
        // cancel outstanding reimport
        if (editable_reimport_pending.has_key(photo))
            editable_reimport_pending.get(photo).cancel();
    }
    
    public void update_reimport_raw_developments(LibraryPhoto photo) {
        fetch_photo_updates(photo).set_reimport_raw_developments(true);
        
        // cancel outstanding reimport
        if (raw_developments_reimport_pending.has_key(photo))
            raw_developments_reimport_pending.get(photo).cancel();
    }
    
    public File? get_editable_file(LibraryPhoto photo) {
        PhotoUpdates? updates = get_existing_photo_updates(photo);
        
        return (updates != null && updates.get_editable_file() != null) ? updates.get_editable_file()
            : photo.get_editable_file();
    }
    
    public Gee.Collection<File>? get_raw_development_files(LibraryPhoto photo) {
        PhotoUpdates? updates = get_existing_photo_updates(photo);
        
        return (updates != null && updates.get_raw_developer_files() != null) ? 
            updates.get_raw_developer_files() : photo.get_raw_developer_files();
    }
    
    public void update_editable_file(LibraryPhoto photo, File file) {
        fetch_photo_updates(photo).set_editable_file(file);
    }
    
    public void update_editable_file_info_altered(LibraryPhoto photo) {
        fetch_photo_updates(photo).set_editable_file_info_altered(true);
    }
    
    public void update_raw_development_file(LibraryPhoto photo, File file) {
        fetch_photo_updates(photo).add_raw_developer_file(file);
    }
    
    public void update_raw_development_file_info_altered(LibraryPhoto photo) {
        fetch_photo_updates(photo).set_raw_developer_file_info_altered(true);
    }
    
    public void update_editable_file_in_alteration(LibraryPhoto photo, bool in_alteration) {
        fetch_photo_updates(photo).set_editable_in_alteration(in_alteration);
    }
    
    public void update_editable_file_alterations_completed(LibraryPhoto photo, FileInfo info) {
        fetch_photo_updates(photo).set_editable_file_info(info);
        fetch_photo_updates(photo).set_editable_in_alteration(false);
    }
    
    public void update_raw_development_file_in_alteration(LibraryPhoto photo, bool in_alteration) {
        fetch_photo_updates(photo).set_raw_development_in_alteration(in_alteration);
    }
    
    public void update_raw_development_file_alterations_completed(LibraryPhoto photo) {
        fetch_photo_updates(photo).set_raw_development_in_alteration(false);
    }
    
    public void update_revert_to_master(LibraryPhoto photo) {
        fetch_photo_updates(photo).set_revert_to_master(true);
    }
    
    protected override void process_updates(Gee.Collection<MonitorableUpdates> all_updates,
        TransactionController controller, ref int op_count) throws Error {
        base.process_updates(all_updates, controller, ref op_count);
        
        Gee.Map<LibraryPhoto, File> set_editable_file = null;
        Gee.Map<LibraryPhoto, FileInfo> set_editable_file_info = null;
        Gee.Map<LibraryPhoto, Gee.Collection<File>> set_raw_developer_files = null;
        Gee.ArrayList<LibraryPhoto> revert_to_master = null;
        Gee.ArrayList<LibraryPhoto> reimport_master = null;
        Gee.ArrayList<LibraryPhoto> reimport_editable = null;
        Gee.ArrayList<LibraryPhoto> reimport_raw_developments = null;
        int reimport_job_count = 0;
        
        foreach (MonitorableUpdates monitorable_updates in all_updates) {
            if (op_count >= MAX_OPERATIONS_PER_CYCLE)
                break;
            
            PhotoUpdates? updates = monitorable_updates as PhotoUpdates;
            if (updates == null)
                continue;
            
            if (updates.get_editable_file() != null) {
                if (set_editable_file == null)
                    set_editable_file = new Gee.HashMap<LibraryPhoto, File>();
                
                set_editable_file.set(updates.photo, updates.get_editable_file());
                updates.set_editable_file(null);
                op_count++;
            }
            
            if (updates.get_editable_file_info() != null) {
                if (set_editable_file_info == null)
                    set_editable_file_info = new Gee.HashMap<LibraryPhoto, FileInfo>();
                
                set_editable_file_info.set(updates.photo, updates.get_editable_file_info());
                updates.set_editable_file_info(null);
                op_count++;
            }
            
            if (updates.get_raw_developer_files() != null) {
                if (set_raw_developer_files == null)
                    set_raw_developer_files = new Gee.HashMap<LibraryPhoto, Gee.Collection<File>>();
                
                set_raw_developer_files.set(updates.photo, updates.get_raw_developer_files());
                updates.clear_raw_developer_files();
                op_count++;
            }
            
            if (updates.is_revert_to_master()) {
                if (revert_to_master == null)
                    revert_to_master = new Gee.ArrayList<LibraryPhoto>();
                
                if (revert_to_master.size < MAX_REVERTS_PER_CYCLE) {
                    revert_to_master.add(updates.photo);
                    updates.set_revert_to_master(false);
                }
                op_count++;
            }
            
            if (updates.is_reimport_master() && reimport_job_count < MAX_REIMPORT_JOBS_PER_CYCLE) {
                if (reimport_master == null)
                    reimport_master = new Gee.ArrayList<LibraryPhoto>();
                
                reimport_master.add(updates.photo);
                updates.set_reimport_master(false);
                reimport_job_count++;
                op_count++;
            }
            
            if (updates.is_reimport_editable() && reimport_job_count < MAX_REIMPORT_JOBS_PER_CYCLE) {
                if (reimport_editable == null)
                    reimport_editable = new Gee.ArrayList<LibraryPhoto>();
                
                reimport_editable.add(updates.photo);
                updates.set_reimport_editable(false);
                reimport_job_count++;
                op_count++;
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
        
        if (reimport_raw_developments != null) {
            mdbg("Reimporting %d raw developments".printf(reimport_raw_developments.size));
            
            foreach (LibraryPhoto photo in reimport_raw_developments) {
                assert(!raw_developments_reimport_pending.has_key(photo));
                
                ReimportRawDevelopmentJob job = new ReimportRawDevelopmentJob(this, photo);
                raw_developments_reimport_pending.set(photo, job);
                workers.enqueue(job);
            }
        }
    }
    
    private void on_master_reimported(BackgroundJob j) {
        ReimportMasterJob job = (ReimportMasterJob) j;
        
        // no longer pending
        bool removed = master_reimport_pending.unset(job.photo);
        assert(removed);
        
        if (job.err != null) {
            critical("Unable to reimport %s due to master file changing: %s", job.photo.to_string(),
                job.err.message);
            
            update_offline(job.photo);
            
            return;
        }
        
        if (!job.mark_online) {
            // the prepare_for_reimport_master failed, photo is now considered offline
            update_offline(job.photo);
            
            return;
        }
        
        try {
            job.photo.finish_reimport_master(job.reimport_state);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // now considered online
        if (job.photo.is_offline())
            update_online(job.photo);
        
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
    
    private void on_raw_development_reimported(BackgroundJob j) {
        ReimportRawDevelopmentJob job = (ReimportRawDevelopmentJob) j;
        
        // no longer pending
        bool removed = raw_developments_reimport_pending.unset(job.photo);
        assert(removed);
        
        if (job.err != null) {
            critical("Unable to reimport raw development %s: %s", job.photo.to_string(), job.err.message);
            
            return;
        }
        
        try {
            job.photo.finish_reimport_raw_development(job.state);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        mdbg("Reimported raw development for %s".printf(job.photo.to_string()));
    }
    
    private void on_raw_development_reimport_cancelled(BackgroundJob j) {
        bool removed = raw_developments_reimport_pending.unset(((ReimportRawDevelopmentJob) j).photo);
        assert(removed);
    }
}

