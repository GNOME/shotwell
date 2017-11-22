/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class VideoMetadata : MediaMetadata {
    
    private MetadataDateTime timestamp = null;
    private string title = null;
    private string comment = null;
   
    public VideoMetadata() {
    }
    
    ~VideoMetadata() {
    }
    
    public override void read_from_file(File file) throws Error {
        QuickTimeMetadataLoader quicktime = new QuickTimeMetadataLoader(file);
        if (quicktime.is_supported()) {
            timestamp = quicktime.get_creation_date_time();
            title = quicktime.get_title();
	        // TODO: is there an quicktime.get_comment ??
            comment = null;
            return;
        }    
        AVIMetadataLoader avi = new AVIMetadataLoader(file);
        if (avi.is_supported()) {
            timestamp = avi.get_creation_date_time();
            title = avi.get_title();
            comment = null;
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
    
    public override string? get_comment() {
        return comment;
    }
    
}

private class QuickTimeMetadataLoader {

    // Quicktime calendar date/time format is number of seconds since January 1, 1904.
    // This converts to UNIX time (66 years + 17 leap days).
    public const time_t QUICKTIME_EPOCH_ADJUSTMENT = 2082844800;

    private File file = null;

    public QuickTimeMetadataLoader(File file) {
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
                ret = true;
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
        } catch (GLib.Error e) {
            debug("Error while testing for QuickTime file for %s: %s", file.get_path(), e.message);
        }
        
        try {
            test.close_file();
        } catch (GLib.Error e) {
            debug("Error while closing Quicktime file: %s", e.message);
        }
        return ret;
    }

    private ulong get_creation_date_time_for_quicktime() {
        QuickTimeAtom test = new QuickTimeAtom(file);
        time_t timestamp = 0;
        
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
                        // Look for "mvhd" section, or break if none is found.
                        child.read_atom();
                        if (child.is_last_atom() || 0 == child.section_size_remaining()) {
                            done = true;
                            break;
                        }
                        
                        if ("mvhd" == child.get_current_atom_name()) {
                            // Skip 4 bytes (version + flags)
                            child.read_uint32();
                            // Grab the timestamp.
                            timestamp = child.read_uint32() - QUICKTIME_EPOCH_ADJUSTMENT;
                            done = true;
                            break;
                        }
                        child.next_atom();
                    }
                }
                test.next_atom();
            }
        } catch (GLib.Error e) {
            debug("Error while testing for QuickTime file: %s", e.message);
        }
        
        try {
            test.close_file();
        } catch (GLib.Error e) {
            debug("Error while closing Quicktime file: %s", e.message);
        }
        
        // Some Android phones package videos recorded with their internal cameras in a 3GP
        // container that looks suspiciously like a QuickTime container but really isn't -- for
        // the timestamps of these Android 3GP videos are relative to the UNIX epoch
        // (January 1, 1970) instead of the QuickTime epoch (January 1, 1904). So, if we detect a
        // QuickTime movie with a negative timestamp, we can be pretty sure it isn't a valid
        // QuickTime movie that was shot before 1904 but is instead a non-compliant 3GP video
        // file. If we detect such a video, we correct its time. See this Redmine ticket
        // (http://redmine.yorba.org/issues/3314) for more information.
        if (timestamp < 0)
            timestamp += QUICKTIME_EPOCH_ADJUSTMENT;
        
        return (ulong) timestamp;
    }
}

private class QuickTimeAtom {
    private GLib.File file = null;
    private string section_name = "";
    private uint64 section_size = 0;
    private uint64 section_offset = 0;
    private GLib.DataInputStream input = null;
    private QuickTimeAtom? parent = null;
    
    public QuickTimeAtom(GLib.File file) {
        this.file = file;
    }
    
