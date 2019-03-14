/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Events.Branch : Sidebar.Branch {
    internal static string icon = Resources.ICON_FOLDER;
    internal static string events_icon = Resources.ICON_EVENTS;
    internal static string single_event_icon = Resources.ICON_ONE_EVENT;
    internal static string no_event_icon = Resources.ICON_NO_EVENT;
    
    // NOTE: Because the comparators must be static methods (due to CompareFunc's stupid impl.)
    // and there's an assumption that only one Events.Branch is ever created, this is a static
    // member but it's modified by instance methods.
    private static bool sort_ascending = false;
    
    private Gee.HashMap<Event, Events.EventEntry> entry_map = new Gee.HashMap<
        Event, Events.EventEntry>();
    private Events.UndatedDirectoryEntry undated_entry = new Events.UndatedDirectoryEntry();
    private Events.NoEventEntry no_event_entry = new Events.NoEventEntry();
    private Events.MasterDirectoryEntry all_events_entry = new Events.MasterDirectoryEntry();
    
    public Branch() {
        base (new Sidebar.Header(_("Events"), _("Browse through your events")),
            Sidebar.Branch.Options.STARTUP_EXPAND_TO_FIRST_CHILD,
            event_year_comparator);
        
        graft(get_root(), all_events_entry);
        
        // seed the branch
        foreach (DataObject object in Event.global.get_all())
            add_event((Event) object);
        
        show_no_events(Event.global.get_no_event_objects().size > 0);
        
        // monitor Events for future changes
        Event.global.contents_altered.connect(on_events_added_removed);
        Event.global.items_altered.connect(on_events_altered);
        Event.global.no_event_collection_altered.connect(on_no_event_collection_altered);
        
        // monitor sorting criteria (see note at sort_ascending about this)
        Config.Facade.get_instance().events_sort_ascending_changed.connect(on_config_changed);
    }
    
    ~Branch() {
        Event.global.contents_altered.disconnect(on_events_added_removed);
        Event.global.items_altered.disconnect(on_events_altered);
        Event.global.no_event_collection_altered.disconnect(on_no_event_collection_altered);
        
        Config.Facade.get_instance().events_sort_ascending_changed.disconnect(on_config_changed);
    }
    
    internal static void init() {
        sort_ascending = Config.Facade.get_instance().get_events_sort_ascending();
    }
    
    internal static void terminate() {
    }
    
    public bool is_user_renameable() {
        return true;
    }
    
    public Events.MasterDirectoryEntry get_master_entry() {
        return all_events_entry;
    }
    
    private static int event_year_comparator(Sidebar.Entry a, Sidebar.Entry b) {
        if (a == b)
            return 0;
        
        // The Undated and No Event entries should always appear last in the
        // list, respectively.
        if (a is Events.UndatedDirectoryEntry) {
            if (b is Events.NoEventEntry)
                return -1;
            return 1;
        } else if (b is Events.UndatedDirectoryEntry) {
            if (a is Events.NoEventEntry)
                return 1;
            return -1;
        }
        
        if (a is Events.NoEventEntry)
            return 1;
        else if (b is Events.NoEventEntry)
            return -1;
        
        // The All events entry should always appear on top
        if (a is Events.MasterDirectoryEntry)
            return -1;
        else if (b is Events.MasterDirectoryEntry)
            return 1;
        
        if (!sort_ascending) {
            Sidebar.Entry swap = a;
            a = b;
            b = swap;
        }
        
        int result = 
            ((Events.YearDirectoryEntry) a).get_year() - ((Events.YearDirectoryEntry) b).get_year();
        assert(result != 0);
        
        return result;
    }
    
    private static int event_month_comparator(Sidebar.Entry a, Sidebar.Entry b) {
        if (a == b)
            return 0;
        
        if (!sort_ascending) {
            Sidebar.Entry swap = a;
            a = b;
            b = swap;
        }
        
        int result = 
            ((Events.MonthDirectoryEntry) a).get_month() - ((Events.MonthDirectoryEntry) b).get_month();
        assert(result != 0);
        
        return result;
    }
    
    private static int event_comparator(Sidebar.Entry a, Sidebar.Entry b) {
        if (a == b)
            return 0;
        
        if (!sort_ascending) {
            Sidebar.Entry swap = a;
            a = b;
            b = swap;
        }
        
        int64 result = ((Events.EventEntry) a).get_event().get_start_time() 
            - ((Events.EventEntry) b).get_event().get_start_time();
        
        // to stabilize sort (events with the same start time are allowed)
        if (result == 0) {
            result = ((Events.EventEntry) a).get_event().get_event_id().id
                - ((Events.EventEntry) b).get_event().get_event_id().id;
        }
        
        assert(result != 0);
        
        return (result < 0) ? -1 : 1;
    }
    
    private static int undated_event_comparator(Sidebar.Entry a, Sidebar.Entry b) {
        if (a == b)
            return 0;
        
        if (!sort_ascending) {
            Sidebar.Entry swap = a;
            a = b;
            b = swap;
        }
        
        int ret = ((Events.EventEntry) a).get_event().get_name().collate(
            ((Events.EventEntry) b).get_event().get_name());
        
        if (ret == 0)
            ret = (int) (((Events.EventEntry) b).get_event().get_instance_id() - 
                ((Events.EventEntry) a).get_event().get_instance_id());
        
        return ret;
    }
    
    public Events.EventEntry? get_entry_for_event(Event event) {
        return entry_map.get(event);
    }
    
    private void on_config_changed() {
        bool value = Config.Facade.get_instance().get_events_sort_ascending();
        
        sort_ascending = value;
        reorder_all();
    }
    
    private void on_events_added_removed(Gee.Iterable<DataObject>? added, 
        Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added)
                add_event((Event) object);
        }
        
        if (removed != null) {
            foreach (DataObject object in removed)
                remove_event((Event) object);
        }
    }
    
    private void on_events_altered(Gee.Map<DataObject, Alteration> altered) {
        foreach (DataObject object in altered.keys) {
            Event event = (Event) object;
            Alteration alteration = altered.get(object);
            
            if (alteration.has_detail("metadata", "time")) {
                // can't merely re-sort the event because it might have moved to a new month or
                // even a new year
                move_event(event);
            } else if (alteration.has_detail("metadata", "name")) {
                Events.EventEntry? entry = entry_map.get(event);
                assert(entry != null);
                
                entry.sidebar_name_changed(event.get_name());
                entry.sidebar_tooltip_changed(event.get_name());
            }
        }
    }
    
    private void on_no_event_collection_altered() {
        show_no_events(Event.global.get_no_event_objects().size > 0);
    }
    
    private void add_event(Event event) {
        time_t event_time = event.get_start_time();
        if (event_time == 0) {
            add_undated_event(event);
            
            return;
        }
        
        Time event_tm = Time.local(event_time);
        
        Sidebar.Entry? year;
        Sidebar.Entry? month = find_event_month(event, event_tm, out year);
        if (month != null) {
            graft_event(month, event, event_comparator);
            
            return;
        }
        
        if (year == null) {
            year = new Events.YearDirectoryEntry(event_tm.format(SubEventsDirectoryPage.YEAR_FORMAT),
                event_tm);
            graft(get_root(), year, event_month_comparator);
        }
        
        month = new Events.MonthDirectoryEntry(event_tm.format(SubEventsDirectoryPage.MONTH_FORMAT),
            event_tm);
        graft(year, month, event_comparator);
        
        graft_event(month, event, event_comparator);
    }
    
    private void move_event(Event event) {
        time_t event_time = event.get_start_time();
        if (event_time == 0) {
            move_to_undated_event(event);
            
            return;
        }
        
        Time event_tm = Time.local(event_time);
        
        Sidebar.Entry? year;
        Sidebar.Entry? month = find_event_month(event, event_tm, out year);
        
        if (year == null) {
            year = new Events.YearDirectoryEntry(event_tm.format(SubEventsDirectoryPage.YEAR_FORMAT),
                event_tm);
            graft(get_root(), year, event_month_comparator);
        }
        
        if (month == null) {
            month = new Events.MonthDirectoryEntry(event_tm.format(SubEventsDirectoryPage.MONTH_FORMAT),
                event_tm);
            graft(year, month, event_comparator);
        }
        
        reparent_event(event, month);
    }
    
    private void remove_event(Event event) {
        // the following code works for undated events as well as dated (no need for special
        // case, as in add_event())
        Sidebar.Entry? entry;
        bool removed = entry_map.unset(event, out entry);
        assert(removed);
        
        Sidebar.Entry? parent = get_parent(entry);
        assert(parent != null);
        
        prune(entry);
        
        // prune up the tree to the root
        while (get_child_count(parent) == 0 && parent != get_root()) {
            Sidebar.Entry? grandparent = get_parent(parent);
            assert(grandparent != null);
            
            prune(parent);
            
            parent = grandparent;
        }
    }
    
    private Sidebar.Entry? find_event_month(Event event, Time event_tm, out Sidebar.Entry found_year) {
        // find the year first
        found_year = find_event_year(event, event_tm);
        if (found_year == null)
            return null;
        
        int event_month = event_tm.month + 1;
        
        // found the year, traverse the months
        return find_first_child(found_year, (entry) => {
            return ((Events.MonthDirectoryEntry) entry).get_month() == event_month;
        });
    }
    
    private Sidebar.Entry? find_event_year(Event event, Time event_tm) {
        int event_year = event_tm.year + 1900;
        
        return find_first_child(get_root(), (entry) => {
            if ((entry is Events.UndatedDirectoryEntry) || (entry is Events.NoEventEntry) || 
                 entry is Events.MasterDirectoryEntry)
                return false;
            else
                return ((Events.YearDirectoryEntry) entry).get_year() == event_year;
        });
    }
    
    private void add_undated_event(Event event) {
        if (!has_entry(undated_entry))
            graft(get_root(), undated_entry, undated_event_comparator);
        
        graft_event(undated_entry, event);
    }
    
    private void move_to_undated_event(Event event) {
        if (!has_entry(undated_entry))
            graft(get_root(), undated_entry);
        
        reparent_event(event, undated_entry);
    }
    
    private void graft_event(Sidebar.Entry parent, Event event,
        owned CompareFunc<Sidebar.Entry>? comparator = null) {
        Events.EventEntry entry = new Events.EventEntry(event);
        entry_map.set(event, entry);
        
        graft(parent, entry, comparator);
    }
    
    private void reparent_event(Event event, Sidebar.Entry new_parent) {
        Events.EventEntry? entry = entry_map.get(event);
        assert(entry != null);
        
        Sidebar.Entry? old_parent = get_parent(entry);
        assert(old_parent != null);
        
        reparent(new_parent, entry);
        
        while (get_child_count(old_parent) == 0 && old_parent != get_root()) {
            Sidebar.Entry? grandparent = get_parent(old_parent);
            assert(grandparent != null);
            
            prune(old_parent);
            
            old_parent = grandparent;
        }
    }
    
    private void show_no_events(bool show) {
        if (show && !has_entry(no_event_entry))
            graft(get_root(), no_event_entry);
        else if (!show && has_entry(no_event_entry))
            prune(no_event_entry);
    }
}

