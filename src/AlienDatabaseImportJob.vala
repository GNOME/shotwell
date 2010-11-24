/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

/**
 * Photo source implementation for alien databases. This class is responsible
 * for extracting meta-data out of a source photo to support the import
 * process.
 *
 * This class does not extend PhotoSource in order to minimise the API to the
 * absolute minimum required to run the import job.
 */
public class AlienDatabaseImportSource {
    private AlienDatabasePhoto db_photo;
    private string? title = null;
    private string? preview_md5 = null;
    private uint64 file_size;
    private time_t modification_time;
    private MetadataDateTime? exposure_time;
    
    public AlienDatabaseImportSource(AlienDatabasePhoto db_photo) {
        this.db_photo = db_photo;
        File photo = File.new_for_path(db_photo.get_folder_path()).
            get_child(db_photo.get_filename());
        
        PhotoMetadata? metadata = new PhotoMetadata();
        try {
            metadata.read_from_file(photo);
        } catch(Error e) {
            warning("Could not get file metadata for %s: %s", get_filename(), e.message);
            metadata = null;
        }
        
        title = (metadata != null) ? metadata.get_title() : null;
        exposure_time = (metadata != null) ? metadata.get_exposure_date_time() : null;
        PhotoPreview? preview = metadata != null ? metadata.get_preview(0) : null;
        if (preview != null) {
            try {
                uint8[] preview_raw = preview.flatten();
                preview_md5 = md5_binary(preview_raw, preview_raw.length);
            } catch(Error e) {
                warning("Could not get raw preview for %s: %s", get_filename(), e.message);
            }
        }
#if TRACE_MD5
        debug("Photo MD5 %s: preview=%s", get_filename(), preview_md5);
#endif
        
        try {
            file_size = query_total_file_size(photo);
        } catch(Error e) {
            warning("Could not get file size for %s: %s", get_filename(), e.message);
        }
        try {
            modification_time = query_file_modified(photo);
        } catch(Error e) {
            warning("Could not get modification time for %s: %s", get_filename(), e.message);
        }
    }
    
    public string get_filename() {
        return db_photo.get_filename();
    }
    
    public string get_fulldir() {
        return db_photo.get_folder_path();
    }
    
    public File get_file() {
        return File.new_for_path(get_fulldir()).get_child(get_filename());
    }
    
    public string get_name() {
        return !is_string_empty(title) ? title : get_filename();
    }
    
    public string? get_title() {
        return title;
    }
    
    public PhotoFileFormat get_file_format() {
        return PhotoFileFormat.get_by_basename_extension(get_filename());
    }
    
    public string to_string() {
        return get_name();
    }
    
    public time_t get_exposure_time() {
        return (exposure_time != null) ? exposure_time.get_timestamp() : modification_time;
    }
    
    public uint64 get_filesize() {
        return file_size;
    }
    
    public AlienDatabasePhoto get_photo() {
        return db_photo;
    }
    
    public bool is_already_imported() {
		// ignore trashed duplicates
        return (preview_md5 != null) 
            ? LibraryPhoto.has_nontrash_duplicate(null, preview_md5, null, get_file_format())
            : false;
    }
}

/**
 * A specialized import job implementation for alien databases.
 */
public class AlienDatabaseImportJob : BatchImportJob {
    private AlienDatabaseImportSource import_source;
    private File? src_file;
    private uint64 filesize;
    private time_t exposure_time;
    private ImportID import_id;
    
    public AlienDatabaseImportJob(AlienDatabaseImportSource import_source) {
        this.import_source = import_source;
        
        // stash everything called in prepare(), as it may/will be called from a separate thread
        src_file = import_source.get_file();
        filesize = import_source.get_filesize();
        exposure_time = import_source.get_exposure_time();
        import_id = ImportID.generate();
    }
    
    public time_t get_exposure_time() {
        return exposure_time;
    }
    
    public override string get_identifier() {
        return import_source.get_filename();
    }
    
    public override bool is_directory() {
        return false;
    }
    
    public override bool determine_file_size(out uint64 filesize, out File file) {
        filesize = this.filesize;
        
        return true;
    }
    
    public override bool prepare(out File file_to_import, out bool copy_to_library) throws Error {
        file_to_import = src_file;
        copy_to_library = false;
        
        return true;
    }
    
    public override bool complete(MediaSource source, ViewCollection generated_events) throws Error {
        LibraryPhoto? photo = source as LibraryPhoto;
        if (photo == null)
            return false;
        
        AlienDatabasePhoto src_photo = import_source.get_photo();
        // tags
        Gee.Collection<AlienDatabaseTag> src_tags = src_photo.get_tags();
        foreach (AlienDatabaseTag src_tag in src_tags) {
            Tag tag = Tag.for_name(src_tag.get_name());
            tag.establish_link(photo);
        }
        // event
        AlienDatabaseEvent? src_event = src_photo.get_event();
        if (src_event != null) {
            Event.generate_single_event(photo, generated_events, src_event.get_name());
        }
        // rating
        photo.set_rating(src_photo.get_rating());
        // title
        string? title = src_photo.get_title();
        if (title != null)
            photo.set_title(title);
        // import ID
        photo.set_import_id(import_id);
        
        return true;
    }
}

