/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class EventSourceCollection : ContainerSourceCollection {
    public signal void no_event_collection_altered();
    
    private ViewCollection no_event;
    
    private class NoEventViewManager : ViewManager {
        public override bool include_in_view(DataSource source) {
            // Note: this is not threadsafe
            return (((LibraryPhoto) source).get_event_id().id != EventID.INVALID) ? false :
                base.include_in_view(source);
        }
    
        public override DataView create_view(DataSource source) {
            return new PhotoView((PhotoSource) source);
        }
    }
    
    public EventSourceCollection() {
        base(LibraryPhoto.global, Event.TYPENAME, "EventSourceCollection", get_event_key);
    }

    public void init() {
        no_event = new ViewCollection("No Event View Collection");
        
        no_event.monitor_source_collection(LibraryPhoto.global, new NoEventViewManager(),
            new Alteration("metadata", "event"));
        
        no_event.contents_altered.connect(on_no_event_collection_altered);
    }
    
    private static int64 get_event_key(DataSource source) {
        Event event = (Event) source;
        EventID event_id = event.get_event_id();
        
        return event_id.id;
    }
    
    public Event? fetch(EventID event_id) {
        return (Event) fetch_by_key(event_id.id);
    }
    
    protected override Gee.Collection<ContainerSource>? get_containers_holding_source(DataSource source) {
        Event? event = ((LibraryPhoto) source).get_event();
        if (event == null)
            return null;
        
        Gee.ArrayList<ContainerSource> list = new Gee.ArrayList<ContainerSource>();
        list.add(event);
        
        return list;
    }
    
    protected override ContainerSource? convert_backlink_to_container(SourceBacklink backlink) {
        EventID event_id = EventID(backlink.instance_id);
        
        Event? event = fetch(event_id);
        if (event != null)
            return event;
        
        foreach (ContainerSource container in get_holding_tank()) {
            if (((Event) container).get_event_id().id == event_id.id)
                return container;
        }
        
        return null;
    }
    
    public Gee.Collection<DataObject> get_no_event_objects() {
        return no_event.get_sources();
    }
    
    private void on_no_event_collection_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        no_event_collection_altered();
    }
}

public class Event : EventSource, ContainerSource, Proxyable {
    public const string TYPENAME = "event";
    
    // In 24-hour time.
    public const int EVENT_BOUNDARY_HOUR = 4;
    
    private const time_t TIME_T_DAY = 24 * 60 * 60;
    
    private class EventSnapshot : SourceSnapshot {
        private EventRow row;
        private LibraryPhoto key_photo;
        private Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        
        public EventSnapshot(Event event) {
            // save current state of event
            row = EventTable.get_instance().get_row(event.get_event_id());
            key_photo = event.get_primary_photo();
            
            // stash all the photos in the event ... these are not used when reconstituting the
            // event, but need to know when they're destroyed, as that means the event cannot
            // be restored
            foreach (PhotoSource photo in event.get_photos())
                photos.add((LibraryPhoto) photo);
            
            LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
        }
        
        ~EventSnapshot() {
            LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
        }
        
        public EventRow get_row() {
            return row;
        }
        
        public override void notify_broken() {
            row = EventRow();
            key_photo = null;
            photos.clear();
            
            base.notify_broken();
        }
        
        private void on_photo_destroyed(DataSource source) {
            LibraryPhoto photo = (LibraryPhoto) source;
            
            // if one of the photos in the event goes away, reconstitution is impossible
            if (key_photo != null && key_photo.equals(photo))
                notify_broken();
            else if (photos.contains(photo))
                notify_broken();
        }
    }
    
    private class EventProxy : SourceProxy {
        public EventProxy(Event event) {
            base (event);
        }
        
        public override DataSource reconstitute(int64 object_id, SourceSnapshot snapshot) {
            EventSnapshot event_snapshot = snapshot as EventSnapshot;
            assert(event_snapshot != null);
            
            return Event.reconstitute(object_id, event_snapshot.get_row());
        }
        
    }
    
    public static EventSourceCollection global = null;
    
    private static EventTable event_table = null;
    
    private EventID event_id;
    private string? raw_name;
    private LibraryPhoto primary_photo;
    private ViewCollection view;
    
