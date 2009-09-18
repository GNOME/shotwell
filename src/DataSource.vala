/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

//
// DataObject
//

public abstract class DataObject : Object {
    protected DataCollection member_of = null;

    // This signal is fired when the source of the data is altered in a way that's significant
    // to how it's represented in the application.  This base signal must be called by child
    // classes if the collection it is a member of is to be notified.
    public virtual signal void altered() {
    }
    
    // XXX: Because the "this" variable is not available in virtual signals, using this method
    // to signal until bug is fixed.
    //
    // See: https://bugzilla.gnome.org/show_bug.cgi?id=593734
    public void notify_altered() {
        altered();
        if (member_of != null)
            member_of.internal_notify_altered(this);
    }
    
    // This signal is fired prior to the object being destroyed.  It is up to all observers to 
    // drop their references to the DataObject.
    public virtual signal void destroyed() {
    }
    
    public abstract string get_name();
    
    // Child classes should call this base class to ensure that the collection this object is
    // a member of is notified and the signal is properly called.  The collection will remove this
    // object automatically.
    public virtual void destroy() {
        destroyed();
        if (member_of != null)
            member_of.internal_notify_destroyed(this);
    }
    
    public DataCollection? get_membership() {
        return member_of;
    }
    
    // This method is only called by DataCollection.
    public void internal_set_membership(DataCollection collection) {
        member_of = collection;
    }
    
    // This method is only called by DataCollection
    public void internal_clear_membership() {
        member_of = null;
    }
}

public abstract class DataSource : DataObject {
    // This signal is fired when some attribute or property of the data is altered, but not its
    // primary representation.  This base signal must be called by child classes if the collection
    // this source is a member of is to be notifed.
    public virtual signal void metadata_altered() {
    }

    // XXX: Because the "this" variable is not available in virtual signals, using this method
    // to signal until bug is fixed.
    //
    // See: https://bugzilla.gnome.org/show_bug.cgi?id=593734
    public void notify_metadata_altered() {
        metadata_altered();

        SourceCollection sc = member_of as SourceCollection;
        if (sc != null)
            sc.internal_notify_metadata_altered(this);
    }
}

public abstract class PhotoSource : DataSource {
    public abstract time_t get_exposure_time();

    public abstract Dimensions get_dimensions();

    public abstract uint64 get_filesize();

    public abstract Exif.Data? get_exif();
}

public abstract class EventSource : DataSource {
    public abstract time_t get_start_time();

    public abstract time_t get_end_time();

    public abstract uint64 get_total_filesize();
    
    public abstract int get_photo_count();
    
    public abstract Gee.Iterable<PhotoSource> get_photos();
}

//
// DataCollection
//

public class DataCollection {
    private Gee.ArrayList<DataObject> list = new Gee.ArrayList<DataObject>();
    private Gee.HashSet<DataObject> hash_set = new Gee.HashSet<DataObject>();
    private Gee.HashSet<DataObject> marked = new Gee.HashSet<DataObject>();

    // When this signal has been fired, the added items are part of the collection
    public virtual signal void items_added(Gee.Iterable<DataObject> added) {
    }
    
    // When this signal is fired, the removed items are still part of the collection
    public virtual signal void items_removed(Gee.Iterable<DataObject> removed) {
    }
    
    // This signal fires whenever any item in the collection signals it has been altered ...
    // this allows monitoring of all objects in the collection without having to register a
    // signal handler for each one
    public virtual signal void item_altered(DataObject item) {
    }

    // When this signal is fired, the item is still part of the collection
    public virtual signal void item_destroyed(DataObject object) {
    }
    
    public DataCollection() {
    }
    
    // A singleton list is used when a single item has been added/remove/selected/unselected
    // and needs to be reported via a signal, which uses a list as a parameter ... although this
    // seems wasteful, can't reuse a single singleton list because it's possible for a method
    // that needs it to be called from within a signal handler for another method, corrupting the
    // list's contents mid-signal
    private static Gee.ArrayList<DataObject> get_singleton(DataObject object) {
        Gee.ArrayList<DataObject> singleton = new Gee.ArrayList<DataObject>();
        singleton.add(object);
        
        return singleton;
    }
    
    public Gee.Iterable<DataObject>? get_all() {
        return list;
    }
    
    public int get_count() {
        return list.size;
    }
    
    public DataObject? get_at(int index) {
        return (list.size > 0) ? list.get(index) : null;
    }
    
    public DataObject? get_first() {
        return (list.size > 0) ? list.get(0) : null;
    }
    
    public DataObject? get_last() {
        return (list.size > 0) ? list.get(list.size - 1) : null;
    }
    
    public DataObject? get_next(DataObject object) {
        if (list.size == 0)
            return null;
        
        int index = list.index_of(object);
        if (index < 0)
            return null;
        
        index++;
        if (index >= list.size)
            index = 0;
        
        return list.get(index);
    }
    
    public DataObject? get_previous(DataObject object) {
        if (list.size == 0)
            return null;
        
        int index = list.index_of(object);
        if (index < 0)
            return null;
        
        index--;
        if (index < 0)
            index = list.size - 1;
        
        return list.get(index);
    }
    
    public bool contains(DataObject object) {
        if (!hash_set.contains(object))
            return false;
        
        assert(object.get_membership() == this);
        
        return true;
    }
    
