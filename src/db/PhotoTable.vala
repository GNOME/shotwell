/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

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

    public uint hash() {
        return int64_hash(id);
    }

    public static bool equal(void *a, void *b) {
        return ((PhotoID *) a)->id == ((PhotoID *) b)->id;
    }
    
    public static string upgrade_photo_id_to_source_id(PhotoID photo_id) {
        return ("%s%016" + int64.FORMAT_MODIFIER + "x").printf(Photo.TYPENAME, photo_id.id);
    }
}

public struct ImportID {
    public const int64 INVALID = 0;

    public int64 id;
    
    public ImportID(int64 id = INVALID) {
        this.id = id;
    }
    
    public static ImportID generate() {
        TimeVal timestamp = TimeVal();
        timestamp.get_current_time();
        int64 id = timestamp.tv_sec;
        
        return ImportID(id);
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
    
    public static int compare_func(ImportID? a, ImportID? b) {
        assert (a != null && b != null);
        return (int) (a.id - b.id);
    }
    
    public static int64 comparator(void *a, void *b) {
        return ((ImportID *) a)->id - ((ImportID *) b)->id;
    }
}

public class PhotoRow {
    public PhotoID photo_id;
    public BackingPhotoRow master;
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
    public string comment;
    public string? backlinks;
    public time_t time_reimported;
    public BackingPhotoID editable_id;
    public bool metadata_dirty;
    
    // Currently selected developer (RAW only)
    public RawDeveloper developer;
    
    // Currently selected developer (RAW only)
    public BackingPhotoID[] development_ids;
    
    
    public PhotoRow() {
        master = new BackingPhotoRow();
        editable_id = BackingPhotoID();
        development_ids = new BackingPhotoID[RawDeveloper.as_array().length];
        foreach (RawDeveloper d in RawDeveloper.as_array())
            development_ids[d] = BackingPhotoID();
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
            + "editable_id INTEGER DEFAULT -1, "
            + "metadata_dirty INTEGER DEFAULT 0, "
            + "developer TEXT, "
            + "develop_shotwell_id INTEGER DEFAULT -1, "
            + "develop_camera_id INTEGER DEFAULT -1, "
            + "develop_embedded_id INTEGER DEFAULT -1, "
            + "comment TEXT"
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

        // These are for duplicate searches
        // https://bugzilla.gnome.org/show_bug.cgi?id=742670
        //
        // 1) index on md5,file_format
        res = db.prepare_v2 ("DROP INDEX IF EXISTS PhotoTableMD5Format", -1, out stmt);
        assert (res == Sqlite.OK);
        res = stmt.step ();
        if (res != Sqlite.DONE) {
            DatabaseTable.warning ("Failed to drop old PhotoTable index", res);
        }

        res = db.prepare_v2 ("CREATE INDEX IF NOT EXISTS PhotoTableMD5FormatV2 on PhotoTable(md5, file_format)", -1, out stmt);
        assert (res == Sqlite.OK);
        res = stmt.step ();
        if (res != Sqlite.DONE) {
            DatabaseTable.warning ("Failed to create index on md5 and file_format", res);
        }

        // 2) index on thumbnail_md5,file_format
        res = db.prepare_v2 ("CREATE INDEX IF NOT EXISTS PhotoTableThumbnailMD5Format on PhotoTable(thumbnail_md5, file_format)", -1, out stmt);
        assert (res == Sqlite.OK);
        res = stmt.step ();
        if (res != Sqlite.DONE) {
            DatabaseTable.warning ("Failed to create index on md5 and file_format", res);
        }

        // 3) index on thumbnail_md5,md5
        res = db.prepare_v2 ("CREATE INDEX IF NOT EXISTS PhotoTableThumbnailMD5MD5 on PhotoTable(thumbnail_md5, md5)", -1, out stmt);
        assert (res == Sqlite.OK);
        res = stmt.step ();
        if (res != Sqlite.DONE) {
            DatabaseTable.warning ("Failed to create index on thumbnail_md5 and md5", res);
        }

        set_table_name("PhotoTable");
    }
    
    public static PhotoTable get_instance() {
        if (instance == null)
            instance = new PhotoTable();
        
        return instance;
    }
    