    private Event(EventRow event_row, int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        this.event_id = event_row.event_id;
        this.raw_name = event_row.name;
        
        Gee.ArrayList<PhotoID?> event_photo_ids = PhotoTable.get_instance().get_event_photos(event_id);
        Gee.ArrayList<PhotoView> event_photos = new Gee.ArrayList<PhotoView>();
        foreach (PhotoID photo_id in event_photo_ids) {
            LibraryPhoto? photo = LibraryPhoto.global.fetch(photo_id);
            if (photo != null)
                event_photos.add(new PhotoView(photo));
        }
        
        view = new ViewCollection("ViewCollection for Event %s".printf(event_id.id.to_string()));
        view.set_comparator(view_comparator, view_comparator_predicate);
        view.add_many(event_photos);
        
        // need to do this manually here because only want to monitor ViewCollection contents after
        // initial batch has been added, but need to keep EventSourceCollection apprised
        if (event_photos.size > 0) {
            global.notify_container_contents_added(this, event_photos);
            global.notify_container_contents_altered(this, event_photos, null);
        }
        
        // get the primary photo for monitoring; if not available, use the first photo in the
        // event
        primary_photo = LibraryPhoto.global.fetch(event_row.primary_photo_id);
        if (primary_photo == null && view.get_count() > 0) {
            primary_photo = (LibraryPhoto) ((DataView) view.get_at(0)).get_source();
            event_table.set_primary_photo(event_id, primary_photo.get_photo_id());
        }
        
        // watch the primary photo to reflect thumbnail changes
        if (primary_photo != null)
            primary_photo.thumbnail_altered.connect(on_primary_thumbnail_altered);

        // watch for for addition, removal, and alteration of photos
        view.items_added.connect(on_photos_added);
        view.items_removed.connect(on_photos_removed);
        view.items_altered.connect(on_photos_altered);
        
        // because we're no longer using source monitoring (for performance reasons), need to watch
        // for photo destruction (but not removal, which is handled automatically in any case)
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
    }

    ~Event() {
        if (primary_photo != null)
            primary_photo.thumbnail_altered.disconnect(on_primary_thumbnail_altered);
        
        view.items_altered.disconnect(on_photos_altered);
        view.items_removed.disconnect(on_photos_removed);
        view.items_added.disconnect(on_photos_added);
        
        LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
    }
    
    public override string get_typename() {
        return TYPENAME;
    }
    
    public override int64 get_instance_id() {
        return get_event_id().id;
    }
    
    public override string get_representative_id() {
        return (primary_photo != null) ? primary_photo.get_source_id() : get_source_id();
    }
    
    public override PhotoFileFormat get_preferred_thumbnail_format() {
        return (primary_photo != null) ? primary_photo.get_preferred_thumbnail_format() :
            PhotoFileFormat.get_system_default_format();
    }

    public override Gdk.Pixbuf? create_thumbnail(int scale) throws Error {
        return (primary_photo != null) ? primary_photo.create_thumbnail(scale) : null;
    }

    public static void init(ProgressMonitor? monitor = null) {
        event_table = EventTable.get_instance();
        global = new EventSourceCollection();
        global.init();
        
        // add all events to the global collection
        Gee.ArrayList<Event> events = new Gee.ArrayList<Event>();
        Gee.ArrayList<Event> unlinked = new Gee.ArrayList<Event>();

        Gee.ArrayList<EventRow?> event_rows = event_table.get_events();
        int count = event_rows.size;
        for (int ctr = 0; ctr < count; ctr++) {
            Event event = new Event(event_rows[ctr]);
            
            if (event.get_photo_count() != 0) {
                events.add(event);
                
                continue;
            }
            
            // TODO: If event has no backlinks, destroy (empty Event stored in database) ... this
            // is expensive to check at startup time, however, should happen in background or
            // during a "clean" operation
            event.rehydrate_backlinks(global, null);
            unlinked.add(event);
        }
        
        global.add_many(events, monitor);
        global.init_add_many_unlinked(unlinked);
    }
    
    public static void terminate() {
    }
    
    private static int64 view_comparator(void *a, void *b) {
        return ((PhotoView *) a)->get_photo_source().get_exposure_time() 
            - ((PhotoView *) b)->get_photo_source().get_exposure_time();
    }
    
