/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class LayoutItem : ThumbnailView {
    public const int FRAME_WIDTH = 1;
    public const int LABEL_PADDING = 4;
    public const int FRAME_PADDING = 4;
    
    public const int TRINKET_SCALE = 12;
    public const int TRINKET_PADDING = 1;

    public const string SELECTED_COLOR = "#0FF";
    public const string UNSELECTED_COLOR = "#FFF";
    
    public const int BRIGHTEN_SHIFT = 0x18;
    
    private static int cached_pango_height = -1;
    
    public Gdk.Rectangle allocation = Gdk.Rectangle();
    
    private CheckerboardLayout parent = null;
    private Pango.Layout pango_layout = null;
    private string title = "";
    private bool title_displayed = true;
    private bool exposure = false;
    private Gdk.Pixbuf pixbuf = null;
    private Gdk.Pixbuf display_pixbuf = null;
    private Gdk.Pixbuf brightened = null;
    private Dimensions pixbuf_dim = Dimensions();
    private int col = -1;
    private int row = -1;
    
    public LayoutItem(ThumbnailSource source, Dimensions initial_pixbuf_dim) {
        base(source);
        
        pixbuf_dim = initial_pixbuf_dim;
    }
    
    // allocation will be invalid (or unset) until this call is made
    public void set_parent(CheckerboardLayout parent) {
        assert(this.parent == null);
        
        this.parent = parent;

        update_pango();
        recalc_size();
    }
    
    public void abandon_parent() {
        parent = null;
        pango_layout = null;
    }
    
    public virtual Gtk.Widget? get_control_panel() {
        return null;
    }
    
    public void set_title(string text) {
        if (text == title)
            return;
        
        title = text;

        update_pango();
        recalc_size();

        notify_view_altered();
    }
    
    public string get_title() {
        return title;
    }
    
    public override string get_name() {
        return get_title();
    }
    
    public Dimensions get_requisition() {
        return Dimensions.for_rectangle(allocation);
    }
    
    public virtual void exposed() {
        exposure = true;
    }
    
    public virtual void unexposed() {
        exposure = false;
    }
    
    public virtual bool is_exposed() {
        return exposure;
    }

    public void display_title(bool display) {
        if (display == title_displayed)
            return;
            
        title_displayed = display;

        recalc_size();
        
        notify_view_altered();
    }
    
    public bool has_image() {
        return pixbuf != null;
    }
    
    public Gdk.Pixbuf? get_image() {
        return pixbuf;
    }
    
    public void set_image(Gdk.Pixbuf pixbuf, bool notify = true) {
        bool image_changed = pixbuf != this.pixbuf;
        
        this.pixbuf = pixbuf;
        display_pixbuf = pixbuf;
        pixbuf_dim = Dimensions.for_pixbuf(pixbuf);

        recalc_size(notify);
        
        if (image_changed && notify)
            notify_view_altered();
    }
    
    public void clear_image(Dimensions dim, bool notify = true) {
        bool had_image = pixbuf != null;
        
        pixbuf = null;
        display_pixbuf = null;
        pixbuf_dim = dim;
        
        recalc_size(notify);
        
        if (had_image && notify)
            notify_view_altered();
    }
    
    private void update_pango() {
        if (parent == null || title == null) {
            pango_layout = null;
            
            return;
        }
        
        // create layout for this string and ellipsize so it never extends past the width of the
        // pixbuf (handled in recalc_size)
        pango_layout = parent.create_pango_layout(title);
        pango_layout.set_ellipsize(Pango.EllipsizeMode.END);
        
        // to avoid a lot of calls to get the pixel height of the label (which is the same for
        // all the items), cache it the first time and be done with it
        if (cached_pango_height < 0)
            pango_layout.get_pixel_size(null, out cached_pango_height);
    }
    
    public static int get_max_width(int scale) {
        // width is frame width (two sides) + frame padding (two sides) + width of pixbuf (text
        // never wider)
        return (FRAME_WIDTH * 2) + (FRAME_PADDING * 2) + scale;
    }
    
    public virtual Gee.List<Gdk.Pixbuf>? get_trinkets(int scale) {
        return null;
    }
    
    public void recalc_size(bool notify_change = true) {
        Gdk.Rectangle old_allocation = allocation;
        
        // only add in the text height if it's being displayed
        int text_height = (title_displayed) ? cached_pango_height + LABEL_PADDING : 0;
        
        // calculate width of all trinkets ... this is important because the trinkets could be
        // wider than the image, in which case need to expand for them
        int trinkets_width = 0;
        Gee.List<Gdk.Pixbuf>? trinkets = get_trinkets(TRINKET_SCALE);
        if (trinkets != null) {
            foreach (Gdk.Pixbuf trinket in trinkets)
                trinkets_width += trinket.get_width();
        }
        
        int image_width = int.max(trinkets_width, pixbuf_dim.width);
        
        // width is frame width (two sides) + frame padding (two sides) + width of pixbuf/trinkets
        // (text never wider)
        allocation.width = (FRAME_WIDTH * 2) + (FRAME_PADDING * 2) + image_width;
        
        // height is frame width (two sides) + frame padding (two sides) + height of pixbuf
        // + height of text + label padding (between pixbuf and text)
        allocation.height = (FRAME_WIDTH * 2) + (FRAME_PADDING * 2) + pixbuf_dim.height + text_height;
        
        if (notify_change && 
            !Dimensions.for_rectangle(allocation).approx_equals(Dimensions.for_rectangle(old_allocation)))
            notify_geometry_altered();
    }
    
    public void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        // frame of FRAME_WIDTH size (determined by GC) only if selected ... however, this is
        // accounted for in allocation so the frame can appear without resizing the item
        if (is_selected())
            drawable.draw_rectangle(gc, false, allocation.x, allocation.y, allocation.width - 1,
                allocation.height - 1);
        
        // find the top-left point of the pixbuf
        Gdk.Point pixbuf_origin = Gdk.Point();
        pixbuf_origin.x = allocation.x + FRAME_WIDTH + FRAME_PADDING;
        pixbuf_origin.y = allocation.y + FRAME_WIDTH + FRAME_PADDING;
        
        // pixbuf (or blank square) FRAME_PADDING interior from the frame
        if (display_pixbuf != null)
            drawable.draw_pixbuf(gc, display_pixbuf, 0, 0, pixbuf_origin.x, pixbuf_origin.y, -1, -1, 
                Gdk.RgbDither.NORMAL, 0, 0);
        
        // get trinkets to determine the max width (pixbuf vs. trinkets)
        int trinkets_width = 0;
        Gee.List<Gdk.Pixbuf>? trinkets = get_trinkets(TRINKET_SCALE);
        if (trinkets != null) {
            foreach (Gdk.Pixbuf trinket in trinkets)
                trinkets_width += trinket.get_width();
        }
        
        int image_width = int.max(trinkets_width, pixbuf_dim.width);
        
        // text itself LABEL_PADDING below bottom of pixbuf
        if (pango_layout != null && title_displayed) {
            // resize the text width to be no more than the pixbuf's
            if (pango_layout != null && image_width > 0)
                pango_layout.set_width(image_width * Pango.SCALE);
        
            Gdk.draw_layout(drawable, gc, allocation.x + FRAME_WIDTH + FRAME_PADDING,
                allocation.y + FRAME_WIDTH + FRAME_PADDING + pixbuf_dim.height + LABEL_PADDING,
                pango_layout);
        }
        
        // draw trinkets last
        if (trinkets != null) {
            foreach (Gdk.Pixbuf trinket in trinkets) {
                drawable.draw_pixbuf(gc, trinket, 0, 0, 
                    pixbuf_origin.x + pixbuf_dim.width - trinket.get_width() - TRINKET_PADDING, 
                    pixbuf_origin.y + pixbuf_dim.height - trinket.get_height() - TRINKET_PADDING, 
                    trinket.get_width(), trinket.get_height(), Gdk.RgbDither.NORMAL, 0, 0);
            }
        }
    }

    public void set_pixel_coordinates(int x, int y) {
        allocation.x = x;
        allocation.y = y;
    }
    
    public void set_grid_coordinates(int col, int row) {
        this.col = col;
        this.row = row;
    }
    
    public int get_column() {
        return col;
    }
    
    public int get_row() {
        return row;
    }
    
    public void brighten() {
        // "should" implies "can" and "didn't already"
        if (brightened != null || pixbuf == null)
            return;
        
        // create a new lightened pixbuf to display
        brightened = pixbuf.copy();
        shift_colors(brightened, BRIGHTEN_SHIFT, BRIGHTEN_SHIFT, BRIGHTEN_SHIFT, 0);
        
        display_pixbuf = brightened;
        
        notify_view_altered();
    }
    
    public void unbrighten() {
        // "should", "can", "didn't already"
        if (brightened == null || pixbuf == null)
            return;
        
        brightened = null;

        // return to the normal image
        display_pixbuf = pixbuf;
        
        notify_view_altered();
    }
    
    public override void visibility_changed(bool visible) {
         // if going from visible to hidden, unbrighten
         if (!visible)
            unbrighten();
    }
}

