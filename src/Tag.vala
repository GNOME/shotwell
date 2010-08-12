/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class TagSourceCollection : ContainerSourceCollection {
    private Gee.HashMap<string, Tag> name_map = new Gee.HashMap<string, Tag>();
    private Gee.HashMap<LibraryPhoto, Gee.List<Tag>> photo_map =
        new Gee.HashMap<LibraryPhoto, Gee.List<Tag>>();
    private Gee.HashMap<LibraryPhoto, Gee.SortedSet<Tag>> sorted_photo_map =
        new Gee.HashMap<LibraryPhoto, Gee.SortedSet<Tag>>();
    
    public TagSourceCollection() {
        base (LibraryPhoto.global, Tag.BACKLINK_NAME, "TagSourceCollection", get_tag_key);
    }
    
    private static int64 get_tag_key(DataSource source) {
        Tag tag = (Tag) source;
        TagID tag_id = tag.get_tag_id();
        
        return tag_id.id;
    }
    
    protected override Gee.Collection<ContainerSource>? get_containers_holding_source(DataSource source) {
        return fetch_for_photo((LibraryPhoto) source);
    }
    
    protected override ContainerSource? convert_backlink_to_container(SourceBacklink backlink) {
        TagID tag_id = Tag.id_from_backlink(backlink);
        
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
    
    // Returns a list of all Tags associated with the Photo in no particular order.
    public Gee.List<Tag>? fetch_for_photo(LibraryPhoto photo) {
        Gee.List<Tag>? tags = photo_map.get(photo);
        if (tags == null)
            return null;
        
        Gee.List<Tag> copy = new Gee.ArrayList<Tag>();
        copy.add_all(tags);
        
        return copy;
    }
    
    // Returns a sorted set of all Tags associated with the Photo (ascending by name).
    public Gee.SortedSet<Tag>? fetch_sorted_for_photo(LibraryPhoto photo) {
        Gee.SortedSet<Tag>? tags = sorted_photo_map.get(photo);
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
    
    private override void notify_items_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            Tag tag = (Tag) object;
            
            assert(!name_map.has_key(tag.get_name()));
            name_map.set(tag.get_name(), tag);
        }
        
        base.notify_items_added(added);
    }
    
    private override void notify_items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            Tag tag = (Tag) object;
            
            bool unset = name_map.unset(tag.get_name());
            assert(unset);
        }
        
        base.notify_items_removed(removed);
    }
    
    public override void notify_item_altered(DataObject item, Alteration alteration) {
        Tag tag = (Tag) item;
        
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
        
        base.notify_item_altered(item, alteration);
    }
    
    private static int compare_tag_name(void *a, void *b) {
        return ((Tag *) a)->get_name().collate(((Tag *) b)->get_name());
    }
    
    public override void notify_container_contents_added(ContainerSource container, 
        Gee.Collection<DataSource> added) {
        Tag tag = (Tag) container;
        Gee.Collection<LibraryPhoto> photos = (Gee.Collection<LibraryPhoto>) added;
        
        foreach (LibraryPhoto photo in photos) {
            Gee.List<Tag>? tags = photo_map.get(photo);
            if (tags == null) {
                tags = new Gee.ArrayList<Tag>();
                photo_map.set(photo, tags);
            }
            
            bool is_added = tags.add(tag);
            assert(is_added);
            
            Gee.SortedSet<Tag>? sorted_tags = sorted_photo_map.get(photo);
            if (sorted_tags == null) {
                sorted_tags = new Gee.TreeSet<Tag>(compare_tag_name);
                sorted_photo_map.set(photo, sorted_tags);
            }
            
            is_added = sorted_tags.add(tag);
            assert(is_added);
        }
        
        base.notify_container_contents_added(container, added);
    }
    
    public override void notify_container_contents_removed(ContainerSource container, 
        Gee.Collection<DataSource> removed) {
        Tag tag = (Tag) container;
        Gee.Collection<LibraryPhoto> photos = (Gee.Collection<LibraryPhoto>) removed;
        
        foreach (LibraryPhoto photo in photos) {
            Gee.List<Tag>? tags = photo_map.get(photo);
            assert(tags != null);
            
            bool is_removed = tags.remove(tag);
            assert(is_removed);
            
            if (tags.size == 0)
                photo_map.unset(photo);
            
            Gee.SortedSet<Tag>? sorted_tags = sorted_photo_map.get(photo);
            assert(sorted_tags != null);
            
            is_removed = sorted_tags.remove(tag);
            assert(is_removed);
            
            if (sorted_tags.size == 0)
                sorted_photo_map.unset(photo);
        }
        
        base.notify_container_contents_removed(container, removed);
    }
}

