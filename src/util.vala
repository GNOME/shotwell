/* Copyright 2009-2010 Yorba Foundation
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

public delegate bool ValueEqualFunc(Value a, Value b);

public bool bool_value_equals(Value a, Value b) {
    return (bool) a == (bool) b;
}

public bool int_value_equals(Value a, Value b) {
    return (int) a == (int) b;
}

public ulong timeval_to_ms(TimeVal time_val) {
    return (((ulong) time_val.tv_sec) * 1000) + (((ulong) time_val.tv_usec) / 1000);
}

public ulong now_ms() {
    return timeval_to_ms(TimeVal());
}

public ulong now_sec() {
    TimeVal time_val = TimeVal();
    
    return time_val.tv_sec;
}

public string md5_binary(uint8 *buffer, size_t length) {
    assert(length != 0);

    Checksum md5 = new Checksum(ChecksumType.MD5);
    md5.update((uchar []) buffer, length);
    
    return md5.get_string();
}

public string md5_file(File file) throws Error {
    Checksum md5 = new Checksum(ChecksumType.MD5);
    uint8[] buffer = new uint8[64 * 1024];
    
    FileInputStream fins = file.read(null);
    for (;;) {
        size_t bytes_read = fins.read(buffer, buffer.length, null);
        if (bytes_read <= 0)
            break;
        
        md5.update((uchar[]) buffer, bytes_read);
    }
    
    try {
        fins.close(null);
    } catch (Error err) {
        warning("Unable to close MD5 input stream for %s: %s", file.get_path(), err.message);
    }
    
    return md5.get_string();
}

public uchar[] serialize_photo_ids(Gee.Collection<TransformablePhoto> photos) {
    int64[] ids = new int64[photos.size];
    int ctr = 0;
    foreach (TransformablePhoto photo in photos)
        ids[ctr++] = photo.get_photo_id().id;
    
    size_t bytes = photos.size * sizeof(int64);
    uchar[] serialized = new uchar[bytes];
    Memory.copy(serialized, ids, bytes);
    
    return serialized;
}

public Gee.List<PhotoID?>? unserialize_photo_ids(uchar* serialized, int size) {
    size_t count = (size / sizeof(int64));
    if (count <= 0 || serialized == null)
        return null;
    
    int64[] ids = new int64[count];
    Memory.copy(ids, serialized, size);
    
    Gee.ArrayList<PhotoID?> list = new Gee.ArrayList<PhotoID?>();
    foreach (int64 id in ids)
        list.add(PhotoID(id));
    
    return list;
}

public inline bool is_string_empty(string? s) {
    return (s == null || s[0] == '\0');
}

public string uchar_array_to_string(uchar[] data, int length = -1) {
    if (length < 0)
        length = data.length;
    
    StringBuilder builder = new StringBuilder();
    for (int ctr = 0; ctr < length; ctr++) {
        if (data[ctr] != '\0')
            builder.append_c((char) data[ctr]);
        else
            break;
    }
    
    return builder.str;
}

public uchar[] string_to_uchar_array(string str) {
    uchar[] data = new uchar[0];
    for (int ctr = 0; ctr < str.length; ctr++)
        data += (uchar) str[ctr];
    
    return data;
}

// Markup.escape_text() will crash if the UTF-8 text is not valid; it relies on a call to 
// g_utf8_next_char(), which demands that the string be validated before use, which escape_text()
// does not do.  This handles this problem by kicking back an empty string if the text is not
// valid.  Text should be validated upon entry to the system as well to guard against this
// problem.
public inline string guarded_markup_escape_text(string plain) {
    return plain.validate() ? Markup.escape_text(plain) : "";
}

public class KeyValueMap {
    private string group;
    private Gee.HashMap<string, string> map = new Gee.HashMap<string, string>(str_hash, str_equal,
        str_equal);
    
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
        
        return (value != null) ? value.to_int() : def;
    }
    
    public double get_double(string key, double def) {
        string value = map.get(key);
        
        return (value != null) ? value.to_double() : def;
    }
    
    public float get_float(string key, float def) {
        string value = map.get(key);
        
        return (value != null) ? (float) value.to_double() : def;
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

public enum CompassPoint {
    NORTH,
    SOUTH,
    EAST,
    WEST
}

// This function is thread-safe.
public uint64 query_total_file_size(File file_or_dir, Cancellable? cancellable = null) throws Error {
    FileType type = file_or_dir.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    if (type == FileType.REGULAR) {
        FileInfo info = null;
        try {
            info = file_or_dir.query_info(FILE_ATTRIBUTE_STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        } catch (Error err) {
            if (err is IOError.CANCELLED)
                throw err;
            
            debug("Unable to query filesize for %s: %s", file_or_dir.get_path(), err.message);

            return 0;
        }
        
        return info.get_size();
    } else if (type != FileType.DIRECTORY) {
        return 0;
    }
        
    FileEnumerator enumerator;
    try {
        enumerator = file_or_dir.enumerate_children(FILE_ATTRIBUTE_STANDARD_NAME,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        if (enumerator == null)
            return 0;
    } catch (Error err) {
        // Don't treat a permissions failure as a hard failure, just skip the directory
        if (err is FileError.PERM || err is IOError.PERMISSION_DENIED)
            return 0;
        
        throw err;
    }
    
    uint64 total_bytes = 0;
        
    FileInfo info = null;
    while ((info = enumerator.next_file(cancellable)) != null)
        total_bytes += query_total_file_size(file_or_dir.get_child(info.get_name()), cancellable);
    
    return total_bytes;
}

public time_t query_file_modified(File file) throws Error {
    FileInfo info = file.query_info(FILE_ATTRIBUTE_TIME_MODIFIED, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, 
        null);

    TimeVal timestamp = TimeVal();
    info.get_modification_time(out timestamp);
    
    return timestamp.tv_sec;
}

public bool query_is_directory(File file) {
    return file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null) == FileType.DIRECTORY;
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

public string strip_pretty_path(string path) {
    if (!path.has_prefix("~"))
        return path;
    
    return Environment.get_home_dir() + path.substring(1);
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

// Verifies that only the mask bits are set in the modifier field, disregarding mouse and 
// key modifers that are not normally of concern (i.e. Num Lock, Caps Lock, etc.).  Mask can be
// one or more bits set, but should only consist of these values:
// * Gdk.ModifierType.SHIFT_MASK
// * Gdk.ModifierType.CONTROL_MASK
// * Gdk.ModifierType.MOD1_MASK (Alt)
// * Gdk.ModifierType.MOD3_MASK
// * Gdk.ModifierType.MOD4_MASK
// * Gdk.ModifierType.MOD5_MASK
// * Gdk.ModifierType.SUPER_MASK
// * Gdk.ModifierType.HYPER_MASK
// * Gdk.ModifierType.META_MASK
//
// (Note: MOD2 seems to be Num Lock in GDK.)
public bool has_only_key_modifier(Gdk.ModifierType field, Gdk.ModifierType mask) {
    return (field 
        & (Gdk.ModifierType.SHIFT_MASK 
        | Gdk.ModifierType.CONTROL_MASK
        | Gdk.ModifierType.MOD1_MASK
        | Gdk.ModifierType.MOD3_MASK
        | Gdk.ModifierType.MOD4_MASK
        | Gdk.ModifierType.MOD5_MASK
        | Gdk.ModifierType.SUPER_MASK
        | Gdk.ModifierType.HYPER_MASK
        | Gdk.ModifierType.META_MASK)) == mask;
}

public delegate void OneShotCallback();

public class OneShotScheduler {
    private string name;
    private OneShotCallback callback;
    private bool scheduled = false;
    private bool reschedule = false;
    private bool cancelled = false;
    
    public OneShotScheduler(string name, OneShotCallback callback) {
        this.name = name;
        this.callback = callback;
    }
    
    ~OneShotScheduler() {
#if TRACE_DTORS
        debug("DTOR: OneShotScheduler for %s", name);
#endif
        
        cancelled = true;
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

public class OpTimer {
    private string name;
    private Timer timer = new Timer();
    private long count = 0;
    private double elapsed = 0;
    private double shortest = double.MAX;
    private double longest = double.MIN;
    
    public OpTimer(string name) {
        this.name = name;
    }
    
    public void start() {
        timer.start();
    }
    
    public void stop() {
        double time = timer.elapsed();
        
        elapsed += time;
        
        if (time < shortest)
            shortest = time;
        
        if (time > longest)
            longest = time;
        
        count++;
    }
    
    public string to_string() {
        if (count > 0) {
            return "%s: count=%ld elapsed=%.03lfs min/avg/max=%.03lf/%.03lf/%.03lf".printf(name, 
                count, elapsed, shortest, elapsed / (double) count, longest);
        } else {
            return "%s: no operations".printf(name);
        }
    }
}

private void remove_from_app(Gee.Collection<LibraryPhoto> photos, string dialog_title, 
    string progress_dialog_text) {
    if (photos.size == 0)
        return;
    
	Gtk.ResponseType result = remove_from_library_dialog(AppWindow.get_instance(), dialog_title, photos.size);
	if (result != Gtk.ResponseType.YES && result != Gtk.ResponseType.NO)
	    return;
    
	bool delete_backing = (result == Gtk.ResponseType.YES);
    
	AppWindow.get_instance().set_busy_cursor();
    
	ProgressDialog progress = null;
	if (photos.size >= 20)
	    progress = new ProgressDialog(AppWindow.get_instance(), progress_dialog_text);
    
	// valac complains about passing an argument for a delegate using ternary operator:
	// https://bugzilla.gnome.org/show_bug.cgi?id=599349
	if (progress != null)
	    LibraryPhoto.global.remove_from_app(photos, delete_backing, progress.monitor);
	else
	    LibraryPhoto.global.remove_from_app(photos, delete_backing);
    
	if (progress != null)
	    progress.close();

	AppWindow.get_instance().set_normal_cursor();
}

// compare the app names, case insensitive
public static int64 app_info_comparator(void *a, void *b) {
    return ((AppInfo) a).get_name().down().collate(((AppInfo) b).get_name().down());
}

public SortedList<AppInfo> get_apps_for_mime_types(string[] mime_types) {        
        SortedList<AppInfo> external_apps = new SortedList<AppInfo>(app_info_comparator);
        
        if (mime_types.length == 0)
            return external_apps;
        
        // make sure the app is avaiable to all mime types
        // 3 loops because List.index() wasn't paying nicely with AppInfo (special equality func?)
        foreach (AppInfo external_app in AppInfo.get_all_for_type(g_content_type_from_mime_type(mime_types[0]))) {
            foreach (string mime_type in mime_types) {
                bool mime_uses_app = false;
                
                List<AppInfo> mime_apps =
                    AppInfo.get_all_for_type(g_content_type_from_mime_type(mime_type));
                
                foreach (AppInfo app in mime_apps) {
                    if (app.equal(external_app))
                        mime_uses_app = true;
                }
                
                // dont add Shotwell to app list
                if (mime_uses_app && !external_apps.contains(external_app) && 
                    !external_app.get_name().contains(Resources.APP_TITLE))
                    external_apps.add(external_app);
            }
        }

        return external_apps;
}

public AppInfo? get_default_app_for_mime_types(string[] mime_types, 
    Gee.ArrayList<string> preferred_apps) {
    SortedList<AppInfo> external_apps = get_apps_for_mime_types(mime_types);
    
    foreach (string preferred_app in preferred_apps) {
        foreach (AppInfo external_app in external_apps) {
            if (external_app.get_name().contains(preferred_app))
                return external_app;
        }
    }
    
    return null;
}

public bool is_twentyfour_hr_time_system() {
    // if no AM/PM designation is found, the location is set to use a 24 hr time system
    string timestring = Time.local(0).format("%p");
    
    return is_string_empty(timestring);
}