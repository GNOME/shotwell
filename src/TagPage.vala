/* Copyright 2010-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class TagPage : CollectionPage {
    public class Stub : PageStub {
        public Tag tag;
        
        public Stub(Tag tag) {
            this.tag = tag;
        }
        
        public override GLib.Icon? get_icon() {
            return new GLib.ThemedIcon(Resources.ICON_ONE_TAG);
        }

        public override string get_name() {
            return tag.get_name();
        }
        
        public override bool is_renameable() {
            return (tag != null);
        }
        
        public override bool is_destroyable() {
            return (tag != null);
        }

        protected override Page construct_page() {
            return new TagPage(tag);
        }
        
        public static int64 comparator(void *a, void *b) {
            return Tag.compare_names(((Stub *) a)->tag, ((Stub *) b)->tag);
        }
    }
    
    private Tag tag;
    
    private TagPage(Tag tag) {
        base (tag.get_name());
        
        this.tag = tag;
        
        Tag.global.items_altered.connect(on_tags_altered);
        tag.mirror_sources(get_view(), create_thumbnail);
        
        init_page_context_menu("/TagsContextMenu");
    }
    
    ~TagPage() {
        get_view().halt_mirroring();
        Tag.global.items_altered.disconnect(on_tags_altered);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        ui_filenames.add("tags.ui");
    }
    
    public static TagPage.Stub create_stub(Tag tag) {
        return new Stub(tag);
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
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
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
    
    private void on_tags_altered(Gee.Map<DataObject, Alteration> map) {
        if (map.has_key(tag))
            set_page_name(tag.get_name());
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_details("DeleteTag",
            Resources.delete_tag_menu(tag.get_name()),
            Resources.delete_tag_tooltip(tag.get_name(), tag.get_sources_count()),
            true);
        
        set_action_details("RenameTag",
            Resources.rename_tag_menu(tag.get_name()),
            Resources.rename_tag_tooltip(tag.get_name()),
            true);
        
        set_action_details("RemoveTagFromPhotos", 
            Resources.untag_photos_menu(tag.get_name(), selected_count),
            Resources.untag_photos_tooltip(tag.get_name(), selected_count),
            selected_count > 0);
        
        base.update_actions(selected_count, count);
    }
    
    public override void rename(string new_name) {
        if (is_string_empty(new_name))
            return;
        
        if (!Tag.global.exists(new_name))
            get_command_manager().execute(new RenameTagCommand(tag, new_name));
        else if (new_name != tag.get_name())
            AppWindow.error_message(Resources.rename_tag_exists_message(new_name));
    }
    
    public override void destroy_source() {
        on_delete_tag();
    }

    private void on_rename_tag() {
        LibraryWindow.get_app().sidebar_rename_in_place(this);
    }
    
    private void on_delete_tag() {
        int count = tag.get_sources_count();
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

