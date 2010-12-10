/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class TagSourceCollection : ContainerSourceCollection {
    private Gee.HashMap<string, Tag> name_map = new Gee.HashMap<string, Tag>();
    private Gee.HashMap<MediaSource, Gee.List<Tag>> source_map =
        new Gee.HashMap<MediaSource, Gee.List<Tag>>();
    private Gee.HashMap<MediaSource, Gee.SortedSet<Tag>> sorted_source_map =
        new Gee.HashMap<MediaSource, Gee.SortedSet<Tag>>();
    
    public TagSourceCollection() {
        base (Tag.TYPENAME, "TagSourceCollection", get_tag_key);

        attach_collection(LibraryPhoto.global);
        attach_collection(Video.global);
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
        
        Tag? tag = fetch(tag_id);
        if (tag != null)
            return tag;
        
        foreach (ContainerSource container in get_holding_tank()) {
            tag = (Tag) container;
            if (tag.get_tag_id().id == tag_id.id)
                return tag;
        }
        
        return null;
    }
    
    public Tag? fetch(TagID tag_id) {
        return (Tag) fetch_by_key(tag_id.id);
    }
    
    public bool exists(string name) {
        return name_map.has_key(name);
    }
    
    public Gee.Collection<string> get_all_names() {
        return name_map.keys;
    }
    
    // Returns a list of all Tags associated with the media source in no particular order.
    public Gee.List<Tag>? fetch_for_source(MediaSource source) {
        Gee.List<Tag>? tags = source_map.get(source);
        if (tags == null)
            return null;
        
        Gee.List<Tag> copy = new Gee.ArrayList<Tag>();
        copy.add_all(tags);
        
        return copy;
    }
    
    // Returns a sorted set of all Tags associated with the media source (ascending by name).
    public Gee.SortedSet<Tag>? fetch_sorted_for_source(MediaSource photo) {
        Gee.SortedSet<Tag>? tags = sorted_source_map.get(photo);
        if (tags == null)
            return null;
        
        Gee.SortedSet<Tag> copy = new Gee.TreeSet<Tag>(compare_tag_name);
        copy.add_all(tags);
        
        return copy;
    }
    
    // Returns null if not Tag with name exists.
    public Tag? fetch_by_name(string name) {
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
    
    private static int compare_tag_name(void *a, void *b) {
        return strcmp(((Tag *) a)->get_name_collate_key(), ((Tag *) b)->get_name_collate_key());
    }
    
    protected override void notify_container_contents_added(ContainerSource container, 
        Gee.Collection<DataSource> added) {
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
                sorted_tags = new Gee.TreeSet<Tag>(compare_tag_name);
                sorted_source_map.set(source, sorted_tags);
            }
            
            is_added = sorted_tags.add(tag);
            assert(is_added);
        }
        
        base.notify_container_contents_added(container, added);
    }
    
    protected override void notify_container_contents_removed(ContainerSource container, 
        Gee.Collection<DataSource> removed) {
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
        
        base.notify_container_contents_removed(container, removed);
    }
}

public class Tag : DataSource, ContainerSource, Proxyable {
    public const string TYPENAME = "tag";
    
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
            row = TagRow();
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
    private string? name_collate_key = null;
    
    private Tag(TagRow row, int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        this.row = row;
        
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
            global.notify_container_contents_added(this, source_list);
            global.notify_container_contents_altered(this, source_list, null);
        }
        
        // monitor ViewCollection to (a) keep the in-memory list of source ids up-to-date, and
        // (b) update the database whenever there's a change;
        media_views.contents_altered.connect(on_media_views_contents_altered);
        
