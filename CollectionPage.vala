Gdk.Color parse_color(string color) {
    Gdk.Color c;
    if (!Gdk.Color.parse(color, out c))
        error("can't parse color");
    return c;
}

public class CollectionPage : Gtk.ScrolledWindow {
    private Gtk.Table layoutTable = new Gtk.Table(0, 0, false);
    private List<Thumbnail> thumbnailList = new List<Thumbnail>();
    private int currentX = 0;
    private int currentY = 0;
    private int cols = 1;
    private int thumbCount = 0;
    
    construct {
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        size_allocate += on_resize;
        
        Gtk.Viewport viewport = new Gtk.Viewport(null, null);
        viewport.add(layoutTable);
        viewport.modify_bg(Gtk.StateType.NORMAL, parse_color("#777"));

        add(viewport);
    }
    
    public CollectionPage() {
    }
    
    public void add_photo(File file) {
        Thumbnail thumbnail = new Thumbnail(file);
        
        thumbnailList.append(thumbnail);
        
        layoutTable.attach(thumbnail, currentX, currentX + 1, currentY, currentY + 1, 
            Gtk.AttachOptions.SHRINK | Gtk.AttachOptions.EXPAND, 
            Gtk.AttachOptions.SHRINK, 
            20, 20);

        if (++currentX >= cols) {
            currentX = 0;
            currentY++;
        }
        
        thumbCount++;
        
        show_all();
    }
    
    private void on_resize(CollectionPage s, Gdk.Rectangle allocation) {
        int newCols = allocation.width / (Thumbnail.THUMB_WIDTH + 20 + 20);
        if (newCols < 1)
            newCols = 1;

        if (cols == newCols)
            return;

        int rows = (thumbCount / newCols) + 1;
        
        message("rows=%d cols=%d", rows, newCols);
        
        cols = newCols;
        
        layoutTable.resize(rows, cols);
        
        currentX = 0;
        currentY = 0;
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            layoutTable.remove(thumbnail);
            layoutTable.attach(thumbnail, currentX, currentX + 1, currentY, currentY + 1,
                Gtk.AttachOptions.SHRINK | Gtk.AttachOptions.EXPAND,
                Gtk.AttachOptions.SHRINK,
                20, 20);
            if(++currentX >= cols) {
                currentX = 0;
                currentY++;
            }
        }
    }
}

