/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Photos {

class GifFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = { "gif" };
    private static string[] KNOWN_MIME_TYPES = { "image/gif" };

    private static GifFileFormatProperties instance = null;

    public static void init() {
        instance = new GifFileFormatProperties();
    }

    public static GifFileFormatProperties get_instance() {
        return instance;
    }

    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.PNG;
    }

    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_user_visible_name() {
        return _("GIF");
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

public class GifSniffer : GdkSniffer {
    private const uint8[] MAGIC_SEQUENCE = { (uint8)'G', (uint8)'I', (uint8)'F', (uint8)'8' };

    public GifSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    private static bool is_gif_file(File file) throws Error {
        FileInputStream instream = file.read(null);

        uint8[] file_lead_sequence = new uint8[MAGIC_SEQUENCE.length];

        instream.read(file_lead_sequence, null);

        return Posix.memcmp (file_lead_sequence, MAGIC_SEQUENCE, MAGIC_SEQUENCE.length) == 0;
    }

    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // Rely on GdkSniffer to detect corruption
        is_corrupted = false;

        if (!is_gif_file(file))
            return null;

        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);

        if (detected == null)
            return null;

        return (detected.file_format == PhotoFileFormat.GIF) ? detected : null;
    }
}

public class GifReader : GdkReader {
    public GifReader(string filepath) {
        base (filepath, PhotoFileFormat.PNG);
    }
}

public class GifMetadataWriter : PhotoFileMetadataWriter {
    public GifMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.GIF);
    }

    public override void write_metadata(PhotoMetadata metadata) throws Error {
        metadata.write_to_file(get_file());
    }
}

public class GifFileFormatDriver : PhotoFileFormatDriver {
    private static GifFileFormatDriver instance = null;

    public static void init() {
        instance = new GifFileFormatDriver();
        GifFileFormatProperties.init();
    }

    public static GifFileFormatDriver get_instance() {
        return instance;
    }

    public override PhotoFileFormatProperties get_properties() {
        return GifFileFormatProperties.get_instance();
    }

    public override PhotoFileReader create_reader(string filepath) {
        return new GifReader(filepath);
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
        return new GifMetadataWriter(filepath);
    }

    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new GifSniffer(file, options);
    }

    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
}

}
