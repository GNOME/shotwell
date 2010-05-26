/* Copyright 2010 Yorba Foundation
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
                writer.write(photo.get_original_pixbuf(Scaling.for_original(), false), Jpeg.Quality.HIGH);
            } catch (Error err) {
                this.err = err;
            }
        }
    }
    
    private class DeleteJob : BackgroundJob {
        public File file;
        
        public DeleteJob(MimicManager manager, File file) {
            base (manager);
            
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
    private Workers workers = new Workers(1, false);
    private Gee.HashMap<Photo, VerifyJob> verify_jobs = new Gee.HashMap<Photo, VerifyJob>();
    
    public MimicManager(SourceCollection sources, File impersonators_dir) {
        this.sources = sources;
        this.impersonators_dir = impersonators_dir;
        
        on_photos_added(sources.get_all());
        
        sources.items_added += on_photos_added;
        sources.item_destroyed += on_photo_destroyed;
    }
    
    ~ImpersonatorManager() {
        sources.items_added -= on_photos_added;
        sources.item_destroyed -= on_photo_destroyed;
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
                
                continue;
            }
            
            VerifyJob job = new VerifyJob(this, photo, writer);
            verify_jobs.set(photo, job);
            
            workers.enqueue(job);
        }
    }
    
    private void on_photo_destroyed(DataSource source) {
        // remove any outstanding VerifyJob
        VerifyJob? outstanding = verify_jobs.get((Photo) source);
        if (outstanding != null) {
            verify_jobs.unset((Photo) source);
            outstanding.cancel();
        }
        
        workers.enqueue(new DeleteJob(this, generate_impersonator_file((Photo) source)));
    }
    
    private void on_verify_completed(BackgroundJob background_job) {
        VerifyJob job = (VerifyJob) background_job;
        
        bool removed = verify_jobs.unset(job.photo);
        assert(removed);
        
        if (job.err != null) {
            critical("Unable to generate impersonator for %s: %s", job.photo.to_string(),
                job.err.message);
            
            return;
        }
        
        job.photo.set_mimic_reader(job.writer.create_reader());
    }
    
    private string generate_impersonator_filepath(Photo photo) {
        return generate_impersonator_file(photo).get_path();
    }
    
    private File generate_impersonator_file(Photo photo) {
        return impersonators_dir.get_child("mimic%016llx.jpg".printf(photo.get_photo_id().id));
    }
}
