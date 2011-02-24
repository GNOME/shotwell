/* Copyright 2010-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public inline bool is_string_empty(string? s) {
    return (s == null || s[0] == '\0');
}

public int utf8_cs_compare(void *a, void *b) {
    return ((string) a).collate((string) b);
}

public int utf8_ci_compare(void *a, void *b) {
    return ((string) a).down().collate(((string) b).down());
}

public string uchar_array_to_string(uchar[] data, int length = -1) {
    if (length < 0)
        length = data.length;
    
    StringBuilder builder = new StringBuilder();
    for (int ctr = 0; ctr < length; ctr++) {
        if (data[ctr] != '\0')
            builder.append_c((char) data[ctr]);
        else
            break;
    }
    
    return builder.str;
}

public uchar[] string_to_uchar_array(string str) {
    uchar[] data = new uchar[0];
    for (int ctr = 0; ctr < str.length; ctr++)
        data += (uchar) str[ctr];
    
    return data;
}

// Markup.escape_text() will crash if the UTF-8 text is not valid; it relies on a call to 
// g_utf8_next_char(), which demands that the string be validated before use, which escape_text()
// does not do.  This handles this problem by kicking back an empty string if the text is not
// valid.  Text should be validated upon entry to the system as well to guard against this
// problem.
//
// Null strings are accepted; they will result in an empty string returned.
public inline string guarded_markup_escape_text(string? plain) {
    return (!is_string_empty(plain) && plain.validate()) ? Markup.escape_text(plain) : "";
}

public long find_last_offset(string str, char c) {
    long offset = str.length;
    while (--offset >= 0) {
        if (str[offset] == c)
            return offset;
    }
    
    return -1;
}

// Helper function for searching an array of case-insensitive strings.  The array should be
// all lowercase.
public bool is_in_ci_array(string str, string[] strings) {
    string strdown = str.down();
    foreach (string str_element in strings) {
        if (strdown == str_element)
            return true;
    }
    
    return false;
}

[Flags]
public enum PrepareInputTextOptions {
    EMPTY_IS_NULL,
    VALIDATE,
    INVALID_IS_NULL,
    STRIP,
    NORMALIZE,
    DEFAULT = EMPTY_IS_NULL | VALIDATE | INVALID_IS_NULL | STRIP | NORMALIZE;
}

public string? prepare_input_text(string? text, PrepareInputTextOptions options = PrepareInputTextOptions.DEFAULT) {
    if (text == null)
        return null;
    
    if ((options & PrepareInputTextOptions.VALIDATE) != 0 && !text.validate())
        return (options & PrepareInputTextOptions.INVALID_IS_NULL) != 0 ? null : "";
    
    string prepped = text;
    
    // Using composed form rather than GLib's default (decomposed) as NFC is the preferred form in
    // Linux and WWW.  More importantly, Pango seems to have serious problems displaying decomposed
    // forms of Korean language glyphs (and perhaps others).  See:
    // http://trac.yorba.org/ticket/2952
    if ((options & PrepareInputTextOptions.NORMALIZE) != 0)
        prepped = prepped.normalize(-1, NormalizeMode.NFC);
    
    if ((options & PrepareInputTextOptions.STRIP) != 0)
        prepped = prepped.strip();
    
    if ((options & PrepareInputTextOptions.EMPTY_IS_NULL) != 0 && is_string_empty(prepped))
        return null;
    
    return prepped;
}

namespace String {

// Note that this method currently turns a word of all zeros into empty space ("000" -> "")
public string strip_leading_zeroes(string str) {
    StringBuilder stripped = new StringBuilder();
    bool prev_is_space = true;
    for (unowned string iter = str; iter.get_char() != 0; iter = iter.next_char()) {
        unichar ch = iter.get_char();
        
        if (!prev_is_space || ch != '0') {
            stripped.append_unichar(ch);
            prev_is_space = ch.isspace();
        }
    }
    
    return stripped.str;
}

}

