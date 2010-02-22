/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace Exif {
    // "Exif"
    public const uint8[] SIGNATURE = { 0x45, 0x78, 0x69, 0x66 };
    
    // Caller must set Entry.data with one of the various convert functions.
    public Exif.Entry alloc_entry(Data exif, Tag tag, Format format) {
        assert(exif.get_data_type().is_valid());
        
        // the recipe for alloc'ing an entry: allocate, add to parent, initialize.  Parent is
        // required for initialize() to know the byte-order.  First, find the IFD that the
        // entry should be placed in.
        Ifd ifd;
        bool found = find_ifd(tag, exif.get_data_type(), out ifd);
        assert(found);
        
        Exif.Entry entry = new Exif.Entry();
        exif.ifd[ifd].add_entry(entry);
        entry.initialize(tag);
        
        return entry;
    }
    
    public void realloc_ascii(Exif.Entry entry, string str) {
        Exif.Mem mem = Exif.Mem.new_default();
        
        if (entry.data != null) {
            mem.free(entry.data);
            entry.data = null;
        }
        
        entry.format = Exif.Format.ASCII;
        entry.components = str.size() + 1;
        entry.size = Exif.Format.ASCII.get_size() * (uint) entry.components;
        
        // need to copy in the string into a buffer allocated by the Mem object
        entry.data = mem.alloc(entry.size);
        Memory.copy(entry.data, str, entry.size);
    }
    
    public void realloc_long(Exif.Data parent, Exif.Entry entry, uint32 l) {
        Exif.Mem mem = Exif.Mem.new_default();
        
        if (entry.data != null) {
            mem.free(entry.data);
            entry.data = null;
        }
        
        entry.format = Exif.Format.LONG;
        entry.components = 1;
        entry.size = Exif.Format.LONG.get_size() * (uint) entry.components;
        entry.data = mem.alloc(entry.size);
        Exif.Convert.set_long(entry.data, parent.get_byte_order(), l);
    }
    
    // This returns the first IFD where a tag is MANDATORY or OPTIONAL ... returns MANDATORY
    // over OPTIONAL if both exist.  Returns false if no IFD found.
    public bool find_ifd(Tag tag, DataType data_type, out Ifd ifd) {
        int mandatory = -1;
        int optional = -1;
        
        for (int ctr = 0; ctr < (int) Exif.IFD_COUNT; ctr++) {
            switch (tag.get_support_level_in_ifd((Ifd) ctr, data_type)) {
                case SupportLevel.MANDATORY:
                    if (mandatory == -1)
                        mandatory = ctr;
                break;
                
                case SupportLevel.OPTIONAL:
                    if (optional == -1)
                        optional = ctr;
                break;
                
                default:
                    // ignored
                break;
            }
        }
        
        if (mandatory != -1)
            ifd = (Ifd) mandatory;
        else if (optional != -1)
            ifd = (Ifd) optional;
        else
            return false;
        
        return true;
    }
    
    public Exif.Entry? find_first_entry(Data data, Exif.Tag tag, Exif.Format format, int size = 1) {
        for (int ctr = 0; ctr < (int) Exif.IFD_COUNT; ctr++) {
            Exif.Content content = data.ifd[ctr];
            if (content == null)
                continue;
            
            Exif.Entry entry = content.get_entry(tag);
            if (entry == null)
                continue;
            
            if (entry.format != format)
                continue;
            
            if ((format != Exif.Format.ASCII) && (format != Exif.Format.UNDEFINED)) {
                if (entry.size != format.get_size() * size)
                    continue;
            }
            
            return entry;
        }
        
        return null;
    }
    
    private Exif.Entry? find_first_entry_multiformat(Exif.Data exif, Exif.Tag tag, Exif.Format format1,
        Exif.Format format2) {
        for (int ctr = 0; ctr < Exif.IFD_COUNT; ctr++) {
            Exif.Content content = exif.ifd[(int) ctr];
            if (content == null)
                continue;
            
            Exif.Entry entry = content.get_entry(tag);
            if (entry == null)
                continue;
            
            if (entry.format != format1 && entry.format != format2)
                continue;
            
            // can only verify size of fixed-length formats
            if ((entry.format != Exif.Format.ASCII) && (entry.format != Exif.Format.UNDEFINED)) {
                if (entry.size != format1.get_size() && entry.size != format2.get_size())
                    continue;
            }
            
            return entry;
        }
        
        return null;
    }
    
    public int remove_all_tags(Data data, Exif.Tag tag) {
        int count = 0;
        for (int ctr = 0; ctr < (int) Exif.IFD_COUNT; ctr++) {
            Exif.Content content = data.ifd[ctr];
            if (content == null)
                continue;
            
            Exif.Entry entry = content.get_entry(tag);
            if (entry == null)
                continue;
            
            content.remove_entry(entry);
            count++;
        }
        
        return count;
    }
    
    public bool convert_datetime(string datetime, out time_t timestamp) {
        Time tm = Time();
        int count = datetime.scanf("%d:%d:%d %d:%d:%d", &tm.year, &tm.month, &tm.day, &tm.hour,
            &tm.minute, &tm.second);
        if (count != 6)
            return false;
        
        // watch for bogus timestamps
        if (tm.year <= 1900 || tm.month <= 0 || tm.day < 0 || tm.hour < 0 || tm.minute < 0 || tm.second < 0)
            return false;
        
        tm.year -= 1900;
        tm.month--;
        tm.isdst = -1;

        timestamp = tm.mktime();
        
        return true;
    }

    public string convert_timestamp(time_t timestamp) {
        return Time.local(timestamp).format("%Y:%m:%d %H:%M:%S");
    }

    public bool get_timestamp(Exif.Data exif, out time_t timestamp) {
        Exif.Entry entry = Exif.find_first_entry(exif, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);

        timestamp = 0;

        if (entry != null) {
            string datetime = entry.get_string();
            if (datetime != null) {
                if (convert_datetime(datetime, out timestamp))
                    return true;
            }
        }
        
        return false;
    }
    
    public void set_timestamp(Exif.Data exif, time_t timestamp) {
        set_datetime(exif, convert_timestamp(timestamp));
    }
    
    public string? get_datetime(Exif.Data exif) {
        Exif.Entry? datetime = find_first_entry(exif, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);
        
        return (datetime != null) ? datetime.get_string() : null;
    }

    public void set_datetime(Exif.Data exif, string datetime) {
        Entry entry = find_first_entry(exif, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);
        if (entry == null)
            entry = alloc_entry(exif, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);
        
        realloc_ascii(entry, datetime);
    }
    
    private double rational_to_double(Exif.Rational rational) {
        return (((double) rational.numerator) / ((double) rational.denominator));
    }

    public Orientation get_orientation(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry == null)
            return Orientation.TOP_LEFT;
        
        int o = Exif.Convert.get_short(entry.data, exif.get_byte_order());
        if (o < (int) Orientation.MIN || o > (int) Orientation.MAX)
            return Orientation.TOP_LEFT;
        
        return (Orientation) o;
    }
    
    public void set_orientation(ref Exif.Data exif, Orientation orientation) {
        Exif.Entry entry = find_first_entry(exif, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry == null)
            entry = alloc_entry(exif, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        
        Exif.Convert.set_short(entry.data, exif.get_byte_order(), orientation);
    }

    public bool get_dimensions(Exif.Data exif, out Dimensions dim) {
        dim = Dimensions();

        Exif.Entry width = find_first_entry_multiformat(exif, Exif.Tag.PIXEL_X_DIMENSION,
            Exif.Format.SHORT, Exif.Format.LONG);
        Exif.Entry height = find_first_entry_multiformat(exif, Exif.Tag.PIXEL_Y_DIMENSION,
            Exif.Format.SHORT, Exif.Format.LONG);
        if ((width == null) || (height == null))
            return false;
        
        if (width.format == Exif.Format.SHORT)
            dim.width = Exif.Convert.get_short(width.data, exif.get_byte_order());
        else if (width.format == Exif.Format.LONG)
            dim.width = (int) Exif.Convert.get_long(width.data, exif.get_byte_order());
        else
            return false;
        
        if (height.format == Exif.Format.SHORT)
            dim.height = Exif.Convert.get_short(height.data, exif.get_byte_order());
        else if (height.format == Exif.Format.LONG)
            dim.height = (int) Exif.Convert.get_long(height.data, exif.get_byte_order());
        else
            return false;
        
        return true;
    }
    
    // TODO: If dimensions are being overwritten and they're SHORTs, and the new dimensions are
    // greater than uint16.MAX, need to remove the old ones and add new LONGs.
    public void set_dimensions(ref Exif.Data exif, Dimensions dim) {
        Exif.Entry width = find_first_entry_multiformat(exif, Exif.Tag.PIXEL_X_DIMENSION,
            Exif.Format.SHORT, Exif.Format.LONG);
        if (width == null)
            width = alloc_entry(exif, Exif.Tag.PIXEL_X_DIMENSION, Exif.Format.LONG);
        
        Exif.Entry height = Exif.find_first_entry_multiformat(exif, Exif.Tag.PIXEL_Y_DIMENSION,
            Exif.Format.SHORT, Exif.Format.LONG);
        if (height == null)
            height = alloc_entry(exif, Exif.Tag.PIXEL_Y_DIMENSION, Exif.Format.LONG);
        
        if (width.format == Exif.Format.SHORT)
            Exif.Convert.set_short(width.data, exif.get_byte_order(), (uint16) dim.width);
        else if (width.format == Exif.Format.LONG)
            Exif.Convert.set_long(width.data, exif.get_byte_order(), dim.width);
        else
            realloc_long(exif, width, dim.width);
        
        if (height.format == Exif.Format.SHORT)
            Exif.Convert.set_short(height.data, exif.get_byte_order(), (uint16) dim.height);
        else if (height.format == Exif.Format.LONG)
            Exif.Convert.set_long(height.data, exif.get_byte_order(), dim.height);
        else
            realloc_long(exif, height, dim.height);
    }

    public string get_exposure(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.EXPOSURE_TIME, Format.RATIONAL);
        
        return (entry != null) ? entry.get_string() : "";
    }

    public string get_aperture(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.FNUMBER, Format.RATIONAL);
        
        return entry != null ? entry.get_string() : "";
    }

    public string get_iso(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.ISO_SPEED_RATINGS, Format.SHORT);
        
        return entry != null ? entry.get_string() : "";
    }

    public string get_camera_make(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.MAKE, Format.ASCII);
        
        return (entry != null) ? entry.get_string() : "";
    }

    public string get_camera_model(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.MODEL, Format.ASCII);
        
        return entry != null ? entry.get_string() : "";
    }


    public string get_flash(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.FLASH, Format.SHORT);
        
        return entry != null ? entry.get_string() : "";
    }


    public string get_focal_length(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.FOCAL_LENGTH, Format.RATIONAL);
        
        return entry != null ? entry.get_string() : "";
    }

    private Exif.Rational[] get_gps_rationals(Exif.Entry entry, Exif.ByteOrder byte_order) {
        Exif.Rational[] rationals = new Exif.Rational[3];

        uchar* data = entry.data;

        rationals[0] = Exif.Convert.get_rational(data, byte_order);
        data += entry.format.get_size();
        rationals[1] = Exif.Convert.get_rational(data, byte_order);
        data += entry.format.get_size();
        rationals[2] = Exif.Convert.get_rational(data, byte_order);

        return rationals;
    }

    public Exif.Rational[]? get_raw_gps_lat(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.GPS_LATITUDE, Format.RATIONAL, 3);

        return entry != null ? get_gps_rationals(entry, exif.get_byte_order()) : null;
    }

    public Exif.Rational[]? get_raw_gps_long(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.GPS_LONGITUDE, Format.RATIONAL, 3);

        return entry != null ? get_gps_rationals(entry, exif.get_byte_order()) : null;
    }

    private double get_angle(Exif.Rational[] rationals) {
        return rational_to_double(rationals[0]) + ((1.0 / 60.0) * rational_to_double(rationals[1])) +
            ((1.0 / 360.0) * rational_to_double(rationals[2]));
    }

    public double get_gps_lat(Exif.Data exif) {
        Exif.Rational[] rationals = get_raw_gps_lat(exif);
        
        return rationals != null ? get_angle(rationals) : -1;
    }

    public double get_gps_long(Exif.Data exif) {
        Exif.Rational[] rationals = get_raw_gps_long(exif);

        return rationals != null ? get_angle(rationals) : -1;
    }

    public string get_gps_lat_ref(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.GPS_LATITUDE_REF, Format.ASCII);

        return entry != null ? entry.get_string() : "";
    }

    public string get_gps_long_ref(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.GPS_LONGITUDE_REF, Format.ASCII);

        return entry != null ? entry.get_string() : "";
    }

    public string get_artist(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.ARTIST, Format.ASCII);

        return entry != null ? entry.get_string() : "";
    }

    public string get_copyright(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.COPYRIGHT, Format.ASCII);

        return entry != null ? entry.get_string() : "";
    }

    public string get_software(Exif.Data exif) {
        Exif.Entry entry = find_first_entry(exif, Tag.SOFTWARE, Format.ASCII);

        return entry != null ? entry.get_string() : "";
    }
}

