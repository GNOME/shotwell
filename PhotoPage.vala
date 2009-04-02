
public class PhotoPage : Gtk.ScrolledWindow {
    private PhotoTable photoTable = new PhotoTable();
    private Gtk.ActionGroup actionGroup = new Gtk.ActionGroup("PhotoActionGroup");
    private Gtk.MenuBar menubar = null;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private PhotoID currentPhotoID;
    private Gtk.Image image = new Gtk.Image();
    private Gtk.Label title = new Gtk.Label(null);

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "File", null, "_File", null, null, null },
        { "Quit", Gtk.STOCK_QUIT, "_Quit", null, "Quit the program", Gtk.main_quit },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, "_About", null, "About this application", null }
    };
    
    construct {
        // set up action group
        actionGroup.add_actions(ACTIONS, this);

        // set up menu bar
        menubar = (Gtk.MenuBar) AppWindow.get_ui_manager().get_widget("/CollectionMenuBar");

        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        title.set_use_underline(false);
        title.set_justify(Gtk.Justification.LEFT);
        title.set_alignment(0, 0);

        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(image, false, false, 0);
        vbox.pack_end(title, false, false, 0);
        
        add_with_viewport(vbox);
    }
    
    public Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public Gtk.MenuBar get_menubar() {
        return menubar;
    }
    
    public Gtk.ActionGroup get_action_group() {
        return actionGroup;
    }
    
    public void display_photo(PhotoID photoID) {
        currentPhotoID = photoID;
        File file = photoTable.get_file(photoID);
        if (file == null)
            return;
        
        debug("Loading %s", file.get_path());

        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            // TODO: Better error handling
            error("%s", err.message);
        }
        
        image.set_from_pixbuf(pixbuf);
        title.set_text(file.get_basename());
    }
}
