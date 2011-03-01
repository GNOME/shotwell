/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

//
// DataSet
//
// A DataSet is a collection class used for internal implementations of DataCollection
// and its children.  It may be of use to other classes, however.
//
// The general purpose of DataSet is to provide low-cost implementations of various collection
// operations at a cost of internally maintaining its objects in more than one simple collection.
// contains(), for example, can return a result with hash-table performance while notions of
// ordering are maintained by a SortedList.  The cost is in adding and removing objects (in general,
// there are others).
//
// Because this class has no signalling mechanisms and does not manipulate DataObjects in ways
// they expect to be manipulated (these features are performed by DataCollection), it's probably
// best not to use this class.  Even in cases of building a list of DataObjects for some quick
// operation is probably best done by a Gee.ArrayList.
//

// ComparatorPredicate is used to determine if a re-sort operation is necessary; it has no
// effect on adding a DataObject to a DataSet in sorted order.
public delegate bool ComparatorPredicate(DataObject object, Alteration alteration);

public class DataSet {
    private SortedList<DataObject> list = new SortedList<DataObject>();
    private Gee.HashSet<DataObject> hash_set = new Gee.HashSet<DataObject>();
    private Comparator user_comparator = null;
    private ComparatorPredicate? comparator_predicate = null;
    
    public DataSet() {
        reset_comparator();
    }
    
    private int64 order_added_comparator(void *a, void *b) {
        return ((DataObject *) a)->internal_get_ordinal() - ((DataObject *) b)->internal_get_ordinal();
    }
    
    private bool order_added_predicate(DataObject object, Alteration alteration) {
        // ordinals don't change (shouldn't change!) while a part of the DataSet
        return false;
    }
    
    private int64 comparator_wrapper(void *a, void *b) {
        if (a == b)
            return 0;
        
        // use the order-added comparator if the user's compare returns equal, to stabilize the
        // sort
        int64 result = user_comparator(a, b);
        if (result == 0)
            result = order_added_comparator(a, b);
        
        assert(result != 0);
        
        return result;
    }
    
    public bool contains(DataObject object) {
        return hash_set.contains(object);
    }
    
    public inline int get_count() {
        return list.get_count();
    }
    
    public void reset_comparator() {
        user_comparator = null;
        comparator_predicate = order_added_predicate;
        list.resort(order_added_comparator);
    }
    
    public Comparator get_comparator() {
        return user_comparator;
    }
    
    public void set_comparator(Comparator user_comparator, ComparatorPredicate? comparator_predicate) {
        this.user_comparator = user_comparator;
        this.comparator_predicate = comparator_predicate;
        list.resort(comparator_wrapper);
    }
    
    public Gee.Collection<DataObject> get_all() {
        return list.read_only_view;
    }
    
    public DataSet copy() {
        DataSet clone = new DataSet();
        clone.list = list.copy();
        clone.hash_set.add_all(hash_set);
        
        return clone;
    }
    
    public DataObject? get_at(int index) {
        return list.get_at(index);
    }
    
    public int index_of(DataObject object) {
        return list.locate(object, false);
    }
    
    // DataObject's ordinal should be set before adding.
    public bool add(DataObject object) {
        if (!list.add(object))
            return false;
        
        if (!hash_set.add(object)) {
            // attempt to back out of previous operation
            list.remove(object);
            
            return false;
        }
        
        return true;
    }
    
    // DataObjects' ordinals should be set before adding.
    public bool add_many(Gee.Collection<DataObject> objects) {
        int count = objects.size;
        if (count == 0)
            return true;
        
        if (!list.add_all(objects))
            return false;
        
        if (!hash_set.add_all(objects)) {
            // back out previous operation
            list.remove_all(objects);
            
            return false;
        }
        
        return true;
    }
    
    public bool remove(DataObject object) {
        bool success = true;
        
        if (!list.remove(object))
            success = false;
        
        if (!hash_set.remove(object))
            success = false;
        
        return success;
    }
    
    public bool remove_many(Gee.Collection<DataObject> objects) {
        bool success = true;
        
        if (!list.remove_all(objects))
            success = false;
        
        if (!hash_set.remove_all(objects))
            success = false;
        
        return success;
    }
    
    // Returns true if the item has moved.
    public bool resort_object(DataObject object, Alteration? alteration) {
        if (comparator_predicate != null && alteration != null
            && !comparator_predicate(object, alteration)) {
            return false;
        }
        
        return list.resort_item(object);
    }
}

// SingletonCollection is a read-only collection designed to hold exactly one item in it.  This
// is far more efficient than creating a dummy collection (such as ArrayList) merely to pass around
// a single item, particularly for signals which require Iterables and Collections.
//
// This collection cannot be used to store null.

public class SingletonCollection<G> : Gee.AbstractCollection<G> {
    private class SingletonIterator<G> : Gee.Iterator<G>, Object {
        private SingletonCollection<G> c;
        private bool done = false;
        private G? current = null;
        
        public SingletonIterator(SingletonCollection<G> c) {
            this.c = c;
        }
        
        public bool first() {
            done = false;
            current = c.object;
            
            return current != null;
        }
        
        public new G? get() {
            return current;
        }
        
        public bool has_next() {
            return false;
        }
        
        public bool next() {
            if (done)
                return false;
            
            done = true;
            current = c.object;
            
            return true;
        }
        
        public void remove() {
            if (!done) {
                c.object = null;
                current = null;
            }
            
            done = true;
        }
    }
    
    private G? object;
    
    public SingletonCollection(G object) {
        this.object = object;
    }
    
    public override bool add(G object) {
        warning("Cannot add to SingletonCollection");
        
        return false;
    }
    
    public override void clear() {
        object = null;
    }
    
    public override bool contains(G object) {
        return this.object == object;
    }
    
    public override Gee.Iterator<G> iterator() {
        return new SingletonIterator<G>(this);
    }
    
    public override bool remove(G item) {
        if (item == object) {
            object = null;
            
            return true;
        }
        
        return false;
    }
    
    public override int size {
        get {
            return (object != null) ? 1 : 0;
        }
    }
}

//
// DataCollection
//

// A Marker is an object for marking (selecting) DataObjects in a DataCollection to then perform
// an action on all of them.  This mechanism allows for performing mass operations in a generic
// way, as well as dealing with the (perpetual) issue of removing items from a Collection within
// an iterator.
public interface Marker : Object {
    public abstract void mark(DataObject object);

    public abstract void unmark(DataObject object);

    public abstract bool toggle(DataObject object);
    
    public abstract void mark_many(Gee.Collection<DataObject> list);
    
    public abstract void unmark_many(Gee.Collection<DataObject> list);
    
    public abstract void mark_all();
    
    // Returns the number of marked items, or the number of items when the marker was frozen
    // and used.
    public abstract int get_count();
    
    // Returns a copy of the collection of marked items.
    public abstract Gee.Collection<DataObject> get_all();
}

// MarkedAction is a callback to perform an action on the marked DataObject.  Return false to
// end iterating.
public delegate bool MarkedAction(DataObject object, Object? user);

// A ProgressMonitor allows for notifications of progress on operations on multiple items (via
// the marked interfaces).  Return false if the operation is cancelled and should end immediately.
public delegate bool ProgressMonitor(uint64 current, uint64 total);

// UnknownTotalMonitor is useful when an interface cannot report the total count to a ProgressMonitor,
// only a count, but the total is known by the caller.
public class UnknownTotalMonitor {
    private uint64 total;
    private ProgressMonitor wrapped_monitor;
    
    public UnknownTotalMonitor(uint64 total, ProgressMonitor wrapped_monitor) {
        this.total = total;
        this.wrapped_monitor = wrapped_monitor;
    }
    
    public bool monitor(uint64 count, uint64 total) {
        return wrapped_monitor(count, this.total);
    }
}

// AggregateProgressMonitor is useful when several discrete operations are being performed against
// a single ProgressMonitor.
public class AggregateProgressMonitor {
    private uint64 grand_total;
    private ProgressMonitor wrapped_monitor;
    private uint64 aggregate_count = 0;
    private uint64 last_count = uint64.MAX;
    
    public AggregateProgressMonitor(uint64 grand_total, ProgressMonitor wrapped_monitor) {
        this.grand_total = grand_total;
        this.wrapped_monitor = wrapped_monitor;
    }
    
    public void next_step(string name) {
        debug("next step: %s (%s/%s)", name, aggregate_count.to_string(), grand_total.to_string());
        last_count = uint64.MAX;
    }
    
