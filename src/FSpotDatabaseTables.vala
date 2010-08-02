/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

/**
 * This class represents a generic F-Spot table.
 */
public abstract class FSpotDatabaseTable<T> : DatabaseTable {
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

/**
 * This class defines a generic table behavior. In practice, it implements
 * the concept of a DAO (Data Access Object) in ORM terms and is responsible
 * for transforming the data extracted from a relational statement into a
 * lightweight value object.
 *
 * The type T defined in the generic is the value object type a behavior
 * implementation is designed to handle. Value object types are designed to
 * contain the data for a single database row.
 */
public interface FSpotTableBehavior<T> : Object {
    public abstract string get_table_name();
    
    public abstract string[] list_columns();
    
    public abstract void build_row(Sqlite.Statement stmt, out T row, int offset = 0);
}

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
            return id_str.to_int64();
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

//
// Photos table
//

public struct FSpotPhotoID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public FSpotPhotoID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
    
    public static uint hash(void *a) {
        return int64_hash(&((FSpotPhotoID *) a)->id);
    }
    
    public static bool equal(void *a, void *b) {
        return ((FSpotPhotoID *) a)->id == ((FSpotPhotoID *) b)->id;
    }
}

public struct FSpotRollID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public FSpotRollID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
    
    public static uint hash(void *a) {
        return int64_hash(&((FSpotRollID *) a)->id);
    }
    
    public static bool equal(void *a, void *b) {
        return ((FSpotRollID *) a)->id == ((FSpotRollID *) b)->id;
    }
}

/**
 * The value object for the "photos" table, representing a single database row.
 */
public class FSpotPhotoRow : Object {
    public FSpotPhotoID photo_id;
    public time_t time;
    public File base_path;
    public string filename;
    public string description;
    public FSpotRollID roll_id;
    public FSpotVersionID default_version_id;
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
        row.base_path = File.new_for_uri(stmt.column_text(offset + 2));
        row.filename = stmt.column_text(offset + 3);
        row.description = stmt.column_text(offset + 4);
        row.roll_id.id = FSpotRollID.INVALID;
        row.default_version_id.id = stmt.column_int64(offset + 5);
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
        row.base_path = File.new_for_uri(stmt.column_text(offset + 2));
        row.filename = stmt.column_text(offset + 3);
        row.description = stmt.column_text(offset + 4);
        row.roll_id.id = stmt.column_int64(offset + 5);
        row.default_version_id.id = stmt.column_int64(offset + 6);
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);

        File uri = File.new_for_uri(stmt.column_text(offset + 2));
        row.base_path = uri.get_parent();
        row.filename = uri.get_basename();

        row.description = stmt.column_text(offset + 3);
        row.roll_id.id = stmt.column_int64(offset + 4);
        row.default_version_id.id = stmt.column_int64(offset + 5);
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);

        File uri = File.new_for_uri(stmt.column_text(offset + 2));
        row.base_path = uri.get_parent();
        row.filename = uri.get_basename();

        row.description = stmt.column_text(offset + 3);
        row.roll_id.id = stmt.column_int64(offset + 4);
        row.default_version_id.id = stmt.column_int64(offset + 5);
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);

        File uri = File.new_for_uri(stmt.column_text(offset + 2));
        row.base_path = uri.get_parent();
        row.filename = uri.get_basename();

        row.description = stmt.column_text(offset + 3);
        row.roll_id.id = stmt.column_int64(offset + 4);
        row.default_version_id.id = stmt.column_int64(offset + 5);
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
        row.base_path = File.new_for_uri(stmt.column_text(offset + 2));
        row.filename = stmt.column_text(offset + 3);
        row.description = stmt.column_text(offset + 4);
        row.roll_id.id = stmt.column_int64(offset + 5);
        row.default_version_id.id = stmt.column_int64(offset + 6);
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
        row.base_path = File.new_for_uri(stmt.column_text(offset + 2));
        row.filename = stmt.column_text(offset + 3);
        row.description = stmt.column_text(offset + 4);
        row.roll_id.id = stmt.column_int64(offset + 5);
        row.default_version_id.id = stmt.column_int64(offset + 6);
        row.rating = stmt.column_int(offset + 7);
        row.md5_sum = "";
    }
}

//
// Photo_versions table
//

public struct FSpotVersionID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public FSpotVersionID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
    
    public static uint hash(void *a) {
        return int64_hash(&((FSpotVersionID *) a)->id);
    }
    
    public static bool equal(void *a, void *b) {
        return ((FSpotVersionID *) a)->id == ((FSpotVersionID *) b)->id;
    }
}

