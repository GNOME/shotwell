/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class DatabaseTable {
    /*** 
     * This number should be incremented every time any database schema is altered.
     ***/
    public const int SCHEMA_VERSION = 3;
    
    protected static Sqlite.Database db;
    
    public string table_name = null;

    // Doing this because static construct {} not working ... passing null will make all databases
    // exist in-memory *only*, which is may be useless for certain tables
    public static void init(File? db_file) {
        string filename = (db_file != null) ? db_file.get_path() : ":memory:";

        int res = Sqlite.Database.open_v2(filename, out db, Sqlite.OPEN_READWRITE | Sqlite.OPEN_CREATE, 
            null);
        if (res != Sqlite.OK)
            error("Unable to open/create photo database %s: %d", filename, res);
    }
    
    public static void terminate() {
    }
    
    // XXX: errmsg() is global, and so this will not be accurate in a threaded situation
    protected static void fatal(string op, int res) {
        error("%s: [%d] %s", op, res, db.errmsg());
    }
    
    // XXX: errmsg() is global, and so this will not be accurate in a threaded situation
    protected static void warning(string op, int res) {
        GLib.warning("%s: [%d] %s", op, res, db.errmsg());
    }
    
    protected void set_table_name(string table_name) {
        this.table_name = table_name;
    }
    
    protected bool exists_by_id(int64 id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM %s WHERE id=?".printf(table_name), -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW && res != Sqlite.DONE)
            fatal("exists_by_id [%lld] %s".printf(id, table_name), res);
        
        return (res == Sqlite.ROW);
    }
    
    protected bool select_by_id(int64 id, string columns, out Sqlite.Statement stmt) {
        string sql = "SELECT %s FROM %s WHERE id=?".printf(columns, table_name);

        int res = db.prepare_v2(sql, -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW && res != Sqlite.DONE)
            fatal("select_by_id [%lld] %s %s".printf(id, table_name, columns), res);
        
        return (res == Sqlite.ROW);
    }
    
    // Caller needs to bind value #1 before calling execute_update_by_id()
    private void prepare_update_by_id(int64 id, string column, out Sqlite.Statement stmt) {
        string sql = "UPDATE %s SET %s=? WHERE id=?".printf(table_name, column);
        
        int res = db.prepare_v2(sql, -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(2, id);
        assert(res == Sqlite.OK);
    }
    
    private bool execute_update_by_id(Sqlite.Statement stmt) {
        int res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("execute_update_by_id", res);
            
            return false;
        }
        
        return true;
    }
    
    protected bool update_text_by_id(int64 id, string column, string text) {
        Sqlite.Statement stmt;
        prepare_update_by_id(id, column, out stmt);
        
        int res = stmt.bind_text(1, text);
        assert(res == Sqlite.OK);
        
        return execute_update_by_id(stmt);
    }
    
    protected bool update_int_by_id(int64 id, string column, int value) {
        Sqlite.Statement stmt;
        prepare_update_by_id(id, column, out stmt);
        
        int res = stmt.bind_int(1, value);
        assert(res == Sqlite.OK);
        
        return execute_update_by_id(stmt);
    }
    
    protected bool update_int64_by_id(int64 id, string column, int64 value) {
        Sqlite.Statement stmt;
        prepare_update_by_id(id, column, out stmt);
        
        int res = stmt.bind_int64(1, value);
        assert(res == Sqlite.OK);
        
        return execute_update_by_id(stmt);
    }
    
    public static bool has_column(string table_name, string column_name) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("PRAGMA table_info(%s)".printf(table_name), -1, out stmt);
        assert(res == Sqlite.OK);
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("has_column %s".printf(table_name), res);
                
                break;
            } else {
                string column = stmt.column_text(1);
                if (column != null && column == column_name)
                    return true;
            }
        }
        
        return false;
    }
    
    public static bool add_column(string table_name, string column_name, string column_constraints) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("ALTER TABLE %s ADD COLUMN %s %s".printf(table_name, column_name,
            column_constraints), -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            critical("Unable to add column %s %s %s: (%d) %s", table_name, column_name, column_constraints,
                res, db.errmsg());
            
            return false;
        }
        
        return true;
    }
}