    public bool monitor(uint64 count, uint64 total) {
        // add the difference from the last, unless a new step has started
        aggregate_count += (last_count != uint64.MAX) ? (count - last_count) : count;
        if (aggregate_count > grand_total)
            aggregate_count = grand_total;
        
        // save for next time
        last_count = count;
        
        return wrapped_monitor(aggregate_count, grand_total);
    }
}

// Useful when debugging.
public bool null_progress_monitor(uint64 count, uint64 total) {
    return true;
}

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
    
    public Comparator get_comparator() {
        return dataset.get_comparator();
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

//
// SourceCollection
//

public abstract class SourceCollection : DataCollection {
    private class DestroyCounter : Object {
        public Marker remove_marker;
        public Gee.ArrayList<DataSource> notify_list = new Gee.ArrayList<DataSource>();
        public Gee.ArrayList<MediaSource> not_removed = new Gee.ArrayList<MediaSource>();
        
        public DestroyCounter(Marker remove_marker) {
            this.remove_marker = remove_marker;
        }
    }
    
    // When this signal is fired, the items are about to be unlinked from the collection.  The
    // appropriate remove signals will follow.
    public virtual signal void items_unlinking(Gee.Collection<DataSource> unlinking) {
    }
    
    // When this signal is fired, the items are being relinked to the collection.  The appropriate
    // add signals have already been fired.
    public virtual signal void items_relinked(Gee.Collection<DataSource> relinked) {
    }
    
    // When this signal is fired, the item is still part of the collection but its own destroy()
    // has already been called.
    public virtual signal void item_destroyed(DataSource source) {
    }
    
    // When this signal is fired, the item is still part of the collection but its own destroy()
    // has already been called.
    public virtual signal void items_destroyed(Gee.Collection<DataSource> destroyed) {
    }
    
    // When this signal is fired, the unlinked item has been unlinked from the collection previously
    // and its destroy() has been called.
    public virtual signal void unlinked_destroyed(DataSource source) {
    }
    
    // When this signal is fired, the backlink to the ContainerSource has already been removed.
    public virtual signal void backlink_removed(SourceBacklink backlink,
        Gee.Collection<DataSource> sources) {
    }
    
    private Gee.MultiMap<SourceBacklink, DataSource>? backlinks = null;
    
    public SourceCollection(string name) {
        base (name);
    }
    
    public abstract bool holds_type_of_source(DataSource source);
    
    protected virtual void notify_items_unlinking(Gee.Collection<DataSource> unlinking) {
        items_unlinking(unlinking);
    }
    
    protected virtual void notify_items_relinked(Gee.Collection<DataSource> relinked) {
        items_relinked(relinked);
    }
    
    protected virtual void notify_item_destroyed(DataSource source) {
        item_destroyed(source);
    }
    
    protected virtual void notify_items_destroyed(Gee.Collection<DataSource> destroyed) {
        items_destroyed(destroyed);
    }
    
    // This is only called by DataSource.
    public virtual void notify_unlinked_destroyed(DataSource unlinked) {
        unlinked_destroyed(unlinked);
    }
    
    protected virtual void notify_backlink_removed(SourceBacklink backlink,
        Gee.Collection<DataSource> sources) {
        backlink_removed(backlink, sources);
    }
    
    protected override bool valid_type(DataObject object) {
        return object is DataSource;
    }
    
    // Destroy all marked items and optionally have them delete their backing.  Returns the
    // number of items which failed to delete their backing (if delete_backing is true) or zero.
    public int destroy_marked(Marker marker, bool delete_backing, ProgressMonitor? monitor = null,
        Gee.List<MediaSource>? not_removed = null) {
        DestroyCounter counter = new DestroyCounter(start_marking());
        
        if (delete_backing)
            act_on_marked(marker, destroy_and_delete_source, monitor, counter);
        else
            act_on_marked(marker, destroy_source, monitor, counter);
        
        // notify of destruction
        foreach (DataSource source in counter.notify_list)
            notify_item_destroyed(source);
        notify_items_destroyed(counter.notify_list);
        
        // remove once all destroyed
        remove_marked(counter.remove_marker);
        
        if (null != not_removed) {
            not_removed.add_all(counter.not_removed);
        }
        
        return counter.not_removed.size;
    }
    
    private bool destroy_and_delete_source(DataObject object, Object? user) {
        bool success = false;
        try {
            success = ((DataSource) object).internal_delete_backing();
        } catch (Error err) {
            success = false;
        }
        
        if (!success && object is MediaSource) {
            ((DestroyCounter) user).not_removed.add((MediaSource) object);
        }
        
        return destroy_source(object, user) && success;
    }
    
    private bool destroy_source(DataObject object, Object? user) {
        DataSource source = (DataSource) object;
        
        source.internal_mark_for_destroy();
        source.destroy();
        
        ((DestroyCounter) user).remove_marker.mark(source);
        ((DestroyCounter) user).notify_list.add(source);
        
        return true;
    }
    
    // This is only called by DataSource.
    public void internal_backlink_set(DataSource source, SourceBacklink backlink) {
        if (backlinks == null) {
            backlinks = new Gee.HashMultiMap<SourceBacklink, DataSource>(SourceBacklink.hash_func,
                SourceBacklink.equal_func);
        }
        
        backlinks.set(backlink, source);
    }
    
    // This is only called by DataSource.
    public void internal_backlink_removed(DataSource source, SourceBacklink backlink) {
        assert(backlinks != null);
        
        bool removed = backlinks.remove(backlink, source);
        assert(removed);
    }
    
    public virtual bool has_backlink(SourceBacklink backlink) {
        return backlinks != null ? backlinks.contains(backlink) : false;
    }
    
    public Gee.Collection<DataSource>? unlink_marked(Marker marker, ProgressMonitor? monitor = null) {
        Gee.ArrayList<DataSource> list = new Gee.ArrayList<DataSource>();
        act_on_marked(marker, prepare_for_unlink, monitor, list);
        
        if (list.size == 0)
            return null;
        
        notify_items_unlinking(list);
        
        remove_marked(mark_many(list));
        
        return list;
    }
    
    private bool prepare_for_unlink(DataObject object, Object? user) {
        DataSource source = (DataSource) object;
        
        source.notify_unlinking(this);
        ((Gee.List<DataSource>) user).add(source);
        
        return true;
    }
    
    public void relink(DataSource source) {
        source.notify_relinking(this);
        
        add(source);
        notify_items_relinked((Gee.Collection<DataSource>) get_singleton(source));
        
        source.notify_relinked();
    }
    
    public void relink_many(Gee.Collection<DataSource> relink) {
        if (relink.size == 0)
            return;
        
        foreach (DataSource source in relink)
            source.notify_relinking(this);
        
        add_many(relink);
        notify_items_relinked(relink);
        
        foreach (DataSource source in relink)
            source.notify_relinked();
    }
    
    public virtual void remove_backlink(SourceBacklink backlink) {
        if (backlinks == null)
            return;
        
        // create copy because the DataSources will be removing the backlinks
        Gee.ArrayList<DataSource> sources = new Gee.ArrayList<DataSource>();
        sources.add_all(backlinks.get(backlink));
        
        foreach (DataSource source in sources)
            source.remove_backlink(backlink);
        
        notify_backlink_removed(backlink, sources);
    }
}

//
// DatabaseSourceCollection
//

public delegate int64 GetSourceDatabaseKey(DataSource source);

// A DatabaseSourceCollection is a SourceCollection that understands database keys (IDs) and the
// nature that a row in a database can only be instantiated once in the system, and so it tracks
// their existance in a map so they can be fetched by their key.
//
// TODO: This would be better implemented as an observer class, possibly with an interface to
// force subclasses to provide a fetch_by_key() method.
public abstract class DatabaseSourceCollection : SourceCollection {
    private GetSourceDatabaseKey source_key_func;
    private Gee.HashMap<int64?, DataSource> map = new Gee.HashMap<int64?, DataSource>(int64_hash, 
        int64_equal, direct_equal);
        
    public DatabaseSourceCollection(string name, GetSourceDatabaseKey source_key_func) {
        base (name);
        
        this.source_key_func = source_key_func;
    }

    public override void notify_items_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            DataSource source = (DataSource) object;
            int64 key = source_key_func(source);
            
            assert(!map.has_key(key));
            
            map.set(key, source);
        }
        
        base.notify_items_added(added);
    }
    
    public override void notify_items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            int64 key = source_key_func((DataSource) object);

            bool is_removed = map.unset(key);
            assert(is_removed);
        }
        
        base.notify_items_removed(removed);
    }
    
    protected DataSource fetch_by_key(int64 key) {
        return map.get(key);
    }
}

