/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

//
// DataObject
//

public abstract class DataObject {
    private DataCollection member_of = null;

    // This signal is fired when the source of the data is altered in a way that's significant
    // to how it's represented in the application.  This base signal must be called by child
    // classes if the collection it is a member of is to be notified.
    public virtual signal void altered() {
    }
    
    // This signal is fired when some attribute or property of the data is altered, but not its
    // primary representation.  This base signal must be called by child classes if the collection
    // this source is a member of is to be notifed.
    public virtual signal void metadata_altered() {
    }
    
    // XXX: Because the "this" variable is not available in virtual signals, using this method
    // to signal until bug is fixed.
    //
    // See: https://bugzilla.gnome.org/show_bug.cgi?id=593734
    public virtual void notify_altered() {
        // fire signal on self
        altered();
        
        // notify DataCollection
        if (member_of != null)
            member_of.internal_notify_altered(this);
    }
    
    // XXX: Because the "this" variable is not available in virtual signals, using this method
    // to signal until bug is fixed.
    //
    // See: https://bugzilla.gnome.org/show_bug.cgi?id=593734
    public virtual void notify_metadata_altered() {
        // fire signal on self
        metadata_altered();
        
        // notify DataCollection
        if (member_of != null)
            member_of.internal_notify_metadata_altered(this);
    }
    
    public abstract string get_name();
    
    public abstract string to_string();
    
    public DataCollection? get_membership() {
        return member_of;
    }
    
    // This method is only called by DataCollection.
    public void internal_set_membership(DataCollection collection) {
        assert(member_of == null);
        member_of = collection;
    }
    
    // This method is only called by DataCollection
    public void internal_clear_membership() {
        member_of = null;
    }
}

//
// DataSource
// 
// A DataSource is an object that is unique throughout the system.  DataSources
// commonly have external and/or persistent representations, hence they have a notion of being
// destroyed (versus removed or freed).  Several DataViews may exist that reference a single
// DataSource.
//

public abstract class DataSource : DataObject {
    protected delegate void ContactSubscriber(DataView view);
    
    private Gee.ArrayList<DataView> subscribers = new Gee.ArrayList<DataView>();
    private bool in_contact = false;
    private bool marked_for_destroy = false;
    
    public override void notify_altered() {
        // signal reflection
        contact_subscribers(subscriber_altered);
        
        base.notify_altered();
    }
    
    private void subscriber_altered(DataView view) {
        view.notify_altered();
    }
    
    public override void notify_metadata_altered() {
        // signal reflection
        contact_subscribers(subscriber_metadata_altered);
        
        base.notify_metadata_altered();
    }

    private void subscriber_metadata_altered(DataView view) {
        view.notify_metadata_altered();
    }
    
    // This signal is fired prior to the object being destroyed.  It is up to all observers to 
    // drop their references to the DataObject.
    public virtual signal void destroyed() {
    }
    
    // This method is called by SourceCollection.  It should not be called otherwise.
    public void internal_mark_for_destroy() {
        marked_for_destroy = true;
    }

    // This method is called by SourceCollection.  It should not be called otherwise.  To destroy
    // a DataSource, destroy it from its SourceCollection.
    //
    // Child classes should call this base class to ensure that the collection this object is
    // a member of is notified and the signal is properly called.  The collection will remove this
    // object automatically.
    public virtual void destroy() {
        assert(marked_for_destroy);
        
        // notify DataViews first that the source is being destroyed
        contact_subscribers(subscriber_source_destroyed);
        
        // clear the subscriber list
        subscribers.clear();
        
        // propagate the signal
        destroyed();
    }
    
    private void subscriber_source_destroyed(DataView view) {
        view.internal_source_destroyed();
    }

    // DataViews subscribe to the DataSource to inform it of their existance.  Not only does this
    // allow for signal reflection (i.e. DataSource.altered -> DataView.altered) it also makes
    // them first-in-line for notification of destruction, so they can remove themselves from 
    // their ViewCollections automatically.
    //
    // This method is only called by DataView.
    public void internal_subscribe(DataView view) {
        assert(!in_contact);
        
        subscribers.add(view);
    }
    
