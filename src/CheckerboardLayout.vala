/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class CheckerboardLayout : Gtk.Widget {

    private class RubberbandProxy : Gtk.Widget {
        public RubberbandProxy(Gtk.Widget parent) {
            Object();
            set_parent(parent);
        }

        ~RubberbandProxy() {
            unparent();
        }

        static construct {
            set_css_name("rubberband");
        }
    }

    private RubberbandProxy rubber_band;

    public const int TOP_PADDING = 16;
    public const int BOTTOM_PADDING = 16;
    public const int ROW_GUTTER_PADDING = 24;

    // the following are minimums, as the pads and gutters expand to fill up the window width
    public const int COLUMN_GUTTER_PADDING = 24;
    
    // For a 40% alpha channel
    private const double SELECTION_ALPHA = 0.40;
    
    // The number of pixels that the scrollbars of Gtk.ScrolledWindows allocate for themselves
    // before their final size is computed. This must be taken into account when computing
    // the width of this widget. This value was 0 in Gtk+ 2.x but is 1 in Gtk+ 3.x. See
    // ticket #3870 (https://bugzilla.gnome.org/show_bug.cgi?id=717754) for more information
    private const int SCROLLBAR_PLACEHOLDER_WIDTH = 1;
    
    private class LayoutRow {
        public int y;
        public int height;
        public CheckerboardItem[] items;
        
        public LayoutRow(int y, int height, int num_in_row) {
            this.y = y;
            this.height = height;
            this.items = new CheckerboardItem[num_in_row];
        }
    }
    
    private ViewCollection view;
    private string page_name = "";
    private LayoutRow[] item_rows = null;
    private Gee.HashSet<CheckerboardItem> exposed_items = new Gee.HashSet<CheckerboardItem>();
    private Gtk.Adjustment hadjustment = null;
    private Gtk.Adjustment vadjustment = null;
    private Gdk.RGBA selected_color;
    private Gdk.RGBA unselected_color;
    private Gdk.RGBA focus_color;
    private Gdk.RGBA border_color;
    private Gdk.RGBA bg_color;
    private Gdk.Rectangle visible_page = Gdk.Rectangle();
    private int last_width = 0;
    private int columns = 0;
    private int rows = 0;
    private Gdk.Point drag_origin = Gdk.Point();
    private Gdk.Point drag_endpoint = Gdk.Point();
    private Gdk.Rectangle selection_band = Gdk.Rectangle();
    private int scale = 0;
    private bool flow_scheduled = false;
    private bool exposure_dirty = true;
    private CheckerboardItem? anchor = null;
    private CheckerboardItem? current_cursor = null;
    private bool in_center_on_anchor = false;
    private bool size_allocate_due_to_reflow = false;
    private bool is_in_view = false;
    private bool reflow_needed = false;
    
    public CheckerboardLayout(ViewCollection view) {
        this.view = view;
        set_css_name("content-view");
        rubber_band = new RubberbandProxy(this);

        clear_drag_select();
        
        // subscribe to the new collection
        view.contents_altered.connect(on_contents_altered);
        view.items_altered.connect(on_items_altered);
        view.items_state_changed.connect(on_items_state_changed);
        view.items_visibility_changed.connect(on_items_visibility_changed);
        view.ordering_changed.connect(on_ordering_changed);
        view.views_altered.connect(on_views_altered);
        view.geometries_altered.connect(on_geometries_altered);
        view.items_selected.connect(on_items_selection_changed);
        view.items_unselected.connect(on_items_selection_changed);

        Config.Facade.get_instance().colors_changed.connect(on_colors_changed);

        // CheckerboardItems offer tooltips
        has_tooltip = true;
        //set_draw_func (on_draw);

        var focus_controller = new Gtk.EventControllerFocus ();
        focus_controller.set_name ("CheckerboardLayout focus watcher");
        add_controller (focus_controller);
        focus_controller.enter.connect (focus_in_event);
        focus_controller.leave.connect (focus_out_event);
    }
    
    ~CheckerboardLayout() {
#if TRACE_DTORS
        debug("DTOR: CheckerboardLayout for %s", view.to_string());
#endif

        view.contents_altered.disconnect(on_contents_altered);
        view.items_altered.disconnect(on_items_altered);
        view.items_state_changed.disconnect(on_items_state_changed);
        view.items_visibility_changed.disconnect(on_items_visibility_changed);
        view.ordering_changed.disconnect(on_ordering_changed);
        view.views_altered.disconnect(on_views_altered);
        view.geometries_altered.disconnect(on_geometries_altered);
        view.items_selected.disconnect(on_items_selection_changed);
        view.items_unselected.disconnect(on_items_selection_changed);
        
        if (hadjustment != null)
            hadjustment.value_changed.disconnect(on_viewport_shifted);
        
        if (vadjustment != null)
            vadjustment.value_changed.disconnect(on_viewport_shifted);

        Config.Facade.get_instance().colors_changed.disconnect(on_colors_changed);
    }
    
    public void set_adjustments(Gtk.Adjustment hadjustment, Gtk.Adjustment vadjustment) {
        this.hadjustment = hadjustment;
        this.vadjustment = vadjustment;
        
        // monitor adjustment changes to report when the visible page shifts
        hadjustment.value_changed.connect(on_viewport_shifted);
        vadjustment.value_changed.connect(on_viewport_shifted);
        
        // monitor parent's size changes for a similar reason
    }
    
    // This method allows for some optimizations to occur in reflow() by using the known max.
    // width of all items in the layout.
    public void set_scale(int scale) {
        this.scale = scale;
    }
    
    public int get_scale() {
        return scale;
    }
    
    public new void set_name(string name) {
        page_name = name;
    }
    
    public void on_viewport_resized() {
        Gtk.Requisition req;
        get_preferred_size(null, out req);
        
        Gtk.Allocation parent_allocation;
        parent.get_allocation(out parent_allocation);
        
        // set the layout's new size to be the same as the parent's width but maintain
        // it's own height
#if TRACE_REFLOW
        debug("on_viewport_resized: due_to_reflow=%s set_size_request %dx%d",
              size_allocate_due_to_reflow.to_string(), parent_allocation.width, req.height);
#endif
        // But if the current height is 0, don't request a size yet. Delay
        // it to do_reflow (bgo#766864)
        if (req.height != 0) {
            set_size_request(parent_allocation.width - SCROLLBAR_PLACEHOLDER_WIDTH, req.height);
        }

        // possible for this widget's size_allocate not to be called, so need to update the page
        // rect here
        viewport_resized();

        if (!size_allocate_due_to_reflow)
            clear_anchor();
        else
            size_allocate_due_to_reflow = false;
    }
    
    private void on_viewport_shifted() {
        update_visible_page();
        need_exposure("on_viewport_shift");

        clear_anchor();
    }

    private void on_items_selection_changed() {
        clear_anchor();
    }

    private void clear_anchor() {
        if (in_center_on_anchor)
            return;

        anchor = null;
    }
    
    private void update_anchor() {
        assert(!in_center_on_anchor);

        Gee.List<CheckerboardItem> items_on_page = intersection(visible_page);
        if (items_on_page.size == 0) {
            anchor = null;
            return;
        }

        foreach (CheckerboardItem item in items_on_page) {
            if (item.is_selected()) {
                anchor = item;
                return;
            }
        }

        if (vadjustment.get_value() == 0) {
            anchor = null;
            return;
        }
        
        // this could be improved to always find the visual center...in the case where only
        // a few photos are in the last visible row, this can choose a photo near the right
        anchor = items_on_page.get((int) items_on_page.size / 2);
    }

    private void center_on_anchor(double upper) {
        if (anchor == null)
            return;

        in_center_on_anchor = true;
  
        double anchor_pos = anchor.allocation.y + (anchor.allocation.height / 2) - 
            (vadjustment.get_page_size() / 2);
        vadjustment.set_value(anchor_pos.clamp(vadjustment.get_lower(), 
            vadjustment.get_upper() - vadjustment.get_page_size()));

        in_center_on_anchor = false;
    }

    public new void set_cursor(CheckerboardItem item) {
        Gee.HashSet<DataView> collection = new Gee.HashSet<DataView>();
        if (current_cursor != null) {
            current_cursor.set_is_cursor(false);
            // Bug #732334, the cursor DataView might have disappeared when user drags a full screen Photo to another event
            if (view.contains(current_cursor)) {
                collection.add(current_cursor);
            }
        }
        item.set_is_cursor(true);
        current_cursor = item;
        collection.add(item);
        on_items_state_changed(collection);
    }
    
    public new CheckerboardItem get_cursor() {
        return current_cursor;
    }
    
    
    private void on_contents_altered(Gee.Iterable<DataObject>? added, 
        Gee.Iterable<DataObject>? removed) {
        
        if (removed != null) {
            foreach (DataObject object in removed)
                exposed_items.remove((CheckerboardItem) object);
        }
        
        // release spatial data structure ... contents_altered means a reflow is required, and since
        // items may be removed, this ensures we're not holding the ref on a removed view
        item_rows = null;
        
        need_reflow("on_contents_altered");
    }
    
    private void on_items_altered() {
        need_reflow("on_items_altered");
    }
    
    private void on_items_state_changed(Gee.Iterable<DataView> changed) {
        items_dirty("on_items_state_changed", changed);
    }
    
    private void on_items_visibility_changed(Gee.Iterable<DataView> changed) {
        need_reflow("on_items_visibility_changed");
    }
    
    private void on_ordering_changed() {
        need_reflow("on_ordering_changed");
    }
    
    private void on_views_altered(Gee.Collection<DataView> altered) {
        items_dirty("on_views_altered", altered);
    }
    
    private void on_geometries_altered() {
        need_reflow("on_geometries_altered");
    }
    
    private void need_reflow(string caller) {
        if (flow_scheduled)
            return;

        if (!is_in_view) {
            reflow_needed = true;
            return;
        }
        
#if TRACE_REFLOW
        debug("need_reflow %s: %s", page_name, caller);
#endif
        flow_scheduled = true;
        Idle.add_full(Priority.HIGH, do_reflow);
    }
    
    private bool do_reflow() {
        reflow("do_reflow");
        need_exposure("do_reflow");

        flow_scheduled = false;
        
        return false;
    }

    private void need_exposure(string caller) {
#if TRACE_REFLOW
        debug("need_exposure %s: %s", page_name, caller);
#endif
        exposure_dirty = true;
        queue_draw();
    }
    
    private void update_visible_page() {
        if (hadjustment != null && vadjustment != null)
            visible_page = get_adjustment_page(hadjustment, vadjustment);
    }
    
    public void set_in_view(bool in_view) {
        is_in_view = in_view;
        
        if (in_view) {
            if (reflow_needed)
                need_reflow("set_in_view (true)");
            else
                need_exposure("set_in_view (true)");
        } else
            unexpose_items("set_in_view (false)");
    }
    
    public CheckerboardItem? get_item_at_pixel(double xd, double yd) {
        if (item_rows == null)
            return null;
            
        int x = (int) xd;
        int y = (int) yd;
        
        // binary search the rows for the one in range of the pixel
        LayoutRow in_range = null;
        int min = 0;
        int max = item_rows.length;
        for(;;) {
            int mid = min + ((max - min) / 2);
            LayoutRow row = item_rows[mid];
            
            if (row == null || y < row.y) {
                // undershot
                // row == null happens when there is an exact number of elements to fill the last row
                max = mid - 1;
            } else if (y > (row.y + row.height)) {
                // undershot
                min = mid + 1;
            } else {
                // bingo
                in_range = row;
                
                break;
            }
            
            if (min > max)
                break;
        }
        
        if (in_range == null)
            return null;
        
        // look for item in row's column in range of the pixel
        foreach (CheckerboardItem item in in_range.items) {
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

    public static int get_tag_index_at_pos(string tag_list, int pos) {
        int sep_len = Tag.TAG_LIST_SEPARATOR_STRING.length;
        assert (sep_len > 0);
        int len = tag_list.length;
        if (pos < 0 || pos >= len)
            return -1;

        // check if we're hovering on a separator
        for (int i = 0; i < sep_len; ++i) {
            if (tag_list[pos] == Tag.TAG_LIST_SEPARATOR_STRING[i] && pos >= i) {
                if (tag_list.substring(pos - i, sep_len) == Tag.TAG_LIST_SEPARATOR_STRING)
                    return -1;
            }
        }

        // Determine the tag index by counting the number of separators before
        // the requested position. This only works if the separator string
        // contains the delimiter used to delimit tags (i.e. the comma `,'.)
        int index = 0;
        for (int i = 0; i < pos; ++i) {
            if (tag_list[i] == Tag.TAG_LIST_SEPARATOR_STRING[0] &&
                    i + sep_len <= len &&
                    tag_list.substring(i, sep_len) == Tag.TAG_LIST_SEPARATOR_STRING) {
                ++index;
                i += sep_len - 1;
            }
        }
        return index;
    }

    private int internal_handle_tag_mouse_event(CheckerboardItem item, int x, int y) {
        Pango.Layout? layout = item.get_tag_list_layout();
        if (layout == null)
            return -1;

        item.translate_coordinates(ref x, ref y);

        Gdk.Rectangle rect = item.get_subtitle_allocation();
        int index, trailing;
        int px = (x - rect.x) * Pango.SCALE;
        int py = (y - rect.y) * Pango.SCALE;
        if (layout.xy_to_index(px, py, out index, out trailing))
            return get_tag_index_at_pos(layout.get_text(), index);
        return -1;
    }

    public bool handle_mouse_motion(CheckerboardItem item, int x, int y, Gdk.ModifierType mask) {
        int dx = x - item.allocation.x;
        int dy = y - item.allocation.y;

        item.handle_mouse_motion(dx, dy, item.allocation.height, item.allocation.width);

        if (!item.has_tags || is_drag_select_active())
            return false;
        int tag_index = internal_handle_tag_mouse_event(item, x, y);
        item.highlight_user_visible_tag(tag_index);
        return (tag_index >= 0);
    }

    public bool handle_left_click(CheckerboardItem item, double xd, double yd, Gdk.ModifierType mask) {
        int tag_index = internal_handle_tag_mouse_event(item, (int)Math.round(xd), (int)Math.round(yd));
        if (tag_index >= 0) {
            Tag tag = item.get_user_visible_tag(tag_index);
            LibraryWindow.get_app().switch_to_tag(tag);
            return true;
        }
        return false;
    }

    public Gee.List<CheckerboardItem> get_visible_items() {
        return intersection(visible_page);
    }
    
    public Gee.List<CheckerboardItem> intersection(Gdk.Rectangle area) {
        Gee.ArrayList<CheckerboardItem> intersects = new Gee.ArrayList<CheckerboardItem>();
        
        Gtk.Allocation allocation;
        get_allocation(out allocation);
        
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
            
            if (area.intersect(row_rect, out bitbucket)) {
                // see what elements, if any, intersect the area
                foreach (CheckerboardItem item in row.items) {
                    if (item == null)
                        continue;
                    
                    if (area.intersect(item.allocation, out bitbucket))
                        intersects.add(item);
                }
            }
        }

        return intersects;
    }
    
    public CheckerboardItem? get_item_relative_to(CheckerboardItem item, CompassPoint point) {
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
        }
        
        CheckerboardItem? new_item = get_item_at_coordinate(col, row);
        
        if (new_item == null && point == CompassPoint.SOUTH) {
            // nothing directly below, get last item on next row
            new_item = (CheckerboardItem?) view.get_last();
            if (new_item.get_row() <= item.get_row())
                new_item = null;
        }

        return (new_item != null) ? new_item : item;
    }
    
    public CheckerboardItem? get_item_at_coordinate(int col, int row) {
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
        
        Gtk.Allocation allocation;
        get_allocation(out allocation);
        
        drag_origin.x = x.clamp(0, allocation.width);
        drag_origin.y = y.clamp(0, allocation.height);
    }
    
    public void set_drag_select_endpoint(double x, double y) {
        Gtk.Allocation allocation;
        get_allocation(out allocation);
        
        drag_endpoint.x = (int) x.clamp(0, allocation.width);
        drag_endpoint.y = (int) y.clamp(0, allocation.height);
        
        // drag_origin and drag_endpoint are maintained only to generate selection_band; all reporting
        // and drawing functions refer to it, not drag_origin and drag_endpoint
        Gdk.Rectangle old_selection_band = selection_band;
        selection_band = Box.from_points(drag_origin, drag_endpoint).get_rectangle();
        
        // force repaint of the union of the old and new, which covers the band reducing in size
            Gdk.Rectangle union;
            selection_band.union(old_selection_band, out union);
        queue_draw();
    }
    
    public Gee.List<CheckerboardItem>? items_in_selection_band() {
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
    
    private void viewport_resized() {
        // update visible page rect
        update_visible_page();
        
        // only reflow() if the width has changed
        if (visible_page.width != last_width) {
            int old_width = last_width;
            last_width = visible_page.width;
            
            need_reflow("viewport_resized (%d -> %d)".printf(old_width, visible_page.width));
        } else {
            // don't need to reflow but exposure may have changed
            need_exposure("viewport_resized (same width=%d)".printf(last_width));
        }
    }
    
    private void expose_items(string caller) {
        // create a new hash set of exposed items that represents an intersection of the old set
        // and the new
        Gee.HashSet<CheckerboardItem> new_exposed_items = new Gee.HashSet<CheckerboardItem>();
        
        view.freeze_notifications();
        
        Gee.List<CheckerboardItem> items = get_visible_items();
        foreach (CheckerboardItem item in items) {
            new_exposed_items.add(item);

            // if not in the old list, then need to expose
            if (!exposed_items.remove(item))
                item.exposed();
        }
        
        // everything remaining in the old exposed list is now unexposed
        foreach (CheckerboardItem item in exposed_items)
            item.unexposed();
        
        // swap out lists
        exposed_items = new_exposed_items;
        exposure_dirty = false;
        
#if TRACE_REFLOW
        debug("expose_items %s: exposed %d items, thawing", page_name, exposed_items.size);
#endif
        view.thaw_notifications();
#if TRACE_REFLOW
        debug("expose_items %s: thaw finished", page_name);
#endif
    }
    
    private void unexpose_items(string caller) {
        view.freeze_notifications();
        
        foreach (CheckerboardItem item in exposed_items)
            item.unexposed();
        
        exposed_items.clear();
        exposure_dirty = false;
        
#if TRACE_REFLOW
        debug("unexpose_items %s: thawing", page_name);
#endif
        view.thaw_notifications();
#if TRACE_REFLOW
        debug("unexpose_items %s: thawed", page_name);
#endif
    }
    
    private void reflow(string caller) {
        reflow_needed = false;
        
        Gtk.Allocation allocation;
        get_allocation(out allocation);
        
        int visible_width = (visible_page.width > 0) ? visible_page.width : allocation.width;
        
#if TRACE_REFLOW
        debug("reflow: Using visible page width of %d (allocated: %d)", visible_width,
            allocation.width);
#endif
        
        // don't bother until layout is of some appreciable size (even this is too low)
        if (visible_width <= 1)
            return;
        
        int total_items = view.get_count();
        
        // need to set_size in case all items were removed and the viewport size has changed
        if (total_items == 0) {
            set_size_request(visible_width, 0);
            item_rows = new LayoutRow[0];

            return;
        }
        
#if TRACE_REFLOW
        debug("reflow %s: %s (%d items)", page_name, caller, total_items);
#endif
        
        // look for anchor if there is none currently
        if (anchor == null || !anchor.is_visible())
            update_anchor();
        
        // clear the rows data structure, as the reflow will completely rearrange it
        item_rows = null;
        
        // Step 1: Determine the widest row in the layout, and from it the number of columns.
        // If owner supplies an image scaling for all items in the layout, then this can be
        // calculated quickly.
        int max_cols = 0;
        if (scale > 0) {
            // calculate interior width
            int remaining_width = visible_width - (COLUMN_GUTTER_PADDING * 2);
            int max_item_width = CheckerboardItem.get_max_width(scale);
            max_cols = remaining_width / max_item_width;
            if (max_cols <= 0)
                max_cols = 1;
            
            // if too large with gutters, decrease until columns fit
            while (max_cols > 1 
                && ((max_cols * max_item_width) + ((max_cols - 1) * COLUMN_GUTTER_PADDING) > remaining_width)) {
#if TRACE_REFLOW
                debug("reflow %s: scaled cols estimate: reducing max_cols from %d to %d", page_name,
                    max_cols, max_cols - 1);
#endif
                max_cols--;
            }
            
            // special case: if fewer items than columns, they are the columns
            if (total_items < max_cols)
                max_cols = total_items;
            
#if TRACE_REFLOW
            debug("reflow %s: scaled cols estimate: max_cols=%d remaining_width=%d max_item_width=%d",
                page_name, max_cols, remaining_width, max_item_width);
#endif
        } else {
            int x = COLUMN_GUTTER_PADDING;
            int col = 0;
            int row_width = 0;
            int widest_row = 0;

            for (int ctr = 0; ctr < total_items; ctr++) {
                CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
                Dimensions req = item.requisition;
                
                // the items must be requisitioned for this code to work
                assert(req.has_area());
                
                // carriage return (i.e. this item will overflow the view)
                if ((x + req.width + COLUMN_GUTTER_PADDING) > visible_width) {
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
            debug("reflow %s: manual cols estimate: max_cols=%d widest_row=%d", page_name, max_cols,
                widest_row);
#endif
        }
        
        assert(max_cols > 0);
        int max_rows = (total_items / max_cols) + 1;
        
        // Step 2: Now that the number of columns is known, find the maximum height for each row
        // and the maximum width for each column
        int row = 0;
        int tallest = 0;
        int widest = 0;
        int row_alignment_point = 0;
        int total_width = 0;
        int col = 0;
        int[] column_widths = new int[max_cols];
        int[] row_heights = new int[max_rows];
        int[] alignment_points = new int[max_rows];
        int gutter = 0;
        
        for (;;) {
            for (int ctr = 0; ctr < total_items; ctr++ ) {
                CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
                Dimensions req = item.requisition;
                int alignment_point = item.get_alignment_point();
                
                // alignment point better be sane
                assert(alignment_point < req.height);
                
                if (req.height > tallest)
                    tallest = req.height;
                
                if (req.width > widest)
                    widest = req.width;
                
                if (alignment_point > row_alignment_point)
                    row_alignment_point = alignment_point;
                
                // store largest thumb size of each column as well as track the total width of the
                // layout (which is the sum of the width of each column)
                if (column_widths[col] < req.width) {
                    total_width -= column_widths[col];
                    column_widths[col] = req.width;
                    total_width += req.width;
                }

                if (++col >= max_cols) {
                    alignment_points[row] = row_alignment_point;
                    row_heights[row++] = tallest;
                    
                    col = 0;
                    row_alignment_point = 0;
                    tallest = 0;
                }
            }
            
            // account for final dangling row
            if (col != 0) {
                alignment_points[row] = row_alignment_point;
                row_heights[row] = tallest;
            }
            
            // Step 3: Calculate the gutter between the items as being equidistant of the
            // remaining space (adding one gutter to account for the right-hand one)
            gutter = (visible_width - total_width) / (max_cols + 1);
            
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
                    page_name, visible_width, total_width, widest, gutter, max_cols);
#endif
                
                col = 0;
                row = 0;
                tallest = 0;
                widest = 0;
                total_width = 0;
                row_alignment_point = 0;
                column_widths = new int[max_cols];
                row_heights = new int[max_rows];
                alignment_points = new int[max_rows];
            } else {
                break;
            }
        }

#if TRACE_REFLOW
        debug("reflow %s: width:%d total_width:%d max_cols:%d gutter:%d", page_name, visible_width, 
            total_width, max_cols, gutter);
#endif
        
        // Step 4: Recalculate the height of each row according to the row's alignment point (which
        // may cause shorter items to extend below the bottom of the tallest one, extending the
        // height of the row)
        col = 0;
        row = 0;
        
        for (int ctr = 0; ctr < total_items; ctr++) {
            CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
            Dimensions req = item.requisition;
            
            // this determines how much padding the item requires to be bottom-alignment along the
            // alignment point; add to the height and you have the item's "true" height on the 
            // laid-down row
            int true_height = req.height + (alignment_points[row] - item.get_alignment_point());
            assert(true_height >= req.height);
            
            // add that to its height to determine it's actual height on the laid-down row
            if (true_height > row_heights[row]) {
#if TRACE_REFLOW
                debug("reflow %s: Adjusting height of row %d from %d to %d", page_name, row,
                    row_heights[row], true_height);
#endif
                row_heights[row] = true_height;
            }
            
            // carriage return
            if (++col >= max_cols) {
                col = 0;
                row++;
            }
        }
        
        // for the spatial structure
        item_rows = new LayoutRow[max_rows];
        
        // Step 5: Lay out the items in the space using all the information gathered
        int x = gutter;
        int y = TOP_PADDING;
        col = 0;
        row = 0;
        LayoutRow current_row = null;
        
        for (int ctr = 0; ctr < total_items; ctr++) {
            CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
            Dimensions req = item.requisition;
            
            // this centers the item in the column
            int xpadding = (column_widths[col] - req.width) / 2;
            assert(xpadding >= 0);
            
            // this bottom-aligns the item along the discovered alignment point
            int ypadding = alignment_points[row] - item.get_alignment_point();
            assert(ypadding >= 0);
            
            // save pixel and grid coordinates
            item.allocation.x = x + xpadding;
            item.allocation.y = y + ypadding;
            item.allocation.width = req.width;
            item.allocation.height = req.height;
            item.set_grid_coordinates(col, row);
            
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
        
        // Step 6: Define the total size of the page as the size of the visible width (to avoid
        // the horizontal scrollbar from appearing) and the height of all the items plus padding
        int total_height = y + row_heights[row] + BOTTOM_PADDING;
        if (visible_width != allocation.width || total_height != allocation.height) {
#if TRACE_REFLOW
            debug("reflow %s: Changing layout dimensions from %dx%d to %dx%d", page_name, 
                allocation.width, allocation.height, visible_width, total_height);
#endif
            set_size_request(visible_width, total_height);
            size_allocate_due_to_reflow = true;
            
            // when height changes, center on the anchor to minimize amount of visual change
            center_on_anchor(total_height);
        }
    }
    
    private void items_dirty(string reason, Gee.Iterable<DataView> items) {
        Gdk.Rectangle dirty = Gdk.Rectangle();
        foreach (DataView data_view in items) {
            CheckerboardItem item = (CheckerboardItem) data_view;
            
            if (!item.is_visible())
                continue;
            
            assert(view.contains(item));
            
            // if not allocated, need to reflow the entire layout; don't bother queueing a draw
            // for any of these, reflow will handle that
            if (item.allocation.width <= 0 || item.allocation.height <= 0) {
                need_reflow("items_dirty: %s".printf(reason));
                
                return;
            }
            
            // only mark area as dirty if visible in viewport
            Gdk.Rectangle intersection = Gdk.Rectangle();
            if (!visible_page.intersect(item.allocation, out intersection))
                continue;
            
            // grow the dirty area
            if (dirty.width == 0 || dirty.height == 0)
                dirty = intersection;
            else
                dirty.union(intersection, out dirty);
        }
        
        if (dirty.width > 0 && dirty.height > 0) {
#if TRACE_REFLOW
            debug("items_dirty %s (%s): Queuing draw of dirty area %s on visible_page %s",
                page_name, reason, rectangle_to_string(dirty), rectangle_to_string(visible_page));
#endif
            //queue_draw_area(dirty.x, dirty.y, dirty.width, dirty.height);
            queue_draw();
        }
    }
    
    public override void map() {
        base.map();
        
        set_colors();
    }

    private void set_colors(bool in_focus = true) {
        // set up selected/unselected colors
        var ctx = get_style_context();
        ctx.save();
        ctx.add_class("view");
        ctx.set_state (Gtk.StateFlags.NORMAL);
        ctx.lookup_color("borders", out border_color);
        ctx.lookup_color("theme_fg_color", out unselected_color);

        ctx.set_state (Gtk.StateFlags.FOCUSED);
        ctx.lookup_color("borders", out focus_color);

        // Checked in GtkIconView - The selection is drawn using render_background
        ctx.set_state (Gtk.StateFlags.FOCUSED | Gtk.StateFlags.SELECTED);
        ctx.lookup_color("theme_selected_bg_color", out selected_color);
        ctx.restore();
    }
    
    public override void size_allocate(int a, int b, int c)  {
        base.size_allocate(a, b, c);
        
        viewport_resized();
    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        // Note: It's possible for draw to be called when in_view is false; this happens
        // when pages are switched prior to switched_to() being called, and some of the other
        // controls allow for events to be processed while they are orienting themselves.  Since
        // we want switched_to() to be the final call in the process (indicating that the page is
        // now in place and should do its thing to update itself), have to be be prepared for
        // GTK/GDK calls between the widgets being actually present on the screen and "switched to"

#if TRACE_REFLOW
        debug("draw %s: %s", page_name, rectangle_to_string(visible_page));
#endif

        if (exposure_dirty)
            expose_items("draw");

        // have all items in the exposed area paint themselves
        foreach (CheckerboardItem item in intersection(visible_page)) {
            item.paint(get_style_context(), snapshot, bg_color, item.is_selected() ? selected_color : unselected_color,
                border_color, focus_color);
        }

        // draw the selection band last, so it appears floating over everything else
        draw_selection_band(snapshot);
    }
    
    private void draw_selection_band(Gtk.Snapshot snapshot) {
        // no selection band, nothing to draw
        if (selection_band.width <= 1 || selection_band.height <= 1)
            return;
        
        // This requires adjustments
        if (hadjustment == null || vadjustment == null)
            return;
        
        // find the visible intersection of the viewport and the selection band
        Gdk.Rectangle visible_page = get_adjustment_page(hadjustment, vadjustment);
        Gdk.Rectangle visible_band = Gdk.Rectangle();
        visible_page.intersect(selection_band, out visible_band);

        rubber_band.allocate_size(visible_band, -1);
        snapshot_child(rubber_band, snapshot);
    }
    
    public override bool query_tooltip(int x, int y, bool keyboard_mode, Gtk.Tooltip tooltip) {
        CheckerboardItem? item = get_item_at_pixel(x, y);
        
        // Note: X & Y allocations are relative to parents, so we need to query the item's tooltip
        // relative to its INTERNAL coordinates, otherwise tooltips don't work
        if (item != null) {
            item.translate_coordinates(ref x, ref y);
            return item.query_tooltip(x, y, tooltip);
        } else {
            return false;
        }
    }
    
    private void on_colors_changed() {
        invalidate_transparent_background();
        queue_draw();
    }

    public void focus_in_event() {
        set_colors(true);
        items_dirty("focus_in_event", view.get_selected());
    }

    public void focus_out_event() {
        set_colors(false);
        items_dirty("focus_out_event", view.get_selected());
    }
}
