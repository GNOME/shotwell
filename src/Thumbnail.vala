/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Thumbnail : CheckerboardItem {
    // Collection properties Thumbnail responds to
    // SHOW_TAGS (bool)
    public const string PROP_SHOW_TAGS = CheckerboardItem.PROP_SHOW_SUBTITLES;
    // SIZE (int, scale)
    public const string PROP_SIZE = "thumbnail-size";
    
    public const int MIN_SCALE = 72;
    public const int MAX_SCALE = ThumbnailCache.Size.LARGEST.get_scale();
    public const int DEFAULT_SCALE = ThumbnailCache.Size.MEDIUM.get_scale();
    
    public const Gdk.InterpType LOW_QUALITY_INTERP = Gdk.InterpType.NEAREST;
    public const Gdk.InterpType HIGH_QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    private const int HQ_IMPROVEMENT_MSEC = 100;
    
    private LibraryPhoto photo;
    private int scale;
    private Dimensions original_dim;
    private Dimensions dim;
    private Cancellable cancellable = null;
    private bool hq_scheduled = false;
    
    public Thumbnail(LibraryPhoto photo, int scale = DEFAULT_SCALE) {
        base(photo, photo.get_dimensions().get_scaled(scale, true), photo.get_name());
        
        this.photo = photo;
        this.scale = scale;
        
        update_tags();
        
        original_dim = photo.get_dimensions();
        dim = original_dim.get_scaled(scale, true);
        
        // if the photo's tags changes, update it here
        Tag.global.item_contents_altered += on_tag_contents_altered;
        Tag.global.item_altered += on_tag_altered;
    }

    ~Thumbnail() {
        if (cancellable != null)
            cancellable.cancel();
        
        Tag.global.item_contents_altered -= on_tag_contents_altered;
        Tag.global.item_altered -= on_tag_altered;
    }
    
    private void update_tags() {
        Gee.Collection<Tag>? tags = Tag.global.fetch_sorted_for_photo(photo);
        if (tags == null || tags.size == 0)
            clear_subtitle();
        else
            set_subtitle(Tag.make_tag_string(tags, "<small>", ", ", "</small>"), true);
    }
    
    private void on_tag_contents_altered(Tag tag, Gee.Collection<LibraryPhoto>? added,
        Gee.Collection<LibraryPhoto>? removed) {
        bool tag_added = (added != null) ? added.contains(photo) : false;
        bool tag_removed = (removed != null) ? removed.contains(photo) : false;
        
        // if photo we're monitoring is added or removed to any tag, update tag list
        if (tag_added || tag_removed)
            update_tags();
    }
    
    private void on_tag_altered(DataObject source) {
        Tag tag = (Tag) source;
        
        if (tag.get_photos().contains(photo))
            update_tags();
    }
    
    public LibraryPhoto get_photo() {
        // There's enough overhead with 10,000 photos and casting from get_source() to do it this way
        return photo;
    }
    
    //
    // Comparators
    //
    
    public static int64 title_ascending_comparator(void *a, void *b) {
        return strcmp(((Thumbnail *) a)->get_title(), ((Thumbnail *) b)->get_title());
    }
    
    public static int64 title_descending_comparator(void *a, void *b) {
        return title_ascending_comparator(b, a);
    }
    
    public static int64 exposure_time_ascending_comparator(void *a, void *b) {
        return ((Thumbnail *) a)->photo.get_exposure_time() - ((Thumbnail *) b)->photo.get_exposure_time();
    }
    
    public static int64 exposure_time_desending_comparator(void *a, void *b) {
        return exposure_time_ascending_comparator(b, a);
    }
    
    private override void thumbnail_altered() {
        original_dim = get_photo().get_dimensions();
        dim = original_dim.get_scaled(scale, true);
        
        if (is_exposed())
            schedule_low_quality_fetch();
        else
            paint_empty();
        
        base.thumbnail_altered();
    }
    
    protected override void notify_collection_property_set(string name, Value? old, Value val) {
        switch (name) {
            case PROP_SIZE:
                resize((int) val);
            break;
        }
        
        base.notify_collection_property_set(name, old, val);
    }
    
    private void resize(int new_scale) {
        assert(new_scale >= MIN_SCALE);
        assert(new_scale <= MAX_SCALE);
        
        if (scale == new_scale)
            return;
        
        scale = new_scale;
        dim = original_dim.get_scaled(scale, true);
        
        cancel_async_fetch();
        
        if (is_exposed() && has_image())
            set_image(resize_pixbuf(get_image(), dim, LOW_QUALITY_INTERP));
        else
            clear_image(dim);
        
        schedule_high_quality_fetch();
    }
    
    private void paint_empty() {
        cancel_async_fetch();
        clear_image(dim);
    }
    
    private void schedule_low_quality_fetch() {
        cancel_async_fetch();
        cancellable = new Cancellable();
        
        ThumbnailCache.fetch_async_scaled(get_photo().get_photo_id(), ThumbnailCache.Size.SMALLEST, 
            dim, LOW_QUALITY_INTERP, on_low_quality_fetched, cancellable);
    }
    
    private void schedule_high_quality_fetch() {
        if (hq_scheduled)
            return;
        
        Timeout.add_full(Priority.DEFAULT, HQ_IMPROVEMENT_MSEC, on_schedule_high_quality);
        hq_scheduled = true;
    }
    
    private bool on_schedule_high_quality() {
        // cancel outstanding I/O
        if (cancellable != null)
            cancellable.cancel();
        cancellable = new Cancellable();
        
        ThumbnailCache.fetch_async_scaled(get_photo().get_photo_id(), scale, dim, HIGH_QUALITY_INTERP,
            on_high_quality_fetched, cancellable);
        
        hq_scheduled = false;
        
        return false;
    }
    
    private void cancel_async_fetch() {
        // cancel outstanding I/O
        if (cancellable != null)
            cancellable.cancel();
    }
    
    private void on_low_quality_fetched(Gdk.Pixbuf? pixbuf, Dimensions dim, Gdk.InterpType interp, 
        Error? err) {
        if (err != null)
            critical("Unable to fetch low-quality thumbnail for %s (scale: %d): %s", to_string(), scale,
                err.message);
        
        if (pixbuf != null)
            set_image(pixbuf);
        
        schedule_high_quality_fetch();
    }
    
    private void on_high_quality_fetched(Gdk.Pixbuf? pixbuf, Dimensions dim, Gdk.InterpType interp, 
        Error? err) {
        if (err != null)
            critical("Unable to fetch high-quality thumbnail for %s (scale: %d): %s", to_string(), scale, 
                err.message);
        
        if (pixbuf != null)
            set_image(pixbuf);
    }
    
    public override void exposed() {
        if (!is_exposed() || !has_image())
            schedule_low_quality_fetch();
        
        base.exposed();
    }
    
    public override void unexposed() {
        cancel_async_fetch();
        
        if (is_exposed() || has_image())
            paint_empty();
        
        base.unexposed();
    }
    
    public override Gee.List<Gdk.Pixbuf>? get_trinkets(int scale) {
        LibraryPhoto photo = get_photo();
        
        // don't let the hose run
        if (!photo.is_hidden() && !photo.is_favorite())
            return null;
        
        Gee.List<Gdk.Pixbuf> trinkets = new Gee.ArrayList<Gdk.Pixbuf>();
        
        if (photo.is_hidden())
            trinkets.add(Resources.get_icon(Resources.ICON_HIDDEN, scale));
        
        if (photo.is_favorite())
            trinkets.add(Resources.get_icon(Resources.ICON_FAVORITE, scale));
        
        return trinkets;
    }
}

