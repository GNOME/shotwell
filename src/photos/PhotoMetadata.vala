/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

//
// PhotoMetadata
//
// PhotoMetadata is a wrapper class around gexiv2.  The reasoning for this is (a) to facilitate
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

public abstract class KeywordTransformer {
    public abstract Gee.List<string> transform (string input) throws Error;
}

public class NullKeywordTransformer : KeywordTransformer {
    public override Gee.List<string> transform (string input) throws Error {
        var result = new Gee.ArrayList<string> ();
        result.add (input);

        return result;
    }
}

/* Transforms ACDSEE's pseudo-XML category format into Lightroom format
 * <Categories>
 * <Category Assigned=\"1\">Alben
 *   <Category Assigned=\"1\">Flowers</Category>
 * </Category>
 * <Category Assigned=\"1\">Orte</Category>
 * <Category Assigned=\"1\">Verschiedenes</Category>
 * </Categories>
 *
 * Will be transformed to a list of Alben, Alben|Flowers, Orte, Verschiedenes
 */
public class ACDSeeKeywordTransformer : KeywordTransformer {
    private MarkupParser parser;
    private Error error;
    private Gee.ArrayQueue<string> stack;
    private Gee.ArrayList<string> result;
    private bool assigned;

    public ACDSeeKeywordTransformer() {
        this.parser = MarkupParser ();
        this.parser.start_element = this.on_start;
        this.parser.end_element = this.on_end;
        this.parser.text = this.on_text;
        this.parser.error = this.on_error;
        this.result = new Gee.ArrayList<string> ();
        this.stack = new Gee.ArrayQueue<string> ();
    }

    public override Gee.List<string> transform (string input) throws Error {
        this.stack.clear();
        this.result.clear();
        var ctx = new MarkupParseContext (this.parser, 0, this, null);

        ctx.parse (input, input.length);

        return result;
    }

    private void on_start (MarkupParseContext ctx,
                           string name,
                           [CCode (array_null_terminated = true,
                                   array_length = false)]
                           string[] attribute_names,
                           [CCode (array_null_terminated = true,
                                   array_length = false)]
                           string[] attribute_values) throws MarkupError {
        this.assigned = false;
        if (name == "Categories") {
            return;
        }

        if (name != "Category") {
            return;
        }

        Markup.collect_attributes (name,
                                   attribute_names,
                                   attribute_values,
                                   Markup.CollectType.BOOLEAN,
                                   "Assigned", out assigned);
    }

    private void on_end (MarkupParseContext ctx, string name)
                         throws MarkupError {
        if (name == "Category") {
            this.stack.poll_tail ();
        }
    }

    private void on_text (MarkupParseContext ctx, string text)
                          throws MarkupError {
        if (text == "") {
            return;
        }

        this.stack.offer_tail (text);
        if (this.assigned) {
            var builder = new StringBuilder ();
            foreach (var f in this.stack) {
                builder.append_printf ("%s|", f);
            }
            if (builder.len > 0) {
                builder.truncate (builder.len - 1);
            }
            this.result.add (builder.str);
        }
    }

    private void on_error (MarkupParseContext ctx, Error error) {
        this.error = error;
    }
}



public class HierarchicalKeywordField {
    public string field_name;
    public string path_separator;
    public bool wants_leading_separator;
    public bool is_writeable;
    public KeywordTransformer transformer;

    public HierarchicalKeywordField(string field_name,
                                    string path_separator,
                                    bool wants_leading_separator,
                                    bool is_writeable,
                                    KeywordTransformer transformer =
                                        new NullKeywordTransformer ()) {
        this.field_name = field_name;
        this.path_separator = path_separator;
        this.wants_leading_separator = wants_leading_separator;
        this.is_writeable = is_writeable;
        this.transformer = transformer;
    }
}

public abstract class PhotoPreview {
    private string name;
    private Dimensions dimensions;
    private uint32 size;
    private string mime_type;
    private string extension;
    
