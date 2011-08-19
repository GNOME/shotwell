/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb.FSpot {

internal class FSpotTagsCache : Object {
    private FSpotTagsTable tags_table;
    private Gee.HashMap<FSpotTagID, FSpotDatabaseTag> tags_map;
    
    public FSpotTagsCache(FSpotTagsTable tags_table) throws DatabaseError {
        this.tags_table = tags_table;
        tags_map = new Gee.HashMap<FSpotTagID, FSpotDatabaseTag> ();
    }
    
    public FSpotDatabaseTag get_tag(FSpotTagRow tag_row) throws DatabaseError {
        FSpotDatabaseTag? tag = tags_map.get(tag_row.tag_id);
        if (tag != null) {
            return tag;
        } else {
            FSpotDatabaseTag? parent_tag = get_tag_from_id(tag_row.category_id);
            FSpotDatabaseTag new_tag = new FSpotDatabaseTag(tag_row, parent_tag);
            tags_map[tag_row.tag_id] = new_tag;
            return new_tag;
        }
    }
    
    private FSpotDatabaseTag? get_tag_from_id(FSpotTagID tag_id) throws DatabaseError {
        if (tag_id.is_null() || tag_id.is_invalid())
            return null;
        FSpotDatabaseTag? tag = tags_map.get(tag_id);
        if (tag != null)
            return tag;
        FSpotTagRow? tag_row = tags_table.get_by_id(tag_id);
        if (tag_row != null) {
            FSpotDatabaseTag? parent_tag = get_tag_from_id(tag_row.category_id);
            FSpotDatabaseTag new_tag = new FSpotDatabaseTag(tag_row, parent_tag);
            tags_map[tag_id] = new_tag;
            return new_tag;
        }
        return null;
    }
}

/**
 * An implementation of AlienDatabase that is able to read from the F-Spot
 * database and extract the relevant objects.
 */
public class FSpotDatabase : Object, AlienDatabase {
    private AlienDatabaseID id;
    private Sqlite.Database fspot_db;
    private FSpotMetaTable meta_table;
    private FSpotPhotosTable photos_table;
    private FSpotPhotoVersionsTable photo_versions_table;
    private FSpotTagsTable tags_table;
    private FSpotTagsCache tags_cache;
    private FSpotRollsTable rolls_table;
    private int64 hidden_tag_id;
    
    public FSpotDatabase(FSpotDatabaseDriver driver, AlienDatabaseID id) throws DatabaseError, AlienDatabaseError {
        this.id = id;
        initialize(driver, id.driver_specific_uri);
    }
    
    public FSpotDatabase.from_file(FSpotDatabaseDriver driver, File db_file) throws DatabaseError, AlienDatabaseError {
        this.id = AlienDatabaseID(driver.get_id(), db_file.get_path());
        initialize(driver, db_file.get_path());
    }
    
    private void initialize(FSpotDatabaseDriver driver, string filename) throws DatabaseError, AlienDatabaseError {
        int res = Sqlite.Database.open_v2(filename, out fspot_db,
            Sqlite.OPEN_READONLY, null);
        if (res != Sqlite.OK)
            throw new DatabaseError.ERROR("Unable to open F-Spot database %s: %d", filename, res);
        meta_table = new FSpotMetaTable(fspot_db);
        hidden_tag_id = meta_table.get_hidden_tag_id();
        
        FSpotDatabaseBehavior db_behavior = new FSpotDatabaseBehavior(driver, get_version());
        
        photos_table = new FSpotPhotosTable(fspot_db, db_behavior);
        photo_versions_table = new FSpotPhotoVersionsTable(fspot_db, db_behavior);
        tags_table = new FSpotTagsTable(fspot_db, db_behavior);
        tags_cache = new FSpotTagsCache(tags_table);
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
    
    private AlienDatabaseVersion get_version() throws DatabaseError {
        return new AlienDatabaseVersion.from_string(meta_table.get_db_version());
    }
    
    public Gee.Collection<AlienDatabasePhoto> get_photos() throws DatabaseError {
        Gee.List<AlienDatabasePhoto> photos = new Gee.ArrayList<AlienDatabasePhoto>();

        foreach (FSpotPhotoRow photo_row in photos_table.get_all()) {
            bool hidden = false;
            bool favorite = false;
            Gee.ArrayList<AlienDatabaseTag> tags = new Gee.ArrayList<AlienDatabaseTag>();
            AlienDatabaseEvent? event = null;
            FSpotRollRow? roll_row = null;
            
            // TODO: We do not convert F-Spot events to Shotwell events because F-Spot's events
            // are essentially tags.  We would need to detect if the tag is an event (use
            // is_tag_event) and then assign the event to the photo ... since a photo can be
            // in multiple F-Spot events, we would need to pick one, and since their tags
            // are heirarchical, we would need to pick a name (probably the leaf)
            try {
                foreach (FSpotTagRow tag_row in tags_table.get_by_photo_id(photo_row.photo_id)) {
                    FSpotDatabaseTag tag = tags_cache.get_tag(tag_row);
                    if (is_tag_hidden(tag))
                        hidden = true;
                    else if (is_tag_favorite(tag))
                        favorite = true;
                    else
                        tags.add(tag);
                }
            } catch(DatabaseError e) {
                // log the error and leave the tag list empty
                message("Failed to retrieve tags for photo ID %ld: %s", (long) photo_row.photo_id.id,
                    e.message);
            }
            
            try {
                roll_row = rolls_table.get_by_id(photo_row.roll_id);
            } catch (DatabaseError e) {
                // log the error and leave the roll row null
                message("Failed to retrieve roll for photo ID %ld: %s", (long) photo_row.photo_id.id,
                    e.message);
            }
            
            try {
                bool photo_versions_added = false;
                foreach (FSpotPhotoVersionRow photo_version_row in photo_versions_table.get_by_photo_id(photo_row.photo_id)) {
                    photos.add(new FSpotDatabasePhoto(
                        photo_row, photo_version_row, roll_row, tags, event, hidden, favorite
                    ));
                    photo_versions_added = true;
                }
                
                // older versions of F-Spot (0.4.3.1 at least, perhaps later) did not maintain photo_versions,
                // this handles that case
                if (!photo_versions_added)
                    photos.add(new FSpotDatabasePhoto(
                        photo_row, null, roll_row, tags, event, hidden, favorite
                    ));
            } catch (DatabaseError e) {
                // if we can't load the different versions, do the best we can
                // and create one photo from the photo row that was found earlier
                message("Failed to retrieve versions for photo ID %ld: %s", (long) photo_row.photo_id.id,
                    e.message);
                photos.add(new FSpotDatabasePhoto(
                    photo_row, null, roll_row, tags, event, hidden, favorite
                ));
            }
        }
        
        return photos;
    }
    
    public bool is_tag_event(FSpotDatabaseTag tag) {
        bool result = (FSpotTagsTable.STOCK_ICON_EVENTS == tag.get_row().stock_icon);
        if (!result) {
            FSpotDatabaseTag? parent = tag.get_fspot_parent();
            if (parent == null)
                result = false;
            else
                result = is_tag_event(parent);
        }
        return result;
    }
    
    public bool is_tag_hidden(FSpotDatabaseTag tag) {
        bool result = (hidden_tag_id == tag.get_row().tag_id.id);
        if (!result) {
            FSpotDatabaseTag? parent = tag.get_fspot_parent();
            if (parent == null)
                result = false;
            else
                result = is_tag_hidden(parent);
        }
        return result;
    }
    
    public bool is_tag_favorite(FSpotDatabaseTag tag) {
        bool result = (FSpotTagsTable.STOCK_ICON_FAV == tag.get_row().stock_icon);
        if (!result) {
            FSpotDatabaseTag? parent = tag.get_fspot_parent();
            if (parent == null)
                result = false;
            else
                result = is_tag_favorite(parent);
        }
        return result;
    }
}

}

