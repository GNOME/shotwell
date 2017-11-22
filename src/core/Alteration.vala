/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

//
// Alteration represents a description of what has changed in the DataObject (reported via the
// "altered" signal).  Since the descriptions can vary wildly depending on the semantics of each
// DataObject, no assumptions or requirements are placed on Alteration other than it must have
// one or more "subjects", each with a "detail".  Subscribers to the "altered" signal can query
// the Alteration object to determine if the change is important to them.
//
// Alteration is an immutable type.  This means it's possible to store const Alterations of oft-used
// values for reuse.
//
// Alterations may be compressed, merging their subjects and details into a new aggregated
// Alteration.  Generally this is handled automatically by DataObject and DataCollection, when
// necessary.
//
// NOTE: subjects and details should be ASCII labels (as in, plain-old ASCII, no code pages).
// They are treated as case-sensitive strings.
//
// Recommended subjects include: image, thumbnail, metadata.
//

public class Alteration {
    private string subject = null;
    private string detail = null;
    private Gee.MultiMap<string, string> map = null;
    
    public Alteration(string subject, string detail) {
        add_detail(subject, detail);
    }
    
    // Create an Alteration that has more than one subject/detail.  list is a comma-delimited
    // string of colon-separated subject:detail pairs.
    public Alteration.from_list(string list) requires (list.length > 0) {
        string[] pairs = list.split(",");
        assert(pairs.length >= 1);
        
        foreach (string pair in pairs) {
            string[] subject_detail = pair.split(":", 2);
            assert(subject_detail.length == 2);
            
            add_detail(subject_detail[0], subject_detail[1]);
        }
    }
    
    // Create an Alteration that has more than one subject/detail from an array of comma-delimited
    // strings of colon-separate subject:detail pairs
    public Alteration.from_array(string[] array) requires (array.length > 0) {
        foreach (string pair in array) {
            string[] subject_detail = pair.split(":", 2);
            assert(subject_detail.length == 2);
            
            add_detail(subject_detail[0], subject_detail[1]);
        }
    }
    
    // Used for compression.
    private Alteration.from_map(Gee.MultiMap<string, string> map) {
        this.map = map;
    }
    
    private void add_detail(string sub, string det) {
        // strip leading and trailing whitespace
        string subject = sub.strip();
        assert(subject.length > 0);
        
        string detail = det.strip();
        assert(detail.length > 0);
        
        // if a simple Alteration, store in singleton refs
        if (this.subject == null && map == null) {
            assert(this.detail == null);
            
            this.subject = subject;
            this.detail = detail;
            
            return;
        }
        
        // Now a complex Alteration, requiring a Map.
        if (map == null)
            map = create_map();
        
        // Move singletons into Map
        if (this.subject != null) {
            assert(this.detail != null);
            
            map.set(this.subject, this.detail);
            this.subject = null;
            this.detail = null;
        }
        
        // Store new subject:detail in Map as well
        map.set(subject, detail);
    }
    
    private Gee.MultiMap<string, string> create_map() {
        return new Gee.HashMultiMap<string, string>(case_hash, case_equal, case_hash, case_equal);
    }
    
    private static bool case_equal(string? a, string? b) {
        return equal_values(a, b);
    }
    
    private static uint case_hash(string? a) {
        return hash_value(a);
    }
    
    private static inline bool equal_values(string str1, string str2) {
        return str1.ascii_casecmp(str2) == 0;
    }
    
    private static inline uint hash_value(string str) {
        return str_hash(str);
    }
    
    public bool has_subject(string subject) {
        if (this.subject != null)
            return equal_values(this.subject, subject);
        
        assert(map != null);
        Gee.Set<string>? keys = map.get_keys();
            if (keys != null) {
                foreach (string key in keys) {
                    if (equal_values(key, subject))
                        return true;
            }
        }
        
        return false;
    }
    
    public bool has_detail(string subject, string detail) {
        if (this.subject != null && this.detail != null)
            return equal_values(this.subject, subject) && equal_values(this.detail, detail);
        
        assert(map != null);
        Gee.Collection<string>? values = map.get(subject);
        if (values != null) {
            foreach (string value in values) {
                if (equal_values(value, detail))
                    return true;
            }
        }
        
        return false;
    }
    
