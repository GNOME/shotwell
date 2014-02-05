/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A simple grouping Entry that is only expandable
public class Sidebar.Grouping : Object, Sidebar.Entry, Sidebar.ExpandableEntry {
    private string name;
    private Icon? open_icon;
    private Icon? closed_icon;
    
    public Grouping(string name, Icon? open_icon, Icon? closed_icon = null) {
        this.name = name;
        this.open_icon = open_icon;
        this.closed_icon = closed_icon ?? open_icon;
    }
    
    public string get_sidebar_name() {
        return name;
    }
    
    public string? get_sidebar_tooltip() {
        return name;
    }
    
    public Icon? get_sidebar_icon() {
        return null;
    }
    
    public Icon? get_sidebar_open_icon() {
        return open_icon;
    }
    
    public Icon? get_sidebar_closed_icon() {
        return closed_icon;
    }
    
    public string to_string() {
        return name;
    }
    
    public bool expand_on_select() {
        return true;
    }
}

// An end-node on the sidebar that represents a Page with its page context menu.  Additional 
// interfaces can be added if additional functionality is required (such as a drop target).
// This class also handles the bookwork of creating the Page on-demand and maintaining it in memory.
public abstract class Sidebar.SimplePageEntry : Object, Sidebar.Entry, Sidebar.SelectableEntry,
    Sidebar.PageRepresentative, Sidebar.Contextable {
    private Page? page = null;
    
    public SimplePageEntry() {
    }
    
    public abstract string get_sidebar_name();
    
    public virtual string? get_sidebar_tooltip() {
        return get_sidebar_name();
    }
    
    public abstract Icon? get_sidebar_icon();
    
    public virtual string to_string() {
        return get_sidebar_name();
    }
    
    protected abstract Page create_page();
    
    public bool has_page() {
        return page != null;
    }
    
    protected Page get_page() {
        if (page == null) {
            page = create_page();
            page_created(page);
        }
        
        return page;
    }
    
    internal void pruned(Sidebar.Tree tree) {
        if (page == null)
            return;
        
        destroying_page(page);
        page.destroy();
        page = null;
    }
    
    public Gtk.Menu? get_sidebar_context_menu(Gdk.EventButton? event) {
        return get_page().get_page_context_menu();
    }
}

// A simple Sidebar.Branch where the root node is the branch in entirety.
public class Sidebar.RootOnlyBranch : Sidebar.Branch {
    public RootOnlyBranch(Sidebar.Entry root) {
        base (root, Sidebar.Branch.Options.NONE, null_comparator);
    }
    
    private static int null_comparator(Sidebar.Entry a, Sidebar.Entry b) {
        return (a != b) ? -1 : 0;
    }
}

public interface Sidebar.Contextable : Object {
    // Return null if the context menu should not be invoked for this event
    public abstract Gtk.Menu? get_sidebar_context_menu(Gdk.EventButton? event);
}

