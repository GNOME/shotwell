
public uint int64_hash(void *p) {
    // Rotating XOR hash
    uint8 *u8 = (uint8 *) p;
    uint hash = 0;
    for (int ctr = 0; ctr < (sizeof(int64) / sizeof(uint8)); ctr++) {
        hash = (hash << 4) ^ (hash >> 28) ^ (*u8++);
    }
    
    return hash;
}

public bool int64_equal(void *a, void *b) {
    int64 *bia = (int64 *) a;
    int64 *bib = (int64 *) b;
    
    return (*bia) == (*bib);
}

public uint file_hash(void *key) {
    File *file = (File *) key;
    
    return str_hash(file->get_path());
}

public bool file_equal(void *a, void *b) {
    File *afile = (File *) a;
    File *bfile = (File *) b;
    
    return afile->get_path() == bfile->get_path();
}

public class KeyValueMap {
    private string group;
    private Gee.HashMap<string, string> map = new Gee.HashMap<string, string>(str_hash, str_equal,
        str_equal);
    
    public KeyValueMap(string group) {
        this.group = group;
    }
    
    public string get_group() {
        return group;
    }
    
    public Gee.Set<string> get_keys() {
        return map.get_keys();
    }
    
    public bool has_key(string key) {
        return map.contains(key);
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
    
    public string get_string(string key, string? def) {
        string value = map.get(key);
        
        return (value != null) ? value : def;
    }
    
    public int get_int(string key, int def) {
        string value = map.get(key);
        
        return (value != null) ? value.to_int() : def;
    }
    
    public double get_double(string key, double def) {
        string value = map.get(key);
        
        return (value != null) ? value.to_double() : def;
    }
}

// Returns false if Gtk.quit() was called
public bool spin_event_loop() {
    while (Gtk.events_pending()) {
        if (Gtk.main_iteration())
            return false;
    }
    
    return true;
}

public long find_last_offset(string str, char c) {
    long offset = str.length;
    while (--offset >= 0) {
        if (str[offset] == c)
            return offset;
    }
    
    return -1;
}

public void disassemble_filename(string basename, out string name, out string ext) {
    long offset = find_last_offset(basename, '.');
    if (offset <= 0) {
        name = basename;
        ext = null;
    } else {
        name = basename.substring(0, offset);
        ext = basename.substring(offset + 1, -1);
    }
}

public enum AdjustmentRelation {
    BELOW,
    IN_RANGE,
    ABOVE
}

public AdjustmentRelation get_adjustment_relation(Gtk.Adjustment adjustment, int value) {
    if (value < (int) adjustment.get_value())
        return AdjustmentRelation.BELOW;
    else if (value > (int) (adjustment.get_value() + adjustment.get_page_size()))
        return AdjustmentRelation.ABOVE;
    else
        return AdjustmentRelation.IN_RANGE;
}

public enum CompassPoint {
    NORTH,
    SOUTH,
    EAST,
    WEST
}
