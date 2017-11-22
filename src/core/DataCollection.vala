/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class DataCollection {
    public const int64 INVALID_OBJECT_ORDINAL = -1;
    
    private class MarkerImpl : Object, Marker {
        public DataCollection owner;
        public Gee.HashSet<DataObject> marked = new Gee.HashSet<DataObject>();
        public int freeze_count = 0;
        
        public MarkerImpl(DataCollection owner) {
            this.owner = owner;
            
            // if items are removed from main collection, they're removed from the marked list
            // as well
            owner.items_removed.connect(on_items_removed);
        }
        
        ~MarkerImpl() {
            owner.items_removed.disconnect(on_items_removed);
        }
        
        public void mark(DataObject object) {
            assert(owner.internal_contains(object));
            
            marked.add(object);
        }

        public void unmark(DataObject object) {
            assert(owner.internal_contains(object));
            
            marked.remove(object);
        }

        public bool toggle(DataObject object) {
            assert(owner.internal_contains(object));

            if (marked.contains(object)) {
                marked.remove(object);
            } else {
                marked.add(object);
            }

            return marked.contains(object);
        }
        
        public void mark_many(Gee.Collection<DataObject> list) {
            foreach (DataObject object in list) {
                assert(owner.internal_contains(object));
                
                marked.add(object);
            }
        }
        
        public void unmark_many(Gee.Collection<DataObject> list) {
            foreach (DataObject object in list) {
                assert(owner.internal_contains(object));
                
                marked.remove(object);
            }
        }
        
        public void mark_all() {
            foreach (DataObject object in owner.get_all())
                marked.add(object);
        }
        
        public int get_count() {
            return (marked != null) ? marked.size : freeze_count;
        }
        
        public Gee.Collection<DataObject> get_all() {
            Gee.ArrayList<DataObject> copy = new Gee.ArrayList<DataObject>();
            copy.add_all(marked);
            
            return copy;
        }
        
        private void on_items_removed(Gee.Iterable<DataObject> removed) {
            foreach (DataObject object in removed)
                marked.remove(object);
        }
        
        // This method is called by DataCollection when it starts iterating over the marked list ...
        // the marker at this point stops monitoring the collection, preventing a possible
        // removal during an iteration, which is bad.
        public void freeze() {
            owner.items_removed.disconnect(on_items_removed);
        }
        
        public void finished() {
            if (marked != null)
                freeze_count = marked.size;
            
            marked = null;
        }
        
        public bool is_valid(DataCollection collection) {
            return (collection == owner) && (marked != null);
        }
    }
    
    private string name;
    private DataSet dataset = new DataSet();
    private Gee.HashMap<string, Value?> properties = new Gee.HashMap<string, Value?>();
    private int64 object_ordinal_generator = 0;
    private int notifies_frozen = 0;
    private Gee.HashMap<DataObject, Alteration> frozen_items_altered = null;
    private bool fire_ordering_changed = false;
    
    // When this signal has been fired, the added items are part of the collection
    public virtual signal void items_added(Gee.Iterable<DataObject> added) {
    }
    
    // When this signal is fired, the removed items are no longer part of the collection
    public virtual signal void items_removed(Gee.Iterable<DataObject> removed) {
    }
    
    // When this signal is fired, the removed items are no longer part of the collection
    public virtual signal void contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
    }
    
    // This signal fires whenever any (or multiple) items in the collection signal they've been
    // altered.
    public virtual signal void items_altered(Gee.Map<DataObject, Alteration> items) {
    }

    // Fired when a new sort comparator is registered or an item has moved in the ordering due to
    // an alteration.
    public virtual signal void ordering_changed() {
    }
    
    // Fired when a collection property is set.  The old value is passed as well, null if not set
    // previously.
    public virtual signal void property_set(string name, Value? old, Value val) {
    }
    
    // Fired when a collection property is cleared.
    public virtual signal void property_cleared(string name) {
    }
    
    // Fired when "altered" signal (and possibly other related signals, depending on the subclass)
    // is frozen.
    public virtual signal void frozen() {
    }
    
    // Fired when "altered" signal (and other related signals, depending on the subclass) is
    // restored (thawed).
    public virtual signal void thawed() {
    }
    
    public DataCollection(string name) {
        this.name = name;
    }
    
    ~DataCollection() {
#if TRACE_DTORS
        debug("DTOR: DataCollection %s", name);
#endif
    }
    
    public virtual string to_string() {
        return "%s (%d)".printf(name, get_count());
    }
    
    // use notifies to ensure proper chronology of signal handling
    protected virtual void notify_items_added(Gee.Iterable<DataObject> added) {
        items_added(added);
    }

    protected virtual void notify_items_removed(Gee.Iterable<DataObject> removed) {
        items_removed(removed);
    }
    
    protected virtual void notify_contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        contents_altered(added, removed);
    }
    
    protected virtual void notify_items_altered(Gee.Map<DataObject, Alteration> items) {
        items_altered(items);
    }
    
    protected virtual void notify_ordering_changed() {
        ordering_changed();
    }
    
    protected virtual void notify_property_set(string name, Value? old, Value val) {
        property_set(name, old, val);
    }
    
    protected virtual void notify_property_cleared(string name) {
        property_cleared(name);
    }
    
    // A singleton list is used when a single item has been added/remove/selected/unselected
    // and needs to be reported via a signal, which uses a list as a parameter ... although this
    // seems wasteful, can't reuse a single singleton list because it's possible for a method
    // that needs it to be called from within a signal handler for another method, corrupting the
    // shared list's contents mid-signal
    protected static Gee.Collection<DataObject> get_singleton(DataObject object) {
        return new SingletonCollection<DataObject>(object);
    }
    
    protected static Gee.Map<DataObject, Alteration> get_alteration_singleton(DataObject object,
        Alteration alteration) {
        Gee.Map<DataObject, Alteration> map = new Gee.HashMap<DataObject, Alteration>();
        map.set(object, alteration);
        
        return map;
    }
    
    public virtual bool valid_type(DataObject object) {
        return true;
    }
    
    public unowned Comparator get_comparator() {
        return dataset.get_comparator();
    }
    
    public unowned ComparatorPredicate get_comparator_predicate() {
        return dataset.get_comparator_predicate();
    }
    
    public virtual void set_comparator(Comparator comparator, ComparatorPredicate? predicate) {
        dataset.set_comparator(comparator, predicate);
        notify_ordering_changed();
    }
    
    // Return to natural ordering of DataObjects, which is order-added
    public virtual void reset_comparator() {
        dataset.reset_comparator();
        notify_ordering_changed();
    }
    
    public virtual Gee.Collection<DataObject> get_all() {
        return dataset.get_all();
    }
    
    protected DataSet get_dataset_copy() {
        return dataset.copy();
    }
    
    public virtual int get_count() {
        return dataset.get_count();
    }
    
    public virtual DataObject? get_at(int index) {
        return dataset.get_at(index);
    }
    
    public virtual int index_of(DataObject object) {
        return dataset.index_of(object);
    }
    
    public virtual bool contains(DataObject object) {
        return internal_contains(object);
    }
    
    // Because subclasses may filter out objects (by overriding key methods here), need an
    // internal_contains for consistency checking.
    private bool internal_contains(DataObject object) {
        if (!dataset.contains(object))
            return false;
        
        assert(object.get_membership() == this);
        
        return true;
    }
    
    private void internal_add(DataObject object) {
        assert(valid_type(object));
        
        object.internal_set_membership(this, object_ordinal_generator++);
        
        bool added = dataset.add(object);
        assert(added);
    }
    
    private void internal_add_many(Gee.List<DataObject> objects, ProgressMonitor? monitor) {
        int count = objects.size;
        for (int ctr = 0; ctr < count; ctr++) {
            DataObject object = objects.get(ctr);
            assert(valid_type(object));
            
            object.internal_set_membership(this, object_ordinal_generator++);
            
            if (monitor != null)
                monitor(ctr, count);
        }
        
        bool added = dataset.add_many(objects);
        assert(added);
    }
    
    private void internal_remove(DataObject object) {
        bool removed = dataset.remove(object);
        assert(removed);
        
        object.internal_clear_membership();
    }
    
    // Returns false if item is already part of the collection.
    public virtual bool add(DataObject object) {
        if (internal_contains(object)) {
            debug("%s cannot add %s: already present", to_string(), object.to_string());
            
            return false;
        }
        
        internal_add(object);
        
        // fire signal after added using singleton list
        Gee.Collection<DataObject> added = get_singleton(object);
        notify_items_added(added);
        notify_contents_altered(added, null);
        
        // This must be called *after* the DataCollection has signalled.
        object.notify_membership_changed(this);
        
        return true;
    }
    
    // Returns the items added to the collection.
    public virtual Gee.Collection<DataObject> add_many(Gee.Collection<DataObject> objects, 
        ProgressMonitor? monitor = null) {
        Gee.ArrayList<DataObject> added = new Gee.ArrayList<DataObject>();
        foreach (DataObject object in objects) {
            if (internal_contains(object)) {
                debug("%s cannot add %s: already present", to_string(), object.to_string());
                
                continue;
            }
            
            added.add(object);
        }
        
        int count = added.size;
        if (count == 0)
            return added;
        
        internal_add_many(added, monitor);
        
        // signal once all have been added
        notify_items_added(added);
        notify_contents_altered(added, null);
        
        // This must be called *after* the DataCollection signals have fired.
        for (int ctr = 0; ctr < count; ctr++)
            added.get(ctr).notify_membership_changed(this);
        
        return added;
    }
    
    // Obtain a marker to build a list of objects to perform an action upon.
    public Marker start_marking() {
        return new MarkerImpl(this);
    }
    
    // Obtain a marker with a single item marked.  More can be added.
    public Marker mark(DataObject object) {
        Marker marker = new MarkerImpl(this);
        marker.mark(object);
        
        return marker;
    }
    
    // Obtain a marker for all items in a collection.  More can be added.
    public Marker mark_many(Gee.Collection<DataObject> objects) {
        Marker marker = new MarkerImpl(this);
        marker.mark_many(objects);
        
        return marker;
    }
    
    // Iterate over all the marked objects performing a user-supplied action on each one.  The
    // marker is invalid after calling this method.
    public void act_on_marked(Marker m, MarkedAction action, ProgressMonitor? monitor = null, 
        Object? user = null) {
        MarkerImpl marker = (MarkerImpl) m;
        
        assert(marker.is_valid(this));
        
        // freeze the marker to prepare it for iteration
        marker.freeze();
        
        uint64 count = 0;
        uint64 total = marker.marked.size;
        
        // iterate, breaking if the callback asks to stop
        foreach (DataObject object in marker.marked) {
            // although marker tracks when items are removed, catch it here as well
            if (!internal_contains(object)) {
                warning("act_on_marked: marker holding ref to unknown %s", object.to_string());
                
                continue;
            }
            
            if (!action(object, user))
                break;
            
            if (monitor != null) {
                if (!monitor(++count, total))
                    break;
            }
        }
        
        // invalidate the marker
        marker.finished();
    }

    // Remove marked items from collection.  This two-step process allows for iterating in a foreach
    // loop and removing without creating a separate list.  The marker is invalid after this call.
    public virtual void remove_marked(Marker m) {
        MarkerImpl marker = (MarkerImpl) m;
        
        assert(marker.is_valid(this));
        
        // freeze the marker before signalling, so it doesn't remove all its items
        marker.freeze();
        
        // remove everything in the marked list
        Gee.ArrayList<DataObject> skipped = null;
        foreach (DataObject object in marker.marked) {
            // although marker should track items already removed, catch it here as well
            if (!internal_contains(object)) {
                warning("remove_marked: marker holding ref to unknown %s", object.to_string());
                
                if (skipped == null)
                    skipped = new Gee.ArrayList<DataObject>();
                
                skipped.add(object);
                
                continue;
            }
            
            internal_remove(object);
        }
        
        if (skipped != null)
            marker.marked.remove_all(skipped);
        
        // signal after removing
        if (marker.marked.size > 0) {
            notify_items_removed(marker.marked);
            notify_contents_altered(null, marker.marked);
            
            // this must be called after the DataCollection has signalled.
            foreach (DataObject object in marker.marked)
                object.notify_membership_changed(null);
        }
        
        // invalidate the marker
        marker.finished();
    }
    
    public virtual void clear() {
        if (dataset.get_count() == 0)
            return;
        
        // remove everything in the list, but have to maintain a new list for reporting the signal.
        // Don't use an iterator, as list is modified in internal_remove().
        Gee.ArrayList<DataObject> removed = new Gee.ArrayList<DataObject>();
        do {
            DataObject? object = dataset.get_at(0);
            assert(object != null);
            
            removed.add(object);
            internal_remove(object);
        } while (dataset.get_count() > 0);
        
        // report after removal
        notify_items_removed(removed);
        notify_contents_altered(null, removed);
        
        // This must be called after the DataCollection has signalled.
        foreach (DataObject object in removed)
            object.notify_membership_changed(null);
    }
    
    // close() must be called before disposing of the DataCollection, so all signals may be
    // disconnected and all internal references to the collection can be dropped.  In the bare
    // minimum, all items will be removed from the collection (and the appropriate signals and
    // notify calls will be made).  Subclasses may fire other signals while disposing of their
    // references.  However, if they are entirely synchronized on DataCollection's signals, that
    // may be enough for them to clean up.
    public virtual void close() {
        clear();
    }
    
    // This method is only called by DataObject to report when it has been altered, so observers of
    // this collection may be notified as well.
    public void internal_notify_altered(DataObject object, Alteration alteration) {
        assert(internal_contains(object));
        
        bool resort_occurred = dataset.resort_object(object, alteration);
        
        if (are_notifications_frozen()) {
            if (frozen_items_altered == null)
                frozen_items_altered = new Gee.HashMap<DataObject, Alteration>();
            
            // if an alteration for the object is already in place, compress the two and add the
            // new one, otherwise set the supplied one
            Alteration? current = frozen_items_altered.get(object);
            if (current != null)
                current = current.compress(alteration);
            else
                current = alteration;
            
            frozen_items_altered.set(object, current);
            
            fire_ordering_changed = fire_ordering_changed || resort_occurred;
            
            return;
        }
        
        if (resort_occurred)
            notify_ordering_changed();
        
        notify_items_altered(get_alteration_singleton(object, alteration));
    }
    
    public Value? get_property(string name) {
        return properties.get(name);
    }
    
    public void set_property(string name, Value val, ValueEqualFunc? value_equals = null) {
        if (value_equals == null) {
            if (val.holds(typeof(bool)))
                value_equals = bool_value_equals;
            else if (val.holds(typeof(int)))
                value_equals = int_value_equals;
            else
                error("value_equals must be specified for this type");
        }
        
        Value? old = properties.get(name);
        if (old != null) {
            if (value_equals(old, val))
                return;
        }
        
        properties.set(name, val);
        
        notify_property_set(name, old, val);
        
        // notify all items in the collection of the change
        int count = dataset.get_count();
        for (int ctr = 0; ctr < count; ctr++)
            dataset.get_at(ctr).notify_collection_property_set(name, old, val);
    }
    
    public void clear_property(string name) {
        if (!properties.unset(name))
            return;
        
        // only notify if the propery was unset (that is, was set to begin with)
        notify_property_cleared(name);
            
        // notify all items
        int count = dataset.get_count();
        for (int ctr = 0; ctr < count; ctr++)
            dataset.get_at(ctr).notify_collection_property_cleared(name);
    }
    
    // This is only guaranteed to freeze notifications that come in from contained objects and
    // need to be propagated with collection signals.  Thus, the caller can freeze notifications,
    // make modifications to many or all member objects, then unthaw and have the aggregated signals
    // fired at once.
    //
    // DataObject/DataSource/DataView should also "eat" their signals as well, to prevent observers
    // from being notified while their collection is frozen, and only fire them when
    // internal_collection_thawed is called.
    //
    // For DataCollection, the signals affected are items_altered and ordering_changed.
    public void freeze_notifications() {
        if (notifies_frozen++ == 0)
            notify_frozen();
    }
    
    public void thaw_notifications() {
        if (notifies_frozen == 0)
            return;
        
        if (--notifies_frozen == 0)
            notify_thawed();
    }
    
    public bool are_notifications_frozen() {
        return notifies_frozen > 0;
    }
    
    // This is called when notifications have frozen.  Child collections should halt notifications
    // until thawed() is called.
    protected virtual void notify_frozen() {
        frozen();
    }
    
    // This is called when enough thaw_notifications() calls have been made.  Child collections
    // should issue caught notifications.
    protected virtual void notify_thawed() {
        if (frozen_items_altered != null) {
            // refs are swapped around due to reentrancy
            Gee.Map<DataObject, Alteration> copy = frozen_items_altered;
            frozen_items_altered = null;
            
            notify_items_altered(copy);
        }
        
        if (fire_ordering_changed) {
            fire_ordering_changed = false;
            notify_ordering_changed();
        }
        
        thawed();
    }
}

