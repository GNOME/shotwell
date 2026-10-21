/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Photos {

public class WebpFileFormatDriver : PhotoFileFormatDriver {
    private static WebpFileFormatDriver instance = null;

    public static void init() {
        instance = new WebpFileFormatDriver();
        WebpFileFormatProperties.init();
    }

    public static WebpFileFormatDriver get_instance() {
        return instance;
    }

    public override PhotoFileFormatProperties get_properties() {
        return WebpFileFormatProperties.get_instance();
    }

    public override PhotoFileReader create_reader(string filepath) {
        return new WebpReader(filepath);
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
        return new WebpWriter(filepath);
    }

    public override PhotoFileMetadataWriter? create_metadata_writer(string filepath) {
        return new WebpMetadataWriter(filepath);
    }

    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new WebpSniffer(file, options);
    }
}

private class WebpFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = {
        "webp"
    };

    private static string[] KNOWN_MIME_TYPES = {
        "image/webp"
    };

    private static WebpFileFormatProperties instance = null;

    public static void init() {
        instance = new WebpFileFormatProperties();
    }

    public static WebpFileFormatProperties get_instance() {
        return instance;
    }

    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.WEBP;
    }

    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_default_extension() {
        return "webp";
    }

    public override string get_user_visible_name() {
        return _("WebP");
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

private class WebpSniffer : GlycinSniffer {
    public WebpSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // Rely on GdkSniffer to detect corruption
        is_corrupted = false;
        
        if (!is_webp(file))
            return null;
        
        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);
        if (detected == null)
            return null;
        
        return (detected.file_format == PhotoFileFormat.WEBP) ? detected : null;
    }
}

private class WebpReader : GlycinReader {
    public WebpReader(string filepath) {
        base (filepath, PhotoFileFormat.WEBP);
    }
}

private class WebpMetadataWriter : PhotoFileMetadataWriter {
    public WebpMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.WEBP);
    }

    public override void write_metadata(PhotoMetadata metadata) throws Error {
        metadata.write_to_file(get_file());
    }
}

public bool is_webp(File file, Cancellable? cancellable = null) throws Error {
    var ins = file.read();

    uint8 buffer[12];
    try {
        ins.read(buffer, null);
        if (buffer[0] == 'R' && buffer[1] == 'I' && buffer[2] == 'F' && buffer[3] == 'F' &&
            buffer[8] == 'W' && buffer[9] == 'E' && buffer[10] == 'B' && buffer[11] == 'P')
            return true;
    } catch (Error error) {
        debug ("Failed to read from file %s: %s", file.get_path (), error.message);
    }

    return false;
}

public class WebpWriter : GlycinWriter {
    public WebpWriter(string filepath) {
        base (filepath, PhotoFileFormat.WEBP);
    }

    public override async void write_async(Gdk.Pixbuf pixbuf, Jpeg.Quality quality, int io_priority, Cancellable? cancellable) throws Error {
        prepare_creator(pixbuf);

        yield do_write_async(io_priority, cancellable);
    }

    public override void write(Gdk.Pixbuf pixbuf, Jpeg.Quality quality) throws Error {
        prepare_creator(pixbuf);

        do_write();
    }    
}

}