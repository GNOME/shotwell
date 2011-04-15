/* Copyright 2011 Yorba Foundation
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

public struct SavedSearchRow {
    public SavedSearchID search_id;
    
    public string name;
    private SearchOperator operator;
    private Gee.List<SearchCondition> conditions;
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
        
        // Index on search text table.
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Text", res);
        
        res = db.prepare_v2("CREATE INDEX IF NOT EXISTS "
            + "SavedSearchDBTable_Text_Index "
            + "ON SavedSearchDBTable_Text(search_id)", -1, out stmt);
        assert(res == Sqlite.OK);
        
        res = stmt.step();
        if (res != Sqlite.DONE)
            fatal("create SavedSearchDBTable_Text_Index", res);
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
        
        SavedSearchRow row = SavedSearchRow();
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
                throw_error("SavedSearchDBTable.add", res);
        } else {
            // Should never get here.
            assert(false);
        }
    }
    
    // Removes the conditions of a search.  Used on delete.
    private void remove_conditions_for_search_id(SavedSearchID search_id) throws DatabaseError {
        remove_conditions_for_table("SavedSearchDBTable_Text", search_id);
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
        
        // Get all text conditions.
        Sqlite.Statement stmt;
        int res = db.prepare_v2("SELECT search_type, context, text FROM SavedSearchDBTable_Text "
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
        
        SavedSearchRow row = SavedSearchRow();
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
            
            SavedSearchRow row = SavedSearchRow();
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

