/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class MediaSource : ThumbnailSource {
    public virtual signal void master_replaced(File old_file, File new_file) {
    }
    
    public MediaSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    protected static inline uint64 internal_add_flags(uint64 flags, uint64 selector) {
        return (flags | selector);
    }

    protected static inline uint64 internal_remove_flags(uint64 flags, uint64 selector) {
        return (flags & ~selector);
    }

    protected static inline bool internal_is_flag_set(uint64 flags, uint64 selector) {
        return ((flags & selector) != 0);
    }

    protected virtual void notify_master_replaced(File old_file, File new_file) {
        master_replaced(old_file, new_file);
    }

    protected abstract bool internal_set_event_id(EventID id);

    protected bool delete_original_file() {
        bool ret = false;
        File file = get_file();
        
        try {
            ret = file.trash(null);
        } catch (Error err) {
            // log error but don't abend, as this is not fatal to operation (also, could be
            // the photo is removed because it could not be found during a verify)
            message("Unable to move original photo %s to trash: %s", file.get_path(), err.message);
        }
        
        // remove empty directories corresponding to imported path, but only if file is located
        // inside the user's Pictures directory
        if (file.has_prefix(AppDirs.get_import_dir())) {
            File parent = file;
            for (int depth = 0; depth < LibraryFiles.DIRECTORY_DEPTH; depth++) {
                parent = parent.get_parent();
                if (parent == null)
                    break;
                
                try {
                    if (!query_is_directory_empty(parent))
                        break;
                } catch (Error err) {
                    warning("Unable to query file info for %s: %s", parent.get_path(), err.message);
                    
                    break;
                }
                
                try {
                    parent.delete(null);
                    debug("Deleted empty directory %s", parent.get_path());
                } catch (Error err) {
                    // again, log error but don't abend
                    message("Unable to delete empty directory %s: %s", parent.get_path(),
                        err.message);
                }
            }
        }
        
        return ret;
    }

    public abstract File get_file();
    public abstract File get_master_file();
    public abstract void set_master_file(File file);
    public abstract uint64 get_filesize();
    
    public abstract string? get_title();
    public abstract void set_title(string? title);

    public abstract Rating get_rating();
    public abstract void set_rating(Rating rating);
    public abstract void increase_rating();
    public abstract void decrease_rating();
    
    public abstract Dimensions get_dimensions();

    // A preview pixbuf is one that can be quickly generated and scaled as a preview. For media
    // type that support transformations (i.e. photos) it is fully transformed.
    //
    // Note that an unscaled scaling is not considered a performance-killer for this method, 
    // although the quality of the pixbuf may be quite poor compared to the actual unscaled 
    // transformed pixbuf.
    public abstract Gdk.Pixbuf get_preview_pixbuf(Scaling scaling) throws Error;

    public abstract bool is_trashed();
    public abstract void trash();
    public abstract void untrash();

    public abstract bool is_offline();
    public abstract void mark_offline();
    public abstract void mark_online();
    
    public abstract string get_master_md5();

    // WARNING: some child classes of MediaSource (e.g. Photo) implement this method in a
    //          non-thread safe manner for efficiency.
    public abstract EventID get_event_id();

    public Event? get_event() {
        EventID event_id = get_event_id();
        
        return event_id.is_valid() ? Event.global.fetch(event_id) : null;
    }

    public bool set_event(Event? event) {
        EventID event_id = (event != null) ? event.get_event_id() : EventID();
        if (get_event_id().id == event_id.id)
            return true;
        
        Event? old_event = get_event();
        
        bool committed = internal_set_event_id(event_id);
        if (committed) {
            if (old_event != null)
                old_event.detach(this);

            if (event != null)
                event.attach(this);
            
            notify_altered(new Alteration("metadata", "event"));
        }

        return committed;
    }
    
    public abstract time_t get_exposure_time();

    public abstract ImportID get_import_id();
}

public class MediaSourceHoldingTank : DatabaseSourceHoldingTank {
    private Gee.HashMap<File, MediaSource> master_file_map = new Gee.HashMap<File, MediaSource>(
        file_hash, file_equal);
    
    public MediaSourceHoldingTank(MediaSourceCollection sources,
        SourceHoldingTank.CheckToKeep check_to_keep, GetSourceDatabaseKey get_key) {
        base (sources, check_to_keep, get_key);
    }
    
    public MediaSource? fetch_by_master_file(File file) {
        return master_file_map.get(file);
    }
    
    public MediaSource? fetch_by_md5(string md5) {
        foreach (MediaSource source in master_file_map.values) {
            if (source.get_master_md5() == md5) {
                return source;
            }
        }
        
        return null;
    }
    
