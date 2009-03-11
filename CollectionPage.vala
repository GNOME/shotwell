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
        
        add(viewport);
    }
    
    public CollectionPage() {
    }
    
    public void add_photo(File file) {
        Thumbnail thumbnail = new Thumbnail(file);
        
        thumbnailList.append(thumbnail);
        thumbCount++;
        
        attach_thumbnail(thumbnail);

        layoutTable.show_all();
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
        message("v.width=%d width=%d", v.allocation.width, allocation.width);
        
        int newCols = allocation.width / (Thumbnail.THUMB_WIDTH + THUMB_X_PADDING + THUMB_X_PADDING);
        if (newCols < 1)
            newCols = 1;

        if (cols == newCols)
            return;

        cols = newCols;
        int rows = (thumbCount / cols) + 1;
        
        message("rows=%d cols=%d", rows, cols);
        
        layoutTable.resize(rows, cols);
        
        currentX = 0;
        currentY = 0;
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            layoutTable.remove(thumbnail);
            attach_thumbnail(thumbnail);
        }
    }
}