/**
 * The value object for the "photo_versions" table, representing a single database row.
 */
public class FSpotPhotoVersionRow : Object {
    public FSpotPhotoID photo_id;
    public FSpotVersionID version_id;
    public string name;
    public File base_path;
    public string filename;
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
    
    public Gee.ArrayList<FSpotPhotoVersionRow> get_by_photo_id(FSpotPhotoID photo_id) throws DatabaseError {
        Gee.ArrayList<FSpotPhotoVersionRow> rows = new Gee.ArrayList<FSpotPhotoVersionRow?>();
        
        Sqlite.Statement stmt;
        
        string column_list = get_joined_column_list();
        string sql = "SELECT %s FROM %s WHERE photo_id=?".printf(
            column_list, table_name
        );

        int res = fspot_db.prepare_v2(sql, -1, out stmt);
        if (res != Sqlite.OK)
            throw_error("Statement failed: %s".printf(sql), res);
        
        res = stmt.bind_int64(1, photo_id.id);
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
// Note: there is a change in the URI format in version 8 but the FSpotURI
// class should be able to deal with the variation, so the v8 behavior should
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.version_id.id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);

        File uri = File.new_for_uri(stmt.column_text(offset + 3));
        row.base_path = uri.get_parent();
        row.filename = uri.get_basename();

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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.version_id.id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);

        File uri = File.new_for_uri(stmt.column_text(offset + 3));
        row.base_path = uri.get_parent();
        row.filename = uri.get_basename();

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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.version_id.id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);

        File uri = File.new_for_uri(stmt.column_text(offset + 3));
        row.base_path = uri.get_parent();
        row.filename = uri.get_basename();

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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.version_id.id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);
        row.base_path = File.new_for_uri(stmt.column_text(offset + 3));
        row.filename = GLib.Uri.unescape_string(stmt.column_text(offset + 4));
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.version_id.id = stmt.column_int64(offset + 1);
        row.name = stmt.column_text(offset + 2);
        row.base_path = File.new_for_uri(stmt.column_text(offset + 3));
        row.filename = GLib.Uri.unescape_string(stmt.column_text(offset + 4));
        row.md5_sum = stmt.column_text(offset + 5);
        row.is_protected = (stmt.column_int(offset + 6) > 0);
    }
}

//
// Tags table
//

public struct FSpotTagID {
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
        row.tag_id.id = stmt.column_int64(offset + 0);
        row.name = stmt.column_text(offset + 1);
        row.category_id.id = stmt.column_int64(offset + 2);
        row.is_category = (stmt.column_int(offset + 3) > 0);
        row.sort_priority = stmt.column_int(offset + 4);
        string icon_str = stmt.column_text(offset + 5);
        if (icon_str != null && icon_str.has_prefix(FSpotTagsTable.PREFIX_STOCK_ICON))
            row.stock_icon = icon_str;
        else
            row.stock_icon = "";
    }
}

//
// photo_tags table
//

/**
 * The value object for the "photo_tags" table, representing a single database row.
 */
public class FSpotPhotoTagRow : Object {
    public FSpotPhotoID photo_id;
    public FSpotTagID tag_id;
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
        row.photo_id.id = stmt.column_int64(offset + 0);
        row.tag_id.id = stmt.column_int64(offset + 1);
    }
}

//
// rolls table
//

/**
 * The value object for the "rolls" table, representing a single database row.
 */
public class FSpotRollRow : Object {
    public FSpotRollID id;
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
    
    public FSpotRollRow? get_by_id(FSpotRollID roll_id) throws DatabaseError {
        Sqlite.Statement stmt;
        FSpotRollRow? row = null;
        string column_list = get_joined_column_list();
        string sql = "SELECT %s FROM %s WHERE id=?".printf(column_list, table_name);

        int res = fspot_db.prepare_v2(sql, -1, out stmt);
        if (res != Sqlite.OK)
            throw_error("Statement failed: %s".printf(sql), res);
        
        res = stmt.bind_int64(1, roll_id.id);
        if (res != Sqlite.OK)
            throw_error("Bind failed for roll_id", res);
        
        res = stmt.step();
        if (res == Sqlite.ROW)
            behavior.build_row(stmt, out row);
        else if (res == Sqlite.DONE)
            message("Could not find roll row with ID %d", (int)roll_id.id);
        
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
        row.id.id = stmt.column_int64(offset + 0);
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
        row.id.id = stmt.column_int64(offset + 0);
        row.time = (time_t) stmt.column_int64(offset + 1);
    }
}

