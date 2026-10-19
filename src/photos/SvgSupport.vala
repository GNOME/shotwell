/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

class SvgFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = { "svg", "svgz" };
    private static string[] KNOWN_MIME_TYPES = { "image/svg+xml", "image/svg+xml-compressed" };

    private static SvgFileFormatProperties instance = null;

    public static void init() {
        instance = new SvgFileFormatProperties();
    }

    public static SvgFileFormatProperties get_instance() {
        return instance;
    }

    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.SVG;
    }

    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_user_visible_name() {
        return _("SVG");
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

public class SvgSniffer : GlycinSniffer {
    private static string[] KNOWN_EXTENSIONS = { "svg", "svgz" };

    public SvgSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    private bool has_svg_extension() {
        string name, ext;
        disassemble_filename(file.get_basename(), out name, out ext);

        if (is_string_empty(ext))
            return false;

        return is_in_ci_array(ext, KNOWN_EXTENSIONS);
    }

    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // Rely on GlycinSniffer to detect corruption
        is_corrupted = false;

        if (!has_svg_extension())
            return null;

        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);
        if (detected == null)
            return null;

        return (detected.file_format == PhotoFileFormat.SVG) ? detected : null;
    }
}

public class SvgReader : GlycinReader {
    public SvgReader(string filepath) {
        base (filepath, PhotoFileFormat.SVG);
    }
}

public class SvgFileFormatDriver : PhotoFileFormatDriver {
    private static SvgFileFormatDriver instance = null;

    public static void init() {
        instance = new SvgFileFormatDriver();
        SvgFileFormatProperties.init();
    }

    public static SvgFileFormatDriver get_instance() {
        return instance;
    }

    public override PhotoFileFormatProperties get_properties() {
        return SvgFileFormatProperties.get_instance();
    }

    public override PhotoFileReader create_reader(string filepath) {
        return new SvgReader(filepath);
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
        return null;
    }

    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new SvgSniffer(file, options);
    }

    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
}
