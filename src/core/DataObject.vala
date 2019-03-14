/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

//
// DataObject
//
// Object IDs are incremented for each DataObject, and therefore may be used to compare
// creation order.  This behavior may be relied upon elsewhere.  Object IDs may be recycled when
// DataObjects are reconstituted by a proxy.
//
// Ordinal IDs are supplied by DataCollections to record the ordering of the object being added
// to the collection.  This value is primarily only used by DataCollection, but may be used
// elsewhere to resolve ordering questions (including stabilizing a sort).
//

// Have to inherit from Object due to ContainerSource and this bug:
// https://bugzilla.gnome.org/show_bug.cgi?id=615904
public abstract class DataObject : Object {
    public const int64 INVALID_OBJECT_ID = -1;
    
    private static int64 object_id_generator = 0;
    
#if TRACE_DTORS
    // because calling to_string() in a destructor is dangerous, stash to_string()'s result in
    // this variable for reporting
    protected string dbg_to_string = null;
#endif
    
    private int64 object_id = INVALID_OBJECT_ID;
    private DataCollection member_of = null;
    private int64 ordinal = DataCollection.INVALID_OBJECT_ORDINAL;
    
    // NOTE: Supplying an object ID should *only* be used when reconstituting the object (generally
    // only done by DataSources).
    protected DataObject(int64 object_id = INVALID_OBJECT_ID) {
        this.object_id = (object_id == INVALID_OBJECT_ID) ? object_id_generator++ : object_id;
    }
    
    public virtual void notify_altered(Alteration alteration) {
        if (member_of != null)
            member_of.internal_notify_altered(this, alteration);
    }
    
    // There is no membership_changed signal as it's expensive (esp. at startup) and not needed
    // at this time.  The notify_membership_changed mechanism is still in place for subclasses.
    //
    // This is called after the change has occurred (i.e., after the DataObject has been added
    // to the DataCollection, or after it has been remove from the same).  It is also called after
    // the DataCollection has reported the change on its own signals, so it and its children can
    // properly integrate the DataObject into its pools.
    //
    // This is only called by DataCollection.
    public virtual void notify_membership_changed(DataCollection? collection) {
    }
    
    // Generally, this is only called by DataCollection.  No signal is bound to this because
    // it's not needed currently and affects performance.
    public virtual void notify_collection_property_set(string name, Value? old, Value val) {
    }
    
    // Generally, this is only called by DataCollection.  No signal is bound to this because
    // it's not needed currently and affects performance.
    public virtual void notify_collection_property_cleared(string name) {
    }
    
    public abstract string get_name();
    
    public abstract string to_string();
    
    public DataCollection? get_membership() {
        return member_of;
    }
    
    public bool has_membership() {
        return member_of != null;
    }
    
    // This method is only called by DataCollection.  It's called after the DataObject has been
    // assigned to a DataCollection.
    public void internal_set_membership(DataCollection collection, int64 ordinal) {
        assert(member_of == null);
        
        member_of = collection;
        this.ordinal = ordinal;
        
#if TRACE_DTORS
        dbg_to_string = to_string();
#endif
    }
    
    // This method is only called by SourceHoldingTank (to give ordinality to its unassociated
    // members).  DataCollections should call internal_set_membership.
    public void internal_set_ordinal(int64 ordinal) {
        assert(member_of == null);
        
        this.ordinal = ordinal;
    }
    
    // This method is only called by DataCollection.  It's called after the DataObject has been
    // assigned to a DataCollection.
    public void internal_clear_membership() {
        member_of = null;
        ordinal = DataCollection.INVALID_OBJECT_ORDINAL;
    }
    
    // This method is only called by DataCollection, DataSet, and SourceHoldingTank.
    public inline int64 internal_get_ordinal() {
        return ordinal;
    }
    
    public inline int64 get_object_id() {
        return object_id;
    }
    
    public Value get_collection_property(string name, Value? def = null) {
        if (member_of == null)
            return def;
        
        Value? result = member_of.get_property(name);
        
        return (result != null) ? result : def;
    }
    
    public void set_collection_property(string name, Value val, ValueEqualFunc? value_equals = null) {
        if (member_of != null)
            member_of.set_property(name, val, value_equals);
    }
    
    public void clear_collection_property(string name) {
        if (member_of != null)
            member_of.clear_property(name);
    }
}

