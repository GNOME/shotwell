/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum ExportFormatMode {
    UNMODIFIED,
    CURRENT,
    SPECIFIED, /* use an explicitly specified format like PNG or JPEG */
    LAST       /* use whatever format was used in the previous export operation */
}

public struct ExportFormatParameters {
    public ExportFormatMode mode;
    public PhotoFileFormat specified_format;
    public Jpeg.Quality quality;
    public bool export_metadata;
    
    private ExportFormatParameters(ExportFormatMode mode, PhotoFileFormat specified_format,
        Jpeg.Quality quality) {
        this.mode = mode;
        this.specified_format = specified_format;
        this.quality = quality;
        this.export_metadata = true;
    }
    
    public static ExportFormatParameters current() {
        return ExportFormatParameters(ExportFormatMode.CURRENT,
            PhotoFileFormat.get_system_default_format(), Jpeg.Quality.HIGH);
    }
       
    public static ExportFormatParameters unmodified() {
        return ExportFormatParameters(ExportFormatMode.UNMODIFIED,
            PhotoFileFormat.get_system_default_format(), Jpeg.Quality.HIGH);
    }
    
    public static ExportFormatParameters for_format(PhotoFileFormat format) {
        return ExportFormatParameters(ExportFormatMode.SPECIFIED, format, Jpeg.Quality.HIGH);
    }
    
    public static ExportFormatParameters last() {
        return ExportFormatParameters(ExportFormatMode.LAST,
            PhotoFileFormat.get_system_default_format(), Jpeg.Quality.HIGH);
    }
    
    public static ExportFormatParameters for_JPEG(Jpeg.Quality quality) {
        return ExportFormatParameters(ExportFormatMode.SPECIFIED, PhotoFileFormat.JFIF,
            quality);
    }
}

public class Exporter : Object {
    public enum Overwrite {
        YES,
        NO,
        CANCEL,
        REPLACE_ALL
    }
    
    public delegate void CompletionCallback(Exporter exporter, bool is_cancelled);
    
    public delegate Overwrite OverwriteCallback(Exporter exporter, File file);
    
    public delegate bool ExportFailedCallback(Exporter exporter, File file, int remaining, 
        Error err);
    
    private class ExportJob : BackgroundJob {
        public MediaSource media;
        public File dest;
        public Scaling? scaling;
        public Jpeg.Quality? quality;
        public PhotoFileFormat? format;
        public Error? err = null;
        public bool direct_copy_unmodified = false;
        public bool export_metadata = true;
        
        public ExportJob(Exporter owner, MediaSource media, File dest, Scaling? scaling, 
            Jpeg.Quality? quality, PhotoFileFormat? format, Cancellable cancellable,
            bool direct_copy_unmodified = false, bool export_metadata = true) {
            base (owner, owner.on_exported, cancellable, owner.on_export_cancelled);
            
            assert(media is Photo || media is Video);
            
            this.media = media;
            this.dest = dest;
            this.scaling = scaling;
            this.quality = quality;
            this.format = format;
            this.direct_copy_unmodified = direct_copy_unmodified;
            this.export_metadata = export_metadata;
        }