    private static bool view_comparator_predicate(DataObject object, Alteration alteration) {
        return alteration.has_detail("metadata", "exposure-time");
    }
    
    // This is used by Photo to notify Event when it's joined.  Don't use this to manually attach a
    // Photo to an Event, use Photo.set_event().
    public void attach(Photo photo) {
        view.add(new PhotoView(photo));
    }
    
    public void attach_many(Gee.Collection<Photo> photos) {
        Gee.ArrayList<PhotoView> views = new Gee.ArrayList<PhotoView>();
        foreach (Photo photo in photos)
            views.add(new PhotoView(photo));
        
        view.add_many(views);
    }
    
    // This is used by Photo to notify Event when it's leaving.  Don't use this manually to detach
    // a Photo, use Photo.set_event().
    public void detach(Photo photo) {
        view.remove_marked(view.mark(view.get_view_for_source(photo)));
    }
    
    public void detach_many(Gee.Collection<Photo> photos) {
        Gee.ArrayList<PhotoView> views = new Gee.ArrayList<PhotoView>();
        foreach (Photo photo in photos) {
            PhotoView? view = (PhotoView?) view.get_view_for_source(photo);
            if (view != null)
                views.add(view);
        }
        
        view.remove_marked(view.mark_many(views));
    }
    
    private Gee.ArrayList<LibraryPhoto> views_to_photos(Gee.Iterable<DataObject> views) {
        Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        foreach (DataObject object in views)
            photos.add((LibraryPhoto) ((DataView) object).get_source());
        
        return photos;
    }
    
    private void on_photos_added(Gee.Iterable<DataObject> added) {
        Gee.Collection<LibraryPhoto> photos = views_to_photos(added);
        global.notify_container_contents_added(this, photos);
        global.notify_container_contents_altered(this, photos, null);
        
        notify_altered(new Alteration.from_list("contents:added, metadata:time"));
    }
    
    // Event needs to know whenever a photo is removed from the system to update the event
    private void on_photos_removed(Gee.Iterable<DataObject> removed) {
        Gee.ArrayList<LibraryPhoto> photos = views_to_photos(removed);
        
        global.notify_container_contents_removed(this, photos);
        global.notify_container_contents_altered(this, null, photos);
        
        // update primary photo if it's been removed (and there's one to take its place)
        foreach (LibraryPhoto photo in photos) {
            if (photo == primary_photo) {
                if (get_photo_count() > 0)
                    set_primary_photo((LibraryPhoto) view.get_first().get_source());
                else
                    release_primary_photo();
                
                break;
            }
        }
        
        // evaporate event if no more photos in it; do not touch thereafter
        if (get_photo_count() == 0) {
            global.evaporate(this);
            
            // as it's possible (highly likely, in fact) that all refs to the Event object have
            // gone out of scope now, do NOT touch this, but exit immediately
            return;
        }
        
        notify_altered(new Alteration.from_list("contents:removed, metadata:time"));
    }
    
    private void on_photo_destroyed(DataSource source) {
        DataView? photo_view = view.get_view_for_source(source);
        if (photo_view != null)
            view.remove_marked(view.mark(photo_view));
    }
    
    public override void notify_relinking(SourceCollection sources) {
        assert(get_photo_count() > 0);
        
        // If the primary photo was lost in the unlink, reestablish it now.
        if (primary_photo == null)
            set_primary_photo((LibraryPhoto) view.get_first().get_source());
        
        base.notify_relinking(sources);
    }
    
    private void on_photos_altered(Gee.Map<DataObject, Alteration> items) {
        foreach (Alteration alteration in items.values) {
            if (alteration.has_subject("metadata")) {
                notify_altered(new Alteration("metadata", "time"));
                
                break;
            }
        }
    }
    
    // This creates an empty event with the key photo.  NOTE: This does not add the key photo to
    // the event.  That must be done manually.
    public static Event? create_empty_event(LibraryPhoto key_photo) {
        try {
            Event event = new Event(EventTable.get_instance().create(key_photo.get_photo_id()));
            global.add(event);
            
            debug("Created empty event %s", event.to_string());
            
            return event;
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
            
            return null;
        }
    }
    