public class Tag : DataSource, ContainerSource, Proxyable {
    public const string BACKLINK_NAME = "tag";
    
    private class TagSnapshot : SourceSnapshot {
        private TagRow row;
        private Gee.HashSet<LibraryPhoto> photos = new Gee.HashSet<LibraryPhoto>();
        
        public TagSnapshot(Tag tag) {
            // stash current state of Tag
            row = tag.row;
            
            // stash photos attached to this tag ... if any are destroyed, the tag cannot be
            // reconstituted
            foreach (LibraryPhoto photo in tag.get_photos())
                photos.add(photo);
            
            LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
        }
        
        ~TagSnapshot() {
            LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
        }
        
        public TagRow get_row() {
            return row;
        }
        
        public override void notify_broken() {
            row = TagRow();
            photos.clear();
            
            base.notify_broken();
        }
        
        private void on_photo_destroyed(DataSource source) {
            if (photos.contains((LibraryPhoto) source))
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
    private ViewCollection photos;
    
    private Tag(TagRow row, int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        this.row = row;
        
        // convert PhotoIDs to LibraryPhotos and PhotoViews for the internal ViewCollection
        Gee.ArrayList<LibraryPhoto> photo_list = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<PhotoView> photo_views = new Gee.ArrayList<PhotoView>();
        if (this.row.photo_id_list != null) {
            foreach (PhotoID photo_id in this.row.photo_id_list) {
                LibraryPhoto photo = LibraryPhoto.global.fetch(photo_id);
                if (photo == null)
                    continue;
                
                photo_list.add(photo);
                photo_views.add(new PhotoView(photo));
            }
        } else {
            // allocate the photo_id_list for use if/when photos are added
            this.row.photo_id_list = new Gee.HashSet<PhotoID?>(PhotoID.hash, PhotoID.equal);
        }
        
        // add to internal ViewCollection, which maintains photos associated with this tag
        photos = new ViewCollection("ViewCollection for tag %lld".printf(row.tag_id.id));
        photos.add_many(photo_views);
        
        // need to do this manually here because only want to monitor photo_contents_altered
        // after add_many() here; but need to keep the TagSourceCollection apprised
        if (photo_list.size > 0) {
            global.notify_container_contents_added(this, photo_list);
            global.notify_container_contents_altered(this, photo_list, null);
        }
        
        // monitor ViewCollection to (a) keep the in-memory list of photo IDs up-to-date, and
        // (b) update the database whenever there's a change;
        photos.contents_altered.connect(on_photos_contents_altered);
        
        // monitor LibraryPhoto to trap when photos are destroyed and automatically remove from
        // the tag
        LibraryPhoto.global.items_destroyed.connect(on_photos_destroyed);
    }
    
    ~Tag() {
        photos.contents_altered.disconnect(on_photos_contents_altered);
        LibraryPhoto.global.items_destroyed.disconnect(on_photos_destroyed);
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
            
            if (tag.get_photos_count() != 0) {
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
        if (name == null)
            return null;
        
        string new_name = name.strip();
        
        return (!is_string_empty(new_name)) ? new_name : null;
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
    
    public override string get_name() {
        return row.name;
    }
    
    public override string to_string() {
        return "Tag %s (%d photos)".printf(row.name, photos.get_count());
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
    
    public static TagID id_from_backlink(SourceBacklink backlink) {
        return TagID(backlink.value.to_int64());
    }
    
    public bool has_links() {
        return LibraryPhoto.global.has_backlink(get_backlink());
    }
    
    public SourceBacklink get_backlink() {
        return new SourceBacklink(BACKLINK_NAME, row.tag_id.id.to_string());
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
    
    public void attach(LibraryPhoto photo) {
        if (!photos.has_view_for_source(photo))
            photos.add(new PhotoView(photo));
    }
    
    public void attach_many(Gee.Collection<LibraryPhoto> sources) {
        Gee.ArrayList<PhotoView> view_list = new Gee.ArrayList<PhotoView>();
        foreach (LibraryPhoto photo in sources) {
            if (!photos.has_view_for_source(photo))
                view_list.add(new PhotoView(photo));
        }
        
        if (view_list.size > 0)
            photos.add_many(view_list);
    }
    
    public bool detach(LibraryPhoto photo) {
        DataView? view = photos.get_view_for_source(photo);
        if (view == null)
            return false;
        
        photos.remove_marked(photos.mark(view));
        
        return true;
    }
    
    public int detach_many(Gee.Collection<LibraryPhoto> sources) {
        int count = 0;
        
        Marker marker = photos.start_marking();
        foreach (LibraryPhoto photo in sources) {
            DataView? view = photos.get_view_for_source(photo);
            if (view == null)
                continue;
            
            marker.mark(view);
            count++;
        }
        
        photos.remove_marked(marker);
        
        return count;
    }
    
    // Returns false if the name already exists
    public bool rename(string new_name) {
        if (Tag.global.exists(new_name))
            return false;
        
        try {
            TagTable.get_instance().rename(row.tag_id, new_name);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        row.name = new_name;
        
        notify_altered(new Alteration("metadata", "name"));
        
        return true;
    }
    
    public bool contains(LibraryPhoto photo) {
        return photos.has_view_for_source(photo);
    }
    
    public int get_photos_count() {
        return photos.get_count();
    }
    
    public Gee.Collection<LibraryPhoto> get_photos() {
        return (Gee.Collection<LibraryPhoto>) photos.get_sources();
    }
    
    public void mirror_photos(ViewCollection view, CreateView mirroring_ctor) {
        view.mirror(photos, mirroring_ctor);
    }
    
    private void on_photos_contents_altered(Gee.Iterable<DataView>? added,
        Gee.Iterable<DataView>? removed) {
        Gee.Collection<LibraryPhoto> added_photos = null;
        if (added != null) {
            added_photos = new Gee.ArrayList<LibraryPhoto>();
            foreach (DataView view in added) {
                LibraryPhoto photo = (LibraryPhoto) view.get_source();
                
                // possible a photo is added twice if the same tag is in photo ... add()
                // returns true only if the set has altered
                if (!row.photo_id_list.contains(photo.get_photo_id())) {
                    bool is_added = row.photo_id_list.add(photo.get_photo_id());
                    assert(is_added);
                }
                
                bool is_added = added_photos.add(photo);
                assert(is_added);
            }
        }
        
        Gee.Collection<LibraryPhoto> removed_photos = null;
        if (removed != null) {
            removed_photos = new Gee.ArrayList<LibraryPhoto>();
            foreach (DataView view in removed) {
                LibraryPhoto photo = (LibraryPhoto) view.get_source();
                
                bool is_removed = row.photo_id_list.remove(photo.get_photo_id());
                assert(is_removed);
                
                bool is_added = removed_photos.add(photo);
                assert(is_added);
            }
        }
        
        try {
            TagTable.get_instance().set_tagged_photos(row.tag_id, row.photo_id_list);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // notify of changes to this tag
        if (added_photos != null)
            global.notify_container_contents_added(this, added_photos);
        
        if (removed_photos != null)
            global.notify_container_contents_removed(this, removed_photos);
        
        if (added_photos != null || removed_photos != null)
            global.notify_container_contents_altered(this, added_photos, removed_photos);
        
        // if no more photos, tag evaporates; do not touch "this" afterwards
        if (photos.get_count() == 0)
            global.evaporate(this);
    }
    
    private void on_photos_destroyed(Gee.Collection<DataSource> sources) {
        detach_many((Gee.Collection<LibraryPhoto>) sources);
    }
    
    public override void destroy() {
        // detach all remaining photos from the tag, so observers are informed ... need to detach
        // the contents_altered handler because it will destroy this object when photos is empty,
        // which is bad reentrancy mojo (but hook it back up for the dtor's sake)
        if (photos.get_count() > 0) {
            photos.contents_altered.disconnect(on_photos_contents_altered);
            
            Gee.ArrayList<LibraryPhoto> removed = new Gee.ArrayList<LibraryPhoto>();
            removed.add_all((Gee.Collection<LibraryPhoto>) photos.get_sources());
            
            photos.clear();
            
            global.notify_container_contents_removed(this, removed);
            global.notify_container_contents_altered(this, null, removed);
            
            photos.contents_altered.connect(on_photos_contents_altered);
        }
        
        try {
            TagTable.get_instance().remove(row.tag_id);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        base.destroy();
    }
}

