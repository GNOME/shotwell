/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

//
// PhotoMetadata
//
// PhotoMetadata is a wrapper class around gexiv2.  The reasoning for this is (a) to facilitiate
// interface changes to meet Shotwell's requirements without needing modifications of the library
// itself, and (b) some requirements for this class (i.e. obtaining raw metadata) is not available
// in gexiv2, and so must be done by hand.
//
// Although it's perceived that Exiv2 will remain Shotwell's metadata library of choice, this
// may change in the future, and so this wrapper helps with that as well.
//
// There is no expectation of thread-safety in this class (yet).
//
// Tags come from Exiv2's naming scheme:
// http://www.exiv2.org/metadata.html
//

public enum MetadataDomain {
    UNKNOWN,
    EXIF,
    XMP,
    IPTC
}

public struct MetadataRational {
    public int numerator;
    public int denominator;
    
    public MetadataRational(int numerator, int denominator) {
        this.numerator = numerator;
        this.denominator = denominator;
    }
    
    public string to_string() {
        return "%d/%d".printf(numerator, denominator);
    }
}

errordomain MetadataDateTimeError {
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
        Time tm = Time();

        if (date_time.scanf("%d:%d:%d %d:%d:%d", &tm.year, &tm.month, &tm.day, &tm.hour, &tm.minute,
            &tm.second) != 6) {
            // for Minolta DiMAGE E223 (colon, instead of space, separates day from hour in exif)
            if (date_time.scanf("%d:%d:%d:%d:%d:%d", &tm.year, &tm.month, &tm.day, &tm.hour, &tm.minute,
                &tm.second) != 6) {
                return false;
            }
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
}

public abstract class PhotoPreview {
    private string name;
    private Dimensions dimensions;
    private uint32 size;
    private string mime_type;
    private string extension;
    
    public PhotoPreview(string name, Dimensions dimensions, uint32 size, string mime_type, string extension) {
        this.name = name;
        this.dimensions = dimensions;
        this.size = size;
        this.mime_type = mime_type;
        this.extension = extension;
    }
    
    public string get_name() {
        return name;
    }
    
    public Dimensions get_pixel_dimensions() {
        return dimensions;
    }
    
    public uint32 get_size() {
        return size;
    }
    
    public string get_mime_type() {
        return mime_type;
    }
    
    public string get_extension() {
        return extension;
    }
    
    public abstract uint8[] flatten() throws Error;
    
    public virtual Gdk.Pixbuf? get_pixbuf() throws Error {
        uint8[] flattened = flatten();
        
        // Need to create from stream or file for decode ... catch decode error and return null,
        // different from an I/O error causing the problem
        try {
            return new Gdk.Pixbuf.from_stream(new MemoryInputStream.from_data(flattened,
                flattened.length, null), null);
        } catch (Error err) {
            warning("Unable to decode thumbnail for %s: %s", name, err.message);
            
            return null;
        }
    }
}

public class PhotoMetadata {
    private class InternalPhotoPreview : PhotoPreview {
        public PhotoMetadata owner;
        public uint number;
        
        public InternalPhotoPreview(PhotoMetadata owner, string name, uint number, 
            GExiv2.PreviewProperties props) {
            base (name, Dimensions((int) props.get_width(), (int) props.get_height()), 
                props.get_size(), props.get_mime_type(), props.get_extension());
            
            this.owner = owner;
            this.number = number;
        }
        
        public override uint8[] flatten() throws Error {
            unowned GExiv2.PreviewProperties?[] props = owner.exiv2.get_preview_properties();
            assert(props != null && props.length > number);
            
            return owner.exiv2.get_preview_image(props[number]).get_data();
        }
    }
    
    private GExiv2.Metadata exiv2 = new GExiv2.Metadata();
    private Exif.Data? exif = null;
    string source_name = "<uninitialized>";
    
    public PhotoMetadata() {
    }
    
    public void read_from_file(File file) throws Error {
        exiv2 = new GExiv2.Metadata();
        exif = null;
        
        exiv2.open_path(file.get_path());
        exif = Exif.Data.new_from_file(file.get_path());
        source_name = file.get_basename();
    }
    
    public void write_to_file(File file) throws Error {
        exiv2.save_file(file.get_path());
    }
    
    public void read_from_buffer(uint8[] buffer, int length = 0) throws Error {
        if (length <= 0)
            length = buffer.length;
        
        assert(buffer.length >= length);
        
        exiv2 = new GExiv2.Metadata();
        exif = null;
        
        exiv2.open_buf(buffer, length);
        exif = Exif.Data.new_from_data(buffer, length);
        source_name = "<memory buffer %d bytes>".printf(length);
    }
    
    public void read_from_app1_segment(uint8[] buffer, int length = 0) throws Error {
        if (length <= 0)
            length = buffer.length;
        
        assert(buffer.length >= length);
        
        exiv2 = new GExiv2.Metadata();
        exif = null;
        
        exiv2.from_app1_segment(buffer, length);
        exif = Exif.Data.new_from_data(buffer, length);
        source_name = "<app1 segment %d bytes>".printf(length);
    }
    
    public static MetadataDomain get_tag_domain(string tag) {
        if (GExiv2.Metadata.is_exif_tag(tag))
            return MetadataDomain.EXIF;
        
        if (GExiv2.Metadata.is_xmp_tag(tag))
            return MetadataDomain.XMP;
        
        if (GExiv2.Metadata.is_iptc_tag(tag))
            return MetadataDomain.IPTC;
        
        return MetadataDomain.UNKNOWN;
    }
    
    public bool has_domain(MetadataDomain domain) {
        switch (domain) {
            case MetadataDomain.EXIF:
                return exiv2.has_exif();
            
            case MetadataDomain.XMP:
                return exiv2.has_xmp();
            
            case MetadataDomain.IPTC:
                return exiv2.has_iptc();
            
            case MetadataDomain.UNKNOWN:
            default:
                return false;
        }
    }
    
    public bool has_exif() {
        return has_domain(MetadataDomain.EXIF);
    }
    
    public bool has_xmp() {
        return has_domain(MetadataDomain.XMP);
    }
    
    public bool has_iptc() {
        return has_domain(MetadataDomain.IPTC);
    }
    
    public bool can_write_to_domain(MetadataDomain domain) {
        switch (domain) {
            case MetadataDomain.EXIF:
                return exiv2.get_supports_exif();
            
            case MetadataDomain.XMP:
                return exiv2.get_supports_xmp();
            
            case MetadataDomain.IPTC:
                return exiv2.get_supports_iptc();
            
            case MetadataDomain.UNKNOWN:
            default:
                return false;
        }
    }
    
    public bool can_write_exif() {
        return can_write_to_domain(MetadataDomain.EXIF);
    }
    
    public bool can_write_xmp() {
        return can_write_to_domain(MetadataDomain.XMP);
    }
    
    public bool can_write_iptc() {
        return can_write_to_domain(MetadataDomain.IPTC);
    }
    
    public bool has_tag(string tag) {
        return exiv2.has_tag(tag);
    }
    
    public Gee.Collection<string>? get_tags(MetadataDomain domain, CompareFunc? compare_func = null) {
        string[] tags = null;
        switch (domain) {
            case MetadataDomain.EXIF:
                tags = exiv2.get_exif_tags();
            break;
            
            case MetadataDomain.XMP:
                tags = exiv2.get_xmp_tags();
            break;
            
            case MetadataDomain.IPTC:
                tags = exiv2.get_iptc_tags();
            break;
        }
        
        if (tags == null || tags.length == 0)
            return null;
        
        Gee.Collection<string> collection = new Gee.TreeSet<string>(compare_func);
        foreach (string tag in tags)
            collection.add(tag);
        
        return collection;
    }
    
    public Gee.Collection<string> get_all_tags(CompareFunc? compare_func = null) {
        Gee.Collection<string> all_tags = new Gee.TreeSet<string>(compare_func);
        
        Gee.Collection<string>? exif_tags = get_tags(MetadataDomain.EXIF);
        if (exif_tags != null && exif_tags.size > 0)
            all_tags.add_all(exif_tags);
        
        Gee.Collection<string>? xmp_tags = get_tags(MetadataDomain.XMP);
        if (xmp_tags != null && xmp_tags.size > 0)
            all_tags.add_all(xmp_tags);
        
        Gee.Collection<string>? iptc_tags = get_tags(MetadataDomain.IPTC);
        if (iptc_tags != null && iptc_tags.size > 0)
            all_tags.add_all(iptc_tags);
        
        return all_tags.size > 0 ? all_tags : null;
    }
    
    public string? get_tag_label(string tag) {
        return GExiv2.Metadata.get_tag_label(tag);
    }
    
    public string? get_tag_description(string tag) {
        return GExiv2.Metadata.get_tag_description(tag);
    }
    
    public string? get_string(string tag) {
        return exiv2.get_tag_string(tag);
    }
    
    public string? get_string_interpreted(string tag) {
        return exiv2.get_tag_interpreted_string(tag);
    }
    
    public string? get_first_string(string[] tags) {
        foreach (string tag in tags) {
            string? value = get_string(tag);
            if (value != null)
                return value;
        }
        
        return null;
    }
    
    public string? get_first_string_interpreted(string[] tags) {
        foreach (string tag in tags) {
            string? value = get_string_interpreted(tag);
            if (value != null)
                return value;
        }
        
        return null;
    }
    
    public Gee.Collection<string>? get_string_multiple(string tag, CompareFunc? compare_func = null) {
        string[] values = exiv2.get_tag_multiple(tag);
        if (values == null || values.length == 0)
            return null;
        
        Gee.Collection<string> collection = new Gee.TreeSet<string>(compare_func);
        foreach (string value in values)
            collection.add(value);
        
        return collection;
    }
    
    public void set_string(string tag, string value) {
        if (!exiv2.set_tag_string(tag, value))
            warning("Unable to set tag %s to string %s from source %s", tag, value, source_name);
    }
    
    public void set_all_string(string[] tags, string value, bool only_if_domain_present) {
        foreach (string tag in tags) {
            if (!only_if_domain_present || has_domain(get_tag_domain(tag)))
                set_string(tag, value);
        }
    }
    
    public void set_string_multiple(string tag, Gee.Collection<string> collection) {
        string[] values = new string[collection.size];
        int ctr = 0;
        foreach (string value in collection)
            values[ctr++] = value;
        
        if (!exiv2.set_tag_multiple(tag, values))
            warning("Unable to set %d strings to tag %s from source %s", values.length, tag, source_name);
    }
    
    public void set_all_string_multiple(string[] tags, Gee.Collection<string> values,
        bool only_if_domain_present) {
        foreach (string tag in tags) {
            if (!only_if_domain_present || has_domain(get_tag_domain(tag)))
                set_string_multiple(tag, values);
        }
    }
    
    public bool get_long(string tag, out long value) {
        if (!has_tag(tag))
            return false;
        
        value = exiv2.get_tag_long(tag);
        
        return true;
    }
    
    public bool get_first_long(string[] tags, out long value) {
        foreach (string tag in tags) {
            if (get_long(tag, out value))
                return true;
        }
        
        return false;
    }
    
    public void set_long(string tag, long value) {
        if (!exiv2.set_tag_long(tag, value))
            warning("Unable to set tag %s to long %ld from source %s", tag, value, source_name);
    }
    
    public void set_all_long(string[] tags, long value, bool only_if_domain_present) {
        foreach (string tag in tags) {
            if (!only_if_domain_present || has_domain(get_tag_domain(tag)))
                set_long(tag, value);
        }
    }
    
    public bool get_rational(string tag, out MetadataRational rational) {
        return exiv2.get_exif_tag_rational(tag, out rational.numerator, out rational.denominator);
    }
    
    public bool get_first_rational(string[] tags, out MetadataRational rational) {
        foreach (string tag in tags) {
            if (get_rational(tag, out rational))
                return true;
        }
        
        return false;
    }
    
    public void set_rational(string tag, MetadataRational rational) {
        if (!exiv2.set_exif_tag_rational(tag, rational.numerator, rational.denominator)) {
            warning("Unable to set tag %s to rational %s from source %s", tag, rational.to_string(),
                source_name);
        }
    }
    
    public void set_all_rational(string[] tags, MetadataRational rational, bool only_if_domain_present) {
        foreach (string tag in tags) {
            if (!only_if_domain_present || has_domain(get_tag_domain(tag)))
                set_rational(tag, rational);
        }
    }
    
    public MetadataDateTime? get_date_time(string tag) {
        string? value = get_string(tag);
        if (value == null)
            return null;
        
        try {
            switch (get_tag_domain(tag)) {
                case MetadataDomain.XMP:
                    return new MetadataDateTime.from_xmp(value);
                
                // TODO: IPTC date/time support (which is tricky here, because date/time values
                // are stored in separate tags)
                case MetadataDomain.IPTC:
                    return null;
                
                case MetadataDomain.EXIF:
                default:
                    return new MetadataDateTime.from_exif(value);
            }
        } catch (Error err) {
            warning("Unable to read date/time %s from source %s: %s", tag, source_name, err.message);
            
            return null;
        }
    }
    
    public MetadataDateTime? get_first_date_time(string[] tags) {
        foreach (string tag in tags) {
            MetadataDateTime? date_time = get_date_time(tag);
            if (date_time != null)
                return date_time;
        }
        
        return null;
    }
    
    public void set_date_time(string tag, MetadataDateTime date_time) {
        switch (get_tag_domain(tag)) {
            case MetadataDomain.EXIF:
                set_string(tag, date_time.get_exif_label());
            break;
            
            case MetadataDomain.XMP:
                set_string(tag, date_time.get_xmp_label());
            break;
            
            // TODO: Support IPTC date/time (which are stored in separate tags)
            case MetadataDomain.IPTC:
            default:
                warning("Cannot set date/time for %s from source %s: unsupported metadata domain %s", tag,
                    source_name, get_tag_domain(tag).to_string());
            break;
        }
    }
    
    public void set_all_date_time(string[] tags, MetadataDateTime date_time, bool only_if_domain_present) {
        foreach (string tag in tags) {
            if (!only_if_domain_present || has_domain(get_tag_domain(tag)))
                set_date_time(tag, date_time);
        }
    }
    
    // Returns raw bytes of EXIF metadata, including signature and optionally the preview (if present).
    public uint8[]? flatten_exif(bool include_preview) {
        if (exif == null)
            return null;
        
        // save thumbnail to strip if no attachments requested (so it can be added back and
        // deallocated automatically)
        uchar *thumbnail = exif.data;
        uint thumbnail_size = exif.size;
        if (!include_preview) {
            exif.data = null;
            exif.size = 0;
        }
        
        uint8[]? flattened = null;
        
        // save the struct to a buffer and copy into a Vala-friendly one
        uchar *saved_data = null;
        uint saved_size = 0;
        exif.save_data(&saved_data, &saved_size);
        if (saved_size > 0 && saved_data != null) {
            flattened = new uint8[saved_size];
            Memory.copy(flattened, saved_data, saved_size);
            
            Exif.Mem.new_default().free(saved_data);
        }
        
        // restore thumbnail (this works in either case)
        exif.data = thumbnail;
        exif.size = thumbnail_size;
        
        return flattened;
    }
    
    // Returns raw bytes of EXIF preview, if present
    public uint8[]? flatten_exif_preview() {
        uchar[] buffer;
        return exiv2.get_exif_thumbnail(out buffer) ? buffer : null;
    }
    
    public uint get_preview_count() {
        unowned GExiv2.PreviewProperties?[] props = exiv2.get_preview_properties();
        
        return (props != null) ? props.length : 0;
    }
    
    // Previews are sorted from smallest to largest (width x height)
    public PhotoPreview? get_preview(uint number) {
        unowned GExiv2.PreviewProperties?[] props = exiv2.get_preview_properties();
        if (props == null || props.length <= number)
            return null;
        
        return new InternalPhotoPreview(this, source_name, number, props[number]);
    }
    
    public void remove_exif_thumbnail() {
        exiv2.erase_exif_thumbnail();
        if (exif != null) {
            Exif.Mem.new_default().free(exif.data);
            exif.data = null;
            exif.size = 0;
        }
    }
    
    public void remove_tag(string tag) {
        exiv2.clear_tag(tag);
    }
    
    public void remove_tags(string[] tags) {
        foreach (string tag in tags)
            remove_tag(tag);
    }
    
    public void clear_domain(MetadataDomain domain) {
        switch (domain) {
            case MetadataDomain.EXIF:
                exiv2.clear_exif();
            break;
            
            case MetadataDomain.XMP:
                exiv2.clear_xmp();
            break;
            
            case MetadataDomain.IPTC:
                exiv2.clear_iptc();
            break;
        }
    }
    
    public void clear() {
        exiv2.clear();
    }
    
    private static string[] DATE_TIME_TAGS = {
        "Exif.Image.DateTime",
        "Xmp.tiff.DateTime",
        "Xmp.xmp.ModifyDate"
    };
    
    public MetadataDateTime? get_modification_date_time() {
        return get_first_date_time(DATE_TIME_TAGS);
    }
    
    public void set_modification_date_time(MetadataDateTime? date_time, bool only_if_domain_present = true) {
        if (date_time != null)
            set_all_date_time(DATE_TIME_TAGS, date_time, only_if_domain_present);
        else
            remove_tags(DATE_TIME_TAGS);
    }
    
    private static string[] EXPOSURE_DATE_TIME_TAGS = {
        "Exif.Photo.DateTimeOriginal",
        "Xmp.exif.DateTimeOriginal",
        "Xmp.xmp.CreateDate"
    };
    
    public MetadataDateTime? get_exposure_date_time() {
        return get_first_date_time(EXPOSURE_DATE_TIME_TAGS);
    }
    
    public void set_exposure_date_time(MetadataDateTime? date_time, bool only_if_domain_present = true) {
        if (date_time != null)
            set_all_date_time(EXPOSURE_DATE_TIME_TAGS, date_time, only_if_domain_present);
        else
            remove_tags(EXPOSURE_DATE_TIME_TAGS);
    }
    
    private static string[] DIGITIZED_DATE_TIME_TAGS = {
        "Exif.Photo.DateTimeDigitized",
        "Xmp.exif.DateTimeDigitized"
    };
    
    public MetadataDateTime? get_digitized_date_time() {
        return get_first_date_time(DIGITIZED_DATE_TIME_TAGS);
    }
    
    public void set_digitized_date_time(MetadataDateTime? date_time, bool only_if_domain_present = true) {
        if (date_time != null)
            set_all_date_time(DIGITIZED_DATE_TIME_TAGS, date_time, only_if_domain_present);
        else
            remove_tags(DIGITIZED_DATE_TIME_TAGS);
    }
    
    private static string[] WIDTH_TAGS = {
        "Exif.Photo.PixelXDimension",
        "Xmp.exif.PixelXDimension",
        "Xmp.tiff.ImageWidth",
        "Xmp.exif.PixelXDimension"
    };
    
    public static string[] HEIGHT_TAGS = {
        "Exif.Photo.PixelYDimension",
        "Xmp.exif.PixelYDimension",
        "Xmp.tiff.ImageHeight",
        "Xmp.exif.PixelYDimension"
    };
    
    public Dimensions? get_pixel_dimensions() {
        // walk the tag arrays concurrently, returning the dimensions of the first found pair
        assert(WIDTH_TAGS.length == HEIGHT_TAGS.length);
        for (int ctr = 0; ctr < WIDTH_TAGS.length; ctr++) {
            // Can't turn this into a single if statement with an || bailing out due to this bug:
            // https://bugzilla.gnome.org/show_bug.cgi?id=565385
            long width;
            if (!get_long(WIDTH_TAGS[ctr], out width))
                continue;
            
            long height;
            if (!get_long(HEIGHT_TAGS[ctr], out height))
                continue;
            
            return Dimensions((int) width, (int) height);
        }
        
        return null;
    }
    
    public void set_pixel_dimensions(Dimensions? dim, bool only_if_domain_present = true) {
         if (dim != null) {
            set_all_long(WIDTH_TAGS, dim.width, only_if_domain_present);
            set_all_long(HEIGHT_TAGS, dim.height, only_if_domain_present);
         } else {
            remove_tags(WIDTH_TAGS);
            remove_tags(HEIGHT_TAGS);
         }
    }
    
    //
    // A note regarding titles and descriptions:
    //
    // iPhoto stores its title in Iptc.Application2.ObjectName and its description in
    // Iptc.Application2.Caption.  Most others use .Caption for the title and another
    // (sometimes) appropriate tag for the description.  And there's general confusion about
    // whether Exif.Image.ImageDescription is a description (which is what the tag name
    // suggests) or a title (which is what the specification states).
    // See: http://trac.yorba.org/wiki/PhotoTags
    //
    // Hence, the following logic tries to do the right thing in most of these cases.  If
    // the iPhoto title tag is detected, it and the iPhoto description tag are used.  Otherwise,
    // the title/description are searched out from a list of standard tags.
    //
    // Exif.Image.ImageDescription seems to be abused, both in that iPhoto uses it as a multiline
    // description and that some cameras insert their make & model information there (IN ALL CAPS,
    // to really rub it in).  We are ignoring the field until a compelling reason to support it
    // is found.
    //
    
    private const string IPHOTO_TITLE_TAG = "Iptc.Application2.ObjectName";
    
    private static string[] STANDARD_TITLE_TAGS = {
        "Iptc.Application2.Caption",
        "Xmp.dc.title",
        "Iptc.Application2.Headline",
        "Xmp.photoshop.Headline"
    };
    
    public string? get_title() {
        string? title = has_tag(IPHOTO_TITLE_TAG) 
            ? get_string_interpreted(IPHOTO_TITLE_TAG)
            : get_first_string_interpreted(STANDARD_TITLE_TAGS);
        
        // strip out leading and trailing whitespace
        if (title != null)
            title = title.strip();
        
        // check for \n and \r to prevent multiline titles, which have been spotted in the wild
        return (!is_string_empty(title) && !title.contains("\n") && !title.contains("\r")) ?
            title : null;
    }
    
    public void set_title(string? title, bool only_if_domain_present = true) {
        if (!is_string_empty(title)) {
            if (has_tag(IPHOTO_TITLE_TAG))
                set_string(IPHOTO_TITLE_TAG, title);
            else
                set_all_string(STANDARD_TITLE_TAGS, title, only_if_domain_present);
        } else {
            remove_tags(STANDARD_TITLE_TAGS);
        }
    }
    
    private const string IPHOTO_DESCRIPTION_TAG = "Iptc.Application2.Caption";
    
    private static string[] STANDARD_DESCRIPTION_TAGS = {
        "Xmp.dc.description"
    };
    
    public string? get_description() {
        // see note in get_title() for the logic here
        if (has_tag(IPHOTO_TITLE_TAG))
            return get_string_interpreted(IPHOTO_DESCRIPTION_TAG);
        else
            return get_first_string_interpreted(STANDARD_DESCRIPTION_TAGS);
    }
    
    public void set_description(string? description, bool only_if_domain_present) {
        if (!is_string_empty(description)) {
            if (has_tag(IPHOTO_TITLE_TAG) 
                && (!only_if_domain_present || has_domain(get_tag_domain(IPHOTO_DESCRIPTION_TAG))))
                set_string(IPHOTO_DESCRIPTION_TAG, description);
            else
                set_all_string(STANDARD_DESCRIPTION_TAGS, description, only_if_domain_present);
        } else {
            remove_tags(STANDARD_DESCRIPTION_TAGS);
        }
    }
    
    private static string[] KEYWORD_TAGS = {
        "Xmp.dc.subject",
        "Iptc.Application2.Keywords"
    };
    
    public Gee.Collection<string>? get_keywords(CompareFunc? compare_func = null) {
        Gee.Collection<string> keywords = null;
        foreach (string tag in KEYWORD_TAGS) {
            Gee.Collection<string>? values = get_string_multiple(tag);
            if (values != null && values.size > 0) {
                if (keywords == null) {
                    if (compare_func == null)
                        keywords = new Gee.HashSet<string>();
                    else
                        keywords = new Gee.TreeSet<string>(compare_func);
                }
                
                keywords.add_all(values);
            }
        }
        
        return (keywords != null && keywords.size > 0) ? keywords : null;
    }
    
    public void set_keywords(Gee.Collection<string>? keywords, bool only_if_domain_present) {
        if (keywords != null)
            set_all_string_multiple(KEYWORD_TAGS, keywords, only_if_domain_present);
        else
            remove_tags(KEYWORD_TAGS);
    }
    
    public bool has_orientation() {
        return exiv2.get_orientation() == GExiv2.Orientation.UNSPECIFIED;
    }
    
    // If not present, returns Orientation.TOP_LEFT.
    public Orientation get_orientation() {
        // GExiv2.Orientation is the same value-wise as Orientation, with one exception:
        // GExiv2.Orientation.UNSPECIFIED must be handled
        GExiv2.Orientation orientation = exiv2.get_orientation();
        if (orientation ==  GExiv2.Orientation.UNSPECIFIED || orientation < Orientation.MIN ||
            orientation > Orientation.MAX)
            return Orientation.TOP_LEFT;
        else
            return (Orientation) orientation;
    }
    
    public void set_orientation(Orientation orientation) {
        // GExiv2.Orientation is the same value-wise as Orientation
        exiv2.set_orientation((GExiv2.Orientation) orientation);
    }
    
    public bool get_gps(out double longitude, out string long_ref, out double latitude, out string lat_ref,
        out double altitude) {
        if (!exiv2.get_gps_info(out longitude, out latitude, out altitude))
            return false;
        
        long_ref = get_string("Exif.GPSInfo.GPSLongitudeRef");
        lat_ref = get_string("Exif.GPSInfo.GPSLatitudeRef");
        
        return true;
    }
    
    public bool get_exposure(out MetadataRational exposure) {
        return get_rational("Exif.Photo.ExposureTime", out exposure);
    }
    
    public string? get_exposure_string() {
        return get_string_interpreted("Exif.Photo.ExposureTime");
    }
    
    public bool get_iso(out long iso) {
        return get_long("Exif.Photo.ISOSpeedRatings", out iso);
    }
    
    public string? get_iso_string() {
        return get_string_interpreted("Exif.Photo.ISOSpeedRatings");
    }
    
    public bool get_aperture(out MetadataRational aperture) {
        return get_rational("Exif.Photo.FNumber", out aperture);
    }
    
    public string? get_aperture_string(bool pango_formatted = false) {
        MetadataRational aperture;
        if (!get_aperture(out aperture))
            return null;
        
        double aperture_value = ((double) aperture.numerator) / ((double) aperture.denominator);
        aperture_value = ((int) (aperture_value * 10.0)) / 10.0;

        return (pango_formatted ? "<i>f</i>/" : "f/") + 
            ((aperture_value % 1 == 0) ? "%.0f" : "%.1f").printf(aperture_value);
    }
    
    public string? get_camera_make() {
        return get_string_interpreted("Exif.Image.Make");
    }
    
    public string? get_camera_model() {
        return get_string_interpreted("Exif.Image.Model");
    }
    
    public bool get_flash(out long flash) {
        // Exif.Image.Flash does not work for some reason
        return get_long("Exif.Photo.Flash", out flash);
    }
    
    public string? get_flash_string() {
        // Exif.Image.Flash does not work for some reason
        return get_string_interpreted("Exif.Photo.Flash");
    }
    
    public bool get_focal_length(out MetadataRational focal_length) {
        return get_rational("Exif.Photo.FocalLength", out focal_length);
    }
    
    public string? get_focal_length_string() {
        return get_string_interpreted("Exif.Photo.FocalLength");
    }
    
    private static string[] ARTIST_TAGS = {
        "Exif.Image.Artist",
        "Exif.Canon.OwnerName" // Custom tag used by Canon DSLR cameras
    };
    
    public string? get_artist() {
        return get_first_string_interpreted(ARTIST_TAGS);
    }
    
    public string? get_copyright() {
        return get_string_interpreted("Exif.Image.Copyright");
    }
    
    public string? get_software() {
        return get_string_interpreted("Exif.Image.Software");
    }
    
    public string? get_exposure_bias() {
        return get_string_interpreted("Exif.Photo.ExposureBiasValue");
    }
}

