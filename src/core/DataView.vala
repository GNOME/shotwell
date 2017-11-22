/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class DataView : DataObject {
    private DataSource source;
    private bool selected = false;
    private bool visible = true;
    
    // Indicates that the selection state has changed.
    public virtual signal void state_changed(bool selected) {
    }
    
    // Indicates the visible state has changed.
    public virtual signal void visibility_changed(bool visible) {
    }
    
    // Indicates that the display (what is seen by the user) of the DataView has changed.
    public virtual signal void view_altered() {
    }
    
    // Indicates that the geometry of the DataView has changed (which implies the view has altered,
    // but only in that the same elements have changed size).
    public virtual signal void geometry_altered() {
    }
    
    public virtual signal void unsubscribed(DataSource source) {
    }
    
    public DataView(DataSource source) {
        this.source = source;
        
        // subscribe to the DataSource, which sets up signal reflection and gives the DataView
        // first notification of destruction.
        source.internal_subscribe(this);
    }
    
    ~DataView() {
#if TRACE_DTORS
        debug("DTOR: DataView %s", dbg_to_string);
#endif
        source.internal_unsubscribe(this);
    }
    
    public override string get_name() {
        return "View of %s".printf(source.get_name());
    }
    
    public override string to_string() {
        return "DataView %s [DataSource %s]".printf(get_name(), source.to_string());
    }
    
    public DataSource get_source() {
        return source;
    }
    
    public bool is_selected() {
        return selected;
    }
    
    // This method is only called by ViewCollection.
    public void internal_set_selected(bool selected) {
        if (this.selected == selected)
            return;
        
        this.selected = selected;
        state_changed(selected);
    }
    
    // This method is only called by ViewCollection.  Returns the toggled state.
    public bool internal_toggle() {
        selected = !selected;
        state_changed(selected);
        
        return selected;
    }
    
    public bool is_visible() {
        return visible;
    }
    
    // This method is only called by ViewCollection.
    public void internal_set_visible(bool visible) {
        if (this.visible == visible)
            return;
        
        this.visible = visible;
        visibility_changed(visible);
    }

    protected virtual void notify_view_altered() {
        // impossible when not visible
        if (!visible)
            return;
        
        ViewCollection vc = get_membership() as ViewCollection;
        if (vc != null) {
            if (!vc.are_notifications_frozen())
                view_altered();
            
            // notify ViewCollection in any event
            vc.internal_notify_view_altered(this);
        } else {
            view_altered();
        }
    }
    
    protected virtual void notify_geometry_altered() {
        // impossible when not visible
        if (!visible)
            return;
        
        ViewCollection vc = get_membership() as ViewCollection;
        if (vc != null) {
            if (!vc.are_notifications_frozen())
                geometry_altered();
            
            // notify ViewCollection in any event
            vc.internal_notify_geometry_altered(this);
        } else {
            geometry_altered();
        }
    }
    
    // This is only called by DataSource
    public virtual void notify_unsubscribed(DataSource source) {
        unsubscribed(source);
    }
}

