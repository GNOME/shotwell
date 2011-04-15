/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// For specifying whether a search should be ORed (any) or ANDed (all).
public enum SearchOperator {
    ANY = 0,
    ALL;
    
    public string to_string() {
        switch (this) {
            case SearchOperator.ANY:
                return "ANY";
            
            case SearchOperator.ALL:
                return "ALL";
            
            default:
                error("unrecognized search operator enumeration value");
        }
    }
    
    public static SearchOperator from_string(string str) {
        if (str == "ANY")
            return SearchOperator.ANY;
        
        else if (str == "ALL")
            return SearchOperator.ALL;
        
        else
            error("unrecognized search operator name: %s", str);
    }
}

// Important note: if you are adding, removing, or otherwise changing
// this table, you're going to have to modify SavedSearchDBTable.vala
// as well.
public abstract class SearchCondition {
    // Type of search condition.
    public enum SearchType {
        ANY_TEXT = 0,
        TITLE,
        TAG,
        EVENT_NAME,
        FILE_NAME;
        
        public string to_string() {
            switch (this) {
                case SearchType.ANY_TEXT:
                    return "ANY_TEXT";
                
                case SearchType.TITLE:
                    return "TITLE";
                
                case SearchType.TAG:
                    return "TAG";
                
                case SearchType.EVENT_NAME:
                    return "EVENT_NAME";
                
                case SearchType.FILE_NAME:
                    return "FILE_NAME";
                
                default:
                    error("unrecognized search type enumeration value");
            }
        }
        
        public static SearchType from_string(string str) {
            if (str == "ANY_TEXT")
                return SearchType.ANY_TEXT;
            
            else if (str == "TITLE")
                return SearchType.TITLE;
            
            else if (str == "TAG")
                return SearchType.TAG;
            
            else if (str == "EVENT_NAME")
                return SearchType.EVENT_NAME;
            
            else if (str == "FILE_NAME")
                return SearchType.FILE_NAME;
            
            else
                error("unrecognized search type name: %s", str);
        }
    }
    
    public SearchType search_type { get; protected set; }
    
    // Determines whether the source is included.
    public abstract bool predicate(MediaSource source);
}

// Condition for text matching.
public class SearchConditionText : SearchCondition {
    public enum Context {
        CONTAINS = 0,
        IS_EXACTLY,
        STARTS_WITH,
        ENDS_WITH,
        DOES_NOT_CONTAIN,
        IS_NOT_SET;
        
        public string to_string() {
            switch (this) {
                case Context.CONTAINS:
                    return "CONTAINS";
                
                case Context.IS_EXACTLY:
                    return "IS_EXACTLY";
                
                case Context.STARTS_WITH:
                    return "STARTS_WITH";
                
                case Context.ENDS_WITH:
                    return "ENDS_WITH";
                
                case Context.DOES_NOT_CONTAIN:
                    return "DOES_NOT_CONTAIN";
                
                case Context.IS_NOT_SET:
                    return "IS_NOT_SET";
                
                default:
                    error("unrecognized text search context enumeration value");
            }
        }
        
        public static Context from_string(string str) {
            if (str == "CONTAINS")
                return Context.CONTAINS;
            
            else if (str == "IS_EXACTLY")
                return Context.IS_EXACTLY;
            
            else if (str == "STARTS_WITH")
                return Context.STARTS_WITH;
            
            else if (str == "ENDS_WITH")
                return Context.ENDS_WITH;
            
            else if (str == "DOES_NOT_CONTAIN")
                return Context.DOES_NOT_CONTAIN;
            
            else if (str == "IS_NOT_SET")
                return Context.IS_NOT_SET;
            
            else
                error("unrecognized text search context name: %s", str);
        }
    }

    // What to search for.
    public string text { get; private set; }
    
    // How to match.
    public Context context { get; private set; }
    
    public SearchConditionText(SearchCondition.SearchType search_type, string? text, Context context) {
        this.search_type = search_type;
        this.text = (text != null) ? text.down() : "";
        this.context = context;
    }
    
    // Match string by context.
    private bool string_match(string needle, string? haystack) {
        switch (context) {
            case Context.CONTAINS:
                return !is_string_empty(haystack) && haystack.contains(needle);
                
            case Context.IS_EXACTLY:
                return !is_string_empty(haystack) && haystack == needle;
                
            case Context.STARTS_WITH:
                return !is_string_empty(haystack) && haystack.has_prefix(needle);
                
            case Context.ENDS_WITH:
                return !is_string_empty(haystack) && haystack.has_suffix(needle);
                
            case Context.DOES_NOT_CONTAIN:
                return is_string_empty(haystack) || !haystack.contains(needle);
                
            case Context.IS_NOT_SET:
                return (is_string_empty(haystack));
        }
        
        return false;
    }
    // Determines whether the source is included.
    public override bool predicate(MediaSource source) {
        bool ret = false;
        
        if (SearchType.ANY_TEXT == search_type || SearchType.TITLE == search_type) {
            ret |= string_match(text, (source.get_title() != null) ? source.get_title().down() : null);
        }
        
        if (SearchType.ANY_TEXT == search_type || SearchType.TAG == search_type) {
            Gee.List<Tag>? tag_list = Tag.global.fetch_for_source(source);
            if (null != tag_list) {
                foreach (Tag tag in tag_list) {
                    ret |= string_match(text, tag.get_name().down());
                }
            } else {
                ret |= string_match(text, null); // for IS_NOT_SET
            }
        }
        
        if (SearchType.ANY_TEXT == search_type || SearchType.EVENT_NAME == search_type) {
            string? event_name = (null != source.get_event()) ? 
                source.get_event().get_name().down() : null;
            ret |= string_match(text, event_name);
        }
        
        if (SearchType.ANY_TEXT == search_type || SearchType.FILE_NAME == search_type) {
            ret |= string_match(text, source.get_basename().down());
        }
        
        return ret;
    }
}

