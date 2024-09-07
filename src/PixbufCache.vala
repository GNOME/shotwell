/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class PixbufCache : Object {
    public delegate bool CacheFilter(Photo photo);
    
    public enum PhotoType {
        BASELINE,
        MASTER
    }
    
    public class PixbufCacheBatch : Gee.TreeMultiMap<BackgroundJob.JobPriority, Photo> {
        public PixbufCacheBatch() {
            base ((GLib.CompareDataFunc<BackgroundJob.JobPriority>)BackgroundJob.JobPriority.compare_func);
        }
    }
    
    private abstract class FetchJob : BackgroundJob {
        public BackgroundJob.JobPriority priority;
        public Photo photo;
        public Scaling scaling;
        public Gdk.Pixbuf pixbuf = null;
        public Error err = null;
        
        protected FetchJob(PixbufCache owner, BackgroundJob.JobPriority priority, Photo photo, 
            Scaling scaling, CompletionCallback callback) {
            base(owner, callback, new Cancellable(), null, new Semaphore());
            
            this.priority = priority;
            this.photo = photo;
            this.scaling = scaling;
        }
        
        public override BackgroundJob.JobPriority get_priority() {
            return priority;
        }
    }
    
    private class BaselineFetchJob : FetchJob {
        public BaselineFetchJob(PixbufCache owner, BackgroundJob.JobPriority priority, Photo photo, 
            Scaling scaling, CompletionCallback callback) {
            base(owner, priority, photo, scaling, callback);
        }
        
        public override void execute() {
            try {
                pixbuf = photo.get_pixbuf(scaling);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private class MasterFetchJob : FetchJob {
        public MasterFetchJob(PixbufCache owner, BackgroundJob.JobPriority priority, Photo photo, 
            Scaling scaling, CompletionCallback callback) {
            base(owner, priority, photo, scaling, callback);
        }
        
        public override void execute() {
            try {
                pixbuf = photo.get_master_pixbuf(scaling);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private static Workers background_workers = null;
    
    private SourceCollection sources;
    private PhotoType type;
    private int max_count;
    private Scaling scaling;
    private unowned CacheFilter? filter;
    private Gee.HashMap<Photo, Gdk.Pixbuf> cache = new Gee.HashMap<Photo, Gdk.Pixbuf>();
    private Gee.ArrayList<Photo> lru = new Gee.ArrayList<Photo>();
    private Gee.HashMap<Photo, FetchJob> in_progress = new Gee.HashMap<Photo, FetchJob>();
    
    public signal void fetched(Photo photo, Gdk.Pixbuf? pixbuf, Error? err);
    
    public PixbufCache(SourceCollection sources, PhotoType type, Scaling scaling, int max_count,
        CacheFilter? filter = null) {
        this.sources = sources;
        this.type = type;
        this.scaling = scaling;
        this.max_count = max_count;
        this.filter = filter;
        
        assert(max_count > 0);
        
        if (background_workers == null)
            background_workers = new Workers(Workers.thread_per_cpu_minus_one(), false);
        
        // monitor changes in the photos to discard from cache ... only interested in changes if
        // not master files
        if (type != PhotoType.MASTER)
            sources.items_altered.connect(on_sources_altered);
        sources.items_removed.connect(on_sources_removed);
    }
    
    ~PixbufCache() {
#if TRACE_PIXBUF_CACHE
        debug("Freeing %d pixbufs and cancelling %d jobs", cache.size, in_progress.size);
#endif
        
        if (type != PhotoType.MASTER)
            sources.items_altered.disconnect(on_sources_altered);
        sources.items_removed.disconnect(on_sources_removed);
        
        foreach (FetchJob job in in_progress.values)
            job.cancel();
    }
    
    public Scaling get_scaling() {
        return scaling;
    }
    
    // This call never blocks.  Returns null if the pixbuf is not present.
    public Gdk.Pixbuf? get_ready_pixbuf(Photo photo) {
        return get_cached(photo);
    }
    
    // This call can potentially block if the pixbuf is not in the cache.  Once loaded, it will
    // be cached.  No signal is fired.
    public Gdk.Pixbuf? fetch(Photo photo) throws Error {
        if (!photo.get_actual_file().query_exists(null))
            decache(photo);
        
        Gdk.Pixbuf pixbuf = get_cached(photo);
        if (pixbuf != null) {
#if TRACE_PIXBUF_CACHE
            debug("Fetched in-memory pixbuf for %s @ %s", photo.to_string(), scaling.to_string());
#endif
            
            return pixbuf;
        }
        
        FetchJob? job = in_progress.get(photo);
        if (job != null) {
            job.wait_for_completion();
            if (job.err != null)
                throw job.err;
            
            return job.pixbuf;
        }
        
#if TRACE_PIXBUF_CACHE
        debug("Forced to make a blocking fetch of %s @ %s", photo.to_string(), scaling.to_string());
#endif
        
        pixbuf = photo.get_pixbuf(scaling);
        
        encache(photo, pixbuf);
        
        return pixbuf;
    }
    
    // This can be used to clear specific pixbufs from the cache, allowing finer control over what
    // pixbufs remain and avoid being dropped when other fetches follow.  It implicitly cancels
    // any outstanding prefetches for the photo.
    public void drop(Photo photo) {
        cancel_prefetch(photo);
        decache(photo);
    }
    
    // This call signals the cache to pre-load the pixbuf for the photo.  When loaded the fetched
    // signal is fired.
    public void prefetch(Photo photo, 
        BackgroundJob.JobPriority priority = BackgroundJob.JobPriority.NORMAL, bool force = false) {
        if (!photo.get_actual_file().query_exists(null))
            decache(photo);
        
        if (!force && cache.has_key(photo)) {
            prioritize(photo);
            
            return;
        }
        
        if (in_progress.has_key(photo))
            return;
        
        if (filter != null && !filter(photo))
            return;
        
        FetchJob job = null;
        switch (type) {
            case PhotoType.BASELINE:
                job = new BaselineFetchJob(this, priority, photo, scaling, on_fetched);
            break;
            
            case PhotoType.MASTER:
                job = new MasterFetchJob(this, priority, photo, scaling, on_fetched);
            break;
            
            default:
                error("Unknown photo type: %d", (int) type);
        }
        
        in_progress.set(photo, job);
        
        background_workers.enqueue(job);
    }
    
    // This call signals the cache to pre-load the pixbufs for all supplied photos.  Each fires
    // the fetch signal as they arrive.
    public void prefetch_many(Gee.Collection<Photo> photos,
        BackgroundJob.JobPriority priority = BackgroundJob.JobPriority.NORMAL, bool force = false) {
        foreach (Photo photo in photos)
            prefetch(photo, priority, force);
    }
    
    // Like prefetch_many, but allows for priorities to be set for each photo
    public void prefetch_batch(PixbufCacheBatch batch, bool force = false) {
        foreach (BackgroundJob.JobPriority priority in batch.get_keys()) {
            foreach (Photo photo in batch.get(priority))
                prefetch(photo, priority, force);
        }
    }
    
    public bool cancel_prefetch(Photo photo) {
        FetchJob job = in_progress.get(photo);
        if (job == null)
            return false;
        
        // remove here because if fully cancelled the callback is never called
        bool removed = in_progress.unset(photo);
        assert(removed);
        
        job.cancel();
        
#if TRACE_PIXBUF_CACHE
        debug("Cancelled prefetch of %s @ %s", photo.to_string(), scaling.to_string());
#endif
        
        return true;
    }
    
    public void cancel_all() {
#if TRACE_PIXBUF_CACHE
        debug("Cancelling prefetch of %d photos at %s", in_progress.values.size, scaling.to_string());
#endif
        foreach (FetchJob job in in_progress.values)
            job.cancel();
        
        in_progress.clear();
    }
    
    private void on_fetched(BackgroundJob j) {
        FetchJob job = (FetchJob) j;
        
        // remove Cancellable from in_progress list, but don't assert on it because it's possible
        // the cancel was called after the task completed
        in_progress.unset(job.photo);
        
        if (job.err != null) {
            assert(job.pixbuf == null);
            
            critical("Unable to readahead %s: %s", job.photo.to_string(), job.err.message);
            fetched(job.photo, null, job.err);
            
            return;
        }
        
#if TRACE_PIXBUF_CACHE
        debug("%s %s fetched into pixbuf cache", type.to_string(), job.photo.to_string());
#endif
        
        encache(job.photo, job.pixbuf);
        
        // fire signal
        fetched(job.photo, job.pixbuf, null);
    }
    
    private void on_sources_altered(Gee.Map<DataObject, Alteration> map) {
        foreach (DataObject object in map.keys) {
            if (!map.get(object).has_subject("image"))
                continue;
            
            Photo photo = (Photo) object;
            
            if (in_progress.has_key(photo)) {
                // Load is in progress, must cancel, but consider in-cache (since it was decached
                // before being put into progress)
                in_progress.get(photo).cancel();
                in_progress.unset(photo);
            } else if (!cache.has_key(photo)) {
                continue;
            }
            
            decache(photo);
            
#if TRACE_PIXBUF_CACHE
            debug("Re-fetching altered pixbuf from cache: %s @ %s", photo.to_string(),
                scaling.to_string());
#endif
            
            prefetch(photo, BackgroundJob.JobPriority.HIGH);
        }
    }
    
    private void on_sources_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            Photo photo = object as Photo;
            assert(photo != null);
            
            decache(photo);
        }
    }
    
    private Gdk.Pixbuf? get_cached(Photo photo) {
        Gdk.Pixbuf pixbuf = cache.get(photo);
        if (pixbuf != null)
            prioritize(photo);
        
        return pixbuf;
    }
    
    // Moves the photo up in the cache LRU.  Assumes photo is actually in cache.
    private void prioritize(Photo photo) {
        int index = lru.index_of(photo);
        assert(index >= 0);
        
        if (index > 0) {
            lru.remove_at(index);
            lru.insert(0, photo);
        }
    }
    
    private void encache(Photo photo, Gdk.Pixbuf pixbuf) {
        // if already in cache, remove (means it was re-fetched, probably due to modification)
        decache(photo);
        
        cache.set(photo, pixbuf);
        lru.insert(0, photo);
        
        while (lru.size > max_count) {
            Photo cached_photo = lru.remove_at(lru.size - 1);
            assert(cached_photo != null);
            
            bool removed = cache.unset(cached_photo);
            assert(removed);
        }
        
        assert(lru.size == cache.size);
    }
    
    private void decache(Photo photo) {
        if (!cache.unset(photo)) {
            assert(!lru.contains(photo));
            
            return;
        }
        
        bool removed = lru.remove(photo);
        assert(removed);
    }
}

