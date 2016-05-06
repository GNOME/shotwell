/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class VideoUpdates : MonitorableUpdates {
    public Video video;
    
    private bool check_interpretable = false;
    
    public VideoUpdates(Video video) {
        base (video);
        
        this.video = video;
    }
    
    public virtual void set_check_interpretable(bool check) {
        check_interpretable = check;
    }
    
    public override void mark_online() {
        base.mark_online();
        
        set_check_interpretable(true);
    }
    
    public bool is_check_interpretable() {
        return check_interpretable;
    }
    
    public override bool is_all_updated() {
        return (check_interpretable == false) && base.is_all_updated();
    }
}

private class VideoMonitor : MediaMonitor {
    private const int MAX_INTERPRETABLE_CHECKS_PER_CYCLE = 5;
    
    // Performs interpretable check on video. In a background job because
    // this will create a new thumbnail for the video.
    private class VideoInterpretableCheckJob : BackgroundJob {
        // IN
        public Video video;
        
        // OUT
        public Video.InterpretableResults? results = null;
        
        public VideoInterpretableCheckJob(Video video, CompletionCallback? callback = null) {
            base (video, callback);
            this.video = video;
        }
        
        public override void execute() {
            results = video.check_is_interpretable();
        }
    }
    
    // Work queue for video thumbnailing.
    // Note: only using 1 thread. If we want to change this to use multiple
    // threads, we need to put a lock around background_jobs wherever it's modified.
    private Workers workers = new Workers(1, false);
    private uint64 background_jobs = 0;
    
    public VideoMonitor(Cancellable cancellable) {
        base (Video.global, cancellable);
                
        foreach (DataObject obj in Video.global.get_all()) {
            Video video = obj as Video;
            assert (video != null);
            if (!video.get_is_interpretable())
                set_check_interpretable(video, true);
        }
    }
    
    protected override MonitorableUpdates create_updates(Monitorable monitorable) {
        assert(monitorable is Video);
        
        return new VideoUpdates((Video) monitorable);
    }
    
    public override MediaSourceCollection get_media_source_collection() {
        return Video.global;
    }
    
    public override bool is_file_represented(File file) {
        VideoSourceCollection.State state;
        return get_state(file, out state) != null;
    }
    
    public override MediaMonitor.DiscoveredFile notify_file_discovered(File file, FileInfo info,
        out Monitorable monitorable) {
        VideoSourceCollection.State state;
        Video? video = get_state(file, out state);
        if (video == null) {
            monitorable = null;
            
            return MediaMonitor.DiscoveredFile.UNKNOWN;
        }
        
        switch (state) {
            case VideoSourceCollection.State.ONLINE:
            case VideoSourceCollection.State.OFFLINE:
                monitorable = video;
                
                return MediaMonitor.DiscoveredFile.REPRESENTED;
            
            case VideoSourceCollection.State.TRASH:
            default:
                // ignored ... trash always stays in trash
                monitorable = null;
                
                return MediaMonitor.DiscoveredFile.IGNORE;
        }
    }
    
    public override Gee.Collection<Monitorable>? candidates_for_unknown_file(File file, FileInfo info,
        out MediaMonitor.DiscoveredFile result) {
        Gee.Collection<Video> matched = new Gee.ArrayList<Video>();
        Video.global.fetch_by_matching_backing(info, matched);
        
        result = MediaMonitor.DiscoveredFile.UNKNOWN;
        
        return matched;
    }
    
    public override bool notify_file_created(File file, FileInfo info) {
        VideoSourceCollection.State state;
        Video? video = get_state(file, out state);
        if (video == null)
            return false;
        
        update_online(video);
        
        return true;
    }
    
