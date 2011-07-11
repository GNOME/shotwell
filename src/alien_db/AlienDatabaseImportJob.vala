/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace AlienDb {

/**
 * A specialized import job implementation for alien databases.
 */
public class AlienDatabaseImportJob : BatchImportJob {
    private AlienDatabaseImportSource import_source;
    private File? src_file;
    private uint64 filesize;
    private time_t exposure_time;
    private AlienDatabaseImportJob? associated = null;
    
    public AlienDatabaseImportJob(AlienDatabaseImportSource import_source) {
        this.import_source = import_source;
        
        // stash everything called in prepare(), as it may/will be called from a separate thread
        src_file = import_source.get_file();
        filesize = import_source.get_filesize();
        exposure_time = import_source.get_exposure_time();
    }
    
    public time_t get_exposure_time() {
        return exposure_time;
    }
    
    public override string get_dest_identifier() {
        return import_source.get_filename();
    }
    
    public override string get_source_identifier() {
        return import_source.get_filename();
    }
    
    public override bool is_directory() {
        return false;
    }
    
    public override string get_basename() {
        return src_file.get_basename();
    }
    
    public override string get_path() {
        return src_file.get_parent().get_path();
    }
    
    public override void set_associated(BatchImportJob associated) {
        this.associated = associated as AlienDatabaseImportJob;
    }
    
    public override bool determine_file_size(out uint64 filesize, out File file) {
        filesize = this.filesize;
        
        return true;
    }
    
    public override bool prepare(out File file_to_import, out bool copy_to_library) throws Error {
        file_to_import = src_file;
        copy_to_library = false;
        
        return true;
    }
    
    public override bool complete(MediaSource source, BatchImportRoll import_roll) throws Error {
        LibraryPhoto? photo = source as LibraryPhoto;
        if (photo == null)
            return false;
        
        AlienDatabasePhoto src_photo = import_source.get_photo();
        // tags
        Gee.Collection<AlienDatabaseTag> src_tags = src_photo.get_tags();
        foreach (AlienDatabaseTag src_tag in src_tags) {
            string? prepped = prepare_input_text(src_tag.get_name(), 
                PrepareInputTextOptions.DEFAULT, DEFAULT_USER_TEXT_INPUT_LENGTH);
            if (prepped != null)
                Tag.for_name(prepped).attach(photo);
        }
        // event
        AlienDatabaseEvent? src_event = src_photo.get_event();
        if (src_event != null) {
            string? prepped = prepare_input_text(src_event.get_name(), 
                PrepareInputTextOptions.DEFAULT, -1);
            if (prepped != null)
                Event.generate_single_event(photo, import_roll.generated_events, prepped);
        }
        // rating
        photo.set_rating(src_photo.get_rating());
        // title
        string? title = src_photo.get_title();
        if (title != null)
            photo.set_title(title);
        // import ID
        photo.set_import_id(import_roll.import_id);
        
        return true;
    }
}

}

