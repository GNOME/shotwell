/* Copyright 2009-2010 Yorba Foundation
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
    private Gdk.Pixbuf unscaled_pixbuf = null;
    private Cancellable cancellable = null;
    private bool hq_scheduled = false;
    private bool hq_reschedule = false;
    
    public Thumbnail(LibraryPhoto photo, int scale = DEFAULT_SCALE) {
        base(photo, photo.get_dimensions().get_scaled(scale, true), photo.get_name());
        
        this.photo = photo;
        this.scale = scale;
        
        update_tags();
        
        original_dim = photo.get_dimensions();
        dim = original_dim.get_scaled(scale, true);
        
        // if the photo's tags changes, update it here
        Tag.global.container_contents_altered.connect(on_tag_contents_altered);
        Tag.global.item_altered.connect(on_tag_altered);
        photo.altered.connect(on_photo_altered);
    }

    ~Thumbnail() {
        if (cancellable != null)
            cancellable.cancel();
        
        Tag.global.container_contents_altered.disconnect(on_tag_contents_altered);
        Tag.global.item_altered.disconnect(on_tag_altered);
        photo.altered.disconnect(on_photo_altered);
    }
    
    private void update_tags() {
        Gee.Collection<Tag>? tags = Tag.global.fetch_sorted_for_photo(photo);
        if (tags == null || tags.size == 0)
            clear_subtitle();
        else
            set_subtitle(Tag.make_tag_string(tags, "<small>", ", ", "</small>", true), true);
    }
    
    private void on_tag_contents_altered(ContainerSource container, Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        bool tag_added = (added != null) ? added.contains(photo) : false;
        bool tag_removed = (removed != null) ? removed.contains(photo) : false;
        
        // if photo we're monitoring is added or removed to any tag, update tag list
        if (tag_added || tag_removed)
            update_tags();
    }
    
    private void on_tag_altered(DataObject source) {
        Tag tag = (Tag) source;
        
        if (tag.contains(photo))
            update_tags();
    }
    
    private void update_title() {
        string title = photo.get_name();
        if (is_string_empty(title))
            clear_title();
        else
            set_title(title);
    }
    
    private void on_photo_altered(Alteration alteration) {
        if (alteration.has_detail("metadata", "name"))
            update_title();
    }
    
    public LibraryPhoto get_photo() {
        // There's enough overhead with 10,000 photos and casting from get_source() to do it this way
        return photo;
    }
    
    //
    // Comparators
    //

    public static int64 photo_id_ascending_comparator(void *a, void *b) {
        return ((Thumbnail *) a)->photo.get_photo_id().id - ((Thumbnail *) b)->photo.get_photo_id().id;
    }

    public static int64 photo_id_descending_comparator(void *a, void *b) {
        return photo_id_ascending_comparator(b, a);
    }
    
    public static int64 title_ascending_comparator(void *a, void *b) {
        int64 result = strcmp(((Thumbnail *) a)->photo.get_name(), ((Thumbnail *) b)->photo.get_name());
        if (result == 0)
            result = photo_id_ascending_comparator(a, b);
        return result;
    }
    
    public static int64 title_descending_comparator(void *a, void *b) {
        int64 result = title_ascending_comparator(b, a);
        if (result == 0)
            result = photo_id_descending_comparator(a, b);
        return result;
    }
    
    public static int64 exposure_time_ascending_comparator(void *a, void *b) {
        int64 result = ((Thumbnail *) a)->photo.get_exposure_time() - ((Thumbnail *) b)->photo.get_exposure_time();
        if (result == 0)
            result = photo_id_ascending_comparator(a, b);
        return result;
    }
    
    public static int64 exposure_time_desending_comparator(void *a, void *b) {
        int64 result = exposure_time_ascending_comparator(b, a);
        if (result == 0)
            result = photo_id_descending_comparator(a, b);
        return result;
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
        
        if (is_exposed()) {
            // attempt to use an unscaled pixbuf (which is always larger or equal to the current
            // size, and will most likely be larger than the new size -- and if not, a new one will
            // be on its way), then use the current pixbuf if available (which may have to be
            // scaled up, which is ugly)
            Gdk.Pixbuf? resizable = null;
            if (unscaled_pixbuf != null)
                resizable = unscaled_pixbuf;
            else if (has_image())
                resizable = get_image();
            
            if (resizable != null)
                set_image(resize_pixbuf(resizable, dim, LOW_QUALITY_INTERP));
            
            delayed_high_quality_fetch();
        } else {
            clear_image(dim);
        }
    }
    
    private void paint_empty() {
        cancel_async_fetch();
        clear_image(dim);
        unscaled_pixbuf = null;
    }
    
    private void schedule_low_quality_fetch() {
        cancel_async_fetch();
        cancellable = new Cancellable();
        
        ThumbnailCache.fetch_async_scaled(get_photo(), ThumbnailCache.Size.SMALLEST, 
            dim, LOW_QUALITY_INTERP, on_low_quality_fetched, cancellable);
    }
    
    private void delayed_high_quality_fetch() {
        if (hq_scheduled) {
            hq_reschedule = true;
            
            return;
        }
        
        Timeout.add_full(Priority.DEFAULT, HQ_IMPROVEMENT_MSEC, on_schedule_high_quality);
        hq_scheduled = true;
    }
    
    private bool on_schedule_high_quality() {
        if (hq_reschedule) {
            hq_reschedule = false;
            
            return true;
        }
        
        cancel_async_fetch();
        cancellable = new Cancellable();
        
        if (is_exposed()) {
            ThumbnailCache.fetch_async_scaled(get_photo(), scale, dim, HIGH_QUALITY_INTERP,
                on_high_quality_fetched, cancellable);
        }
        
        hq_scheduled = false;
        
        return false;
    }
    
    private void cancel_async_fetch() {
        // cancel outstanding I/O
        if (cancellable != null)
            cancellable.cancel();
    }
    
    private void on_low_quality_fetched(Gdk.Pixbuf? pixbuf, Gdk.Pixbuf? unscaled, Dimensions dim,
        Gdk.InterpType interp, Error? err) {
        if (err != null)
            critical("Unable to fetch low-quality thumbnail for %s (scale: %d): %s", to_string(), scale,
                err.message);
        
        if (pixbuf != null)
            set_image(pixbuf);
        
        if (unscaled != null)
            unscaled_pixbuf = unscaled;
        
        delayed_high_quality_fetch();
    }
    
    private void on_high_quality_fetched(Gdk.Pixbuf? pixbuf, Gdk.Pixbuf? unscaled, Dimensions dim,
        Gdk.InterpType interp, Error? err) {
        if (err != null)
            critical("Unable to fetch high-quality thumbnail for %s (scale: %d): %s", to_string(), scale, 
                err.message);
        
        if (pixbuf != null)
            set_image(pixbuf);
        
        if (unscaled != null)
            unscaled_pixbuf = unscaled;
    }
    
    public override void exposed() {
        if (!has_image())
            schedule_low_quality_fetch();
        
        base.exposed();
    }
    
    public override void unexposed() {
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

