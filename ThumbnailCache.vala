
public class ThumbnailCache {
    public static const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.HYPER;
    public static const int DEFAULT_JPEG_QUALITY = 95;
    public static const int MAX_INMEMORY_DATA_SIZE = 256 * 1024;

    public static ThumbnailCache big = null;
    
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
    private Gee.HashMap<int, ImageData> cacheMap = new Gee.HashMap<int, ImageData>(
        direct_hash, direct_equal, direct_equal);
    private long cachedBytes = 0;
    
    private ThumbnailCache(int scale, Gdk.InterpType interp = DEFAULT_INTERP,
        int jpegQuality = DEFAULT_JPEG_QUALITY) {
        assert(scale != 0);
        assert((jpegQuality >= 0) && (jpegQuality <= 100));

        this.cacheDir = AppWindow.get_data_subdir("thumbs", "thumbs%d".printf(scale));
        this.scale = scale;
        this.interp = interp;
        this.jpegQuality = "%d".printf(jpegQuality);
    }
    
    public Gdk.Pixbuf? fetch(int id) {
        // use JPEG in memory cache if available
        if (cacheMap.contains(id)) {
            ImageData data = cacheMap.get(id);
            try {
                MemoryInputStream memins = new MemoryInputStream.from_data(data.buffer, 
                    data.buffer.length, null);
                Gdk.Pixbuf thumbnail = new Gdk.Pixbuf.from_stream(memins, null);

                return thumbnail;
            } catch (Error err) {
                error("%s", err.message);
                
                // fall through
            }
        }

        // load from disk and then story in memory
        File cached = get_cached_file(id);
        message("Loading from disk [%d] %s", id, cached.get_path());

        Gdk.Pixbuf thumbnail = null;
        try {
            FileInfo info = cached.query_info(FILE_ATTRIBUTE_STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            if(info.get_size() > MAX_INMEMORY_DATA_SIZE) {
                // too big to store in memory, so build the pixbuf straight from disk
                message("%s too large to cache, loading straight from disk", cached.get_path());

                return new Gdk.Pixbuf.from_file(cached.get_path());
            }

            FileInputStream fins = cached.read(null);
            if (fins == null) {
                error("Unable to open file %s for reading", cached.get_path());
                
                return null;
            }
            
            uchar[] buffer = new uchar[info.get_size()];
            
            size_t bytesRead;
            if (fins.read_all(buffer, buffer.length, out bytesRead, null) == false) {
                error("Unable to read %d bytes from %s", buffer.length, cached.get_path());
                
                return null;
            }

            if (bytesRead != buffer.length) {
                error("Only read %d out of %d bytes from %s", (int) bytesRead, buffer.length,
                    cached.get_path());
                
                return null;
            }
            
            ImageData data = new ImageData(buffer);
            cacheMap.set(id, data);
            cachedBytes += data.buffer.length;

            MemoryInputStream memins = new MemoryInputStream.from_data(data.buffer, 
                data.buffer.length, null);
            thumbnail = new Gdk.Pixbuf.from_stream(memins, null);
        } catch (Error err) {
            error("%s", err.message);
        }
        
        return thumbnail;
    }
    
    public bool import(int id, File file, bool force = false) {
        File cached = get_cached_file(id);
        
        // if not forcing the cache operation, check if file exists before performing
        if (!force) {
            if (cached.query_exists(null))
                return true;
        }
        
        message("Building persistent thumbnail for [%d] %s", id, cached.get_path());
        
        // load full-scale photo and convert to pixbuf
        Gdk.Pixbuf original;
        try {
            original = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("Error loading image %s: %s", file.get_path(), err.message);
            
            return false;
        }

        // scale according to cache's parameters
        Gdk.Pixbuf thumbnail = scale_pixbuf(file.get_path(), original, scale, interp);
        
        // save scaled image as JPEG
        try {
            if (thumbnail.save(cached.get_path(), "jpeg", "quality", jpegQuality) == false) {
                error("Unable to save thumbnail %s", cached.get_path());
                
                return false;
            }
        } catch (Error err) {
            error("Error saving thumbnail to %s: %s", cached.get_path(), err.message);
            
            return false;
        }
        
        return true;
    }
    
    public void remove(int id) {
        File cached = get_cached_file(id);
        
        message("Removing [%d] %s", id, cached.get_path());
        
        // remove from in-memory cache
        cacheMap.remove(id);
 
        // remove from disk
        try {
            if (cached.delete(null) == false) {
                error("Unable to delete cached thumb %s", cached.get_path());
            }
        } catch (Error err) {
            error("Error deleting cached thumb: %s", err.message);
        }
    }
    
    public Dimensions get_dimensions(int id) {
        File cached = get_cached_file(id);
        
        // for now, load the file and check its size ... more efficient way of doing this TBD
        Gdk.Pixbuf pixbuf;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(cached.get_path());
        } catch (Error err) {
            error("Error loading image for dimensions %s: %s", cached.get_path(), err.message);
            
            return Dimensions();
        }
        
        return Dimensions(pixbuf.get_width(), pixbuf.get_height());
    }

    private File get_cached_file(int id) {
        return cacheDir.get_child("thumb%08x.jpg".printf(id));
    }
}
