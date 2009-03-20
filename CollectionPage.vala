
public class CollectionPage : Gtk.ScrolledWindow {
    public static const int THUMB_X_PADDING = 20;
    public static const int THUMB_Y_PADDING = 20;
    public static const string BG_COLOR = "#777";
    
    private PhotoTable photoTable = null;
    private Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    private Gtk.Table layoutTable = new Gtk.Table(0, 0, false);
    private Gee.ArrayList<Thumbnail> thumbnailList = new Gee.ArrayList<Thumbnail>();
    private int currentX = 0;
    private int currentY = 0;
    private int cols = 0;
    private int thumbCount = 0;
    private int scale = Thumbnail.DEFAULT_SCALE;
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] RIGHT_CLICK_ACTIONS = {
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove }
    };
    
    construct {
        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        // set table column and row padding ... this is done globally rather than per-thumbnail
        layoutTable.set_col_spacings(THUMB_X_PADDING);
        layoutTable.set_row_spacings(THUMB_Y_PADDING);
        
        Gtk.ActionGroup actionGroup = new Gtk.ActionGroup("CollectionPageActionGroup");
        actionGroup.add_actions(RIGHT_CLICK_ACTIONS, this);
        AppWindow.get_ui_manager().insert_action_group(actionGroup, 0);

        // need to manually build viewport to set its background color
        viewport.add(layoutTable);
        viewport.modify_bg(Gtk.StateType.NORMAL, parse_color(BG_COLOR));

        // notice that this is capturing the viewport's resize, not the scrolled window's,
        // as that's what interesting when laying out the photos
        viewport.size_allocate += on_viewport_resize;

        // This signal handler is to load the collection page with photos when its viewport is
        // realized ... this is because if the collection page is loaded during construction, the
        // viewport does not respond properly to the layout table's resizing and it winds up tagging
        // extra space to the tail of the view.  This allows us to wait until the viewport is realized
        // and responds properly to resizing
        viewport.realize += on_viewport_realized;

        // when the viewport is exposed, the thumbnails are informed when they are exposed (and
        // should be showing their image) and when they're unexposed (so they can destroy the image,
        // freeing up memory)
        viewport.expose_event += on_viewport_exposed;
        
        add(viewport);
        
        button_press_event += on_click;
    }
    
    public CollectionPage() {
        photoTable = new PhotoTable();
    }
    
    public void add_photo(PhotoID photoID, File file) {
        Thumbnail thumbnail = new Thumbnail(photoID, file, scale);
        
        thumbnailList.add(thumbnail);
        thumbCount++;
        
        attach_thumbnail(thumbnail);

        layoutTable.show_all();
    }
    
    public void remove_photo(Thumbnail thumbnail) {
        thumbnailList.remove(thumbnail);
        layoutTable.remove(thumbnail);
        
        assert(thumbCount > 0);
        thumbCount--;
    }
    
    public void repack() {
        int rows = (thumbCount / cols) + 1;
        
        debug("repack() scale=%d thumbCount=%d rows=%d cols=%d", scale, thumbCount, rows, cols);
        
        layoutTable.resize(rows, cols);

        currentX = 0;
        currentY = 0;

        foreach (Thumbnail thumbnail in thumbnailList) {
            layoutTable.remove(thumbnail);
            attach_thumbnail(thumbnail);
        }
    }
    
    private void attach_thumbnail(Thumbnail thumbnail) {
        layoutTable.attach(thumbnail, currentX, currentX + 1, currentY, currentY + 1,
            Gtk.AttachOptions.SHRINK | Gtk.AttachOptions.EXPAND,
            Gtk.AttachOptions.SHRINK | Gtk.AttachOptions.FILL,
            0, 0);

        if(++currentX >= cols) {
            currentX = 0;
            currentY++;
        }
    }
    
    private void on_viewport_resize(Gtk.Viewport v, Gdk.Rectangle allocation) {
        int newCols = allocation.width / (Thumbnail.get_max_width(scale) + (THUMB_X_PADDING * 2));
        if (newCols < 1)
            newCols = 1;
        
        if (cols != newCols) {
            debug("width:%d cols:%d", allocation.width, newCols);

            cols = newCols;
            repack();
        }
    }
    
    public Thumbnail? get_thumbnail_at(double xd, double yd) {
        int x = (int) xd;
        int y = (int) yd;

        int xadj = (int) viewport.get_hadjustment().get_value();
        int yadj = (int) viewport.get_vadjustment().get_value();
        
        x += xadj;
        y += yadj;
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            Gtk.Allocation alloc = thumbnail.allocation;
            if ((x >= alloc.x) && (y >= alloc.y) && (x <= (alloc.x + alloc.width))
                && (y <= (alloc.y + alloc.height))) {
                return thumbnail;
            }
        }
        
        return null;
    }
    
    public int get_count() {
        return thumbCount;
    }
    
    public void select_all() {
        foreach (Thumbnail thumbnail in thumbnailList) {
            thumbnail.select();
        }
    }
    
    public void unselect_all() {
        foreach (Thumbnail thumbnail in thumbnailList) {
            thumbnail.unselect();
        }
    }
    
    public Thumbnail[] get_selected() {
        Thumbnail[] thumbnails = new Thumbnail[0];
        foreach (Thumbnail thumbnail in thumbnailList) {
            if (thumbnail.is_selected())
                thumbnails += thumbnail;
        }
        
        return thumbnails;
    }
    
    public int get_selected_count() {
        int count = 0;
        foreach (Thumbnail thumbnail in thumbnailList) {
            if (thumbnail.is_selected())
                count++;
        }
        
        return count;
    }
    
    public void increase_thumb_size() {
        if (scale == Thumbnail.MAX_SCALE)
            return;
        
        scale += Thumbnail.SCALE_STEPPING;
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            thumbnail.resize(scale);
        }
        
        layoutTable.resize_children();
    }
    
    public void decrease_thumb_size() {
        if (scale == Thumbnail.MIN_SCALE)
            return;
        
        scale -= Thumbnail.SCALE_STEPPING;
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            thumbnail.resize(scale);
        }
        
        layoutTable.resize_children();
    }

    private void on_viewport_realized() {
        File[] photoFiles = photoTable.get_photo_files();
        foreach (File file in photoFiles) {
            PhotoID photoID = photoTable.get_id(file);
            add_photo(photoID, file);
        }
    }

    private bool on_viewport_exposed(Gtk.Viewport v, Gdk.EventExpose event) {
        // since expose events can stack up, wait until the last one to do the full
        // search
        if (event.count == 0)
            check_exposure();

        return false;
    }
    
    private bool on_click(CollectionPage c, Gdk.EventButton event) {
        switch (event.button) {
            case 1:
                return on_left_click(event);
            
            case 3:
                return on_right_click(event);
            
            default:
                return false;
        }
    }
        
    private bool on_left_click(Gdk.EventButton event) {
        // only interested in single-clicks presses for now
        if (event.type != Gdk.EventType.BUTTON_PRESS) {
            return false;
        }
        
        // mask out the modifiers we're interested in
        uint state = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
        
        Thumbnail thumbnail = get_thumbnail_at(event.x, event.y);
        if (thumbnail != null) {
            message("clicked on %s", thumbnail.get_file().get_basename());
            
            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK: {
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    thumbnail.toggle_select();
                } break;
                
                case Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                default: {
                    // a "raw" click deselects all thumbnails and selects the single chosen
                    unselect_all();
                    thumbnail.select();
                } break;
            }
        } else {
            // user clicked on "dead" area
            unselect_all();
        }

        return false;
    }
    
    private bool on_right_click(Gdk.EventButton event) {
        // only interested in single-clicks for now
        if (event.type != Gdk.EventType.BUTTON_PRESS) {
            return false;
        }
        
        Thumbnail thumbnail = get_thumbnail_at(event.x, event.y);
        if (thumbnail != null) {
            // this counts as a select
            unselect_all();
            thumbnail.select();

            Gtk.Menu contextMenu = (Gtk.Menu) AppWindow.get_ui_manager().get_widget("/CollectionRightClickMenu");
            contextMenu.popup(null, null, null, event.button, event.time);
            
            return true;
        } else {
            // clicked on a "dead" area
        }
        
        return false;
    }
    
    private void on_remove() {
        Thumbnail[] thumbnails = get_selected();
        foreach (Thumbnail thumbnail in thumbnails) {
            remove_photo(thumbnail);
            ThumbnailCache.big.remove(photoTable.get_id(thumbnail.get_file()));
            photoTable.remove(thumbnail.get_file());
        }
        
        repack();
    }
    
    private void check_exposure() {
        Gdk.Rectangle viewrect = Gdk.Rectangle();
        viewrect.x = (int) viewport.get_hadjustment().get_value();
        viewrect.y = (int) viewport.get_vadjustment().get_value();
        viewrect.width = viewport.allocation.width;
        viewrect.height = viewport.allocation.height;
        
        Gdk.Rectangle thumbrect = Gdk.Rectangle();
        Gdk.Rectangle bitbucket = Gdk.Rectangle();

        int exposedCount = 0;
        int unexposedCount = 0;
        foreach (Thumbnail thumbnail in thumbnailList) {
            Gtk.Allocation alloc = thumbnail.get_exposure();
            thumbrect.x = alloc.x;
            thumbrect.y = alloc.y;
            thumbrect.width = alloc.width;
            thumbrect.height = alloc.height;
            
            if (viewrect.intersect(thumbrect, bitbucket)) {
                thumbnail.exposed();
                exposedCount++;
            } else {
                thumbnail.unexposed();
                unexposedCount++;
            }
        }
        
        //message("%d exposed, %d unexposed", exposedCount, unexposedCount);
    }
}

