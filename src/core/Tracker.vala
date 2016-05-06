/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Core {

// A TrackerAccumulator is called by Tracker indicating when a DataObject should be included or
// unincluded in its accumulated data.  All methods return true if their data has changed,
// indicating that the Tracker's "updated" signal should be fired.
public interface TrackerAccumulator : Object {
    public abstract bool include(DataObject object);
    
    public abstract bool uninclude(DataObject object);
    
    public abstract bool altered(DataObject object, Alteration alteration);
}

// A Tracker monitors a DataCollection and reports to an installed TrackerAccumulator when objects
// are available and unavailable.  This simplifies connecting to the DataCollection manually to
// monitoring availability (or subclassing for similar reasons, which may not always be available).
public class Tracker {
    protected delegate bool IncludeUnincludeObject(DataObject object);
    
    private DataCollection collection;
    private Gee.Collection<DataObject>? initial;
    private TrackerAccumulator? acc = null;
    
    public virtual signal void updated() {
    }
    
    public Tracker(DataCollection collection, Gee.Collection<DataObject>? initial = null) {
        this.collection = collection;
        this.initial = initial;
    }
    
    ~Tracker() {
        if (acc != null) {
            collection.items_added.disconnect(on_items_added);
            collection.items_removed.disconnect(on_items_removed);
            collection.items_altered.disconnect(on_items_altered);
        }
    }
    
    public void start(TrackerAccumulator acc) {
        // can only be started once
        assert(this.acc == null);
        
        this.acc = acc;
        
        collection.items_added.connect(on_items_added);
        collection.items_removed.connect(on_items_removed);
        collection.items_altered.connect(on_items_altered);
        
        if (initial != null && initial.size > 0)
            on_items_added(initial);
        else if (initial == null)
            on_items_added(collection.get_all());
        
        initial = null;
    }
    
    public DataCollection get_collection() {
        return collection;
    }
    
    private void on_items_added(Gee.Iterable<DataObject> added) {
        include_uninclude(added, acc.include);
    }
    
    private void on_items_removed(Gee.Iterable<DataObject> removed) {
        include_uninclude(removed, acc.uninclude);
    }
    
    // Subclasses can use this as a utility method.
    protected void include_uninclude(Gee.Iterable<DataObject> objects, IncludeUnincludeObject cb) {
        bool fire_updated = false;
        foreach (DataObject object in objects)
            fire_updated = cb(object) || fire_updated;
        
        if (fire_updated)
            updated();
    }
    
    private void on_items_altered(Gee.Map<DataObject, Alteration> map) {
        bool fire_updated = false;
        foreach (DataObject object in map.keys)
            fire_updated = acc.altered(object, map.get(object)) || fire_updated;
        
        if (fire_updated)
            updated();
    }
}

// A ViewTracker is Tracker designed for ViewCollections.  It uses an internal mux to route
// Tracker's calls to three TrackerAccumulators: all (all objects in the ViewCollection), selected
// (only for selected objects) and visible (only for items not hidden or filtered out).
public class ViewTracker : Tracker {
    private class Mux : Object, TrackerAccumulator {
        public TrackerAccumulator? all;
        public TrackerAccumulator? visible;
        public TrackerAccumulator? selected;
        
        public Mux(TrackerAccumulator? all, TrackerAccumulator? visible, TrackerAccumulator? selected) {
            this.all = all;
            this.visible = visible;
            this.selected = selected;
        }
        
        public bool include(DataObject object) {
            DataView view = (DataView) object;
            
            bool fire_updated = false;
            
            if (all != null)
                fire_updated = all.include(view) || fire_updated;
            
            if (visible != null && view.is_visible())
                fire_updated = visible.include(view) || fire_updated;
            
            if (selected != null && view.is_selected())
                fire_updated = selected.include(view) || fire_updated;
            
            return fire_updated;
        }
        
        public bool uninclude(DataObject object) {
            DataView view = (DataView) object;
            
            bool fire_updated = false;
            
            if (all != null)
                fire_updated = all.uninclude(view) || fire_updated;
            
            if (visible != null && view.is_visible())
                fire_updated = visible.uninclude(view) || fire_updated;
            
            if (selected != null && view.is_selected())
                fire_updated = selected.uninclude(view) || fire_updated;
            
            return fire_updated;
        }
        
        public bool altered(DataObject object, Alteration alteration) {
            DataView view = (DataView) object;
            
            bool fire_updated = false;
            
            if (all != null)
                fire_updated = all.altered(view, alteration) || fire_updated;
            
            if (visible != null && view.is_visible())
                fire_updated = visible.altered(view, alteration) || fire_updated;
            
            if (selected != null && view.is_selected())
                fire_updated = selected.altered(view, alteration) || fire_updated;
            
            return fire_updated;
        }
    }
    
    private Mux? mux = null;
    
    public ViewTracker(ViewCollection collection) {
        base (collection, collection.get_all_unfiltered());
    }
    
    ~ViewTracker() {
        if (mux != null) {
            ViewCollection? collection = get_collection() as ViewCollection;
            assert(collection != null);
            collection.items_shown.disconnect(on_items_shown);
            collection.items_hidden.disconnect(on_items_hidden);
            collection.items_selected.disconnect(on_items_selected);
            collection.items_unselected.disconnect(on_items_unselected);
        }
    }
    
    public new void start(TrackerAccumulator? all, TrackerAccumulator? visible, TrackerAccumulator? selected) {
        assert(mux == null);
        
        mux = new Mux(all, visible, selected);
        
        ViewCollection? collection = get_collection() as ViewCollection;
        assert(collection != null);
        collection.items_shown.connect(on_items_shown);
        collection.items_hidden.connect(on_items_hidden);
        collection.items_selected.connect(on_items_selected);
        collection.items_unselected.connect(on_items_unselected);
        
        base.start(mux);
    }
    
    private void on_items_shown(Gee.Collection<DataView> shown) {
        if (mux.visible != null)
            include_uninclude(shown, mux.visible.include);
    }
    
    private void on_items_hidden(Gee.Collection<DataView> hidden) {
        if (mux.visible != null)
            include_uninclude(hidden, mux.visible.uninclude);
    }
    
    private void on_items_selected(Gee.Iterable<DataView> selected) {
        if (mux.selected != null)
            include_uninclude(selected, mux.selected.include);
    }
    
    private void on_items_unselected(Gee.Iterable<DataView> unselected) {
        if (mux.selected != null)
            include_uninclude(unselected, mux.selected.uninclude);
    }
}

}
