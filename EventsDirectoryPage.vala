
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
        
        { "ViewMenu", null, "_View", null, null, on_view_menu },

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
    
    public void report_backing_changed(PhotoID photo_id) {
        int count = 0;
        foreach (LayoutItem item in get_items()) {
            DirectoryItem directory_item = (DirectoryItem) item;
            if (directory_item.photo_id.id == photo_id.id) {
                // should only be one, but do 'em all
                directory_item.on_backing_changed();
                count++;
            }
        }

        // in the field, do 'em all, but sanity check here at home
        assert(count <= 1);

        // if something changed, refresh, as the geometry could cause layout changes
        if (count > 0)
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
        { "MakePrimary", null, "Make _Primary", null, null, on_make_primary }
    };

    public EventPage(EventID event_id, PhotoID[] photos) {
        base(photos, "event.ui", ACTIONS);
        
        this.event_id = event_id;
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
            event_table.set_primary_photo(event_id, thumbnail.get_photo_id());
            
            break;
        }
    }
}

