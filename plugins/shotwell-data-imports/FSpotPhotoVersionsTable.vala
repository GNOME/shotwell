/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DataImports.FSpot.Db {

/**
 * The value object for the "photo_versions" table, representing a single database row.
 */
public class FSpotPhotoVersionRow : Object {
    public int64 photo_id;
    public int64 version_id;
    public string name;
    public File? base_path;
    public string? filename;
    public string md5_sum;
    public bool is_protected;
}

/**
 * This class represents the F-Spot photo_versions table.
 */
public class FSpotPhotoVersionsTable : FSpotDatabaseTable<FSpotPhotoVersionRow> {
    public static const string TABLE_NAME = "Photo_versions";

    public FSpotPhotoVersionsTable(Sqlite.Database db, FSpotDatabaseBehavior db_behavior) {
        base(db);
        set_behavior(db_behavior.get_photo_versions_behavior());
    }
    
    public Gee.ArrayList<FSpotPhotoVersionRow> get_by_photo_id(int64 photo_id) throws DatabaseError {
        Gee.ArrayList<FSpotPhotoVersionRow> rows = new Gee.ArrayList<FSpotPhotoVersionRow?>();
        
        Sqlite.Statement stmt;
        
        string column_list = get_joined_column_list();
        string sql = "SELECT %s FROM %s WHERE photo_id=?".printf(
            column_list, table_name
        );

        int res = fspot_db.prepare_v2(sql, -1, out stmt);
        if (res != Sqlite.OK)
            throw_error("Statement failed: %s".printf(sql), res);
        
        res = stmt.bind_int64(1, photo_id);
        if (res != Sqlite.OK)
            throw_error("Bind failed for photo_id", res);
        
        res = stmt.step();
        while (res == Sqlite.ROW) {
            FSpotPhotoVersionRow row;
            behavior.build_row(stmt, out row);
            rows.add(row);
            res = stmt.step();
        }
        
        return rows;
    }
}

// Photo_versions table behavior for v0-8
// Note: there is a change in the URI format in version 8 but the File.new_for_uri
// constructor should be able to deal with the variation, so the v8 behavior should
// be handled in a way identical to v0-7
public class FSpotPhotoVersionsV0Behavior : FSpotTableBehavior<FSpotPhotoVersionRow>, Object {
    private static FSpotPhotoVersionsV0Behavior instance;
    
    private FSpotPhotoVersionsV0Behavior() {
    }
    
    public static FSpotPhotoVersionsV0Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotoVersionsV0Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotoVersionsTable.TABLE_NAME;
    }    
    
    public string[] list_columns() {
        return { "photo_id", "version_id", "name", "uri" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoVersionRow row, int offset = 0) {
        row = new FSpotPhotoVersionRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.version_id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);

        string? full_path = stmt.column_text(offset + 3);
        if (full_path != null) {
            File uri = File.new_for_uri(full_path);
            row.base_path = uri.get_parent();
            row.filename = uri.get_basename();
        }

        row.md5_sum = "";
        row.is_protected = false;
    }
}

// Photo_versions table behavior for v9-15
// add protected field
public class FSpotPhotoVersionsV9Behavior : FSpotTableBehavior<FSpotPhotoVersionRow>, Object {
    private static FSpotPhotoVersionsV9Behavior instance;
    
    private FSpotPhotoVersionsV9Behavior() {
    }
    
    public static FSpotPhotoVersionsV9Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotoVersionsV9Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotoVersionsTable.TABLE_NAME;
    }    
    
    public string[] list_columns() {
        return { "photo_id", "version_id", "name", "uri",
            "protected" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoVersionRow row, int offset = 0) {
        row = new FSpotPhotoVersionRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.version_id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);

        string? full_path = stmt.column_text(offset + 3);
        if (full_path != null) {
            File uri = File.new_for_uri(full_path);
            row.base_path = uri.get_parent();
            row.filename = uri.get_basename();
        }

        row.md5_sum = "";
        row.is_protected = (stmt.column_int(offset + 4) > 0);
    }
}

// Photo_versions table behavior for v16
// add md5_sum in photo_versions
public class FSpotPhotoVersionsV16Behavior : FSpotTableBehavior<FSpotPhotoVersionRow>, Object {
    private static FSpotPhotoVersionsV16Behavior instance;
    
    private FSpotPhotoVersionsV16Behavior() {
    }
    
    public static FSpotPhotoVersionsV16Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotoVersionsV16Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotoVersionsTable.TABLE_NAME;
    }    
    
    public string[] list_columns() {
        return { "photo_id", "version_id", "name", "uri",
            "md5_sum", "protected" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoVersionRow row, int offset = 0) {
        row = new FSpotPhotoVersionRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.version_id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);

        string? full_path = stmt.column_text(offset + 3);
        if (full_path != null) {
            File uri = File.new_for_uri(full_path);
            row.base_path = uri.get_parent();
            row.filename = uri.get_basename();
        }

        row.md5_sum = stmt.column_text(offset + 4);
        row.is_protected = (stmt.column_int(offset + 5) > 0);
    }
}

// Photo_versions table behavior for v17
// v17 split the URI into base_uri and filename (reverting back to the original
// design introduced in v0, albeit with a URI rather than a file system path)
public class FSpotPhotoVersionsV17Behavior : FSpotTableBehavior<FSpotPhotoVersionRow>, Object {
    private static FSpotPhotoVersionsV17Behavior instance;
    
    private FSpotPhotoVersionsV17Behavior() {
    }
    
    public static FSpotPhotoVersionsV17Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotoVersionsV17Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotoVersionsTable.TABLE_NAME;
    }    
    
    public string[] list_columns() {
        return { "photo_id", "version_id", "name", "base_uri", "filename",
            "md5_sum", "protected" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoVersionRow row, int offset = 0) {
        row = new FSpotPhotoVersionRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.version_id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);
        
        string? base_path = stmt.column_text(offset + 3);
        string? filename = stmt.column_text(offset + 4);
        if (base_path != null && filename != null) {
            row.base_path = File.new_for_uri(base_path);
            row.filename = filename;
        }
        
        row.md5_sum = stmt.column_text(offset + 5);
        row.is_protected = (stmt.column_int(offset + 6) > 0);
    }
}

// Photo_versions table behavior for v18
// md5_sum renamed import_md5
public class FSpotPhotoVersionsV18Behavior : FSpotTableBehavior<FSpotPhotoVersionRow>, Object {
    private static FSpotPhotoVersionsV18Behavior instance;
    
    private FSpotPhotoVersionsV18Behavior() {
    }
    
    public static FSpotPhotoVersionsV18Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotoVersionsV18Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotoVersionsTable.TABLE_NAME;
    }    
    
    public string[] list_columns() {
        return { "photo_id", "version_id", "name", "base_uri", "filename",
            "import_md5", "protected" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoVersionRow row, int offset = 0) {
        row = new FSpotPhotoVersionRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.version_id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);
        
        string? base_path = stmt.column_text(offset + 3);
        string? filename = stmt.column_text(offset + 4);
        if (base_path != null && filename != null) {
            row.base_path = File.new_for_uri(base_path);
            row.filename = filename;
        }
        
        row.md5_sum = stmt.column_text(offset + 5);
        row.is_protected = (stmt.column_int(offset + 6) > 0);
    }
}

}

