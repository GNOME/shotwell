/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Thumbnails {
    private Gee.HashMap<ThumbnailCache.Size, Gdk.Pixbuf> map = new Gee.HashMap<ThumbnailCache.Size,
        Gdk.Pixbuf>();
    
    public Thumbnails() {
    }
    
    public void set(ThumbnailCache.Size size, Gdk.Pixbuf pixbuf) {
        map.set(size, pixbuf);
    }
    
    public void remove(ThumbnailCache.Size size) {
        map.unset(size);
    }
    
    public Gdk.Pixbuf? get(ThumbnailCache.Size size) {
        return map.get(size);
    }
}

public class ThumbnailCache : Object {
    public const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.HYPER;
    public const Jpeg.Quality DEFAULT_QUALITY = Jpeg.Quality.HIGH;
    public const int MAX_INMEMORY_DATA_SIZE = 512 * 1024;
    
    public enum Size {
        LARGEST = 360,
        BIG = 360,
        MEDIUM = 128,
        SMALLEST = 128;
        
        public int get_scale() {
            return (int) this;
        }
        
        public Scaling get_scaling() {
            return Scaling.for_best_fit(get_scale(), true);
        }
        
        public static Size get_best_size(int scale) {
            return scale <= MEDIUM.get_scale() ? MEDIUM : BIG;
        }
    }
    
    // Changed from public const to private static due to this bug:
    // https://bugzilla.gnome.org/show_bug.cgi?id=612315
    private static Size[] ALL_SIZES = { Size.BIG, Size.MEDIUM };
    
    public delegate void AsyncFetchCallback(Gdk.Pixbuf? pixbuf, Dimensions dim, Gdk.InterpType interp, 
        Error? err);
    
    private class ImageData {
        public Gdk.Pixbuf pixbuf;
        public ulong bytes;
        
        public ImageData(Gdk.Pixbuf pixbuf) {
            this.pixbuf = pixbuf;

            // This is not entirely accurate (see Gtk doc note on pixbuf Image Data), but close enough
            // for government work
            bytes = (ulong) pixbuf.get_rowstride() * (ulong) pixbuf.get_height();
        }
        
        ~ImageData() {
            cycle_dropped_bytes += bytes;
            schedule_debug();
        }
    }

    private class AsyncFetchJob : BackgroundJob {
        public ThumbnailCache cache;
        public PhotoID photo_id;
        public Dimensions dim;
        public Gdk.InterpType interp;
        public AsyncFetchCallback callback;
        public Gdk.Pixbuf pixbuf = null;
        public Gdk.Pixbuf scaled = null;
        public Error err = null;
        public bool fetched = false;
        
        public AsyncFetchJob(ThumbnailCache cache, PhotoID photo_id, Gdk.Pixbuf? prefetched, 
            Dimensions dim, Gdk.InterpType interp,  AsyncFetchCallback callback, Cancellable? cancellable) {
            base(cache, async_fetch_completion_callback, cancellable);
            
            this.cache = cache;
            this.photo_id = photo_id;
            this.pixbuf = prefetched;
            this.dim = dim;
            this.interp = interp;
            this.callback = callback;
        }
        
        public override BackgroundJob.JobPriority get_priority() {
            // lower-quality interps are scheduled first; this is interpreted as a "quick" thumbnail
            // fetch, versus higher-quality, which are to clean up the display
            switch (interp) {
                case Gdk.InterpType.NEAREST:
                case Gdk.InterpType.TILES:
                    return JobPriority.HIGH;
                
                case Gdk.InterpType.BILINEAR:
                case Gdk.InterpType.HYPER:
                default:
                    return JobPriority.NORMAL;
            }
        }
        
        private override void execute() {
            try {
                // load-and-decode if not already prefetched
                if (pixbuf == null) {
                    pixbuf = new Gdk.Pixbuf.from_file(cache.get_cached_file(photo_id).get_path());
                    fetched = true;
                }
                
                // scale if specified
                scaled = dim.has_area() ? resize_pixbuf(pixbuf, dim, interp) : pixbuf;
            } catch (Error err) {
                this.err = err;
            }
        }
    }
        
    private static Workers fetch_workers = null;
    
    public const ulong MAX_BIG_CACHED_BYTES = 40 * 1024 * 1024;
    public const ulong MAX_MEDIUM_CACHED_BYTES = 30 * 1024 * 1024;

    private static ThumbnailCache big = null;
    private static ThumbnailCache medium = null;
    
    private static OneShotScheduler debug_scheduler = null;
    private static int cycle_fetched_thumbnails = 0;
    private static int cycle_overflow_thumbnails = 0;
    private static ulong cycle_dropped_bytes = 0;
    private static int cycle_cancelled_async = 0;
    
