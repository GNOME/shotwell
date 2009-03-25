
public class CollectionLayout : Gtk.Layout {
    private Gee.ArrayList<Thumbnail> thumbnails = new Gee.ArrayList<Thumbnail>();
    private int currentX = 0;
    private int currentY = 0;
    private int rowTallest = 0;

    public CollectionLayout() {
        modify_bg(Gtk.StateType.NORMAL, parse_color(CollectionPage.BG_COLOR));
        expose_event += on_expose;
        size_allocate += on_resize;
    }
    
    public void append(Thumbnail thumbnail) {
        thumbnails.add(thumbnail);

        // need to do this to have its size requisitioned
        thumbnail.show_all();

        Gtk.Requisition req;
        thumbnail.size_request(out req);
        
        if (rowTallest < req.height)
            rowTallest = req.height;

        // carriage return
        if (currentX + req.width > allocation.width) {
            currentX = 0;
            currentY += rowTallest;
            rowTallest = 0;
        }

        put(thumbnail, currentX, currentY);
        
        currentX += req.width;
    }
    
    public void remove_thumbnail(Thumbnail thumbnail) {
        thumbnails.remove(thumbnail);
        remove(thumbnail);
    }
    
    public void refresh() {
        currentX = 0;
        currentY = 0;
        rowTallest = 0;

        foreach (Thumbnail thumbnail in thumbnails) {
            Gtk.Requisition req;
            thumbnail.size_request(out req);
                
            if (req.height > rowTallest)
                rowTallest = req.height;
                
            // carriage return
            if (currentX + req.width > allocation.width) {
                currentX = 0;
                currentY += rowTallest;
                rowTallest = 0;
            }

            move(thumbnail, currentX, currentY);

            currentX += req.width;
        }
        
        set_size(allocation.width, currentY + rowTallest);
    }

    private int lastWidth = 0;
    
    private void on_resize() {
        // only refresh if the viewport width has changed
        if (allocation.width != lastWidth) {
            lastWidth = allocation.width;
            refresh();
        }
    }
    
    private bool on_expose(CollectionLayout cl, Gdk.EventExpose event) {
        Gdk.Rectangle visibleRect = Gdk.Rectangle();
        visibleRect.x = (int) get_hadjustment().get_value();
        visibleRect.y = (int) get_vadjustment().get_value();
        visibleRect.width = allocation.width;
        visibleRect.height = allocation.height;

        /*
        debug("on_client_exposed x:%d y:%d w:%d h:%d", visibleRect.x, visibleRect.y,
            visibleRect.width, visibleRect.height);
        */
        
        Gdk.Rectangle bitbucket = Gdk.Rectangle();
        int exposedCount = 0;
        int unexposedCount = 0;

        foreach (Thumbnail thumbnail in thumbnails) {
            if (visibleRect.intersect((Gdk.Rectangle) thumbnail.allocation, bitbucket)) {
                thumbnail.exposed();
                exposedCount++;
            } else {
                thumbnail.unexposed();
                unexposedCount++;
            }
        }
        
        debug("exposed:%d unexposed:%d", exposedCount, unexposedCount);

        return false;
    }
}