public class CheckerboardLayout : Gtk.DrawingArea {
    public const int TOP_PADDING = 16;
    public const int BOTTOM_PADDING = 16;
    public const int ROW_GUTTER_PADDING = 24;

    // the following are minimums, as the pads and gutters expand to fill up the window width
    public const int COLUMN_GUTTER_PADDING = 24;
    
    private class LayoutRow {
        public int y;
        public int height;
        public LayoutItem[] items;
        
        public LayoutRow(int y, int height, int num_in_row) {
            this.y = y;
            this.height = height;
            this.items = new LayoutItem[num_in_row];
        }
    }
    
    private static Gdk.Pixbuf selection_interior = null;

    private ViewCollection view;
    private string page_name = "";
    private LayoutRow[] item_rows = null;
    private Gee.HashSet<LayoutItem> exposed_items = new Gee.HashSet<LayoutItem>();
    private Gtk.Adjustment hadjustment = null;
    private Gtk.Adjustment vadjustment = null;
    private string message = null;
    private Gdk.GC selected_gc = null;
    private Gdk.GC unselected_gc = null;
    private Gdk.GC selection_band_gc = null;
    private bool in_view = false;
    private Gdk.Rectangle visible_page = Gdk.Rectangle();
    private int last_width = 0;
    private int columns = 0;
    private int rows = 0;
    private Gdk.Point drag_origin = Gdk.Point();
    private Gdk.Point drag_endpoint = Gdk.Point();
    private Gdk.Rectangle selection_band = Gdk.Rectangle();
    private uint32 selection_transparency_color = 0;
    private OneShotScheduler reflow_scheduler = null;
    private int scale = 0;
    private bool flow_dirty = true;

