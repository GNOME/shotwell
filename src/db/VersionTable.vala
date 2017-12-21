/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class VersionTable : DatabaseTable {
    private static VersionTable instance = null;
    
    private VersionTable() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS VersionTable ("
            + "id INTEGER PRIMARY KEY, "
            + "schema_version INTEGER, "
            + "app_version TEXT, "
            + "user_data TEXT NULL"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create version table", res);

        set_table_name("VersionTable");
    }
    
    public static VersionTable get_instance() {
        if (instance == null)
            instance = new VersionTable();
        
        return instance;
    }
    
    public int get_version(out string app_version) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT schema_version, app_version FROM VersionTable ORDER BY schema_version DESC LIMIT 1", 
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE)
                fatal("get_version", res);
            
            app_version = null;
            
            return -1;
        }
        
        app_version = stmt.column_text(1);
        
        return stmt.column_int(0);
    }
    
    public void set_version(int version, string app_version, string? user_data = null) {
        Sqlite.Statement stmt;

        string bitbucket;
        if (get_version(out bitbucket) != -1) {
            // overwrite existing row
            int res = db.prepare_v2("UPDATE VersionTable SET schema_version=?, app_version=?, user_data=?", 
                -1, out stmt);
            assert(res == Sqlite.OK);
        } else {
            // insert new row
            int res = db.prepare_v2("INSERT INTO VersionTable (schema_version, app_version, user_data) VALUES (?,?, ?)",
                -1, out stmt);
            assert(res == Sqlite.OK);
        }
            
        int res = stmt.bind_int(1, version);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(2, app_version);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(3, user_data);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("set_version %d %s %s".printf(version, app_version, user_data), res);
    }
    
    public void update_version(int version, string app_version) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE VersionTable SET schema_version=?, app_version=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int(1, version);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(2, app_version);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("update_version %d".printf(version), res);
    }
}

