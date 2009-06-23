
public abstract class LayoutItem : Gtk.Alignment {
    public static const int LABEL_PADDING = 4;
    public static const int FRAME_PADDING = 4;
    public static const string TEXT_COLOR = "#FFF";
    public static const string SELECTED_COLOR = "#0FF";
    public static const string UNSELECTED_COLOR = "#FFF";
    
    // Due to the potential for thousands or tens of thousands of thumbnails being present in the
    // system, all widgets used here and by subclasses should be NOWINDOW widgets.
    protected Gtk.Image image = new Gtk.Image();
    protected Gtk.Label title = new Gtk.Label("");
    protected Gtk.Frame frame = new Gtk.Frame(null);
    
    private bool selected = false;
    private Gtk.VBox vbox = new Gtk.VBox(false, 0);
    private bool title_displayed = true;

    private int col = -1;
    private int row = -1;
    
    public LayoutItem() {
        // bottom-align everything
        set(0, 1, 0, 0);
        
        title.set_use_underline(false);
        title.set_justify(Gtk.Justification.LEFT);
        title.set_alignment(0, 0);
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(TEXT_COLOR));
        
        Gtk.Widget panel = get_control_panel();

        // store everything in a vbox, with the expandable image on top followed by a widget
        // on the bottom for display and controls
        vbox.set_border_width(FRAME_PADDING);
        vbox.pack_start(image, false, false, 0);
        vbox.pack_end(title, false, false, LABEL_PADDING);
        if (panel != null)
            vbox.pack_end(panel, false, false, 0);
        
        // surround everything with a frame
        frame.set_shadow_type(Gtk.ShadowType.NONE);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        frame.add(vbox);

        add(frame);
    }
    
    public virtual Gtk.Widget? get_control_panel() {
        return null;
    }
    
    public string get_title() {
        return title.get_text();
    }
    
    public virtual void exposed() {
    }
    
    public virtual void unexposed() {
    }

    public void display_title(bool display) {
        if (display && !title_displayed) {
            vbox.pack_end(title, false, false, LABEL_PADDING);
            title_displayed = true;
        } else if (!display && title_displayed) {
            vbox.remove(title);
            title_displayed = false;
        }
    }
    
    public virtual void select() {
        selected = true;

        frame.set_shadow_type(Gtk.ShadowType.OUT);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
        
        Gtk.Widget panel = get_control_panel();
        if (panel != null)
            panel.modify_fg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
    }

    public virtual void unselect() {
        selected = false;

        frame.set_shadow_type(Gtk.ShadowType.NONE);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));

        Gtk.Widget panel = get_control_panel();
        if (panel != null)
            panel.modify_fg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
    }

    public bool toggle_select() {
        if (selected)
            unselect();
        else
            select();
        
        return selected;
    }

    public bool is_selected() {
        return selected;
    }
    
    public void set_coordinates(int col, int row) {
        this.col = col;
        this.row = row;
    }
    
    public int get_column() {
        return col;
    }
    
    public int get_row() {
        return row;
    }
}

public class CollectionLayout : Gtk.Layout {
    public static const int TOP_PADDING = 16;
    public static const int BOTTOM_PADDING = 16;
    public static const int ROW_GUTTER_PADDING = 24;

    // the following are minimums, as the pads and gutters expand to fill up the window width
    public static const int LEFT_PADDING = 16;
    public static const int RIGHT_PADDING = 16;
    public static const int COLUMN_GUTTER_PADDING = 24;
    
    public SortedList<LayoutItem> items = new SortedList<LayoutItem>(new Gee.ArrayList<LayoutItem>());

    private Gtk.Label message = new Gtk.Label("");
    private bool in_view = false;
    private int last_width = 0;
    private bool refresh_on_resize = true;
    private int columns = 0;
    private int rows = 0;

    public CollectionLayout() {
        modify_bg(Gtk.StateType.NORMAL, AppWindow.BG_COLOR);

        Gdk.Color color = parse_color(LayoutItem.UNSELECTED_COLOR);
        message.modify_fg(Gtk.StateType.NORMAL, color);
        message.set_single_line_mode(false);
        message.set_use_underline(false);
        
        size_allocate += on_resize;
    }
    
    public signal void expose_after();
    
    public void set_message(string text) {
        clear();

        message.set_text(text);
        
        display_message();
    }
    
    public void set_refresh_on_resize(bool refresh_on_resize) {
        this.refresh_on_resize = refresh_on_resize;
    }
    
    public void set_in_view(bool in_view) {
        this.in_view = in_view;
        if (in_view)
            return;
        
        // need to wait for expose event to start exposing items, but if no longer in view, might
        // as well unload now
        foreach (LayoutItem item in items)
            item.unexposed();
    }
    
    public void set_comparator(Comparator<LayoutItem> cmp) {
        // re-sort list with new comparator
        SortedList<LayoutItem> resorted = new SortedList<LayoutItem>(new Gee.ArrayList<LayoutItem>(), cmp);
        
        foreach (LayoutItem item in items) {
            // add to new list and remove from Gtk.Layout
            resorted.add(item);
            remove(item);
        }
        
        items = resorted;
    }
    
