
public class Thumbnail : Gtk.Alignment {
    public static const int THUMB_WIDTH = 128;
    public static const int THUMB_HEIGHT = 128;
    public static const int LABEL_PADDING = 4;
    public static const string TEXT_COLOR = "#FFF";
    
    private File file;
    private Gtk.Image image;
    private Gtk.Label title;
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
        vbox.pack_start(image, false, false, 0);
        vbox.pack_end(title, false, false, LABEL_PADDING);

        add(vbox);
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
        
        message("%s %dx%d -> %lf -> %dx%d", file.get_path(), width, height, ratio, newWidth, newHeight);
        
        return pixbuf.scale_simple(newWidth, newHeight, Gdk.InterpType.NEAREST);
    }
    
    public File get_file() {
        return file;
    }
    
    public void select() {
        selected = true;
    }
    
    public void unselect() {
        selected = false;
    }
    
    public bool toggle_select() {
        selected = !selected;
        
        return selected;
    }
    
    public bool is_selected() {
        return selected;
    }
}

