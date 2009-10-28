/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// A BatchImportJob describes a unit of work the BatchImport object should perform.  It returns
// a file to be imported.  If the file is a directory, it is automatically recursed by BatchImport
// to find all files that need to be imported into the library.
public abstract class BatchImportJob {
    public abstract string get_identifier();
    
    public abstract bool prepare(out File file_to_import, out bool copy_to_library);
}

// A BatchImportResult associates a particular job with a File that an import was performed on
// and the import result.  A BatchImportJob can specify multiple files, so there is not necessarily
// a one-to-one relationship beteen it and this object.
//
// Note that job may be null (in the case of a pre-failed job that must be reported) and file may
// be null (for similar reasons).
public class BatchImportResult {
    public BatchImportJob job;
    public File file;
    public string identifier;
    public ImportResult result;
    
    public BatchImportResult(BatchImportJob job, File? file, string identifier, ImportResult result) {
        this.job = job;
        this.file = file;
        this.identifier = identifier;
        this.result = result;
    }
}

public class ImportManifest {
    public ImportID import_id = ImportID();
    public uint64 total_imported_bytes = 0;
    public Gee.List<LibraryPhoto> imported = new Gee.ArrayList<LibraryPhoto>();
    public Gee.List<BatchImportResult> success = new Gee.ArrayList<BatchImportResult>();
    public Gee.List<BatchImportResult> failed = new Gee.ArrayList<BatchImportResult>();
    public Gee.List<BatchImportResult> skipped = new Gee.ArrayList<BatchImportResult>();
    public Gee.List<BatchImportResult> aborted = new Gee.ArrayList<BatchImportResult>();
    public Gee.List<BatchImportResult> already_imported = new Gee.ArrayList<BatchImportResult>();
    public Gee.List<BatchImportResult> all = new Gee.ArrayList<BatchImportResult>();
    
    public ImportManifest(Gee.List<BatchImportJob>? prefailed = null, Gee.List<BatchImportJob>? pre_already_imported = null) {
        this.import_id = PhotoTable.get_instance().generate_import_id();
        
        if (prefailed != null) {
            foreach (BatchImportJob job in prefailed) {
                BatchImportResult batch_result = new BatchImportResult(job, null, job.get_identifier(), 
                    ImportResult.FILE_ERROR);
                add_result(batch_result);
            }
        }
        
        if (pre_already_imported != null) {
            foreach (BatchImportJob job in pre_already_imported) {
                BatchImportResult batch_result = new BatchImportResult(job, null, job.get_identifier(),
                    ImportResult.PHOTO_EXISTS);
                add_result(batch_result);
            }
        }
    }
    
    public void add_result(BatchImportResult batch_result) {
        switch (batch_result.result) {
            case ImportResult.SUCCESS:
                success.add(batch_result);
            break;
            
            case ImportResult.USER_ABORT:
                aborted.add(batch_result);
            break;

            case ImportResult.NOT_A_FILE:
            case ImportResult.UNSUPPORTED_FORMAT:
                skipped.add(batch_result);
            break;
            
            case ImportResult.PHOTO_EXISTS:
                already_imported.add(batch_result);
            break;
            
            default:
                failed.add(batch_result);
            break;
        }
        
        all.add(batch_result);
    }
}

// BatchImport performs the work of taking a file (supplied by BatchImportJob's) and properly importing
// it into the system, including database additions and thumbnail creation.  It can be monitored by
// multiple observers, but only one ImportReporter can be registered.
public class BatchImport {
    public const int IMPORT_DIRECTORY_DEPTH = 3;
    
    private Gee.Iterable<BatchImportJob> jobs;
    private string name;
    private uint64 total_bytes;
    private ImportReporter reporter;
    private ImportManifest manifest;
    private BatchImport ref_holder = null;
    private bool scheduled = false;
    private bool user_aborted = false;
    private int import_file_count = 0;
    
    // these are for debugging and testing only
    private int fail_every = 0;
    private int skip_every = 0;
    
    // Called at the end of the batched jobs.  Can be used to report the result of the import
    // to the user.  This is called BEFORE import_complete is fired.
    public delegate void ImportReporter(ImportManifest manifest);
    
    // Called once, when the schedule task begins
    public signal void starting();
    
    // Called for each Photo imported to the system
    public signal void imported(LibraryPhoto photo);
    
    // Called when a job fails.  import_complete will also be called at the end of the batch
    public signal void import_job_failed(BatchImportResult result);
    
    // Called at the end of the batched jobs; this will be signalled exactly once for the batch
    public signal void import_complete(ImportManifest manifest);

