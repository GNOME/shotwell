/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class DirectWindow : AppWindow {
    private DirectPhotoPage direct_photo_page;
    
    public DirectWindow(File file) {
        base();

        direct_photo_page = new DirectPhotoPage(file);
        direct_photo_page.get_view().items_altered.connect(on_photo_changed);
        direct_photo_page.get_view().items_state_changed.connect(on_photo_changed);
        
        set_current_page(direct_photo_page);
        
        update_title(file, false);
        
        direct_photo_page.switched_to();
        
        // simple layout: menu on top, photo in center, toolbar along bottom (mimicking the
        // PhotoPage in the library, but without the sidebar)
        Gtk.Box layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        layout.prepend(direct_photo_page);
        layout.append(direct_photo_page.get_toolbar());
        
        set_menubar(direct_photo_page.get_menubar ());

        set_child(layout);

        var key = new Gtk.EventControllerKey();
        key.key_pressed.connect(key_press_event);
        ((Gtk.Widget)this).add_controller(key);
    }
    
    public static DirectWindow get_app() {
        return (DirectWindow) instance;
    }
    
    public DirectPhotoPage get_direct_page() {
        return (DirectPhotoPage) get_current_page();
    }
    
    public void update_title(File file, bool modified) {
        title = "%s%s (%s) - %s".printf((modified) ? "•" : "", file.get_basename(),
            get_display_pathname(file.get_parent()), Resources.APP_TITLE);
    }
    
    // Expose on_fullscreen publicly so we can call it from the DirectPhotoPage
    public void do_fullscreen() {
        on_fullscreen();
    }

    protected override void on_fullscreen() {
        File file = get_direct_page().get_current_file();
        
        go_fullscreen(new DirectFullscreenPhotoPage(file));
    }
    
    public override string get_app_role() {
        return Resources.APP_DIRECT_ROLE;
    }
    
    private void on_photo_changed() {
        Photo? photo = direct_photo_page.get_photo();
        if (photo != null)
            update_title(photo.get_file(), photo.has_alterations());
    }
    
    protected override void on_quit() {
        Config.Facade.get_instance().set_direct_window_state(maximized, dimensions);
        
        base.on_quit();
    }
    
    private bool close_check_pending = false;
    public override bool close_request() {
        if (!close_check_pending) {
            close_check_pending = true;
            get_direct_page().check_quit.begin((obj, res) =>{
                close_check_pending = false;
                var result = get_direct_page().check_quit.end(res);
                if (result) {
                    destroy();
                }
            });
        }

        return true;
    }

    public override bool key_press_event(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        // check for an escape
        if (Gdk.keyval_name(keyval) == "Escape") {
            on_quit();
            
            return true;
        }

        return base.key_press_event(event, keyval, keycode, modifiers);
    }
}

