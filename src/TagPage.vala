/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class TagPage : CollectionPage {
    private Tag tag;
    
    public TagPage(Tag tag) {
        base (tag.get_name(), "tags.ui", create_actions());
        
        this.tag = tag;
        
        tag.altered += on_tag_altered;
        tag.mirror_photos(get_view(), create_thumbnail);
        
        init_page_context_menu("/TagsContextMenu");
        
        ui.add_ui(ui.new_merge_id(), "/CollectionMenuBar/PhotosMenu/RemoveTagPlaceholder",
            "RemoveTag", "RemoveTag", Gtk.UIManagerItemType.AUTO, false);
        ui.add_ui(ui.new_merge_id(), "/CollectionContextMenu/ContextRemoveTagPlaceholder",
            "ContextRemoveTag", "RemoveTag", Gtk.UIManagerItemType.AUTO, false);
    }
    
    ~TagPage() {
        get_view().halt_mirroring();
    }
    
    public Tag get_tag() {
        return tag;
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
    
    private static Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry delete_tag = { "DeleteTag", null, TRANSLATABLE, null, null, on_delete_tag };
        delete_tag.label = Resources.DELETE_TAG_MENU;
        delete_tag.tooltip = Resources.DELETE_TAG_TOOLTIP;
        actions += delete_tag;
        
        Gtk.ActionEntry rename_tag = { "RenameTag", null, TRANSLATABLE, null, null, on_rename_tag };
        rename_tag.label = Resources.RENAME_TAG_MENU;
        rename_tag.tooltip = Resources.RENAME_TAG_TOOLTIP;
        actions += rename_tag;
        
        Gtk.ActionEntry remove_tag = { "RemoveTag", null, TRANSLATABLE, null, null, on_remove_tag };
        remove_tag.label = Resources.UNTAG_PHOTOS_MENU;
        remove_tag.tooltip = Resources.UNTAG_PHOTOS_TOOLTIP;
        actions += remove_tag;
        
        return actions;
    }
    
    private void on_tag_altered() {
        set_page_name(tag.get_name());
    }
    
    protected override void on_photos_menu() {
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RemoveTagPlaceholder/RemoveTag", 
            get_view().get_selected_count() > 0);
        
        base.on_photos_menu();
    }
    
    protected override bool on_context_invoked() {
        set_item_sensitive("/CollectionContextMenu/ContextRemoveTagPlaceholder/ContextRemoveTag",
            get_view().get_selected_count() > 0);
        
        return base.on_context_invoked();
    }
    
    private void on_rename_tag() {
        RenameTagDialog dialog = new RenameTagDialog(tag.get_name());
        string? new_name = dialog.execute();
        if (new_name != null)
            get_command_manager().execute(new RenameTagCommand(tag, new_name));
    }
    
    private void on_delete_tag() {
        get_command_manager().execute(new DeleteTagCommand(tag));
    }
    
    private void on_remove_tag() {
        if (get_view().get_selected_count() > 0) {
            get_command_manager().execute(new TagUntagPhotosCommand(tag, 
                (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources(), false));
        }
    }
}

