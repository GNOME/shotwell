/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class SidebarMarker {
    private Gtk.TreeRowReference row;
    
    public SidebarMarker(Gtk.TreeStore store, Gtk.TreePath path) {
        row = new Gtk.TreeRowReference(store, path);
    }
    
    public Gtk.TreeRowReference get_row() {
        return row;
    }
    
    // The path should not be stored, as it may change as the store is altered.  See Gtk docs for
    // more on the relationship of Gtk.TreePath and Gtk.TreeRowReference
    public Gtk.TreePath get_path() {
        return row.get_path();
    }
}

public interface SidebarPage : Object {
    public abstract string get_sidebar_text();
    
    public abstract SidebarMarker? get_marker();
    
    public abstract void set_marker(SidebarMarker marker);
    
    public abstract void clear_marker();
}
    
public class Sidebar : Gtk.TreeView {
    private Gtk.TreeStore store = new Gtk.TreeStore(1, typeof(string));
    private Gee.HashSet<SidebarPage> pages = new Gee.HashSet<SidebarPage>();

    public Sidebar() {
        set_model(store);

        var text = new Gtk.CellRendererText();
        var text_column = new Gtk.TreeViewColumn();
        text_column.pack_start(text, true);
        text_column.add_attribute(text, "text", 0);
        append_column(text_column);
        
        set_headers_visible(false);
        set_enable_search(false);
        set_rules_hint(false);
        set_show_expanders(true);
        set_reorderable(false);
        set_enable_tree_lines(false);
        set_grid_lines(Gtk.TreeViewGridLines.NONE);
        set_tooltip_column(0);

        Gtk.TreeSelection selection = get_selection();
        selection.set_mode(Gtk.SelectionMode.BROWSE);
        selection.set_select_function(on_selection, null);
    }
    
    public void place_cursor(SidebarPage page) {
        if (page.get_marker() != null)
            get_selection().select_path(page.get_marker().get_path());
    }
    
    public void expand_branch(SidebarMarker marker) {
        expand_row(marker.get_path(), true);
    }
    
    private SidebarMarker attach_page(SidebarPage page, Gtk.TreeIter iter) {
        // set up the columns
        store.set(iter, 0, page.get_sidebar_text());
        
        // create a marker for this page
        SidebarMarker marker = new SidebarMarker(store, store.get_path(iter));
        
        // stash the marker in the page itself
        page.set_marker(marker);
        
        // add to the master table
        assert(!pages.contains(page));
        pages.add(page);
        
        return marker;
    }
    
    private void detach_page(SidebarPage page) {
        // destroy the marker linking the page to the sidebar
        page.clear_marker();
        
        // remove from master table
        pages.remove(page);
    }
    
    private SidebarPage? locate_page(Gtk.TreePath path) {
        foreach (SidebarPage page in pages) {
            if (page.get_marker().get_path().compare(path) == 0)
                return page;
        }
        
        return null;
    }

    // adds a top-level parent to the sidebar
    public SidebarMarker add_parent(SidebarPage parent) {
        // add a row, get its iter
        Gtk.TreeIter parent_iter;
        store.append(out parent_iter, null);
        
        return attach_page(parent, parent_iter);
    }    

    public SidebarMarker add_child(SidebarMarker parent, SidebarPage child) {
        // find the parent
        Gtk.TreeIter parent_iter;
        store.get_iter(out parent_iter, parent.get_path());
        
        // append the child to its branch, get child's iter
        Gtk.TreeIter child_iter;
        store.append(out child_iter, parent_iter);
        
        return attach_page(child, child_iter);
    }
    
    public SidebarMarker add_grouping_row(string name) {
        // add the row, get its iter
        Gtk.TreeIter grouping_iter;
        store.append(out grouping_iter, null);
        
        // set the columns
        store.set(grouping_iter, 0, name);
        
        // return the row reference, which is the only way to refer to the grouping now
        return new SidebarMarker(store, store.get_path(grouping_iter));
    }
    
