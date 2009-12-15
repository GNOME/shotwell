/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace Exif {
    // "Exif"
    public const uint8[] SIGNATURE = { 0x45, 0x78, 0x69, 0x66 };

    public Exif.Entry? find_first_entry(Data data, Exif.Tag tag, Exif.Format format) {
        for (int ctr = 0; ctr < (int) Exif.IFD_COUNT; ctr++) {
            Exif.Content content = data.ifd[ctr];
            assert(content != null);
            
            Exif.Entry entry = content.get_entry(tag);
            if (entry == null)
                continue;
            
            assert(entry.format == format);
            if ((format != Exif.Format.ASCII) && (format != Exif.Format.UNDEFINED))
                assert(entry.size == format.get_size());
            
            return entry;
        }
        
        return null;
    }
    
    public int remove_all_tags(Data data, Exif.Tag tag) {
        int count = 0;
        for (int ctr = 0; ctr < (int) Exif.IFD_COUNT; ctr++) {
            Exif.Content content = data.ifd[ctr];
            assert(content != null);
            
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
        if (tm.year <= 1900 || tm.month <= 0)
            return false;
        
        tm.year -= 1900;
        tm.month--;
        tm.isdst = -1;

        timestamp = tm.mktime();
        
        return true;
    }

    public bool get_timestamp(Exif.Data exif, out time_t timestamp) {
        Exif.Entry entry = Exif.find_first_entry(exif, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);
        if (entry != null) {
            string datetime = entry.get_value();
            if (datetime != null) {
                if (convert_datetime(datetime, out timestamp))
                    return true;
            }
        }
        
        return false;
    }

    private Exif.Entry? find_entry(Exif.Data exif, Exif.Ifd ifd, Exif.Tag tag, Exif.Format format, int size = 1) {
        assert(exif != null);
        
        Exif.Content content = exif.ifd[(int) ifd];
        assert(content != null);
        
        Exif.Entry entry = content.get_entry(tag);
        if (entry == null)
            return null;
        
        assert(entry.format == format);
        if ((format != Exif.Format.ASCII) && (format != Exif.Format.UNDEFINED))
            assert(entry.size == format.get_size() * size);
        
        return entry;
    }

    private Exif.Entry? find_entry_multiformat(Exif.Data exif, Exif.Ifd ifd, Exif.Tag tag,
        Exif.Format format1, Exif.Format format2) {
        assert(exif != null);
        
        Exif.Content content = exif.ifd[(int) ifd];
        assert(content != null);
        
        Exif.Entry entry = content.get_entry(tag);
        if (entry == null)
            return null;
        
        assert((entry.format == format1) || (entry.format == format2));
        if ((entry.format != Exif.Format.ASCII) && (entry.format != Exif.Format.UNDEFINED))
            assert((entry.size == format1.get_size()) || (entry.size == format2.get_size()));
        
        return entry;
    }

    private double rational_to_double(Exif.Rational rational) {
        return (((double) rational.numerator) / ((double) rational.denominator));
    }

    public Orientation get_orientation(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.ZERO, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry == null)
            return Orientation.TOP_LEFT;
        
        int o = Exif.Convert.get_short(entry.data, exif.get_byte_order());
        if (o < (int) Orientation.MIN || o > (int) Orientation.MAX)
            return Orientation.TOP_LEFT;
        
        return (Orientation) o;
    }
    
    public void set_orientation(ref Exif.Data exif, Orientation orientation) {
        Exif.Entry entry = find_first_entry(exif, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry == null) {
            // TODO: Need a fall-back here
            error("Unable to set orientation: no entry found");
        }
        
        Exif.Convert.set_short(entry.data, exif.get_byte_order(), orientation);
    }

    public bool get_dimensions(Exif.Data exif, out Dimensions dim) {
        Exif.Entry width = find_entry_multiformat(exif, Exif.Ifd.EXIF, 
            Exif.Tag.PIXEL_X_DIMENSION, Exif.Format.SHORT, Exif.Format.LONG);
        Exif.Entry height = find_entry_multiformat(exif, Exif.Ifd.EXIF,
            Exif.Tag.PIXEL_Y_DIMENSION, Exif.Format.SHORT, Exif.Format.LONG);
        if ((width == null) || (height == null))
            return false;

        if (width.format == Exif.Format.SHORT) {
            dim.width = Exif.Convert.get_short(width.data, exif.get_byte_order());
        } else {
            assert(width.format == Exif.Format.LONG);

            dim.width = (int) Exif.Convert.get_long(width.data, exif.get_byte_order());
        }

        if (height.format == Exif.Format.SHORT) {
            dim.height = Exif.Convert.get_short(height.data, exif.get_byte_order());
        } else {
            assert(height.format == Exif.Format.LONG);

            dim.height = (int) Exif.Convert.get_long(height.data, exif.get_byte_order());
        }
        
        return true;
    }

    public void set_dimensions(ref Exif.Data exif, Dimensions dim) {
        Exif.Entry width = Exif.find_entry_multiformat(exif, Exif.Ifd.EXIF,
            Exif.Tag.PIXEL_X_DIMENSION, Exif.Format.SHORT, Exif.Format.LONG);
        Exif.Entry height = Exif.find_entry_multiformat(exif, Exif.Ifd.EXIF,
            Exif.Tag.PIXEL_Y_DIMENSION, Exif.Format.SHORT, Exif.Format.LONG);
        if ((width == null) || (height == null))
            return;
        
        if (width.format == Exif.Format.SHORT) {
            Exif.Convert.set_short(width.data, exif.get_byte_order(), (uint16) dim.width);
        } else {
            assert(width.format == Exif.Format.LONG);
            
            Exif.Convert.set_long(width.data, exif.get_byte_order(), dim.width);
        }
        
        if (height.format == Exif.Format.SHORT) {
            Exif.Convert.set_short(height.data, exif.get_byte_order(), (uint16) dim.height);
        } else {
            assert(height.format == Exif.Format.LONG);
            
            Exif.Convert.set_long(height.data, exif.get_byte_order(), dim.height);
        }
    }

    public string get_exposure(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.EXIF, Exif.Tag.EXPOSURE_TIME, Exif.Format.RATIONAL);

        if (entry == null)
            return "";

        Exif.Rational exposure = Exif.Convert.get_rational(entry.data, exif.get_byte_order());

        if (rational_to_double(exposure) >= 1) {
            return "%f s".printf(rational_to_double(exposure));
        } else {
            // round to the nearest five

            int denominator = (int) exposure.denominator;

            if (denominator > 10) {
                int off = denominator % 5;
                denominator += (off >= 3) ? 5 - off : -1 * off;
            }
            
            return "%d/%d s".printf((int) exposure.numerator, denominator);
        }
    }

    public string get_aperture(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.EXIF, Exif.Tag.FNUMBER, Exif.Format.RATIONAL);

        if (entry == null)
            return "";

        return entry.get_value();
    }

    public string get_iso(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.EXIF, Exif.Tag.ISO_SPEED_RATINGS, Exif.Format.SHORT);

        if (entry == null)
            return "";

        return entry.get_value();
    }

    public string get_camera_make(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.ZERO, Exif.Tag.MAKE, Exif.Format.ASCII);

        if (entry == null)
            return "";

        return entry.get_value();
    }

    public string get_camera_model(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.ZERO, Exif.Tag.MODEL, Exif.Format.ASCII);

        if (entry == null)
            return "";

        return entry.get_value();
    }


    public string get_flash(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.EXIF, Exif.Tag.FLASH, Exif.Format.SHORT);

        if (entry == null)
            return "";

        return entry.get_value();
    }


    public string get_focal_length(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.EXIF, Exif.Tag.FOCAL_LENGTH,
            Exif.Format.RATIONAL);

        if (entry == null)
            return "";

        return entry.get_value();
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
        Exif.Entry entry = find_entry(exif, Exif.Ifd.GPS, Exif.Tag.GPS_LATITUDE,
            Exif.Format.RATIONAL, 3);

        if (entry == null)
            return null;

        return get_gps_rationals(entry, exif.get_byte_order());
    }

    public Exif.Rational[]? get_raw_gps_long(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.GPS, Exif.Tag.GPS_LONGITUDE,
            Exif.Format.RATIONAL, 3);

        if (entry == null)
            return null;

        return get_gps_rationals(entry, exif.get_byte_order());
    }

    private double get_angle(Exif.Rational[] rationals) {
        return rational_to_double(rationals[0]) + ((1.0 / 60.0) * rational_to_double(rationals[1])) +
            ((1.0 / 360.0) * rational_to_double(rationals[2]));
    }

    public double get_gps_lat(Exif.Data exif) {
        Exif.Rational[] rationals = get_raw_gps_lat(exif);
        if (rationals == null)
            return -1;

        return get_angle(rationals);
    }

    public double get_gps_long(Exif.Data exif) {
        Exif.Rational[] rationals = get_raw_gps_long(exif);

        if (rationals == null)
            return -1;

        return get_angle(rationals);
    }

    public string get_gps_lat_ref(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.GPS, Exif.Tag.GPS_LATITUDE_REF,
            Exif.Format.ASCII);

        if (entry == null)
            return "";

        return entry.get_value();
    }

    public string get_gps_long_ref(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.GPS, Exif.Tag.GPS_LONGITUDE_REF,
            Exif.Format.ASCII);

        if (entry == null)
            return "";

        return entry.get_value();
    }

    public string get_artist(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.ZERO, Exif.Tag.ARTIST, Exif.Format.ASCII);

        if (entry == null)
            return "";

        return entry.get_value();
    }

    public string get_copyright(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.ZERO, Exif.Tag.COPYRIGHT, Exif.Format.ASCII);

        if (entry == null)
            return "";

        return entry.get_value();
    }

    public string get_software(Exif.Data exif) {
        Exif.Entry entry = find_entry(exif, Exif.Ifd.ZERO, Exif.Tag.SOFTWARE, Exif.Format.ASCII);

        if (entry == null)
            return "";

        return entry.get_value();
    }
}

