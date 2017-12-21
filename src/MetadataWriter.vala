/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// MetadataWriter tracks LibraryPhotos for alterations to their metadata and commits those changes
// in a timely manner to their backing files.  Because only the MetadataWriter knows when the
// metadata has been properly committed, it is also responsible for updating the metadata-dirty
// flag in Photo.  Thus, MetadataWriter should *always* be running, even if the user has turned off
// the feature, so if they turn it on MetadataWriter can properly go out and update the backing
// files.

public class MetadataWriter : Object {
    public const uint COMMIT_DELAY_MSEC = 3000;
    public const uint COMMIT_SPACING_MSEC = 50;
    
    private const string[] INTERESTED_PHOTO_METADATA_DETAILS = { "name", "comment", "rating", "exposure-time" };
    
    private class CommitJob : BackgroundJob {
        public LibraryPhoto photo;
        public Gee.Set<string>? current_keywords;
        public Photo.ReimportMasterState reimport_master_state = null;
        public Photo.ReimportEditableState reimport_editable_state = null;
        public Error? err = null;
        public bool wrote_master = false;
        public bool wrote_editable = false;
        
        public CommitJob(MetadataWriter owner, LibraryPhoto photo, Gee.Set<string>? keywords) {
            base (owner, owner.on_update_completed, new Cancellable(), owner.on_update_cancelled);

            this.photo = photo;
            current_keywords = keywords;
        }

        public override void execute() {
            try {
                commit_master();
                commit_editable();
            } catch (Error err) {
                this.err = err;
            }
        }
        
        private void commit_master() throws Error {
            // If we have an editable, any orientation changes should be written only to it;
            // otherwise, we'll end up ruining the original, and as such, breaking the
            // ability to revert to it.
            bool skip_orientation = photo.has_editable();
            
            if (!photo.get_master_file_format().can_write_metadata())
                return;
            
            PhotoMetadata metadata = photo.get_master_metadata();
            if (update_metadata(metadata, skip_orientation)) {
                LibraryMonitor.blacklist_file(photo.get_master_file(), "MetadataWriter.commit_master");
                try {
                    photo.persist_master_metadata(metadata, out reimport_master_state);
                } finally {
                    LibraryMonitor.unblacklist_file(photo.get_master_file());
                }
            }
            
            wrote_master = true;
        }
        
        private void commit_editable() throws Error {
            if (!photo.has_editable() || !photo.get_editable_file_format().can_write_metadata())
                return;
            
            PhotoMetadata? metadata = photo.get_editable_metadata();
            assert(metadata != null);
            
            if (update_metadata(metadata)) {
                LibraryMonitor.blacklist_file(photo.get_editable_file(), "MetadataWriter.commit_editable");
                try {
                    photo.persist_editable_metadata(metadata, out reimport_editable_state);
                } finally {
                    LibraryMonitor.unblacklist_file(photo.get_editable_file());
                }
            }
            
            wrote_editable = true;
        }
        