    public SidebarMarker insert_grouping_after(SidebarMarker after, string name) {
         // find sibling
         Gtk.TreeIter after_iter;
         store.get_iter(out after_iter, after.get_path());
         
         // insert before sibling
         Gtk.TreeIter grouping_iter;
         store.insert_after(out grouping_iter, null, after_iter);
         
         // set the columns
         store.set(grouping_iter, 0, name);
         
         // return row reference, which is only way to refer to grouping
         return new SidebarMarker(store, store.get_path(grouping_iter));
     }
    
    public SidebarMarker insert_sibling_before(SidebarMarker before, SidebarPage page) {
        // find sibling in tree
        Gtk.TreeIter before_iter;
        store.get_iter(out before_iter, before.get_path());
        
        // insert page before sibling, get its new iter
        Gtk.TreeIter page_iter;
        store.insert_before(out page_iter, null, before_iter);
        
        return attach_page(page, page_iter);
    }
    
    public SidebarMarker insert_sibling_after(SidebarMarker after, SidebarPage page) {
        // find sibling in tree
        Gtk.TreeIter after_iter;
        store.get_iter(out after_iter, after.get_path());
        
        // insert page after sibling, get its new iter
        Gtk.TreeIter page_iter;
        store.insert_after(out page_iter, null, after_iter);
        
        return attach_page(page, page_iter);
    }
    
    public SidebarMarker insert_child_sorted(SidebarMarker parent, SidebarPage child, 
        Comparator<SidebarPage> comparator) {
        // find parent in sidebar using its row reference
        Gtk.TreeIter parent_iter;
        bool found = store.get_iter(out parent_iter, parent.get_path());
        assert(found);
        
        // iterate the children of the parent page, inserting child in sorted order
        Gtk.TreeIter child_iter;
        found = store.iter_children(out child_iter, parent_iter);
        while (found) {
            SidebarPage page = locate_page(store.get_path(child_iter));
            if (page != null) {
                // look to insert before the current page
                if (comparator.compare(child, page) < 0)
                    return insert_sibling_before(page.get_marker(), child);
            }
            
            found = store.iter_next(ref child_iter);
        }
        
        // not found or branch is empty, add to end
        return add_child(parent, child);
    }
    
    public void prune_branch(SidebarMarker parent) {
        Gtk.TreeIter parent_iter;
        store.get_iter(out parent_iter, parent.get_path());
        
        store.remove(parent_iter);
    }
    
    public void prune_branch_children(SidebarMarker parent) {
        // get parent's iter
        Gtk.TreeIter parent_iter;
        store.get_iter(out parent_iter, parent.get_path());
        
        // iterate its children, removing them all and clearing their markers
        Gtk.TreeIter child_iter;
        bool valid = store.iter_children(out child_iter, parent_iter);
        while (valid) {
            SidebarPage page = locate_page(store.get_path(child_iter));
            if (page != null)
                detach_page(page);
            
            valid = store.remove(child_iter);
        }
    }
    
    public void remove_page(SidebarPage page) {
        // do nothing if page is not in sidebar
        if (page.get_marker() != null) {
            // Path can be null if the row is blown away ... need to detach, but it's obviously
            // not located in the model any longer
            Gtk.TreePath path = page.get_marker().get_path();
            if (path != null) {
                // locate in sidebar; again, if not there, don't complain
                Gtk.TreeIter iter;
                if (store.get_iter(out iter, path))
                    store.remove(iter);
            }
        }
        
        // in every case, attempt to detach from this object
        detach_page(page);
    }

    private bool on_selection(Gtk.TreeSelection selection, Gtk.TreeModel model, Gtk.TreePath path,
        bool path_currently_selected) {
        // only allow selection if a page is associated with the path; if not, it's a grouping row,
        // which is unselectable
        return locate_page(path) != null;
    }
}