//
// ContainerSourceCollection
//

// A ContainerSourceCollection is for DataSources which maintain links to one or more other
// DataSources, assumed to be of a different type.  ContainerSourceCollection automates the task
// of handling unlinking and relinking and maintaining backlinks.  Unlinked DataSources are
// held in a holding tank, until they are either relinked or destroyed.
//
// If the ContainerSourceCollection's DataSources are types that "evaporate" (i.e. they disappear
// when they hold no items), they should use the evaporate() method, which will either destroy
// the DataSource or hold it in the tank (if backlinks are outstanding).
public abstract class ContainerSourceCollection : DatabaseSourceCollection {
    private Gee.HashSet<SourceCollection> attached_collections = new Gee.HashSet<SourceCollection>();
    private string backlink_name;
    private Gee.HashSet<ContainerSource> holding_tank = new Gee.HashSet<ContainerSource>();
    
    public virtual signal void container_contents_added(ContainerSource container,
        Gee.Collection<DataSource> added, bool relinked) {
    }
    
    public virtual signal void container_contents_removed(ContainerSource container, 
        Gee.Collection<DataSource> removed, bool unlinked) {
    }
    
    public virtual signal void container_contents_altered(ContainerSource container, 
        Gee.Collection<DataSource>? added, bool relinked, Gee.Collection<DataSource>? removed,
        bool unlinked) {
    }
    
    public virtual signal void backlink_to_container_removed(ContainerSource container,
        Gee.Collection<DataSource> sources) {
    }
    
    public ContainerSourceCollection(string backlink_name, string name,
        GetSourceDatabaseKey source_key_func) {
        base (name, source_key_func);
        
        this.backlink_name = backlink_name;
    }
    
    ~ContainerSourceCollection() {
        detach_all_collections();
    }
    
    protected override void notify_backlink_removed(SourceBacklink backlink,
        Gee.Collection<DataSource> sources) {
        base.notify_backlink_removed(backlink, sources);
        
        ContainerSource? container = convert_backlink_to_container(backlink);
        if (container != null)
            notify_backlink_to_container_removed(container, sources);
    }
    
    public virtual void notify_container_contents_added(ContainerSource container, 
        Gee.Collection<DataSource> added, bool relinked) {
        // if container is in holding tank, remove it now and relink to collection
        if (holding_tank.contains(container)) {
            bool removed = holding_tank.remove(container);
            assert(removed);
            
            relink(container);
        }
        
        container_contents_added(container, added, relinked);
    }
    
    public virtual void notify_container_contents_removed(ContainerSource container, 
        Gee.Collection<DataSource> removed, bool unlinked) {
        container_contents_removed(container, removed, unlinked);
    }
    
    public virtual void notify_container_contents_altered(ContainerSource container,
        Gee.Collection<DataSource>? added, bool relinked, Gee.Collection<DataSource>? removed,
        bool unlinked) {
        container_contents_altered(container, added, relinked, removed, unlinked);
    }
    
    public virtual void notify_backlink_to_container_removed(ContainerSource container,
        Gee.Collection<DataSource> sources) {
        backlink_to_container_removed(container, sources);
    }
    
    protected abstract Gee.Collection<ContainerSource>? get_containers_holding_source(DataSource source);
    
    // Looks in holding_tank as well.
    protected abstract ContainerSource? convert_backlink_to_container(SourceBacklink backlink);

    protected void freeze_attached_notifications() {
        foreach(SourceCollection collection in attached_collections)
            collection.freeze_notifications();
    }
    
    protected void thaw_attached_notifications() {
        foreach(SourceCollection collection in attached_collections)
            collection.thaw_notifications();
    }

    public Gee.Collection<ContainerSource> get_holding_tank() {
        return holding_tank.read_only_view;
    }
    
    public void init_add_unlinked(ContainerSource unlinked) {
        holding_tank.add(unlinked);
    }
    
    public void init_add_many_unlinked(Gee.Collection<ContainerSource> unlinked) {
        holding_tank.add_all(unlinked);
    }
    
    public bool relink_from_holding_tank(ContainerSource source) {
        if (!holding_tank.remove(source))
            return false;
        
        relink(source);
        
        return true;
    }
    
    private void on_contained_sources_unlinking(Gee.Collection<DataSource> unlinking) {
        freeze_attached_notifications();
        
        Gee.HashMultiMap<ContainerSource, DataSource> map =
            new Gee.HashMultiMap<ContainerSource, DataSource>();
        
        foreach (DataSource source in unlinking) {
            Gee.Collection<ContainerSource>? containers = get_containers_holding_source(source);
            if (containers == null || containers.size == 0)
                continue;
            
            foreach (ContainerSource container in containers) {
                map.set(container, source);
                source.set_backlink(container.get_backlink());
            }
        }
        
        foreach (ContainerSource container in map.get_keys())
            container.break_link_many(map.get(container));
        
        thaw_attached_notifications();
    }
    
    private void on_contained_sources_relinked(Gee.Collection<DataSource> relinked) {
        freeze_attached_notifications();
        
        Gee.HashMultiMap<ContainerSource, DataSource> map =
            new Gee.HashMultiMap<ContainerSource, DataSource>();
        
        foreach (DataSource source in relinked) {
            Gee.List<SourceBacklink>? backlinks = source.get_backlinks(backlink_name);
            if (backlinks == null || backlinks.size == 0)
                continue;
            
            foreach (SourceBacklink backlink in backlinks) {
                ContainerSource? container = convert_backlink_to_container(backlink);
                if (container != null) {
                    map.set(container, source);
                } else {
                    warning("Unable to relink %s to container backlink %s", source.to_string(),
                        backlink.to_string());
                }
            }
        }
        
        foreach (ContainerSource container in map.get_keys())
            container.establish_link_many(map.get(container));
        
        thaw_attached_notifications();
    }
    
    private void on_contained_source_destroyed(DataSource source) {
        Gee.Iterator<ContainerSource> iter = holding_tank.iterator();
        while (iter.next()) {
            ContainerSource container = iter.get();
            if (!container.has_links()) {
                iter.remove();
                container.destroy_orphan(true);
            }
        }
    }
    
    protected override void notify_item_destroyed(DataSource source) {
        foreach (SourceCollection collection in attached_collections) {
            collection.remove_backlink(((ContainerSource) source).get_backlink());
        }
        
        base.notify_item_destroyed(source);
    }
    
    // This method should be called by a ContainerSource when it needs to "evaporate" -- it no 
    // longer holds any source objects and should not be available to the user any longer.  If link
    // state persists for this ContainerSource, it will be held in the holding tank.  Otherwise, it's
    // destroyed.
    public void evaporate(ContainerSource container) {
        foreach (SourceCollection collection in attached_collections) {
            if (collection.has_backlink(container.get_backlink())) {
                unlink_marked(mark(container));
                bool added = holding_tank.add(container);
                assert(added);
                return;
            }
        }

        destroy_marked(mark(container), true);
    }

    public void attach_collection(SourceCollection collection) {
        if (attached_collections.contains(collection)) {
            warning("attempted to multiple-attach '%s' to '%s'", collection.to_string(), to_string());
            return;
        }

        attached_collections.add(collection);

        collection.items_unlinking.connect(on_contained_sources_unlinking);
        collection.items_relinked.connect(on_contained_sources_relinked);
        collection.item_destroyed.connect(on_contained_source_destroyed);
        collection.unlinked_destroyed.connect(on_contained_source_destroyed);
    }

    public void detach_all_collections() {
        foreach (SourceCollection collection in attached_collections) {
            collection.items_unlinking.disconnect(on_contained_sources_unlinking);
            collection.items_relinked.disconnect(on_contained_sources_relinked);
            collection.item_destroyed.disconnect(on_contained_source_destroyed);
            collection.unlinked_destroyed.disconnect(on_contained_source_destroyed);
        }

        attached_collections.clear();
    }
}

// A SourceHoldingTank is similar to the holding tank used by ContainerSourceCollection, but for
// non-ContainerSources to be held offline from their natural SourceCollection (i.e. PhotoSources
// being held in a trashcan, for example).  It is *not* a DataCollection (important!), but rather
// a signalled collection that moves DataSources to and from their SourceCollection.
//
// DataSources can be shuttled from their SourceCollection to the SourceHoldingTank manually
// (via unlink_and_hold) or can be automatically moved by installing a HoldingPredicate.
// Only one HoldingConditional may be installed.  Because of assertions in the methods, it's unwise
// to use more than one method.  add() and add_many() should ONLY be used for DataSources not
// first installed in their SourceCollection (i.e. they're born in the SourceHoldingTank).
//
// NOTE: DataSources should never be in more than one SourceHoldingTank.  No tests are performed
// here to verify this.  This is why a filter/predicate method (which could automatically move
// them in as they're altered) is not offered; there's no easy way to keep DataSources from being
// moved into more than one holding tank, or which should have preference.  The CheckToRemove
// predicate is offered only to know when to release them.

