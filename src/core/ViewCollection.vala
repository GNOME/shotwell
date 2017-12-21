/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A ViewCollection holds DataView objects, which are view instances wrapping DataSource objects.
// Thus, multiple views can exist of a single SourceCollection, each view displaying all or some
// of that SourceCollection.  A view collection also has a notion of order
// (first/last/next/previous) that can be overridden by child classes.  It also understands hidden
// objects, which are withheld entirely from the collection until they're made visible.  Currently
// the only way to hide objects is with a ViewFilter.
//
// A ViewCollection may also be locked.  When locked, it will not (a) remove hidden items from the
// collection and (b) remove DataViews representing unlinked DataSources.  This allows for the
// ViewCollection to be "frozen" while manipulating items within it.  When the collection is
// unlocked, all changes are applied at once.
//
// The default implementation provides a browser which orders the view in the order they're
// stored in DataCollection, which is not specified.
public class ViewCollection : DataCollection {
    public class Monitor {
    }
    
    private class MonitorImpl : Monitor {
        public ViewCollection owner;
        public SourceCollection sources;
        public ViewManager manager;
        public Alteration? prereq;
        
        public MonitorImpl(ViewCollection owner, SourceCollection sources, ViewManager manager,
            Alteration? prereq) {
            this.owner = owner;
            this.sources = sources;
            this.manager = manager;
            this.prereq = prereq;
            
            sources.items_added.connect(owner.on_sources_added);
            sources.items_removed.connect(owner.on_sources_removed);
            sources.items_altered.connect(owner.on_sources_altered);
        }
        
        ~MonitorImpl() {
            sources.items_added.disconnect(owner.on_sources_added);
            sources.items_removed.disconnect(owner.on_sources_removed);
            sources.items_altered.disconnect(owner.on_sources_altered);
        }
    }
    
    private class ToggleLists : Object {
        public Gee.ArrayList<DataView> selected = new Gee.ArrayList<DataView>();
        public Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();
    }
    
#if MEASURE_VIEW_FILTERING
    private static OpTimer filter_timer = new OpTimer("ViewCollection filter timer");
#endif
    
    private Gee.HashMultiMap<SourceCollection, MonitorImpl> monitors = new Gee.HashMultiMap<
        SourceCollection, MonitorImpl>();
    private ViewCollection mirroring = null;
    private unowned CreateView mirroring_ctor = null;
    private unowned CreateViewPredicate should_mirror = null;
    private Gee.Set<ViewFilter> filters = new Gee.HashSet<ViewFilter>();
    private DataSet selected = new DataSet();
    private DataSet visible = null;
    private Gee.HashSet<DataView> frozen_views_altered = null;
    private Gee.HashSet<DataView> frozen_geometries_altered = null;
    
    // TODO: source-to-view mapping ... for now, only one view is allowed for each source.
    // This may need to change in the future.
    private Gee.HashMap<DataSource, DataView> source_map = new Gee.HashMap<DataSource, DataView>();
    
    // Signal aggregator.
    public virtual signal void items_selected(Gee.Iterable<DataView> selected) {
    }
    
    // Signal aggregator.
    public virtual signal void items_unselected(Gee.Iterable<DataView> unselected) {
    }
    
    // Signal aggregator.
    public virtual signal void items_state_changed(Gee.Iterable<DataView> changed) {
    }
    
    // This signal is fired when the selection in the view has changed in any capacity.  Items
    // are not reported individually because they may have been removed (and are not reported as
    // unselected).  In other words, although individual DataViews' selection status may not have
    // changed, what characterizes the total selection of the ViewCollection has changed.
    public virtual signal void selection_group_altered() {
    }
    
    // Signal aggregator.
    public virtual signal void items_shown(Gee.Collection<DataView> visible) {
    }
    
    // Signal aggregator.
    public virtual signal void items_hidden(Gee.Collection<DataView> hidden) {
    }
    
    // Signal aggregator.
    public virtual signal void items_visibility_changed(Gee.Collection<DataView> changed) {
    }
    
    // Signal aggregator.
    public virtual signal void item_view_altered(DataView view) {
    }
    
    // Signal aggregator.
    public virtual signal void item_geometry_altered(DataView view) {
    }
    
    public virtual signal void views_altered(Gee.Collection<DataView> views) {
    }
    
    public virtual signal void geometries_altered(Gee.Collection<DataView> views) {
    }
    
    public virtual signal void view_filter_installed(ViewFilter filer) {
    }
    
    public virtual signal void view_filter_removed(ViewFilter filer) {
    }
    
    public ViewCollection(string name) {
        base (name);
    }
    
