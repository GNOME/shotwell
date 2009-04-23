
public struct DatabaseID {
    public static const int64 INVALID = 0;

    public int64 id;
    
    public DatabaseID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
}

public class DatabaseTable : Object {
    protected static Sqlite.Database db;

    // Doing this because static construct {} not working
    public static void init() {
        File dbFile = AppWindow.get_data_subdir("data").get_child("photo.db");
        int res = Sqlite.Database.open_v2(dbFile.get_path(), out db, 
            Sqlite.OPEN_READWRITE | Sqlite.OPEN_CREATE, null);
        if (res != Sqlite.OK) {
            error("Unable to open/create photo database %s: %d", dbFile.get_path(), res);
        }
    }
    
    // TODO: errmsg() is global, and so this will not be accurate in a threaded situation
    protected static void fatal(string op, int res) {
        error("%s: [%d] %s", op, res, db.errmsg());
    }
    
    // TODO: errmsg() is global, and so this will not be accurate in a threaded situation
    protected static void warning(string op, int res) {
        GLib.warning("%s: [%d] %s", op, res, db.errmsg());
    }
}

public struct PhotoID {
    public static const int64 INVALID = -1;

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

public class PhotoTable : DatabaseTable {
    public PhotoTable() {
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
            + "import_id INTEGER, "
            + "event_id INTEGER"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("create photo table", res);
        }
    }
    
    public PhotoID add(File file, Dimensions dim, int64 filesize, long timestamp, long exposure_time,
        Exif.Orientation orientation, ImportID importID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO PhotoTable (filename, width, height, filesize, timestamp, exposure_time, orientation, import_id, event_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        debug("Import %s %dx%d size=%lld mod=%ld exp=%ld or=%d", file.get_path(), dim.width, dim.height,
            filesize, timestamp, exposure_time, (int) orientation);

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
        res = stmt.bind_int64(7, orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(8, importID.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(9, PhotoID.INVALID);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                fatal("add_photo", res);
            
            return PhotoID();
        }

        return PhotoID(db.last_insert_rowid());
    }
    
    public bool update(PhotoID photoID, File file, Dimensions dim, int64 filesize, long timestamp, long exposure_time,
        Exif.Orientation orientation) {
        TimeVal time_imported = TimeVal();
        time_imported.get_current_time();
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "UPDATE PhotoTable SET filename = ?, width = ?, height = ?, filesize = ?, timestamp = ?, "
            + "exposure_time = ?, orientation = ?, time_imported = ? WHERE id = ?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        debug("Update [%lld] %s %dx%d size=%lld mod=%ld exp=%ld or=%d", photoID.id, file.get_path(), dim.width, 
            dim.height, filesize, timestamp, exposure_time, (int) orientation);

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
        res = stmt.bind_int64(7, orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(8, time_imported.tv_sec);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(9, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                fatal("update_photo", res);
            
            return false;
        }

        return true;
    }
    
    public bool get_photo(PhotoID photoID, out PhotoRow row) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT filename, width, height, filesize, timestamp, exposure_time, orientation, import_id, event_id FROM PhotoTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW)
            return false;
        
        row.photo_id = photoID;
        row.file = File.new_for_path(stmt.column_text(0));
        row.dim = Dimensions(stmt.column_int(1), stmt.column_int(2));
        row.filesize = stmt.column_int64(3);
        row.timestamp = (long) stmt.column_int64(4);
        row.exposure_time = (long) stmt.column_int64(5);
        row.orientation = (Exif.Orientation) stmt.column_int(6);
        row.import_id = ImportID(stmt.column_int64(7));
        row.event_id = EventID(stmt.column_int64(8));
        
        return true;
    }
    
    public File? get_file(PhotoID photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT filename FROM PhotoTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.ROW)
            return File.new_for_path(stmt.column_text(0));
        
        return null;
    }
    
    public long get_exposure_time(PhotoID photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT exposure_time FROM PhotoTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW)
            return 0;
        
        return (long) stmt.column_int64(0);
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
        if(res != Sqlite.ROW) {
            warning("get_photo_id", res);

            return PhotoID();
        }
        
        return PhotoID(stmt.column_int64(0));
    }

    public File[] get_photo_files() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT filename FROM PhotoTable", -1, out stmt);
        assert(res == Sqlite.OK);

        File[] photoFiles = new File[0];
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_photo_files", res);

                break;
            }
            
            photoFiles += File.new_for_path(stmt.column_text(0));
        }
        
        return photoFiles;
    }
    
    public PhotoID[] get_photo_ids() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM PhotoTable", -1, out stmt);
        assert(res == Sqlite.OK);

        PhotoID[] photoIds = new PhotoID[0];
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_photo_ids", res);

                break;
            }
            
            photoIds += PhotoID(stmt.column_int64(0));
        }
        
        return photoIds;
    }
    
    public Dimensions? get_dimensions(PhotoID photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT width, height FROM PhotoTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.ROW) {
            return Dimensions(stmt.column_int(0), stmt.column_int(1));
        }
        
        return null;
    }
    
    public bool set_event(PhotoID photo_id, EventID event_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE PhotoTable SET event_id = ? WHERE id = ?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, event_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) { 
            fatal("set_event", res);
            
            return false;
        }
        
        return true;
    }
}

