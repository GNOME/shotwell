
public class DirectoryItem : LayoutItem {
    public static const Gdk.InterpType INTERP = Gdk.InterpType.BILINEAR;
    public static const int SCALE =
        ThumbnailCache.MEDIUM_SCALE + ((ThumbnailCache.BIG_SCALE - ThumbnailCache.MEDIUM_SCALE) / 2);
    
    public PhotoID photo_id;
    public EventID event_id;
    
    public DirectoryItem(EventID event_id) {
        this.event_id = event_id;
        
        on_backing_changed();
    }
    
    public override void on_backing_changed() {
        EventTable event_table = new EventTable();
        
        title.set_text(event_table.get_name(event_id));

        photo_id = event_table.get_primary_photo(event_id);
        assert(photo_id.is_valid());

        PhotoTable photo_table = new PhotoTable();        
        Exif.Orientation orientation = photo_table.get_orientation(photo_id);

        Gdk.Pixbuf pixbuf = ThumbnailCache.fetch_scaled(photo_id, SCALE, INTERP);
        pixbuf = rotate_to_exif(pixbuf, orientation);
        image.set_from_pixbuf(pixbuf);
        image.set_size_request(pixbuf.get_width(), pixbuf.get_height());
    }
}

public class EventsDirectoryPage : CheckerboardPage {
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, null },

        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    private EventTable event_table = new EventTable();
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();

    public EventsDirectoryPage() {
        init_ui_start("events_directory.ui", "EventsDirectoryActionGroup", ACTIONS);
        init_ui_bind("/EventsDirectoryMenuBar");
        
        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void on_item_activated(LayoutItem item) {
        DirectoryItem event = (DirectoryItem) item;
        AppWindow.get_instance().switch_to_event(event.event_id);
    }
    
    public void add_event(EventID event_id) {
        DirectoryItem item = new DirectoryItem(event_id);
        add_item(item);
    }
    
    public override void switched_to() {
        remove_all();
        
        EventID[] events = event_table.get_events();
        foreach (EventID event_id in events) {
            add_event(event_id);
        }
        
        show_all();

        refresh();
    }
}

public class EventPage : CollectionPage {
    public EventID event_id;
    
    public EventPage(EventID event_id, PhotoID[] photos) {
        base(photos);
        
        this.event_id = event_id;
    }
}