    protected virtual void notify_items_selected_unselected(Gee.Collection<DataView>? selected,
        Gee.Collection<DataView>? unselected) {
        bool has_selected = (selected != null) && (selected.size > 0);
        bool has_unselected = (unselected != null) && (unselected.size > 0);
        
        if (has_selected)
            items_selected(selected);
        
        if (has_unselected)
            items_unselected(unselected);
        
        Gee.Collection<DataView>? sum;
        if (has_selected && !has_unselected) {
            sum = selected;
        } else if (!has_selected && has_unselected) {
            sum = unselected;
        } else if (!has_selected && !has_unselected) {
            sum = null;
        } else {
            sum = new Gee.HashSet<DataView>();
            sum.add_all(selected);
            sum.add_all(unselected);
        }
        
        if (sum != null) {
            items_state_changed(sum);
            notify_selection_group_altered();
        }
    }
    
    protected virtual void notify_selection_group_altered() {
        selection_group_altered();
    }
    
    protected virtual void notify_item_view_altered(DataView view) {
        item_view_altered(view);
    }
    
    protected virtual void notify_views_altered(Gee.Collection<DataView> views) {
        views_altered(views);
    }
    
    protected virtual void notify_item_geometry_altered(DataView view) {
        item_geometry_altered(view);
    }
    
    protected virtual void notify_geometries_altered(Gee.Collection<DataView> views) {
        geometries_altered(views);
    }
    
    protected virtual void notify_items_shown(Gee.Collection<DataView> shown) {
        items_shown(shown);
    }
    
    protected virtual void notify_items_hidden(Gee.Collection<DataView> hidden) {
        items_hidden(hidden);
    }
    
    protected virtual void notify_items_visibility_changed(Gee.Collection<DataView> changed) {
        items_visibility_changed(changed);
    }
    
    protected virtual void notify_view_filter_installed(ViewFilter filter) {
        view_filter_installed(filter);
    }
    
    protected virtual void notify_view_filter_removed(ViewFilter filter) {
        view_filter_removed(filter);
    }
    
    public override void clear() {
        // cannot clear a ViewCollection if it is monitoring a SourceCollection or mirroring a
        // ViewCollection
        if (monitors.size > 0 || mirroring != null) {
            warning("Cannot clear %s: monitoring or mirroring in effect", to_string());
            
            return;
        }
        
        base.clear();
    }
    
    public override void close() {
        halt_all_monitoring();
        halt_mirroring();
        foreach (ViewFilter f in filters)
            f.refresh.disconnect(on_view_filter_refresh);
        filters.clear();
        
        base.close();
    }
    
    public Monitor monitor_source_collection(SourceCollection sources, ViewManager manager,
        Alteration? prereq, Gee.Collection<DataSource>? initial = null,
        ProgressMonitor? progress_monitor = null) {
        // cannot use source monitoring and mirroring at the same time
        halt_mirroring();
        
        freeze_notifications();
        
        // create a monitor, which will hook up all the signals and filter from there
        MonitorImpl monitor = new MonitorImpl(this, sources, manager, prereq);
        monitors.set(sources, monitor);
        
        if (initial != null && initial.size > 0) {
            // add from the initial list handed to us, using the ViewManager to add/remove later
            Gee.ArrayList<DataView> created_views = new Gee.ArrayList<DataView>();
            foreach (DataSource source in initial)
                created_views.add(manager.create_view(source));
            
            add_many(created_views, progress_monitor);
        } else {
            // load in all items from the SourceCollection, filtering with the manager
            add_sources(sources, (Gee.Iterable<DataSource>) sources.get_all(), progress_monitor);
        }
        
        thaw_notifications();
        
        return monitor;
    }
    
    public void halt_monitoring(Monitor m) {
        MonitorImpl monitor = (MonitorImpl) m;
        
        bool removed = monitors.remove(monitor.sources, monitor);
        assert(removed);
    }
    
    public void halt_all_monitoring() {
        monitors.clear();
    }
    
    public void mirror(ViewCollection to_mirror, CreateView mirroring_ctor,
        CreateViewPredicate? should_mirror) {
        halt_mirroring();
        halt_all_monitoring();
        clear();
        
        mirroring = to_mirror;
        this.mirroring_ctor = mirroring_ctor;
        this.should_mirror = should_mirror;
        set_comparator(to_mirror.get_comparator(), to_mirror.get_comparator_predicate());
        
        // load up with current items
        on_mirror_contents_added(mirroring.get_all());
        
        mirroring.items_added.connect(on_mirror_contents_added);
        mirroring.items_removed.connect(on_mirror_contents_removed);
    }
    
    public void halt_mirroring() {
        if (mirroring != null) {
            mirroring.items_added.disconnect(on_mirror_contents_added);
            mirroring.items_removed.disconnect(on_mirror_contents_removed);
        }
        
        mirroring = null;
    }
    