    // PhotoRow.photo_id, event_id, master.orientation, flags, and time_created are ignored on input.
    // All fields are set on exit with values stored in the database.  editable_id field is ignored.
    public PhotoID add(PhotoRow photo_row) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO PhotoTable (filename, width, height, filesize, timestamp, exposure_time, "
            + "orientation, original_orientation, import_id, event_id, md5, thumbnail_md5, "
            + "exif_md5, time_created, file_format, title, rating, editable_id, developer, comment) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
        res = stmt.bind_text(19, photo_row.developer.to_string());
        assert(res == Sqlite.OK);
        res = stmt.bind_text(20, photo_row.comment);
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
    // updated.  editable_id is ignored.  transformations are untouched; use
    // remove_all_transformations() if necessary.
    public void reimport(PhotoRow row) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "UPDATE PhotoTable SET width = ?, height = ?, filesize = ?, timestamp = ?, "
            + "exposure_time = ?, orientation = ?, original_orientation = ?, md5 = ?, " 
            + "exif_md5 = ?, thumbnail_md5 = ?, file_format = ?, title = ?, time_reimported = ? "
            + "WHERE id = ?", -1, out stmt);
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
        res = stmt.bind_text(12, row.title);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(13, time_reimported);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(14, row.photo_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("PhotoTable.reimport_master", res);
        
        row.time_reimported = time_reimported;
        row.orientation = row.master.original_orientation;
    }

    public bool master_exif_updated(PhotoID photoID, int64 filesize, long timestamp, 
        string md5, string? exif_md5, string? thumbnail_md5, PhotoRow row) {
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

    // Force corrupted orientations to a safe value.  
    //
    // In previous versions of Shotwell, this field could be written to
    // the DB as a zero due to Vala 0.14 breaking the way it handled
    // objects passed as 'ref' arguments to methods. 
    // 
    // For further details, please see http://redmine.yorba.org/issues/4354 and 
    // https://bugzilla.gnome.org/show_bug.cgi?id=663818 .
    private void validate_orientation(PhotoRow row) {
        if ((row.orientation < Orientation.MIN) ||
            (row.orientation > Orientation.MAX)) {
            // orientation was corrupted; set it to top left.
            set_orientation(row.photo_id, Orientation.MIN);
            row.orientation = Orientation.MIN;
        }
    }
        
    public PhotoRow? get_row(PhotoID photo_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT filename, width, height, filesize, timestamp, exposure_time, orientation, "
            + "original_orientation, import_id, event_id, transformations, md5, thumbnail_md5, "
            + "exif_md5, time_created, flags, rating, file_format, title, backlinks, "
            + "time_reimported, editable_id, metadata_dirty, developer, develop_shotwell_id, "
            + "develop_camera_id, develop_embedded_id, comment "
            + "FROM PhotoTable WHERE id=?", 
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, photo_id.id);
        assert(res == Sqlite.OK);
        
        if (stmt.step() != Sqlite.ROW)
            return null;
            
        PhotoRow row = new PhotoRow();
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
        row.metadata_dirty = stmt.column_int(22) != 0;
        row.developer = stmt.column_text(23) != null ? RawDeveloper.from_string(stmt.column_text(23)) :
            RawDeveloper.CAMERA;
        row.development_ids[RawDeveloper.SHOTWELL] = BackingPhotoID(stmt.column_int64(24));
        row.development_ids[RawDeveloper.CAMERA] = BackingPhotoID(stmt.column_int64(25));
        row.development_ids[RawDeveloper.EMBEDDED] = BackingPhotoID(stmt.column_int64(26));
        row.comment = stmt.column_text(27);
        
        return row;
    }
    
    public Gee.ArrayList<PhotoRow?> get_all() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "SELECT id, filename, width, height, filesize, timestamp, exposure_time, orientation, "
            + "original_orientation, import_id, event_id, transformations, md5, thumbnail_md5, "
            + "exif_md5, time_created, flags, rating, file_format, title, backlinks, time_reimported, "
            + "editable_id, metadata_dirty, developer, develop_shotwell_id, develop_camera_id, " 
            + "develop_embedded_id, comment FROM PhotoTable", 
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        Gee.ArrayList<PhotoRow?> all = new Gee.ArrayList<PhotoRow?>();
        