public abstract class Events.DirectoryEntry : Sidebar.SimplePageEntry, Sidebar.ExpandableEntry {
    public override string? get_sidebar_icon() {
        return Events.Branch.icon;
    }
    
    public bool expand_on_select() {
        return true;
    }
}

public class Events.MasterDirectoryEntry : Events.DirectoryEntry {
    public MasterDirectoryEntry() {
    }
    
    public override string get_sidebar_name() {
        return MasterEventsDirectoryPage.NAME;
    }
    
    public override string? get_sidebar_icon() {
        return Events.Branch.events_icon;
    }
    
    protected override Page create_page() {
        return new MasterEventsDirectoryPage();
    }
}

public class Events.YearDirectoryEntry : Events.DirectoryEntry {
    private string name;
    private Time tm;
    
    public YearDirectoryEntry(string name, Time tm) {
        this.name = name;
        this.tm = tm;
    }
    
    public override string get_sidebar_name() {
        return name;
    }
    
    public int get_year() {
        return tm.year + 1900;
    }
    
    protected override Page create_page() {
        return new SubEventsDirectoryPage(SubEventsDirectoryPage.DirectoryType.YEAR, tm);
    }
}

public class Events.MonthDirectoryEntry : Events.DirectoryEntry {
    private string name;
    private Time tm;
    