    public void copy_into(ViewCollection to_copy, CreateView copying_ctor, 
        CreateViewPredicate should_copy) {
        // Copy into self.
        Gee.ArrayList<DataObject> copy_view = new Gee.ArrayList<DataObject>();
        foreach (DataObject object in to_copy.get_all()) {
            DataView view = (DataView) object;
            if (should_copy(view.get_source())) {
                copy_view.add(copying_ctor(view.get_source()));
            }
        }
        add_many(copy_view);
    }
    
    public bool is_view_filter_installed(ViewFilter f) {
        return filters.contains(f);
    }
    
    public void install_view_filter(ViewFilter f) {
        if (is_view_filter_installed(f))
            return;
        
        filters.add(f);
        f.refresh.connect(on_view_filter_refresh);
        
        // filter existing items
        on_view_filter_refresh();
        
        // notify of change after activating filter
        notify_view_filter_installed(f);
    }
    
    public void remove_view_filter(ViewFilter f) {
        if (!is_view_filter_installed(f))
            return;
        
        filters.remove(f);
        f.refresh.disconnect(on_view_filter_refresh);
        
        // filter existing items
        on_view_filter_refresh();
        
        // notify of change after activating filter
        notify_view_filter_removed(f);
    }
    
    private void on_view_filter_refresh() {
        filter_altered_items((Gee.Collection<DataView>) base.get_all());
    }
    
    // Runs predicate on all filters, returns ANDed result.
    private bool is_in_filter(DataView view) {
        foreach (ViewFilter f in filters) {
            if (!f.predicate(view))
                return false;
        }
        return true;
    }
    
    public override bool valid_type(DataObject object) {
        return object is DataView;
    }
    
    private void on_sources_added(DataCollection sources, Gee.Iterable<DataSource> added) {
        add_sources((SourceCollection) sources, added);
    }
    
    private void add_sources(SourceCollection sources, Gee.Iterable<DataSource> added,
        ProgressMonitor? progress_monitor = null) {
        // add only source items which are to be included by the manager ... do this in batches
        // to take advantage of add_many()
        DataView created_view = null;
        Gee.ArrayList<DataView> created_views = null;
        foreach (DataSource source in added) {
            CreateView factory = null;
            foreach (MonitorImpl monitor in monitors.get(sources)) {
                if (monitor.manager.include_in_view(source)) {
                    factory = monitor.manager.create_view;
                    
                    break;
                }
            }
            
            if (factory != null) {
                DataView new_view = factory(source);
                
                // this bit of code is designed to avoid creating the ArrayList if only one item
                // is being added to the ViewCollection
                if (created_views != null) {
                    created_views.add(new_view);
                } else if (created_view == null) {
                    created_view = new_view;
                } else {
                    created_views = new Gee.ArrayList<DataView>();
                    created_views.add(created_view);
                    created_view = null;
                    created_views.add(new_view);
                }
            }
        }
        
        if (created_view != null)
            add(created_view);
        else if (created_views != null && created_views.size > 0)
            add_many(created_views, progress_monitor);
    }

    public override bool add(DataObject object) {
        ((DataView) object).internal_set_visible(true);
        
        if (!base.add(object))
            return false;
        
        filter_altered_items((Gee.Collection<DataView>) get_singleton(object));
        
        return true;
    }

    public override Gee.Collection<DataObject> add_many(Gee.Collection<DataObject> objects, 
        ProgressMonitor? monitor = null) {
        foreach (DataObject object in objects)
            ((DataView) object).internal_set_visible(true);
        
        Gee.Collection<DataObject> return_list = base.add_many(objects, monitor);
        
        filter_altered_items((Gee.Collection<DataView>) return_list);
        
        return return_list;
    }
    
    private void on_sources_removed(Gee.Iterable<DataSource> removed) {
        // mark all view items associated with the source to be removed
        Marker marker = null;
        foreach (DataSource source in removed) {
            DataView view = source_map.get(source);
            
            // ignore if not represented in this view
            if (view != null) {
                if (marker == null)
                    marker = start_marking();
                
                marker.mark(view);
            }
        }
        
        if (marker != null && marker.get_count() != 0)
            remove_marked(marker);
    }
    
