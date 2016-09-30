/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class TagSourceCollection : ContainerSourceCollection {
    private Gee.HashMap<string, Tag> name_map = new Gee.HashMap<string, Tag>(Tag.hash_name_string,
        Tag.equal_name_strings);
    private Gee.HashMap<MediaSource, Gee.List<Tag>> source_map =
        new Gee.HashMap<MediaSource, Gee.List<Tag>>();
    private Gee.HashMap<MediaSource, Gee.SortedSet<Tag>> sorted_source_map =
        new Gee.HashMap<MediaSource, Gee.SortedSet<Tag>>();
    
    public TagSourceCollection() {
        base (Tag.TYPENAME, "TagSourceCollection", get_tag_key);

        attach_collection(LibraryPhoto.global);
        attach_collection(Video.global);
        
        // deal with LibraryPhotos being reimported (and possibly their on-disk keywords changing)
        LibraryPhoto.global.source_reimported.connect(on_photo_source_reimported);
    }
    
    ~TagSourceCollection() {
        LibraryPhoto.global.source_reimported.disconnect(on_photo_source_reimported);
    }
        
    public override bool holds_type_of_source(DataSource source) {
        return source is Tag;
    }
    
    private static int64 get_tag_key(DataSource source) {
        return ((Tag) source).get_instance_id();
    }
    
    protected override Gee.Collection<ContainerSource>? get_containers_holding_source(DataSource source) {
        return fetch_for_source((MediaSource) source);
    }
    
    public override ContainerSource? convert_backlink_to_container(SourceBacklink backlink) {
        TagID tag_id = TagID(backlink.instance_id);
        Tag? result = null;

        // see if the backlinked tag is already rehydrated and available
        Tag? tag = fetch(tag_id);        
        if (tag != null) {
            result = tag;
        } else {
            // backlinked tag wasn't already available, so look for it in the holding tank
            foreach (ContainerSource container in get_holding_tank()) {
                tag = (Tag) container;
                if (tag.get_tag_id().id == tag_id.id) {
                    result = tag;
                    break;
                }
            }
        }

        // if we have pulled a hierarchical tag out of the holding tank and the tag we've pulled out
        // has a parent, its parent might need to be promoted (because it was flattened when put
        // into the holding tank), so check for this case and promote if necessary
        if (result != null) {
            if ((result.get_path().has_prefix(Tag.PATH_SEPARATOR_STRING)) &&
                (HierarchicalTagUtilities.enumerate_parent_paths(result.get_path()).size > 0)) {
                string top_level_with_prefix_path =
                    HierarchicalTagUtilities.enumerate_parent_paths(result.get_path()).get(0);
                string top_level_no_prefix_path =
                    HierarchicalTagUtilities.hierarchical_to_flat(top_level_with_prefix_path);

                foreach (ContainerSource container in get_holding_tank()) {
                    Tag parent_candidate = (Tag) container;
                    if (parent_candidate.get_path() == top_level_no_prefix_path)
                        parent_candidate.promote();
                }
            }
        }
        
        return result;
    }
    
    public Tag? fetch(TagID tag_id) {
        return (Tag) fetch_by_key(tag_id.id);
    }
    
    public bool exists(string name, bool treat_htags_as_root = false) {
        return fetch_by_name(name, treat_htags_as_root) != null;
    }
    
    public Gee.Collection<string> get_all_names() {
        return name_map.keys;
    }
    
    // Returns a list of all Tags associated with the media source in no particular order.
    //
    // NOTE: As a search optimization, this returns the list that is maintained by Tags.global.
    // Do NOT modify this list.
    public Gee.List<Tag>? fetch_for_source(MediaSource source) {
        return source_map.get(source);
    }
    
    // Returns a sorted set of all Tags associated with the media source (ascending by name).
    //
    // NOTE: As an optimization, this returns the list that is maintained by Tags.global.
    // Do NOT modify this list.
    public Gee.SortedSet<Tag>? fetch_sorted_for_source(MediaSource photo) {
        return sorted_source_map.get(photo);
    }
    
    // Returns null if not Tag with name exists.
    // treat_htags_as_root: set to true if you want this function to treat htags as root tags
    public Tag? fetch_by_name(string name, bool treat_htags_as_root = false) {
        if (treat_htags_as_root) {
            if (name.has_prefix(Tag.PATH_SEPARATOR_STRING)) {
                if (HierarchicalTagUtilities.enumerate_path_components(name).size == 1) {
                    Tag? tag = name_map.get(HierarchicalTagUtilities.hierarchical_to_flat(name));
                    if (tag != null)
                        return tag;
                 }
            } else {
                Tag? tag = name_map.get(HierarchicalTagUtilities.flat_to_hierarchical(name));
                if (tag != null)
                    return tag;
            }
        }
        
        return name_map.get(name);
    }
    
    public Tag? restore_tag_from_holding_tank(string name) {
        Tag? found = null;
        foreach (ContainerSource container in get_holding_tank()) {
            Tag tag = (Tag) container;
            if (tag.get_name() == name) {
                found = tag;
                
                break;
            }
        }
        
        if (found != null) {
            bool relinked = relink_from_holding_tank(found);
            assert(relinked);
        }
        
        return found;
    }
    
    protected override void notify_items_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            Tag tag = (Tag) object;
            
            assert(!name_map.has_key(tag.get_name()));
            name_map.set(tag.get_name(), tag);
        }
        
        base.notify_items_added(added);
    }
    
    protected override void notify_items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            Tag tag = (Tag) object;
                        
            bool unset = name_map.unset(tag.get_name());
            assert(unset);

            // if we just removed the last child tag of a top-level hierarchical tag, then convert
            // the top-level tag back to a flat tag
            Tag? parent = tag.get_hierarchical_parent();
            if ((parent != null) && (parent.get_hierarchical_parent() == null)) {
                if (parent.get_hierarchical_children().size == 0)
                    parent.flatten();
            }
        }
        
        base.notify_items_removed(removed);
    }
    
    protected override void notify_items_altered(Gee.Map<DataObject, Alteration> map) {
        foreach (DataObject object in map.keys) {
            Tag tag = (Tag) object;
            
            string? old_name = null;
            
            // look for this tag being renamed
            Gee.MapIterator<string, Tag> iter = name_map.map_iterator();
            while (iter.next()) {
                if (!iter.get_value().equals(tag))
                    continue;
                
                old_name = iter.get_key();
                
                break;
            }
            
            assert(old_name != null);
            
            if (tag.get_name() != old_name) {
                name_map.unset(old_name);
                name_map.set(tag.get_name(), tag);
            }
        }
        
        base.notify_items_altered(map);
    }
    
    protected override void notify_container_contents_added(ContainerSource container, 
        Gee.Collection<DataObject> added, bool relinking) {
        Tag tag = (Tag) container;
        Gee.Collection<MediaSource> sources = (Gee.Collection<MediaSource>) added;
        
        foreach (MediaSource source in sources) {
            Gee.List<Tag>? tags = source_map.get(source);
            if (tags == null) {
                tags = new Gee.ArrayList<Tag>();
                source_map.set(source, tags);
            }
            
            bool is_added = tags.add(tag);
            assert(is_added);
            
            Gee.SortedSet<Tag>? sorted_tags = sorted_source_map.get(source);
            if (sorted_tags == null) {
                sorted_tags = new Gee.TreeSet<Tag>(Tag.compare_names);
                sorted_source_map.set(source, sorted_tags);
            }
            
            is_added = sorted_tags.add(tag);
            assert(is_added);
        }
        
        base.notify_container_contents_added(container, added, relinking);
    }
    
    protected override void notify_container_contents_removed(ContainerSource container, 
        Gee.Collection<DataObject> removed, bool unlinking) {
        Tag tag = (Tag) container;
        Gee.Collection<MediaSource> sources = (Gee.Collection<MediaSource>) removed;
        
        foreach (MediaSource source in sources) {
            Gee.List<Tag>? tags = source_map.get(source);
            assert(tags != null);
            
            bool is_removed = tags.remove(tag);
            assert(is_removed);
            
            if (tags.size == 0)
                source_map.unset(source);
            
            Gee.SortedSet<Tag>? sorted_tags = sorted_source_map.get(source);
            assert(sorted_tags != null);
            
            is_removed = sorted_tags.remove(tag);
            assert(is_removed);
            
            if (sorted_tags.size == 0)
                sorted_source_map.unset(source);
        }
        
        base.notify_container_contents_removed(container, removed, unlinking);
    }
    
    private void on_photo_source_reimported(LibraryPhoto photo, PhotoMetadata? metadata) {
        // with the introduction of HTags, all of this logic has been moved to
        // Photo.apply_user_metadata_for_reimport( )
    }
}

