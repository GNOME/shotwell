/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// This dialog displays a boolean search configuration.
[GtkTemplate (ui = "/org/gnome/Shotwell/ui/saved_search_dialog.ui")]
public class SavedSearchDialog : Gtk.Dialog {
    
    // Contains a search row, with a type selector and remove button.
    private class SearchRowContainer {
        public signal void remove(SearchRowContainer this_row);
        public signal void changed(SearchRowContainer this_row);
        
        private Gtk.ComboBoxText type_combo;
        private Gtk.Box box;
        private Gtk.Button remove_button;
        private SearchCondition.SearchType[] search_types;
        private Gee.HashMap<SearchCondition.SearchType, int> search_types_index;
        
        private SearchRow? my_row = null;
        
        public SearchRowContainer() {
            setup_gui();
            set_type(SearchCondition.SearchType.ANY_TEXT);
        }
        
        public SearchRowContainer.edit_existing(SearchCondition sc) {
            setup_gui();
            set_type(sc.search_type);
            set_type_combo_box(sc.search_type);
            my_row.populate(sc);
        }
        
        // Creates the GUI for this row.
        private void setup_gui() {
            search_types = SearchCondition.SearchType.as_array();
            search_types_index = new Gee.HashMap<SearchCondition.SearchType, int>();
            SearchCondition.SearchType.sort_array(ref search_types);
            
            type_combo = new Gtk.ComboBoxText();
            for (int i = 0; i < search_types.length; i++) {
                SearchCondition.SearchType st = search_types[i];
                search_types_index.set(st, i);
                type_combo.append_text(st.display_text());
            }
            set_type_combo_box(SearchCondition.SearchType.ANY_TEXT); // Sets default.
            type_combo.changed.connect(on_type_changed);
            
            remove_button = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON);
            remove_button.set_relief(Gtk.ReliefStyle.NONE);
            remove_button.clicked.connect(on_removed);
            
            box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            box.pack_start(type_combo, false, false, 0);
            box.pack_end(remove_button, false, false, 0);
            box.margin_top = 2;
            box.margin_bottom = 2;
            box.margin_start = 8;
            box.margin_end = 8;
            box.show_all();
        }
        
        private void on_type_changed() {
            set_type(get_search_type());
            changed(this);
        }
        
        private void set_type_combo_box(SearchCondition.SearchType st) {
            type_combo.set_active(search_types_index.get(st));
        }
        
        private void set_type(SearchCondition.SearchType type) {
            if (my_row != null)
                box.remove(my_row.get_widget());
            
            switch (type) {
                case SearchCondition.SearchType.ANY_TEXT:
                case SearchCondition.SearchType.EVENT_NAME:
                case SearchCondition.SearchType.FILE_NAME:
#if ENABLE_FACES
                case SearchCondition.SearchType.FACE:
#endif
                case SearchCondition.SearchType.TAG:
                case SearchCondition.SearchType.COMMENT:
                case SearchCondition.SearchType.TITLE:
                    my_row = new SearchRowText(this);
                    break;
                    
                case SearchCondition.SearchType.MEDIA_TYPE:
                    my_row = new SearchRowMediaType(this);
                    break;
                    
                case SearchCondition.SearchType.FLAG_STATE:
                    my_row = new SearchRowFlagged(this);
                    break;
                    
                case SearchCondition.SearchType.MODIFIED_STATE:
                    my_row = new SearchRowModified(this);
                    break;
                
                case SearchCondition.SearchType.RATING:
                    my_row = new SearchRowRating(this);
                    break;
                
                case SearchCondition.SearchType.DATE:
                    my_row = new SearchRowDate(this);
                    break;
                
                default:
                    assert_not_reached ();
            }
            
            box.pack_start (my_row.get_widget());
        }
        
        public SearchCondition.SearchType get_search_type() {
            return search_types[type_combo.get_active()];
        }
        
        private void on_removed() {
            remove(this);
        }
        
        public void allow_removal(bool allow) {
            remove_button.sensitive = allow;
        }
        
        public Gtk.Widget get_widget() {
            return box;
        }
        
        public SearchCondition get_search_condition() {
            return my_row.get_search_condition();
        }
        