        private bool update_metadata(PhotoMetadata metadata, bool skip_orientation = false) {
            bool changed = false;
            
            // title (caption)
            string? current_title = photo.get_title();
            if (current_title != metadata.get_title()) {
                metadata.set_title(current_title);
                changed = true;
            }
            
            // comment
            string? current_comment = photo.get_comment();
            if (current_comment != metadata.get_comment()) {
                metadata.set_comment(current_comment);
                changed = true;
            }
            
            // rating
            Rating current_rating = photo.get_rating();
            if (current_rating != metadata.get_rating()) {
                metadata.set_rating(current_rating);
                changed = true;
            }
            
            // exposure date/time
            time_t current_exposure_time = photo.get_exposure_time();
            time_t metadata_exposure_time = 0;
            MetadataDateTime? metadata_exposure_date_time = metadata.get_exposure_date_time();
            if (metadata_exposure_date_time != null)
                metadata_exposure_time = metadata_exposure_date_time.get_timestamp();
            if (current_exposure_time != metadata_exposure_time) {
                metadata.set_exposure_date_time(current_exposure_time != 0
                    ? new MetadataDateTime(current_exposure_time)
                    : null);
                changed = true;
            }

            // tags (keywords) ... replace (or clear) entirely rather than union or intersection
            Gee.Set<string> safe_keywords = new Gee.HashSet<string>();

            // Since the tags are stored in an image file's `keywords' field in
            // non-hierarchical format, before checking whether the tags that
            // should be associated with this image have been written, we'll need
            // to produce non-hierarchical versions of the tags to be tested.
            // get_user_visible_name() does this by returning the most deeply-nested
            // portion of a given hierarchical tag; that is, for a tag "/a/b/c",
            // it'll return "c", which is exactly the form we want here.
            if (current_keywords != null) {
                foreach(string tmp in current_keywords) {
                    Tag tag = Tag.for_path(tmp);
                    safe_keywords.add(tag.get_user_visible_name());
                }
            }

            if (!equal_sets(safe_keywords, metadata.get_keywords())) {
                metadata.set_keywords(current_keywords);
                changed = true;
            }

            // orientation
            if (!skip_orientation) {
                Orientation current_orientation = photo.get_orientation();
                if (current_orientation != metadata.get_orientation()) {
                    metadata.set_orientation(current_orientation);
                    changed = true;
                }
            }

            // add the software name/version only if updating the metadata in the file
            if (changed)
                metadata.set_software(Resources.APP_TITLE, Resources.APP_VERSION);
            
            return changed;
        }
    }
    
    private static MetadataWriter instance = null;
    
    private Workers workers = new Workers(1, false);
    private bool enabled = false;
    private HashTimedQueue<LibraryPhoto> dirty;
    private Gee.HashMap<LibraryPhoto, CommitJob> pending = new Gee.HashMap<LibraryPhoto, CommitJob>();
    private Gee.HashSet<CommitJob> pending_cancel = new Gee.HashSet<CommitJob>();
    private Gee.HashSet<string> interested_photo_details = new Gee.HashSet<string>();
    private LibraryPhoto? ignore_photo_alteration = null;
    private uint outstanding_total = 0;
    private uint outstanding_completed = 0;
    private bool closed = false;
    private int pause_count = 0;
    private Gee.HashSet<LibraryPhoto> importing_photos = new Gee.HashSet<LibraryPhoto>();
    
    public signal void progress(uint completed, uint total);
    
    private MetadataWriter() {
        dirty = new HashTimedQueue<LibraryPhoto>(COMMIT_DELAY_MSEC, on_photo_dequeued);
        dirty.set_dequeue_spacing_msec(COMMIT_SPACING_MSEC);
        
        // start with the writer paused, waiting for the LibraryMonitor initial discovery to
        // complete (note that if the LibraryMonitor is ever disabled, the MetadataWriter will not
        // start on its own)
        pause();
        
        // convert all interested metadata Alteration details into lookup hash
        foreach (string detail in INTERESTED_PHOTO_METADATA_DETAILS)
            interested_photo_details.add(detail);

        // sync up with the configuration system
        enabled = Config.Facade.get_instance().get_commit_metadata_to_masters();
        Config.Facade.get_instance().commit_metadata_to_masters_changed.connect(on_config_changed);
        
        // add all current photos to look for ones that are dirty and need updating
        force_rescan();
        
        LibraryPhoto.global.media_import_starting.connect(on_importing_photos);
        LibraryPhoto.global.media_import_completed.connect(on_photos_imported);
        LibraryPhoto.global.contents_altered.connect(on_photos_added_removed);
        LibraryPhoto.global.items_altered.connect(on_photos_altered);
        LibraryPhoto.global.frozen.connect(on_collection_frozen);
        LibraryPhoto.global.thawed.connect(on_collection_thawed);
        LibraryPhoto.global.items_destroyed.connect(on_photos_destroyed);
        
        Tag.global.items_altered.connect(on_tags_altered);
        Tag.global.container_contents_altered.connect(on_tag_contents_altered);
        Tag.global.backlink_to_container_removed.connect(on_tag_backlink_removed);
        Tag.global.frozen.connect(on_collection_frozen);
        Tag.global.thawed.connect(on_collection_thawed);
        
        Application.get_instance().exiting.connect(on_application_exiting);
        
        LibraryMonitorPool.get_instance().monitor_installed.connect(on_monitor_installed);
        LibraryMonitorPool.get_instance().monitor_destroyed.connect(on_monitor_destroyed);
    }
    