    protected PhotoPreview(string name, Dimensions dimensions, uint32 size, string mime_type, string extension) {
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
    
    public abstract Bytes flatten() throws Error;
    
    public virtual Gdk.Pixbuf? get_pixbuf() throws Error {
        var flattened = flatten();
        
        // Need to create from stream or file for decode ... catch decode error and return null,
        // different from an I/O error causing the problem
        try {
            return new Gdk.Pixbuf.from_stream(new
                    MemoryInputStream.from_bytes(flattened));
        } catch (Error err) {
            warning("Unable to decode thumbnail for %s: %s", name, err.message);
            
            return null;
        }
    }
}

public class PhotoMetadata : MediaMetadata {
    public enum SetOption {
        ALL_DOMAINS,
        ONLY_IF_DOMAIN_PRESENT,
        AT_LEAST_DEFAULT_DOMAIN
    }
    
    public const PrepareInputTextOptions PREPARE_STRING_OPTIONS =
        PrepareInputTextOptions.INVALID_IS_NULL
        | PrepareInputTextOptions.EMPTY_IS_NULL
        | PrepareInputTextOptions.STRIP
        | PrepareInputTextOptions.STRIP_CRLF
        | PrepareInputTextOptions.NORMALIZE
        | PrepareInputTextOptions.VALIDATE;
    
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
        
        public override Bytes flatten() throws Error {
            unowned GExiv2.PreviewProperties?[] props = owner.exiv2.get_preview_properties();
            assert(props != null && props.length > number);
            
            return new
                Bytes(owner.exiv2.get_preview_image(props[number]).get_data());
        }
    }
    
    private GExiv2.Metadata exiv2 = new GExiv2.Metadata();
    private Exif.Data? exif = null;
    string source_name = "<uninitialized>";
    private string? metadata_hash = null;
    private string? thumbnail_md5 = null;
    
    public PhotoMetadata() {
    }
    
    public override void read_from_file(File file) throws Error {
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
        
#if NEW_GEXIV2_API
        exiv2.open_buf(buffer[0:length]);
#else
        exiv2.open_buf(buffer, length);
#endif
        exif = Exif.Data.new_from_data(buffer);
        source_name = "<memory buffer %d bytes>".printf(length);
    }
    
