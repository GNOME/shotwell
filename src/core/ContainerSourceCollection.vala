/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

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
        Gee.Collection<DataObject> added, bool relinked) {
    }
    
    public virtual signal void container_contents_removed(ContainerSource container, 
        Gee.Collection<DataObject> removed, bool unlinked) {
    }
    
    public virtual signal void container_contents_altered(ContainerSource container, 
        Gee.Collection<DataObject>? added, bool relinked,
        Gee.Collection<DataObject>? removed,
        bool unlinked) {
    }
    
    public virtual signal void backlink_to_container_removed(ContainerSource container,
        Gee.Collection<DataSource> sources) {
    }
    
    protected ContainerSourceCollection(string backlink_name, string name,
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
        Gee.Collection<DataObject> added, bool relinked) {
        // if container is in holding tank, remove it now and relink to collection
        if (holding_tank.contains(container)) {
            bool removed = holding_tank.remove(container);
            assert(removed);
            
            relink(container);
        }
        
        container_contents_added(container, added, relinked);
    }
    
    public virtual void notify_container_contents_removed(ContainerSource container, 
        Gee.Collection<DataObject> removed, bool unlinked) {
        container_contents_removed(container, removed, unlinked);
    }
    
    public virtual void notify_container_contents_altered(ContainerSource container,
        Gee.Collection<DataObject>? added, bool relinked, Gee.Collection<DataSource>? removed,
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
            
            // By design, we no longer discard 'orphan' tags, that is, tags with zero media sources
            // remaining, since empty tags are explicitly allowed to persist as of the 0.12 dev cycle.
            if ((!container.has_links()) && !(container is Tag)) {
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

