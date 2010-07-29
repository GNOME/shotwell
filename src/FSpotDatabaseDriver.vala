/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class FSpotDatabaseDriver : Object, AlienDatabaseDriver {
    public static const string FSPOT_DRIVER_ID = "f-spot";
    
    private class FSpotBehaviorEntry {
        private AlienDatabaseVersion version;
        private FSpotTableBehavior behavior;
        
        public FSpotBehaviorEntry(AlienDatabaseVersion version, FSpotTableBehavior behavior) {
            this.version = version;
            this.behavior = behavior;
        }
        
        public AlienDatabaseVersion get_version() {
            return version;
        }
        
        public FSpotTableBehavior get_behavior() {
            return behavior;
        }
    }
    
    private Gee.Map<string, Gee.List<FSpotBehaviorEntry>> behavior_map;
    
    public FSpotDatabaseDriver() {
        behavior_map = new Gee.HashMap<string, Gee.List<FSpotBehaviorEntry>>();
        // photos table
        Gee.List<FSpotBehaviorEntry> photos_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0-4
        photos_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 0 }),
            FSpotPhotosV0Behavior.get_instance()
        ));
        // v5-6
        photos_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 5 }),
            FSpotPhotosV5Behavior.get_instance()
        ));
        // v7-10
        photos_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 7 }),
            FSpotPhotosV7Behavior.get_instance()
        ));
        // v11-15
        photos_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 11 }),
            FSpotPhotosV11Behavior.get_instance()
        ));
        // v16
        photos_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 16 }),
            FSpotPhotosV16Behavior.get_instance()
        ));
        // v17
        photos_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 17 }),
            FSpotPhotosV17Behavior.get_instance()
        ));
        // v18+
        photos_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 18 }),
            FSpotPhotosV18Behavior.get_instance()
        ));
        behavior_map.set(FSpotPhotosTable.TABLE_NAME, photos_list);
        // tags table
        Gee.List<FSpotBehaviorEntry> tags_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0+
        tags_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 0 }),
            FSpotTagsV0Behavior.get_instance()
        ));
        behavior_map.set(FSpotTagsTable.TABLE_NAME, tags_list);
        // photo_tags table
        Gee.List<FSpotBehaviorEntry> photo_tags_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0+
        photo_tags_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 0 }),
            FSpotPhotoTagsV0Behavior.get_instance()
        ));
        behavior_map.set(FSpotPhotoTagsTable.TABLE_NAME, photo_tags_list);
        // photo_versions table
        Gee.List<FSpotBehaviorEntry> photo_versions_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0-8
        photo_versions_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 0 }),
            FSpotPhotoVersionsV0Behavior.get_instance()
        ));
        // v9-15
        photo_versions_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 9 }),
            FSpotPhotoVersionsV9Behavior.get_instance()
        ));
        // v16
        photo_versions_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 16 }),
            FSpotPhotoVersionsV16Behavior.get_instance()
        ));
        // v17
        photo_versions_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 17 }),
            FSpotPhotoVersionsV17Behavior.get_instance()
        ));
        // v18+
        photo_versions_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 18 }),
            FSpotPhotoVersionsV18Behavior.get_instance()
        ));
        behavior_map.set(FSpotPhotoVersionsTable.TABLE_NAME, photo_versions_list);
        // rolls table
        Gee.List<FSpotBehaviorEntry> rolls_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0-4
        rolls_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 0 }),
            FSpotRollsV0Behavior.get_instance()
        ));
        // v5+
        rolls_list.add(new FSpotBehaviorEntry(
            new AlienDatabaseVersion({ 5 }),
            FSpotRollsV5Behavior.get_instance()
        ));
        behavior_map.set(FSpotRollsTable.TABLE_NAME, rolls_list);
    }
    
    ~FSpotDatabaseDriver() {
    }
    
    public AlienDatabaseDriverID get_id() {
        return AlienDatabaseDriverID(FSPOT_DRIVER_ID);
    }
    
    public string get_display_name() {
        return "F-Spot";
    }
    
    public Gee.Collection<DiscoveredAlienDatabase> get_discovered_databases() {
        Gee.ArrayList<DiscoveredAlienDatabase> discovered_databases =
            new Gee.ArrayList<DiscoveredAlienDatabase>();
        
        File[] db_files = {
            // where the DB is in Ubuntu Lucid
            File.new_for_path(Environment.get_user_config_dir()).
                get_child("f-spot").get_child("photos.db"),
            // where it seems to be in Ubuntu Jaunty
            File.new_for_path(Environment.get_home_dir()).get_child(".gnome2").
                get_child("f-spot").get_child("photos.db"),
            // where it should really be if it followed the XDG spec
            File.new_for_path(Environment.get_user_data_dir()).
                get_child("f-spot").get_child("photos.db")
        };
        
        foreach (File db_file in db_files) {
            if (db_file.query_exists(null)) {
                discovered_databases.add(new DiscoveredAlienDatabase(
                    AlienDatabaseID(get_id(), db_file.get_path())
                ));
                message("Discovered database: %s", db_file.get_path());
            }
        }
        
        return discovered_databases;
    }
    
    public FSpotTableBehavior? find_behavior(string table_name, AlienDatabaseVersion version) {
        FSpotTableBehavior behavior = null;
        Gee.List<FSpotBehaviorEntry> behavior_list = behavior_map.get(table_name);
        if (behavior_list != null)
            foreach (FSpotBehaviorEntry entry in behavior_list) {
                if (version.compare_to(entry.get_version()) >= 0)
                    behavior = entry.get_behavior();
            }
        else
            warning("Could not find behavior list for table %s", table_name);
        return behavior;
    }

    public AlienDatabase open_database(AlienDatabaseID db_id) throws AlienDatabaseError {
        return new FSpotDatabase(this, db_id);
    }
    
    public AlienDatabase open_database_from_file(File db_file) throws AlienDatabaseError {
        return new FSpotDatabase.from_file(this, db_file);
    }
    
    public string get_menu_name() {
        return "ImportFromFSpot";
    }
    
    public Gtk.ActionEntry get_action_entry() {
        Gtk.ActionEntry result = {
            "ImportFromFSpot", null, TRANSLATABLE, null, null, on_import_from_fspot
        };
        result.label = _("Import From _F-Spot...");
        result.tooltip = _("Import the content of an external F-Spot database");
        return result;
    }
    
    public static void on_import_from_fspot() {
        AlienDatabaseDriver driver = AlienDatabaseHandler.get_instance().get_driver(
            AlienDatabaseDriverID(FSPOT_DRIVER_ID)
        );
        AlienDatabaseImportDialog dialog = new AlienDatabaseImportDialog(
            _("Import From F-Spot"), driver
        );
        dialog.show();
    }
}

