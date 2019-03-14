/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A simple grouping Entry that is only expandable
public class Sidebar.Grouping : Object, Sidebar.Entry, Sidebar.ExpandableEntry,
    Sidebar.RenameableEntry {
    
    private string name;
    private string? tooltip;
    private string? icon;
    
    public Grouping(string name, string? icon, string? tooltip = null) {
        this.name = name;
        this.icon = icon;
        this.tooltip = tooltip;
    }
    
    public void rename(string name) {
        this.name = name;
        sidebar_name_changed(name);
    }
    
    public bool is_user_renameable() {
        return false;
    }
    
    public string get_sidebar_name() {
        return name;
    }
    
    public string? get_sidebar_tooltip() {
        return tooltip;
    }
    
    public string? get_sidebar_icon() {
        return icon;
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
    
    public abstract string get_sidebar_name();
    
    public virtual string? get_sidebar_tooltip() {
        return get_sidebar_name();
    }
    
    public abstract string? get_sidebar_icon();
    
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

/**
 * A header is an entry that is visually distinguished from its children. Bug 6397 recommends
 * headers to appear bolded and without any icons. To prevent the icons from rendering, we set the
 * icons to null in the base class @see Sidebar.Grouping. But we also go a step further by
 * using a custom cell_data_function (@see Sidebar.Tree::icon_renderer_function) which ensures that
 * header icons won't be rendered. This approach avoids the blank icon spacing issues.
 */
public class Sidebar.Header : Sidebar.Grouping, Sidebar.EmphasizableEntry {
    private bool emphasized;
    
    public Header(string name, string? tooltip = null, bool emphasized = true) {
        base(name, null, tooltip);
        this.emphasized = emphasized;
    }
    
    public bool is_emphasized() {
        return emphasized;
    }
}

public interface Sidebar.Contextable : Object {
    // Return null if the context menu should not be invoked for this event
    public abstract Gtk.Menu? get_sidebar_context_menu(Gdk.EventButton? event);
}

