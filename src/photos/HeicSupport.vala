/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Photos {

public class HeicFileFormatDriver : PhotoFileFormatDriver {
    private static HeicFileFormatDriver instance = null;

    public static void init() {
        instance = new HeicFileFormatDriver();
        HeicFileFormatProperties.init();
    }

    public static HeicFileFormatDriver get_instance() {
        return instance;
    }

    public override PhotoFileFormatProperties get_properties() {
        return HeicFileFormatProperties.get_instance();
    }

    public override PhotoFileReader create_reader(string filepath) {
        return new HeicReader(filepath);
    }

    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
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
        return new HeicSniffer(file, options);
    }
}

private class HeicFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = {
        "heic", "heif"
    };

    private static string[] KNOWN_MIME_TYPES = {
        "image/heif", "image/heic"
    };

    private static HeicFileFormatProperties instance = null;

    public static void init() {
        instance = new HeicFileFormatProperties();
    }

    public static HeicFileFormatProperties get_instance() {
        return instance;
    }

    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.HEIC;
    }

    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }

    public override string get_default_extension() {
        return "heic";
    }

    public override string get_user_visible_name() {
        return _("HEIC");
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

private class HeicSniffer : PhotoFileSniffer {
    private DetectedPhotoInformation detected = null;

    public HeicSniffer(File file, PhotoFileSniffer.Options options) {
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
        //uint8[] buffer = calc_md5 ? new uint8[64 * 1024] : new uint8[8 * 1024];
        //size_t count = 0;

        // loop through until all conditions we're searching for are met
        FileInputStream fins = file.read(null);
        //var ba = new ByteArray();
        #if 0
        for (;;) {
            size_t bytes_read = fins.read(buffer, null);
            if (bytes_read <= 0)
                break;

            ba.append(buffer[0:bytes_read]);
            mins.add_data(buffer[0:bytes_read]);

            count += bytes_read;

            if (calc_md5)
                md5_checksum.update(buffer, bytes_read);

            d.bytes = ba.data;

            try {
                atom.read_atom();
            } catch (Error error) {
                is_corrupted = true;
                break;
            }

            if (state > WebP.ParsingState.PARSED_HEADER) {
                detected.file_format = PhotoFileFormat.HEIC;
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
        #endif

        if (fins != null)
            fins.close(null);

        if (calc_md5)
            detected.md5 = md5_checksum.get_string();

        return detected;
    }
}

private class HeicReader : PhotoFileReader {
    public HeicReader(string filepath) {
        base (filepath, PhotoFileFormat.HEIC);
    }

    public override PhotoMetadata read_metadata() throws Error {
        PhotoMetadata metadata = new PhotoMetadata();
        metadata.read_from_file(get_file());

        return metadata;
    }

    public override Gdk.Pixbuf unscaled_read() throws Error {
        uint8[] buffer;

        FileUtils.get_data(this.get_filepath(), out buffer);
        var handle = new Heif.Context();
        var result = handle.read_from_memory_without_copy (buffer);
        if (result.code != Heif.Error.OK) {
            throw new PhotoFormatError.DECODE_ERROR(result.message);
        }

        unowned Heif.ImageHandle hdl;
        result = handle.get_primary_image_handle(out hdl);
        if (result.code != Heif.Error.OK) {
            throw new PhotoFormatError.DECODE_ERROR(result.message);
        }

        unowned Heif.Image image;
        result = hdl.decode_image(out image, Heif.Colorspace.RGB, Heif.Chroma.INTERLEAVED_RGBA);
        if (result.code != Heif.Error.OK) {
            throw new PhotoFormatError.DECODE_ERROR(result.message);
        }

        var width = image.get_width(Heif.Channel.INTERLEAVED);
        var height = image.get_height(Heif.Channel.INTERLEAVED);

        int stride;
        var data = image.get_plane_readonly(Heif.Channel.INTERLEAVED, out stride);

        // TODO: Avoid copy by fixing the issue with libheif context not being ref-counted
        data.length = height * stride;
        var bytes = new Bytes(data);
        var pixbuf = new Gdk.Pixbuf.from_bytes(bytes, Gdk.Colorspace.RGB, true, 8, width, height, stride);

        return pixbuf;
    }
}

public bool is_heic(File file, Cancellable? cancellable = null) throws Error {
    var ins = file.read();

    uint8 buffer[12];
    try {
        ins.read(buffer, null);

        if (buffer[4] != 'f' ||
            buffer[5] != 't' ||
            buffer[6] != 'y' ||
            buffer[7] != 'p')
            return false;

        if (buffer.length >= 12) {
            var brand = "%c%c%c%c".printf(buffer[8], buffer[9], buffer[10], buffer[11]);

            if (brand == "heic")
                return true;
            else if (brand == "mif1")
                return true;

            return false;
        }

        return false;
    } catch (Error error) {
        debug ("Failed to read from file %s: %s", file.get_path (), error.message);
    }

    return false;
}

}
