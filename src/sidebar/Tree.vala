// SPDX-License-Identifier: LGPL-2.1-or-later
// SPDX-FileCopyrightText: Copyright 2024 Jens Georg <mail@jensge.org>

public class Sidebar.Tree : Object {
    public const int SIDEBAR_MIN_WIDTH = 120;

    private Gtk.SelectionModel selection;
    private Gtk.ListView list_view;
    private Gtk.SignalListItemFactory list_item_factory;
    private GLib.ListStore toplevel_items = new GLib.ListStore(typeof(Sidebar.Entry));
    
    public signal void entry_selected(Sidebar.SelectableEntry selectable);
    public signal void selected_entry_removed(Sidebar.SelectableEntry removed);
    public signal void branch_added(Sidebar.Branch branch);
    public signal void branch_removed(Sidebar.Branch branch);
    public signal void branch_shown(Sidebar.Branch branch, bool shown);
    public signal void page_created(Sidebar.PageRepresentative entry, Page page);    
    public signal void destroying_page(Sidebar.PageRepresentative entry, Page page);

    public Tree() {
        Object();
    }

    private void on_item_setup(Object object) {
        var expander = new Gtk.TreeExpander();
        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        var icon = new Gtk.Image();
        var label = new Gtk.Label(null);
        label.set_attributes(Pango.AttrList.from_string("0 -1 weight bold"));
        box.prepend(icon);
        box.append(label);
        expander.set_child(box);
        ((Gtk.ListItem)object).set_child(expander);

        var item = new Gtk.ConstantExpression(typeof(Gtk.ListItem), object);
        var expander_ex_0 = new Gtk.PropertyExpression(typeof(Gtk.ListItem), item, "item");
        var expander_ex = new Gtk.PropertyExpression(typeof(Gtk.TreeListRow), expander_ex_0, "item");
        expander_ex_0.bind(expander, "list-row", object);

        var label_ex2 = new Gtk.PropertyExpression(typeof(Sidebar.Entry), expander_ex, "label");
        label_ex2.bind(label, "label", object);
        var icon_ex = new Gtk.PropertyExpression(typeof(Sidebar.Entry), expander_ex, "icon-name");
        icon_ex.bind(icon, "icon-name", object);
    }

    public Gtk.ListView get_view() {
        if (this.list_view == null) {
            this.list_item_factory = new Gtk.SignalListItemFactory();
            this.list_item_factory.setup.connect(on_item_setup);
            this.selection = new Gtk.SingleSelection(get_model());
            this.list_view = new Gtk.ListView(selection, list_item_factory);
            this.list_view.set_size_request(SIDEBAR_MIN_WIDTH, -1);
        }

        return this.list_view;
    }

    private GLib.ListModel? on_model_create_model(Object item) {
        if (item is Gtk.TreeListRow) {
            var inner_item = ((Gtk.TreeListRow)item).get_item();

            print("create model for inner_item %s\n", inner_item.get_type().name());
            return ((Entry)inner_item).get_model();
        }
        print("create model for item %s\n", item.get_type().name());
        return ((Entry)item).get_model();
    }

    public GLib.ListModel get_model() {
        return new Gtk.TreeListModel(toplevel_items, false, true, on_model_create_model);
    }

    public void graft(Sidebar.Branch branch, int position) requires (position >= 0) {
        this.toplevel_items.insert(position, branch);
    }
    public bool rename_entry_in_place(Sidebar.Entry entry) {
        return false;
    }

    public void enable_editing() {}
    public bool expand_to_entry(Sidebar.Entry entry) { return false;}
    public void disable_editing() {}
    public bool place_cursor(Sidebar.Entry entry, bool mask_signal) {
        return false;
    }
    public bool is_keypress_interpreted(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        return false;
    }
}