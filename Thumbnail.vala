
public class Thumbnail : Gtk.Alignment {
    public static const int LABEL_PADDING = 4;
    public static const int FRAME_PADDING = 4;
    public static const string TEXT_COLOR = "#FFF";
    public static const string SELECTED_COLOR = "#FF0";
    public static const string UNSELECTED_COLOR = "#FFF";
    
    public static const int MIN_SCALE = 64;
    public static const int MAX_SCALE = 360;
    public static const int DEFAULT_SCALE = 128;
    public static const int SCALE_STEPPING = 4;
    public static const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.NEAREST;
    
    // Due to the potential for thousands or tens of thousands of thumbnails being present in a
    // particular view, all widgets used here should be NOWINDOW widgets.
    private int id;
    private File file;
    private int scale;
    private Gtk.Image image = new Gtk.Image();
    private Gtk.Label title = null;
    private Gtk.Frame frame = null;
    private bool selected = false;
    
    construct {
    }

    public Thumbnail(int id, File file, int scale = DEFAULT_SCALE) {
        this.id = id;
        this.file = file;
        this.scale = scale;
        
        // bottom-align everything
        set(0, 1, 0, 0);
        
        Gdk.Pixbuf cached = ThumbnailCache.big.fetch(id);
        image.set_from_pixbuf(scale_pixbuf(file, cached, scale, DEFAULT_INTERP));
        
        title = new Gtk.Label(file.get_basename());
        title.set_use_underline(false);
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(TEXT_COLOR));
        
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.set_border_width(FRAME_PADDING);
        vbox.pack_start(image, false, false, 0);
        vbox.pack_end(title, false, false, LABEL_PADDING);
        
        frame = new Gtk.Frame(null);
        frame.set_shadow_type(Gtk.ShadowType.ETCHED_OUT);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        frame.add(vbox);

        add(frame);
    }
    
    public static int get_max_width(int scale) {
        // TODO: Be more precise about this ... the magic 32 at the end is merely a dart on the board
        // for accounting for extra pixels used by the frame
        return scale + (FRAME_PADDING * 2) + 32;
    }

    public File get_file() {
        return file;
    }
    
    public Gtk.Allocation get_exposure() {
        return image.allocation;
    }

    public void select() {
        selected = true;

        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
    }
    
    public void unselect() {
        selected = false;

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
        assert((newScale >= MIN_SCALE) && (newScale <= MAX_SCALE));
        
        if (scale == newScale)
            return;
            
        Gdk.Pixbuf cached = ThumbnailCache.big.fetch(id);

        scale = newScale;
        image.set_from_pixbuf(scale_pixbuf(file, cached, scale, DEFAULT_INTERP));
    }
    
    public void exposed() {
        message("Exposed %s", file.get_path());
    }
    
    public void unexposed() {
        message("Unexposed %s", file.get_path());
    }
}