public class SourceHoldingTank {
    // Return true if the DataSource should remain in the SourceHoldingTank, false otherwise.
    public delegate bool CheckToKeep(DataSource source, Alteration alteration);
    
    private SourceCollection sources;
    private CheckToKeep check_to_keep;
    private DataSet tank = new DataSet();
    private Gee.HashSet<DataSource> relinks = new Gee.HashSet<DataSource>();
    private Gee.HashSet<DataSource> unlinking = new Gee.HashSet<DataSource>();
    private int64 ordinal = 0;
    
    public virtual signal void contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
    }
    
    public SourceHoldingTank(SourceCollection sources, CheckToKeep check_to_keep) {
        this.sources = sources;
        this.check_to_keep = check_to_keep;
        
        this.sources.item_destroyed.connect(on_source_destroyed);
        this.sources.thawed.connect(on_source_collection_thawed);
    }
    
    ~SourceHoldingTank() {
        sources.item_destroyed.disconnect(on_source_destroyed);
        sources.thawed.disconnect(on_source_collection_thawed);
    }
    
    protected virtual void notify_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        if (added != null) {
            foreach (DataSource source in added)
                source.notify_held_in_tank(this);
        }
        
        if (removed != null) {
            foreach (DataSource source in removed)
                source.notify_held_in_tank(null);
        }
        
        contents_altered(added, removed);
    }
    
    public int get_count() {
        return tank.get_count();
    }
    
    public Gee.Collection<DataSource> get_all() {
        return (Gee.Collection<DataSource>) tank.get_all();
    }
    
    public bool contains(DataSource source) {
        return tank.contains(source) || unlinking.contains(source);
    }
    
    // Only use for DataSources that have not been installed in their SourceCollection.
    public void add_many(Gee.Collection<DataSource> many) {
        if (many.size == 0)
            return;
        
        foreach (DataSource source in many)
            source.internal_set_ordinal(ordinal++);
        
        bool added = tank.add_many(many);
        assert(added);
        
        notify_contents_altered(many, null);
    }
    
    // Do not pass in DataSources which have already been unlinked, including into this holding
    // tank.
    public void unlink_and_hold(Gee.Collection<DataSource> unlink) {
        if (unlink.size == 0)
            return;
        
        // store in the unlinking collection to guard against reentrancy
        unlinking.add_all(unlink);
        
        sources.unlink_marked(sources.mark_many(unlink));
        
        foreach (DataSource source in unlink)
            source.internal_set_ordinal(ordinal++);
        
        bool added = tank.add_many(unlink);
        assert(added);
        
        // remove from the unlinking pool, as they're now unlinked
        unlinking.remove_all(unlink);
        
        notify_contents_altered(unlink, null);
    }
    
    public bool has_backlink(SourceBacklink backlink) {
        int count = tank.get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            if (((DataSource) tank.get_at(ctr)).has_backlink(backlink))
                return true;
        }
        
        return false;
    }
    
    public void remove_backlink(SourceBacklink backlink) {
        int count = tank.get_count();
        for (int ctr = 0; ctr < count; ctr++)
            ((DataSource) tank.get_at(ctr)).remove_backlink(backlink);
    }
    
    public void destroy_orphans(Gee.List<DataSource> destroy, bool delete_backing,
        ProgressMonitor? monitor = null, Gee.List<DataSource>? not_removed = null) {
        if (destroy.size == 0)
            return;
        
        bool removed = tank.remove_many(destroy);
        assert(removed);
        
        notify_contents_altered(null, destroy);
        
        int count = destroy.size;
        for (int ctr = 0; ctr < count; ctr++) {
            DataSource source = destroy.get(ctr);
            if (!source.destroy_orphan(delete_backing)) {
                if (null != not_removed) {
                    not_removed.add(source);
                }
            }
            if (monitor != null)
                monitor(ctr + 1, count);
        }
    }
    
    private void on_source_destroyed(DataSource source) {
        if (!tank.contains(source))
            return;
        
        bool removed = tank.remove(source);
        assert(removed);
        
        notify_contents_altered(null, new SingletonCollection<DataSource>(source));
    }
    
    // This is only called by DataSource
    public void internal_notify_altered(DataSource source, Alteration alteration) {
        assert(tank.contains(source));
        
        // see if it should stay put
        if (check_to_keep(source, alteration))
            return;
        
        bool removed = tank.remove(source);
        assert(removed);
        
        if (sources.are_notifications_frozen()) {
            relinks.add(source);
            
            return;
        }
        
        notify_contents_altered(null, new SingletonCollection<DataSource>(source));
        
        sources.relink(source);
    }
    
    private void on_source_collection_thawed() {
        if (relinks.size == 0)
            return;
        
        // swap out to protect against reentrancy
        Gee.HashSet<DataSource> copy = relinks;
        relinks = new Gee.HashSet<DataSource>();
        
        notify_contents_altered(null, copy);
        
        sources.relink_many(copy);
    }
}

public class DatabaseSourceHoldingTank : SourceHoldingTank {
    private GetSourceDatabaseKey get_key;
    private Gee.HashMap<int64?, DataSource> map = new Gee.HashMap<int64?, DataSource>(int64_hash,
        int64_equal);
    
    public DatabaseSourceHoldingTank(SourceCollection sources,
        SourceHoldingTank.CheckToKeep check_to_keep, GetSourceDatabaseKey get_key) {
        base (sources, check_to_keep);
        
        this.get_key = get_key;
    }
    
    public DataSource? get_by_id(int64 id) {
        return map.get(id);
    }
    
    protected override void notify_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        if (added != null) {
            foreach (DataSource source in added)
                map.set(get_key(source), source);
        }
        
        if (removed != null) {
            foreach (DataSource source in removed)
                map.unset(get_key(source));
        }
        
        base.notify_contents_altered(added, removed);
    }
}

//
// ViewCollection
//

// A ViewManager allows an interface for ViewCollection to monitor a SourceCollection and
// (selectively) add DataViews automatically.
public abstract class ViewManager {
    // This predicate function can be used to filter which DataView objects should be included
    // in the collection as new source objects appear in the SourceCollection.  May be called more
    // than once for any DataSource object.
    public virtual bool include_in_view(DataSource source) {
        return true;
    }
    
    // If include_in_view returns true, this method will be called to instantiate a DataView object
    // for the ViewCollection.
    public abstract DataView create_view(DataSource source);
}

// CreateView is a construction delegate used when mirroring or copying a ViewCollection 
// in another ViewCollection.
public delegate DataView CreateView(DataSource source);

// CreateViewPredicate is a filter delegate used when copy a ViewCollection in another
// ViewCollection.
public delegate bool CreateViewPredicate(DataSource source);

// A ViewFilter allows for items in a ViewCollection to be shown or hidden depending on the
// supplied predicate method.  For now, only one ViewFilter may be installed, although this may
// change in the future.  The ViewFilter is used whenever an object is added to the collection
// and when its altered/metadata_altered signals fire.
public abstract class ViewFilter {
    // Fire this signal whenever a refresh is needed.  The ViewCollection listens
    // to this signal to know when to reapply the filter.
    public virtual signal void refresh() {
    }
    
    // Return true if view should be visible, false if it should be hidden.
    public abstract bool predicate(DataView view);
}

// A ViewCollection holds DataView objects, which are view instances wrapping DataSource objects.
// Thus, multiple views can exist of a single SourceCollection, each view displaying all or some
// of that SourceCollection.  A view collection also has a notion of order
// (first/last/next/previous) that can be overridden by child classes.  It also understands hidden
// objects, which are withheld entirely from the collection until they're made visible.  Currently
// the only way to hide objects is with a ViewFilter.
//
// A ViewCollection may also be locked.  When locked, it will not (a) remove hidden items from the
// collection and (b) remove DataViews representing unlinked DataSources.  This allows for the
// ViewCollection to be "frozen" while manipulating items within it.  When the collection is
// unlocked, all changes are applied at once.
//
// The default implementation provides a browser which orders the view in the order they're
// stored in DataCollection, which is not specified.
public class ViewCollection : DataCollection {
    public class Monitor {
    }
    