public errordomain ExifError {
    FILE_FORMAT
}

public class PhotoExif  {
    private File file;
    private Exif.Data exif = new Exif.Data();
    
    public PhotoExif(File file) {
        this.file = file;
        
        // TODO: Assuming JPEG; in future, will need to detect file type and select proper image
        // data arrangement
        exif.set_data_type(Exif.DataType.COMPRESSED);
    }
    
    public void load() throws Error, ExifError {
        size_t raw_length;
        uint8[]? raw = get_raw_exif(out raw_length);
        if (raw == null)
            throw new ExifError.FILE_FORMAT("EXIF not found in %s", file.get_path());
        
        exif = Exif.Data.new_from_data(raw, raw_length);
        // TODO: Assuming JPEG; in future, will need to detect file type and select proper
        // image data arrangement (note that new_from_data(), new_from_file(), and the other
        // variants don't set this automatically)
        exif.set_data_type(Exif.DataType.COMPRESSED);
        
        // fix now, all at once
        exif.fix();
    }
    
    public bool query_has_exif() {
        // because libexif will return an empty Data structure for files with no EXIF, manually
        // take a peek for ourselves and get the skinny
        try {
            size_t raw_length;
            return get_raw_exif(out raw_length) != null;
        } catch (Error err) {
            warning("Unable to load EXIF from %s: %s", file.get_path(), err.message);
            
            return false;
        }
    }
    
