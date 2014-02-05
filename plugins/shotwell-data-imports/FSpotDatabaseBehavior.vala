/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DataImports.FSpot.Db {

private class FSpotBehaviorEntry {
    private Utils.VersionNumber version;
    private FSpotTableBehavior behavior;
    
    public FSpotBehaviorEntry(Utils.VersionNumber version, FSpotTableBehavior behavior) {
        this.version = version;
        this.behavior = behavior;
    }
    
    public Utils.VersionNumber get_version() {
        return version;
    }
    
    public FSpotTableBehavior get_behavior() {
        return behavior;
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
    public static Utils.VersionNumber MIN_UNSUPPORTED_VERSION =
        new Utils.VersionNumber({ 19 });
    private static Gee.Map<string, Gee.List<FSpotBehaviorEntry>> behavior_map;
    
    private FSpotTableBehavior<FSpotPhotoRow> photos_behavior;
    private FSpotTableBehavior<FSpotTagRow> tags_behavior;
    private FSpotTableBehavior<FSpotPhotoTagRow> photo_tags_behavior;
    private FSpotTableBehavior<FSpotPhotoVersionRow> photo_versions_behavior;
    private FSpotTableBehavior<FSpotRollRow> rolls_behavior;
    
    public static void create_behavior_map() {
        behavior_map = new Gee.HashMap<string, Gee.List<FSpotBehaviorEntry>>();
        // photos table
        Gee.List<FSpotBehaviorEntry> photos_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0-4
        photos_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 0 }),
            FSpotPhotosV0Behavior.get_instance()
        ));
        // v5-6
        photos_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 5 }),
            FSpotPhotosV5Behavior.get_instance()
        ));
        // v7-10
        photos_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 7 }),
            FSpotPhotosV7Behavior.get_instance()
        ));
        // v11-15
        photos_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 11 }),
            FSpotPhotosV11Behavior.get_instance()
        ));
        // v16
        photos_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 16 }),
            FSpotPhotosV16Behavior.get_instance()
        ));
        // v17
        photos_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 17 }),
            FSpotPhotosV17Behavior.get_instance()
        ));
        // v18+
        photos_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 18 }),
            FSpotPhotosV18Behavior.get_instance()
        ));
        behavior_map.set(FSpotPhotosTable.TABLE_NAME, photos_list);
        // tags table
        Gee.List<FSpotBehaviorEntry> tags_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0+
        tags_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 0 }),
            FSpotTagsV0Behavior.get_instance()
        ));
        behavior_map.set(FSpotTagsTable.TABLE_NAME, tags_list);
        // photo_tags table
        Gee.List<FSpotBehaviorEntry> photo_tags_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0+
        photo_tags_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 0 }),
            FSpotPhotoTagsV0Behavior.get_instance()
        ));
        behavior_map.set(FSpotPhotoTagsTable.TABLE_NAME, photo_tags_list);
        // photo_versions table
        Gee.List<FSpotBehaviorEntry> photo_versions_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0-8
        photo_versions_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 0 }),
            FSpotPhotoVersionsV0Behavior.get_instance()
        ));
        // v9-15
        photo_versions_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 9 }),
            FSpotPhotoVersionsV9Behavior.get_instance()
        ));
        // v16
        photo_versions_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 16 }),
            FSpotPhotoVersionsV16Behavior.get_instance()
        ));
        // v17
        photo_versions_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 17 }),
            FSpotPhotoVersionsV17Behavior.get_instance()
        ));
        // v18+
        photo_versions_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 18 }),
            FSpotPhotoVersionsV18Behavior.get_instance()
        ));
        behavior_map.set(FSpotPhotoVersionsTable.TABLE_NAME, photo_versions_list);
        // rolls table
        Gee.List<FSpotBehaviorEntry> rolls_list = new Gee.ArrayList<FSpotBehaviorEntry>();
        // v0-4
        rolls_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 0 }),
            FSpotRollsV0Behavior.get_instance()
        ));
        // v5+
        rolls_list.add(new FSpotBehaviorEntry(
            new Utils.VersionNumber({ 5 }),
            FSpotRollsV5Behavior.get_instance()
        ));
        behavior_map.set(FSpotRollsTable.TABLE_NAME, rolls_list);
    }
    
    public static FSpotTableBehavior? find_behavior(string table_name, Utils.VersionNumber version) {
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
    public FSpotDatabaseBehavior(Utils.VersionNumber version) throws Spit.DataImports.DataImportError {
        if (version.compare_to(MIN_UNSUPPORTED_VERSION) >= 0)
            throw new Spit.DataImports.DataImportError.UNSUPPORTED_VERSION("Version %s is not yet supported", version.to_string());
        
        FSpotTableBehavior? photos_generic_behavior = find_behavior(FSpotPhotosTable.TABLE_NAME, version);
        if (photos_generic_behavior != null)
            photos_behavior = photos_generic_behavior as FSpotTableBehavior<FSpotPhotoRow>;
        FSpotTableBehavior? tags_generic_behavior = find_behavior(FSpotTagsTable.TABLE_NAME, version);
        if (tags_generic_behavior != null)
            tags_behavior = tags_generic_behavior as FSpotTableBehavior<FSpotTagRow>;
        FSpotTableBehavior? photo_tags_generic_behavior = find_behavior(FSpotPhotoTagsTable.TABLE_NAME, version);
        if (photo_tags_generic_behavior != null)
            photo_tags_behavior = photo_tags_generic_behavior as FSpotTableBehavior<FSpotPhotoTagRow>;
        FSpotTableBehavior? photo_versions_generic_behavior = find_behavior(FSpotPhotoVersionsTable.TABLE_NAME, version);
        if (photo_versions_generic_behavior != null)
            photo_versions_behavior = photo_versions_generic_behavior as FSpotTableBehavior<FSpotPhotoVersionRow>;
        FSpotTableBehavior? rolls_generic_behavior = find_behavior(FSpotRollsTable.TABLE_NAME, version);
        if (rolls_generic_behavior != null)
            rolls_behavior = rolls_generic_behavior as FSpotTableBehavior<FSpotRollRow>;
        
        if (photos_behavior == null || tags_behavior == null ||
            photo_tags_behavior == null || photo_versions_behavior == null ||
            rolls_behavior == null
        )
            throw new Spit.DataImports.DataImportError.UNSUPPORTED_VERSION("Version %s is not supported", version.to_string());
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

}

