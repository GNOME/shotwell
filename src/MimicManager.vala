/* Copyright 2010-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MimicManager : Object {
    // If this changes in the future, the stored files may need to be updated, as the wrong
    // adapter may be used.
    private const PhotoFileFormat MIMIC_FILE_FORMAT = PhotoFileFormat.JFIF;
    
    private class VerifyJob : BackgroundJob {
        public Photo photo;
        public PhotoFileWriter writer;
        public Error? err = null;
        
        public VerifyJob(MimicManager manager, Photo photo, PhotoFileWriter writer) {
            base (manager, manager.on_verify_completed, new Cancellable());
            
            this.photo = photo;
            this.writer = writer;
        }
        
        public override void execute() {
            if (writer.file_exists())
                return;
            
            try {
                writer.write(photo.get_master_pixbuf(Scaling.for_original(), false), Jpeg.Quality.HIGH);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private class DeleteJob : BackgroundJob {
        public File file;
        
        public DeleteJob(MimicManager manager, File file) {
            base (manager, manager.on_delete_completed, new Cancellable());
            
            set_completion_semaphore(new Semaphore());
            
            this.file = file;
        }
        
        public override void execute() {
            try {
                file.delete(null);
            } catch (Error err) {
                // ignored
            }
        }
    }
    
    private SourceCollection sources;
    private File impersonators_dir;
    private Workers workers = new Workers(Workers.thread_per_cpu_minus_one(), false);
    private Gee.HashMap<Photo, VerifyJob> verify_jobs = new Gee.HashMap<Photo, VerifyJob>();
    private Gee.HashSet<DeleteJob> delete_jobs = new Gee.HashSet<DeleteJob>();
    private int pause_count = 0;
    private Gee.ArrayList<VerifyJob> paused_list = new Gee.ArrayList<VerifyJob>();
    private int completed_jobs = 0;
    private int total_jobs = 0;
    
    public signal void progress(int completed, int total);
    
    public MimicManager(SourceCollection sources, File impersonators_dir) {
        this.sources = sources;
        this.impersonators_dir = impersonators_dir;
        
        on_photos_added(sources.get_all());
        
        sources.items_added.connect(on_photos_added);
        sources.item_destroyed.connect(on_photo_destroyed);
        sources.unlinked_destroyed.connect(on_photo_destroyed);
        
        Application.get_instance().exiting.connect(on_application_exiting);
    }
    
    ~MimicManager() {
        sources.items_added.disconnect(on_photos_added);
        sources.item_destroyed.disconnect(on_photo_destroyed);
        sources.unlinked_destroyed.disconnect(on_photo_destroyed);
        
        Application.get_instance().exiting.disconnect(on_application_exiting);
    }
    
    public void pause() {
        if (pause_count++ == 0)
            progress(0, 0);
    }
    
    public void resume() {
        if (--pause_count > 0)
            return;
            
        pause_count = 0;
        
        foreach (VerifyJob job in paused_list)
            enqueue_verify_job(job);
        
        paused_list.clear();
    }
    
    private void on_application_exiting(bool panicked) {
        foreach (VerifyJob job in verify_jobs.values)
            job.cancel();
        
        // wait out all the delete jobs, no way to restart these properly because of the way that
        // IDs may be reused after destruction
        foreach (DeleteJob job in delete_jobs)
            job.wait_for_completion();
    }
    
    private void enqueue_verify_job(VerifyJob job) {
        total_jobs++;
        verify_jobs.set(job.photo, job);
        workers.enqueue(job);
    }
    
    private void on_photos_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            Photo photo = (Photo) object;
            if (!photo.would_use_mimic())
                continue;
            
            PhotoFileWriter writer;
            try {
                writer = MIMIC_FILE_FORMAT.create_writer(generate_impersonator_filepath(photo));
            } catch (PhotoFormatError err) {
                error("Unable to create PhotoFileWriter for impersonator: %s", err.message);
            }
            
            VerifyJob job = new VerifyJob(this, photo, writer);
            
            if (pause_count > 0) {
                paused_list.add(job);
                
                continue;
            }
            
            enqueue_verify_job(job);
        }
    }
    
    private void on_photo_destroyed(DataSource source) {
        // remove any outstanding VerifyJob
        VerifyJob? outstanding = verify_jobs.get((Photo) source);
        if (outstanding != null) {
            verify_jobs.unset((Photo) source);
            outstanding.cancel();
        }
        
        DeleteJob job = new DeleteJob(this, generate_impersonator_file((Photo) source));
        
        total_jobs++;
        delete_jobs.add(job);
        workers.enqueue(job);
    }
    
    private void on_verify_completed(BackgroundJob background_job) {
        VerifyJob job = (VerifyJob) background_job;
        
        bool removed = verify_jobs.unset(job.photo);
        assert(removed);
        
        report_completed_job();
        
        if (job.err != null) {
            critical("Unable to generate impersonator for %s: %s", job.photo.to_string(),
                job.err.message);
            
            return;
        }
        
        job.photo.set_mimic_reader(job.writer.create_reader());
    }
    
    private void on_delete_completed(BackgroundJob background_job) {
        bool removed = delete_jobs.remove((DeleteJob) background_job);
        assert(removed);
        
        report_completed_job();
    }
    
    private void report_completed_job() {
        if (++completed_jobs >= total_jobs) {
            completed_jobs = 0;
            total_jobs = 0;
        }
        
        progress(completed_jobs, total_jobs);
    }
    
    private string generate_impersonator_filepath(Photo photo) {
        return generate_impersonator_file(photo).get_path();
    }
    
    private File generate_impersonator_file(Photo photo) {
        return impersonators_dir.get_child("mimic%016llx.jpg".printf(photo.get_photo_id().id));
    }
}
