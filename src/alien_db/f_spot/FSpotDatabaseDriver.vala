/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace AlienDb.FSpot {

public class FSpotDatabaseDriver : Object, AlienDatabaseDriver {
    public static const string FSPOT_DRIVER_ID = "f-spot";
    private static FSpotDatabaseDriver instance;
    
    /**
     * Initialisation method that creates a singleton instance.
     */
    public static void init() {
        // Check for null in case init() is called more than once.
        if(instance == null)
            instance = new FSpotDatabaseDriver();
    }
    
    public static FSpotDatabaseDriver get_instance() {
        return instance;
    }
    
    /**
     * Termination method that clears the singleton instance.
     */
    public static void terminate() {
        instance = null;
    }
    
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
        return new  AlienDatabaseDriverID(FSPOT_DRIVER_ID);
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
                    new AlienDatabaseID(get_id(), db_file.get_path())
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

    public AlienDatabase open_database(AlienDatabaseID db_id) throws DatabaseError, AlienDatabaseError {
        return new FSpotDatabase(this, db_id);
    }
    
    public AlienDatabase open_database_from_file(File db_file) throws DatabaseError, AlienDatabaseError {
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
    
    public static bool is_available() {
        AlienDatabaseDriver? driver = AlienDatabaseHandler.get_instance().get_driver(
            new AlienDatabaseDriverID(FSPOT_DRIVER_ID));
        
        return (driver != null) ? driver.get_discovered_databases().size > 0 : false;
    }
    
    public static void do_import(BatchImport.ImportReporter? report_to_when_done = null) {
        AlienDatabaseDriver? driver = AlienDatabaseHandler.get_instance().get_driver(
            new AlienDatabaseDriverID(FSPOT_DRIVER_ID));
        if (driver == null)
            return;
        
        AlienDatabaseImportDialogController dialog = new AlienDatabaseImportDialogController(
            _("Import From F-Spot"),
            driver, report_to_when_done);
        dialog.execute();
    }
    
    private static void on_import_from_fspot() {
        do_import();
    }
}

}

