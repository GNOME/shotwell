
namespace Exif {
    public enum Orientation {
        TOP_LEFT = 1,
        TOP_RIGHT = 2,
        BOTTOM_RIGHT = 3,
        BOTTOM_LEFT = 4,
        LEFT_TOP = 5,
        RIGHT_TOP = 6,
        RIGHT_BOTTOM = 7,
        LEFT_BOTTOM = 8;
        
        public string get_description() {
            switch(this) {
                case TOP_LEFT:
                    return "top-left";
                    
                case TOP_RIGHT:
                    return "top-right";
                    
                case BOTTOM_RIGHT:
                    return "bottom-right";
                    
                case BOTTOM_LEFT:
                    return "bottom-left";
                    
                case LEFT_TOP:
                    return "left-top";
                    
                case RIGHT_TOP:
                    return "right-top";
                    
                case RIGHT_BOTTOM:
                    return "right-bottom";
                    
                case LEFT_BOTTOM:
                    return "left-bottom";
                    
                default:
                    return "unknown orientation %d".printf((int) this);
            }
        }
        
        public Orientation rotate_clockwise() {
            switch(this) {
                case TOP_LEFT:
                    return RIGHT_TOP;
                    
                case TOP_RIGHT:
                    return RIGHT_BOTTOM;
                    
                case BOTTOM_RIGHT:
                    return LEFT_BOTTOM;
                    
                case BOTTOM_LEFT:
                    return LEFT_TOP;
                    
                case LEFT_TOP:
                    return TOP_RIGHT;
                    
                case RIGHT_TOP:
                    return BOTTOM_RIGHT;
                    
                case RIGHT_BOTTOM:
                    return BOTTOM_LEFT;
                    
                case LEFT_BOTTOM:
                    return TOP_LEFT;
                    
                default: {
                    error("rotate_clockwise: %d", this);
                    
                    return this;
                }
            }
        }
        
        public Orientation rotate_counterclockwise() {
            switch(this) {
                case TOP_LEFT:
                    return LEFT_BOTTOM;
                    
                case TOP_RIGHT:
                    return LEFT_TOP;
                    
                case BOTTOM_RIGHT:
                    return RIGHT_TOP;
                    
                case BOTTOM_LEFT:
                    return RIGHT_BOTTOM;
                    
                case LEFT_TOP:
                    return BOTTOM_LEFT;
                    
                case RIGHT_TOP:
                    return TOP_LEFT;
                    
                case RIGHT_BOTTOM:
                    return TOP_RIGHT;
                    
                case LEFT_BOTTOM:
                    return BOTTOM_RIGHT;
                    
                default: {
                    error("rotate_counterclockwise: %d", this);
                    
                    return this;
                }
            }
        }
        
        public Orientation flip_top_to_bottom() {
            switch(this) {
                case TOP_LEFT:
                    return BOTTOM_LEFT;
                    
                case TOP_RIGHT:
                    return BOTTOM_RIGHT;
                    
                case BOTTOM_RIGHT:
                    return TOP_RIGHT;
                    
                case BOTTOM_LEFT:
                    return TOP_LEFT;
                    
                case LEFT_TOP:
                    return RIGHT_TOP;
                    
                case RIGHT_TOP:
                    return LEFT_TOP;
                    
                case RIGHT_BOTTOM:
                    return LEFT_BOTTOM;
                    
                case LEFT_BOTTOM:
                    return RIGHT_BOTTOM;
                    
                default: {
                    error("flip_top_to_bottom: %d", this);
                    
                    return this;
                }
            }
        }
        
