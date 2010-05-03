/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace LibraryFiles {
public const int DIRECTORY_DEPTH = 3;

// Returns true if the file is claimed, false if it exists, and throws an Error otherwise.
private bool claim_file(File file) throws Error {
    try {
        file.create(FileCreateFlags.NONE, null);
        
        // created; success
        return true;
    } catch (Error err) {
        // check for file-exists error
        if (!(err is IOError.EXISTS)) {
            debug("claim_file %s: %s", file.get_path(), err.message);
            
            throw err;
        }
        
        return false;
    }
}

// This method uses File.create() in order to "claim" a file in the filesystem.  Thus, when the
// method returns success a file may exist already, and should be overwritten.
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
    File dir = AppDirs.get_photos_dir();
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
    
    // create the file to atomically "claim" it
    File file = dir.get_child(basename);
    if (claim_file(file)) {
        collision = false;
        
        return file;
    }
    
    // file exists, collision and keep searching
    collision = true;
    
    string name, ext;
    disassemble_filename(basename, out name, out ext);
    
    // generate a unique filename
    for (int ctr = 1; ctr < int.MAX; ctr++) {
        string new_name = (ext != null) ? "%s_%d.%s".printf(name, ctr, ext) : "%s_%d".printf(name, ctr);
        
        file = dir.get_child(new_name);
        if (claim_file(file))
            return file;
    }
    
    debug("generate_unique_filename for %s: unable to claim file", basename);
    
    return null;
}

// This function is thread-safe.
private File duplicate(File src, FileProgressCallback? progress_callback) throws Error {
    time_t timestamp = 0;
    try {
        timestamp = query_file_modified(src);
    } catch (Error err) {
        critical("Unable to access file modification for %s: %s", src.get_path(), err.message);
    }
    
    PhotoFileReader reader = PhotoFileFormat.get_by_file_extension(src).create_reader(src.get_path());
    PhotoMetadata? metadata = null;
    try {
        metadata = reader.read_metadata();
    } catch (Error err) {
        // ignored, leave metadata as null
    }
    
    bool collision;
    File? dest = generate_unique_file(src.get_basename(), metadata, timestamp, out collision);
    if (dest == null)
        throw new FileError.FAILED("Unable to generate unique pathname for destination");
    
    src.copy(dest, FileCopyFlags.ALL_METADATA | FileCopyFlags.OVERWRITE, null, progress_callback);
    
    return dest;
}
}
