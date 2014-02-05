/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DataImports.FSpot.Db {

/**
 * The value object for the "meta" table, representing a single database row.
 */
public class FSpotMetaRow : Object {
    // ignore the ID
    public string name;
    public string data;
}

/**
 * This class represents the F-Spot meta table, which stores some essential
 * meta-data for the whole database. It is implemented as a simple dictionary
 * where each row in the table is a key/value pair.
 *
 * The meta table implementation is the only one that throws a database error
 * if something goes wrong because:
 *  * it is essential to read the content of that table in order to identify
 *    the version of the database and select the correct behavior,
 *  * this table is read at the very beginning of the process so any failure
 *    will occur immediately,
 *  * failing to read this table means that there is no point in reading the
 *    attempting to read the rest of the database so we might as well abort.
 */
public class FSpotMetaTable : FSpotDatabaseTable<FSpotMetaRow> {
    
    public FSpotMetaTable(Sqlite.Database db) {
        base(db);
        set_behavior(FSpotMetaBehavior.get_instance());
    }
    
    public string? get_data(string name) throws DatabaseError {
        string[] columns = behavior.list_columns();
        string column_list = string.joinv(", ", columns);
        string sql = "SELECT %s FROM %s WHERE name=?".printf(column_list, table_name);
        Sqlite.Statement stmt;
        int res = fspot_db.prepare_v2(sql, -1, out stmt);
        if (res != Sqlite.OK)
            throw_error("Statement failed: %s".printf(sql), res);
        
        res = stmt.bind_text(1, name);
        if (res != Sqlite.OK)
            throw_error("Bind failed for name %s".printf(name), res);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE)
                throw_error("FSpotMetaTable.get_data", res);
            
            return null;
        }
        
        FSpotMetaRow row;
        behavior.build_row(stmt, out row);
        return row.data;
    }
    
    public string? get_app_version() throws DatabaseError {
        return get_data("F-Spot Version");
    }
    
    public string? get_db_version() throws DatabaseError {
        return get_data("F-Spot Database Version");
    }
    
    public int64 get_hidden_tag_id() throws DatabaseError {
        string id_str = get_data("Hidden Tag Id");
        if(id_str != null) {
            return int64.parse(id_str);
        } else {
            return -1;
        }
    }
}

public class FSpotMetaBehavior : FSpotTableBehavior<FSpotMetaRow>, Object {
    public static const string TABLE_NAME = "Meta";
    
    private static FSpotMetaBehavior instance;
    
    private FSpotMetaBehavior() {
    }
    
    public static FSpotMetaBehavior get_instance() {
        if (instance == null)
            instance = new FSpotMetaBehavior();
        return instance;
    }
    
    public string get_table_name() {
        return TABLE_NAME;
    }
    
    public string[] list_columns() {
        return { "name", "data" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotMetaRow row, int offset = 0) {
        row = new FSpotMetaRow();
        row.name = stmt.column_text(offset + 0);
        row.data = stmt.column_text(offset + 1);
    }
}

}