    private File cache_dir;
    private Size size;
    private ulong max_cached_bytes;
    private Gdk.InterpType interp;
    private Jpeg.Quality quality;
    private Gee.HashMap<int64?, ImageData> cache_map = new Gee.HashMap<int64?, ImageData>(
        int64_hash, int64_equal, direct_equal);
    private Gee.ArrayList<int64?> cache_lru = new Gee.ArrayList<int64?>(int64_equal);
    private ulong cached_bytes = 0;
    
    private ThumbnailCache(Size size, ulong max_cached_bytes, Gdk.InterpType interp = DEFAULT_INTERP,
        Jpeg.Quality quality = DEFAULT_QUALITY) {
        cache_dir = AppDirs.get_data_subdir("thumbs", "thumbs%d".printf(size.get_scale()));
        this.size = size;
        this.max_cached_bytes = max_cached_bytes;
        this.interp = interp;
        this.quality = quality;
    }
    
    // Doing this because static construct {} not working nor new'ing in the above statement
    public static void init() {
        debug_scheduler = new OneShotScheduler("ThumbnailCache cycle reporter", report_cycle);
        fetch_workers = new Workers(Workers.THREAD_PER_CPU, false);
        
        big = new ThumbnailCache(Size.BIG, MAX_BIG_CACHED_BYTES);
        medium = new ThumbnailCache(Size.MEDIUM, MAX_MEDIUM_CACHED_BYTES);
    }
    
    public static void terminate() {
        fetch_workers.die();
    }
    
    public static void import_from_source(PhotoID photo_id, PhotoSource source, bool force = false)
        throws Error {
        big._import_from_source(photo_id, source, force);
        medium._import_from_source(photo_id, source, force);
    }
    
    public static void import_thumbnails(PhotoID photo_id, Thumbnails thumbnails, bool force = false)
        throws Error {
        big._import_thumbnail(photo_id, thumbnails.get(Size.BIG), force);
        medium._import_thumbnail(photo_id, thumbnails.get(Size.MEDIUM), force);
    }
    
    public static void duplicate(PhotoID src_id, PhotoID dest_id) {
        big._duplicate(src_id, dest_id);
        medium._duplicate(src_id, dest_id);
    }
    
    public static void remove(PhotoID photo_id) {
        big._remove(photo_id);
        medium._remove(photo_id);
    }
    
    private static ThumbnailCache get_best_cache(int scale) {
        Size size = Size.get_best_size(scale);
        if (size == Size.BIG) {
            return big;
        } else {
            assert(size == Size.MEDIUM);
            
            return medium;
        }
    }
    
    private static ThumbnailCache get_cache_for(Size size) {
        switch (size) {
            case Size.BIG:
                return big;
            
            case Size.MEDIUM:
                return medium;
            
            default:
                error("Unknown thumbnail size %d", size.get_scale());
                
                return medium;
        }
    }
    
    public static Gdk.Pixbuf fetch(PhotoID photo_id, int scale) throws Error {
        return get_best_cache(scale)._fetch(photo_id);
    }
    
    public static void fetch_async(PhotoID photo_id, int scale, AsyncFetchCallback callback,
        Cancellable? cancellable = null) {
        get_best_cache(scale)._fetch_async(photo_id, Dimensions(), DEFAULT_INTERP, callback, 
            cancellable);
    }
    
    public static void fetch_async_scaled(PhotoID photo_id, int scale, Dimensions dim, Gdk.InterpType interp,
        AsyncFetchCallback callback, Cancellable? cancellable = null) {
        get_best_cache(scale)._fetch_async(photo_id, dim, interp, callback, cancellable);
    }

    public static void replace(PhotoID photo_id, Size size, Gdk.Pixbuf replacement) throws Error {
        get_cache_for(size)._replace(photo_id, replacement);
    }
    
    public static bool exists(PhotoID photo_id) {
        return big._exists(photo_id) && medium._exists(photo_id);
    }
    
    public static void rotate(PhotoID photo_id, Rotation rotation) throws Error {
        foreach (Size size in ALL_SIZES) {
            Gdk.Pixbuf thumbnail = fetch(photo_id, size);
            thumbnail = rotation.perform(thumbnail);
            replace(photo_id, size, thumbnail);
        }
    }
    
    // This does not add the thumbnails to the ThumbnailCache, merely generates them for the
    // supplied image file.
    public static void generate(Thumbnails thumbnails, File file, Orientation orientation, 
        Dimensions original_dim) throws Error {
        foreach (Size size in ALL_SIZES) {
            Dimensions dim = size.get_scaling().get_scaled_dimensions(original_dim);
            
            // even if pixbuf is available, don't want to rescale it for the thumbnails;
            // a single scale is preferable, esp. for long-term storage
            Gdk.Pixbuf thumbnail = new Gdk.Pixbuf.from_file_at_size(file.get_path(), dim.width,
                    dim.height);
            thumbnail = orientation.rotate_pixbuf(thumbnail);
            
            thumbnails.set(size, thumbnail);
        }
    }
    
