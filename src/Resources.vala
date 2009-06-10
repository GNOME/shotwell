
// defined by ./configure and included by gcc -D
extern const string PREFIX;

namespace Resources {
    public const string STOCK_CLOCKWISE = "shotwell-rotate-clockwise";
    public const string STOCK_COUNTERCLOCKWISE = "shotwell-rotate-counterclockwise";

    public static const string ROTATE_CLOCKWISE_LABEL = "Rotate";
    public static const string ROTATE_CLOCKWISE_TOOLTIP = "Rotate the photo(s) clockwise";
    
    public static const string ROTATE_COUNTERCLOCKWISE_LABEL = "Rotate";
    public static const string ROTATE_COUNTERCLOCKWISE_TOOLTIP = "Rotate the photo(s) counterclockwise";
    
    private Gtk.IconFactory factory = null;
    
    public void init () {
        factory = new Gtk.IconFactory();
        
        File icons_dir = AppWindow.get_resources_dir().get_child("icons");
        add_stock_icon(icons_dir.get_child("object-rotate-right.svg"), STOCK_CLOCKWISE);
        add_stock_icon(icons_dir.get_child("object-rotate-left.svg"), STOCK_COUNTERCLOCKWISE);
        
        factory.add_default();
    }
    
    public void terminate() {
    }
    
    public File get_ui(string filename) {
        return AppWindow.get_resources_dir().get_child("ui").get_child(filename);
    }
    
    private void add_stock_icon(File file, string stock_id) {
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }
        
        Gtk.IconSet icon_set = new Gtk.IconSet.from_pixbuf(pixbuf);
        factory.add(stock_id, icon_set);
    }
}

