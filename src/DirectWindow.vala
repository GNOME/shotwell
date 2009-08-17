/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class DirectWindow : AppWindow {
    public DirectWindow(File file) {
        DirectPhotoPage direct_photo_page = new DirectPhotoPage(file);
        direct_photo_page.set_container(this);
        direct_photo_page.photo_replaced += on_photo_replaced;
        
        current_page = direct_photo_page;
        
        update_title(file);

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
    }
    
    public void update_title(File file) {
        title = file.get_basename() + " ~ " + Resources.APP_TITLE;
    }
    
    public override void on_fullscreen() {
        File file = ((DirectPhotoPage) current_page).get_current_file();
        
        DirectPhotoPage fs_photo = new DirectPhotoPage(file);
        FullscreenWindow fs_window = new FullscreenWindow(fs_photo);
        fs_photo.set_container(fs_window);

        go_fullscreen(fs_window);
    }
    
    private void on_photo_replaced(TransformablePhoto old_photo, TransformablePhoto new_photo) {
        update_title(new_photo.get_file());
    }
}

