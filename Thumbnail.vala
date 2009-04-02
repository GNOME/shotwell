
public class Thumbnail : Gtk.Alignment {
    public static const int LABEL_PADDING = 4;
    public static const int FRAME_PADDING = 4;
    public static const string TEXT_COLOR = "#FFF";
    public static const string SELECTED_COLOR = "#FF0";
    public static const string UNSELECTED_COLOR = "#FFF";
    
    public static const int MIN_SCALE = 64;
    public static const int MAX_SCALE = 360;
    public static const int DEFAULT_SCALE = 128;
    public static const Gdk.InterpType LOW_QUALITY_INTERP = Gdk.InterpType.NEAREST;
    public static const Gdk.InterpType HIGH_QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    // Due to the potential for thousands or tens of thousands of thumbnails being present in a
    // particular view, all widgets used here should be NOWINDOW widgets.
    private PhotoID photoID;
    private File file;
    private int scale;
    private Gtk.Image image = new Gtk.Image();
    private Gtk.Label title = null;
    private Gtk.Frame frame = null;
    private bool selected = false;
    private Dimensions originalDim;
    private Dimensions scaledDim;
    private Gdk.Pixbuf cached = null;
    private Gdk.InterpType scaledInterp = LOW_QUALITY_INTERP;
    private PhotoExif exif;
    
    public Thumbnail(PhotoID photoID, File file, int scale = DEFAULT_SCALE) {
        this.photoID = photoID;
        this.file = file;
        this.scale = scale;
        this.exif = new PhotoExif(file);
        this.originalDim = new PhotoTable().get_dimensions(photoID);
        this.scaledDim = get_scaled_dimensions(originalDim, scale);
        this.scaledDim = get_rotated_dimensions(scaledDim, exif.get_orientation());

        // bottom-align everything
        set(0, 1, 0, 0);
        
        // the image widget is only filled with a Pixbuf when exposed; if the pixbuf is cleared or
        // not present, the widget will collapse, and so the layout manager won't account for it
        // properly when it's off the viewport.  The solution is to manually set the widget's
        // requisition size, even when it contains no pixbuf
        image.set_size_request(scaledDim.width, scaledDim.height);
        
        title = new Gtk.Label(build_unexposed_title());
        title.set_use_underline(false);
        title.set_justify(Gtk.Justification.LEFT);
        title.set_alignment(0, 0);
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(TEXT_COLOR));
        
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.set_border_width(FRAME_PADDING);
        vbox.pack_start(image, false, false, 0);
        vbox.pack_end(title, false, false, LABEL_PADDING);
        
        frame = new Gtk.Frame(null);
        frame.set_shadow_type(Gtk.ShadowType.NONE);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        frame.add(vbox);

        add(frame);
    }

    public File get_file() {
        return file;
    }
    
    public PhotoID get_photo_id() {
        return photoID;
    }
    
    private string build_exposed_title() {
        int64 fileSize = 0;
        try {
            FileInfo info = file.query_info(FILE_ATTRIBUTE_STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            fileSize = info.get_size();
        } catch(Error err) {
            error("%s", err.message);
        }
        
        Dimensions dim;
        bool dimFound = exif.get_dimensions(out dim);

        string datetime = exif.get_datetime();
        
        return "%s\n%s\n%s\n%lld bytes".printf(
            file.get_basename(), 
            (datetime != null) ? datetime : "",
            (dimFound) ? "%d x %d".printf(dim.width, dim.height) : "",
            fileSize);
    }
    
    private string build_unexposed_title() {
        return "%s\n\n\n".printf(file.get_basename());
    }
    
    public void select() {
        selected = true;

        frame.set_shadow_type(Gtk.ShadowType.OUT);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
    }

    public void unselect() {
        selected = false;

        frame.set_shadow_type(Gtk.ShadowType.NONE);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
    }

    public bool toggle_select() {
        if (selected) {
            unselect();
        } else {
            select();
        }
        
        return selected;
    }

    public bool is_selected() {
        return selected;
    }

    public void resize(int newScale) {
        assert(newScale >= MIN_SCALE);
        assert(newScale <= MAX_SCALE);
        
        if (scale == newScale)
            return;

        int oldScale = scale;
        scale = newScale;
        scaledDim = get_scaled_dimensions(originalDim, scale);
        scaledDim = get_rotated_dimensions(scaledDim, exif.get_orientation());

        // only fetch and scale if exposed        
        if (cached != null) {
            if (ThumbnailCache.refresh_pixbuf(oldScale, newScale)) {
                cached = ThumbnailCache.fetch(photoID, newScale);
                cached = rotate_to_exif(cached, exif.get_orientation());
            }
            
            Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, LOW_QUALITY_INTERP);
            scaledInterp = LOW_QUALITY_INTERP;
            image.set_from_pixbuf(scaled);
        }

        // set the image widget's size regardless of the presence of an image
        image.set_size_request(scaledDim.width, scaledDim.height);
    }
    
    public void paint_high_quality() {
        if (cached == null)
            return;
        
        if (scaledInterp == HIGH_QUALITY_INTERP)
            return;
        
        // only go through the scaling if indeed the image is going to be scaled ... although
        // scale_simple() will probably just return the pixbuf if it sees the stupid case, Gtk.Image
        // does not, and will fire off resized events when the new image (which is not really new)
        // is added
        if ((cached.get_width() != scaledDim.width) || (cached.get_height() != scaledDim.height)) {
            Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, HIGH_QUALITY_INTERP);
            image.set_from_pixbuf(scaled);
        }

        scaledInterp = HIGH_QUALITY_INTERP;
    }
    
    public void exposed() {
        if (cached != null)
            return;

        title.set_text(build_exposed_title());
        cached = ThumbnailCache.fetch(photoID, scale);
        cached = rotate_to_exif(cached, exif.get_orientation());
        Gdk.Pixbuf scaled = cached.scale_simple(scaledDim.width, scaledDim.height, LOW_QUALITY_INTERP);
        scaledInterp = LOW_QUALITY_INTERP;
        image.set_from_pixbuf(scaled);
        image.set_size_request(scaledDim.width, scaledDim.height);
    }
    
    public void unexposed() {
        if (cached == null)
            return;

        title.set_text(build_unexposed_title());
        cached = null;
        image.clear();
        image.set_size_request(scaledDim.width, scaledDim.height);
    }
    
    public bool is_exposed() {
        return (cached != null);
    }
}

