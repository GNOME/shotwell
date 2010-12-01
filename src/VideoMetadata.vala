/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class VideoMetadata : MediaMetadata {
    
    private MetadataDateTime timestamp = null;
    private string title = null;
   
    public VideoMetadata() {
    }
    
    ~VideoMetadata() {
    }
    
    public override void read_from_file(File file) throws Error {
        // Check against quicktime.
        QuickTimeMetadataLoader quicktime = new QuickTimeMetadataLoader(file);
        if (quicktime.is_supported()) {
            timestamp = quicktime.get_creation_date_time();
            title = quicktime.get_title();
            return;
        }
        
        throw new IOError.NOT_SUPPORTED("File %s is not a supported video format", file.get_path());
    }
    
    public override MetadataDateTime? get_creation_date_time() {
        return timestamp;
    }
    
    public override string? get_title() {
        return title;
    }
    
}

private class QuickTimeMetadataLoader {

    // Quicktime calendar date/time format is number of seconds since January 1, 1904.
    // This converts to UNIX time (66 years + 17 leap days).
    public static const ulong QUICKTIME_EPOCH_ADJUSTMENT = 2082844800;

    private File file = null;

    public QuickTimeMetadataLoader(File file) throws Error {
        this.file = file;
    }
    
    public MetadataDateTime? get_creation_date_time() {
        return new MetadataDateTime((time_t) get_creation_date_time_for_quicktime());
    }
    
    public string? get_title() {
        // Not supported.
        return null;
    }

    // Checks if the given file is a QuickTime file.
    public bool is_supported() {
        QuickTimeAtom test = new QuickTimeAtom(file);
        
        bool ret = false;
        try {
            test.open_file();
            test.read_atom();
            
            // Look for the header.
            if ("ftyp" == test.get_current_atom_name()) {
                // Read identifier.
                GLib.StringBuilder sb = new GLib.StringBuilder();
                sb.append_c((char)test.read_byte());
                sb.append_c((char)test.read_byte());
                sb.append_c((char)test.read_byte());
                sb.append_c((char)test.read_byte());
                string id_string = sb.str;
            
                if ("qt  " == id_string || "avc1" == id_string) {
                    ret = true;
                }
            } else {
                // Some versions of QuickTime don't have
                // an ftyp section, so we'll just look
                // for the mandatory moov section.
                while(true) {
                    if ("moov" == test.get_current_atom_name()) {
                        ret = true;
                        break;
                    }
                    test.next_atom();
                    test.read_atom();
                    if (test.is_last_atom()) {
                        break;
                    }
                }
            }
            
            test.close_file();
        } catch (GLib.Error e) {
            debug("Error while testing for QuickTime file for %s: %s", file.get_path(), e.message);
        }
        
        return ret;
    }

    private ulong get_creation_date_time_for_quicktime() {
        QuickTimeAtom test = new QuickTimeAtom(file);
        ulong timestamp = 0;
        
        try {
            test.open_file();
            bool done = false;
            while(!done) {
                // Look for "moov" section.
                test.read_atom();
                if (test.is_last_atom()) break;
                if ("moov" == test.get_current_atom_name()) {
                    QuickTimeAtom child = test.get_first_child_atom();
                    while (!done) {
                        // Look for "mvhd" section.
                        child.read_atom();
                        if ("mvhd" == child.get_current_atom_name()) {
                            // Skip 4 bytes (version + flags)
                            child.read_uint32();
                            // Grab the timestamp.
                            timestamp = child.read_uint32() - QUICKTIME_EPOCH_ADJUSTMENT;
                            done = true;
                            break;
                        }
                    }
                }
                test.next_atom();
            }
            test.close_file();
        } catch (GLib.Error e) {
            debug("Error while testing for QuickTime file: %s", e.message);
        }
        return timestamp;
    }
}

private class QuickTimeAtom {
    private GLib.File file = null;
    private string section_name = "";
    private uint64 section_size = 0;
    private uint64 section_offset = 0;
    private GLib.DataInputStream input = null;
    
    public QuickTimeAtom(GLib.File file) {
        this.file = file;
    }
    
    private QuickTimeAtom.with_input_stream(GLib.DataInputStream input) {
        this.input = input;
    }   
    
    public void open_file() throws GLib.Error {
        close_file();
        input = new GLib.DataInputStream(file.read());
        input.set_byte_order(DataStreamByteOrder.BIG_ENDIAN);
        section_size = 0;
        section_offset = 0;
        section_name = "";
    }
    
    public void close_file() throws GLib.Error {
        if (null != input) {
            input.close();
            input = null;
        }
    }    
    
    public QuickTimeAtom get_first_child_atom() {
        // Child will simply have the input stream
        // but not the size/offset.  This works because
        // child atoms follow immediately after a header,
        // so no skipping is required to access the child
        // from the current position.
        return new QuickTimeAtom.with_input_stream(input);
    }
    
    public uchar read_byte() throws GLib.Error {
        section_offset++;
        return input.read_byte();
    }
    
    public uint32 read_uint32() throws GLib.Error {
        section_offset += 4;
        return input.read_uint32();
    }
    
    public uint64 read_uint64() throws GLib.Error {
        section_offset += 8;
        return input.read_uint64();
    }

    public void read_atom() throws GLib.Error {
        // Read atom size.
        section_size = read_uint32();
        
        // Read atom name.
        GLib.StringBuilder sb = new GLib.StringBuilder();
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        section_name = sb.str;
        
        if (1 == section_size) {
            // This indicates the section size is a 64-bit
            // value, specified below the atom name.
            section_size = read_uint64();
        }
    }
    
    public void next_atom() throws GLib.Error {
        // skip() only accepts size_t's, so we may have to
        // break the operation into several increments.
        assert(section_size >= section_offset);
        uint64 skip_amount = section_size - section_offset;
        while (skip_amount > 0) {
            // skip() throws an error if the amount is too large, so check against ssize_t instead
            if (skip_amount >= ssize_t.MAX) {
                input.skip(ssize_t.MAX);
                skip_amount -= ssize_t.MAX;
            } else {
                input.skip((size_t) skip_amount);
                skip_amount = 0;
            }
        }
        section_size = 0;
        section_offset = 0;
    }
    
    public string get_current_atom_name() {
        return section_name;
    }
   
    public bool is_last_atom() {
        return 0 == section_size;
    }
    
}