        // monitor the global collections to trap when photos and videos are destroyed, then
        // automatically remove from the tag
        LibraryPhoto.global.items_destroyed.connect(on_sources_destroyed);
        Video.global.items_destroyed.connect(on_sources_destroyed);
    }
    
    ~Tag() {
        media_views.contents_altered.disconnect(on_media_views_contents_altered);
        LibraryPhoto.global.items_destroyed.disconnect(on_sources_destroyed);
        Video.global.items_destroyed.disconnect(on_sources_destroyed);
    }
    
    public static void init() {
        global = new TagSourceCollection();
        
        // scoop up all the rows at once
        Gee.List<TagRow?> rows = null;
        try {
            rows = TagTable.get_instance().get_all_rows();
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // turn them into Tag objects
        Gee.ArrayList<Tag> tags = new Gee.ArrayList<Tag>();
        Gee.ArrayList<Tag> unlinked = new Gee.ArrayList<Tag>();
        int count = rows.size;
        for (int ctr = 0; ctr < count; ctr++) {
            Tag tag = new Tag(rows.get(ctr));
            
            if (tag.get_sources_count() != 0) {
                tags.add(tag);
                
                continue;
            }
            
            if (tag.has_links()) {
                tag.rehydrate_backlinks(global, null);
                unlinked.add(tag);
                
                continue;
            }
            
            warning("Empty tag %s found with no backlinks, destroying", tag.to_string());
            tag.destroy_orphan(true);
        }
        
        // add them all at once to the SourceCollection
        global.add_many(tags);
        global.init_add_many_unlinked(unlinked);
    }
    
    public static void terminate() {
    }
    
    // Returns a Tag for the name, creating a new empty one if it does not already exist
    public static Tag for_name(string name) {
        Tag? tag = global.fetch_by_name(name);
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
    
    public static string make_tag_string(Gee.Collection<Tag> tags, string? start = null, 
        string separator = ", ", string? end = null, bool escape = false) {
        StringBuilder builder = new StringBuilder(start ?? "");
        int ctr = 0;
        int count = tags.size;
        foreach (Tag tag in tags) {
            builder.append(escape ? guarded_markup_escape_text(tag.get_name()) : tag.get_name());
            if (ctr++ < count - 1)
                builder.append(separator);
        }
        if (end != null)
            builder.append(end);
        
        return builder.str;
    }
    
    // Utility function to cleanup a tag name that comes from user input and prepare it for use
    // in the system and storage in the database.  Returns null if the name is unacceptable.
    public static string? prep_tag_name(string name) {
        return prepare_input_text(name);
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
    
    public override string get_typename() {
        return TYPENAME;
    }
    
    public override int64 get_instance_id() {
        return get_tag_id().id;
    }
    
    public override string get_name() {
        return row.name;
    }
    
    public string get_name_collate_key() {
        if (name_collate_key == null)
            name_collate_key = row.name.collate_key();
        
        return name_collate_key;
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
    
    private static Tag reconstitute(int64 object_id, TagRow row) {
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
        detach((LibraryPhoto) source);
    }
    
    public void break_link_many(Gee.Collection<DataSource> sources) {
        detach_many((Gee.Collection<LibraryPhoto>) sources);
    }
    
    public void establish_link(DataSource source) {
        attach((LibraryPhoto) source);
    }
    
    public void establish_link_many(Gee.Collection<DataSource> sources) {
        attach_many((Gee.Collection<LibraryPhoto>) sources);
    }
    
    public void attach(MediaSource source) {
        if (!media_views.has_view_for_source(source))
            media_views.add(new ThumbnailView(source));
    }
    
    public void attach_many(Gee.Collection<MediaSource> sources) {
        Gee.ArrayList<ThumbnailView> view_list = new Gee.ArrayList<ThumbnailView>();
        foreach (MediaSource source in sources) {
            if (!media_views.has_view_for_source(source))
                view_list.add(new ThumbnailView(source));
        }
        
        if (view_list.size > 0)
            media_views.add_many(view_list);
    }
    
    public bool detach(MediaSource source) {
        DataView? view = media_views.get_view_for_source(source);
        if (view == null)
            return false;
        
        media_views.remove_marked(media_views.mark(view));
        
        return true;
    }
    
    public int detach_many(Gee.Collection<MediaSource> sources) {
        int count = 0;
        
        Marker marker = media_views.start_marking();
        foreach (MediaSource source in sources) {
            DataView? view = media_views.get_view_for_source(source);
            if (view == null)
                continue;
            
            marker.mark(view);
            count++;
        }
        
        media_views.remove_marked(marker);
        
        return count;
    }
    
    // Returns false if the name already exists or a bad name.
    public bool rename(string name) {
        string? new_name = prep_tag_name(name);
        if (new_name == null)
            return false;
        
        if (Tag.global.exists(new_name))
            return false;
        
        try {
            TagTable.get_instance().rename(row.tag_id, new_name);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
            return false;
        }
        
        row.name = new_name;
        name_collate_key = null;
        
        notify_altered(new Alteration("metadata", "name"));
        
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
        view.mirror(media_views, mirroring_ctor);
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
            global.notify_container_contents_added(this, added_sources);
        
        if (removed_sources != null)
            global.notify_container_contents_removed(this, removed_sources);
        
        if (added_sources != null || removed_sources != null)
            global.notify_container_contents_altered(this, added_sources, removed_sources);
        
        // if no more sources, tag evaporates; do not touch "this" afterwards
        if (media_views.get_count() == 0)
            global.evaporate(this);
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
            
            global.notify_container_contents_removed(this, removed);
            global.notify_container_contents_altered(this, null, removed);
            
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

