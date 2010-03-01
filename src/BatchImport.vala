/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// A BatchImportJob describes a unit of work the BatchImport object should perform.  It returns
// a file to be imported.  If the file is a directory, it is automatically recursed by BatchImport
// to find all files that need to be imported into the library.
//
// NOTE: Both methods may be called from the context of a background thread or the main GTK thread.
// Implementations should be able to handle either situation.  The prepare method will always be
// called by the same thread context.
public abstract class BatchImportJob {
    public abstract string get_identifier();
    
    public abstract bool is_directory();
    
    public abstract bool prepare(out File file_to_import, out bool copy_to_library) throws Error;
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
    public string? errmsg = null;
    
    public BatchImportResult(BatchImportJob job, File? file, string identifier, ImportResult result) {
        this.job = job;
        this.file = file;
        this.identifier = identifier;
        this.result = result;
    }
    
    public BatchImportResult.from_error(BatchImportJob job, File? file, string identifier,
        Error err, ImportResult default_result) {
        this.job = job;
        this.file = file;
        this.identifier = identifier;
        this.result = ImportResult.convert_error(err, default_result);
        this.errmsg = err.message;
    }
}

public class ImportManifest {
    public ImportID import_id = ImportID();
    public uint64 total_imported_bytes = 0;
    public Gee.List<LibraryPhoto> imported = new Gee.ArrayList<LibraryPhoto>();
    public Gee.List<BatchImportResult> success = new Gee.ArrayList<BatchImportResult>();
    public Gee.List<BatchImportResult> camera_failed = new Gee.ArrayList<BatchImportResult>();
    public Gee.List<BatchImportResult> failed = new Gee.ArrayList<BatchImportResult>();
    public Gee.List<BatchImportResult> skipped_photos = new Gee.ArrayList<BatchImportResult>();
    public Gee.List<BatchImportResult> skipped_files = new Gee.ArrayList<BatchImportResult>();
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
                if (!query_is_directory(batch_result.file))
                    aborted.add(batch_result);
            break;

            case ImportResult.UNSUPPORTED_FORMAT:
                skipped_photos.add(batch_result);
            break;

            case ImportResult.NOT_A_FILE:
            case ImportResult.NOT_AN_IMAGE:
                skipped_files.add(batch_result);
            break;
            
            case ImportResult.PHOTO_EXISTS:
                already_imported.add(batch_result);
            break;
            
            case ImportResult.CAMERA_ERROR:
                camera_failed.add(batch_result);
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
//
// TODO: With background threads. the better way to implement this is via a FSM (finite state 
// machine) that exists in states and responds to various events thrown off by the background
// jobs.  However, getting this code to a point that it works with threads is task enough, so it
// will have to wait (especially since we'll want to write a generic FSM engine).
public class BatchImport {
    private static Workers workers = new Workers(2, false);
    
    private Gee.Iterable<BatchImportJob> jobs;
    private string name;
    private uint64 total_bytes;
    private ImportReporter reporter;
    private ImportManifest manifest;
    private bool scheduled = false;
    private bool completed = false;
    private int file_imports_to_perform = -1;
    private int file_imports_completed = 0;
    private Cancellable? cancellable = null;
    
    // Called at the end of the batched jobs.  Can be used to report the result of the import
    // to the user.  This is called BEFORE import_complete is fired.
    public delegate void ImportReporter(ImportManifest manifest);
    
    // Called once, when the scheduled task begins
    public signal void starting();
    
    // Called for each Photo imported to the system.  The pixbuf is screen-sized and rotated.
    public signal void imported(LibraryPhoto photo, Gdk.Pixbuf pixbuf);
    
    // Called when a fatal error occurs that stops the import entirely.  Remaining jobs will be
    // failed and import_complete() is still fired.
    public signal void fatal_error(ImportResult result, string message);
    
    // Called when a job fails.  import_complete will also be called at the end of the batch
    public signal void import_job_failed(BatchImportResult result);
    
    // Called at the end of the batched jobs; this will be signalled exactly once for the batch
    public signal void import_complete(ImportManifest manifest);

