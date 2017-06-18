/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Spit.DataImports {

/**
 * Photo source implementation for alien databases. This class is responsible
 * for extracting meta-data out of a source photo to support the import
 * process.
 *
 * This class does not extend PhotoSource in order to minimise the API to the
 * absolute minimum required to run the import job.
 */
public class DataImportSource {
    private bool backing_file_found;
    private ImportableMediaItem db_photo;
    private string? title = null;
    private string? preview_md5 = null;
    private uint64 file_size;
    private time_t modification_time;
    private MetadataDateTime? exposure_time;
    
    public DataImportSource(ImportableMediaItem db_photo) {
        this.db_photo = db_photo;
        
        // A well-behaved plugin will ensure that the path and file name are
        // not null but we check just in case
        string folder_path = db_photo.get_folder_path();
        string filename = db_photo.get_filename();
        File? photo = null;
        if (folder_path != null && filename != null) {
            photo = File.new_for_path(db_photo.get_folder_path()).
                get_child(db_photo.get_filename());
                
            backing_file_found = photo.query_exists();
        } else {
            backing_file_found = false;
        }
        
        if (photo != null && backing_file_found) {
            PhotoMetadata? metadata = new PhotoMetadata();
            try {
                metadata.read_from_file(photo);
            } catch(Error e) {
                warning("Could not get file metadata for %s: %s", get_filename(), e.message);
                metadata = null;
            }
            title = db_photo.get_title();
            if (title == null) {
                title = (metadata != null) ? metadata.get_title() : null;
            }
            time_t? date_time = db_photo.get_exposure_time();
            if (date_time != null) {
                exposure_time = new MetadataDateTime(date_time);
            } else {
                exposure_time = (metadata != null) ? metadata.get_exposure_date_time() : null;
            }

            if (metadata != null) {
                preview_md5 = metadata.thumbnail_hash();
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
        } else {
            debug ("Photo file %s not found".printf(photo.get_path()));
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
    
    public ImportableMediaItem get_photo() {
        return db_photo;
    }
    
    public bool is_already_imported() {
		// ignore trashed duplicates
        return (preview_md5 != null) 
            ? LibraryPhoto.has_nontrash_duplicate(null, preview_md5, null, get_file_format())
            : false;
    }
    
    public bool was_backing_file_found() {
        return backing_file_found;
    }
}

}

