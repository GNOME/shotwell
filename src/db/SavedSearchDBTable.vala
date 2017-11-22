/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public struct SavedSearchID {
    public const int64 INVALID = -1;

    public int64 id;
    
    public SavedSearchID(int64 id = INVALID) {
        this.id = id;
    }
    
    public bool is_invalid() {
        return (id == INVALID);
    }
    
    public bool is_valid() {
        return (id != INVALID);
    }
}

public class SavedSearchRow {
    public SavedSearchID search_id;
    
    public string name;
    public SearchOperator operator;
    public Gee.List<SearchCondition> conditions;
}

public class SavedSearchDBTable : DatabaseTable {
    private static SavedSearchDBTable instance = null;
    
    private SavedSearchDBTable() {
        set_table_name("SavedSearchDBTable");
        
        // Create main search table.
        Sqlite.Statement stmt;
        int res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "SavedSearchDBTable "
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "name TEXT UNIQUE NOT NULL, "
            + "operator TEXT NOT NULL"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable", res);
        
        // Create search text table.
        res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "SavedSearchDBTable_Text "
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "search_id INTEGER NOT NULL, "
            + "search_type TEXT NOT NULL, "
            + "context TEXT NOT NULL, "
            + "text TEXT"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Text", res);
        
        // Create search media type table.
        res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "SavedSearchDBTable_MediaType "
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "search_id INTEGER NOT NULL, "
            + "search_type TEXT NOT NULL, "
            + "context TEXT NOT NULL, "
            + "type TEXT NOT_NULL"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_MediaType", res);
        
        // Create flagged search table.
        res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "SavedSearchDBTable_Flagged "
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "search_id INTEGER NOT NULL, "
            + "search_type TEXT NOT NULL, "
            + "flag_state TEXT NOT NULL"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Flagged", res);
            
        // Create modified search table.
        res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "SavedSearchDBTable_Modified "
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "search_id INTEGER NOT NULL, "
            + "search_type TEXT NOT NULL, "
            + "context TEXT NOT NULL, "
            + "modified_state TEXT NOT NULL"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Modified", res);
        
        // Create rating search table.
        res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "SavedSearchDBTable_Rating "
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "search_id INTEGER NOT NULL, "
            + "search_type TEXT NOT NULL, "
            + "rating INTEGER NOT_NULL, "
            + "context TEXT NOT NULL"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Rating", res);
        
        // Create date search table.
        res = db.prepare_v2("CREATE TABLE IF NOT EXISTS "
            + "SavedSearchDBTable_Date "
            + "("
            + "id INTEGER PRIMARY KEY, "
            + "search_id INTEGER NOT NULL, "
            + "search_type TEXT NOT NULL, "
            + "context TEXT NOT NULL, "
            + "date_one INTEGER NOT_NULL, "
            + "date_two INTEGER NOT_NULL"
            + ")", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Rating", res);
        
        // Create indexes.
        res = db.prepare_v2("CREATE INDEX IF NOT EXISTS "
            + "SavedSearchDBTable_Text_Index "
            + "ON SavedSearchDBTable_Text(search_id)", -1, out stmt);
        assert(res == Sqlite.OK);
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Text_Index", res);
        
        res = db.prepare_v2("CREATE INDEX IF NOT EXISTS "
            + "SavedSearchDBTable_MediaType_Index "
            + "ON SavedSearchDBTable_MediaType(search_id)", -1, out stmt);
        assert(res == Sqlite.OK);
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_MediaType_Index", res);
        
        res = db.prepare_v2("CREATE INDEX IF NOT EXISTS "
            + "SavedSearchDBTable_Flagged_Index "
            + "ON SavedSearchDBTable_Flagged(search_id)", -1, out stmt);
        assert(res == Sqlite.OK);
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Flagged_Index", res);
        
        res = db.prepare_v2("CREATE INDEX IF NOT EXISTS "
            + "SavedSearchDBTable_Modified_Index "
            + "ON SavedSearchDBTable_Modified(search_id)", -1, out stmt);
        assert(res == Sqlite.OK);
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Modified_Index", res);
        
        res = db.prepare_v2("CREATE INDEX IF NOT EXISTS "
            + "SavedSearchDBTable_Rating_Index "
            + "ON SavedSearchDBTable_Rating(search_id)", -1, out stmt);
        assert(res == Sqlite.OK);
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Rating_Index", res);
        
        res = db.prepare_v2("CREATE INDEX IF NOT EXISTS "
            + "SavedSearchDBTable_Date_Index "
            + "ON SavedSearchDBTable_Date(search_id)", -1, out stmt);
        assert(res == Sqlite.OK);
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Date_Index", res);
    }
    
    public static SavedSearchDBTable get_instance() {
        if (instance == null)
            instance = new SavedSearchDBTable();
        
        return instance;
    }
    
    public SavedSearchRow add(string name, SearchOperator operator, 
        Gee.ArrayList<SearchCondition> conditions) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO SavedSearchDBTable (name, operator) VALUES (?, ?)", -1,
            out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, name);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(2, operator.to_string());
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("SavedSearchDBTable.add", res);
        
