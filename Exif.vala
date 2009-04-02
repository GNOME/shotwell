
namespace Exif {
    namespace Orientation {
        public static const int TOP_LEFT = 1;
        public static const int TOP_RIGHT = 2;
        public static const int BOTTOM_RIGHT = 3;
        public static const int BOTTOM_LEFT = 4;
        public static const int LEFT_TOP = 5;
        public static const int RIGHT_TOP = 6;
        public static const int RIGHT_BOTTOM = 7;
        public static const int LEFT_BOTTOM = 8;
    }
}

public class PhotoExif {
    private File file;
    private Exif.Data exifData = null;
    
    public PhotoExif(File file) {
        this.file = file;
    }
    
    public int get_orientation() {
        update();
        
        Exif.Entry orientation = find_entry(Exif.Ifd.ZERO, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (orientation == null)
            return Exif.Orientation.TOP_LEFT;
        
        return Exif.Convert.get_short(orientation.data, exifData.get_byte_order());
    }
    
    public bool get_dimensions(out Dimensions dim) {
        update();
        
        Exif.Entry width = find_entry(Exif.Ifd.EXIF, Exif.Tag.PIXEL_X_DIMENSION, Exif.Format.SHORT);
        Exif.Entry height = find_entry(Exif.Ifd.EXIF, Exif.Tag.PIXEL_Y_DIMENSION, Exif.Format.SHORT);
        if ((width == null) || (height == null))
            return false;
        
        dim.width = Exif.Convert.get_short(width.data, exifData.get_byte_order());
        dim.height = Exif.Convert.get_short(height.data, exifData.get_byte_order());
        
        return true;
    }
    
    public string? get_datetime() {
        update();
        
        Exif.Entry datetime = find_entry(Exif.Ifd.EXIF, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);
        if (datetime == null)
            return null;
        
        return datetime.get_value();
    }
    
    private void update() {
        // TODO: Update internal data structures if file changes
        if (exifData != null)
            return;
        
        debug("Loading EXIF from %s", file.get_path());
        
        exifData = Exif.Data.new_from_file(file.get_path());
        // TODO: Better error handling
        assert(exifData != null);
        
        // fix now, all at once
        exifData.fix();
    }
    
    private Exif.Entry? find_entry(Exif.Ifd ifd, Exif.Tag tag, Exif.Format format) {
        assert(exifData != null);
        
        Exif.Content content = exifData.ifd[ifd];
        assert(content != null);
        
        Exif.Entry entry = content.get_entry(tag);
        if (entry == null)
            return null;
        
        assert(entry.format == format);
        if ((format != Exif.Format.ASCII) && (format != Exif.Format.UNDEFINED))
            assert(entry.size == format.get_size());
        
        return entry;
    }
}