    private void internal_add(DataObject object) {
        object.internal_set_membership(this);
        
        bool added = list.add(object);
        assert(added);
        added = hash_set.add(object);
        assert(added);
    }
    
    private void internal_remove(DataObject object) {
        object.internal_clear_membership();
        
        bool removed = list.remove(object);
        assert(removed);
        removed = hash_set.remove(object);
        assert(removed);
    }
    
    // Returns false if item is already part of the collection.
    public bool add(DataObject object) {
        if (contains(object))
            return false;
        
        internal_add(object);
        
        // fire signal after added with singleton list
        items_added(get_singleton(object));
        
        return true;
    }
    
    // Returns number of items added to collection.
    public int add_many(Gee.Iterable<DataObject> objects) {
        Gee.ArrayList<DataObject> added = new Gee.ArrayList<DataObject>();
        foreach (DataObject object in objects) {
            if (contains(object))
                continue;
            
            internal_add(object);
            added.add(object);
        }
        
        // signal once all have been added
        if (added.size > 0)
            items_added(added);
        
        return added.size;
    }
    
    // Clears the list of marked objects
    public void reset_mark() {
        marked.clear();
    }

    // Returns false if item is not in collection.
    public bool mark(DataObject object) {
        if (!contains(object))
            return false;
        
        marked.add(object);
        
        return true;
    }
    
    // Returns number of objects marked for removal.
    public int mark_many(Gee.Iterable<DataObject> objects) {
        int count = 0;
        foreach (DataObject object in objects) {
            if (!contains(object))
                continue;
            
            marked.add(object);
            count++;
        }
        
        return count;
    }
    
    // Returns false if the object is not a member of the collection
    public bool remove(DataObject object) {
        if (!contains(object))
            return false;
        
        // signal before removing using a singleton
        items_removed(get_singleton(object));
        
        internal_remove(object);
        
        return true;
    }
    
    // Remove marked items from collection.  This two-step process allows for iterating in a foreach
    // loop and removing without creating a separate list.  Returns number of items removed.
    public int remove_marked() {
        if (marked.size == 0)
            return 0;
        
        // signal before removing
        items_removed(marked);
        
        foreach (DataObject object in marked)
            internal_remove(object);
        
        int count = marked.size;
        marked.clear();
        
        return count;
    }
    
    // Destroy all marked items.  This allows for iterating in a foreach loop and destroying without
    // creating a separate list.  Returns number of items destroyed.
    public int destroy_marked() {
        if (marked.size == 0)
            return 0;
        
        // No need to remove; the destroy signal from the object does that for us.
        foreach (DataObject object in marked)
            object.destroy();
        
        int count = marked.size;
        marked.clear();
        
        return count;
    }
    
    public void clear() {
        if (list.size == 0)
            return;
        
        items_removed(list);
        
        // remove after firing the signal
        foreach (DataObject object in list)
            internal_remove(object);
        
        assert(list.size == 0);
        assert(hash_set.size == 0);
    }
    
    // This method is only called by DataObject to report when it has been altered, so observers of
    // this collection may be notified as well.
    public void internal_notify_altered(DataObject object) {
        assert(contains(object));
        
        item_altered(object);
    }
    
    // This method is only called by DataObject to report when it is being destroyed, so observers
    // of this collection may be notified as well.
    public void internal_notify_destroyed(DataObject object) {
        assert(contains(object));
        
        // report to observers
        items_removed(get_singleton(object));
        item_destroyed(object);
        
        // remove from collection
        internal_remove(object);
    }
}

public class SourceCollection : DataCollection {
    // This signal fires whenever any item in the collection signals its metadata has been altered ...
    // this allows monitoring of all objects in the collection without having to register a
    // signal handler for each one
    public virtual signal void item_metadata_altered(DataSource source) {
    }
    
    // This method is only called by DataSource to report when its metadata has been altered, so
    // observers of this collection may be notified as well.
    public void internal_notify_metadata_altered(DataSource source) {
        assert(contains(source));
        
        item_metadata_altered(source);
    }
}

public delegate int64 GetSourceDatabaseKey(DataSource source);

// A DatabaseSourceCollection is a SourceCollection that understands database keys (IDs) and the
// nature that a row in a database can only be instantiated once in the system, and so it tracks
// their existance in a map so they can be fetched by their key.
public class DatabaseSourceCollection : SourceCollection {
    private GetSourceDatabaseKey source_key_func;
    private Gee.HashMap<int64?, DataSource> map = new Gee.HashMap<int64?, DataSource>(int64_hash, 
        int64_equal, direct_equal);
        
    public DatabaseSourceCollection(GetSourceDatabaseKey source_key_func) {
        this.source_key_func = source_key_func;
    }

    public override void items_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            DataSource source = (DataSource) object;
            int64 key = source_key_func(source);
            
            assert(!map.contains(key));
            
            map.set(key, source);
        }
        
        base.items_added(added);
    }
    
    public override void items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            int64 key = source_key_func((DataSource) object);

            bool is_removed = map.remove(key);
            assert(is_removed);
        }
        
        base.items_removed(removed);
    }
    
    protected DataSource fetch_by_key(int64 key) {
        return map.get(key);
    }
}
