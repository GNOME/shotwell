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
        update();
        
        if (no_exif)
            return false;
        
        // because libexif will return an empty Data structure for files with no EXIF, manually
        // take a peek for ourselves and get the skinny
        try {
            FileInputStream fins = file.read(null);
            
            Jpeg.Marker marker;
            int segment_length;

            // first marker should be SOI
            segment_length = Jpeg.read_marker(fins, out marker);
            if ((marker != Jpeg.Marker.SOI) || (segment_length != 0)) {
                no_exif = true;
                
                return false;
            }
            
            // for EXIF, next marker is always APP1
            segment_length = Jpeg.read_marker(fins, out marker);
            if ((marker != Jpeg.Marker.APP1) || (segment_length < 0)) {
                no_exif = true;
                
                return false;
            }
            
            uint8[] sig = new uint8[Exif.SIGNATURE.length];
            size_t bytes_read;
            fins.read_all(sig, Exif.SIGNATURE.length, out bytes_read, null);
            if (bytes_read != Exif.SIGNATURE.length) {
                no_exif = true;
                
                return false;
            }
            
            for (int ctr = 0; ctr < Exif.SIGNATURE.length; ctr++) {
                if (sig[ctr] != Exif.SIGNATURE[ctr]) {
                    no_exif = true;

                    return false;
                }
            }
            
            no_exif = false;
            
            return true;
        } catch (Error err) {
            debug("Error checking for EXIF presence: %s", err.message);
        }
        
        no_exif = true;
        
        return false;
    }
    
    public Exif.Data? get_exif() {
        if (exif != null)
            return exif;
        
        if (!has_exif())
            return null;
            
        update();

        return null;
    }
    
    public void set_exif(Exif.Data exif) {
        this.exif = exif;
        no_exif = false;
    }
    
    public Orientation get_orientation() {
        update();
        
        Exif.Entry entry = find_entry(Exif.Ifd.ZERO, Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry == null)
            return Orientation.TOP_LEFT;
        
        int o = Exif.Convert.get_short(entry.data, exif.get_byte_order());
        if (o < (int) Orientation.MIN || o > (int) Orientation.MAX)
            return Orientation.TOP_LEFT;
        
        return (Orientation) o;
    }
    
    public void set_orientation(Orientation orientation) {
        update();
        
        Exif.Entry entry = find_first_entry(Exif.Tag.ORIENTATION, Exif.Format.SHORT);
        if (entry == null) {
            // TODO: Need a fall-back here
            error("Unable to set orientation: no entry found");
        }
        
        Exif.Convert.set_short(entry.data, exif.get_byte_order(), orientation);
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
        
        Exif.Entry datetime = find_entry(Exif.Ifd.EXIF, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);
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
    
    private Exif.Entry? find_entry(Exif.Ifd ifd, Exif.Tag tag, Exif.Format format) {
        assert(exif != null);
        
        Exif.Content content = exif.ifd[(int) ifd];
        assert(content != null);
        
        Exif.Entry entry = content.get_entry(tag);
        if (entry == null)
            return null;
        
        assert(entry.format == format);
        if ((format != Exif.Format.ASCII) && (format != Exif.Format.UNDEFINED))
            assert(entry.size == format.get_size());
        
        return entry;
    }
    
    private Exif.Entry? find_first_entry(Exif.Tag tag, Exif.Format format) {
        assert(exif != null);
        
        return Exif.find_first_entry(exif, tag, format);
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

