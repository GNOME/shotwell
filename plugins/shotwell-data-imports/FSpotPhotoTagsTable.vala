/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DataImports.FSpot.Db {

/**
 * The value object for the "photo_tags" table, representing a single database row.
 */
public class FSpotPhotoTagRow : Object {
    public int64 photo_id;
    public int64 tag_id;
}

/**
 * This class represents the F-Spot photo_tags table.
 */
public class FSpotPhotoTagsTable : FSpotDatabaseTable<FSpotPhotoTagRow> {
    public static const string TABLE_NAME = "Photo_Tags";
    
    public FSpotPhotoTagsTable(Sqlite.Database db, FSpotDatabaseBehavior db_behavior) {
        base(db);
        set_behavior(db_behavior.get_photo_tags_behavior());
    }
}

public class FSpotPhotoTagsV0Behavior : FSpotTableBehavior<FSpotPhotoTagRow>, Object {
    private static FSpotPhotoTagsV0Behavior instance;
    
    private FSpotPhotoTagsV0Behavior() {
    }
    
    public static FSpotPhotoTagsV0Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotoTagsV0Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotoTagsTable.TABLE_NAME;
    }

    public string[] list_columns() {
        return { "photo_id", "tag_id" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoTagRow row, int offset = 0) {
        row = new FSpotPhotoTagRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.tag_id = stmt.column_int64(offset + 1);
    }
}

}

