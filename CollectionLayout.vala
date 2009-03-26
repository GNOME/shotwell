
public class CollectionLayout : Gtk.Layout {
    public static const int TOP_PADDING = 32;
    public static const int BOTTOM_PADDING = 32;
    public static const int ROW_GUTTER_PADDING = 32;

    // the following are minimums, as the pads and gutters expand to fill up the window width
    public static const int LEFT_PADDING = 32;
    public static const int RIGHT_PADDING = 32;
    public static const int COLUMN_GUTTER_PADDING = 32;
    
    private Gee.ArrayList<Thumbnail> thumbnails = new Gee.ArrayList<Thumbnail>();

    public CollectionLayout() {
        modify_bg(Gtk.StateType.NORMAL, parse_color(CollectionPage.BG_COLOR));
        expose_event += on_expose;
        size_allocate += on_resize;
    }
    
    public void append(Thumbnail thumbnail) {
        thumbnails.add(thumbnail);

        // need to do this to have its size requisitioned in refresh()
        thumbnail.show_all();
    }
    
    public void remove_thumbnail(Thumbnail thumbnail) {
        thumbnails.remove(thumbnail);
        remove(thumbnail);
    }
    
    public Thumbnail? get_thumbnail_at(double xd, double yd) {
        int x = (int) xd;
        int y = (int) yd;

        foreach (Thumbnail thumbnail in thumbnails) {
            Gtk.Allocation alloc = thumbnail.allocation;
            if ((x >= alloc.x) && (y >= alloc.y) && (x <= (alloc.x + alloc.width))
                && (y <= (alloc.y + alloc.height))) {
                return thumbnail;
            }
        }
        
        return null;
    }
    
    public void refresh() {
        // don't bother until layout is of some appreciable size
        if (allocation.width <= 1)
            return;
            
        // Step 1: Determine the widest row in the layout, and from it the number of columns
        int x = LEFT_PADDING;
        int col = 0;
        int maxCols = 0;
        int rowWidth = 0;
        int widestRow = 0;

        foreach (Thumbnail thumbnail in thumbnails) {
            // perform size requests first time through, but not thereafter
            Gtk.Requisition req;
            thumbnail.size_request(out req);
                
            // carriage return (i.e. this thumbnail will overflow the view)
            if ((x + req.width + RIGHT_PADDING) > allocation.width) {
                if (rowWidth > widestRow) {
                    widestRow = rowWidth;
                    maxCols = col;
                }
                
                col = 0;
                x = LEFT_PADDING;
                rowWidth = 0;
            }
            
            x += req.width + COLUMN_GUTTER_PADDING;
            rowWidth += req.width;
            
            col++;
        }
        
        // account for dangling last row
        if (rowWidth > widestRow) {
            widestRow = rowWidth;
            maxCols = col;
        }
        
        // Step 2: Now that the number of columns is known, find the maximum height for each row
        // and the maximum width for each column
        int row = 0;
        int tallest = 0;
        int totalWidth = 0;
        col = 0;
        int[] columnWidths = new int[maxCols];
        int[] rowHeights = new int[(thumbnails.size / maxCols) + 1];
        
        foreach (Thumbnail thumbnail in thumbnails) {
            Gtk.Requisition req = thumbnail.requisition;
            
            if (req.height > tallest)
                tallest = req.height;
            
            // store largest thumb size of each column as well as track the total width of the
            // layout (which is the sum of the width of each column)
            if (columnWidths[col] < req.width) {
                totalWidth -= columnWidths[col];
                columnWidths[col] = req.width;
                totalWidth += req.width;
            }

            if (++col >= maxCols) {
                col = 0;
                rowHeights[row++] = tallest;
                tallest = 0;
            }
        }
        
        // account for final dangling row
        if (col != 0)
            rowHeights[row] = tallest;

        // Step 3: Calculate the gutter between the thumbnails as being equidistant of the
        // remaining space (adding one gutter to account for the right-hand one)
        int gutter = (allocation.width - totalWidth) / (maxCols + 1);

        /*
        debug("refresh() w:%d widestRow:%d totalWidth:%d cols:%d gutter:%d", 
            allocation.width, widestRow, totalWidth, maxCols, gutter);
        */

        // Step 4: Lay out the thumbnails in the space using all the information gathered
        x = gutter;
        int y = TOP_PADDING;
        col = 0;
        row = 0;

        foreach (Thumbnail thumbnail in thumbnails) {
            Gtk.Requisition req = thumbnail.requisition;

            // carriage return
            if (col >= maxCols) {
                x = gutter;
                y += rowHeights[row] + ROW_GUTTER_PADDING;
                col = 0;
                row++;
            }
            
            // this centers the thumbnail in the column
            int xpadding = (columnWidths[col] - req.width) / 2;
            assert(xpadding >= 0);
            
            // this bottom-aligns the thumbnail along the row
            int ypadding = (rowHeights[row] - req.height);
            assert(ypadding >= 0);
            
            // if thumbnail was recently appended, it needs to be put() rather than move()'d
            if (thumbnail.parent == this) {
                move(thumbnail, x + xpadding, y + ypadding);
            } else {
                put(thumbnail, x + xpadding, y + ypadding);
            }

            x += columnWidths[col] + gutter;
            col++;
        }
        
        // Step 5: Define the total size of the page as the size of the allocated width and
        // the height of all the thumbnails plus padding
        set_size(allocation.width, y + rowHeights[row] + BOTTOM_PADDING);
    }

    private int lastWidth = 0;
    
    private void on_resize() {
        // only refresh() if the viewport width has changed
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
        
        /*
        debug("exposed:%d unexposed:%d", exposedCount, unexposedCount);
        */

        return false;
    }
}
