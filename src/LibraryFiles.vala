/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace LibraryFiles {
public const int DIRECTORY_DEPTH = 3;

// This method uses global::generate_unique_file_at in order to "claim" a file in the filesystem.
// Thus, when the method returns success a file may exist already, and should be overwritten.
//
// This function is thread safe.
public File? generate_unique_file(string basename, PhotoMetadata? metadata, time_t ts, out bool collision)
    throws Error {
    // use exposure timestamp over the supplied one (which probably comes from the file's
    // modified time, or is simply time()), unless it's zero, in which case use current time
    time_t timestamp = ts;
    if (metadata != null) {
        MetadataDateTime? date_time = metadata.get_exposure_date_time();
        if (date_time != null)
            timestamp = date_time.get_timestamp();
        else if (timestamp == 0)
            timestamp = time_t();
    }
    
    Time tm = Time.local(timestamp);
    
    // build a directory tree inside the library, as deep as DIRECTORY_DEPTH:
    // yyyy/mm/dd
    File dir = AppDirs.get_import_dir();
    dir = dir.get_child("%04u".printf(tm.year + 1900));
    dir = dir.get_child("%02u".printf(tm.month + 1));
    dir = dir.get_child("%02u".printf(tm.day));
    
    try {
        dir.make_directory_with_parents(null);
    } catch (Error err) {
        if (!(err is IOError.EXISTS))
            throw err;
        
        // silently ignore not creating a directory that already exists
    }
    
    return global::generate_unique_file(dir, basename, out collision);
}

// This function is thread-safe.
private File duplicate(File src, FileProgressCallback? progress_callback, bool blacklist) throws Error {
    time_t timestamp = 0;
    try {
        timestamp = query_file_modified(src);
    } catch (Error err) {
        critical("Unable to access file modification for %s: %s", src.get_path(), err.message);
    }
       
    PhotoMetadata? metadata = null;
    if (!VideoReader.is_supported_video_file(src)) { // video files don't have EXIF metadata
        PhotoFileReader reader = PhotoFileFormat.get_by_file_extension(src).create_reader(
            src.get_path());
        try {
            metadata = reader.read_metadata();
        } catch (Error err) {
            // ignored, leave metadata as null
        }
    }
    
    bool collision;
    File? dest = generate_unique_file(src.get_basename(), metadata, timestamp, out collision);
    if (dest == null)
        throw new FileError.FAILED("Unable to generate unique pathname for destination");
    
    if (blacklist)
        LibraryMonitor.blacklist_file(dest);
    
    try {
        src.copy(dest, FileCopyFlags.ALL_METADATA | FileCopyFlags.OVERWRITE, null, progress_callback);
    } finally {
        if (blacklist)
            LibraryMonitor.unblacklist_file(dest);
    }
    
    return dest;
}
}