public class Tag : DataSource, ContainerSource, Proxyable, Indexable {
    public const string TYPENAME = "tag";
    public const string PATH_SEPARATOR_STRING = "/";
    public const string TAG_LIST_SEPARATOR_STRING = ", ";
    
    private class TagSnapshot : SourceSnapshot {
        private TagRow row;
        private Gee.HashSet<MediaSource> sources = new Gee.HashSet<MediaSource>();
        
        public TagSnapshot(Tag tag) {
            // stash current state of Tag
            row = tag.row;
            
            // stash photos and videos attached to this tag ... if any are destroyed, the tag
            // cannot be reconstituted
            foreach (MediaSource source in tag.get_sources())
                sources.add(source);
            
            LibraryPhoto.global.item_destroyed.connect(on_source_destroyed);
            Video.global.item_destroyed.connect(on_source_destroyed);
        }
        
        ~TagSnapshot() {
            LibraryPhoto.global.item_destroyed.disconnect(on_source_destroyed);
            Video.global.item_destroyed.disconnect(on_source_destroyed);
        }
        
        public TagRow get_row() {
            return row;
        }
        
        public override void notify_broken() {
            row = new TagRow();
            sources.clear();
            
            base.notify_broken();
        }
        
        private void on_source_destroyed(DataSource source) {
            if (sources.contains((MediaSource) source))
                notify_broken();
        }
    }
    
