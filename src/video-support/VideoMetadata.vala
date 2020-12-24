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