    public BatchImport(Gee.Iterable<BatchImportJob> jobs, string name, ImportReporter? reporter,
        uint64 total_bytes = 0, Gee.ArrayList<BatchImportJob>? prefailed = null, 
        Gee.ArrayList<BatchImportJob>? pre_already_imported = null) {
        this.jobs = jobs;
        this.name = name;
        this.reporter = reporter;
        this.total_bytes = total_bytes;
        this.manifest = new ImportManifest(prefailed, pre_already_imported);
        this.fail_every = get_test_variable("SHOTWELL_FAIL_EVERY");
        this.skip_every = get_test_variable("SHOTWELL_SKIP_EVERY");
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
    
    private void job_result(BatchImportJob job, File? file, string identifier, ImportResult result) {
        BatchImportResult batch_result = new BatchImportResult(job, file, identifier, result);
        manifest.add_result(batch_result);
        
        if (result == ImportResult.USER_ABORT)
            user_aborted = true;
        
        if (result != ImportResult.SUCCESS)
            import_job_failed(batch_result);
    }

    private bool perform_import() {
        starting();
        
        foreach (BatchImportJob job in jobs) {
            if (AppWindow.has_user_quit())
                user_aborted = true;
                
            if (user_aborted) {
                job_result(job, null, job.get_identifier(), ImportResult.USER_ABORT);
                
                continue;
            }
            
            File file;
            bool copy_to_library;
            if (job.prepare(out file, out copy_to_library))
                import(job, file, copy_to_library, job.get_identifier());
            else
                job_result(job, null, job.get_identifier(), ImportResult.FILE_ERROR);
        }
        
        // report completed
        if (reporter != null)
            reporter(manifest);
        
        import_complete(manifest);

        // XXX: unref "this" ... vital that the self pointer is not touched from here on out
        ref_holder = null;
        
        return false;
    }

    private void import(BatchImportJob job, File file, bool copy_to_library, string id) {
        if (user_aborted) {
            job_result(job, file, id, ImportResult.USER_ABORT);
            
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
        
        job_result(job, file, id, result);
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
        
        // test case (can be set with SHOTWELL_FAIL_EVERY environment variable)
        if (fail_every > 0) {
            if (import_file_count % fail_every == 0)
                return ImportResult.FILE_ERROR;
        }
        
        // test case (can be set with SHOTWELL_SKIP_EVERY environment variable)
        if (skip_every > 0) {
            if (import_file_count % skip_every == 0)
                return ImportResult.NOT_A_FILE;
        }
        
#if !NO_DUPE_DETECTION
        // duplicate detection: If EXIF data present, look for a match with either EXIF itself
        // or the thumbnail
        PhotoExif photo_exif = new PhotoExif(file);
        if (photo_exif.has_exif()) {
            // get EXIF and thumbnail fingerprints
            string exif_md5 = photo_exif.get_md5();
            string thumbnail_md5 = photo_exif.get_thumbnail_md5();
            
            // look for matches
            bool exif_matched = (exif_md5 != null) ? PhotoTable.get_instance().has_exif_md5(exif_md5) 
                : false;
            bool thumbnail_matched = (thumbnail_md5 != null) 
                ? PhotoTable.get_instance().has_thumbnail_md5(exif_md5) : false;
            
            debug("MD5 of %s: EXIF=%s (%d) thumbnail=%s (%d)", file.get_path(), exif_md5, 
                (int) exif_matched, thumbnail_md5, (int) thumbnail_matched);
            
            // either one will do
            if (exif_matched || thumbnail_matched)
                return ImportResult.PHOTO_EXISTS;
        } else {
            // if no EXIF data, then do full MD5 match
            string full_md5 = null;
            try {
                full_md5 = md5_file(file);
                debug("Full MD5 checksum of %s: %s", file.get_path(), full_md5);
            } catch (Error err) {
                warning("Unable to perform MD5 checksum on %s: %s", file.get_path(), err.message);
            }
            
            if (full_md5 != null && PhotoTable.get_instance().has_full_md5(full_md5))
                return ImportResult.PHOTO_EXISTS;
        }
#endif
        
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
        
        LibraryPhoto photo;
        ImportResult result = LibraryPhoto.import(import, manifest.import_id, out photo);
        if (result != ImportResult.SUCCESS) {
            // if file was copied, delete the copy
            if (import != file) {
                debug("Deleting failed imported copy %s", import.get_path());
                try {
                    import.delete(null);
                } catch (Error err) {
                    critical("Unable to delete copy of imported file %s: %s", import.get_path(),
                        err.message);
                }
            }

            return result;
        }
        
        // add LibraryPhoto to manifest (BatchImportResult is added elsewhere)
        manifest.imported.add(photo);
        
        // report to observers
        imported(photo);

        return ImportResult.SUCCESS;
    }
}