    private class MonitorImpl : Monitor {
        public ViewCollection owner;
        public SourceCollection sources;
        public ViewManager manager;
        public Alteration? prereq;
        
        public MonitorImpl(ViewCollection owner, SourceCollection sources, ViewManager manager,
            Alteration? prereq) {
            this.owner = owner;
            this.sources = sources;
            this.manager = manager;
            this.prereq = prereq;
            
            sources.items_added.connect(owner.on_sources_added);
            sources.items_removed.connect(owner.on_sources_removed);
            sources.items_altered.connect(owner.on_sources_altered);
        }
        
        ~MonitorImpl() {
            sources.items_added.disconnect(owner.on_sources_added);
            sources.items_removed.disconnect(owner.on_sources_removed);
            sources.items_altered.disconnect(owner.on_sources_altered);
        }
    }
    
    private class ToggleLists : Object {
        public Gee.ArrayList<DataView> selected = new Gee.ArrayList<DataView>();
        public Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();
    }
    
    private Gee.HashMultiMap<SourceCollection, MonitorImpl> monitors = new Gee.HashMultiMap<
        SourceCollection, MonitorImpl>();
    private ViewCollection mirroring = null;
    private CreateView mirroring_ctor = null;
    private CreateViewPredicate should_mirror = null;
    private ViewFilter? filter = null;
    private DataSet selected = new DataSet();
    private DataSet visible = null;
    private Gee.HashSet<DataView> frozen_views_altered = null;
    private Gee.HashSet<DataView> frozen_geometries_altered = null;
    
    // TODO: source-to-view mapping ... for now, only one view is allowed for each source.
    // This may need to change in the future.
    private Gee.HashMap<DataSource, DataView> source_map = new Gee.HashMap<DataSource, DataView>(
        direct_hash, direct_equal, direct_equal);
    
    // Signal aggregator.
    public virtual signal void items_selected(Gee.Iterable<DataView> selected) {
    }
    
    // Signal aggregator.
    public virtual signal void items_unselected(Gee.Iterable<DataView> unselected) {
    }
    
    // Signal aggregator.
    public virtual signal void items_state_changed(Gee.Iterable<DataView> changed) {
    }
    
    // This signal is fired when the selection in the view has changed in any capacity.  Items
    // are not reported individually because they may have been removed (and are not reported as
    // unselected).  In other words, although individual DataViews' selection status may not have
    // changed, what characterizes the total selection of the ViewCollection has changed.
    public virtual signal void selection_group_altered() {
    }
    
    // Signal aggregator.
    public virtual signal void items_shown(Gee.Collection<DataView> visible) {
    }
    
    // Signal aggregator.
    public virtual signal void items_hidden(Gee.Collection<DataView> hidden) {
    }
    
    // Signal aggregator.
    public virtual signal void items_visibility_changed(Gee.Collection<DataView> changed) {
    }
    
    // Signal aggregator.
    public virtual signal void item_view_altered(DataView view) {
    }
    
    // Signal aggregator.
    public virtual signal void item_geometry_altered(DataView view) {
    }
    
    public virtual signal void views_altered(Gee.Collection<DataView> views) {
    }
    
    public virtual signal void geometries_altered(Gee.Collection<DataView> views) {
    }
    
    public virtual signal void view_filter_changed(ViewFilter? old_filer, ViewFilter? new_filter) {
    }
    
    public ViewCollection(string name) {
        base (name);
    }
    
    protected virtual void notify_items_selected_unselected(Gee.Collection<DataView>? selected,
        Gee.Collection<DataView>? unselected) {
        bool has_selected = (selected != null) && (selected.size > 0);
        bool has_unselected = (unselected != null) && (unselected.size > 0);
        
        if (has_selected)
            items_selected(selected);
        
        if (has_unselected)
            items_unselected(unselected);
        
        Gee.Collection<DataView>? sum;
        if (has_selected && !has_unselected) {
            sum = selected;
        } else if (!has_selected && has_unselected) {
            sum = unselected;
        } else if (!has_selected && !has_unselected) {
            sum = null;
        } else {
            sum = new Gee.HashSet<DataView>();
            sum.add_all(selected);
            sum.add_all(unselected);
        }
        
        if (sum != null) {
            items_state_changed(sum);
            notify_selection_group_altered();
        }
    }
    
    protected virtual void notify_selection_group_altered() {
        selection_group_altered();
    }
    
    protected virtual void notify_item_view_altered(DataView view) {
        item_view_altered(view);
    }
    
    protected virtual void notify_views_altered(Gee.Collection<DataView> views) {
        views_altered(views);
    }
    
    protected virtual void notify_item_geometry_altered(DataView view) {
        item_geometry_altered(view);
    }
    
    protected virtual void notify_geometries_altered(Gee.Collection<DataView> views) {
        geometries_altered(views);
    }
    
    protected virtual void notify_items_shown(Gee.Collection<DataView> shown) {
        items_shown(shown);
    }
    
    protected virtual void notify_items_hidden(Gee.Collection<DataView> hidden) {
        items_hidden(hidden);
    }
    
    protected virtual void notify_items_visibility_changed(Gee.Collection<DataView> changed) {
        items_visibility_changed(changed);
    }
    
    protected virtual void notify_view_filter_changed(ViewFilter? old_filter, ViewFilter? new_filter) {
        view_filter_changed(old_filter, new_filter);
    }
    
    public override void clear() {
        // cannot clear a ViewCollection if it is monitoring a SourceCollection or mirroring a
        // ViewCollection
        if (monitors.size > 0 || mirroring != null) {
            warning("Cannot clear %s: monitoring or mirroring in effect", to_string());
            
            return;
        }
        
        base.clear();
    }
    
    public override void close() {
        halt_all_monitoring();
        halt_mirroring();
        if (null != filter) {
            filter.refresh.disconnect(on_view_filter_refresh);
        }
        filter = null;
        
        base.close();
    }
    
    public Monitor monitor_source_collection(SourceCollection sources, ViewManager manager,
        Alteration? prereq, Gee.Collection<DataSource>? initial = null,
        ProgressMonitor? progress_monitor = null) {
        // cannot use source monitoring and mirroring at the same time
        halt_mirroring();
        
        // create a monitor, which will hook up all the signals and filter from there
        MonitorImpl monitor = new MonitorImpl(this, sources, manager, prereq);
        monitors.set(sources, monitor);
        
        if (initial != null && initial.size > 0) {
            // add from the initial list handed to us, using the ViewManager to add/remove later
            Gee.ArrayList<DataView> created_views = new Gee.ArrayList<DataView>();
            foreach (DataSource source in initial)
                created_views.add(manager.create_view(source));
            
            add_many(created_views, progress_monitor);
        } else {
            // load in all items from the SourceCollection, filtering with the manager
            add_sources(sources, (Gee.Iterable<DataSource>) sources.get_all(), progress_monitor);
        }
        
        return monitor;
    }
    
    public void halt_monitoring(Monitor m) {
        MonitorImpl monitor = (MonitorImpl) m;
        
        bool removed = monitors.remove(monitor.sources, monitor);
        assert(removed);
    }
    
    public void halt_all_monitoring() {
        monitors.clear();
    }
    
    public void mirror(ViewCollection to_mirror, CreateView mirroring_ctor,
        CreateViewPredicate? should_mirror) {
        halt_mirroring();
        halt_all_monitoring();
        clear();
        
        mirroring = to_mirror;
        this.mirroring_ctor = mirroring_ctor;
        this.should_mirror = should_mirror;
        
        // used to mirror the ordering of to_mirror
        set_comparator(mirroring_comparator, null);
        
        // load up with current items
        on_mirror_contents_added(mirroring.get_all());
        
        mirroring.items_added.connect(on_mirror_contents_added);
        mirroring.items_removed.connect(on_mirror_contents_removed);
        mirroring.ordering_changed.connect(on_mirror_ordering_changed);
    }
    
    public void halt_mirroring() {
        if (mirroring != null) {
            mirroring.items_added.disconnect(on_mirror_contents_added);
            mirroring.items_removed.disconnect(on_mirror_contents_removed);
            mirroring.ordering_changed.disconnect(on_mirror_ordering_changed);
        }
        
        mirroring = null;
    }
    
