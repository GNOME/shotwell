
public class ThumbnailCache {
    public static ThumbnailCache big = null;
    
    public static void set_app_data_dir(File appDataDir) {
        big = new ThumbnailCache(appDataDir, 360);
    }
    
    private File cacheDir;
    private int scale;
    private Gdk.InterpType interp;
    private string jpegQuality;
    private Gee.HashMap<int, Gdk.Pixbuf> pixbufMap = new Gee.HashMap<int, Gdk.Pixbuf>(direct_hash, 
        direct_equal, direct_equal);
    
    private ThumbnailCache(File appDataDir, int scale, Gdk.InterpType interp = Gdk.InterpType.NEAREST,
        int jpegQuality = 90) {
        assert(scale != 0);
        assert((jpegQuality >= 0) && (jpegQuality <= 100));

        this.cacheDir = appDataDir.get_child("thumbs").get_child("thumbs%d".printf(scale));
        this.scale = scale;
        this.interp = interp;
        this.jpegQuality = "%d".printf(jpegQuality);
        
        try {
            if (this.cacheDir.query_exists(null) == false) {
                if (this.cacheDir.make_directory_with_parents(null) == false) {
                    error("Unable to create cache dir %s", this.cacheDir.get_path());
                }
            }
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    public Gdk.Pixbuf? fetch(int id) {
        Gdk.Pixbuf thumbnail = null;

        if (pixbufMap.contains(id)) {
            thumbnail = pixbufMap.get(id);
            if (thumbnail != null) {
                return thumbnail;
            }
        }

        File cached = get_cached_file(id);

        message("Loading from disk %d %s", id, cached.get_path());

        try {
            thumbnail = new Gdk.Pixbuf.from_file(cached.get_path());
            pixbufMap.set(id, thumbnail);
        } catch (Error err) {
            error("%s", err.message);
        }
        
        return thumbnail;
    }
    
    public bool import(int id, File file, bool force = false) {
        File cached = get_cached_file(id);
        
        message("Importing %d %s", id, cached.get_path());
        
        // if not forcing the cache operation, check if file exists before performing
        if (!force) {
            if (cached.query_exists(null))
                return true;
        }
        
        // load full-scale photo and convert to pixbuf
        Gdk.Pixbuf original;
        try {
            original = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("Error loading image %s: %s", file.get_path(), err.message);
            
            return false;
        }

        // scale according to cache's parameters
        Gdk.Pixbuf thumbnail = scale_pixbuf(file, original, scale, interp);
        
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
        
        message("Removing %d %s", id, cached.get_path());
 
        try {
            if (cached.delete(null) == false) {
                error("Unable to delete cached thumb %s", cached.get_path());
            }
        } catch (Error err) {
            error("Error deleting cached thumb: %s", err.message);
        }
    }
    
    private File get_cached_file(int id) {
        return cacheDir.get_child("thumb%08x.jpg".printf(id));
    }
}