    private class TagProxy : SourceProxy {
        public TagProxy(Tag tag) {
            base (tag);
        }
        
        public override DataSource reconstitute(int64 object_id, SourceSnapshot snapshot) {
            return Tag.reconstitute(object_id, ((TagSnapshot) snapshot).get_row());
        }
    }
    
    public static TagSourceCollection global = null;
    
    private TagRow row;
    private ViewCollection media_views;
    private string? name_collation_key = null;
    private bool unlinking = false;
    private bool relinking = false;
    private string? indexable_keywords = null;
    
    private Tag(TagRow row, int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        this.row = row;
        
        // normalize user text
        this.row.name = prep_tag_name(this.row.name);
        
        // convert source ids to MediaSources and ThumbnailViews for the internal ViewCollection
        Gee.ArrayList<MediaSource> source_list = new Gee.ArrayList<MediaSource>();
        Gee.ArrayList<ThumbnailView> thumbnail_views = new Gee.ArrayList<ThumbnailView>();
        if (this.row.source_id_list != null) {
            foreach (string source_id in this.row.source_id_list) {
                MediaSource? current_source =
                    (MediaSource?) MediaCollectionRegistry.get_instance().fetch_media(source_id);
                if (current_source == null)
                    continue;
                
                source_list.add(current_source);
                thumbnail_views.add(new ThumbnailView(current_source));
            }
        } else {
            // allocate the source_id_list for use if/when media sources are added
            this.row.source_id_list = new Gee.HashSet<string>();
        }
        
        // add to internal ViewCollection, which maintains media sources associated with this tag
        media_views = new ViewCollection("ViewCollection for tag %s".printf(row.tag_id.id.to_string()));
        media_views.add_many(thumbnail_views);
        
        // need to do this manually here because only want to monitor photo_contents_altered
        // after add_many() here; but need to keep the TagSourceCollection apprised
        if (source_list.size > 0) {
            global.notify_container_contents_added(this, source_list, false);
            global.notify_container_contents_altered(this, source_list, false, null, false);
        }
        
        // monitor ViewCollection to (a) keep the in-memory list of source ids up-to-date, and
        // (b) update the database whenever there's a change;
        media_views.contents_altered.connect(on_media_views_contents_altered);
        
        // monitor the global collections to trap when photos and videos are destroyed, then
        // automatically remove from the tag
        LibraryPhoto.global.items_destroyed.connect(on_sources_destroyed);
        Video.global.items_destroyed.connect(on_sources_destroyed);
        
        update_indexable_keywords();
    }
    
    ~Tag() {
        media_views.contents_altered.disconnect(on_media_views_contents_altered);
        LibraryPhoto.global.items_destroyed.disconnect(on_sources_destroyed);
        Video.global.items_destroyed.disconnect(on_sources_destroyed);
    }
    
