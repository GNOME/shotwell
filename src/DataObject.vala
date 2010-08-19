/* Copyright 2009-2010 Yorba Foundation
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

//
// Alteration represents a description of what has changed in the DataObject (reported via the
// "altered" signal).  Since the descriptions can vary wildly depending on the semantics of each
// DataObject, no assumptions or requirements are placed on Alteration other than it must have
// one or more "subjects", each with a "detail".  Subscribers to the "altered" signal can query
// the Alteration object to determine if the change is important to them.
//
// Alteration is an immutable type.  This means it's possible to store const Alterations of oft-used
// values for reuse.
//
// Alterations may be compressed, merging their subjects and details into a new aggregated
// Alteration.  Generally this is handled automatically by DataObject and DataCollection, when
// necessary.
//
// NOTE: subjects and details should be ASCII labels (as in, plain-old ASCII, no code pages).
// They are treated as case-sensitive strings.
//
// Recommended subjects include: image, thumbnail, metadata.
//

public class Alteration {
    private string subject = null;
    private string detail = null;
    private Gee.MultiMap<string, string> map = null;
    
    public Alteration(string subject, string detail) {
        add_detail(subject, detail);
    }
    
    // Create an Alteration that has more than one subject/detail.  list is a comma-delimited
    // string of colon-separated subject:detail pairs.
    public Alteration.from_list(string list) requires (list.length > 0) {
        string[] pairs = list.split(",");
        assert(pairs.length >= 1);
        
        foreach (string pair in pairs) {
            string[] subject_detail = pair.split(":", 2);
            assert(subject_detail.length == 2);
            
            add_detail(subject_detail[0], subject_detail[1]);
        }
    }
    
    // Used for compression.
    private Alteration.from_map(Gee.MultiMap<string, string> map) {
        this.map = map;
    }
    
    private void add_detail(string sub, string det) {
        // strip leading and trailing whitespace
        string subject = sub.strip();
        assert(subject.length > 0);
        
        string detail = det.strip();
        assert(detail.length > 0);
        
        // if a simple Alteration, store in singleton refs
        if (this.subject == null && map == null) {
            assert(this.detail == null);
            
            this.subject = subject;
            this.detail = detail;
            
            return;
        }
        
        // Now a complex Alteration, requiring a Map.
        if (map == null)
            map = create_map();
        
        // Move singletons into Map
        if (this.subject != null) {
            assert(this.detail != null);
            
            map.set(this.subject, this.detail);
            this.subject = null;
            this.detail = null;
        }
        
        // Store new subject:detail in Map as well
        map.set(subject, detail);
    }
    
    private Gee.MultiMap<string, string> create_map() {
        return new Gee.HashMultiMap<string, string>(case_hash, case_equal, case_hash, case_equal);
    }
    
    private static bool case_equal(void *a, void *b) {
        return equal_values((string) a, (string) b);
    }
    
    private static uint case_hash(void *a) {
        return hash_value((string) a);
    }
    
    private static inline bool equal_values(string str1, string str2) {
        return str1.ascii_casecmp(str2) == 0;
    }
    
    private static inline uint hash_value(string str) {
        return str_hash(str);
    }
    
    public bool has_subject(string subject) {
        if (this.subject != null)
            return equal_values(this.subject, subject);
        
        assert(map != null);
        Gee.Set<string>? keys = map.get_keys();
            if (keys != null) {
                foreach (string key in keys) {
                    if (equal_values(key, subject))
                        return true;
            }
        }
        
        return false;
    }
    
    public bool has_detail(string subject, string detail) {
        if (this.subject != null && this.detail != null)
            return equal_values(this.subject, subject) && equal_values(this.detail, detail);
        
        assert(map != null);
        Gee.Collection<string>? values = map.get(subject);
        if (values != null) {
            foreach (string value in values) {
                if (equal_values(value, detail))
                    return true;
            }
        }
        
        return false;
    }
    
    public string to_string() {
        if (subject != null) {
            assert(detail != null);
            
            return "%s:%s".printf(subject, detail);
        }
        
        assert(map != null);
        
        string str = "";
        foreach (string key in map.get_keys()) {
            foreach (string value in map.get(key)) {
                if (str.length != 0)
                    str += ", ";
                
                str += "%s:%s".printf(key, value);
            }
        }
        
        return str;
    }
    
    // Returns true if this object has any subject:detail matches with the supplied Alteration.
    public bool contains_any(Alteration other) {
        // identity
        if (this == other)
            return true;
        
        // if both singletons, check for singleton match
        if (subject != null && other.subject != null && detail != null && other.detail != null)
            return equal_values(subject, other.subject) && equal_values(detail, other.detail);
        
        // if both multiples, check for any match at all
        if (map != null && other.map != null) {
            Gee.Set<string>? keys = map.get_keys();
            assert(keys != null);
            Gee.Set<string>? other_keys = other.map.get_keys();
            assert(other_keys != null);
            
            foreach (string subject in other_keys) {
                if (!keys.contains(subject))
                    continue;
                
                Gee.Collection<string>? details = map.get(subject);
                Gee.Collection<string>? other_details = other.map.get(subject);
                
                if (details != null && other_details != null) {
                    foreach (string detail in other_details) {
                        if (details.contains(detail))
                            return true;
                    }
                }
            }
        }
        
        return false;
    }
    
    public bool equals(Alteration other) {
        // identity
        if (this == other)
            return true;
        
        // if both singletons, check for singleton match
        if (subject != null && other.subject != null && detail != null && other.detail != null)
            return equal_values(subject, other.subject) && equal_values(detail, other.detail);
        
        // if both multiples, check for across-the-board matches
        if (map != null && other.map != null) {
            // see if both maps contain the same set of keys
            Gee.Set<string>? keys = map.get_keys();
            assert(keys != null);
            Gee.Set<string>? other_keys = other.map.get_keys();
            assert(other_keys != null);
            
            if (keys.size != other_keys.size)
                return false;
            
            if (!keys.contains_all(other_keys))
                return false;
            
            if (!other_keys.contains_all(keys))
                return false;
            
            foreach (string key in keys) {
                Gee.Collection<string> values = map.get(key);
                Gee.Collection<string> other_values = other.map.get(key);
                
                if (values.size != other_values.size)
                    return false;
                
                if (!values.contains_all(other_values))
                    return false;
                
                if (!other_values.contains_all(values))
                    return false;
            }
            
            // maps are identical
            return true;
        }
        
        // one singleton and one multiple, not equal
        return false;
    }
    
    private static void multimap_add_all(Gee.MultiMap<string, string> dest,
        Gee.MultiMap<string, string> src) {
        Gee.Set<string> keys = src.get_keys();
        foreach (string key in keys) {
            Gee.Collection<string> values = src.get(key);
            foreach (string value in values)
                dest.set(key, value);
        }
    }
    
    // This merges the Alterations, returning a new Alteration with both represented.  If both
    // Alterations are equal, this will return this object rather than create a new one.
    public Alteration compress(Alteration other) {
        if (equals(other))
            return this;
        
        // Build a new Alteration with both represented ... if they're unequal, then the new one
        // is guaranteed not to be a singleton
        Gee.MultiMap<string, string> compressed = create_map();
        
        if (subject != null && detail != null) {
            compressed.set(subject, detail);
        } else {
            assert(map != null);
            multimap_add_all(compressed, map);
        }
        
        if (other.subject != null && other.detail != null) {
            compressed.set(other.subject, other.detail);
        } else {
            assert(other.map != null);
            multimap_add_all(compressed, other.map);
        }
        
        return new Alteration.from_map(compressed);
    }
}

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
    private Alteration frozen_alteration = null;
    
    // This signal is fired when the source of the data is altered in a way that's significant
    // to how it's represented in the application.  This base signal must be called by child
    // classes if the collection it is a member of is to be notified.
    public virtual signal void altered(Alteration alteration) {
    }
    
    // NOTE: Supplying an object ID should *only* be used when reconstituting the object (generally
    // only done by DataSources).
    public DataObject(int64 object_id = INVALID_OBJECT_ID) {
        this.object_id = (object_id == INVALID_OBJECT_ID) ? object_id_generator++ : object_id;
    }
    
    public virtual void notify_altered(Alteration alteration) {
        // fire signal on self, if notifications aren't frozen
        if (member_of != null) {
            if (!member_of.are_notifications_frozen())
                altered(alteration);
            else
                frozen_alteration = (frozen_alteration == null) ? alteration
                    : frozen_alteration.compress(alteration);
        } else {
            altered(alteration);
        }
        
        // notify DataCollection in any event
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
    
    // This method is only called by DataCollection
    public virtual void internal_collection_thawed() {
        // if captured one or more alterations while frozen, fire them now
        if (frozen_alteration == null)
            return;
        
        // swap due to possible reentrancy
        Alteration copy = frozen_alteration;
        frozen_alteration = null;
        
        // don't call notify_altered(), as that will redirect the Alteration to the DataCollection,
        // which is already handling this for its observers
        altered(copy);
    }

    public inline int64 get_object_id() {
        return object_id;
    }
    
    public Value? get_collection_property(string name, Value? def = null) {
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

//
// DataSource
// 
// A DataSource is an object that is unique throughout the system.  DataSources
// commonly have external and/or persistent representations, hence they have a notion of being
// destroyed (versus removed or freed).  Several DataViews may exist that reference a single
// DataSource.  Note that DataSources MUST be destroyed (rather than simply removed) from their
// SourceCollection, and that they MUST be destroyed via their SourceCollection (rather than
// calling DataSource.destroy() directly.)
//
// Destroying a DataSource indicates it should remove all secondary and tertiary structures (such
// as thumbnails) and any records pointing to its backing store.  SourceCollection.destroy_marked()
// has a parameter indicating if the backing should be destroyed as well; that is when
// internal_delete_backing() is called.
//
// There are no provisions (currently) for a DataSource to be removed from its SourceCollection
// without destroying its backing and/or secondary and tertiary structures.  DataSources are intended
// to go to the grave with their SourceCollection otherwise.  If a need arises for a DataSource to
// be peaceably removed from its SourceCollection, code will need to be written.  SourceSnapshots
// may be one solution to this problem.
//
// Some DataSources cannot be reconstituted (for example, if its backing file is deleted).  In
// that case, dehydrate() should return null.  When reconstituted, it is the responsibility of the
// implementation to ensure an exact clone is produced, minus any details that are not relevant or
// exposed (such as a database ID).
//
// If other DataSources refer to this DataSource, their state will *not* be 
// saved/restored.  This must be achieved via other means.  However, implementations *should*
// track when changes to external state would break the proxy and call notify_broken();
//

public abstract class SourceSnapshot {
    private bool snapshot_broken = false;
    
    // This is signalled when the DataSource, for whatever reason, can no longer be reconstituted
    // from this Snapshot.
    public virtual signal void broken() {
    }
    
    public virtual void notify_broken() {
        snapshot_broken = true;
        
        broken();
    }
    
    public bool is_broken() {
        return snapshot_broken;
    }
}

// Link state name may not contain the equal sign ("=").  Link names and values may not contain the 
// pipe-character ("|").  Both will be stripped of leading and trailing whitespace.  This may
// affect retrieval.
public class SourceBacklink {
    private string _name;
    private string _value;
    
    public string name {
        get {
            return _name;
        }
    }
    
    public string value {
        get {
            return _value;
        }
    }
    
    public SourceBacklink(string name, string value) {
        assert(!name.contains("="));
        assert(!name.contains("|"));
        assert(!value.contains("|"));
        
        _name = name.strip();
        _value = value.strip();
    }
    
    public string to_string() {
        return "Backlink %s=%s".printf(name, value);
    }
    
    public static uint hash_func(void *key) {
        SourceBacklink *backlink = (SourceBacklink *) key;
        
        return str_hash(backlink->_name) ^ str_hash(backlink->_value);
    }
    
    public static bool equal_func(void *a, void *b) {
        SourceBacklink *alink = (SourceBacklink *) a;
        SourceBacklink *blink = (SourceBacklink *) b;
        
        return str_equal(alink->_name, blink->_name) && str_equal(alink->_value, blink->_value);
    }
}

public abstract class DataSource : DataObject {
    protected delegate void ContactSubscriber(DataView view);
    protected delegate void ContactSubscriberAlteration(DataView view, Alteration alteration);
    
    private DataView[] subscribers = new DataView[4];
    private weak SourceCollection unlinked_from_collection = null;
    private Gee.HashMap<string, Gee.List<string>> backlinks = null;
    private bool in_contact = false;
    private bool marked_for_destroy = false;
    private bool is_destroyed = false;
    private Alteration frozen_alteration = null;
    
    // This signal is fired after the DataSource has been unlinked from its SourceCollection.
    public virtual signal void unlinked(SourceCollection sources) {
    }
    
    // This signal is fired after the DataSource has been relinked to a SourceCollection.
    public virtual signal void relinked(SourceCollection sources) {
    }
    
    // This signal is fired at the end of the destroy() chain.  The object's state is either fragile
    // or unusable.  It is up to all observers to drop their references to the DataObject.
    public virtual signal void destroyed() {
    }
    
    public DataSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    ~DataSource() {
#if TRACE_DTORS
        debug("DTOR: DataSource %s", dbg_to_string);
#endif
    }
    
    public override void notify_altered(Alteration alteration) {
        // if SourceCollection is frozen, freeze notifications to subscribers as well
        if (get_membership() != null && get_membership().are_notifications_frozen()) {
            frozen_alteration = (frozen_alteration == null) ? alteration
                : frozen_alteration.compress(alteration);
        } else {
            // signal reflection
            contact_subscribers_alteration(subscriber_altered, alteration);
        }
        
        // call base class in all cases
        base.notify_altered(alteration);
    }
    
    public override void internal_collection_thawed() {
        if (frozen_alteration != null) {
            // swap out due to possible reentrancy
            Alteration alteration = frozen_alteration;
            frozen_alteration = null;
            
            contact_subscribers_alteration(subscriber_altered, alteration);
        }
        
        base.internal_collection_thawed();
    }
    
    private void subscriber_altered(DataView view, Alteration alteration) {
        view.notify_altered(alteration);
    }
    
    public override void notify_membership_changed(DataCollection? collection) {
        // DataSources can only be removed once they've been destroyed or unlinked.
        if (collection == null) {
            assert(is_destroyed || backlinks != null);
        } else {
            assert(!is_destroyed);
        }
        
        // If removed from a collection but have backlinks, then that's an unlink.
        if (collection == null && backlinks != null)
            notify_unlinked();
        
        base.notify_membership_changed(collection);
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.
    public virtual void notify_unlinking(SourceCollection collection) {
        assert(backlinks == null && unlinked_from_collection == null);
        
        unlinked_from_collection = collection;
        backlinks = new Gee.HashMap<string, Gee.List<string>>();
        
        contact_subscribers(subscriber_unlinking);
    }
    
    // This method is called by DataSource.  It should not be called otherwise.
    protected virtual void notify_unlinked() {
        assert(unlinked_from_collection != null && backlinks != null);
        
        unlinked(unlinked_from_collection);
        
        // give the DataSource a chance to persist the link state, if any
        if (backlinks.size > 0)
            commit_backlinks(unlinked_from_collection, dehydrate_backlinks());
    }
    
    private void subscriber_unlinking(DataView view) {
        view.notify_source_unlinking(unlinked_from_collection);
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.
    public virtual void notify_relinking(SourceCollection collection) {
        assert(backlinks != null && unlinked_from_collection == collection);
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.
    public virtual void notify_relinked() {
        assert(backlinks != null && unlinked_from_collection != null);
        
        SourceCollection relinked_to = unlinked_from_collection;
        backlinks = null;
        unlinked_from_collection = null;
        relinked(relinked_to);
        contact_subscribers(subscriber_relinked);
        
        // have the DataSource delete any persisted link state
        commit_backlinks(null, null);
    }
    
    private void subscriber_relinked(DataView view) {
        view.notify_source_relinked((SourceCollection) get_membership());
    }
    
    public bool has_backlink(SourceBacklink backlink) {
        if (backlinks == null)
            return false;
        
        Gee.List<string>? values = backlinks.get(backlink.name);
        
        return values != null ? values.contains(backlink.value) : false;
    }
    
    public Gee.List<SourceBacklink>? get_backlinks(string name) {
        if (backlinks == null)
            return null;
        
        Gee.List<string>? values = backlinks.get(name);
        if (values == null || values.size == 0)
            return null;
        
        Gee.List<SourceBacklink> backlinks = new Gee.ArrayList<SourceBacklink>();
        foreach (string value in values)
            backlinks.add(new SourceBacklink(name, value));
        
        return backlinks;
    }
    
    public void set_backlink(SourceBacklink backlink) {
        // can only be called during an unlink operation
        assert(backlinks != null);
        
        Gee.List<string> values = backlinks.get(backlink.name);
        if (values == null) {
            values = new Gee.ArrayList<string>();
            backlinks.set(backlink.name, values);
        }
        
        values.add(backlink.value);
        
        SourceCollection? sources = (SourceCollection?) get_membership();
        if (sources != null)
            sources.internal_backlink_set(this, backlink);
    }
    
    public bool remove_backlink(SourceBacklink backlink) {
        if (backlinks == null)
            return false;
        
        Gee.List<string> values = backlinks.get(backlink.name);
        if (values == null)
            return false;
        
        int original_size = values.size;
        assert(original_size > 0);
        
        Gee.Iterator<string> iter = values.iterator();
        while (iter.next()) {
            if (iter.get() == backlink.value)
                iter.remove();
        }
        
        if (values.size == 0)
            backlinks.unset(backlink.name);
        
        // Commit here because this can come at any time; setting the backlinks should only 
        // happen during an unlink, which commits at the end of the cycle.
        commit_backlinks(unlinked_from_collection, dehydrate_backlinks());
        
        SourceCollection? sources = (SourceCollection?) get_membership();
        if (sources != null)
            sources.internal_backlink_removed(this, backlink);
        
        return values.size != original_size;
    }
    
    // Base implementation is to do nothing; if DataSource wishes to persist link state across
    // application sessions, it should do so when this is called.  Do not call this base method
    // when overriding; it will only issue a warning.
    //
    // If dehydrated is null, the persisted link state should be deleted.  sources will be null
    // as well.
    protected virtual void commit_backlinks(SourceCollection? sources, string? dehydrated) {
        if (sources != null || dehydrated != null)
            warning("No implementation to commit link state for %s", to_string());
    }
    
    private string? dehydrate_backlinks() {
        if (backlinks == null || backlinks.size == 0)
            return null;
        
        StringBuilder builder = new StringBuilder();
        foreach (string name in backlinks.keys) {
            Gee.List<string> values = backlinks.get(name);
            if (values == null || values.size == 0)
                continue;
            
            string value_field = "";
            foreach (string value in values) {
                if (value != null && value.length > 0)
                    value_field += value + "|";
            }
            
            if (value_field.length > 0)
                builder.append("%s=%s\n".printf(name, value_field));
        }
        
        return builder.str.length > 0 ? builder.str : null;
    }
    
    // If dehydrated is null, this method will still put the DataSource into an unlinked state,
    // simply without any backlinks to reestablish.
    public void rehydrate_backlinks(SourceCollection unlinked_from, string? dehydrated) {
        unlinked_from_collection = unlinked_from;
        backlinks = new Gee.HashMap<string, Gee.List<string>>();
        
        if (dehydrated == null)
            return;
        
        string[] lines = dehydrated.split("\n");
        foreach (string line in lines) {
            if (line.length == 0)
                continue;
            
            string[] tokens = line.split("=", 2);
            if (tokens.length < 2) {
                warning("Unable to rehydrate \"%s\" for %s: name and value not present", line,
                    to_string());
                
                continue;
            }
            
            string[] decoded_values = tokens[1].split("|");
            Gee.List<string> values = new Gee.ArrayList<string>();
            foreach (string value in decoded_values) {
                if (value != null && value.length > 0)
                    values.add(value);
            }
            
            if (values.size > 0)
                backlinks.set(tokens[0], values);
        }
    }
    
    // If a DataSource cannot produce snapshots, return null.
    public virtual SourceSnapshot? save_snapshot() {
        return null;
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.
    public void internal_mark_for_destroy() {
        marked_for_destroy = true;
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.
    //
    // This method deletes whatever backing this DataSource represents.  It should either return
    // false or throw an error if the delete fails.
    public virtual bool internal_delete_backing() throws Error {
        return true;
    }
    
    // Because of the rules of DataSources, a DataSource is only equal to itself; subclasses
    // may override this to perform validations and/or assertions
    public virtual bool equals(DataSource? source) {
        return (this == source);
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.  To destroy
    // a DataSource, destroy it from its SourceCollection.
    //
    // Child classes should call this base class to ensure that the collection this object is
    // a member of is notified and the signal is properly called.  The collection will remove this
    // object automatically.
    public virtual void destroy() {
        assert(marked_for_destroy);
        
        // mark as destroyed
        is_destroyed = true;
        
        // unsubscribe all subscribers
        for (int ctr = 0; ctr < subscribers.length; ctr++) {
            if (subscribers[ctr] != null) {
                DataView view = subscribers[ctr];
                subscribers[ctr] = null;
                
                view.notify_unsubscribed(this);
            }
        }
        
        // propagate the signal
        destroyed();
    }
    
    // This method can be used to destroy a DataSource before it's added to a SourceCollection
    // or has been unlinked from one. It should not be used otherwise.  (In particular, don't
    // automate destroys by removing and then calling this method -- that will happen automatically.)
    // To destroy a DataSource already integrated into a SourceCollection, call
    // SourceCollection.destroy_marked().
    public void destroy_orphan(bool delete_backing) {
        if (delete_backing) {
            try {
                if (!internal_delete_backing())
                    warning("Unable to delete backing for %s", to_string());
            } catch (Error err) {
                warning("Unable to delete backing for %s: %s", to_string(), err.message);
            }
        }
        
        internal_mark_for_destroy();
        destroy();
        
        if (unlinked_from_collection != null)
            unlinked_from_collection.notify_unlinked_destroyed(this);
    }

    // DataViews subscribe to the DataSource to inform it of their existance.  Not only does this
    // allow for signal reflection (i.e. DataSource.altered -> DataView.altered) it also makes
    // them first-in-line for notification of destruction, so they can remove themselves from 
    // their ViewCollections automatically.
    //
    // This method is only called by DataView.
    public void internal_subscribe(DataView view) {
        assert(!in_contact);
        
        for (int ctr = 0; ctr < subscribers.length; ctr++) {
            if (subscribers[ctr] == null) {
                subscribers[ctr] = view;
                
                return;
            }
        }
        
        subscribers += view;
    }
    
    // This method is only called by DataView.  NOTE: This method does NOT call
    // DataView.notify_unsubscribed(), as it's assumed the DataView itself will do so if appropriate.
    public void internal_unsubscribe(DataView view) {
        assert(!in_contact);
        
        for (int ctr = 0; ctr < subscribers.length; ctr++) {
            if (subscribers[ctr] == view) {
                subscribers[ctr] = null;
                
                return;
            }
        }
    }
    
    protected void contact_subscribers(ContactSubscriber contact_subscriber) {
        assert(!in_contact);
        
        in_contact = true;
        for (int ctr = 0; ctr < subscribers.length; ctr++) {
            if (subscribers[ctr] != null)
                contact_subscriber(subscribers[ctr]);
        }
        in_contact = false;
    }
    
    protected void contact_subscribers_alteration(ContactSubscriberAlteration contact_subscriber,
        Alteration alteration) {
        assert(!in_contact);
        
        in_contact = true;
        for (int ctr = 0; ctr < subscribers.length; ctr++) {
            if (subscribers[ctr] != null)
                contact_subscriber(subscribers[ctr], alteration);
        }
        in_contact = false;
    }
}

public abstract class ThumbnailSource : DataSource {
    public virtual signal void thumbnail_altered() {
    }
    
    public ThumbnailSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    public virtual void notify_thumbnail_altered() {
        // fire signal on self
        thumbnail_altered();
        
        // signal reflection to DataViews
        contact_subscribers(subscriber_thumbnail_altered);
    }
    
    private void subscriber_thumbnail_altered(DataView view) {
        ((ThumbnailView) view).notify_thumbnail_altered();
    }

    public abstract Gdk.Pixbuf? get_thumbnail(int scale) throws Error;
    
    // get_thumbnail( ) may return a cached pixbuf; create_thumbnail( ) is guaranteed to create
    // a new pixbuf (e.g., by the source loading, decoding, and scaling image data)
    public abstract Gdk.Pixbuf? create_thumbnail(int scale) throws Error;
    
    public abstract string? get_unique_thumbnail_name();
    
    public abstract PhotoFileFormat get_preferred_thumbnail_format();
}

public abstract class PhotoSource : ThumbnailSource {
    public PhotoSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    public abstract time_t get_exposure_time();

    public abstract Dimensions get_dimensions();

    public abstract uint64 get_filesize();

    public abstract PhotoMetadata? get_metadata();
    
    public abstract Gdk.Pixbuf get_pixbuf(Scaling scaling) throws Error;
}

public abstract class EventSource : ThumbnailSource {
    public EventSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    public abstract time_t get_start_time();

    public abstract time_t get_end_time();

    public abstract uint64 get_total_filesize();
    
    public abstract int get_photo_count();
    
    public abstract Gee.Iterable<PhotoSource> get_photos();
}

//
// ContainerSource
//

public interface ContainerSource : DataSource {
    public abstract bool has_links();
    
    public abstract SourceBacklink get_backlink();
    
    public abstract void break_link(DataSource source);
    
    public abstract void break_link_many(Gee.Collection<DataSource> sources);
    
    public abstract void establish_link(DataSource source);
    
    public abstract void establish_link_many(Gee.Collection<DataSource> sources);
}

//
// SourceProxy
//
// A SourceProxy allows for a DataSource's state to be maintained in memory regardless of
// whether or not the DataSource has been destroyed.  If a user of SourceProxy
// requests the represented object and it is still in memory, it will be returned.  If not, it
// is reconstituted and the new DataSource is returned.
//
// Several SourceProxy can be wrapped around the same DataSource.  If the DataSource is
// destroyed, all Proxys drop their reference.  When a Proxy reconstitutes the DataSource, all
// will be aware of it and re-establish their reference.
//
// The snapshot that is maintained is the snapshot in regards to the time of the Proxy's creation.
// Proxys do not update their snapshot thereafter.  If a snapshot reports it is broken, the
// Proxy will not reconstitute the DataSource and get_source() will return null thereafter.
//
// There is no preferential treatment in regards to snapshots of the DataSources.  The first
// Proxy to reconstitute the DataSource wins.
//

public abstract class SourceProxy {
    private int64 object_id;
    private string source_string;
    private DataSource source;
    private SourceSnapshot snapshot;
    private SourceCollection membership;
    
    // This is only signalled by the SourceProxy that reconstituted the DataSource.  All
    // Proxys will signal when this occurs.
    public virtual signal void reconstituted(DataSource source) {
    }
    
    // This is signalled when the SourceProxy has dropped a destroyed DataSource.  Calling
    // get_source() will force it to be reconstituted.
    public virtual signal void dehydrated() {
    }
    
    // This is signalled when the held DataSourceSnapshot reports it is broken.  The DataSource
    // will not be reconstituted and get_source() will return null thereafter.
    public virtual signal void broken() {
    }
    
    public SourceProxy(DataSource source) {
        object_id = source.get_object_id();
        source_string = source.to_string();
        
        snapshot = source.save_snapshot();
        assert(snapshot != null);
        snapshot.broken.connect(on_snapshot_broken);
        
        set_source(source);
        
        membership = (SourceCollection) source.get_membership();
        assert(membership != null);
        membership.items_added.connect(on_source_added);
    }
    
    ~SourceProxy() {
        drop_source();
        membership.items_added.disconnect(on_source_added);
    }
    
    public abstract DataSource reconstitute(int64 object_id, SourceSnapshot snapshot);
    
    public virtual void notify_reconstituted(DataSource source) {
        reconstituted(source);
    }
    
    public virtual void notify_dehydrated() {
        dehydrated();
    }
    
    public virtual void notify_broken() {
        broken();
    }
    
    private void on_snapshot_broken() {
        drop_source();
        
        notify_broken();
    }
    
    private void set_source(DataSource source) {
        drop_source();
        
        this.source = source;
        source.destroyed.connect(on_destroyed);
    }
    
    private void drop_source() {
        if (source == null)
            return;
        
        source.destroyed.disconnect(on_destroyed);
        source = null;
    }
    
    public DataSource? get_source() {
        if (snapshot.is_broken())
            return null;
        
        if (source != null)
            return source;
        
        // without the source, need to reconstitute it and re-add to its original SourceCollection
        // it should also automatically add itself to its original collection (which is trapped
        // in on_source_added)
        DataSource new_source = reconstitute(object_id, snapshot);
        assert(source == new_source);
        assert(source.get_object_id() == object_id);
        assert(membership.contains(source));
        
        return source;
    }
    
    private void on_destroyed() {
        assert(source != null);
        
        // drop the reference ... will need to reconstitute later if requested
        drop_source();
        
        notify_dehydrated();
    }
    
    private void on_source_added(Gee.Iterable<DataObject> added) {
        // only interested in new objects when the proxied object has gone away
        if (source != null)
            return;
        
        foreach (DataObject object in added) {
            // looking for new objects with original source object's id
            if (object.get_object_id() != object_id)
                continue;
            
            // this is it; stash for future use
            set_source((DataSource) object);
            
            notify_reconstituted((DataSource) object);
            
            break;
        }
    }
}

public interface Proxyable {
    public abstract SourceProxy get_proxy();
}

//
// DataView
//

public class DataView : DataObject {
    private DataSource source;
    private bool selected = false;
    private bool visible = true;
    
    // Indicates that the selection state has changed.
    public virtual signal void state_changed(bool selected) {
    }
    
    // Indicates the visible state has changed.
    public virtual signal void visibility_changed(bool visible) {
    }
    
    // Indicates that the display (what is seen by the user) of the DataView has changed.
    public virtual signal void view_altered() {
    }
    
    // Indicates that the geometry of the DataView has changed (which implies the view has altered,
    // but only in that the same elements have changed size).
    public virtual signal void geometry_altered() {
    }
    
    public virtual signal void unsubscribed(DataSource source) {
    }
    
    public DataView(DataSource source) {
        this.source = source;
        
        // subscribe to the DataSource, which sets up signal reflection and gives the DataView
        // first notification of destruction.
        source.internal_subscribe(this);
    }
    
    ~DataView() {
#if TRACE_DTORS
        debug("DTOR: DataView %s", dbg_to_string);
#endif
        source.internal_unsubscribe(this);
    }
 
    public override string get_name() {
        return "View of %s".printf(source.get_name());
    }
    
    public override string to_string() {
        return "DataView %s [DataSource %s]".printf(get_name(), source.to_string());
    }
    
    public DataSource get_source() {
        return source;
    }
    
    public bool is_selected() {
        return selected;
    }
    
    // This method is only called by ViewCollection.
    public void internal_set_selected(bool selected) {
        if (this.selected == selected)
            return;
        
        this.selected = selected;
        state_changed(selected);
    }
    
    // This method is only called by ViewCollection.  Returns the toggled state.
    public bool internal_toggle() {
        selected = !selected;
        state_changed(selected);
        
        return selected;
    }
    
    public bool is_visible() {
        return visible;
    }
    
    // This method is only called by ViewCollection.
    public void internal_set_visible(bool visible) {
        if (this.visible == visible)
            return;
        
        this.visible = visible;
        visibility_changed(visible);
    }

    protected virtual void notify_view_altered() {
        // impossible when not visible
        if (!visible)
            return;
        
        ViewCollection vc = get_membership() as ViewCollection;
        if (vc != null) {
            if (!vc.are_notifications_frozen())
                view_altered();
            
            // notify ViewCollection in any event
            vc.internal_notify_view_altered(this);
        } else {
            view_altered();
        }
    }
    
    protected virtual void notify_geometry_altered() {
        // impossible when not visible
        if (!visible)
            return;
        
        ViewCollection vc = get_membership() as ViewCollection;
        if (vc != null) {
            if (!vc.are_notifications_frozen())
                geometry_altered();
            
            // notify ViewCollection in any event
            vc.internal_notify_geometry_altered(this);
        } else {
            geometry_altered();
        }
    }
    
    // This is only called by DataSource
    public virtual void notify_unsubscribed(DataSource source) {
        unsubscribed(source);
    }
    
    // This is only called by DataSource
    public virtual void notify_source_unlinking(SourceCollection sources) {
        ViewCollection? membership = (ViewCollection?) get_membership();
        if (membership != null)
            membership.internal_notify_unlinking(this, sources);
    }
    
    // This is only called by DataSource
    public virtual void notify_source_relinked(SourceCollection sources) {
        ViewCollection? membership = (ViewCollection?) get_membership();
        if (membership != null)
            membership.internal_notify_relinked(this, sources);
    }
}

public class ThumbnailView : DataView {
    public virtual signal void thumbnail_altered() {
    }
    
    public ThumbnailView(ThumbnailSource source) {
        base(source);
    }
    
    public virtual void notify_thumbnail_altered() {
        // fire signal on self
        thumbnail_altered();
    }
}

public class PhotoView : ThumbnailView {
    public PhotoView(PhotoSource source) {
        base(source);
    }
    
    public PhotoSource get_photo_source() {
        return (PhotoSource) get_source();
    }
}

public class EventView : ThumbnailView {
    public EventView(EventSource source) {
        base(source);
    }
    
    public EventSource get_event_source() {
        return (EventSource) get_source();
    }
}

