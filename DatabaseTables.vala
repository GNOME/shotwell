
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
    public static const int INVALID = -1;

    public int id;
    
    public PhotoID(int id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
}

public class PhotoTable : DatabaseTable {
    public PhotoTable() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS PhotoTable ("
            + "id INTEGER PRIMARY KEY, "
            + "filename TEXT UNIQUE NOT NULL, "
            + "width INTEGER, "
            + "height INTEGER"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.step();
        if (res != Sqlite.DONE) {
            fatal("create photo table", res);
        }
    }
    
    public bool add(File file, Dimensions dim) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO PhotoTable (filename, width, height) VALUES (?, ?, ?)", 
            -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_text(1, file.get_path());
        assert(res == Sqlite.OK);
        res = stmt.bind_int(2, dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(3, dim.height);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                fatal("add_photo", res);
            
            return false;
        }

        return true;
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

        res = stmt.bind_int(1, photoID.id);
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
        if(res == Sqlite.ROW) {
            return PhotoID(stmt.column_int(0));
        }
        
        warning("get_photo_id", res);
        
        return PhotoID();
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
    
    public Dimensions? get_dimensions(PhotoID photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT width, height FROM PhotoTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        stmt.bind_int(1, photoID.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.ROW) {
            return Dimensions(stmt.column_int(0), stmt.column_int(1));
        }
        
        return null;
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

        res = stmt.bind_int(1, photoID.id);
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

        res = stmt.bind_int(1, photoID.id);
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

        res = stmt.bind_int(1, photoID.id);
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

        res = stmt.bind_int(1, photoID.id);
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
        
        res = stmt.bind_int(1, photoID.id);
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

