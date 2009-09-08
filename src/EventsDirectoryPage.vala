/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

class EventDirectoryItem : LayoutItem, EventSource {
    public const int SCALE =
        ThumbnailCache.MEDIUM_SCALE + ((ThumbnailCache.BIG_SCALE - ThumbnailCache.MEDIUM_SCALE) / 2);
    
    public Event event;

    public EventDirectoryItem(Event event) {
        this.event = event;
        
        event.altered += update_display;
        
        update_display();
    }

    public time_t get_start_time() {
        return event.get_start_time();
    }

    public time_t get_end_time() {
        return event.get_end_time();
    }

    public Gee.Iterable<PhotoSource> get_photos() {
        return event.get_photos();
    }

    public int get_photo_count() {
        return event.get_photo_count();
    }
    
    public uint64 get_total_filesize() {
        return event.get_total_filesize();
    }
    
    private void update_display() {
        set_title(event.get_name());
        set_image(event.get_primary_photo().get_preview_pixbuf(Scaling.for_best_fit(SCALE)));
    }
}

public class EventsDirectoryPage : CheckerboardPage {
    private class CompareEventItem : Comparator<EventDirectoryItem> {
        private int sort;
        
        public CompareEventItem(int sort) {
            assert(sort == LibraryWindow.SORT_EVENTS_ORDER_ASCENDING 
                || sort == LibraryWindow.SORT_EVENTS_ORDER_DESCENDING);
            
            this.sort = sort;
        }
        
        public override int64 compare(EventDirectoryItem a, EventDirectoryItem b) {
            int64 start_a = (int64) a.event.get_start_time();
            int64 start_b = (int64) b.event.get_start_time();
            
            switch (sort) {
                case LibraryWindow.SORT_EVENTS_ORDER_ASCENDING:
                    return start_a - start_b;
                
                case LibraryWindow.SORT_EVENTS_ORDER_DESCENDING:
                default:
                    return start_b - start_a;
            }
        }
    }
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, null },
        
        { "ViewMenu", null, "_View", null, null, on_view_menu },

        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();

    public EventsDirectoryPage() {
        base("Events");
        
        // watch for creation of new events
        Event.notifier.added += on_added_event;
        
        init_ui_start("events_directory.ui", "EventsDirectoryActionGroup", ACTIONS);
        init_ui_bind("/EventsDirectoryMenuBar");
        
        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        set_layout_comparator(new CompareEventItem(LibraryWindow.get_app().get_events_sort()));

        // add all events to the page
        Gee.ArrayList<Event> events = Event.fetch_all();
        foreach (Event event in events)
            add_event(event);
    }
    
    public override void realize() {
        refresh();
        
        base.realize();
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void switched_to() {
        base.switched_to();
        
        refresh();
    }
    
    public override void on_item_activated(LayoutItem item) {
        EventDirectoryItem event = (EventDirectoryItem) item;
        LibraryWindow.get_app().switch_to_event(event.event);
    }
    
    private EventDirectoryItem? get_fullscreen_item() {
        Gee.Iterable<LayoutItem> iter = null;
        
        // use first selected item, otherwise use first item
        if (get_selected_count() > 0) {
            iter = get_selected();
        } else {
            iter = get_items();
        }
        
        foreach (LayoutItem item in iter)
            return (EventDirectoryItem) item;
        
        return null;
    }
    
    public EventPage? get_fullscreen_event() {
        EventDirectoryItem item = get_fullscreen_item();

        // Yeah, this sucks.  We can do better.
        return (item != null) ? LibraryWindow.get_app().load_event_page(item.event) : null;
    }
    
    public override LayoutItem? get_fullscreen_photo() {
        EventPage page = get_fullscreen_event();
        
        return (page != null) ? page.get_fullscreen_photo() : null;
    }

    public void add_event(Event event) {
        EventDirectoryItem item = new EventDirectoryItem(event);
        add_item(item);
        
        event.removed += on_event_removed;
    }
    
    public void notify_sort_changed(int sort) {
        set_layout_comparator(new CompareEventItem(sort));
        refresh();
    }
    
    private void on_view_menu() {
        set_item_sensitive("/EventsDirectoryMenuBar/ViewMenu/Fullscreen", get_count() > 0);
    }
    
    private void on_added_event(Event event) {
        add_event(event);
        
        refresh();
    }
    
    private void on_event_removed(Event event) {
        // have to remove the item outside the iterator
        EventDirectoryItem to_remove = null;
        foreach (LayoutItem item in get_items()) {
            EventDirectoryItem event_item = (EventDirectoryItem) item;
            if (event_item.event.equals(event)) {
                to_remove = event_item;
                
                break;
            }
        }
        
        if (to_remove != null)
            remove_item(to_remove);
    }
}

public class EventPage : CollectionPage {
    public Event page_event;
    
    private const Gtk.ActionEntry[] ACTIONS = {
        { "MakePrimary", Resources.MAKE_PRIMARY, "Make _Key Photo for Event", null, null, on_make_primary }
    };

    public EventPage(Event page_event) {
        base(page_event.get_name(), "event.ui", ACTIONS);
        
        this.page_event = page_event;

        // load in all the photos associated with this event
        Gee.Iterable<PhotoSource> photos = page_event.get_photos();
        foreach (PhotoSource source in photos)
            add_photo((LibraryPhoto) source);
    }
    
    protected override void on_photos_menu() {
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/MakePrimary", get_selected_count() == 1);
        
        base.on_photos_menu();
    }
    
    private void on_make_primary() {
        assert(get_selected_count() == 1);
        
        // iterate to first one, use that, bail out
        foreach (LayoutItem item in get_selected()) {
            page_event.set_primary_photo(((Thumbnail) item).get_photo());
            
            break;
        }
    }
}