    public Gee.Collection<string>? get_details(string subject) {
        if (this.subject != null && detail != null && equal_values(this.subject, subject)) {
            Gee.ArrayList<string> details = new Gee.ArrayList<string>();
            details.add(detail);
            
            return details;
        }
        
        return (map != null) ? map.get(subject) : null;
    }
    
    public string to_string() {
        if (subject != null) {
            assert(detail != null);
            
            return "%s:%s".printf(subject, detail);
        }
        
        assert(map != null);
        
        string str = "";
        foreach (string key in map.get_keys()) {
            foreach (string value in map.get(key)) {
                if (str.length != 0)
                    str += ", ";
                
                str += "%s:%s".printf(key, value);
            }
        }
        
        return str;
    }
    
    // Returns true if this object has any subject:detail matches with the supplied Alteration.
    public bool contains_any(Alteration other) {
        // identity
        if (this == other)
            return true;
        
        // if both singletons, check for singleton match
        if (subject != null && other.subject != null && detail != null && other.detail != null)
            return equal_values(subject, other.subject) && equal_values(detail, other.detail);
        
        // if one is singleton and the other a multiple, search for singleton in multiple
        if ((map != null && other.map == null) || (map == null && other.map != null)) {
            string single_subject = subject != null ? subject : other.subject;
            string single_detail = detail != null ? detail : other.detail;
            Gee.MultiMap<string, string> multimap = map != null ? map : other.map;
            
            return multimap.contains(single_subject) && map.get(single_subject).contains(single_detail);
        }
        
        // if both multiples, check for any match at all
        if (map != null && other.map != null) {
            Gee.Set<string>? keys = map.get_keys();
            assert(keys != null);
            Gee.Set<string>? other_keys = other.map.get_keys();
            assert(other_keys != null);
            
            foreach (string subject in other_keys) {
                if (!keys.contains(subject))
                    continue;
                
                Gee.Collection<string>? details = map.get(subject);
                Gee.Collection<string>? other_details = other.map.get(subject);
                
                if (details != null && other_details != null) {
                    foreach (string detail in other_details) {
                        if (details.contains(detail))
                            return true;
                    }
                }
            }
        }
        
        return false;
    }
    
    public bool equals(Alteration other) {
        // identity
        if (this == other)
            return true;
        
        // if both singletons, check for singleton match
        if (subject != null && other.subject != null && detail != null && other.detail != null)
            return equal_values(subject, other.subject) && equal_values(detail, other.detail);
        
        // if both multiples, check for across-the-board matches
        if (map != null && other.map != null) {
            // see if both maps contain the same set of keys
            Gee.Set<string>? keys = map.get_keys();
            assert(keys != null);
            Gee.Set<string>? other_keys = other.map.get_keys();
            assert(other_keys != null);
            
            if (keys.size != other_keys.size)
                return false;
            
            if (!keys.contains_all(other_keys))
                return false;
            
            if (!other_keys.contains_all(keys))
                return false;
            
            foreach (string key in keys) {
                Gee.Collection<string> values = map.get(key);
                Gee.Collection<string> other_values = other.map.get(key);
                
                if (values.size != other_values.size)
                    return false;
                
                if (!values.contains_all(other_values))
                    return false;
                
                if (!other_values.contains_all(values))
                    return false;
            }
            
            // maps are identical
            return true;
        }
        
        // one singleton and one multiple, not equal
        return false;
    }
    
    private static void multimap_add_all(Gee.MultiMap<string, string> dest,
        Gee.MultiMap<string, string> src) {
        Gee.Set<string> keys = src.get_keys();
        foreach (string key in keys) {
            Gee.Collection<string> values = src.get(key);
            foreach (string value in values)
                dest.set(key, value);
        }
    }
    
    // This merges the Alterations, returning a new Alteration with both represented.  If both
    // Alterations are equal, this will return this object rather than create a new one.
    public Alteration compress(Alteration other) {
        if (equals(other))
            return this;
        
        // Build a new Alteration with both represented ... if they're unequal, then the new one
        // is guaranteed not to be a singleton
        Gee.MultiMap<string, string> compressed = create_map();
        
        if (subject != null && detail != null) {
            compressed.set(subject, detail);
        } else {
            assert(map != null);
            multimap_add_all(compressed, map);
        }
        
        if (other.subject != null && other.detail != null) {
            compressed.set(other.subject, other.detail);
        } else {
            assert(other.map != null);
            multimap_add_all(compressed, other.map);
        }
        
        return new Alteration.from_map(compressed);
    }
}

