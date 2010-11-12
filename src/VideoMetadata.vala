/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

extern void *lqt_open_read(string filename);
extern int quicktime_close(void *handle);
extern ulong lqt_get_creation_time(void *handle);
extern unowned string? quicktime_get_name(void *handle);

public class VideoMetadata : MediaMetadata {
    // Quicktime calendar date/time format is number of seconds since January 1, 1904.
    // This converts to UNIX time (66 years + 17 leap days).
    private const ulong QUICKTIME_EPOCH_ADJUSTMENT = 2082844800;
    
    private void *lqt_handle = null;
    
    public VideoMetadata() {
    }
    
    ~VideoMetadata() {
        if (lqt_handle != null)
            quicktime_close(lqt_handle);
    }
    
    public override void read_from_file(File file) throws Error {
        lqt_handle = lqt_open_read(file.get_path());
        if (lqt_handle == null)
            throw new IOError.FAILED("Unable to open %s for video reading", file.get_path());
    }
    
    public override MetadataDateTime? get_creation_date_time() {
        if (lqt_handle == null)
            return null;
        
        ulong creation_time = lqt_get_creation_time(lqt_handle);
        if (creation_time < QUICKTIME_EPOCH_ADJUSTMENT)
            return null;
        
        creation_time -= QUICKTIME_EPOCH_ADJUSTMENT;
        
        // Due to a bug in libquicktime, some file formats return current time rather than a stored
        // time ... allow for one second difference in case there's a clock tick, which I don't
        // anticipate, but then again, I don't anticipate a library returning current time for
        // a stored value.
        ulong current_time = (ulong) time_t();
        if (creation_time == current_time)
            return null;
        else if ((creation_time < current_time) && ((current_time - creation_time) <= 1))
            return null;
        else if ((creation_time > current_time) && ((creation_time - current_time) <= 1))
            return null;
        
        return new MetadataDateTime((time_t) creation_time);
    }
    
    public override string? get_title() {
        return (lqt_handle != null) ? quicktime_get_name(lqt_handle) : null;
    }
}

