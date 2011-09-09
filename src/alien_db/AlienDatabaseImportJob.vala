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
    
    private HierarchicalTagIndex? build_exclusion_index(Gee.Collection<AlienDatabaseTag> src_tags) {
        Gee.Set<string> detected_htags = new Gee.HashSet<string>();
        
        foreach (AlienDatabaseTag src_tag in src_tags) {
            string? prepped = HierarchicalTagUtilities.join_path_components(
                Tag.prep_tag_names(
                    build_path_components(src_tag)
                )
            );
            
            if (prepped != null && prepped.has_prefix(Tag.PATH_SEPARATOR_STRING))
                detected_htags.add(prepped);
        }
        
        return (detected_htags.size > 0) ? HierarchicalTagIndex.from_paths(detected_htags) : null;
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
        
        // Some alien photo management programs (e.g. f-spot) support hierarchical tags
        // internally, in their own databases, but don't read and write this hierarchical tag
        // metadata into files. Instead, they only write flat tags into files. For example, you
        // can have a photo tagged with the hierarchical tag "/Animals/Dogs/Labrador/Billy" in
        // the f-spot database but only "Billy" will be written out to file metadata (if metadata
        // writing is enabled in f-spot). So what we have to do is knock out this flat tag
        // detritus in the files before importing them. Obviously, we do this only for flat tags
        // that are redundant (i.e., they're already being pulled in as components of hierarchical
        // tags directly from the alien database).
        HierarchicalTagIndex? detected_htags =
            build_exclusion_index(import_source.get_photo().get_tags());
        
        PhotoMetadata src_metadata = new PhotoMetadata();
        try {
            src_metadata.read_from_file(src_file);
        } catch (Error e) {
            warning("error reading metadata from file '%s' during pre-import tag sanitization: %s",
                src_file.get_path(), e.message);
        }

        Gee.Set<string> src_tags = src_metadata.get_keywords();
        Gee.Set<string>? sanitized_src_tags = null;
        if (src_tags != null && detected_htags != null) {
            foreach (string tag in src_tags) {
                if (!detected_htags.is_tag_in_index(tag)) {
                    if (sanitized_src_tags == null)
                        sanitized_src_tags = new Gee.HashSet<string>();
                    
                    sanitized_src_tags.add(tag);
                } else {
                    debug("knocking out flat tag '%s' because it's already known as a " +
                        "hierarchical tag component", tag);
                }
            }
        }
        
        if (sanitized_src_tags != null) {
            src_metadata.set_keywords(sanitized_src_tags);
            try {
                src_metadata.write_to_file(src_file);
            } catch (Error e) {
                warning("error writing metadata to file '%s' during pre-import tag sanitization: %s",
                    src_file.get_path(), e.message);
            }
        }
        
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
            string? prepped = HierarchicalTagUtilities.join_path_components(
                Tag.prep_tag_names(
                    build_path_components(src_tag)
                )
            );
            if (prepped != null) {
                if (HierarchicalTagUtilities.enumerate_path_components(prepped).size == 1) {
                    if (prepped.has_prefix(Tag.PATH_SEPARATOR_STRING))
                        prepped = HierarchicalTagUtilities.hierarchical_to_flat(prepped);
                } else {
                    Gee.List<string> parents =
                        HierarchicalTagUtilities.enumerate_parent_paths(prepped);

                    assert(parents.size > 0);

                    string top_level_parent = parents.get(0);
                    string flat_top_level_parent =
                        HierarchicalTagUtilities.hierarchical_to_flat(top_level_parent);
                    
                    if (Tag.global.exists(flat_top_level_parent))
                        Tag.for_path(flat_top_level_parent).promote();
                }

                Tag.for_path(prepped).attach(photo);
            }
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
    
    private string[] build_path_components(AlienDatabaseTag tag) {
        // use a linked list as we are always inserting in head position
        Gee.List<string> components = new Gee.LinkedList<string>();
        for (AlienDatabaseTag current_tag = tag; current_tag != null; current_tag = current_tag.get_parent()) {
            components.insert(0, HierarchicalTagUtilities.make_flat_tag_safe(current_tag.get_name()));
        }
        return components.to_array();
    }
}

}

