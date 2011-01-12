/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class SidebarMarker : Object {
    private int position;
    private Gtk.TreeRowReference row;
    private weak SidebarPage? page = null;
    
    public SidebarMarker(Gtk.TreeStore store, Gtk.TreePath path, int position = -1) {
        this.position = position;
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
    
    // Returns -1 if no position was set for the marker
    public int get_position() {
        return position;
    }
    
    public void set_page(SidebarPage page) {
        this.page = page;
    }
    
    public SidebarPage? get_page() {
        return page;
    }
}

public interface SidebarPage : Object {
    public abstract string get_sidebar_text();
    
    public abstract SidebarMarker? get_marker();
    
    public abstract void set_marker(SidebarMarker marker);
    
    public abstract void clear_marker();

    public abstract GLib.Icon? get_icon();

    public abstract string get_page_name();
    
    public abstract bool is_renameable();
    
    public abstract void rename(string new_name);

    public abstract Gtk.Menu? get_page_context_menu();

    public abstract bool popup_context_menu(Gtk.Menu? context_menu, Gdk.EventButton? event = null);
}

public class Sidebar : Gtk.TreeView {
    // store = (page name, page, Icon, icon, expander-closed icon, expander-open icon)
    private Gtk.TreeStore store = new Gtk.TreeStore(6, typeof(string), typeof(SidebarMarker),
        typeof(GLib.Icon?), typeof(Gdk.Pixbuf?), typeof(Gdk.Pixbuf?), typeof(Gdk.Pixbuf?));
    private Gtk.TreePath current_path = null;

    public signal void drop_received(Gdk.DragContext context, int x, int y, 
        Gtk.SelectionData selection_data, uint info, uint time, Gtk.TreePath? path, SidebarPage? page);
    
    private Gtk.IconTheme icon_theme;
    private Gtk.CellRendererPixbuf icon;
    private Gtk.CellRendererText text;
    private Gtk.Entry? text_entry = null;
    private Gee.HashMap<GLib.Icon, Gdk.Pixbuf> icon_cache = new Gee.HashMap<GLib.Icon, Gdk.Pixbuf>();
    private int editing_disabled = 0;
    
    private ThemedIcon icon_folder_open = new ThemedIcon(Resources.ICON_FOLDER_OPEN);
    private ThemedIcon icon_folder_closed = new ThemedIcon(Resources.ICON_FOLDER_CLOSED);
    
    public Sidebar() {
        set_model(store);
        
        Gtk.TreeViewColumn text_column = new Gtk.TreeViewColumn();
        text_column.set_sizing(Gtk.TreeViewColumnSizing.FIXED);
        icon = new Gtk.CellRendererPixbuf();
        text_column.pack_start(icon, false);
        text_column.add_attribute(icon, "pixbuf", 3);
        text_column.add_attribute(icon, "pixbuf_expander_closed", 4);
        text_column.add_attribute(icon, "pixbuf_expander_open", 5);
        text = new Gtk.CellRendererText();
        text.editing_canceled.connect(on_editing_canceled);
        text.editing_started.connect(on_editing_started);
        text_column.pack_start(text, true);
        text_column.add_attribute(text, "markup", 0);
        append_column(text_column);
        
        Gtk.CellRendererText invisitext = new Gtk.CellRendererText();
        Gtk.TreeViewColumn page_holder = new Gtk.TreeViewColumn();
        page_holder.pack_start(invisitext, true);
        page_holder.visible = false;
        append_column(page_holder);
        
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
        selection.set_select_function(on_selection);

        enable_model_drag_dest(LibraryWindow.DEST_TARGET_ENTRIES, Gdk.DragAction.ASK);
        
        popup_menu.connect(on_context_menu_keypress);
        
        icon_theme = Gtk.IconTheme.get_default();
        icon_theme.append_search_path(AppDirs.get_resources_dir().get_child("icons").get_path());
        icon_theme.changed.connect(on_theme_change);
    }
    
    ~Sidebar() {
        text.editing_canceled.disconnect(on_editing_canceled);
        text.editing_started.disconnect(on_editing_started);
    }
    
    public void place_cursor(SidebarPage page) {
        if (page.get_marker() != null) {
            get_selection().select_path(page.get_marker().get_path());
            set_cursor(page.get_marker().get_path(), null, false);
            
            // scroll to page in sidebar, if needed
            scroll_to_page(page.get_marker());
        }
    }
    
    public bool is_page_selected(SidebarPage page) {
        return (page.get_marker() != null) ? get_selection().path_is_selected(page.get_marker().get_path()) : false;
    }
    
    public override void cursor_changed() {
        if (editing_disabled == 0) {
            SidebarPage? page = locate_page(current_path);
            text.editable = page != null && page.is_renameable();
        }
        
        if (base.cursor_changed != null)
            base.cursor_changed();
    }
    
    public void disable_editing() {
        if (editing_disabled++ == 0)
            text.editable = false;
    }
    
    public void enable_editing() {
        if (editing_disabled == 0)
            return;
        
        if (--editing_disabled == 0) {
            SidebarPage? page = locate_page(current_path);
            text.editable = page != null && page.is_renameable();
        }
    }
    
    public void expand_branch(SidebarMarker marker) {
        expand_row(marker.get_path(), false);
    }
    
    public bool is_branch_expanded(SidebarMarker marker) {
        return is_row_expanded(marker.get_path());
    }
    
    public void toggle_branch_expansion(Gtk.TreePath path) {
        if (is_row_expanded(path))
            collapse_row(path);
        else
            expand_row(path, false);
    }

    public void expand_tree(SidebarMarker marker) {
        expand_to_path(marker.get_path());
    }

    public void expand_to_first_child(SidebarMarker marker) {
        Gtk.TreePath path = marker.get_path();
        
        Gtk.TreeIter iter;
        while (store.get_iter(out iter, path)) {
            if (store.iter_has_child(iter)) {
                path.down();
            } else {
                break;
            }
        }

        expand_to_path(path);
    }
    
    private Gdk.Pixbuf? lookup_icon(GLib.Icon gicon) throws Error {
        Gdk.Pixbuf? icon = icon_cache.get(gicon);
        if (icon != null)
            return icon;
        
        Gtk.IconInfo? info = icon_theme.lookup_by_gicon(gicon, 16, 0);
        if (info == null)
            return null;
        
        icon = info.load_icon();
        if (icon == null)
            return null;
        
        icon_cache.set(gicon, icon);
        
        return icon;
    }

    private void set_iter_icon(Gtk.TreeIter iter, GLib.Icon icon) {
        // keep icon for theme change, some items have no page to request name from
        store.set(iter, 2, icon);

        Gdk.Pixbuf? closed = null;
        Gdk.Pixbuf? open = null;
        
        try {
            closed = lookup_icon(icon);
        } catch (Error err) {
            warning("Unable to load ico %s", err.message);
        }
        
        if (closed == null) {
            // icon_name is null OR icon not found, dont show an icon
            store.set(iter, 3, null);
            store.set(iter, 4, null);
            store.set(iter, 5, null);
        } else {
            try {
                if (icon.equal(icon_folder_closed))
                    // icon is a folder, so both open and closed are needed
                    open = lookup_icon(icon_folder_open);
            } catch (Error err) {
                warning("Unable to load icon %s", err.message);
            }
            
            if (open == null) {
                // no expander-open icon, only load one icon
                store.set(iter, 3, closed);
                store.set(iter, 4, null);
                store.set(iter, 5, null);
            } else {
                // load expander-open and expander-closed icons
                store.set(iter, 3, null);
                store.set(iter, 4, closed);
                store.set(iter, 5, open);
            }
        }
    }

    public void update_page_icon(SidebarPage page) {
        Gtk.TreeIter iter;
        store.get_iter(out iter, page.get_marker().get_path());
        set_iter_icon(iter, page.get_icon());
    }

    public void reload_iter_and_child_icons(Gtk.TreeIter iter) {
        GLib.Icon? icon;
        store.get(iter, 2, out icon);
        set_iter_icon(iter, icon);

        Gtk.TreeIter child;
        if (store.iter_children(out child, iter)) {
            do {
                reload_iter_and_child_icons(child);
            } while (store.iter_next(ref child));
        }
    }

    private void on_theme_change() {
        Gtk.TreeIter iter;
        if (store.get_iter_first(out iter)) {
            do {
                reload_iter_and_child_icons(iter);
            } while (store.iter_next(ref iter));
        }
    }

    private SidebarMarker attach_page(SidebarPage page, Gtk.TreeIter iter, int position = -1) {
        // create a marker for this page
        SidebarMarker marker = new SidebarMarker(store, store.get_path(iter), position);
        marker.set_page(page);
        
        // stash the marker in the page itself
        page.set_marker(marker);
        
        // set up the columns
        store.set(iter, 0, guarded_markup_escape_text(page.get_sidebar_text()));
        store.set(iter, 1, marker);
        set_iter_icon(iter, page.get_icon());
        
        return marker;
    }
    
    private void detach_page(SidebarPage page) {
        // destroy the marker linking the page to the sidebar
        page.clear_marker();
    }
    
    private SidebarMarker attach_grouping(string name, GLib.Icon? icon, Gtk.TreeIter iter, int position = -1) {
        SidebarMarker marker = new SidebarMarker(store, store.get_path(iter), position);
        
        // set up the columns
        store.set(iter, 0, guarded_markup_escape_text(name));
        store.set(iter, 1, marker);
        set_iter_icon(iter, icon);
        
        return marker;
    }
    
    private SidebarPage? locate_page(Gtk.TreePath path) {
        SidebarMarker? marker = locate_marker(path);
        
        return marker != null ? marker.get_page() : null;
    }
    
    private SidebarMarker? locate_marker(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!store.get_iter(out iter, path))
            return null;
        
        Value val;
        store.get_value(iter, 1, out val);
        
        return (SidebarMarker) val;
    }
    
    // adds a top-level parent to the sidebar at the specified position (which must be >= 0)
    public SidebarMarker add_toplevel(SidebarPage parent, int position) requires (position >= 0) {
        // add a row, get its iter
        Gtk.TreeIter parent_iter;
        bool found = store.get_iter_first(out parent_iter);
        while (found) {
            SidebarMarker? marker = locate_marker(store.get_path(parent_iter));
            if (marker != null && position < marker.get_position())
                return attach_page(parent, insert_before(marker), position);
            
            found = store.iter_next(ref parent_iter);
        }
        
        // add to the bottom of the top-level list
        store.append(out parent_iter, null);
        
        return attach_page(parent, parent_iter, position);
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
    
    // Like add_parent, position must be specified
    public SidebarMarker add_toplevel_grouping(string name, GLib.Icon? icon, int position) requires (position > 0) {
        // add the row, get its iter
        Gtk.TreeIter grouping_iter;
        bool found = store.get_iter_first(out grouping_iter);
        while (found) {
            SidebarMarker? marker = locate_marker(store.get_path(grouping_iter));
            if (marker != null && position < marker.get_position())
                return attach_grouping(name, icon, insert_before(marker), position);
            
            found = store.iter_next(ref grouping_iter);
        }
        
        // add to the bottom of the top-level list
        store.append(out grouping_iter, null);
        
        return attach_grouping(name, icon, grouping_iter, position);
    }
    
    private Gtk.TreeIter insert_before(SidebarMarker before) {
        // find sibling in tree
        Gtk.TreeIter before_iter;
        store.get_iter(out before_iter, before.get_path());
        
        // create insertion iter
        Gtk.TreeIter insert_iter;
        store.insert_before(out insert_iter, null, before_iter);
        
        return insert_iter;
    }
    
    public SidebarMarker insert_child_sorted(SidebarMarker parent, SidebarPage child, 
        Comparator comparator) {
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
                if (comparator(child, page) < 0)
                    return attach_page(child, insert_before(page.get_marker()));
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
            if (page != null) {
                if (has_children(page.get_marker()))
                    prune_branch_children(page.get_marker());
                detach_page(page);
            }
            
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
        if (locate_page(path) != null) {
            current_path = path;
            return true;
        }

        return false;
    }

    private Gtk.TreePath? get_path_from_event(Gdk.EventButton event) {
        int x, y, cell_x, cell_y;
        Gdk.ModifierType mask;
        event.window.get_pointer(out x, out y, out mask);
        
        Gtk.TreePath path;
        return get_path_at_pos(x, y, out path, null, out cell_x, out cell_y) ? path : null;
    }
    
    private bool on_context_menu_keypress() {
        GLib.List<Gtk.TreePath> rows = get_selection().get_selected_rows(null);
        if (rows == null)
            return false;
        
        Gtk.TreePath? path = rows.data;
        if (path == null)
            return false;
        
        scroll_to_cell(path, null, false, 0, 0);
        popup_context_menu(path);
        
        return true;
    }
    
    protected bool popup_context_menu(Gtk.TreePath path, Gdk.EventButton? event = null) {
        SidebarPage page = locate_page(path);
        if (page == null)
            return false;
        
        Gtk.Menu context_menu = page.get_page_context_menu();
        
        return (context_menu != null) ? page.popup_context_menu(context_menu, event) : false;
    }

    public override bool button_press_event(Gdk.EventButton event) {
        if (event.button == 3 && event.type == Gdk.EventType.BUTTON_PRESS) {
            // single right click
            Gtk.TreePath? path = get_path_from_event(event);
            if (path != null)
                popup_context_menu(path, event);
        } else if (event.button == 1 && event.type == Gdk.EventType.2BUTTON_PRESS) {
            // double left click
            Gtk.TreePath? path = get_path_from_event(event);
            
            if (path != null) {
                toggle_branch_expansion(path);
                
                if (rename_path(path))
                    return false;
            }
        }
        
        return base.button_press_event(event);
    }

    public override bool key_press_event(Gdk.EventKey event) {
        if (Gdk.keyval_name(event.keyval) == "Return" || Gdk.keyval_name(event.keyval) == "KP_Enter") {
            toggle_branch_expansion(current_path);
            return false;
        } else if (Gdk.keyval_name(event.keyval) == "F2") {
            return rename_in_place();
        }
        
        bool return_val = base.key_press_event(event);
        
        if (has_grab() && !return_val) {
            AppWindow.get_instance().key_press_event(event);
        }
        
        return return_val;
    }
    
    public bool rename_in_place() {
        Gtk.TreePath? cursor_path;
        Gtk.TreeViewColumn? cursor_column;
        get_cursor(out cursor_path, out cursor_column);
        cursor_path = current_path;

        if (rename_path(cursor_path)) {
            set_cursor(cursor_path, cursor_column, true);
            return false;
        }

        return true;
    }

    public void rename(SidebarMarker marker, string name) {
        // set up the columns
        Gtk.TreeIter iter;
        store.get_iter(out iter, marker.get_path());
        store.set(iter, 0, guarded_markup_escape_text(name));
    }

    public SidebarPage? get_parent_page(SidebarPage page) {
        if (page.get_marker() != null) {
            Gtk.TreePath path = page.get_marker().get_path();
            if (path != null) {
                if (path.up())
                    return locate_page(path);
            }
        }

        return null;
    }

    public bool has_children(SidebarMarker marker) {
        Gtk.TreePath path = marker.get_path();
        if (path != null) {
            Gtk.TreeIter iter;
            
            if (store.get_iter(out iter, path))
                return store.iter_has_child(iter);
        }

        return false;
    }

    public int get_children_count(SidebarMarker marker) {
        Gtk.TreePath path = marker.get_path();
        if (path != null) {
            Gtk.TreeIter iter;
            
            if (store.get_iter(out iter, path))
                return store.iter_n_children(iter);
        }

        return 0;
    }

    public void scroll_to_page(SidebarMarker marker) {
        Gtk.TreePath path = marker.get_path();
        scroll_to_cell(path, null, false, 0, 0);
    }

    public void sort_branch(SidebarMarker marker, Comparator comparator) {
        Gtk.TreePath path = marker.get_path();

        if (path == null)
            return;

        Gtk.TreeIter iter;
        store.get_iter(out iter, path);

        int num_children = store.iter_n_children(iter);
        bool changes_made = (num_children > 0);

        // sort this level with bubble sort
        while (changes_made) {
            changes_made = false;

            path.down();

            for (int i = 0; i < (num_children - 1); i++) {
                Gtk.TreeIter iter1, iter2 = Gtk.TreeIter();
                Gtk.TreePath path1 = path;
                path.next();
                Gtk.TreePath path2 = path;

                if (store.iter_nth_child(out iter1, iter, i) && 
                    store.iter_nth_child(out iter2, iter, i + 1) &&
                    comparator(locate_page(path1), locate_page(path2)) > 0) {
                    
                    store.swap(iter1, iter2);
                    changes_made = true;
                }
            }

            path.up();
        }

        // sort each sublevel
        path.down();
        while (num_children > 0) {
            sort_branch(locate_page(path).get_marker(), comparator);
            path.next();
            num_children--;
        }
    }

    public override void drag_data_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time) {

        Gtk.TreePath path = null;
        Gtk.TreeViewDropPosition pos;
        SidebarPage page = null;

        if (get_dest_row_at_pos(x, y, out path, out pos)) {
            page = locate_page(path);
        }

        drop_received(context, x, y, selection_data, info, time, path, page);
    }

    public override bool drag_motion(Gdk.DragContext context, int x, int y, uint time) {
        // call the base signal to get rows with children to spring open
        base.drag_motion(context, x, y, time);

        Gtk.TreePath path = null;
        Gtk.TreeViewDropPosition pos;
        
        bool has_dest = get_dest_row_at_pos(x, y, out path, out pos);
        
        // we don't want to insert between rows, only select the rows themselves
        if (pos == Gtk.TreeViewDropPosition.BEFORE)
            set_drag_dest_row(path, Gtk.TreeViewDropPosition.INTO_OR_BEFORE);
        else if (pos == Gtk.TreeViewDropPosition.AFTER)
            set_drag_dest_row(path, Gtk.TreeViewDropPosition.INTO_OR_AFTER);

        Gdk.drag_status(context, context.suggested_action, time);

        return has_dest;
    }
    
    // should return true if path is renameable by user
    private bool rename_path(Gtk.TreePath path) {
        if (editing_disabled > 0)
            return false;
        
        SidebarPage? page = locate_page(path);
        if (page == null || !page.is_renameable())
            return false;
        
        get_selection().select_path(path);
        
        return true;
    }
        
    private void on_editing_started(Gtk.CellEditable editable, string path) {
        if (editable is Gtk.Entry) {
            text_entry = (Gtk.Entry) editable;
            text_entry.editing_done.connect(on_editing_done);
            text_entry.focus_out_event.connect(on_editing_focus_out);
        }
        
        AppWindow.get_instance().pause_keyboard_trapping();
    }
    
    private void on_editing_canceled() {
        AppWindow.get_instance().resume_keyboard_trapping();
        
        text_entry.editing_done.disconnect(on_editing_done);
    }
    
    private void on_editing_done() {
        AppWindow.get_instance().resume_keyboard_trapping();
        
        SidebarPage? page = locate_page(current_path);
        
        if (page != null && page.is_renameable())
            page.rename(text_entry.get_text());
        
        text_entry.editing_done.disconnect(on_editing_done);
    }

    private bool on_editing_focus_out(Gdk.EventFocus event) {
        text_entry.editing_done();
        return false;
    }
}
