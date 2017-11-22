/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Returns true if the file is claimed, false if it exists, and throws an Error otherwise.  The file
// will be created when the function exits and should be overwritten.  Note that the file is not
// held open; claiming a file is merely based on its existence.
//
// This function is thread-safe.
public bool claim_file(File file) throws Error {
    try {
        file.create(FileCreateFlags.NONE, null);
        
        // created; success
        return true;
    } catch (Error err) {
        // check for file-exists error
        if (!(err is IOError.EXISTS)) {
            warning("claim_file %s: %s", file.get_path(), err.message);
            
            throw err;
        }
        
        return false;
    }
}

// This function "claims" a file on the filesystem in the directory specified with a basename the
// same or similar as what has been requested (adds numerals to the end of the name until a unique
// one has been found).  The file may exist when this function returns, and it should be
// overwritten.  It does *not* attempt to create the parent directory, however.
//
// This function is thread-safe.
public File? generate_unique_file(File dir, string basename, out bool collision) throws Error {
    // create the file to atomically "claim" it
    File file = dir.get_child(basename);
    if (claim_file(file)) {
        collision = false;
        
        return file;
    }
    
    // file exists, note collision and keep searching
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
    
    warning("generate_unique_filename %s for %s: unable to claim file", dir.get_path(), basename);
    
    return null;
}

public void disassemble_filename(string basename, out string name, out string ext) {
    long offset = find_last_offset(basename, '.');
    if (offset <= 0) {
        name = basename;
        ext = null;
    } else {
        name = basename.substring(0, offset);
        ext = basename.substring(offset + 1, -1);
    }
}

// This function is thread-safe.
public uint64 query_total_file_size(File file_or_dir, Cancellable? cancellable = null) throws Error {
    FileType type = file_or_dir.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    if (type == FileType.REGULAR) {
        FileInfo info = null;
        try {
            info = file_or_dir.query_info(FileAttribute.STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        } catch (Error err) {
            if (err is IOError.CANCELLED)
                throw err;
            
            debug("Unable to query filesize for %s: %s", file_or_dir.get_path(), err.message);

            return 0;
        }
        
        return info.get_size();
    } else if (type != FileType.DIRECTORY) {
        return 0;
    }
        
    FileEnumerator enumerator;
    try {
        enumerator = file_or_dir.enumerate_children(FileAttribute.STANDARD_NAME,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        if (enumerator == null)
            return 0;
    } catch (Error err) {
        // Don't treat a permissions failure as a hard failure, just skip the directory
        if (err is FileError.PERM || err is IOError.PERMISSION_DENIED)
            return 0;
        
        throw err;
    }
    
    uint64 total_bytes = 0;
        
    FileInfo info = null;
    while ((info = enumerator.next_file(cancellable)) != null)
        total_bytes += query_total_file_size(file_or_dir.get_child(info.get_name()), cancellable);
    
    return total_bytes;
}

// Does not currently recurse.  Could be modified to do so.  Does not error out on first file that
// does not delete, but logs a warning and continues.
// Note: if supplying a progress monitor, a file count is also required.  The count_files_in_directory()
// function below should do the trick.
public void delete_all_files(File dir, Gee.Set<string>? exceptions = null, ProgressMonitor? monitor = null, 
    uint64 file_count = 0, Cancellable? cancellable = null) throws Error {
    FileType type = dir.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    if (type != FileType.DIRECTORY)
        throw new IOError.NOT_DIRECTORY("%s is not a directory".printf(dir.get_path()));
    
    FileEnumerator enumerator = dir.enumerate_children("standard::name,standard::type",
        FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
    FileInfo info = null;
    uint64 i = 0;
    while ((info = enumerator.next_file(cancellable)) != null) {
        if (info.get_file_type() != FileType.REGULAR)
            continue;
        
        if (exceptions != null && exceptions.contains(info.get_name()))
            continue;
        
        File file = dir.get_child(info.get_name());
        try {
            file.delete(cancellable);
        } catch (Error err) {
            warning("Unable to delete file %s: %s", file.get_path(), err.message);
        }
        
        if (monitor != null && file_count > 0)
            monitor(file_count, ++i);
    }
}

public time_t query_file_modified(File file) throws Error {
    FileInfo info = file.query_info(FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, 
        null);

    return info.get_modification_time().tv_sec;
}

public bool query_is_directory(File file) {
    return file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null) == FileType.DIRECTORY;
}

public bool query_is_directory_empty(File dir) throws Error {
    if (dir.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null) != FileType.DIRECTORY)
        return false;
    
    FileEnumerator enumerator = dir.enumerate_children("standard::name",
        FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    if (enumerator == null)
        return false;
    
    return enumerator.next_file(null) == null;
}

public string get_display_pathname(File file) {
    // attempt to replace home path with tilde in a user-pleasable way
    string path = file.get_parse_name();
    string home = Environment.get_home_dir();

    if (path == home)
        return "~";
    
    if (path.has_prefix(home))
        return "~%s".printf(path.substring(home.length));

    return path;
}

public string strip_pretty_path(string path) {
    if (!path.has_prefix("~"))
        return path;
    
    return Environment.get_home_dir() + path.substring(1);
}

public string? get_file_info_id(FileInfo info) {
    return info.get_attribute_string(FileAttribute.ID_FILE);
}

// Breaks a uint64 skip amount into several smaller skips.
public void skip_uint64(InputStream input, uint64 skip_amount) throws GLib.Error {
    while (skip_amount > 0) {
        // skip() throws an error if the amount is too large, so check against ssize_t.MAX
        if (skip_amount >= ssize_t.MAX) {
            input.skip(ssize_t.MAX);
            skip_amount -= ssize_t.MAX;
        } else {
            input.skip((size_t) skip_amount);
            skip_amount = 0;
        }
    }
}

// Returns the number of files (and/or directories) within a directory.
public uint64 count_files_in_directory(File dir) throws GLib.Error {
    if (!query_is_directory(dir))
        return 0;
    
    uint64 count = 0;
    FileEnumerator enumerator = dir.enumerate_children("standard::*",
        FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    
    FileInfo info = null;
    while ((info = enumerator.next_file()) != null)
        count++;
    
    return count;
}

// Replacement for deprecated Gio.file_equal
public bool file_equal(File? a, File? b) {
    return (a != null && b != null) ? a.equal(b) : false;
}

// Replacement for deprecated Gio.file_hash
public uint file_hash(File? file) {
    return file != null ? file.hash() : 0;
}

