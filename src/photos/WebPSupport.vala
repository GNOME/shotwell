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
        return false;
    }

    public override bool can_write_metadata() {
        return true;
    }

    public override PhotoFileWriter? create_writer(string filepath) {
        return null;
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

private class WebpSniffer : PhotoFileSniffer {
    private DetectedPhotoInformation detected = null;

    public WebpSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
        detected = new DetectedPhotoInformation();
    }

    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        is_corrupted = false;

        if (!is_webp(file))
            return null;

         // valac chokes on the ternary operator here
        Checksum? md5_checksum = null;
        if (calc_md5)
            md5_checksum = new Checksum(ChecksumType.MD5);

        detected.metadata = new PhotoMetadata();
        try {
            detected.metadata.read_from_file(file);
        } catch (Error err) {
            debug("Failed to load meta-data from file: %s", err.message);
            // no metadata detected
            detected.metadata = null;
        }

        if (calc_md5 && detected.metadata != null) {
            detected.exif_md5 = detected.metadata.exif_hash();
            detected.thumbnail_md5 = detected.metadata.thumbnail_hash();
        }

        // if no MD5, don't read as much, as the needed info will probably be gleaned
        // in the first 8K to 16K
        uint8[] buffer = calc_md5 ? new uint8[64 * 1024] : new uint8[8 * 1024];
        size_t count = 0;

        // loop through until all conditions we're searching for are met
        FileInputStream fins = file.read(null);
        var ba = new ByteArray();
        for (;;) {
            size_t bytes_read = fins.read(buffer, null);
            if (bytes_read <= 0)
                break;

            ba.append(buffer[0:bytes_read]);

            count += bytes_read;

            if (calc_md5)
                md5_checksum.update(buffer, bytes_read);

            WebP.Data d = WebP.Data();
            d.bytes = ba.data;

            WebP.ParsingState state;
            var demux = new WebP.Demuxer.partial(d, out state);

            if (state == WebP.ParsingState.PARSE_ERROR) {
                is_corrupted = true;
                break;
            }

            if (state > WebP.ParsingState.PARSED_HEADER) {
                detected.file_format = PhotoFileFormat.WEBP;
                detected.format_name = "WebP";
                detected.channels = 4;
                detected.bits_per_channel = 8;
                detected.image_dim.width = (int) demux.get(WebP.FormatFeature.CANVAS_WIDTH);
                detected.image_dim.height = (int) demux.get(WebP.FormatFeature.CANVAS_HEIGHT);

                // if not searching for anything else, exit
                if (!calc_md5)
                    break;
            }
        }

        if (fins != null)
            fins.close(null);

        if (calc_md5)
            detected.md5 = md5_checksum.get_string();

        // We have never reached the header parsing state, but also didn't encounter any error
        if (detected.file_format != PhotoFileFormat.WEBP) {
            return null;
        }
        
        return detected;

    }
}

private class WebpReader : PhotoFileReader {
    public WebpReader(string filepath) {
        base (filepath, PhotoFileFormat.WEBP);
    }

    public override PhotoMetadata read_metadata() throws Error {
        PhotoMetadata metadata = new PhotoMetadata();
        metadata.read_from_file(get_file());

        return metadata;
    }

    public override Gdk.Pixbuf unscaled_read() throws Error {
        uint8[] buffer;

        FileUtils.get_data(this.get_filepath(), out buffer);
        var features = WebP.BitstreamFeatures();
        WebP.GetFeatures(buffer, out features);

        if (features.has_animation) {
            throw new IOError.INVALID_DATA("Animated WebP files are not yet supported");
        }
        
        int width, height;
        var pixdata = WebP.DecodeRGBA(buffer, out width, out height);
        if (pixdata == null) {
            throw new IOError.INVALID_DATA("Failed to decode WebP file");
        }
        pixdata.length = width * height * 4;

        return new Gdk.Pixbuf.from_data(pixdata, Gdk.Colorspace.RGB, true, 8, width, height, width * 4);
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

}
