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
        
        get_view().selection_group_altered.connect(on_selection_group_altered);
        
        Gtk.Toolbar toolbar = get_toolbar();
        
        // delete button
        Gtk.ToolButton delete_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_DELETE);
        delete_button.set_related_action(action_group.get_action("RemoveFromLibrary"));
        
        toolbar.insert(delete_button, -1);
        
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
        
        Gtk.ActionEntry remove = { "RemoveFromLibrary", Gtk.STOCK_DELETE, TRANSLATABLE, "Delete",
            TRANSLATABLE, on_remove_from_library };
        remove.label = Resources.DELETE_PHOTOS_MENU;
        remove.tooltip = Resources.DELETE_FROM_LIBRARY_TOOLTIP;
        actions += remove;
        
        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        view.label = _("_View");
        actions += view;
        
        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        help.label = _("_Help");
        actions += help;
        
        return actions;
    }
    
    protected override void init_actions(int selected_count, int count) {
        update_actions(selected_count, count);
        
        action_group.get_action("RemoveFromLibrary").is_important = true;
        
        base.init_actions(selected_count, count);
    }
    
    private void on_selection_group_altered() {
        update_actions(get_view().get_selected_count(), get_view().get_count());
    }
    
    private void update_actions(int selected_count, int count) {
        set_action_sensitive("RemoveFromLibrary", selected_count > 0);
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
    
    private void on_remove_from_library() {
        Gee.Collection<LibraryPhoto> photos =
            (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources();
        if (photos.size == 0)
            return;
        
        if (!remove_offline_dialog(AppWindow.get_instance(), photos.size))
            return;
        
        AppWindow.get_instance().set_busy_cursor();
        
        ProgressDialog progress = null;
        if (photos.size >= 20)
            progress = new ProgressDialog(AppWindow.get_instance(), _("Deleting..."));
        
        // valac complains about passing an argument for a delegate using ternary operator:
        // https://bugzilla.gnome.org/show_bug.cgi?id=599349
        if (progress != null)
            LibraryPhoto.global.remove_from_app(photos, false, progress.monitor);
        else
            LibraryPhoto.global.remove_from_app(photos, false);
        
        if (progress != null)
            progress.close();
        
        AppWindow.get_instance().set_normal_cursor();
    }
    
    public override string? get_icon_name() {
        return Resources.ICON_MISSING_FILES;
    }

    public override CheckerboardItem? get_fullscreen_photo() {
        return null;
    }
}