    private void on_sources_altered(DataCollection collection, Gee.Map<DataObject, Alteration> items) {
        // let ViewManager decide whether or not to keep, but only add if not already present
        // and only remove if already present
        Gee.ArrayList<DataView> to_add = null;
        Gee.ArrayList<DataView> to_remove = null;
        bool ordering_changed = false;
        foreach (DataObject object in items.keys) {
            Alteration alteration = items.get(object);
            DataSource source = (DataSource) object;
            
            MonitorImpl? monitor = null;
            bool ignored = true;
            foreach (MonitorImpl monitor_impl in monitors.get((SourceCollection) collection)) {
                if (monitor_impl.prereq != null && !alteration.contains_any(monitor_impl.prereq))
                    continue;
                
                ignored = false;
                
                if (monitor_impl.manager.include_in_view(source)) {
                    monitor = monitor_impl;
                    
                    break;
                }
            }
            
            if (ignored) {
                assert(monitor == null);
                
                continue;
            }
            
            if (monitor != null && !has_view_for_source(source)) {
                if (to_add == null)
                    to_add = new Gee.ArrayList<DataView>();
                
                to_add.add(monitor.manager.create_view(source));
            } else if (monitor == null && has_view_for_source(source)) {
                if (to_remove == null)
                    to_remove = new Gee.ArrayList<DataView>();
                
                to_remove.add(get_view_for_source(source));
            } else if (monitor != null && has_view_for_source(source)) {
                DataView view = get_view_for_source(source);
                
                if (selected.contains(view))
                    selected.resort_object(view, alteration);
                
                if (visible != null && is_visible(view)) {
                    if (visible.resort_object(view, alteration))
                        ordering_changed = true;
                }
            }
        }
        
        if (to_add != null)
            add_many(to_add);
        
        if (to_remove != null)
            remove_marked(mark_many(to_remove));
        
        if (ordering_changed)
            notify_ordering_changed();
    }
    
    private void on_mirror_contents_added(Gee.Iterable<DataObject> added) {
        Gee.ArrayList<DataView> to_add = new Gee.ArrayList<DataView>();
        foreach (DataObject object in added) {
            DataSource source = ((DataView) object).get_source();
            
            if (should_mirror == null || should_mirror(source))
                to_add.add(mirroring_ctor(source));
        }
        
        if (to_add.size > 0)
            add_many(to_add);
    }
    
    private void on_mirror_contents_removed(Gee.Iterable<DataObject> removed) {
        Marker marker = start_marking();
        foreach (DataObject object in removed) {
            DataView view = (DataView) object;
            
            DataView? our_view = get_view_for_source(view.get_source());
            assert(our_view != null);
            
            marker.mark(our_view);
        }
        
        remove_marked(marker);
    }
    
    // Keep the source map and state tables synchronized
    protected override void notify_items_added(Gee.Iterable<DataObject> added) {
        Gee.ArrayList<DataView> added_visible = null;
        Gee.ArrayList<DataView> added_selected = null;
        
        foreach (DataObject object in added) {
            DataView view = (DataView) object;
            source_map.set(view.get_source(), view);
            
            if (view.is_selected() && view.is_visible()) {
                if (added_selected == null)
                    added_selected = new Gee.ArrayList<DataView>();
                
                added_selected.add(view);
            }
            
            // add to visible list only if there is one
            if (view.is_visible() && visible != null) {
                if (added_visible == null)
                    added_visible = new Gee.ArrayList<DataView>();
                
                added_visible.add(view);
            }
        }
        
        if (added_visible != null) {
            bool is_added = add_many_visible(added_visible);
            assert(is_added);
        }
        
        if (added_selected != null) {
            add_many_selected(added_selected);
            notify_items_selected_unselected(added_selected, null);
        }
        
        base.notify_items_added(added);
    }
    
    // Keep the source map and state tables synchronized
    protected override void notify_items_removed(Gee.Iterable<DataObject> removed) {
        Gee.ArrayList<DataView>? selected_removed = null;
        foreach (DataObject object in removed) {
            DataView view = (DataView) object;

            // It's possible for execution to get here in direct mode with the source
            // in question already having been removed from the source map, but the
            // double removal is unimportant to direct mode, so if this happens, the
            // remove is skipped the second time (to prevent crashing).
            if (source_map.has_key(view.get_source())) {
                bool is_removed = source_map.unset(view.get_source());
                assert(is_removed);

                if (view.is_selected()) {
                    // hidden items may be selected, but they won't be in the selected pool
                    assert(selected.contains(view) == view.is_visible());

                    if (view.is_visible()) {
                        if (selected_removed == null)
                            selected_removed = new Gee.ArrayList<DataView>();

                        selected_removed.add(view);
                    }
                }

                if (view.is_visible() && visible != null) {
                    is_removed = visible.remove(view);
                    assert(is_removed);
                }
            }
        }

        if (selected_removed != null) {
            remove_many_selected(selected_removed);

            // If a selected item was removed, only fire the selected_removed signal, as the total
            // selection character of the ViewCollection has changed, but not the individual items'
            // state.
            notify_selection_group_altered();
        }

        base.notify_items_removed(removed);
    }
    