        while ((res = stmt.step()) == Sqlite.ROW) {
            PhotoRow row = new PhotoRow();
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
            row.metadata_dirty = stmt.column_int(23) != 0;
            row.developer = stmt.column_text(24) != null ? RawDeveloper.from_string(stmt.column_text(24)) :
                RawDeveloper.CAMERA;
            row.development_ids[RawDeveloper.SHOTWELL] = BackingPhotoID(stmt.column_int64(25));
            row.development_ids[RawDeveloper.CAMERA] = BackingPhotoID(stmt.column_int64(26));
            row.development_ids[RawDeveloper.EMBEDDED] = BackingPhotoID(stmt.column_int64(27));
            row.comment = stmt.column_text(28);
            
            validate_orientation(row);
            
            all.add(row);
        }
        
        return all;
    }
    
    // Create a duplicate of the specified row.  A new byte-for-byte duplicate (including filesystem
    // metadata) of PhotoID's file  needs to back this duplicate and its editable (if exists).
    public PhotoID duplicate(PhotoID photo_id, string new_filename, BackingPhotoID editable_id,
        BackingPhotoID develop_shotwell, BackingPhotoID develop_camera_id, 
        BackingPhotoID develop_embedded_id) {
        // get a copy of the original row, duplicating most (but not all) of it
        PhotoRow original = get_row(photo_id);
        
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO PhotoTable (filename, width, height, filesize, "
            + "timestamp, exposure_time, orientation, original_orientation, import_id, event_id, "
            + "transformations, md5, thumbnail_md5, exif_md5, time_created, flags, rating, "
            + "file_format, title, editable_id, developer, develop_shotwell_id, develop_camera_id, "
            + "develop_embedded_id, comment) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
        
        res = stmt.bind_text(21, original.developer.to_string());
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(22, develop_shotwell.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(23, develop_camera_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(24, develop_embedded_id.id);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(25, original.comment);
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
    
    public bool set_comment(PhotoID photo_id, string? new_comment) {
       return update_text_by_id(photo_id.id, "comment", new_comment != null ? new_comment : "");
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
    
    public void remove(PhotoID photo_id) throws DatabaseError {
        delete_by_id(photo_id.id);
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
    
    public Gee.ArrayList<string> get_event_source_ids(EventID event_id) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id FROM PhotoTable WHERE event_id = ?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, event_id.id);
        assert(res == Sqlite.OK);
        
        Gee.ArrayList<string> result = new Gee.ArrayList<string>();
        for(;;) {
            res = stmt.step();
            if (res == Sqlite.DONE) {
                break;
            } else if (res != Sqlite.ROW) {
                fatal("get_event_source_ids", res);

                break;
            }
            
            result.add(PhotoID.upgrade_photo_id_to_source_id(PhotoID(stmt.column_int64(0))));
        }
        
        return result;
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
            KeyFile keyfile = new KeyFile();
            if (!keyfile.load_from_data(trans, trans.length, KeyFileFlags.NONE))
                return null;
            
            Gee.HashMap<string, KeyValueMap> map = new Gee.HashMap<string, KeyValueMap>();
            
            string[] objects = keyfile.get_groups();
            foreach (string object in objects) {
                string[] keys = keyfile.get_keys(object);
                if (keys == null || keys.length == 0)
                    continue;
                
                KeyValueMap key_map = new KeyValueMap(object);
                for (int ctr = 0; ctr < keys.length; ctr++)
                    key_map.set_string(keys[ctr], keyfile.get_string(object, keys[ctr]));
                
                map.set(object, key_map);
            }
            
            return map;
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    public static string? unmarshall_all_transformations(Gee.HashMap<string, KeyValueMap>? transformations) {
        if (transformations == null || transformations.keys.size == 0)
            return null;
        
        KeyFile keyfile = new KeyFile();
        
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
            KeyFile keyfile = new KeyFile();
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
        }
        
        return set_raw_transformations(photo_id, trans);
    }
    
    public bool remove_transformation(PhotoID photo_id, string object) {
        string trans = get_raw_transformations(photo_id);
        if (trans == null)
            return true;
        
        try {
            KeyFile keyfile = new KeyFile();
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
            
            if (md5 != null) {
                sql += " md5=?";

            }
            if (thumbnail_md5 != null) {
                if (md5 == null)
                    sql += " thumbnail_md5=?";
                else
                    sql += " OR (md5 IS NULL AND thumbnail_md5=?)";
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
    
    public void attach_editable(PhotoRow row, BackingPhotoID editable_id) throws DatabaseError {
        update_int64_by_id_2(row.photo_id.id, "editable_id", editable_id.id);
        
        row.editable_id = editable_id;
    }
    
    public void detach_editable(PhotoRow row) throws DatabaseError {
        update_int64_by_id_2(row.photo_id.id, "editable_id", BackingPhotoID.INVALID);
        
        row.editable_id = BackingPhotoID();
    }
    
    public void set_metadata_dirty(PhotoID photo_id, bool dirty) throws DatabaseError {
        update_int_by_id_2(photo_id.id, "metadata_dirty", dirty ? 1 : 0);
    }
    
    public void update_raw_development(PhotoRow row, RawDeveloper rd, BackingPhotoID backing_photo_id) 
        throws DatabaseError {
        
        string col;
        switch (rd) {
            case RawDeveloper.SHOTWELL:
                col = "develop_shotwell_id";
                break;
            
            case RawDeveloper.CAMERA:
                col = "develop_camera_id";
                break;
            
            case RawDeveloper.EMBEDDED:
                col = "develop_embedded_id";
                break;
            
            default:
                assert_not_reached();
        }
        
        row.development_ids[rd] = backing_photo_id;
        update_int64_by_id_2(row.photo_id.id, col, backing_photo_id.id);
        
        if (backing_photo_id.id != BackingPhotoID.INVALID)
            update_text_by_id_2(row.photo_id.id, "developer", rd.to_string());
    }
    
    public void remove_development(PhotoRow row, RawDeveloper rd) throws DatabaseError {
        update_raw_development(row, rd, BackingPhotoID());
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

public class BackingPhotoRow {
    public BackingPhotoID id;
    public time_t time_created;
    public string? filepath = null;
    public int64 filesize;
    public time_t timestamp;
    public PhotoFileFormat file_format;
    public Dimensions dim;
    public Orientation original_orientation;
    
    public bool matches_file_info(FileInfo info) {
        if (filesize != info.get_size())
            return false;
        
        return timestamp == info.get_modification_time().tv_sec;
    }
    
    public bool is_touched(FileInfo info) {
        if (filesize != info.get_size())
            return false;
        
        return timestamp != info.get_modification_time().tv_sec;
    }
    
    // Copies another backing photo row into this one.
    public void copy_from(BackingPhotoRow from) {
        id = from.id;
        time_created = from.time_created;
        filepath = from.filepath;
        filesize = from.filesize;
        timestamp = from.timestamp;
        file_format = from.file_format;
        dim = from.dim;
        original_orientation = from.original_orientation;
    }
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
    
    public void add(BackingPhotoRow state) throws DatabaseError {
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
        
        state.id = BackingPhotoID(db.last_insert_rowid());
        state.time_created = time_created;
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
        
        BackingPhotoRow row = new BackingPhotoRow();
        row.id = id;
        row.filepath = stmt.column_text(0);
        row.timestamp = (time_t) stmt.column_int64(1);
        row.filesize = stmt.column_int64(2);
        row.dim = Dimensions(stmt.column_int(3), stmt.column_int(4));
        row.original_orientation = (Orientation) stmt.column_int(5);
        row.file_format = PhotoFileFormat.unserialize(stmt.column_int(6));
        row.time_created = (time_t) stmt.column_int64(7);
        
        return row;
    }
    
    // Everything but filepath is updated.
    public void update(BackingPhotoRow row) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("UPDATE BackingPhotoTable SET timestamp=?, filesize=?, "
            + "width=?, height=?, original_orientation=?, file_format=? "
            + "WHERE id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, row.timestamp);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, row.filesize);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(3, row.dim.width);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(4, row.dim.height);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(5, row.original_orientation);
        assert(res == Sqlite.OK);
        res = stmt.bind_int(6, row.file_format.serialize());
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(7, row.id.id);
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
    
    public void remove(BackingPhotoID backing_id) throws DatabaseError {
        delete_by_id(backing_id.id);
    }
    
    public void set_filepath(BackingPhotoID id, string filepath) throws DatabaseError {
        update_text_by_id_2(id.id, "filepath", filepath);
    }
    
    public void update_timestamp(BackingPhotoID id, time_t timestamp) throws DatabaseError {
        update_int64_by_id_2(id.id, "timestamp", timestamp);
    }
}