    public CheckerboardLayout(ViewCollection view) {
        this.view = view;
        
        clear_drag_select();
        
        reflow_scheduler = new OneShotScheduler("CheckerboardLayout for %s".printf(view.to_string()),
            background_reflow);
        
        // set existing items to be part of this layout
        foreach (DataObject object in view.get_all_unfiltered())
            ((LayoutItem) object).set_parent(this);

        // subscribe to the new collection
        view.contents_altered += on_contents_altered;
        view.item_altered += on_item_altered;
        view.item_metadata_altered += on_item_metadata_altered;
        view.items_state_changed += on_items_state_changed;
        view.items_visibility_changed += on_items_visibility_changed;
        view.ordering_changed += on_ordering_changed;
        view.item_view_altered += on_item_view_altered;
        view.item_geometry_altered += on_item_geometry_altered;
        view.views_altered += on_views_altered;
        view.geometries_altered += on_geometries_altered;
        
        modify_bg(Gtk.StateType.NORMAL, AppWindow.BG_COLOR);
    }
    
    ~CheckerboardLayout() {
#if TRACE_DTORS
        debug("DTOR: CheckerboardLayout for %s", view.to_string());
#endif

        view.contents_altered -= on_contents_altered;
        view.item_altered -= on_item_altered;
        view.item_metadata_altered -= on_item_metadata_altered;
        view.items_state_changed -= on_items_state_changed;
        view.items_visibility_changed -= on_items_visibility_changed;
        view.ordering_changed -= on_ordering_changed;
        view.item_view_altered -= on_item_view_altered;
        view.item_geometry_altered -= on_item_geometry_altered;
        view.views_altered -= on_views_altered;
        view.geometries_altered -= on_geometries_altered;
        
        if (hadjustment != null)
            hadjustment.value_changed -= on_viewport_shifted;
        
        if (vadjustment != null)
            vadjustment.value_changed -= on_viewport_shifted;
        
        if (parent != null)
            parent.size_allocate -= on_viewport_resized;
        
        reflow_scheduler.cancel();
    }
    
    public void set_adjustments(Gtk.Adjustment hadjustment, Gtk.Adjustment vadjustment) {
        this.hadjustment = hadjustment;
        this.vadjustment = vadjustment;
        
        // monitor adjustment changes to report when the visible page shifts
        hadjustment.value_changed += on_viewport_shifted;
        vadjustment.value_changed += on_viewport_shifted;
        
        // monitor parent's size changes for a similar reason
        parent.size_allocate += on_viewport_resized;
    }
    
