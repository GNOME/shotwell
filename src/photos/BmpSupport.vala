/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Photos {

class BmpFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = { "bmp", "dib" };
    private static string[] KNOWN_MIME_TYPES = { GPhoto.MIME.BMP };

    private static BmpFileFormatProperties instance = null;

    public static void init() {
        instance = new BmpFileFormatProperties();
    }
    
    public static BmpFileFormatProperties get_instance() {
        return instance;
    }
    
    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.BMP;
    }
    
    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_user_visible_name() {
        return _("BMP");
    }

    public override string get_default_extension() {
        return KNOWN_EXTENSIONS[0];
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

public class BmpSniffer : GdkSniffer {
    private const uint8[] MAGIC_SEQUENCE = { 0x42, 0x4D };

    public BmpSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    private static bool is_bmp_file(File file) throws Error {
        FileInputStream instream = file.read(null);

        uint8[] file_lead_sequence = new uint8[MAGIC_SEQUENCE.length];

        instream.read(file_lead_sequence, null);

        for (int i = 0; i < MAGIC_SEQUENCE.length; i++) {
            if (file_lead_sequence[i] != MAGIC_SEQUENCE[i])
                return false;
        }

        return true;
    }

    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // Rely on GdkSniffer to detect corruption
        is_corrupted = false;
        
        if (!is_bmp_file(file))
            return null;
        
        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);
        if (detected == null)
            return null;
        
        return (detected.file_format == PhotoFileFormat.BMP) ? detected : null;
    }
}

public class BmpReader : GdkReader {
    public BmpReader(string filepath) {
        base (filepath, PhotoFileFormat.BMP);
    }
}

public class BmpWriter : PhotoFileWriter {
    public BmpWriter(string filepath) {
        base (filepath, PhotoFileFormat.BMP);
    }
    
    public override void write(Gdk.Pixbuf pixbuf, Jpeg.Quality quality) throws Error {
        pixbuf.save(get_filepath(), "bmp", null);
    }
}

public class BmpMetadataWriter : PhotoFileMetadataWriter {
    public BmpMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.BMP);
    }
    
    public override void write_metadata(PhotoMetadata metadata) throws Error {
        // Metadata writing isn't supported for .BMPs, so this is a no-op. 
    }
}
             
public class BmpFileFormatDriver : PhotoFileFormatDriver {
    private static BmpFileFormatDriver instance = null;

    public static void init() {
        instance = new BmpFileFormatDriver();
        BmpFileFormatProperties.init();
    }
    
    public static BmpFileFormatDriver get_instance() {
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return BmpFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new BmpReader(filepath);
    }
    
    public override bool can_write_image() {
        return true;
    }
    
    public override bool can_write_metadata() {
        return false;
    }
    
    public override PhotoFileWriter? create_writer(string filepath) {
        return new BmpWriter(filepath);
    }
    
    public override PhotoFileMetadataWriter? create_metadata_writer(string filepath) {
        return new BmpMetadataWriter(filepath);
    }
    
    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new BmpSniffer(file, options);
    }
    
    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
}

}