    protected override void notify_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        if (added != null) {
            foreach (DataSource source in added) {
                MediaSource media_source = (MediaSource) source;
                master_file_map.set(media_source.get_master_file(), media_source);
                media_source.master_replaced.connect(on_master_source_replaced);
            }
        }
        
        if (removed != null) {
            foreach (DataSource source in removed) {
                MediaSource media_source = (MediaSource) source;
                bool is_removed = master_file_map.unset(media_source.get_master_file());
                assert(is_removed);
                media_source.master_replaced.disconnect(on_master_source_replaced);
            }
        }
        
        base.notify_contents_altered(added, removed);
    }
    
    private void on_master_source_replaced(MediaSource media_source, File old_file, File new_file) {
        bool removed = master_file_map.unset(old_file);
        assert(removed);

        master_file_map.set(new_file, media_source);
    }
}

public abstract class MediaSourceCollection : DatabaseSourceCollection {
    private MediaSourceHoldingTank trashcan = null;
    private MediaSourceHoldingTank offline_bin = null;
    private Gee.MultiMap<ImportID?, MediaSource> import_rolls =
        new Gee.TreeMultiMap<ImportID?, MediaSource>(ImportID.compare_func);
    private Gee.TreeSet<ImportID?> sorted_import_ids = new Gee.TreeSet<ImportID?>(ImportID.compare_func);
    private Gee.Set<MediaSource> flagged = new Gee.HashSet<MediaSource>();
    
    public virtual signal void trashcan_contents_altered(Gee.Collection<MediaSource>? added,
        Gee.Collection<MediaSource>? removed) {
    }

    public virtual signal void import_roll_altered() {
    }

    public virtual signal void offline_contents_altered(Gee.Collection<MediaSource>? added,
        Gee.Collection<MediaSource>? removed) {
    }
    
    public virtual signal void flagged_contents_altered() {
    }
    
    public MediaSourceCollection(string name, GetSourceDatabaseKey source_key_func) {
        base(name, source_key_func);
        
        trashcan = create_trashcan();
        offline_bin = create_offline_bin();
    }

    public static void filter_media(Gee.Collection<MediaSource> media,
        Gee.Collection<LibraryPhoto>? photos, Gee.Collection<Video>? videos) {
        foreach (MediaSource source in media) {
            if (photos != null && source is LibraryPhoto)
                photos.add((LibraryPhoto) source);
            else if (videos != null && source is Video)
                videos.add((Video) source);
            else if (photos != null || videos != null)
                warning("Unrecognized media: %s", source.to_string());
        }
    }

    protected abstract MediaSourceHoldingTank create_trashcan();
    protected abstract MediaSourceHoldingTank create_offline_bin();

    protected MediaSourceHoldingTank get_trashcan() {
        return trashcan;
    }

    protected MediaSourceHoldingTank get_offline_bin() {
        return offline_bin;
    }
    
    // NOTE: numeric id's are not unique throughout the system -- they're only unique
    //       per media type. So a MediaSourceCollection should only ever hold media
    //       of the same type.
    protected abstract MediaSource? fetch_by_numeric_id(int64 numeric_id);

    protected virtual void notify_import_roll_altered() {
        import_roll_altered();
    }
    
    protected virtual void notify_flagged_contents_altered() {
        flagged_contents_altered();
    }
    
    protected override void items_altered(Gee.Map<DataObject, Alteration> items) {
        Gee.ArrayList<MediaSource> to_trashcan = null;
        Gee.ArrayList<MediaSource> to_offline = null;
        bool flagged_altered = false;
        foreach (DataObject object in items.keys) {
            Alteration alteration = items.get(object);
            
            MediaSource source = (MediaSource) object;
            
            if (!alteration.has_subject("metadata"))
                continue;
            
            if (source.is_trashed() && !get_trashcan().contains(source)) {
                if (to_trashcan == null)
                    to_trashcan = new Gee.ArrayList<MediaSource>();
                
                to_trashcan.add(source);
                
                // sources can only be in trashcan or offline -- not both
                continue;
            }
            
            if (source.is_offline() && !get_offline_bin().contains(source)) {
                if (to_offline == null)
                    to_offline = new Gee.ArrayList<MediaSource>();
                
                to_offline.add(source);
            }
            
            Flaggable? flaggable = source as Flaggable;
            if (flaggable != null) {
                if (flaggable.is_flagged())
                    flagged_altered = flagged.add(source) || flagged_altered;
                else
                    flagged_altered = flagged.remove(source) || flagged_altered;
            }
        }
        
        if (to_trashcan != null)
            get_trashcan().unlink_and_hold(to_trashcan);
        
        if (to_offline != null)
            get_offline_bin().unlink_and_hold(to_offline);
        
        if (flagged_altered)
            notify_flagged_contents_altered();
        
        base.items_altered(items);
    }

