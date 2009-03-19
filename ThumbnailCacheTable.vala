
public class ThumbnailCacheTable {
    private unowned Sqlite.Database db;
    private string tableName;
    
    public ThumbnailCacheTable(int scale) {
        assert(scale > 0);

        this.db = AppWindow.get_db();
        this.tableName = "Thumb%dTable".printf(scale);
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + tableName
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "photo_id INTEGER UNIQUE, "
            + "width INTEGER, "
            + "height INTEGER"
            + ")", -1, out stmt);
        if (res != Sqlite.OK) {
            error("Unable to prepare create stmt: %d", res);
            
            return;
        }
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            error("Unable to create %s: %d", tableName, res);
            
            return;
        }
    }
    
    public bool remove(int photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM %s WHERE photo_id=?".printf(tableName), -1, out stmt);
        if (res != Sqlite.OK) {
            error("Unable to prepare delete stmt: %d", res);
            
            return false;
        }
        
        stmt.bind_int(1, photoID);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            error("Error deleting photo %d: %d", photoID, res);
            
            return false;
        }
        
        return true;
    }
    
    public bool exists(int photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM %s WHERE photo_id=?".printf(tableName), -1, out stmt);
        if (res != Sqlite.OK) {
            error("Unable to prepare select stmt: %d", res);
            
            return false;
        }
        
        stmt.bind_int(1, photoID);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            if (res != Sqlite.DONE) {
                error("Error finding photo %d: %d", photoID, res);
            }
            
            return false;
        }
        
        return true;
    }
    
    public bool add_dimensions(int photoID, Dimensions dim) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO %s (photo_id, width, height) VALUES (?, ?, ?)".printf(tableName),
            -1, out stmt);
        if (res != Sqlite.OK) {
            error("Unable to prepare insert stmt: %d", res);
            
            return false;
        }
        
        stmt.bind_int(1, photoID);
        stmt.bind_int(2, dim.width);
        stmt.bind_int(3, dim.height);
        
        res = stmt.step();
        if (res != Sqlite.DONE) {
            error("Error adding dimensions to %s: %d", tableName, res);
            
            return false;
        }
        
        return true;
    }
    
    public Dimensions? get_dimensions(int photoID) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT width, height FROM %s WHERE photo_id=?".printf(tableName), 
            -1, out stmt);
        if (res != Sqlite.OK) {
            error("Unable to prepare selec stmt: %d", res);
            
            return null;
        }
        
        stmt.bind_int(1, photoID);
        
        res = stmt.step();
        if (res != Sqlite.ROW) {
            // not found
            return null;
        }
        
        return Dimensions(stmt.column_int(0), stmt.column_int(1));
    }
}

