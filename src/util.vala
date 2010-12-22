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

public int int64_compare(void *a, void *b) {
    int64 diff = *((int64 *) a) - *((int64 *) b);
    if (diff < 0)
        return -1;
    else if (diff > 0)
        return 1;
    else
        return 0;
}

public int uint64_compare(void *a, void *b) {
    uint64 a64 = *((uint64 *) a);
    uint64 b64 = *((uint64 *) b);
    
    if (a64 < b64)
        return -1;
    else if (a64 > b64)
        return 1;
    else
        return 0;
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

// Once generic functions are available in Vala, this could be genericized.
public bool equal_sets(Gee.Set<string>? a, Gee.Set<string>? b) {
    if ((a == null && b != null) || (a != null && b == null))
        return false;
    
    if (a == null && b == null)
        return true;
    
    if (a.size != b.size)
        return false;
    
    // because they're sets and the same size, only need to iterate over one set to know
    // it is equal to the other
    foreach (string element in a) {
        if (!b.contains(element))
            return false;
    }
    
    return true;
}

// Once generic functions are available in Vala, this could be genericized.
public Gee.Set<string>? intersection_of_sets(Gee.Set<string>? a, Gee.Set<string>? b,
    Gee.Set<string>? excluded) {
    if (a != null && b == null) {
        if (excluded != null)
            excluded.add_all(a);
        
        return null;
    }
    
    if (a == null && b != null) {
        if (excluded != null)
            excluded.add_all(b);
        
        return null;
    }
    
    Gee.Set<string> intersection = new Gee.HashSet<string>();
    
    foreach (string element in a) {
        if (b.contains(element))
            intersection.add(element);
        else if (excluded != null)
            excluded.add(element);
    }
    
    foreach (string element in b) {
        if (a.contains(element))
            intersection.add(element);
        else if (excluded != null)
            excluded.add(element);
    }
    
    return intersection.size > 0 ? intersection : null;
}

public uchar[] serialize_photo_ids(Gee.Collection<Photo> photos) {
    int64[] ids = new int64[photos.size];
    int ctr = 0;
    foreach (Photo photo in photos)
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

public uchar[] serialize_media_sources(Gee.Collection<MediaSource> media) {
    Gdk.Atom[] atoms = new Gdk.Atom[media.size];
    int ctr = 0;
    foreach (MediaSource current_media in media)
        atoms[ctr++] = Gdk.Atom.intern(current_media.get_source_id(), false);
    
    size_t bytes = media.size * sizeof(Gdk.Atom);
    uchar[] serialized = new uchar[bytes];
    Memory.copy(serialized, atoms, bytes);
    
    return serialized;
}

public Gee.List<MediaSource>? unserialize_media_sources(uchar* serialized, int size) {
    size_t count = (size / sizeof(Gdk.Atom));
    if (count <= 0 || serialized == null)
        return null;
    
    Gdk.Atom[] atoms = new Gdk.Atom[count];
    Memory.copy(atoms, serialized, size);
    
    Gee.ArrayList<MediaSource> list = new Gee.ArrayList<MediaSource>();
    foreach (Gdk.Atom current_atom in atoms) {
        MediaSource media = MediaCollectionRegistry.get_instance().fetch_media(current_atom.name());
        assert(media != null);
        list.add(media);
    }

    return list;
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

public void remove_photos_from_library(Gee.Collection<LibraryPhoto> photos) {
    remove_from_app(photos, _("Remove From Library"),
        ngettext("Removing Photo From Library", "Removing Photos From Library", photos.size));
}

public void remove_from_app(Gee.Collection<MediaSource> sources, string dialog_title, 
    string progress_dialog_text) {
    if (sources.size == 0)
        return;
    
    Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
    Gee.ArrayList<Video> videos = new Gee.ArrayList<Video>();
    MediaSourceCollection.filter_media(sources, photos, videos);
    
    string? user_message = null;
    if ((!photos.is_empty) && (!videos.is_empty)) {
        user_message = ngettext("This will remove the photo/video from your Shotwell library.  Would you also like to move the file to your desktop trash?\n\nThis action cannot be undone.",
            "This will remove %d photos/videos from your Shotwell library.  Would you also like to move the files to your desktop trash?\n\nThis action cannot be undone.",
             sources.size).printf(sources.size);
    } else if (!videos.is_empty) {
        user_message = ngettext("This will remove the video from your Shotwell library.  Would you also like to move the file to your desktop trash?\n\nThis action cannot be undone.",
            "This will remove %d videos from your Shotwell library.  Would you also like to move the files to your desktop trash?\n\nThis action cannot be undone.",
             sources.size).printf(sources.size);
    } else {
        user_message = ngettext("This will remove the photo from your Shotwell library.  Would you also like to move the file to your desktop trash?\n\nThis action cannot be undone.",
            "This will remove %d photos from your Shotwell library.  Would you also like to move the files to your desktop trash?\n\nThis action cannot be undone.",
             sources.size).printf(sources.size);
    }
    
    Gtk.ResponseType result = remove_from_library_dialog(AppWindow.get_instance(), dialog_title,
        user_message, sources.size);
    if (result != Gtk.ResponseType.YES && result != Gtk.ResponseType.NO)
        return;
    
    bool delete_backing = (result == Gtk.ResponseType.YES);
    
    AppWindow.get_instance().set_busy_cursor();
    
    ProgressDialog progress = null;
    ProgressMonitor monitor = null;
    if (sources.size >= 20) {
        progress = new ProgressDialog(AppWindow.get_instance(), progress_dialog_text);
        monitor = progress.monitor;
    }
        
    Gee.ArrayList<LibraryPhoto> not_removed_photos = new Gee.ArrayList<LibraryPhoto>();
    Gee.ArrayList<Video> not_removed_videos = new Gee.ArrayList<Video>();
    
    // Remove and attempt to trash.
    LibraryPhoto.global.remove_from_app(photos, delete_backing, monitor, not_removed_photos);
    Video.global.remove_from_app(videos, delete_backing, monitor, not_removed_videos);
    
    // Check for files we couldn't trash.
    int num_not_removed = not_removed_photos.size + not_removed_videos.size;
    if (delete_backing && num_not_removed > 0) {
        string not_deleted_message = 
            ngettext("The photo or video cannot be moved to your desktop trash.  Delete this file?",
                "%d photos/videos cannot be moved to your desktop trash.  Delete these files?",
                num_not_removed).printf(num_not_removed);
        Gtk.ResponseType result_delete = remove_from_filesystem_dialog(AppWindow.get_instance(), 
            dialog_title, not_deleted_message);
            
        if (Gtk.ResponseType.YES == result_delete) {
            // Attempt to delete the files.
            Gee.ArrayList<LibraryPhoto> not_deleted_photos = new Gee.ArrayList<LibraryPhoto>();
            Gee.ArrayList<Video> not_deleted_videos = new Gee.ArrayList<Video>();
            LibraryPhoto.global.delete_backing_files(not_removed_photos, monitor, not_deleted_photos);
            Video.global.delete_backing_files(not_removed_videos, monitor, not_deleted_videos);
            
            int num_not_deleted = not_deleted_photos.size + not_deleted_videos.size;
            if (num_not_deleted > 0) {
                // Alert the user that the files were not removed.
                string delete_failed_message = 
                    ngettext("The photo or video cannot be deleted.",
                        "%d photos/videos cannot be deleted.",
                        num_not_deleted).printf(num_not_deleted);
                AppWindow.error_message_with_title(dialog_title, delete_failed_message, AppWindow.get_instance());
            }
        }
    }
    
    if (progress != null)
        progress.close();
    
    AppWindow.get_instance().set_normal_cursor();
}

public bool is_twentyfour_hr_time_system() {
    // if no AM/PM designation is found, the location is set to use a 24 hr time system
    return is_string_empty(Time.local(0).format("%p"));
}

public string get_window_manager() {
    return Gdk.x11_screen_get_window_manager_name(AppWindow.get_instance().get_screen());
}

