/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Entry completion for values separated by separators (e.g. comma in the case of tags)
// Partly inspired by the class of the same name in gtkmm-utils by Marko Anastasov
public class EntryMultiCompletion : Gtk.EntryCompletion {
    private string delimiter;

    public EntryMultiCompletion(Gee.Collection<string> completion_list, string? delimiter) {
        assert(delimiter == null || delimiter.length == 1);
        this.delimiter = delimiter;

        set_model(create_completion_store(completion_list));
        set_text_column(0);
        set_match_func(match_func);
    }

    private static Gtk.ListStore create_completion_store(Gee.Collection<string> completion_list) {
        Gtk.ListStore completion_store = new Gtk.ListStore(1, typeof(string));
        Gtk.TreeIter store_iter;
        Gee.Iterator<string> completion_iter = completion_list.iterator();
        while (completion_iter.next()) {
            completion_store.append(out store_iter);
            completion_store.set(store_iter, 0, completion_iter.get(), -1);
        }

        return completion_store;
    }

    private bool match_func(Gtk.EntryCompletion completion, string key, Gtk.TreeIter iter) {
        Gtk.TreeModel model = completion.get_model();
        string possible_match;
        model.get(iter, 0, out possible_match);

        // Normalize key and possible matches to allow comparison of non-ASCII characters.
        // Use a "COMPOSE" normalization to allow comparison to the position value returned by
        // Gtk.Entry, i.e. one character=one position. Using the default normalization a character
        // like "é" or "ö" would have a length of two.
        possible_match = possible_match.casefold().normalize(-1, NormalizeMode.ALL_COMPOSE);
        string normed_key = key.normalize(-1, NormalizeMode.ALL_COMPOSE);

        if (delimiter == null) {
            return possible_match.has_prefix(normed_key.strip());
        } else {
            if (normed_key.contains(delimiter)) {
                // check whether cursor is before last delimiter
                int offset = normed_key.char_count(normed_key.last_index_of_char(delimiter[0]));
                int position = ((Gtk.Entry) get_entry()).get_position();
                if (position <= offset)
                    return false; // TODO: Autocompletion for tags not last in list
            }

            string last_part = get_last_part(normed_key.strip(), delimiter);

            if (last_part.length == 0)
                return false; // need at least one character to show matches

            return possible_match.has_prefix(last_part.strip());
        }
    }

    public override bool match_selected(Gtk.TreeModel model, Gtk.TreeIter iter) {
        string match;
        model.get(iter, 0, out match);

        Gtk.Entry entry = (Gtk.Entry)get_entry();

        string old_text = entry.get_text().normalize(-1, NormalizeMode.ALL_COMPOSE);
        if (old_text.length > 0) {
            if (old_text.contains(delimiter)) {
                old_text = old_text.substring(0, old_text.last_index_of_char(delimiter[0]) + 1) + (delimiter != " " ? " " : "");
            } else
                old_text = "";
        }

        string new_text = old_text + match + delimiter + (delimiter != " " ? " " : "");
        entry.set_text(new_text);
        entry.set_position((int) new_text.length);

        return true;
    }

    // Find last string after any delimiter
    private static string get_last_part(string s, string delimiter) {
        string[] split = s.split(delimiter);

        if((split != null) && (split[0] != null)) {
            return split[split.length - 1];
        } else {
            return "";
        }
    }
}
