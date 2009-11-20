/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class EventSourceCollection : DatabaseSourceCollection {
    public EventSourceCollection() {
        base("EventSourceCollection", get_event_key);
    }
    
    private static int64 get_event_key(DataSource source) {
        Event event = (Event) source;
        EventID event_id = event.get_event_id();
        
        return event_id.id;
    }
    
    public Event fetch(EventID event_id) {
        return (Event) fetch_by_key(event_id.id);
    }
}

public class Event : EventSource, Proxyable {
    public const long EVENT_LULL_SEC = 4 * 60 * 60;
    public const long EVENT_MAX_DURATION_SEC = 12 * 60 * 60;
    private const int MIN_PHOTOS_FOR_PROGRESS_WINDOW = 100;
    
    private class DateComparator : Comparator<LibraryPhoto> {
        public override int64 compare(LibraryPhoto a, LibraryPhoto b) {
            return a.get_exposure_time() - b.get_exposure_time();
        }
    }

    private class EventManager : ViewManager {
        private EventID event_id;

        public EventManager(EventID event_id) {
            this.event_id = event_id;
        }

        public override bool include_in_view(DataSource source) {
            TransformablePhoto photo = (TransformablePhoto) source;
            return photo.get_event_id().id == event_id.id;
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
            
            LibraryPhoto.global.item_destroyed += on_photo_destroyed;
        }
        
