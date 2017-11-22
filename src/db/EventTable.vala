/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

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

public class EventRow {
    public EventID event_id;
    public string? name;
    public time_t time_created;
    public string? primary_source_id;
    public string? comment;
}

public class EventTable : DatabaseTable {
    private static EventTable instance = null;
    
    private EventTable() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS EventTable ("
            + "id INTEGER PRIMARY KEY, "
            + "name TEXT, "
            + "primary_photo_id INTEGER, "
            + "time_created INTEGER,"
            + "primary_source_id TEXT,"
            + "comment TEXT"
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
    
    // Returns a valid source ID, creating one from a legacy primary photo ID when needed.
    private string? source_id_upgrade(int64 primary_photo_id, string? primary_source_id) {
        if (MediaCollectionRegistry.get_instance().is_valid_source_id(primary_source_id)) {
            return primary_source_id;
        }
        if (primary_photo_id != PhotoID.INVALID) {
            // Upgrade to source_id from photo_id.
            return PhotoID.upgrade_photo_id_to_source_id(PhotoID(primary_photo_id));
        }
        return null;
    }
    
    public EventRow create(string? primary_source_id, string? comment) throws DatabaseError {
        assert(primary_source_id != null && primary_source_id != "");
    
        Sqlite.Statement stmt;
        int res = db.prepare_v2(
            "INSERT INTO EventTable (primary_source_id, time_created, comment) VALUES (?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        time_t time_created = (time_t) now_sec();
        
        res = stmt.bind_text(1, primary_source_id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, time_created);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(3, comment);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("EventTable.create", res);
        
        EventRow row = new EventRow();
        row.event_id = EventID(db.last_insert_rowid());
        row.name = null;
        row.primary_source_id = primary_source_id;
        row.time_created = time_created;
        row.comment = comment;
        
        return row;
    }
    
    // NOTE: The event_id in EventRow is ignored here.  No checking is done to prevent
    // against creating duplicate events or for the validity of other fields in the row (i.e.
    // the primary photo ID).
    public EventID create_from_row(EventRow row) {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO EventTable (name, primary_photo_id, primary_source_id, time_created, comment) VALUES (?, ?, ?, ?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, row.name);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(2, PhotoID.INVALID);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(3, row.primary_source_id);
        assert(res == Sqlite.OK);
        res = stmt.bind_int64(4, row.time_created);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(5, row.comment);
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
            "SELECT name, primary_photo_id, primary_source_id, time_created, comment FROM EventTable WHERE id=?", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, event_id.id);
        assert(res == Sqlite.OK);
        
        if (stmt.step() != Sqlite.ROW)
            return null;
        
        EventRow row = new EventRow();
        row.event_id = event_id;
        row.name = stmt.column_text(0);
        if (row.name != null && row.name.length == 0)
            row.name = null;
        row.primary_source_id = source_id_upgrade(stmt.column_int64(1), stmt.column_text(2));
        row.time_created = (time_t) stmt.column_int64(3);
        row.comment = stmt.column_text(4);
        
        return row;
    }
    
    public void remove(EventID event_id) throws DatabaseError {
        delete_by_id(event_id.id);
    }
    
    public Gee.ArrayList<EventRow?> get_events() {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id, name, primary_photo_id, primary_source_id, time_created, comment FROM EventTable",
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

            EventRow row = new EventRow();

            row.event_id = EventID(stmt.column_int64(0));
            row.name = stmt.column_text(1);
            row.primary_source_id = source_id_upgrade(stmt.column_int64(2), stmt.column_text(3));
            row.time_created = (time_t) stmt.column_int64(4);            
            row.comment = stmt.column_text(5);

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
    
    public string? get_primary_source_id(EventID event_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(event_id.id, "primary_source_id", out stmt))
            return null;
        
        return stmt.column_text(0);
    }
        
    public bool set_primary_source_id(EventID event_id, string primary_source_id) {
        return update_text_by_id(event_id.id, "primary_source_id", primary_source_id);
    }
    
    public time_t get_time_created(EventID event_id) {
        Sqlite.Statement stmt;
        if (!select_by_id(event_id.id, "time_created", out stmt))
            return 0;
        
        return (time_t) stmt.column_int64(0);
    }

    public bool set_comment(EventID event_id, string new_comment) {
        return update_text_by_id(event_id.id, "comment", new_comment != null ? new_comment : "");
    }
    
}