public enum DatabaseVerifyResult {
    OK,
    FUTURE_VERSION,
    UPGRADE_ERROR,
    NO_UPGRADE_AVAILABLE
}

public DatabaseVerifyResult verify_database(out string app_version) {
    VersionTable version_table = VersionTable.get_instance();
    int version = version_table.get_version(out app_version);
    debug("Database version %d create by app version %s", version, app_version);
    
    if (version == -1) {
        // no version set, do it now (tables will be created on demand)
        version_table.set_version(DatabaseTable.SCHEMA_VERSION, Resources.APP_VERSION);
    } else if (version > DatabaseTable.SCHEMA_VERSION) {
        // Back to the future
        return DatabaseVerifyResult.FUTURE_VERSION;
    } else if (version < DatabaseTable.SCHEMA_VERSION) {
        // Past is present
        DatabaseVerifyResult result = upgrade_database(version);
        if (result != DatabaseVerifyResult.OK)
            return result;
    }
    
    PhotoTable photo_table = PhotoTable.get_instance();
    EventTable event_table = EventTable.get_instance();
    Gee.ArrayList<EventID?> event_ids = event_table.get_events();

    // verify photos for all events and check that the end_time is set (see Bug #665 and #670).
    foreach (EventID event_id in event_ids) {
        if (!photo_table.event_has_photos(event_id)) {
            message("Removing event [%lld] %s: No photos associated with event", event_id.id,
                event_table.get_name(event_id));
            event_table.remove(event_id);
        }
    }
    
    return DatabaseVerifyResult.OK;
}

private DatabaseVerifyResult upgrade_database(int version) {
    assert(version < DatabaseTable.SCHEMA_VERSION);
    
    // No upgrade available from version 1.
    if (version == 1)
        return DatabaseVerifyResult.NO_UPGRADE_AVAILABLE;
    
    debug("Upgrading database from schema version %d to %d", version, DatabaseTable.SCHEMA_VERSION);
    
    //
    // Version 2: For all intents and purposes, the baseline schema version.
    // * Removed start_time and end_time from EventsTable
    //
    
    //
    // Version 3:
    // * Added flags column to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "flags")) {
        debug("upgrade_database: adding flags column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "flags", "INTEGER DEFAULT 0"))
            return DatabaseVerifyResult.UPGRADE_ERROR;
    }
    
    version = 3;
    
    VersionTable.get_instance().update_version(version);
    
    debug("Database upgrade to schema version %d successful", version);
    
    return DatabaseVerifyResult.OK;
}

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
    
    public void update_version(int version) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE VersionTable SET schema_version=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int(1, version);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("update_version %d".printf(version), res);
    }
}

public struct PhotoID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public PhotoID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
}

public struct ImportID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public ImportID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
}

public struct PhotoRow {
    public PhotoID photo_id;
    public File file;
    public Dimensions dim;
    public int64 filesize;
    public time_t timestamp;
    public time_t exposure_time;
    public Orientation orientation;
    public Orientation original_orientation;
    public ImportID import_id;
    public EventID event_id;
    public Gee.HashMap<string, KeyValueMap>? transformations;
    public string md5;
    public string thumbnail_md5;
    public string exif_md5;
    public time_t time_created;
    public uint64 flags;
    
    public PhotoRow() {
    }
}

public class PhotoTable : DatabaseTable {
    private static PhotoTable instance = null;
    
