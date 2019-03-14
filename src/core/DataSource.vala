/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

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

public abstract class DataSource : DataObject {
    protected delegate void ContactSubscriber(DataView view);
    protected delegate void ContactSubscriberAlteration(DataView view, Alteration alteration);
    
    private DataView[] subscribers = new DataView[4];
    private SourceHoldingTank holding_tank = null;
    private weak SourceCollection unlinked_from_collection = null;
    private Gee.HashMap<string, Gee.List<string>> backlinks = null;
    private bool in_contact = false;
    private bool marked_for_destroy = false;
    private bool is_destroyed = false;
    
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
    
    protected DataSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    ~DataSource() {
#if TRACE_DTORS
        debug("DTOR: DataSource %s", dbg_to_string);
#endif
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
    
    public virtual void notify_held_in_tank(SourceHoldingTank? holding_tank) {
        // this should never be called if part of a collection
        assert(get_membership() == null);
        
        // DataSources can only be held in a tank if not already in one, and must be removed from
        // one before being put in another
        if (holding_tank != null) {
            assert(this.holding_tank == null);
        } else {
            assert(this.holding_tank != null);
        }
        
        this.holding_tank = holding_tank;
    }
    
    public override void notify_altered(Alteration alteration) {
        // re-route this to the SourceHoldingTank if held in one
        if (holding_tank != null) {
            holding_tank.internal_notify_altered(this, alteration);
        } else {
            contact_subscribers_alteration(alteration);
            
            base.notify_altered(alteration);
        }
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.
    public virtual void notify_unlinking(SourceCollection collection) {
        assert(backlinks == null && unlinked_from_collection == null);
        
        unlinked_from_collection = collection;
        backlinks = new Gee.HashMap<string, Gee.List<string>>();
    }
    
    // This method is called by DataSource.  It should not be called otherwise.
    protected virtual void notify_unlinked() {
        assert(unlinked_from_collection != null && backlinks != null);
        
        unlinked(unlinked_from_collection);
        
        // give the DataSource a chance to persist the link state, if any
        if (backlinks.size > 0)
            commit_backlinks(unlinked_from_collection, dehydrate_backlinks());
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.
    public virtual void notify_relinking(SourceCollection collection) {
        assert((backlinks != null) && (unlinked_from_collection == collection));
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.
    public virtual void notify_relinked() {
        assert(backlinks != null && unlinked_from_collection != null);
        
        SourceCollection relinked_to = unlinked_from_collection;
        backlinks = null;
        unlinked_from_collection = null;
        relinked(relinked_to);
        
        // have the DataSource delete any persisted link state
        commit_backlinks(null, null);
    }
    
    // Each DataSource has a unique typename.  All DataSources of the same type should have the
    // same typename.  This method should be thread-safe.
    //
    // NOTE: Because this value may be persisted in various ways, it should not be changed once
    // defined.
    public abstract string get_typename();
    
    // Each DataSource of a particular typename has an instance ID.  Many DataSources can have a
    // typename of "tag" and many DataSources can have an ID of 42, but only one DataSource may
    // have a typename of "tag" AND an ID of 42.  If the DataSource is persisted, this number should
    // be persisted as well.  This method should be thread-safe.
    public abstract int64 get_instance_id();
    
    // This returns a string that can be used to uniquely identify the DataSource throughout the
    // system.  This method should be thread-safe.
    public virtual string get_source_id() {
        return ("%s-%016" + int64.FORMAT_MODIFIER + "x").printf(get_typename(), get_instance_id());
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
                if (!is_string_empty(value))
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
    // SourceCollection.destroy_marked().  Returns true if the operation completed successfully,
    // otherwise it will return false.
    public bool destroy_orphan(bool delete_backing) {
        bool ret = true;
        if (delete_backing) {
            try {
                ret = internal_delete_backing();
                if (!ret)
                    warning("Unable to delete backing for %s", to_string());
                    
            } catch (Error err) {
                warning("Unable to delete backing for %s: %s", to_string(), err.message);
                ret = false;
            }
        }
        
        internal_mark_for_destroy();
        destroy();
        
        if (unlinked_from_collection != null)
            unlinked_from_collection.notify_unlinked_destroyed(this);
            
        return ret;
    }

    // DataViews subscribe to the DataSource to inform it of their existence.  Not only does this
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
    
    protected void contact_subscribers_alteration(Alteration alteration) {
        assert(!in_contact);
        
        in_contact = true;
        for (int ctr = 0; ctr < subscribers.length; ctr++) {
            if (subscribers[ctr] != null)
                subscribers[ctr].notify_altered(alteration);
        }
        in_contact = false;
    }
}

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
    
    // This only applies if the SourceBacklink comes from a DataSource.
    public string typename {
        get {
            return _name;
        }
    }
    
    // This only applies if the SourceBacklink comes from a DataSource.
    public int64 instance_id {
        get {
            return int64.parse(_value);
        }
    }
    
    public SourceBacklink(string name, string value) {
        assert(validate_name_value(name, value));
        
        _name = name.strip();
        _value = value.strip();
    }
    
    public SourceBacklink.from_source(DataSource source) {
        _name = source.get_typename().strip();
        _value = source.get_instance_id().to_string().strip();
        
        assert(validate_name_value(_name, _value));
    }
    
    private static bool validate_name_value(string name, string value) {
        return !name.contains("=") && !name.contains("|") && !value.contains("|");
    }
    
    public string to_string() {
        return "Backlink %s=%s".printf(name, value);
    }
    
    public static uint hash_func(SourceBacklink? backlink) {        
        return str_hash(backlink._name) ^ str_hash(backlink._value);
    }
    
    public static bool equal_func(SourceBacklink? alink, SourceBacklink? blink) {       
        return str_equal(alink._name, blink._name) && str_equal(alink._value, blink._value);
    }
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
    
    protected SourceProxy(DataSource source) {
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
        if (source != new_source)
            source = new_source;
        if (object_id != source.get_object_id())
            object_id = new_source.get_object_id();
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

public interface Proxyable : Object {
    public abstract SourceProxy get_proxy();
}

