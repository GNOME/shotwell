/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace LibraryFiles {
public const int DIRECTORY_DEPTH = 3;
    
public File? generate_unique_file(string filename, Exif.Data? exif, time_t ts, out bool collision) {
    File dir = AppDirs.get_photos_dir();
    time_t timestamp = ts;
    
    // use EXIF exposure timestamp over the supplied one (which probably comes from the file's
    // modified time, or is simply now())
    if (exif != null && !Exif.get_timestamp(exif, out timestamp)) {
        // if no exposure time supplied, use now()
        if (ts == 0)
            timestamp = time_t();
    }
    
    Time tm = Time.local(timestamp);
    
    // build a directory tree inside the library, as deep as DIRECTORY_DEPTH:
    // yyyy/mm/dd
    dir = dir.get_child("%04u".printf(tm.year + 1900));
    dir = dir.get_child("%02u".printf(tm.month + 1));
    dir = dir.get_child("%02u".printf(tm.day));
    
    try {
        if (!dir.query_exists(null))
            dir.make_directory_with_parents(null);
    } catch (Error err) {
        error("Unable to create photo library directory %s", dir.get_path());
    }
    
    // if file doesn't exist, use that and done
    File file = dir.get_child(filename);
    if (!file.query_exists(null)) {
        collision = false;

        return file;
    }

    collision = true;

    string name, ext;
    disassemble_filename(file.get_basename(), out name, out ext);

    // generate a unique filename
    for (int ctr = 1; ctr < int.MAX; ctr++) {
        string new_name = (ext != null) ? "%s_%d.%s".printf(name, ctr, ext) : "%s_%d".printf(name, ctr);

        file = dir.get_child(new_name);
        
        if (!file.query_exists(null))
            return file;
    }
    
    return null;
}

private File duplicate(File src) throws Error {
    time_t timestamp = 0;
    try {
        timestamp = query_file_modified(src);
    } catch (Error err) {
        critical("Unable to access file modification for %s: %s", src.get_path(), err.message);
    }
    
    PhotoExif exif = new PhotoExif(src);
    
    bool collision;
    File? dest = generate_unique_file(src.get_basename(), exif.get_exif(), timestamp, out collision);
    if (dest == null)
        throw new FileError.FAILED("Unable to generate unique pathname for destination");
    
    debug("Copying %s to %s", src.get_path(), dest.get_path());
    
    src.copy(dest, FileCopyFlags.ALL_METADATA, null, on_copy_progress);
    
    return dest;
}

private void on_copy_progress(int64 current, int64 total) {
    spin_event_loop();
}
}
