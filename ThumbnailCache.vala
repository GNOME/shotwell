
// these functions generate compiler warnings due to Vala not supporting const pointers (yet) ...
// see http://www.mail-archive.com/vala-list@gnome.org/msg00977.html
public uint photo_id_hash(void *key) {
    PhotoID *photoID = (PhotoID *) key;
    
    return (uint) photoID->id;
}

public bool photo_id_equal(void *a, void *b) {
    PhotoID *aID = (PhotoID *) a;
    PhotoID *bID = (PhotoID *) b;
    
    return aID->id == bID->id;
}

public class ThumbnailCache : Object {
    public static const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.HYPER;
    public static const int DEFAULT_JPEG_QUALITY = 95;
    public static const int MAX_INMEMORY_DATA_SIZE = 256 * 1024;

    public static ThumbnailCache big = null;
    
    // Doing this because static construct {} not working nor new'ing in the above statement
    public static void init() {
        big = new ThumbnailCache(360);
    }

    private class ImageData {
        public uchar[] buffer;
        
        public ImageData(uchar[] buffer) {
            this.buffer = buffer;
        }
    }

    private File cacheDir;
    private int scale;
    private Gdk.InterpType interp;
    private string jpegQuality;
    private Gee.HashMap<PhotoID, ImageData> cacheMap = new Gee.HashMap<PhotoID, ImageData>(
        photo_id_hash, photo_id_equal, direct_equal);
    private long cachedBytes = 0;
    private ThumbnailCacheTable cacheTable;
    
    private ThumbnailCache(int scale, Gdk.InterpType interp = DEFAULT_INTERP,
        int jpegQuality = DEFAULT_JPEG_QUALITY) {
        assert(scale != 0);
        assert((jpegQuality >= 0) && (jpegQuality <= 100));

        this.cacheDir = AppWindow.get_data_subdir("thumbs", "thumbs%d".printf(scale));
        this.scale = scale;
        this.interp = interp;
        this.jpegQuality = "%d".printf(jpegQuality);
        this.cacheTable = new ThumbnailCacheTable(scale);
    }
    
    public Gdk.Pixbuf? fetch(PhotoID photoID) {
        // use JPEG in memory cache if available
        if (cacheMap.contains(photoID)) {
            ImageData data = cacheMap.get(photoID);
            try {
                MemoryInputStream memins = new MemoryInputStream.from_data(data.buffer, 
                    data.buffer.length, null);
                Gdk.Pixbuf thumbnail = new Gdk.Pixbuf.from_stream(memins, null);

                return thumbnail;
            } catch (Error err) {
                error("%s", err.message);
            }
        }

        // load from disk and then store in memory
        File cached = get_cached_file(photoID);
        debug("Loading from disk [%d] %s", photoID.id, cached.get_path());

        Gdk.Pixbuf thumbnail = null;
        try {
            int filesize = cacheTable.get_filesize(photoID);
            if(filesize > MAX_INMEMORY_DATA_SIZE) {
                // too big to store in memory, so build the pixbuf straight from disk
                debug("%s too large to cache, loading straight from disk", cached.get_path());

                return new Gdk.Pixbuf.from_file(cached.get_path());
            }

            FileInputStream fins = cached.read(null);
            assert(fins != null);

            uchar[] buffer = new uchar[filesize];
            
            size_t bytesRead;
            if (fins.read_all(buffer, filesize, out bytesRead, null) == false) {
                error("Unable to read %d bytes from %s", buffer.length, cached.get_path());
            }
            
            assert(bytesRead == filesize);

            ImageData data = new ImageData(buffer);
            cacheMap.set(photoID, data);
            cachedBytes += data.buffer.length;

            MemoryInputStream memins = new MemoryInputStream.from_data(data.buffer, 
                data.buffer.length, null);
            thumbnail = new Gdk.Pixbuf.from_stream(memins, null);
        } catch (Error err) {
            error("%s", err.message);
        }
        
        return thumbnail;
    }
    
    public bool import(PhotoID photoID, File file, bool force = false) {
        File cached = get_cached_file(photoID);
        
        // if not forcing the cache operation, check if file exists and is represented in the
        // database before continuing
        if (!force) {
            if (cached.query_exists(null) && cacheTable.exists(photoID))
                return true;
        }

        debug("Building persistent thumbnail for [%d] %s", photoID.id, cached.get_path());
        
        // load full-scale photo and convert to pixbuf
        Gdk.Pixbuf original;
        try {
            original = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }

        // scale according to cache's parameters
        Gdk.Pixbuf thumbnail = scale_pixbuf(original, scale, interp);
        
        // save scaled image as JPEG
        int filesize = -1;
        try {
            if (thumbnail.save(cached.get_path(), "jpeg", "quality", jpegQuality) == false) {
                error("Unable to save thumbnail %s", cached.get_path());
            }

            FileInfo info = cached.query_info(FILE_ATTRIBUTE_STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            
            // this should never be huge
            assert(info.get_size() <= int.MAX);
            filesize = (int) info.get_size();
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // store in database
        Dimensions dim = Dimensions(thumbnail.get_width(), thumbnail.get_height());
        cacheTable.add(photoID, filesize, dim);
        
        return true;
    }
    
    public void remove(PhotoID photoID) {
        File cached = get_cached_file(photoID);
        
        debug("Removing [%d] %s", photoID.id, cached.get_path());

        if (cacheMap.contains(photoID)) {
            ImageData data = cacheMap.get(photoID);

            assert(cachedBytes >= data.buffer.length);
            cachedBytes -= data.buffer.length;

            // remove from in-memory cache
            cacheMap.remove(photoID);
        }
        
        // remove from db table
        cacheTable.remove(photoID);
 
        // remove from disk
        try {
            if (cached.delete(null) == false) {
                error("Unable to delete cached thumb %s", cached.get_path());
            }
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    public Dimensions? get_dimensions(PhotoID photoID) {
        return cacheTable.get_dimensions(photoID);
    }

    private File get_cached_file(PhotoID photoID) {
        return cacheDir.get_child("thumb%08x.jpg".printf(photoID.id));
    }
}
