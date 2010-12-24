/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class TrashPage : CheckerboardPage {
    public class Stub : PageStub {
        public Stub() {
        }
        
        protected override Page construct_page() {
            return new TrashPage(get_name());
        }
        
        public override string get_name() {
            return _("Trash");
        }
        
        public override GLib.Icon? get_icon() {
            if (LibraryPhoto.global.get_trashcan_count() > 0)
                return new GLib.ThemedIcon(Resources.ICON_TRASH_FULL);
            
            if (Video.global.get_trashcan_count() > 0)
                return new GLib.ThemedIcon(Resources.ICON_TRASH_FULL);
                
            return new GLib.ThemedIcon(Resources.ICON_TRASH_EMPTY);
        }
    }
    
    private class TrashView : Thumbnail {
        public TrashView(MediaSource source) {
            base (source);
            
            assert(source.is_trashed());
        }
    }
    
    private TrashPage(string name) {
        base (name);
        
        init_item_context_menu("/TrashContextMenu");
        init_page_context_menu("/TrashPageMenu");

        // Adds one menu entry per alien database driver
        AlienDatabaseHandler.get_instance().add_menu_entries(
            ui, "/TrashMenuBar/FileMenu/ImportFromAlienDbPlaceholder"
        );
        
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
        
        // monitor trashcans and initialize view with all items in them
        LibraryPhoto.global.trashcan_contents_altered.connect(on_trashcan_contents_altered);
        Video.global.trashcan_contents_altered.connect(on_trashcan_contents_altered);
        on_trashcan_contents_altered(LibraryPhoto.global.get_trashcan_contents(), null);
        on_trashcan_contents_altered(Video.global.get_trashcan_contents(), null);
    }
    
    protected override string? get_menubar_path() {
        return "/TrashMenuBar";
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("trash.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        file.label = _("_File");
        actions += file;
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        edit.label = _("_Edit");
        actions += edit;
        
        Gtk.ActionEntry delete_action = { "Delete", Gtk.STOCK_DELETE, TRANSLATABLE, "Delete",
            TRANSLATABLE, on_delete };
        delete_action.label = Resources.DELETE_PHOTOS_MENU;
        delete_action.tooltip = Resources.DELETE_FROM_TRASH_TOOLTIP;
        actions += delete_action;
        
        Gtk.ActionEntry restore = { "Restore", Gtk.STOCK_UNDELETE, TRANSLATABLE, null, TRANSLATABLE,
            on_restore };
        restore.label = Resources.RESTORE_PHOTOS_MENU;
        restore.tooltip = Resources.RESTORE_PHOTOS_TOOLTIP;
        actions += restore;
        
        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        view.label = _("_View");
        actions += view;
        
        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, TRANSLATABLE, null };
        help.label = _("_Help");
        actions += help;
        
        return actions;
    }
    
    public static Stub create_stub() {
        return new Stub();
    }
    
    protected override void update_actions(int selected_count, int count) {
        bool has_selected = selected_count > 0;
        
        set_action_sensitive("Delete", has_selected);
        set_action_important("Delete", true);
        set_action_sensitive("Restore", has_selected);
        set_action_important("Restore", true);
        set_common_action_important("CommonEmptyTrash", true);
        
        base.update_actions(selected_count, count);
    }
    
    private void on_trashcan_contents_altered(Gee.Collection<MediaSource>? added,
        Gee.Collection<MediaSource>? removed) {
        if (added != null) {
            foreach (MediaSource source in added)
                get_view().add(new TrashView(source));
        }
        
        if (removed != null) {
            Marker marker = get_view().start_marking();
            foreach (MediaSource source in removed)
                marker.mark(get_view().get_view_for_source(source));
            get_view().remove_marked(marker);
        }
    }
    
    private void on_restore() {
        if (get_view().get_selected_count() == 0)
            return;
        
        get_command_manager().execute(new TrashUntrashPhotosCommand(
            (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources(), false));
    }
    
    public override GLib.Icon? get_icon() {
        return new GLib.ThemedIcon(get_view().get_count() == 0 ? 
            Resources.ICON_TRASH_EMPTY : Resources.ICON_TRASH_FULL);
    }

    public override CheckerboardItem? get_fullscreen_photo() {
        return null;
    }
    
    private void on_delete() {
        remove_from_app((Gee.Collection<MediaSource>) get_view().get_selected_sources(), _("Delete"), 
            ngettext("Deleting a Photo", "Deleting Photos", get_view().get_selected_count()));
    }
}