    private PhotoTable() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS PhotoTable ("
            + "id INTEGER PRIMARY KEY, "
            + "filename TEXT UNIQUE NOT NULL, "
            + "width INTEGER, "
            + "height INTEGER, "
            + "filesize INTEGER, "
            + "timestamp INTEGER, "
            + "exposure_time INTEGER, "
            + "orientation INTEGER, "
            + "original_orientation INTEGER, "
            + "import_id INTEGER, "
            + "event_id INTEGER, "
            + "transformations TEXT, "
            + "md5 TEXT, "
            + "thumbnail_md5 TEXT, "
            + "exif_md5 TEXT, "
            + "time_created INTEGER, "
            + "flags INTEGER DEFAULT 0 "
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create photo table", res);
        
        // index on event_id
        Sqlite.Statement stmt2;
        int res2 = db.prepare_v2("CREATE INDEX IF NOT EXISTS PhotoEventIDIndex ON PhotoTable (event_id)",
            -1, out stmt2);
        assert(res2 == Sqlite.OK);

        res2 = stmt2.step();
        if (res2 != Sqlite.DONE)
            fatal("create photo table", res2);

        set_table_name("PhotoTable");
    }
    
    public static PhotoTable get_instance() {
        if (instance == null)
            instance = new PhotoTable();
        
        return instance;
    }
    
    public ImportID generate_import_id() {
        // TODO: Use a guid here?  Key here is that last imported photos can be easily identified
        // by finding the largest value in the PhotoTable
        TimeVal timestamp = TimeVal();
        timestamp.get_current_time();
        int64 id = timestamp.tv_sec;
        
        return ImportID(id);
    }
    
