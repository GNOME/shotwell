/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// A BatchImportJob describes a unit of work the BatchImport object should perform.  It returns
// a file to be imported.  If the file is a directory, it is automatically recursed by BatchImport
// to find all files that need to be imported into the library.
//
// NOTE: All methods may be called from the context of a background thread or the main GTK thread.
// Implementations should be able to handle either situation.  The prepare method will always be
// called by the same thread context.
public abstract class BatchImportJob {
    public abstract string get_identifier();
    
    public abstract bool is_directory();
    
    // Returns the file size of the BatchImportJob or returns a file/directory which can be queried
    // by BatchImportJob to determine it.  Returns true if the size is return, false if the File is
    // specified.
    // 
    // filesize should only be returned if BatchImportJob represents a single file.
    public abstract bool determine_file_size(out uint64 filesize, out File file_or_dir);
    
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
    public File? file;
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
        bool reported = true;
        switch (batch_result.result) {
            case ImportResult.SUCCESS:
                success.add(batch_result);
            break;

            case ImportResult.USER_ABORT:
                if (batch_result.file != null && !query_is_directory(batch_result.file))
                    aborted.add(batch_result);
                else
                    reported = false;
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
        
        if (reported)
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
public class BatchImport : Object {
    private static Workers sniff_worker = new Workers(1, false);
    private static Workers prep_worker = new Workers(1, false);
    private static Workers import_worker = new Workers(2, false);
    private static Workers thumbnail_worker = new Workers(1, false);
    
    private Gee.Iterable<BatchImportJob> jobs;
    private string name;
    private uint64 completed_bytes = 0;
    private uint64 total_bytes = 0;
    private ImportReporter reporter;
    private ImportManifest manifest;
    private bool scheduled = false;
    private bool completed = false;
    private int file_imports_to_perform = -1;
    private int file_imports_completed = 0;
    private Cancellable? cancellable = null;
    private ulong last_preparing_ms = 0;
    private ViewCollection generated_events = new ViewCollection("BatchImport generated events");
#if !NO_DUPE_DETECTION
    private Gee.HashSet<string> imported_thumbnail_md5 = new Gee.HashSet<string>();
    private Gee.HashSet<string> imported_full_md5 = new Gee.HashSet<string>();
#endif
    
    // These queues are staging queues, holding batches of work that must happen in the import
    // process, working on them all at once to minimize overhead.
    private uint64 ready_files_bytes = 0;
    private Gee.ArrayList<PreparedFile> ready_files = new Gee.ArrayList<PreparedFile>();
    private Gee.ArrayList<CompletedImportPhoto> ready_thumbnails =
        new Gee.ArrayList<CompletedImportPhoto>();
    private Gee.ArrayList<CompletedImportPhoto> display_imported_queue =
        new Gee.ArrayList<CompletedImportPhoto>();
    private Gee.ArrayList<LibraryPhoto> ready_photos = new Gee.ArrayList<LibraryPhoto>();
    
    // Called at the end of the batched jobs.  Can be used to report the result of the import
    // to the user.  This is called BEFORE import_complete is fired.
    public delegate void ImportReporter(ImportManifest manifest);
    
    // Called once, when the scheduled task begins
    public signal void starting();
    
    // Called repeatedly while preparing the launched BatchImport
    public signal void preparing();
    
    // Called repeatedly to report the progress of the BatchImport (but only called after the
    // last "preparing" signal)
    public signal void progress(uint64 completed_bytes, uint64 total_bytes);
    
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
        Gee.ArrayList<BatchImportJob>? prefailed = null,
        Gee.ArrayList<BatchImportJob>? pre_already_imported = null,
        Cancellable? cancellable = null) {
        this.jobs = jobs;
        this.name = name;
        this.reporter = reporter;
        this.manifest = new ImportManifest(prefailed, pre_already_imported);
        this.cancellable = (cancellable != null) ? cancellable : new Cancellable();
        
        // watch for user exit in the application
        AppWindow.get_instance().user_quit.connect(user_halt);
        
        // Use a timer to report imported photos to observers
        Timeout.add(200, display_imported_timer);
    }
    
    ~BatchImport() {
#if TRACE_DTORS
        debug("DTOR: BatchImport (%s)", name);
#endif
        AppWindow.get_instance().user_quit.disconnect(user_halt);
    }
    
    public string get_name() {
        return name;
    }
    
    public void user_halt() {
        cancellable.cancel();
    }
    
    private void log_status(string where) {
#if TRACE_IMPORT
        debug("%s: to_perform=%d completed=%d ready_files=%d ready_thumbnails=%d display_queue=%d ready_photos=%d",
            where, file_imports_to_perform, file_imports_completed, ready_files.size,
            ready_thumbnails.size, display_imported_queue.size, ready_photos.size);
#endif
    }
    
    private bool report_failure(BatchImportResult import_result) {
        bool proceed = true;
        
        manifest.add_result(import_result);
        
        if (import_result.result != ImportResult.SUCCESS) {
            import_job_failed(import_result);
            
            if (import_result.file != null && !import_result.result.is_abort()) {
                uint64 filesize = 0;
                try {
                    // A BatchImportResult file is guaranteed to be a single file
                    filesize = query_total_file_size(import_result.file);
                } catch (Error err) {
                    debug("Unable to query file size of %s: %s", import_result.file.get_path(),
                        err.message);
                }
                
                report_progress(filesize);
            }
        }
        
        // fire this signal only once, and only on non-user aborts
        if (import_result.result.is_nonuser_abort() && proceed) {
            fatal_error(import_result.result, import_result.errmsg);
            proceed = false;
        }
        
        return proceed;
    }
    
    private void report_progress(uint64 increment_of_progress) {
        completed_bytes += increment_of_progress;
        
        // only report "progress" if progress has been made (and enough time has progressed),
        // otherwise still preparing
        if (completed_bytes == 0) {
            ulong now = now_ms();
            if (now - last_preparing_ms > 250) {
                last_preparing_ms = now;
                preparing();
            }
        } else if (increment_of_progress > 0) {
            ulong now = now_ms();
            if (now - last_preparing_ms > 250) {
                last_preparing_ms = now;
                progress(completed_bytes, total_bytes);
            }
        }
    }
    
    private bool report_failures(BackgroundImportJob background_job) {
        bool proceed = true;
        
        foreach (BatchImportResult import_result in background_job.failed) {
            if (!report_failure(import_result))
                proceed = false;
        }
        
        return proceed;
    }
    
    private void report_completed(string where) {
        if (completed)
            error("Attempted to complete already-completed import: %s", where);
        
        completed = true;
        
        flush_ready_photos();
        
        log_status("Import completed: %s".printf(where));
        
        // report completed to the reporter (called prior to the "import_complete" signal)
        if (reporter != null)
            reporter(manifest);
        
        import_complete(manifest);
        
        // resume the MimicManager
        LibraryPhoto.mimic_manager.resume();
    }
    
    // This should be called whenever a file's import process is complete, successful or otherwise
    private void file_import_complete() {
        // mark this job as completed
        file_imports_completed++;
        if (file_imports_to_perform != -1)
            assert(file_imports_completed <= file_imports_to_perform);
        
        // because notifications can come in after completions, have to watch if this is the
        // last file
        if (file_imports_to_perform != -1 && file_imports_completed == file_imports_to_perform)
            report_completed("completed preparing files, all outstanding imports completed");
    }
    
    public void schedule() {
        assert(scheduled == false);
        scheduled = true;
        
        // halt the MimicManager will performing import, as it will drag the system down
        LibraryPhoto.mimic_manager.pause();
        
        starting();
        
        // fire off a background job to generate all FileToPrepare work
        sniff_worker.enqueue(new WorkSniffer(this, jobs, on_work_sniffed_out, cancellable,
            on_sniffer_cancelled, on_sniffer_working));
    }
    
    //
    // WorkSniffer stage
    //
    
    private void on_sniffer_working() {
        report_progress(0);
    }
    
    private void on_work_sniffed_out(BackgroundJob j) {
        assert(!completed);
        
        WorkSniffer sniffer = (WorkSniffer) j;
        
        if (!report_failures(sniffer) || sniffer.files_to_prepare.size == 0) {
            report_completed("work sniffed out: nothing to do");
            
            return;
        }
        
        total_bytes = sniffer.total_bytes;
        
        // submit single background job to go out and prepare all the files, reporting back when/if
        // they're ready for import; this is important because gPhoto can't handle multiple accesses
        // to a camera without fat locking, and it's just not worth it.  Serializing the imports
        // also means the user sees the photos coming in in (roughly) the order they selected them
        // on the screen
        PrepareFilesJob prepare_files_job = new PrepareFilesJob(this, sniffer.files_to_prepare, 
            on_file_prepared, on_files_prepared, cancellable, on_file_prepare_cancelled);
        
        prep_worker.enqueue(prepare_files_job);
    }
    
    private void on_sniffer_cancelled(BackgroundJob j) {
        assert(!completed);
        
        WorkSniffer sniffer = (WorkSniffer) j;
        
        report_failures(sniffer);
        report_completed("work sniffer cancelled");
    }
    
    //
    // PrepareFiles stage
    //
    
    // Note that this call can wind up completing the import if the user has cancelled the
    // operation.
    private void flush_ready_files() {
        if (ready_files.size == 0)
            return;
        
        if (cancellable.is_cancelled()) {
            foreach (PreparedFile prepared_file in ready_files) {
                report_failure(new BatchImportResult(prepared_file.job, prepared_file.file,
                    prepared_file.file.get_path(), ImportResult.USER_ABORT));
                file_import_complete();
            }
            
            ready_files.clear();
            
            return;
        }
        
        PreparedFilesImportJob job = new PreparedFilesImportJob(this, ready_files, manifest.import_id,
            on_import_files_completed, cancellable, on_import_files_cancelled);
        
        ready_files = new Gee.ArrayList<PreparedFile>();
        ready_files_bytes = 0;
        
        import_worker.enqueue(job);
    }
    
    private void enqueue_prepared_file(PreparedFile prepared_file) {
        ready_files.add(prepared_file);
        ready_files_bytes += prepared_file.filesize;
        
        // We want to cluster the work to give the background thread plenty to do, but not
        // cluster so many the UI is starved of completion notices ... these comparisons
        // strive for the happy medium
        if (ready_files.size > 25 || ready_files_bytes > (50 * (1024 * 1024)) || cancellable.is_cancelled())
            flush_ready_files();
    }
    
    // This checks for duplicates in the current import batch, which may not already be in the
    // library and therefore not detected there.
    private bool is_in_current_import(PreparedFile prepared_file) {
#if !NO_DUPE_DETECTION
        if (prepared_file.thumbnail_md5 != null
            && imported_thumbnail_md5.contains(prepared_file.thumbnail_md5)) {
            debug("Not importing %s: thumbnail match detected in import set",
                prepared_file.file.get_path());
            
            return true;
        }
        
        if (prepared_file.full_md5 != null
            && imported_full_md5.contains(prepared_file.full_md5)) {
            debug("Not importing %s: full match detected in import set",
                prepared_file.file.get_path());
            
            return true;
        }
        
        // add for next one
        if (prepared_file.thumbnail_md5 != null)
            imported_thumbnail_md5.add(prepared_file.thumbnail_md5);
        
        if (prepared_file.full_md5 != null)
            imported_full_md5.add(prepared_file.full_md5);
#endif
        return false;
    }
    
    // Called when a cluster of files are located and deemed proper for import by PrepareFiledJob
    private void on_file_prepared(BackgroundJob j, NotificationObject? user) {
        assert(!completed);
        
        PreparedFileCluster cluster = (PreparedFileCluster) user;
        
        foreach (PreparedFile prepared_file in cluster.list) {
            BatchImportResult import_result = null;
            
            if (TransformablePhoto.is_duplicate(prepared_file.file, prepared_file.thumbnail_md5,
                prepared_file.full_md5, prepared_file.file_format)) {
                // If a file is being linked and has a dupe in the trash, we take it out of the trash
                // and revert its edits.
                if (!prepared_file.copy_to_library) {
                    LibraryPhoto photo = LibraryPhoto.global.get_trashed_by_file(prepared_file.file);
                    
                    if (photo != null) {
                        debug("duplicate linked photo found in trash, untrashing and removing" + 
                            " transforms for %s", prepared_file.file.get_path());
                        
                        photo.untrash();
                        photo.remove_all_transformations();
                        
                        import_result = new BatchImportResult(prepared_file.job, prepared_file.file,
                            prepared_file.file.get_path(), ImportResult.SUCCESS);
                        
                        report_progress(photo.get_filesize());
                        file_import_complete();
                        
                        continue;
                    }
                }
                
                // Photos with duplicates that exist outside of the trash are marked as already existing
                if (LibraryPhoto.has_nontrash_duplicate(prepared_file.file,
                    prepared_file.thumbnail_md5, prepared_file.full_md5, prepared_file.file_format)) {
                    debug("duplicate photo detected outside of trash, not importing %s",
                        prepared_file.file.get_path());
                    
                    import_result = new BatchImportResult(prepared_file.job, prepared_file.file, 
                        prepared_file.file.get_path(), ImportResult.PHOTO_EXISTS);
                }
                
                if (import_result == null) {
                    debug("duplicate photos found in trash only, importing as usual for %s",
                        prepared_file.file.get_path());
                }
            } else if (is_in_current_import(prepared_file)) {
                // this looks for duplicates within the import set, since TransformablePhoto.is_duplicate
                // only looks within already-imported photos for dupes
                import_result = new BatchImportResult(prepared_file.job, prepared_file.file,
                    prepared_file.file.get_path(), ImportResult.PHOTO_EXISTS);
            }
            
            if (import_result != null) {
                report_failure(import_result);
                file_import_complete();
                
                continue;
            }
            
            report_progress(0);
            
            enqueue_prepared_file(prepared_file);
        }
        
        // if the number of file imports is known, this notification has come in after the completion
        // callback, so flush the queue
        if (file_imports_to_perform != -1)
            flush_ready_files();
    }
    
    private void done_preparing_files(BackgroundJob j, string caller) {
        assert(!completed);
        
        PrepareFilesJob prepare_files_job = (PrepareFilesJob) j;
        
        report_failures(prepare_files_job);
        
        // mark this job as completed and record how many file imports must finish to be complete
        file_imports_to_perform = prepare_files_job.prepared_files;
        assert(file_imports_to_perform >= file_imports_completed);
        
        log_status(caller);
        
        // this call can result in report_completed() being called, so don't call twice
        flush_ready_files();
        
        // if none prepared, then none outstanding (or will become outstanding, depending on how
        // the notifications are queued)
        if (file_imports_to_perform == 0 && !completed)
            report_completed("no files prepared for import");
        else if (file_imports_completed == file_imports_to_perform && !completed)
            report_completed("completed preparing files, all outstanding imports completed");
    }
    
    private void on_files_prepared(BackgroundJob j) {
        done_preparing_files(j, "on_files_prepared");
    }
    
    private void on_file_prepare_cancelled(BackgroundJob j) {
        done_preparing_files(j, "on_file_prepare_cancelled");
    }
    
    //
    // Files ready for import stage
    //
    
    private void flush_ready_thumbnails() {
        if (ready_thumbnails.size == 0)
            return;
        
        ThumbnailWriterJob job = new ThumbnailWriterJob(this, ready_thumbnails,
            on_thumbnail_writer_completed, cancellable, on_thumbnail_writer_cancelled);
        
        ready_thumbnails = new Gee.ArrayList<CompletedImportPhoto>();
        
        thumbnail_worker.enqueue(job);
    }
    
    private void enqueue_ready_thumbnail(LibraryPhoto photo, Thumbnails thumbnails,
        BatchImportResult import_result) {
        ready_thumbnails.add(new CompletedImportPhoto(photo, thumbnails, import_result));
    }
    
    private void on_import_files_completed(BackgroundJob j) {
        assert(!completed);
        
        PreparedFilesImportJob job = (PreparedFilesImportJob) j;
        
        log_status("on_import_files_completed (%d files)".printf(job.failed.size + job.ready.size));
        
        // all should be ready in some form
        assert(job.not_ready.size == 0);
        
        // mark failed photos
        foreach (BatchImportResult result in job.failed) {
            assert(result.result != ImportResult.SUCCESS);
            
            report_failure(result);
            file_import_complete();
        }
        
        // import ready photos into database
        foreach (ReadyForImport ready in job.ready) {
            assert(ready.batch_result.result == ImportResult.SUCCESS);
            
            LibraryPhoto photo = null;
            ready.batch_result.result = LibraryPhoto.import_create(ready.import_params, out photo);
            
            if (ready.batch_result.result != ImportResult.SUCCESS) {
                debug("on_import_file_completed: %s", ready.batch_result.result.to_string());
                
                report_failure(ready.batch_result);
                file_import_complete();
            } else {
                enqueue_ready_thumbnail(photo, ready.import_params.thumbnails, ready.batch_result);
            }
        }
        
        if (ready_thumbnails.size > 10 || ready_files.size == 0)
            flush_ready_thumbnails();
    }
    
    private void on_import_files_cancelled(BackgroundJob j) {
        assert(!completed);
        
        PreparedFilesImportJob job = (PreparedFilesImportJob) j;
        
        log_status("on_import_files_cancelled");
        
        foreach (PreparedFile prepared_file in job.not_ready) {
            report_failure(new BatchImportResult(prepared_file.job, prepared_file.file,
                prepared_file.file.get_path(), ImportResult.USER_ABORT));
            file_import_complete();
        }
        
        foreach (BatchImportResult result in job.failed) {
            report_failure(result);
            file_import_complete();
        }
        
        foreach (ReadyForImport ready in job.ready) {
            BatchImportResult result = ready.abort();
            report_failure(result);
            file_import_complete();
        }
        
        flush_ready_thumbnails();
    }
    
    //
    // ThumbnailWriter stage
    //
    
    private void on_thumbnail_writer_completed(BackgroundJob j) {
        assert(!completed);
        
        ThumbnailWriterJob job = (ThumbnailWriterJob) j;
        
        log_status("on_thumbnail_writer_completed");
        
        foreach (CompletedImportPhoto completed in job.completed_import_photos) {
            if (completed.batch_result.result != ImportResult.SUCCESS) {
                warning("Failed to import %s: unable to write thumbnails (%s)",
                    completed.photo.to_string(), completed.batch_result.result.to_string());
                
                LibraryPhoto.import_failed(completed.photo);
                
                report_failure(completed.batch_result);
                file_import_complete();
            } else {
                manifest.imported.add(completed.photo);
                manifest.add_result(completed.batch_result);
                
                display_imported_queue.add(completed);
            }
        }
    }
    
    private void on_thumbnail_writer_cancelled(BackgroundJob j) {
        assert(!completed);
        
        ThumbnailWriterJob job = (ThumbnailWriterJob) j;
        
        log_status("on_thumbnail_writer_cancelled");
        
        foreach (CompletedImportPhoto completed in job.completed_import_photos) {
            report_failure(completed.batch_result);
            file_import_complete();
        }
    }
    
    //
    // Display imported photos and integrate into system
    //
    
    private void flush_ready_photos() {
        if (ready_photos.size == 0)
            return;
        
        log_status("flush_ready_photos");
        
        LibraryPhoto.global.add_many(ready_photos);
        
        foreach (LibraryPhoto photo in ready_photos)
            Event.generate_import_event(photo, generated_events);
        
        ready_photos.clear();
    }
    
    // This is called throughout the import process to notify watchers of imported photos in such
    // a way that the GTK event queue gets a chance to operate.
    private bool display_imported_timer() {
        if (display_imported_queue.size == 0) {
            if (completed)
                debug("display_imported_timer exiting");
            return !completed;
        }
        
        if (cancellable.is_cancelled())
            debug("Importing %d photos at once", display_imported_queue.size);
        
        log_status("display_imported_timer");
        
        // if cancelled, do them all at once, to speed up reporting completion
        do {
            CompletedImportPhoto completed = display_imported_queue.remove_at(0);
            
            // Stage the number of ready photos to incorporate into the system rather than doing them
            // one at a time, to keep the UI thread responsive.
            ready_photos.add(completed.photo);
            
            imported(completed.photo, completed.thumbnails.get(ThumbnailCache.Size.LARGEST));
            report_progress(completed.photo.get_filesize());
            file_import_complete();
        } while (cancellable.is_cancelled() && display_imported_queue.size > 0);
        
        if (ready_photos.size > 25 || cancellable.is_cancelled())
            flush_ready_photos();
        
        return true;
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
    
    protected BackgroundImportJob(BatchImport owner, CompletionCallback callback,
        Cancellable cancellable, CancellationCallback? cancellation) {
        base (owner, callback, cancellable, cancellation);
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
        
        // if fatal but the flag is not set, set it now
        if (result.is_abort())
            abort(result);
        else
            debug("Import failure %s: %s", identifier, result.to_string());
        
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
    public uint64 total_bytes = 0;
    
    private Gee.Iterable<BatchImportJob> jobs;
    private NotificationCallback working_notification;
    
    public WorkSniffer(BatchImport owner, Gee.Iterable<BatchImportJob> jobs, CompletionCallback callback, 
        Cancellable cancellable, CancellationCallback cancellation, 
        NotificationCallback working_notification) {
        base (owner, callback, cancellable, cancellation);
        
        this.jobs = jobs;
        this.working_notification = working_notification;
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
            
            if (is_cancelled())
                break;
        }
    }
    
    private void sniff_job(BatchImportJob job) throws Error {
        uint64 size;
        File file_or_dir;
        bool determined_size = job.determine_file_size(out size, out file_or_dir);
        if (determined_size)
            total_bytes += size;
        
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
            // if did not get the file size, do so now
            if (!determined_size)
                total_bytes += query_total_file_size(file_or_dir, get_cancellable());
            
            // job is a direct file, so no need to search, prepare it directly
            files_to_prepare.add(new FileToPrepare(job));
            notify(working_notification, null);
        }
    }
    
    public void search_dir(BatchImportJob job, File dir, bool copy_to_library) throws Error {
        FileEnumerator enumerator = dir.enumerate_children("standard::*",
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        
        FileInfo info = null;
        while ((info = enumerator.next_file(get_cancellable())) != null) {
            // next_file() doesn't always respect the cancellable
            if (is_cancelled())
                break;
            
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
                total_bytes += info.get_size();
                files_to_prepare.add(new FileToPrepare(job, child, copy_to_library));
                notify(working_notification, null);
            } else {
                warning("Ignoring import of %s file type %d", child.get_path(), (int) file_type);
            }
        }
    }
}

private class PreparedFile {
    public BatchImportJob job;
    public ImportResult result;
    public File file;
    public string id;
    public bool copy_to_library;
    public string? exif_md5;
    public string? thumbnail_md5;
    public string? full_md5;
    public PhotoFileFormat file_format;
    public uint64 filesize;
    