    ~MetadataWriter() {
        Config.Facade.get_instance().commit_metadata_to_masters_changed.disconnect(on_config_changed);
        
        LibraryPhoto.global.media_import_starting.disconnect(on_importing_photos);
        LibraryPhoto.global.media_import_completed.disconnect(on_photos_imported);
        LibraryPhoto.global.contents_altered.disconnect(on_photos_added_removed);
        LibraryPhoto.global.items_altered.disconnect(on_photos_altered);
        LibraryPhoto.global.frozen.disconnect(on_collection_frozen);
        LibraryPhoto.global.thawed.disconnect(on_collection_thawed);
        LibraryPhoto.global.items_destroyed.disconnect(on_photos_destroyed);
        
        Tag.global.items_altered.disconnect(on_tags_altered);
        Tag.global.container_contents_altered.disconnect(on_tag_contents_altered);
        Tag.global.backlink_to_container_removed.disconnect(on_tag_backlink_removed);
        Tag.global.frozen.disconnect(on_collection_frozen);
        Tag.global.thawed.disconnect(on_collection_thawed);
        
        Application.get_instance().exiting.disconnect(on_application_exiting);
        
        LibraryMonitorPool.get_instance().monitor_installed.disconnect(on_monitor_installed);
        LibraryMonitorPool.get_instance().monitor_destroyed.disconnect(on_monitor_destroyed);
    }
    
    public static void init() {
        instance = new MetadataWriter();
    }
    
    public static void terminate() {
        if (instance != null)
            instance.close();
        
        instance = null;
    }
    
    public static MetadataWriter get_instance() {
        return instance;
    }
    
    // This will examine all photos for dirty metadata and schedule commits if enabled.
    public void force_rescan() {
        schedule_if_dirty((Gee.Collection<LibraryPhoto>) LibraryPhoto.global.get_all(), "force rescan");
    }
    
    public void pause() {
        if (pause_count++ != 0)
            return;
        
        dirty.pause();
        
        progress(0, 0);
    }
    
    public void unpause() {
        if (pause_count == 0 || --pause_count != 0)
            return;
        
        dirty.unpause();
    }
    
    public void close() {
        if (closed)
            return;
        
        cancel_all(true);
        
        closed = true;
    }
    
    private void on_config_changed() {
        bool value = Config.Facade.get_instance().get_commit_metadata_to_masters();
        
        if (enabled == value)
            return;
        
        enabled = value;
        if (enabled)
            force_rescan();
        else
            cancel_all(false);
    }
    
    private void on_application_exiting() {
        close();
    }
    
    private void on_monitor_installed(LibraryMonitor monitor) {
        monitor.discovery_completed.connect(on_discovery_completed);
    }

    private void on_monitor_destroyed(LibraryMonitor monitor) {
        monitor.discovery_completed.disconnect(on_discovery_completed);
    }
    
    private void on_discovery_completed() {
        unpause();
    }
    
    private void on_collection_frozen() {
        pause();
    }
    
    private void on_collection_thawed() {
        unpause();
    }
    
    private void on_importing_photos(Gee.Collection<MediaSource> media_sources) {
        importing_photos.add_all((Gee.Collection<LibraryPhoto>) media_sources);
    }
    
