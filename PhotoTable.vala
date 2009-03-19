
public class PhotoTable {
    private static const string TABLE = "PhotoTable";
    
    private unowned Sqlite.Database db;
    
    public PhotoTable() {
        this.db = AppWindow.get_db();
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS PhotoTable ("
            + "id INTEGER PRIMARY KEY, "
            + "filename TEXT UNIQUE NOT NULL"
            + ")", -1, out stmt);
        if (res != Sqlite.OK) {
            error("Unable to prepare create stmt: %d", res);
            
            return;
        }
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            error("Unable to create PhotoTable: %d", res);
            
            return;
        }
    }
    
    public bool add_photo(File file) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO PhotoTable (filename) VALUES (?)", -1, out stmt);
        if (res != Sqlite.OK) {
            error("Unable to prepare insert stmt: %d", res);
            
            return false;
        }
        
        stmt.bind_text(1, file.get_path());
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            if (res != Sqlite.CONSTRAINT)
                error("add_photo: %s [%d]", db.errmsg(), res);
            
            return false;
        }

        return true;
    }
    
    public bool remove_photo(File file) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM PhotoTable WHERE filename=?", -1, out stmt);
        if (res != Sqlite.OK) {
            error("Unable to prepare delete stmt: %d", res);
            
            return false;
        }
        
        stmt.bind_text(1, file.get_path());
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            error("remove_photo: %s [%d]", db.errmsg(), res);
            
            return false;
        }
        
        return true;
    }
    
    public bool is_photo_stored(File file) {
        return (get_photo_id(file) != 0);
    }
    
    public int get_photo_id(File file) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT ID FROM PhotoTable WHERE filename=?", -1, out stmt);
        if (res != Sqlite.OK) {
            error("preparing select stmt: %s [%d]", db.errmsg(), res);
            
            return 0;
        }
        
        stmt.bind_text(1, file.get_path());
        
        res = stmt.step();
        if (res != Sqlite.DONE && res != Sqlite.ROW) {
            error("is_photo_stored: %s [%d]", db.errmsg(), res);
            
            return 0;
        }
        
        return stmt.column_int(0);
    }

    public File[] get_photo_files() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT filename FROM PhotoTable", -1, out stmt);
        if (res != Sqlite.OK) {
            error("Unable to prepare select stmt: %d", res);
            
            return new File[0];
        }

        File[] photoFiles = new File[0];

        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                error("get_photo_files: %s [%d]", db.errmsg(), res);
                
                break;
            }
            
            photoFiles += File.new_for_path(stmt.column_text(0));
        }
        
        return photoFiles;
    }
}
