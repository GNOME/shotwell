/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if ENABLE_FACES

public class FacePage : CollectionPage {
    private Face face;
    
    public FacePage(Face face) {
        base (face.get_name());
        
        this.face = face;
        
        Face.global.items_altered.connect(on_faces_altered);
        face.mirror_sources(get_view(), create_thumbnail);
        
        init_page_context_menu("FacesContextMenu");
    }
    
    ~FacePage() {
        get_view().halt_mirroring();
        Face.global.items_altered.disconnect(on_faces_altered);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        ui_filenames.add("faces.ui");
    }
    
    public Face get_face() {
        return face;
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.Facade.get_instance().get_event_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.Facade.get_instance().set_event_photos_sort(sort_order, sort_by);
    }

    private const GLib.ActionEntry[] entries = {
        { "DeleteFace", on_delete_face },
        { "RenameFace", on_rename_face },
        { "RemoveFaceFromPhotos", on_remove_face_from_photos },
        { "DeleteFaceSidebar", on_delete_face },
        { "RenameFaceSidebar", on_rename_face }
    };

    protected override void init_actions(int selected_count, int count) {
        base.init_actions(selected_count, count);
        
        set_action_sensitive("DeleteFace", true);
        set_action_sensitive("RenameFace", true);
        set_action_sensitive("RemoveFaceFromPhotos", true);
    }
 

    protected override void add_actions (GLib.ActionMap map) {
        base.add_actions (map);

        map.add_action_entries (entries, this);
    }

    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();
        groups += create_faces_menu_injectables();
        return groups;
    }

    private InjectionGroup create_faces_menu_injectables(){
        InjectionGroup menuFaces = new InjectionGroup("FacesMenuPlaceholder");
       
        menuFaces.add_menu_item(Resources.remove_face_from_photos_menu(this.face.get_name(), get_view().get_count()), "RemoveFaceFromPhotos", "<Primary>r");
        menuFaces.add_menu_item(Resources.rename_face_menu(this.face.get_name()), "RenameFace", "<Primary>e");
        menuFaces.add_menu_item(Resources.delete_face_menu(this.face.get_name()), "DeleteFace", "<Primary>t");
        
        return menuFaces;
    }

    private void on_faces_altered(Gee.Map<DataObject, Alteration> map) {
        if (map.has_key(face)) {
            set_page_name(face.get_name());
            update_actions(get_view().get_selected_count(), get_view().get_count());
        }
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_details("DeleteFace",
            Resources.delete_face_menu(face.get_name()),
            null,
            true);
        
        set_action_details("RenameFace",
            Resources.rename_face_menu(face.get_name()),
            null,
            true);
        
        set_action_details("RemoveFaceFromPhotos", 
            Resources.remove_face_from_photos_menu(face.get_name(), get_view().get_count()),
            null,
            selected_count > 0);
        
        base.update_actions(selected_count, count);
    }
    
    private void on_rename_face() {
        LibraryWindow.get_app().rename_face_in_sidebar(face);
    }
    
    private void on_delete_face() {
        if (Dialogs.confirm_delete_face(face))
            AppWindow.get_command_manager().execute(new DeleteFaceCommand(face));
    }
    
    private void on_remove_face_from_photos() {
        if (get_view().get_selected_count() > 0) {
            get_command_manager().execute(new RemoveFacesFromPhotosCommand(face, 
                (Gee.Collection<MediaSource>) get_view().get_selected_sources()));
        }
    }
}

#endif