        ~EventSnapshot() {
            LibraryPhoto.global.item_destroyed -= on_photo_destroyed;
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
    private LibraryPhoto primary_photo;
    private ViewCollection view;
    
    private Event(EventID event_id, int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        this.event_id = event_id;
        primary_photo = get_primary_photo();
        
        // watch the primary photo to reflect thumbnail changes
        if (primary_photo != null)
            primary_photo.thumbnail_altered += on_primary_thumbnail_altered;

        view = new ViewCollection("ViewCollection for %lld".printf(event_id.id));
        view.monitor_source_collection(LibraryPhoto.global, new EventManager(event_id)); 

        // watch for for removal and addition of photos
        view.items_removed += on_photos_removed;
        view.items_added += on_photos_added;
    }

    ~Event() {
        if (primary_photo != null)
            primary_photo.thumbnail_altered -= on_primary_thumbnail_altered;
        
        view.items_removed -= on_photos_removed;
        view.items_added -= on_photos_added;
    }
    
    public static void init() {
        event_table = EventTable.get_instance();
        global = new EventSourceCollection();
        
        // add all events to the global collection
        Gee.ArrayList<EventID?> events = event_table.get_events();
        foreach (EventID event_id in events)
            global.add(new Event(event_id));
    }
    
    public static void terminate() {
    }

    private void on_photos_added() {
        notify_altered();
    }
  
    // Event needs to know whenever a photo is removed from the system to update the event
    private void on_photos_removed(Gee.Iterable<DataObject> removed) {
        // remove event if no more photos in it
        if (get_photo_count() == 0) {
            debug("Destroying event %s", to_string());
            
            Marker marker = Event.global.mark(this);
            Event.global.destroy_marked(marker);
            
            // as it's possible (highly likely, in fact) that all refs to the Event object have
            // gone out of scope now, do NOT touch this, but exit immediately
            return;
        }
        
        foreach (DataObject object in removed)
            on_photo_removed((LibraryPhoto) ((PhotoView) object).get_source());
        
        notify_altered();
    }
    
    private void on_photo_removed(LibraryPhoto photo) {
        // update primary photo if this is the one
        if (event_table.get_primary_photo(event_id).id == photo.get_photo_id().id) {
            PhotoView first = (PhotoView) view.get_at(0);
            set_primary_photo((LibraryPhoto) first.get_photo_source());
        }
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
    
    public static void generate_events(Gee.List<LibraryPhoto> unsorted_photos) {
        debug("Processing imported photos to create events ...");
        
        // sort photos by date
        SortedList<LibraryPhoto> imported_photos = new SortedList<LibraryPhoto>(new DateComparator());
        foreach (LibraryPhoto photo in unsorted_photos)
            imported_photos.add(photo);

        // walk through photos, splitting into events based on criteria
        time_t last_exposure = 0;
        time_t current_event_start = 0;
        Event current_event = null;
        foreach (LibraryPhoto photo in imported_photos) {
            time_t exposure_time = photo.get_exposure_time();

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
            
            // see if enough time has elapsed to create a new event, or to store this photo in
            // the current one
            bool create_event = false;
            if (last_exposure == 0) {
                // first photo, start a new event
                create_event = true;
            } else {
                assert(last_exposure <= exposure_time);
                assert(current_event_start <= exposure_time);

                if (exposure_time - last_exposure >= EVENT_LULL_SEC) {
                    // enough time has passed between photos to signify a new event
                    create_event = true;
                } else if (exposure_time - current_event_start >= EVENT_MAX_DURATION_SEC) {
                    // the current event has gone on for too long, stop here and start a new one
                    create_event = true;
                }
            }
            
            if (create_event) {
                if (current_event != null) {
                    global.add(current_event);
                    
                    debug("Added event %s to global collection", current_event.to_string());
                }

                current_event_start = exposure_time;
                current_event = new Event(event_table.create(photo.get_photo_id()));

                debug("Created new event %s", current_event.to_string());
            }
            
            assert(current_event != null);
            
            debug("Adding %s to event %s (exposure=%ld last_exposure=%ld)", photo.to_string(), 
                current_event.to_string(), exposure_time, last_exposure);
            
            photo.set_event(current_event);

            last_exposure = exposure_time;
        }

        if (current_event != null) {
            global.add(current_event);
            
            debug("Added event %s to global collection", current_event.to_string());
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
    
    public bool equals(Event event) {
        // due to the event_map, identity should be preserved by pointers, but ID is the true test
        if (this == event) {
            assert(event_id.id == event.event_id.id);
            
            return true;
        }
        
        assert(event_id.id != event.event_id.id);
        
        return false;
    }
    
    public override string to_string() {
        return "Event [%lld/%lld] %s".printf(event_id.id, get_object_id(), get_name());
    }
    
    public override string get_name() {
        string event_name = event_table.get_name(event_id);

        // if no name, pretty up the start time
        if (event_name != null)
            return event_name;

        time_t start_time = get_start_time();
        
        return (start_time != 0) 
            ? format_local_date(Time.local(start_time)) 
            : _("Event %lld").printf(event_id.id);
    }
    
    public string? get_raw_name() {
        return event_table.get_name(event_id);
    }
    
    public bool rename(string? name) {
        bool renamed = event_table.rename(event_id, name);
        if (renamed)
            notify_altered();
        
        return renamed;
    }
    
    public time_t get_creation_time() {
        return event_table.get_time_created(event_id);
    }
    
    public override time_t get_start_time() {
        time_t start_time = time_t();

        foreach (PhotoSource photo in get_photos()) {
            if (photo.get_exposure_time() < start_time)
                start_time = photo.get_exposure_time();
        }

        return start_time;
    }
    
    public override time_t get_end_time() {
        time_t end_time = 0;

        foreach (PhotoSource photo in get_photos()) {
            if (photo.get_exposure_time() > end_time)
                end_time = photo.get_exposure_time();
        }

        return end_time;
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
        return LibraryPhoto.global.fetch(event_table.get_primary_photo(event_id));
    }
    
    public bool set_primary_photo(LibraryPhoto photo) {
        bool committed = event_table.set_primary_photo(event_id, photo.get_photo_id());
        if (committed) {
            // switch to the new photo
            if (primary_photo != null)
                primary_photo.thumbnail_altered -= on_primary_thumbnail_altered;

            primary_photo = photo;
            primary_photo.thumbnail_altered += on_primary_thumbnail_altered;
            
            notify_thumbnail_altered();
        }
        
        return committed;
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

