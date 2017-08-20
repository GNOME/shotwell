/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class RawFileFormatDriver : PhotoFileFormatDriver {
    private static RawFileFormatDriver instance = null;
    
    public static void init() {
        instance = new RawFileFormatDriver();
        RawFileFormatProperties.init();
    }
    
    public static RawFileFormatDriver get_instance() {
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return RawFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new RawReader(filepath);
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
        return new RawSniffer(file, options);
    }
}

public class RawFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = {
        "3fr", "arw", "srf", "sr2", "bay", "crw", "cr2", "cap", "iiq", "eip", "dcs", "dcr", "drf",
        "k25", "kdc", "dng", "erf", "fff", "mef", "mos", "mrw", "nef", "nrw", "orf", "ptx", "pef",
        "pxn", "r3d", "raf", "raw", "rw2", "raw", "rwl", "rwz", "x3f", "srw"
    };

    private static string[] KNOWN_MIME_TYPES = {
        /* a catch-all MIME type for all formats supported by the dcraw command-line
           tool (and hence libraw) */
        "image/x-dcraw",
    
        /* manufacturer blessed MIME types */
        "image/x-canon-cr2",
        "image/x-canon-crw",
        "image/x-fuji-raf",
        "image/x-adobe-dng",
        "image/x-panasonic-raw",
        "image/x-raw",
        "image/x-minolta-mrw",
        "image/x-nikon-nef",
        "image/x-olympus-orf",
        "image/x-pentax-pef",
        "image/x-sony-arw",
        "image/x-sony-srf",
        "image/x-sony-sr2",
        "image/x-samsung-raw",

        /* generic MIME types for file extensions*/
        "image/x-3fr",
        "image/x-arw",
        "image/x-srf",
        "image/x-sr2",
        "image/x-bay",
        "image/x-crw",
        "image/x-cr2",
        "image/x-cap",
        "image/x-iiq",
        "image/x-eip",
        "image/x-dcs",
        "image/x-dcr",
        "image/x-drf",
        "image/x-k25",
        "image/x-kdc",
        "image/x-dng",
        "image/x-erf",
        "image/x-fff",
        "image/x-mef",
        "image/x-mos",
        "image/x-mrw",
        "image/x-nef",
        "image/x-nrw",
        "image/x-orf",
        "image/x-ptx",
        "image/x-pef",
        "image/x-pxn",
        "image/x-r3d",
        "image/x-raf",
        "image/x-raw",
        "image/x-rw2",
        "image/x-raw",
        "image/x-rwl",
        "image/x-rwz",
        "image/x-x3f",
        "image/x-srw"
    };
    
    private static RawFileFormatProperties instance = null;
    
    public static void init() {
        instance = new RawFileFormatProperties();
    }
    
    public static RawFileFormatProperties get_instance() {
        return instance;
    }
    
    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.RAW;
    }

    public override string get_user_visible_name() {
        return _("RAW");
    }

    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.NONE;
    }
    
    public override string get_default_extension() {
        // Because RAW is a smorgasbord of file formats and exporting to a RAW file is
        // not expected, this function should probably never be called.  However, need to pick
        // one, so here it is.
        return "raw";
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

public class RawSniffer : PhotoFileSniffer {
    public RawSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }
    
    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        // this sniffer doesn't detect corrupted files
        is_corrupted = false;
        
        DetectedPhotoInformation detected = new DetectedPhotoInformation();
        
        GRaw.Processor processor = new GRaw.Processor();
        processor.output_params->user_flip = GRaw.Flip.NONE;
        
        try {
            processor.open_file(file.get_path());
            processor.unpack();
            processor.adjust_sizes_info_only();
        } catch (GRaw.Exception exception) {
            if (exception is GRaw.Exception.UNSUPPORTED_FILE)
                return null;
            
            throw exception;
        }
        
        detected.image_dim = Dimensions(processor.get_sizes().iwidth, processor.get_sizes().iheight);
        detected.colorspace = Gdk.Colorspace.RGB;
        detected.channels = 3;
        detected.bits_per_channel = 8;
        
        RawReader reader = new RawReader(file.get_path());
        try {
            detected.metadata = reader.read_metadata();
        } catch (Error err) {
            // ignored
        }
        
        if (detected.metadata != null) {
            detected.exif_md5 = detected.metadata.exif_hash();
            detected.thumbnail_md5 = detected.metadata.thumbnail_hash();
        }
        
        if (calc_md5)
            detected.md5 = md5_file(file);
        
        detected.format_name = "raw";
        detected.file_format = PhotoFileFormat.RAW;
        
        return detected;
    }
}