    public void copy_into(ViewCollection to_copy, CreateView copying_ctor, 
        CreateViewPredicate should_copy) {
        // Copy into self.
        Gee.ArrayList<DataObject> copy_view = new Gee.ArrayList<DataObject>();
        foreach (DataObject object in to_copy.get_all()) {
            DataView view = (DataView) object;
            if (should_copy(view.get_source())) {
                copy_view.add(copying_ctor(view.get_source()));
            }
        }
        add_many(copy_view);
    }
    
    public void install_view_filter(ViewFilter filter) {
        if (this.filter == filter)
            return;
        
        // this currently replaces any existing ViewFilter
        ViewFilter? old_filter = this.filter;
        this.filter = filter;
        this.filter.refresh.connect(on_view_filter_refresh);
        
        // filter existing items
        on_view_filter_refresh();
        
        // notify of change after activating filter
        notify_view_filter_changed(old_filter, filter);
    }
    
    private void on_view_filter_refresh() {
        filter_altered_items((Gee.Collection<DataView>) base.get_all());
    }
    
    public void reset_view_filter() {
        if (null != this.filter)
            filter.refresh.disconnect(on_view_filter_refresh);
        
        ViewFilter? old_filter = this.filter;
        this.filter = null;
        
        // reset visibility of all hidden items ... can't use marker for reasons explained in
        // reapply_view_filter().
        Gee.ArrayList<DataView> to_show = new Gee.ArrayList<DataView>();
        foreach (DataObject object in base.get_all()) {
            DataView view = (DataView) object;
            if (view.is_visible()) {
                assert(is_visible(view));
                
                continue;
            }
            
            to_show.add(view);
        }
        
        show_items(to_show);
        
        // notify of change after deactivating filter
        if (old_filter != null)
            notify_view_filter_changed(old_filter, null);
    }
    
    public override bool valid_type(DataObject object) {
        return object is DataView;
    }
    
    private void on_sources_added(DataCollection sources, Gee.Iterable<DataSource> added) {
        add_sources((SourceCollection) sources, added);
    }
    
    private void add_sources(SourceCollection sources, Gee.Iterable<DataSource> added,
        ProgressMonitor? progress_monitor = null) {
        // add only source items which are to be included by the manager ... do this in batches
        // to take advantage of add_many()
        DataView created_view = null;
        Gee.ArrayList<DataView> created_views = null;
        foreach (DataSource source in added) {
            CreateView factory = null;
            foreach (MonitorImpl monitor in monitors.get(sources)) {
                if (monitor.manager.include_in_view(source)) {
                    factory = monitor.manager.create_view;
                    
                    break;
                }
            }
            
            if (factory != null) {
                DataView new_view = factory(source);
                
                // this bit of code is designed to avoid creating the ArrayList if only one item
                // is being added to the ViewCollection
                if (created_views != null) {
                    created_views.add(new_view);
                } else if (created_view == null) {
                    created_view = new_view;
                } else {
                    created_views = new Gee.ArrayList<DataView>();
                    created_views.add(created_view);
                    created_view = null;
                    created_views.add(new_view);
                }
            }
        }
        
        if (created_view != null)
            add(created_view);
        else if (created_views != null && created_views.size > 0)
            add_many(created_views, progress_monitor);
    }

    public override bool add(DataObject object) {
        ((DataView) object).internal_set_visible(true);
        
        if (!base.add(object))
            return false;
        
        filter_altered_items((Gee.Collection<DataView>) get_singleton(object));
        
        return true;
    }

    public override Gee.Collection<DataObject> add_many(Gee.Collection<DataObject> objects, 
        ProgressMonitor? monitor = null) {
        foreach (DataObject object in objects)
            ((DataView) object).internal_set_visible(true);
        
        Gee.Collection<DataObject> return_list = base.add_many(objects, monitor);
        
        filter_altered_items((Gee.Collection<DataView>) return_list);
        
        return return_list;
    }
    
    private void on_sources_removed(Gee.Iterable<DataSource> removed) {
        // mark all view items associated with the source to be removed
        Marker marker = null;
        foreach (DataSource source in removed) {
            DataView view = source_map.get(source);
            
            // ignore if not represented in this view
            if (view != null) {
                if (marker == null)
                    marker = start_marking();
                
                marker.mark(view);
            }
        }
        
        if (marker != null && marker.get_count() != 0)
            remove_marked(marker);
    }
    
    private void on_sources_altered(DataCollection collection, Gee.Map<DataObject, Alteration> items) {
        // let ViewManager decide whether or not to keep, but only add if not already present
        // and only remove if already present
        Gee.ArrayList<DataView> to_add = null;
        Gee.ArrayList<DataView> to_remove = null;
        bool ordering_changed = false;
        foreach (DataObject object in items.keys) {
            Alteration alteration = items.get(object);
            DataSource source = (DataSource) object;
            
            MonitorImpl? monitor = null;
            bool ignored = true;
            foreach (MonitorImpl monitor_impl in monitors.get((SourceCollection) collection)) {
                if (monitor_impl.prereq != null && !alteration.contains_any(monitor_impl.prereq))
                    continue;
                
                ignored = false;
                
                if (monitor_impl.manager.include_in_view(source)) {
                    monitor = monitor_impl;
                    
                    break;
                }
            }
            
            if (ignored) {
                assert(monitor == null);
                
                continue;
            }
            
            if (monitor != null && !has_view_for_source(source)) {
                if (to_add == null)
                    to_add = new Gee.ArrayList<DataView>();
                
                to_add.add(monitor.manager.create_view(source));
            } else if (monitor == null && has_view_for_source(source)) {
                if (to_remove == null)
                    to_remove = new Gee.ArrayList<DataView>();
                
                to_remove.add(get_view_for_source(source));
            } else if (monitor != null && has_view_for_source(source)) {
                DataView view = get_view_for_source(source);
                
                if (selected.contains(view))
                    selected.resort_object(view, alteration);
                
                if (visible != null && is_visible(view)) {
                    if (visible.resort_object(view, alteration))
                        ordering_changed = true;
                }
            }
        }
        
        if (to_add != null)
            add_many(to_add);
        
        if (to_remove != null)
            remove_marked(mark_many(to_remove));
        
        if (ordering_changed)
            notify_ordering_changed();
    }
    
    private int64 mirroring_comparator(void *a, void *b) {
        assert(mirroring != null);
        
        int aindex = mirroring.index_of_source(((DataView *) a)->get_source());
        assert(aindex >= 0);
        
        int bindex = mirroring.index_of_source(((DataView *) b)->get_source());
        assert(bindex >= 0);
        
        return aindex - bindex;
    }
    
    private void on_mirror_contents_added(Gee.Iterable<DataObject> added) {
        Gee.ArrayList<DataView> to_add = new Gee.ArrayList<DataView>();
        foreach (DataObject object in added) {
            DataSource source = ((DataView) object).get_source();
            
            if (should_mirror == null || should_mirror(source))
                to_add.add(mirroring_ctor(source));
        }
        
        if (to_add.size > 0)
            add_many(to_add);
    }
    
    private void on_mirror_contents_removed(Gee.Iterable<DataObject> removed) {
        Marker marker = start_marking();
        foreach (DataObject object in removed) {
            DataView view = (DataView) object;
            
            DataView? our_view = get_view_for_source(view.get_source());
            assert(our_view != null);
            
            marker.mark(our_view);
        }
        
        remove_marked(marker);
    }
    
    private void on_mirror_ordering_changed() {
        // By re-setting the comparator, this forces a resort of the collection (but only do it
        // if the comparator is still set to the mirroring_comparator, as the user may have changed
        // it after mirroring started)
        if (get_comparator() == mirroring_comparator)
            set_comparator(mirroring_comparator, null);
    }
    
    // Keep the source map and state tables synchronized
    protected override void notify_items_added(Gee.Iterable<DataObject> added) {
        Gee.ArrayList<DataView> added_visible = null;
        Gee.ArrayList<DataView> added_selected = null;
        
        foreach (DataObject object in added) {
            DataView view = (DataView) object;
            source_map.set(view.get_source(), view);
            
            if (view.is_selected() && view.is_visible()) {
                if (added_selected == null)
                    added_selected = new Gee.ArrayList<DataView>();
                
                added_selected.add(view);
            }
            
            // add to visible list only if there is one
            if (view.is_visible() && visible != null) {
                if (added_visible == null)
                    added_visible = new Gee.ArrayList<DataView>();
                
                added_visible.add(view);
            }
        }
        
        if (added_visible != null) {
            bool is_added = add_many_visible(added_visible);
            assert(is_added);
        }
        
        if (added_selected != null) {
            add_many_selected(added_selected);
            notify_items_selected_unselected(added_selected, null);
        }
        
        base.notify_items_added(added);
    }
    
