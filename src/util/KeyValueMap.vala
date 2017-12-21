/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class KeyValueMap {
    private string group;
    private Gee.HashMap<string, string> map = new Gee.HashMap<string, string>();
    
    public KeyValueMap(string group) {
        this.group = group;
    }
    
    public KeyValueMap copy() {
        KeyValueMap clone = new KeyValueMap(group);
        foreach (string key in map.keys)
            clone.map.set(key, map.get(key));
        
        return clone;
    }
    
    public string get_group() {
        return group;
    }
    
    public Gee.Set<string> get_keys() {
        return map.keys;
    }
    
    public bool has_key(string key) {
        return map.has_key(key);
    }
    
    public void set_string(string key, string value) {
        assert(key != null);
        
        map.set(key, value);
    }
    
    public void set_int(string key, int value) {
        assert(key != null);
        
        map.set(key, value.to_string());
    }
    
    public void set_double(string key, double value) {
        assert(key != null);
        
        map.set(key, value.to_string());
    }
    
    public void set_float(string key, float value) {
        assert(key != null);
        
        map.set(key, value.to_string());
    }

    public void set_bool(string key, bool value) {
        assert(key != null);
        
        map.set(key, value.to_string());
    }

    public string get_string(string key, string? def) {
        string value = map.get(key);
        
        return (value != null) ? value : def;
    }
    
    public int get_int(string key, int def) {
        string value = map.get(key);
        
        return (value != null) ? int.parse(value) : def;
    }
    
    public double get_double(string key, double def) {
        string value = map.get(key);
        
        return (value != null) ? double.parse(value) : def;
    }
    
    public float get_float(string key, float def) {
        string value = map.get(key);
        
        return (value != null) ? (float) double.parse(value) : def;
    }

    public bool get_bool(string key, bool def) {
        string value = map.get(key);
        
        return (value != null) ? bool.parse(value) : def;
    }
    
    // REDEYE: redeye reduction operates on circular regions defined by
    //         (Gdk.Point, int) pairs, where the Gdk.Point specifies the
    //         bounding circle's center and the the int specifies the circle's
    //         radius so, get_point( ) and set_point( ) functions have been
    //         added here to easily encode/decode Gdk.Points as strings.
    public Gdk.Point get_point(string key, Gdk.Point def) {
        string value = map.get(key);
        
        if (value == null) {
            return def;
        } else {
            Gdk.Point result = {0};
            if (value.scanf("(%d, %d)", &result.x, &result.y) == 2)
                return result;
            else
                return def;
        }
    }

    public void set_point(string key, Gdk.Point point) {
        map.set(key, "(%d, %d)".printf(point.x, point.y));
    }
}