    public PhotoID add(File file, Dimensions dim, int64 filesize, long timestamp, time_t exposure_time,
        Orientation orientation, ImportID import_id, string? md5, string? thumbnail_md5, string? exif_md5) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO PhotoTable (filename, width, height, filesize, timestamp, exposure_time, "
            + "orientation, original_orientation, import_id, event_id, md5, thumbnail_md5, exif_md5, "
            + "time_created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, file.get_path());
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(3, dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(4, filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(5, timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(6, exposure_time);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(7, orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(8, orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(9, import_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(10, PhotoID.INVALID);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(11, md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(12, thumbnail_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(13, exif_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(14, now_sec());
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                fatal("add_photo", res);
            
            return PhotoID();
        }

        return PhotoID(db.last_insert_rowid());
    }
    
    public bool update(PhotoID photoID, Dimensions dim, int64 filesize, long timestamp, 
        time_t exposure_time, Orientation orientation) {
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "UPDATE PhotoTable SET width = ?, height = ?, filesize = ?, timestamp = ?, "
            + "exposure_time = ?, orientation = ?, original_orientation = ? WHERE id = ?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        debug("Update [%lld] %dx%d size=%lld mod=%ld exp=%ld or=%d", photoID.id, dim.width, 
            dim.height, filesize, timestamp, exposure_time, (int) orientation);

        res = stmt.bind_int(1, dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(3, filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(4, timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(5, exposure_time);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(6, orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(7, orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(7, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                fatal("update_photo", res);
            
            return false;
        }

        return true;
    }
    
    public PhotoRow? get_row(PhotoID photo_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT filename, width, height, filesize, timestamp, exposure_time, orientation, "
            + "original_orientation, import_id, event_id, transformations, md5, thumbnail_md5, "
            + "exif_md5, time_created, flags FROM PhotoTable WHERE id=?", 
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photo_id.id);
        assert(res == Sqlite.OK);
        
        if (stmt.step() != Sqlite.ROW)
            return null;
            
        PhotoRow row = PhotoRow();
        row.photo_id = photo_id;
        row.file = File.new_for_path(stmt.column_text(0));
        row.dim = Dimensions(stmt.column_int(1), stmt.column_int(2));
        row.filesize = stmt.column_int64(3);
        row.timestamp = (time_t) stmt.column_int64(4);
        row.exposure_time = (time_t) stmt.column_int64(5);
        row.orientation = (Orientation) stmt.column_int(6);
        row.original_orientation = (Orientation) stmt.column_int(7);
        row.import_id.id = stmt.column_int64(8);
        row.event_id.id = stmt.column_int64(9);
        row.transformations = marshall_all_transformations(stmt.column_text(10));
        row.md5 = stmt.column_text(11);
        row.thumbnail_md5 = stmt.column_text(12);
        row.exif_md5 = stmt.column_text(13);
        row.time_created = (time_t) stmt.column_int64(14);
        row.flags = stmt.column_int64(15);
        
        return row;
    }
    
    public Gee.ArrayList<PhotoRow?> get_all() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT id, filename, width, height, filesize, timestamp, exposure_time, orientation, "
            + "original_orientation, import_id, event_id, transformations, md5, thumbnail_md5, "
            + "exif_md5, time_created, flags FROM PhotoTable", 
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        Gee.ArrayList<PhotoRow?> all = new Gee.ArrayList<PhotoRow?>();
        
        while ((res = stmt.step()) == Sqlite.ROW) {
            PhotoRow row = PhotoRow();
            row.photo_id.id = stmt.column_int64(0);
            row.file = File.new_for_path(stmt.column_text(1));
            row.dim = Dimensions(stmt.column_int(2), stmt.column_int(3));
            row.filesize = stmt.column_int64(4);
            row.timestamp = (time_t) stmt.column_int64(5);
            row.exposure_time = (time_t) stmt.column_int64(6);
            row.orientation = (Orientation) stmt.column_int(7);
            row.original_orientation = (Orientation) stmt.column_int(8);
            row.import_id.id = stmt.column_int64(9);
            row.event_id.id = stmt.column_int64(10);
            row.transformations = marshall_all_transformations(stmt.column_text(11));
            row.md5 = stmt.column_text(12);
            row.thumbnail_md5 = stmt.column_text(13);
            row.exif_md5 = stmt.column_text(14);
            row.time_created = (time_t) stmt.column_int64(15);
            row.flags = stmt.column_int64(16);
            
            all.add(row);
        }
        
        return all;
    }
    
    // Create a duplicate of the specified row.  A new byte-for-byte duplicate of PhotoID's file 
    // needs to back this duplicate.
    public PhotoID duplicate(PhotoID photo_id, string new_filename) {
        // get a copy of the original row, duplicating most (but not all) of it
        PhotoRow original = get_row(photo_id);
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO PhotoTable (filename, width, height, filesize, timestamp, "
            + "exposure_time, orientation, original_orientation, import_id, event_id, transformations, "
            + "md5, thumbnail_md5, exif_md5, time_created, flags) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, new_filename);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, original.dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(3, original.dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(4, original.filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(5, original.timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(6, original.exposure_time);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(7, original.orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(8, original.original_orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(9, original.import_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(10, original.event_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(11, unmarshall_all_transformations(original.transformations));
        assert(res == Sqlite.OK);
        res = stmt.bind_text(12, original.md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(13, original.thumbnail_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(14, original.exif_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(15, now_sec());
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(15, (int64) original.flags);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                fatal("duplicate", res);
            
            return PhotoID();
        }
        
        return PhotoID(db.last_insert_rowid());
    }
    
    public bool exists(PhotoID photo_id) {
        return exists_by_id(photo_id.id);
    }

    public File? get_file(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "filename", out stmt))
            return null;
        
        return File.new_for_path(stmt.column_text(0));
    }
    
    public string? get_name(PhotoID photo_id) {
        File file = get_file(photo_id);
        
        return (file != null) ? file.get_basename() : null;
    }
    
    public time_t get_exposure_time(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "exposure_time", out stmt))
            return 0;
        
        return (time_t) stmt.column_int64(0);
    }
    
    public time_t get_timestamp(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "timestamp", out stmt))
            return 0;

        return (time_t) stmt.column_int64(0);
    }
    
    public int64 get_filesize(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "filesize", out stmt))
            return -1;
        
        return stmt.column_int64(0);
    }
    
    public bool remove_by_file(File file) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM PhotoTable WHERE filename=?", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_text(1, file.get_path());
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            warning("remove", res);
            
            return false;
        }
        
        return true;
    }
    
    public bool remove(PhotoID photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM PhotoTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            warning("remove", res);
            
            return false;
        }
        
        return true;
    }
    
    public bool is_photo_stored(File file) {
        return (get_id(file).is_invalid() == false);
    }
    
    public PhotoID get_id(File file) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT ID FROM PhotoTable WHERE filename=?", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_text(1, file.get_path());
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        
        return (res == Sqlite.ROW) ? PhotoID(stmt.column_int64(0)) : PhotoID();
    }

    public Gee.ArrayList<PhotoID?> get_photos() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM PhotoTable", -1, out stmt);
        assert(res == Sqlite.OK);

        Gee.ArrayList<PhotoID?> photo_ids = new Gee.ArrayList<PhotoID?>();
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_photos", res);

                break;
            }
            