public class ThumbnailCacheTable : DatabaseTable {
    private string tableName;
    
    public ThumbnailCacheTable(int scale) {
        assert(scale > 0);

        this.tableName = "Thumb%dTable".printf(scale);
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + tableName
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "photo_id INTEGER UNIQUE, "
            + "width INTEGER, "
            + "height INTEGER, "
            + "filesize INTEGER"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("create thumbnail cache table", res);
        }
    }
    
    public bool remove(PhotoID photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM %s WHERE photo_id=?".printf(tableName), -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            warning("remove photo", res);

            return false;
        }
        
        return true;
    }
    
    public bool exists(PhotoID photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM %s WHERE photo_id=?".printf(tableName), -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE) {
                fatal("exists", res);
            }
            
            return false;
        }
        
        return true;
    }
    
    public void add(PhotoID photoID, int filesize, Dimensions dim) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO %s (photo_id, filesize, width, height) VALUES (?, ?, ?, ?)".printf(tableName),
            -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, filesize);
        assert(res == Sqlite.OK);
        stmt.bind_int(3, dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(4, dim.height);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("add", res);
        }
    }
    
    public Dimensions? get_dimensions(PhotoID photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT width, height FROM %s WHERE photo_id=?".printf(tableName), 
            -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if(res != Sqlite.DONE) {
                fatal("get_dimensions", res);
            }

            return null;
        }
        
        return Dimensions(stmt.column_int(0), stmt.column_int(1));
    }
    
    public int get_filesize(PhotoID photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT filesize FROM %s WHERE photo_id=?".printf(tableName),
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE) {
                fatal("get_filesize", res);
            }
            
            return -1;
        }
        
        return stmt.column_int(0);
    }
}

public struct ImportID {
    public static const int64 INVALID = -1;

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

public class ImportTable : DatabaseTable {
    public ImportTable() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS ImportTable ("
            + "id INTEGER PRIMARY KEY, "
            + "time_imported INTEGER"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("create photo table", res);
        }
    }

    public ImportID generate() {
        TimeVal time_imported = TimeVal();
        time_imported.get_current_time();
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO ImportTable (time_imported) VALUES (?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, time_imported.tv_sec);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("import generate", res);
            
            return ImportID();
        }
        
        return ImportID(db.last_insert_rowid());
    }
}

public struct EventID {
    public static const int64 INVALID = -1;

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

public class EventTable : DatabaseTable {
    public EventTable() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS EventTable ("
            + "id INTEGER PRIMARY KEY, "
            + "name TEXT, "
            + "primary_photo_id INTEGER, "
            + "time_created INTEGER"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("create photo table", res);
        }
    }
    
    public EventID create(string name, PhotoID primaryPhoto) {
        assert(primaryPhoto.is_valid());
        
        TimeVal time_created = TimeVal();
        time_created.get_current_time();
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO EventTable (name, primary_photo_id, time_created) VALUES (?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, name);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, primaryPhoto.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(3, time_created.tv_sec);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("create_event", res);
            
            return EventID();
        }

        return EventID(db.last_insert_rowid());;
    }
    
    public EventID[] get_events() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM EventTable", -1, out stmt);
        assert(res == Sqlite.OK);

        EventID[] eventIds = new EventID[0];
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_events_ids", res);

                break;
            }
            
            eventIds += EventID(stmt.column_int64(0));
        }
        
        return eventIds;
    }
    
    public string? get_name(EventID eventID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT name FROM EventTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, eventID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE) {
                fatal("event get_name", res);
            }
            
            return null;
        }
        
        return stmt.column_text(1);
    }
    
    public PhotoID get_primary_photo(EventID eventID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT primary_photo_id FROM EventTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, eventID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE) {
                fatal("event get_name", res);
            }
            
            return PhotoID();
        }
        
        return PhotoID(stmt.column_int(1));
    }
}

public struct PhotoRow {
    public PhotoID photo_id;
    public File file;
    public Dimensions dim;
    public int64 filesize;
    public long timestamp;
    public long exposure_time;
    public Exif.Orientation orientation;
    public ImportID import_id;
    public EventID event_id;
}