    private void filter_altered_items(Gee.Collection<DataView> views) {
        // Can't use the marker system because ViewCollection completely overrides DataCollection
        // and hidden items cannot be marked.
        Gee.ArrayList<DataView> to_show = null;
        Gee.ArrayList<DataView> to_hide = null;
        
#if MEASURE_VIEW_FILTERING
        filter_timer.start();
#endif
        foreach (DataView view in views) {
            if (is_in_filter(view)) {
                if (!view.is_visible()) {
                    if (to_show == null)
                        to_show = new Gee.ArrayList<DataView>();
                    
                    to_show.add(view);
                }
            } else {
                if (view.is_visible()) {
                    if (to_hide == null)
                        to_hide = new Gee.ArrayList<DataView>();
                    
                    to_hide.add(view);
                }
            }
        }
#if MEASURE_VIEW_FILTERING
        filter_timer.stop();
        debug("Filtering for %s: %s", to_string(), filter_timer.to_string());
#endif
        
        if (to_show != null)
            show_items(to_show);
        
        if (to_hide != null)
            hide_items(to_hide);
    }
    
    public override void items_altered(Gee.Map<DataObject, Alteration> map) {
        // Cast - our DataObjects are DataViews.
        filter_altered_items((Gee.Collection<DataView>)map.keys);

        base.items_altered(map);
    }
    
    public override void set_comparator(Comparator comparator, ComparatorPredicate? predicate) {
        selected.set_comparator(comparator, predicate);
        if (visible != null)
            visible.set_comparator(comparator, predicate);
        
        base.set_comparator(comparator, predicate);
    }
    
    public override void reset_comparator() {
        selected.reset_comparator();
        if (visible != null)
            visible.reset_comparator();
        
        base.reset_comparator();
    }
    
    public override Gee.Collection<DataObject> get_all() {
        return (visible != null) ? visible.get_all() : base.get_all();
    }
    
    public Gee.Collection<DataObject> get_all_unfiltered() {
        return base.get_all();
    }    

    public override int get_count() {
        return (visible != null) ? visible.get_count() : base.get_count();
    }
    
    public int get_unfiltered_count() {
        return base.get_count();
    }
    
    public override DataObject? get_at(int index) {
        return (visible != null) ? visible.get_at(index) : base.get_at(index);
    }
    
    public override int index_of(DataObject object) {
        return (visible != null) ? visible.index_of(object) : base.index_of(object);
    }
    
    public override bool contains(DataObject object) {
        // use base method first, which can quickly ascertain if the object is *not* a member of
        // this collection
        if (!base.contains(object))
            return false;
        
        // even if a member, must be visible to be "contained"
        return is_visible((DataView) object);
    }
    
    public virtual DataView? get_first() {
        return (get_count() > 0) ? (DataView?) get_at(0) : null;
    }

    /**
     * @brief A helper method for places in the app that need a
     *  non-rejected media source (namely Events, when looking to
     *  automatically choose a thumbnail).
     *
     * @note If every view in this collection is rejected, we
     *  return the first view; this is intentional.  This prevents
     *  pathological events that have nothing but rejected images
     *  in them from breaking.
     */
    public virtual DataView? get_first_unrejected() {
        // We have no media, unrejected or otherwise...
        if (get_count() < 1)
            return null;

        // Loop through media we do have...
        DataView dv = get_first();
        int num_views = get_count();

        while ((dv != null) && (index_of(dv) < (num_views - 1))) {
            MediaSource tmp = dv.get_source() as MediaSource;

            if ((tmp != null) && (tmp.get_rating() != Rating.REJECTED)) {
                // ...found a good one; return it.
                return dv;
            } else {
                dv = get_next(dv);
            }
        }

        // Got to the end of the collection, none found, need to return
        // _something_...
        return get_first();
    }

    public virtual DataView? get_last() {
        return (get_count() > 0) ? (DataView?) get_at(get_count() - 1) : null;
    }
    
    public virtual DataView? get_next(DataView view) {
        if (get_count() == 0)
            return null;
        
        int index = index_of(view);
        if (index < 0)
            return null;
        
        index++;
        if (index >= get_count())
            index = 0;
        
        return (DataView?) get_at(index);
    }
    
    public virtual DataView? get_previous(DataView view) {
        if (get_count() == 0)
            return null;
        
        int index = index_of(view);
        if (index < 0)
            return null;
        
        index--;
        if (index < 0)
            index = get_count() - 1;
        
        return (DataView?) get_at(index);
    }
    
    public bool get_immediate_neighbors(DataSource home, out DataSource? next,
        out DataSource? prev, string? type_selector = null) {
        next = null;
        prev = null;
        
        DataView home_view = get_view_for_source(home);
        if (home_view == null)
            return false;
        
        DataView? next_view = get_next(home_view);
        while (next_view != home_view) {
            if ((type_selector == null) || (next_view.get_source().get_typename() == type_selector)) {
                next = next_view.get_source();
                break;
            }
            next_view = get_next(next_view);
        }
        
        DataView? prev_view = get_previous(home_view);
        while (prev_view != home_view) {
            if ((type_selector == null) || (prev_view.get_source().get_typename() == type_selector)) {
                prev = prev_view.get_source();
                break;
            }
            prev_view = get_previous(prev_view);
        }
        
        return true;
    }
    
