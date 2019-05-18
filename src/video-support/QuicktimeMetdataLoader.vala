public class QuickTimeMetadataLoader {

    // Quicktime calendar date/time format is number of seconds since January 1, 1904.
    // This converts to UNIX time (66 years + 17 leap days).
    public const time_t QUICKTIME_EPOCH_ADJUSTMENT = 2082844800;

    private File file = null;

    public QuickTimeMetadataLoader(File file) {
        this.file = file;
    }

    public string get_creation_date_time() {
        return get_creation_date_time_for_quicktime().to_string();
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
