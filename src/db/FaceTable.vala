/* Copyright 2018 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if ENABLE_FACES
public struct FaceID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public FaceID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
}

public class FaceRow {
    public FaceID face_id;
    public string name;
    public time_t time_created;
}

public class FaceTable : DatabaseTable {
    private static FaceTable instance = null;
    
    private FaceTable() {
        set_table_name("FaceTable");
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "FaceTable "
            + "("
            + "id INTEGER NOT NULL PRIMARY KEY, "
            + "name TEXT NOT NULL, "
            + "time_created TIMESTAMP"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create FaceTable", res);
    }
    
    public static FaceTable get_instance() {
        if (instance == null)
            instance = new FaceTable();
        
        return instance;
    }
    
    public FaceRow add(string name) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO FaceTable (name, time_created) VALUES (?, ?)", -1,
            out stmt);
        assert(res == Sqlite.OK);
        
        time_t time_created = (time_t) now_sec();
        
        res = stmt.bind_text(1, name);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, time_created);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("FaceTable.add", res);
        
        FaceRow row = new FaceRow();
        row.face_id = FaceID(db.last_insert_rowid());
        row.name = name;
        row.time_created = time_created;
        
        return row;
    }
    
    public FaceID create_from_row(FaceRow row) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO FaceTable (name, time_created) VALUES (?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, row.name);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, row.time_created);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("FaceTable.create_from_row", res);
        
        return FaceID(db.last_insert_rowid());
    }
    
    public void remove(FaceID face_id) throws DatabaseError {
        delete_by_id(face_id.id);
    }
    
    public string? get_name(FaceID face_id) throws DatabaseError {
        Sqlite.Statement stmt;
        if (!select_by_id(face_id.id, "name", out stmt))
            return null;
        
        return stmt.column_text(0);
    }
    
    public FaceRow? get_row(FaceID face_id) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT name, time_created FROM FaceTable WHERE id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, face_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.DONE)
            return null;
        else if (res != Sqlite.ROW)
            throw_error("FaceTable.get_row", res);
        
        FaceRow row = new FaceRow();
        row.face_id = face_id;
        row.name = stmt.column_text(0);
        row.time_created = (time_t) stmt.column_int64(1);
        
        return row;
    }
    
    public Gee.List<FaceRow?> get_all_rows() throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id, name, time_created FROM FaceTable", -1,
            out stmt);
        assert(res == Sqlite.OK);
        
        Gee.List<FaceRow?> rows = new Gee.ArrayList<FaceRow?>();
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("FaceTable.get_all_rows", res);
            
            // res == Sqlite.ROW
            FaceRow row = new FaceRow();
            row.face_id = FaceID(stmt.column_int64(0));
            row.name = stmt.column_text(1);
            row.time_created = (time_t) stmt.column_int64(2);
            
            rows.add(row);
        }
        
        return rows;
    }
    
    public void rename(FaceID face_id, string new_name) throws DatabaseError {
        update_text_by_id_2(face_id.id, "name", new_name);
    }
}
#endif
