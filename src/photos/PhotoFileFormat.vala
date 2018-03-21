/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public errordomain PhotoFormatError {
    READ_ONLY
}

//
// PhotoFileFormat
//

namespace PhotoFileFormatData {
    private static PhotoFileFormat[] writeable = null;
    private static PhotoFileFormat[] image_writeable = null;
    private static PhotoFileFormat[] metadata_writeable = null;
    
    private delegate bool ApplicableTest(PhotoFileFormat format);
    
    private PhotoFileFormat[] find_applicable(ApplicableTest test) {
        PhotoFileFormat[] applicable = new PhotoFileFormat[0];
        foreach (PhotoFileFormat format in PhotoFileFormat.get_supported()) {
            if (test(format))
                applicable += format;
        }
        
        return applicable;
    }
    
    public PhotoFileFormat[] get_writeable() {
        if (writeable == null)
            writeable = find_applicable((format) => { return format.can_write(); });
        
        return writeable;
    }
    
    public static PhotoFileFormat[] get_image_writeable() {
        if (image_writeable == null)
            image_writeable = find_applicable((format) => { return format.can_write_image(); });
        
        return image_writeable;
    }
    
    public static PhotoFileFormat[] get_metadata_writeable() {
        if (metadata_writeable == null)
            metadata_writeable = find_applicable((format) => { return format.can_write_metadata(); });
        
        return metadata_writeable;
    }
}

public enum PhotoFileFormat {
    JFIF,
    RAW,
    PNG,
    TIFF,
    BMP,
    GIF,
    UNKNOWN;
    
    // This is currently listed in the order of detection, that is, the file is examined from
    // left to right.  (See PhotoFileInterrogator.)
    public static PhotoFileFormat[] get_supported() {
        return { JFIF, RAW, PNG, TIFF, BMP, GIF };
    }
    
    public static PhotoFileFormat[] get_writeable() {
        return PhotoFileFormatData.get_writeable();
    }
    
    public static PhotoFileFormat[] get_image_writeable() {
        return PhotoFileFormatData.get_image_writeable();
    }
    
    public static PhotoFileFormat[] get_metadata_writeable() {
        return PhotoFileFormatData.get_metadata_writeable();
    }
    
    public static PhotoFileFormat get_by_basename_extension(string basename) {
        string name, ext;
        disassemble_filename(basename, out name, out ext);
        
        if (is_string_empty(ext))
            return UNKNOWN;
        
        foreach (PhotoFileFormat file_format in get_supported()) {
            if (file_format.get_driver().get_properties().is_recognized_extension(ext))
                return file_format;
        }
        
        return UNKNOWN;
    }
    
    public static bool is_file_supported(File file) {
        return is_basename_supported(file.get_basename());
    }
    
    public static bool is_basename_supported(string basename) {
        string name, ext;
        disassemble_filename(basename, out name, out ext);
        
        if (is_string_empty(ext))
            return false;
        
        foreach (PhotoFileFormat format in get_supported()) {
            if (format.get_driver().get_properties().is_recognized_extension(ext))
                return true;
        }
        
        return false;
    }
    
    // Guaranteed to be writeable.
    public static PhotoFileFormat get_system_default_format() {
        return JFIF;
    }

    public static PhotoFileFormat get_by_file_extension(File file) {
        return get_by_basename_extension(file.get_basename());
    }
    
    // These values are persisted in the database.  DO NOT CHANGE THE INTEGER EQUIVALENTS.
    public int serialize() {
        switch (this) {
            case JFIF:
                return 0;
            
            case RAW:
                return 1;

            case PNG:
                return 2;
            
            case TIFF:
                return 3;

            case BMP:
                return 4;

            case GIF:
                return 5;
            
            case UNKNOWN:
            default:
                return -1;
        }
    }
    
    // These values are persisted in the database.  DO NOT CHANGE THE INTEGER EQUIVALENTS.
    public static PhotoFileFormat unserialize(int value) {
        switch (value) {
            case 0:
                return JFIF;
            
            case 1:
                return RAW;

            case 2:
                return PNG;
            
            case 3:
                return TIFF;

            case 4:
                return BMP;

            case 5:
                return GIF;
                            
            default:
                return UNKNOWN;
        }
    }

    public static PhotoFileFormat from_gphoto_type(string type) {
        switch (type) {
            case GPhoto.MIME.JPEG:
                return PhotoFileFormat.JFIF;
            
            case GPhoto.MIME.RAW:
            case GPhoto.MIME.CRW:
                return PhotoFileFormat.RAW;
            
            case GPhoto.MIME.PNG:
                return PhotoFileFormat.PNG;
            
            case GPhoto.MIME.TIFF:
                return PhotoFileFormat.TIFF;

            case GPhoto.MIME.BMP:
                return PhotoFileFormat.BMP;

            // GPhoto does not have GIF

            default:
                // check file extension against those we support
                return PhotoFileFormat.UNKNOWN;
        }
    }
    
    // Converts GDK's pixbuf library's name to a PhotoFileFormat
    public static PhotoFileFormat from_pixbuf_name(string name) {
        switch (name) {
            case "jpeg":
                return PhotoFileFormat.JFIF;
            
            case "png":
                return PhotoFileFormat.PNG;
            
            case "tiff":
                return PhotoFileFormat.TIFF;
            
            case "bmp":
                return PhotoFileFormat.BMP;

            case "gif":
                return PhotoFileFormat.GIF;
            
            default:
                return PhotoFileFormat.UNKNOWN;
        }
    }
    
