/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

class HeifFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = { "heif", "heic", "hif" };
    private static string[] KNOWN_MIME_TYPES = { "image/heif" };

    private static HeifFileFormatProperties instance = null;

    public static void init() {
        instance = new HeifFileFormatProperties();
    }
    
    public static HeifFileFormatProperties get_instance() {
        return instance;
    }
    
    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.HEIF;
    }
    
    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_user_visible_name() {
        return _("HEIF");
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

public class HeifSniffer : GdkSniffer {
    private const string[] MAGIC_SEQUENCES = { "heic", "heix", "hevc", "heim", "heis", "hevm", "hevs", "mif1", "msf1"};

    public HeifSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // Rely on GdkSniffer to detect corruption
        is_corrupted = false;
        
        if (!is_supported_bmff_with_variants(file, MAGIC_SEQUENCES))
            return null;
        
        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);
        if (detected == null)
            return null;

        if (detected.file_format == PhotoFileFormat.AVIF)
            detected.file_format = PhotoFileFormat.HEIF;

        // Heif contains its own rotation information, so we need to ignore the EXIF rotation+
        if (detected.metadata != null) {
            detected.metadata.set_orientation(Orientation.TOP_LEFT);
        }

        return (detected.file_format == PhotoFileFormat.HEIF) ? detected : null;
    }

}

public class HeifReader : GdkReader {
    public HeifReader(string filepath) {
        base (filepath, PhotoFileFormat.HEIF);
    }

    public override PhotoMetadata read_metadata() throws Error {
        PhotoMetadata metadata = new PhotoMetadata();
        metadata.read_from_file(get_file());
        // Heif contains its own rotation information, so we need to ignore the EXIF rotation
        metadata.set_orientation(Orientation.TOP_LEFT);
        return metadata;
    }

}

public class HeifMetadataWriter : PhotoFileMetadataWriter {
    public HeifMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.HEIF);
    }
    
    public override void write_metadata(PhotoMetadata metadata) throws Error {
        metadata.write_to_file(get_file());
    }
}

public class HeifFileFormatDriver : PhotoFileFormatDriver {
    private static HeifFileFormatDriver instance = null;
    
    public static void init() {
        instance = new HeifFileFormatDriver();
        HeifFileFormatProperties.init();
    }
    
    public static HeifFileFormatDriver get_instance() {
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return HeifFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new HeifReader(filepath);
    }
    
    public override bool can_write_image() {
        return false;
    }
    
    public override bool can_write_metadata() {
        return false;
    }
    
    public override PhotoFileWriter? create_writer(string filepath) {
        return null;
    }
    
    public override PhotoFileMetadataWriter? create_metadata_writer(string filepath) {
        return new HeifMetadataWriter(filepath);
    }
    
    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new HeifSniffer(file, options);
    }
    
    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
}