    // This method allows for some optimizations to occur in reflow() by using the known max.
    // width of all items in the layout.
    public void set_scale(int scale) {
        this.scale = scale;
    }
    
    public int get_scale() {
        return scale;
    }
    
    public void set_name(string name) {
        page_name = name;
    }
    
    private void on_viewport_resized() {
        Gtk.Requisition req;
        size_request(out req);

        if (message == null) {
            // set the layout's new size to be the same as the parent's width but maintain 
            // it's own height
            set_size_request(parent.allocation.width, req.height);
        } else {
            // set the layout's width and height to always match the parent's
            set_size_request(parent.allocation.width, parent.allocation.height);
        }
        
        // possible for this widget's size_allocate not to be called, so need to update the page
        // rect here
        update_visible_page();
    }
    
    private void on_viewport_shifted() {
        update_visible_page();
    }
    
    private void on_contents_altered(Gee.Iterable<DataObject>? added, 
        Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added) {
                LayoutItem item = (LayoutItem) object;

                item.set_parent(this);
            }
            
            // this clears the message
            message = null;
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                LayoutItem item = (LayoutItem) object;
                
                item.abandon_parent();
                exposed_items.remove(item);
            }
        }
        
        // release spatial data structure ... contents_altered means a reflow is required, and since
        // items may be removed, this ensures we're not holding the ref on a removed view
        item_rows = null;
        
        schedule_background_reflow("on_contents_altered");
    }
    
    private void on_item_altered() {
        schedule_background_reflow("on_item_altered");
    }
    
    private void on_item_metadata_altered() {
        schedule_background_reflow("on_item_metadata_altered");
    }
    
    private void on_items_state_changed(Gee.Iterable<DataView> changed) {
        if (!in_view)
            return;
            
        foreach (DataView view in changed)
            repaint_item((LayoutItem) view);
    }
    
    private void on_items_visibility_changed(Gee.Iterable<DataView> changed) {
        schedule_background_reflow("on_items_visibility_changed");
    }
    
    private void on_ordering_changed() {
        schedule_background_reflow("on_ordering_changed");
    }
    
    private void on_item_view_altered(DataView view) {
        if (in_view)
            repaint_item((LayoutItem) view);
    }
    
    private void on_item_geometry_altered(DataView view) {
        schedule_background_reflow("on_item_geometry_altered");
    }
    
    private void on_views_altered() {
        if (in_view)
            queue_draw();
    }
    
    private void on_geometries_altered() {
        // don't schedule as this indicates all have resized and are ready for reflow
        if (reflow("on_geometries_altered"))
            queue_draw();
    }
    
    private void schedule_background_reflow(string caller) {
#if TRACE_REFLOW
        debug("schedule_background_reflow %s: %s (in_view=%d)", page_name, caller, (int) in_view);
#endif
        
        if (in_view)
            reflow_scheduler.at_idle();
        else
            flow_dirty = true;
    }
    
    private void background_reflow() {
        if (reflow("background_reflow"))
            queue_draw();
    }
    
    public void set_message(string text) {
        message = text;

        // set the layout's size to be exactly the same as the parent's
        if (parent != null)
            set_size_request(parent.allocation.width, parent.allocation.height);
    }
    
    private void update_visible_page(bool reexpose = true) {
        if (hadjustment == null || vadjustment == null)
            return;
            
        Gdk.Rectangle current_visible = get_adjustment_page(hadjustment, vadjustment);
        
        bool changed = !rectangles_equal(visible_page, current_visible);
        
        visible_page = current_visible;
        
        if (!reexpose || !in_view || !changed)
            return;
        
        // create a new hash set of exposed items that represents an intersection of the old set
        // and the new
        Gee.HashSet<LayoutItem> new_exposed_items = new Gee.HashSet<LayoutItem>();
        
        Gee.List<LayoutItem> items = intersection(visible_page);
        foreach (LayoutItem item in items) {
            new_exposed_items.add(item);

            // if not in the old list, then need to expose
            if (!exposed_items.remove(item))
                item.exposed();
        }
        
        // everything remaining in the old exposed list is now unexposed
        foreach (LayoutItem item in exposed_items)
            item.unexposed();
        
        // swap out lists
        exposed_items = new_exposed_items;
    }
    
    public void set_in_view(bool in_view) {
        this.in_view = in_view;
        if (in_view) {
            // update the visible page rectangle, but only re-expose items if not going to reflow
            // the layout (which exposes already)
            update_visible_page(!flow_dirty);
            
            // if the flow dirtied at some point, now reflow the layout
            if (flow_dirty) {
                if (reflow("set_in_view"))
                    queue_draw();
            }

            return;
        }
        
        // clear this to force a re-expose when back in view
        visible_page = Gdk.Rectangle();

        // unexpose everything currently exposed
        foreach (LayoutItem item in exposed_items)
            item.unexposed();
        
        exposed_items.clear();
    }
    
    public LayoutItem? get_item_at_pixel(double xd, double yd) {
        int x = (int) xd;
        int y = (int) yd;
        
        // look for the row in the range of the pixel
        LayoutRow in_range = null;
        foreach (LayoutRow row in item_rows) {
            // this happens when there is an exact number of elements to fill the last row
            if (row == null)
                continue;
            
            if (y < row.y) {
                // overshot ... this happens because there's gaps in the rows
                break;
            }

            // if inside height range, this is it
            if (y <= (row.y + row.height)) {
                in_range = row;
                
                break;
            }
        }
        
        if (in_range == null)
            return null;
        
        // look for item in row's column in range of the pixel
        foreach (LayoutItem item in in_range.items) {
            // this happens on an incompletely filled-in row (usually the last one with empty
            // space remaining)
            if (item == null)
                continue;
            
            if (x < item.allocation.x) {
                // overshot ... this happens because there's gaps in the columns
                break;
            }
            
            // need to verify actually over item's full dimensions, since they vary in size inside 
            // a row
            if (x <= (item.allocation.x + item.allocation.width) && y >= item.allocation.y 
                && y <= (item.allocation.y + item.allocation.height))
                return item;
        }

        return null;
    }
    
    public Gee.List<LayoutItem> get_visible_items() {
        return intersection(visible_page);
    }
    
    public Gee.List<LayoutItem> intersection(Gdk.Rectangle area) {
        Gee.ArrayList<LayoutItem> intersects = new Gee.ArrayList<LayoutItem>();
        
        Gdk.Rectangle bitbucket = Gdk.Rectangle();
        foreach (LayoutRow row in item_rows) {
            if (row == null)
                continue;
            
            if ((area.y + area.height) < row.y) {
                // overshoot
                break;
            }
            
            if ((row.y + row.height) < area.y) {
                // haven't reached it yet
                continue;
            }
            
            // see if the row intersects the area
            Gdk.Rectangle row_rect = Gdk.Rectangle();
            row_rect.x = 0;
            row_rect.y = row.y;
            row_rect.width = allocation.width;
            row_rect.height = row.height;
            
            if (area.intersect(row_rect, bitbucket)) {
                // see what elements, if any, intersect the area
                foreach (LayoutItem item in row.items) {
                    if (item == null)
                        continue;
                    
                    if (area.intersect(item.allocation, bitbucket))
                        intersects.add(item);
                }
            }
        }

        return intersects;
    }
    
    public LayoutItem? get_item_relative_to(LayoutItem item, CompassPoint point) {
        if (view.get_count() == 0)
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
                if (++col >= columns) {
                    if(++row >= rows) {
                        row = rows - 1;
                        col = columns - 1;
                    } else {
                        col = 0;
                    }
                }
            break;
            
            case CompassPoint.WEST:
                if (--col < 0) {
                    if (--row < 0) {
                        row = 0;
                        col = 0;
                    } else {
                        col = columns - 1;
                    }
                }
            break;
            
            default:
                error("Bad compass point %d", (int) point);
            break;
        }
        
        LayoutItem new_item = get_item_at_coordinate(col, row);
        
        return (new_item != null) ? new_item : item;
    }
    
    public LayoutItem? get_item_at_coordinate(int col, int row) {
        if (row >= item_rows.length)
            return null;
            
        LayoutRow item_row = item_rows[row];
        if (item_row == null)
            return null;
        
        if (col >= item_row.items.length)
            return null;
        
        return item_row.items[col];
    }
    
    public void set_drag_select_origin(int x, int y) {
        clear_drag_select();
        
        drag_origin.x = x.clamp(0, allocation.width);
        drag_origin.y = y.clamp(0, allocation.height);
    }
    
    public void set_drag_select_endpoint(int x, int y) {
        drag_endpoint.x = x.clamp(0, allocation.width);
        drag_endpoint.y = y.clamp(0, allocation.height);
        
        // drag_origin and drag_endpoint are maintained only to generate selection_band; all reporting
        // and drawing functions refer to it, not drag_origin and drag_endpoint
        Gdk.Rectangle old_selection_band = selection_band;
        selection_band = Box.from_points(drag_origin, drag_endpoint).get_rectangle();
        
        // force repaint of the union of the old and new, which covers the band reducing in size
        if (window != null) {
            Gdk.Rectangle union;
            selection_band.union(old_selection_band, out union);
            
            queue_draw_area(union.x, union.y, union.width, union.height);
        }
    }
    
    public Gee.List<LayoutItem>? items_in_selection_band() {
        if (!Dimensions.for_rectangle(selection_band).has_area())
            return null;

        return intersection(selection_band);
    }
    
    public bool is_drag_select_active() {
        return drag_origin.x >= 0 && drag_origin.y >= 0;
    }
    
    public void clear_drag_select() {
        selection_band = Gdk.Rectangle();
        drag_origin.x = -1;
        drag_origin.y = -1;
        drag_endpoint.x = -1;
        drag_endpoint.y = -1;
        
        // force a total repaint to clear the selection band
        queue_draw();
    }
    
    // Returns true if a redraw is required
    private bool reflow(string caller) {
        // if set in message mode, nothing to do here
        if (message != null)
            return false;
        
        // don't bother until layout is of some appreciable size (even this is too low)
        if (allocation.width <= 1)
            return false;
        
        // don't reflow if not in view of the user
        if (!in_view) {
            flow_dirty = true;
            
            return false;
        }
        
        int total_items = view.get_count();
        
        // clear the rows data structure, as the reflow will completely rearrange it
        item_rows = null;
        
#if TRACE_REFLOW
        debug("reflow %s: %s (%d items)", page_name, caller, total_items);
#endif
        
        // need to set_size in case all items were removed and the viewport size has changed
        if (total_items == 0) {
            set_size_request(allocation.width, 0);
            item_rows = new LayoutRow[0];
            flow_dirty = false;

            return true;
        }
        
        // Step 1: Determine the widest row in the layout, and from it the number of columns
        // If owner supplies an image scaling for all items in the layout, then this can be
        // calculated quickly.
        int max_cols = 0;
        if (scale > 0) {
            // calculate interior width
            int remaining_width = allocation.width - (COLUMN_GUTTER_PADDING * 2);
            int max_item_width = LayoutItem.get_max_width(scale);
            max_cols = remaining_width / max_item_width;
            if (max_cols <= 0)
                max_cols = 1;
            
            // if too large with gutters, decrease until columns fit
            while (max_cols > 1 
                && ((max_cols * max_item_width) + ((max_cols - 1) * COLUMN_GUTTER_PADDING) > remaining_width)) {
#if TRACE_REFLOW
                debug("reflow: scaled cols estimate: reducing max_cols from %d to %d", max_cols,
                    max_cols - 1);
#endif
                max_cols--;
            }
            
            // special case: if fewer items than columns, they are they columns
            if (total_items < max_cols)
                max_cols = total_items;
            
#if TRACE_REFLOW
            debug("reflow: scaled cols estimate: max_cols=%d remaining_width=%d max_item_width=%d",
                max_cols, remaining_width, max_item_width);
#endif
        } else {
            int x = COLUMN_GUTTER_PADDING;
            int col = 0;
            int row_width = 0;
            int widest_row = 0;

            for (int ctr = 0; ctr < total_items; ctr++) {
                LayoutItem item = (LayoutItem) view.get_at(ctr);
                Dimensions req = item.get_requisition();
                
                // the items must be requisitioned for this code to work
                assert(req.has_area());
                
                // carriage return (i.e. this item will overflow the view)
                if ((x + req.width + COLUMN_GUTTER_PADDING) > allocation.width) {
                    if (row_width > widest_row) {
                        widest_row = row_width;
                        max_cols = col;
                    }
                    
                    col = 0;
                    x = COLUMN_GUTTER_PADDING;
                    row_width = 0;
                }
                
                x += req.width + COLUMN_GUTTER_PADDING;
                row_width += req.width;
                
                col++;
            }
            
            // account for dangling last row
            if (row_width > widest_row)
                max_cols = col;
            
#if TRACE_REFLOW
            debug("reflow: manual cols estimate: max_cols=%d widest_row=%d", max_cols, widest_row);
#endif
        }
        
        assert(max_cols > 0);
        int max_rows = (total_items / max_cols) + 1;
        
        // Step 2: Now that the number of columns is known, find the maximum height for each row
        // and the maximum width for each column
        int row = 0;
        int tallest = 0;
        int widest = 0;
        int total_width = 0;
        int col = 0;
        int[] column_widths = new int[max_cols];
        int[] row_heights = new int[max_rows];
        int gutter = 0;
        
        for (;;) {
            for (int ctr = 0; ctr < total_items; ctr++ ) {
                LayoutItem item = (LayoutItem) view.get_at(ctr);
                Dimensions req = item.get_requisition();
                
                if (req.height > tallest)
                    tallest = req.height;
                
                if (req.width > widest)
                    widest = req.width;
                
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
            if (gutter < COLUMN_GUTTER_PADDING) {
                max_cols--;
                max_rows = (total_items / max_cols) + 1;
                
#if TRACE_REFLOW
                debug("reflow %s: readjusting columns: alloc.width=%d total_width=%d widest=%d gutter=%d max_cols now=%d", 
                    page_name, allocation.width, total_width, widest, gutter, max_cols);
#endif

                col = 0;
                row = 0;
                tallest = 0;
                widest = 0;
                total_width = 0;
                column_widths = new int[max_cols];
                row_heights = new int[max_rows];
            } else {
                break;
            }
        }

#if TRACE_REFLOW
        debug("reflow %s: width:%d total_width:%d max_cols:%d gutter:%d", page_name, allocation.width, 
            total_width, max_cols, gutter);
#endif

        // for the spatial structure
        item_rows = new LayoutRow[max_rows];

        // Step 4: Lay out the items in the space using all the information gathered
        int x = gutter;
        int y = TOP_PADDING;
        col = 0;
        row = 0;
        LayoutRow current_row = null;
        bool report_exposure = (visible_page.width > 1 && visible_page.height > 1);
        Gdk.Rectangle bitbucket = Gdk.Rectangle();
        
        for (int ctr = 0; ctr < total_items; ctr++) {
            LayoutItem item = (LayoutItem) view.get_at(ctr);
            Dimensions req = item.get_requisition();

            // this centers the item in the column
            int xpadding = (column_widths[col] - req.width) / 2;
            assert(xpadding >= 0);
            
            // this bottom-aligns the item along the row
            int ypadding = (row_heights[row] - req.height);
            assert(ypadding >= 0);
            
            // save pixel and grid coordinates
            item.set_pixel_coordinates(x + xpadding, y + ypadding);
            item.set_grid_coordinates(col, row);
            
            // report exposed or unexposed
            if (report_exposure) {
                if (item.allocation.intersect(visible_page, bitbucket)) {
                    exposed_items.add(item);
                    item.exposed();
                } else {
                    exposed_items.remove(item);
                    item.unexposed();
                }
            }
            
            // add to current row in spatial data structure
            if (current_row == null)
                current_row = new LayoutRow(y, row_heights[row], max_cols);
            
            current_row.items[col] = item;

            x += column_widths[col] + gutter;

            // carriage return
            if (++col >= max_cols) {
                assert(current_row != null);
                item_rows[row] = current_row;
                current_row = null;

                x = gutter;
                y += row_heights[row] + ROW_GUTTER_PADDING;
                col = 0;
                row++;
            }
        }
        
        // add last row to spatial data structure
        if (current_row != null)
            item_rows[row] = current_row;
        
        // save dimensions of checkerboard
        columns = max_cols;
        rows = row + 1;
        assert(rows == max_rows);
        
        // Step 5: Define the total size of the page as the size of the allocated width and
        // the height of all the items plus padding
        set_size_request(allocation.width, y + row_heights[row] + BOTTOM_PADDING);
        
        flow_dirty = false;
        
        return true;
    }
    
    private void repaint_item(LayoutItem item) {
        if (!item.is_visible())
            return;

        assert(view.contains(item));
        assert(item.allocation.width > 0 && item.allocation.height > 0);
        
        // only repaint if visible in viewport
        Gdk.Rectangle bitbucket = Gdk.Rectangle();
        if (!visible_page.intersect(item.allocation, bitbucket))
            return;
        
        queue_draw_area(item.allocation.x, item.allocation.y, item.allocation.width,
            item.allocation.height);
    }
    
    private override void map() {
        base.map();
        
        // set up selected/unselected colors
        Gdk.Color selected_color = fetch_color(LayoutItem.SELECTED_COLOR, window);
        Gdk.Color unselected_color = fetch_color(LayoutItem.UNSELECTED_COLOR, window);
        selection_transparency_color = convert_rgba(selected_color, 0x40);

        // set up GC's for painting layout items
        Gdk.GCValues gc_values = Gdk.GCValues();
        gc_values.foreground = selected_color;
        gc_values.function = Gdk.Function.COPY;
        gc_values.fill = Gdk.Fill.SOLID;
        gc_values.line_width = LayoutItem.FRAME_WIDTH;
        
        Gdk.GCValuesMask mask = 
            Gdk.GCValuesMask.FOREGROUND 
            | Gdk.GCValuesMask.FUNCTION 
            | Gdk.GCValuesMask.FILL
            | Gdk.GCValuesMask.LINE_WIDTH;

        selected_gc = new Gdk.GC.with_values(window, gc_values, mask);
        
        gc_values.foreground = unselected_color;
        
        unselected_gc = new Gdk.GC.with_values(window, gc_values, mask);

        gc_values.line_width = 1;
        gc_values.foreground = selected_color;
        
        selection_band_gc = new Gdk.GC.with_values(window, gc_values, mask);
    }
    
    private override void size_allocate(Gdk.Rectangle allocation) {
        base.size_allocate(allocation);
        
        // only reflow() if the width has changed
        if (allocation.width != last_width) {
            last_width = allocation.width;
            
            // update visible page rect but don't call expose events, as reflow will do that
            update_visible_page(false);
            
            if (reflow("size_allocate (%d)".printf(last_width)))
                queue_draw();
        } else {
            // update visible page rect, re-exposing as necessary
            update_visible_page();
        }
    }
    
    private override bool expose_event(Gdk.EventExpose event) {
        assert(in_view);
        
        // watch for message mode
        if (message == null) {
            // have all items in the exposed area paint themselves
            foreach (LayoutItem item in intersection(event.area))
                item.paint(item.is_selected() ? selected_gc : unselected_gc, window);
        } else {
            // draw the message in the center of the window
            Pango.Layout pango_layout = create_pango_layout(message);
            int text_width, text_height;
            pango_layout.get_pixel_size(out text_width, out text_height);
            
            int x = allocation.width - text_width;
            x = (x > 0) ? x / 2 : 0;
            
            int y = allocation.height - text_height;
            y = (y > 0) ? y / 2 : 0;

            Gdk.draw_layout(window, style.white_gc, x, y, pango_layout);
        }

        bool result = (base.expose_event != null) ? base.expose_event(event) : true;
        
        // draw the selection band last, so it appears floating over everything else
        draw_selection_band(event);

        return result;
    }
    
    private void draw_selection_band(Gdk.EventExpose event) {
        // no selection band, nothing to draw
        if (selection_band.width <= 1 || selection_band.height <= 1)
            return;
        
        // This requires adjustments
        if (hadjustment == null || vadjustment == null)
            return;
        
        // find the visible intersection of the viewport and the selection band
        Gdk.Rectangle visible_page = get_adjustment_page(hadjustment, vadjustment);
        Gdk.Rectangle visible_band = Gdk.Rectangle();
        visible_page.intersect(selection_band, visible_band);
        
        // pixelate selection rectangle interior
        if (visible_band.width > 1 && visible_band.height > 1) {
            // generate a pixbuf of the selection color with a transparency to paint over the
            // visible selection area ... reuse old pixbuf (which is shared among all instances)
            // if possible
            if (selection_interior == null || selection_interior.width < visible_band.width
                || selection_interior.height < visible_band.height) {
                selection_interior = new Gdk.Pixbuf(Gdk.Colorspace.RGB, true, 8, visible_band.width,
                    visible_band.height);
               selection_interior.fill(selection_transparency_color);
            }
            
            window.draw_pixbuf(selection_band_gc, selection_interior, 0, 0, visible_band.x, 
                visible_band.y, visible_band.width, visible_band.height, Gdk.RgbDither.NORMAL, 0, 0);
        }

        // border
        Gdk.draw_rectangle(window, selection_band_gc, false, selection_band.x, selection_band.y,
            selection_band.width - 1, selection_band.height - 1);
    }
}