        public override void execute() {
            try {
                if (media is Photo) {
                    ((Photo) media).export(dest, scaling, quality, format, direct_copy_unmodified, export_metadata);
                } else if (media is Video) {
                    ((Video) media).export(dest);
                }
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private Gee.Collection<MediaSource> to_export = new Gee.ArrayList<MediaSource>();
    private File[] exported_files;
    private File? dir;
    private Scaling scaling;
    private int completed_count = 0;
    private Workers workers = new Workers(Workers.threads_per_cpu(1, 4), false);
    private unowned CompletionCallback? completion_callback = null;
    private unowned ExportFailedCallback? error_callback = null;
    private unowned OverwriteCallback? overwrite_callback = null;
    private unowned ProgressMonitor? monitor = null;
    private Cancellable cancellable;
    private bool replace_all = false;
    private bool aborted = false;
    private ExportFormatParameters export_params;

    public Exporter(Gee.Collection<MediaSource> to_export, File? dir, Scaling scaling,
        ExportFormatParameters export_params, bool auto_replace_all = false) {
        this.to_export.add_all(to_export);
        this.dir = dir;
        this.scaling = scaling;
        this.export_params = export_params;
        this.replace_all = auto_replace_all;
    }
       
    public Exporter.for_temp_file(Gee.Collection<MediaSource> to_export, Scaling scaling,
        ExportFormatParameters export_params) {
        this.to_export.add_all(to_export);
        this.dir = null;
        this.scaling = scaling;
        this.export_params = export_params;
    }

    // This should be called only once; the object does not reset its internal state when completed.
    public void export(CompletionCallback completion_callback, ExportFailedCallback error_callback,
        OverwriteCallback overwrite_callback, Cancellable? cancellable, ProgressMonitor? monitor) {
        this.completion_callback = completion_callback;
        this.error_callback = error_callback;
        this.overwrite_callback = overwrite_callback;
        this.monitor = monitor;
        this.cancellable = cancellable ?? new Cancellable();
        
        if (!process_queue())
            export_completed(true);
    }
    
    private void on_exported(BackgroundJob j) {
        ExportJob job = (ExportJob) j;
        
        completed_count++;
        
        // because the monitor spins the event loop, and so it's possible this function will be
        // re-entered, decide now if this is the last job
        bool completed = completed_count == to_export.size;
        
        if (!aborted && job.err != null) {
            if (!error_callback(this, job.dest, to_export.size - completed_count, job.err)) {
                aborted = true;
                
                if (!completed)
                    return;
            }
        }
        
        if (!aborted && monitor != null) {
            if (!monitor(completed_count, to_export.size, false)) {
                aborted = true;
                
                if (!completed)
                    return;
            } else {
                exported_files += job.dest;
            }
        }
        
        if (completed)
            export_completed(false);
    }
    
    private void on_export_cancelled(BackgroundJob j) {
        if (++completed_count == to_export.size)
            export_completed(true);
    }
    
    public File[] get_exported_files() {
        return exported_files;
    }
    
    private bool process_queue() {
        int submitted = 0;
        foreach (MediaSource source in to_export) {
            File? use_source_file = null;
            PhotoFileFormat real_export_format = PhotoFileFormat.get_system_default_format();
            string? basename = null;
            if (source is Photo) {
                Photo photo = (Photo) source;
                real_export_format = photo.get_export_format_for_parameters(export_params);
                basename = photo.get_export_basename_for_parameters(export_params);
            } else if (source is Video) {
                basename = ((Video) source).get_basename();
            }
            assert(basename != null);
            
            if (use_source_file != null) {
                exported_files += use_source_file;
                
                completed_count++;
                if (monitor != null) {
                    if (!monitor(completed_count, to_export.size)) {
                        cancellable.cancel();
                        
                        return false;
                    }
                }
                
                continue;
            }
            
            File? export_dir = dir;
            File? dest = null;
            
            if (export_dir == null) {
                try {
                    bool collision;
                    dest = generate_unique_file(AppDirs.get_temp_dir(), basename, out collision);
                } catch (Error err) {
                    AppWindow.error_message(_("Unable to generate a temporary file for %s: %s").printf(
                        source.get_file().get_basename(), err.message));
                    
                    break;
                }
            } else {
                dest = dir.get_child(basename);
                
                if (!replace_all && dest.query_exists(null)) {
                    switch (overwrite_callback(this, dest)) {
                        case Overwrite.YES:
                            // continue
                        break;
                        
                        case Overwrite.REPLACE_ALL:
                            replace_all = true;
                        break;
                        
                        case Overwrite.CANCEL:
                            cancellable.cancel();
                            
                            return false;
                        
                        case Overwrite.NO:
                        default:
                            completed_count++;
                            if (monitor != null) {
                                if (!monitor(completed_count, to_export.size)) {
                                    cancellable.cancel();
                                    
                                    return false;
                                }
                            }
                            
                            continue;
                    }
                }
            }

            workers.enqueue(new ExportJob(this, source, dest, scaling, export_params.quality,
                real_export_format, cancellable, export_params.mode == ExportFormatMode.UNMODIFIED, export_params.export_metadata));
            submitted++;
        }
        
        return submitted > 0;
    }
    
    private void export_completed(bool is_cancelled) {
        completion_callback(this, is_cancelled);
    }
}

public class ExporterUI {
    private Exporter exporter;
    private Cancellable cancellable = new Cancellable();
    private ProgressDialog? progress_dialog = null;
    private unowned Exporter.CompletionCallback? completion_callback = null;
    
    public ExporterUI(Exporter exporter) {
        this.exporter = exporter;
    }
    
    public void export(Exporter.CompletionCallback completion_callback) {
        this.completion_callback = completion_callback;
        
        AppWindow.get_instance().set_busy_cursor();
        
        progress_dialog = new ProgressDialog(AppWindow.get_instance(), _("Exporting"), cancellable);
        exporter.export(on_export_completed, on_export_failed, on_export_overwrite, cancellable,
            progress_dialog.monitor);
    }
    
    private void on_export_completed(Exporter exporter, bool is_cancelled) {
        if (progress_dialog != null) {
            progress_dialog.close();
            progress_dialog = null;
        }
        
        AppWindow.get_instance().set_normal_cursor();
        
        completion_callback(exporter, is_cancelled);
    }
    
    private Exporter.Overwrite on_export_overwrite(Exporter exporter, File file) {
        progress_dialog.set_modal(false);
        string question = _("File %s already exists. Replace?").printf(file.get_basename());
        Gtk.ResponseType response = AppWindow.negate_affirm_all_cancel_question(question, 
            _("_Skip"), _("_Replace"), _("Replace _All"), _("Export"));
        
        progress_dialog.set_modal(true);

        switch (response) {
            case Gtk.ResponseType.APPLY:
                return Exporter.Overwrite.REPLACE_ALL;
            
            case Gtk.ResponseType.YES:
                return Exporter.Overwrite.YES;
            
            case Gtk.ResponseType.CANCEL:
                return Exporter.Overwrite.CANCEL;
            
            case Gtk.ResponseType.NO:
            default:
                return Exporter.Overwrite.NO;
        }
    }
    
    private bool on_export_failed(Exporter exporter, File file, int remaining, Error err) {
        return export_error_dialog(file, remaining > 0) != Gtk.ResponseType.CANCEL;
    }
}

