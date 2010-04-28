/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

private class CheckerboardItemText {
    private static int one_line_height = 0;
    
    private string text;
    private bool marked_up;
    private Pango.Alignment alignment;
    private Pango.Layout layout = null;
    private bool single_line = true;
    private int height = 0;
    
    public Gdk.Rectangle allocation = Gdk.Rectangle();
    
    public CheckerboardItemText(string text, Pango.Alignment alignment = Pango.Alignment.LEFT,
        bool marked_up = false) {
        this.text = text;
        this.marked_up = marked_up;
        this.alignment = alignment;
        
        single_line = is_single_line();
    }
    
    private bool is_single_line() {
        return text.chr(-1, '\n') == null;
    }
    
    public bool is_marked_up() {
        return marked_up;
    }
    
    public bool is_set_to(string text, bool marked_up, Pango.Alignment alignment) {
        return (this.marked_up == marked_up && this.alignment == alignment && this.text == text);
    }
    
    public string get_text() {
        return text;
    }
    
    public int get_height() {
        if (height == 0)
            update_height();
        
        return height;
    }
    
    public Pango.Layout get_pango_layout(int max_width = 0) {
        if (layout == null)
            create_pango();
        
        if (max_width > 0)
            layout.set_width(max_width * Pango.SCALE);
        
        return layout;
    }
    
    private void update_height() {
        if (one_line_height != 0 && single_line)
            height = one_line_height;
        else
            create_pango();
    }
    
    private void create_pango() {
        // create layout for this string and ellipsize so it never extends past its laid-down width
        layout = AppWindow.get_instance().create_pango_layout(null);
        if (!marked_up)
            layout.set_text(text, -1);
        else
            layout.set_markup(text, -1);
        
        layout.set_ellipsize(Pango.EllipsizeMode.END);
        layout.set_alignment(alignment);
        
        // getting pixel size is expensive, and we only need the height, so use cached values
        // whenever possible
        if (one_line_height != 0 && single_line) {
            height = one_line_height;
        } else {
            int width;
            layout.get_pixel_size(out width, out height);
            
            // cache first one-line height discovered
            if (one_line_height == 0 && single_line)
                one_line_height = height;
        }
    }
}

public abstract class CheckerboardItem : ThumbnailView {
    // Collection properties CheckerboardItem understands
    // SHOW_TITLES (bool)
    public const string PROP_SHOW_TITLES = "show-titles";
    // SHOW_SUBTITLES (bool)
    public const string PROP_SHOW_SUBTITLES = "show-subtitles";
    
    public const int FRAME_WIDTH = 1;
    public const int LABEL_PADDING = 4;
    public const int FRAME_PADDING = 4;
    public const int BORDER_WIDTH = 1;
    
    public const int TRINKET_SCALE = 12;
    public const int TRINKET_PADDING = 1;
    
    public const int BRIGHTEN_SHIFT = 0x18;
    
    public Dimensions requisition = Dimensions();
    public Gdk.Rectangle allocation = Gdk.Rectangle();
    
    private bool exposure = false;
    private CheckerboardItemText? title = null;
    private bool title_visible = true;
    private CheckerboardItemText? subtitle = null;
    private bool subtitle_visible = false;
    private Gdk.Pixbuf pixbuf = null;
    private Gdk.Pixbuf display_pixbuf = null;
    private Gdk.Pixbuf brightened = null;
    private Dimensions pixbuf_dim = Dimensions();
    private int col = -1;
    private int row = -1;
    
    public CheckerboardItem(ThumbnailSource source, Dimensions initial_pixbuf_dim, string title,
        bool marked_up = false, Pango.Alignment alignment = Pango.Alignment.LEFT) {
        base(source);
        
        pixbuf_dim = initial_pixbuf_dim;
        this.title = new CheckerboardItemText(title, alignment, marked_up);
        
        // Don't calculate size here, wait for the item to be assigned to a ViewCollection
        // (notify_membership_changed) and calculate when the collection's property settings
        // are known
    }
    
    public override string get_name() {
        return (title != null) ? title.get_text() : base.get_name();
    }
    
    public string get_title() {
        return (title != null) ? title.get_text() : "";
    }
    
    public void set_title(string text, bool marked_up = false,
        Pango.Alignment alignment = Pango.Alignment.LEFT) {
        if (title != null && title.is_set_to(text, marked_up, alignment))
            return;
        
        title = new CheckerboardItemText(text, alignment, marked_up);
        
        if (title_visible) {
            recalc_size("set_title");
            notify_view_altered();
        }
    }
    