public class FSpotDatabase : Object, AlienDatabase {
    private AlienDatabaseID id;
    private Sqlite.Database fspot_db;
    private FSpotMetaTable meta_table;
    private FSpotPhotosTable photos_table;
    private FSpotPhotoVersionsTable photo_versions_table;
    private FSpotTagsTable tags_table;
    private FSpotRollsTable rolls_table;
    private int64 hidden_tag_id;
    
    public FSpotDatabase(FSpotDatabaseDriver driver, AlienDatabaseID id) throws AlienDatabaseError {
        this.id = id;
        initialize(driver, id.driver_specific_uri);
    }
    
    public FSpotDatabase.from_file(FSpotDatabaseDriver driver, File db_file) throws AlienDatabaseError {
        this.id = AlienDatabaseID(driver.get_id(), db_file.get_path());
        initialize(driver, db_file.get_path());
    }
    
    private void initialize(FSpotDatabaseDriver driver, string filename) throws AlienDatabaseError {
        int res = Sqlite.Database.open_v2(filename, out fspot_db,
            Sqlite.OPEN_READONLY, null);
        if (res != Sqlite.OK)
            throw new AlienDatabaseError.DATABASE_ERROR("Unable to open F-Spot database %s: %d", filename, res);
        meta_table = new FSpotMetaTable(fspot_db);
        hidden_tag_id = meta_table.get_hidden_tag_id();
        
        FSpotDatabaseBehavior db_behavior = new FSpotDatabaseBehavior(driver, get_version());
        
        photos_table = new FSpotPhotosTable(fspot_db, db_behavior);
        photo_versions_table = new FSpotPhotoVersionsTable(fspot_db, db_behavior);
        tags_table = new FSpotTagsTable(fspot_db, db_behavior);
        rolls_table = new FSpotRollsTable(fspot_db, db_behavior);
    }
    
    ~FSpotDatabase() {
    }
    
    public string get_uri() {
        return id.to_uri();
    }
    
    public string get_display_name() {
        return _("F-Spot");
    }
    
    private AlienDatabaseVersion get_version() throws AlienDatabaseError {
        return new AlienDatabaseVersion.from_string(meta_table.get_db_version());
    }
    
