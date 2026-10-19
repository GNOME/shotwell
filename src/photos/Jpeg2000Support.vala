/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

class Jpeg2000FileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = { "jp2", "jpx", "j2k", "jpc", "jpf" };
    private static string[] KNOWN_MIME_TYPES = { "image/jp2", "image/jpx", "image/x-jp2-codestream" };

    private static Jpeg2000FileFormatProperties instance = null;

    public static void init() {
        instance = new Jpeg2000FileFormatProperties();
    }

    public static Jpeg2000FileFormatProperties get_instance() {
        return instance;
    }

    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.JPEG2000;
    }

    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_user_visible_name() {
        return _("JPEG 2000");
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

public class Jpeg2000Sniffer : GlycinSniffer {
    // JP2 signature box, as defined by ISO/IEC 15444-1, followed by the file type box.
    private const uint8[] JP2_SIGNATURE = {
        0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A
    };

    // Raw JPEG 2000 codestream (J2K / JPC) starts with SOC followed by SIZ.
    private const uint8[] CODESTREAM_MAGIC_SEQUENCE = { 0xFF, 0x4F, 0xFF, 0x51 };

    // File type box brands belonging to the JPEG 2000 family.
    private const string[] JP2_BRANDS = { "jp2 ", "jpx ", "jpm ", "jph ", "j2k ", "jpc " };

    public Jpeg2000Sniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    private static bool is_jpeg2000_file(File file) throws Error {
        FileInputStream instream = file.read(null);

        // JP2 signature box (12 bytes) + file type box header (8 bytes) + major brand (4 bytes).
        uint8[] buffer = new uint8[24];

        if (instream.read(buffer, null) < CODESTREAM_MAGIC_SEQUENCE.length)
            return false;

        // Raw codestream (J2K / JPC)
        if (Memory.cmp(CODESTREAM_MAGIC_SEQUENCE, buffer, CODESTREAM_MAGIC_SEQUENCE.length) == 0)
            return true;

        // JP2/JPX family: signature box followed by a file type ("ftyp") box
        if (buffer.length < 24)
            return false;

        if (Memory.cmp(JP2_SIGNATURE, buffer, JP2_SIGNATURE.length) != 0)
            return false;

        if (Memory.cmp("ftyp".data, buffer[16:20], 4) != 0)
            return false;

        uint8[] brand_bytes = buffer[20:24];
        brand_bytes += '\0';
        string brand = (string)brand_bytes;

        foreach (string known in JP2_BRANDS) {
            if (brand == known)
                return true;
        }

        return false;
    }

    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // Rely on GlycinSniffer to detect corruption
        is_corrupted = false;

        if (!is_jpeg2000_file(file))
            return null;

        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);
        if (detected == null)
            return null;

        return (detected.file_format == PhotoFileFormat.JPEG2000) ? detected : null;
    }
}

public class Jpeg2000Reader : GlycinReader {
    public Jpeg2000Reader(string filepath) {
        base (filepath, PhotoFileFormat.JPEG2000);
    }
}

public class Jpeg2000MetadataWriter : PhotoFileMetadataWriter {
    public Jpeg2000MetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.JPEG2000);
    }

    public override void write_metadata(PhotoMetadata metadata) throws Error {
        metadata.write_to_file(get_file());
    }
}

public class Jpeg2000FileFormatDriver : PhotoFileFormatDriver {
    private static Jpeg2000FileFormatDriver instance = null;

    public static void init() {
        instance = new Jpeg2000FileFormatDriver();
        Jpeg2000FileFormatProperties.init();
    }

    public static Jpeg2000FileFormatDriver get_instance() {
        return instance;
    }

    public override PhotoFileFormatProperties get_properties() {
        return Jpeg2000FileFormatProperties.get_instance();
    }

    public override PhotoFileReader create_reader(string filepath) {
        return new Jpeg2000Reader(filepath);
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
        return new Jpeg2000MetadataWriter(filepath);
    }

    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new Jpeg2000Sniffer(file, options);
    }

    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
}
