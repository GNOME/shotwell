/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

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

public ulong timeval_to_ms(TimeVal time_val) {
    return (((ulong) time_val.tv_sec) * 1000) + (((ulong) time_val.tv_usec) / 1000);
}

public ulong now_ms() {
    return timeval_to_ms(TimeVal());
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
        
        return (value != null) ? value.to_int() : def;
    }
    
    public double get_double(string key, double def) {
        string value = map.get(key);
        
        return (value != null) ? value.to_double() : def;
    }

    public bool get_bool(string key, bool def) {
        string value = map.get(key);
        
        return (value != null) ? value.to_bool() : def;
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

public Gdk.Rectangle get_adjustment_page(Gtk.Adjustment hadj, Gtk.Adjustment vadj) {
    Gdk.Rectangle rect = Gdk.Rectangle();
    rect.x = (int) hadj.get_value();
    rect.y = (int) vadj.get_value();
    rect.width = (int) hadj.get_page_size();
    rect.height = (int) vadj.get_page_size();
    
    return rect;
}

public bool rectangles_equal(Gdk.Rectangle a, Gdk.Rectangle b) {
    return (a.x == b.x) && (a.y == b.y) && (a.width == b.width) && (a.height == b.height);
}

public string rectangle_to_string(Gdk.Rectangle rect) {
    return "%dx%d %d,%d".printf(rect.x, rect.y, rect.width, rect.height);
}

public enum CompassPoint {
    NORTH,
    SOUTH,
    EAST,
    WEST
}

public uint64 query_total_file_size(File file_or_dir) throws Error {
    spin_event_loop();

    FileType type = file_or_dir.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    if (type == FileType.REGULAR) {
        FileInfo info = null;
        try {
            info = file_or_dir.query_info(FILE_ATTRIBUTE_STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            debug("Unable to query filesize for %s: %s", file_or_dir.get_path(), err.message);

            return 0;
        }
        
        return info.get_size();
    } else if (type != FileType.DIRECTORY) {
        return 0;
    }
        
    FileEnumerator enumerator = file_or_dir.enumerate_children("*",
        FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    if (enumerator == null)
        return 0;
    
    uint64 total_bytes = 0;
        
    FileInfo info = null;
    while ((info = enumerator.next_file(null)) != null)
        total_bytes += query_total_file_size(file_or_dir.get_child(info.get_name()));
    
    return total_bytes;
}

public time_t query_file_modified(File file) throws Error {
    FileInfo info = file.query_info(FILE_ATTRIBUTE_TIME_MODIFIED, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, 
        null);

    TimeVal timestamp = TimeVal();
    info.get_modification_time(out timestamp);
    
    return timestamp.tv_sec;
}

public bool query_is_directory_empty(File dir) throws Error {
    if (dir.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null) != FileType.DIRECTORY)
        return false;
    
    FileEnumerator enumerator = dir.enumerate_children("*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    if (enumerator == null)
        return false;
    
    return enumerator.next_file(null) == null;
}

public string get_display_pathname(File file) {
    // attempt to replace home path with tilde in a user-pleasable way
    string path = file.get_parse_name();
    string home = Environment.get_home_dir();

    if (path == home)
        return "~";
    
    if (path.has_prefix(home))
        return "~%s".printf(path.substring(home.length));

    return path;
}

public string format_local_date(Time date) {
    string date_string = date.format(_("%a %b %d, %Y"));
    StringBuilder date_string_stripped = new StringBuilder("");
    bool pre_is_space = true;
    for (int i = 0; i < date_string.length; i++) {
        if (pre_is_space && (date_string[i] == '0')) {
            pre_is_space = false;
        } else {
            date_string_stripped.append_unichar(date_string[i]);
            pre_is_space = date_string[i].isspace();
        }
    }
    return date_string_stripped.str;
}

public delegate void OneShotCallback();

public class OneShotScheduler {
    private OneShotCallback callback;
    private bool scheduled = false;
    private bool reschedule = false;
    private bool cancelled = false;
    
    public OneShotScheduler(OneShotCallback callback) {
        this.callback = callback;
    }
    
    public bool is_scheduled() {
        return scheduled;
    }
    
    public void at_idle() {
        if (scheduled)
            return;
            
        scheduled = true;
        cancelled = false;
        Idle.add(callback_wrapper);
    }
    
    public void at_priority_idle(int priority) {
        if (scheduled)
            return;
        
        scheduled = true;
        cancelled = false;
        Idle.add_full(priority, callback_wrapper);
    }
    
    public void after_timeout(uint msec, bool reschedule) {
        if (scheduled) {
            if (reschedule)
                this.reschedule = true;
            
            return;
        }
        
        scheduled = true;
        cancelled = false;
        Timeout.add(msec, callback_wrapper);
    }
    
    public void priority_after_timeout(int priority, uint msec, bool reschedule) {
        if (scheduled) {
            if (reschedule)
                this.reschedule = true;
                
            return;
        }
        
        scheduled = true;
        cancelled = false;
        Timeout.add_full(priority, msec, callback_wrapper);
    }
    
    public void cancel() {
        cancelled = true;
        reschedule = false;
        scheduled = false;
    }
    
    private bool callback_wrapper() {
        if (cancelled) {
            cancelled = false;
            scheduled = false;
            
            return false;
        }
        
        if (reschedule) {
            reschedule = false;
            
            return true;
        }
        
        scheduled = false;
        callback();
        
        return false;
    }
}

