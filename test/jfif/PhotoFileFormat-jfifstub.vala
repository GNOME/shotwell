// stub for JFIF support test

public enum PhotoFileFormat {
    JFIF,
    UNKNOWN;

    public static PhotoFileFormat[] get_supported() { return { JFIF }; }

    public static PhotoFileFormat from_pixbuf_name(string name) {
        if (name == "jpeg") {
            return PhotoFileFormat.JFIF;
        } else {
            return PhotoFileFormat.UNKNOWN;
        }
    }

    public void init() { JfifFileFormatDriver.init(); }

    public PhotoFileFormatDriver get_driver() {
        return JfifFileFormatDriver.get_instance();
    }

    public PhotoFileReader create_reader(string filepath) {
        return get_driver().create_reader(filepath);
    }

    public PhotoFileWriter create_writer(string filepath) throws PhotoFormatError {
        PhotoFileWriter writer = get_driver().create_writer(filepath);
        return writer;
    }

    public PhotoFileMetadataWriter create_metadata_writer(string filepath) throws PhotoFormatError {
        PhotoFileMetadataWriter writer = get_driver().create_metadata_writer(filepath);
        return writer;
    }

    public PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return get_driver().create_sniffer(file, options);
    }
}

public errordomain PhotoFormatError {
    READ_ONLY
}

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

public enum PhotoFileFormatFlags {
    NONE =                  0x00000000,
}

public abstract class PhotoFileFormatProperties {
    public abstract PhotoFileFormat get_file_format();
    
    public abstract PhotoFileFormatFlags get_flags();
    
    public virtual bool is_recognized_extension(string ext) {
        return is_in_ci_array(ext, get_known_extensions());
    }
    
    public abstract string get_default_extension();
    
    public abstract string[] get_known_extensions();
    
    public abstract string get_default_mime_type();
    
    public abstract string[] get_mime_types();

    public abstract string get_user_visible_name();
    
    public File convert_file_extension(File file) {
        string name, ext;
        disassemble_filename(file.get_basename(), out name, out ext);
        if (ext != null && is_recognized_extension(ext))
            return file;
        
        return file.get_parent().get_child("%s.%s".printf(name, get_default_extension()));
    }
}
