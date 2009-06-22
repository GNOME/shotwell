
public class DirectoryItem : LayoutItem {
    public static const Gdk.InterpType INTERP = Gdk.InterpType.BILINEAR;
    public static const int SCALE =
        ThumbnailCache.MEDIUM_SCALE + ((ThumbnailCache.BIG_SCALE - ThumbnailCache.MEDIUM_SCALE) / 2);
    
    public EventID event_id;

    public DirectoryItem(EventID event_id, EventTable event_table) {
        this.event_id = event_id;
        
        title.set_text(event_table.get_name(event_id));
        
        PhotoID photo_id = event_table.get_primary_photo(event_id);
        assert(photo_id.is_valid());
        
        Photo photo = Photo.fetch(photo_id);
        Gdk.Pixbuf pixbuf = photo.get_thumbnail(SCALE);
        pixbuf = scale_pixbuf(pixbuf, SCALE, INTERP);

        image.set_from_pixbuf(pixbuf);
        image.set_size_request(pixbuf.get_width(), pixbuf.get_height());
    }
}

public class EventsDirectoryPage : CheckerboardPage {
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, null },
        
        { "ViewMenu", null, "_View", null, null, on_view_menu },

        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    private EventTable event_table = new EventTable();
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();

    public EventsDirectoryPage() {
        base("Events");
        
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
    
    public override LayoutItem? get_fullscreen_photo() {
        Gee.Iterable<LayoutItem> iter = null;
        
        // use first selected item, otherwise use first item
        if (get_selected_count() > 0) {
            iter = get_selected();
        } else {
            iter = get_items();
        }
        
        foreach (LayoutItem item in iter) {
            EventPage page = AppWindow.get_instance().find_event_page(((DirectoryItem) item).event_id);
            if (page != null)
                return page.get_fullscreen_photo();
        }
        
        return null;
    }
    
    public void add_event(EventID event_id) {
        DirectoryItem item = new DirectoryItem(event_id, event_table);
        add_item(item);
    }
    
    public override void switched_to() {
        base.switched_to();

        remove_all();
        
        Gee.ArrayList<EventID?> event_ids = event_table.get_events();
        foreach (EventID event_id in event_ids)
            add_event(event_id);
        
        show_all();

        refresh();
    }
    
    private void on_view_menu() {
        set_item_sensitive("/EventsDirectoryMenuBar/ViewMenu/Fullscreen", get_count() > 0);
    }
}

public class EventPage : CollectionPage {
    public EventID event_id;
    
    private EventTable event_table = new EventTable();
    
    private const Gtk.ActionEntry[] ACTIONS = {
        { "MakePrimary", Resources.MAKE_PRIMARY, "Make _Key Photo for Event", null, null, on_make_primary }
    };

    public EventPage(EventID event_id) {
        base("Event", "event.ui", ACTIONS);
        
        this.event_id = event_id;

        set_page_name(event_table.get_name(event_id));
    }
    
    protected override void on_photos_menu() {
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/MakePrimary", get_selected_count() == 1);
        
        base.on_photos_menu();
    }
    
    private void on_make_primary() {
        assert(get_selected_count() == 1);
        
        // iterate to first one, use that, bail out
        foreach (LayoutItem item in get_selected()) {
            Thumbnail thumbnail = (Thumbnail) item;
            event_table.set_primary_photo(event_id, thumbnail.get_photo().get_photo_id());
            
            break;
        }
    }
}