    // This will create an event using the fields supplied in EventRow.  The event_id is ignored.
    private static Event reconstitute(int64 object_id, EventRow row) {
        row.event_id = EventTable.get_instance().create_from_row(row);
        Event event = new Event(row, object_id);
        global.add(event);
        assert(global.contains(event));
        
        debug("Reconstituted event %s", event.to_string());
        
        return event;
    }
    
    public bool has_links() {
        return LibraryPhoto.global.has_backlink(get_backlink());
    }
    
    public SourceBacklink get_backlink() {
        return new SourceBacklink.from_source(this);
    }
    
    public void break_link(DataSource source) {
        ((LibraryPhoto) source).set_event(null);
    }
    
    public void break_link_many(Gee.Collection<DataSource> sources) {
        LibraryPhoto.global.freeze_notifications();
        Photo.set_many_to_event((Gee.Collection<Photo>) sources, null);
        LibraryPhoto.global.thaw_notifications();
    }
    
    public void establish_link(DataSource source) {
        ((LibraryPhoto) source).set_event(this);
    }
    
    public void establish_link_many(Gee.Collection<DataSource> sources) {
        LibraryPhoto.global.freeze_notifications();
        Photo.set_many_to_event((Gee.Collection<Photo>) sources, this);
        LibraryPhoto.global.thaw_notifications();
    }
    
    public bool is_in_starting_day(time_t time) {
        // it's possible the Event ref is held although it's been emptied
        // (such as the user removing items during an import, when events
        // are being generate on-the-fly) ... return false here and let
        // the caller make a new one
        if (view.get_count() == 0)
            return false;
        
        // photos are stored in ViewCollection from earliest to latest
        LibraryPhoto earliest_photo = (LibraryPhoto) ((PhotoView) view.get_at(0)).get_source();
        Time earliest_tm = Time.local(earliest_photo.get_exposure_time());
        
        // use earliest to generate the boundary hour for that day
        Time start_boundary_tm = Time();
        start_boundary_tm.second = 0;
        start_boundary_tm.minute = 0;
        start_boundary_tm.hour = EVENT_BOUNDARY_HOUR;
        start_boundary_tm.day = earliest_tm.day;
        start_boundary_tm.month = earliest_tm.month;
        start_boundary_tm.year = earliest_tm.year;
        start_boundary_tm.isdst = -1;
        
        time_t start_boundary = start_boundary_tm.mktime();
        
        // if the earliest's exposure time was on the day but *before* the boundary hour,
        // step it back a day to the prior day's boundary
        if (earliest_tm.hour < EVENT_BOUNDARY_HOUR)
            start_boundary -= TIME_T_DAY;
        
        time_t end_boundary = (start_boundary + TIME_T_DAY - 1);
        
        return time >= start_boundary && time <= end_boundary;
    }
    
    // This method attempts to add the photo to an event in the supplied list that it would
    // naturally fit into (i.e. its exposure is within the boundary day of the earliest event
    // photo).  Otherwise, a new Event is generated and the photo is added to it and the list.
    public static void generate_import_event(
        LibraryPhoto photo, ViewCollection events_so_far, string? event_name = null
    ) {
        time_t exposure_time = photo.get_exposure_time();
        if (exposure_time == 0 && event_name == null) {
            debug("Skipping event assignment to %s: no exposure time and no event name", photo.to_string());
            
            return;
        }
        
        int count = events_so_far.get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            Event event = (Event) ((EventView) events_so_far.get_at(ctr)).get_source();
            
            if (event_name != null) {
                if (event.has_name() && event_name == event.get_name()) {
                    photo.set_event(event);
                    
                    return;
                }
            } else if (event.is_in_starting_day(exposure_time)) {
                photo.set_event(event);
                
                return;
            }
        }
        
        // no Event so far fits the bill for this photo, so create a new one
        try {
            Event event = new Event(EventTable.get_instance().create(photo.get_photo_id()));
            if (event_name != null)
                event.rename(event_name);
            photo.set_event(event);
            global.add(event);
            
            events_so_far.add(new EventView(event));
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
    }
    
    public EventID get_event_id() {
        return event_id;
    }
    
    public override SourceSnapshot? save_snapshot() {
        return new EventSnapshot(this);
    }
    
