/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

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
    
    protected SourceCollection(string name) {
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

