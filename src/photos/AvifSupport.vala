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
    public AvifSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // Rely on GdkSniffer to detect corruption
        is_corrupted = false;
        
        if (!is_supported_bmff_with_variants(file, {"avif", "avis"}))
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
        pixbuf.save(get_filepath(), "avif", "quality", quality.get_pct_text(), null);
    }
}

public class AvifMetadataWriter : PhotoFileMetadataWriter {
    public AvifMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.AVIF);
    }
    
    public override void write_metadata(PhotoMetadata metadata) throws Error {
        // TODO: Not yet implemented in gexiv2
        // metadata.write_to_file(get_file());
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
        try {
            var loader = new Gdk.PixbufLoader.with_type("avif");
            return loader.get_format().is_writable();
        } catch (Error err) {
            critical("Could not create aviv loader");
        }
        return true;
    }
    
    public override bool can_write_metadata() {
        return false;
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

