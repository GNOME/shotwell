/* Copyright 2010-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class MediaMetadata {
    public MediaMetadata() {
    }
    
    public abstract void read_from_file(File file) throws Error;
    
    public abstract MetadataDateTime? get_creation_date_time();
    
    public abstract string? get_title();
}

public struct MetadataRational {
    public int numerator;
    public int denominator;
    
    public MetadataRational(int numerator, int denominator) {
        this.numerator = numerator;
        this.denominator = denominator;
    }
    
    private bool is_component_valid(int component) {
        return (component >= 0) && (component <= 1000000);
    }
    
    public bool is_valid() {
        return (is_component_valid(numerator) && is_component_valid(denominator));
    }
    
    public string to_string() {
        return (is_valid()) ? ("%d/%d".printf(numerator, denominator)) : "";
    }
}

public errordomain MetadataDateTimeError {
    INVALID_FORMAT,
    UNSUPPORTED_FORMAT
}

public class MetadataDateTime {
    // known EXIF date/time formats, starting with the standard one, followed by others that have
    // been seen in the wild ... this array is attempted sequentially, so keep that in mind if
    // new formats are added.  Also, all formats should yield 6 int values in this order:
    // year, month, day, hour, minute, second
    private static string[] EXIF_DATE_TIME_FORMATS = {
        "%d:%d:%d %d:%d:%d",
        
        // for Minolta DiMAGE E223 (colon, instead of space, separates day from hour in exif)
        "%d:%d:%d:%d:%d:%d",
        
        // for Samsung NV10 (which uses a period instead of colons for the date and two spaces
        // between date and time)
        "%d.%d.%d  %d:%d:%d"
    };
    
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
        Time tm = Time();
        
        bool found = false;
        foreach (string fmt in EXIF_DATE_TIME_FORMATS) {
            if (date_time.scanf(fmt, &tm.year, &tm.month, &tm.day, &tm.hour, &tm.minute,
                &tm.second) == 6) {
                found = true;
                
                break;
            }
        }
        
        if (!found)
            return false;
        
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

