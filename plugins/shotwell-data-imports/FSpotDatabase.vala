/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DataImports.FSpot.Db {

public const int64 NULL_ID = 0;
public const int64 INVALID_ID = -1;

/**
 * Initialization method for the whole module.
 */
public void init() {
    FSpotDatabaseBehavior.create_behavior_map();
}

/**
 * An object that is able to read from the F-Spot
 * database and extract the relevant objects.
 */
public class FSpotDatabase : Object {
    private Sqlite.Database fspot_db;
    private FSpotMetaTable meta_table;
    public FSpotPhotosTable photos_table;
    public FSpotPhotoVersionsTable photo_versions_table;
    public FSpotTagsTable tags_table;
    public FSpotRollsTable rolls_table;
    public int64 hidden_tag_id;
    
    public FSpotDatabase(File db_file) throws DatabaseError, Spit.DataImports.DataImportError {
        string filename = db_file.get_path();
        int res = Sqlite.Database.open_v2(filename, out fspot_db,
            Sqlite.OPEN_READONLY, null);
        if (res != Sqlite.OK)
            throw new DatabaseError.ERROR("Unable to open F-Spot database %s: %d", filename, res);
        meta_table = new FSpotMetaTable(fspot_db);
        hidden_tag_id = meta_table.get_hidden_tag_id();
        
        FSpotDatabaseBehavior db_behavior = new FSpotDatabaseBehavior(get_version());
        
        photos_table = new FSpotPhotosTable(fspot_db, db_behavior);
        photo_versions_table = new FSpotPhotoVersionsTable(fspot_db, db_behavior);
        tags_table = new FSpotTagsTable(fspot_db, db_behavior);
        rolls_table = new FSpotRollsTable(fspot_db, db_behavior);
    }
    
    ~FSpotDatabase() {
    }
    
    private Utils.VersionNumber get_version() throws DatabaseError {
        return new Utils.VersionNumber.from_string(meta_table.get_db_version());
    }
}

}

