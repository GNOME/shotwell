/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class TagSourceCollection : DatabaseSourceCollection {
    private Gee.HashMap<string, Tag> map = new Gee.HashMap<string, Tag>();
    
    public virtual signal void item_contents_added(Tag tag, Gee.Collection<LibraryPhoto> photos) {
    }
    
    public virtual signal void item_contents_removed(Tag tag, Gee.Collection<LibraryPhoto> photos) {
    }
    
    public virtual signal void item_contents_altered(Tag tag, Gee.Collection<LibraryPhoto>? added,
        Gee.Collection<LibraryPhoto>? removed) {
    }
    
    public TagSourceCollection() {
        base ("TagSourceCollection", get_tag_key);
    }
    
    private static int64 get_tag_key(DataSource source) {
        Tag tag = (Tag) source;
        TagID tag_id = tag.get_tag_id();
        
        return tag_id.id;
    }
    
    public Tag fetch(TagID tag_id) {
        return (Tag) fetch_by_key(tag_id.id);
    }
    
    public bool exists(string name) {
        return map.has_key(name);
    }
    
    // Returns null if not Tag with name exists.
    public Tag? fetch_by_name(string name) {
        return map.get(name);
    }
    
    private override void notify_items_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            Tag tag = (Tag) object;
            
            assert(!map.has_key(tag.get_name()));
            
            map.set(tag.get_name(), tag);
        }
        
        base.notify_items_added(added);
    }
    
    private override void notify_items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            Tag tag = (Tag) object;
            
            bool unset = map.unset(tag.get_name());
            assert(unset);
        }
        
        base.notify_items_removed(removed);
    }
    
    public virtual void notify_item_contents_added(Tag tag, Gee.Collection<LibraryPhoto> photos) {
        item_contents_added(tag, photos);
    }
    
    public virtual void notify_item_contents_removed(Tag tag, Gee.Collection<LibraryPhoto> photos) {
        item_contents_removed(tag, photos);
    }
    
    public virtual void notify_item_contents_altered(Tag tag, Gee.Collection<LibraryPhoto>? added,
        Gee.Collection<LibraryPhoto>? removed) {
        item_contents_altered(tag, added, removed);
    }
}

public class Tag : DataSource, Proxyable {
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
            
            LibraryPhoto.global.item_destroyed += on_photo_destroyed;
        }
        
        ~TagSnapshot() {
            LibraryPhoto.global.item_destroyed -= on_photo_destroyed;
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
        
        // convert PhotoIDs to LibraryPhoto
        Gee.ArrayList<PhotoView> photo_list = new Gee.ArrayList<PhotoView>();
        if (this.row.photo_id_list != null) {
            foreach (PhotoID photo_id in this.row.photo_id_list) {
                LibraryPhoto photo = LibraryPhoto.global.fetch(photo_id);
                if (photo != null)
                    photo_list.add(new PhotoView(photo));
            }
        } else {
            // allocate the photo_id_list for use if/when photos are added
            this.row.photo_id_list = new Gee.HashSet<PhotoID?>(PhotoID.hash, PhotoID.equal);
        }
        
        // add to internal ViewCollection, which maintains photos associated with this tag
        photos = new ViewCollection("ViewCollection for tag %lld".printf(row.tag_id.id));
        photos.add_many(photo_list);
        
        // monitor ViewCollection to (a) keep the in-memory list of photo IDs up-to-date, and
        // (b) update the database whenever there's a change
        photos.contents_altered += on_photos_contents_altered;
        
        // monitor LibraryPhoto to trap when photos are destroyed and automatically remove from
        // the tag
        LibraryPhoto.global.item_destroyed += on_photo_destroyed;
    }
    
    ~Tag() {
        photos.contents_altered -= on_photos_contents_altered;
        LibraryPhoto.global.item_destroyed -= on_photo_destroyed;
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
        int count = rows.size;
        for (int ctr = 0; ctr < count; ctr++)
            tags.add(new Tag(rows.get(ctr)));
        
        // add them all at once to the SourceCollection
        global.add_many(tags);
    }
    
    public static void terminate() {
    }
    
    // Returns a Tag for the name, creating a new empty one if it does not already exist
    public static Tag for_name(string name) {
        Tag? tag = global.fetch_by_name(name);
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
    
    private static int compare_tag_name(void *a, void *b) {
        return ((Tag *) a)->get_name().collate(((Tag *) b)->get_name());
    }
    
    // Returns a sorted set of all Tags associated with the Photo (ascending by name).
    public static Gee.SortedSet<Tag> get_sorted_tags(LibraryPhoto photo) {
        Gee.SortedSet<Tag> tags = new Gee.TreeSet<Tag>(compare_tag_name);
        collect_tags(photo, tags);
        
        return tags;
    }
    
    // Returns a list of all Tags associated with the Photo, in no guaranteed order.
    public static Gee.List<Tag> get_tags(LibraryPhoto photo) {
        Gee.List<Tag> tags = new Gee.ArrayList<Tag>();
        collect_tags(photo, tags);
        
        return tags;
    }
    
    private static void collect_tags(LibraryPhoto photo, Gee.Collection<Tag> tags) {
        foreach (DataObject object in global.get_all()) {
            Tag tag = (Tag) object;
            
            if (tag.contains(photo))
                tags.add(tag);
        }
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
    
    public void rename(string new_name) {
        try {
            TagTable.get_instance().rename(row.tag_id, new_name);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        row.name = new_name;
        
        notify_altered();
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
                
                bool is_added = row.photo_id_list.add(photo.get_photo_id());
                assert(is_added);
                
                is_added = added_photos.add(photo);
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
        
        // notify of changes to this tag
        if (added_photos != null)
            global.notify_item_contents_added(this, added_photos);
        
        if (removed_photos != null)
            global.notify_item_contents_removed(this, removed_photos);
        
        if (added_photos != null || removed_photos != null)
            global.notify_item_contents_altered(this, added_photos, removed_photos);
        
        // if no more photos, tag evaporates
        if (photos.get_count() == 0) {
            debug("Destroying %s", to_string());
            
            global.destroy_marked(global.mark(this), false);
            
            // exit now, do not touch this or any external representation of Tag from here on
            return;
        }
        
        try {
            TagTable.get_instance().set_tagged_photos(row.tag_id, row.photo_id_list);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        notify_altered();
    }
    
    private void on_photo_destroyed(DataSource source) {
        detach((LibraryPhoto) source);
    }
    
    public override void destroy() {
        // detach all remaining photos from the tag, so observers are informed ... need to detach
        // the contents_altered handler because it will destroy this object when photos is empty,
        // which is bad reentrancy mojo (but hook it back up for the dtor's sake)
        if (photos.get_count() > 0) {
            photos.contents_altered -= on_photos_contents_altered;
            
            Gee.ArrayList<LibraryPhoto> removed = new Gee.ArrayList<LibraryPhoto>();
            removed.add_all((Gee.Collection<LibraryPhoto>) photos.get_sources());
            
            photos.clear();
            
            global.notify_item_contents_removed(this, removed);
            global.notify_item_contents_altered(this, null, removed);
            
            photos.contents_altered += on_photos_contents_altered;
        }
        
        try {
            TagTable.get_instance().remove(row.tag_id);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        base.destroy();
    }
}