    private void on_photos_imported(Gee.Collection<MediaSource> media_sources) {
        importing_photos.remove_all((Gee.Collection<LibraryPhoto>) media_sources);
    }
    
    private void on_photos_added_removed(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        // no reason to go through this exercise if auto-commit is disabled
        if (added != null && enabled)
            schedule_if_dirty((Gee.Iterable<LibraryPhoto>) added, "added to LibraryPhoto.global");
        
        // want to cancel jobs no matter what, however
        if (removed != null) {
            bool cancelled = false;
            foreach (DataObject object in removed)
                cancelled = cancel_job((LibraryPhoto) object) || cancelled;
            
            if (cancelled)
                progress(outstanding_completed, outstanding_total);
        }
    }
    
    private void on_photos_altered(Gee.Map<DataObject, Alteration> items) {
        Gee.HashSet<LibraryPhoto> photos = null;
        foreach (DataObject object in items.keys) {
            LibraryPhoto photo = (LibraryPhoto) object;
            
            // ignore this signal on this photo (means it's coming up from completing the metadata
            // update)
            if (photo == ignore_photo_alteration)
                continue;
            
            Alteration alteration = items.get(object);
            
            // if an image:orientation detail, write that out
            if (alteration.has_detail("image", "orientation")) {
                if (photos == null)
                    photos = new Gee.HashSet<LibraryPhoto>();
                
                photos.add(photo);
                
                continue;
            }
            
            // get all "metadata" details for this alteration
            Gee.Collection<string>? details = alteration.get_details("metadata");
            if (details == null)
                continue;
            
            // only enqueue an update if an alteration of metadata actually written out occurs
            foreach (string detail in details) {
                if (interested_photo_details.contains(detail)) {
                    if (photos == null)
                        photos = new Gee.HashSet<LibraryPhoto>();
                    
                    photos.add(photo);
                    
                    break;
                }
            }
        }
        
        if (photos != null)
            photos_are_dirty(photos, "alteration", false);
    }
    
    private void on_photos_destroyed(Gee.Collection<DataSource> destroyed) {
        foreach (DataSource source in destroyed) {
            LibraryPhoto photo = (LibraryPhoto) source;
            cancel_job(photo);
            importing_photos.remove(photo);
        }
    }
    
    private void on_tags_altered(Gee.Map<DataObject, Alteration> map) {
        Gee.HashSet<LibraryPhoto>? photos = null;
        foreach (DataObject object in map.keys) {
            if (!map.get(object).has_detail("metadata", "name"))
                continue;
            
            if (photos == null)
                photos = new Gee.HashSet<LibraryPhoto>();
            
            foreach (MediaSource media in ((Tag) object).get_sources()) {
                LibraryPhoto? photo = media as LibraryPhoto;
                if (photo != null)
                    photos.add(photo);
            }
        }
        
        if (photos != null)
            photos_are_dirty(photos, "tag renamed", false);
    }
    
    private void on_tag_contents_altered(ContainerSource container, Gee.Collection<DataSource>? added,
        bool relinking, Gee.Collection<DataSource>? removed, bool unlinking) {
        Tag tag = (Tag) container;
        
        if (added != null && !relinking) {
            Gee.ArrayList<LibraryPhoto> added_photos = new Gee.ArrayList<LibraryPhoto>();
            foreach (DataSource source in added) {
                LibraryPhoto? photo =  source as LibraryPhoto;
                if (photo != null && !importing_photos.contains(photo))
                    added_photos.add(photo);
            }
            
            photos_are_dirty(added_photos, "added to %s".printf(tag.to_string()), false);
        }
        
        if (removed != null && !unlinking) {
            Gee.ArrayList<LibraryPhoto> removed_photos = new Gee.ArrayList<LibraryPhoto>();
            foreach (DataSource source in removed) {
                LibraryPhoto? photo = source as LibraryPhoto;
                if (photo != null)
                    removed_photos.add(photo);
            }
            
            photos_are_dirty(removed_photos, "removed from %s".printf(tag.to_string()), false);
        }
    }
    
