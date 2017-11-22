/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Photos {

public class TiffFileFormatDriver : PhotoFileFormatDriver {
    private static TiffFileFormatDriver instance = null;
    
    public static void init() {
        instance = new TiffFileFormatDriver();
        TiffFileFormatProperties.init();
    }
    
    public static TiffFileFormatDriver get_instance() {
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return TiffFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new TiffReader(filepath);
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
        return new TiffWriter(filepath);
    }
    
    public override PhotoFileMetadataWriter? create_metadata_writer(string filepath) {
        return new TiffMetadataWriter(filepath);
    }
    
    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new TiffSniffer(file, options);
    }
}

private class TiffFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = {
        "tif", "tiff"
    };
    
    private static string[] KNOWN_MIME_TYPES = {
        "image/tiff"
    };
    
    private static TiffFileFormatProperties instance = null;
    
    public static void init() {
        instance = new TiffFileFormatProperties();
    }
    
    public static TiffFileFormatProperties get_instance() {
        return instance;
    }
    
    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.TIFF;
    }
    
    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }
    
    public override string get_default_extension() {
        return "tif";
    }

    public override string get_user_visible_name() {
        return _("TIFF");
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

private class TiffSniffer : GdkSniffer {
    public TiffSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }
    
    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // Rely on GdkSniffer to detect corruption
        is_corrupted = false;
        
        if (!is_tiff(file))
            return null;
        
        DetectedPhotoInformation? detected = base.sniff(out is_corrupted);
        if (detected == null)
            return null;
        
        return (detected.file_format == PhotoFileFormat.TIFF) ? detected : null;
    }
}

private class TiffReader : GdkReader {
    public TiffReader(string filepath) {
        base (filepath, PhotoFileFormat.TIFF);
    }
}

private class TiffWriter : PhotoFileWriter {
    private const string COMPRESSION_NONE = "1";
    private const string COMPRESSION_HUFFMAN = "2";
    private const string COMPRESSION_LZW = "5";
    private const string COMPRESSION_JPEG = "7";
    private const string COMPRESSION_DEFLATE = "8";
    
    public TiffWriter(string filepath) {
        base (filepath, PhotoFileFormat.TIFF);
    }
    
    public override void write(Gdk.Pixbuf pixbuf, Jpeg.Quality quality) throws Error {
        pixbuf.save(get_filepath(), "tiff", "compression", COMPRESSION_LZW);
    }
}

private class TiffMetadataWriter : PhotoFileMetadataWriter {
    public TiffMetadataWriter(string filepath) {
        base (filepath, PhotoFileFormat.TIFF);
    }
    
    public override void write_metadata(PhotoMetadata metadata) throws Error {
        metadata.write_to_file(get_file());
    }
}

public bool is_tiff(File file, Cancellable? cancellable = null) throws Error {
    DataInputStream dins = new DataInputStream(file.read());
    
    // first two bytes: "II" (0x4949, for Intel) or "MM" (0x4D4D, for Motorola)
    DataStreamByteOrder order;
    switch (dins.read_uint16(cancellable)) {
        case 0x4949:
            order = DataStreamByteOrder.LITTLE_ENDIAN;
        break;
        
        case 0x4D4D:
            order = DataStreamByteOrder.BIG_ENDIAN;
        break;
        
        default:
            return false;
    }
    
    dins.set_byte_order(order);
    
    // second two bytes: some random number
    uint16 lue = dins.read_uint16(cancellable);
    if (lue != 42)
        return false;
    
    // remaining bytes are offset of first IFD, which doesn't matter for our purposes
    return true;
}

}
