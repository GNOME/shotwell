/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class DirectWindow : AppWindow {
    private DirectPhotoPage direct_photo_page;
    
    public DirectWindow(File file) {
        direct_photo_page = new DirectPhotoPage(file);
        direct_photo_page.get_view().items_altered.connect(on_photo_changed);
        direct_photo_page.get_view().items_state_changed.connect(on_photo_changed);
        
        set_current_page(direct_photo_page);
        
        update_title(file, false);
        
        direct_photo_page.switched_to();
        
        // simple layout: menu on top, photo in center, toolbar along bottom (mimicking the
        // PhotoPage in the library, but without the sidebar)
        Gtk.Box layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        layout.pack_start(direct_photo_page.get_menubar(), false, false, 0);
        layout.pack_start(direct_photo_page, true, true, 0);
        layout.pack_end(direct_photo_page.get_toolbar(), false, false, 0);
        
        add(layout);
    }
    
    public static DirectWindow get_app() {
        return (DirectWindow) instance;
    }
    
    public DirectPhotoPage get_direct_page() {
        return (DirectPhotoPage) get_current_page();
    }
    
    public void update_title(File file, bool modified) {
        title = "%s%s (%s) - %s".printf((modified) ? "*" : "", file.get_basename(),
            get_display_pathname(file.get_parent()), Resources.APP_TITLE);
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
        if (!get_direct_page().check_quit())
            return;

        Config.Facade.get_instance().set_direct_window_state(maximized, dimensions);
        
        base.on_quit();
    }
    
    public override bool delete_event(Gdk.EventAny event) {
        if (!get_direct_page().check_quit())
            return true;
        
        return (base.delete_event != null) ? base.delete_event(event) : false;
    }

    public override bool button_press_event(Gdk.EventButton event) {
        if (event.type == Gdk.EventType.2BUTTON_PRESS) {
            on_fullscreen();

            return true;
        }
        
        return false;
    }

    public override bool key_press_event(Gdk.EventKey event) {
        // check for an escape
        if (Gdk.keyval_name(event.keyval) == "Escape") {
            on_quit();
            
            return true;
        }
        
       // ...then let the base class take over
       return (base.key_press_event != null) ? base.key_press_event(event) : false;
    }
}

