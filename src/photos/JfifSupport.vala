/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class JfifFileFormatDriver : PhotoFileFormatDriver {
    private static JfifFileFormatDriver instance = null;

    public static void init() {
        instance = new JfifFileFormatDriver();
        JfifFileFormatProperties.init();
    }
    
    public static JfifFileFormatDriver get_instance() {
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return JfifFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new JfifReader(filepath);
    }
    
    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
    
    public override bool can_write_image() {
        return true;
    }
    
    public override bool can_write_metadata() {
        return true;
    }
    
    public override PhotoFileWriter? create_writer(string filepath) {
        return new JfifWriter(filepath);
    }
    
    public override PhotoFileMetadataWriter? create_metadata_writer(string filepath) {
        return new JfifMetadataWriter(filepath);
    }
    
    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new JfifSniffer(file, options);
    }
}

public class JfifFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = {
        "jpg", "jpeg", "jpe", "thm"
    };

    private static string[] KNOWN_MIME_TYPES = {
        "image/jpeg"
    };
        
    private static JfifFileFormatProperties instance = null;

    public static void init() {
        instance = new JfifFileFormatProperties();
    }
    
    public static JfifFileFormatProperties get_instance() {
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
    
    public override string get_default_mime_type() {
        return KNOWN_MIME_TYPES[0];
    }
    
    public override string[] get_mime_types() {
        return KNOWN_MIME_TYPES;
    }
}

public class JfifSniffer : GdkSniffer {
    public JfifSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }
    
    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        is_corrupted = false;
        if (!calc_md5) {
            return fast_sniff (out is_corrupted);
        } else {
            if (!Jpeg.is_jpeg(file)) {
                return null;
            }

            return base.sniff (out is_corrupted);

        }
    }

    private DetectedPhotoInformation? fast_sniff(out bool is_corrupted) throws Error {
        var detected = new DetectedPhotoInformation();

        // Rely on GdkSniffer to detect corruption
        is_corrupted = false;

        var fins = file.read(null);
        var dins = new DataInputStream(fins);
        dins.set_byte_order(DataStreamByteOrder.BIG_ENDIAN);

        var marker = Jpeg.Marker.INVALID;
        var length = Jpeg.read_marker_2(dins, out marker);

        if (marker != Jpeg.Marker.SOI) {
            return null;
        }

        length = Jpeg.read_marker_2(dins, out marker);
        while (marker != Jpeg.Marker.SOF && length > 0) {
            (dins as Seekable).seek(length, SeekType.CUR, null);
            length = Jpeg.read_marker_2(dins, out marker);
        }

        if (marker == SOF) {
            if (length < 6) {
                is_corrupted = true;
                return null;
            }

            // Skip precision
            dins.read_byte();

            // Next two 16 bytes are image dimensions
            uint16 height = dins.read_uint16();
            uint16 width = dins.read_uint16();

            detected.image_dim = Dimensions(width, height);
            detected.colorspace = Gdk.Colorspace.RGB;
            detected.channels = 3;
            detected.bits_per_channel = 8;
            detected.format_name = "jpeg";
            detected.file_format = PhotoFileFormat.from_pixbuf_name(detected.format_name);
        } else {
            is_corrupted = true;
        }

        return (detected.file_format == PhotoFileFormat.JFIF) ? detected : null;

    }
}

public class JfifReader : GdkReader {
    public JfifReader(string filepath) {
        base (filepath, PhotoFileFormat.JFIF);
    }
}

public class JfifWriter : PhotoFileWriter {
    public JfifWriter(string filepath) {
        base (filepath, PhotoFileFormat.JFIF);
    }
    
    public override void write(Gdk.Pixbuf pixbuf, Jpeg.Quality quality) throws Error {
        pixbuf.save(get_filepath(), "jpeg", "quality", quality.get_pct_text());
    }
}

public class JfifMetadataWriter : PhotoFileMetadataWriter {
    public JfifMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.JFIF);
    }
    
    public override void write_metadata(PhotoMetadata metadata) throws Error {
        metadata.write_to_file(get_file());
    }
}

namespace Jpeg {
    public const uint8 MARKER_PREFIX = 0xFF;
    
    public enum Marker {
        // Could also be 0xFF according to spec
        INVALID = 0x00,
        
        SOI = 0xD8,
        EOI = 0xD9,
        SOF = 0xC0,
        
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
        var fins = file.read(null);
        return is_jpeg_stream(fins);
    }

    public bool is_jpeg_stream(InputStream ins) throws Error {
        Marker marker;
        int segment_length = read_marker(ins, out marker);
        
        // for now, merely checking for SOI
        return (marker == Marker.SOI) && (segment_length == 0);
    }

    public bool is_jpeg_bytes(Bytes bytes) throws Error {
        var mins = new MemoryInputStream.from_bytes(bytes);

        return is_jpeg_stream(mins);
    }

    private int32 read_marker_2(DataInputStream dins, out Jpeg.Marker marker) throws Error {
        marker = Jpeg.Marker.INVALID;

        if (dins.read_byte() != Jpeg.MARKER_PREFIX)
            return -1;
        
        marker = (Jpeg.Marker) dins.read_byte();
        if ((marker == Jpeg.Marker.SOI) || (marker == Jpeg.Marker.EOI)) {
            // no length
            return -1;
        }
        
        uint16 length = dins.read_uint16();
        if (length < 2 && dins is Seekable) {
            debug("Invalid length %Xh at ofs %" + int64.FORMAT + "Xh", length,
                    (dins as Seekable).tell() - 2);
            
            return -1;
        }
        
        // account for two length bytes already read
        return length - 2;
    }

    private int read_marker(InputStream fins, out Jpeg.Marker marker) throws Error {
        DataInputStream dins = new DataInputStream(fins);
        dins.set_byte_order(DataStreamByteOrder.BIG_ENDIAN);

        return read_marker_2(dins, out marker);
    }
}