        SavedSearchRow row = new SavedSearchRow();
        row.search_id = SavedSearchID(db.last_insert_rowid());
        row.name = name;
        row.operator = operator;
        row.conditions = conditions;
        
        foreach (SearchCondition sc in conditions) {
            add_condition(row.search_id, sc);
        }
        
        return row;
    }
    
    private void add_condition(SavedSearchID id, SearchCondition condition) throws DatabaseError {
        if (condition is SearchConditionText) {
            SearchConditionText text = condition as SearchConditionText;
            Sqlite.Statement stmt;
            int res = db.prepare_v2("INSERT INTO SavedSearchDBTable_Text (search_id, search_type, context, "
                + "text) VALUES (?, ?, ?, ?)", -1,
                out stmt);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_int64(1, id.id);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(2, text.search_type.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(3, text.context.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(4, text.text);
            assert(res == Sqlite.OK);
            
            res = stmt.step();
            if (res != Sqlite.DONE)
                throw_error("SavedSearchDBTable_Text.add", res);
        } else if (condition is SearchConditionMediaType) {
            SearchConditionMediaType media_type = condition as SearchConditionMediaType;
            Sqlite.Statement stmt;
            int res = db.prepare_v2("INSERT INTO SavedSearchDBTable_MediaType (search_id, search_type, context, "
                + "type) VALUES (?, ?, ?, ?)", -1,
                out stmt);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_int64(1, id.id);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(2, media_type.search_type.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(3, media_type.context.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(4, media_type.media_type.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.step();
            if (res != Sqlite.DONE)
                throw_error("SavedSearchDBTable_MediaType.add", res);
        } else if (condition is SearchConditionFlagged) {
            SearchConditionFlagged flag_state = condition as SearchConditionFlagged;
            Sqlite.Statement stmt;
            int res = db.prepare_v2("INSERT INTO SavedSearchDBTable_Flagged (search_id, search_type, "
                + "flag_state) VALUES (?, ?, ?)", -1,
                out stmt);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_int64(1, id.id);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(2, flag_state.search_type.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(3, flag_state.state.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.step();
            if (res != Sqlite.DONE)
                throw_error("SavedSearchDBTable_Flagged.add", res);
        } else if (condition is SearchConditionModified) {
            SearchConditionModified modified_state = condition as SearchConditionModified;
            Sqlite.Statement stmt;
            int res = db.prepare_v2("INSERT INTO SavedSearchDBTable_Modified (search_id, search_type, context, "
                + "modified_state) VALUES (?, ?, ?, ?)", -1,
                out stmt);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_int64(1, id.id);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(2, modified_state.search_type.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(3, modified_state.context.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(4, modified_state.state.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.step();
            if (res != Sqlite.DONE)
                throw_error("SavedSearchDBTable_Modified.add", res);
        } else if (condition is SearchConditionRating) {
            SearchConditionRating rating = condition as SearchConditionRating;
            Sqlite.Statement stmt;
            int res = db.prepare_v2("INSERT INTO SavedSearchDBTable_Rating (search_id, search_type, rating, "
                + "context) VALUES (?, ?, ?, ?)", -1,
                out stmt);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_int64(1, id.id);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(2, rating.search_type.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_int(3, rating.rating.serialize());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(4, rating.context.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.step();
            if (res != Sqlite.DONE)
                throw_error("SavedSearchDBTable_Rating.add", res);
        } else if (condition is SearchConditionDate) {
            SearchConditionDate date = condition as SearchConditionDate;
            Sqlite.Statement stmt;
            int res = db.prepare_v2("INSERT INTO SavedSearchDBTable_Date (search_id, search_type, "
                + "context, date_one, date_two) VALUES (?, ?, ?, ?, ?)", -1,
                out stmt);
            assert(res == Sqlite.OK);
            
            res = stmt.bind_int64(1, id.id);
            assert(res == Sqlite.OK);
            
             res = stmt.bind_text(2, date.search_type.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_text(3, date.context.to_string());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_int64(4, date.date_one.to_unix());
            assert(res == Sqlite.OK);
            
            res = stmt.bind_int64(5, date.date_two.to_unix());
            assert(res == Sqlite.OK);
            
            res = stmt.step();
            if (res != Sqlite.DONE)
                throw_error("SavedSearchDBTable_Date.add", res);
        } else {
            assert_not_reached();
        }
    }
    
    // Removes the conditions of a search.  Used on delete.
    private void remove_conditions_for_search_id(SavedSearchID search_id) throws DatabaseError {
        remove_conditions_for_table("SavedSearchDBTable_Text", search_id);
        remove_conditions_for_table("SavedSearchDBTable_MediaType", search_id);
        remove_conditions_for_table("SavedSearchDBTable_Flagged", search_id);
        remove_conditions_for_table("SavedSearchDBTable_Modified", search_id);
        remove_conditions_for_table("SavedSearchDBTable_Rating", search_id);
        remove_conditions_for_table("SavedSearchDBTable_Date", search_id);
    }
    
    private void remove_conditions_for_table(string table_name, SavedSearchID search_id)
        throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("DELETE FROM %s WHERE search_id=?".printf(table_name), -1, out stmt);
        assert(res == Sqlite.OK);

        res = stmt.bind_int64(1, search_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("%s.remove".printf(table_name), res);
    }
    
    // Returns all conditions for a given search.  Used on loading a search.
    private Gee.List<SearchCondition> get_conditions_for_id(SavedSearchID search_id)
        throws DatabaseError {
        Gee.List<SearchCondition> list = new Gee.ArrayList<SearchCondition>();
        Sqlite.Statement stmt;
        int res;
        
        // Get all text conditions.
        res = db.prepare_v2("SELECT search_type, context, text FROM SavedSearchDBTable_Text "
            + "WHERE search_id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, search_id.id);
        assert(res == Sqlite.OK);
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("SavedSearchDBTable_Text.get_all_rows", res);
            
            SearchConditionText condition = new SearchConditionText(
                SearchCondition.SearchType.from_string(stmt.column_text(0)), 
                stmt.column_text(2), 
                SearchConditionText.Context.from_string(stmt.column_text(1)));
            
            list.add(condition);
        }
        
        // Get all media type conditions.
        res = db.prepare_v2("SELECT search_type, context, type FROM SavedSearchDBTable_MediaType "
            + "WHERE search_id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, search_id.id);
        assert(res == Sqlite.OK);
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("SavedSearchDBTable_MediaType.get_all_rows", res);
            
            SearchConditionMediaType condition = new SearchConditionMediaType(
                SearchCondition.SearchType.from_string(stmt.column_text(0)), 
                SearchConditionMediaType.Context.from_string(stmt.column_text(1)),
                SearchConditionMediaType.MediaType.from_string(stmt.column_text(2)));
            
            list.add(condition);
        }
        
        // Get all flagged state conditions.
        res = db.prepare_v2("SELECT search_type, flag_state FROM SavedSearchDBTable_Flagged "
            + "WHERE search_id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, search_id.id);
        assert(res == Sqlite.OK);
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("SavedSearchDBTable_Flagged.get_all_rows", res);
            
            SearchConditionFlagged condition = new SearchConditionFlagged(
                SearchCondition.SearchType.from_string(stmt.column_text(0)), 
                SearchConditionFlagged.State.from_string(stmt.column_text(1)));
            
            list.add(condition);
        }
        
        // Get all modified state conditions.
        res = db.prepare_v2("SELECT search_type, context, modified_state FROM SavedSearchDBTable_Modified "
            + "WHERE search_id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, search_id.id);
        assert(res == Sqlite.OK);
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("SavedSearchDBTable_Modified.get_all_rows", res);
            
            SearchConditionModified condition = new SearchConditionModified(
                SearchCondition.SearchType.from_string(stmt.column_text(0)),
                SearchConditionModified.Context.from_string(stmt.column_text(1)),
                SearchConditionModified.State.from_string(stmt.column_text(2)));
            
            list.add(condition);
        }
        
        // Get all rating conditions.
        res = db.prepare_v2("SELECT search_type, rating, context FROM SavedSearchDBTable_Rating "
            + "WHERE search_id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, search_id.id);
        assert(res == Sqlite.OK);
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("SavedSearchDBTable_Rating.get_all_rows", res);
            
            SearchConditionRating condition = new SearchConditionRating(
                SearchCondition.SearchType.from_string(stmt.column_text(0)), 
                Rating.unserialize(stmt.column_int(1)),
                SearchConditionRating.Context.from_string(stmt.column_text(2)));
            
            list.add(condition);
        }
        
        // Get all date conditions.
        res = db.prepare_v2("SELECT search_type, context, date_one, date_two FROM SavedSearchDBTable_Date "
            + "WHERE search_id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, search_id.id);
        assert(res == Sqlite.OK);
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("SavedSearchDBTable_Date.get_all_rows", res);
            
            SearchConditionDate condition = new SearchConditionDate(
                SearchCondition.SearchType.from_string(stmt.column_text(0)), 
                SearchConditionDate.Context.from_string(stmt.column_text(1)),
                new DateTime.from_unix_local(stmt.column_int64(2)),
                new DateTime.from_unix_local(stmt.column_int64(3)));
            list.add(condition);
        }
        
        return list;
    }
    
    // All fields but search_id are respected in SavedSearchRow.
    public SavedSearchID create_from_row(SavedSearchRow row) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("INSERT INTO SavedSearchDBTable (name, operator) VALUES (?, ?)",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_text(1, row.name);
        assert(res == Sqlite.OK);
        res = stmt.bind_text(2, row.operator.to_string());
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            throw_error("SavedSearchDBTable.create_from_row", res);
        
        SavedSearchID search_id = SavedSearchID(db.last_insert_rowid());
        
        foreach (SearchCondition sc in row.conditions) {
            add_condition(search_id, sc);
        }
        
        return search_id;
    }
    
    public void remove(SavedSearchID search_id) throws DatabaseError {
        remove_conditions_for_search_id(search_id);
        delete_by_id(search_id.id);
    }
    
    public SavedSearchRow? get_row(SavedSearchID search_id) throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT name, operator FROM SavedSearchDBTable WHERE id=?",
            -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.bind_int64(1, search_id.id);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res == Sqlite.DONE)
            return null;
        else if (res != Sqlite.ROW)
            throw_error("SavedSearchDBTable.get_row", res);
        
        SavedSearchRow row = new SavedSearchRow();
        row.search_id = search_id;
        row.name = stmt.column_text(0);
        row.operator = SearchOperator.from_string(stmt.column_text(1));
        
        return row;
    }
    
    public Gee.List<SavedSearchRow?> get_all_rows() throws DatabaseError {
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT id, name, operator FROM SavedSearchDBTable", -1,
            out stmt);
        assert(res == Sqlite.OK);
        
        Gee.List<SavedSearchRow?> rows = new Gee.ArrayList<SavedSearchRow?>();
        
        for (;;) {
            res = stmt.step();
            if (res == Sqlite.DONE)
                break;
            else if (res != Sqlite.ROW)
                throw_error("SavedSearchDBTable.get_all_rows", res);
            
            SavedSearchRow row = new SavedSearchRow();
            row.search_id = SavedSearchID(stmt.column_int64(0));
            row.name = stmt.column_text(1);
            row.operator = SearchOperator.from_string(stmt.column_text(2));
            row.conditions = get_conditions_for_id(row.search_id);
            
            rows.add(row);
        }
        
        return rows;
    }
    
    public void rename(SavedSearchID search_id, string new_name) throws DatabaseError {
        update_text_by_id_2(search_id.id, "name", new_name);
    }
}