    protected override void notify_contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        bool import_roll_changed = false;
        bool flagged_altered = false;
        if (added != null) {
            foreach (DataObject object in added) {
                MediaSource current_media = (MediaSource) object;
                
                ImportID import_id = current_media.get_import_id();
                if (import_id.is_valid()) {
                    sorted_import_ids.add(import_id);
                    import_rolls.set(import_id, current_media);
                    
                    import_roll_changed = true;
                }
                
                Flaggable? flaggable = current_media as Flaggable;
                if (flaggable != null ) {
                    if (flaggable.is_flagged())
                        flagged_altered = flagged.add(current_media) || flagged_altered;
                    else
                        flagged_altered = flagged.remove(current_media) || flagged_altered;
                }
            }
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                MediaSource current_media = (MediaSource) object;
                
                ImportID import_id = current_media.get_import_id();
                if (import_id.is_valid()) {
                    bool is_removed = import_rolls.remove(import_id, current_media);
                    assert(is_removed);
                    if (!import_rolls.contains(import_id))
                        sorted_import_ids.remove(import_id);
                    
                    import_roll_changed = true;
                }
                
                flagged_altered = flagged.remove(current_media) || flagged_altered;
            }
        }
        
        if (import_roll_changed)
            notify_import_roll_altered();
        
        if (flagged_altered)
            notify_flagged_contents_altered();
        
        base.notify_contents_altered(added, removed);
    }
    
    public virtual MediaSource? fetch_by_source_id(string source_id) {
        string[] components = source_id.split("-");

        assert(components.length == 2);

        unowned string endptr;
        int64 id = components[1].to_int64(out endptr, 16);

        assert(endptr[0] == '\0');

        return fetch_by_numeric_id(id);
    }

    public abstract Gee.Collection<string> get_event_source_ids(EventID event_id);

    public Gee.Collection<MediaSource> get_trashcan_contents() {
        return (Gee.Collection<MediaSource>) get_trashcan().get_all();
    }

    public Gee.Collection<MediaSource> get_offline_bin_contents() {
        return (Gee.Collection<MediaSource>) get_offline_bin().get_all();
    }
    
    public Gee.Collection<MediaSource> get_flagged() {
        return flagged.read_only_view;
    }
    
    // The returned set of ImportID's is sorted from oldest to newest.
    public Gee.SortedSet<ImportID?> get_import_roll_ids() {
        return sorted_import_ids;
    }
    
    public ImportID? get_last_import_id() {
        return sorted_import_ids.size != 0 ? sorted_import_ids.last() : null;
    }
    
    public Gee.Collection<MediaSource?>? get_import_roll(ImportID import_id) {
        return import_rolls.get(import_id);
    }

    public void add_many_to_trash(Gee.Collection<MediaSource> sources) {
        get_trashcan().add_many(sources);
    }

    public void add_many_to_offline(Gee.Collection<MediaSource> sources) {
        get_offline_bin().add_many(sources);
    }

    public int get_trashcan_count() {
        return get_trashcan().get_count();
    }

    // This operation cannot be cancelled; the return value of the ProgressMonitor is ignored.
    // Note that delete_backing dictates whether or not the photos are tombstoned (if deleted,
    // tombstones are not created).
    public void remove_from_app(Gee.Collection<MediaSource>? sources, bool delete_backing,
        ProgressMonitor? monitor = null, Gee.List<MediaSource>? not_removed = null) {
        assert(sources != null);
        // only tombstone if the backing is not being deleted
        Gee.HashSet<MediaSource> to_tombstone = !delete_backing ? new Gee.HashSet<MediaSource>() : null;
        
        // separate photos into two piles: those in the trash and those not
        Gee.ArrayList<MediaSource> trashed = new Gee.ArrayList<MediaSource>();
        Gee.ArrayList<MediaSource> offlined = new Gee.ArrayList<MediaSource>();
        Gee.ArrayList<MediaSource> not_trashed = new Gee.ArrayList<MediaSource>();
        foreach (MediaSource source in sources) {
            if (source.is_trashed())
                trashed.add(source);
            else if (source.is_offline())
                offlined.add(source);
            else
                not_trashed.add(source);
            
            if (to_tombstone != null)
                to_tombstone.add(source);
        }
        
        int total_count = sources.size;
        assert(total_count == (trashed.size + offlined.size + not_trashed.size));
        
        // use an aggregate progress monitor, as it's possible there are three steps here
        AggregateProgressMonitor agg_monitor = null;
        if (monitor != null) {
            agg_monitor = new AggregateProgressMonitor(total_count, monitor);
            monitor = agg_monitor.monitor;
        }
        
        if (trashed.size > 0)
            get_trashcan().destroy_orphans(trashed, delete_backing, monitor, not_removed);
        
        if (offlined.size > 0)
            get_offline_bin().destroy_orphans(offlined, delete_backing, monitor, not_removed);
        
        // untrashed media sources may be destroyed outright
        if (not_trashed.size > 0)
            destroy_marked(mark_many(not_trashed), delete_backing, monitor, not_removed);
        
        if (to_tombstone != null && to_tombstone.size > 0) {
            try {
                Tombstone.entomb_many_sources(to_tombstone);
            } catch (DatabaseError err) {
                AppWindow.database_error(err);
            }
        }
    }
    
    // Deletes (i.e. not trashes) the backing files.
    // Note: must be removed from DB first.
    public void delete_backing_files(Gee.Collection<MediaSource> sources,
        ProgressMonitor? monitor = null, Gee.List<MediaSource>? not_deleted = null) {
        int total_count = sources.size;
        int i = 1;
        
        foreach (MediaSource source in sources) {
            File file = source.get_file();
            try {
                file.delete(null);
            } catch (Error err) {
                // Note: we may get an exception even though the delete succeeded.
                debug("Exception deleting file %s: %s", file.get_path(), err.message);
            }
            
            bool deleted = !file.query_exists();
            if (!deleted && null != not_deleted) {
                not_deleted.add(source);
            }
            
            if (monitor != null) {
                monitor(i, total_count);
            }
            i++;
        }
            
    }
}