    // "Extended" as in immediate neighbors and their neighbors
    public Gee.Set<DataSource> get_extended_neighbors(DataSource home, string? typename = null) {
        // build set of neighbors
        Gee.Set<DataSource> neighbors = new Gee.HashSet<DataSource>();
        
        // immediate neighbors
        DataSource next, prev;
        if (!get_immediate_neighbors(home, out next, out prev, typename))
            return neighbors;
        
        // add next and its distant neighbor
        if (next != null) {
            neighbors.add(next);
            
            DataSource next_next, next_prev;
            get_immediate_neighbors(next, out next_next, out next_prev, typename);
            
            // only add next-next because next-prev is home
            if (next_next != null)
                neighbors.add(next_next);
        }
        
        // add previous and its distant neighbor
        if (prev != null) {
            neighbors.add(prev);
            
            DataSource next_prev, prev_prev;
            get_immediate_neighbors(prev, out next_prev, out prev_prev, typename);
            
            // only add prev-prev because next-prev is home
            if (prev_prev != null)
                neighbors.add(prev_prev);
        }
        
        // finally, in a small collection a neighbor could be home itself, so exclude it
        neighbors.remove(home);
        
        return neighbors;
    }
    
    // Do NOT add hidden items to the selection collection, mark them as selected and they will be
    // added when/if they are made visible.
    private void add_many_selected(Gee.Collection<DataView> views) {
        if (views.size == 0)
            return;
        
        foreach (DataView view in views)
            assert(view.is_visible());
        
        bool added = selected.add_many(views);
        assert(added);
    }
    
    private void remove_many_selected(Gee.Collection<DataView> views) {
        if (views.size == 0)
            return;
        
        bool removed = selected.remove_many(views);
        assert(removed);
    }
    
    // Selects all the marked items.  The marker will be invalid after this call.
    public void select_marked(Marker marker) {
        Gee.ArrayList<DataView> selected = new Gee.ArrayList<DataView>();
        act_on_marked(marker, select_item, null, selected);
        
        if (selected.size > 0) {
            add_many_selected(selected);
            notify_items_selected_unselected(selected, null);
        }
    }
    
    // Selects all items.
    public void select_all() {
        Marker marker = start_marking();
        marker.mark_all();
        select_marked(marker);
    }
    
    private bool select_item(DataObject object, Object? user) {
        DataView view = (DataView) object;
        if (view.is_selected()) {
            if (view.is_visible())
                assert(selected.contains(view));
            
            return true;
        }
        
        view.internal_set_selected(true);
        
        // Do NOT add hidden items to the selection collection, merely mark them as selected
        // and they will be re-added when/if they are made visible
        if (view.is_visible())
            ((Gee.ArrayList<DataView>) user).add(view);
        
        return true;
    }
    
    // Unselects all the marked items.  The marker will be invalid after this call.
    public void unselect_marked(Marker marker) {
        Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();
        act_on_marked(marker, unselect_item, null, unselected);
        
        if (unselected.size > 0) {
            remove_many_selected(unselected);
            notify_items_selected_unselected(null, unselected);
        }
    }
    
    // Unselects all items.
    public void unselect_all() {
        if (selected.get_count() == 0)
            return;
        
        Marker marker = start_marking();
        marker.mark_many(get_selected());

        unselect_marked(marker);
    }
    
    // Unselects all items but the one specified.
    public void unselect_all_but(DataView exception) {
        Marker marker = start_marking();
        foreach (DataObject object in get_all()) {
            DataView view = (DataView) object;
            if (view != exception)
                marker.mark(view);
        }
        
        unselect_marked(marker);
    }
    
    private bool unselect_item(DataObject object, Object? user) {
        DataView view = (DataView) object;
        if (!view.is_selected()) {
            assert(!selected.contains(view));
            
            return true;
        }
        
        view.internal_set_selected(false);
        ((Gee.ArrayList<DataView>) user).add(view);
        
        return true;
    }
    
    // Performs the operations in that order: unselects the marked then selects the marked
    public void unselect_and_select_marked(Marker unselect, Marker select) {
        Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();
        act_on_marked(unselect, unselect_item, null, unselected);
        
        remove_many_selected(unselected);
        
        Gee.ArrayList<DataView> selected = new Gee.ArrayList<DataView>();
        act_on_marked(select, select_item, null, selected);
        
        add_many_selected(selected);
        
        notify_items_selected_unselected(selected, unselected);
    }
    
