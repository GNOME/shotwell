/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Tags.Branch : Sidebar.Branch {
    private Gee.HashMap<Tag, Tags.SidebarEntry> entry_map = new Gee.HashMap<Tag, Tags.SidebarEntry>();
    
    public Branch() {
        base (new Tags.Grouping(),
            Sidebar.Branch.Options.HIDE_IF_EMPTY
                | Sidebar.Branch.Options.AUTO_OPEN_ON_NEW_CHILD
                | Sidebar.Branch.Options.STARTUP_OPEN_GROUPING,
            comparator);
        
        // seed the branch with existing tags
        on_tags_added_removed(Tag.global.get_all(), null);
        
        // monitor collection for future events
        Tag.global.contents_altered.connect(on_tags_added_removed);
        Tag.global.items_altered.connect(on_tags_altered);
    }
    
    ~Branch() {
        Tag.global.contents_altered.disconnect(on_tags_added_removed);
        Tag.global.items_altered.disconnect(on_tags_altered);
    }
    
    public Tags.SidebarEntry? get_entry_for_tag(Tag tag) {
        return entry_map.get(tag);
    }
    
    private static int comparator(Sidebar.Entry a, Sidebar.Entry b) {
        if (a == b)
            return 0;
        
        return Tag.compare_names(((Tags.SidebarEntry) a).for_tag(),
            ((Tags.SidebarEntry) b).for_tag());
    }
    
    private void on_tags_added_removed(Gee.Iterable<DataObject>? added_raw, Gee.Iterable<DataObject>? removed) {
        if (added_raw != null) {
            // prepare a collection of tags guaranteed to be sorted; this is critical for
            // hierarchical tags since it ensures that parent tags must be encountered
            // before their children
            Gee.SortedSet<Tag> added = new Gee.TreeSet<Tag>(Tag.compare_names);
            foreach (DataObject object in added_raw) {
                Tag tag = (Tag) object;
                added.add(tag);
            }
                
            foreach (Tag tag in added) {
                // ensure that all parent tags of this tag (if any) already have sidebar
                // entries
                Tag? parent_tag = tag.get_hierarchical_parent();
                while (parent_tag != null) {
                    if (!entry_map.has_key(parent_tag)) {
                        Tags.SidebarEntry parent_entry = new Tags.SidebarEntry(parent_tag);
                        entry_map.set(parent_tag, parent_entry);
                    }
                    
                    parent_tag = parent_tag.get_hierarchical_parent();
                }
                
                Tags.SidebarEntry entry = new Tags.SidebarEntry(tag);
                entry_map.set(tag, entry);
                
                parent_tag = tag.get_hierarchical_parent();
                if (parent_tag != null) {
                    Tags.SidebarEntry parent_entry = entry_map.get(parent_tag);
                    graft(parent_entry, entry);
                } else {
                    graft(get_root(), entry);
                }
            }
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                Tag tag = (Tag) object;
                
                Tags.SidebarEntry? entry = entry_map.get(tag);
                assert(entry != null);
                
                bool is_removed = entry_map.unset(tag);
                assert(is_removed);
                
                prune(entry);
            }
        }
    }
    
    private void on_tags_altered(Gee.Map<DataObject, Alteration> altered) {
        foreach (DataObject object in altered.keys) {
            if (!altered.get(object).has_detail("metadata", "name"))
                continue;
            
            Tag tag = (Tag) object;
            Tags.SidebarEntry? entry = entry_map.get(tag);
            assert(entry != null);
            
            entry.sidebar_name_changed(tag.get_user_visible_name());
            entry.sidebar_tooltip_changed(tag.get_user_visible_name());
            reorder(entry);
        }
    }
}

public class Tags.Grouping : Sidebar.Grouping, Sidebar.InternalDropTargetEntry {
    public Grouping() {
        base (_("Tags"), new ThemedIcon(Resources.ICON_TAGS));
    }
    
    public bool internal_drop_received(Gee.List<MediaSource> media) {
        AddTagsDialog dialog = new AddTagsDialog();
        string[]? names = dialog.execute();
        if (names == null || names.length == 0)
            return false;
        
        AppWindow.get_command_manager().execute(new AddTagsCommand(names, media));
        
        return true;
    }
}

public class Tags.SidebarEntry : Sidebar.SimplePageEntry, Sidebar.RenameableEntry,
    Sidebar.DestroyableEntry, Sidebar.InternalDropTargetEntry, Sidebar.ExpandableEntry {
    private static Icon single_tag_icon;
    
    private Tag tag;
    
    public SidebarEntry(Tag tag) {
        this.tag = tag;
    }
    
    internal static void init() {
        single_tag_icon = new ThemedIcon(Resources.ICON_ONE_TAG);
    }
    
    internal static void terminate() {
        single_tag_icon = null;
    }
    
    public Tag for_tag() {
        return tag;
    }
    
    public override string get_sidebar_name() {
        return tag.get_user_visible_name();
    }
    
    public override Icon? get_sidebar_icon() {
        return single_tag_icon;
    }
    
    protected override Page create_page() {
        return new TagPage(tag);
    }
    
    public void rename(string new_name) {
        string? prepped = Tag.prep_tag_name(new_name);
        if (prepped == null)
            return;
        
        if (!Tag.global.exists(prepped))
            AppWindow.get_command_manager().execute(new RenameTagCommand(tag, prepped));
        else if (prepped != tag.get_name())
            AppWindow.error_message(Resources.rename_tag_exists_message(prepped));
    }
    
    public void destroy_source() {
        if (Dialogs.confirm_delete_tag(tag))
            AppWindow.get_command_manager().execute(new DeleteTagCommand(tag));
    }
    
    public bool internal_drop_received(Gee.List<MediaSource> media) {
        AppWindow.get_command_manager().execute(new TagUntagPhotosCommand(tag, media, media.size,
            true));
        
        return true;
    }
    
    public Icon? get_sidebar_open_icon() {
        return single_tag_icon;
    }
    
    public Icon? get_sidebar_closed_icon() {
        return single_tag_icon;
    }
    
    public bool expand_on_select() {
        return false;
    }
}

