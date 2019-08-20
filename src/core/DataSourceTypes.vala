/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

//
// Media sources
//

public abstract class ThumbnailSource : DataSource {
    public virtual signal void thumbnail_altered() {
    }
    
    protected ThumbnailSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    public virtual void notify_thumbnail_altered() {
        // fire signal on self
        thumbnail_altered();
        
        // signal reflection to DataViews
        contact_subscribers(subscriber_thumbnail_altered);
    }
    
    private void subscriber_thumbnail_altered(DataView view) {
        ((ThumbnailView) view).notify_thumbnail_altered();
    }

    public abstract Gdk.Pixbuf? get_thumbnail(int scale) throws Error;
    
    // get_thumbnail( ) may return a cached pixbuf; create_thumbnail( ) is guaranteed to create
    // a new pixbuf (e.g., by the source loading, decoding, and scaling image data)
    public abstract Gdk.Pixbuf? create_thumbnail(int scale) throws Error;
    
    // A ThumbnailSource may use another ThumbnailSource as its representative.  It's up to the
    // subclass to forward on the appropriate methods to this ThumbnailSource.  But, since multiple
    // ThumbnailSources may be referring to a single ThumbnailSource, this allows for that to be
    // detected and optimized (in caching).
    //
    // Note that it's the responsibility of this ThumbnailSource to fire "thumbnail-altered" if its
    // representative does the same.
    //
    // Default behavior is to return the ID of this.
    public virtual string get_representative_id() {
        return get_source_id();
    }
    
    public abstract PhotoFileFormat get_preferred_thumbnail_format();
}

public abstract class PhotoSource : MediaSource {
    protected PhotoSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }

    public abstract PhotoMetadata? get_metadata();
    
    public abstract Gdk.Pixbuf get_pixbuf(Scaling scaling) throws Error;
}

public abstract class VideoSource : MediaSource {
}

//
// EventSource
//

public abstract class EventSource : ThumbnailSource {
    protected EventSource(int64 object_id = INVALID_OBJECT_ID) {
        base (object_id);
    }
    
    public abstract time_t get_start_time();
    
    public abstract time_t get_end_time();
    
    public abstract uint64 get_total_filesize();
    
    public abstract int get_media_count();
    
    public abstract Gee.Collection<MediaSource> get_media();
    
    public abstract string? get_comment();
    
    public abstract bool set_comment(string? comment);
}

//
// ContainerSource
//

public interface ContainerSource : DataSource {
    public abstract bool has_links();
    
    public abstract SourceBacklink get_backlink();
    
    public abstract void break_link(DataSource source);
    
    public abstract void break_link_many(Gee.Collection<DataSource> sources);
    
    public abstract void establish_link(DataSource source);
    
    public abstract void establish_link_many(Gee.Collection<DataSource> sources);
}