    public void clear_title() {
        if (title == null)
            return;
        
        title = null;
        
        if (title_visible) {
            recalc_size("clear_title");
            notify_view_altered();
        }
    }
    
    private void set_title_visible(bool visible) {
        if (title_visible == visible)
            return;
        
        title_visible = visible;
        
        recalc_size("set_title_visible");
        notify_view_altered();
    }
    
    public string get_subtitle() {
        return (subtitle != null) ? subtitle.get_text() : "";
    }
    
    public void set_subtitle(string text, bool marked_up = false, 
        Pango.Alignment alignment = Pango.Alignment.LEFT) {
        if (subtitle != null && subtitle.is_set_to(text, marked_up, alignment))
            return;
        
        subtitle = new CheckerboardItemText(text, alignment, marked_up);
        
        if (subtitle_visible) {
            recalc_size("set_subtitle");
            notify_view_altered();
        }
    }
    
    public void clear_subtitle() {
        if (subtitle == null)
            return;
        
        subtitle = null;
        
        if (subtitle_visible) {
            recalc_size("clear_subtitle");
            notify_view_altered();
        }
    }
    
    private void set_subtitle_visible(bool visible) {
        if (subtitle_visible == visible)
            return;
        
        subtitle_visible = visible;
        
        recalc_size("set_subtitle_visible");
        notify_view_altered();
    }
    
    protected override void notify_membership_changed(DataCollection? collection) {
        bool title_visible = (bool) get_collection_property(PROP_SHOW_TITLES, true);
        bool subtitle_visible = (bool) get_collection_property(PROP_SHOW_SUBTITLES, false);
        
        bool altered = false;
        if (this.title_visible != title_visible) {
            this.title_visible = title_visible;
            altered = true;
        }
        
        if (this.subtitle_visible != subtitle_visible) {
            this.subtitle_visible = subtitle_visible;
            altered = true;
        }
        
        if (altered || !requisition.has_area()) {
            recalc_size("notify_membership_changed");
            notify_view_altered();
        }
        
        base.notify_membership_changed(collection);
    }
    
    protected override void notify_collection_property_set(string name, Value? old, Value val) {
        switch (name) {
            case PROP_SHOW_TITLES:
                set_title_visible((bool) val);
            break;
            
            case PROP_SHOW_SUBTITLES:
                set_subtitle_visible((bool) val);
            break;
        }
        
        base.notify_collection_property_set(name, old, val);
    }
    
