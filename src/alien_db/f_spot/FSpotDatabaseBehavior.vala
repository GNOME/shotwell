/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb.FSpot {

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

}