    public BatchImport(Gee.Iterable<BatchImportJob> jobs, string name, ImportReporter? reporter,
        uint64 total_bytes = 0, Gee.ArrayList<BatchImportJob>? prefailed = null, 
        Gee.ArrayList<BatchImportJob>? pre_already_imported = null,
        Cancellable? cancellable = null) {
        this.jobs = jobs;
        this.name = name;
        this.reporter = reporter;
        this.total_bytes = total_bytes;
        this.manifest = new ImportManifest(prefailed, pre_already_imported);
        this.cancellable = (cancellable != null) ? cancellable : new Cancellable();
        
        // watch for user exit in the application
        AppWindow.get_instance().user_quit += user_halt;
    }
    
    ~BatchImport() {
        AppWindow.get_instance().user_quit -= user_halt;
    }
    
    public string get_name() {
        return name;
    }
    
    public uint64 get_total_bytes() {
        return total_bytes;
    }
    
    public void user_halt() {
        cancellable.cancel();
    }
    
    private bool report_failures(BackgroundImportJob background_job) {
        bool proceed = true;
        
        foreach (BatchImportResult import_result in background_job.failed) {
            manifest.add_result(import_result);
            
            if (import_result.result != ImportResult.SUCCESS)
                import_job_failed(import_result);
            
            // fire this signal only once, and only on non-user aborts
            if (import_result.result.is_nonuser_abort() && proceed) {
                fatal_error(import_result.result, import_result.errmsg);
                proceed = false;
            }
        }
        
        return proceed;
    }
    
    private void report_completed(string where) {
        if (completed)
            error("Attempted to complete already-completed import: %s", where);
        
        completed = true;
        
        debug("Import completed: %s", where);
        
        // report completed to the reporter (called prior to the "import_complete" signal)
        if (reporter != null)
            reporter(manifest);
        
        import_complete(manifest);
    }
    
    public void schedule() {
        assert(scheduled == false);
        scheduled = true;
        
        starting();
        
        // fire off a background job to generate all FileToPrepare work
        workers.enqueue(new WorkSniffer(jobs, on_work_sniffed_out, cancellable, on_sniffer_cancelled));
    }
    
    private void on_work_sniffed_out(BackgroundJob j) {
        WorkSniffer sniffer = (WorkSniffer) j;
        
        if (!report_failures(sniffer) || sniffer.files_to_prepare.size == 0) {
            report_completed("work sniffed out: nothing to do");
            
            return;
        }
        
        // submit single background job to go out and prepare all the files, reporting back when/if
        // they're ready for import; this is important because gPhoto can't handle multiple accesses
        // to a camera without fat locking, and it's just not worth it.  Serializing the imports
        // also means the user sees the photos coming in in (roughly) the order they selected them on the
        // screen
        PrepareFilesJob prepare_files_job = new PrepareFilesJob(sniffer.files_to_prepare, 
            on_file_prepared, on_files_prepared, cancellable, on_file_prepare_cancelled);
        
        workers.enqueue(prepare_files_job);
    }
    
    private void on_sniffer_cancelled(BackgroundJob j) {
        WorkSniffer sniffer = (WorkSniffer) j;
        
        report_failures(sniffer);
        report_completed("work sniffer cancelled");
    }
    
    private void on_file_prepared(BackgroundJob j, NotificationObject user) {
        PreparedFile prepared_file = (PreparedFile) user;
        
        if (TransformablePhoto.is_duplicate(prepared_file.file, prepared_file.exif_md5,
            prepared_file.thumbnail_md5, prepared_file.full_md5)) {
            manifest.add_result(new BatchImportResult(prepared_file.job, prepared_file.file, 
                prepared_file.file.get_path(), ImportResult.PHOTO_EXISTS));
            
            // mark this job as completed
            file_imports_completed++;
            
            // because notifications can come in after completion, have to watch if this is the
            // last file
            if (file_imports_to_perform != -1 && file_imports_completed == file_imports_to_perform)
                report_completed("completed preparing files, all outstanding imports completed");
            
            return;
        }
        
        FileImportJob file_import_job = new FileImportJob(prepared_file, manifest.import_id, 
            on_import_file_completed, cancellable, on_import_file_cancelled);
        
        workers.enqueue(file_import_job);
    }
    