    public void init() {
        switch (this) {
            case JFIF:
                JfifFileFormatDriver.init();
                break;
            
            case RAW:
                RawFileFormatDriver.init();
                break;
            
            case PNG:
                PngFileFormatDriver.init();
                break;
            
            case TIFF:
                Photos.TiffFileFormatDriver.init();
                break;
            
            case BMP:
                Photos.BmpFileFormatDriver.init();
                break;

            case GIF:
                Photos.GifFileFormatDriver.init();
                break;

            default:
                error("Unsupported file format %s", this.to_string());
        }
    }
    
    private PhotoFileFormatDriver get_driver() {
        switch (this) {
            case JFIF:
                return JfifFileFormatDriver.get_instance();
            
            case RAW:
                return RawFileFormatDriver.get_instance();
            
            case PNG:
                return PngFileFormatDriver.get_instance();
            
            case TIFF:
                return Photos.TiffFileFormatDriver.get_instance();
            
            case BMP:
                return Photos.BmpFileFormatDriver.get_instance();

            case GIF:
                return Photos.GifFileFormatDriver.get_instance();

            default:
                error("Unsupported file format %s", this.to_string());
        }
    }
    
    public PhotoFileFormatProperties get_properties() {
        return get_driver().get_properties();
    }
    
    // Supplied with a name, returns the name with the file format's default extension.
    public string get_default_basename(string name) {
        return "%s.%s".printf(name, get_properties().get_default_extension());
    }
    
    public PhotoFileReader create_reader(string filepath) {
        return get_driver().create_reader(filepath);
    }
    
    // This means the image and its metadata are writeable.
    public bool can_write() {
        return can_write_image() && can_write_metadata();
    }
    
    public bool can_write_image() {
        return get_driver().can_write_image();
    }
    
    public bool can_write_metadata() {
        return get_driver().can_write_metadata();
    }
    
    public PhotoFileWriter create_writer(string filepath) throws PhotoFormatError {
        PhotoFileWriter writer = get_driver().create_writer(filepath);
        if (writer == null)
            throw new PhotoFormatError.READ_ONLY("File format %s is read-only", this.to_string());
        
        return writer;
    }
    
    public PhotoFileMetadataWriter create_metadata_writer(string filepath) throws PhotoFormatError {
        PhotoFileMetadataWriter writer = get_driver().create_metadata_writer(filepath);
        if (writer == null)
            throw new PhotoFormatError.READ_ONLY("File format %s metadata is read-only", this.to_string());
        
        return writer;
    }
    
    public PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return get_driver().create_sniffer(file, options);
    }
    
    public PhotoMetadata create_metadata() {
        return get_driver().create_metadata();
    }
    
    public string get_default_mime_type() {
        return get_driver().get_properties().get_default_mime_type();
    }
    
    public string[] get_mime_types() {
        return get_driver().get_properties().get_mime_types();
    }
    
    public static string[] get_editable_mime_types() {
        string[] mime_types = {};
        
        foreach (PhotoFileFormat file_format in PhotoFileFormat.get_supported()) {
            foreach (string mime_type in file_format.get_mime_types())
                mime_types += mime_type;
        }
        
        return mime_types;
    }
}

//
// PhotoFileFormatDriver
//
// Each supported file format is expected to have a PhotoFileFormatDriver that returns all possible
// resources that are needed to operate on file of its particular type.  It's expected that each
// format subsystem will only create and cache a single instance of this driver, although it's
// not required.
//
// Like the other elements in the PhotoFileFormat family, this class should be thread-safe.
//

public abstract class PhotoFileFormatDriver {
    public abstract PhotoFileFormatProperties get_properties();
    
    public abstract PhotoFileReader create_reader(string filepath);
    
    public abstract PhotoMetadata create_metadata();
    
    public abstract bool can_write_image();
    
    public abstract bool can_write_metadata();
    
    public abstract PhotoFileWriter? create_writer(string filepath);
    
    public abstract PhotoFileMetadataWriter? create_metadata_writer(string filepath);
    
    public abstract PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options);
}

//
// PhotoFileFormatProperties
//
// Although each PhotoFileFormatProperties is expected to be largely static and immutable, these
// classes should be thread-safe.
//

public enum PhotoFileFormatFlags {
    NONE =                  0x00000000,
}

public abstract class PhotoFileFormatProperties {
    public abstract PhotoFileFormat get_file_format();
    
    public abstract PhotoFileFormatFlags get_flags();
    
    // Default implementation will search for ext in get_known_extensions(), assuming they are
    // all stored in lowercase.
    public virtual bool is_recognized_extension(string ext) {
        return is_in_ci_array(ext, get_known_extensions());
    }
    
    public abstract string get_default_extension();
    
    public abstract string[] get_known_extensions();
    
    public abstract string get_default_mime_type();
    
    public abstract string[] get_mime_types();

    // returns the user-visible name of the file format -- this name is used in user interface
    // strings whenever the file format needs to named. This name is not the same as the format
    // enum value converted to a string. The format enum value is meaningful to developers and is
    // constant across languages (e.g. "JFIF", "TGA") whereas the user-visible name is translatable
    // and is meaningful to users (e.g. "JPEG", "Truevision TARGA")
    public abstract string get_user_visible_name();
    
    // Takes a given file and returns one with the file format's default extension, unless it
    // already has one of the format's known extensions
    public File convert_file_extension(File file) {
        string name, ext;
        disassemble_filename(file.get_basename(), out name, out ext);
        if (ext != null && is_recognized_extension(ext))
            return file;
        
        return file.get_parent().get_child("%s.%s".printf(name, get_default_extension()));
    }
}

