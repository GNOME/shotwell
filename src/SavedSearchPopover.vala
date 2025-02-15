protected class SavedSearchPopover {
    public Gtk.Popover popover = null;
    private Gtk.ListBox list_box = null;
    private Gtk.Button[] edit_buttons = null;
    private Gtk.Button[] delete_buttons = null;
    Gtk.Button add = null;

    public signal void search_activated(SavedSearch search);
    public signal void edit_clicked(SavedSearch search);
    public signal void delete_clicked(SavedSearch search);
    public signal void add_clicked();

    public signal void closed();

    public SavedSearchPopover() {
        popover = new Gtk.Popover();
        popover.closed.connect(on_popover_closed);
        list_box = new Gtk.ListBox();
        edit_buttons = new Gtk.Button[0];
        delete_buttons = new Gtk.Button[0];

        foreach (var search in SavedSearchTable.get_instance().get_all()) {
            Gtk.Box row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 1);
            row.set_data("search", search);
            row.set_homogeneous(false);
            Gtk.Label label = new Gtk.Label(search.get_name());
            label.halign = Gtk.Align.START;
            label.xalign = 0.0f;
            label.hexpand = true;
            row.prepend(label);

            var edit_button = new Gtk.Button.from_icon_name("text-editor-symbolic");
            row.append(edit_button);
            edit_button.add_css_class("toolbar");
            edit_button.has_frame = false;

            // Prevent referenced capture of self 
            SavedSearchPopover *self = this;
            edit_button.clicked.connect(() => {
                self->edit_clicked(search);
            });
            edit_buttons += edit_button;

            var delete_button = new Gtk.Button.from_icon_name("edit-delete-symbolic");
            row.append(delete_button);
            delete_button.add_css_class("toolbar");
            delete_button.has_frame = false;
            delete_button.clicked.connect(() => {
                self->delete_clicked (search);
            });
            delete_buttons += delete_button;

            list_box.insert(row, -1);
        }

        add = new Gtk.Button.from_icon_name("list-add-symbolic");
        add.clicked.connect(on_add_click);
        list_box.insert(add, -1);

        list_box.row_activated.connect(on_activate_row);
        list_box.selection_mode = Gtk.SelectionMode.NONE;
        popover.set_child(list_box);
        popover.autohide = false;

    }

    ~SavedSearchPopover() {
        add.clicked.disconnect(on_add_click);
        list_box.row_activated.disconnect(on_activate_row);
        popover.closed.disconnect(on_popover_closed);
    }

    private bool is_search_row(Gtk.ListBoxRow? row) {
        if (row == null) return false;
        if (row.get_child() is Gtk.Button) return false;
        return true;
    }

    private SavedSearch? get_search(Gtk.ListBoxRow row) {
        return row.get_child().get_data("search");
    }

    private void on_activate_row(Gtk.ListBoxRow? row) {
        if (is_search_row(row))
            search_activated(get_search(row));
        popover.hide();
    }

    private void on_add_click() {
        add_clicked();
    }

    private void on_popover_closed() {
        closed();
    }

    public void show_all() {
        popover.show();
    }

    public void hide() {
        popover.hide();
    }
}
