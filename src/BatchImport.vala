/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class BatchImportJob {
    public abstract string get_identifier();
    
    public abstract bool prepare(out File file_to_import, out bool copy_to_library);
}

// BatchImport performs the work of taking a file (supplied by BatchImportJob's) and properly importing
// it into the system, including database additions, thumbnail creation, and reporting it to AppWindow
// so it's properly added to various views and events.
public class BatchImport {
    public const int IMPORT_DIRECTORY_DEPTH = 3;
    
    private class DateComparator : Comparator<Photo> {
        public override int64 compare(Photo photo_a, Photo photo_b) {
            return photo_a.get_exposure_time() - photo_b.get_exposure_time();
        }
    }
    
    public static File? create_library_path(string filename, Exif.Data? exif, time_t ts, 
        out bool collision) {
        File dir = AppWindow.get_photos_dir();
        time_t timestamp = ts;
        
        // use EXIF exposure timestamp over the supplied one (which probably comes from the file's
        // modified time, or is simply now())
        if (exif != null && !Exif.get_timestamp(exif, out timestamp)) {
            // if no exposure time supplied, use now()
            if (ts == 0)
                timestamp = time_t();
        }
        
        Time tm = Time.local(timestamp);
        
        // build a directory tree inside the library, as deep as IMPORT_DIRECTORY_DEPTH:
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

    private static ImportResult copy_file(File src, out File dest) {
        PhotoExif exif = new PhotoExif(src);
        time_t timestamp = 0;
        try {
            timestamp = query_file_modified(src);
        } catch (Error err) {
            critical("Unable to access file modification for %s: %s", src.get_path(), err.message);
        }

        bool collision;
        dest = create_library_path(src.get_basename(), exif.get_exif(), timestamp, out collision);
        if (dest == null)
            return ImportResult.FILE_ERROR;
        
        debug("Copying %s to %s", src.get_path(), dest.get_path());
        
        try {
            src.copy(dest, FileCopyFlags.ALL_METADATA, null, on_copy_progress);
        } catch (Error err) {
            critical("Unable to copy file %s to %s: %s", src.get_path(), dest.get_path(),
                err.message);
            
            return ImportResult.FILE_ERROR;
        }
        
        return ImportResult.SUCCESS;
    }
    
    private static void on_copy_progress(int64 current, int64 total) {
        spin_event_loop();
    }

    private static int get_test_variable(string name) {
        string value = Environment.get_variable(name);
        if (value == null || value.length == 0)
            return 0;
        
        return value.to_int();
    }
    
    private Gee.Iterable<BatchImportJob> jobs;
    private string name;
    private uint64 total_bytes;
    private BatchImport ref_holder = null;
    private SortedList<Photo> success = null;
    private Gee.ArrayList<string> failed = null;
    private Gee.ArrayList<string> skipped = null;
    private ImportID import_id = ImportID();
    private bool scheduled = false;
    private bool user_aborted = false;
    private int import_file_count = 0;
    
    // these are for debugging and testing only
    private int fail_every = 0;
    private int skip_every = 0;
    
    public BatchImport(Gee.Iterable<BatchImportJob> jobs, string name, uint64 total_bytes = 0) {
        this.jobs = jobs;
        this.name = name;
        this.total_bytes = total_bytes;
        this.fail_every = get_test_variable("SHOTWELL_FAIL_EVERY");
        this.skip_every = get_test_variable("SHOTWELL_SKIP_EVERY");
    }
    
    // Called once, when the schedule task begins
    public signal void starting();
    
    // Called for each Photo imported to the system
    public signal void imported(Photo photo);
    
    // Called when a job fails.  import_complete will also be called at the end of the batch
    public signal void import_job_failed(ImportResult result, BatchImportJob job, File? file);
    
    // Called at the end of the batched jobs; this will be signalled exactly once for the batch
    public signal void import_complete(ImportID import_id, SortedList<Photo> photos_by_date, 
        Gee.ArrayList<string> failed, Gee.ArrayList<string> skipped);

    public string get_name() {
        return name;
    }
    
    public uint64 get_total_bytes() {
        return total_bytes;
    }
    
    public void user_halt() {
        user_aborted = true;
    }

    public void schedule() {
        assert(!scheduled);
        
        // XXX: This is necessary because Idle.add doesn't ref SourceFunc:
        // http://bugzilla.gnome.org/show_bug.cgi?id=548427
        this.ref_holder = this;

        Idle.add(perform_import);
        scheduled = true;
    }

    private bool perform_import() {
        starting();
        
        success = new SortedList<Photo>(new DateComparator());
        failed = new Gee.ArrayList<string>();
        skipped = new Gee.ArrayList<string>();
        import_id = (new PhotoTable()).generate_import_id();

        foreach (BatchImportJob job in jobs) {
            if (AppWindow.has_user_quit())
                user_aborted = true;
                
            if (user_aborted) {
                import_job_failed(ImportResult.USER_ABORT, job, null);
                skipped.add(job.get_identifier());
                
                continue;
            }
            
            File file;
            bool copy_to_library;
            if (job.prepare(out file, out copy_to_library)) {
                import(job, file, copy_to_library, job.get_identifier());
            } else {
                import_job_failed(ImportResult.FILE_ERROR, job, null);
                failed.add(job.get_identifier());
            }
        }
        
        // report to AppWindow to organize into events
        if (success.size > 0)
            AppWindow.get_instance().batch_import_complete(success);
        
        // report completed
        import_complete(import_id, success, failed, skipped);

        // XXX: unref "this" ... vital that the self pointer is not touched from here on out
        ref_holder = null;
        
        return false;
    }

    private void import(BatchImportJob job, File file, bool copy_to_library, string id) {
        if (user_aborted) {
            skipped.add(id);
            
            return;
        }
        
        FileType type = file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        
        ImportResult result;
        switch (type) {
            case FileType.DIRECTORY:
                result = import_dir(job, file, copy_to_library);
            break;
            
            case FileType.REGULAR:
                result = import_file(file, copy_to_library);
            break;
            
            default:
                debug("Skipping file %s (neither a directory nor a file)", file.get_path());
                result = ImportResult.NOT_A_FILE;
            break;
        }
        
        switch (result) {
            case ImportResult.SUCCESS:
                // all is well, photo(s) added to success list
            break;
            
            case ImportResult.USER_ABORT:
                // no fall-through in Vala
                user_aborted = true;
                skipped.add(id);
                import_job_failed(result, job, file);
            break;

            case ImportResult.NOT_A_FILE:
            case ImportResult.PHOTO_EXISTS:
            case ImportResult.UNSUPPORTED_FORMAT:
                skipped.add(id);
                import_job_failed(result, job, file);
            break;
            
            default:
                failed.add(id);
                import_job_failed(result, job, file);
            break;
        }
    }
    
    private ImportResult import_dir(BatchImportJob job, File dir, bool copy_to_library) {
        try {
            FileEnumerator enumerator = dir.enumerate_children("*",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            if (enumerator == null)
                return ImportResult.FILE_ERROR;
            
            if (!spin_event_loop())
                return ImportResult.USER_ABORT;

            FileInfo info = null;
            while ((info = enumerator.next_file(null)) != null) {
                File child = dir.get_child(info.get_name());
                import(job, child, copy_to_library, child.get_uri());
            }
        } catch (Error err) {
            debug("Unable to import from %s: %s", dir.get_path(), err.message);
            
            return ImportResult.FILE_ERROR;
        }
        
        return ImportResult.SUCCESS;
    }
    
    private ImportResult import_file(File file, bool copy_to_library) {
        if (!spin_event_loop())
            return ImportResult.USER_ABORT;

        import_file_count++;
        if (fail_every > 0) {
            if (import_file_count % fail_every == 0)
                return ImportResult.FILE_ERROR;
        }
        
        if (skip_every > 0) {
            if (import_file_count % skip_every == 0)
                return ImportResult.NOT_A_FILE;
        }
        
        File import = file;
        
        // never copy file if already in library directory
        bool is_in_library_dir = file.has_prefix(AppWindow.get_photos_dir());
        
        if (copy_to_library && !is_in_library_dir) {
            File copied;
            ImportResult result = copy_file(file, out copied);
            if (result != ImportResult.SUCCESS)
                return result;
            
            debug("Copied %s into library at %s", file.get_path(), copied.get_path());
            
            import = copied;
        }
        
        Photo photo;
        ImportResult result = Photo.import(import, import_id, out photo);
        if (result != ImportResult.SUCCESS) {
            if (copy_to_library) {
                try {
                    import.delete(null);
                } catch (Error err) {
                    critical("Unable to delete copy of imported file %s: %s", import.get_path(),
                        err.message);
                }
            }

            return result;
        }
        
        success.add(photo);
        
        // report to AppWindow for system-wide inclusion
        AppWindow.get_instance().photo_imported(photo);

        // report to observers
        imported(photo);

        return ImportResult.SUCCESS;
    }
}