    // Returns raw bytes for the EXIF data, including signature and thumbnail
    public uint8[]? get_raw_exif(out size_t raw_length) throws Error {
        FileInputStream fins = file.read(null);
        
        Jpeg.Marker marker;
        int segment_length;

        // first marker should be SOI
        segment_length = Jpeg.read_marker(fins, out marker);
        if ((marker != Jpeg.Marker.SOI) || (segment_length != 0)) {
            warning("No SOI marker found in %s", file.get_path());
            
            return null;
        }
        
        // find first APP1 marker that is EXIF and use that
        uint8[] raw = null;
        for (;;) {
            segment_length = Jpeg.read_marker(fins, out marker);
            if (segment_length == -1) {
                // EOS
                return null;
            }
            
            if (marker != Jpeg.Marker.APP1 || segment_length < Exif.SIGNATURE.length) {
                if (segment_length > 0)
                    fins.skip(segment_length, null);
                
                continue;
            }
            
            // read in the APP1 segment
            raw = new uint8[segment_length];
            
            size_t bytes_read;
            fins.read_all(raw, raw.length, out bytes_read, null);
            if (bytes_read != raw.length) {
                warning("Unable to read full segment in %s", file.get_path());
                
                // don't attempt to resynchronize (because this condition probably means EOF), but 
                // move on
                continue;
            }
            
            // verify signature
            if (Memory.cmp(raw, Exif.SIGNATURE, Exif.SIGNATURE.length) != 0) {
                warning("Invalid EXIF signature in APP1 segment of %s", file.get_path());
                
                continue;
            }
            
            // Although read_marker removes the length of the length bytes from the segment, it
            // appears at least one camera produces JPEGS with the segment reported size still two bytes
            // longer than it should be (due to it not including the length field in the size itself)?
            // This checks if the size overshot and needs to be reduced.
            if (raw[segment_length - 2] == Jpeg.MARKER_PREFIX) {
                segment_length -= 2;
                if (segment_length <= 0) {
                    warning("Detected invalid length field in too-short EXIF segment in %s",
                        file.get_path());
                    
                    continue;
                }
            }
            
            // do this last, as size_t is unsigned and therefore can't catch underflow
            raw_length = segment_length;
            
            // found it, done
            break;
        }
        
        if (marker != Jpeg.Marker.APP1 || raw == null) {
            warning("No APP1 marker found in %s", file.get_path());
            
            return null;
        }
        
        return raw;
    }
    