    // Keep the source map and state tables synchronized
    protected override void notify_items_removed(Gee.Iterable<DataObject> removed) {
        Gee.ArrayList<DataView>? selected_removed = null;
        foreach (DataObject object in removed) {
            DataView view = (DataView) object;

            bool is_removed = source_map.unset(view.get_source());
            assert(is_removed);
            
            if (view.is_selected()) {
                // hidden items may be selected, but they won't be in the selected pool
                assert(selected.contains(view) == view.is_visible());
                
                if (view.is_visible()) {
                    if (selected_removed == null)
                        selected_removed = new Gee.ArrayList<DataView>();
                    
                    selected_removed.add(view);
                }
            }
            
            if (view.is_visible() && visible != null) {
                is_removed = visible.remove(view);
                assert(is_removed);
            }
        }
        
        if (selected_removed != null) {
            remove_many_selected(selected_removed);
            
            // If a selected item was removed, only fire the selected_removed signal, as the total
            // selection character of the ViewCollection has changed, but not the individual items'
            // state.
            notify_selection_group_altered();
        }
        
        base.notify_items_removed(removed);
    }
    
    private void filter_altered_items(Gee.Collection<DataView> views) {
        if (filter == null)
            return;
        
        // Can't use the marker system because ViewCollection completely overrides DataCollection
        // and hidden items cannot be marked.
        Gee.ArrayList<DataView> to_show = null;
        Gee.ArrayList<DataView> to_hide = null;
        
        foreach (DataView view in views) {
            if (filter.predicate(view)) {
                if (!view.is_visible()) {
                    if (to_show == null)
                        to_show = new Gee.ArrayList<DataView>();
                    
                    to_show.add(view);
                }
            } else {
                if (view.is_visible()) {
                    if (to_hide == null)
                        to_hide = new Gee.ArrayList<DataView>();
                    
                    to_hide.add(view);
                }
            }
        }
        
        if (to_show != null)
            show_items(to_show);
        
        if (to_hide != null)
            hide_items(to_hide);
    }
    
    public override void items_altered(Gee.Map<DataObject, Alteration> map) {
        filter_altered_items(map.keys);

        base.items_altered(map);
    }
    
    public override void set_comparator(Comparator comparator, ComparatorPredicate? predicate) {
        selected.set_comparator(comparator, predicate);
        if (visible != null)
            visible.set_comparator(comparator, predicate);
        
        base.set_comparator(comparator, predicate);
    }
    
    public override void reset_comparator() {
        selected.reset_comparator();
        if (visible != null)
            visible.reset_comparator();
        
        base.reset_comparator();
    }
    
    public override Gee.Collection<DataObject> get_all() {
        return (visible != null) ? visible.get_all() : base.get_all();
    }
    
    public Gee.Collection<DataObject> get_all_unfiltered() {
        return base.get_all();
    }    

    public override int get_count() {
        return (visible != null) ? visible.get_count() : base.get_count();
    }
    
    public int get_unfiltered_count() {
        return base.get_count();
    }
    
    public override DataObject? get_at(int index) {
        return (visible != null) ? visible.get_at(index) : base.get_at(index);
    }
    
    public override int index_of(DataObject object) {
        return (visible != null) ? visible.index_of(object) : base.index_of(object);
    }
    
    public override bool contains(DataObject object) {
        // use base method first, which can quickly ascertain if the object is *not* a member of
        // this collection
        if (!base.contains(object))
            return false;
        
        // even if a member, must be visible to be "contained"
        return is_visible((DataView) object);
    }
    
    public virtual DataView? get_first() {
        return (get_count() > 0) ? (DataView?) get_at(0) : null;
    }
    
    public virtual DataView? get_last() {
        return (get_count() > 0) ? (DataView?) get_at(get_count() - 1) : null;
    }
    
    public virtual DataView? get_next(DataView view) {
        if (get_count() == 0)
            return null;
        
        int index = index_of(view);
        if (index < 0)
            return null;
        
        index++;
        if (index >= get_count())
            index = 0;
        
        return (DataView?) get_at(index);
    }
    
    public virtual DataView? get_previous(DataView view) {
        if (get_count() == 0)
            return null;
        
        int index = index_of(view);
        if (index < 0)
            return null;
        
        index--;
        if (index < 0)
            index = get_count() - 1;
        
        return (DataView?) get_at(index);
    }
    
    public bool get_immediate_neighbors(DataSource home, out DataSource? next,
        out DataSource? prev, string? type_selector = null) {
        DataView home_view = get_view_for_source(home);
        if (home_view == null)
            return false;
        
        next = null;
        DataView? next_view = get_next(home_view);
        while (next_view != home_view) {
            if ((type_selector == null) || (next_view.get_source().get_typename() == type_selector)) {
                next = next_view.get_source();
                break;
            }
            next_view = get_next(next_view);
        }
        
        prev = null;
        DataView? prev_view = get_previous(home_view);
        while (prev_view != home_view) {
            if ((type_selector == null) || (prev_view.get_source().get_typename() == type_selector)) {
                prev = prev_view.get_source();
                break;
            }
            prev_view = get_previous(prev_view);
        }
        
        return true;
    }
    
    // "Extended" as in immediate neighbors and their neighbors
    public Gee.Set<DataSource> get_extended_neighbors(DataSource home, string? typename = null) {
        // build set of neighbors
        Gee.Set<DataSource> neighbors = new Gee.HashSet<DataSource>();
        
        // immediate neighbors
        DataSource next, prev;
        if (!get_immediate_neighbors(home, out next, out prev, typename))
            return neighbors;
        
        // add next and its distant neighbor
        if (next != null) {
            neighbors.add(next);
            
            DataSource next_next, next_prev;
            get_immediate_neighbors(next, out next_next, out next_prev, typename);
            
            // only add next-next because next-prev is home
            if (next_next != null)
                neighbors.add(next_next);
        }
        
        // add previous and its distant neighbor
        if (prev != null) {
            neighbors.add(prev);
            
            DataSource next_prev, prev_prev;
            get_immediate_neighbors(prev, out next_prev, out prev_prev, typename);
            
            // only add prev-prev because next-prev is home
            if (prev_prev != null)
                neighbors.add(prev_prev);
        }
        
        // finally, in a small collection a neighbor could be home itself, so exclude it
        neighbors.remove(home);
        
        return neighbors;
    }
    
    // Do NOT add hidden items to the selection collection, mark them as selected and they will be
    // added when/if they are made visible.
    private void add_many_selected(Gee.Collection<DataView> views) {
        if (views.size == 0)
            return;
        
        foreach (DataView view in views)
            assert(view.is_visible());
        
        bool added = selected.add_many(views);
        assert(added);
    }
    
    private void remove_many_selected(Gee.Collection<DataView> views) {
        if (views.size == 0)
            return;
        
        bool removed = selected.remove_many(views);
        assert(removed);
    }
    
    // Selects all the marked items.  The marker will be invalid after this call.
    public void select_marked(Marker marker) {
        Gee.ArrayList<DataView> selected = new Gee.ArrayList<DataView>();
        act_on_marked(marker, select_item, null, selected);
        
        if (selected.size > 0) {
            add_many_selected(selected);
            notify_items_selected_unselected(selected, null);
        }
    }
    
    // Selects all items.
    public void select_all() {
        Marker marker = start_marking();
        marker.mark_all();
        select_marked(marker);
    }
    
    private bool select_item(DataObject object, Object? user) {
        DataView view = (DataView) object;
        if (view.is_selected()) {
            if (view.is_visible())
                assert(selected.contains(view));
            
            return true;
        }
        
        view.internal_set_selected(true);
        
        // Do NOT add hidden items to the selection collection, merely mark them as selected
        // and they will be re-added when/if they are made visible
        if (view.is_visible())
            ((Gee.ArrayList<DataView>) user).add(view);
        
        return true;
    }
    
    // Unselects all the marked items.  The marker will be invalid after this call.
    public void unselect_marked(Marker marker) {
        Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();
        act_on_marked(marker, unselect_item, null, unselected);
        
        if (unselected.size > 0) {
            remove_many_selected(unselected);
            notify_items_selected_unselected(null, unselected);
        }
    }
    
    // Unselects all items.
    public void unselect_all() {
        if (selected.get_count() == 0)
            return;
        
        Marker marker = start_marking();
        marker.mark_many(get_selected());

        unselect_marked(marker);
    }
    
