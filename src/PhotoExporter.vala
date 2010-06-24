/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class PhotoExporter : Object {
    public enum Overwrite {
        YES,
        NO,
        CANCEL,
        REPLACE_ALL
    }
    
    public delegate void CompletionCallback(PhotoExporter exporter);
    
    public delegate Overwrite OverwriteCallback(PhotoExporter exporter, File file);
    
    public delegate bool ExportFailedCallback(PhotoExporter exporter, File file, int remaining, 
        Error err);
    
    private class ExportJob : BackgroundJob {
        public Photo photo;
        public File dest;
        public Scaling scaling;
        public Jpeg.Quality quality;
        public PhotoFileFormat format;
        public Error? err = null;
        
        public ExportJob(PhotoExporter owner, Photo photo, File dest, Scaling scaling, 
            Jpeg.Quality quality, PhotoFileFormat format, Cancellable? cancellable) {
            base (owner, owner.on_exported, cancellable);
            
            this.photo = photo;
            this.dest = dest;
            this.scaling = scaling;
            this.quality = quality;
            this.format = format;
        }
        
        public override void execute() {
            try {
                photo.export(dest, scaling, quality, format);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private Gee.Collection<Photo> photos = new Gee.ArrayList<Photo>();
    private File dir;
    private Scaling scaling;
    private Jpeg.Quality quality;
    private PhotoFileFormat file_format;
    private int completed_count = 0;
    private Workers workers = new Workers(Workers.threads_per_cpu(), false);
    private CompletionCallback? completion_callback = null;
    private ExportFailedCallback? error_callback = null;
    private OverwriteCallback? overwrite_callback = null;
    private ProgressMonitor? monitor = null;
    private Cancellable? cancellable = null;
    private bool replace_all = false;
    private bool aborted = false;
    
    public PhotoExporter(Gee.Collection<Photo> photos, File dir, Scaling scaling, Jpeg.Quality quality, 
        PhotoFileFormat file_format) {
        this.photos.add_all(photos);
        this.dir = dir;
        this.scaling = scaling;
        this.quality = quality;
        this.file_format = file_format;
    }
    
    // This should be called only once; the object does not reset its internal state when completed.
    public void export(CompletionCallback completion_callback, ExportFailedCallback error_callback,
        OverwriteCallback overwrite_callback, Cancellable? cancellable, ProgressMonitor? monitor) {
        this.completion_callback = completion_callback;
        this.error_callback = error_callback;
        this.overwrite_callback = overwrite_callback;
        this.monitor = monitor;
        this.cancellable = cancellable;
        
        if (!process_queue())
            export_completed();
    }
    
    private void on_exported(BackgroundJob j) {
        ExportJob job = (ExportJob) j;
        
        completed_count++;
        
        // because the monitor spins the event loop, and so it's possible this function will be
        // re-entered, decide now if this is the last job
        bool completed = completed_count == photos.size;
        
        if (!aborted && job.err != null) {
            if (!error_callback(this, job.dest, photos.size - completed_count, job.err)) {
                aborted = true;
                
                if (!completed)
                    return;
            }
        }
        
        if (!aborted && monitor != null) {
            if (!monitor(completed_count, photos.size)) {
                aborted = true;
                
                if (!completed)
                    return;
            }
        }
        
        if (completed)
            export_completed();
    }
    
    private bool process_queue() {
        int submitted = 0;
        foreach (Photo photo in photos) {
            string basename = photo.get_export_basename(file_format);
            File dest = dir.get_child(basename);
            
            if (!replace_all && dest.query_exists(null)) {
                switch (overwrite_callback(this, dest)) {
                    case Overwrite.YES:
                        // continue
                    break;
                    
                    case Overwrite.REPLACE_ALL:
                        replace_all = true;
                    break;
                    
                    case Overwrite.CANCEL:
                        if (cancellable != null)
                            cancellable.cancel();
                        
                        return false;
                    
                    case Overwrite.NO:
                    default:
                        if (monitor != null) {
                            if (!monitor(++completed_count, photos.size))
                                return false;
                        }
                        
                        continue;
                }
            }
            
            ExportJob job = new ExportJob(this, photo, dest, scaling, quality, file_format, 
                cancellable);
            workers.enqueue(job);
            submitted++;
        }
        
        return submitted > 0;
    }
    
    private void export_completed() {
        completion_callback(this);
    }
}

public class PhotoExporterUI {
    private PhotoExporter exporter;
    private Cancellable cancellable = new Cancellable();
    private ProgressDialog? progress_dialog = null;
    private PhotoExporter.CompletionCallback? completion_callback = null;
    
    public PhotoExporterUI(PhotoExporter exporter) {
        this.exporter = exporter;
    }
    
    public void export(PhotoExporter.CompletionCallback completion_callback) {
        this.completion_callback = completion_callback;
        
        AppWindow.get_instance().set_busy_cursor();
        
        progress_dialog = new ProgressDialog(AppWindow.get_instance(), _("Exporting"), cancellable);
        exporter.export(on_export_completed, on_export_failed, on_export_overwrite, cancellable,
            progress_dialog.monitor);
    }
    
    private void on_export_completed(PhotoExporter exporter) {
        if (progress_dialog != null) {
            progress_dialog.close();
            progress_dialog = null;
        }
        
        AppWindow.get_instance().set_normal_cursor();
        
        completion_callback(exporter);
    }
    
    private PhotoExporter.Overwrite on_export_overwrite(PhotoExporter exporter, File file) {
        string question = _("File %s already exists.  Replace?").printf(file.get_basename());
        Gtk.ResponseType response = AppWindow.negate_affirm_all_cancel_question(question, 
            _("_Skip"), _("_Replace"), _("Replace _All"), _("Export Photos"));
        
        switch (response) {
            case Gtk.ResponseType.APPLY:
                return PhotoExporter.Overwrite.REPLACE_ALL;
            
            case Gtk.ResponseType.YES:
                return PhotoExporter.Overwrite.YES;
            
            case Gtk.ResponseType.CANCEL:
                return PhotoExporter.Overwrite.CANCEL;
            
            case Gtk.ResponseType.NO:
            default:
                return PhotoExporter.Overwrite.NO;
        }
    }
    
    private bool on_export_failed(PhotoExporter exporter, File file, int remaining, Error err) {
        return export_error_dialog(file, remaining > 0) != Gtk.ResponseType.CANCEL;
    }
}

