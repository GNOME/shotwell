/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

class AvifFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = { "avif" };
    private static string[] KNOWN_MIME_TYPES = { "image/avif" };

    private static AvifFileFormatProperties instance = null;

    public static void init() {
        instance = new AvifFileFormatProperties();
    }
    
    public static AvifFileFormatProperties get_instance() {
        return instance;
    }
    
    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.AVIF;
    }
    
    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_user_visible_name() {
        return _("AVIF");
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

public class AvifSniffer : GdkSniffer {
    private const uint8[] MAGIC_SEQUENCE = { 102, 116, 121, 112, 97, 118, 105, 102 };

    public AvifSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    private static bool is_avif_file(File file) throws Error {
        FileInputStream instream = file.read(null);

        // Read out first four bytes
        uint8[] unknown_start = new uint8[4];

        instream.read(unknown_start, null);

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
        
        if (!is_avif_file(file))
            return null;
        
        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);
        if (detected == null)
            return null;
        
        return (detected.file_format == PhotoFileFormat.AVIF) ? detected : null;
    }
}

public class AvifReader : GdkReader {
    public AvifReader(string filepath) {
        base (filepath, PhotoFileFormat.AVIF);
    }
}

public class AvifWriter : PhotoFileWriter {
    public AvifWriter(string filepath) {
        base (filepath, PhotoFileFormat.AVIF);
    }
    
    public override void write(Gdk.Pixbuf pixbuf, Jpeg.Quality quality) throws Error {
        pixbuf.save(get_filepath(), "avif", "quality", "90", null);
    }
}

public class AvifMetadataWriter : PhotoFileMetadataWriter {
    public AvifMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.AVIF);
    }
    
    public override void write_metadata(PhotoMetadata metadata) throws Error {
        metadata.write_to_file(get_file());
    }
}

public class AvifFileFormatDriver : PhotoFileFormatDriver {
    private static AvifFileFormatDriver instance = null;
    
    public static void init() {
        instance = new AvifFileFormatDriver();
        AvifFileFormatProperties.init();
    }
    
    public static AvifFileFormatDriver get_instance() {
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return AvifFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new AvifReader(filepath);
    }
    
    public override bool can_write_image() {
        return true;
    }
    
    public override bool can_write_metadata() {
        return true;
    }
    
    public override PhotoFileWriter? create_writer(string filepath) {
        return new AvifWriter(filepath);
    }
    
    public override PhotoFileMetadataWriter? create_metadata_writer(string filepath) {
        return new AvifMetadataWriter(filepath);
    }
    
    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new AvifSniffer(file, options);
    }
    
    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
}