    public void add_item(LayoutItem item) {
        items.add(item);
        
        // this demolishes any message that's been set
        if (message.get_text().length > 0) {
            remove(message);
            message.set_text("");
        }

        // need to do this to have its size requisitioned in refresh()
        item.show_all();
    }
    
    public void remove_item(LayoutItem item) {
        items.remove(item);
        
        // this situation can happen if the item was added but the page not yet rendered ... because
        // CollectionLayout doens't know where to place the item until refresh(), that's when it's
        // initially added
        if (item.parent != null)
            remove(item);
    }
    
    public LayoutItem? get_item_at_pixel(double xd, double yd) {
        int x = (int) xd;
        int y = (int) yd;

        foreach (LayoutItem item in items) {
            Gtk.Allocation alloc = item.allocation;
            if ((x >= alloc.x) && (y >= alloc.y) && (x <= (alloc.x + alloc.width))
                && (y <= (alloc.y + alloc.height))) {
                return item;
            }
        }
        
        return null;
    }
    
    public Gee.List<LayoutItem> intersection(Gdk.Rectangle rect) {
        int bottom = rect.y + rect.height + 1;
        int right = rect.x + rect.width + 1;
        
        Gee.ArrayList<LayoutItem> intersects = new Gee.ArrayList<LayoutItem>();
        
        Gdk.Rectangle bitbucket = Gdk.Rectangle();
        
        foreach (LayoutItem item in items) {
            if (rect.intersect((Gdk.Rectangle) item.allocation, bitbucket))
                intersects.add(item);
            
            // short-circuit: if past the dimensions of the box in the sorted list, bail out
            if (item.allocation.y > bottom && item.allocation.x > right)
                break;
        }
        
        return intersects;
    }
    
    public LayoutItem? get_item_relative_to(LayoutItem item, CompassPoint point) {
        if (items.size == 0)
            return null;
        
        assert(columns > 0);
        assert(rows > 0);
        
        int col = item.get_column();
        int row = item.get_row();
        
        if (col < 0 || row < 0) {
            critical("Attempting to locate item not placed in layout: %s", item.get_title());
            
            return null;
        }
        
        switch (point) {
            case CompassPoint.NORTH:
                if (--row < 0)
                    row = 0;
            break;
            
            case CompassPoint.SOUTH:
                if (++row >= rows)
                    row = rows - 1;
            break;
            
            case CompassPoint.EAST:
                if (++col >= columns)
                    col = columns - 1;
            break;
            
            case CompassPoint.WEST:
                if (--col < 0)
                    col = 0;
            break;
            
            default:
                error("Bad compass point %d", (int) point);
            break;
        }
        
        LayoutItem new_item = get_item_at_coordinate(col, row);
        
        return (new_item != null) ? new_item : item;
    }
    
    public LayoutItem? get_item_at_coordinate(int col, int row) {
        // TODO: If searching by coordinates becomes more vital, the items could be stored
        // in an array of arrays for quicker lookup.
        foreach (LayoutItem item in items) {
            if (item.get_column() == col && item.get_row() == row)
                return item;
        }
        
        return null;
    }
    
    public void clear() {
        // remove page message
        if (message.get_text().length > 0) {
            remove(message);
            message.set_text("");
        }
        
        // remove all items from Gtk.Layout
        foreach (LayoutItem item in items)
            remove(item);
        
        // clear internal list
        items.clear();
        columns = 0;
        rows = 0;
    }
    