// Contains the logic of a search.
// A saved search requires a name, an AND/OR (all/any) operator, as well as a list of one or more conditions.
public class SavedSearch : DataSource {
    public const string TYPENAME = "saved_search";
    
    // Row from the database.
    private SavedSearchRow row;
    
    public SavedSearch(SavedSearchRow row, int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
        
        this.row = row;
    }
    
    public override string get_name() {
        return row.name;
    }
    
    public override string to_string() {
        return "SavedSearch " + get_name();
    }
    
    public override string get_typename() {
        return TYPENAME;
    }
    
    public SavedSearchID get_saved_search_id() {
        return row.search_id;
    }

    public override int64 get_instance_id() {
        return get_saved_search_id().id;
    }

    public static int compare_names(void *a, void *b) {
        SavedSearch *asearch = (SavedSearch *) a;
        SavedSearch *bsearch = (SavedSearch *) b;
        
        return String.collated_compare(asearch->get_name(), bsearch->get_name());
    }
    
    public bool predicate(MediaSource source) {
        bool ret;
        if (SearchOperator.ALL == row.operator) 
            ret = true;
        else
            ret = false; // assumes conditions.size() > 0
        
        foreach (SearchCondition c in row.conditions) {
            if (SearchOperator.ALL == row.operator) 
                ret &= c.predicate(source);
            else
                ret |= c.predicate(source);
        }
        return ret;
    }
    
    public void reconstitute() {
        try {
            row.search_id = SavedSearchDBTable.get_instance().create_from_row(row);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        SavedSearchTable.get_instance().add_to_map(this);
        debug("Reconstituted %s", to_string());
    }
    
    // Returns false if the name already exists or a bad name.
    public bool rename(string new_name) {
        if (is_string_empty(new_name))
            return false;
        
        if (SavedSearchTable.get_instance().exists(new_name))
            return false;
        
        try {
            SavedSearchDBTable.get_instance().rename(row.search_id, new_name);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
            return false;
        }
        
        SavedSearchTable.get_instance().remove_from_map(this);
        row.name = new_name;
        SavedSearchTable.get_instance().add_to_map(this);
        
        LibraryWindow.get_app().switch_to_saved_search(this);
        return true;
    }
}

// This table contains every saved search.  It's the prefered way to add and destroy a saved 
// search as well, since this table's create/destroy methods are tied to the database.
public class SavedSearchTable {
    private static SavedSearchTable? instance = null;
    private Gee.HashMap<string, SavedSearch> search_map = new Gee.HashMap<string, SavedSearch>();

    public signal void search_added(SavedSearch search);
    public signal void search_removed(SavedSearch search);
    
    private SavedSearchTable() {
        // Load existing searches from DB.
        try {
            foreach(SavedSearchRow row in SavedSearchDBTable.get_instance().get_all_rows())
                add_to_map(new SavedSearch(row));
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
    }
    
    public static SavedSearchTable get_instance() {
        if (instance == null)
            instance = new SavedSearchTable();
        
        return instance;
    }
    
    public Gee.Collection<SavedSearch> get_all() {
        return search_map.values;
    }
    
    // Creates a saved search with the given name, operator, and conditions.  The saved search is
    // added to the database and to this table.
    public SavedSearch create(string name, SearchOperator operator, 
        Gee.ArrayList<SearchCondition> conditions) {
        SavedSearch? search = null;
        // Create a new SavedSearch in the database.
        try {
            search = new SavedSearch(SavedSearchDBTable.get_instance().add(name, operator, conditions));
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // Add search to table.
        add_to_map(search);
        LibraryWindow.get_app().switch_to_saved_search(search);
        return search;
    }
    
    // Removes a saved search, both from here and from the table.
    public void remove(SavedSearch search) {
        try {
            SavedSearchDBTable.get_instance().remove(search.get_saved_search_id());
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        remove_from_map(search);
    }
    
    public void add_to_map(SavedSearch search) {
        search_map.set(search.get_name(), search);
        search_added(search);
    }
    
    public void remove_from_map(SavedSearch search) {
        search_map.unset(search.get_name());
        search_removed(search);
    }
    
    public Gee.Iterable<SavedSearch> get_saved_searches() {
        return search_map.values;
    }
    
    public int get_count() {
        return search_map.size;
    }
    
    public bool exists(string search_name) {
        return search_map.has_key(search_name);
    }
}
