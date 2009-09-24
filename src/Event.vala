/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class EventSourceCollection : DatabaseSourceCollection {
    public EventSourceCollection() {
        base(get_event_key);
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

public class Event : EventSource {
    public const long EVENT_LULL_SEC = 3 * 60 * 60;
    public const long EVENT_MAX_DURATION_SEC = 12 * 60 * 60;
    
    public static EventSourceCollection global = null;
    
    private static EventTable event_table = null;

    private EventID event_id;
    private LibraryPhoto primary_photo;
    
    private Event(EventID event_id) {
        this.event_id = event_id;
        primary_photo = get_primary_photo();
        
        // watch the primary photo to reflect thumbnail changes
        if (primary_photo != null)
            primary_photo.thumbnail_altered += on_primary_thumbnail_altered;
    }
    
    public static void init() {
        event_table = new EventTable();
        global = new EventSourceCollection();
        
        // add all events to the global collection
        Gee.ArrayList<EventID?> events = event_table.get_events();
        foreach (EventID event_id in events)
            global.add(new Event(event_id));
        
        // Event watches LibraryPhoto for removals
        LibraryPhoto.global.items_removed += on_photos_removed;
    }
    
    public static void terminate() {
    }
    
    // Event needs to know whenever a photo is removed from the system to update the event
    private static void on_photos_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed)
            on_photo_removed((LibraryPhoto) object);
    }
    
    private static void on_photo_removed(LibraryPhoto photo) {
        // update event's primary photo if this is the one; remove event if no more photos in it
        Event event = photo.get_event();
        if (event != null && event.get_primary_photo() == photo) {
            Gee.Iterable<PhotoSource> photos = event.get_photos();
            
            LibraryPhoto found = null;
            // TODO: For now, simply selecting the first photo possible
            foreach (PhotoSource event_photo in photos) {
                if (photo != (LibraryPhoto) event_photo) {
                    found = (LibraryPhoto) event_photo;
                    
                    break;
                }
            }
            
            if (found != null) {
                event.set_primary_photo(found);
            } else {
                // this indicates this is the last photo of the event, so no more event
                assert(event.get_photo_count() <= 1);

                debug("Destroying event %s", event.to_string());
                Marker marker = Event.global.mark(event);
                Event.global.destroy_marked(marker);
            }
        }
    }
    
    public static void generate_events(SortedList<LibraryPhoto> imported_photos) {
        debug("Processing imported photos to create events ...");

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
                    assert(last_exposure != 0);
                    current_event.set_end_time(last_exposure);
                    
                    global.add(current_event);
                    
                    debug("Reported event creation %s", current_event.to_string());
                }

                current_event_start = exposure_time;
                current_event = new Event(
                    event_table.create(photo.get_photo_id(), current_event_start));

                debug("Created event %s", current_event.to_string());
            }
            
            assert(current_event != null);
            
            debug("Adding %s to event %s (exposure=%ld last_exposure=%ld)", photo.to_string(), 
                current_event.to_string(), exposure_time, last_exposure);
            
            photo.set_event(current_event);

            last_exposure = exposure_time;
        }
        
        // mark the last event's end time
        if (current_event != null) {
            assert(last_exposure != 0);
            current_event.set_end_time(last_exposure);
            
            global.add(current_event);
            
            debug("Created event %s", current_event.to_string());
        }
    }
    
    public EventID get_event_id() {
        return event_id;
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
        return "[%lld] %s".printf(event_id.id, get_name());
    }
    
    public override string get_name() {
        return event_table.get_name(event_id);
    }
    
    public string? get_raw_name() {
        return event_table.get_raw_name(event_id);
    }
    
    public bool rename(string name) {
        bool renamed = event_table.rename(event_id, name);
        if (renamed)
            notify_altered();
        
        return renamed;
    }
    
    public override time_t get_start_time() {
        return event_table.get_start_time(event_id);
    }
    
    public override time_t get_end_time() {
        return event_table.get_end_time(event_id);
    }
    
    public bool set_end_time(time_t end_time) {
        bool committed = event_table.set_end_time(event_id, end_time);
        if (committed)
            notify_altered();
        
        return committed;
    }
    
    public override uint64 get_total_filesize() {
        return (new PhotoTable()).get_event_photo_filesize(event_id);
    }
    
    public override int get_photo_count() {
        return (new PhotoTable()).get_event_photo_count(event_id);
    }
    
    public override Gee.Iterable<PhotoSource> get_photos() {
        Gee.ArrayList<PhotoID?> photos = (new PhotoTable()).get_event_photos(event_id);
        
        Gee.ArrayList<PhotoSource> result = new Gee.ArrayList<PhotoSource>();
        foreach (PhotoID photo_id in photos)
            result.add(LibraryPhoto.global.fetch(photo_id));
        
        return result;
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
        return get_primary_photo().get_preview_pixbuf(scaling);
    }

    public override void destroy() {
        // remove from the database
        event_table.remove(event_id);
        
        // mark all photos for this event as now event-less
        (new PhotoTable()).drop_event(event_id);
        
        base.destroy();
   }
}

