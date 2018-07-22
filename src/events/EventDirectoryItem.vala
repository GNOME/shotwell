/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

class EventDirectoryItem : CheckerboardItem {
    private static int CROPPED_SCALE {
        get {
            return ThumbnailCache.Size.MEDIUM.get_scale() 
                + ((ThumbnailCache.Size.BIG.get_scale() - ThumbnailCache.Size.MEDIUM.get_scale()) / 2);
        }
    }
    
    public static Scaling squared_scaling = Scaling.to_fill_viewport(Dimensions(CROPPED_SCALE,
        CROPPED_SCALE));
    
    public Event event;
    
    private Gdk.Rectangle paul_lynde = Gdk.Rectangle();
    
    public EventDirectoryItem(Event event) {
        base (event, Dimensions(CROPPED_SCALE, CROPPED_SCALE), get_formatted_title(event), event.get_comment(), true,
            Pango.Alignment.CENTER);
        
        this.event = event;
        
        // find the center square
        paul_lynde = get_paul_lynde_rect(event.get_primary_source());
        
        // don't display yet, but claim its dimensions
        clear_image(Dimensions.for_rectangle(paul_lynde));
        
        // monitor the event for changes
        Event.global.items_altered.connect(on_events_altered);
    }
    
    ~EventDirectoryItem() {
        Event.global.items_altered.disconnect(on_events_altered);
    }
    
    // square the photo's dimensions and locate the pixbuf's center square
    private static Gdk.Rectangle get_paul_lynde_rect(MediaSource source) {
        Dimensions scaled = squared_scaling.get_scaled_dimensions(source.get_dimensions());
        
        Gdk.Rectangle paul_lynde = Gdk.Rectangle();
        paul_lynde.x = (scaled.width - CROPPED_SCALE).clamp(0, scaled.width) / 2;
        paul_lynde.y = (scaled.height - CROPPED_SCALE).clamp(0, scaled.height) / 2;
        paul_lynde.width = CROPPED_SCALE;
        paul_lynde.height = CROPPED_SCALE;
        
        return paul_lynde;
    }
    
    // scale and crop the center square of the media
    private static Gdk.Pixbuf get_paul_lynde(MediaSource media, Gdk.Rectangle paul_lynde) throws Error {
        Gdk.Pixbuf pixbuf;

        try {
            pixbuf = media.get_preview_pixbuf(squared_scaling);
        } catch (Error error) {
            ThumbnailCache.fetch_async_scaled(media, ThumbnailCache.Size.BIG,
                                             new Dimensions(ThumbnailCache.Size.BIG, ThumbnailCache.Size.BIG),
                                             ThumbnailCache.DEFAULT_INTERP, () => {});
            if (media is LibraryPhoto) {
                LibraryPhoto photo = (LibraryPhoto) media;
                pixbuf = photo.get_pixbuf(squared_scaling);
            } else {
                throw error;
            }
        }
        
        Dimensions thumbnail_dimensions = Dimensions.for_pixbuf(pixbuf);
        
        if (thumbnail_dimensions.width > 2 * paul_lynde.width ||
            thumbnail_dimensions.height > paul_lynde.height * 2 ) {
            LibraryPhoto photo = (LibraryPhoto) media;
            pixbuf = photo.get_pixbuf(squared_scaling);
            thumbnail_dimensions = Dimensions.for_pixbuf(pixbuf);
        }
        
        // to catch rounding errors in the two algorithms
        paul_lynde = clamp_rectangle(paul_lynde, thumbnail_dimensions);
        
        // crop the center square
        return new Gdk.Pixbuf.subpixbuf(pixbuf, paul_lynde.x, paul_lynde.y, paul_lynde.width,
            paul_lynde.height);
    }
    
