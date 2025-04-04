/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

class PngFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = { "png" };
    private static string[] KNOWN_MIME_TYPES = { "image/png" };

    private static PngFileFormatProperties instance = null;

    public static void init() {
        instance = new PngFileFormatProperties();
    }
    
    public static PngFileFormatProperties get_instance() {
        return instance;
    }
    
    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.PNG;
    }
    
    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_user_visible_name() {
        return _("PNG");
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

public class PngSniffer : GdkSniffer {
    private const uint8[] MAGIC_SEQUENCE = { 137, 80, 78, 71, 13, 10, 26, 10 };

    public PngSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    private static bool is_png_file(File file) throws Error {
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
        
        if (!is_png_file(file))
            return null;
        
        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);
        if (detected == null)
            return null;
        
        return (detected.file_format == PhotoFileFormat.PNG) ? detected : null;
    }
}

public class PngReader : GdkReader {
    public PngReader(string filepath) {
        base (filepath, PhotoFileFormat.PNG);
    }
}

public class PngWriter : PhotoFileWriter {
    public PngWriter(string filepath) {
        base (filepath, PhotoFileFormat.PNG);
    }
    
    public override void write(Gdk.Pixbuf pixbuf, Jpeg.Quality quality) throws Error {
        pixbuf.save(get_filepath(), "png", "compression", "9", null);
    }
}

public class PngMetadataWriter : PhotoFileMetadataWriter {
    public PngMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.PNG);
    }
    
    public override void write_metadata(PhotoMetadata metadata) throws Error {
        metadata.write_to_file(get_file());
    }
}

public class PngFileFormatDriver : PhotoFileFormatDriver {
    private static PngFileFormatDriver instance = null;
    
    public static void init() {
        instance = new PngFileFormatDriver();
        PngFileFormatProperties.init();
    }
    
    public static PngFileFormatDriver get_instance() {
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return PngFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new PngReader(filepath);
    }
    
    public override bool can_write_image() {
        return true;
    }
    
    public override bool can_write_metadata() {
        return true;
    }
    
    public override PhotoFileWriter? create_writer(string filepath) {
        return new PngWriter(filepath);
    }
    
    public override PhotoFileMetadataWriter? create_metadata_writer(string filepath) {
        return new PngMetadataWriter(filepath);
    }
    
    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new PngSniffer(file, options);
    }
    
    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
}

