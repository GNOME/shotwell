/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public abstract class CheckerboardItem : ThumbnailView {
    // Collection properties CheckerboardItem understands
    // SHOW_TITLES (bool)
    public const string PROP_SHOW_TITLES = "show-titles";
    // SHOW_COMMENTS (bool)
    public const string PROP_SHOW_COMMENTS = "show-comments";
    // SHOW_SUBTITLES (bool)
    public const string PROP_SHOW_SUBTITLES = "show-subtitles";
    
    public const int FRAME_WIDTH = 8;
    public const int LABEL_PADDING = 4;
    public const int BORDER_WIDTH = 1;

    public const int SHADOW_RADIUS = 4;
    public const float SHADOW_INITIAL_ALPHA = 0.5f;
    
    public const int TRINKET_SCALE = 12;
    public const int TRINKET_PADDING = 1;
    
    public const int BRIGHTEN_SHIFT = 0x18;
    
    public Dimensions requisition = Dimensions();
    public Gdk.Rectangle allocation = Gdk.Rectangle();
    
    private bool exposure = false;
    private CheckerboardItemText? title = null;
    private bool title_visible = true;
    private CheckerboardItemText? comment = null;
    private bool comment_visible = true;
    private CheckerboardItemText? subtitle = null;
    private bool subtitle_visible = false;
    private bool is_cursor = false;
    private Pango.Alignment tag_alignment = Pango.Alignment.LEFT;
    private Gee.List<Tag>? user_visible_tag_list = null;
    private Gee.Collection<Tag> tags;
    private Gdk.Pixbuf pixbuf = null;
    private Gdk.Pixbuf display_pixbuf = null;
    private Gdk.Pixbuf brightened = null;
    private Dimensions pixbuf_dim = Dimensions();
    private int col = -1;
    private int row = -1;
    private int horizontal_trinket_offset = 0;
    
    protected CheckerboardItem(ThumbnailSource source, Dimensions initial_pixbuf_dim, string title, string? comment,
        bool marked_up = false, Pango.Alignment alignment = Pango.Alignment.LEFT) {
        base(source);
        
        pixbuf_dim = initial_pixbuf_dim;
        this.title = new CheckerboardItemText(title, alignment, marked_up);
        // on the checkboard page we display the comment in 
        // one line, i.e., replacing all newlines with spaces.
        // that means that the display will contain "..." if the comment
        // is too long.
        // warning: changes here have to be done in set_comment, too!
        if (comment != null)
            this.comment = new CheckerboardItemText(comment.replace("\n", " "), alignment,
                marked_up);
        
        // Don't calculate size here, wait for the item to be assigned to a ViewCollection
        // (notify_membership_changed) and calculate when the collection's property settings
        // are known
    }

    public bool has_tags { get; private set; }

    public override string get_name() {
        return (title != null) ? title.get_text() : base.get_name();
    }
    
    public string get_title() {
        return (title != null) ? title.get_text() : "";
    }
    
    public string get_comment() {
        return (comment != null) ? comment.get_text() : "";
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

    public void translate_coordinates(ref int x, ref int y) {
        x -= allocation.x + FRAME_WIDTH;
        y -= allocation.y + FRAME_WIDTH;
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
    
    public void set_comment(string text, bool marked_up = false,
        Pango.Alignment alignment = Pango.Alignment.LEFT) {
        if (comment != null && comment.is_set_to(text, marked_up, alignment))
            return;
        
        comment = new CheckerboardItemText(text.replace("\n", " "), alignment, marked_up);
        
        if (comment_visible) {
            recalc_size("set_comment");
            notify_view_altered();
        }
    }
    
    public void clear_comment() {
        if (comment == null)
            return;
        
        comment = null;
        
        if (comment_visible) {
            recalc_size("clear_comment");
            notify_view_altered();
        }
    }
    
    private void set_comment_visible(bool visible) {
        if (comment_visible == visible)
            return;
        
        comment_visible = visible;
        
        recalc_size("set_comment_visible");
        notify_view_altered();
    }

    public void set_tags(Gee.Collection<Tag>? tags,
            Pango.Alignment alignment = Pango.Alignment.LEFT) {
        has_tags = (tags != null && tags.size > 0);
        tag_alignment = alignment;
        string text;
        if (has_tags) {
            this.tags = tags;
            user_visible_tag_list = Tag.make_user_visible_tag_list(tags);
            text = Tag.make_tag_markup_string(user_visible_tag_list);
        } else {
            text = "<small>.</small>";
        }

        if (subtitle != null && subtitle.is_set_to(text, true, alignment))
            return;
        subtitle = new CheckerboardItemText(text, alignment, true);

        if (subtitle_visible) {
            recalc_size("set_subtitle");
            notify_view_altered();
        }
    }

    public void clear_tags() {
        clear_subtitle();
        has_tags = false;
        user_visible_tag_list = null;
    }

    public void highlight_user_visible_tag(int index)
            requires (user_visible_tag_list != null) {
        string text = Tag.make_tag_markup_string(user_visible_tag_list, index);
        subtitle = new CheckerboardItemText(text, tag_alignment, true);

        if (subtitle_visible)
            notify_view_altered();
    }

    public Tag get_user_visible_tag(int index)
            requires (index >= 0 && index < user_visible_tag_list.size) {
        return user_visible_tag_list.get(index);
    }

    public Pango.Layout? get_tag_list_layout() {
        return has_tags ? subtitle.get_pango_layout() : null;
    }

    public Gdk.Rectangle get_subtitle_allocation() {
        return subtitle.allocation;
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

    public void set_is_cursor(bool is_cursor) {
        this.is_cursor = is_cursor;
    }

    public bool get_is_cursor() {
        return is_cursor;
    }
    
    public virtual void handle_mouse_motion(int x, int y, int height, int width) {

    }

    public virtual void handle_mouse_leave() {
        unbrighten();
    }

    public virtual void handle_mouse_enter() {
        brighten();
    }

    protected override void notify_membership_changed(DataCollection? collection) {
        bool title_visible = (bool) get_collection_property(PROP_SHOW_TITLES, true);
        bool comment_visible = (bool) get_collection_property(PROP_SHOW_COMMENTS, true);
        bool subtitle_visible = (bool) get_collection_property(PROP_SHOW_SUBTITLES, false);
        
        bool altered = false;
        if (this.title_visible != title_visible) {
            this.title_visible = title_visible;
            altered = true;
        }
        
        if (this.comment_visible != comment_visible) {
            this.comment_visible = comment_visible;
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
            
            case PROP_SHOW_COMMENTS:
                set_comment_visible((bool) val);
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
        return FRAME_WIDTH + BORDER_WIDTH + pixbuf_dim.height;
    }
    
    public virtual void exposed() {
        exposure = true;
    }
    
    public virtual void unexposed() {
        exposure = false;
        
        if (title != null)
            title.clear_pango_layout();
        
        if (comment != null)
            comment.clear_pango_layout();
        
        if (subtitle != null)
            subtitle.clear_pango_layout();
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
        return (FRAME_WIDTH * 2) + scale;
    }
    
    private void recalc_size(string reason) {
        Dimensions old_requisition = requisition;
        
        // only add in the text heights if they're displayed
        int title_height = (title != null && title_visible)
            ? title.get_height() + LABEL_PADDING : 0;
        int comment_height = (comment != null && comment_visible)
            ? comment.get_height() + LABEL_PADDING : 0;
        int subtitle_height = (subtitle != null && subtitle_visible)
            ? subtitle.get_height() + LABEL_PADDING : 0;
        
        // width is frame width (two sides) + frame padding (two sides) + width of pixbuf
        // (text never wider)
        requisition.width = (FRAME_WIDTH * 2) + (BORDER_WIDTH * 2) + pixbuf_dim.width;
        
        // height is frame width (two sides) + frame padding (two sides) + height of pixbuf
        // + height of text + label padding (between pixbuf and text)
        requisition.height = (FRAME_WIDTH * 2) + (BORDER_WIDTH * 2)
            + pixbuf_dim.height + title_height + comment_height + subtitle_height;
        
#if TRACE_REFLOW_ITEMS
        debug("recalc_size %s: %s title_height=%d comment_height=%d subtitle_height=%d requisition=%s", 
            get_source().get_name(), reason, title_height, comment_height, subtitle_height,
            requisition.to_string());
#endif
        
        if (!requisition.approx_equals(old_requisition)) {
#if TRACE_REFLOW_ITEMS
            debug("recalc_size %s: %s notifying geometry altered", get_source().get_name(), reason);
#endif
            notify_geometry_altered();
        }
    }
    
    protected static Dimensions get_border_dimensions(Dimensions object_dim, int border_width) {
        Dimensions dimensions = Dimensions();
        dimensions.width = object_dim.width + (border_width * 2);
        dimensions.height = object_dim.height + (border_width * 2);
        return dimensions;
    }
    
    protected static Gdk.Point get_border_origin(Gdk.Point object_origin, int border_width) {
        Gdk.Point origin = Gdk.Point();
        origin.x = object_origin.x - border_width;
        origin.y = object_origin.y - border_width;
        return origin;
    }

    protected virtual void paint_shadow(Cairo.Context ctx, Dimensions dimensions, Gdk.Point origin, 
        int radius, float initial_alpha) { 
        double rgb_all = 0.0;
        
        // top right corner
        paint_shadow_in_corner(ctx, origin.x + dimensions.width, origin.y + radius, rgb_all, radius, 
            initial_alpha, -0.5 * Math.PI, 0);
        // bottom right corner
        paint_shadow_in_corner(ctx, origin.x + dimensions.width, origin.y + dimensions.height, rgb_all, 
            radius, initial_alpha, 0, 0.5 * Math.PI);
        // bottom left corner
        paint_shadow_in_corner(ctx, origin.x + radius, origin.y + dimensions.height, rgb_all, radius, 
            initial_alpha, 0.5 * Math.PI, Math.PI);

        // left right 
        Cairo.Pattern lr = new Cairo.Pattern.linear(0, origin.y + dimensions.height, 
            0, origin.y + dimensions.height + radius);
        lr.add_color_stop_rgba(0.0, rgb_all, rgb_all, rgb_all, initial_alpha);
        lr.add_color_stop_rgba(1.0, rgb_all, rgb_all, rgb_all, 0.0);
        ctx.set_source(lr);
        ctx.rectangle(origin.x + radius, origin.y + dimensions.height, dimensions.width - radius, radius);
        ctx.fill();

        // top down
        Cairo.Pattern td = new Cairo.Pattern.linear(origin.x + dimensions.width, 
            0, origin.x + dimensions.width + radius, 0);
        td.add_color_stop_rgba(0.0, rgb_all, rgb_all, rgb_all, initial_alpha);
        td.add_color_stop_rgba(1.0, rgb_all, rgb_all, rgb_all, 0.0);
        ctx.set_source(td);
        ctx.rectangle(origin.x + dimensions.width, origin.y + radius, 
            radius, dimensions.height - radius);
        ctx.fill();
    }

    protected void paint_shadow_in_corner(Cairo.Context ctx, int x, int y, 
	double rgb_all, float radius, float initial_alpha, double arc1, double arc2) {
        Cairo.Pattern p = new Cairo.Pattern.radial(x, y, 0, x, y, radius);
        p.add_color_stop_rgba(0.0, rgb_all, rgb_all, rgb_all, initial_alpha);
        p.add_color_stop_rgba(1.0, rgb_all, rgb_all, rgb_all, 0);
        ctx.set_source(p);
        ctx.move_to(x, y);
        ctx.arc(x, y, radius, arc1, arc2);
        ctx.close_path();
        ctx.fill(); 
    }

    protected virtual void paint_border(Cairo.Context ctx, Dimensions object_dimensions,
        Gdk.Point object_origin, int border_width) {
        if (border_width == 1) {
            ctx.rectangle(object_origin.x - border_width, object_origin.y - border_width,
                object_dimensions.width + (border_width * 2),
                object_dimensions.height + (border_width * 2));
            ctx.fill();
        } else {
            Dimensions dimensions = get_border_dimensions(object_dimensions, border_width);
            Gdk.Point origin = get_border_origin(object_origin, border_width);
            
            // amount of rounding needed on corners varies by size of object
            double scale = int.max(object_dimensions.width, object_dimensions.height);
            draw_rounded_corners_filled(ctx, dimensions, origin, 0.25 * scale);
        }
    }

    protected virtual void paint_image(Cairo.Context ctx, Gdk.Pixbuf pixbuf, Gdk.Point origin) {
        paint_pixmap_with_background(ctx, pixbuf, origin.x, origin.y);
    }

    private int get_selection_border_width(int scale) {
        return ((scale <= ((Thumbnail.MIN_SCALE + Thumbnail.MAX_SCALE) / 3)) ? 5 : 4)
            + BORDER_WIDTH;
    }
    
    protected virtual Gdk.Pixbuf? get_top_left_trinket(int scale) {
        return null;
    }
    
    protected virtual Gdk.Pixbuf? get_top_right_trinket(int scale) {
        return null;
    }
    
    protected virtual Gdk.Pixbuf? get_bottom_left_trinket(int scale) {
        return null;
    }
    
    protected virtual Gdk.Pixbuf? get_bottom_right_trinket(int scale) {
        return null;
    }
    
    public void paint(Gtk.StyleContext style_context, Cairo.Context ctx, Gdk.RGBA bg_color, Gdk.RGBA selected_color,
        Gdk.RGBA? border_color, Gdk.RGBA? focus_color) {
        ctx.save();
        ctx.translate(allocation.x + FRAME_WIDTH,
                      allocation.y + FRAME_WIDTH);
        // calc the top-left point of the pixbuf
        Gdk.Point pixbuf_origin = Gdk.Point();
        pixbuf_origin.x = BORDER_WIDTH;
        pixbuf_origin.y = BORDER_WIDTH;
        
        ctx.set_line_width(FRAME_WIDTH);
        ctx.set_source_rgba(selected_color.red, selected_color.green, selected_color.blue,
            selected_color.alpha);

        // draw shadow
        if (border_color != null) {
            ctx.save();
            Dimensions shadow_dim = Dimensions();
            shadow_dim.width = pixbuf_dim.width + BORDER_WIDTH;
            shadow_dim.height = pixbuf_dim.height + BORDER_WIDTH;
            paint_shadow(ctx, shadow_dim, pixbuf_origin, SHADOW_RADIUS, SHADOW_INITIAL_ALPHA);
            ctx.restore();
        }
        
        // draw a border for the cursor with the selection width and normal border color
        if (is_cursor) {
            ctx.save();
            ctx.set_source_rgba(focus_color.red, focus_color.green, focus_color.blue,
                    focus_color.alpha);
            paint_border(ctx, pixbuf_dim, pixbuf_origin,
                get_selection_border_width(int.max(pixbuf_dim.width, pixbuf_dim.height)));
            ctx.restore();
        }
        
        // draw selection border
        if (is_selected()) {
            // border thickness depends on the size of the thumbnail
            ctx.save();
            paint_border(ctx, pixbuf_dim, pixbuf_origin,
                get_selection_border_width(int.max(pixbuf_dim.width, pixbuf_dim.height)));
            ctx.restore();
        }
        
        if (display_pixbuf != null) {
            ctx.save();
            ctx.set_source_rgba(bg_color.red, bg_color.green, bg_color.blue, bg_color.alpha);
            paint_image(ctx, display_pixbuf, pixbuf_origin);
            ctx.restore();
        }
        
        // title and subtitles are LABEL_PADDING below bottom of pixbuf
        int text_y = pixbuf_dim.height + FRAME_WIDTH + LABEL_PADDING;
        if (title != null && title_visible) {
            // get the layout sized so its width is no more than the pixbuf's
            // resize the text width to be no more than the pixbuf's
            title.allocation.x = 0;
            title.allocation.y = text_y;
            title.allocation.width = pixbuf_dim.width;
            title.allocation.height = title.get_height();
            style_context.render_layout(ctx, title.allocation.x, title.allocation.y,
                    title.get_pango_layout(pixbuf_dim.width));

            text_y += title.get_height() + LABEL_PADDING;
        }

        if (comment != null && comment_visible) {
            comment.allocation.x = 0;
            comment.allocation.y = text_y;
            comment.allocation.width = pixbuf_dim.width;
            comment.allocation.height = comment.get_height();
            style_context.render_layout(ctx, comment.allocation.x, comment.allocation.y,
                    comment.get_pango_layout(pixbuf_dim.width));

            text_y += comment.get_height() + LABEL_PADDING;
        }

        if (subtitle != null && subtitle_visible) {
            subtitle.allocation.x = 0;
            subtitle.allocation.y = text_y;
            subtitle.allocation.width = pixbuf_dim.width;
            subtitle.allocation.height = subtitle.get_height();

            style_context.render_layout(ctx, subtitle.allocation.x, subtitle.allocation.y,
                    subtitle.get_pango_layout(pixbuf_dim.width));

            // increment text_y if more text lines follow
        }
        
        ctx.set_source_rgba(selected_color.red, selected_color.green, selected_color.blue,
            selected_color.alpha);
        
        // draw trinkets last
        Gdk.Pixbuf? trinket = get_bottom_left_trinket(TRINKET_SCALE);
        if (trinket != null) {
            int x = pixbuf_origin.x + TRINKET_PADDING + get_horizontal_trinket_offset();
            int y = pixbuf_origin.y + pixbuf_dim.height - trinket.get_height() -
                TRINKET_PADDING;
            Gdk.cairo_set_source_pixbuf(ctx, trinket, x, y);
            ctx.rectangle(x, y, trinket.get_width(), trinket.get_height());
            ctx.fill();
        }
        
        trinket = get_top_left_trinket(TRINKET_SCALE);
        if (trinket != null) {
            int x = pixbuf_origin.x + TRINKET_PADDING + get_horizontal_trinket_offset();
            int y = pixbuf_origin.y + TRINKET_PADDING;
            Gdk.cairo_set_source_pixbuf(ctx, trinket, x, y);
            ctx.rectangle(x, y, trinket.get_width(), trinket.get_height());
            ctx.fill();
        }
        
        trinket = get_top_right_trinket(TRINKET_SCALE);
        if (trinket != null) {
            int x = pixbuf_origin.x + pixbuf_dim.width - trinket.width - 
                get_horizontal_trinket_offset() - TRINKET_PADDING;
            int y = pixbuf_origin.y + TRINKET_PADDING;
            Gdk.cairo_set_source_pixbuf(ctx, trinket, x, y);
            ctx.rectangle(x, y, trinket.get_width(), trinket.get_height());
            ctx.fill();
        }
        
        trinket = get_bottom_right_trinket(TRINKET_SCALE);
        if (trinket != null) {
            int x = pixbuf_origin.x + pixbuf_dim.width - trinket.width - 
                get_horizontal_trinket_offset() - TRINKET_PADDING;
            int y = pixbuf_origin.y + pixbuf_dim.height - trinket.height - 
                TRINKET_PADDING;
            Gdk.cairo_set_source_pixbuf(ctx, trinket, x, y);
            ctx.rectangle(x, y, trinket.get_width(), trinket.get_height());
            ctx.fill();
        }
        ctx.restore();
    }
    
    protected void set_horizontal_trinket_offset(int horizontal_trinket_offset) {
        assert(horizontal_trinket_offset >= 0);
        this.horizontal_trinket_offset = horizontal_trinket_offset;
    }
    
    protected int get_horizontal_trinket_offset() {
        return horizontal_trinket_offset;
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
        
        base.visibility_changed(visible);
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
        
        if (comment != null && comment_visible && coord_in_rectangle(x, y, comment.allocation))
            return query_tooltip_on_text(comment, tooltip);
        
        if (subtitle != null && subtitle_visible && coord_in_rectangle(x, y, subtitle.allocation))
            return query_tooltip_on_text(subtitle, tooltip);
        
        return false;
    }
}


