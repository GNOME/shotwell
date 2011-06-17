/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class EventPage : CollectionPage {
    private Event page_event;
    
    public EventPage(Event page_event) {
        base (page_event.get_name());
        
        this.page_event = page_event;
        page_event.mirror_photos(get_view(), create_thumbnail);
        
        init_page_context_menu("/EventContextMenu");
        
        Event.global.items_altered.connect(on_events_altered);
    }
    
    ~EventPage() {
        Event.global.items_altered.disconnect(on_events_altered);
        get_view().halt_mirroring();
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("event.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] new_actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry make_primary = { "MakePrimary", Resources.MAKE_PRIMARY,
            TRANSLATABLE, null, TRANSLATABLE, on_make_primary };
        make_primary.label = Resources.MAKE_KEY_PHOTO_MENU;
        new_actions += make_primary;

        Gtk.ActionEntry rename = { "Rename", null, TRANSLATABLE, null, TRANSLATABLE, on_rename };
        rename.label = Resources.RENAME_EVENT_MENU;
        new_actions += rename;

        return new_actions;
    }
    
    protected override void init_actions(int selected_count, int count) {
        base.init_actions(selected_count, count);
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("MakePrimary", selected_count == 1);
        
        // hide this command in CollectionPage, as it does not apply here
        set_action_visible("CommonJumpToEvent", false);
        
        base.update_actions(selected_count, count);
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.Facade.get_instance().get_event_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.Facade.get_instance().set_event_photos_sort(sort_order, sort_by);
    }
    
    private void on_events_altered(Gee.Map<DataObject, Alteration> map) {
        if (map.has_key(page_event))
            set_page_name(page_event.get_name());
    }
    
    private void on_make_primary() {
        if (get_view().get_selected_count() != 1)
            return;
        
        page_event.set_primary_source((MediaSource) get_view().get_selected_at(0).get_source());
    }

    private void on_rename() {
        LibraryWindow.get_app().rename_event_in_sidebar(page_event);
    }
}

public class NoEventPage : CollectionPage {
    public const string NAME = _("No Event");
    
    // This seems very similar to EventSourceCollection -> ViewManager
    private class NoEventViewManager : CollectionViewManager {
        public NoEventViewManager(NoEventPage page) {
            base (page);
        }
        
        // this is not threadsafe
        public override bool include_in_view(DataSource source) {
            return (((MediaSource) source).get_event_id().id != EventID.INVALID) ? false :
                base.include_in_view(source);
        }
    }
    
    private static Alteration no_event_page_alteration = new Alteration("metadata", "event");
    
    public NoEventPage() {
        base (NAME);
        
        ViewManager filter = new NoEventViewManager(this);
        get_view().monitor_source_collection(LibraryPhoto.global, filter, no_event_page_alteration);
        get_view().monitor_source_collection(Video.global, filter, no_event_page_alteration);
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.Facade.get_instance().get_event_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.Facade.get_instance().set_event_photos_sort(sort_order, sort_by);
    }
}