public class MediaCollectionRegistry {
    private static MediaCollectionRegistry? instance = null;
    
    private Gee.HashMap<string, MediaSourceCollection> collection_registry =
        new Gee.HashMap<string, MediaSourceCollection>(str_hash, str_equal, direct_equal);
    
    private MediaCollectionRegistry() {
    }
    
    public static MediaCollectionRegistry get_instance() {
        if (instance == null)
            instance = new MediaCollectionRegistry();

        return instance;
    }
    
    public static string get_typename_from_source_id(string source_id) {
        // we have to special-case photos because their source id format is non-standard. this
        // is due to a historical quirk.
        if (source_id.has_prefix(Photo.TYPENAME)) {
            return Photo.TYPENAME;
        } else {
            string[] components = source_id.split("-");
            assert(components.length == 2);

            return components[0];
        }
    }

    public void register_collection(string typename, MediaSourceCollection collection) {
        collection_registry.set(typename, collection);
    }
    
    // NOTE: going forward, please use get_collection( ) and get_all_collections( ) to get the
    //       collection associated with a specific media type or to get all registered collections,
    //       respectively, instead of explicitly referencing Video.global and LibraryPhoto.global.
    //       This will make it *much* easier to add new media types in the future.
    public MediaSourceCollection? get_collection(string typename) {
        return collection_registry.get(typename);
    }
    
    public Gee.Collection<MediaSourceCollection> get_all() {
        return collection_registry.values;
    }
    
    public void freeze_all() {
        foreach (MediaSourceCollection sources in get_all())
            sources.freeze_notifications();
    }
    
    public void thaw_all() {
        foreach (MediaSourceCollection sources in get_all())
            sources.thaw_notifications();
    }
    
    public MediaSource? fetch_media(string source_id) {
        string typename = get_typename_from_source_id(source_id);
               
        MediaSourceCollection? collection = get_collection(typename);
        if (collection == null) {
            critical("source id '%s' has unrecognized media type '%s'", source_id, typename);
            return null;
        }

        return collection.fetch_by_source_id(source_id);
    }

    public ImportID? get_last_import_id() {
        ImportID last_import_id = ImportID();

        foreach (MediaSourceCollection current_collection in get_all()) {
            ImportID? current_import_id = current_collection.get_last_import_id();

            if (current_import_id == null)
                continue;

            if (current_import_id.id > last_import_id.id)
                last_import_id = current_import_id;
        }

        // VALA: can't use the ternary operator here because of bug 616897 : "Mixed nullability in
        //       ternary operator fails"
        if (last_import_id.id == ImportID.INVALID)
            return null;
        else
            return last_import_id;
    }

    public Gee.Collection<string> get_source_ids_for_event_id(EventID event_id) {
        Gee.ArrayList<string> result = new Gee.ArrayList<string>();
        
        foreach (MediaSourceCollection current_collection in get_all()) {
            result.add_all(current_collection.get_event_source_ids(event_id));
        }
        
        return result;
    }
}