    // This method is only called by DataView.
    public void internal_unsubscribe(DataView view) {
        assert(!in_contact);
        
        bool removed = subscribers.remove(view);
        assert(removed);
    }
    
    protected void contact_subscribers(ContactSubscriber contact_subscriber) {
        assert(!in_contact);
        
        in_contact = true;
        foreach (DataView view in subscribers)
            contact_subscriber(view);
        in_contact = false;
    }
}

public abstract class ThumbnailSource : DataSource {
    public virtual signal void thumbnail_altered() {
    }
    
    // XXX: Because the "this" variable is not available in virtual signals, using this method
    // to signal until bug is fixed.
    //
    // See: https://bugzilla.gnome.org/show_bug.cgi?id=593734
    public virtual void notify_thumbnail_altered() {
        // fire signal on self
        thumbnail_altered();
        
        // signal reflection
        contact_subscribers(subscriber_thumbnail_altered);
    }
    
    private void subscriber_thumbnail_altered(DataView view) {
        ((ThumbnailView) view).notify_thumbnail_altered();
    }

    public abstract Gdk.Pixbuf? get_thumbnail(int scale) throws Error;
}

public abstract class PhotoSource : ThumbnailSource {
    public abstract time_t get_exposure_time();

    public abstract Dimensions get_dimensions();

    public abstract uint64 get_filesize();

    public abstract Exif.Data? get_exif();
    
    public abstract Gdk.Pixbuf get_pixbuf(Scaling scaling) throws Error;
}

public abstract class EventSource : ThumbnailSource {
    public abstract time_t get_start_time();

    public abstract time_t get_end_time();

    public abstract uint64 get_total_filesize();
    
    public abstract int get_photo_count();
    
    public abstract Gee.Iterable<PhotoSource> get_photos();
}

//
// DataView
//

public class DataView : DataObject {
    private DataSource source;
    private bool selected = false;
    
    public virtual signal void state_changed(bool selected) {
    }
    
    public virtual signal void view_altered() {
    }
    
    public DataView(DataSource source) {
        this.source = source;
        
        // subscribe to the DataSource, which sets up signal reflection and gives the DataView
        // first notification of destruction.
        source.internal_subscribe(this);
    }
    
    // This method is only called by DataSource.  It should not be called otherwise.
    public void internal_source_destroyed() {
        // The DataSource is being destroyed, so remove this view from its ViewCollection.
        ViewCollection vc = get_membership() as ViewCollection;
        if (vc != null) {
            Marker marker = vc.mark(this);
            vc.remove_marked(marker);
        }
    }
    
    public override string get_name() {
        return "View of %s".printf(source.get_name());
    }
    
    public override string to_string() {
        return "%s [%s]".printf(get_name(), source.to_string());
    }
    
    public DataSource get_source() {
        return source;
    }
    
    public bool is_selected() {
        return selected;
    }
    
    // This method is only called by ViewCollection.
    public void internal_set_selected(bool selected) {
        this.selected = selected;
        state_changed(selected);
    }
    
    // This method is only called by ViewCollection.  Returns the toggled state.
    public bool internal_toggle() {
        selected = !selected;
        state_changed(selected);
        
        return selected;
    }

    // XXX: Because the "this" variable is not available in virtual signals, using this method
    // to signal until bug is fixed.
    //
    // See: https://bugzilla.gnome.org/show_bug.cgi?id=593734
    public virtual void notify_view_altered() {
        view_altered();
        
        ViewCollection vc = get_membership() as ViewCollection;
        if (vc != null)
            vc.internal_notify_view_altered(this);
    }
}

public class ThumbnailView : DataView {
    public virtual signal void thumbnail_altered() {
    }
    
    public ThumbnailView(ThumbnailSource source) {
        base(source);
    }

    // XXX: Because the "this" variable is not available in virtual signals, using this method
    // to signal until bug is fixed.
    //
    // See: https://bugzilla.gnome.org/show_bug.cgi?id=593734
    public virtual void notify_thumbnail_altered() {
        // fire signal on self
        thumbnail_altered();
        
        // this also implies the view has changed
        notify_view_altered();
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

public class EventView : ThumbnailView {
    public EventView(EventSource source) {
        base(source);
    }
    
    public EventSource get_event_source() {
        return (EventSource) get_source();
    }
}