    // Returns the MD5 hash for the EXIF (excluding thumbnail)
    public string? get_md5() {
        int flattened_size;
        uchar *flattened = flatten_sans_thumbnail(out flattened_size);
        if (flattened == null)
            return null;
        
        string md5 = md5_binary(flattened, flattened_size);
        
        Exif.Mem.new_default().free(flattened);
        
        return md5;
    }
    
    // Returns the MD5 hash of the thumbnail
    public string? get_thumbnail_md5() {
        return (exif.data != null && exif.size > 0) ? md5_binary(exif.data, exif.size) : null;
    }
    
    public Exif.Data get_exif() {
        return exif;
    }
    
    public void set_exif(Exif.Data exif) {
        this.exif = exif;
    }
    
    public Orientation get_orientation() {
        return Exif.get_orientation(exif);
    }
    
    public void set_orientation(Orientation orientation) {
        Exif.set_orientation(ref exif, orientation);
    }
    
    public bool get_dimensions(out Dimensions dim) {
        return Exif.get_dimensions(exif, out dim);
    }
    
    public void set_dimensions(Dimensions dim) {
        Exif.set_dimensions(ref exif, dim);
    }
    
    public string? get_datetime() {
        return Exif.get_datetime(exif);
    }

    public void set_datetime(string datetime) {
        Exif.set_datetime(exif, datetime);
    }
    