    private void on_tag_backlink_removed(ContainerSource container, Gee.Collection<DataSource> sources) {
        Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        foreach (DataSource source in sources) {
            LibraryPhoto? photo = source as LibraryPhoto;
            if (photo != null)
                photos.add(photo);
        }
        
        photos_are_dirty(photos, "backlink removed from %s".printf(container.to_string()), false);
    }
    
    private void count_enqueued_work(int count, bool report) {
        outstanding_total += count;
        
#if TRACE_METADATA_WRITER
        debug("[%u/%u] %d metadata jobs enqueued", outstanding_completed, outstanding_total, count);
#endif
        
        if (report)
            progress(outstanding_completed, outstanding_total);
    }
    
    private void count_cancelled_work(int count, bool report) {
        outstanding_total = (outstanding_total >= count) ? outstanding_total - count : 0;
        if (outstanding_completed >= outstanding_total) {
            outstanding_completed = 0;
            outstanding_total = 0;
        }
        
#if TRACE_METADATA_WRITER
        debug("[%u/%u] %d metadata jobs cancelled", outstanding_completed, outstanding_total, count);
#endif
        
        if (report)
            progress(outstanding_completed, outstanding_total);
    }
    
    private void count_completed_work(int count, bool report) {
        outstanding_completed += count;
        if (outstanding_completed >= outstanding_total) {
            outstanding_completed = 0;
            outstanding_total = 0;
        }
        
#if TRACE_METADATA_WRITER
        debug("[%u/%u] %d metadata jobs completed", outstanding_completed, outstanding_total, count);
#endif
        
        if (report)
            progress(outstanding_completed, outstanding_total);
    }
    
    private void schedule_if_dirty(Gee.Iterable<MediaSource> media_sources, string reason) {
        Gee.ArrayList<LibraryPhoto> photos = null;
        foreach (MediaSource media in media_sources) {
            LibraryPhoto? photo = media as LibraryPhoto;
            if (photo == null)
                continue;
            
            // if in the importing stage, do not schedule for commit
            if (importing_photos.contains(photo))
                continue;
            
            if (photo.is_master_metadata_dirty()) {
                if (photos == null)
                    photos = new Gee.ArrayList<LibraryPhoto>();
                
                photos.add(photo);
            }
        }
        
        if (photos != null)
            photos_are_dirty(photos, reason, true);
    }
    
    // No photos are dirty.  The human body is a thing of beauty and grace.
    private void photos_are_dirty(Gee.Collection<LibraryPhoto> photos, string reason, bool already_marked) {
        if (photos.size == 0)
            return;
        
        // cancel all outstanding and pending jobs
        foreach (LibraryPhoto photo in photos)
            cancel_job(photo);
        
        // mark all the photos as dirty
        if (!already_marked) {
            try {
                LibraryPhoto.global.transaction_controller.begin();
                
                foreach (LibraryPhoto photo in photos)
                    photo.set_master_metadata_dirty(true);
                
                LibraryPhoto.global.transaction_controller.commit();
            } catch (Error err) {
                if (err is DatabaseError)
                    AppWindow.database_error((DatabaseError) err);
                else
                    error("Unable to mark metadata as dirty: %s", err.message);
            }
        }
        
        // ok to drop this on the floor, now that they're marked dirty (will attempt to write them
        // out the next time MetadataWriter runs)
        if (closed || !enabled)
            return;
        
#if TRACE_METADATA_WRITER
        debug("[%s] adding %d photos to dirty list", reason, photos.size);
#endif
        
        foreach (LibraryPhoto photo in photos) {
            bool enqueued = dirty.enqueue(photo);
            assert(enqueued);
        }
        
        count_enqueued_work(photos.size, true);
    }
    