    public PreparedFile(BatchImportJob job, File file, string id, bool copy_to_library, string? exif_md5, 
        string? thumbnail_md5, string? full_md5, PhotoFileFormat file_format, uint64 filesize) {
        this.job = job;
        this.result = ImportResult.SUCCESS;
        this.file = file;
        this.id = id;
        this.copy_to_library = copy_to_library;
        this.exif_md5 = exif_md5;
        this.thumbnail_md5 = thumbnail_md5;
        this.full_md5 = full_md5;
        this.file_format = file_format;
        this.filesize = filesize;
    }
}

private class PreparedFileCluster : NotificationObject {
    public Gee.ArrayList<PreparedFile> list;
    
    public PreparedFileCluster(Gee.ArrayList<PreparedFile> list) {
        this.list = list;
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
    
    public PrepareFilesJob(BatchImport owner, Gee.List<FileToPrepare> files_to_prepare,
        NotificationCallback notification, CompletionCallback callback, Cancellable cancellable,
        CancellationCallback cancellation) {
        base (owner, callback, cancellable, cancellation);
        
        this.files_to_prepare = files_to_prepare;
        this.notification = notification;
        library_dir = AppDirs.get_import_dir();
        fail_every = get_test_variable("SHOTWELL_FAIL_EVERY");
        skip_every = get_test_variable("SHOTWELL_SKIP_EVERY");
    }
    
    private static int get_test_variable(string name) {
        string value = Environment.get_variable(name);
        
        return (value == null || value.length == 0) ? 0 : value.to_int();
    }
    
    private override void execute() {
        Timer timer = new Timer();
        
        Gee.ArrayList<PreparedFile> list = new Gee.ArrayList<PreparedFile>();
        foreach (FileToPrepare file_to_prepare in files_to_prepare) {
            ImportResult result = abort_check();
            if (result != ImportResult.SUCCESS) {
                report_failure(file_to_prepare.job, null, file_to_prepare.job.get_identifier(),
                    result);
                
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
                PreparedFile prepared_file;
                result = prepare_file(job, file, copy_to_library, out prepared_file);
                if (result == ImportResult.SUCCESS) {
                    prepared_files++;
                    list.add(prepared_file);
                } else {
                    report_failure(job, file, file.get_path(), result);
                }
            } catch (Error err) {
                report_error(job, file, file.get_path(), err, ImportResult.FILE_ERROR);
            }
            
            if (list.size > 100 || (timer.elapsed() > 0.5 && list.size > 0)) {
                debug("Dumping %d prepared files", list.size);
                PreparedFileCluster cluster = new PreparedFileCluster(list);
                list = new Gee.ArrayList<PreparedFile>();
                notify(notification, cluster);
                timer.start();
            }
        }
        
        if (list.size > 0) {
            ImportResult result = abort_check();
            if (result == ImportResult.SUCCESS) {
                notify(notification, new PreparedFileCluster(list));
            } else {
                // subtract these, as they are not being submitted
                assert(prepared_files >= list.size);
                prepared_files -= list.size;
                
                foreach (PreparedFile prepared_file in list) {
                    report_failure(prepared_file.job, prepared_file.file, prepared_file.file.get_path(),
                        result);
                }
            }
        }
    }
    
    private ImportResult prepare_file(BatchImportJob job, File file, bool copy_to_library,
        out PreparedFile prepared_file) throws Error {
        if (!TransformablePhoto.is_file_image(file))
            return ImportResult.NOT_AN_IMAGE;

        if (!TransformablePhoto.is_file_supported(file))
            return ImportResult.UNSUPPORTED_FORMAT;
        
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
        
        // attempt to detect the file format by its extension
        PhotoFileFormat file_format = PhotoFileFormat.get_by_file_extension(file);
        if (file_format == PhotoFileFormat.UNKNOWN) {
            warning("Skipping %s: unrecognized file extension", file.get_path());
            
            return ImportResult.UNSUPPORTED_FORMAT;
        }
        
        string exif_only_md5 = null;
        string thumbnail_md5 = null;
        string full_md5 = null;
        
        // duplicate detection: If EXIF data present, look for a match with either EXIF itself
        // or the thumbnail.  If not, do a full MD5.
        PhotoFileReader reader = file_format.create_reader(file.get_path());
        PhotoMetadata? metadata = reader.read_metadata();
        if (metadata != null) {
            uint8[]? flattened_sans_thumbnail = metadata.flatten_exif(false);
            if (flattened_sans_thumbnail != null && flattened_sans_thumbnail.length > 0)
                exif_only_md5 = md5_binary(flattened_sans_thumbnail, flattened_sans_thumbnail.length);
            
            uint8[]? flattened_thumbnail = metadata.flatten_exif_preview();
            if (flattened_thumbnail != null && flattened_thumbnail.length > 0)
                thumbnail_md5 = md5_binary(flattened_thumbnail, flattened_thumbnail.length);
        }
        
        // If no EXIF or thumbnail MD5, then do full MD5 match ... it's possible for
        // photos to have identical EXIF, hence the thumbnail should be the giveaway, but only
        // if present (which can only be true if EXIF is present)
        if (exif_only_md5 == null || thumbnail_md5 == null) {
            try {
                full_md5 = md5_file(file);
            } catch (Error err) {
                warning("Unable to perform MD5 checksum on %s: %s", file.get_path(), err.message);
            }
        }
        
#if TRACE_MD5
        debug("import MD5 %s: exif=%s preview=%s full=%s", file.get_basename(), exif_only_md5,
            thumbnail_md5, full_md5);
#endif
        
        uint64 filesize = query_total_file_size(file, get_cancellable());
        
        // never copy file if already in library directory
        bool is_in_library_dir = file.has_prefix(library_dir);
        
        // notify the BatchImport this is ready to go
        prepared_file = new PreparedFile(job, file, file.get_path(), 
            copy_to_library && !is_in_library_dir, exif_only_md5, thumbnail_md5, full_md5,
            file_format, filesize);
        
        return ImportResult.SUCCESS;
    }
}

private class ReadyForImport {
    public File final_file;
    public PreparedFile prepared_file;
    public PhotoImportParams import_params;
    public BatchImportResult batch_result;
    