    public bool get_timestamp(out time_t timestamp) {
        return Exif.get_timestamp(exif, out timestamp);
    }

    public void set_timestamp(time_t timestamp) {
        Exif.set_timestamp(exif, timestamp);
    }
    
    public int remove_all_tags(Exif.Tag tag) {
        return Exif.remove_all_tags(exif, tag);
    }
    
    public bool remove_thumbnail() {
        if (exif.data == null)
            return false;
        
        Exif.Mem.new_default().free(exif.data);
        exif.data = null;
        exif.size = 0;
        
        return true;
    }
    
    // Returned pointer must be freed with Exif.Mem.free()
    private uchar *flatten(out int size) {
        uchar *flattened = null;
        int flattened_size = 0;
        exif.save_data(&flattened, &flattened_size);
        
        size = flattened_size;
        
        return flattened;
    }
    
    // Returned pointer must be freed with Exif.Mem.free()
    private uchar *flatten_sans_thumbnail(out int size) {
        // save thumbnail pointer and size during operation
        uchar *thumbnail = exif.data;
        uint thumbnail_size = exif.size;
        
        exif.data = null;
        exif.size = 0;
        
        uchar *flattened = null;
        int flattened_size = 0;
        exif.save_data(&flattened, &flattened_size);
        
        size = flattened_size;
        
        // restore thumbnail
        exif.data = thumbnail;
        exif.size = thumbnail_size;
        
        return flattened;
    }
    
