/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// For specifying whether a search should be ORed (any) or ANDed (all).
public enum SearchOperator {
    ANY = 0,
    ALL,
    NONE;
    
    public string to_string() {
        switch (this) {
            case SearchOperator.ANY:
                return "ANY";
            
            case SearchOperator.ALL:
                return "ALL";
            
            case SearchOperator.NONE:
                return "NONE";
            
            default:
                error("unrecognized search operator enumeration value");
        }
    }
    
    public static SearchOperator from_string(string str) {
        if (str == "ANY")
            return SearchOperator.ANY;
        
        else if (str == "ALL")
            return SearchOperator.ALL;
        
        else if (str == "NONE")
            return SearchOperator.NONE;
        
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
        FILE_NAME,
#if ENABLE_FACES   
        FACE,
#endif
        MEDIA_TYPE,
        FLAG_STATE,
        MODIFIED_STATE,
        RATING,
        COMMENT,
        DATE;
        // Note: when adding new types, be sure to update all functions below.
        
        public static SearchType[] as_array() {
            return { ANY_TEXT, TITLE, TAG, COMMENT, EVENT_NAME, FILE_NAME, 
#if ENABLE_FACES   
            FACE, 
#endif
            MEDIA_TYPE, FLAG_STATE, MODIFIED_STATE, RATING, DATE };
        }
        
        // Sorts an array alphabetically by display name.
        public static void sort_array(ref SearchType[] array) {
            Posix.qsort(array, array.length, sizeof(SearchType), (a, b) => {
                return utf8_cs_compare(((*(SearchType*) a)).display_text(), 
                    ((*(SearchType*) b)).display_text());
            });
        }
        
        public string to_string() {
            switch (this) {
                case SearchType.ANY_TEXT:
                    return "ANY_TEXT";
                
                case SearchType.TITLE:
                    return "TITLE";
                
                case SearchType.TAG:
                    return "TAG";

                case SearchType.COMMENT:
                    return "COMMENT";
                
                case SearchType.EVENT_NAME:
                    return "EVENT_NAME";
                
                case SearchType.FILE_NAME:
                    return "FILE_NAME";
#if ENABLE_FACES                   
                case SearchType.FACE:
                    return "FACE";
#endif                
                case SearchType.MEDIA_TYPE:
                    return "MEDIA_TYPE";
                
                case SearchType.FLAG_STATE:
                    return "FLAG_STATE";
                
                case SearchType.MODIFIED_STATE:
                    return "MODIFIED_STATE";
                
                case SearchType.RATING:
                    return "RATING";
                
                case SearchType.DATE:
                    return "DATE";
                
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

            else if (str == "COMMENT")
                return SearchType.COMMENT;
            
            else if (str == "EVENT_NAME")
                return SearchType.EVENT_NAME;
            
            else if (str == "FILE_NAME")
                return SearchType.FILE_NAME;
#if ENABLE_FACES               
            else if (str == "FACE")
                return SearchType.FACE;
#endif            
            else if (str == "MEDIA_TYPE")
                return SearchType.MEDIA_TYPE;
            
            else if (str == "FLAG_STATE")
                return SearchType.FLAG_STATE;
            
            else if (str == "MODIFIED_STATE")
                return SearchType.MODIFIED_STATE;
            
            else if (str == "RATING")
                return SearchType.RATING;
            
            else if (str == "DATE")
                return SearchType.DATE;
            
            else
                error("unrecognized search type name: %s", str);
        }
        
        public string display_text() {
            switch (this) {
                case SearchType.ANY_TEXT:
                    return _("Any text");
                
                case SearchType.TITLE:
                    return _("Title");
                
                case SearchType.TAG:
                    return _("Tag");
                
                case SearchType.COMMENT:
                    return _("Comment");

                case SearchType.EVENT_NAME:
                    return _("Event name");
                
                case SearchType.FILE_NAME:
                    return _("File name");
#if ENABLE_FACES                   
                case SearchType.FACE:
                    return _("Face");
#endif                
                case SearchType.MEDIA_TYPE:
                    return _("Media type");
                
                case SearchType.FLAG_STATE:
                    return _("Flag state");
                
                case SearchType.MODIFIED_STATE:
                    return _("Photo state");
                
                case SearchType.RATING:
                    return _("Rating");
                
                case SearchType.DATE:
                    return _("Date");
                
                default:
                    error("unrecognized search type enumeration value");
            }
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
        IS_NOT_SET,
        IS_SET;
        
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
                
                case Context.IS_SET:
                    return "IS_SET";
                
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
            
            else if (str == "IS_SET")
                return Context.IS_SET;
            
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
        this.text = (text != null) ? String.remove_diacritics(text.down()) : "";
        this.context = context;
    }
    
    // Match string by context.
    private bool string_match(string needle, string? haystack) {
        switch (context) {
            case Context.CONTAINS:
            case Context.DOES_NOT_CONTAIN:
                return !is_string_empty(haystack) && haystack.contains(needle);

            case Context.IS_EXACTLY:
                return !is_string_empty(haystack) && haystack == needle;
                
            case Context.STARTS_WITH:
                return !is_string_empty(haystack) && haystack.has_prefix(needle);
                
            case Context.ENDS_WITH:
                return !is_string_empty(haystack) && haystack.has_suffix(needle);

            case Context.IS_NOT_SET:
                return (is_string_empty(haystack));
            
            case Context.IS_SET:
                return (!is_string_empty(haystack));
        }
        
        return false;
    }
    
    // Determines whether the source is included.
    public override bool predicate(MediaSource source) {
        bool ret = false;
        
        // title
        if (SearchType.ANY_TEXT == search_type || SearchType.TITLE == search_type) {
            string? title = (null != source.get_title()) ?
                String.remove_diacritics(source.get_title().down()) : null;
            ret |= string_match(text, title);
        }
        
        // tags
        if (SearchType.ANY_TEXT == search_type || SearchType.TAG == search_type) {
            Gee.List<Tag>? tag_list = Tag.global.fetch_for_source(source);
            if (null != tag_list) {
                string itag;
                foreach (Tag tag in tag_list) {
                    itag = tag.get_searchable_name().down(); // get_searchable already remove diacritics
                    ret |= string_match(text, itag);
                }
            } else {
                ret |= string_match(text, null); // for IS_NOT_SET
            }
        }
        
        // event name
        if (SearchType.ANY_TEXT == search_type || SearchType.EVENT_NAME == search_type) {
            string? event_name = (null != source.get_event()) ? 
                String.remove_diacritics(source.get_event().get_name().down()) : null;
            ret |= string_match(text, event_name);
        }

        // comment
        if (SearchType.ANY_TEXT == search_type || SearchType.COMMENT == search_type) {
            string? comment = source.get_comment();
            if(null != comment)
                ret |= string_match(text, String.remove_diacritics(comment.down()));
        }
        
        // file name
        if (SearchType.ANY_TEXT == search_type || SearchType.FILE_NAME == search_type) {
            ret |= string_match(text, String.remove_diacritics(source.get_basename().down()));
        }

#if ENABLE_FACES
        if (SearchType.ANY_TEXT == search_type || SearchType.FACE == search_type) {
            Gee.List<Face>? face_list = Face.global.fetch_for_source(source);
            if (null != face_list) {
                foreach (Face face in face_list) {
                    ret |= string_match(text, face.get_name().down());
                }
            } else {
                ret |= string_match(text, null); // for IS_NOT_SET
            }
        }
#endif

        return (context == Context.DOES_NOT_CONTAIN) ? !ret : ret;
    }
}

// Condition for media type matching.
public class SearchConditionMediaType : SearchCondition {
    public enum Context {
        IS = 0,
        IS_NOT;
        
        public string to_string() {
            switch (this) {
                case Context.IS:
                    return "IS";
                
                case Context.IS_NOT:
                    return "IS_NOT";
                
                default:
                    error("unrecognized media search context enumeration value");
            }
        }
        
        public static Context from_string(string str) {
            if (str == "IS")
                return Context.IS;
            
            else if (str == "IS_NOT")
                return Context.IS_NOT;
            
            else
                error("unrecognized media search context name: %s", str);
        }
    }
    
    public enum MediaType {
        PHOTO_ALL = 0,
        PHOTO_RAW,
        VIDEO;
        
        public string to_string() {
            switch (this) {
                case MediaType.PHOTO_ALL:
                    return "PHOTO_ALL";
                
                case MediaType.PHOTO_RAW:
                    return "PHOTO_RAW";
                
                case MediaType.VIDEO:
                    return "VIDEO";
                
                default:
                    error("unrecognized media search type enumeration value");
            }
        }
        
        public static MediaType from_string(string str) {
            if (str == "PHOTO_ALL")
                return MediaType.PHOTO_ALL;
            
            else if (str == "PHOTO_RAW")
                return MediaType.PHOTO_RAW;
            
            else if (str == "VIDEO")
                return MediaType.VIDEO;
            
            else
                error("unrecognized media search type name: %s", str);
        }
    }
    
    // What to search for.
    public MediaType media_type { get; private set; }
    
    // How to match.
    public Context context { get; private set; }
    
    public SearchConditionMediaType(SearchCondition.SearchType search_type, Context context, MediaType media_type) {
        this.search_type = search_type;
        this.context = context;
        this.media_type = media_type;
    }
    
    // Determines whether the source is included.
    public override bool predicate(MediaSource source) {
        // For the given type, check it against the MediaSource type
        // and the given search context.
        switch (media_type) {
            case MediaType.PHOTO_ALL:
                if (source is Photo)
                    return context == Context.IS;
                else
                    return context == Context.IS_NOT;
                    
            case MediaType.PHOTO_RAW:
                if (source is Photo && ((Photo) source).get_master_file_format() == PhotoFileFormat.RAW)
                    return context == Context.IS;
                else
                    return context == Context.IS_NOT;
                    
            case MediaType.VIDEO:
                if (source is VideoSource)
                    return context == Context.IS;
                else
                    return context == Context.IS_NOT;
                    
            default:
                    error("unrecognized media search type enumeration value");
        }
    }
}

// Condition for flag state matching.
public class SearchConditionFlagged : SearchCondition {
    public enum State {
        FLAGGED = 0,
        UNFLAGGED;
        
        public string to_string() {
            switch (this) {
                case State.FLAGGED:
                    return "FLAGGED";
                
                case State.UNFLAGGED:
                    return "UNFLAGGED";
                
                default:
                    error("unrecognized flagged search state enumeration value");
            }
        }
        
        public static State from_string(string str) {
            if (str == "FLAGGED")
                return State.FLAGGED;
            
            else if (str == "UNFLAGGED")
                return State.UNFLAGGED;
            
            else
                error("unrecognized flagged search state name: %s", str);
        }
    }
    
    // What to match.
    public State state { get; private set; }
    
    public SearchConditionFlagged(SearchCondition.SearchType search_type, State state) {
        this.search_type = search_type;
        this.state = state;
    }
    
    // Determines whether the source is included.
    public override bool predicate(MediaSource source) {
        if (state == State.FLAGGED) {
            return ((Flaggable) source).is_flagged();
        } else if (state == State.UNFLAGGED) {
            return !((Flaggable) source).is_flagged();
        } else {
            error("unrecognized flagged search state");
        }
    }
}

// Condition for modified state matching.
public class SearchConditionModified : SearchCondition {

    public enum Context {
        HAS = 0,
        HAS_NO;
        
        public string to_string() {
            switch (this) {
                case Context.HAS:
                    return "HAS";
                
                case Context.HAS_NO:
                    return "HAS_NO";
                
                default:
                    error("unrecognized modified search context enumeration value");
            }
        }
        
        public static Context from_string(string str) {
            if (str == "HAS")
                return Context.HAS;
            
            else if (str == "HAS_NO")
                return Context.HAS_NO;
            
            else
                error("unrecognized modified search context name: %s", str);
        }
    }
    
    public enum State {
        MODIFIED = 0,
        INTERNAL_CHANGES,
        EXTERNAL_CHANGES;
        
        public string to_string() {
            switch (this) {
                case State.MODIFIED:
                    return "MODIFIED";
                
                case State.INTERNAL_CHANGES:
                    return "INTERNAL_CHANGES";
                    
                 case State.EXTERNAL_CHANGES:
                    return "EXTERNAL_CHANGES";
                
                default:
                    error("unrecognized modified search state enumeration value");
            }
        }
        
        public static State from_string(string str) {
            if (str == "MODIFIED")
                return State.MODIFIED;
            
            else if (str == "INTERNAL_CHANGES")
                return State.INTERNAL_CHANGES;
                
            else if (str == "EXTERNAL_CHANGES")
                return State.EXTERNAL_CHANGES;
            
            else
                error("unrecognized modified search state name: %s", str);
        }
    }

    // What to match.
    public State state { get; private set; }

    // How to match.
    public Context context { get; private set; }

    public SearchConditionModified(SearchCondition.SearchType search_type, Context context, State state) {
        this.search_type = search_type;
        this.context = context;
        this.state = state;
    }
    
    // Determines whether the source is included.
    public override bool predicate(MediaSource source) {
        // check against state and the given search context.
        Photo? photo = source as Photo;
        if (photo == null)
            return false;
        
        bool match;
        if (state == State.MODIFIED)
            match = photo.has_transformations() || photo.has_editable();
        else if (state == State.INTERNAL_CHANGES)
            match = photo.has_transformations();
        else if (state == State.EXTERNAL_CHANGES)
            match = photo.has_editable();
        else
            error("unrecognized modified search state");

        if (match)
            return context == Context.HAS;
        else
            return context == Context.HAS_NO;
    }
}


// Condition for rating matching.
public class SearchConditionRating : SearchCondition {
    public enum Context {
        AND_HIGHER = 0,
        ONLY,
        AND_LOWER;
        
        public string to_string() {
            switch (this) {
                case Context.AND_HIGHER:
                    return "AND_HIGHER";
                
                case Context.ONLY:
                    return "ONLY";
                
                case Context.AND_LOWER:
                    return "AND_LOWER";
                
                default:
                    error("unrecognized rating search context enumeration value");
            }
        }
        
        public static Context from_string(string str) {
            if (str == "AND_HIGHER")
                return Context.AND_HIGHER;
            
            else if (str == "ONLY")
                return Context.ONLY;
            
            else if (str == "AND_LOWER")
                return Context.AND_LOWER;
            
            else
                error("unrecognized rating search context name: %s", str);
        }
    }
    
    // Rating to check against.
    public Rating rating { get; private set; }
    
    // How to match.
    public Context context { get; private set; }
    
    public SearchConditionRating(SearchCondition.SearchType search_type, Rating rating, Context context) {
        this.search_type = search_type;
        this.rating = rating;
        this.context = context;
    }
    
    // Determines whether the source is included.
    public override bool predicate(MediaSource source) {
        Rating source_rating = source.get_rating();
        if (context == Context.AND_HIGHER)
            return source_rating >= rating;
        else if (context == Context.ONLY)
            return source_rating == rating;
        else if (context == Context.AND_LOWER)
            return source_rating <= rating;
        else
            error("unknown rating search context");
    }
}


// Condition for date range.
public class SearchConditionDate : SearchCondition {
    public enum Context {
        EXACT = 0,
        AFTER,
        BEFORE,
        BETWEEN,
        IS_NOT_SET;
        
        public string to_string() {
            switch (this) {
                case Context.EXACT:
                    return "EXACT";
                
                case Context.AFTER:
                    return "AFTER";
                
                case Context.BEFORE:
                    return "BEFORE";
                
                case Context.BETWEEN:
                    return "BETWEEN";
                    
                case Context.IS_NOT_SET:
                    return "IS_NOT_SET";
                
                default:
                    error("unrecognized date search context enumeration value");
            }
        }
        
        public static Context from_string(string str) {
            if (str == "EXACT")
                return Context.EXACT;
            
            if (str == "AFTER")
                return Context.AFTER;
            
            else if (str == "BEFORE")
                return Context.BEFORE;
            
            else if (str == "BETWEEN")
                return Context.BETWEEN;
            
            else if (str == "IS_NOT_SET")
                return Context.IS_NOT_SET;
            
            else
                error("unrecognized date search context name: %s", str);
        }
    }
    
    // Date to check against.  Second date only used for between searches.
    public DateTime date_one { get; private set; }
    public DateTime date_two { get; private set; }
    
    // How to match.
    public Context context { get; private set; }
    
    public SearchConditionDate(SearchCondition.SearchType search_type, Context context, 
        DateTime date_one, DateTime date_two) {
        this.search_type = search_type;
        this.context = context;
        if (context != Context.BETWEEN || date_two.compare(date_one) >= 1) {
            this.date_one = date_one;
            this.date_two = date_two;
        } else {
            this.date_one = date_two;
            this.date_two = date_one;
        }
       
    }
    
    // Determines whether the source is included.
    public override bool predicate(MediaSource source) {
        time_t exposure_time = source.get_exposure_time();
        if (exposure_time == 0)
            return context == Context.IS_NOT_SET;
        
        DateTime dt = new DateTime.from_unix_local(exposure_time);
        switch (context) {
            case Context.EXACT:
                DateTime second = date_one.add_days(1);
                return (dt.compare(date_one) >= 0 && dt.compare(second) < 0);
            
            case Context.AFTER:
                return (dt.compare(date_one) >= 0);
            
            case Context.BEFORE:
                return (dt.compare(date_one) <= 0);
            
            case Context.BETWEEN:
                DateTime second = date_two.add_days(1);
                return (dt.compare(date_one) >= 0 && dt.compare(second) < 0);
            
            case Context.IS_NOT_SET:
                return false; // Already checked above.
            
            default:
                error("unrecognized date search context enumeration value");
        }
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
        if (SearchOperator.ALL == row.operator || SearchOperator.NONE == row.operator)
            ret = true;
        else
            ret = false; // assumes conditions.size() > 0
        
        foreach (SearchCondition c in row.conditions) {
            if (SearchOperator.ALL == row.operator)
                ret &= c.predicate(source);
            else if (SearchOperator.ANY == row.operator)
                ret |= c.predicate(source);
            else if (SearchOperator.NONE == row.operator)
                ret &= !c.predicate(source);
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
    
    public Gee.List<SearchCondition> get_conditions() {
        return row.conditions.read_only_view;
    }
    
    public SearchOperator get_operator() {
        return row.operator;
    }
}

// This table contains every saved search.  It's the preferred way to add and destroy a saved 
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
    
    // Generate a unique search name (not thread safe)
    public string generate_unique_name() {
        for (int ctr = 1; ctr < int.MAX; ctr++) {
            string name = "%s %d".printf(Resources.DEFAULT_SAVED_SEARCH_NAME, ctr);
            
            if (!exists(name))
                return name;
        }
        return ""; // If all names are used (unlikely!)
    }
}