    public MonthDirectoryEntry(string name, Time tm) {
        this.name = name;
        this.tm = tm;
    }
    
    public override string get_sidebar_name() {
        return name;
    }
    
    public int get_year() {
        return tm.year + 1900;
    }
    
    public int get_month() {
        return tm.month + 1;
    }
    
    protected override Page create_page() {
        return new SubEventsDirectoryPage(SubEventsDirectoryPage.DirectoryType.MONTH, tm);
    }
}

public class Events.UndatedDirectoryEntry : Events.DirectoryEntry {
    public UndatedDirectoryEntry() {
    }
    
    public override string get_sidebar_name() {
        return SubEventsDirectoryPage.UNDATED_PAGE_NAME;
    }
    
    protected override Page create_page() {
        return new SubEventsDirectoryPage(SubEventsDirectoryPage.DirectoryType.UNDATED,
            Time.local(0));
    }
}

public class Events.EventEntry : Sidebar.SimplePageEntry, Sidebar.RenameableEntry,
    Sidebar.InternalDropTargetEntry {
    private Event event;
    
    public EventEntry(Event event) {
        this.event = event;
    }
    
    public Event get_event() {
        return event;
    }
    
    public override string get_sidebar_name() {
        return event.get_name();
    }
    
    public override string? get_sidebar_icon() {
        return Events.Branch.single_event_icon;
    }
    
    protected override Page create_page() {
        return new EventPage(event);
    }
    
    public bool is_user_renameable() {
        return true;
    }
    
    public void rename(string new_name) {
        string? prepped = Event.prep_event_name(new_name);
        if (prepped != null)
            AppWindow.get_command_manager().execute(new RenameEventCommand(event, prepped));
    }
    
    public bool internal_drop_received(Gee.List<MediaSource> media) {
        // ugh ... some early Commands expected DataViews instead of DataSources (to make life
        // easier for Pages) and this is one of the prices paid for that
        Gee.ArrayList<DataView> views = new Gee.ArrayList<DataView>();
        foreach (MediaSource media_source in media)
            views.add(new DataView(media_source));
        
        AppWindow.get_command_manager().execute(new SetEventCommand(views, event));
        
        return true;
    }
    
    public bool internal_drop_received_arbitrary(Gtk.SelectionData data) {
        return false;
    }
}


public class Events.NoEventEntry : Sidebar.SimplePageEntry {
    public NoEventEntry() {
    }
    
    public override string get_sidebar_name() {
        return NoEventPage.NAME;
    }
    
    public override string? get_sidebar_icon() {
        return Events.Branch.no_event_icon;
    }
    
    protected override Page create_page() {
        return new NoEventPage();
    }
}