    public ReadyForImport(File final_file, PreparedFile prepared_file, PhotoImportParams import_params,
        BatchImportResult batch_result) {
        this.final_file = final_file;
        this.prepared_file = prepared_file;
        this.import_params = import_params;
        this.batch_result = batch_result;
    }
    
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

private class PreparedFilesImportJob : BackgroundJob {
    public Gee.ArrayList<PreparedFile> not_ready = new Gee.ArrayList<PreparedFile>();
    public Gee.ArrayList<ReadyForImport> ready = new Gee.ArrayList<ReadyForImport>();
    public Gee.ArrayList<BatchImportResult> failed = new Gee.ArrayList<BatchImportResult>();
    
    private ImportID import_id;
    private PhotoImportParams photo_import_params = null;
    
    public PreparedFilesImportJob(BatchImport owner, Gee.Collection<PreparedFile> prepared_files,
        ImportID import_id, CompletionCallback callback, Cancellable cancellable,
        CancellationCallback cancellation) {
        base (owner, callback, cancellable, cancellation);
        
        this.import_id = import_id;
        not_ready.add_all(prepared_files);
    }
    
    private override void execute() {
        while (not_ready.size > 0) {
            PreparedFile prepared_file = not_ready.remove_at(0);
            process_prepared_file(prepared_file);
        }
    }
    
