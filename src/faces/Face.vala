/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if ENABLE_FACES
public class FaceSourceCollection : ContainerSourceCollection {
    private Gee.HashMap<string, Face> name_map = new Gee.HashMap<string, Face>
        ((Gee.HashDataFunc)Face.hash_name_string, (Gee.EqualDataFunc)Face.equal_name_strings);
    private Gee.HashMap<MediaSource, Gee.List<Face>> source_map =
        new Gee.HashMap<MediaSource, Gee.List<Face>>();
    
    public FaceSourceCollection() {
        base (Face.TYPENAME, "FaceSourceCollection", get_face_key);

        attach_collection(LibraryPhoto.global);
    }
    
    public override bool holds_type_of_source(DataSource source) {
        return source is Face;
    }
    
    private static int64 get_face_key(DataSource source) {
        return ((Face) source).get_instance_id();
    }
    
    protected override Gee.Collection<ContainerSource>? get_containers_holding_source(DataSource source) {
        return fetch_for_source((MediaSource) source);
    }
    
    public override ContainerSource? convert_backlink_to_container(SourceBacklink backlink) {
        FaceID face_id = FaceID(backlink.instance_id);
        
        Face? face = fetch(face_id);
        if (face != null)
            return face;
        
        foreach (ContainerSource container in get_holding_tank()) {
            face = (Face) container;
            if (face.get_face_id().id == face_id.id)
                return face;
        }
        
        return null;
    }
    
    public Face? fetch(FaceID face_id) {
        return (Face) fetch_by_key(face_id.id);
    }
    
    public bool exists(string name) {
        return name_map.has_key(name);
    }
    
    public Gee.Collection<string> get_all_names() {
        return name_map.keys;
    }
    
    // Returns a list of all Faces associated with the media source in no particular order.
    //
    // NOTE: As a search optimization, this returns the list that is maintained by Faces.global.
    // Do NOT modify this list.
    public Gee.List<Face>? fetch_for_source(MediaSource source) {
        return source_map.get(source);
    }
    
    // Returns null if not Face with name exists.
    public Face? fetch_by_name(string name) {
        return name_map.get(name);
    }
    
    public Face? restore_face_from_holding_tank(string name) {
        Face? found = null;
        foreach (ContainerSource container in get_holding_tank()) {
            Face face = (Face) container;
            if (face.get_name() == name) {
                found = face;
                
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
            Face face = (Face) object;
            
            assert(!name_map.has_key(face.get_name()));
            name_map.set(face.get_name(), face);
        }
        
        base.notify_items_added(added);
    }
    
    protected override void notify_items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            Face face = (Face) object;
            
            bool unset = name_map.unset(face.get_name());
            assert(unset);
        }
        
        base.notify_items_removed(removed);
    }
    
    protected override void notify_items_altered(Gee.Map<DataObject, Alteration> map) {
        foreach (DataObject object in map.keys) {
            Face face = (Face) object;
            
            string? old_name = null;
            
            // look for this face being renamed
            Gee.MapIterator<string, Face> iter = name_map.map_iterator();
            while (iter.next()) {
                if (!iter.get_value().equals(face))
                    continue;
                
                old_name = iter.get_key();
                
                break;
            }
            
            assert(old_name != null);
            
            if (face.get_name() != old_name) {
                name_map.unset(old_name);
                name_map.set(face.get_name(), face);
            }
        }
        
        base.notify_items_altered(map);
    }
    
    protected override void notify_container_contents_added(ContainerSource container, 
        Gee.Collection<DataObject> added, bool relinking) {
        Face face = (Face) container;
        Gee.Collection<MediaSource> sources = (Gee.Collection<MediaSource>) added;
        
        foreach (MediaSource source in sources) {
            Gee.List<Face>? faces = source_map.get(source);
            if (faces == null) {
                faces = new Gee.ArrayList<Face>();
                source_map.set(source, faces);
            }
            
            bool is_added = faces.add(face);
            assert(is_added);
        }
        
        base.notify_container_contents_added(container, added, relinking);
    }
    
    protected override void notify_container_contents_removed(ContainerSource container, 
        Gee.Collection<DataObject> removed, bool unlinking) {
        Face face = (Face) container;
        Gee.Collection<MediaSource> sources = (Gee.Collection<MediaSource>) removed;
        
        foreach (MediaSource source in sources) {
            Gee.List<Face>? faces = source_map.get(source);
            assert(faces != null);
            
            bool is_removed = faces.remove(face);
            assert(is_removed);
            
            if (faces.size == 0)
                source_map.unset(source);
        }
        
        base.notify_container_contents_removed(container, removed, unlinking);
    }
}

public class Face : DataSource, ContainerSource, Proxyable, Indexable {
    public const string TYPENAME = "face";
    
    private class FaceSnapshot : SourceSnapshot {
        private FaceRow row;
        private Gee.HashSet<MediaSource> sources = new Gee.HashSet<MediaSource>();
        
