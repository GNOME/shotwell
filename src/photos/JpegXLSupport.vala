/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

class JpegXLFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = { "jxl", "jpegxl" };
    private static string[] KNOWN_MIME_TYPES = { "image/jxl" };

    private static JpegXLFileFormatProperties instance = null;

    public static void init() {
        instance = new JpegXLFileFormatProperties();
    }
    
    public static JpegXLFileFormatProperties get_instance() {
        return instance;
    }
    
    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.JPEGXL;
    }
    
    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_user_visible_name() {
        return _("JPEGXL");
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

public class JpegXLSniffer : GdkSniffer {
    // See https://github.com/ImageMagick/jpeg-xl/blob/main/doc/format_overview.md#file-format
    private const uint8[] CODESTREAM_MAGIC_SEQUENCE = { 0xff, 0x0a };
    private const uint8[] BMFF_MAGIC_SEQUENCE = {0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A};


    public JpegXLSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    private static bool is_jpegxl_file(File file) throws Error {
        FileInputStream instream = file.read(null);

        // Read out first four bytes
        uint8[] file_lead_sequence = new uint8[BMFF_MAGIC_SEQUENCE.length];

        var size = instream.read(file_lead_sequence, null);

        return size == BMFF_MAGIC_SEQUENCE.length && (Memory.cmp(CODESTREAM_MAGIC_SEQUENCE, file_lead_sequence, CODESTREAM_MAGIC_SEQUENCE.length) == 0 ||
                Memory.cmp(BMFF_MAGIC_SEQUENCE, file_lead_sequence, BMFF_MAGIC_SEQUENCE.length) == 0);

    }

    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // Rely on GdkSniffer to detect corruption
        is_corrupted = false;
        
        if (!is_jpegxl_file(file))
            return null;
        
        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);
        if (detected == null)
            return null;

        return (detected.file_format == PhotoFileFormat.JPEGXL) ? detected : null;
    }

}

public class JpegXLReader : GdkReader {
    public JpegXLReader(string filepath) {
        base (filepath, PhotoFileFormat.JPEGXL);
    }
}

public class JpegXLMetadataWriter : PhotoFileMetadataWriter {
    public JpegXLMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.JPEGXL);
    }
    
    public override void write_metadata(PhotoMetadata metadata) throws Error {
        metadata.write_to_file(get_file());
    }
}

public class JpegXLFileFormatDriver : PhotoFileFormatDriver {
    private static JpegXLFileFormatDriver instance = null;
    
    public static void init() {
        instance = new JpegXLFileFormatDriver();
        JpegXLFileFormatProperties.init();
    }
    
    public static JpegXLFileFormatDriver get_instance() {
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return JpegXLFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new JpegXLReader(filepath);
    }
    
    public override bool can_write_image() {
        return false;
    }
    
    public override bool can_write_metadata() {
        return true;
    }
    
    public override PhotoFileWriter? create_writer(string filepath) {
        return null;
    }
    
    public override PhotoFileMetadataWriter? create_metadata_writer(string filepath) {
        return new JpegXLMetadataWriter(filepath);
    }
    
    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new JpegXLSniffer(file, options);
    }
    
    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
}

