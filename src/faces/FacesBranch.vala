/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if ENABLE_FACES

public class Faces.Branch : Sidebar.Branch {
    private Gee.HashMap<Face, Faces.SidebarEntry> entry_map = new Gee.HashMap<Face, Faces.SidebarEntry>();
    
    public Branch() {
        base (new Faces.Grouping(),
            Sidebar.Branch.Options.HIDE_IF_EMPTY
                | Sidebar.Branch.Options.AUTO_OPEN_ON_NEW_CHILD
                | Sidebar.Branch.Options.STARTUP_EXPAND_TO_FIRST_CHILD,
            comparator);
        
        // seed the branch with existing faces
        on_faces_added_removed(Face.global.get_all(), null);
        
        // monitor collection for future events
        Face.global.contents_altered.connect(on_faces_added_removed);
        Face.global.items_altered.connect(on_faces_altered);
    }
    
    ~Branch() {
        Face.global.contents_altered.disconnect(on_faces_added_removed);
        Face.global.items_altered.disconnect(on_faces_altered);
    }
    
    public Faces.SidebarEntry? get_entry_for_face(Face face) {
        return entry_map.get(face);
    }
    
    private static int comparator(Sidebar.Entry a, Sidebar.Entry b) {
        if (a == b)
            return 0;
        
        return Face.compare_names(((Faces.SidebarEntry) a).for_face(),
            ((Faces.SidebarEntry) b).for_face());
    }
    
    private void on_faces_added_removed(Gee.Iterable<DataObject>? added, Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added) {
                Face face = (Face) object;
                
                Faces.SidebarEntry entry = new Faces.SidebarEntry(face);
                entry_map.set(face, entry);
                
                graft(get_root(), entry);
            }
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                Face face = (Face) object;
                
                Faces.SidebarEntry? entry = entry_map.get(face);
                assert(entry != null);
                
                bool is_removed = entry_map.unset(face);
                assert(is_removed);
                
                prune(entry);
            }
        }
    }
    
    private void on_faces_altered(Gee.Map<DataObject, Alteration> altered) {
        foreach (DataObject object in altered.keys) {
            if (!altered.get(object).has_detail("metadata", "name"))
                continue;
            
            Face face = (Face) object;
            Faces.SidebarEntry? entry = entry_map.get(face);
            assert(entry != null);
            
            entry.sidebar_name_changed(face.get_name());
            entry.sidebar_tooltip_changed(face.get_name());
            reorder(entry);
        }
    }
}

public class Faces.Grouping : Sidebar.Header {
    public Grouping() {
        base (_("Faces"));
    }
}

public class Faces.SidebarEntry : Sidebar.SimplePageEntry, Sidebar.RenameableEntry,
    Sidebar.DestroyableEntry {
    private static string single_face_icon = Resources.ICON_ONE_FACE;
    
    private Face face;
    
    public SidebarEntry(Face face) {
        this.face = face;
    }
    
    internal static void init() {
    }
    
    internal static void terminate() {
    }
    
    public Face for_face() {
        return face;
    }
    
    public bool is_user_renameable() {
        return true;
    }
    
    public override string get_sidebar_name() {
        return face.get_name();
    }
    
    public override string? get_sidebar_icon() {
        return single_face_icon;
    }
    
    protected override Page create_page() {
        return new FacePage(face);
    }
    
    public void rename(string new_name) {
        string? prepped = Face.prep_face_name(new_name);
        if (prepped == null)
            return;
        
        if (!Face.global.exists(prepped))
            AppWindow.get_command_manager().execute(new RenameFaceCommand(face, prepped));
        else if (prepped != face.get_name())
            AppWindow.error_message(Resources.rename_face_exists_message(prepped));
    }
    
    public void destroy_source() {
        if (Dialogs.confirm_delete_face(face))
            AppWindow.get_command_manager().execute(new DeleteFaceCommand(face));
    }
}

#endif