            photo_ids.add(PhotoID(stmt.column_int64(0)));
        }
        
        return photo_ids;
    }
    
    public Dimensions get_dimensions(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "width, height", out stmt))
            return Dimensions();
        
        return Dimensions(stmt.column_int(0), stmt.column_int(1));
    }
    
    public Orientation get_original_orientation(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "original_orientation", out stmt))
            return Orientation.TOP_LEFT;

        return (Orientation) stmt.column_int(0);
    }
    
    public Orientation get_orientation(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "orientation", out stmt))
            return Orientation.TOP_LEFT;

        return (Orientation) stmt.column_int(0);
    }
    
    public bool set_orientation(PhotoID photo_id, Orientation orientation) {
        return update_int_by_id(photo_id.id, "orientation", (int) orientation);
    }
    
    public uint64 get_flags(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "flags", out stmt))
            return 0;
        
        return stmt.column_int64(0);
    }
    
    public bool set_flags(PhotoID photo_id, uint64 flags) {
        return update_int64_by_id(photo_id.id, "flags", (int64) flags);
    }

    public EventID get_event(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "event_id", out stmt))
            return EventID();
        
        return EventID(stmt.column_int64(0));
    }
    
    public int get_event_photo_count(EventID event_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM PhotoTable WHERE event_id = ?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, event_id.id);
        assert(res == Sqlite.OK);
        
        int count = 0;
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_event_photo_count", res);
                
                break;
            }
            
            count++;
        }
        
        return count;
    }
    
    public Gee.ArrayList<PhotoID?> get_event_photos(EventID event_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM PhotoTable WHERE event_id = ?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, event_id.id);
        assert(res == Sqlite.OK);
        
        Gee.ArrayList<PhotoID?> photo_ids = new Gee.ArrayList<PhotoID?>();
        for(;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_event_photos", res);

                break;
            }
            
            photo_ids.add(PhotoID(stmt.column_int64(0)));
        }
        
        return photo_ids;
    }
    
    public bool event_has_photos(EventID event_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM PhotoTable WHERE event_id = ? LIMIT 1", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, event_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.DONE) {
            return false;
        } else if (res != Sqlite.ROW) {
            fatal("event_has_photos", res);
            
            return false;
        }
        
        return true;
    }

    public bool drop_event(EventID event_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE PhotoTable SET event_id = ? WHERE event_id = ?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, EventID.INVALID);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, event_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("drop_event", res);
            
            return false;
        }
        
        return true;
    }

    public bool set_event(PhotoID photo_id, EventID event_id) {
        return update_int64_by_id(photo_id.id, "event_id", event_id.id);
    }

    private string? get_raw_transformations(PhotoID photo_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(photo_id.id, "transformations", out stmt))
            return null;

        string trans = stmt.column_text(0);
        if (trans == null || trans.length == 0)
            return null;

        return trans;
    }
    
    private bool set_raw_transformations(PhotoID photo_id, string trans) {
        return update_text_by_id(photo_id.id, "transformations", trans);
    }
    
    public bool set_transformation_state(PhotoID photo_id, Orientation orientation,
        Gee.HashMap<string, KeyValueMap>? transformations) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE PhotoTable SET orientation = ?, transformations = ? WHERE id = ?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int(1, orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(2, unmarshall_all_transformations(transformations));
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(3, photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("set_transformation_state", res);
            
            return false;
        }
        
        return true;
    }
    
    public bool has_transformations(PhotoID photo_id) {
        return get_raw_transformations(photo_id) != null;
    }
    
    public static Gee.HashMap<string, KeyValueMap>? marshall_all_transformations(string? trans) {
        if (trans == null || trans.length == 0)
            return null;
            
        try {
            FixedKeyFile keyfile = new FixedKeyFile();
            if (!keyfile.load_from_data(trans, trans.length, KeyFileFlags.NONE))
                return null;
            
            Gee.HashMap<string, KeyValueMap> map = new Gee.HashMap<string, KeyValueMap>(str_hash,
                str_equal, direct_equal);
            
            string[] objects = keyfile.get_groups();
            foreach (string object in objects) {
                size_t count;
                string[] keys = keyfile.get_keys(object, out count);
                if (keys == null || count == 0)
                    continue;
                
                KeyValueMap key_map = new KeyValueMap(object);
                for (int ctr =0 ; ctr < count; ctr++)
                    key_map.set_string(keys[ctr], keyfile.get_string(object, keys[ctr]));
                
                map.set(object, key_map);
            }
            
            return map;
        } catch (Error err) {
            error("%s", err.message);
            
            return null;
        }
    }
    
    public static string? unmarshall_all_transformations(Gee.HashMap<string, KeyValueMap>? transformations) {
        if (transformations == null || transformations.keys.size == 0)
            return null;
        
        FixedKeyFile keyfile = new FixedKeyFile();
        
        foreach (string object in transformations.keys) {
            KeyValueMap map = transformations.get(object);
            
            foreach (string key in map.get_keys()) {
                string? value = map.get_string(key, null);
                assert(value != null);
                
                keyfile.set_string(object, key, value);
            }
        }
        
        size_t length;
        string unmarshalled = keyfile.to_data(out length);
        assert(unmarshalled != null);
        assert(unmarshalled.length > 0);
        
        return unmarshalled;
    }
    
    public Gee.HashMap<string, KeyValueMap>? get_all_transformations(PhotoID photo_id) {
        string trans = get_raw_transformations(photo_id);
        
        return (trans != null) ? marshall_all_transformations(trans) : null;
    }
    
    public KeyValueMap? get_transformation(PhotoID photo_id, string object) {
        string trans = get_raw_transformations(photo_id);
        if (trans == null)
            return null;
            
        try {
            FixedKeyFile keyfile = new FixedKeyFile();
            if (!keyfile.load_from_data(trans, trans.length, KeyFileFlags.NONE))
                return null;
                
            if (!keyfile.has_group(object))
                return null;
            
            size_t count;
            string[] keys = keyfile.get_keys(object, out count);
            if (keys == null || count == 0)
                return null;

            KeyValueMap map = new KeyValueMap(object);
            for (int ctr = 0; ctr < count; ctr++)
                map.set_string(keys[ctr], keyfile.get_string(object, keys[ctr]));
            
            return map;
        } catch (Error err) {
            error("%s", err.message);
            
            return null;
        }
    }
    
    public bool set_transformation(PhotoID photo_id, KeyValueMap map) {
        string trans = get_raw_transformations(photo_id);
        
        try {
            FixedKeyFile keyfile = new FixedKeyFile();
            if (trans != null) {
                if (!keyfile.load_from_data(trans, trans.length, KeyFileFlags.NONE))
                    return false;
            }
            
            Gee.Set<string> keys = map.get_keys();
            foreach (string key in keys) {
                string value = map.get_string(key, null);
                assert(value != null);
                
                keyfile.set_string(map.get_group(), key, value);
            }
            
            size_t length;
            trans = keyfile.to_data(out length);
            assert(trans != null);
            assert(trans.length > 0);
        } catch (Error err) {
            error("%s", err.message);
            
            return false;
        }
        
        return set_raw_transformations(photo_id, trans);
    }
    
    public bool remove_transformation(PhotoID photo_id, string object) {
        string trans = get_raw_transformations(photo_id);
        if (trans == null)
            return true;
        
        try {
            FixedKeyFile keyfile = new FixedKeyFile();
            if (!keyfile.load_from_data(trans, trans.length, KeyFileFlags.NONE))
                return false;
            
            if (!keyfile.has_group(object))
                return true;
            
            keyfile.remove_group(object);
            
            size_t length;
            trans = keyfile.to_data(out length);
            assert(trans != null);
        } catch (Error err) {
            error("%s", err.message);
            
            return false;
        }
        
        return set_raw_transformations(photo_id, trans);
    }
    
    public bool remove_all_transformations(PhotoID photo_id) {
        if (get_raw_transformations(photo_id) == null)
            return false;
        
        return update_text_by_id(photo_id.id, "transformations", "");
    }

    public int get_transformation_count(PhotoID photo_id) {
        string trans = get_raw_transformations(photo_id);
        if (trans == null)
            return 0;

        FixedKeyFile keyfile = new FixedKeyFile();
        try {
            if (!keyfile.load_from_data(trans, trans.length, KeyFileFlags.NONE))
                return 0;
        } catch (KeyFileError err) {
            GLib.warning("Unable to load keyfile from data: %s", err.message);
            
            return 0;
        }
        
        string[] groups = keyfile.get_groups();

        return groups.length;
    }
    
    private bool has_hash(string column, string md5) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM PhotoTable WHERE %s=?".printf(column), -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, md5);
        assert(res == Sqlite.OK);
        
        return stmt.step() == Sqlite.ROW;
    }
    
    public bool has_full_md5(string md5) {
        return has_hash("md5", md5);
    }
    
    public bool has_thumbnail_md5(string thumbnail_md5) {
        return has_hash("thumbnail_md5", thumbnail_md5);
    }
    
    public bool has_exif_md5(string exif_md5) {
        return has_hash("exif_md5", exif_md5);
    }
}

