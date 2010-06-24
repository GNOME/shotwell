/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class TrashPage : CheckerboardPage {
    private class TrashView : Thumbnail {
        public TrashView(LibraryPhoto photo) {
            base (photo);
            
            assert(photo.is_trashed());
        }
    }
    
    public TrashPage() {
        base (_("Trash"));
        
        init_ui("trash.ui", "/TrashMenuBar", "TrashActionGroup", create_actions());
        init_item_context_menu("/TrashContextMenu");
        init_page_context_menu("/TrashPageMenu");
        
        Gtk.Toolbar toolbar = get_toolbar();
        
        // delete button
        Gtk.ToolButton delete_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_DELETE);
        delete_button.set_related_action(action_group.get_action("Delete"));
        
        toolbar.insert(delete_button, -1);
        
        // restore button
        Gtk.ToolButton restore_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_UNDELETE);
        restore_button.set_related_action(action_group.get_action("Restore"));
        
        toolbar.insert(restore_button, -1);
        
        // empty trash button
        Gtk.ToolButton empty_trash_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_CLEAR);
        empty_trash_button.set_related_action(common_action_group.get_action("CommonEmptyTrash"));
        
        toolbar.insert(empty_trash_button, -1);
        
        get_view().selection_group_altered.connect(on_selection_altered);
        get_view().contents_altered.connect(on_contents_altered);
        
        // monitor trashcan and initialize view with all items in it
        LibraryPhoto.global.trashcan_contents_altered.connect(on_trashcan_contents_altered);
        on_trashcan_contents_altered(LibraryPhoto.global.get_trashcan(), null);
    }
    
    private static Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        file.label = _("_File");
        actions += file;
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, TRANSLATABLE, on_edit_menu };
        edit.label = _("_Edit");
        actions += edit;
        
        Gtk.ActionEntry delete_action = { "Delete", Gtk.STOCK_DELETE, TRANSLATABLE, "Delete",
            TRANSLATABLE, on_delete };
        delete_action.label = Resources.DELETE_PHOTOS_MENU;
        delete_action.tooltip = Resources.DELETE_PHOTOS_TOOLTIP;
        actions += delete_action;
        
        Gtk.ActionEntry restore = { "Restore", Gtk.STOCK_UNDELETE, TRANSLATABLE, null, TRANSLATABLE,
            on_restore };
        restore.label = Resources.RESTORE_PHOTOS_MENU;
        restore.tooltip = Resources.RESTORE_PHOTOS_TOOLTIP;
        actions += restore;
        
        Gtk.ActionEntry select_all = { "SelectAll", Gtk.STOCK_SELECT_ALL, TRANSLATABLE, "<Ctrl>A",
            TRANSLATABLE, on_select_all };
        select_all.label = _("Select _All");
        actions += select_all;
        
        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        view.label = _("_View");
        actions += view;
        
        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        help.label = _("_Help");
        actions += help;
        
        return actions;
    }
    
    protected override void init_actions(int selected_count, int count) {
        set_action_sensitive("Delete", selected_count > 0);
        set_action_sensitive("Restore", selected_count > 0);
        set_action_sensitive("SelectAll", count > 0);
        
        action_group.get_action("Delete").is_important = true;
        action_group.get_action("Restore").is_important = true;
        common_action_group.get_action("CommonEmptyTrash").is_important = true;
        
        base.init_actions(selected_count, count);
    }
    
    private void on_selection_altered() {
        set_action_sensitive("Delete", get_view().get_selected_count() > 0);
        set_action_sensitive("Restore", get_view().get_selected_count() > 0);
    }
    
    private void on_contents_altered() {
        set_action_sensitive("SelectAll", get_view().get_count() > 0);
    }
    
    private void on_trashcan_contents_altered(Gee.Collection<LibraryPhoto>? added,
        Gee.Collection<LibraryPhoto>? removed) {
        if (added != null) {
            foreach (LibraryPhoto photo in added)
                get_view().add(new TrashView(photo));
        }
        
        if (removed != null) {
            Marker marker = get_view().start_marking();
            foreach (LibraryPhoto photo in removed)
                marker.mark(get_view().get_view_for_source(photo));
            get_view().remove_marked(marker);
        }
    }
    
    private void on_edit_menu() {
        decorate_undo_item("/TrashMenuBar/EditMenu/Undo");
        decorate_redo_item("/TrashMenuBar/EditMenu/Redo");
    }
    
    private void on_restore() {
        if (get_view().get_selected_count() == 0)
            return;
        
        get_command_manager().execute(new TrashUntrashPhotosCommand(
            (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources(), false));
    }
    
    private void on_select_all() {
        get_view().select_all();
    }
    
    public override CheckerboardItem? get_fullscreen_photo() {
        return null;
    }
    
    private void on_delete() {
        remove_from_app((Gee.Collection<LibraryPhoto>) get_view().get_selected_sources(), _("Delete"), 
            ngettext("Deleting a Photo", "Deleting Photos", get_view().get_selected_count()));
    }
}

