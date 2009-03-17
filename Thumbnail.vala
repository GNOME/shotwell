
public class Thumbnail : Gtk.Alignment {
    public static const int THUMB_WIDTH = 128;
    public static const int THUMB_HEIGHT = 128;
    public static const int LABEL_PADDING = 4;
    public static const string TEXT_COLOR = "#FFF";
    public static const string SELECTED_COLOR = "#FF0";
    public static const string UNSELECTED_COLOR = "#FFF";
    
    // Due to the potential for thousands or tens of thousands of thumbnails being present in a
    // particular view, all widgets used here should be NOWINDOW widgets.
    private File file = null;
    private Gtk.Image image = null;
    private Gtk.Label title = null;
    private Gtk.Frame frame = null;
    private bool selected = false;
    
    construct {
    }

    public Thumbnail(File file) {
        this.file = file;
        
        // bottom-align everything
        set(0, 1, 0, 0);
        
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("Error loading image: %s", err.message);
            
            return;
        }
        
        pixbuf = scale(pixbuf, THUMB_WIDTH, THUMB_HEIGHT);

        image = new Gtk.Image.from_pixbuf(pixbuf);

        title = new Gtk.Label(file.get_basename());
        title.set_use_underline(false);
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(TEXT_COLOR));
        
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.set_border_width(4);
        vbox.pack_start(image, false, false, 0);
        vbox.pack_end(title, false, false, LABEL_PADDING);
        
        frame = new Gtk.Frame(null);
        frame.set_shadow_type(Gtk.ShadowType.ETCHED_OUT);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        frame.add(vbox);

        add(frame);
    }
    
    public Gdk.Pixbuf scale(Gdk.Pixbuf pixbuf, int maxWidth, int maxHeight) {
        int width = pixbuf.get_width();
        int height = pixbuf.get_height();

        int diffWidth = width - maxWidth;
        int diffHeight = height - maxHeight;
        
        double ratio = 0.0;
        if (diffWidth > diffHeight) {
            ratio = (double) maxWidth / (double) width;
        } else {
            ratio = (double) maxHeight / (double) height;
        }

        int newWidth = (int) ((double) width * ratio);
        int newHeight = (int) ((double) height * ratio);
        
        message("%s %d x %d * %lf%% -> %d x %d", file.get_path(), width, height, ratio, newWidth, newHeight);
        
        return pixbuf.scale_simple(newWidth, newHeight, Gdk.InterpType.NEAREST);
    }
    
    public File get_file() {
        return file;
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
}