    public SourceProxy get_proxy() {
        return new EventProxy(this);
    }
    
    public override bool equals(DataSource? source) {
        // Validate primary key is unique, which is vital to all this working
        Event? event = source as Event;
        if (event != null) {
            if (this != event) {
                assert(event_id.id != event.event_id.id);
            }
        }
        
        return base.equals(source);
    }
    
    public override string to_string() {
        return "Event [%s/%s] %s".printf(event_id.id.to_string(), get_object_id().to_string(), get_name());
    }
    
    public bool has_name() {
        return raw_name != null && raw_name.length > 0;
    }
    
    public override string get_name() {
        if (has_name())
            return get_raw_name();
        
        // if no name, pretty up the start time
        time_t start_time = get_start_time();
        
        return (start_time != 0) 
            ? format_local_date(Time.local(start_time)) 
            : _("Event %s").printf(event_id.id.to_string());
    }
    
    public string? get_raw_name() {
        return raw_name;
    }
    
    public bool rename(string? name) {
        bool renamed = event_table.rename(event_id, name);
        if (renamed) {
            raw_name = is_string_empty(name) ? null : name;
            notify_altered(new Alteration("metadata", "name"));
        }
        
        return renamed;
    }
    
    public time_t get_creation_time() {
        return event_table.get_time_created(event_id);
    }
    
    public override time_t get_start_time() {
        // Because the ViewCollection is sorted by a DateComparator, the start time is the
        // first item.  However, we keep looking if it has no start time.
        int count = view.get_count();
        for (int i = 0; i < count; i++) {
            time_t time = ((PhotoView) view.get_at(i)).get_photo_source().get_exposure_time();
            if (time != 0)
                return time;
        }

        return 0;
    }
    
    public override time_t get_end_time() {
        int count = view.get_count();
        
        // Because the ViewCollection is sorted by a DateComparator, the end time is the
        // last item--no matter what.
        if (count == 0)
            return 0;
        
        PhotoView photo = (PhotoView) view.get_at(count - 1);
        
        return photo.get_photo_source().get_exposure_time();
    }
    
    public override uint64 get_total_filesize() {
        uint64 total = 0;
        foreach (PhotoSource photo in get_photos()) {
            total += photo.get_filesize();
        }
        
        return total;
    }
    
    public override int get_photo_count() {
        return view.get_count();
    }
    
    public override Gee.Collection<PhotoSource> get_photos() {
        return (Gee.Collection<PhotoSource>) view.get_sources();
    }
    
    public void mirror_photos(ViewCollection view, CreateView mirroring_ctor) {
        view.mirror(this.view, mirroring_ctor);
    }
    
    private void on_primary_thumbnail_altered() {
        notify_thumbnail_altered();
    }

    public LibraryPhoto get_primary_photo() {
        return primary_photo;
    }
    
    public bool set_primary_photo(LibraryPhoto photo) {
        assert(view.has_view_for_source(photo));
        
        bool committed = event_table.set_primary_photo(event_id, photo.get_photo_id());
        if (committed) {
            // switch to the new photo
            if (primary_photo != null)
                primary_photo.thumbnail_altered.disconnect(on_primary_thumbnail_altered);

            primary_photo = photo;
            primary_photo.thumbnail_altered.connect(on_primary_thumbnail_altered);
            
            notify_thumbnail_altered();
        }
        
        return committed;
    }
    
    private void release_primary_photo() {
        if (primary_photo == null)
            return;
        
        primary_photo.thumbnail_altered.disconnect(on_primary_thumbnail_altered);
        primary_photo = null;
    }
    
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return primary_photo != null ? primary_photo.get_thumbnail(scale) : null;
    }
    
    public Gdk.Pixbuf? get_preview_pixbuf(Scaling scaling) {
        try {
            return get_primary_photo().get_preview_pixbuf(scaling);
        } catch (Error err) {
            return null;
        }
    }

    public override void destroy() {
        // stop monitoring the photos collection
        view.halt_all_monitoring();
        
        // remove from the database
        try {
            event_table.remove(event_id);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // mark all photos for this event as now event-less
        PhotoTable.get_instance().drop_event(event_id);
        
        base.destroy();
   }
}

