/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class VideoSourceCollection : MediaSourceCollection {
    public enum State {
        UNKNOWN,
        ONLINE,
        OFFLINE,
        TRASH
    }

    public override TransactionController transaction_controller {
        get {
            if (_transaction_controller == null)
                _transaction_controller = new MediaSourceTransactionController(this);

            return _transaction_controller;
        }
    }

    private TransactionController _transaction_controller = null;
    private Gee.MultiMap<uint64?, Video> filesize_to_video =
        new Gee.TreeMultiMap<uint64?, Video>(uint64_compare);

    public VideoSourceCollection() {
        base("VideoSourceCollection", get_video_key);

        get_trashcan().contents_altered.connect(on_trashcan_contents_altered);
        get_offline_bin().contents_altered.connect(on_offline_contents_altered);
    }

    protected override MediaSourceHoldingTank create_trashcan() {
        return new MediaSourceHoldingTank(this, is_video_trashed, get_video_key);
    }

    protected override MediaSourceHoldingTank create_offline_bin() {
        return new MediaSourceHoldingTank(this, is_video_offline, get_video_key);
    }

    public override MediaMonitor create_media_monitor(Workers workers, Cancellable cancellable) {
        return new VideoMonitor(cancellable);
    }

    public override bool holds_type_of_source(DataSource source) {
        return source is Video;
    }

    public override string get_typename() {
        return Video.TYPENAME;
    }

    public override bool is_file_recognized(File file) {
        return VideoReader.is_supported_video_file(file);
    }

    private void on_trashcan_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        trashcan_contents_altered((Gee.Collection<Video>?) added,
            (Gee.Collection<Video>?) removed);
    }

    private void on_offline_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        offline_contents_altered((Gee.Collection<Video>?) added,
            (Gee.Collection<Video>?) removed);
    }

    protected override MediaSource? fetch_by_numeric_id(int64 numeric_id) {
        return fetch(VideoID(numeric_id));
    }

    public static int64 get_video_key(DataSource source) {
        Video video = (Video) source;
        VideoID video_id = video.get_video_id();

        return video_id.id;
    }

    public static bool is_video_trashed(DataSource source) {
        return ((Video) source).is_trashed();
    }

    public static bool is_video_offline(DataSource source) {
        return ((Video) source).is_offline();
    }

    public Video fetch(VideoID video_id) {
        return (Video) fetch_by_key(video_id.id);
    }

    public override Gee.Collection<string> get_event_source_ids(EventID event_id){
        return VideoTable.get_instance().get_event_source_ids(event_id);
    }

    public Video? get_state_by_file(File file, out State state) {
        Video? video = (Video?) fetch_by_master_file(file);
        if (video != null) {
            state = State.ONLINE;

            return video;
        }

        video = (Video?) get_trashcan().fetch_by_master_file(file);
        if (video != null) {
            state = State.TRASH;

            return video;
        }

        video = (Video?) get_offline_bin().fetch_by_master_file(file);
        if (video != null) {
            state = State.OFFLINE;

            return video;
        }

        state = State.UNKNOWN;

        return null;
    }

    private void compare_backing(Video video, FileInfo info, Gee.Collection<Video> matching_master) {
        if (video.get_filesize() != info.get_size())
            return;

        if (video.get_timestamp().equal(coarsify_date_time(info.get_modification_date_time())))
            matching_master.add(video);
    }

    public void fetch_by_matching_backing(FileInfo info, Gee.Collection<Video> matching_master) {
        foreach (DataObject object in get_all())
            compare_backing((Video) object, info, matching_master);

        foreach (MediaSource media in get_offline_bin_contents())
            compare_backing((Video) media, info, matching_master);
    }

    protected override void notify_contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added) {
                Video video = (Video) object;

                filesize_to_video.set(video.get_master_filesize(), video);
            }
        }

        if (removed != null) {
            foreach (DataObject object in removed) {
                Video video = (Video) object;

                filesize_to_video.remove(video.get_master_filesize(), video);
            }
        }

        base.notify_contents_altered(added, removed);
    }

    public VideoID get_basename_filesize_duplicate(string basename, uint64 filesize) {
        foreach (Video video in filesize_to_video.get(filesize)) {
            if (utf8_ci_compare(video.get_master_file().get_basename(), basename) == 0)
                return video.get_video_id();
        }

        return VideoID(); // the default constructor of the VideoID struct creates an invalid
                          // video id, which is just what we want in this case
    }

    public bool has_basename_filesize_duplicate(string basename, uint64 filesize) {
        return get_basename_filesize_duplicate(basename, filesize).is_valid();
    }
}
