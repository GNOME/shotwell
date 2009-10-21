/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class PixbufCache {
    public enum PhotoType {
        REGULAR,
        ORIGINAL
    }
    
    private abstract class FetchJob : BackgroundJob {
        public PixbufCache owner;
        public BackgroundJob.JobPriority priority;
        public TransformablePhoto photo;
        public Scaling scaling;
        public Gdk.Pixbuf pixbuf = null;
        public Error err = null;
        
        public FetchJob(PixbufCache owner, BackgroundJob.JobPriority priority, TransformablePhoto photo, 
            Scaling scaling, CompletionCallback callback, Cancellable cancellable) {
            base(callback, cancellable);
            
            // maintain the owner ref because Workers do not, and if the PixbufCache is derefed
            // before a job completes, an assertion fires
            this.owner = owner;
            this.priority = priority;
            this.photo = photo;
            this.scaling = scaling;
        }
        
        public override BackgroundJob.JobPriority get_priority() {
            return priority;
        }
    }
    
    private class RegularFetchJob : FetchJob {
        public RegularFetchJob(PixbufCache owner, BackgroundJob.JobPriority priority, TransformablePhoto photo, 
            Scaling scaling, CompletionCallback callback, Cancellable cancellable) {
            base(owner, priority, photo, scaling, callback, cancellable);
        }
    
        public override void execute() {
            try {
                pixbuf = photo.get_pixbuf(scaling);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private class OriginalFetchJob : FetchJob {
        public OriginalFetchJob(PixbufCache owner, BackgroundJob.JobPriority priority, TransformablePhoto photo, 
            Scaling scaling, CompletionCallback callback, Cancellable cancellable) {
            base(owner, priority, photo, scaling, callback, cancellable);
        }
    
        public override void execute() {
            try {
                pixbuf = photo.get_original_pixbuf(scaling);
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
    private Gee.HashMap<TransformablePhoto, Gdk.Pixbuf> cache = new Gee.HashMap<TransformablePhoto,
        Gdk.Pixbuf>();
    private Gee.ArrayList<TransformablePhoto> lru = new Gee.ArrayList<TransformablePhoto>();
    private Gee.HashMap<TransformablePhoto, Cancellable> in_progress = new Gee.HashMap<TransformablePhoto,
        Cancellable>();
    
    public signal void fetched(TransformablePhoto photo, Gdk.Pixbuf? pixbuf, Error? err);
    
    public PixbufCache(SourceCollection sources, PhotoType type, Scaling scaling, int max_count) {
        this.sources = sources;
        this.type = type;
        this.scaling = scaling;
        this.max_count = max_count;
        
        assert(max_count > 0);
        
        if (background_workers == null)
            background_workers = new Workers(Workers.THREAD_PER_CPU, false);
        
        // monitor changes in the photos to discard from cache
        sources.item_altered += on_source_altered;
        sources.items_removed += on_sources_removed;
    }
    
    ~PixbufCache() {
        debug("Freeing %d pixbufs and cancelling %d jobs", cache.size, in_progress.size);
        
        sources.item_altered -= on_source_altered;
        sources.items_removed -= on_sources_removed;
        
        foreach (Cancellable cancellable in in_progress.values)
            cancellable.cancel();
    }
    
    public Scaling get_scaling() {
        return scaling;
    }
    
    // This call never blocks.  Returns null if the pixbuf is not present.
    public Gdk.Pixbuf? get_ready_pixbuf(TransformablePhoto photo) {
        return get_cached(photo);
    }
    
    // This call can potentially block if the pixbuf is not in the cache.  Once loaded, it will
    // be cached.  No signal is fired.
    public Gdk.Pixbuf? fetch(TransformablePhoto photo) throws Error {
        Gdk.Pixbuf pixbuf = get_cached(photo);
        if (pixbuf != null)
            return pixbuf;
        
        pixbuf = photo.get_pixbuf(scaling);
        
        encache(photo, pixbuf);
        
        return pixbuf;
    }
    
    // This call signals the cache to pre-load the pixbuf for the photo.  When loaded the fetched
    // signal is fired.
    public void prefetch(TransformablePhoto photo, 
        BackgroundJob.JobPriority priority = BackgroundJob.JobPriority.NORMAL, bool force = false) {
        if (!force && cache.contains(photo))
            return;
        
        if (in_progress.contains(photo))
            return;
        
        Cancellable cancellable = new Cancellable();
        in_progress.set(photo, cancellable);
        
        FetchJob job = null;
        switch (type) {
            case PhotoType.REGULAR:
                job = new RegularFetchJob(this, priority, photo, scaling, on_fetched, cancellable);
            break;
            
            case PhotoType.ORIGINAL:
                job = new OriginalFetchJob(this, priority, photo, scaling, on_fetched, cancellable);
            break;
            
            default:
                error("Unknown photo type: %d", (int) type);
            break;
        }
        
        background_workers.enqueue(job);
    }
    
    public bool cancel_prefetch(TransformablePhoto photo) {
        Cancellable cancellable = in_progress.get(photo);
        if (cancellable == null)
            return false;
        
        // remove here because if fully cancelled the callback is never called
        bool removed = in_progress.unset(photo);
        assert(removed);
        
        cancellable.cancel();
        
        return true;
    }
    
    public void cancel_all() {
        foreach (Cancellable cancellable in in_progress.values)
            cancellable.cancel();
        
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
        
        encache(job.photo, job.pixbuf);
        
        // fire signal
        fetched(job.photo, job.pixbuf, null);
    }
    
    private void on_source_altered(DataObject object) {
        TransformablePhoto photo = object as TransformablePhoto;
        assert(photo != null);
        
        debug("Removing altered pixbuf from cache: %s", photo.to_string());
        
        decache(photo);
    }
    
    private void on_sources_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            TransformablePhoto photo = object as TransformablePhoto;
            assert(photo != null);
            
            debug("Removing destroyed photo from cache: %s", photo.to_string());
            
            decache(photo);
        }
    }
    
    private Gdk.Pixbuf? get_cached(TransformablePhoto photo) {
        Gdk.Pixbuf pixbuf = cache.get(photo);
        if (pixbuf == null)
            return null;
        
        // move up in the LRU
        int index = lru.index_of(photo);
        assert(index >= 0);
        lru.remove_at(index);
        lru.insert(0, photo);
        
        return pixbuf;
    }
    
    private void encache(TransformablePhoto photo, Gdk.Pixbuf pixbuf) {
        // if already in cache, remove (means it was re-fetched, probably due to modification)
        decache(photo);
        
        cache.set(photo, pixbuf);
        lru.insert(0, photo);
        
        while (lru.size > max_count) {
            TransformablePhoto cached_photo = lru.remove_at(lru.size - 1);
            assert(cached_photo != null);
            
            bool removed = cache.unset(cached_photo);
            assert(removed);
        }
        
        assert(lru.size == cache.size);
    }
    
    private void decache(TransformablePhoto photo) {
        if (!cache.remove(photo)) {
            assert(!lru.contains(photo));
            
            return;
        }
        
        bool removed = lru.remove(photo);
        assert(removed);
    }
}