    private void process_prepared_file(PreparedFile prepared_file) {
        BatchImportResult batch_result = null;
        
        File final_file = prepared_file.file;
        if (prepared_file.copy_to_library) {
            try {
                final_file = LibraryFiles.duplicate(prepared_file.file, null);
                if (final_file == null) {
                    batch_result = new BatchImportResult(prepared_file.job, prepared_file.file,
                        prepared_file.id, ImportResult.FILE_ERROR);
                    
                    failed.add(batch_result);
                    
                    return;
                }
            } catch (Error err) {
                batch_result = new BatchImportResult.from_error(prepared_file.job, prepared_file.file,
                    prepared_file.id, err, ImportResult.FILE_ERROR);
                
                failed.add(batch_result);
                
                return;
            }
        }
        
        photo_import_params = new PhotoImportParams(final_file, import_id, PhotoFileSniffer.Options.GET_ALL,
            prepared_file.exif_md5, prepared_file.thumbnail_md5, prepared_file.full_md5, new Thumbnails());
        
        ImportResult result = TransformablePhoto.prepare_for_import(photo_import_params);
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
        
        batch_result = new BatchImportResult(prepared_file.job, final_file, prepared_file.id, result);
        if (batch_result.result != ImportResult.SUCCESS)
            failed.add(batch_result);
        else
            ready.add(new ReadyForImport(final_file, prepared_file, photo_import_params, batch_result));
    }
}

private class CompletedImportPhoto {
    public LibraryPhoto photo;
    public Thumbnails thumbnails;
    public BatchImportResult batch_result;
    
    public CompletedImportPhoto(LibraryPhoto photo, Thumbnails thumbnails, BatchImportResult batch_result) {
        this.photo = photo;
        this.thumbnails = thumbnails;
        this.batch_result = batch_result;
    }
}

private class ThumbnailWriterJob : BackgroundImportJob {
    public Gee.Collection<CompletedImportPhoto> completed_import_photos;
    
    public ThumbnailWriterJob(BatchImport owner, Gee.Collection<CompletedImportPhoto> completed_import_photos,
        CompletionCallback callback, Cancellable cancellable, CancellationCallback cancel_callback) {
        base (owner, callback, cancellable, cancel_callback);
        
        this.completed_import_photos = completed_import_photos;
    }
    
    public override void execute() {
        foreach (CompletedImportPhoto completed in completed_import_photos) {
            try {
                ThumbnailCache.import_thumbnails(completed.photo, completed.thumbnails, true);
                completed.batch_result.result = ImportResult.SUCCESS;
            } catch (Error err) {
                completed.batch_result.result = ImportResult.convert_error(err, ImportResult.FILE_ERROR);
            }
        }
    }
}