public errordomain ExifError {
    FILE_FORMAT
}

extern void free(void *ptr);

public class PhotoExif  {
    private File file;
    private Exif.Data exif = null;
    private bool no_exif = false;
    
    public PhotoExif(File file) {
        this.file = file;
    }
    
    public bool has_exif() {
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
    
    // Returns raw bytes for the EXIF data, including signature but not the thumbnail
    public uint8[]? get_raw_exif(out size_t raw_length) throws Error {
        update();
        
        if (no_exif)
            return null;
        
        FileInputStream fins = file.read(null);
        
        Jpeg.Marker marker;
        int segment_length;

        // first marker should be SOI
        segment_length = Jpeg.read_marker(fins, out marker);
        if ((marker != Jpeg.Marker.SOI) || (segment_length != 0)) {
            warning("No SOI marker found in %s", file.get_path());
            
            return null;
        }
        
        // for EXIF, next marker is always APP1
        segment_length = Jpeg.read_marker(fins, out marker);
        if ((marker != Jpeg.Marker.APP1) || (segment_length < Exif.SIGNATURE.length)) {
            warning("No APP1 marker found in %s", file.get_path());
            
            return null;
        }
        
        // since returning all of EXIF block, including signature but not the thumbnail (which is how
        // GPhoto returns it, and therefore makes it easy to compare checksums), allocate full block 
        // and read it all in (that is, use optimism here)
        raw_length = segment_length - exif.size;
        if (raw_length <= 0) {
            warning("No EXIF data to read in %s", file.get_path());
            
            return null;
        }
        
        uint8[] raw = new uint8[raw_length];
        
        size_t bytes_read;
        fins.read_all(raw, raw.length, out bytes_read, null);
        if (bytes_read != raw.length) {
            warning("Unable to read full segment in %s", file.get_path());
            
            return null;
        }
        
        // verify signature
        if (Memory.cmp(raw, Exif.SIGNATURE, Exif.SIGNATURE.length) != 0) {
            warning("Invalid EXIF signature in %s", file.get_path());
            
            return null;
        }
        
        // TODO: Although read_marker removes the length of the length bytes from the segment, it
        // appears at least one camera produces JPEGS with the segment reported size still two bytes
        // longer than it should be (due to it not including the length field in the size itself)?
        // This checks if the size overshot and needs to be reduced.
        if (raw[raw_length - 2] == Jpeg.MARKER_PREFIX)
            raw_length -= 2;
        
        return raw;
    }
    
    // Returns the MD5 hash for the EXIF (excluding thumbnail)
    public string? get_md5() {
        size_t raw_length;
        uint8[] raw = null;
        
        try {
            raw = get_raw_exif(out raw_length);
        } catch (Error err) {
            warning("Unable to get EXIF to calculate checksum for %s: %s", file.get_path(),
                err.message);
        }
        
        if (raw == null || raw_length <= 0)
            return null;
        
        return md5_binary(raw, raw_length);
    }
    
    // Returns the MD5 hash of the thumbnail
    public string? get_thumbnail_md5() {
        Exif.Data data = get_exif();
        if (data == null)
            return null;
        
        if (data.data == null || data.size <= 0)
            return null;
        
        return md5_binary(data.data, data.size);
    }
    
    public Exif.Data? get_exif() {
        if (exif != null)
            return exif;
        
        if (!has_exif())
            return null;
            
        update();

        return exif;
    }
    
    public void set_exif(Exif.Data exif) {
        this.exif = exif;
        no_exif = false;
    }
    
    public Orientation get_orientation() {
        update();
        
        return Exif.get_orientation(exif);
    }
    
    public void set_orientation(Orientation orientation) {
        update();
        
        Exif.set_orientation(ref exif, orientation);
    }
    
    public bool get_dimensions(out Dimensions dim) {
        update();

        return Exif.get_dimensions(exif, out dim);
    }
    
    public void set_dimensions(Dimensions dim) {
        update();

        Exif.set_dimensions(ref exif, dim);
    }
    
    public string? get_datetime() {
        update();
        
        Exif.Entry datetime = Exif.find_entry(exif, Exif.Ifd.EXIF, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);
        if (datetime == null)
            return null;
        
        return datetime.get_value();
    }
    
    public bool get_timestamp(out time_t timestamp) {
        string datetime = get_datetime();
        if (datetime == null)
            return false;
        
        return Exif.convert_datetime(datetime, out timestamp);
    }
    
    public int remove_all_tags(Exif.Tag tag) {
        update();
        
        if (exif == null)
            return 0;
    
        return Exif.remove_all_tags(exif, tag);
    }
    
    public bool remove_thumbnail() {
        update();
        
        if (exif == null)
            return false;
        
        if (exif.data == null)
            return false;
        
        free(exif.data);
        exif.data = null;
        exif.size = 0;
        
        return true;
    }
    
    private void update() {
        if (no_exif)
            return;
            
        // TODO: Update internal data structures if file changes
        if (exif != null)
            return;
        
        exif = Exif.Data.new_from_file(file.get_path());
        if (exif == null) {
            no_exif = true;
            
            return;
        }

        // fix now, all at once
        exif.fix();
    }
    
    public void commit() throws Error {
        if (exif == null)
            return;
        
        FileInputStream fins = file.read(null);
        
        Jpeg.Marker marker;
        int segment_length;
        bool original_has_exif = true;

        // first marker is always SOI
        segment_length = Jpeg.read_marker(fins, out marker);
        if ((marker != Jpeg.Marker.SOI) || (segment_length != 0))
            throw new ExifError.FILE_FORMAT("SOI not found in %s".printf(file.get_path()));
        
        // for EXIF, next marker is always APP1
        segment_length = Jpeg.read_marker(fins, out marker);
        if (segment_length <= 0)
            throw new ExifError.FILE_FORMAT("EXIF APP1 length of %d".printf(segment_length));
        if (marker != Jpeg.Marker.APP1)
            original_has_exif = false;
            
        // flatten exif to buffer
        uchar *flattened = null;
        int flattened_size = 0;
        exif.save_data(&flattened, &flattened_size);
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

                // skip past APP1
                if (original_has_exif)
                    fins.skip(segment_length, null);

                File temp = null;
                FileOutputStream fouts = create_temp(file, out temp);
                size_t bytes_written = 0;
                
                debug("Building new file at %s with %d bytes EXIF, overwriting %s", temp.get_path(),
                    flattened_size, file.get_path());

                // write SOI
                Jpeg.write_marker(fouts, Jpeg.Marker.SOI, 0);
                
                // write APP1 with EXIF data
                Jpeg.write_marker(fouts, Jpeg.Marker.APP1, flattened_size);
                fouts.write_all(flattened, flattened_size, out bytes_written, null);
                assert(bytes_written == flattened_size);
                
                // if original has no EXIF, need to write the marker read in earlier
                if (!original_has_exif) {
                    // if APP0, then it's JFIF, and don't want to write this segment
                    if (marker != Jpeg.Marker.APP0) {
                        Jpeg.write_marker(fouts, marker, segment_length);
                    } else {
                        fins.skip(segment_length, null);
                    }
                }
                
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
            free(flattened);
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

