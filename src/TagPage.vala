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
        
        tag.altered.connect(on_tag_altered);
        tag.mirror_photos(get_view(), create_thumbnail);
        
        init_page_context_menu("/TagsContextMenu");
        
        ui.add_ui(ui.new_merge_id(), "/CollectionContextMenu/ContextTagsPlaceholder",
            "ContextRemoveTagFromPhotos", "RemoveTagFromPhotos", Gtk.UIManagerItemType.AUTO, false);
    }
    
    ~TagPage() {
        get_view().halt_mirroring();
        tag.altered.disconnect(on_tag_altered);
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
        // label and tooltip are assigned when the menu is displayed
        actions += delete_tag;
        
        Gtk.ActionEntry rename_tag = { "RenameTag", null, TRANSLATABLE, null, null, on_rename_tag };
        // label and tooltip are assigned when the menu is displayed
        actions += rename_tag;
        
        Gtk.ActionEntry remove_tag = { "RemoveTagFromPhotos", null, TRANSLATABLE, null, null, 
            on_remove_tag_from_photos };
        // label and tooltip are assigned when the menu is displayed
        actions += remove_tag;
        
        return actions;
    }
    
    private void on_tag_altered() {
        set_page_name(tag.get_name());
    }
    
    protected override void on_tags_menu() {
        int selected_count = get_view().get_selected_count();
        
        set_item_display("/CollectionMenuBar/TagsMenu/DeleteTag",
            Resources.delete_tag_menu(tag.get_name()),
            Resources.delete_tag_tooltip(tag.get_name(), tag.get_photos_count()),
            true);
        
        set_item_display("/CollectionMenuBar/TagsMenu/RenameTag",
            Resources.rename_tag_menu(tag.get_name()),
            Resources.rename_tag_tooltip(tag.get_name()),
            true);
        
        set_item_display("/CollectionMenuBar/TagsMenu/RemoveTagFromPhotos", 
            Resources.untag_photos_menu(tag.get_name(), selected_count),
            Resources.untag_photos_tooltip(tag.get_name(), selected_count),
            selected_count > 0);
        
        base.on_tags_menu();
    }
    
    protected override bool on_context_invoked() {
        int selected_count = get_view().get_selected_count();
        
        set_item_display("/CollectionContextMenu/ContextTagsPlaceholder/ContextRemoveTagFromPhotos",
            Resources.untag_photos_menu(tag.get_name(), selected_count),
            Resources.untag_photos_tooltip(tag.get_name(), selected_count),
            selected_count > 0);
        
        return base.on_context_invoked();
    }
    
    public override Gtk.Menu? get_page_context_menu() {
        set_item_display("/TagsContextMenu/ContextRenameTag",
            Resources.rename_tag_menu(tag.get_name()),
            Resources.rename_tag_tooltip(tag.get_name()),
            true);
        
        set_item_display("/TagsContextMenu/ContextDeleteTag",
            Resources.delete_tag_menu(tag.get_name()),
            Resources.delete_tag_tooltip(tag.get_name(), tag.get_photos_count()),
            true);
        
        return base.get_page_context_menu();
    }
    
    private void on_rename_tag() {
        for (;;) {
            RenameTagDialog dialog = new RenameTagDialog(tag.get_name());
            string? new_name = dialog.execute();
            if (new_name == null)
                return;
        
            if (!Tag.global.exists(new_name)) {
                get_command_manager().execute(new RenameTagCommand(tag, new_name));
                
                return;
            }
            
            AppWindow.error_message(Resources.rename_tag_exists_message(new_name));
        }
        
        
    }
    
    private void on_delete_tag() {
        int count = tag.get_photos_count();
        string msg = ngettext(
            "This will remove the tag \"%s\" from one photo.  Continue?",
            "This will remove the tag \"%s\" from %d photos.  Continue?",
            count).printf(tag.get_name(), count);
        
        if (!AppWindow.negate_affirm_question(msg, _("_Cancel"), _("_Delete"),
            Resources.DELETE_TAG_TITLE))
            return;
        
        get_command_manager().execute(new DeleteTagCommand(tag));
    }
    
    private void on_remove_tag_from_photos() {
        if (get_view().get_selected_count() > 0) {
            get_command_manager().execute(new TagUntagPhotosCommand(tag, 
                (Gee.Collection<LibraryPhoto>) get_view().get_selected_sources(), 
                get_view().get_selected_count(), false));
        }
    }
}