    private QuickTimeAtom.with_input_stream(GLib.DataInputStream input, QuickTimeAtom parent) {
        this.input = input;
        this.parent = parent;
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
    
    private void advance_section_offset(uint64 amount) {
        section_offset += amount;
        if (null != parent) {
            parent.advance_section_offset(amount);
        }
    }
    
    public QuickTimeAtom get_first_child_atom() {
        // Child will simply have the input stream
        // but not the size/offset.  This works because
        // child atoms follow immediately after a header,
        // so no skipping is required to access the child
        // from the current position.
        return new QuickTimeAtom.with_input_stream(input, this);
    }
    
    public uchar read_byte() throws GLib.Error {
        advance_section_offset(1);
        return input.read_byte();
    }
    
    public uint32 read_uint32() throws GLib.Error {
        advance_section_offset(4);
        return input.read_uint32();
    }
    
    public uint64 read_uint64() throws GLib.Error {
        advance_section_offset(8);
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
        
        // Check string.
        if (section_name.length != 4) {
            throw new IOError.NOT_SUPPORTED("QuickTime atom name length is invalid for %s", 
                file.get_path());
        }
        for (int i = 0; i < section_name.length; i++) {
            if (!section_name[i].isprint()) {
                throw new IOError.NOT_SUPPORTED("Bad QuickTime atom in file %s", file.get_path());
            }
        }
        
        if (1 == section_size) {
            // This indicates the section size is a 64-bit
            // value, specified below the atom name.
            section_size = read_uint64();
        }
    }
    
    private void skip(uint64 skip_amount) throws GLib.Error {
        skip_uint64(input, skip_amount);
    }
    
    public uint64 section_size_remaining() {
        assert(section_size >= section_offset);
        return section_size - section_offset;
    }
    
    public void next_atom() throws GLib.Error {
        skip(section_size_remaining());
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

private class AVIMetadataLoader {

    private File file = null;
    
    // A numerical date string, i.e 2010:01:28 14:54:25
    private const int NUMERICAL_DATE_LENGTH = 19;
    
    // Marker for timestamp section in a Nikon nctg blob.
    private const uint16 NIKON_NCTG_TIMESTAMP_MARKER = 0x13;
    
    // Size limit to ensure we don't parse forever on a bad file.
    private const int MAX_STRD_LENGTH = 100;

    public AVIMetadataLoader(File file) {
        this.file = file;
    }
    
    public MetadataDateTime? get_creation_date_time() {
        return new MetadataDateTime((time_t) get_creation_date_time_for_avi());
    }
    
    public string? get_title() {
        // Not supported.
        return null;
    }

    // Checks if the given file is an AVI file.
    public bool is_supported() {
        AVIChunk chunk = new AVIChunk(file);
        bool ret = false;
        try {
            chunk.open_file();
            chunk.read_chunk();
            // Look for the header and identifier.
            if ("RIFF" == chunk.get_current_chunk_name() &&
                "AVI " == chunk.read_name()) {
                ret = true;
            }
        } catch (GLib.Error e) {
            debug("Error while testing for AVI file: %s", e.message);
        }
        
        try {
            chunk.close_file();
        } catch (GLib.Error e) {
            debug("Error while closing AVI file: %s", e.message);
        } 
        return ret;
    }
    
    // Parses a Nikon nctg tag.  Based losely on avi_read_nikon() in FFmpeg.
    private string read_nikon_nctg_tag(AVIChunk chunk) throws GLib.Error {
        bool found_date = false;
        while (chunk.section_size_remaining() > sizeof(uint16)*2) {
            uint16 tag = chunk.read_uint16();
            uint16 size = chunk.read_uint16();
            if (NIKON_NCTG_TIMESTAMP_MARKER == tag) {
                found_date = true;
                break;
            }
            chunk.skip(size);
        }
        
        if (found_date) {
            // Read numerical date string, example: 2010:01:28 14:54:25
            GLib.StringBuilder sb = new GLib.StringBuilder();
            for (int i = 0; i < NUMERICAL_DATE_LENGTH; i++) {
                sb.append_c((char) chunk.read_byte());
            }
            return sb.str;
        }
        return "";
    }
    
    // Parses a Fujifilm strd tag. Based on information from:
    // http://www.eden-foundation.org/products/code/film_date_stamp/index.html
    private string read_fuji_strd_tag(AVIChunk chunk) throws GLib.Error {
        chunk.skip(98); // Ignore 98-byte binary blob.
        chunk.skip(8); // Ignore the string "FUJIFILM"
        // Read until we find four colons, then two more chars.
        int colons = 0;
        int post_colons = 0;
        GLib.StringBuilder sb = new GLib.StringBuilder();
        // End of date is two chars past the fourth colon.
        while (colons <= 4 && post_colons < 2) {
            char c = (char) chunk.read_byte();
            if (4 == colons) {
                post_colons++;
            }
            if (':' == c) {
                colons++;
            }
            if (c.isprint()) {
                sb.append_c(c);
            }
            if (sb.len > MAX_STRD_LENGTH) {
                return ""; // Give up searching.
            }
        }
        
        if (sb.str.length < NUMERICAL_DATE_LENGTH) {
            return ""; 
        }
        // Date is now at the end of the string.
        return sb.str.substring(sb.str.length - NUMERICAL_DATE_LENGTH);
    }
    
    // Recursively read file until the section is found.
    private string? read_section(AVIChunk chunk) throws GLib.Error {
        while (true) {
            chunk.read_chunk();
            string name = chunk.get_current_chunk_name();
            if ("IDIT" == name) {
                return chunk.section_to_string();
            } else if ("nctg" == name) {
                return read_nikon_nctg_tag(chunk);
            } else if ("strd" == name) {
                return read_fuji_strd_tag(chunk);
            }
            
            if ("LIST" == name) {
                chunk.read_name(); // Read past list name.
                string result = read_section(chunk.get_first_child_chunk());
                if (null != result) {
                    return result;
                }
            }
            
            if (chunk.is_last_chunk()) {
                break;
            }
            chunk.next_chunk();
        }
        return null;
    }
    
    // Parses a date from a string.
    // Largely based on GStreamer's avi/gstavidemux.c 
    // and the information here: 
    // http://www.eden-foundation.org/products/code/film_date_stamp/index.html
    private ulong parse_date(string sdate) {
        if (sdate.length == 0) {
            return 0;
        }
        
        Date date = Date();
        uint seconds = 0;
        int year, month, day, hour, min, sec;
        char weekday[4];
        char monthstr[4];
        
        if (sdate[0].isdigit()) {
            // Format is: 2005:08:17 11:42:43
            // Format is: 2010/11/30/ 19:42
            // Format is: 2010/11/30 19:42
            string tmp = sdate.dup();
            tmp.canon("0123456789 ", ' '); // strip everything but numbers and spaces
            sec = 0;
            int result = tmp.scanf("%d %d %d %d %d %d", out year, out month, out day, out hour, out min, out sec);
            if(result < 5) {
                return 0;
            }
            date.set_dmy((DateDay) day, (DateMonth) month, (DateYear) year);
            seconds = sec + min * 60 + hour * 3600;
        } else {
            // Format is: Mon Mar  3 09:44:56 2008
            if(7 != sdate.scanf("%3s %3s %d %d:%d:%d %d", weekday, monthstr, out day, out hour,
                  out min, out sec, out year)) {
                return 0; // Error
            }
            date.set_dmy((DateDay) day, month_from_string((string) monthstr), (DateYear) year);
            seconds = sec + min * 60 + hour * 3600;
        }
        
        Time time = Time();
        date.to_time(out time);
        
        // watch for overflow (happens on quasi-bogus dates, like Year 200)
        time_t tm = time.mktime();
        ulong result = tm + seconds;
        if (result < tm) {
            debug("Overflow for timestamp in video file %s", file.get_path());
            
            return 0;
        }
        
        return result;
    }
    
    private DateMonth month_from_string(string s) {
        switch (s.down()) {
        case "jan":
            return DateMonth.JANUARY;
        case "feb":
            return DateMonth.FEBRUARY;
        case "mar":
            return DateMonth.MARCH;
        case "apr":
            return DateMonth.APRIL;
        case "may":
            return DateMonth.MAY;
        case "jun":
            return DateMonth.JUNE;
        case "jul":
            return DateMonth.JULY;
        case "aug":
            return DateMonth.AUGUST;
        case "sep":
            return DateMonth.SEPTEMBER;
        case "oct":
            return DateMonth.OCTOBER;
        case "nov":
            return DateMonth.NOVEMBER;
        case "dec":
            return DateMonth.DECEMBER;
        }
        return DateMonth.BAD_MONTH;
    }

    private ulong get_creation_date_time_for_avi() {
        AVIChunk chunk = new AVIChunk(file);
        ulong timestamp = 0;
        try {
            chunk.open_file();
            chunk.nonsection_skip(12); // Advance past 12 byte header.
            string sdate = read_section(chunk);
            if (null != sdate) {
                timestamp = parse_date(sdate.strip());
            }
        } catch (GLib.Error e) {
            debug("Error while reading AVI file: %s", e.message);
        }
        
        try {
            chunk.close_file();
        } catch (GLib.Error e) {
            debug("Error while closing AVI file: %s", e.message);
        } 
        return timestamp;
    }
}

private class AVIChunk {
    private GLib.File file = null;
    private string section_name = "";
    private uint64 section_size = 0;
    private uint64 section_offset = 0;
    private GLib.DataInputStream input = null;
    private AVIChunk? parent = null;
    private const int MAX_STRING_TO_SECTION_LENGTH = 1024;
    
    public AVIChunk(GLib.File file) {
        this.file = file;
    }
    
    private AVIChunk.with_input_stream(GLib.DataInputStream input, AVIChunk parent) {
        this.input = input;
        this.parent = parent;
    }   
    
    public void open_file() throws GLib.Error {
        close_file();
        input = new GLib.DataInputStream(file.read());
        input.set_byte_order(DataStreamByteOrder.LITTLE_ENDIAN);
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
    
    public void nonsection_skip(uint64 skip_amount) throws GLib.Error {
        skip_uint64(input, skip_amount);
    }
    
    public void skip(uint64 skip_amount) throws GLib.Error {
        advance_section_offset(skip_amount);
        skip_uint64(input, skip_amount);
    }
    
    public AVIChunk get_first_child_chunk() {
        return new AVIChunk.with_input_stream(input, this);
    }
    
    private void advance_section_offset(uint64 amount) {
        if ((section_offset + amount) > section_size)
            amount = section_size - section_offset;
        
        section_offset += amount;
        if (null != parent) {
            parent.advance_section_offset(amount);
        }
    }
    
    public uchar read_byte() throws GLib.Error {
        advance_section_offset(1);
        return input.read_byte();
    }
    
    public uint16 read_uint16() throws GLib.Error {
       advance_section_offset(2);
       return input.read_uint16();
    }
    
    public void read_chunk() throws GLib.Error {
        // don't use checked reads here because they advance the section offset, which we're trying
        // to determine here
        GLib.StringBuilder sb = new GLib.StringBuilder();
        sb.append_c((char) input.read_byte());
        sb.append_c((char) input.read_byte());
        sb.append_c((char) input.read_byte());
        sb.append_c((char) input.read_byte());
        section_name = sb.str;
        section_size = input.read_uint32();
        section_offset = 0;
    }
    
    public string read_name() throws GLib.Error {
        GLib.StringBuilder sb = new GLib.StringBuilder();
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        return sb.str;
    }
    
    public void next_chunk() throws GLib.Error {
        skip(section_size_remaining());
        section_size = 0;
        section_offset = 0;
    }
    
    public string get_current_chunk_name() {
        return section_name;
    }
   
    public bool is_last_chunk() {
        return section_size == 0;
    }
    
    public uint64 section_size_remaining() {
        assert(section_size >= section_offset);
        return section_size - section_offset;
    }
    
    // Reads section contents into a string.
    public string section_to_string() throws GLib.Error {
        GLib.StringBuilder sb = new GLib.StringBuilder();
        while (section_offset < section_size) {
            sb.append_c((char) read_byte());
            if (sb.len > MAX_STRING_TO_SECTION_LENGTH) {
                return sb.str;
            }
        }
        return sb.str;
    }
    
}