    // Toggle the selection state of all marked items.  The marker will be invalid after this
    // call.
    public void toggle_marked(Marker marker) {
        ToggleLists lists = new ToggleLists();
        act_on_marked(marker, toggle_item, null, lists);
        
        // add and remove selected before firing the signals
        add_many_selected(lists.selected);
        remove_many_selected(lists.unselected);
        
        notify_items_selected_unselected(lists.selected, lists.unselected);
    }
    
    private bool toggle_item(DataObject object, Object? user) {
        DataView view = (DataView) object;
        ToggleLists lists = (ToggleLists) user;
        
        // toggle the selection state of the view, adding or removing it from the selected list
        // to maintain state and adding it to the ToggleLists for the caller to signal with
        //
        // See add_many_selected for rules on not adding hidden items to the selection pool
        if (view.internal_toggle()) {
            if (view.is_visible())
                lists.selected.add(view);
        } else {
            lists.unselected.add(view);
        }
        
        return true;
    }
    
    public int get_selected_count() {
        return selected.get_count();
    }
    
    public Gee.List<DataView> get_selected() {
        return (Gee.List<DataView>) selected.get_all();
    }
    
    public DataView? get_selected_at(int index) {
        return (DataView?) selected.get_at(index);
    }
    
    private bool is_visible(DataView view) {
        return (visible != null) ? visible.contains(view) : true;
    }

    private bool add_many_visible(Gee.Collection<DataView> many) {
        if (visible == null)
            return true;
        
        if (!visible.add_many(many))
            return false;
        
        // if all are visible, then revert to using base class's set
        if (visible.get_count() == base.get_count())
            visible = null;
        
        return true;
    }
    
    // This method requires that all items in to_hide are not hidden already.
    private void hide_items(Gee.List<DataView> to_hide) {
        Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();

        int count = to_hide.size;
        for (int ctr = 0; ctr < count; ctr++) {
            DataView view = to_hide.get(ctr);
            assert(view.is_visible());
            
            if (view.is_selected()) {
                view.internal_set_selected(false);
                unselected.add(view);
            } else {
                assert(!selected.contains(view));
            }
            
            view.internal_set_visible(false);
        }
        
        if (visible == null) {
            // make a copy of the full set before removing items
            visible = get_dataset_copy();
        }
        
        bool removed = visible.remove_many(to_hide);
        assert(removed);
        
        remove_many_selected(unselected);
        
        if (unselected.size > 0)
            notify_items_selected_unselected(null, unselected);
        
        if (to_hide.size > 0) {
            notify_items_hidden(to_hide);
            notify_items_visibility_changed(to_hide);
        }
    }
    
    // This method requires that all items in to_show are hidden already.
    private void show_items(Gee.List<DataView> to_show) {
        Gee.ArrayList<DataView> added_selected = new Gee.ArrayList<DataView>();
        
        int count = to_show.size;
        for (int ctr = 0; ctr < count; ctr++) {
            DataView view = to_show.get(ctr);
            assert(!view.is_visible());
            
            view.internal_set_visible(true);
            
            // See note in add_selected for selection handling with hidden/visible items
            if (view.is_selected()) {
                assert(!selected.contains(view));
                added_selected.add(view);
            }
        }
        
        bool added = add_many_visible(to_show);
        assert(added);
        
        add_many_selected(added_selected);
        
        if (to_show.size > 0) {
            notify_items_shown(to_show);
            notify_items_visibility_changed(to_show);
        }
    }
    
    // This currently does not respect filtering.
    public bool has_view_for_source(DataSource source) {
        return get_view_for_source(source) != null;
    }
    
    // This currently does not respect filtering.
    public DataView? get_view_for_source(DataSource source) {
        return source_map.get(source);
    }
     
     // Respects filtering.
    public bool has_view_for_source_with_filtered(DataSource source) {
        return get_view_for_source_filtered(source) != null;
    }
    
    // Respects filtering.
    public DataView? get_view_for_source_filtered(DataSource source) {
        DataView? view = source_map.get(source);
        // Consult with filter to make sure DataView is visible.
        if (view != null && !is_in_filter(view))
            return null;
        return view;
    }
     
    // TODO: This currently does not respect filtering.
    public Gee.Collection<DataSource> get_sources() {
        return source_map.keys.read_only_view;
    }
    
    // TODO: This currently does not respect filtering.
    public bool has_source_of_type(Type t) {
        assert(t.is_a(typeof(DataSource)));
        
        foreach (DataSource source in source_map.keys) {
            if (source.get_type().is_a(t))
                return true;
        }
        
        return false;
    }
    