public struct ThumbnailCacheRow {
    PhotoID photo_id;
    Dimensions dim;
    int filesize;
}

public class ThumbnailCacheTable : DatabaseTable {
    public ThumbnailCacheTable(int scale) {
        assert(scale > 0);

        set_table_name("Thumb%dTable".printf(scale));
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + table_name
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "photo_id INTEGER UNIQUE, "
            + "width INTEGER, "
            + "height INTEGER, "
            + "filesize INTEGER"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create %s".printf(table_name), res);
    }
    
    public bool remove(PhotoID photo_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM %s WHERE photo_id=?".printf(table_name), -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            warning("%s remove".printf(table_name), res);

            return false;
        }
        
        return true;
    }
    
    public bool exists(PhotoID photo_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM %s WHERE photo_id=?".printf(table_name), -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE)
                fatal("%s exists".printf(table_name), res);
            
            return false;
        }
        
        return true;
    }
    
    public void add(PhotoID photo_id, int filesize, Dimensions dim) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO %s (photo_id, filesize, width, height) VALUES (?, ?, ?, ?)".printf(table_name),
            -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, photo_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, filesize);
        assert(res == Sqlite.OK);
        stmt.bind_int(3, dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(4, dim.height);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("%s add".printf(table_name), res);
    }
    
    public ThumbnailCacheRow? get_row(PhotoID photo_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT width, height, filesize FROM %s WHERE photo_id=?".printf(table_name),
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE)
                fatal("%s get_row".printf(table_name), res);
            
            return null;
        }
        
        ThumbnailCacheRow row = ThumbnailCacheRow();
        row.photo_id = photo_id;
        row.dim = Dimensions(stmt.column_int(0), stmt.column_int(1));
        row.filesize = stmt.column_int(2);
        
        return row;
    }
    
    public void duplicate(PhotoID src_id, PhotoID dest_id) {
        // copy
        ThumbnailCacheRow? row = get_row(src_id);
        if (row == null)
            error("Unable to duplicate thumbnail cache row %lld", src_id.id);
        
        // paste
        add(dest_id, row.filesize, row.dim);
    }
    
    public void replace(PhotoID photo_id, int filesize, Dimensions dim) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "UPDATE %s SET filesize=?, width=?, height=? WHERE photo_id=?".printf(table_name),
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int(1, filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(3, dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(4, photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("%s replace".printf(table_name), res);
    }
    
    public Dimensions get_dimensions(PhotoID photo_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT width, height FROM %s WHERE photo_id=?".printf(table_name), 
            -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if(res != Sqlite.DONE)
                fatal("%s get_dimensions".printf(table_name), res);

            return Dimensions();
        }
        
        return Dimensions(stmt.column_int(0), stmt.column_int(1));
    }
    
    public int get_filesize(PhotoID photo_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT filesize FROM %s WHERE photo_id=?".printf(table_name),
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE)
                fatal("%s get_filesize".printf(table_name), res);
            
            return -1;
        }
        
        return stmt.column_int(0);
    }
}