    public void commit() throws Error {
        FileInputStream fins = file.read(null);
        
        Jpeg.Marker marker;
        int segment_length;
        bool original_has_exif = false;

        // first marker is always SOI
        segment_length = Jpeg.read_marker(fins, out marker);
        if ((marker != Jpeg.Marker.SOI) || (segment_length != 0))
            throw new ExifError.FILE_FORMAT("SOI not found in %s".printf(file.get_path()));
        
        segment_length = Jpeg.read_marker(fins, out marker);

        // skip any APP0 (drop JFIF)
        if (marker == Jpeg.Marker.APP0) {
            fins.skip(segment_length, null);
            segment_length = Jpeg.read_marker(fins, out marker);
        }
        
        if (marker == Jpeg.Marker.APP1)
            original_has_exif = true;
            
        // flatten exif to buffer
        int flattened_size = 0;
        uchar *flattened = flatten(out flattened_size);
        assert(flattened != null);
        assert(flattened_size > 0);
        
        try {
            if ((flattened_size == segment_length) && original_has_exif) {
                // the new EXIF data is exactly the same size as the data in the file, so simply
                // overwrite

                debug("Writing EXIF in-place of %d bytes to %s", flattened_size, file.get_path());
                
                // close for reading
                fins.close(null);
                fins = null;
                
                // open for writing ... don't use FileOutputStream, as it will overwrite everything
                // it seeks over
                FStream fs = FStream.open(file.get_path(), "r+");
                if (fs == null)
                    throw new IOError.FAILED("%s: fopen() error".printf(file.get_path()));
                
                // seek over Marker:SOI, Marker:APP1, and length (none change)
                if (fs.seek(2 + 2 + 2, FileSeek.SET) < 0)
                    throw new IOError.FAILED("%s: fseek() error %d", file.get_path(), fs.error());

                // write data in over current EXIF
                size_t count_written = fs.write(flattened, flattened_size, 1);
                if (count_written != 1)
                    throw new IOError.FAILED("%s: fwrite() error %d", file.get_path(), errno);
            } else {
                // create a new photo file with the updated EXIF and move it on top of the old one
                File temp = null;
                FileOutputStream fouts = create_temp(file, out temp);
                size_t bytes_written = 0;
                
                debug("Building new file at %s with %d bytes EXIF, overwriting %s", 
                    temp.get_path(), flattened_size, file.get_path());

                // write SOI
                Jpeg.write_marker(fouts, Jpeg.Marker.SOI, 0);

                // skip past APP1
                if (original_has_exif)
                    fins.skip(segment_length, null);

                // write APP1 with EXIF data
                Jpeg.write_marker(fouts, Jpeg.Marker.APP1, flattened_size);
                fouts.write_all(flattened, flattened_size, out bytes_written, null);
                assert(bytes_written == flattened_size);
                
                // if original has no EXIF, need to write the marker read in earlier
                if (!original_has_exif)
                    Jpeg.write_marker(fouts, marker, segment_length);
                
                // copy remainder of file into new file
                uint8[] copy_buffer = new uint8[64 * 1024];
                for(;;) {
                    ssize_t bytes_read = fins.read(copy_buffer, copy_buffer.length, null);
                    if (bytes_read == 0)
                        break;
                    
                    assert(bytes_read > 0);
                    
                    fouts.write_all(copy_buffer, bytes_read, out bytes_written, null);
                    assert(bytes_written == bytes_read);
                }
                
                // close both for move
                fouts.close(null);
                fins.close(null);
                
                temp.move(file, FileCopyFlags.OVERWRITE, null, null);
            }
        } finally {
            Exif.Mem.new_default().free(flattened);
        }
    }
    
    private static FileOutputStream? create_temp(File original, out File temp) throws Error {
        File parent = original.get_parent();
        assert(parent != null);
        
        for (int ctr = 0; ctr < int.MAX; ctr++) {
            File t = parent.get_child("shotwell.%08X.tmp".printf(ctr));
            FileOutputStream fouts = t.create(FileCreateFlags.PRIVATE, null);
            if (fouts != null) {
                temp = t;
                
                return fouts;
            }
        }
        
        return null;
    }
}