    public void refresh() {
        if (message.get_text().length > 0) {
            display_message();
            
            return;
        }
        
        // don't bother until layout is of some appreciable size
        if (allocation.width <= 1)
            return;
        
        // need to set_size in case all items were removed and the viewport size has changed
        if (items.size == 0) {
            set_size(allocation.width, 0);

            return;
        }

        // Step 1: Determine the widest row in the layout, and from it the number of columns
        int x = LEFT_PADDING;
        int col = 0;
        int max_cols = 0;
        int row_width = 0;
        int widest_row = 0;

        foreach (LayoutItem item in items) {
            // perform size requests first time through, but not thereafter
            Gtk.Requisition req;
            item.size_request(out req);
            
            // the items must be requisitioned for this code to work
            assert(req.height > 0);
            assert(req.width > 0);
            
            // carriage return (i.e. this item will overflow the view)
            if ((x + req.width + RIGHT_PADDING) > allocation.width) {
                if (row_width > widest_row) {
                    widest_row = row_width;
                    max_cols = col;
                }
                
                col = 0;
                x = LEFT_PADDING;
                row_width = 0;
            }
            
            x += req.width + COLUMN_GUTTER_PADDING;
            row_width += req.width;
            
            col++;
        }
        
        // account for dangling last row
        if (row_width > widest_row) {
            widest_row = row_width;
            max_cols = col;
        }
        
        assert(max_cols > 0);
        
        // Step 2: Now that the number of columns is known, find the maximum height for each row
        // and the maximum width for each column
        int row = 0;
        int tallest = 0;
        int total_width = 0;
        col = 0;
        int[] column_widths = new int[max_cols];
        int[] row_heights = new int[(items.size / max_cols) + 1];
        int gutter = 0;
        
        for (;;) {
            foreach (LayoutItem item in items) {
                Gtk.Requisition req = item.requisition;
                
                if (req.height > tallest)
                    tallest = req.height;
                
                // store largest thumb size of each column as well as track the total width of the
                // layout (which is the sum of the width of each column)
                if (column_widths[col] < req.width) {
                    total_width -= column_widths[col];
                    column_widths[col] = req.width;
                    total_width += req.width;
                }

                if (++col >= max_cols) {
                    col = 0;
                    row_heights[row++] = tallest;
                    tallest = 0;
                }
            }
            
            // account for final dangling row
            if (col != 0)
                row_heights[row] = tallest;
            
            // Step 3: Calculate the gutter between the items as being equidistant of the
            // remaining space (adding one gutter to account for the right-hand one)
            gutter = (allocation.width - total_width) / (max_cols + 1);
            
            // if only one column, gutter size could be less than minimums
            if (max_cols == 1)
                break;

            // have to reassemble if the gutter is too small ... this happens because Step One
            // takes a guess at the best column count, but when the max. widths of the columns are
            // added up, they could overflow
            if ((gutter < LEFT_PADDING) || (gutter < RIGHT_PADDING) || (gutter < COLUMN_GUTTER_PADDING)) {
                max_cols--;
                col = 0;
                row = 0;
                tallest = 0;
                total_width = 0;
                column_widths = new int[max_cols];
                row_heights = new int[(items.size / max_cols) + 1];
                /*
                debug("refresh(): readjusting columns: max_cols=%d", max_cols);
                */
            } else {
                break;
            }
        }

        /*
        debug("refresh(): width:%d total_width:%d max_cols:%d gutter:%d", allocation.width, total_width, 
            max_cols, gutter);
        */

        // Step 4: Lay out the items in the space using all the information gathered
        x = gutter;
        int y = TOP_PADDING;
        col = 0;
        row = 0;

        foreach (LayoutItem item in items) {
            Gtk.Requisition req = item.requisition;

            // this centers the item in the column
            int xpadding = (column_widths[col] - req.width) / 2;
            assert(xpadding >= 0);
            
            // this bottom-aligns the item along the row
            int ypadding = (row_heights[row] - req.height);
            assert(ypadding >= 0);
            
            // if item was recently appended, it needs to be put() rather than move()'d
            if (item.parent == (Gtk.Widget) this)
                move(item, x + xpadding, y + ypadding);
            else
                put(item, x + xpadding, y + ypadding);
            
            item.set_coordinates(col, row);

            x += column_widths[col] + gutter;

            // carriage return
            if (++col >= max_cols) {
                x = gutter;
                y += row_heights[row] + ROW_GUTTER_PADDING;
                col = 0;
                row++;
            }
        }
        
        columns = max_cols;
        rows = row + 1;
        
        // Step 5: Define the total size of the page as the size of the allocated width and
        // the height of all the items plus padding
        set_size(allocation.width, y + row_heights[row] + BOTTOM_PADDING);
    }
    
    private void display_message() {
        assert(message.get_text().length > 0);
        
        Gtk.Requisition req;
        message.size_request(out req);
        
        int x = (allocation.width - req.width) / 2;
        if (x < 0)
            x = 0;
            
        int y = (allocation.height - req.height) / 2;
        if (y < 0)
            y = 0;
            
        if (message.parent == (Gtk.Widget) this) {
            move(message, x, y);
        } else {
            put(message, x, y);
        }
        
        message.show_all();
    }

    private void on_resize() {
        // only refresh() if the width has changed
        if (refresh_on_resize && allocation.width != last_width) {
            last_width = allocation.width;
            refresh();
        }
    }
    
    private override bool expose_event(Gdk.EventExpose event) {
        if (!in_view) {
            foreach (LayoutItem item in items)
                item.unexposed();
            
            bool result = (base.expose_event != null) ? base.expose_event(event) : true;
            
            expose_after();
            
            return result;
        }
        
        Gdk.Rectangle visible_rect = Gdk.Rectangle();
        visible_rect.x = (int) get_hadjustment().get_value();
        visible_rect.y = (int) get_vadjustment().get_value();
        visible_rect.width = allocation.width;
        visible_rect.height = allocation.height;

        Gdk.Rectangle bitbucket = Gdk.Rectangle();

        foreach (LayoutItem item in items) {
            if (visible_rect.intersect((Gdk.Rectangle) item.allocation, bitbucket))
                item.exposed();
            else
                item.unexposed();
        }
        
        bool result = (base.expose_event != null) ? base.expose_event(event) : true;
        
        expose_after();
        
        return result;
    }
}
