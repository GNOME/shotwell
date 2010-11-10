/* Copyright 2010 Yorba Foundation
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
    
    private const string[] INTERESTED_PHOTO_METADATA_DETAILS = { "name", "rating", "exposure-time" };
    
    private class CommitJob : BackgroundJob {
        public LibraryPhoto photo;
        public Gee.Set<string>? current_keywords;
        public Photo.ReimportMasterState reimport_master_state = null;
        public Photo.ReimportEditableState reimport_editable_state = null;
        public Error? err = null;
        
        public CommitJob(MetadataWriter owner, LibraryPhoto photo, Gee.Set<string>? keywords) {
            base (owner, owner.on_update_completed, new Cancellable());
            
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
            if (!photo.get_master_file_format().can_write_metadata())
                return;
            
            PhotoMetadata metadata = photo.get_master_metadata();
            if (update_metadata(metadata)) {
                LibraryMonitor.blacklist_file(photo.get_master_file());
                try {
                    photo.persist_master_metadata(metadata, out reimport_master_state);
                } finally {
                    LibraryMonitor.unblacklist_file(photo.get_master_file());
                }
            }
        }
        
        private void commit_editable() throws Error {
            if (!photo.has_editable() || !photo.get_editable_file_format().can_write_metadata())
                return;
            
            PhotoMetadata? metadata = photo.get_editable_metadata();
            assert(metadata != null);
            
            if (update_metadata(metadata)) {
                LibraryMonitor.blacklist_file(photo.get_editable_file());
                try {
                    photo.persist_editable_metadata(metadata, out reimport_editable_state);
                } finally {
                    LibraryMonitor.unblacklist_file(photo.get_editable_file());
                }
            }
        }
        
        private bool update_metadata(PhotoMetadata metadata) {
            bool changed = false;
            
            // title (caption)
            string? current_title = photo.get_title();
            if (current_title != metadata.get_title()) {
                metadata.set_title(current_title);
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
            if (!equal_sets(current_keywords, metadata.get_keywords())) {
                metadata.set_keywords(current_keywords);
                changed = true;
            }
            
            // orientation
            Orientation current_orientation = photo.get_orientation();
            if (current_orientation != metadata.get_orientation()) {
                metadata.set_orientation(current_orientation);
                changed = true;
            }
            
            // add the software name/version only if updating the metadata in the file
            if (changed)
                metadata.set_software(Resources.APP_TITLE, Resources.APP_VERSION);
            
            return changed;
        }
    }
    
    private static MetadataWriter instance = null;
    
    private Workers workers = new Workers(Workers.thread_per_cpu_minus_one(), false);
    private bool enabled = false;
    private HashTimedQueue<LibraryPhoto> dirty;
    private Gee.HashMap<LibraryPhoto, CommitJob> pending = new Gee.HashMap<LibraryPhoto, CommitJob>();
    private Gee.HashSet<string> interested_photo_details = new Gee.HashSet<string>();
    private LibraryPhoto? ignore_photo_alteration = null;
    private uint outstanding_total = 0;
    private uint outstanding_completed = 0;
    private bool closed = false;
    
    public signal void progress(uint completed, uint total);
    
    private MetadataWriter() {
        dirty = new HashTimedQueue<LibraryPhoto>(COMMIT_DELAY_MSEC, on_photo_dequeued);
        dirty.set_dequeue_spacing_msec(COMMIT_SPACING_MSEC);
        
        // convert all interested metadata Alteration details into lookup hash
        foreach (string detail in INTERESTED_PHOTO_METADATA_DETAILS)
            interested_photo_details.add(detail);
        
        // sync up with Config
        enabled = Config.get_instance().get_commit_metadata_to_masters();
        Config.get_instance().bool_changed.connect(on_config_bool_changed);
        
        // add all current photos to look for ones that are dirty and need updating
        force_rescan();
        
        LibraryPhoto.global.contents_altered.connect(on_photos_added_removed);
        LibraryPhoto.global.items_altered.connect(on_photos_altered);
        Tag.global.container_contents_altered.connect(on_tag_contents_altered);
        Tag.global.backlink_to_container_removed.connect(on_tag_backlink_removed);
        
        Application.get_instance().exiting.connect(on_application_exiting);
    }
    
    ~MetadataWriter() {
        Config.get_instance().bool_changed.disconnect(on_config_bool_changed);
        
        LibraryPhoto.global.contents_altered.disconnect(on_photos_added_removed);
        LibraryPhoto.global.items_altered.disconnect(on_photos_altered);
        Tag.global.container_contents_altered.disconnect(on_tag_contents_altered);
        Tag.global.backlink_to_container_removed.disconnect(on_tag_backlink_removed);
        
        Application.get_instance().exiting.disconnect(on_application_exiting);
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
        schedule_dirty((Gee.Collection<LibraryPhoto>) LibraryPhoto.global.get_all(), "force rescan");
    }
    
    public void close() {
        if (closed)
            return;
        
        cancel_all(true);
        
        closed = true;
    }
    
    private void on_config_bool_changed(string path, bool value) {
        if (path != Config.BOOL_COMMIT_METADATA_TO_MASTERS)
            return;
        
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
    
    private void on_photos_added_removed(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        // no reason to go through this exercise if auto-commit is disabled
        if (added != null && enabled)
            schedule_dirty((Gee.Collection<LibraryPhoto>) added, "added to LibraryPhoto.global");
        
        // want to cancel jobs no matter what, however
        if (removed != null) {
            foreach (DataObject object in removed)
                cancel_job((LibraryPhoto) object);
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
            photos_dirty(photos, "alteration", false);
    }
    
    private void on_tag_contents_altered(ContainerSource container, Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        Tag tag = (Tag) container;
        
        if (added != null) {
            Gee.ArrayList<LibraryPhoto> added_photos = new Gee.ArrayList<LibraryPhoto>();
            foreach (DataSource source in added) {
                LibraryPhoto photo =  source as LibraryPhoto;
                if (photo != null)
                    added_photos.add(photo);
            }
            
            photos_dirty(added_photos, "added to %s".printf(tag.to_string()), false);
        }
        
        if (removed != null) {
            // Unlike adding, a photo can be removed from a tag but still hold a backlink to it
            // (this happens when it goes offline and it's removed from the Tag ContainerSource,
            // but not technically "untagged").  Watch for this situation.
            SourceBacklink backlink = container.get_backlink();
            Gee.ArrayList<LibraryPhoto> actually_removed = new Gee.ArrayList<LibraryPhoto>();
            foreach (DataSource source in removed) {
                LibraryPhoto photo = source as LibraryPhoto;
                if (photo == null)
                    continue;
                
                if (!photo.has_backlink(backlink))
                    actually_removed.add(photo);
            }
            
            photos_dirty(actually_removed, "removed from %s".printf(tag.to_string()), false);
        }
    }
    
    private void on_tag_backlink_removed(ContainerSource container, Gee.Collection<DataSource> sources) {
        schedule_dirty((Gee.Collection<MediaSource>) sources,
            "backlink removed from %s".printf(container.to_string()));
    }
    
    private void schedule_dirty(Gee.Collection<MediaSource> media_sources, string reason) {
        Gee.ArrayList<LibraryPhoto> dirty = null;
        foreach (MediaSource media in media_sources) {
            LibraryPhoto? photo = media as LibraryPhoto;
            if (photo == null)
                continue;
            
            if (photo.is_master_metadata_dirty()) {
                if (dirty == null)
                    dirty = new Gee.ArrayList<LibraryPhoto>();
                
                dirty.add(photo);
            }
        }
        
        if (dirty != null)
            photos_dirty(dirty, reason, true);
    }
    
    private void photos_dirty(Gee.Collection<LibraryPhoto> photos, string reason, bool already_marked) {
        foreach (LibraryPhoto photo in photos) {
            // cancel all outstanding and pending jobs
            cancel_job(photo);
            
            if (dirty.contains(photo)) {
                bool removed = dirty.remove_first(photo);
                assert(removed);
                
                assert(!dirty.contains(photo));
            }
        }
        
        // mark all the photos as dirty
        if (!already_marked) {
            try {
                Photo.set_many_master_metadata_dirty(LibraryPhoto.global, photos, true);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
        }
        
        // ok to drop this on the floor, now that they're marked dirty (will attempt to write them
        // out the next time MetadataWriter runs)
        if (closed || !enabled)
            return;
        
        foreach (LibraryPhoto photo in photos) {
#if TRACE_METADATA_WRITER
            debug("Enqueuing %s for metadata commit: %s", photo.to_string(), reason);
#endif
            bool enqueued = dirty.enqueue(photo);
            assert(enqueued);
        }
        
        outstanding_total = photos.size + pending.size;
        outstanding_completed = 0;
    }
    
    private void cancel_all(bool wait) {
        dirty.clear();
        
        foreach (CommitJob job in pending.values)
            job.cancel();
        
        if (wait)
            workers.wait_for_empty_queue();
        
        pending.clear();
        
        outstanding_completed = 0;
        outstanding_total = 0;
        progress(outstanding_completed, outstanding_total);
    }
    
    private void cancel_job(LibraryPhoto photo) {
        if (pending.has_key(photo)) {
            pending.get(photo).cancel();
            pending.unset(photo);
        }
        
        if (outstanding_total > 0)
            outstanding_total--;
        
        if (outstanding_completed >= outstanding_total) {
            outstanding_completed = 0;
            outstanding_total = 0;
        }
        
        progress(outstanding_completed, outstanding_total);
    }
    
    private void on_photo_dequeued(LibraryPhoto photo) {
        assert(!pending.has_key(photo));
        
        if (!enabled)
            return;
        
        Gee.Set<string>? keywords = null;
        Gee.Collection<Tag>? tags = Tag.global.fetch_for_source(photo);
        if (tags != null) {
            keywords = new Gee.HashSet<string>();
            foreach (Tag tag in tags)
                keywords.add(tag.get_name());
        }
        
        CommitJob job = new CommitJob(this, photo, keywords);
        pending.set(photo, job);
        
#if TRACE_METADATA_WRITER
        debug("%s dequeued for metadata commit, %d pending", photo.to_string(), pending.size);
#endif
        
        workers.enqueue(job);
    }
    
    private void on_update_completed(BackgroundJob j) {
        CommitJob job = (CommitJob) j;
        
        if (job.err != null)
            warning("Unable to update metadata for %s: %s", job.photo.to_string(), job.err.message);
        
        bool removed = pending.unset(job.photo);
        assert(removed);
        
        if (++outstanding_completed >= outstanding_total) {
            outstanding_completed = 0;
            outstanding_total = 0;
            
            // fire this to specify a reset
            progress(outstanding_completed, outstanding_total);
        }
        
        if (job.reimport_master_state != null || job.reimport_editable_state != null) {
#if TRACE_METADATA_WRITER
            debug("[%u/%u] %s metadata committed", outstanding_completed, outstanding_total,
                job.photo.to_string());
#endif
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
            
            if (outstanding_total > 0)
                progress(outstanding_completed, outstanding_total);
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
    }
}