        public FaceSnapshot(Face face) {
            // stash current state of Face
            row = face.row;
            
            // stash photos attached to this face ... if any are destroyed, the face
            // cannot be reconstituted
            foreach (MediaSource source in face.get_sources())
                sources.add(source);
            
            LibraryPhoto.global.item_destroyed.connect(on_source_destroyed);
        }
        
        ~FaceSnapshot() {
            LibraryPhoto.global.item_destroyed.disconnect(on_source_destroyed);
        }
        
        public FaceRow get_row() {
            return row;
        }
        
        public override void notify_broken() {
            row = new FaceRow();
            sources.clear();
            
            base.notify_broken();
        }
        
        private void on_source_destroyed(DataSource source) {
            if (sources.contains((MediaSource) source))
                notify_broken();
        }
    }
    
    private class FaceProxy : SourceProxy {
        public FaceProxy(Face face) {
            base (face);
        }
        
        public override DataSource reconstitute(int64 object_id, SourceSnapshot snapshot) {
            return Face.reconstitute(object_id, ((FaceSnapshot) snapshot).get_row());
        }
    }
    
    public static FaceSourceCollection global = null;
    
    private FaceRow row;
    private ViewCollection media_views;
    private string? name_collation_key = null;
    private bool unlinking = false;
    private bool relinking = false;
    private string? indexable_keywords = null;
    
    private Face(FaceRow row, int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        this.row = row;
        
        // normalize user text
        this.row.name = prep_face_name(this.row.name);
        
        Gee.Set<PhotoID?> photo_id_list = FaceLocation.get_photo_ids_by_face(this);
        Gee.ArrayList<Photo> photo_list = new Gee.ArrayList<Photo>();
        Gee.ArrayList<ThumbnailView> thumbnail_views = new Gee.ArrayList<ThumbnailView>();
        if (photo_id_list != null) {
            foreach (PhotoID photo_id in photo_id_list) {
                MediaSource? current_source =
                    LibraryPhoto.global.fetch_by_source_id(PhotoID.upgrade_photo_id_to_source_id(photo_id));
                if (current_source == null)
                    continue;
                
                photo_list.add((Photo) current_source);
                thumbnail_views.add(new ThumbnailView(current_source));
            }
        }
        
        // add to internal ViewCollection, which maintains media sources associated with this face
        media_views = new ViewCollection("ViewCollection for face %s".printf(row.face_id.id.to_string()));
        media_views.add_many(thumbnail_views);
        
        // need to do this manually here because only want to monitor photo_contents_altered
        // after add_many() here; but need to keep the FaceSourceCollection apprised
        if (photo_list.size > 0) {
            global.notify_container_contents_added(this, photo_list, false);
            global.notify_container_contents_altered(this, photo_list, false, null, false);
        }
        
        // monitor ViewCollection to (a) keep the in-memory list of source ids up-to-date, and
        // (b) update the database whenever there's a change;
        media_views.contents_altered.connect(on_media_views_contents_altered);
        
        // monitor the global collections to trap when photos are destroyed, then
        // automatically remove from the face
        LibraryPhoto.global.items_destroyed.connect(on_sources_destroyed);
        
        update_indexable_keywords();
    }
    
    ~Face() {
        media_views.contents_altered.disconnect(on_media_views_contents_altered);
        LibraryPhoto.global.items_destroyed.disconnect(on_sources_destroyed);
    }
    
