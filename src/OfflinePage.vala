/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class OfflinePage : CheckerboardPage {
    private class OfflineView : Thumbnail {
        public OfflineView(LibraryPhoto photo) {
            base (photo);
            
            assert(photo.is_offline());
        }
    }
    
    public OfflinePage() {
        base (_("Missing Files"));
        
        init_ui("offline.ui", "/OfflineMenuBar", "OfflineActionGroup", create_actions());
        
        // monitor offline and initialize view with all items in it
        LibraryPhoto.global.offline_contents_altered.connect(on_offline_contents_altered);
        on_offline_contents_altered(LibraryPhoto.global.get_offline(), null);
    }
    
    private static Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        file.label = _("_File");
        actions += file;
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, TRANSLATABLE, on_edit_menu };
        edit.label = _("_Edit");
        actions += edit;
        
        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        view.label = _("_View");
        actions += view;
        
        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        help.label = _("_Help");
        actions += help;
        
        return actions;
    }
    
    private void on_offline_contents_altered(Gee.Collection<LibraryPhoto>? added,
        Gee.Collection<LibraryPhoto>? removed) {
        if (added != null) {
            foreach (LibraryPhoto photo in added)
                get_view().add(new OfflineView(photo));
        }
        
        if (removed != null) {
            Marker marker = get_view().start_marking();
            foreach (LibraryPhoto photo in removed)
                marker.mark(get_view().get_view_for_source(photo));
            get_view().remove_marked(marker);
        }
    }
    
    private void on_edit_menu() {
        decorate_undo_item("/OfflineMenuBar/EditMenu/Undo");
        decorate_redo_item("/OfflineMenuBar/EditMenu/Redo");
    }
    
    public override CheckerboardItem? get_fullscreen_photo() {
        return null;
    }
}