    public override bool notify_file_moved(File old_file, File new_file, FileInfo new_file_info) {
        VideoSourceCollection.State old_state;
        Video? old_video = get_state(old_file, out old_state);
        
        VideoSourceCollection.State new_state;
        Video? new_video = get_state(new_file, out new_state);
        
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
        
        if (old_video != null && new_video == null) {
            // 1.
            update_master_file(old_video, new_file);
        } else if (old_video == null && new_video != null) {
            // 2.
            set_check_interpretable(new_video, true);
        } else if (old_video == null && new_video == null) {
            // 3.
            return false;
        } else {
            assert(old_video != null && new_video != null);
            
            // 4.
            update_offline(old_video);
            set_check_interpretable(new_video, true);
        }
        
        return true;
    }
    
    public override bool notify_file_altered(File file) {
        VideoSourceCollection.State state;
        return get_state(file, out state) != null;
    }
    
    public override bool notify_file_attributes_altered(File file) {
        VideoSourceCollection.State state;
        Video? video = get_state(file, out state);
        if (video == null)
            return false;
        
        update_master_file_info_altered(video);
        update_master_file_in_alteration(video, true);
        
        return true;
    }
    
    public override bool notify_file_alteration_completed(File file, FileInfo info) {
        VideoSourceCollection.State state;
        Video? video = get_state(file, out state);
        if (video == null)
            return false;
        
        update_master_file_alterations_completed(video, info);
        
        return true;
    }
    
    public override bool notify_file_deleted(File file) {
        VideoSourceCollection.State state;
        Video? video = get_state(file, out state);
        if (video == null)
            return false;
        
        update_master_file_in_alteration(video, false);
        update_offline(video);
        
        return true;
    }
    
    private Video? get_state(File file, out VideoSourceCollection.State state) {
        File? real_file = null;
        foreach (Monitorable monitorable in get_monitorables()) {
            Video video = (Video) monitorable;
            
            VideoUpdates? updates = get_existing_video_updates(video);
            if (updates == null)
                continue;
            
            if (updates.get_master_file() != null && updates.get_master_file().equal(file)) {
                real_file = video.get_master_file();
                
                break;
            }
        }
        
        return Video.global.get_state_by_file(real_file ?? file, out state);
    }
    
    public VideoUpdates fetch_video_updates(Video video) {
        VideoUpdates? updates = fetch_updates(video) as VideoUpdates;
        assert(updates != null);
        
        return updates;
    }
    
    public VideoUpdates? get_existing_video_updates(Video video) {
        return get_existing_updates(video) as VideoUpdates;
    }
    
    public void set_check_interpretable(Video video, bool check) {
        fetch_video_updates(video).set_check_interpretable(check);
    }
    
    protected override void process_updates(Gee.Collection<MonitorableUpdates> all_updates,
        TransactionController controller, ref int op_count) throws Error {
        base.process_updates(all_updates, controller, ref op_count);
        
        Gee.ArrayList<Video>? check = null;
        
        foreach (MonitorableUpdates monitorable_updates in all_updates) {
            if (op_count >= MAX_OPERATIONS_PER_CYCLE)
                break;
            
            // use a separate limit on interpretable checks because they're more expensive than
            // simple database commands
            if (check != null && check.size >= MAX_INTERPRETABLE_CHECKS_PER_CYCLE)
                break;
            
            VideoUpdates? updates = monitorable_updates as VideoUpdates;
            if (updates == null)
                continue;
            
            if (updates.is_check_interpretable()) {
                if (check == null)
                    check = new Gee.ArrayList<Video>();
                
                check.add(updates.video);
                updates.set_check_interpretable(false);
                op_count++;
            }
        }
        
        if (check != null) {
            mdbg("Checking interpretable for %d videos".printf(check.size));
            
            Video.notify_offline_thumbs_regenerated();
            
            background_jobs += check.size;
            foreach (Video video in check)
                workers.enqueue(new VideoInterpretableCheckJob(video, on_interpretable_check_complete));
        }
    }
    
    void on_interpretable_check_complete(BackgroundJob j) {
        VideoInterpretableCheckJob job = (VideoInterpretableCheckJob) j;
        
        job.results.foreground_finish();
        
        --background_jobs;
        if (background_jobs <= 0)
            Video.notify_normal_thumbs_regenerated();
    }
}