    private void on_files_prepared(BackgroundJob j) {
        PrepareFilesJob prepare_files_job = (PrepareFilesJob) j;
        
        report_failures(prepare_files_job);
        
        // mark this job as completed and record how many file imports must finish to be complete
        file_imports_to_perform = prepare_files_job.prepared_files;
        
        // if none prepared, then none outstanding (or will become outstanding, depending on how
        // the notifications are queued)
        if (file_imports_to_perform == 0)
            report_completed("no files prepared for import");
        else if (file_imports_completed == file_imports_to_perform)
            report_completed("completed preparing files, all outstanding imports completed");
    }
    
    private void on_file_prepare_cancelled(BackgroundJob j) {
        PrepareFilesJob prepare_files_job = (PrepareFilesJob) j;
        
        report_failures(prepare_files_job);
        
        file_imports_to_perform = prepare_files_job.prepared_files;
        
        // If FileImportJobs are outstanding, need to wait for them to cancel as well ... see
        // on_files_prepared for the logic of all this
        if (file_imports_to_perform == 0)
            report_completed("cancelled, no files prepared");
        else if (file_imports_completed == file_imports_to_perform)
            report_completed("cancelled, all outstanding imports completed");
    }
    
    private void on_import_file_completed(BackgroundJob j) {
        FileImportJob job = (FileImportJob) j;
        
        file_imports_completed++;
        
        // if success, import photo into database and in-memory data structures
        LibraryPhoto photo = null;
        if (job.batch_result.result == ImportResult.SUCCESS)
            job.batch_result.result = LibraryPhoto.import(ref job.photo_row, job.thumbnails, out photo);
        
        if (job.batch_result.result == ImportResult.SUCCESS) {
            manifest.imported.add(photo);
            imported(photo, job.pixbuf);
        } else {
            // the utter shame of it all
            debug("Failed to import %s: %s (%s)", job.get_filename(),
                job.batch_result.result.to_string(), job.batch_result.errmsg);
            import_job_failed(job.batch_result);
        }
        
        manifest.add_result(job.batch_result);
        
        // if no more outstanding jobs and the PrepareFilesJob is completed, report the BatchImport
        // as completed
        if (file_imports_to_perform != -1 && file_imports_completed == file_imports_to_perform)
            report_completed("all files prepared, all import jobs completed");
    }
    
    private void on_import_file_cancelled(BackgroundJob j) {
        FileImportJob job = (FileImportJob) j;
        
        file_imports_completed++;
        
        job.abort();
        
        import_job_failed(job.batch_result);
        manifest.add_result(job.batch_result);
        
        // see on_import_file_completed for logic
        if (file_imports_to_perform != -1 && file_imports_completed == file_imports_to_perform)
            report_completed("cancelled, all import jobs completed");
    }
}

//
// The order of the background jobs is important, both for how feedback is presented to the user
// and to protect certain subsystems which don't work well in a multithreaded situation (i.e.
// gPhoto).
//
// 1. WorkSniffer builds a list of all the work to do.  If the BatchImportJob is a file, there's
// not much more to do.  If it represents a directory, the directory is traversed, with more work
// generated for each file.  Very little processing is done here on each file, however, and the
// BatchImportJob.prepare is only called when a directory.
//
// 2. PrepareFilesJob walks the list WorkSniffer generated, preparing each file and examining it
// for any obvious problems.  This in turn generates a list of prepared files (i.e. downloaded from
// camera).
//
// 3. Each file ready for importing is a separate background job.  It is responsible for copying
// the file (if required), examining it, and generating a pixbuf for preview and thumbnails.
//

private abstract class BackgroundImportJob : BackgroundJob {
    public ImportResult abort_flag = ImportResult.SUCCESS;
    public Gee.List<BatchImportResult> failed = new Gee.ArrayList<BatchImportResult>();
    
