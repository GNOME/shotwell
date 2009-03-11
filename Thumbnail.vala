
public class Thumbnail : Gtk.VBox {
    public static const int THUMB_WIDTH = 128;
    public static const int THUMB_HEIGHT = 128;
    
    private File file;
    private Gtk.Image image;
    private Gtk.Label label;
    
    construct {
    }

    public Thumbnail(File file) {
        this.file = file;
        
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
            
            return;
        }
        
        pixbuf = scale(pixbuf, THUMB_WIDTH, THUMB_HEIGHT);

        label = new Gtk.Label(file.get_basename());
        label.set_use_underline(false);
        
        image = new Gtk.Image.from_pixbuf(pixbuf);

        pack_start(image, true, true, 0);
        pack_end(label, false, false, 4);
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
}