        public Orientation flip_left_to_right() {
            switch(this) {
                case TOP_LEFT:
                    return TOP_RIGHT;
                    
                case TOP_RIGHT:
                    return TOP_LEFT;
                    
                case BOTTOM_RIGHT:
                    return BOTTOM_LEFT;
                    
                case BOTTOM_LEFT:
                    return BOTTOM_RIGHT;
                    
                case LEFT_TOP:
                    return RIGHT_TOP;
                    
                case RIGHT_TOP:
                    return LEFT_TOP;
                    
                case RIGHT_BOTTOM:
                    return LEFT_BOTTOM;
                    
                case LEFT_BOTTOM:
                    return RIGHT_BOTTOM;
                    
                default: {
                    error("flip_left_to_right: %d", this);
                    
                    return this;
                }
            }
        }
    }

    public static const int ORIENTATION_MIN = 1;
    public static const int ORIENTATION_MAX = 8;
}

namespace Jpeg {
    public static const uint8 MARKER_PREFIX = 0xFF;
    
    public enum Marker {
        SOI = 0xD8,
        EOI = 0xD9,
        
        APP0 = 0xE0,
        APP1 = 0xE1;
        
        public uint8 get_byte() {
            return (uint8) this;
        }
    }
}

public errordomain ExifError {
    FILE_FORMAT
}

extern void free(void *ptr);
    
public class PhotoExif {
    private File file;
    private Exif.Data exifData = null;
    
    public PhotoExif(File file) {
        this.file = file;
    }
    
    public Exif.Orientation get_orientation() {
        update();
        
        Exif.Entry entry = find_entry(Exif.Ifd.ZERO, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry == null)
            return Exif.Orientation.TOP_LEFT;
        
        int o = Exif.Convert.get_short(entry.data, exifData.get_byte_order());
        assert(o >= Exif.ORIENTATION_MIN);
        assert(o <= Exif.ORIENTATION_MAX);
        
        return (Exif.Orientation) o;
    }
    