    protected BackgroundImportJob(CompletionCallback callback, Cancellable cancellable,
        CancellationCallback? cancellation) {
        base (callback, cancellable, cancellation);
    }
    
    // Subclasses should call this every iteration, and if the result is not SUCCESS, consider the
    // operation (and therefore all after) aborted
    protected ImportResult abort_check() {
        if (abort_flag == ImportResult.SUCCESS && is_cancelled())
            abort_flag = ImportResult.USER_ABORT;
        
        return abort_flag;
    }
    
    protected void abort(ImportResult result) {
        // only update the abort flag if not already set
        if (abort_flag == ImportResult.SUCCESS)
            abort_flag = result;
    }
    
    protected void report_failure(BatchImportJob job, File? file, string identifier, 
        ImportResult result) {
        assert(result != ImportResult.SUCCESS);
        
        debug("Import failure %s: %s", identifier, result.to_string());
        
        // if fatal but the flag is not set, set it now
        if (result.is_abort())
            abort(result);
        
        failed.add(new BatchImportResult(job, file, identifier, result));
    }
    
    protected void report_error(BatchImportJob job, File? file, string identifier,
        Error err, ImportResult default_result) {
        ImportResult result = ImportResult.convert_error(err, default_result);
        
        debug("Import error %s: %s (%s)", identifier, err.message, result.to_string());
        
        if (result.is_abort())
            abort(result);
        
        failed.add(new BatchImportResult.from_error(job, file, identifier, err, default_result));
    }
}

private class FileToPrepare {
    public BatchImportJob job;
    public File? file;
    public bool copy_to_library;
    
    public FileToPrepare(BatchImportJob job, File? file = null, bool copy_to_library = true) {
        this.job = job;
        this.file = file;
        this.copy_to_library = copy_to_library;
    }
}

private class WorkSniffer : BackgroundImportJob {
    public Gee.List<FileToPrepare> files_to_prepare = new Gee.ArrayList<FileToPrepare>();
    
    private Gee.Iterable<BatchImportJob> jobs;
    
    public WorkSniffer(Gee.Iterable<BatchImportJob> jobs, CompletionCallback callback, 
        Cancellable cancellable, CancellationCallback cancellation) {
        base (callback, cancellable, cancellation);
        
        this.jobs = jobs;
    }
    
    public override void execute() {
        // walk the list of jobs accumulating work for the background jobs; if submitted job
        // is a directory, recurse into the directory picking up files to import (also creating
        // work for the background jobs)
        foreach (BatchImportJob job in jobs) {
            ImportResult result = abort_check();
            if (result != ImportResult.SUCCESS) {
                report_failure(job, null, job.get_identifier(), result);
                
                continue;
            }
            
            try {
                sniff_job(job);
            } catch (Error err) {
                report_error(job, null, job.get_identifier(), err, ImportResult.FILE_ERROR);
            }
        }
    }
    
    private void sniff_job(BatchImportJob job) throws Error {
        if (job.is_directory()) {
            // safe to call job.prepare without it invoking extra I/O; this is merely a directory
            // to search
            File dir;
            bool copy_to_library;
            if (!job.prepare(out dir, out copy_to_library)) {
                report_failure(job, null, job.get_identifier(), ImportResult.FILE_ERROR);
                
                return;
            }
            assert(query_is_directory(dir));
            
            try {
                search_dir(job, dir, copy_to_library);
            } catch (Error err) {
                report_error(job, dir, dir.get_path(), err, ImportResult.FILE_ERROR);
            }
        } else {
            // job is a direct file, so no need to search, prepare it directly
            files_to_prepare.add(new FileToPrepare(job));
        }
    }
    
