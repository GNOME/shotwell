/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
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
    private unowned Comparator user_comparator = null;
    private unowned ComparatorPredicate? comparator_predicate = null;
    
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
        int64 result = 0;
        
        if (user_comparator != null)
            result = user_comparator(a, b);
            
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
    
    public unowned Comparator get_comparator() {
        return user_comparator;
    }
    
    public unowned ComparatorPredicate get_comparator_predicate() {
        return comparator_predicate;
    }
    
    public void set_comparator(Comparator user_comparator, ComparatorPredicate? comparator_predicate) {
        this.user_comparator = user_comparator;
        this.comparator_predicate = comparator_predicate;
        list.resort(comparator_wrapper);
    }
    
    public Gee.List<DataObject> get_all() {
        return list.read_only_view_as_list;
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

