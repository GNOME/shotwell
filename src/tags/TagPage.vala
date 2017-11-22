/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class TagPage : CollectionPage {
    private Tag tag;
    
    public TagPage(Tag tag) {
        base (tag.get_name());
        
        this.tag = tag;
        
        Tag.global.items_altered.connect(on_tags_altered);
        tag.mirror_sources(get_view(), create_thumbnail);
        
        init_page_context_menu("TagsContextMenu");
    }
    
    ~TagPage() {
        get_view().halt_mirroring();
        Tag.global.items_altered.disconnect(on_tags_altered);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        ui_filenames.add("tags.ui");
    }
    
    public Tag get_tag() {
        return tag;
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.Facade.get_instance().get_event_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.Facade.get_instance().set_event_photos_sort(sort_order, sort_by);
    }

    private const GLib.ActionEntry entries[] = {
        { "DeleteTag", on_delete_tag },
        { "RenameTag", on_rename_tag },
        { "RemoveTagFromPhotos", on_remove_tag_from_photos },
        { "NewChildTagSidebar", on_new_child_tag_sidebar }
    };

    protected override void add_actions(GLib.ActionMap map) {
        base.add_actions(map);

        map.add_action_entries(entries, this);
    }

    protected override void remove_actions(GLib.ActionMap map) {
        base.remove_actions(map);
        foreach (var entry in entries) {
            map.remove_action(entry.name);
        }
    }

    private void on_tags_altered(Gee.Map<DataObject, Alteration> map) {
        if (map.has_key(tag)) {
            set_page_name(tag.get_name());
            update_actions(get_view().get_selected_count(), get_view().get_count());
        }
    }

    public override void switched_to () {
        base.switched_to ();
        this.update_menu_item_label ("DeleteTag",
            Resources.delete_tag_menu(tag.get_user_visible_name()));
        this.update_menu_item_label ("RenameTag",
            Resources.rename_tag_menu(tag.get_user_visible_name()));
        this.update_menu_item_label ("RemoveTagFromPhotos",
            Resources.untag_photos_menu(tag.get_user_visible_name(), 0));
     }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_details("DeleteTag",
            Resources.delete_tag_menu(tag.get_user_visible_name()),
            null,
            true);
        
        set_action_details("RenameTag",
            Resources.rename_tag_menu(tag.get_user_visible_name()),
            null,
            true);
        
        set_action_details("RemoveTagFromPhotos", 
            Resources.untag_photos_menu(tag.get_user_visible_name(), selected_count),
            null,
            selected_count > 0);
        
        base.update_actions(selected_count, count);
    }
    
    private void on_new_child_tag_sidebar() {
        NewChildTagCommand creation_command = new NewChildTagCommand(tag);
        
        AppWindow.get_command_manager().execute(creation_command);
        
        LibraryWindow.get_app().rename_tag_in_sidebar(creation_command.get_created_child());
    }
    
    private void on_rename_tag() {
        LibraryWindow.get_app().rename_tag_in_sidebar(tag);
    }
    
    private void on_delete_tag() {
        if (Dialogs.confirm_delete_tag(tag))
            AppWindow.get_command_manager().execute(new DeleteTagCommand(tag));
    }
    
    private void on_remove_tag_from_photos() {
        if (get_view().get_selected_count() > 0) {
            get_command_manager().execute(new TagUntagPhotosCommand(tag, 
                (Gee.Collection<MediaSource>) get_view().get_selected_sources(), 
                get_view().get_selected_count(), false));
        }
    }
}

