
public class ThumbnailCache : Object {
    public static const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.HYPER;
    public static const int DEFAULT_JPEG_QUALITY = 90;
    public static const int MAX_INMEMORY_DATA_SIZE = 256 * 1024;
    
    public static const int BIG_SCALE = 360;
    public static const int MEDIUM_SCALE = 128;
    public static const int SMALL_SCALE = 64;

    private static ThumbnailCache big = null;
    private static ThumbnailCache medium = null;
    private static ThumbnailCache small = null;
    
    // Doing this because static construct {} not working nor new'ing in the above statement
    public static void init() {
        big = new ThumbnailCache(BIG_SCALE);
        medium = new ThumbnailCache(MEDIUM_SCALE);
        small = new ThumbnailCache(SMALL_SCALE);
    }
    
    public static Dimensions import(PhotoID photoID, Gdk.Pixbuf original, bool force = false) {
        big._import(photoID, original, force);
        medium._import(photoID, original, force);
        small._import(photoID, original, force);
        
        return Dimensions(original.get_width(), original.get_height());
    }
    
    public static void remove(PhotoID photoID) {
        big._remove(photoID);
        medium._remove(photoID);
        small._remove(photoID);
    }

    private static const int BIG_MED_BREAK = MEDIUM_SCALE + ((BIG_SCALE - MEDIUM_SCALE) / 2);
    private static const int SMALL_MED_BREAK = SMALL_SCALE + ((MEDIUM_SCALE - SMALL_SCALE) / 2);

    public static bool refresh_pixbuf(int oldScale, int newScale) {
        if (oldScale > MEDIUM_SCALE) {
            return (newScale <= MEDIUM_SCALE);
        } else if(oldScale > SMALL_SCALE) {
            return (newScale <= SMALL_SCALE) || (newScale > MEDIUM_SCALE);
        } else {
            return (newScale > SMALL_SCALE);
        }
    }

    public static Gdk.Pixbuf? fetch(PhotoID photoID, int scale) {
        if (scale > MEDIUM_SCALE) {
            return big._fetch(photoID);
        } else if(scale > SMALL_SCALE) {
            return medium._fetch(photoID);
        } else {
            return small._fetch(photoID);
        }
    }
    
    public static Gdk.Pixbuf? fetch_scaled(PhotoID photo_id, int scale, Gdk.InterpType interp) {
        Gdk.Pixbuf pixbuf = fetch(photo_id, scale);
        if (pixbuf == null)
            return null;
        
        return scale_pixbuf(pixbuf, scale, interp);
    }
    
    private class ImageData {
        public Gdk.Pixbuf pixbuf;
        public uint bytes;
        
        public ImageData(Gdk.Pixbuf pixbuf, uint bytes) {
            this.pixbuf = pixbuf;
            this.bytes = bytes;
        }
    }

    private File cache_dir;
    private int scale;
    private Gdk.InterpType interp;
    private string jpeg_quality;
    private Gee.HashMap<int64?, ImageData> cache_map = new Gee.HashMap<int64?, ImageData>(
        int64_hash, int64_equal, direct_equal);
    private long cached_bytes = 0;
    private ThumbnailCacheTable cache_table;
    
    private ThumbnailCache(int scale, Gdk.InterpType interp = DEFAULT_INTERP,
        int jpeg_quality = DEFAULT_JPEG_QUALITY) {
        assert(scale != 0);
        assert((jpeg_quality >= 0) && (jpeg_quality <= 100));

        this.cache_dir = AppWindow.get_data_subdir("thumbs", "thumbs%d".printf(scale));
        this.scale = scale;
        this.interp = interp;
        this.jpeg_quality = "%d".printf(jpeg_quality);
        this.cache_table = new ThumbnailCacheTable(scale);
    }
    
    private Gdk.Pixbuf? _fetch(PhotoID photo_id) {
        // use JPEG in memory cache if available
        if (cache_map.contains(photo_id.id)) {
            ImageData data = cache_map.get(photo_id.id);
            
            return data.pixbuf;
        }

        File cached = get_cached_file(photo_id);

        debug("Loading from disk [%lld] %s", photo_id.id, cached.get_path());

        Gdk.Pixbuf thumbnail = null;
        try {
            int filesize = cache_table.get_filesize(photo_id);
            if(filesize > MAX_INMEMORY_DATA_SIZE) {
                // too big to store in memory, so build the pixbuf straight from disk
                debug("%s too large to cache, loading straight from disk", cached.get_path());

                return new Gdk.Pixbuf.from_file(cached.get_path());
            }

            FileInputStream fins = cached.read(null);
            assert(fins != null);

            uchar[] buffer = new uchar[filesize];
            
            size_t bytes_read;
            if (!fins.read_all(buffer, filesize, out bytes_read, null))
                error("Unable to read %d bytes from %s", buffer.length, cached.get_path());
            
            assert(bytes_read == filesize);

            MemoryInputStream memins = new MemoryInputStream.from_data(buffer, buffer.length, null);
            thumbnail = new Gdk.Pixbuf.from_stream(memins, null);

            // Although buffer.length doesn't accurately represent the in-memory size of the pixbuf
            // object, it suffices to indicate magnitude when trimming LRU
            ImageData data = new ImageData(thumbnail, buffer.length);
            cache_map.set(photo_id.id, data);
            cached_bytes += buffer.length;
        } catch (Error err) {
            error("%s", err.message);
        }
        
        return thumbnail;
    }
    
    private void _import(PhotoID photo_id, Gdk.Pixbuf original, bool force = false) {
        File cached = get_cached_file(photo_id);
        
        // if not forcing the cache operation, check if file exists and is represented in the
        // database before continuing
        if (!force) {
            if (cached.query_exists(null) && cache_table.exists(photo_id))
                return;
        } else {
            // wipe previous from system and continue
            _remove(photo_id);
        }

        debug("Building persistent thumbnail for [%lld] %s", photo_id.id, cached.get_path());
        
        // scale according to cache's parameters
        Gdk.Pixbuf thumbnail = scale_pixbuf(original, scale, interp);
        
        // save scaled image as JPEG
        int filesize = -1;
        try {
            if (!thumbnail.save(cached.get_path(), "jpeg", "quality", jpeg_quality))
                error("Unable to save thumbnail %s", cached.get_path());

            FileInfo info = cached.query_info(FILE_ATTRIBUTE_STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            
            // this should never be huge
            assert(info.get_size() <= int.MAX);
            filesize = (int) info.get_size();
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // store in database
        cache_table.add(photo_id, filesize, Dimensions.for_pixbuf(thumbnail));
    }
    
    private void _remove(PhotoID photo_id) {
        File cached = get_cached_file(photo_id);
        
        debug("Removing [%lld] %s", photo_id.id, cached.get_path());

        if (cache_map.contains(photo_id.id)) {
            ImageData data = cache_map.get(photo_id.id);

            assert(cached_bytes >= data.bytes);
            cached_bytes -= data.bytes;

            // remove from in-memory cache
            cache_map.remove(photo_id.id);
        }
        
        // remove from db table
        cache_table.remove(photo_id);
 
        // remove from disk
        try {
            if (!cached.delete(null))
                warning("Unable to delete cached thumb %s", cached.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    private File get_cached_file(PhotoID photo_id) {
        return cache_dir.get_child("thumb%016llx.jpg".printf(photo_id.id));
    }
}