    public static void init(ProgressMonitor? monitor) {
        global = new TagSourceCollection();
        
        // scoop up all the rows at once
        Gee.List<TagRow?> rows = null;
        try {
            rows = TagTable.get_instance().get_all_rows();
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // turn the freshly-read TagRows into Tag objects.

        // a lookup table of fully-qualified path ancestries and their  
        // attendant tag objects, used later for finding and deleting child     
        // tags with missing parents or incorrect source counts, then
        // finally adding the remaining tags to the global media source list.
        Gee.TreeMap<string, Tag> ancestry_dictionary = new Gee.TreeMap<string, Tag>();

        Gee.ArrayList<Tag> unlinked = new Gee.ArrayList<Tag>();
        int count = rows.size;
        for (int ctr = 0; ctr < count; ctr++) {
            TagRow row = rows.get(ctr);

            // make sure the tag name is valid
            string? name = prep_tag_name(row.name);
            if (name == null) {
                // TODO: More graceful handling of this situation would be to rename the tag or
                // alert the user.
                warning("Invalid tag name \"%s\": removing from database", row.name);
                try {
                    TagTable.get_instance().remove(row.tag_id);
                } catch (DatabaseError err) {
                    warning("Unable to delete tag \"%s\": %s", row.name, err.message);
                }

                continue;
            }

            row.name = name;

            Tag tag = new Tag(row);
            if (monitor != null)
                monitor(ctr, count);

            ancestry_dictionary.set(tag.get_path(), tag);

            if (tag.has_links()) {
                tag.rehydrate_backlinks(global, null);
                unlinked.add(tag);
            }
        }

        Gee.Set<Tag> victim_set = new Gee.HashSet<Tag>();

        // look through the dictionary for pathological pairs of tags like so:
        // 'Tag Name' and '/Tag Name'; if we see these, merge the media sources
        // from '/Tag Name' into 'Tag Name' and delete the hierarchical version.
        foreach (string fq_tag_path in ancestry_dictionary.keys) {
            if (HierarchicalTagUtilities.enumerate_parent_paths(fq_tag_path).size < 1) {
                if ((fq_tag_path.has_prefix(Tag.PATH_SEPARATOR_STRING)) &&
                    (ancestry_dictionary.has_key(HierarchicalTagUtilities.hierarchical_to_flat(fq_tag_path)))) {
                    victim_set.add(ancestry_dictionary.get(fq_tag_path));
                }
            }
        }

        foreach (Tag tag in victim_set) {
            Gee.Collection<MediaSource> source_collection = tag.get_sources();
            string flat_version = tag.get_user_visible_name();
            global.fetch_by_name(flat_version).attach_many(source_collection);

            ancestry_dictionary.unset(tag.get_path());

            tag.detach_many(tag.get_sources());
            tag.destroy_orphan(true);
        }

        // look through the dictionary for children with invalid source 
        // counts and/or missing parents and reap them. we'll also flatten
        // any top-level parents who have 0 children remaining after the reap.
        victim_set.clear();

        foreach (string fq_tag_path in ancestry_dictionary.keys) {
            Gee.List<string> parents_to_search =
                HierarchicalTagUtilities.enumerate_parent_paths(fq_tag_path);

            Tag curr_child = ancestry_dictionary.get(fq_tag_path);

            foreach (string parent_path in parents_to_search) {
                // if this tag has more sources than its parent, then we're
                // in an inconsistent state and need to remove this tag.
                int child_ref_count = curr_child.get_sources_count();
                int parent_ref_count = -1; 
                
                // does this parent even exist?
                if (ancestry_dictionary.has_key(parent_path)) {
                    // yes, get its source count.
                    parent_ref_count = ancestry_dictionary.get(parent_path).get_sources_count();
                }
                                
                // do we have more sources than our parent?
                if (child_ref_count > parent_ref_count) {
                    // yes, ask to be reaped later. we can't kill ourselves
                    // now because it would interfere with the dictionary's
                    // iterator.
                    victim_set.add(curr_child);

                    // if we already know we're going to be reaped,
                    // don't search anymore.
                    break;
                }

                // is our parent being reaped? 
                if (victim_set.contains(ancestry_dictionary.get(parent_path))) {
                    // yes, we have to be reaped too.
                    victim_set.add(curr_child);
                    break;
                }
            }
        }

        // actually reap invalid children.
        foreach (Tag t in victim_set) { 
            ancestry_dictionary.unset(t.get_path());
            t.destroy_orphan(true);
        }

        // add remaining tags all at once to the SourceCollection
        global.add_many(ancestry_dictionary.values);
        global.init_add_many_unlinked(unlinked);
        
        // flatten root tags who have zero children; this will catch
        // both parents whose children were reaped and corrupted parents.
        foreach (Tag t in ancestry_dictionary.values) {
            // do we have no parent and no children?
            if ((t.get_hierarchical_children().size < 1) && (t.get_hierarchical_parent() == null)) {
                //yes, flatten.
                t.flatten();
            }
        }
    }
    
    public static void terminate() {
    }
    
    public static int compare_names(Tag a, Tag b) {        
        return String.precollated_compare(a.get_name(), a.get_name_collation_key(), b.get_name(),
            b.get_name_collation_key());
    }

    public static int compare_user_visible_names(Tag a, Tag b) {
        return String.precollated_compare(a.get_user_visible_name(), a.get_name_collation_key(),
                                          b.get_user_visible_name(), b.get_name_collation_key());
    }

    public static uint hash_name_string(string a) {
        return String.collated_hash(a);
    }
    
    public static bool equal_name_strings(string a, string b) {
        return String.collated_equals(a, b);
    }
    
    // Returns a Tag for the path, creating a new empty one if it does not already exist.
    // path should have already been prepared by prep_tag_name.
    public static Tag for_path(string name) {
        Tag? tag = global.fetch_by_name(name, true);
        if (tag == null)
            tag = global.restore_tag_from_holding_tank(name);
        
        if (tag != null)
            return tag;
        
        // create a new Tag for this name
        try {
            tag = new Tag(TagTable.get_instance().add(name));
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        global.add(tag);
        
        return tag;
    }
    
    public static Gee.Collection<Tag> get_terminal_tags(Gee.Collection<Tag> tags) {
        Gee.Set<string> result_paths = new Gee.HashSet<string>();
        
        foreach (Tag tag in tags) {
            // if it's not hierarchical, it's terminal
            if (!tag.get_path().has_prefix(Tag.PATH_SEPARATOR_STRING)) {
                result_paths.add(tag.get_path());
                continue;
            }
            
            // okay, it is hierarchical
            
            // has it got a parent?
            if (tag.get_hierarchical_parent() != null) {
                // have we seen its parent? if so, remove its parent from the result set since
                // its parent clearly isn't terminal
                if (result_paths.contains(tag.get_hierarchical_parent().get_path()))
                    result_paths.remove(tag.get_hierarchical_parent().get_path());
            }
            
            result_paths.add(tag.get_path());
        }
        
        Gee.ArrayList<Tag> result = new Gee.ArrayList<Tag>();
        foreach (string path in result_paths) {
            if (Tag.global.exists(path)) {
                result.add(Tag.for_path(path));
            } else {
                foreach (Tag probed_tag in tags) {
                    if (probed_tag.get_path() == path)
                        result.add(probed_tag);
                }
            }
        }
        
        return result;
    }

    // Creates a sorted list of terminal tags, unique by user-visible-name
    public static Gee.List<Tag> make_user_visible_tag_list(Gee.Collection<Tag> tags) {
        Gee.HashSet<string> seen_tags = new Gee.HashSet<string>();
        Gee.Collection<Tag> terminal_tags = get_terminal_tags(tags);
        Gee.ArrayList<Tag> sorted_tags = new Gee.ArrayList<Tag>();
        foreach (Tag tag in terminal_tags) {
            string user_visible_name = tag.get_user_visible_name();
            if (!seen_tags.contains(user_visible_name)) {
                sorted_tags.add(tag);
                seen_tags.add(user_visible_name);
            }
        }
        sorted_tags.sort(Tag.compare_user_visible_names);
        return sorted_tags;
    }

    public static string make_tag_markup_string(Gee.List<Tag> tags, int highlight_index = -1) {
        StringBuilder builder = new StringBuilder("<small>");
        int i = 0;
        bool first = true;
        foreach(Tag tag in tags) {
            string tag_name = tag.get_user_visible_name();
            string esc_tag_name = guarded_markup_escape_text(tag_name);
            if (first)
                first = false;
            else
                builder.append(TAG_LIST_SEPARATOR_STRING);
            if (highlight_index == i)
                builder.append("<u>");
            builder.append(esc_tag_name);
            if (highlight_index == i)
                builder.append("</u>");
            ++i;
        }

        builder.append("</small>");
        string built = builder.str;
        return built;
    }

    // Utility function to cleanup a tag name that comes from user input and prepare it for use
    // in the system and storage in the database.  Returns null if the name is unacceptable.
    public static string? prep_tag_name(string name) {
        return prepare_input_text(name, PrepareInputTextOptions.DEFAULT, DEFAULT_USER_TEXT_INPUT_LENGTH);
    }
    
    // Akin to prep_tag_name.  Returned array may be smaller than the in parameter (or empty!) if
    // names are discovered that cannot be used.
    public static string[] prep_tag_names(string[] names) {
        string[] result = new string[0];
        
        for (int ctr = 0; ctr < names.length; ctr++) {
            string? new_name = prep_tag_name(names[ctr]);
            if (new_name != null)
                result += new_name;
        }
        
        return result;
    }
    
    private void set_raw_flat_name(string name) {
        string? prepped_name = prep_tag_name(name);

        assert(prepped_name != null);
        assert(!prepped_name.has_prefix(Tag.PATH_SEPARATOR_STRING));
        
        try {
            TagTable.get_instance().rename(row.tag_id, prepped_name);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
            return;
        }
        
        row.name = prepped_name;
        name_collation_key = null;
        
        update_indexable_keywords();
        
        notify_altered(new Alteration.from_list("metadata:name, indexable:keywords"));
    }
    
    private void set_raw_path(string path, bool suppress_notify = false) {
        string? prepped_path = prep_tag_name(path);
        
        assert(prepped_path != null);
        assert(prepped_path.has_prefix(Tag.PATH_SEPARATOR_STRING));        
        assert(!Tag.global.exists(prepped_path));
        
        try {
            TagTable.get_instance().rename(row.tag_id, prepped_path);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
            return;
        }
        
        row.name = prepped_path;
        name_collation_key = null;
        
        if (!suppress_notify) {
            update_indexable_keywords();
            notify_altered(new Alteration.from_list("metadata:name, indexable:keywords"));
        }
    }
    
    public override string get_typename() {
        return TYPENAME;
    }
    
    public override int64 get_instance_id() {
        return get_tag_id().id;
    }
    
    public override string get_name() {
        return row.name;
    }
    
    public string get_path() {
        return get_name();
    }
    
    public string get_user_visible_name() {
        return HierarchicalTagUtilities.get_basename(get_path());
    }

    public string get_searchable_name() {
        string istring = HierarchicalTagUtilities.get_basename(get_path()).down();
        return String.remove_diacritics(istring);
    }
    
    public void flatten() {
        assert (get_hierarchical_parent() == null);
        
        set_raw_flat_name(get_user_visible_name());
    }
    
    public void promote() {
        if (get_path().has_prefix(Tag.PATH_SEPARATOR_STRING))
            return;

        set_raw_path(Tag.PATH_SEPARATOR_STRING + get_path());
    }
    
    public Tag? get_hierarchical_parent() {
        // if this is a flat tag, it has no parent
        if (!get_path().has_prefix(Tag.PATH_SEPARATOR_STRING))
            return null;

        Gee.List<string> components =
            HierarchicalTagUtilities.enumerate_path_components(get_path());
        
        assert(components.size > 0);
        
        if (components.size == 1) {
            return null;
        }
        
        string parent_path = "";
        for (int i = 0; i < (components.size - 1); i++)
            parent_path += (Tag.PATH_SEPARATOR_STRING + components.get(i));
        
        if (Tag.global.exists(parent_path))
            return Tag.for_path(parent_path);
        else
            return null;
    }
    
    public int get_attachment_count(MediaSource source) {
        // if we don't contain the source, the attachment count is zero
        if (!contains(source))
            return 0;

        // we ourselves contain the source, so that's one attachment
        int result = 1;
        
        // check to see if our children contain the source
        foreach (Tag child in get_hierarchical_children())
            if (child.contains(source))
                result++;
        
        return result;
    }
    
    /**
     * gets all hierarchical children of a tag recursively; tags are enumerated from most-derived
     * to least-derived
     */
    public Gee.List<Tag> get_hierarchical_children() {
        Gee.ArrayList<Tag> result = new Gee.ArrayList<Tag>();
        Gee.ArrayList<Tag> result_reversed = new Gee.ArrayList<Tag>();
        
        // if it's a flag tag, it doesn't have children
        if (!get_path().has_prefix(Tag.PATH_SEPARATOR_STRING))
            return result;
        
        // default lexicographic comparison for strings ensures hierarchical tag paths will be
        // sorted from least-derived to most-derived
        Gee.TreeSet<string> forward_sorted_paths = new Gee.TreeSet<string>();
        
        string target_path = get_path() + Tag.PATH_SEPARATOR_STRING;
        foreach (string path in Tag.global.get_all_names()) {
            if (path.has_prefix(target_path))
                forward_sorted_paths.add(path);
        }
        
        foreach (string tmp in forward_sorted_paths) {
            result_reversed.add(Tag.for_path(tmp));
        }
        
        for (int index = result_reversed.size - 1; index >= 0; index--) {
            result.add(result_reversed[index]);
        }

        return result;
    }
    
    // Gets the next "untitled" tag name available.
    // Note: Not thread-safe.
    private static string get_next_untitled_tag_name(string? _prefix = null) {
        string prefix = _prefix != null ? _prefix : "";
        string candidate_name = _("untitled");
        uint64 counter = 0;
        do {
            string path_candidate = prefix + candidate_name +
                ((counter == 0) ? "" : (" " + counter.to_string()));
            
            if (!Tag.global.exists(path_candidate))
                return path_candidate;
            
            counter++;
        } while (counter < uint64.MAX);
        
        // If we get here, it means all untitled tags up to uint64.MAX were used.
        assert_not_reached();
    }
    
    public Tag create_new_child() {
        string path_prefix = get_path();
        
        if (!path_prefix.has_prefix(Tag.PATH_SEPARATOR_STRING)) {
            set_raw_path(HierarchicalTagUtilities.flat_to_hierarchical(get_path()));
            
            path_prefix = get_path();
        }
        
        return Tag.for_path(get_next_untitled_tag_name(path_prefix + Tag.PATH_SEPARATOR_STRING));
    }
    
    public static Tag create_new_root() {
        return Tag.for_path(get_next_untitled_tag_name());
    }
    
    public string get_name_collation_key() {
        if (name_collation_key == null)
            name_collation_key = row.name.collate_key();
        
        return name_collation_key;
    }
    
    public override string to_string() {
        return "Tag %s (%d sources)".printf(row.name, media_views.get_count());
    }
    
    public override bool equals(DataSource? source) {
        // Validate uniqueness of primary key
        Tag? tag = source as Tag;
        if (tag != null) {
            if (tag != this) {
                assert(tag.row.tag_id.id != row.tag_id.id);
            }
        }
        
        return base.equals(source);
    }
    
    public TagID get_tag_id() {
        return row.tag_id;
    }
    
    public override SourceSnapshot? save_snapshot() {
        return new TagSnapshot(this);
    }
    
    public SourceProxy get_proxy() {
        return new TagProxy(this);
    }
    
    public static Tag reconstitute(int64 object_id, TagRow row) {   
        // fill in the row with the new TagID for this reconstituted tag        
        try {
            row.tag_id = TagTable.get_instance().create_from_row(row);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
                
        Tag tag = new Tag(row, object_id);
        global.add(tag);
        
        debug("Reconstituted %s", tag.to_string());
        
        return tag;
    }
    
    public bool has_links() {
        return LibraryPhoto.global.has_backlink(get_backlink());
    }
    
    public SourceBacklink get_backlink() {
        return new SourceBacklink.from_source(this);
    }
    
    public void break_link(DataSource source) {
        unlinking = true;
        
        detach((LibraryPhoto) source);
        
        unlinking = false;
    }
    
    public void break_link_many(Gee.Collection<DataSource> sources) {
        unlinking = true;
        
        detach_many((Gee.Collection<LibraryPhoto>) sources);
        
        unlinking = false;
    }
    
    public void establish_link(DataSource source) {
        relinking = true;
        
        attach((LibraryPhoto) source);
        
        relinking = false;
    }
    
    public void establish_link_many(Gee.Collection<DataSource> sources) {
        relinking = true;
        
        attach_many((Gee.Collection<LibraryPhoto>) sources);
        
        relinking = false;
    }
    
    private void update_indexable_keywords() {
        indexable_keywords = prepare_indexable_string(get_searchable_name());
    }
    
    public unowned string? get_indexable_keywords() {
        return indexable_keywords;
    }
    
    public void attach(MediaSource source) {
        Tag? attach_to = this;
        while (attach_to != null) {
            if (!attach_to.media_views.has_view_for_source(source)) {
                attach_to.media_views.add(new ThumbnailView(source));
            }

            attach_to = attach_to.get_hierarchical_parent();
        }
    }
    
    public void attach_many(Gee.Collection<MediaSource> sources) {
        Tag? attach_to = this;
        while (attach_to != null) {
            Gee.ArrayList<ThumbnailView> view_list = new Gee.ArrayList<ThumbnailView>();
            foreach (MediaSource source in sources) {
                if (!attach_to.media_views.has_view_for_source(source))
                    view_list.add(new ThumbnailView(source));
            }
            
            if (view_list.size > 0)
                attach_to.media_views.add_many(view_list);

            attach_to = attach_to.get_hierarchical_parent();
        }
    }
    
    // Returns a list of Tags the MediaSource was detached from as a result of detaching it from
    // this Tag.  (This Tag will always be in the list unless null is returned, indicating the
    // MediaSource isn't present at all.)
    public Gee.List<Tag>? detach(MediaSource source) {
        DataView? this_view = media_views.get_view_for_source(source);
        if (this_view == null)
            return null;
        
        Gee.List<Tag>? detached_from = new Gee.ArrayList<Tag>();
        
        foreach (Tag child_tag in get_hierarchical_children()) {
            DataView? child_view = child_tag.media_views.get_view_for_source(source);
            if (child_view != null) {
                child_tag.media_views.remove_marked(child_tag.media_views.mark(child_view));
                detached_from.add(child_tag);
            }
        }
        
        media_views.remove_marked(media_views.mark(this_view));
        detached_from.add(this);
        
        return detached_from;
    }
    
    // Returns a map of Tags the MediaSource was detached from as a result of detaching it from
    // this Tag.  (This Tag will always be in the list unless null is returned, indicating the
    // MediaSource isn't present at all.)
    public Gee.MultiMap<Tag, MediaSource>? detach_many(Gee.Collection<MediaSource> sources) {
        Gee.MultiMap<Tag, MediaSource>? detached_from = new Gee.HashMultiMap<Tag, MediaSource>();
        
        Marker marker = media_views.start_marking();
        foreach (MediaSource source in sources) {
            DataView? view = media_views.get_view_for_source(source);
            if (view == null)
                continue;
            
            foreach (Tag child_tag in get_hierarchical_children()) {
                DataView? child_view = child_tag.media_views.get_view_for_source(source);
                if (child_view != null) {
                    child_tag.media_views.remove_marked(child_tag.media_views.mark(child_view));
                    detached_from.set(child_tag, source);
                }
            }
            
            marker.mark(view);
            detached_from.set(this, source);
        }
        
        media_views.remove_marked(marker);
        
        return (detached_from.size > 0) ? detached_from : null;
    }
    
    // Returns false if the name already exists or a bad name.
    public bool rename(string name) {
        if (name == get_user_visible_name())
            return true;

        string? new_name = prep_tag_name(name);
        if (new_name == null)
            return false;

        // if this is a hierarchical tag, then parents and children come into play
        if (get_path().has_prefix(Tag.PATH_SEPARATOR_STRING)) {
            string new_path = new_name;
            string old_path = get_path();

            Tag? parent = get_hierarchical_parent();
            if (parent != null) {
                new_path = parent.get_path() + PATH_SEPARATOR_STRING + new_path;
            } else {
                new_path = Tag.PATH_SEPARATOR_STRING + new_path;
            }
            
            if (Tag.global.exists(new_path, true))
                return false;

            Gee.Collection<Tag> children = get_hierarchical_children();

            set_raw_path(new_path, true);

            foreach (Tag child in children) {
                // keep these loop-local temporaries around -- it's useful to be able to print them
                // out when debugging     
                string old_child_path = child.get_path();
                
                // find the first instance of old_path in the child path -- we want to replace
                // the first and only the first instance
                int old_path_index = old_child_path.index_of(old_path);
                assert(old_path_index != -1);
                
                string child_subpath = old_child_path.substring(old_path_index + old_path.length);
                
                string new_child_path = new_path + child_subpath;

                child.set_raw_path(new_child_path, true);
            }
            
            update_indexable_keywords();
            notify_altered(new Alteration.from_list("metadata:name, indexable:keywords"));
            foreach (Tag child in children) {
                child.notify_altered(new Alteration.from_list("metadata:name, indexable:keywords"));
            }
        } else {
            // if this is a flat tag, no problem -- just keep doing what we've always done
            if (Tag.global.exists(new_name, true))
                return false;
            
            set_raw_flat_name(new_name);
        }
        
        return true;
    }
    
    public bool contains(MediaSource source) {
        return media_views.has_view_for_source(source);
    }
    
    public int get_sources_count() {
        return media_views.get_count();
    }
    
    public Gee.Collection<MediaSource> get_sources() {
        return (Gee.Collection<MediaSource>) media_views.get_sources();
    }
    
    public void mirror_sources(ViewCollection view, CreateView mirroring_ctor) {
        view.mirror(media_views, mirroring_ctor, null);
    }
    
    private void on_media_views_contents_altered(Gee.Iterable<DataView>? added,
        Gee.Iterable<DataView>? removed) {
        Gee.Collection<MediaSource> added_sources = null;
        if (added != null) {
            added_sources = new Gee.ArrayList<MediaSource>();
            foreach (DataView view in added) {
                MediaSource source = (MediaSource) view.get_source();
                
                // possible a source is added twice if the same tag is in source ... add()
                // returns true only if the set has altered
                if (!row.source_id_list.contains(source.get_source_id())) {
                    bool is_added = row.source_id_list.add(source.get_source_id());
                    assert(is_added);
                }
                
                bool is_added = added_sources.add(source);
                assert(is_added);
            }
        }
        
        Gee.Collection<MediaSource> removed_sources = null;
        if (removed != null) {
            removed_sources = new Gee.ArrayList<MediaSource>();
            foreach (DataView view in removed) {
                MediaSource source = (MediaSource) view.get_source();
                
                bool is_removed = row.source_id_list.remove(source.get_source_id());
                assert(is_removed);
                
                bool is_added = removed_sources.add(source);
                assert(is_added);
            }
        }
        
        try {
            TagTable.get_instance().set_tagged_sources(row.tag_id, row.source_id_list);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // notify of changes to this tag
        if (added_sources != null)
            global.notify_container_contents_added(this, added_sources, relinking);
        
        if (removed_sources != null)
            global.notify_container_contents_removed(this, removed_sources, unlinking);
        
        if (added_sources != null || removed_sources != null) {
            global.notify_container_contents_altered(this, added_sources, relinking, removed_sources,
                unlinking);
        }
    }
    
    private void on_sources_destroyed(Gee.Collection<DataSource> sources) {
        detach_many((Gee.Collection<MediaSource>) sources);
    }
    
    public override void destroy() {
        // detach all remaining sources from the tag, so observers are informed ... need to detach
        // the contents_altered handler because it will destroy this object when sources is empty,
        // which is bad reentrancy mojo (but hook it back up for the dtor's sake)
        if (media_views.get_count() > 0) {
            media_views.contents_altered.disconnect(on_media_views_contents_altered);
            
            Gee.ArrayList<MediaSource> removed = new Gee.ArrayList<MediaSource>();
            removed.add_all((Gee.Collection<MediaSource>) media_views.get_sources());
            
            media_views.clear();
            
            global.notify_container_contents_removed(this, removed, false);
            global.notify_container_contents_altered(this, null, false, removed, false);
            
            media_views.contents_altered.connect(on_media_views_contents_altered);
        }
        
        try {
            TagTable.get_instance().remove(row.tag_id);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        base.destroy();
    }
}

