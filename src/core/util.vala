/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// SingletonCollection is a read-only collection designed to hold exactly one item in it.  This
// is far more efficient than creating a dummy collection (such as ArrayList) merely to pass around
// a single item, particularly for signals which require Iterables and Collections.
//
// This collection cannot be used to store null.

public class SingletonCollection<G> : Gee.AbstractCollection<G> {
    private class SingletonIterator<G> : Object, Gee.Traversable<G>, Gee.Iterator<G> {
        private SingletonCollection<G> c;
        private bool done = false;
        private G? current = null;
        
        public SingletonIterator(SingletonCollection<G> c) {
            this.c = c;
        }
        
        public bool read_only {
            get { return done; }
        }
        
        public bool valid {
            get { return done; }
        }
        
        public bool foreach(Gee.ForallFunc<G> f) {
            return f(c.object);
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
    
    public override bool read_only {
        get { return false; }
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
public delegate bool ProgressMonitor(uint64 current, uint64 total, bool do_event_loop = true);

// UnknownTotalMonitor is useful when an interface cannot report the total count to a ProgressMonitor,
// only a count, but the total is known by the caller.
public class UnknownTotalMonitor {
    private uint64 total;
    private unowned ProgressMonitor wrapped_monitor;
    
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
    private unowned ProgressMonitor wrapped_monitor;
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


double degrees_to_radians(double theta) {
    return (theta * (GLib.Math.PI / 180.0));
}