    // Unselects all items but the one specified.
    public void unselect_all_but(DataView exception) {
        Marker marker = start_marking();
        foreach (DataObject object in get_all()) {
            DataView view = (DataView) object;
            if (view != exception)
                marker.mark(view);
        }
        
        unselect_marked(marker);
    }
    
    private bool unselect_item(DataObject object, Object? user) {
        DataView view = (DataView) object;
        if (!view.is_selected()) {
            assert(!selected.contains(view));
            
            return true;
        }
        
        view.internal_set_selected(false);
        ((Gee.ArrayList<DataView>) user).add(view);
        
        return true;
    }
    
    // Performs the operations in that order: unselects the marked then selects the marked
    public void unselect_and_select_marked(Marker unselect, Marker select) {
        Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();
        act_on_marked(unselect, unselect_item, null, unselected);
        
        remove_many_selected(unselected);
        
        Gee.ArrayList<DataView> selected = new Gee.ArrayList<DataView>();
        act_on_marked(select, select_item, null, selected);
        
        add_many_selected(selected);
        
        notify_items_selected_unselected(selected, unselected);
    }
    
    // Toggle the selection state of all marked items.  The marker will be invalid after this
    // call.
    public void toggle_marked(Marker marker) {
        ToggleLists lists = new ToggleLists();
        act_on_marked(marker, toggle_item, null, lists);
        
        // add and remove selected before firing the signals
        add_many_selected(lists.selected);
        remove_many_selected(lists.unselected);
        
        notify_items_selected_unselected(lists.selected, lists.unselected);
    }
    
    private bool toggle_item(DataObject object, Object? user) {
        DataView view = (DataView) object;
        ToggleLists lists = (ToggleLists) user;
        
        // toggle the selection state of the view, adding or removing it from the selected list
        // to maintain state and adding it to the ToggleLists for the caller to signal with
        //
        // See add_many_selected for rules on not adding hidden items to the selection pool
        if (view.internal_toggle()) {
            if (view.is_visible())
                lists.selected.add(view);
        } else {
            lists.unselected.add(view);
        }
        
        return true;
    }
    
    public int get_selected_count() {
        return selected.get_count();
    }
    
    public Gee.Collection<DataView> get_selected() {
        return (Gee.Collection<DataView>) selected.get_all();
    }
    
    public DataView? get_selected_at(int index) {
        return (DataView?) selected.get_at(index);
    }
    
    private bool is_visible(DataView view) {
        return (visible != null) ? visible.contains(view) : true;
    }

    private bool add_many_visible(Gee.Collection<DataView> many) {
        if (visible == null)
            return true;
        
        if (!visible.add_many(many))
            return false;
        
        // if all are visible, then revert to using base class's set
        if (visible.get_count() == base.get_count())
            visible = null;
        
        return true;
    }
    
    // This method requires that all items in to_hide are not hidden already.
    private void hide_items(Gee.List<DataView> to_hide) {
        Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();

        int count = to_hide.size;
        for (int ctr = 0; ctr < count; ctr++) {
            DataView view = to_hide.get(ctr);
            assert(view.is_visible());
            
            if (view.is_selected()) {
                view.internal_set_selected(false);
                unselected.add(view);
            } else {
                assert(!selected.contains(view));
            }
            
            view.internal_set_visible(false);
        }
        
        if (visible == null) {
            // make a copy of the full set before removing items
            visible = get_dataset_copy();
        }
        
        bool removed = visible.remove_many(to_hide);
        assert(removed);
        
        remove_many_selected(unselected);
        
        if (unselected.size > 0)
            notify_items_selected_unselected(null, unselected);
        
        if (to_hide.size > 0) {
            notify_items_hidden(to_hide);
            notify_items_visibility_changed(to_hide);
        }
    }
    
    // This method requires that all items in to_show are hidden already.
    private void show_items(Gee.List<DataView> to_show) {
        Gee.ArrayList<DataView> added_selected = new Gee.ArrayList<DataView>();
        
        int count = to_show.size;
        for (int ctr = 0; ctr < count; ctr++) {
            DataView view = to_show.get(ctr);
            assert(!view.is_visible());
            
            view.internal_set_visible(true);
            
            // See note in add_selected for selection handling with hidden/visible items
            if (view.is_selected()) {
                assert(!selected.contains(view));
                added_selected.add(view);
            }
        }
        
        bool added = add_many_visible(to_show);
        assert(added);
        
        add_many_selected(added_selected);
        
        if (to_show.size > 0) {
            notify_items_shown(to_show);
            notify_items_visibility_changed(to_show);
        }
    }
    
    // TODO: This currently does not respect filtering.
    public bool has_view_for_source(DataSource source) {
        return source_map.has_key(source);
    }
    
    // TODO: This currently does not respect filtering.
    public DataView? get_view_for_source(DataSource source) {
        return source_map.get(source);
    }
    
    // TODO: This currently does not respect filtering.
    public Gee.Collection<DataSource> get_sources() {
        return source_map.keys.read_only_view;
    }
    
    // TODO: This currently does not respect filtering.
    public bool has_source_of_type(Type t) {
        assert(t.is_a(typeof(DataSource)));
        
        foreach (DataSource source in source_map.keys) {
            if (source.get_type().is_a(t))
                return true;
        }
        
        return false;
    }
    
    // TODO: This currently does not respect filtering.
    public int get_sources_of_type_count(Type t) {
        assert(t.is_a(typeof(DataSource)));
        
        int count = 0;
        foreach (DataSource source in source_map.keys) {
            if (source.get_type().is_a(t))
                count++;
        }
        
        return count;
    }
    
    // TODO: This currently does not respect filtering.
    public Gee.Collection<DataSource>? get_sources_of_type(Type t) {
        assert(t.is_a(typeof(DataSource)));
        
        Gee.Collection<DataSource>? sources = null;
        foreach (DataSource source in source_map.keys) {
            if (source.get_type().is_a(t)) {
                if (sources == null)
                    sources = new Gee.ArrayList<DataSource>();
                
                sources.add(source);
            }
        }
        
        return sources;
    }
    
    public Gee.Collection<DataSource> get_selected_sources() {
        Gee.Collection<DataSource> sources = new Gee.ArrayList<DataSource>();
        
        int count = selected.get_count();
        for (int ctr = 0; ctr < count; ctr++)
            sources.add(((DataView) selected.get_at(ctr)).get_source());
        
        return sources;
    }
    
    public DataSource? get_selected_source_at(int index) {
        DataObject? object = selected.get_at(index);
        
        return (object != null) ? ((DataView) object).get_source() : null;
    }
    
    public Gee.Collection<DataSource>? get_selected_sources_of_type(Type t) {
        Gee.Collection<DataSource>? sources = null;
        foreach (DataView view in get_selected()) {
            DataSource source = view.get_source();
            if (source.get_type().is_a(t)) {
                if (sources == null)
                    sources = new Gee.ArrayList<DataSource>();
                
                sources.add(source);
            }
        }
        
        return sources;
    }
    
    // Returns -1 if source is not in the ViewCollection.
    public int index_of_source(DataSource source) {
        DataView? view = get_view_for_source(source);
        
        return (view != null) ? index_of(view) : -1;
    }
    
    // This is only used by DataView.
    public void internal_notify_view_altered(DataView view) {
        if (!are_notifications_frozen()) {
            notify_item_view_altered(view);
            notify_views_altered((Gee.Collection<DataView>) get_singleton(view));
        } else {
            if (frozen_views_altered == null)
                frozen_views_altered = new Gee.HashSet<DataView>();
            frozen_views_altered.add(view);
        }
    }
    
    // This is only used by DataView.
    public void internal_notify_geometry_altered(DataView view) {
        if (!are_notifications_frozen()) {
            notify_item_geometry_altered(view);
            notify_geometries_altered((Gee.Collection<DataView>) get_singleton(view));
        } else {
            if (frozen_geometries_altered == null)
                frozen_geometries_altered = new Gee.HashSet<DataView>();
            frozen_geometries_altered.add(view);
        }
    }
    
    protected override void notify_thawed() {
        if (frozen_views_altered != null) {
            foreach (DataView view in frozen_views_altered)
                notify_item_view_altered(view);
            notify_views_altered(frozen_views_altered);
            frozen_views_altered = null;
        }
        
        if (frozen_geometries_altered != null) {
            foreach (DataView view in frozen_geometries_altered)
                notify_item_geometry_altered(view);
            notify_geometries_altered(frozen_geometries_altered);
            frozen_geometries_altered = null;
        }
        
        base.notify_thawed();
    }
    
    public bool are_items_filtered_out() {
        return base.get_count() != get_count();
    }
}