    public Gee.Collection<AlienDatabasePhoto> get_photos() throws AlienDatabaseError {
        Gee.List<AlienDatabasePhoto> photos = new Gee.ArrayList<AlienDatabasePhoto>();

        foreach (FSpotPhotoRow photo_row in photos_table.get_all()) {
            bool hidden = false;
            bool favorite = false;
            Gee.ArrayList<AlienDatabaseTag> tags = new Gee.ArrayList<AlienDatabaseTag>();
            AlienDatabaseEvent? event = null;
            
            // TODO: We do not convert F-Spot events to Shotwell events because F-Spot's events
            // are essentially tags.  We would need to detect if the tag is an event (use
            // is_tag_event) and then assign the event to the photo ... since a photo can be
            // in multiple F-Spot events, we would need to pick one, and since their tags
            // are heirarchical, we would need to pick a name (probably the leaf)
            foreach (FSpotTagRow tag_row in tags_table.get_by_photo_id(photo_row.photo_id)) {
                FSpotDatabaseTag tag = new FSpotDatabaseTag(tag_row);
                if (is_tag_hidden(tag))
                    hidden = true;
                else if (is_tag_favorite(tag))
                    favorite = true;
                else
                    while (tag != null) {
                        if(!tag.is_stock())
                            tags.add(tag);
                        tag = get_tag_parent(tag);
                    }
            }
            
            FSpotRollRow? roll_row = rolls_table.get_by_id(photo_row.roll_id);
            
            foreach (FSpotPhotoVersionRow photo_version_row in photo_versions_table.get_by_photo_id(photo_row.photo_id)) {
                photos.add(new FSpotDatabasePhoto(
                    photo_row, photo_version_row, roll_row, tags, event, hidden, favorite
                ));
            }
        }
        
        return photos;
    }
    
    public FSpotDatabaseTag? get_tag_parent(FSpotDatabaseTag tag) throws AlienDatabaseError {
        FSpotDatabaseTag? parent_tag = null;
        FSpotTagID parent_id = tag.get_row().category_id;
        if (parent_id.is_valid() && !parent_id.is_null()) {
            FSpotTagRow? parent_row = tags_table.get_by_id(parent_id);
            if (parent_row != null)
                parent_tag = new FSpotDatabaseTag(parent_row);
        }
        return parent_tag;
    }
    
    public bool is_tag_event(FSpotDatabaseTag tag) throws AlienDatabaseError {
        bool result = (FSpotTagsTable.STOCK_ICON_EVENTS == tag.get_row().stock_icon);
        if (!result) {
            FSpotDatabaseTag? parent = get_tag_parent(tag);
            if (parent == null)
                result = false;
            else
                result = is_tag_event(parent);
        }
        return result;
    }
    
    public bool is_tag_hidden(FSpotDatabaseTag tag) throws AlienDatabaseError {
        bool result = (hidden_tag_id == tag.get_row().tag_id.id);
        if (!result) {
            FSpotDatabaseTag? parent = get_tag_parent(tag);
            if (parent == null)
                result = false;
            else
                result = is_tag_hidden(parent);
        }
        return result;
    }
    
    public bool is_tag_favorite(FSpotDatabaseTag tag) throws AlienDatabaseError {
        bool result = (FSpotTagsTable.STOCK_ICON_FAV == tag.get_row().stock_icon);
        if (!result) {
            FSpotDatabaseTag? parent = get_tag_parent(tag);
            if (parent == null)
                result = false;
            else
                result = is_tag_favorite(parent);
        }
        return result;
    }
}

/**
 * A class that consolidates the behavior of all F-Spot tables (apart from meta)
 * and is the one place to check whether the database version is supported.
 */
public class FSpotDatabaseBehavior : Object {
    // Minimum unsupported version: any database from that version and above
    // is not supported as it's too new and support has not been provided
    // In practice, the code may work with future versions but this cannot be
    // guaranteed as it hasn't been tested so it's probably better to just
    // bomb out at that point rather than risk importing incorrect data
    public static AlienDatabaseVersion MIN_UNSUPPORTED_VERSION =
        new AlienDatabaseVersion({ 19 });
    
    private FSpotTableBehavior<FSpotPhotoRow> photos_behavior;
    private FSpotTableBehavior<FSpotTagRow> tags_behavior;
    private FSpotTableBehavior<FSpotPhotoTagRow> photo_tags_behavior;
    private FSpotTableBehavior<FSpotPhotoVersionRow> photo_versions_behavior;
    private FSpotTableBehavior<FSpotRollRow> rolls_behavior;
    
