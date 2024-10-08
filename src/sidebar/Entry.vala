/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public interface Sidebar.Entry : Object {
    public signal void sidebar_tooltip_changed(string? tooltip);
    
    public signal void sidebar_icon_changed(string? icon);
    
    public abstract string get_sidebar_name();
    
    public abstract string? get_sidebar_tooltip();
    
    public abstract string? get_sidebar_icon();
    
    public abstract string to_string();
    
    internal virtual void grafted(Sidebar.Tree tree) {
    }
    
    internal virtual void pruned(Sidebar.Tree tree) {
    }
}

public interface Sidebar.ExpandableEntry : Sidebar.Entry {
    public abstract bool expand_on_select();
}

public interface Sidebar.SelectableEntry : Sidebar.Entry {
}

public interface Sidebar.PageRepresentative : Sidebar.Entry, Sidebar.SelectableEntry {
    // Fired after the page has been created
    public signal void page_created(Page page);
    
    // Fired before the page is destroyed.
    public signal void destroying_page(Page page);
    
    public abstract bool has_page();
    
    public abstract Page get_page();
}

public interface Sidebar.RenameableEntry : Sidebar.Entry {
    public signal void sidebar_name_changed(string name);
    
    public abstract void rename(string new_name);
    
    // Return true to allow the user to rename the sidebar entry in the UI.
    public abstract bool is_user_renameable();
}

public interface Sidebar.EmphasizableEntry : Sidebar.Entry {
    public signal void is_emphasized_changed(bool emphasized);
    
    public abstract bool is_emphasized();
}

public interface Sidebar.DestroyableEntry : Sidebar.Entry {
    public abstract void destroy_source();
}

public interface Sidebar.InternalDropTargetEntry : Sidebar.Entry {
    // Returns true if drop was successful
    public abstract bool internal_drop_received(Gee.List<MediaSource> sources);
    #if 0
    public abstract bool internal_drop_received_arbitrary(Gtk.SelectionData data);
    #endif
}

#if 0
public interface Sidebar.InternalDragSourceEntry : Sidebar.Entry {
    public abstract void prepare_selection_data(Gtk.SelectionData data);
}
#endif
