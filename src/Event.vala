/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class EventSourceCollection : ContainerSourceCollection {
    public EventSourceCollection() {
        base(LibraryPhoto.global, Event.BACKLINK_NAME, "EventSourceCollection", get_event_key);
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
        EventID event_id = Event.id_from_backlink(backlink);
        
        Event? event = fetch(event_id);
        if (event != null)
            return event;
        
        foreach (ContainerSource container in get_holding_tank()) {
            if (((Event) container).get_event_id().id == event_id.id)
                return container;
        }
        
        return null;
    }
}

public class Event : EventSource, ContainerSource, Proxyable {
    public const string BACKLINK_NAME = "event";
    
    // In 24-hour time.
    public const int EVENT_BOUNDARY_HOUR = 4;
    
    private const time_t TIME_T_DAY = 24 * 60 * 60;
    
    private class EventManager : ViewManager {
        private EventID event_id;

        public EventManager(EventID event_id) {
            this.event_id = event_id;
        }

        public override bool include_in_view(DataSource source) {
            return ((TransformablePhoto) source).get_event_id().id == event_id.id;
        }

        public override DataView create_view(DataSource source) {
            return new PhotoView((PhotoSource) source);
        }
    }
    
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
    
    private Event(EventID event_id, int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        this.event_id = event_id;
        this.raw_name = event_table.get_name(event_id);
        
        Gee.ArrayList<PhotoID?> event_photo_ids = PhotoTable.get_instance().get_event_photos(event_id);
        Gee.ArrayList<LibraryPhoto> event_photos = new Gee.ArrayList<LibraryPhoto>();
        foreach (PhotoID photo_id in event_photo_ids)
            event_photos.add(LibraryPhoto.global.fetch(photo_id));
        
        view = new ViewCollection("ViewCollection for Event %lld".printf(event_id.id));
        view.set_comparator(view_comparator);
        view.monitor_source_collection(LibraryPhoto.global, new EventManager(event_id), event_photos); 
        
        // need to do this manually here because only want to monitor ViewCollection contents after
        // initial batch has been added, but need to keep EventSourceCollection apprised
        if (event_photos.size > 0) {
            global.notify_container_contents_added(this, event_photos);
            global.notify_container_contents_altered(this, event_photos, null);
        }
        
        // get the primary photo for monitoring; if not available, use the first photo in the
        // event
        primary_photo = LibraryPhoto.global.fetch(event_table.get_primary_photo(event_id));
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
        view.items_metadata_altered.connect(on_photos_metadata_altered);
    }

    ~Event() {
        if (primary_photo != null)
            primary_photo.thumbnail_altered.disconnect(on_primary_thumbnail_altered);
        
        view.items_metadata_altered.disconnect(on_photos_metadata_altered);
        view.items_removed.disconnect(on_photos_removed);
        view.items_added.disconnect(on_photos_added);
    }
    
    public static void init(ProgressMonitor? monitor = null) {
        event_table = EventTable.get_instance();
        global = new EventSourceCollection();
        
        // add all events to the global collection
        Gee.ArrayList<Event> events = new Gee.ArrayList<Event>();
        Gee.ArrayList<Event> unlinked = new Gee.ArrayList<Event>();

        Gee.ArrayList<EventID?> event_ids = event_table.get_events();
        int count = event_ids.size;
        for (int ctr = 0; ctr < count; ctr++) {
            Event event = new Event(event_ids[ctr]);
            
            if (event.get_photo_count() != 0) {
                events.add(event);
                
                continue;
            }
            
            if (event.has_links()) {
                event.rehydrate_backlinks(global, null);
                unlinked.add(event);
                
                continue;
            }
            
            message("Empty event %s with no backlinks found, destroying", event.to_string());
            event.destroy_orphan(true);
        }
        
        global.add_many(events, monitor);
        global.init_add_many_unlinked(unlinked);
    }
    
    public static void terminate() {
    }
    
    private static int64 source_comparator(void *a, void *b) {
        return ((PhotoSource *) a)->get_exposure_time() - ((PhotoSource *) b)->get_exposure_time();
    }
    
    private static int64 view_comparator(void *a, void *b) {
        return ((PhotoView *) a)->get_photo_source().get_exposure_time() 
            - ((PhotoView *) b)->get_photo_source().get_exposure_time();
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
        
        notify_altered();
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
        
        notify_altered();
    }
    
    public override void notify_relinking(SourceCollection sources) {
        assert(get_photo_count() > 0);
        
        // If the primary photo was lost in the unlink, reestablish it now.
        if (primary_photo == null)
            set_primary_photo((LibraryPhoto) view.get_first().get_source());
        
        base.notify_relinking(sources);
    }
    
    private void on_photos_metadata_altered() {
        notify_altered();
    }
    
    // This creates an empty event with the key photo.  NOTE: This does not add the key photo to
    // the event.  That must be done manually.
    public static Event create_empty_event(LibraryPhoto key_photo) {
        EventID event_id = EventTable.get_instance().create(key_photo.get_photo_id());
        Event event = new Event(event_id);
        global.add(event);
        
        debug("Created empty event %s", event.to_string());
        
        return event;
    }
    
    // This will create an event using the fields supplied in EventRow.  The event_id is ignored.
    private static Event reconstitute(int64 object_id, EventRow row) {
        EventID event_id = EventTable.get_instance().create_from_row(row);
        Event event = new Event(event_id, object_id);
        global.add(event);
        assert(global.contains(event));
        
        debug("Reconstituted event %s", event.to_string());
        
        return event;
    }
    
