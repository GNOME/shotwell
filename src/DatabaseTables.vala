/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public errordomain DatabaseError {
    ERROR,
    BACKING,
    MEMORY,
    ABORT,
    LIMITS,
    TYPESPEC
}

public class DatabaseTable {
    /*** 
     * This number should be incremented every time any database schema is altered.
     * 
     * NOTE: Adding or removing tables or removing columns do not need a new schema version, because
     * tables are created on demand and tables and columns are easily ignored when already present.
     * However, the change should be noted in upgrade_database() as a comment.
     ***/
    public const int SCHEMA_VERSION = 8;
    
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
        
        // disable synchronized commits for performance reasons ... this is not vital, hence we
        // don't error out if this fails
        res = db.exec("PRAGMA synchronous=OFF");
        if (res != Sqlite.OK)
            warning("Unable to disable synchronous mode", res);
    }
    
    public static void terminate() {
        // freeing the database closes it
        db = null;
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
    
    // This method will throw an error on an SQLite return code unless it's OK, DONE, or ROW, which
    // are considered normal results.
    protected void throw_error(string method, int res) throws DatabaseError {
        string msg = "(%s) [%d] - %s".printf(method, res, db.errmsg());
        
        switch (res) {
            case Sqlite.OK:
            case Sqlite.DONE:
            case Sqlite.ROW:
                return;
            
            case Sqlite.PERM:
            case Sqlite.BUSY:
            case Sqlite.READONLY:
            case Sqlite.IOERR:
            case Sqlite.CORRUPT:
            case Sqlite.CANTOPEN:
            case Sqlite.NOLFS:
            case Sqlite.AUTH:
            case Sqlite.FORMAT:
            case Sqlite.NOTADB:
                throw new DatabaseError.BACKING(msg);
            
            case Sqlite.NOMEM:
                throw new DatabaseError.MEMORY(msg);
            
            case Sqlite.ABORT:
            case Sqlite.LOCKED:
            case Sqlite.INTERRUPT:
                throw new DatabaseError.ABORT(msg);
            
            case Sqlite.FULL:
            case Sqlite.EMPTY:
            case Sqlite.TOOBIG:
            case Sqlite.CONSTRAINT:
            case Sqlite.RANGE:
                throw new DatabaseError.LIMITS(msg);
            
            case Sqlite.SCHEMA:
            case Sqlite.MISMATCH:
                throw new DatabaseError.TYPESPEC(msg);
            
            case Sqlite.ERROR:
            case Sqlite.INTERNAL:
            case Sqlite.MISUSE:
            default:
                throw new DatabaseError.ERROR(msg);
        }
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
    
    protected void update_text_by_id_2(int64 id, string column, string text) throws DatabaseError {
        Sqlite.Statement stmt;
        prepare_update_by_id(id, column, out stmt);
        
        int res = stmt.bind_text(1, text);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("DatabaseTable.update_text_by_id_2 %s.%s".printf(table_name, column), res);
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
    
    protected void update_int64_by_id_2(int64 id, string column, int64 value) throws DatabaseError {
        Sqlite.Statement stmt;
        prepare_update_by_id(id, column, out stmt);
        
        int res = stmt.bind_int64(1, value);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("DatabaseTable.update_int64_by_id_2 %s.%s".printf(table_name, column), res);
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
    
    public int get_count() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT COUNT(id) AS RowCount FROM %s".printf(table_name), -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            critical("Unable to retrieve row count on %s: (%d) %s", table_name, res, db.errmsg());
            
            return 0;
        }
        
        return stmt.column_int(0);
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
    
    if (version >= 0)
        debug("Database schema version %d created by app version %s", version, app_version);
    
    if (version == -1) {
        // no version set, do it now (tables will be created on demand)
        debug("Creating database schema version %d for app version %s", DatabaseTable.SCHEMA_VERSION,
            Resources.APP_VERSION);
        version_table.set_version(DatabaseTable.SCHEMA_VERSION, Resources.APP_VERSION);
        app_version = Resources.APP_VERSION;
    } else if (version > DatabaseTable.SCHEMA_VERSION) {
        // Back to the future
        return DatabaseVerifyResult.FUTURE_VERSION;
    } else if (version < DatabaseTable.SCHEMA_VERSION) {
        // Past is present
        DatabaseVerifyResult result = upgrade_database(version);
        if (result != DatabaseVerifyResult.OK)
            return result;
    }
    
    return DatabaseVerifyResult.OK;
}

private DatabaseVerifyResult upgrade_database(int version) {
    assert(version < DatabaseTable.SCHEMA_VERSION);
    
    // No upgrade available from version 1.
    if (version == 1)
        return DatabaseVerifyResult.NO_UPGRADE_AVAILABLE;
    
    message("Upgrading database from schema version %d to %d", version, DatabaseTable.SCHEMA_VERSION);
    
    //
    // Version 2: For all intents and purposes, the baseline schema version.
    // * Removed start_time and end_time from EventsTable
    //
    
    //
    // Version 3:
    // * Added flags column to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "flags")) {
        message("upgrade_database: adding flags column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "flags", "INTEGER DEFAULT 0"))
            return DatabaseVerifyResult.UPGRADE_ERROR;
    }
    
    version = 3;
    
    //
    // ThumbnailTable(s) removed.
    //
    
    //
    // Version 4:
    // * Added file_format column to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "file_format")) {
        message("upgrade_database: adding file_format column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "file_format", "INTEGER DEFAULT 0"))
            return DatabaseVerifyResult.UPGRADE_ERROR;
    }
    
    version = 4;
    
    //
    // Version 5:
    // * Added title column to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "title")) {
        message("upgrade_database: adding title column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "title", "TEXT"))
            return DatabaseVerifyResult.UPGRADE_ERROR;
    }
    
    version = 5;
    
    //
    // Version 6:
    // * Added backlinks column to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "backlinks")) {
        message("upgrade_database: adding backlinks column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "backlinks", "TEXT"))
            return DatabaseVerifyResult.UPGRADE_ERROR;
    }
    
    version = 6;
    
    //
    // * Ignore the exif_md5 column from PhotoTable.  Because removing columns with SQLite is
    //   painful, simply ignoring the column for now.  Keeping it up-to-date when possible in
    //   case a future requirement is discovered.
    //
    
    //
    // Version 7:
    // * Added BackingPhotoTable (which creates itself if needed)
    // * Added time_reimported and editable_id columns to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "time_reimported")) {
        message("upgrade_database: adding time_reimported column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "time_reimported", "INTEGER"))
            return DatabaseVerifyResult.UPGRADE_ERROR;
    }
    
    if (!DatabaseTable.has_column("PhotoTable", "editable_id")) {
        message("upgrade_database: adding editable_id column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "editable_id", "INTEGER DEFAULT -1"))
            return DatabaseVerifyResult.UPGRADE_ERROR;
    }
    
    version = 7;
    
    //
    // * Ignore the orientation column in BackingPhotoTable.  (See note above about removing
    //   columns from tables.)
    //
    
    //
    // Version 8:
    // * Added rating column to PhotoTable
    //

    if (!DatabaseTable.has_column("PhotoTable", "rating")) {
        message("upgrade_database: adding rating column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "rating", "INTEGER DEFAULT 0"))
            return DatabaseVerifyResult.UPGRADE_ERROR;
    }
    
    version = 8;
    
    assert(version == DatabaseTable.SCHEMA_VERSION);
    VersionTable.get_instance().update_version(version, Resources.APP_VERSION);
    
    message("Database upgrade to schema version %d successful", version);
    
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

//
// PhotoTable
//

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
    
    public static uint hash(void *a) {
        return int64_hash(&((PhotoID *) a)->id);
    }
    
    public static bool equal(void *a, void *b) {
        return ((PhotoID *) a)->id == ((PhotoID *) b)->id;
    }
}

public struct ImportID {
    public const int64 INVALID = 0;

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
    
    public static int compare_func(void *a, void *b) {
        int64 cmp = comparator(a, b);
        if (cmp < 0)
            return -1;
        else if (cmp > 0)
            return 1;
        else
            return 0;
    }
    
    public static int64 comparator(void *a, void *b) {
        return ((ImportID *) a)->id - ((ImportID *) b)->id;
    }
}

public struct BackingPhotoState {
    public string? filepath;
    public int64 filesize;
    public time_t timestamp;
    public PhotoFileFormat file_format;
    public Dimensions dim;
    public Orientation original_orientation;
    
    public bool matches_file_info(FileInfo info) {
        if (filesize != info.get_size())
            return false;
        
        TimeVal modification;
        info.get_modification_time(out modification);
        
        return timestamp == modification.tv_sec;
    }
}

public struct PhotoRow {
    public PhotoID photo_id;
    public BackingPhotoState master;
    public time_t exposure_time;
    public ImportID import_id;
    public EventID event_id;
    public Orientation orientation;
    public Gee.HashMap<string, KeyValueMap>? transformations;
    public string md5;
    public string thumbnail_md5;
    public string exif_md5;
    public time_t time_created;
    public uint64 flags;
    public Rating rating;
    public string title;
    public string? backlinks;
    public time_t time_reimported;
    public BackingPhotoID editable_id;
    
    public PhotoRow() {
        editable_id = BackingPhotoID();
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
            + "flags INTEGER DEFAULT 0, "
            + "rating INTEGER DEFAULT 0, "
            + "file_format INTEGER DEFAULT 0, "
            + "title TEXT, "
            + "backlinks TEXT, "
            + "time_reimported INTEGER, "
            + "editable_id INTEGER DEFAULT -1"
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
    
    // PhotoRow.photo_id, event_id, master.orientation, flags, and time_created are ignored on input.
    // All fields are set on exit with values stored in the database.  editable_id field is ignored.
    public PhotoID add(ref PhotoRow photo_row) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO PhotoTable (filename, width, height, filesize, timestamp, exposure_time, "
            + "orientation, original_orientation, import_id, event_id, md5, thumbnail_md5, "
            + "exif_md5, time_created, file_format, title, rating, editable_id) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        ulong time_created = now_sec();
        
        res = stmt.bind_text(1, photo_row.master.filepath);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, photo_row.master.dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(3, photo_row.master.dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(4, photo_row.master.filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(5, photo_row.master.timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(6, photo_row.exposure_time);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(7, photo_row.master.original_orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(8, photo_row.master.original_orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(9, photo_row.import_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(10, EventID.INVALID);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(11, photo_row.md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(12, photo_row.thumbnail_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(13, photo_row.exif_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(14, time_created);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(15, photo_row.master.file_format.serialize());
        assert(res == Sqlite.OK);
        res = stmt.bind_text(16, photo_row.title);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(17, photo_row.rating.serialize());
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(18, BackingPhotoID.INVALID);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                fatal("add_photo", res);
            
            return PhotoID();
        }
        
        // fill in ignored fields with database values
        photo_row.photo_id = PhotoID(db.last_insert_rowid());
        photo_row.orientation = photo_row.master.original_orientation;
        photo_row.event_id = EventID();
        photo_row.time_created = (time_t) time_created;
        photo_row.flags = 0;
        
        return photo_row.photo_id;
    }
    
    // The only fields recognized in the PhotoRow are photo_id, dimensions,
    // filesize, timestamp, exposure_time, original_orientation, file_format,
    // and the md5 fields.  When the method returns, time_reimported and master.orientation has been 
    // updated.  editable_id is ignored.  transformations are cleared.
    public void reimport(ref PhotoRow row) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "UPDATE PhotoTable SET width = ?, height = ?, filesize = ?, timestamp = ?, "
            + "exposure_time = ?, orientation = ?, original_orientation = ?, md5 = ?, " 
            + "exif_md5 = ?, thumbnail_md5 = ?, file_format = ?, time_reimported = ?, "
            + "transformations = ? WHERE id = ?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        time_t time_reimported = (time_t) now_sec();
        
        res = stmt.bind_int(1, row.master.dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, row.master.dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(3, row.master.filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(4, row.master.timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(5, row.exposure_time);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(6, row.master.original_orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(7, row.master.original_orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(8, row.md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(9, row.exif_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(10, row.thumbnail_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(11, row.master.file_format.serialize());
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(12, time_reimported);
        assert(res == Sqlite.OK);
        res = stmt.bind_null(13);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(14, row.photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("PhotoTable.reimport_master", res);
        
        row.time_reimported = time_reimported;
        row.orientation = row.master.original_orientation;
        row.transformations = null;
    }

    public bool master_exif_updated(PhotoID photoID, int64 filesize, long timestamp, 
        string md5, string? exif_md5, string? thumbnail_md5, ref PhotoRow row) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "UPDATE PhotoTable SET filesize = ?, timestamp = ?, md5 = ?, exif_md5 = ?,"
            + "thumbnail_md5 =? WHERE id = ?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(3, md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(4, exif_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(5, thumbnail_md5);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(6, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                fatal("write_update_photo", res);
            
            return false;
        }
        
        row.master.filesize = filesize;
        row.master.timestamp = timestamp;
        row.md5 = md5;
        row.exif_md5 = exif_md5;
        row.thumbnail_md5 = thumbnail_md5;
        
        return true;
    }
    
    public PhotoRow? get_row(PhotoID photo_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT filename, width, height, filesize, timestamp, exposure_time, orientation, "
            + "original_orientation, import_id, event_id, transformations, md5, thumbnail_md5, "
            + "exif_md5, time_created, flags, rating, file_format, title, backlinks, "
            + "time_reimported, editable_id "
            + "FROM PhotoTable WHERE id=?", 
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photo_id.id);
        assert(res == Sqlite.OK);
        
        if (stmt.step() != Sqlite.ROW)
            return null;
            
        PhotoRow row = PhotoRow();
        row.photo_id = photo_id;
        row.master.filepath = stmt.column_text(0);
        row.master.dim = Dimensions(stmt.column_int(1), stmt.column_int(2));
        row.master.filesize = stmt.column_int64(3);
        row.master.timestamp = (time_t) stmt.column_int64(4);
        row.exposure_time = (time_t) stmt.column_int64(5);
        row.orientation = (Orientation) stmt.column_int(6);
        row.master.original_orientation = (Orientation) stmt.column_int(7);
        row.import_id.id = stmt.column_int64(8);
        row.event_id.id = stmt.column_int64(9);
        row.transformations = marshall_all_transformations(stmt.column_text(10));
        row.md5 = stmt.column_text(11);
        row.thumbnail_md5 = stmt.column_text(12);
        row.exif_md5 = stmt.column_text(13);
        row.time_created = (time_t) stmt.column_int64(14);
        row.flags = stmt.column_int64(15);
        row.rating = Rating.unserialize(stmt.column_int(16));
        row.master.file_format = PhotoFileFormat.unserialize(stmt.column_int(17));
        row.title = stmt.column_text(18);
        row.backlinks = stmt.column_text(19);
        row.time_reimported = (time_t) stmt.column_int64(20);
        row.editable_id = BackingPhotoID(stmt.column_int64(21));
        
        return row;
    }
    
    public Gee.ArrayList<PhotoRow?> get_all() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT id, filename, width, height, filesize, timestamp, exposure_time, orientation, "
            + "original_orientation, import_id, event_id, transformations, md5, thumbnail_md5, "
            + "exif_md5, time_created, flags, rating, file_format, title, backlinks, time_reimported, "
            + "editable_id FROM PhotoTable", 
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        Gee.ArrayList<PhotoRow?> all = new Gee.ArrayList<PhotoRow?>();
        
        while ((res = stmt.step()) == Sqlite.ROW) {
            PhotoRow row = PhotoRow();
            row.photo_id.id = stmt.column_int64(0);
            row.master.filepath = stmt.column_text(1);
            row.master.dim = Dimensions(stmt.column_int(2), stmt.column_int(3));
            row.master.filesize = stmt.column_int64(4);
            row.master.timestamp = (time_t) stmt.column_int64(5);
            row.exposure_time = (time_t) stmt.column_int64(6);
            row.orientation = (Orientation) stmt.column_int(7);
            row.master.original_orientation = (Orientation) stmt.column_int(8);
            row.import_id.id = stmt.column_int64(9);
            row.event_id.id = stmt.column_int64(10);
            row.transformations = marshall_all_transformations(stmt.column_text(11));
            row.md5 = stmt.column_text(12);
            row.thumbnail_md5 = stmt.column_text(13);
            row.exif_md5 = stmt.column_text(14);
            row.time_created = (time_t) stmt.column_int64(15);
            row.flags = stmt.column_int64(16);
            row.rating = Rating.unserialize(stmt.column_int(17));
            row.master.file_format = PhotoFileFormat.unserialize(stmt.column_int(18));
            row.title = stmt.column_text(19);
            row.backlinks = stmt.column_text(20);
            row.time_reimported = (time_t) stmt.column_int64(21);
            row.editable_id = BackingPhotoID(stmt.column_int64(22));
            
            all.add(row);
        }
        
        return all;
    }
    
    // Create a duplicate of the specified row.  A new byte-for-byte duplicate (including filesystem
    // metadata) of PhotoID's file  needs to back this duplicate and its editable (if exists).
    public PhotoID duplicate(PhotoID photo_id, string new_filename, BackingPhotoID editable_id) {
        // get a copy of the original row, duplicating most (but not all) of it
        PhotoRow original = get_row(photo_id);
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO PhotoTable (filename, width, height, filesize, "
            + "timestamp, exposure_time, orientation, original_orientation, import_id, event_id, "
            + "transformations, md5, thumbnail_md5, exif_md5, time_created, flags, rating, "
            + "file_format, title, editable_id) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, new_filename);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, original.master.dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(3, original.master.dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(4, original.master.filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(5, original.master.timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(6, original.exposure_time);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(7, original.orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(8, original.master.original_orientation);
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
        res = stmt.bind_int64(16, (int64) original.flags);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(17, original.rating.serialize());
        assert(res == Sqlite.OK);
        res = stmt.bind_int(18, original.master.file_format.serialize());
        assert(res == Sqlite.OK);
        res = stmt.bind_text(19, original.title);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(20, editable_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                fatal("duplicate", res);
            
            return PhotoID();
        }
        
        return PhotoID(db.last_insert_rowid());
    }
    
    public bool set_title(PhotoID photo_id, string? new_title) {
       return update_text_by_id(photo_id.id, "title", new_title != null ? new_title : "");
    }
    
    public void set_filepath(PhotoID photo_id, string filepath) throws DatabaseError {
        update_text_by_id_2(photo_id.id, "filename", filepath);
    }
    
    public void update_timestamp(PhotoID photo_id, time_t timestamp) throws DatabaseError {
        update_int64_by_id_2(photo_id.id, "timestamp", timestamp);
    }
    
    public bool set_exposure_time(PhotoID photo_id, time_t time) {
        return update_int64_by_id(photo_id.id, "exposure_time", (int64) time);
    }
    
    public void set_import_id(PhotoID photo_id, ImportID import_id) throws DatabaseError {
        update_int64_by_id_2(photo_id.id, "import_id", import_id.id);
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
        return get_id(file).is_valid();
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
    
    public bool set_orientation(PhotoID photo_id, Orientation orientation) {
        return update_int_by_id(photo_id.id, "orientation", (int) orientation);
    }
    
    public bool replace_flags(PhotoID photo_id, uint64 flags) {
        return update_int64_by_id(photo_id.id, "flags", (int64) flags);
    }
    
    public bool set_rating(PhotoID photo_id, Rating rating) {
        return update_int_by_id(photo_id.id, "rating", rating.serialize());
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
    
    // Use PhotoFileFormat.UNKNOWN if not to search for matching file format; it's only used if
    // searching for MD5 duplicates.
    private Sqlite.Statement get_duplicate_stmt(File? file, string? thumbnail_md5, string? md5,
        PhotoFileFormat file_format) {
        assert(file != null || thumbnail_md5 != null || md5 != null);
        
        string sql = "SELECT id FROM PhotoTable WHERE";
        bool first = true;
        
        if (file != null) {
            sql += " filename=?";
            first = false;
        }
        
        if (thumbnail_md5 != null || md5 != null) {
            if (first)
                sql += " ((";
            else
                sql += " OR ((";
            first = false;
            
            if (thumbnail_md5 != null)
                sql += " thumbnail_md5=?";
            
            if (md5 != null) {
                if (thumbnail_md5 == null)
                    sql += " md5=?";
                else
                    sql += " OR md5=?";
            }
            
            sql += ")";
            
            if (file_format != PhotoFileFormat.UNKNOWN)
                sql += " AND file_format=?";
            
            sql += ")";
        }
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2(sql, -1, out stmt);
        assert(res == Sqlite.OK);
        
        int col = 1;
        
        if (file != null) {
            res = stmt.bind_text(col++, file.get_path());
            assert(res == Sqlite.OK);
        }
        
        if (thumbnail_md5 != null) {
            res = stmt.bind_text(col++, thumbnail_md5);
            assert(res == Sqlite.OK);
        }
        
        if (md5 != null) {
            res = stmt.bind_text(col++, md5);
            assert(res == Sqlite.OK);
        }
        
        if ((thumbnail_md5 != null || md5 != null) && file_format != PhotoFileFormat.UNKNOWN) {
            res = stmt.bind_int(col++, file_format.serialize());
            assert(res == Sqlite.OK);
        }

        return stmt;
    }

    public bool has_duplicate(File? file, string? thumbnail_md5, string? md5, PhotoFileFormat file_format) {
        Sqlite.Statement stmt = get_duplicate_stmt(file, thumbnail_md5, md5, file_format);
        int res = stmt.step();
        
        if (res == Sqlite.DONE) {
            // not found
            return false;
        } else if (res == Sqlite.ROW) {
            // at least one found
            return true;
        } else {
            fatal("has_duplicate", res);
            
            return false;
        }
    }
    
    public PhotoID[] get_duplicate_ids(File? file, string? thumbnail_md5, string? md5,
        PhotoFileFormat file_format) {
        Sqlite.Statement stmt = get_duplicate_stmt(file, thumbnail_md5, md5, file_format);
        
        PhotoID[] ids = new PhotoID[0];

        int res = stmt.step();
        while (res == Sqlite.ROW) {
            ids += PhotoID(stmt.column_int64(0));
            res = stmt.step();
        }

        return ids;
    }
    
    public void update_backlinks(PhotoID photo_id, string? backlinks) throws DatabaseError {
        update_text_by_id_2(photo_id.id, "backlinks", backlinks != null ? backlinks : "");
    }
    
    public void attach_editable(ref PhotoRow row, BackingPhotoID editable_id) throws DatabaseError {
        update_int64_by_id_2(row.photo_id.id, "editable_id", editable_id.id);
        
        row.editable_id = editable_id;
    }
    
    public void detach_editable(ref PhotoRow row) throws DatabaseError {
        update_int64_by_id_2(row.photo_id.id, "editable_id", BackingPhotoID.INVALID);
        
        row.editable_id = BackingPhotoID();
    }
}

//
// EventTable
//

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
    
    public EventRow create(PhotoID primary_photo_id) throws DatabaseError {
        assert(primary_photo_id.is_valid());
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO EventTable (primary_photo_id, time_created) VALUES (?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        time_t time_created = (time_t) now_sec();
        
        res = stmt.bind_int64(1, primary_photo_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, time_created);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("EventTable.create", res);
        
        EventRow row = EventRow();
        row.event_id = EventID(db.last_insert_rowid());
        row.name = null;
        row.primary_photo_id = primary_photo_id;
        row.time_created = time_created;
        
        return row;
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
    
    public Gee.ArrayList<EventRow?> get_events() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id, name, primary_photo_id, time_created FROM EventTable",
            -1, out stmt);
        assert(res == Sqlite.OK);

        Gee.ArrayList<EventRow?> event_rows = new Gee.ArrayList<EventRow?>();
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_events", res);

                break;
            }
            
            EventRow row = EventRow();
            row.event_id = EventID(stmt.column_int64(0));
            row.name = stmt.column_text(1);
            row.primary_photo_id = PhotoID(stmt.column_int64(2));
            row.time_created = (time_t) stmt.column_int64(3);
            
            event_rows.add(row);
        }
        
        return event_rows;
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

//
// TagTable
//

public struct TagID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public TagID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
}

public struct TagRow {
    public TagID tag_id;
    public string name;
    public Gee.Set<PhotoID?>? photo_id_list;
    public time_t time_created;
}

public class TagTable : DatabaseTable {
    private static TagTable instance = null;
    
    private TagTable() {
        set_table_name("TagTable");
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "TagTable "
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "name TEXT UNIQUE NOT NULL, "
            + "photo_id_list TEXT, "
            + "time_created INTEGER"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create TagTable", res);
    }
    
    public static TagTable get_instance() {
        if (instance == null)
            instance = new TagTable();
        
        return instance;
    }
    
    public TagRow add(string name) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO TagTable (name, time_created) VALUES (?, ?)", -1,
            out stmt);
        assert(res == Sqlite.OK);
        
        time_t time_created = (time_t) now_sec();
        
        res = stmt.bind_text(1, name);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, time_created);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("TagTable.add", res);
        
        TagRow row = TagRow();
        row.tag_id = TagID(db.last_insert_rowid());
        row.name = name;
        row.photo_id_list = null;
        row.time_created = time_created;
        
        return row;
    }
    
    // All fields but tag_id are respected in TagRow.
    public TagID create_from_row(TagRow row) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO TagTable (name, photo_id_list, time_created) VALUES (?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, row.name);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(2, serialize_photo_ids(row.photo_id_list));
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(3, row.time_created);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("TagTable.create_from_row", res);
        
        return TagID(db.last_insert_rowid());
    }
    
    public void remove(TagID tag_id) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM TagTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, tag_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("TagTable.remove", res);
    }
    
    public string? get_name(TagID tag_id) throws DatabaseError {
        Sqlite.Statement stmt;
        if (!select_by_id(tag_id.id, "name", out stmt))
            return null;
        
        return stmt.column_text(0);
    }
    
    public TagRow? get_row(TagID tag_id) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT name, photo_id_list, time_created FROM TagTable WHERE id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, tag_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.DONE)
            return null;
        else if (res != Sqlite.ROW)
            throw_error("TagTable.get_row", res);
        
        TagRow row = TagRow();
        row.tag_id = tag_id;
        row.name = stmt.column_text(0);
        row.photo_id_list = unserialize_photo_ids(stmt.column_text(1));
        row.time_created = (time_t) stmt.column_int64(2);
        
        return row;
    }
    
    public Gee.List<TagRow?> get_all_rows() throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id, name, photo_id_list, time_created FROM TagTable", -1,
            out stmt);
        assert(res == Sqlite.OK);
        
        Gee.List<TagRow?> rows = new Gee.ArrayList<TagRow?>();
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("TagTable.get_all_rows", res);
            
            // res == Sqlite.ROW
            TagRow row = TagRow();
            row.tag_id = TagID(stmt.column_int64(0));
            row.name = stmt.column_text(1);
            row.photo_id_list = unserialize_photo_ids(stmt.column_text(2));
            row.time_created = (time_t) stmt.column_int64(3);
            
            rows.add(row);
        }
        
        return rows;
    }
    
    public void rename(TagID tag_id, string new_name) throws DatabaseError {
        update_text_by_id_2(tag_id.id, "name", new_name);
    }
    
    public void set_tagged_photos(TagID tag_id, Gee.Collection<PhotoID?> photo_ids) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE TagTable SET photo_id_list=? WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, serialize_photo_ids(photo_ids));
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, tag_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("TagTable.set_tagged_photos", res);
    }
    
    private string? serialize_photo_ids(Gee.Collection<PhotoID?>? photo_ids) {
        if (photo_ids == null)
            return null;
        
        StringBuilder result = new StringBuilder();
        
        foreach (PhotoID photo_id in photo_ids) {
            result.append(photo_id.id.to_string());
            result.append(",");
        }
        
        return (result.len != 0) ? result.str : null;
    }
    
    private Gee.Set<PhotoID?> unserialize_photo_ids(string? text_list) {
        Gee.Set<PhotoID?> result = new Gee.HashSet<PhotoID?>(PhotoID.hash, PhotoID.equal);
        
        if (text_list == null)
            return result;
        
        string[] split = text_list.split(",");
        foreach (string token in split) {
            if (is_string_empty(token))
                continue;
            
            unowned string endptr;
            int64 id = token.to_int64(out endptr, 10);
            
            // this verifies that the string was properly translated
            if (endptr[0] != '\0')
                continue;
            
            result.add(PhotoID(id));
        }
        
        return result;
    }
}

//
// BackingPhotoTable
//
// BackingPhotoTable is designed to hold any number of alternative backing photos
// for a Photo.  In the first implementation it was designed for editable photos (Edit with
// External Editor), but if other such alternates are needed, this is where to store them.
//
// Note that no transformations are held here.
//

public struct BackingPhotoID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public BackingPhotoID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
}

public struct BackingPhotoRow {
    public BackingPhotoID id;
    public time_t time_created;
    public BackingPhotoState state;
}

public class BackingPhotoTable : DatabaseTable {
    private static BackingPhotoTable instance = null;
    
    private BackingPhotoTable() {
        set_table_name("BackingPhotoTable");
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "BackingPhotoTable "
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "filepath TEXT UNIQUE NOT NULL, "
            + "timestamp INTEGER, "
            + "filesize INTEGER, "
            + "width INTEGER, "
            + "height INTEGER, "
            + "original_orientation INTEGER, "
            + "file_format INTEGER, "
            + "time_created INTEGER "
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create PhotoBackingTable", res);
    }
    
    public static BackingPhotoTable get_instance() {
        if (instance == null)
            instance = new BackingPhotoTable();
        
        return instance;
    }
    
    public BackingPhotoRow add(BackingPhotoState state) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO BackingPhotoTable "
            + "(filepath, timestamp, filesize, width, height, original_orientation, "
            + "file_format, time_created) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", 
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        time_t time_created = (time_t) now_sec();
        
        res = stmt.bind_text(1, state.filepath);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, state.timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(3, state.filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(4, state.dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(5, state.dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(6, state.original_orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(7, state.file_format.serialize());
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(8, (int64) time_created);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("PhotoBackingTable.add", res);
        
        BackingPhotoRow row = BackingPhotoRow();
        row.id = BackingPhotoID(db.last_insert_rowid());
        row.time_created = time_created;
        row.state = state;
        
        return row;
    }
    
    public BackingPhotoRow? fetch(BackingPhotoID id) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT filepath, timestamp, filesize, width, height, "
            + "original_orientation, file_format, time_created FROM BackingPhotoTable WHERE id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.DONE)
            return null;
        else if (res != Sqlite.ROW)
            throw_error("BackingPhotoTable.fetch_for_photo", res);
        
        BackingPhotoRow row = BackingPhotoRow();
        row.id = id;
        row.state.filepath = stmt.column_text(0);
        row.state.timestamp = (time_t) stmt.column_int64(1);
        row.state.filesize = stmt.column_int64(2);
        row.state.dim = Dimensions(stmt.column_int(3), stmt.column_int(4));
        row.state.original_orientation = (Orientation) stmt.column_int(5);
        row.state.file_format = PhotoFileFormat.unserialize(stmt.column_int(6));
        row.time_created = (time_t) stmt.column_int64(7);
        
        return row;
    }
    
    // Everything but filepath is updated.
    public void update(BackingPhotoID id, BackingPhotoState state) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE BackingPhotoTable SET timestamp=?, filesize=?, "
            + "width=?, height=?, original_orientation=?, file_format=? "
            + "WHERE id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, state.timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, state.filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(3, state.dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(4, state.dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(5, state.original_orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(6, state.file_format.serialize());
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(7, id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("BackingPhotoTable.update", res);
    }
    
    public void update_attributes(BackingPhotoID id, time_t timestamp, int64 filesize) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE BackingPhotoTable SET timestamp=?, filesize=? WHERE id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(3, id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("BackingPhotoTable.update_attributes", res);
    }
    
    public void remove(BackingPhotoID id) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM BackingPhotoTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("BackingPhotoTable.remove", res);
    }
    
    public void set_filepath(BackingPhotoID id, string filepath) throws DatabaseError {
        update_text_by_id_2(id.id, "filepath", filepath);
    }
    
    public void update_timestamp(BackingPhotoID id, time_t timestamp) throws DatabaseError {
        update_int64_by_id_2(id.id, "timestamp", timestamp);
    }
}