public class RawReader : PhotoFileReader {
    public RawReader(string filepath) {
        base (filepath, PhotoFileFormat.RAW);
    }
    
    public override PhotoMetadata read_metadata() throws Error {
        PhotoMetadata metadata = new PhotoMetadata();
        metadata.read_from_file(get_file());
        
        return metadata;
    }
    
    public override Gdk.Pixbuf unscaled_read() throws Error {
        GRaw.Processor processor = new GRaw.Processor();
        processor.configure_for_rgb_display(false);
        processor.output_params->user_flip = GRaw.Flip.NONE;
        
        processor.open_file(get_filepath());
        processor.unpack();
        processor.process();
        
        return processor.make_mem_image().get_pixbuf_copy();
    }
    
    public override Gdk.Pixbuf scaled_read(Dimensions full, Dimensions scaled) throws Error {
        // Try to get the embedded thumbnail first
        double width_proportion = (double) scaled.width / (double) full.width;
        double height_proportion = (double) scaled.height / (double) full.height;
        bool half_size = width_proportion < 0.5 && height_proportion < 0.5;
        
        GRaw.Processor processor = new GRaw.Processor();
        processor.configure_for_rgb_display(half_size);
        processor.output_params->user_flip = GRaw.Flip.NONE;
        
        processor.open_file(get_filepath());
        try {
            if (this.get_role () == Role.THUMBNAIL) {
                processor.unpack_thumb();
                var image = processor.make_thumb_image ();
                return resize_pixbuf (image.get_pixbuf_copy (),
                                      scaled,
                                      Gdk.InterpType.BILINEAR);
            }
        } catch (Error error) {
            // Nothing to do, continue with raw developer
        }

        processor.unpack();
        processor.process();
        
        GRaw.ProcessedImage image = processor.make_mem_image();
        
        return resize_pixbuf(image.get_pixbuf_copy(), scaled, Gdk.InterpType.BILINEAR);
    }
}

// Development mode of a RAW photo.
public enum RawDeveloper {
    SHOTWELL = 0,  // Developed internally by Shotwell
    CAMERA,        // JPEG from RAW+JPEG pair (if available)
    EMBEDDED;      // Largest-size
    
    public static RawDeveloper[] as_array() {
        return { SHOTWELL, CAMERA, EMBEDDED };
    }
    
    public string to_string() {
        switch (this) {
            case SHOTWELL:
                return "SHOTWELL";
            case CAMERA:
                return "CAMERA";
            case EMBEDDED:
                return "EMBEDDED";
            default:
                assert_not_reached();
        }
    }
    
    public static RawDeveloper from_string(string value) {
        switch (value) {
            case "SHOTWELL":
                return SHOTWELL;
            case "CAMERA":
                return CAMERA;
            case "EMBEDDED":
                return EMBEDDED;
            default:
                assert_not_reached();
        }
    }
    
    public string get_label() {
        switch (this) {
            case SHOTWELL:
                return _("Shotwell");
            case CAMERA:
            case EMBEDDED:
                return _("Camera");
            default:
                assert_not_reached();
        }
    }
    
    // Determines if two RAW developers are equivalent, treating camera and embedded
    // as the same.
    public bool is_equivalent(RawDeveloper d) {
        if (this == d)
            return true;
        
        if ((this == RawDeveloper.CAMERA && d == RawDeveloper.EMBEDDED) ||
            (this == RawDeveloper.EMBEDDED && d == RawDeveloper.CAMERA))
            return true;
        
        return false;
    }
    
    // Creates a backing JPEG.
    // raw_filepath is the full path of the imported RAW file.
    public BackingPhotoRow create_backing_row_for_development(string raw_filepath,
        string? camera_development_filename = null) throws Error {
        BackingPhotoRow ns = new BackingPhotoRow();
        File master = File.new_for_path(raw_filepath);
        string name, ext;
        disassemble_filename(master.get_basename(), out name, out ext);
        
        string basename;
        
        // If this image is coming in with an existing development, use its existing
        // filename instead.
        if (camera_development_filename == null) {
            basename = name + "_" + ext +
                (this != CAMERA ? ("_" + this.to_string().down()) : "") + ".jpg";
        } else {
            basename = camera_development_filename;
        }
        
        string newbasename = LibraryFiles.convert_basename(basename);

        bool c;
        File? new_back = generate_unique_file(master.get_parent(), newbasename, out c);
        claim_file(new_back);
        ns.file_format = PhotoFileFormat.JFIF;
        ns.filepath = new_back.get_path();
        
        return ns;
    }
}