    public static void init(ProgressMonitor? monitor) {
        global = new FaceSourceCollection();
        
        // scoop up all the rows at once
        Gee.List<FaceRow?> rows = null;
        try {
            rows = FaceTable.get_instance().get_all_rows();
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // turn them into Face objects
        Gee.ArrayList<Face> faces = new Gee.ArrayList<Face>();
        Gee.ArrayList<Face> unlinked = new Gee.ArrayList<Face>();
        int count = rows.size;
        for (int ctr = 0; ctr < count; ctr++) {
            FaceRow row = rows.get(ctr);
            
            // make sure the face name is valid
            string? name = prep_face_name(row.name);
            if (name == null) {
                // TODO: More graceful handling of this situation would be to rename the face or
                // alert the user.
                warning("Invalid face name \"%s\": removing from database", row.name);
                try {
                    FaceTable.get_instance().remove(row.face_id);
                } catch (DatabaseError err) {
                    warning("Unable to delete face \"%s\": %s", row.name, err.message);
                }
                
                continue;
            }
            
            row.name = name;
            
            Face face = new Face(row);
            if (monitor != null)
                monitor(ctr, count);
            
            if (face.get_sources_count() != 0) {
                faces.add(face);
                
                continue;
            }
            
            if (face.has_links()) {
                face.rehydrate_backlinks(global, null);
                unlinked.add(face);
                
                continue;
            }
            
            warning("Empty face %s found with no backlinks, destroying", face.to_string());
            face.destroy_orphan(true);
        }
        
        // add them all at once to the SourceCollection
        global.add_many(faces);
        global.init_add_many_unlinked(unlinked);
    }
    
    public static void terminate() {
    }
    
    public static int compare_names(void *a, void *b) {
        Face *aface = (Face *) a;
        Face *bface = (Face *) b;
        
        return String.precollated_compare(aface->get_name(), aface->get_name_collation_key(),
            bface->get_name(), bface->get_name_collation_key());
    }
    
    public static uint hash_name_string(void *a) {
        return String.collated_hash(a);
    }
    
    public static bool equal_name_strings(void *a, void *b) {
        return String.collated_equals(a, b);
    }
    
    // Returns a Face for the name, creating a new empty one if it does not already exist.
    // name should have already been prepared by prep_face_name.
    public static Face for_name(string name) {
        Face? face = global.fetch_by_name(name);
        if (face == null)
            face = global.restore_face_from_holding_tank(name);
        
        if (face != null)
            return face;
        
        // create a new Face for this name
        try {
            face = new Face(FaceTable.get_instance().add(name));
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        global.add(face);
        
        return face;
    }
    
    // Utility function to cleanup a face name that comes from user input and prepare it for use
    // in the system and storage in the database.  Returns null if the name is unacceptable.
    public static string? prep_face_name(string name) {
        return prepare_input_text(name, PrepareInputTextOptions.DEFAULT, DEFAULT_USER_TEXT_INPUT_LENGTH);
    }
    
    public override string get_typename() {
        return TYPENAME;
    }
    
    public override int64 get_instance_id() {
        return get_face_id().id;
    }
    
    public override string get_name() {
        return row.name;
    }
    
    public string get_name_collation_key() {
        if (name_collation_key == null)
            name_collation_key = row.name.collate_key();
        
        return name_collation_key;
    }
    
    public override string to_string() {
        return "Face %s (%d sources)".printf(row.name, media_views.get_count());
    }
    
    public override bool equals(DataSource? source) {
        // Validate uniqueness of primary key
        Face? face = source as Face;
        if (face != null) {
            if (face != this) {
                assert(face.row.face_id.id != row.face_id.id);
            }
        }
        
        return base.equals(source);
    }
    
    public FaceID get_face_id() {
        return row.face_id;
    }
    
    public override SourceSnapshot? save_snapshot() {
        return new FaceSnapshot(this);
    }
    
    public SourceProxy get_proxy() {
        return new FaceProxy(this);
    }
    
    private static Face reconstitute(int64 object_id, FaceRow row) {
        // fill in the row with the new FaceID for this reconstituted face
        try {
            row.face_id = FaceTable.get_instance().create_from_row(row);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        Face face = new Face(row, object_id);
        global.add(face);
        
        debug("Reconstituted %s", face.to_string());
        
        return face;
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
        indexable_keywords = prepare_indexable_string(get_name());
    }
    
    public unowned string? get_indexable_keywords() {
        return indexable_keywords;
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
        string? new_name = prep_face_name(name);
        if (new_name == null)
            return false;
        
        if (Face.global.exists(new_name))
            return false;
        
        try {
            FaceTable.get_instance().rename(row.face_id, new_name);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
            return false;
        }
        
        row.name = new_name;
        name_collation_key = null;
        
        update_indexable_keywords();
        
        notify_altered(new Alteration.from_list("metadata:name, indexable:keywords"));
        
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
        Gee.Set<PhotoID?>? photo_id_list = FaceLocation.get_photo_ids_by_face(this);
        
        Gee.Collection<Photo> added_photos = null;
        if (added != null) {
            added_photos = new Gee.ArrayList<Photo>();
            foreach (DataView view in added) {
                Photo photo = (Photo) view.get_source();
                
                if (photo_id_list != null)
                    assert(!photo_id_list.contains(photo.get_photo_id()));
                
                bool is_added = added_photos.add(photo);
                assert(is_added);
            }
        }
        
        Gee.Collection<Photo> removed_photos = null;
        if (removed != null) {
            assert(photo_id_list != null);
            
            removed_photos = new Gee.ArrayList<Photo>();
            foreach (DataView view in removed) {
                Photo photo = (Photo) view.get_source();
                
                assert(photo_id_list.contains(photo.get_photo_id()));
                
                bool is_added = removed_photos.add(photo);
                assert(is_added);
            }
        }
        
        if (removed_photos != null)
            foreach (Photo photo in removed_photos)
                FaceLocation.destroy(get_face_id(), photo.get_photo_id());
        
        // notify of changes to this face
        if (added_photos != null)
            global.notify_container_contents_added(this, added_photos, relinking);
        
        if (removed_photos != null)
            global.notify_container_contents_removed(this, removed_photos, unlinking);
        
        if (added_photos != null || removed_photos != null) {
            global.notify_container_contents_altered(this, added_photos, relinking, removed_photos,
                unlinking);
        }
        
        // if no more sources, face evaporates; do not touch "this" afterwards
        if (media_views.get_count() == 0)
            global.evaporate(this);
    }
    
    private void on_sources_destroyed(Gee.Collection<DataSource> sources) {
        detach_many((Gee.Collection<MediaSource>) sources);
    }
    
    public override void destroy() {
        // detach all remaining sources from the face, so observers are informed ... need to detach
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
            FaceTable.get_instance().remove(row.face_id);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        base.destroy();
    }
}

#endif
