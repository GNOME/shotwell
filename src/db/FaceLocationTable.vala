/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if ENABLE_FACES   

public struct FaceLocationID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public FaceLocationID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
}

public class FaceLocationRow {
    public FaceLocationID face_location_id;
    public FaceID face_id;
    public PhotoID photo_id;
    public string geometry;
}

public class FaceLocationTable : DatabaseTable {
    private static FaceLocationTable instance = null;
    
    private FaceLocationTable() {
        set_table_name("FaceLocationTable");
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "FaceLocationTable "
            + "("
            + "id INTEGER NOT NULL PRIMARY KEY, "
            + "face_id INTEGER NOT NULL, "
            + "photo_id INTEGER NOT NULL, "
            + "geometry TEXT"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create FaceLocationTable", res);
    }
    
    public static FaceLocationTable get_instance() {
        if (instance == null)
            instance = new FaceLocationTable();
        
        return instance;
    }
 
    public FaceLocationRow add(FaceID face_id, PhotoID photo_id, string geometry) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO FaceLocationTable (face_id, photo_id, geometry) VALUES (?, ?, ?)",
             -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, face_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, photo_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(3, geometry);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("FaceLocationTable.add", res);
        
        FaceLocationRow row = new FaceLocationRow();
        row.face_location_id = FaceLocationID(db.last_insert_rowid());
        row.face_id = face_id;
        row.photo_id = photo_id;
        row.geometry = geometry;
        
        return row;
    }
    
    public Gee.List<FaceLocationRow?> get_all_rows() throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT id, face_id, photo_id, geometry FROM FaceLocationTable",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        Gee.List<FaceLocationRow?> rows = new Gee.ArrayList<FaceLocationRow?>();
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("FaceLocationTable.get_all_rows", res);
            
            // res == Sqlite.ROW
            FaceLocationRow row = new FaceLocationRow();
            row.face_location_id = FaceLocationID(stmt.column_int64(0));
            row.face_id = FaceID(stmt.column_int64(1));
            row.photo_id = PhotoID(stmt.column_int64(2));
            row.geometry = stmt.column_text(3);
            
            rows.add(row);
        }
        
        return rows;
    }
    
    public Gee.ArrayList<string> get_face_source_ids(FaceID face_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT photo_id FROM FaceLocationTable WHERE face_id = ?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, face_id.id);
        assert(res == Sqlite.OK);
        
        Gee.ArrayList<string> result = new Gee.ArrayList<string>();
        for(;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_face_source_ids", res);

                break;
            }
            
            result.add(PhotoID.upgrade_photo_id_to_source_id(PhotoID(stmt.column_int64(0))));
        }
        
        return result;
    }
    
    public string? get_face_source_serialized_geometry(Face face, MediaSource source)
        throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT geometry FROM FaceLocationTable WHERE face_id=? AND photo_id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, face.get_instance_id());
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, ((Photo) source).get_instance_id());
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.DONE)
            return null;
        else if (res != Sqlite.ROW)
            throw_error("FaceLocationTable.get_face_source_serialized_geometry", res);
        
        return stmt.column_text(0);
    }
    
    public void remove_face_from_source(FaceID face_id, PhotoID photo_id) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "DELETE FROM FaceLocationTable WHERE face_id=? AND photo_id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, face_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("FaceLocationTable.remove_face_from_source", res);
    }
    
    public void update_face_location_serialized_geometry(FaceLocation face_location)
        throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE FaceLocationTable SET geometry=? WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, face_location.get_serialized_geometry());
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, face_location.get_face_location_id().id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("FaceLocationTable.update_face_location_serialized_geometry", res);
    }
}

#endif