    public void read_from_app1_segment(Bytes buffer) throws Error {
        exiv2 = new GExiv2.Metadata();
        exif = null;
        
#if NEW_GEXIV2_API
        exiv2.from_app1_segment(buffer.get_data());
#else
        exif = Exif.Data.new_from_data(buffer.get_data());
#endif
        source_name = "<app1 segment %zu bytes>".printf(buffer.get_size());
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
    
    private Gee.Set<string> create_string_set(owned CompareDataFunc<string>? compare_func) {
        // ternary doesn't work here
        if (compare_func == null)
            return new Gee.HashSet<string>();
        else
            return new Gee.TreeSet<string>((owned) compare_func);
    }
    
    public Gee.Collection<string>? get_tags(MetadataDomain domain,
        owned CompareDataFunc<string>? compare_func = null) {
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
        
        Gee.Collection<string> collection = create_string_set((owned) compare_func);
        foreach (string tag in tags)
            collection.add(tag);
        
        return collection;
    }
    
    public Gee.Collection<string> get_all_tags(
        owned CompareDataFunc<string>? compare_func = null) {
        Gee.Collection<string> all_tags = create_string_set((owned) compare_func);
        
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
    
    public string? get_string(string tag, PrepareInputTextOptions options = PREPARE_STRING_OPTIONS) {
        return prepare_input_text(exiv2.get_tag_string(tag), options, DEFAULT_USER_TEXT_INPUT_LENGTH);
    }
    
    public string? get_string_interpreted(string tag, PrepareInputTextOptions options = PREPARE_STRING_OPTIONS) {
        return prepare_input_text(exiv2.get_tag_interpreted_string(tag), options, DEFAULT_USER_TEXT_INPUT_LENGTH);
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
    
    // Returns a List that has been filtered through a Set, so no duplicates will be returned.
    //
    // NOTE: get_tag_multiple() in gexiv2 currently does not work with EXIF tags (as EXIF can 
    // never return a list of strings).  It will quietly return NULL if attempted.  Until fixed
    // (there or here), don't use this function to access EXIF.  See:
    // http://trac.yorba.org/ticket/2966
    public Gee.List<string>? get_string_multiple(string tag) {
        string[] values = exiv2.get_tag_multiple(tag);
        if (values == null || values.length == 0)
            return null;
        
        Gee.List<string> list = new Gee.ArrayList<string>();
        
        Gee.HashSet<string> collection = new Gee.HashSet<string>();
        foreach (string value in values) {
            string? prepped = prepare_input_text(value, PREPARE_STRING_OPTIONS,
                DEFAULT_USER_TEXT_INPUT_LENGTH);
                
            if (prepped != null && !collection.contains(prepped)) {
                list.add(prepped);
                collection.add(prepped);
            }
        }
        
        return list.size > 0 ? list : null;
    }
    
    // Returns a List that has been filtered through a Set, so no duplicates will be found.
    //
    // NOTE: get_tag_multiple() in gexiv2 currently does not work with EXIF tags (as EXIF can 
    // never return a list of strings).  It will quietly return NULL if attempted.  Until fixed
    // (there or here), don't use this function to access EXIF.  See:
    // http://trac.yorba.org/ticket/2966
    public Gee.List<string>? get_first_string_multiple(string[] tags) {
        foreach (string tag in tags) {
            Gee.List<string>? values = get_string_multiple(tag);
            if (values != null && values.size > 0)
                return values;
        }
        
        return null;
    }
    
    public void set_string(string tag, string value, PrepareInputTextOptions options = PREPARE_STRING_OPTIONS) {
        string? prepped = prepare_input_text(value, options, DEFAULT_USER_TEXT_INPUT_LENGTH);
        if (prepped == null) {
            warning("Not setting tag %s to string %s: invalid UTF-8", tag, value);
            
            return;
        }
        
        if (!exiv2.set_tag_string(tag, prepped))
            warning("Unable to set tag %s to string %s from source %s", tag, value, source_name);
    }
    
    private delegate void SetGenericValue(string tag);
    
    private void set_all_generic(string[] tags, SetOption option, SetGenericValue setter) {
        bool written = false;
        foreach (string tag in tags) {
            if (option == SetOption.ALL_DOMAINS || has_domain(get_tag_domain(tag))) {
                setter(tag);
                written = true;
            }
        }
        
        if (option == SetOption.AT_LEAST_DEFAULT_DOMAIN && !written && tags.length > 0) {
            MetadataDomain default_domain = get_tag_domain(tags[0]);
            
            // write at least the first one, as it's the default
            setter(tags[0]);
            
            // write the remainder, if they are of the same domain
            for (int ctr = 1; ctr < tags.length; ctr++) {
                if (get_tag_domain(tags[ctr]) == default_domain)
                    setter(tags[ctr]);
            }
        }
    }
    
    public void set_all_string(string[] tags, string value, SetOption option) {
        set_all_generic(tags, option, (tag) => { set_string(tag, value); });
    }
    
    public void set_string_multiple(string tag, Gee.Collection<string> collection) {
        string[] values = new string[0];
        foreach (string value in collection) {
            string? prepped = prepare_input_text(value, PREPARE_STRING_OPTIONS,-1);
            if (prepped != null)
                values += prepped;
            else
                warning("Unable to set string %s to %s: invalid UTF-8", value, tag);
        }
        
        if (values.length == 0)
            return;

        // append a null pointer to the end of the string array -- this is a necessary
        // workaround for http://trac.yorba.org/ticket/3264. See also
        // http://trac.yorba.org/ticket/3257, which describes the user-visible behavior
        // seen in the Flickr Connector as a result of the former bug.
        values += null;
        
        if (!exiv2.set_tag_multiple(tag, values))
            warning("Unable to set %d strings to tag %s from source %s", values.length, tag, source_name);
    }
    
    public void set_all_string_multiple(string[] tags, Gee.Collection<string> values, SetOption option) {
        set_all_generic(tags, option, (tag) => { set_string_multiple(tag, values); });
    }
    
    public bool get_long(string tag, out long value) {
        if (!has_tag(tag)) {
            value = 0;
            
            return false;
        }
        
        value = exiv2.get_tag_long(tag);
        
        return true;
    }
    
    public bool get_first_long(string[] tags, out long value) {
        foreach (string tag in tags) {
            if (get_long(tag, out value))
                return true;
        }
        
        value = 0;
        
        return false;
    }
    
    public void set_long(string tag, long value) {
        if (!exiv2.set_tag_long(tag, value))
            warning("Unable to set tag %s to long %ld from source %s", tag, value, source_name);
    }
    
    public void set_all_long(string[] tags, long value, SetOption option) {
        set_all_generic(tags, option, (tag) => { set_long(tag, value); });
    }
    
    public bool get_rational(string tag, out MetadataRational rational) {
        int numerator, denominator;
        bool result = exiv2.get_exif_tag_rational(tag, out numerator, out denominator);
        
        rational = MetadataRational(numerator, denominator);
        
        return result;
    }
    
    public bool get_first_rational(string[] tags, out MetadataRational rational) {
        foreach (string tag in tags) {
            if (get_rational(tag, out rational))
                return true;
        }
        
        rational = MetadataRational(0, 0);
        
        return false;
    }
    
    public void set_rational(string tag, MetadataRational rational) {
        if (!exiv2.set_exif_tag_rational(tag, rational.numerator, rational.denominator)) {
            warning("Unable to set tag %s to rational %s from source %s", tag, rational.to_string(),
                source_name);
        }
    }
    
    public void set_all_rational(string[] tags, MetadataRational rational, SetOption option) {
        set_all_generic(tags, option, (tag) => { set_rational(tag, rational); });
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
    
    public void set_all_date_time(string[] tags, MetadataDateTime date_time, SetOption option) {
        set_all_generic(tags, option, (tag) => { set_date_time(tag, date_time); });
    }
    
    // Returns raw bytes of EXIF metadata, including signature and optionally the preview (if present).
    public string? exif_hash() {
        if (exif == null)
            return null;

        if (this.metadata_hash != null) {
            return this.metadata_hash;
        }

        string? hash = null;

        var thumb = exif.data;
        var thumb_size = exif.size;

        // Strip potential thumbnail
        exif.data = null;
        exif.size = 0;

        uchar *saved_data = null;
        uint saved_size = 0;

        exif.save_data(&saved_data, &saved_size);

        exif.data = thumb;
        exif.size = thumb_size;

        if (saved_size > 0 && saved_data != null) {
            var md5 = new Checksum(ChecksumType.MD5);
            md5.update((uchar []) saved_data, saved_size);
            Exif.Mem.new_default().free(saved_data);

            this.metadata_hash = md5.get_string ();
        }

        return hash;
    }
    
    // Returns raw bytes of EXIF preview, if present
    public string? thumbnail_hash() {
        if (this.thumbnail_md5 != null) {
            return this.thumbnail_md5;
        }

        uchar[] buffer;
        if (exiv2.get_exif_thumbnail(out buffer)) {
            var md5 = new Checksum(ChecksumType.MD5);
            md5.update(buffer, buffer.length);

            this.thumbnail_md5 = md5.get_string();

            return this.thumbnail_md5;
         }

        return null;
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
        "Xmp.xmp.ModifyDate",
        "Xmp.acdsee.datetime"
    };
    
    public MetadataDateTime? get_modification_date_time() {
        return get_first_date_time(DATE_TIME_TAGS);
    }
    
    public void set_modification_date_time(MetadataDateTime? date_time,
        SetOption option = SetOption.ALL_DOMAINS) {
        if (date_time != null)
            set_all_date_time(DATE_TIME_TAGS, date_time, option);
        else
            remove_tags(DATE_TIME_TAGS);
    }
    
    private static string[] EXPOSURE_DATE_TIME_TAGS = {
        "Exif.Photo.DateTimeOriginal",
        "Xmp.exif.DateTimeOriginal",
        "Xmp.xmp.CreateDate",
        "Exif.Photo.DateTimeDigitized",
        "Xmp.exif.DateTimeDigitized",
        "Exif.Image.DateTime"
    };
    
    public MetadataDateTime? get_exposure_date_time() {
        return get_first_date_time(EXPOSURE_DATE_TIME_TAGS);
    }
    
    public void set_exposure_date_time(MetadataDateTime? date_time,
        SetOption option = SetOption.ALL_DOMAINS) {
        if (date_time != null)
            set_all_date_time(EXPOSURE_DATE_TIME_TAGS, date_time, option);
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
    
    public void set_digitized_date_time(MetadataDateTime? date_time,
        SetOption option = SetOption.ALL_DOMAINS) {
        if (date_time != null)
            set_all_date_time(DIGITIZED_DATE_TIME_TAGS, date_time, option);
        else
            remove_tags(DIGITIZED_DATE_TIME_TAGS);
    }
    
    public override MetadataDateTime? get_creation_date_time() {
        MetadataDateTime? creation = get_exposure_date_time();
        if (creation == null)
            creation = get_digitized_date_time();
        
        return creation;
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
    
    public void set_pixel_dimensions(Dimensions? dim, SetOption option = SetOption.ALL_DOMAINS) {
         if (dim != null) {
            set_all_long(WIDTH_TAGS, dim.width, option);
            set_all_long(HEIGHT_TAGS, dim.height, option);
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
        "Xmp.photoshop.Headline",
        "Xmp.acdsee.caption"
    };
    
    public override string? get_title() {
        // using get_string_multiple()/get_first_string_multiple() because it's possible for
        // multiple strings to be specified in XMP for different language codes, and want to
        // retrieve only the first one (other get_string variants will return ugly strings like
        //
        //   lang="x-default" Xyzzy
        //
        // but get_string_multiple will return a list of titles w/o language information
        Gee.List<string>? titles = has_tag(IPHOTO_TITLE_TAG)
            ? get_string_multiple(IPHOTO_TITLE_TAG)
            : get_first_string_multiple(STANDARD_TITLE_TAGS);
        
        // use the first string every time (assume it's default)
        // TODO: We could get a list of all titles by their lang="<iso code>" and attempt to find
        // the right one for the user's locale, but this does not seem to be a normal use case
        string? title = (titles != null && titles.size > 0) ? titles[0] : null;
        
        // strip out leading and trailing whitespace
        if (title != null)
            title = title.strip();
        
        // check for \n and \r to prevent multiline titles, which have been spotted in the wild
        return (!is_string_empty(title) && !title.contains("\n") && !title.contains("\r")) ?
            title : null;
    }
    
    public void set_title(string? title, SetOption option = SetOption.ALL_DOMAINS) {
        if (!is_string_empty(title)) {
            if (has_tag(IPHOTO_TITLE_TAG))
                set_string(IPHOTO_TITLE_TAG, title);
            else
                set_all_string(STANDARD_TITLE_TAGS, title, option);
        } else {
            remove_tags(STANDARD_TITLE_TAGS);
        }
    }

    private static string[] COMMENT_TAGS = {
        "Exif.Photo.UserComment",
        "Xmp.acdsee.notes"
    };
    
    public override string? get_comment() {
        return get_first_string_interpreted (COMMENT_TAGS);
    }
    
    public void set_comment(string? comment,
                            SetOption option = SetOption.ALL_DOMAINS) {
        /* https://bugzilla.gnome.org/show_bug.cgi?id=781897 - Do not strip
         * newlines from comments */
        if (!is_string_empty(comment))
            set_all_generic(COMMENT_TAGS, option, (tag) => {
                set_string(tag, comment, PREPARE_STRING_OPTIONS &
                        ~PrepareInputTextOptions.STRIP_CRLF);
            });
        else
            remove_tags(COMMENT_TAGS);
    }
    
    private static string[] KEYWORD_TAGS = {
        "Xmp.dc.subject",
        "Iptc.Application2.Keywords",
        "Xmp.xmp.Label"
    };
    
    private static HierarchicalKeywordField[] HIERARCHICAL_KEYWORD_TAGS = {
        // Xmp.lr.hierarchicalSubject should be writeable but isn't due to this bug
        // in libexiv2: http://dev.exiv2.org/issues/784
        new HierarchicalKeywordField("Xmp.lr.hierarchicalSubject", "|", false, false),
        new HierarchicalKeywordField("Xmp.acdsee.keywords", "|", false, false),
        new HierarchicalKeywordField("Xmp.acdsee.categories", "|", false, false,
                                     new ACDSeeKeywordTransformer ()),
        new HierarchicalKeywordField("Xmp.digiKam.TagsList", "/", false, true),
        new HierarchicalKeywordField("Xmp.MicrosoftPhoto.LastKeywordXMP", "/", false, true)
    };
    
    public Gee.Set<string>? get_keywords(owned CompareDataFunc<string>? compare_func = null) {
        Gee.Set<string> keywords = null;
        foreach (string tag in KEYWORD_TAGS) {
            Gee.Collection<string>? values = get_string_multiple(tag);
            if (values != null && values.size > 0) {
                if (keywords == null)
                    keywords = create_string_set((owned) compare_func);

                foreach (string current_value in values)
                    keywords.add(HierarchicalTagUtilities.make_flat_tag_safe(current_value));
            }
        }
        
        return (keywords != null && keywords.size > 0) ? keywords : null;
    }
    
    private void internal_set_hierarchical_keywords(HierarchicalTagIndex? index) {
        foreach (HierarchicalKeywordField current_field in HIERARCHICAL_KEYWORD_TAGS)
            remove_tag(current_field.field_name);

        if (index == null)
            return;

        foreach (HierarchicalKeywordField current_field in HIERARCHICAL_KEYWORD_TAGS) {
            if (!current_field.is_writeable)
                continue;

            Gee.Set<string> writeable_set = new Gee.TreeSet<string>();

            foreach (string current_path in index.get_all_paths()) {
                string writeable_path = current_path.replace(Tag.PATH_SEPARATOR_STRING,
                    current_field.path_separator);
                if (!current_field.wants_leading_separator)
                    writeable_path = writeable_path.substring(1);

                writeable_set.add(writeable_path);
            }
            
            set_string_multiple(current_field.field_name, writeable_set);
        }
    }
    
    public void set_keywords(Gee.Collection<string>? keywords, SetOption option = SetOption.ALL_DOMAINS) {
        HierarchicalTagIndex htag_index = new HierarchicalTagIndex();
        Gee.Set<string> flat_keywords = new Gee.TreeSet<string>();

        if (keywords != null) {
            foreach (string keyword in keywords) {
                if (keyword.has_prefix(Tag.PATH_SEPARATOR_STRING)) {
                    Gee.Collection<string> path_components =
                        HierarchicalTagUtilities.enumerate_path_components(keyword);
                    foreach (string component in path_components)
                        htag_index.add_path(component, keyword);
                } else {
                    flat_keywords.add(keyword);
                }
            }
            
            flat_keywords.add_all(htag_index.get_all_tags());
        }

        if (keywords != null) {
            set_all_string_multiple(KEYWORD_TAGS, flat_keywords, option);
            internal_set_hierarchical_keywords(htag_index);
        } else {
            remove_tags(KEYWORD_TAGS);
            internal_set_hierarchical_keywords(null);
        }
    }
    
    public bool has_hierarchical_keywords() {
        foreach (HierarchicalKeywordField field in HIERARCHICAL_KEYWORD_TAGS) {
            Gee.Collection<string>? values = get_string_multiple(field.field_name);
            
            if (values != null && values.size > 0)
                return true;
        }
        
        return false;
    }
    
    public Gee.Set<string> get_hierarchical_keywords() {
        assert(has_hierarchical_keywords());

        Gee.Set<string> h_keywords = create_string_set(null);

        foreach (HierarchicalKeywordField field in HIERARCHICAL_KEYWORD_TAGS) {
            Gee.Collection<string>? values = get_string_multiple(field.field_name);
            
            if (values == null || values.size < 1)
                continue;

            var transformed_values = new Gee.ArrayList<string> ();
            foreach (var current_value in values) {
                try {
                    var transformed = field.transformer.transform (current_value);
                    transformed_values.add_all (transformed);
                } catch (Error error) {
                    critical ("Failed to transform tag value %s: %s",
                              current_value,
                              error.message);
                }
            }
            
            foreach (var current_value in transformed_values) {
                string? canonicalized =
                    HierarchicalTagUtilities.canonicalize(current_value,
                    field.path_separator);

                if (canonicalized != null)
                    h_keywords.add(canonicalized);
            }
        }
        
        return h_keywords;
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
        if (!exiv2.get_gps_info(out longitude, out latitude, out altitude)) {
            long_ref = null;
            lat_ref = null;
            
            return false;
        }
        
        long_ref = get_string("Exif.GPSInfo.GPSLongitudeRef");
        lat_ref = get_string("Exif.GPSInfo.GPSLatitudeRef");
        
        return true;
    }
    
    public bool get_exposure(out MetadataRational exposure) {
        return get_rational("Exif.Photo.ExposureTime", out exposure);
    }
    
    public string? get_exposure_string() {
        MetadataRational exposure_time;
        if (!get_rational("Exif.Photo.ExposureTime", out exposure_time))
            return null;
        
        if (!exposure_time.is_valid())
            return null;

        return get_string_interpreted("Exif.Photo.ExposureTime");
    }
    
    public bool get_iso(out long iso) {
        bool fetched_ok = get_long("Exif.Photo.ISOSpeedRatings", out iso);

        if (fetched_ok == false)
            return false;
        
        // lower boundary is original (ca. 1935) Kodachrome speed, the lowest ISO rated film ever
        // manufactured; upper boundary is 4 x fastest high-speed digital camera speeds
        if ((iso < 6) || (iso > 409600))
            return false;
        
        return true;
    }
    
    public string? get_iso_string() {
        long iso;
        if (!get_iso(out iso))
            return null;

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
        "Exif.Canon.OwnerName", // Custom tag used by Canon DSLR cameras
        "Xmp.acdsee.author" // Custom tag used by ACDSEE software
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
    
    public void set_software(string software, string version) {
        // always set this one, even if EXIF not present
        set_string("Exif.Image.Software", "%s %s".printf(software, version));
        
        if (has_iptc()) {
            set_string("Iptc.Application2.Program", software);
            set_string("Iptc.Application2.ProgramVersion", version);
        }
    }
    
    public void remove_software() {
        remove_tag("Exif.Image.Software");
        remove_tag("Iptc.Application2.Program");
        remove_tag("Iptc.Application2.ProgramVersion");
    }
    
    public string? get_exposure_bias() {
        return get_string_interpreted("Exif.Photo.ExposureBiasValue");
    }
    
    private static string[] RATING_TAGS = {
        "Xmp.xmp.Rating",
        "Iptc.Application2.Urgency",
        "Xmp.photoshop.Urgency",
        "Exif.Image.Rating",
        "Xmp.acdsee.rating",
    };
    
    public Rating get_rating() {
        string? rating_string = get_first_string(RATING_TAGS);
        if(rating_string != null)
            return Rating.unserialize(int.parse(rating_string));

        rating_string = get_string("Exif.Image.RatingPercent");
        if(rating_string == null) {
            return Rating.UNRATED;
        }

        int int_percent_rating = int.parse(rating_string);
        for(int i = 5; i >= 0; --i) {
            if(int_percent_rating >= Resources.rating_thresholds[i])
                return Rating.unserialize(i);
        }
        return Rating.unserialize(-1);
    }
    
    // Among photo managers, Xmp.xmp.Rating tends to be the standard way to represent ratings.
    // Other photo managers, notably F-Spot, take hints from Urgency fields about what the rating
    // of an imported photo should be, and we have decided to do as well. Xmp.xmp.Rating is the only 
    // field we've seen photo manages export ratings to, while Urgency fields seem to have a fundamentally
    // different meaning. See http://trac.yorba.org/wiki/PhotoTags#Rating for more information.
    public void set_rating(Rating rating) {
        int int_rating = rating.serialize();
        set_string("Xmp.xmp.Rating", int_rating.to_string());
        set_string("Exif.Image.Rating", int_rating.to_string());

        if( 0 <= int_rating )
            set_string("Exif.Image.RatingPercent", Resources.rating_thresholds[int_rating].to_string());
        else // in this case we _know_ int_rating is -1
            set_string("Exif.Image.RatingPercent", int_rating.to_string());
    }
}

