/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb.FSpot {

// This needs to be a class so that it can be used as a key for a Gee.HashMap
public class FSpotTagID {
    public const int64 INVALID = -1;
    public const int64 NULL_ID = 0;

    public int64 id;
    
    public FSpotTagID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
    
    public bool is_null() {
        return (id == NULL_ID);
    }
    
    public static uint hash(void *a) {
        return int64_hash(&((FSpotTagID *) a)->id);
    }
    
    public static bool equal(void *a, void *b) {
        return ((FSpotTagID *) a)->id == ((FSpotTagID *) b)->id;
    }
}

/**
 * The value object for the "tags" table, representing a single database row.
 */
public class FSpotTagRow : Object {
    public FSpotTagID tag_id;
    public string name;
    public FSpotTagID category_id;
    public bool is_category;
    public int sort_priority;
    public string stock_icon; // only store stock icons
}

/**
 * This class represents the F-Spot tags table.
 */
public class FSpotTagsTable : FSpotDatabaseTable<FSpotTagRow> {
    public static const string TABLE_NAME = "Tags";
    
    public static const string PREFIX_STOCK_ICON = "stock_icon:";
    public static const string STOCK_ICON_FAV    = "stock_icon:emblem-favorite";
    public static const string STOCK_ICON_PEOPLE = "stock_icon:emblem-people";
    public static const string STOCK_ICON_PLACES = "stock_icon:emblem-places";
    public static const string STOCK_ICON_EVENTS = "stock_icon:emblem-event";
    
    private FSpotTableBehavior<FSpotPhotoTagRow> photo_tags_behavior;
    
    public FSpotTagsTable(Sqlite.Database db, FSpotDatabaseBehavior db_behavior) {
        base(db);
        set_behavior(db_behavior.get_tags_behavior());
        photo_tags_behavior = db_behavior.get_photo_tags_behavior();
    }
    
    public FSpotTagRow? get_by_id(FSpotTagID tag_id) throws DatabaseError {
        Sqlite.Statement stmt;
        FSpotTagRow? row = null;
        string column_list = get_joined_column_list();
        string sql = "SELECT %s FROM %s WHERE id=?".printf(column_list, table_name);

        int res = fspot_db.prepare_v2(sql, -1, out stmt);
        if (res != Sqlite.OK)
            throw_error("Statement failed: %s".printf(sql), res);
        
        res = stmt.bind_int64(1, tag_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.ROW)
            behavior.build_row(stmt, out row);
        else if (res == Sqlite.DONE)
            message("Could not find tag row with ID %d", (int)tag_id.id);
        
        return row;
    }
    
    public Gee.ArrayList<FSpotTagRow> get_by_photo_id(FSpotPhotoID photo_id) throws DatabaseError {
        Gee.ArrayList<FSpotTagRow> rows = new Gee.ArrayList<FSpotTagRow?>();
        
        Sqlite.Statement stmt;
        
        string column_list = get_joined_column_list(true);
        string sql = "SELECT %1$s FROM %2$s, %3$s WHERE %3$s.photo_id=? AND %3$s.tag_id = %2$s.id".printf(
            column_list, table_name, photo_tags_behavior.get_table_name()
        );

        int res = fspot_db.prepare_v2(sql, -1, out stmt);
        if (res != Sqlite.OK)
            throw_error("Statement failed: %s".printf(sql), res);
        
        res = stmt.bind_int64(1, photo_id.id);
        if (res != Sqlite.OK)
            throw_error("Bind failed for photo_id", res);
        
        res = stmt.step();
        while (res == Sqlite.ROW) {
            FSpotTagRow row;
            behavior.build_row(stmt, out row);
            rows.add(row);
            res = stmt.step();
        }
        
        return rows;
    }
}

public class FSpotTagsV0Behavior : FSpotTableBehavior<FSpotTagRow>, Object {
    private static FSpotTagsV0Behavior instance;
    
    private FSpotTagsV0Behavior() {
    }
    
    public static FSpotTagsV0Behavior get_instance() {
        if (instance == null)
            instance = new FSpotTagsV0Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotTagsTable.TABLE_NAME;
    }

    public string[] list_columns() {
        return { "id", "name", "category_id", "is_category", "sort_priority", "icon" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotTagRow row, int offset = 0) {
        row = new FSpotTagRow();
        row.tag_id = new FSpotTagID(stmt.column_int64(offset + 0));
        row.name = stmt.column_text(offset + 1);
        row.category_id = new FSpotTagID(stmt.column_int64(offset + 2));
        row.is_category = (stmt.column_int(offset + 3) > 0);
        row.sort_priority = stmt.column_int(offset + 4);
        string icon_str = stmt.column_text(offset + 5);
        if (icon_str != null && icon_str.has_prefix(FSpotTagsTable.PREFIX_STOCK_ICON))
            row.stock_icon = icon_str;
        else
            row.stock_icon = "";
    }
}

}