    private static string get_formatted_title(Event event) {
        bool has_photos = MediaSourceCollection.has_photo(event.get_media());
        bool has_videos = MediaSourceCollection.has_video(event.get_media());
        
        int count = event.get_media_count();
        string count_text = "";
        if (has_photos && has_videos)
            count_text = ngettext("%d Photo/Video", "%d Photos/Videos", count).printf(count);
        else if (has_videos)
            count_text = ngettext("%d Video", "%d Videos", count).printf(count);
        else
            count_text = ngettext("%d Photo", "%d Photos", count).printf(count);
        
        string? daterange = event.get_formatted_daterange();
        string name = event.get_name();
        
        // if we don't have a daterange or if it's the same as name, then don't print it; otherwise
        // print it beneath the preview photo
        if (daterange == null || daterange == name)
            return "<b>%s</b>\n%s".printf(guarded_markup_escape_text(name),
                guarded_markup_escape_text(count_text));
        else
            return "<b>%s</b>\n%s\n%s".printf(guarded_markup_escape_text(name),
               guarded_markup_escape_text(count_text), guarded_markup_escape_text(daterange));
    }

    public override void exposed() {
        if (is_exposed())
            return;
        
        try {
            set_image(get_paul_lynde(event.get_primary_source(), paul_lynde));
        } catch (Error err) {
            critical("Unable to fetch preview for %s: %s", event.to_string(), err.message);
        }
        
        update_comment();
        
        base.exposed();
    }
    
    public override void unexposed() {
        if (!is_exposed())
            return;
        
        clear_image(Dimensions.for_rectangle(paul_lynde));
        
        base.unexposed();
    }
    
    private void on_events_altered(Gee.Map<DataObject, Alteration> map) {
        update_comment();
        if (map.has_key(event))
            set_title(get_formatted_title(event), true, Pango.Alignment.CENTER);
    }
    
    protected override void thumbnail_altered() {
        MediaSource media = event.get_primary_source();
        
        set_paul_lynde(media);
    }

    private void set_paul_lynde(MediaSource media) {
        // get new center square
        paul_lynde = get_paul_lynde_rect(media);
        
        if (is_exposed()) {
            try {
                set_image(get_paul_lynde(media, paul_lynde));
            } catch (Error err) {
                critical("Unable to fetch preview for %s: %s", event.to_string(), err.message);
            }
        } else {
            clear_image(Dimensions.for_rectangle(paul_lynde));
        }

        base.thumbnail_altered();
    }

    public override void handle_mouse_leave() {
        base.handle_mouse_leave();
        set_paul_lynde(event.get_primary_source());
    }

    public override void handle_mouse_motion(int x, int y, int height, int width) {
        int steppedX = x - (x % 15);
        int element_index = (int) Math.round( (double) steppedX / width * (event.get_media_count() - 1) );
        unowned MediaSource media = event.get_media().to_array()[element_index];
        set_paul_lynde(media);
    }

    protected override void paint_shadow(Cairo.Context ctx, Dimensions dimensions, Gdk.Point origin,
        int radius, float initial_alpha) {       
        Dimensions altered = Dimensions(dimensions.width - 25, dimensions.height - 25);
        base.paint_shadow(ctx, altered, origin, 36, initial_alpha);
    }
    
    protected override void paint_border(Cairo.Context ctx, Dimensions object_dimensions,
        Gdk.Point object_origin, int border_width) {
        Dimensions dimensions = get_border_dimensions(object_dimensions, border_width);
        Gdk.Point origin = get_border_origin(object_origin, border_width);

        draw_rounded_corners_filled(ctx, dimensions, origin, 6.0);
    }

    protected override void paint_image(Cairo.Context ctx, Gdk.Pixbuf pixbuf,
        Gdk.Point origin) {
        Dimensions dimensions = Dimensions.for_pixbuf(pixbuf);

        if (pixbuf.get_has_alpha())
            draw_rounded_corners_filled(ctx, dimensions, origin, 6.0);

        // use rounded corners on events
        context_rounded_corners(ctx, dimensions, origin, 6.0);
        Gdk.cairo_set_source_pixbuf(ctx, pixbuf, origin.x, origin.y);
        ctx.paint();
    }

    private void update_comment(bool init = false) {
        string comment = event.get_comment();
        if (is_string_empty(comment))
            clear_comment();
        else if (!init)
            set_comment(comment);
        else
            set_comment("");
    }
}


