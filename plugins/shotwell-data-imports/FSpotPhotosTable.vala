/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DataImports.FSpot.Db {

/**
 * The value object for the "photos" table, representing a single database row.
 */
public class FSpotPhotoRow : Object {
    public int64 photo_id;
    public time_t time;
    public File? base_path;
    public string? filename;
    public string description;
    public int64 roll_id;
    public int64 default_version_id;
    public int rating;
    public string md5_sum;
}

/**
 * This class represents the F-Spot photos table.
 */
public class FSpotPhotosTable : FSpotDatabaseTable<FSpotPhotoRow> {
    public static const string TABLE_NAME = "Photos";
    
    public FSpotPhotosTable(Sqlite.Database db, FSpotDatabaseBehavior db_behavior) {
        base(db);
        set_behavior(db_behavior.get_photos_behavior());
    }
    
    public Gee.ArrayList<FSpotPhotoRow> get_all() throws DatabaseError {
        Gee.ArrayList<FSpotPhotoRow> all = new Gee.ArrayList<FSpotPhotoRow?>();
        
        Sqlite.Statement stmt;
        int res = select_all(out stmt);
        while (res == Sqlite.ROW) {
            FSpotPhotoRow row;
            behavior.build_row(stmt, out row);
            all.add(row);
            res = stmt.step();
        }
        
        return all;
    }
}

// Photos table behavior for v0-4
// The original table format
public class FSpotPhotosV0Behavior : FSpotTableBehavior<FSpotPhotoRow>, Object {
    private static FSpotPhotosV0Behavior instance;
    
    private FSpotPhotosV0Behavior() {
    }
    
    public static FSpotPhotosV0Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotosV0Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotosTable.TABLE_NAME;
    }
    
    public string[] list_columns() {
        return { "id", "time", "directory_path", "name", "description",
            "default_version_id" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoRow row, int offset = 0) {
        row = new FSpotPhotoRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
        
        string? base_path = stmt.column_text(offset + 2);
        string? filename = stmt.column_text(offset + 3);
        if (base_path != null && filename != null) {
            row.base_path = File.new_for_uri(base_path);
            row.filename = filename;
        }
        
        row.description = stmt.column_text(offset + 4);
        row.roll_id = INVALID_ID;
        row.default_version_id = stmt.column_int64(offset + 5);
        row.rating = 0;
        row.md5_sum = "";
    }
}

// Photos table behavior for v5-6
// v5 introduced a roll_id to reference the imported roll (rolls were a new
// table migrated from imports)
public class FSpotPhotosV5Behavior : FSpotTableBehavior<FSpotPhotoRow>, Object {
    private static FSpotPhotosV5Behavior instance;
    
    private FSpotPhotosV5Behavior() {
    }
    
    public static FSpotPhotosV5Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotosV5Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotosTable.TABLE_NAME;
    }
    
    public string[] list_columns() {
        return { "id", "time", "directory_path", "name", "description", "roll_id",
            "default_version_id" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoRow row, int offset = 0) {
        row = new FSpotPhotoRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
        
        string? base_path = stmt.column_text(offset + 2);
        string? filename = stmt.column_text(offset + 3);
        if (base_path != null && filename != null) {
            row.base_path = File.new_for_uri(base_path);
            row.filename = filename;
        }
        
        row.description = stmt.column_text(offset + 4);
        row.roll_id = stmt.column_int64(offset + 5);
        row.default_version_id = stmt.column_int64(offset + 6);
        row.rating = 0;
        row.md5_sum = "";
    }
}

// Photos table behavior for v7-10
// v7 merged directory_path and name into a single URI value with a file://
// prefix; presumaly this is meant to be able to handle remote files using a
// different URI prefix such as remote files
public class FSpotPhotosV7Behavior : FSpotTableBehavior<FSpotPhotoRow>, Object {
    private static FSpotPhotosV7Behavior instance;
    
    private FSpotPhotosV7Behavior() {
    }
    
    public static FSpotPhotosV7Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotosV7Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotosTable.TABLE_NAME;
    }
    
    public string[] list_columns() {
        return { "id", "time", "uri", "description", "roll_id",
            "default_version_id" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoRow row, int offset = 0) {
        row = new FSpotPhotoRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);

        string? full_path = stmt.column_text(offset + 2);
        if (full_path != null) {
            File uri = File.new_for_uri(full_path);
            row.base_path = uri.get_parent();
            row.filename = uri.get_basename();
        }

        row.description = stmt.column_text(offset + 3);
        row.roll_id = stmt.column_int64(offset + 4);
        row.default_version_id = stmt.column_int64(offset + 5);
        row.rating = 0;
        row.md5_sum = "";
    }
}

