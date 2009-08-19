/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class DirectWindow : AppWindow {
    public DirectWindow(File file) {
        DirectPhotoPage direct_photo_page = new DirectPhotoPage(file);
        direct_photo_page.set_container(this);
        direct_photo_page.contents_changed += on_photo_changed;
        direct_photo_page.queryable_altered += on_photo_changed;
        
        current_page = direct_photo_page;
        
        update_title(file, false);

        // add accelerators
        Gtk.AccelGroup accel_group = current_page.ui.get_accel_group();
        if (accel_group != null)
            add_accel_group(accel_group);
        
        // simple layout: menu on top, photo in center, toolbar along bottom (mimicking the
        // PhotoPage in the library, but without the sidebar)
        Gtk.VBox layout = new Gtk.VBox(false, 0);
        layout.pack_start(current_page.get_menubar(), false, false, 0);
        layout.pack_start(current_page, true, true, 0);
        layout.pack_end(current_page.get_toolbar(), false, false, 0);
        
        add(layout);
        
        current_page.switched_to();
    }
    
    public DirectPhotoPage get_direct_page() {
        return (DirectPhotoPage) current_page;
    }
    
    public void update_title(File file, bool modified) {
        title = "%s%s (%s) - %s".printf((modified) ? "*" : "", file.get_basename(),
            get_display_pathname(file.get_parent()), Resources.APP_TITLE);
    }
    
    public override void on_fullscreen() {
        File file = get_direct_page().get_current_file();
        
        DirectPhotoPage fs_photo = new DirectPhotoPage(file);
        FullscreenWindow fs_window = new FullscreenWindow(fs_photo);
        fs_photo.set_container(fs_window);

        go_fullscreen(fs_window);
    }
    
    public override string get_app_role() {
        return Resources.APP_DIRECT_ROLE;
    }
    
    private void on_photo_changed() {
        TransformablePhoto photo = get_direct_page().get_photo();
        update_title(photo.get_file(), photo.has_transformations());
    }
    
    private override void on_quit() {
        if (!get_direct_page().check_quit())
            return;
        
        base.on_quit();
    }
    
    private override bool delete_event(Gdk.Event event) {
        if (!get_direct_page().check_quit())
            return true;
        
        return (base.delete_event != null) ? base.delete_event(event) : false;
    }
}