    // The alignment point is the coordinate on the y-axis (relative to the top of the
    // CheckerboardItem) which this item should be aligned to.  This allows for
    // bottom-alignment along the bottom edge of the thumbnail.
    public int get_alignment_point() {
        return FRAME_WIDTH + FRAME_PADDING + pixbuf_dim.height;
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

    public bool has_image() {
        return pixbuf != null;
    }
    
    public Gdk.Pixbuf? get_image() {
        return pixbuf;
    }
    
    public void set_image(Gdk.Pixbuf pixbuf) {
        this.pixbuf = pixbuf;
        display_pixbuf = pixbuf;
        pixbuf_dim = Dimensions.for_pixbuf(pixbuf);
        
        recalc_size("set_image");
        notify_view_altered();
    }
    
    public void clear_image(Dimensions dim) {
        bool had_image = pixbuf != null;
        
        pixbuf = null;
        display_pixbuf = null;
        pixbuf_dim = dim;
        
        recalc_size("clear_image");
        
        if (had_image)
            notify_view_altered();
    }
    
    public static int get_max_width(int scale) {
        // width is frame width (two sides) + frame padding (two sides) + width of pixbuf (text
        // never wider)
        return (FRAME_WIDTH * 2) + (FRAME_PADDING * 2) + scale;
    }
    
    public virtual Gee.List<Gdk.Pixbuf>? get_trinkets(int scale) {
        return null;
    }
    
    private void recalc_size(string reason) {
        Dimensions old_requisition = requisition;
        
        // only add in the text heights if they're displayed
        int title_height = (title != null && title_visible)
            ? title.get_height() + LABEL_PADDING : 0;
        int subtitle_height = (subtitle != null && subtitle_visible)
            ? subtitle.get_height() + LABEL_PADDING : 0;
        
        // calculate width of all trinkets ... this is important because the trinkets could be
        // wider than the image, in which case need to expand for them
        int trinkets_width = 0;
        Gee.List<Gdk.Pixbuf>? trinkets = get_trinkets(TRINKET_SCALE);
        if (trinkets != null) {
            foreach (Gdk.Pixbuf trinket in trinkets)
                trinkets_width += trinket.get_width() + TRINKET_PADDING;
        }
        
        int image_width = int.max(trinkets_width, pixbuf_dim.width);
        
        // width is frame width (two sides) + frame padding (two sides) + width of pixbuf/trinkets
        // (text never wider)
        requisition.width = (FRAME_WIDTH * 2) + (FRAME_PADDING * 2) + (BORDER_WIDTH * 2)
            + image_width;
        
        // height is frame width (two sides) + frame padding (two sides) + height of pixbuf
        // + height of text + label padding (between pixbuf and text)
        requisition.height = (FRAME_WIDTH * 2) + (FRAME_PADDING * 2) + (BORDER_WIDTH * 2)
            + pixbuf_dim.height + title_height + subtitle_height;
        
#if TRACE_REFLOW_ITEMS
        debug("recalc_size %s: %s title_height=%d subtitle_height=%d requisition=%s", 
            get_source().get_name(), reason, title_height, subtitle_height, requisition.to_string());
#endif
        
        if (!requisition.approx_equals(old_requisition)) {
#if TRACE_REFLOW_ITEMS
            debug("recalc_size %s: %s notifying geometry altered", get_source().get_name(), reason);
#endif
            notify_geometry_altered();
        }
    }
    
    protected virtual void paint_border(Gdk.GC gc, Gdk.Drawable drawable, Dimensions dimensions, 
        Gdk.Point origin) {
        // border should be one pixel wide...if we want to change this later, we should pass it in
        drawable.draw_rectangle(gc, true, origin.x, origin.y, dimensions.width, dimensions.height);
    }
    
    protected virtual void paint_image(Gdk.GC gc, Gdk.Drawable drawable, Gdk.Pixbuf pixbuf, Gdk.Point origin) {
        drawable.draw_pixbuf(gc, display_pixbuf, 0, 0, origin.x, origin.y, -1, -1, 
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    public void paint(Gdk.GC gc, Gdk.Drawable drawable, Gdk.GC? border_gc) {
        // frame of FRAME_WIDTH size (determined by GC) only if selected ... however, this is
        // accounted for in allocation so the frame can appear without resizing the item
        if (is_selected()){
            drawable.draw_rectangle(gc, false, allocation.x, allocation.y, allocation.width - 1,
                pixbuf_dim.height + (FRAME_PADDING * 2) + (BORDER_WIDTH * 2) + FRAME_WIDTH);
        }
        
        // calc the top-left point of the pixbuf
        Gdk.Point pixbuf_origin = Gdk.Point();
        pixbuf_origin.x = allocation.x + FRAME_WIDTH + FRAME_PADDING + BORDER_WIDTH;
        pixbuf_origin.y = allocation.y + FRAME_WIDTH + FRAME_PADDING + BORDER_WIDTH;
        
        // draw border
        if (display_pixbuf != null && border_gc != null) {
            Dimensions border_dimensions = Dimensions.for_pixbuf(display_pixbuf);
            border_dimensions.width += BORDER_WIDTH * 2;
            border_dimensions.height += BORDER_WIDTH * 2;

            Gdk.Point border_origin = Gdk.Point();
            border_origin.x = pixbuf_origin.x - BORDER_WIDTH;
            border_origin.y = pixbuf_origin.y - BORDER_WIDTH;

            paint_border(border_gc, drawable, border_dimensions, border_origin);
        }
        
        if (display_pixbuf != null)
            paint_image(gc, drawable, display_pixbuf, pixbuf_origin);
        
        // get trinkets to determine the max width (pixbuf vs. trinkets)
        int trinkets_width = 0;
        Gee.List<Gdk.Pixbuf>? trinkets = get_trinkets(TRINKET_SCALE);
        if (trinkets != null) {
            foreach (Gdk.Pixbuf trinket in trinkets)
                trinkets_width += trinket.get_width();
        }
        
        int image_width = int.max(trinkets_width, pixbuf_dim.width);
        
        // title and subtitles are LABEL_PADDING below bottom of pixbuf
        int text_y = allocation.y + FRAME_WIDTH + FRAME_PADDING + pixbuf_dim.height + FRAME_PADDING
            + FRAME_WIDTH + LABEL_PADDING;
        if (title != null && title_visible) {
            // get the layout sized so its with is no more than the pixbuf's
            // resize the text width to be no more than the pixbuf's
            title.allocation = { allocation.x + FRAME_WIDTH + FRAME_PADDING, text_y,
                image_width, title.get_height() };
            
            Gdk.draw_layout(drawable, gc, title.allocation.x, title.allocation.y,
                title.get_pango_layout(image_width));
            
            text_y += title.get_height() + LABEL_PADDING;
        }
        
        if (subtitle != null && subtitle_visible) {
            subtitle.allocation = { allocation.x + FRAME_WIDTH + FRAME_PADDING, text_y,
                image_width, subtitle.get_height() };
            
            Gdk.draw_layout(drawable, gc, subtitle.allocation.x, subtitle.allocation.y,
                subtitle.get_pango_layout(image_width));
            
            // increment text_y if more text lines follow
        }
        
        // draw trinkets last
        if (trinkets != null) {
            int current_trinkets_width = 0;
            foreach (Gdk.Pixbuf trinket in trinkets) {
                current_trinkets_width = current_trinkets_width + trinket.get_width() + TRINKET_PADDING;
                drawable.draw_pixbuf(gc, trinket, 0, 0, 
                    pixbuf_origin.x + pixbuf_dim.width - current_trinkets_width,
                    pixbuf_origin.y + pixbuf_dim.height - trinket.get_height() - TRINKET_PADDING, 
                    trinket.get_width(), trinket.get_height(), Gdk.RgbDither.NORMAL, 0, 0);
            }
        }
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
    
    private bool query_tooltip_on_text(CheckerboardItemText text, Gtk.Tooltip tooltip) {
        if (!text.get_pango_layout().is_ellipsized())
            return false;
        
        if (text.is_marked_up())
            tooltip.set_markup(text.get_text());
        else
            tooltip.set_text(text.get_text());
        
        return true;
    }
    
    public bool query_tooltip(int x, int y, Gtk.Tooltip tooltip) {
        if (title != null && title_visible && coord_in_rectangle(x, y, title.allocation))
            return query_tooltip_on_text(title, tooltip);
        
        if (subtitle != null && subtitle_visible && coord_in_rectangle(x, y, subtitle.allocation))
            return query_tooltip_on_text(subtitle, tooltip);
        
        return false;
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
        public CheckerboardItem[] items;
        
        public LayoutRow(int y, int height, int num_in_row) {
            this.y = y;
            this.height = height;
            this.items = new CheckerboardItem[num_in_row];
        }
    }
    
    private static Gdk.Pixbuf selection_interior = null;

    private ViewCollection view;
    private string page_name = "";
    private LayoutRow[] item_rows = null;
    private Gee.HashSet<CheckerboardItem> exposed_items = new Gee.HashSet<CheckerboardItem>();
    private Gtk.Adjustment hadjustment = null;
    private Gtk.Adjustment vadjustment = null;
    private string message = null;
    private Gdk.GC selected_gc = null;
    private Gdk.GC unselected_gc = null;
    private Gdk.GC border_gc = null;
    private Gdk.GC selection_band_gc = null;
    private Gdk.Rectangle visible_page = Gdk.Rectangle();
    private int last_width = 0;
    private int columns = 0;
    private int rows = 0;
    private Gdk.Point drag_origin = Gdk.Point();
    private Gdk.Point drag_endpoint = Gdk.Point();
    private Gdk.Rectangle selection_band = Gdk.Rectangle();
    private uint32 selection_transparency_color = 0;
    private int scale = 0;
    private bool flow_scheduled = false;
    private bool exposure_dirty = true;
    private CheckerboardItem? anchor = null;
    private bool in_center_on_anchor = false;
    private bool size_allocate_due_to_reflow = false;
    private bool display_borders = true;
    
    public CheckerboardLayout(ViewCollection view) {
        this.view = view;
        
        clear_drag_select();
        
        // subscribe to the new collection
        view.contents_altered += on_contents_altered;
        view.items_altered += on_items_altered;
        view.items_metadata_altered += on_items_metadata_altered;
        view.items_state_changed += on_items_state_changed;
        view.items_visibility_changed += on_items_visibility_changed;
        view.ordering_changed += on_ordering_changed;
        view.views_altered += on_views_altered;
        view.geometries_altered += on_geometries_altered;
        view.items_selected += on_items_selection_changed;
        view.items_unselected += on_items_selection_changed;
        
        modify_bg(Gtk.StateType.NORMAL, Config.get_instance().get_bg_color());

        Config.get_instance().colors_changed += on_colors_changed;
        Config.get_instance().display_borders_changed += on_display_borders_changed;

        // CheckerboardItems offer tooltips
        has_tooltip = true;
    }
    
    ~CheckerboardLayout() {
#if TRACE_DTORS
        debug("DTOR: CheckerboardLayout for %s", view.to_string());
#endif

        view.contents_altered -= on_contents_altered;
        view.items_altered -= on_items_altered;
        view.items_metadata_altered -= on_items_metadata_altered;
        view.items_state_changed -= on_items_state_changed;
        view.items_visibility_changed -= on_items_visibility_changed;
        view.ordering_changed -= on_ordering_changed;
        view.views_altered -= on_views_altered;
        view.geometries_altered -= on_geometries_altered;
        view.items_selected -= on_items_selection_changed;
        view.items_unselected -= on_items_selection_changed;
        
        if (hadjustment != null)
            hadjustment.value_changed -= on_viewport_shifted;
        
        if (vadjustment != null)
            vadjustment.value_changed -= on_viewport_shifted;
        
        if (parent != null)
            parent.size_allocate -= on_viewport_resized;

        Config.get_instance().colors_changed -= on_colors_changed;
        Config.get_instance().display_borders_changed -= on_display_borders_changed;
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

        // update the vadjustment's upper manually rather than waiting for GTK to do so
        // because subsequent calculations and settings rely on it ... updating upper 
        // will only happen later, when this event finishes
        vadjustment.set_upper(upper);
  
        double anchor_pos = anchor.allocation.y + (anchor.allocation.height / 2) - 
            (vadjustment.get_page_size() / 2);
        vadjustment.set_value(anchor_pos.clamp(vadjustment.get_lower(), 
            vadjustment.get_upper() - vadjustment.get_page_size()));

        in_center_on_anchor = false;
    }
    
    private void on_contents_altered(Gee.Iterable<DataObject>? added, 
        Gee.Iterable<DataObject>? removed) {
        if (added != null)
            message = null;
        
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
    
    private void on_items_metadata_altered() {
        need_reflow("on_items_metadata_altered");
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
    
    public void set_message(string text) {
        message = text;

        // set the layout's size to be exactly the same as the parent's
        if (parent != null)
            set_size_request(parent.allocation.width, parent.allocation.height);
    }
    
    private void update_visible_page() {
        if (hadjustment != null && vadjustment != null)
            visible_page = get_adjustment_page(hadjustment, vadjustment);
    }
    
    public void set_in_view(bool in_view) {
        if (in_view)
            need_exposure("set_in_view (true)");
        else
            unexpose_items("set_in_view (false)");
    }
    
    public CheckerboardItem? get_item_at_pixel(double xd, double yd) {
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
    
    public Gee.List<CheckerboardItem> get_visible_items() {
        return intersection(visible_page);
    }
    
    public Gee.List<CheckerboardItem> intersection(Gdk.Rectangle area) {
        Gee.ArrayList<CheckerboardItem> intersects = new Gee.ArrayList<CheckerboardItem>();
        
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
                foreach (CheckerboardItem item in row.items) {
                    if (item == null)
                        continue;
                    
                    if (area.intersect(item.allocation, bitbucket))
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
            break;
        }
        
        CheckerboardItem new_item = get_item_at_coordinate(col, row);
        
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
        if (allocation.width != last_width) {
            int old_width = last_width;
            last_width = allocation.width;
            
            need_reflow("viewport_resized (%d -> %d)".printf(old_width, allocation.width));
        } else {
            // don't need to reflow but exposure may have changed
            need_exposure("viewport_resized");
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
        // if set in message mode, nothing to do here
        if (message != null)
            return;
        
        // don't bother until layout is of some appreciable size (even this is too low)
        if (allocation.width <= 1)
            return;
        
        int total_items = view.get_count();
        
        // need to set_size in case all items were removed and the viewport size has changed
        if (total_items == 0) {
            set_size_request(allocation.width, 0);
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
            int remaining_width = allocation.width - (COLUMN_GUTTER_PADDING * 2);
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
                alignment_points = new int[max_rows];
            } else {
                break;
            }
        }

#if TRACE_REFLOW
        debug("reflow %s: width:%d total_width:%d max_cols:%d gutter:%d", page_name, allocation.width, 
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
            item.allocation = { x + xpadding, y + ypadding, req.width, req.height };
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
        
        // Step 6: Define the total size of the page as the size of the allocated width and
        // the height of all the items plus padding
        int total_height = y + row_heights[row] + BOTTOM_PADDING;
        if (total_height != allocation.height) {
#if TRACE_REFLOW
            debug("reflow %s: Changing layout dimensions from %dx%d to %dx%d", page_name, 
                allocation.width, allocation.height, allocation.width, total_height);
#endif
            set_size_request(allocation.width, total_height);
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
            if (!visible_page.intersect(item.allocation, intersection))
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
            queue_draw_area(dirty.x, dirty.y, dirty.width, dirty.height);
        }
    }
    
    private override void map() {
        base.map();

        selected_gc = new Gdk.GC(window);        
        unselected_gc = new Gdk.GC(window);
        border_gc = new Gdk.GC(window); 
        selection_band_gc = new Gdk.GC(window);

        set_colors();
    }

    private void set_colors() {
        if (selected_gc == null || unselected_gc == null || border_gc == null ||
            selection_band_gc == null)
            return;
        
        // set up selected/unselected colors
        Gdk.Color selected_color = fetch_color(
            Config.get_instance().get_selected_color().to_string(), window);
        Gdk.Color unselected_color = fetch_color(
            Config.get_instance().get_unselected_color().to_string(), window);
        Gdk.Color border_color = fetch_color(
            Config.get_instance().get_border_color().to_string(), window);
        selection_transparency_color = convert_rgba(selected_color, 0x40);

        // set up GC's for painting layout items
        Gdk.GCValues gc_values = Gdk.GCValues();
        gc_values.foreground = selected_color;
        gc_values.function = Gdk.Function.COPY;
        gc_values.fill = Gdk.Fill.SOLID;
        gc_values.line_width = CheckerboardItem.FRAME_WIDTH;
        
        Gdk.GCValuesMask mask = 
            Gdk.GCValuesMask.FOREGROUND 
            | Gdk.GCValuesMask.FUNCTION 
            | Gdk.GCValuesMask.FILL
            | Gdk.GCValuesMask.LINE_WIDTH;

        selected_gc.set_values(gc_values, mask);
        
        gc_values.foreground = unselected_color;
        
        unselected_gc.set_values(gc_values, mask);

        gc_values.foreground = border_color;
        
        border_gc.set_values(gc_values, mask);

        gc_values.line_width = 1;
        gc_values.foreground = selected_color;
        
        selection_band_gc.set_values(gc_values, mask);
    }
    
    private override void size_allocate(Gdk.Rectangle allocation) {
        base.size_allocate(allocation);
        
        viewport_resized();
    }
    
    private override bool expose_event(Gdk.EventExpose event) {
        // Note: It's possible for expose_event to be called when in_view is false; this happens
        // when pages are switched prior to switched_to() being called, and some of the other
        // controls allow for events to be processed while they are orienting themselves.  Since
        // we want switched_to() to be the final call in the process (indicating that the page is
        // now in place and should do its thing to update itself), have to be be prepared for
        // GTK/GDK calls between the widgets being actually present on the screen and "switched to"
        
        // watch for message mode
        if (message == null) {
#if TRACE_REFLOW
            debug("expose_event %s: %s", page_name, rectangle_to_string(event.area));
#endif
            
            if (exposure_dirty)
                expose_items("expose_event");
            
            // have all items in the exposed area paint themselves
            foreach (CheckerboardItem item in intersection(event.area))
                item.paint(item.is_selected() ? selected_gc : unselected_gc, window,
                    display_borders ? border_gc : null);
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
    
    private override bool query_tooltip(int x, int y, bool keyboard_mode, Gtk.Tooltip tooltip) {
        CheckerboardItem? item = get_item_at_pixel(x, y);
        
        return (item != null) ? item.query_tooltip(x, y, tooltip) : false;
    }
    
    private void on_colors_changed() {
        modify_bg(Gtk.StateType.NORMAL, Config.get_instance().get_bg_color());
        set_colors();
    }

    private void on_display_borders_changed(bool display_borders) {
        this.display_borders = display_borders;
        need_exposure("on_display_borders_changed");
    }
}