// Photos table behavior for v11-15
// v11 introduced the concept of rating so add this to the list of fields
public class FSpotPhotosV11Behavior : FSpotTableBehavior<FSpotPhotoRow>, Object {
    private static FSpotPhotosV11Behavior instance;
    
    private FSpotPhotosV11Behavior() {
    }
    
    public static FSpotPhotosV11Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotosV11Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotosTable.TABLE_NAME;
    }
    
    public string[] list_columns() {
        return { "id", "time", "uri", "description", "roll_id",
            "default_version_id", "rating" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoRow row, int offset = 0) {
        row = new FSpotPhotoRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);

        string? full_path = stmt.column_text(offset + 2);
        if (full_path != null) {
            File uri = File.new_for_uri(full_path);
            row.base_path = uri.get_parent();
            row.filename = uri.get_basename();
        }

        row.description = stmt.column_text(offset + 3);
        row.roll_id = stmt.column_int64(offset + 4);
        row.default_version_id = stmt.column_int64(offset + 5);
        row.rating = stmt.column_int(offset + 6);
        row.md5_sum = "";
    }
}

// Photos table behavior for v16
// v16 introduced the MD5 sum so add this to the list of fields
public class FSpotPhotosV16Behavior : FSpotTableBehavior<FSpotPhotoRow>, Object {
    private static FSpotPhotosV16Behavior instance;
    
    private FSpotPhotosV16Behavior() {
    }
    
    public static FSpotPhotosV16Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotosV16Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotosTable.TABLE_NAME;
    }
    
    public string[] list_columns() {
        return { "id", "time", "uri", "description", "roll_id",
            "default_version_id", "rating", "md5_sum" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoRow row, int offset = 0) {
        row = new FSpotPhotoRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);

        string? full_path = stmt.column_text(offset + 2);
        if (full_path != null) {
            File uri = File.new_for_uri(full_path);
            row.base_path = uri.get_parent();
            row.filename = uri.get_basename();
        }

        row.description = stmt.column_text(offset + 3);
        row.roll_id = stmt.column_int64(offset + 4);
        row.default_version_id = stmt.column_int64(offset + 5);
        row.rating = stmt.column_int(offset + 6);
        row.md5_sum = stmt.column_text(offset + 7);
    }
}

// Photos table behavior for v17
// v17 split the URI into base_uri and filename (reverting back to the original
// design introduced in v0, albeit with a URI rather than a file system path)
public class FSpotPhotosV17Behavior : FSpotTableBehavior<FSpotPhotoRow>, Object {
    private static FSpotPhotosV17Behavior instance;
    
    private FSpotPhotosV17Behavior() {
    }
    
    public static FSpotPhotosV17Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotosV17Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotosTable.TABLE_NAME;
    }
    
    public string[] list_columns() {
        return { "id", "time", "base_uri", "filename", "description", "roll_id",
            "default_version_id", "rating", "md5_sum" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoRow row, int offset = 0) {
        row = new FSpotPhotoRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
        
        string? base_path = stmt.column_text(offset + 2);
        string? filename = stmt.column_text(offset + 3);
        if (base_path != null && filename != null) {
            row.base_path = File.new_for_uri(base_path);
            row.filename = filename;
        }
        
        row.description = stmt.column_text(offset + 4);
        row.roll_id = stmt.column_int64(offset + 5);
        row.default_version_id = stmt.column_int64(offset + 6);
        row.rating = stmt.column_int(offset + 7);
        row.md5_sum = stmt.column_text(offset + 8);
    }
}

// v18: no more MD5 hash in the photos table: moved to photo_versions table
public class FSpotPhotosV18Behavior : FSpotTableBehavior<FSpotPhotoRow>, Object {
    private static FSpotPhotosV18Behavior instance;
    
    private FSpotPhotosV18Behavior() {
    }
    
    public static FSpotPhotosV18Behavior get_instance() {
        if (instance == null)
            instance = new FSpotPhotosV18Behavior();
        return instance;
    }
    
    public string get_table_name() {
        return FSpotPhotosTable.TABLE_NAME;
    }
    
    public string[] list_columns() {
        return { "id", "time", "base_uri", "filename", "description", "roll_id",
            "default_version_id", "rating" };
    }
    
    public void build_row(Sqlite.Statement stmt, out FSpotPhotoRow row, int offset = 0) {
        row = new FSpotPhotoRow();
        row.photo_id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
        
        string? base_path = stmt.column_text(offset + 2);
        string? filename = stmt.column_text(offset + 3);
        if (base_path != null && filename != null) {
            row.base_path = File.new_for_uri(base_path);
            row.filename = filename;
        }
        
        row.description = stmt.column_text(offset + 4);
        row.roll_id = stmt.column_int64(offset + 5);
        row.default_version_id = stmt.column_int64(offset + 6);
        row.rating = stmt.column_int(offset + 7);
        row.md5_sum = "";
    }
}

}