public struct EventID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public EventID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
}

public struct EventRow {
    public EventID event_id;
    public string? name;
    public PhotoID primary_photo_id;
    public time_t time_created;
}

public class EventTable : DatabaseTable {
    private static EventTable instance = null;
    
    private EventTable() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS EventTable ("
            + "id INTEGER PRIMARY KEY, "
            + "name TEXT, "
            + "primary_photo_id INTEGER, "
            + "time_created INTEGER"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create photo table", res);
        
        set_table_name("EventTable");
    }
    
    public static EventTable get_instance() {
        if (instance == null)
            instance = new EventTable();
        
        return instance;
    }
    
    public EventID create(PhotoID primary_photo_id) {
        assert(primary_photo_id.is_valid());
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO EventTable (primary_photo_id, time_created) VALUES (?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, primary_photo_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, now_sec());
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("create_event", res);
            
            return EventID();
        }

        return EventID(db.last_insert_rowid());
    }
    
    // NOTE: The event_id in EventRow is ignored here.  No checking is done to prevent
    // against creating duplicate events or for the validity of other fields in the row (i.e.
    // the primary photo ID).
    public EventID create_from_row(EventRow row) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO EventTable (name, primary_photo_id, time_created) VALUES (?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, row.name);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, row.primary_photo_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(3, row.time_created);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("Event create_from_row", res);
            
            return EventID();
        }
        
        return EventID(db.last_insert_rowid());
    }
    
    public EventRow? get_row(EventID event_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT name, primary_photo_id, time_created FROM EventTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, event_id.id);
        assert(res == Sqlite.OK);
        
        if (stmt.step() != Sqlite.ROW)
            return null;
        
        EventRow row = EventRow();
        row.event_id = event_id;
        row.name = stmt.column_text(0);
        if (row.name != null && row.name.length == 0)
            row.name = null;
        row.primary_photo_id.id = stmt.column_int64(1);
        row.time_created = (time_t) stmt.column_int64(2);
        
        return row;
    }
    
    public bool remove(EventID event_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM EventTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, event_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            warning("event remove", res);
            
            return false;
        }
        
        return true;
    }
    
    public Gee.ArrayList<EventID?> get_events() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM EventTable", -1, out stmt);
        assert(res == Sqlite.OK);

        Gee.ArrayList<EventID?> event_ids = new Gee.ArrayList<EventID?>();
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_events", res);

                break;
            }
            
            event_ids.add(EventID(stmt.column_int64(0)));
        }
        
        return event_ids;
    }
    
    public bool rename(EventID event_id, string? name) {
        return update_text_by_id(event_id.id, "name", name != null ? name : "");
    }
    
    public string? get_name(EventID event_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(event_id.id, "name", out stmt))
            return null;

        string name = stmt.column_text(0);

        return (name != null && name.length > 0) ? name : null;
    }
    
    public PhotoID get_primary_photo(EventID event_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(event_id.id, "primary_photo_id", out stmt))
            return PhotoID();
        
        return PhotoID(stmt.column_int64(0));
    }
    
    public bool set_primary_photo(EventID event_id, PhotoID photo_id) {
        return update_int64_by_id(event_id.id, "primary_photo_id", photo_id.id);
    }
    
    public time_t get_time_created(EventID event_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(event_id.id, "time_created", out stmt))
            return 0;
        
        return (time_t) stmt.column_int64(0);
    }
}