    public void search_dir(BatchImportJob job, File dir, bool copy_to_library) throws Error {
        FileEnumerator enumerator = dir.enumerate_children("standard::*",
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        
        FileInfo info = null;
        while ((info = enumerator.next_file(null)) != null) {
            File child = dir.get_child(info.get_name());
            FileType file_type = info.get_file_type();
            
            if (file_type == FileType.DIRECTORY) {
                if (info.get_name().has_prefix("."))
                    continue;

                try {
                    search_dir(job, child, copy_to_library);
                } catch (Error err) {
                    report_error(job, child, child.get_path(), err, ImportResult.FILE_ERROR);
                }
            } else if (file_type == FileType.REGULAR) {
                files_to_prepare.add(new FileToPrepare(job, child, copy_to_library));
            } else {
                warning("Ignoring import of %s file type %d", child.get_path(), (int) file_type);
            }
        }
    }
}

private class PreparedFile : NotificationObject {
    public BatchImportJob job;
    public ImportResult result;
    public File file;
    public string id;
    public bool copy_to_library;
    public string? exif_md5;
    public string? thumbnail_md5;
    public string? full_md5;
    
    public PreparedFile(BatchImportJob job, File file, string id, bool copy_to_library, string? exif_md5, 
        string? thumbnail_md5, string? full_md5) {
        this.job = job;
        this.result = ImportResult.SUCCESS;
        this.file = file;
        this.id = id;
        this.copy_to_library = copy_to_library;
        this.exif_md5 = exif_md5;
        this.thumbnail_md5 = thumbnail_md5;
        this.full_md5 = full_md5;
    }
}

private class PrepareFilesJob : BackgroundImportJob {
    // Do not examine until the CompletionCallback has been called.
    public int prepared_files = 0;
    
    private Gee.List<FileToPrepare> files_to_prepare;
    private NotificationCallback notification;
    private File library_dir;
    
    // these are for debugging and testing only
    private int import_file_count = 0;
    private int fail_every = 0;
    private int skip_every = 0;
    
    public PrepareFilesJob(Gee.List<FileToPrepare> files_to_prepare, NotificationCallback notification,
        CompletionCallback callback, Cancellable cancellable, CancellationCallback cancellation) {
        base (callback, cancellable, cancellation);
        
        this.files_to_prepare = files_to_prepare;
        this.notification = notification;
        library_dir = AppDirs.get_photos_dir();
        fail_every = get_test_variable("SHOTWELL_FAIL_EVERY");
        skip_every = get_test_variable("SHOTWELL_SKIP_EVERY");
    }
    
    private static int get_test_variable(string name) {
        string value = Environment.get_variable(name);
        
        return (value == null || value.length == 0) ? 0 : value.to_int();
    }
    
    private override void execute() {
        foreach (FileToPrepare file_to_prepare in files_to_prepare) {
            ImportResult result = abort_check();
            if (result != ImportResult.SUCCESS) {
                report_failure(file_to_prepare.job, null, file_to_prepare.job.get_identifier(), result);
                
                continue;
            }
            
            BatchImportJob job = file_to_prepare.job;
            File? file = file_to_prepare.file;
            bool copy_to_library = file_to_prepare.copy_to_library;
            
            // if no file seen, then it needs to be offered/generated by the BatchImportJob
            if (file == null) {
                try {
                    if (!job.prepare(out file, out copy_to_library)) {
                        report_failure(job, null, job.get_identifier(), ImportResult.FILE_ERROR);
                        
                        continue;
                    }
                } catch (Error err) {
                    report_error(job, null, job.get_identifier(), err, ImportResult.FILE_ERROR);
                    
                    continue;
                }
            }
            
            try {
                result = prepare_file(job, file, copy_to_library);
                if (result != ImportResult.SUCCESS)
                    report_failure(job, file, file.get_path(), result);
            } catch (Error err) {
                report_error(job, file, file.get_path(), err, ImportResult.FILE_ERROR);
            }
        }
    }
    
