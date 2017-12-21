/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

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
    private unowned CheckToKeep check_to_keep;
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
        if (!tank.contains(source)) {
            debug("SourceHoldingTank.internal_notify_altered called for %s not stored in %s",
                source.to_string(), to_string());
            
            return;
        }
        
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
    
    public string to_string() {
        return "SourceHoldingTank @ 0x%p".printf(this);
    }
}

