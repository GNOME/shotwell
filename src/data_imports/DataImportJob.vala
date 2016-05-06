/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Spit.DataImports  {

/**
 * A specialized import job implementation for alien databases.
 */
public class DataImportJob : BatchImportJob {
    private DataImportSource import_source;
    private File? src_file;
    private uint64 filesize;
    private time_t exposure_time;
    private DataImportJob? associated = null;
    private HierarchicalTagIndex? detected_htags = null;
    
    public DataImportJob(DataImportSource import_source) {
        this.import_source = import_source;
        
        // stash everything called in prepare(), as it may/will be called from a separate thread
        src_file = import_source.get_file();
        filesize = import_source.get_filesize();
        exposure_time = import_source.get_exposure_time();
    }
    
    private HierarchicalTagIndex? build_exclusion_index(ImportableTag[] src_tags) {
        Gee.Set<string> detected_htags = new Gee.HashSet<string>();
        
        foreach (ImportableTag src_tag in src_tags) {
            string? prepped = HierarchicalTagUtilities.join_path_components(
                Tag.prep_tag_names(
                    build_path_components(src_tag)
                )
            );
            
            if (prepped != null && prepped.has_prefix(Tag.PATH_SEPARATOR_STRING)) {
                detected_htags.add(prepped);

                Gee.List<string> parents = HierarchicalTagUtilities.enumerate_parent_paths(prepped);
                foreach (string parent in parents)
                    detected_htags.add(parent);
            }
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
        this.associated = associated as DataImportJob;
    }
    
    public override bool determine_file_size(out uint64 filesize, out File file) {
        file = null;
        filesize = this.filesize;
        
        return true;
    }
    
    public override bool prepare(out File file_to_import, out bool copy_to_library) throws Error {
        file_to_import = src_file;
        copy_to_library = false;
        
        detected_htags = build_exclusion_index(import_source.get_photo().get_tags());
        
        return true;
    }
    
    public override bool complete(MediaSource source, BatchImportRoll import_roll) throws Error {
        LibraryPhoto? photo = source as LibraryPhoto;
        if (photo == null)
            return false;
        
        ImportableMediaItem src_photo = import_source.get_photo();
        
        // tags
        if (detected_htags != null) {
            Gee.Collection<string> paths = detected_htags.get_all_paths();

            foreach (string path in paths)
                Tag.for_path(path);
        }
        
        ImportableTag[] src_tags = src_photo.get_tags();
        foreach (ImportableTag src_tag in src_tags) {
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
        ImportableEvent? src_event = src_photo.get_event();
        if (src_event != null) {
            string? prepped = prepare_input_text(src_event.get_name(), 
                PrepareInputTextOptions.DEFAULT, -1);
            if (prepped != null)
                Event.generate_single_event(photo, import_roll.generated_events, prepped);
        }
        // rating
        Rating dst_rating;
        ImportableRating src_rating = src_photo.get_rating();
        if (src_rating.is_rejected())
            dst_rating = Rating.REJECTED;
        else if (src_rating.is_unrated())
            dst_rating = Rating.UNRATED;
        else
            dst_rating = Rating.unserialize(src_rating.get_value());
        photo.set_rating(dst_rating);
        // title
        string? title = src_photo.get_title();
        if (title != null)
            photo.set_title(title);
        // exposure time
        time_t? date_time = src_photo.get_exposure_time();
        if (date_time != null)
            photo.set_exposure_time(date_time);
        // import ID
        photo.set_import_id(import_roll.import_id);
        
        return true;
    }
    
    private string[] build_path_components(ImportableTag tag) {
        // use a linked list as we are always inserting in head position
        Gee.List<string> components = new Gee.LinkedList<string>();
        for (ImportableTag current_tag = tag; current_tag != null; current_tag = current_tag.get_parent()) {
            components.insert(0, HierarchicalTagUtilities.make_flat_tag_safe(current_tag.get_name()));
        }
        return components.to_array();
    }
}

}