    private ImportResult prepare_file(BatchImportJob job, File file, bool copy_to_library) throws Error {
        if (!TransformablePhoto.is_file_image(file)) {
            message("Not importing %s: Not an image file", file.get_path());
            
            return ImportResult.NOT_AN_IMAGE;
        }

        if (!TransformablePhoto.is_file_supported(file)) {
            message("Not importing %s: Unsupported extension", file.get_path());
            
            return ImportResult.UNSUPPORTED_FORMAT;
        }
        
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
        
        string exif_md5 = null;
        string thumbnail_md5 = null;
        string full_md5 = null;
        
        // duplicate detection: If EXIF data present, look for a match with either EXIF itself
        // or the thumbnail.  If not, do a full MD5.
        PhotoExif photo_exif = new PhotoExif(file);
        try {
            photo_exif.load();
        } catch (Error err) {
            photo_exif = null;
        }
        
        if (photo_exif != null) {
            // get EXIF and thumbnail fingerprints
            exif_md5 = photo_exif.get_md5();
            thumbnail_md5 = photo_exif.get_thumbnail_md5();
        } else {
            // if no EXIF data, then do full MD5 match
            try {
                full_md5 = md5_file(file);
            } catch (Error err) {
                warning("Unable to perform MD5 checksum on %s: %s", file.get_path(), err.message);
            }
        }
        
        // never copy file if already in library directory
        bool is_in_library_dir = file.has_prefix(library_dir);
        
        // notify the BatchImport this is ready to go
        prepared_files++;
        notify(notification, new PreparedFile(job, file, file.get_path(), 
            copy_to_library && !is_in_library_dir, exif_md5, thumbnail_md5, full_md5));
        
        return ImportResult.SUCCESS;
    }
}

private class FileImportJob : BackgroundJob {
    public BatchImportResult batch_result = null;
    public PhotoRow photo_row = PhotoRow();
    public Gdk.Pixbuf pixbuf = null;
    public Thumbnails thumbnails = null;
    
    private PreparedFile prepared_file;
    private ImportID import_id;
    private File final_file = null;
    
    public FileImportJob(PreparedFile prepared_file, ImportID import_id, CompletionCallback callback,
        Cancellable cancellable, CancellationCallback cancellation) {
        base (callback, cancellable, cancellation);
        
        this.import_id = import_id;
        this.prepared_file = prepared_file;
    }
    
    // Not thread-safe.  Only call after CompletionCallback executed.
    public string get_filename() {
        return (final_file != null) ? final_file.get_path() : prepared_file.file.get_path();
    }
    
    private override void execute() {
        BatchImportJob job = prepared_file.job;
        final_file = prepared_file.file;
        
        if (prepared_file.copy_to_library) {
            try {
                final_file = LibraryFiles.duplicate(prepared_file.file, null);
                if (final_file == null) {
                    batch_result = new BatchImportResult(job, prepared_file.file, prepared_file.id,
                        ImportResult.FILE_ERROR);
                    
                    return;
                }
            } catch (Error err) {
                batch_result = new BatchImportResult.from_error(job, prepared_file.file, prepared_file.id,
                    err, ImportResult.FILE_ERROR);
                
                return;
            }
        }
        
        PhotoFileInterrogator interrogator = new PhotoFileInterrogator(final_file,
            PhotoFileInterrogator.Options.GET_ALL, Scaling.for_screen(AppWindow.get_instance(), false));
        thumbnails = new Thumbnails();
        
        ImportResult result = TransformablePhoto.prepare_for_import(final_file, import_id,
            interrogator, out photo_row, out pixbuf, thumbnails);
        if (result != ImportResult.SUCCESS && final_file != prepared_file.file) {
            debug("Deleting failed imported copy %s", final_file.get_path());
            try {
                final_file.delete(null);
            } catch (Error err) {
                // don't let this file error cause a failure
                warning("Unable to delete copy of imported file %s: %s", final_file.get_path(),
                    err.message);
            }
        }
        
        batch_result = new BatchImportResult(job, final_file, prepared_file.id, result);
    }
    
    // Not thread-safe.  Call only after CompletionCallback invoked.
    public BatchImportResult abort() {
        // if file copied, delete it
        if (final_file != null && final_file != prepared_file.file) {
            debug("Deleting aborted import copy %s", final_file.get_path());
            try {
                final_file.delete(null);
            } catch (Error err) {
                warning("Unable to delete copy of imported file (aborted import) %s: %s",
                    final_file.get_path(), err.message);
            }
        }
        
        batch_result = new BatchImportResult(prepared_file.job, prepared_file.file, prepared_file.id,
            ImportResult.USER_ABORT);
        
        return batch_result;
    }
}

