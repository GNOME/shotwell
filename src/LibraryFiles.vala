/* Copyright 2009-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace LibraryFiles {

// This method uses global::generate_unique_file_at in order to "claim" a file in the filesystem.
// Thus, when the method returns success a file may exist already, and should be overwritten.
//
// This function is thread safe.
public File? generate_unique_file(string basename, MediaMetadata? metadata, time_t ts, out bool collision)
    throws Error {
    // use exposure timestamp over the supplied one (which probably comes from the file's
    // modified time, or is simply time()), unless it's zero, in which case use current time
    
    time_t timestamp = ts;
    if (metadata != null) {
        MetadataDateTime? date_time = metadata.get_creation_date_time();
        if (date_time != null)
            timestamp = date_time.get_timestamp();
        else if (timestamp == 0)
            timestamp = time_t();
    }
    
    // build a directory tree inside the library
    File dir = AppDirs.get_baked_import_dir(timestamp);
    try {
        dir.make_directory_with_parents(null);
    } catch (Error err) {
        if (!(err is IOError.EXISTS))
            throw err;
        
        // silently ignore not creating a directory that already exists
    }
    
    // Optionally convert to lower-case.
    string newbasename = basename;
    if (Config.Facade.get_instance().get_use_lowercase_filenames())
        newbasename = newbasename.down();
    
    return global::generate_unique_file(dir, newbasename, out collision);
}

// This function is thread-safe.
private File duplicate(File src, FileProgressCallback? progress_callback, bool blacklist) throws Error {
    time_t timestamp = 0;
    try {
        timestamp = query_file_modified(src);
    } catch (Error err) {
        critical("Unable to access file modification for %s: %s", src.get_path(), err.message);
    }
       
    MediaMetadata? metadata = null;
    if (VideoReader.is_supported_video_file(src)) {
        VideoReader reader = new VideoReader(src);
        try {
            metadata = reader.read_metadata();
        } catch (Error err) {
            // ignored, leave metadata as null
        }            
    } else {
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
        LibraryMonitor.blacklist_file(dest, "LibraryFiles.duplicate");
    
    try {
        src.copy(dest, FileCopyFlags.ALL_METADATA | FileCopyFlags.OVERWRITE, null, progress_callback);
        if (blacklist)
            LibraryMonitor.unblacklist_file(dest);
    } catch (Error err) {
        message("There was a problem copying %s: %s", src.get_path(), err.message);
        if (blacklist && (md5_file(src) != md5_file(dest)))
            LibraryMonitor.unblacklist_file(dest);
    }
    
    // Make file writable by getting current Unix mode and or it with 600 (user read/write)
    try {
        FileInfo info = dest.query_info(FileAttribute.UNIX_MODE, FileQueryInfoFlags.NONE);
        uint32 mode = info.get_attribute_uint32(FileAttribute.UNIX_MODE) | 0600;
        if (!dest.set_attribute_uint32(FileAttribute.UNIX_MODE, mode, FileQueryInfoFlags.NONE)) {
            warning("Could not make file writable");
        }
    } catch (Error err) {
        warning("Could not make file writable: %s", err.message);
    }
    
    return dest;
}
}