    // Displaying a debug message for each thumbnail loaded and dropped can cause a ton of messages
    // and slow down scrolling operations ... this delays reporting them, and only then reporting
    // them in one aggregate sum
    private static void schedule_debug() {
        debug_scheduler.priority_after_timeout(Priority.LOW, 500, true);
    }

    private static void report_cycle() {
        if (cycle_fetched_thumbnails > 0) {
            debug("%d thumbnails fetched into memory", cycle_fetched_thumbnails);
            cycle_fetched_thumbnails = 0;
        }
        
        if (cycle_overflow_thumbnails > 0) {
            debug("%d thumbnails overflowed from memory cache", cycle_overflow_thumbnails);
            cycle_overflow_thumbnails = 0;
        }
        
        if (cycle_dropped_bytes > 0) {
            debug("%lu bytes freed", cycle_dropped_bytes);
            cycle_dropped_bytes = 0;
        }
        
        if (cycle_cancelled_async > 0) {
            debug("%lu async fetches cancelled", cycle_cancelled_async);
            cycle_cancelled_async = 0;
        }
        
        foreach (Size size in ALL_SIZES) {
            ThumbnailCache cache = get_cache_for(size);
            ulong avg = (cache.cache_lru.size != 0) ? cache.cached_bytes / cache.cache_lru.size : 0;
            debug("thumbnail cache %d: %d thumbnails, %lu/%lu bytes, %lu bytes/thumbnail", 
                cache.size.get_scale(), cache.cache_lru.size, cache.cached_bytes,
                cache.max_cached_bytes, avg);
        }
    }
    
    private Gdk.Pixbuf _fetch(PhotoID photo_id) throws Error {
        // use JPEG in memory cache if available
        Gdk.Pixbuf pixbuf = fetch_from_memory(photo_id);
        if (pixbuf != null)
            return pixbuf;

        pixbuf = new Gdk.Pixbuf.from_file(get_cached_file(photo_id).get_path());
        
        cycle_fetched_thumbnails++;
        schedule_debug();
        
        // stash in memory for next time
        store_in_memory(photo_id, pixbuf);

        return pixbuf;
    }
    
    private void _fetch_async(PhotoID photo_id, Dimensions dim, Gdk.InterpType interp, 
        AsyncFetchCallback callback, Cancellable? cancellable) {
        // check if the pixbuf is already in memory
        Gdk.Pixbuf pixbuf = fetch_from_memory(photo_id);
        if (pixbuf != null && (!dim.has_area() || Dimensions.for_pixbuf(pixbuf).equals(dim))) {
            // if no scaling operation required, callback in this context and done (otherwise,
            // let the background threads perform the scaling operation, to spread out the work)
            callback(pixbuf, dim, interp, null);
                
            return;
        }
        
        // TODO: Note that there exists a cache condition in this current implementation.  It's
        // possible for two requests for the same thumbnail to come in back-to-back.  Since there's
        // no "reservation" system to indicate that an outstanding job is fetching that thumbnail
        // (and the other should wait until it's done), two (or more) fetches could occur on the
        // same thumbnail file.
        //
        // Due to the design of Shotwell, with one thumbnail per page, this is seen as an unlikely
        // situation.  This may change in the future, and the caching situation will need to be 
        // handled.
        
        fetch_workers.enqueue(new AsyncFetchJob(this, photo_id, pixbuf, dim, interp, callback, 
            cancellable));
    }
    
    // Called within Gtk.main's thread context
    private static void async_fetch_completion_callback(BackgroundJob background_job) {
        AsyncFetchJob job = (AsyncFetchJob) background_job;
        
        // don't store in cache if cancelled for locality reasons
        if (job.is_cancelled()) {
            cycle_cancelled_async++;
            schedule_debug();
            
            return;
        }
        
        // only store in cache if fetched, not pre-fetched
        if (job.pixbuf != null && job.fetched)
            job.cache.store_in_memory(job.photo_id, job.pixbuf);
        
        job.callback(job.scaled, job.dim, job.interp, job.err);
    }
    
    private void _import_from_source(PhotoID photo_id, PhotoSource source, bool force = false)
        throws Error {
        File file = get_cached_file(photo_id);
        
        // if not forcing the cache operation, check if file exists and is represented in the
        // database before continuing
        if (!force) {
            if (_exists(photo_id))
                return;
        } else {
            // wipe from system and continue
            _remove(photo_id);
        }
        
        save_thumbnail(file, source.get_pixbuf(Scaling.for_best_fit(size.get_scale(), true)));
        
        // See note in _import_with_pixbuf for reason why this is not maintained in in-memory
        // cache
    }
    
