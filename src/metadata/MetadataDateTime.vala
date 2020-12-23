public errordomain MetadataDateTimeError {
    INVALID_FORMAT,
    UNSUPPORTED_FORMAT
}

public class MetadataDateTime {

    private time_t timestamp;

    public MetadataDateTime(time_t timestamp) {
        this.timestamp = timestamp;
    }

    public MetadataDateTime.from_exif(string label) throws MetadataDateTimeError {
        if (!from_exif_date_time(label, out timestamp))
            throw new MetadataDateTimeError.INVALID_FORMAT("%s is not EXIF format date/time", label);
    }

    public MetadataDateTime.from_iptc(string date, string time) throws MetadataDateTimeError {
        // TODO: Support IPTC date/time format
        throw new MetadataDateTimeError.UNSUPPORTED_FORMAT("IPTC date/time format not currently supported");
    }

    public MetadataDateTime.from_xmp(string label) throws MetadataDateTimeError {
        TimeVal time_val = TimeVal();
        if (!time_val.from_iso8601(label))
            throw new MetadataDateTimeError.INVALID_FORMAT("%s is not XMP format date/time", label);

        timestamp = time_val.tv_sec;
    }

    public time_t get_timestamp() {
        return timestamp;
    }

    public string get_exif_label() {
        return to_exif_date_time(timestamp);
    }

    // TODO: get_iptc_date() and get_iptc_time()

    public string get_xmp_label() {
        TimeVal time_val = TimeVal();
        time_val.tv_sec = timestamp;
        time_val.tv_usec = 0;

        return time_val.to_iso8601();
    }

    public static bool from_exif_date_time(string date_time, out time_t timestamp) {
        timestamp = 0;

        Time tm = Time();

        // Check standard EXIF format
        if (date_time.scanf("%d:%d:%d %d:%d:%d",
                            &tm.year, &tm.month, &tm.day, &tm.hour, &tm.minute, &tm.second) != 6) {
            // Fallback in a more generic format
            string tmp = date_time.dup();
            tmp.canon("0123456789", ' ');
            if (tmp.scanf("%4d%2d%2d%2d%2d%2d",
                          &tm.year, &tm.month, &tm.day, &tm.hour, &tm.minute,&tm.second) != 6)
                return false;
        }

        // watch for bogosity
        if (tm.year <= 1900 || tm.month <= 0 || tm.day < 0 || tm.hour < 0 || tm.minute < 0 || tm.second < 0)
            return false;

        tm.year -= 1900;
        tm.month--;
        tm.isdst = -1;

        timestamp = tm.mktime();

        return true;
    }

    public static string to_exif_date_time(time_t timestamp) {
        return Time.local(timestamp).format("%Y:%m:%d %H:%M:%S");
    }

    public string to_string() {
        return to_exif_date_time(timestamp);
    }
}