    public static EventID id_from_backlink(SourceBacklink backlink) {
        return EventID(backlink.value.to_int64());
    }
    
    public bool has_links() {
        return LibraryPhoto.global.has_backlink(get_backlink());
    }
    
    public SourceBacklink get_backlink() {
        return new SourceBacklink(BACKLINK_NAME, event_id.id.to_string());
    }
    
    public void break_link(DataSource source) {
        ((LibraryPhoto) source).set_event(null);
    }
    
    public void establish_link(DataSource source) {
        ((LibraryPhoto) source).set_event(this);
    }
    
    public static void generate_events(Gee.List<LibraryPhoto> unsorted_photos, ProgressMonitor? monitor) {
        int count = 0;
        int total = unsorted_photos.size;
        
        // sort photos by date
        SortedList<LibraryPhoto> imported_photos = new SortedList<LibraryPhoto>(source_comparator);
        imported_photos.add_all(unsorted_photos);

        // walk through photos, splitting into new events when the boundary hour is crossed
        Event current_event = null;
        Time event_tm = Time();
        foreach (LibraryPhoto photo in imported_photos) {
            time_t exposure_time = photo.get_exposure_time();

            // report to ProgressMonitor
            if (monitor != null) {
                if (!monitor(++count, total))
                    break;
            }
            
            if (exposure_time == 0) {
                // no time recorded; skip
                debug("Skipping event assignment to %s: No exposure time", photo.to_string());
                
                continue;
            }
            
            if (photo.get_event() != null) {
                // already part of an event; skip
                debug("Skipping event assignment to %s: Already part of event %s", photo.to_string(),
                    photo.get_event().to_string());
                    
                continue;
            }
            
            // check if time to create a new event
            if (current_event == null) {
                current_event = new Event(event_table.create(photo.get_photo_id()));
                event_tm = Time.local(exposure_time);
            } else {
                // see if stepped past the event day boundary by converting to that hour on
                // the current photo's day and seeing if it and the last one straddle it or the
                // day after's boundary
                Time start_boundary_tm = Time();
                start_boundary_tm.second = 0;
                start_boundary_tm.minute = 0;
                start_boundary_tm.hour = EVENT_BOUNDARY_HOUR;
                start_boundary_tm.day = event_tm.day;
                start_boundary_tm.month = event_tm.month;
                start_boundary_tm.year = event_tm.year;
                
                time_t start_boundary = start_boundary_tm.mktime();
                
                // if the event's exposure time was on the day but *before* the boundary hour,
                // step it back a day to the prior day's boundary
                if (event_tm.hour < EVENT_BOUNDARY_HOUR)
                    start_boundary -= TIME_T_DAY;
                
                time_t end_boundary = (start_boundary + TIME_T_DAY - 1);
                
                // If photo outside either boundary, new event is starting
                if (exposure_time < start_boundary || exposure_time > end_boundary) {
                    global.add(current_event);
                    
                    debug("Added event %s to global collection", current_event.to_string());
                    
                    current_event = new Event(event_table.create(photo.get_photo_id()));
                    event_tm = Time.local(exposure_time);
                }
            }
            
            // add photo to this event
            photo.set_event(current_event);
        }
        
        // make sure to add the current_event to the global
        if (current_event != null) {
            global.add(current_event);
            
            debug("Added final event %s to global collection", current_event.to_string());
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
        return "Event [%lld/%lld] %s".printf(event_id.id, get_object_id(), get_name());
    }
    
    public bool has_name() {
        return raw_name != null && raw_name.length > 0;
    }
    
    public override string get_name() {
        if (raw_name != null)
            return raw_name;
        
        // if no name, pretty up the start time
        time_t start_time = get_start_time();
        
        return (start_time != 0) 
            ? format_local_date(Time.local(start_time)) 
            : _("Event %lld").printf(event_id.id);
    }
    
    public string? get_raw_name() {
        return raw_name;
    }
    
    public bool rename(string? name) {
        bool renamed = event_table.rename(event_id, name);
        if (renamed) {
            raw_name = is_string_empty(name) ? null : name;
            notify_altered();
        }
        
        return renamed;
    }
    
    public time_t get_creation_time() {
        return event_table.get_time_created(event_id);
    }
    
    public override time_t get_start_time() {
        // Because the ViewCollection is sorted by a DateComparator, the start time is the
        // first item.  However, we keep looking if it has no start time.
        for (int i = 0; i < view.get_count(); i++) {
            time_t time = ((PhotoView) view.get_at(i)).get_photo_source().get_exposure_time();
            if (time != 0)
                return time;
        }

        return 0;
    }
    
    public override time_t get_end_time() {
        // Because the ViewCollection is sorted by a DateComparator, the end time is the
        // last item--no matter what.
        if (view.get_count() == 0)
            return 0;
        
        PhotoView photo = (PhotoView) view.get_at(view.get_count() - 1);
        
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
    
    public override Gee.Iterable<PhotoSource> get_photos() {
        return (Gee.Iterable<PhotoSource>) view.get_sources();
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
        view.halt_monitoring();
        
        // remove from the database
        event_table.remove(event_id);
        
        // mark all photos for this event as now event-less
        PhotoTable.get_instance().drop_event(event_id);
        
        base.destroy();
   }
}