    private void cancel_all(bool wait) {
        dirty.clear();
        
        foreach (CommitJob job in pending.values)
            job.cancel();
        
        if (wait)
            workers.wait_for_empty_queue();
        
        count_cancelled_work(int.MAX, true);
    }
    
    private bool cancel_job(LibraryPhoto photo) {
        bool cancelled = false;
        
        if (pending.has_key(photo)) {
            CommitJob j = (CommitJob) pending.get(photo);
            pending_cancel.add(j);
            j.cancel();
            pending.unset(photo);
            cancelled = true;
        }
        
        if (dirty.contains(photo)) {
            bool removed = dirty.remove_first(photo);
            assert(removed);
            
            assert(!dirty.contains(photo));
            
            count_cancelled_work(1, false);
            cancelled = true;
        }
        
        return cancelled;
    }
    
    private void on_photo_dequeued(LibraryPhoto photo) {
        if (!enabled) {
            count_cancelled_work(1, true);
            
            return;
        }
        
        Gee.Set<string>? keywords = null;
        Gee.Collection<Tag>? tags = Tag.global.fetch_for_source(photo);
        if (tags != null) {
            keywords = new Gee.HashSet<string>();
            foreach (Tag tag in tags)
                keywords.add(tag.get_name());
        }
        
        // check if there is already a job for that photo. if yes, cancel it.
        if (pending.has_key(photo))
            cancel_job(photo);

        CommitJob job = new CommitJob(this, photo, keywords);
        pending.set(photo, job);
        
#if TRACE_METADATA_WRITER
        debug("%s dequeued for metadata commit, %d pending", photo.to_string(), pending.size);
#endif
        
        workers.enqueue(job);
    }
    
    private void on_update_completed(BackgroundJob j) {
        CommitJob job = (CommitJob) j;
        
        if (job.err != null) {
            warning("Unable to write metadata to %s: %s", job.photo.to_string(), job.err.message);
        } else {
            if (job.wrote_master)
                message("Completed writing metadata to %s", job.photo.get_master_file().get_path());
            else
                message("Unable to write metadata to %s", job.photo.get_master_file().get_path());
            
            if (job.photo.get_editable_file() != null) {
                if (job.wrote_editable)
                    message("Completed writing metadata to %s", job.photo.get_editable_file().get_path());
                else
                    message("Unable to write metadata to %s", job.photo.get_editable_file().get_path());
            }
        }
        
        bool removed = pending.unset(job.photo);
        assert(removed);
        
        // since there's potentially multiple state-change operations here, use the transaction
        // controller
        LibraryPhoto.global.transaction_controller.begin();
        
        if (job.reimport_master_state != null || job.reimport_editable_state != null) {
            // finish_update_*_metadata are going to issue an "altered" signal, and we want to 
            // ignore it
            assert(ignore_photo_alteration == null);
            ignore_photo_alteration = job.photo;
            try {
                if (job.reimport_master_state != null)
                    job.photo.finish_update_master_metadata(job.reimport_master_state);
                
                if (job.reimport_editable_state != null)
                    job.photo.finish_update_editable_metadata(job.reimport_editable_state);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            } finally {
                // this assertion guards against reentrancy
                assert(ignore_photo_alteration == job.photo);
                ignore_photo_alteration = null;
            }
        } else {
#if TRACE_METADATA_WRITER
            debug("[%u/%u] No metadata changes for %s", outstanding_completed, outstanding_total,
                job.photo.to_string());
#endif
        }
        
        try {
            job.photo.set_master_metadata_dirty(false);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        LibraryPhoto.global.transaction_controller.commit();
        
        count_completed_work(1, true);
    }
    
    private void on_update_cancelled(BackgroundJob j) {
        bool removed = pending_cancel.remove((CommitJob) j);
        assert(removed);
        
        count_cancelled_work(1, true);
    }
}

