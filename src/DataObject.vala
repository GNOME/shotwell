/* Copyright 2009 Yorba Foundation
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

// TODO: When this bug is fixed, we should remove the inheritance from Object, as it's more
// heavyweight than we require and impedes load-time at startup.
// https://bugzilla.gnome.org/show_bug.cgi?id=611845
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
    
    // This signal is fired when the source of the data is altered in a way that's significant
    // to how it's represented in the application.  This base signal must be called by child
    // classes if the collection it is a member of is to be notified.
    public virtual signal void altered() {
    }
    
    // This signal is fired when some attribute or property of the data is altered, but not its
    // primary representation.  This base signal must be called by child classes if the collection
    // this source is a member of is to be notifed.
    public virtual signal void metadata_altered() {
    }
    
    // This signal is fired when a collection property the DataObject is a member of is set (or
    // changed).
    public virtual signal void collection_property_set(string name, Value? old, Value val) {
    }
    
    // This signal is fired when a collection property the DataObject is a member of is cleared.
    public virtual signal void collection_property_cleared(string name) {
    }
    
    // NOTE: Supplying an object ID should *only* be used when reconstituting the object (generally
    // only done by DataSources).
    public DataObject(int64 object_id = INVALID_OBJECT_ID) {
        this.object_id = (object_id == INVALID_OBJECT_ID) ? object_id_generator++ : object_id;
    }
    
    public virtual void notify_altered() {
        // fire signal on self, if notifications aren't frozen
        if (member_of != null) {
            if (!member_of.are_notifications_frozen())
                altered();
        } else {
            altered();
        }
        
        // notify DataCollection in any event
        if (member_of != null)
            member_of.internal_notify_altered(this);
    }
    
    public virtual void notify_metadata_altered() {
        // fire signal on self, if notifications aren't frozen
        if (member_of != null) {
            if (!member_of.are_notifications_frozen())
                metadata_altered();
        } else {
            metadata_altered();
        }
        
        // notify DataCollection in any event
        if (member_of != null)
            member_of.internal_notify_metadata_altered(this);
    }
    
    // There is no membership_changed signal as it's expensive (esp. at startup) and not needed
    // at this time.  The notify_membership_changed mechanism is still in place for subclasses.
    public virtual void notify_membership_changed(DataCollection? collection) {
    }
    
    // Generally, this is only called by DataCollection.
    public virtual void notify_collection_property_set(string name, Value? old, Value val) {
        collection_property_set(name, old, val);
    }
    
    // Generally, this is only called by DataCollection.
    public virtual void notify_collection_property_cleared(string name) {
        collection_property_cleared(name);
    }
    
    public abstract string get_name();
    
    public abstract string to_string();
    
    public DataCollection? get_membership() {
        return member_of;
    }
    
    public bool has_membership() {
        return member_of != null;
    }
    
    // This method is only called by DataCollection.
    public void internal_set_membership(DataCollection collection, int64 ordinal) {
        assert(member_of == null);
        
        member_of = collection;
        this.ordinal = ordinal;

        notify_membership_changed(member_of);
        
#if TRACE_DTORS
        dbg_to_string = to_string();
#endif
    }
    
    // This method is only called by DataCollection
    public void internal_clear_membership() {
        member_of = null;
        ordinal = DataCollection.INVALID_OBJECT_ORDINAL;

        notify_membership_changed(null);
    }
    
    // This method is only called by DataCollection and DataSet
    public inline int64 internal_get_ordinal() {
        assert(member_of != null);

        return ordinal;
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
    
    public void set_collection_property(string name, Value val) {
        if (member_of != null)
            member_of.set_property(name, val);
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

public abstract class DataSource : DataObject {
    protected delegate void ContactSubscriber(DataView view);
    
    private DataView[] subscribers = null;
    private bool in_contact = false;
    private bool marked_for_destroy = false;
    private bool is_destroyed = false;
    
    // This signal is fired at the end of the destroy() chain.  The object's state is either fragile
    // or unusable.  It is up to all observers to drop their references to the DataObject.
    public virtual signal void destroyed() {
    }
    
    public DataSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        // allocating this here rather than at declaration time due to this bug:
        // https://bugzilla.gnome.org/show_bug.cgi?id=607714
        subscribers = new DataView[4];
    }
    
    ~DataSource() {
#if TRACE_DTORS
        debug("DTOR: DataSource %s", dbg_to_string);
#endif
    }
    
    public override void notify_altered() {
        // signal reflection
        contact_subscribers(subscriber_altered);
        
        base.notify_altered();
    }
    
    private void subscriber_altered(DataView view) {
        view.notify_altered();
    }
    
    public override void notify_metadata_altered() {
        // signal reflection
        contact_subscribers(subscriber_metadata_altered);
        
        base.notify_metadata_altered();
    }

    private void subscriber_metadata_altered(DataView view) {
        view.notify_metadata_altered();
    }
    
    public override void notify_membership_changed(DataCollection? collection) {
        // DataSources can only be removed once they've been destroyed, and may not be re-added
        // likewise
        if (collection == null) {
            assert(is_destroyed);
        } else {
            assert(!is_destroyed);
        }
        
        base.notify_membership_changed(collection);
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
        
        // propagate the signal
        destroyed();
    }

    // DataViews subscribe to the DataSource to inform it of their existance.  Not only does this
    // allow for signal reflection (i.e. DataSource.altered -> DataView.altered) it also makes
    // them first-in-line for notification of destruction, so they can remove themselves from 
    // their ViewCollections automatically.
    //
    // This method is only called by DataView.
    public void internal_subscribe(DataView view) {
        assert(!in_contact);
        
        bool added = false;
        for (int ctr = 0; ctr < subscribers.length; ctr++) {
            if (subscribers[ctr] == null) {
                subscribers[ctr] = view;
                added = true;
                
                break;
            }
        }
        
        if (!added)
            subscribers += view;
    }
    
    // This method is only called by DataView.
    public void internal_unsubscribe(DataView view) {
        assert(!in_contact);
        
        bool removed = false;
        for (int ctr = 0; ctr < subscribers.length; ctr++) {
            if (subscribers[ctr] == view) {
                subscribers[ctr] = null;
                removed = true;
                
                break;
            }
        }
        
        assert(removed);
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
}

public abstract class ThumbnailSource : DataSource {
    public ThumbnailSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    public virtual signal void thumbnail_altered() {
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
}

public abstract class PhotoSource : ThumbnailSource {
    public PhotoSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    public abstract time_t get_exposure_time();

    public abstract Dimensions get_dimensions();

    public abstract uint64 get_filesize();

    public abstract Exif.Data? get_exif();
    
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
        snapshot.broken += on_snapshot_broken;
        
        set_source(source);
        
        membership = (SourceCollection) source.get_membership();
        assert(membership != null);
        membership.items_added += on_source_added;
    }
    
    ~SourceProxy() {
        drop_source();
        membership.items_added -= on_source_added;
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
        source.destroyed += on_destroyed;
    }
    
    private void drop_source() {
        if (source == null)
            return;
        
        source.destroyed -= on_destroyed;
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

