/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class JfifFileFormatDriver : PhotoFileFormatDriver {
    private static JfifFileFormatDriver instance = null;
    
    public static JfifFileFormatDriver get_instance() {
        lock (instance) {
            if (instance == null)
                instance = new JfifFileFormatDriver();
        }
        
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return JfifFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new JfifReader(filepath);
    }
    
    public override bool can_write() {
        return true;
    }
    
    public override PhotoFileWriter? create_writer(string filepath) {
        return new JfifWriter(filepath);
    }
    
    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new JfifSniffer(file, options);
    }
}

public class JfifFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = {
        "jpg", "jpeg", "jpe"
    };
    
    private static JfifFileFormatProperties instance = null;
    
    public static JfifFileFormatProperties get_instance() {
        lock (instance) {
            if (instance == null)
                instance = new JfifFileFormatProperties();
        }
        
        return instance;
    }
    
    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.JFIF;
    }
    
    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }
    
    public override string get_default_extension() {
        return "jpg";
    }

    public override string get_user_visible_name() {
        return _("JPEG");
    }

    public override string[] get_known_extensions() {
        return KNOWN_EXTENSIONS;
    }
}

public class JfifSniffer : GdkSniffer {
    public JfifSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }
    
    public override DetectedPhotoInformation? sniff() throws Error {
        if (!Jpeg.is_jpeg(file))
            return null;
        
        DetectedPhotoInformation? detected = base.sniff();
        if (detected == null)
            return null;
        
        return (detected.file_format == PhotoFileFormat.JFIF) ? detected : null;
    }
}

public class JfifReader : GdkReader {
    public JfifReader(string filepath) {
        base (filepath, PhotoFileFormat.JFIF, Exif.DataType.COMPRESSED);
    }
    
    public override Exif.Data? read_exif() throws Error {
        PhotoExif photo_exif = new PhotoExif(get_file());
        try {
            photo_exif.load();
        } catch (Error err) {
            if (err is ExifError.FILE_FORMAT)
                return null;
            
            throw err;
        }
        
        return photo_exif.get_exif();
    }
    
    public override Gdk.Pixbuf? read_thumbnail() throws Error {
        Exif.Data? exif = read_exif();
        
        return (exif != null) ? Exif.get_thumbnail_pixbuf(exif) : null;
    }
}

public class JfifWriter : PhotoFileWriter {
    public JfifWriter(string filepath) {
        base (filepath, PhotoFileFormat.JFIF);
    }
    
    public override Exif.Data new_exif() {
        return (new PhotoExif(get_file())).get_exif();
    }
    
    public override void write_exif(Exif.Data exif) throws Error {
        PhotoExif photo_exif = new PhotoExif(get_file());
        photo_exif.set_exif(exif);
        photo_exif.commit();
    }
    
    public override void write(Gdk.Pixbuf pixbuf, Jpeg.Quality quality) throws Error {
        pixbuf.save(get_filepath(), "jpeg", "quality", quality.get_pct_text());
    }
}

namespace Jpeg {
    public const uint8 MARKER_PREFIX = 0xFF;
    
    public enum Marker {
        SOI = 0xD8,
        EOI = 0xD9,
        
        APP0 = 0xE0,
        APP1 = 0xE1;
        
        public uint8 get_byte() {
            return (uint8) this;
        }
    }
    
    public enum Quality {
        LOW = 50,
        MEDIUM = 75,
        HIGH = 90,
        MAXIMUM = 100;
        
        public int get_pct() {
            return (int) this;
        }
        
        public string get_pct_text() {
            return "%d".printf((int) this);
        }
        
        public static Quality[] get_all() {
            return { LOW, MEDIUM, HIGH, MAXIMUM };
        }
        
        public string? to_string() {
            switch (this) {
                case LOW:
                    return _("Low (%d%%)").printf((int) this);
                
                case MEDIUM:
                    return _("Medium (%d%%)").printf((int) this);
                
                case HIGH:
                    return _("High (%d%%)").printf((int) this);
                    
                case MAXIMUM:
                    return _("Maximum (%d%%)").printf((int) this);
            }
            
            warn_if_reached();
            
            return null;
        }
    }
    
    public bool is_jpeg(File file) throws Error {
        FileInputStream fins = file.read(null);
        
        Marker marker;
        int segment_length = read_marker(fins, out marker);
        
        // for now, merely checking for SOI
        return (marker == Marker.SOI) && (segment_length == 0);
    }

    private int read_marker(FileInputStream fins, out Jpeg.Marker marker) throws Error {
        uint8 byte = 0;
        uint16 length = 0;
        size_t bytes_read;

        fins.read_all(&byte, 1, out bytes_read, null);
        if (byte != Jpeg.MARKER_PREFIX)
            return -1;
        
        fins.read_all(&byte, 1, out bytes_read, null);
        marker = (Jpeg.Marker) byte;
        if ((marker == Jpeg.Marker.SOI) || (marker == Jpeg.Marker.EOI)) {
            // no length
            return 0;
        }
        
        fins.read_all(&length, 2, out bytes_read, null);
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
        
        uint16 host = (uint16) length.clamp(0, uint16.MAX);
        uint16 motorola = (uint16) host.to_big_endian().clamp(0, uint16.MAX);

        fouts.write_all(&motorola, 2, out written, null);
    }
}

