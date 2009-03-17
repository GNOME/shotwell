Gdk.Color parse_color(string color) {
    Gdk.Color c;
    if (!Gdk.Color.parse(color, out c))
        error("can't parse color");
    return c;
}

public class CollectionPage : Gtk.ScrolledWindow {
    public static const int THUMB_X_PADDING = 20;
    public static const int THUMB_Y_PADDING = 20;
    public static const string BG_COLOR = "#777";
    
    private unowned Sqlite.Database db = null;
    private PhotoTable photoTable = null;
    private Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    private Gtk.Table layoutTable = new Gtk.Table(0, 0, false);
    private List<Thumbnail> thumbnailList = new List<Thumbnail>();
    private int currentX = 0;
    private int currentY = 0;
    private int cols = 0;
    private int thumbCount = 0;
    
    construct {
        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        // set table column and row padding ... this is done globally rather than per-thumbnail
        layoutTable.set_col_spacings(THUMB_X_PADDING);
        layoutTable.set_row_spacings(THUMB_Y_PADDING);

        // need to manually build viewport to set its background color
        viewport.add(layoutTable);
        viewport.modify_bg(Gtk.StateType.NORMAL, parse_color(BG_COLOR));

        // notice that this is capturing the viewport's resize, not the scrolled window's,
        // as that's what interesting when laying out the photos
        viewport.size_allocate += on_resize;

        // This signal handler is to load the collection page with photos when its viewport is
        // realized ... this is because if the collection page is loaded during construction, the
        // viewport does not respond properly to the layout table's resizing and it winds up tagging
        // extra space to the tail of the view.  This allows us to wait until the viewport is realized
        // and responds properly to resizing
        viewport.realize += on_viewport_realized;
        
        add(viewport);
    }
    
    public CollectionPage(Sqlite.Database db) {
        this.db = db;
        
        photoTable = new PhotoTable(db);
    }
    
    public void add_photo(File file) {
        Thumbnail thumbnail = new Thumbnail(file);
        
        thumbnailList.append(thumbnail);
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
        
        message("repack() rows=%d cols=%d", rows, cols);
        
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
    
    private void on_resize(Gtk.Viewport v, Gdk.Rectangle allocation) {
        int newCols = allocation.width / (Thumbnail.THUMB_WIDTH + THUMB_X_PADDING + THUMB_X_PADDING);
        if (newCols < 1)
            newCols = 1;

        if (cols != newCols) {
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

    private void on_viewport_realized() {
        File[] photoFiles = photoTable.get_photo_files();
        foreach (File file in photoFiles) {
            add_photo(file);
        }
    }
}