    private void _import_thumbnail(PhotoID photo_id, Gdk.Pixbuf? scaled, bool force = false) 
        throws Error {
        assert(scaled != null);
        assert(Dimensions.for_pixbuf(scaled).approx_scaled(size.get_scale()));
        
        File file = get_cached_file(photo_id);
        
        // if not forcing the cache operation, check if file exists and is represented in the
        // database before continuing
        if (!force) {
            if (_exists(photo_id))
                return;
        } else {
            // wipe previous from system and continue
            _remove(photo_id);
        }
        
        save_thumbnail(file, scaled);
        
        // do NOT store in the in-memory cache ... if a lot of photos are being imported at
        // once, this will blow cache locality, especially when the user is viewing one portion
        // of the collection while new photos are added far off the viewport
    }
    
    private void _duplicate(PhotoID src_id, PhotoID dest_id) {
        File src_file = get_cached_file(src_id);
        File dest_file = get_cached_file(dest_id);
        
        try {
            src_file.copy(dest_file, FileCopyFlags.ALL_METADATA, null, null);
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // Do NOT store in memory cache, for similar reasons as stated in _import().
    }
    
    private void _replace(PhotoID photo_id, Gdk.Pixbuf original) throws Error {
        File file = get_cached_file(photo_id);
        
        // Remove from in-memory cache, if present
        remove_from_memory(photo_id);
        
        // scale to cache's parameters
        Gdk.Pixbuf scaled = scale_pixbuf(original, size.get_scale(), interp, true);
        
        // save scaled image as JPEG
        save_thumbnail(file, scaled);
        
        // Store in in-memory cache; a _replace() probably represents a user-initiated
        // action (<cough>rotate</cough>) and the thumbnail will probably be fetched immediately.
        // This means the thumbnail will be cached in scales that aren't immediately needed, but the
        // benefit seems to outweigh the side-effects
        store_in_memory(photo_id, scaled);
    }
    
    private void _remove(PhotoID photo_id) {
        File file = get_cached_file(photo_id);
        
        // remove from in-memory cache
        remove_from_memory(photo_id);
        
        // remove from disk
        try {
            file.delete(null);
        } catch (Error err) {
            // ignored
        }
    }
    
    private bool _exists(PhotoID photo_id) {
        File file = get_cached_file(photo_id);

        return file.query_exists(null);
    }
    
    private File get_cached_file(PhotoID photo_id) {
        return cache_dir.get_child("thumb%016llx.jpg".printf(photo_id.id));
    }
    
    private Gdk.Pixbuf? fetch_from_memory(PhotoID photo_id) {
        ImageData data = cache_map.get(photo_id.id);
        
        return (data != null) ? data.pixbuf : null;
    }
    
    private void store_in_memory(PhotoID photo_id, Gdk.Pixbuf thumbnail) {
        if (max_cached_bytes <= 0)
            return;
        
        remove_from_memory(photo_id);
        
        ImageData data = new ImageData(thumbnail);

        // see if this is too large to keep in memory
        if(data.bytes > MAX_INMEMORY_DATA_SIZE) {
            debug("Persistant thumbnail [%lld] too large to cache in memory", photo_id.id);

            return;
        }
        
        cache_map.set(photo_id.id, data);
        cache_lru.insert(0, photo_id.id);
        
        cached_bytes += data.bytes;
        
        // trim cache
        while (cached_bytes > max_cached_bytes) {
            assert(cache_lru.size > 0);
            int index = cache_lru.size - 1;
            
            int64 id = cache_lru.get(index);
            cache_lru.remove_at(index);
            
            data = cache_map.get(id);
            
            cycle_overflow_thumbnails++;
            schedule_debug();
            
            bool removed = cache_map.unset(id);
            assert(removed);

            assert(data.bytes <= cached_bytes);
            cached_bytes -= data.bytes;
        }
    }
    
    private bool remove_from_memory(PhotoID photo_id) {
        ImageData data = cache_map.get(photo_id.id);
        if (data == null)
            return false;
        
        assert(cached_bytes >= data.bytes);
        cached_bytes -= data.bytes;

        // remove data from in-memory cache
        bool removed = cache_map.unset(photo_id.id);
        assert(removed);
        
        // remove from LRU
        removed = cache_lru.remove(photo_id.id);
        assert(removed);
        
        return true;
    }
    
    private void save_thumbnail(File file, Gdk.Pixbuf pixbuf) throws Error {
        pixbuf.save(file.get_path(), "jpeg", "quality", quality.get_pct_text());
    }
}

