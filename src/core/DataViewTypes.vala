/* SPDX-FileCopyrightText: 2016 Software Freedom Conservancy Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

public class ThumbnailView : DataView {
    public virtual signal void thumbnail_altered() {
    }
    
    public ThumbnailView(ThumbnailSource source) {
        base(source);
    }
    
    public virtual void notify_thumbnail_altered() {
        // fire signal on self
        thumbnail_altered();
    }
}

public class PhotoView : ThumbnailView {
    public PhotoView(PhotoSource source) {
        base(source);
    }
    
    public PhotoSource get_photo_source() {
        return (PhotoSource) get_source();
    }
}

public class VideoView : ThumbnailView {
    public VideoView(VideoSource source) {
        base(source);
    }
    
    public VideoSource get_video_source() {
        return (VideoSource) get_source();
    }
}

public class EventView : ThumbnailView {
    public EventView(EventSource source) {
        base(source);
    }
    
    public EventSource get_event_source() {
        return (EventSource) get_source();
    }
}

