/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DataImports.FSpot.Db {

/**
 * The value object for the "rolls" table, representing a single database row.
 */
public class FSpotRollRow : Object {
    public int64 id;
    public time_t time;
}

/**
 * This class represents the F-Spot rolls table.
 */
public class FSpotRollsTable : FSpotDatabaseTable<FSpotRollRow> {
    public static const string TABLE_NAME = "Rolls";
    public static const string TABLE_NAME_PRE_V5 = "Imports";
    
    public FSpotRollsTable(Sqlite.Database db, FSpotDatabaseBehavior db_behavior) {
        base(db);
        set_behavior(db_behavior.get_rolls_behavior());
    }
    
    public FSpotRollRow? get_by_id(int64 roll_id) throws DatabaseError {
        Sqlite.Statement stmt;
        FSpotRollRow? row = null;
        string column_list = get_joined_column_list();
        string sql = "SELECT %s FROM %s WHERE id=?".printf(column_list, table_name);

        int res = fspot_db.prepare_v2(sql, -1, out stmt);
        if (res != Sqlite.OK)
            throw_error("Statement failed: %s".printf(sql), res);
        
        res = stmt.bind_int64(1, roll_id);
        if (res != Sqlite.OK)
            throw_error("Bind failed for roll_id", res);
        
        res = stmt.step();
        if (res == Sqlite.ROW)
            behavior.build_row(stmt, out row);
        else if (res == Sqlite.DONE)
            message("Could not find roll row with ID %d", (int)roll_id);
        
        return row;
    }
}

// Rolls table behavior for v0-4
public class FSpotRollsV0Behavior : FSpotTableBehavior<FSpotRollRow>, Object {
    private static FSpotRollsV0Behavior instance;
    
    private FSpotRollsV0Behavior() {
    }
    
    public static FSpotRollsV0Behavior get_instance() {
        if (instance == null)
            instance = new FSpotRollsV0Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotRollsTable.TABLE_NAME_PRE_V5;
    }

    public string[] list_columns() {
        return { "id", "time" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotRollRow row, int offset = 0) {
        row = new FSpotRollRow();
        row.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
    }
}

// Rolls table behavior for v5+
// Table name changed from "imports" to "rolls"
public class FSpotRollsV5Behavior : FSpotTableBehavior<FSpotRollRow>, Object {
    private static FSpotRollsV5Behavior instance;
    
    private FSpotRollsV5Behavior() {
    }
    
    public static FSpotRollsV5Behavior get_instance() {
        if (instance == null)
            instance = new FSpotRollsV5Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotRollsTable.TABLE_NAME;
    }

    public string[] list_columns() {
        return { "id", "time" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotRollRow row, int offset = 0) {
        row = new FSpotRollRow();
        row.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
    }
}

}