    public void set_orientation(Exif.Orientation orientation) {
        update();
        
        Exif.Entry entry = find_first_entry(Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry == null) {
            // TODO: Need a fall-back here
            error("Unable to set orientation: no entry found");
        }
        
        Exif.Convert.set_short(entry.data, exifData.get_byte_order(), orientation);
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
    
    private Exif.Entry? find_first_entry(Exif.Tag tag, Exif.Format format) {
        assert(exifData != null);
        
        for (int ctr = 0; ctr < (int) Exif.Ifd.COUNT; ctr++) {
            Exif.Content content = exifData.ifd[ctr];
            assert(content != null);
            
            Exif.Entry entry = content.get_entry(tag);
            if (entry == null)
                continue;
            
            assert(entry.format == format);
            if ((format != Exif.Format.ASCII) && (format != Exif.Format.UNDEFINED))
                assert(entry.size == format.get_size());
            
            return entry;
        }
        
        return null;
    }
    
    public void commit() throws Error {
        if (exifData == null)
            return;
        
        FileInputStream fins = file.read(null);
        
        Jpeg.Marker marker;
        int segmentLength;

        // first marker is always SOI
        segmentLength = read_marker(fins, out marker);
        if ((marker != Jpeg.Marker.SOI) || (segmentLength != 0))
            throw new ExifError.FILE_FORMAT("SOI not found in %s".printf(file.get_path()));
        
        // for EXIF, next marker is always APP1
        segmentLength = read_marker(fins, out marker);
        if (marker != Jpeg.Marker.APP1)
            throw new ExifError.FILE_FORMAT("EXIF APP1 not found in %s".printf(file.get_path()));
        if (segmentLength <= 0)
            throw new ExifError.FILE_FORMAT("EXIF APP1 length of %d".printf(segmentLength));
            
        // flatten exif to buffer
        uchar *flattened = null;
        int flattenedSize = 0;
        exifData.save_data(&flattened, &flattenedSize);
        assert(flattened != null);
        assert(flattenedSize > 0);

        try {
            /*
            if (flattenedSize == segmentLength) {
                // the new EXIF data is exactly the same size as the data in the file, so simply
                // overwrite

                debug("Writing EXIF in-place of %d bytes to %s", flattenedSize, file.get_path());
                
                // close for reading
                fins.close(null);
                fins = null;
                
                // open for writing
                FileOutputStream fouts = file.replace(null, false, FileCreateFlags.PRIVATE, null);
                size_t bytesWritten = 0;
                
                // seeking with a replace() file destroys what's it seeks past (??), so just
                // writing since it's all of 6 bytes
                // Marker:SOI and Marker:APP1 and length (none change)
                write_marker(fouts, Jpeg.Marker.SOI, 0);
                write_marker(fouts, Jpeg.Marker.APP1, flattenedSize);
                fouts.write_all(flattened, flattenedSize, out bytesWritten, null);
                
                fouts.close(null);
            } else */ {
                // create a new photo file with the updated EXIF and move it on top of the old one

                // skip past APP1
                fins.skip(segmentLength, null);

                File temp = null;
                FileOutputStream fouts = create_temp(file, out temp);
                size_t bytesWritten = 0;
                
                debug("Building new file at %s with %d bytes EXIF, overwriting %s", temp.get_path(),
                    flattenedSize, file.get_path());

                // write SOI
                write_marker(fouts, Jpeg.Marker.SOI, 0);
                
                // write APP1 with EXIF data
                write_marker(fouts, Jpeg.Marker.APP1, flattenedSize);
                fouts.write_all(flattened, flattenedSize, out bytesWritten, null);
                
                // copy remainder of file into new file
                uint8[] copyBuffer = new uint8[64 * 1024];
                for(;;) {
                    ssize_t bytesRead = fins.read(copyBuffer, copyBuffer.length, null);
                    if (bytesRead == 0)
                        break;
                        
                    assert(bytesRead > 0);

                    fouts.write_all(copyBuffer, bytesRead, out bytesWritten, null);
                }
                
                // close both for move
                fouts.close(null);
                fins.close(null);
                
                temp.move(file, FileCopyFlags.OVERWRITE, null, null);
            }
        } finally {
            free(flattened);
        }
    }

    private int read_marker(FileInputStream fins, out Jpeg.Marker marker) throws Error {
        uint8 byte = 0;
        uint16 length = 0;
        size_t bytesRead;

        fins.read_all(&byte, 1, out bytesRead, null);
        if (byte != Jpeg.MARKER_PREFIX)
            return -1;
        
        fins.read_all(&byte, 1, out bytesRead, null);
        marker = (Jpeg.Marker) byte;
        if ((marker == Jpeg.Marker.SOI) || (marker == Jpeg.Marker.EOI)) {
            // no length
            return 0;
        }
        
        fins.read_all(&length, 2, out bytesRead, null);
        length = uint16.from_big_endian(length);
        if (length < 2) {
            debug("Invalid length %Xh at ofs %llXh", length, fins.tell() - 2);
            
            return -1;
        }
        
        // account for two length bytes already read
        return length - 2;
    }
    
    // this writes the marker and a length (if positive)
    private void write_marker(FileOutputStream fouts, Jpeg.Marker marker, int length) throws Error {
        // this is required to compile
        uint8 prefix = Jpeg.MARKER_PREFIX;
        uint8 byte = marker.get_byte();
        
        size_t written;
        fouts.write_all(&prefix, 1, out written, null);
        fouts.write_all(&byte, 1, out written, null);

        if (length <= 0)
            return;

        // +2 to account for length bytes
        length += 2;
        
        uint16 host = (uint16) length;
        uint16 motorola = (uint16) host.to_big_endian();

        fouts.write_all(&motorola, 2, out written, null);
    }

    private FileOutputStream? create_temp(File original, out File temp) throws Error {
        File parent = original.get_parent();
        assert(parent != null);
        
        for (int ctr = 0; ctr < int.MAX; ctr++) {
            File t = parent.get_child("shotwell.%08X.tmp".printf(ctr));
            FileOutputStream fouts = t.create(FileCreateFlags.PRIVATE, null);
            if (fouts != null) {
                temp = t;
                
                return fouts;
            }
        }
        
        return null;
    }
}

