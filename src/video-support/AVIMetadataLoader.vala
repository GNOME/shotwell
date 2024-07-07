public class AVIMetadataLoader {

    public static TimeZone local = new TimeZone.local();

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
        return new MetadataDateTime(get_creation_date_time_for_avi());
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
    private DateTime? parse_date(string sdate) {
        if (sdate.length == 0) {
            return null;
        }

        int year, month, day, hour, min, sec;
        char weekday[4];
        char monthstr[4];
        DateTime parsed_date;

        if (sdate[0].isdigit()) {
            // Format is: 2005:08:17 11:42:43
            // Format is: 2010/11/30/ 19:42
            // Format is: 2010/11/30 19:42
            string tmp = sdate.dup();
            tmp.canon("0123456789 ", ' '); // strip everything but numbers and spaces
            sec = 0;
            int result = tmp.scanf("%d %d %d %d %d %d", out year, out month, out day, out hour, out min, out sec);
            if(result < 5) {
                return null;
            }

            parsed_date = new DateTime.utc(year, month, day, hour, min, sec);
        } else {
            // Format is: Mon Mar  3 09:44:56 2008
            if(7 != sdate.scanf("%3s %3s %d %d:%d:%d %d", weekday, monthstr, out day, out hour,
                  out min, out sec, out year)) {
                return null; // Error
            }
            parsed_date = new DateTime(AVIMetadataLoader.local, year, month_from_string((string)monthstr), day, hour, min, sec);
        }

        return parsed_date;
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

    private DateTime? get_creation_date_time_for_avi() {
        AVIChunk chunk = new AVIChunk(file);
        DateTime? timestamp = null;
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