    public FSpotDatabaseBehavior(
        FSpotDatabaseDriver driver, AlienDatabaseVersion version
    ) throws AlienDatabaseError {
        if (version.compare_to(MIN_UNSUPPORTED_VERSION) >= 0)
            throw new AlienDatabaseError.UNSUPPORTED_VERSION("Version %s is not yet supported", version.to_string());
        
        FSpotTableBehavior? photos_generic_behavior = driver.find_behavior(FSpotPhotosTable.TABLE_NAME, version);
        if (photos_generic_behavior != null)
            photos_behavior = photos_generic_behavior as FSpotTableBehavior<FSpotPhotoRow>;
        FSpotTableBehavior? tags_generic_behavior = driver.find_behavior(FSpotTagsTable.TABLE_NAME, version);
        if (tags_generic_behavior != null)
            tags_behavior = tags_generic_behavior as FSpotTableBehavior<FSpotTagRow>;
        FSpotTableBehavior? photo_tags_generic_behavior = driver.find_behavior(FSpotPhotoTagsTable.TABLE_NAME, version);
        if (photo_tags_generic_behavior != null)
            photo_tags_behavior = photo_tags_generic_behavior as FSpotTableBehavior<FSpotPhotoTagRow>;
        FSpotTableBehavior? photo_versions_generic_behavior = driver.find_behavior(FSpotPhotoVersionsTable.TABLE_NAME, version);
        if (photo_versions_generic_behavior != null)
            photo_versions_behavior = photo_versions_generic_behavior as FSpotTableBehavior<FSpotPhotoVersionRow>;
        FSpotTableBehavior? rolls_generic_behavior = driver.find_behavior(FSpotRollsTable.TABLE_NAME, version);
        if (rolls_generic_behavior != null)
            rolls_behavior = rolls_generic_behavior as FSpotTableBehavior<FSpotRollRow>;
        
        if (photos_behavior == null || tags_behavior == null ||
            photo_tags_behavior == null || photo_versions_behavior == null ||
            rolls_behavior == null
        )
            throw new AlienDatabaseError.UNSUPPORTED_VERSION("Version %s is not supported", version.to_string());
    }
    
    public FSpotTableBehavior<FSpotPhotoRow> get_photos_behavior() {
        return photos_behavior;
    }
    
    public FSpotTableBehavior<FSpotTagRow> get_tags_behavior() {
        return tags_behavior;
    }
    
    public FSpotTableBehavior<FSpotPhotoTagRow> get_photo_tags_behavior() {
        return photo_tags_behavior;
    }
    
    public FSpotTableBehavior<FSpotPhotoVersionRow> get_photo_versions_behavior() {
        return photo_versions_behavior;
    }
    
    public FSpotTableBehavior<FSpotRollRow> get_rolls_behavior() {
        return rolls_behavior;
    }
}

/**
 * The object that implements an F-Spot photo and provides access to all the
 * elements necessary to read data from the photographic source.
 */
public class FSpotDatabasePhoto : Object, AlienDatabasePhoto {
    private FSpotPhotoRow photo_row;
    private FSpotPhotoVersionRow photo_version_row;
    private FSpotRollRow? roll_row;
    private Gee.Collection<AlienDatabaseTag> tags;
    private AlienDatabaseEvent? event;
    private Rating rating;
    
    public FSpotDatabasePhoto(
        FSpotPhotoRow photo_row,
        FSpotPhotoVersionRow photo_version_row,
        FSpotRollRow? roll_row,
        Gee.Collection<AlienDatabaseTag> tags,
        AlienDatabaseEvent? event,
        bool is_hidden,
        bool is_favorite
    ) {
        this.photo_row = photo_row;
        this.photo_version_row = photo_version_row;
        this.roll_row = roll_row;
        this.tags = tags;
        this.event = event;
        if (photo_row.rating > 0)
            this.rating = Rating.unserialize(photo_row.rating);
        else if (is_hidden)
            this.rating = Rating.REJECTED;
        else if (is_favorite)
            this.rating = Rating.FIVE;
        else
            this.rating = Rating.UNRATED;
    }
    
    public string get_folder_path() {
        return photo_version_row.base_path.get_path();
    }
    
    public string get_filename() {
        return photo_version_row.filename;
    }
    
    public Gee.Collection<AlienDatabaseTag> get_tags() {
        return tags;
    }
    
    public AlienDatabaseEvent? get_event() {
        return event;
    }
    
    public Rating get_rating() {
        return rating;
    }
    
    public string? get_title() {
        return is_string_empty(photo_row.description) ? null : photo_row.description;
    }
    
    public ImportID? get_import_id() {
        if (roll_row != null)
            return ImportID((int64)roll_row.time);
        else
            return null;
    }
}

public class FSpotDatabaseTag: Object, AlienDatabaseTag {
    private FSpotTagRow row;
    
    public FSpotDatabaseTag(FSpotTagRow row) {
        this.row = row;
    }
    
    public string get_name() {
        return row.name;
    }
    
    public bool is_stock() {
        return (row.stock_icon.has_prefix(FSpotTagsTable.PREFIX_STOCK_ICON));
    }
    
    public FSpotTagRow get_row() {
        return row;
    }
    
    public FSpotDatabaseEvent to_event() {
        return new FSpotDatabaseEvent(this.row);
    }
}

// Events are a special type of tags as far as FSpot is concered so this
// class wraps a tag row.
public class FSpotDatabaseEvent: Object, AlienDatabaseEvent {
    private FSpotTagRow row;
    
    public FSpotDatabaseEvent(FSpotTagRow row) {
        this.row = row;
    }
    
    public string get_name() {
        return row.name;
    }
}

