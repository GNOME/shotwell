/* Copyright 2016 Software Freedom Conservancy Inc.
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
    
    // Some code relies on Size's pixel values being manipulated and then using Size's methods,
    // so be careful before changing any of these values (and especially careful before arbitrarily
    // manipulating a Size enum)
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
    
    private static Size[] ALL_SIZES = { Size.BIG, Size.MEDIUM };
    
    public delegate void AsyncFetchCallback(Gdk.Pixbuf? pixbuf, Gdk.Pixbuf? unscaled, Dimensions dim,
        Gdk.InterpType interp, Error? err);
    
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
        public string thumbnail_name;
        public ThumbnailSource source;
        public PhotoFileFormat source_format;
        public Dimensions dim;
        public Gdk.InterpType interp;
        public unowned AsyncFetchCallback callback;
        public Gdk.Pixbuf unscaled;
        public Gdk.Pixbuf scaled = null;
        public Error err = null;
        public bool fetched = false;
        public bool replace = false;
        
        public AsyncFetchJob(ThumbnailCache cache, string thumbnail_name,
            ThumbnailSource source, Gdk.Pixbuf? prefetched, Dimensions dim,
            Gdk.InterpType interp, AsyncFetchCallback callback, Cancellable? cancellable) {
            base(cache, async_fetch_completion_callback, cancellable);
            
            this.cache = cache;
            this.thumbnail_name = thumbnail_name;
            this.source = source;
            this.source_format = source.get_preferred_thumbnail_format();
            this.unscaled = prefetched;
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
        
        public override void execute() {
            try {
                // load-and-decode if not already prefetched
                if (unscaled == null) {
                    unscaled = cache.read_pixbuf(thumbnail_name, source_format);
                    fetched = true;
                }
                
                if (is_cancelled())
                    return;
                
                // scale if specified
                scaled = dim.has_area() ? resize_pixbuf(unscaled, dim, interp) : unscaled;
            } catch (Error err) {
                if (err is FileError) {
                    try {
                        generate_thumbnail();
                    } catch (Error generr) {
                        // save thumbnail generation error, not original, for processing in callback
                        err = generr;
                    }
                } else {
                    // save error for processing in callback
                    this.err = err;
                }
            }
        }
        
        private void generate_thumbnail() throws Error {
            Photo? photo = source as Photo;
            if (photo != null) {
                unscaled = photo.get_pixbuf(Scaling.for_best_fit(dim.major_axis(), true));
            } else {
                Video? video = source as Video;
                if (video != null)
                    unscaled = video.create_thumbnail(dim.width);
            }
            
            if (unscaled != null) {
                scaled = resize_pixbuf(unscaled, dim, interp);
                replace = true;
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
    private static int cycle_async_fetched_thumbnails = 0;
    private static int cycle_async_resized_thumbnails = 0;
    private static int cycle_overflow_thumbnails = 0;
    private static ulong cycle_dropped_bytes = 0;
    
    private File cache_dir;
    private Size size;
    private ulong max_cached_bytes;
    private Gdk.InterpType interp;
    private Jpeg.Quality quality;
    private Gee.HashMap<string, ImageData> cache_map = new Gee.HashMap<string, ImageData>();
    private Gee.ArrayList<string> cache_lru = new Gee.ArrayList<string>();
    private ulong cached_bytes = 0;
    
    private ThumbnailCache(Size size, ulong max_cached_bytes, Gdk.InterpType interp = DEFAULT_INTERP,
        Jpeg.Quality quality = DEFAULT_QUALITY) {
        cache_dir = AppDirs.get_cache_subdir("thumbs", "thumbs%d".printf(size.get_scale()));
        this.size = size;
        this.max_cached_bytes = max_cached_bytes;
        this.interp = interp;
        this.quality = quality;
    }
    
    // Doing this because static construct {} not working nor new'ing in the above statement
    public static void init() {
        debug_scheduler = new OneShotScheduler("ThumbnailCache cycle reporter", report_cycle);
        fetch_workers = new Workers(Workers.threads_per_cpu(1), true);
        
        big = new ThumbnailCache(Size.BIG, MAX_BIG_CACHED_BYTES);
        medium = new ThumbnailCache(Size.MEDIUM, MAX_MEDIUM_CACHED_BYTES);
    }
    
    public static void terminate() {
    }
    
    public static void import_from_source(ThumbnailSource source, bool force = false)
        throws Error {
        debug("import from source: %s", source.to_string());
        big._import_from_source(source, force);
        medium._import_from_source(source, force);
    }
    
    public static void import_thumbnails(ThumbnailSource source, Thumbnails thumbnails,
        bool force = false) throws Error {
        big._import_thumbnail(source, thumbnails.get(Size.BIG), force);
        medium._import_thumbnail(source, thumbnails.get(Size.MEDIUM), force);
    }
    
    public static void duplicate(ThumbnailSource src_source, ThumbnailSource dest_source) {
        big._duplicate(src_source, dest_source);
        medium._duplicate(src_source, dest_source);
    }
    
    public static void remove(ThumbnailSource source) {
        big._remove(source);
        medium._remove(source);
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
        }
    }
    
    public static Gdk.Pixbuf fetch(ThumbnailSource source, int scale) throws Error {
        return get_best_cache(scale)._fetch(source);
    }
    
    public static void fetch_async(ThumbnailSource source, int scale, AsyncFetchCallback callback,
        Cancellable? cancellable = null) {
        get_best_cache(scale)._fetch_async(source, source.get_preferred_thumbnail_format(),
            Dimensions(), DEFAULT_INTERP, callback, cancellable);
    }
    
    public static void fetch_async_scaled(ThumbnailSource source, int scale, Dimensions dim,
        Gdk.InterpType interp, AsyncFetchCallback callback, Cancellable? cancellable = null) {
        get_best_cache(scale)._fetch_async(source,
            source.get_preferred_thumbnail_format(), dim, interp, callback, cancellable);
    }
    
    public static void replace(ThumbnailSource source, Size size, Gdk.Pixbuf replacement)
        throws Error {
        get_cache_for(size)._replace(source, replacement);
    }
    
    public static bool exists(ThumbnailSource source) {
        return big._exists(source) && medium._exists(source);
    }
    
    public static void rotate(ThumbnailSource source, Rotation rotation) throws Error {
        foreach (Size size in ALL_SIZES) {
            Gdk.Pixbuf thumbnail = fetch(source, size);
            thumbnail = rotation.perform(thumbnail);
            replace(source, size, thumbnail);
        }
    }
    
    // This does not add the thumbnails to the ThumbnailCache, merely generates them for the
    // supplied image file.
    public static void generate_for_photo(Thumbnails thumbnails, PhotoFileReader reader,
        Orientation orientation, Dimensions original_dim) throws Error {
        // Taking advantage of Size's values matching their pixel size
        Size max_size = Size.BIG * 2;
        Dimensions dim = max_size.get_scaling().get_scaled_dimensions(original_dim);
        Gdk.Pixbuf? largest_thumbnail = null;
        try {
            largest_thumbnail = reader.scaled_read(original_dim, dim);
        } catch (Error err) {
            // if the scaled read generated an error, catch it and try to do an unscaled read
            // followed by a downsample. If the call to unscaled_read() below throws an error,
            // just propagate it up to the caller
            largest_thumbnail = reader.unscaled_read();
        }
        largest_thumbnail = orientation.rotate_pixbuf(largest_thumbnail);
        Dimensions largest_thumb_dimensions = Dimensions.for_pixbuf(largest_thumbnail);

        foreach (Size size in ALL_SIZES) {
            dim = size.get_scaling().get_scaled_dimensions(largest_thumb_dimensions);
            thumbnails.set(size, largest_thumbnail.scale_simple(dim.width, dim.height, Gdk.InterpType.HYPER));
        }
    }
    
    public static void generate_for_video_frame(Thumbnails thumbnails, Gdk.Pixbuf preview_frame) {
        foreach (Size size in ALL_SIZES) {
            Scaling current_scaling = size.get_scaling();
            Gdk.Pixbuf current_thumbnail = current_scaling.perform_on_pixbuf(preview_frame,
                Gdk.InterpType.HYPER, true);
            thumbnails.set(size, current_thumbnail);
        }
    }
    
    // Displaying a debug message for each thumbnail loaded and dropped can cause a ton of messages
    // and slow down scrolling operations ... this delays reporting them, and only then reporting
    // them in one aggregate sum
    private static void schedule_debug() {
#if MONITOR_THUMBNAIL_CACHE
        debug_scheduler.priority_after_timeout(Priority.LOW, 500, true);
#endif
    }

    private static void report_cycle() {
#if MONITOR_THUMBNAIL_CACHE
        if (cycle_fetched_thumbnails > 0) {
            debug("%d thumbnails fetched into memory", cycle_fetched_thumbnails);
            cycle_fetched_thumbnails = 0;
        }
        
        if (cycle_async_fetched_thumbnails > 0) {
            debug("%d thumbnails fetched async into memory", cycle_async_fetched_thumbnails);
            cycle_async_fetched_thumbnails = 0;
        }
        
        if (cycle_async_resized_thumbnails > 0) {
            debug("%d thumbnails resized async into memory", cycle_async_resized_thumbnails);
            cycle_async_resized_thumbnails = 0;
        }
        
        if (cycle_overflow_thumbnails > 0) {
            debug("%d thumbnails overflowed from memory cache", cycle_overflow_thumbnails);
            cycle_overflow_thumbnails = 0;
        }
        
        if (cycle_dropped_bytes > 0) {
            debug("%lu bytes freed", cycle_dropped_bytes);
            cycle_dropped_bytes = 0;
        }
        
        foreach (Size size in ALL_SIZES) {
            ThumbnailCache cache = get_cache_for(size);
            ulong avg = (cache.cache_lru.size != 0) ? cache.cached_bytes / cache.cache_lru.size : 0;
            debug("thumbnail cache %d: %d thumbnails, %lu/%lu bytes, %lu bytes/thumbnail", 
                cache.size.get_scale(), cache.cache_lru.size, cache.cached_bytes,
                cache.max_cached_bytes, avg);
        }
#endif
    }
    
    private Gdk.Pixbuf _fetch(ThumbnailSource source) throws Error {
        // use JPEG in memory cache if available
        Gdk.Pixbuf pixbuf = fetch_from_memory(source.get_source_id());
        if (pixbuf != null)
            return pixbuf;
        
        pixbuf = read_pixbuf(source.get_source_id(), source.get_preferred_thumbnail_format());
        
        cycle_fetched_thumbnails++;
        schedule_debug();
        
        // stash in memory for next time
        store_in_memory(source.get_source_id(), pixbuf);
        
        return pixbuf;
    }
    
    private void _fetch_async(ThumbnailSource source, PhotoFileFormat format, Dimensions dim,
        Gdk.InterpType interp, AsyncFetchCallback callback, Cancellable? cancellable) {
        // check if the pixbuf is already in memory
        string thumbnail_name = source.get_source_id();
        Gdk.Pixbuf pixbuf = fetch_from_memory(thumbnail_name);
        if (pixbuf != null && (!dim.has_area() || Dimensions.for_pixbuf(pixbuf).equals(dim))) {
            // if no scaling operation required, callback in this context and done (otherwise,
            // let the background threads perform the scaling operation, to spread out the work)
            callback(pixbuf, pixbuf, dim, interp, null);
            
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
        
        fetch_workers.enqueue(new AsyncFetchJob(this, thumbnail_name, source, pixbuf, dim,
            interp, callback, cancellable));
    }
    
    // Called within Gtk.main's thread context
    private static void async_fetch_completion_callback(BackgroundJob background_job) {
        AsyncFetchJob job = (AsyncFetchJob) background_job;
        
        // Is the problem that the thumbnail couldn't be read? If so, it's recoverable;
        // we'll just create it and leave this.err as null if creation works.
        if (job.replace && job.unscaled != null) {
            try {
                replace(job.source, job.cache.size, job.unscaled);
            } catch (Error err) {
                job.err = err;
            }
        }
        
        if (job.unscaled != null) {
            if (job.fetched) {
                // only store in cache if fetched, not pre-fetched
                job.cache.store_in_memory(job.thumbnail_name, job.unscaled);
                
                cycle_async_fetched_thumbnails++;
                schedule_debug();
            } else {
                cycle_async_resized_thumbnails++;
                schedule_debug();
            }
        }
        
        job.callback(job.scaled, job.unscaled, job.dim, job.interp, job.err);
    }
    
    private void _import_from_source(ThumbnailSource source, bool force = false)
        throws Error {
        File file = get_source_cached_file(source);
        
        // if not forcing the cache operation, check if file exists and is represented in the
        // database before continuing
        if (!force) {
            if (_exists(source))
                return;
        } else {
            // wipe from system and continue
            _remove(source);
        }

        LibraryPhoto photo = (LibraryPhoto) source;
        save_thumbnail(file, photo.get_pixbuf(Scaling.for_best_fit(size.get_scale(), true)), source);
        
        // See note in _import_with_pixbuf for reason why this is not maintained in in-memory
        // cache
    }
    
    private void _import_thumbnail(ThumbnailSource source, Gdk.Pixbuf? scaled, bool force = false) 
        throws Error {
        assert(scaled != null);
        assert(Dimensions.for_pixbuf(scaled).approx_scaled(size.get_scale()));
        
        // if not forcing the cache operation, check if file exists and is represented in the
        // database before continuing
        if (!force) {
            if (_exists(source))
                return;
        } else {
            // wipe previous from system and continue
            _remove(source);
        }
        
        save_thumbnail(get_source_cached_file(source), scaled, source);
        
        // do NOT store in the in-memory cache ... if a lot of photos are being imported at
        // once, this will blow cache locality, especially when the user is viewing one portion
        // of the collection while new photos are added far off the viewport
    }
    
    private void _duplicate(ThumbnailSource src_source, ThumbnailSource dest_source) {
        File src_file = get_source_cached_file(src_source);
        File dest_file = get_cached_file(dest_source.get_representative_id(),
            src_source.get_preferred_thumbnail_format());
        
        try {
            src_file.copy(dest_file, FileCopyFlags.ALL_METADATA | FileCopyFlags.OVERWRITE, null, null);
        } catch (Error err) {
            AppWindow.panic("%s".printf(err.message));
        }
        
        // Do NOT store in memory cache, for similar reasons as stated in _import().
    }
    
    private void _replace(ThumbnailSource source, Gdk.Pixbuf original) throws Error {
        File file = get_source_cached_file(source);
        
        // Remove from in-memory cache, if present
        remove_from_memory(source.get_source_id());
        
        // scale to cache's parameters
        Gdk.Pixbuf scaled = scale_pixbuf(original, size.get_scale(), interp, true);
        
        // save scaled image to disk
        save_thumbnail(file, scaled, source);
        
        // Store in in-memory cache; a _replace() probably represents a user-initiated
        // action (<cough>rotate</cough>) and the thumbnail will probably be fetched immediately.
        // This means the thumbnail will be cached in scales that aren't immediately needed, but
        // the benefit seems to outweigh the side-effects
        store_in_memory(source.get_source_id(), scaled);
    }
    
    private void _remove(ThumbnailSource source) {
        File file = get_source_cached_file(source);
        
        // remove from in-memory cache
        remove_from_memory(source.get_source_id());
        
        // remove from disk
        try {
            file.delete(null);
        } catch (Error err) {
            // ignored
        }
    }
    
    private bool _exists(ThumbnailSource source) {
        return get_source_cached_file(source).query_exists(null);
    }
    
    // This method is thread-safe.
    private Gdk.Pixbuf read_pixbuf(string thumbnail_name, PhotoFileFormat format) throws Error {
        return format.create_reader(get_cached_file(thumbnail_name,
            format).get_path()).unscaled_read();
    }
    
    private File get_source_cached_file(ThumbnailSource source) {
        return get_cached_file(source.get_representative_id(),
            source.get_preferred_thumbnail_format());
    }
    
    private File get_cached_file(string thumbnail_name, PhotoFileFormat thumbnail_format) {
        return cache_dir.get_child(thumbnail_format.get_default_basename(thumbnail_name));
    }
    
    private Gdk.Pixbuf? fetch_from_memory(string thumbnail_name) {
        ImageData data = cache_map.get(thumbnail_name);
        
        return (data != null) ? data.pixbuf : null;
    }
    
    private void store_in_memory(string thumbnail_name, Gdk.Pixbuf thumbnail) {
        if (max_cached_bytes <= 0)
            return;
        
        remove_from_memory(thumbnail_name);
        
        ImageData data = new ImageData(thumbnail);

        // see if this is too large to keep in memory
        if(data.bytes > MAX_INMEMORY_DATA_SIZE) {
            debug("Persistent thumbnail [%s] too large to cache in memory", thumbnail_name);

            return;
        }
        
        cache_map.set(thumbnail_name, data);
        cache_lru.insert(0, thumbnail_name);
        
        cached_bytes += data.bytes;
        
        // trim cache
        while (cached_bytes > max_cached_bytes) {
            assert(cache_lru.size > 0);
            int index = cache_lru.size - 1;
            
            string victim_name = cache_lru.get(index);
            cache_lru.remove_at(index);
            
            data = cache_map.get(victim_name);
            
            cycle_overflow_thumbnails++;
            schedule_debug();
            
            bool removed = cache_map.unset(victim_name);
            assert(removed);

            assert(data.bytes <= cached_bytes);
            cached_bytes -= data.bytes;
        }
    }
    
    private bool remove_from_memory(string thumbnail_name) {
        ImageData data = cache_map.get(thumbnail_name);
        if (data == null)
            return false;
        
        assert(cached_bytes >= data.bytes);
        cached_bytes -= data.bytes;

        // remove data from in-memory cache
        bool removed = cache_map.unset(thumbnail_name);
        assert(removed);
        
        // remove from LRU
        removed = cache_lru.remove(thumbnail_name);
        assert(removed);
        
        return true;
    }
    
    private void save_thumbnail(File file, Gdk.Pixbuf pixbuf, ThumbnailSource source) throws Error {
        source.get_preferred_thumbnail_format().create_writer(file.get_path()).write(pixbuf,
            DEFAULT_QUALITY);
    }
}

