/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class BackingFileState {
    public string filepath;
    public int64 filesize;
    public time_t modification_time;
    public string? md5;
    
    public BackingFileState(string filepath, int64 filesize, time_t modification_time, string? md5) {
        this.filepath = filepath;
        this.filesize = filesize;
        this.modification_time = modification_time;
        this.md5 = md5;
    }
    
    public BackingFileState.from_photo_row(BackingPhotoRow photo_row, string? md5) {
        this.filepath = photo_row.filepath;
        this.filesize = photo_row.filesize;
        this.modification_time = photo_row.timestamp;
        this.md5 = md5;
    }
    
    public File get_file() {
        return File.new_for_path(filepath);
    }
}

public abstract class MediaSource : ThumbnailSource, Indexable {
    public virtual signal void master_replaced(File old_file, File new_file) {
    }
    
    private Event? event = null;
    private string? indexable_keywords = null;
    
    protected MediaSource(int64 object_id = INVALID_OBJECT_ID) {
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
    
    protected override void notify_altered(Alteration alteration) {
        Alteration local = alteration;
        
        if (local.has_detail("metadata", "name") ||
            local.has_detail("metadata", "comment") ||
            local.has_detail("backing", "master")) {
            update_indexable_keywords();
            local = local.compress(new Alteration("indexable", "keywords"));
        }
        
        base.notify_altered(local);
    }
    
    // use this method as a kind of post-constructor initializer; it means the DataSource has been
    // added or removed to a SourceCollection.
    protected override void notify_membership_changed(DataCollection? collection) {
        if (collection != null && indexable_keywords == null) {
            // don't fire the alteration here, as the MediaSource is only being added to its
            // SourceCollection
            update_indexable_keywords();
        }
        
        base.notify_membership_changed(collection);
    }
    
    private void update_indexable_keywords() {
        string[] indexables = new string[3];
        indexables[0] = get_title();
        indexables[1] = get_basename();
        indexables[2] = get_comment();
        
        indexable_keywords = prepare_indexable_strings(indexables);
    }
    
    public unowned string? get_indexable_keywords() {
        return indexable_keywords;
    }
    
    protected abstract bool set_event_id(EventID id);

    protected bool delete_original_file() {
        bool ret = false;
        File file = get_master_file();
        
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
            while (!parent.equal(AppDirs.get_import_dir())) {
                parent = parent.get_parent();
                if ((parent == null) || (parent.equal(AppDirs.get_import_dir())))
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
    
    public override string get_name() {
        string? title = get_title();
        
        return is_string_empty(title) ? get_basename() : title;
    }
    
    public virtual string get_basename() {
        return get_file().get_basename();
    }
    
    public abstract File get_file();
    public abstract File get_master_file();
    public abstract uint64 get_master_filesize();
    public abstract uint64 get_filesize();
    public abstract time_t get_timestamp();
    
    // Must return at least one, for the master file.
    public abstract BackingFileState[] get_backing_files_state();
    
    public abstract string? get_title();
    public abstract string? get_comment();
    public abstract void set_title(string? title);
    public abstract bool set_comment(string? comment);
    
    public static string? prep_title(string? title) {
        return prepare_input_text(title, 
            PrepareInputTextOptions.DEFAULT & ~PrepareInputTextOptions.EMPTY_IS_NULL, DEFAULT_USER_TEXT_INPUT_LENGTH);
    }

    public static string? prep_comment(string? comment) {
        return prepare_input_text(comment,
            PrepareInputTextOptions.DEFAULT & ~PrepareInputTextOptions.STRIP_CRLF & ~PrepareInputTextOptions.EMPTY_IS_NULL, -1);
    }
    
    public abstract Rating get_rating();
    public abstract void set_rating(Rating rating);
    public abstract void increase_rating();
    public abstract void decrease_rating();
    
    public abstract Dimensions get_dimensions(Photo.Exception disallowed_steps = Photo.Exception.NONE);

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
        if (event != null)
            return event;
        
        EventID event_id = get_event_id();
        if (!event_id.is_valid())
            return null;
        
        event = Event.global.fetch(event_id);
        
        return event;
    }

    public bool set_event(Event? new_event) {
        EventID event_id = (new_event != null) ? new_event.get_event_id() : EventID();
        if (get_event_id().id == event_id.id)
            return true;
        
        bool committed = set_event_id(event_id);
        if (committed) {
            if (event != null)
                event.detach(this);

            if (new_event != null)
                new_event.attach(this);
            
            event = new_event;
            
            notify_altered(new Alteration("metadata", "event"));
        }

        return committed;
    }
    
    public static void set_many_to_event(Gee.Collection<MediaSource> media_sources, Event? event,
        TransactionController controller) throws Error {
        EventID event_id = (event != null) ? event.get_event_id() : EventID();
        
        controller.begin();
        
        foreach (MediaSource media in media_sources) {
            Event? old_event = media.get_event();
            if (old_event != null)
                old_event.detach(media);
            
            media.set_event_id(event_id);
            media.event = event;
        }
        
        if (event != null)
            event.attach_many(media_sources);
        
        Alteration alteration = new Alteration("metadata", "event");
        foreach (MediaSource media in media_sources)
            media.notify_altered(alteration);
        
        controller.commit();
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

// This class is good for any MediaSourceCollection that is backed by a DatabaseTable (which should
// be all of them, but if not, they should construct their own implementation).
public class MediaSourceTransactionController : TransactionController {
    private MediaSourceCollection sources;
    
    public MediaSourceTransactionController(MediaSourceCollection sources) {
        this.sources = sources;
    }
    
    protected override void begin_impl() throws Error {
        DatabaseTable.begin_transaction();
        sources.freeze_notifications();
    }
    
    protected override void commit_impl() throws Error {
        sources.thaw_notifications();
        DatabaseTable.commit_transaction();
    }
}

public abstract class MediaSourceCollection : DatabaseSourceCollection {
    public abstract TransactionController transaction_controller { get; }
    
    private MediaSourceHoldingTank trashcan = null;
    private MediaSourceHoldingTank offline_bin = null;
    private Gee.HashMap<File, MediaSource> by_master_file = new Gee.HashMap<File, MediaSource>(
        file_hash, file_equal);
    private Gee.MultiMap<ImportID?, MediaSource> import_rolls =
        new Gee.TreeMultiMap<ImportID?, MediaSource>(ImportID.compare_func);
    private Gee.TreeSet<ImportID?> sorted_import_ids = new Gee.TreeSet<ImportID?>(ImportID.compare_func);
    private Gee.Set<MediaSource> flagged = new Gee.HashSet<MediaSource>();
    
    // This signal is fired when MediaSources are added to the collection due to a successful import.
    // "items-added" and "contents-altered" will follow.
    public virtual signal void media_import_starting(Gee.Collection<MediaSource> media) {
    }
    
    // This signal is fired when MediaSources have been added to the collection due to a successful
    // import and import postprocessing has completed (such as adding an import Photo to its Tags).
    // Thus, signals that have already been fired (in this order) are "media-imported", "items-added",
    // "contents-altered" before this signal.
    public virtual signal void media_import_completed(Gee.Collection<MediaSource> media) {
    }
    
    public virtual signal void master_file_replaced(MediaSource media, File old_file, File new_file) {
    }
    
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
    
    protected MediaSourceCollection(string name, GetSourceDatabaseKey source_key_func) {
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
    
    public static void count_media(Gee.Collection<MediaSource> media, out int photo_count,
        out int video_count) {
        var photos = new Gee.ArrayList<LibraryPhoto>();
        var videos = new Gee.ArrayList<Video>();
        
        filter_media(media, photos, videos);
        
        photo_count = photos.size;
        video_count = videos.size;
    }
    
    public static bool has_photo(Gee.Collection<MediaSource> media) {
        foreach (MediaSource current_media in media) {
            if (current_media is Photo) {
                return true;
            }
        }

        return false;
    }

    public static bool has_video(Gee.Collection<MediaSource> media) {
        foreach (MediaSource current_media in media) {
            if (current_media is Video) {
                return true;
            }
        }

        return false;
    }

    protected abstract MediaSourceHoldingTank create_trashcan();
    
    protected abstract MediaSourceHoldingTank create_offline_bin();
    
    public abstract MediaMonitor create_media_monitor(Workers workers, Cancellable cancellable);
    
    public abstract string get_typename();
    
    public abstract bool is_file_recognized(File file);
    
    public MediaSourceHoldingTank get_trashcan() {
        return trashcan;
    }

    public MediaSourceHoldingTank get_offline_bin() {
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
    
    protected virtual void notify_media_import_starting(Gee.Collection<MediaSource> media) {
        media_import_starting(media);
    }
    
    protected virtual void notify_media_import_completed(Gee.Collection<MediaSource> media) {
        media_import_completed(media);
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
                MediaSource media = (MediaSource) object;
                
                by_master_file.set(media.get_master_file(), media);
                media.master_replaced.connect(on_master_replaced);
                
                ImportID import_id = media.get_import_id();
                if (import_id.is_valid()) {
                    sorted_import_ids.add(import_id);
                    import_rolls.set(import_id, media);
                    
                    import_roll_changed = true;
                }
                
                Flaggable? flaggable = media as Flaggable;
                if (flaggable != null ) {
                    if (flaggable.is_flagged())
                        flagged_altered = flagged.add(media) || flagged_altered;
                    else
                        flagged_altered = flagged.remove(media) || flagged_altered;
                }
            }
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                MediaSource media = (MediaSource) object;
                
                bool is_removed = by_master_file.unset(media.get_master_file());
                assert(is_removed);
                media.master_replaced.disconnect(on_master_replaced);
                
                ImportID import_id = media.get_import_id();
                if (import_id.is_valid()) {
                    is_removed = import_rolls.remove(import_id, media);
                    assert(is_removed);
                    if (!import_rolls.contains(import_id))
                        sorted_import_ids.remove(import_id);
                    
                    import_roll_changed = true;
                }
                
                flagged_altered = flagged.remove(media) || flagged_altered;
            }
        }
        
        if (import_roll_changed)
            notify_import_roll_altered();
        
        if (flagged_altered)
            notify_flagged_contents_altered();
        
        base.notify_contents_altered(added, removed);
    }
    
    private void on_master_replaced(MediaSource media, File old_file, File new_file) {
        bool is_removed = by_master_file.unset(old_file);
        assert(is_removed);
        
        by_master_file.set(new_file, media);
        
        master_file_replaced(media, old_file, new_file);
    }
    
    public MediaSource? fetch_by_master_file(File file) {
        return by_master_file.get(file);
    }
    
    public virtual MediaSource? fetch_by_source_id(string source_id) {
        string[] components = source_id.split("-");
        assert(components.length == 2);
        
        return fetch_by_numeric_id(parse_int64(components[1], 16));
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
    
    // This method should be used in place of add_many() when adding MediaSources due to a successful
    // import.  This function fires appropriate signals and calls add_many(), so the signals
    // associated with that call will be fired too.
    public virtual void import_many(Gee.Collection<MediaSource> media) {
        notify_media_import_starting(media);
        
        add_many(media);
        
        postprocess_imported_media(media);
        
        notify_media_import_completed(media);
    }
    
    // Child classes can override this method to perform postprocessing on a imported media, such
    // as associating them with tags or events.
    protected virtual void postprocess_imported_media(Gee.Collection<MediaSource> media) {
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
                Tombstone.entomb_many_sources(to_tombstone, Tombstone.Reason.REMOVED_BY_USER);
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

            var masterfile = source.get_master_file();
            if (masterfile != null) {
                try {
                    masterfile.delete(null);
                } catch (Error err) {
                    if (!(err is IOError.NOT_FOUND)) {
                        debug("Exception deleting master file %s: %s", masterfile.get_path(), err.message);
                    }
                }
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
    private const int LIBRARY_MONITOR_START_DELAY_MSEC = 1000;
    
    private static MediaCollectionRegistry? instance = null;
    
    private Gee.ArrayList<MediaSourceCollection> all = new Gee.ArrayList<MediaSourceCollection>();
    private Gee.HashMap<string, MediaSourceCollection> by_typename = 
        new Gee.HashMap<string, MediaSourceCollection>();
    
    private MediaCollectionRegistry() {
        Application.get_instance().init_done.connect(on_init_done);
    }
    
    ~MediaCollectionRegistry() {
        Application.get_instance().init_done.disconnect(on_init_done);
    }
    
    private void on_init_done() {
        // install the default library monitor
        LibraryMonitor library_monitor = new LibraryMonitor(AppDirs.get_import_dir(), true,
            !CommandlineOptions.no_runtime_monitoring);

        LibraryMonitorPool.get_instance().replace(library_monitor, LIBRARY_MONITOR_START_DELAY_MSEC);
    }
    
    public static void init() {
        instance = new MediaCollectionRegistry();
        Config.Facade.get_instance().import_directory_changed.connect(on_import_directory_changed);
    }
    
    public static void terminate() {
        Config.Facade.get_instance().import_directory_changed.disconnect(on_import_directory_changed);
    }
    
    private static void on_import_directory_changed() {        
        File import_dir = AppDirs.get_import_dir();
        
        LibraryMonitor? current = LibraryMonitorPool.get_instance().get_monitor();
        if (current != null && current.get_root().equal(import_dir))
            return;
        
        LibraryMonitor replacement = new LibraryMonitor(import_dir, true,
            !CommandlineOptions.no_runtime_monitoring);
        LibraryMonitorPool.get_instance().replace(replacement, LIBRARY_MONITOR_START_DELAY_MSEC);
        LibraryFiles.select_copy_function();
    }
    
    public static MediaCollectionRegistry get_instance() {
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

    public void register_collection(MediaSourceCollection collection) {
        all.add(collection);
        by_typename.set(collection.get_typename(), collection);
    }
    
    // NOTE: going forward, please use get_collection( ) and get_all_collections( ) to get the
    //       collection associated with a specific media type or to get all registered collections,
    //       respectively, instead of explicitly referencing Video.global and LibraryPhoto.global.
    //       This will make it *much* easier to add new media types in the future.
    public MediaSourceCollection? get_collection(string typename) {
        return by_typename.get(typename);
    }
    
    public Gee.Collection<MediaSourceCollection> get_all() {
        return all.read_only_view;
    }
    
    public void freeze_all() {
        foreach (MediaSourceCollection sources in get_all())
            sources.freeze_notifications();
    }
    
    public void thaw_all() {
        foreach (MediaSourceCollection sources in get_all())
            sources.thaw_notifications();
    }
    
    public void begin_transaction_on_all() {
        foreach (MediaSourceCollection sources in get_all())
            sources.transaction_controller.begin();
    }
    
    public void commit_transaction_on_all() {
        foreach (MediaSourceCollection sources in get_all())
            sources.transaction_controller.commit();
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
    
    public MediaSourceCollection? get_collection_for_file(File file) {
        foreach (MediaSourceCollection collection in get_all()) {
            if (collection.is_file_recognized(file))
                return collection;
        }
        
        return null;
    }
    
    public bool is_valid_source_id(string? source_id) {
        if (is_string_empty(source_id)) {
            return false;
        }
        return (source_id.has_prefix(Photo.TYPENAME) || source_id.has_prefix(Video.TYPENAME + "-"));
    }
}

