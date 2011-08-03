/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class HierarchicalTagIndex {
    private Gee.Map<string, Gee.Collection<string>> tag_table;
    private Gee.SortedSet<string> known_paths;
    
    public HierarchicalTagIndex( ) {
        this.tag_table = new Gee.HashMap<string, Gee.ArrayList<string>>();
        this.known_paths = new Gee.TreeSet<string>();
    }

    public void add_path(string tag, string path) {
        if (!tag_table.has_key(tag)) {
            tag_table.set(tag, new Gee.ArrayList<string>());
        }
        
        tag_table.get(tag).add(path);
        known_paths.add(path);
    }
    
    public Gee.Collection<string> get_all_paths() {
        return known_paths;
    }
    
    public bool is_tag_in_index(string tag) {
        return tag_table.has_key(tag);
    }
    
    public Gee.Collection<string> get_all_tags() {
        return tag_table.keys;
    }
    
    public bool is_path_known(string path) {
        return known_paths.contains(path);
    }
}

