/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// See the note in MediaInterfaces.vala for some thoughts on the theory of expanding Shotwell's
// features via interfaces rather than class hierarchies.

// Indexable DataSources provide raw strings that may be searched against (and, in the future,
// indexed) for free-text search queries.  DataSources implementing Indexable must prepare and
// store (i.e. cache) these strings using prepare_indexable_string(s), as preparing the strings
// for each call is expensive.
//
// When the indexable string has changed, the object should fire an alteration of
// "indexable:keywords".  The prepare methods will not do this.

public interface Indexable : DataSource {
    public abstract unowned string? get_indexable_keywords();
    
    public static string? prepare_indexable_string(string? str) {
        if(is_string_empty(str))
            return null;
        return String.remove_diacritics(str.down());
    }
    
    public static string? prepare_indexable_strings(string[]? strs) {
        if (strs == null || strs.length == 0)
            return null;
        
        StringBuilder builder = new StringBuilder();
        int ctr = 0;
        do {
            if (!is_string_empty(strs[ctr])) {
                builder.append(strs[ctr].down());
                if (ctr < strs.length - 1)
                    builder.append_c(' ');
            }
        } while (++ctr < strs.length);
        
        return !is_string_empty(builder.str) ? builder.str : null;
    }
}