    public int get_sources_of_type_count(Type t) {
        assert(t.is_a(typeof(DataSource)));
        
        int count = 0;
        foreach (DataObject object in get_all()) {
            if (((DataView) object).get_source().get_type().is_a(t))
                count++;
        }
        
        return count;
    }
    
    public Gee.List<DataSource>? get_sources_of_type(Type t) {
        assert(t.is_a(typeof(DataSource)));
        
        Gee.List<DataSource>? sources = null;
        foreach (DataObject object in get_all()) {
            DataSource source = ((DataView) object).get_source();
            if (source.get_type().is_a(t)) {
                if (sources == null)
                    sources = new Gee.ArrayList<DataSource>();
                
                sources.add(source);
            }
        }
        
        return sources;
    }
    
    public Gee.List<DataSource> get_selected_sources() {
        Gee.List<DataSource> sources = new Gee.ArrayList<DataSource>();
        
        int count = selected.get_count();
        for (int ctr = 0; ctr < count; ctr++)
            sources.add(((DataView) selected.get_at(ctr)).get_source());
        
        return sources;
    }
    
    public DataSource? get_selected_source_at(int index) {
        DataObject? object = selected.get_at(index);
        
        return (object != null) ? ((DataView) object).get_source() : null;
    }
    
    public Gee.List<DataSource>? get_selected_sources_of_type(Type t) {
        Gee.List<DataSource>? sources = null;
        foreach (DataView view in get_selected()) {
            DataSource source = view.get_source();
            if (source.get_type().is_a(t)) {
                if (sources == null)
                    sources = new Gee.ArrayList<DataSource>();
                
                sources.add(source);
            }
        }
        
        return sources;
    }
    
    // Returns -1 if source is not in the ViewCollection.
    public int index_of_source(DataSource source) {
        DataView? view = get_view_for_source(source);
        
        return (view != null) ? index_of(view) : -1;
    }
    
    // This is only used by DataView.
    public void internal_notify_view_altered(DataView view) {
        if (!are_notifications_frozen()) {
            notify_item_view_altered(view);
            notify_views_altered((Gee.Collection<DataView>) get_singleton(view));
        } else {
            if (frozen_views_altered == null)
                frozen_views_altered = new Gee.HashSet<DataView>();
            frozen_views_altered.add(view);
        }
    }
    
    // This is only used by DataView.
    public void internal_notify_geometry_altered(DataView view) {
        if (!are_notifications_frozen()) {
            notify_item_geometry_altered(view);
            notify_geometries_altered((Gee.Collection<DataView>) get_singleton(view));
        } else {
            if (frozen_geometries_altered == null)
                frozen_geometries_altered = new Gee.HashSet<DataView>();
            frozen_geometries_altered.add(view);
        }
    }
    
    protected override void notify_thawed() {
        if (frozen_views_altered != null) {
            foreach (DataView view in frozen_views_altered)
                notify_item_view_altered(view);
            notify_views_altered(frozen_views_altered);
            frozen_views_altered = null;
        }
        
        if (frozen_geometries_altered != null) {
            foreach (DataView view in frozen_geometries_altered)
                notify_item_geometry_altered(view);
            notify_geometries_altered(frozen_geometries_altered);
            frozen_geometries_altered = null;
        }
        
        base.notify_thawed();
    }
    
    public bool are_items_filtered_out() {
        return base.get_count() != get_count();
    }
}

// A ViewManager allows an interface for ViewCollection to monitor a SourceCollection and
// (selectively) add DataViews automatically.
public abstract class ViewManager {
    // This predicate function can be used to filter which DataView objects should be included
    // in the collection as new source objects appear in the SourceCollection.  May be called more
    // than once for any DataSource object.
    public virtual bool include_in_view(DataSource source) {
        return true;
    }
    
    // If include_in_view returns true, this method will be called to instantiate a DataView object
    // for the ViewCollection.
    public abstract DataView create_view(DataSource source);
}

// CreateView is a construction delegate used when mirroring or copying a ViewCollection 
// in another ViewCollection.
public delegate DataView CreateView(DataSource source);

// CreateViewPredicate is a filter delegate used when copy a ViewCollection in another
// ViewCollection.
public delegate bool CreateViewPredicate(DataSource source);

// A ViewFilter allows for items in a ViewCollection to be shown or hidden depending on the
// supplied predicate method.  For now, only one ViewFilter may be installed, although this may
// change in the future.  The ViewFilter is used whenever an object is added to the collection
// and when its altered/metadata_altered signals fire.
public abstract class ViewFilter {
    // Fire this signal whenever a refresh is needed.  The ViewCollection listens
    // to this signal to know when to reapply the filter.
    public virtual signal void refresh() {
    }
    
    // Return true if view should be visible, false if it should be hidden.
    public abstract bool predicate(DataView view);
}

