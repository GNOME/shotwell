/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace DataImports.FSpot.Db {

/**
 * This class represents a generic F-Spot table.
 */
public abstract class FSpotDatabaseTable<T> : ImportableDatabaseTable {
    protected unowned Sqlite.Database fspot_db;
    protected FSpotTableBehavior<T> behavior;
    
    public FSpotDatabaseTable(Sqlite.Database db) {
        this.fspot_db = db;
    }
    
    public void set_behavior(FSpotTableBehavior<T> behavior) {
        this.behavior = behavior;
        set_table_name(behavior.get_table_name());
    }
    
    public FSpotTableBehavior<T> get_behavior() {
        return behavior;
    }
    
    protected string get_joined_column_list(bool with_table = false) {
        string[] columns = behavior.list_columns();
        if (with_table)
            for (int i = 0; i < columns.length; i++)
                columns[i] = "%s.%s".printf(table_name, columns[i]);
        return string.joinv(", ", columns);
    }
    
    protected int select_all(out Sqlite.Statement stmt) throws DatabaseError {
        string column_list = get_joined_column_list();
        string sql = "SELECT %s FROM %s".printf(column_list, table_name);

        int res = fspot_db.prepare_v2(sql, -1, out stmt);
        if (res != Sqlite.OK)
            throw_error("Statement failed: %s".printf(sql), res);
        
        res = stmt.step();
        if (res != Sqlite.ROW && res != Sqlite.DONE)
            throw_error("select_all %s %s".printf(table_name, column_list), res);
        
        return res;
    }
}

}

