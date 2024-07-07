public errordomain MetadataDateTimeError {
    INVALID_FORMAT,
    UNSUPPORTED_FORMAT
}

public class MetadataDateTime {

    private DateTime timestamp;
    private static TimeZone local = new TimeZone.local();

    public MetadataDateTime(DateTime timestamp) {
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
        var dt = new DateTime.from_iso8601(label, null);
        if (dt == null)
            throw new MetadataDateTimeError.INVALID_FORMAT("%s is not XMP format date/time", label);

        timestamp = dt;
    }

    public DateTime? get_timestamp() {
        return timestamp;
    }

    public string get_exif_label() {
        return to_exif_date_time(timestamp);
    }

    // TODO: get_iptc_date() and get_iptc_time()

    public string get_xmp_label() {
        return timestamp.format_iso8601();
    }

    public static bool from_exif_date_time(string date_time, out DateTime? timestamp) {
        timestamp = null;

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

        timestamp = new DateTime(local, tm.year, tm.month, tm.day, tm.hour, tm.minute, tm.second);

        return true;
    }

    public static string to_exif_date_time(DateTime timestamp) {
        return timestamp.to_local().format("%Y:%m:%d %H:%M:%S");
    }

    public string to_string() {
        return to_exif_date_time(timestamp);
    }
}
