/* Copyright 2016 Software Freedom Conservancy Inc.
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
            return (((MediaSource) source).get_event_id().id != EventID.INVALID) ? false :
                base.include_in_view(source);
        }
    
        public override DataView create_view(DataSource source) {
            return new ThumbnailView((MediaSource) source);
        }
    }
    
    public EventSourceCollection() {
        base(Event.TYPENAME, "EventSourceCollection", get_event_key);

        attach_collection(LibraryPhoto.global);
        attach_collection(Video.global);
    }

    public void init() {
        no_event = new ViewCollection("No Event View Collection");
        
        NoEventViewManager view_manager = new NoEventViewManager();
        Alteration filter_alteration = new Alteration("metadata", "event");

        no_event.monitor_source_collection(LibraryPhoto.global, view_manager, filter_alteration);
        no_event.monitor_source_collection(Video.global, view_manager, filter_alteration);
        
        no_event.contents_altered.connect(on_no_event_collection_altered);
    }
    
    public override bool holds_type_of_source(DataSource source) {
        return source is Event;
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
        Event? event = ((MediaSource) source).get_event();
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

public class Event : EventSource, ContainerSource, Proxyable, Indexable {
    public const string TYPENAME = "event";
    
    // SHOW_COMMENTS (bool)
    public const string PROP_SHOW_COMMENTS = "show-comments";
    
    // In 24-hour time.
    public const int EVENT_BOUNDARY_HOUR = 4;
    
    private const time_t TIME_T_DAY = 24 * 60 * 60;
    
    private class EventSnapshot : SourceSnapshot {
        private EventRow row;
        private MediaSource primary_source;
        private Gee.ArrayList<MediaSource> attached_sources = new Gee.ArrayList<MediaSource>();
        
        public EventSnapshot(Event event) {
            // save current state of event
            row = EventTable.get_instance().get_row(event.get_event_id());
            primary_source = event.get_primary_source();
            
            // stash all the media sources in the event ... these are not used when reconstituting
            // the event, but need to know when they're destroyed, as that means the event cannot
            // be restored
            foreach (MediaSource source in event.get_media())
                attached_sources.add(source);
            
            LibraryPhoto.global.item_destroyed.connect(on_attached_source_destroyed);
            Video.global.item_destroyed.connect(on_attached_source_destroyed);
        }
        
        ~EventSnapshot() {
            LibraryPhoto.global.item_destroyed.disconnect(on_attached_source_destroyed);
            Video.global.item_destroyed.disconnect(on_attached_source_destroyed);
        }
        
        public EventRow get_row() {
            return row;
        }
        
        public override void notify_broken() {
            row = new EventRow();
            primary_source = null;
            attached_sources.clear();
            
            base.notify_broken();
        }
        
        private void on_attached_source_destroyed(DataSource source) {
            MediaSource media_source = (MediaSource) source;
            
            // if one of the media sources in the event goes away, reconstitution is impossible
            if (media_source != null && primary_source.equals(media_source))
                notify_broken();
            else if (attached_sources.contains(media_source))
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
    private MediaSource primary_source;
    private ViewCollection view;
    private bool unlinking = false;
    private bool relinking = false;
    private string? indexable_keywords = null;
    private string? comment = null;
    
    private Event(EventRow event_row, int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        // normalize user text
        event_row.name = prep_event_name(event_row.name);
        
        this.event_id = event_row.event_id;
        this.raw_name = event_row.name;
        this.comment = event_row.comment;
        
        Gee.Collection<string> event_source_ids =
            MediaCollectionRegistry.get_instance().get_source_ids_for_event_id(event_id);
        Gee.ArrayList<ThumbnailView> event_thumbs = new Gee.ArrayList<ThumbnailView>();
        foreach (string current_source_id in event_source_ids) {
            MediaSource? media =
                MediaCollectionRegistry.get_instance().fetch_media(current_source_id);
            if (media != null)
                event_thumbs.add(new ThumbnailView(media));
        }
        
        view = new ViewCollection("ViewCollection for Event %s".printf(event_id.id.to_string()));
        view.set_comparator(view_comparator, view_comparator_predicate);
        view.add_many(event_thumbs);
        
        // need to do this manually here because only want to monitor ViewCollection contents after
        // initial batch has been added, but need to keep EventSourceCollection apprised
        if (event_thumbs.size > 0) {
            global.notify_container_contents_added(this, event_thumbs, false);
            global.notify_container_contents_altered(this, event_thumbs, false, null, false);
        }
        
        // get the primary source for monitoring; if not available, use the first unrejected
        // source in the event
        primary_source = MediaCollectionRegistry.get_instance().fetch_media(event_row.primary_source_id);
        if (primary_source == null && view.get_count() > 0) {
            primary_source = (MediaSource) ((DataView) view.get_first_unrejected()).get_source();
            event_table.set_primary_source_id(event_id, primary_source.get_source_id());
        }
        
        // watch the primary source to reflect thumbnail changes
        if (primary_source != null)
            primary_source.thumbnail_altered.connect(on_primary_thumbnail_altered);

        // watch for for addition, removal, and alteration of photos and videos
        view.items_added.connect(on_media_added);
        view.items_removed.connect(on_media_removed);
        view.items_altered.connect(on_media_altered);
        
        // because we're no longer using source monitoring (for performance reasons), need to watch
        // for media destruction (but not removal, which is handled automatically in any case)
        LibraryPhoto.global.item_destroyed.connect(on_media_destroyed);
        Video.global.item_destroyed.connect(on_media_destroyed);
        
        update_indexable_keywords();
    }

    ~Event() {
        if (primary_source != null)
            primary_source.thumbnail_altered.disconnect(on_primary_thumbnail_altered);
        
        view.items_altered.disconnect(on_media_altered);
        view.items_removed.disconnect(on_media_removed);
        view.items_added.disconnect(on_media_added);
        
        LibraryPhoto.global.item_destroyed.disconnect(on_media_destroyed);
        Video.global.item_destroyed.disconnect(on_media_destroyed);
    }
    
    public override string get_typename() {
        return TYPENAME;
    }
    
    public override int64 get_instance_id() {
        return get_event_id().id;
    }
    
    public override string get_representative_id() {
        return (primary_source != null) ? primary_source.get_source_id() : get_source_id();
    }
    
    public override PhotoFileFormat get_preferred_thumbnail_format() {
        return (primary_source != null) ? primary_source.get_preferred_thumbnail_format() :
            PhotoFileFormat.get_system_default_format();
    }

    public override Gdk.Pixbuf? create_thumbnail(int scale) throws Error {
        return (primary_source != null) ? primary_source.create_thumbnail(scale) : null;
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
            if (monitor != null)
                monitor(ctr, count);
            
            if (event.get_media_count() != 0) {
                events.add(event);
                
                continue;
            }
            
            // TODO: If event has no backlinks, destroy (empty Event stored in database) ... this
            // is expensive to check at startup time, however, should happen in background or
            // during a "clean" operation
            event.rehydrate_backlinks(global, null);
            unlinked.add(event);
        }
        
        global.add_many(events);
        global.init_add_many_unlinked(unlinked);
    }
    
    public static void terminate() {
    }

    private static int64 view_comparator(void *a, void *b) {
        return ((MediaSource) ((ThumbnailView *) a)->get_source()).get_exposure_time()
            - ((MediaSource) ((ThumbnailView *) b)->get_source()).get_exposure_time() ;
    }
    
    private static bool view_comparator_predicate(DataObject object, Alteration alteration) {
        return alteration.has_detail("metadata", "exposure-time");
    }
    
    public static string? prep_event_name(string? name) {
        // Ticket #3218 - we tell prepare_input_text to 
        // allow empty strings, and if the rest of the app sees
        // one, it already knows to rename it to  
        // one of the default event names.
        return prepare_input_text(name, 
            PrepareInputTextOptions.NORMALIZE | PrepareInputTextOptions.VALIDATE | 
            PrepareInputTextOptions.INVALID_IS_NULL | PrepareInputTextOptions.STRIP |
            PrepareInputTextOptions.STRIP_CRLF, DEFAULT_USER_TEXT_INPUT_LENGTH);
    }
    
    // This is used by MediaSource to notify Event when it's joined.  Don't use this to manually attach a
    // a photo or video to an Event, use MediaSource.set_event().
    public void attach(MediaSource source) {
        view.add(new ThumbnailView(source));
    }
    
    public void attach_many(Gee.Collection<MediaSource> media) {
        Gee.ArrayList<ThumbnailView> views = new Gee.ArrayList<ThumbnailView>();
        foreach (MediaSource current_source in media)
            views.add(new ThumbnailView(current_source));
        
        view.add_many(views);
    }
    
    // This is used by internally by Photos and Videos to notify their parent Event as to when
    // they're leaving.  Don't use this manually to detach a MediaSource; instead use
    // MediaSource.set_event( )
    public void detach(MediaSource source) {
        view.remove_marked(view.mark(view.get_view_for_source(source)));
    }
    
    public void detach_many(Gee.Collection<MediaSource> media) {
        Gee.ArrayList<ThumbnailView> views = new Gee.ArrayList<ThumbnailView>();
        foreach (MediaSource current_source in media) {
            ThumbnailView? view = (ThumbnailView?) view.get_view_for_source(current_source);
            if (view != null)
                views.add(view);
        }
        
        view.remove_marked(view.mark_many(views));
    }
    
    // TODO: A preferred way to do this is for ContainerSource to have an abstract interface for
    // obtaining the DataCollection in the ContainerSource of all the media objects.  Then,
    // ContinerSource could offer this helper class.
    public bool contains_media_type(string media_type) {
        foreach (MediaSource media in get_media()) {
            if (media.get_typename() == media_type)
                return true;
        }
        
        return false;
    }
    
    private Gee.ArrayList<MediaSource> views_to_media(Gee.Iterable<DataObject> views) {
        Gee.ArrayList<MediaSource> media = new Gee.ArrayList<MediaSource>();
        foreach (DataObject object in views)
            media.add((MediaSource) ((DataView) object).get_source());
        
        return media;
    }
    
    private void on_media_added(Gee.Iterable<DataObject> added) {
        Gee.Collection<MediaSource> media = views_to_media(added);
        global.notify_container_contents_added(this, media, relinking);
        global.notify_container_contents_altered(this, media, relinking, null, false);
        
        notify_altered(new Alteration.from_list("contents:added, metadata:time"));
    }
    
    // Event needs to know whenever a media source is removed from the system to update the event
    private void on_media_removed(Gee.Iterable<DataObject> removed) {
        Gee.ArrayList<MediaSource> media = views_to_media(removed);
        
        global.notify_container_contents_removed(this, media, unlinking);
        global.notify_container_contents_altered(this, null, false, media, unlinking);
        
        // update primary source if it's been removed (and there's one to take its place)
        foreach (MediaSource current_source in media) {
            if (current_source == primary_source) {
                if (get_media_count() > 0)
                    set_primary_source((MediaSource) view.get_first_unrejected().get_source());
                else
                    release_primary_source();
                
                break;
            }
        }
        
        // evaporate event if no more media in it; do not touch thereafter
        if (get_media_count() == 0) {
            global.evaporate(this);
            
            // as it's possible (highly likely, in fact) that all refs to the Event object have
            // gone out of scope now, do NOT touch this, but exit immediately
            return;
        }
        
        notify_altered(new Alteration.from_list("contents:removed, metadata:time"));
    }
    
    private void on_media_destroyed(DataSource source) {
        ThumbnailView? thumbnail_view = (ThumbnailView) view.get_view_for_source(source);
        if (thumbnail_view != null)
            view.remove_marked(view.mark(thumbnail_view));
    }
    
    public override void notify_relinking(SourceCollection sources) {
        assert(get_media_count() > 0);
        
        // If the primary source was lost in the unlink, reestablish it now.
        if (primary_source == null)
            set_primary_source((MediaSource) view.get_first_unrejected().get_source());
        
        base.notify_relinking(sources);
    }

    /** @brief This gets called when one or more media items inside this
     *  event gets modified in some fashion. If the media item's date changes
     *  and the event was previously undated, the name of the event needs to
     *  change as well; all of that happens automatically in here.
     *
     *  In addition, if the _rating_ of one or more media items has changed,
     *  the thumbnail of this event may need to change, as the primary
     *  image may have been rejected and should not be the thumbnail anymore.
     */
    private void on_media_altered(Gee.Map<DataObject, Alteration> items) {
        bool should_remake_thumb = false;
         
        foreach (Alteration alteration in items.values) {
            if (alteration.has_detail("metadata", "exposure-time")) {
                
                string alt_list = "metadata:time";
                
                if(!has_name())
                    alt_list += (", metadata:name");

                notify_altered(new Alteration.from_list(alt_list));
                
                break;
            }
            
            if (alteration.has_detail("metadata", "rating"))
                should_remake_thumb = true;
        }
        
        if (should_remake_thumb) {
            // check whether we actually need to remake this thumbnail...
            if ((get_primary_source() == null) || (get_primary_source().get_rating() == Rating.REJECTED)) {
                // yes, rejected - drop it and get a new one...
                set_primary_source((MediaSource) view.get_first_unrejected().get_source());
            }

            // ...otherwise, if the primary source wasn't rejected, just leave it alone.
        }
    }
    
    // This creates an empty event with a primary source.  NOTE: This does not add the source to
    // the event.  That must be done manually.
    public static Event? create_empty_event(MediaSource source) {
        try {
            Event event = new Event(EventTable.get_instance().create(source.get_source_id(), null));
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
        return (LibraryPhoto.global.has_backlink(get_backlink()) ||
            Video.global.has_backlink(get_backlink()));
    }
    
    public SourceBacklink get_backlink() {
        return new SourceBacklink.from_source(this);
    }
    
    public void break_link(DataSource source) {
        unlinking = true;
        
        ((MediaSource) source).set_event(null);
        
        unlinking = false;
    }
    
    public void break_link_many(Gee.Collection<DataSource> sources) {
        unlinking = true;
        
        Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<Video> videos = new Gee.ArrayList<Video>();
        MediaSourceCollection.filter_media((Gee.Collection<MediaSource>) sources, photos, videos);
        
        try {
            MediaSource.set_many_to_event(photos, null, LibraryPhoto.global.transaction_controller);
        } catch (Error err) {
            AppWindow.error_message("%s".printf(err.message));
        }
        
        try {
            MediaSource.set_many_to_event(videos, null, Video.global.transaction_controller);
        } catch (Error err) {
            AppWindow.error_message("%s".printf(err.message));
        }
        
        unlinking = false;
    }
    
    public void establish_link(DataSource source) {
        relinking = true;
        
        ((MediaSource) source).set_event(this);
        
        relinking = false;
    }
    
    public void establish_link_many(Gee.Collection<DataSource> sources) {
        relinking = true;
        
        Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<Video> videos = new Gee.ArrayList<Video>();
        MediaSourceCollection.filter_media((Gee.Collection<MediaSource>) sources, photos, videos);
        
        try {
            MediaSource.set_many_to_event(photos, this, LibraryPhoto.global.transaction_controller);
        } catch (Error err) {
            AppWindow.error_message("%s".printf(err.message));
        }
        
        try {
            MediaSource.set_many_to_event(videos, this, Video.global.transaction_controller);
        } catch (Error err) {
            AppWindow.error_message("%s".printf(err.message));
        }
        
        relinking = false;
    }
    
    private void update_indexable_keywords() {
        string[] components = new string[3];
        int i = 0;

        string? rawname = get_raw_name();
        if (rawname != null)
            components[i++] = rawname;

        string? comment = get_comment();
        if (comment != null)
            components[i++] = comment;

        if (i == 0)
            indexable_keywords = null;
        else {
            components[i] = null;
            indexable_keywords = prepare_indexable_string(string.joinv(" ", components));
        }
    }
    
    public unowned string? get_indexable_keywords() {
        return indexable_keywords;
    }
    
    public bool is_in_starting_day(time_t time) {
        // it's possible the Event ref is held although it's been emptied
        // (such as the user removing items during an import, when events
        // are being generate on-the-fly) ... return false here and let
        // the caller make a new one
        if (view.get_count() == 0)
            return false;
        
        // media sources are stored in ViewCollection from earliest to latest
        MediaSource earliest_media = (MediaSource) ((DataView) view.get_at(0)).get_source();
        Time earliest_tm = Time.local(earliest_media.get_exposure_time());
        
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
        if (earliest_tm.hour < EVENT_BOUNDARY_HOUR) {
            debug("Hour before boundary, shifting back one day");
            start_boundary -= TIME_T_DAY;
        }
        
        time_t end_boundary = (start_boundary + TIME_T_DAY - 1);
        
        return time >= start_boundary && time <= end_boundary;
    }
    
    // This method attempts to add a media source to an event in the supplied list that it would
    // naturally fit into (i.e. its exposure is within the boundary day of the earliest event
    // photo).  Otherwise, a new Event is generated and the source is added to it and the list.
    private static Event? generate_event(MediaSource media, ViewCollection events_so_far,
        string? event_name, out bool new_event) {
        time_t exposure_time = media.get_exposure_time();
        
        if (exposure_time == 0 && event_name == null) {
            debug("Skipping event assignment to %s: no exposure time and no event name", media.to_string());
            new_event = false;

            return null;
        }

        int count = events_so_far.get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            Event event = (Event) ((EventView) events_so_far.get_at(ctr)).get_source();
            
            if ((event_name != null && event.has_name() && event_name == event.get_name())
                || event.is_in_starting_day(exposure_time)) {
                new_event = false;
                
                return event;
            }
        }
        
        // no Event so far fits the bill for this photo or video, so create a new one
        try {
            Event event = new Event(EventTable.get_instance().create(media.get_source_id(), null));
            if (event_name != null)
                event.rename(event_name);
            
            events_so_far.add(new EventView(event));
            
            new_event = true;
            return event;
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        new_event = false;
        
        return null;
    }
    
    public static void generate_single_event(MediaSource media, ViewCollection events_so_far,
        string? event_name = null) {
        // do not replace existing assignments
        if (media.get_event() != null)
            return;
        
        bool new_event;
        Event? event = generate_event(media, events_so_far, event_name, out new_event);
        if (event == null)
            return;

        media.set_event(event);
        
        if (new_event)
            global.add(event);
    }
    
    public static void generate_many_events(Gee.Collection<MediaSource> sources, ViewCollection events_so_far) {
        Gee.Collection<Event> to_add = new Gee.ArrayList<Event>();
        foreach (MediaSource media in sources) {
            // do not replace existing assignments
            if (media.get_event() != null)
                continue;
            
            bool new_event;
            Event? event = generate_event(media, events_so_far, null, out new_event);
            if (event == null)
                continue;
            
            media.set_event(event);
            
            if (new_event)
                to_add.add(event);
        }
        
        if (to_add.size > 0)
            global.add_many(to_add);
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
        string? datestring = get_formatted_daterange();
        
        return !is_string_empty(datestring) ? datestring : _("Event %s").printf(event_id.id.to_string());
    }
    
    public string? get_formatted_daterange() {
        time_t start_time = get_start_time();
        time_t end_time = get_end_time();
        
        if (end_time == 0 && start_time == 0)
            return null;
        
        if (end_time == 0 && start_time != 0)
            return format_local_date(Time.local(start_time));
        
        Time start = Time.local(start_time);
        Time end = Time.local(end_time);
        
        if (start.day == end.day && start.month == end.month && start.day == end.day)
            return format_local_date(Time.local(start_time));
        
        return format_local_datespan(start, end);
    }
    
    public string? get_raw_name() {
        return raw_name;
    }
    
    public override string? get_comment() {
        return comment;
    }
    
    public bool rename(string? name) {
        string? new_name = prep_event_name(name);
        
        // Allow rename to date but it should go dynamic, so set name to ""
        if (new_name == get_formatted_daterange()) {
            new_name = "";
        }
        
        bool renamed = event_table.rename(event_id, new_name);
        if (renamed) {
            raw_name = new_name;
            update_indexable_keywords();
            notify_altered(new Alteration.from_list("metadata:name, indexable:keywords"));
        }
        
        return renamed;
    }
    
    public override bool set_comment(string? comment) {
        string? new_comment = MediaSource.prep_comment(comment);
        
        bool committed = event_table.set_comment(event_id, new_comment);
        if (committed) {
            this.comment = new_comment;
            update_indexable_keywords();
            notify_altered(new Alteration.from_list("metadata:comment, indexable:keywords"));
        }
        
        return committed;
    }
    
    public time_t get_creation_time() {
        return event_table.get_time_created(event_id);
    }
    
    public override time_t get_start_time() {
        // Because the ViewCollection is sorted by a DateComparator, the start time is the
        // first item.  However, we keep looking if it has no start time.
        int count = view.get_count();
        for (int i = 0; i < count; i++) {
            time_t time = ((MediaSource) (((DataView) view.get_at(i)).get_source())).get_exposure_time();
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
       
        return  ((MediaSource) (((DataView) view.get_at(count - 1)).get_source())).get_exposure_time();
    }
    
    public override uint64 get_total_filesize() {
        uint64 total = 0;
        foreach (MediaSource current_source in get_media()) {
            total += current_source.get_filesize();
        }
        
        return total;
    }
    
    public override int get_media_count() {
        return view.get_count();
    }
    
    public override Gee.Collection<MediaSource> get_media() {
        return (Gee.Collection<MediaSource>) view.get_sources();
    }
    
    public void mirror_photos(ViewCollection view, CreateView mirroring_ctor) {
        view.mirror(this.view, mirroring_ctor, null);
    }
    
    private void on_primary_thumbnail_altered() {
        notify_thumbnail_altered();
    }

    public MediaSource get_primary_source() {
        return primary_source;
    }
    
    public bool set_primary_source(MediaSource source) {
        assert(view.has_view_for_source(source));
        
        bool committed = event_table.set_primary_source_id(event_id, source.get_source_id());
        if (committed) {
            // switch to the new media source
            if (primary_source != null)
                primary_source.thumbnail_altered.disconnect(on_primary_thumbnail_altered);

            primary_source = source;
            primary_source.thumbnail_altered.connect(on_primary_thumbnail_altered);
            
            notify_thumbnail_altered();
        }
        
        return committed;
    }
    
    private void release_primary_source() {
        if (primary_source == null)
            return;
        
        primary_source.thumbnail_altered.disconnect(on_primary_thumbnail_altered);
        primary_source = null;
    }
    
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return primary_source != null ? primary_source.get_thumbnail(scale) : null;
    }
    
    public Gdk.Pixbuf? get_preview_pixbuf(Scaling scaling) {
        try {
            return get_primary_source().get_preview_pixbuf(scaling);
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
        
        // mark all photos and videos for this event as now event-less
        PhotoTable.get_instance().drop_event(event_id);
        VideoTable.get_instance().drop_event(event_id);
        
        base.destroy();
   }
}