        public bool is_complete() {
            return my_row.is_complete();
        }
    }
    
    // Represents a row-type.
    private abstract class SearchRow {
        // Returns the GUI widget for this row. 
        public abstract Gtk.Widget get_widget();
        
        // Returns the search condition for this row.
        public abstract SearchCondition get_search_condition();
        
        // Fills out the fields in this row based on an existing search condition (for edit mode.)
        public abstract void populate(SearchCondition sc);
        
        // Returns true if the row is valid and complete.
        public abstract bool is_complete();
    }
    
    private class SearchRowText : SearchRow {
        private Gtk.Box box;
        private Gtk.ComboBoxText text_context;
        private Gtk.Entry entry;
        
        private SearchRowContainer parent;
        
        public SearchRowText(SearchRowContainer parent) {
            this.parent = parent;
            
            // Ordering must correspond with SearchConditionText.Context
            text_context = new Gtk.ComboBoxText();
            text_context.append_text(_("contains"));
            text_context.append_text(_("is exactly"));
            text_context.append_text(_("starts with"));
            text_context.append_text(_("ends with"));
            text_context.append_text(_("does not contain"));
            text_context.append_text(_("is not set"));
            text_context.append_text(_("is set"));
            text_context.set_active(0);
            text_context.changed.connect(on_changed);
            
            entry = new Gtk.Entry();
            entry.set_width_chars(25);
            entry.set_activates_default(true);
            entry.changed.connect(on_changed);
            
            box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 3);
            box.pack_start(text_context, false, false, 0);
            box.pack_start(entry, false, false, 0);
            box.show_all();
        }
        
        ~SearchRowText() {
            text_context.changed.disconnect(on_changed);
            entry.changed.disconnect(on_changed);
        }
        
        public override Gtk.Widget get_widget() {
            return box;
        }
        
        public override SearchCondition get_search_condition() {
            SearchCondition.SearchType type = parent.get_search_type();
            string text = entry.get_text();
            SearchConditionText.Context context = get_text_context();
            SearchConditionText c = new SearchConditionText(type, text, context);
            return c;
        }
        
        public override void populate(SearchCondition sc) {
            SearchConditionText? text = sc as SearchConditionText;
            assert(text != null);
            text_context.set_active(text.context);
            entry.set_text(text.text);
            on_changed();
        }
        
        public override bool is_complete() {
            return entry.text.chomp() != "" ||
                get_text_context() == SearchConditionText.Context.IS_NOT_SET ||
                get_text_context() == SearchConditionText.Context.IS_SET;
        }
        
        private SearchConditionText.Context get_text_context() {
            return (SearchConditionText.Context) text_context.get_active();
        }
        
        private void on_changed() {
            if (get_text_context() == SearchConditionText.Context.IS_NOT_SET
                || get_text_context() == SearchConditionText.Context.IS_SET) {
                entry.hide();
            } else {
                entry.show();
            }
            
            parent.changed(parent);
        }
    }
    
    private class SearchRowMediaType : SearchRow {
        private Gtk.Box box;
        private Gtk.ComboBoxText media_context;
        private Gtk.ComboBoxText media_type;
        
        private SearchRowContainer parent;
        
        public SearchRowMediaType(SearchRowContainer parent) {
            this.parent = parent;
            
            // Ordering must correspond with SearchConditionMediaType.Context
            media_context = new Gtk.ComboBoxText();
            media_context.append_text(_("is"));
            media_context.append_text(_("is not"));
            media_context.set_active(0);
            media_context.changed.connect(on_changed);
            
            // Ordering must correspond with SearchConditionMediaType.MediaType
            media_type = new Gtk.ComboBoxText();
            media_type.append_text(_("any photo"));
            media_type.append_text(_("a raw photo"));
            media_type.append_text(_("a video"));
            media_type.set_active(0);
            media_type.changed.connect(on_changed);
            
            box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 3);
            box.pack_start(media_context, false, false, 0);
            box.pack_start(media_type, false, false, 0);
            box.show_all();
        }
        
        ~SearchRowMediaType() {
            media_context.changed.disconnect(on_changed);
            media_type.changed.disconnect(on_changed);
        }
        
        public override Gtk.Widget get_widget() {
            return box;
        }
        
        public override SearchCondition get_search_condition() {
            SearchCondition.SearchType search_type = parent.get_search_type();
            SearchConditionMediaType.Context context = (SearchConditionMediaType.Context) media_context.get_active();
            SearchConditionMediaType.MediaType type = (SearchConditionMediaType.MediaType) media_type.get_active();
            SearchConditionMediaType c = new SearchConditionMediaType(search_type, context, type);
            return c;
        }
        
        public override void populate(SearchCondition sc) {
            SearchConditionMediaType? media = sc as SearchConditionMediaType;
            assert(media != null);
            media_context.set_active(media.context);
            media_type.set_active(media.media_type);
        }
        
        public override bool is_complete() {
            return true;
        }
        
        private void on_changed() {
            parent.changed(parent);
        }
    }
    
    private class SearchRowModified : SearchRow {
        private Gtk.Box box;
        private Gtk.ComboBoxText modified_context;
        private Gtk.ComboBoxText modified_state;
        
        private SearchRowContainer parent;
        
        public SearchRowModified(SearchRowContainer parent) {
            this.parent = parent;

            modified_context = new Gtk.ComboBoxText();
            modified_context.append_text(_("has"));
            modified_context.append_text(_("has no"));
            modified_context.set_active(0);
            modified_context.changed.connect(on_changed);
            
            modified_state = new Gtk.ComboBoxText();
            modified_state.append_text(_("modifications"));
            modified_state.append_text(_("internal modifications"));
            modified_state.append_text(_("external modifications"));
            modified_state.set_active(0);
            modified_state.changed.connect(on_changed);
            
            box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 3);
            box.pack_start(modified_context, false, false, 0);
            box.pack_start(modified_state, false, false, 0);
            box.show_all();
        }
        
        ~SearchRowModified() {
            modified_state.changed.disconnect(on_changed);
            modified_context.changed.disconnect(on_changed);
        }
        
        public override Gtk.Widget get_widget() {
            return box;
        }

        public override SearchCondition get_search_condition() {
            SearchCondition.SearchType search_type = parent.get_search_type();
            SearchConditionModified.Context context = (SearchConditionModified.Context) modified_context.get_active();
            SearchConditionModified.State state = (SearchConditionModified.State) modified_state.get_active();
            SearchConditionModified c = new SearchConditionModified(search_type, context, state);
            return c;
        }
        
        public override void populate(SearchCondition sc) {
            SearchConditionModified? scm = sc as SearchConditionModified;
            assert(scm != null);
            modified_state.set_active(scm.state);
            modified_context.set_active(scm.context);
        }
        
        public override bool is_complete() {
            return true;
        }
        
        private void on_changed() {
            parent.changed(parent);
        }
    }
    
    private class SearchRowFlagged : SearchRow {
        private Gtk.Box box;
        private Gtk.ComboBoxText flagged_state;
        
        private SearchRowContainer parent;
        
        public SearchRowFlagged(SearchRowContainer parent) {
            this.parent = parent;
            
            // Ordering must correspond with SearchConditionFlagged.State
            flagged_state = new Gtk.ComboBoxText();
            flagged_state.append_text(_("flagged"));
            flagged_state.append_text(_("not flagged"));
            flagged_state.set_active(0);
            flagged_state.changed.connect(on_changed);
            
            box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 3);
            box.pack_start(new Gtk.Label(_("is")), false, false, 0);
            box.pack_start(flagged_state, false, false, 0);
            box.show_all();
        }
        
        ~SearchRowFlagged() {
            flagged_state.changed.disconnect(on_changed);
        }
        
        public override Gtk.Widget get_widget() {
            return box;
        }
        
        public override SearchCondition get_search_condition() {
            SearchCondition.SearchType search_type = parent.get_search_type();
            SearchConditionFlagged.State state = (SearchConditionFlagged.State) flagged_state.get_active();
            SearchConditionFlagged c = new SearchConditionFlagged(search_type, state);
            return c;
        }
        
        public override void populate(SearchCondition sc) {
            SearchConditionFlagged? f = sc as SearchConditionFlagged;
            assert(f != null);
            flagged_state.set_active(f.state);
        }
        
        public override bool is_complete() {
            return true;
        }
        
        private void on_changed() {
            parent.changed(parent);
        }
    }
    
    private class SearchRowRating : SearchRow {
        private Gtk.Box box;
        private Gtk.ComboBoxText rating;
        private Gtk.ComboBoxText context;
        
        private SearchRowContainer parent;
        
        public SearchRowRating(SearchRowContainer parent) {
            this.parent = parent;
            
            // Ordering must correspond with Rating
            rating = new Gtk.ComboBoxText();
            rating.append_text(Resources.rating_combo_box(Rating.REJECTED));
            rating.append_text(Resources.rating_combo_box(Rating.UNRATED));
            rating.append_text(Resources.rating_combo_box(Rating.ONE));
            rating.append_text(Resources.rating_combo_box(Rating.TWO));
            rating.append_text(Resources.rating_combo_box(Rating.THREE));
            rating.append_text(Resources.rating_combo_box(Rating.FOUR));
            rating.append_text(Resources.rating_combo_box(Rating.FIVE));
            rating.set_active(0);
            rating.changed.connect(on_changed);
            
            context = new Gtk.ComboBoxText();
            context.append_text(_("and higher"));
            context.append_text(_("only"));
            context.append_text(_("and lower"));
            context.set_active(0);
            context.changed.connect(on_changed);
            
            box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 3);
            box.pack_start(new Gtk.Label(_("is")), false, false, 0);
            box.pack_start(rating, false, false, 0);
            box.pack_start(context, false, false, 0);
            box.show_all();
        }
        
        ~SearchRowRating() {
            rating.changed.disconnect(on_changed);
            context.changed.disconnect(on_changed);
        }
        
        public override Gtk.Widget get_widget() {
            return box;
        }
        
        public override SearchCondition get_search_condition() {
            SearchCondition.SearchType search_type = parent.get_search_type();
            Rating search_rating = (Rating) rating.get_active() + Rating.REJECTED;
            SearchConditionRating.Context search_context = (SearchConditionRating.Context) context.get_active();
            SearchConditionRating c = new SearchConditionRating(search_type, search_rating, search_context);
            return c;
        }
        
        public override void populate(SearchCondition sc) {
            SearchConditionRating? r = sc as SearchConditionRating;
            assert(r != null);
            context.set_active(r.context);
            rating.set_active(r.rating - Rating.REJECTED);
        }
        
        public override bool is_complete() {
            return true;
        }
        
        private void on_changed() {
            parent.changed(parent);
        }
    }
    
    private class SearchRowDate : SearchRow {
        private const string DATE_FORMAT = "%x";
        private Gtk.Box box;
        private Gtk.ComboBoxText context;
        private Gtk.Button label_one;
        private Gtk.Button label_two;
        private Gtk.Calendar cal_one;
        private Gtk.Calendar cal_two;
        private Gtk.Label and;
        
        private SearchRowContainer parent;
        
        public SearchRowDate(SearchRowContainer parent) {
            this.parent = parent;
            
            // Ordering must correspond with Context
            context = new Gtk.ComboBoxText();
            context.append_text(_("is exactly"));
            context.append_text(_("is after"));
            context.append_text(_("is before"));
            context.append_text(_("is between"));
            context.append_text(_("is not set"));
            context.set_active(0);
            context.changed.connect(on_changed);
            
            cal_one = new Gtk.Calendar();
            cal_two = new Gtk.Calendar();
            
            label_one = new Gtk.Button();
            label_one.clicked.connect(on_one_clicked);
            label_two = new Gtk.Button();
            label_two.clicked.connect(on_two_clicked);
            
            and = new Gtk.Label(_("and"));
            
            box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 3);
            box.pack_start(context, false, false, 0);
            box.pack_start(label_one, false, false, 0);
            box.pack_start(and, false, false, 0);
            box.pack_start(label_two, false, false, 0);
            
            box.show_all();
            update_date_labels();
        }
        
        ~SearchRowDate() {
            context.changed.disconnect(on_changed);
        }
        
        private void update_date_labels() {
            SearchConditionDate.Context c = (SearchConditionDate.Context) context.get_active();
            
            // Only show "and" and 2nd date label for between mode.
            if (c == SearchConditionDate.Context.BETWEEN) {
                label_one.show();
                and.show();
                label_two.show();
            } else if (c == SearchConditionDate.Context.IS_NOT_SET) {
                label_one.hide();
                and.hide();
                label_two.hide();
            } else {
                label_one.show();
                and.hide();
                label_two.hide();
            }
            
            // Set label text to date.
            label_one.label = get_date_one().format(DATE_FORMAT);
            label_two.label = get_date_two().format(DATE_FORMAT);;
        }
        
        public override Gtk.Widget get_widget() {
            return box;
        }
        
        private DateTime get_date_one() {
            return new DateTime.local(cal_one.year, cal_one.month + 1, cal_one.day, 0, 0, 0.0);
        }
        
        private DateTime get_date_two() {
            return new DateTime.local(cal_two.year, cal_two.month + 1, cal_two.day, 0, 0, 0.0);
        }
        
        private void set_date_one(DateTime date) {
            cal_one.day   = date.get_day_of_month();
            cal_one.month = date.get_month() - 1;
            cal_one.year  = date.get_year();
        }
        
        private void set_date_two(DateTime date) {
            cal_two.day   = date.get_day_of_month();
            cal_two.month = date.get_month() - 1;
            cal_two.year  = date.get_year();
        }
        
        public override SearchCondition get_search_condition() {
            SearchCondition.SearchType search_type = parent.get_search_type();
            SearchConditionDate.Context search_context = (SearchConditionDate.Context) context.get_active();
            SearchConditionDate c = new SearchConditionDate(search_type, search_context, get_date_one(),
                get_date_two());
            return c;
        }
        
        public override void populate(SearchCondition sc) {
            SearchConditionDate? cond = sc as SearchConditionDate;
            assert(cond != null);
            context.set_active(cond.context);
            set_date_one(cond.date_one);
            set_date_two(cond.date_two);
            update_date_labels();
        }
        
        public override bool is_complete() {
            return true;
        }
        
        private void on_changed() {
            parent.changed(parent);
            update_date_labels();
        }
        
        private void popup_calendar(Gtk.Calendar cal) {
            int orig_day = cal.day;
            int orig_month = cal.month;
            int orig_year = cal.year;
            Gtk.Dialog d = new Gtk.Dialog.with_buttons(null, null, 
                Gtk.DialogFlags.MODAL, Resources.CANCEL_LABEL, Gtk.ResponseType.REJECT, 
                Resources.OK_LABEL, Gtk.ResponseType.ACCEPT);
            d.set_modal(true);
            d.set_resizable(false);
            d.set_decorated(false);
            ((Gtk.Box) d.get_content_area()).add(cal);
            ulong id_1 = cal.day_selected.connect(()=>{update_date_labels();});
            ulong id_2 = cal.day_selected_double_click.connect(()=> {
                  d.response(Gtk.ResponseType.ACCEPT);
            });
            d.show_all();
            int res = d.run();
            if (res != Gtk.ResponseType.ACCEPT) {
                // User hit cancel, restore original date.
                cal.day = orig_day;
                cal.month = orig_month;
                cal.year = orig_year;
            }
            cal.disconnect(id_1);
            cal.disconnect(id_2);
            d.destroy();
            update_date_labels();
        }
        
        private void on_one_clicked() {
            popup_calendar(cal_one);
        }
        
        private void on_two_clicked() {
            popup_calendar(cal_two);
        }
    }
    
    [GtkChild]
    private Gtk.Button add_criteria;
    [GtkChild]
    private Gtk.ComboBoxText operator;
    [GtkChild]
    private Gtk.Entry search_title;
    [GtkChild]
    private Gtk.ListBox row_listbox;

    private Gee.ArrayList<SearchRowContainer> row_list = new Gee.ArrayList<SearchRowContainer>();
    private bool edit_mode = false;
    private SavedSearch? previous_search = null;
    private bool valid = false;
    
    public SavedSearchDialog() {
        Object (use_header_bar : Resources.use_header_bar());

        setup_dialog();
        
        // Default name.
        search_title.set_text(SavedSearchTable.get_instance().generate_unique_name());
        search_title.select_region(0, -1); // select all
        
        // Default is text search.
        add_text_search();
        row_list.get(0).allow_removal(false);

        show_all();
        set_valid(false);
    }
    
    public SavedSearchDialog.edit_existing(SavedSearch saved_search) {
        Object (use_header_bar : Resources.use_header_bar());

        previous_search = saved_search;
        edit_mode = true;
        setup_dialog();
        
        show_all();
        
        // Load existing search into dialog.
        operator.set_active((SearchOperator) saved_search.get_operator());
        search_title.set_text(saved_search.get_name());
        foreach (SearchCondition sc in saved_search.get_conditions()) {
            add_row(new SearchRowContainer.edit_existing(sc));
        }
        
        if (row_list.size == 1)
            row_list.get(0).allow_removal(false);
        
        set_valid(true);
    }
    
    // Builds the dialog UI.  Doesn't add buttons to the dialog or call dialog.show().
    private void setup_dialog() {
        set_transient_for(AppWindow.get_instance());
        response.connect(on_response);

        add_criteria.clicked.connect(on_add_criteria);
        
        search_title.changed.connect(on_title_changed);
    }
    
    // Displays the dialog.
    public new void show() {
        run();
        destroy();
    }
    
    // Adds a row of search criteria.
    private void on_add_criteria() {
        add_text_search();
    }
    
    private void add_text_search() {
        SearchRowContainer text = new SearchRowContainer();
        add_row(text);
    }
    
    // Appends a row of search criteria to the list and table.
    private void add_row(SearchRowContainer row) {
        if (row_list.size == 1)
            row_list.get(0).allow_removal(true);
        row_listbox.add(row.get_widget());
        row_list.add(row);
        row.remove.connect(on_remove_row);
        row.changed.connect(on_row_changed);
        set_valid(row.is_complete());
    }
    
    // Removes a row of search criteria.
    private void on_remove_row(SearchRowContainer row) {
        row.remove.disconnect(on_remove_row);
        row.changed.disconnect(on_row_changed);
        row_listbox.remove(row.get_widget().get_parent());
        row_list.remove(row);
        if (row_list.size == 1)
            row_list.get(0).allow_removal(false);
        set_valid(true); // try setting to "true" since we removed a row
    }

    private void on_response(int response_id) {
        if (response_id == Gtk.ResponseType.OK) {
            if (SavedSearchTable.get_instance().exists(search_title.get_text()) && 
                !(edit_mode && previous_search.get_name() == search_title.get_text())) {
                AppWindow.error_message(Resources.rename_search_exists_message(search_title.get_text()));
                return;
            }
            
            if (edit_mode) {
                // Remove previous search.
                SavedSearchTable.get_instance().remove(previous_search);
            }
            
            // Build the condition list from the search rows, and add our new saved search to the table.
            Gee.ArrayList<SearchCondition> conditions = new Gee.ArrayList<SearchCondition>();
            foreach (SearchRowContainer c in row_list) {
                conditions.add(c.get_search_condition());
            }
            
            // Create the object.  It will be added to the DB and SearchTable automatically.
            SearchOperator search_operator = (SearchOperator)operator.get_active();
            SavedSearchTable.get_instance().create(search_title.get_text(), search_operator, conditions);
        }
    }
    
    private void on_row_changed(SearchRowContainer row) {
        set_valid(row.is_complete());
    }
    
    private void on_title_changed() {
        set_valid(is_title_valid());
    }
    
    private bool is_title_valid() {
        if (edit_mode && previous_search != null && 
            previous_search.get_name() == search_title.get_text())
            return true; // Title hasn't changed.
        if (search_title.get_text().chomp() == "")
            return false;
        if (SavedSearchTable.get_instance().exists(search_title.get_text()))
            return false;
        return true;
    }
    
    // Call this with your new value for validity whenever a row or the title changes.
    private void set_valid(bool v) {
        if (!v) {
            valid = false;
        } else if (v != valid) {
            if (is_title_valid()) {
                // Go through rows to check validity.
                int valid_rows = 0;
                foreach (SearchRowContainer c in row_list) {
                    if (c.is_complete())
                        valid_rows++;
                }
                valid = (valid_rows == row_list.size);
            } else {
                valid = false; // title was invalid
            }
        }
        
        set_response_sensitive(Gtk.ResponseType.OK, valid);
    }
}
