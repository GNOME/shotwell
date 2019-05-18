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
        var reader = VideoMetadataReader.get_instance();

        var context = new MainContext();
        context.push_thread_default();
        var loop = new MainLoop(context, false);
        AsyncResult result = null;

        reader.read_metadata.begin(file.get_uri(), (obj, res) => {
                result = res;
                loop.quit();
        });
        loop.run();
        var values = reader.read_metadata.end(result);
        context.pop_thread_default();
        timestamp = new MetadataDateTime((time_t) ulong.parse(values[0]));
        title = values[1];
        comment = values[2];
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
