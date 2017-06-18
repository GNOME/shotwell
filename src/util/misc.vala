/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public uint int64_hash(int64? n) {
    // Rotating XOR hash
    uint8 *u8 = (uint8 *) n;
    uint hash = 0;
    for (int ctr = 0; ctr < (sizeof(int64) / sizeof(uint8)); ctr++) {
        hash = (hash << 4) ^ (hash >> 28) ^ (*u8++);
    }
    
    return hash;
}

public bool int64_equal(int64? a, int64? b) {
    int64 *bia = (int64 *) a;
    int64 *bib = (int64 *) b;
    
    return (*bia) == (*bib);
}

public int int64_compare(int64? a, int64? b) {
    int64 diff = *((int64 *) a) - *((int64 *) b);
    if (diff < 0)
        return -1;
    else if (diff > 0)
        return 1;
    else
        return 0;
}

public int uint64_compare(uint64? a, uint64? b) {
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

public inline time_t now_time_t() {
    return (time_t) now_sec();
}

public string md5_file(File file) throws Error {
    Checksum md5 = new Checksum(ChecksumType.MD5);
    uint8[] buffer = new uint8[64 * 1024];
    
    FileInputStream fins = file.read(null);
    for (;;) {
        size_t bytes_read = fins.read(buffer, null);
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
    if ((a != null && a.size == 0) && (b == null))
        return true;
    
    if ((a == null) && (b != null && b.size == 0))
        return true;
    
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

public string format_local_datespan(Time from_date, Time to_date) {
    string from_format, to_format;
   
    // Ticket #3240 - Change the way date ranges are pretty-
    // printed if the start and end date occur on consecutive days.    
    if (from_date.year == to_date.year) {
        // are these consecutive dates?
        if ((from_date.month == to_date.month) && (from_date.day == (to_date.day - 1))) {
            // Yes; display like so: Sat, July 4 - 5, 20X6
            from_format =  Resources.get_start_multiday_span_format_string();
            to_format = Resources.get_end_multiday_span_format_string();
        } else {
            // No, but they're in the same year; display in shortened
            // form: Sat, July 4 - Mon, July 6, 20X6
            from_format = Resources.get_start_multimonth_span_format_string();
            to_format = Resources.get_end_multimonth_span_format_string();
        }
    } else {
        // Span crosses a year boundary, use long form dates
        // for both start and end date.
        from_format = Resources.get_long_date_format_string();
        to_format = Resources.get_long_date_format_string();
    }
     
    return String.strip_leading_zeroes("%s - %s".printf(from_date.format(from_format),
        to_date.format(to_format)));
}

public string format_local_date(Time date) {
    return String.strip_leading_zeroes(date.format(Resources.get_long_date_format_string()));
}

public delegate void OneShotCallback();

public class OneShotScheduler {
    private string name;
    private unowned OneShotCallback callback;
    private uint scheduled = 0;
    
    public OneShotScheduler(string name, OneShotCallback callback) {
        this.name = name;
        this.callback = callback;
    }
    
    ~OneShotScheduler() {
#if TRACE_DTORS
        debug("DTOR: OneShotScheduler for %s", name);
#endif
        
        cancel();
    }
    
    public bool is_scheduled() {
        return scheduled != 0;
    }
    
    public void at_idle() {
        at_priority_idle(Priority.DEFAULT_IDLE);
    }
    
    public void at_priority_idle(int priority) {
        if (scheduled == 0)
            scheduled = Idle.add_full(priority, callback_wrapper);
    }
    
    public void after_timeout(uint msec, bool reschedule) {
        priority_after_timeout(Priority.DEFAULT, msec, reschedule);
    }
    
    public void priority_after_timeout(int priority, uint msec, bool reschedule) {
        if (scheduled != 0 && !reschedule)
            return;
        
        if (scheduled != 0)
            Source.remove(scheduled);
        
        scheduled = Timeout.add_full(priority, msec, callback_wrapper);
    }
    
    public void cancel() {
        if (scheduled == 0)
            return;
        
        Source.remove(scheduled);
        scheduled = 0;
    }
    
    private bool callback_wrapper() {
        scheduled = 0;
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

