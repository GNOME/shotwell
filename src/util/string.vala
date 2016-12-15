/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern int64 g_ascii_strtoll(string str, out char *endptr, uint num_base);

public const int DEFAULT_USER_TEXT_INPUT_LENGTH = 1024;

public inline bool is_string_empty(string? s) {
    return (s == null || s[0] == '\0');
}

// utf8 case sensitive compare
public int utf8_cs_compare(void *a, void *b) {
    return ((string) a).collate((string) b);
}

// utf8 case insensitive compare
public int utf8_ci_compare(void *a, void *b) {
    return ((string) a).down().collate(((string) b).down());
}

// utf8 array to string
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

// string to uchar array
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
    STRIP_CRLF,
    NORMALIZE,
    DEFAULT = EMPTY_IS_NULL | VALIDATE | INVALID_IS_NULL | STRIP_CRLF | STRIP | NORMALIZE;
}

private string? guess_convert(string text) {
    string? output = null;
    size_t bytes_read = 0;
    unowned string charset = null;
    debug ("CONVERT: Text did not validate as UTF-8, trying conversion");

    // Try with locale
    if (!GLib.get_charset(out charset)) {
        output = text.locale_to_utf8(text.length, out bytes_read, null, null);
        if (bytes_read == text.length) {
            debug ("CONVERT: Locale is not UTF-8, convert from %s", charset);
            return output;
        }
    }

    try {
        output = GLib.convert (text, text.length, "UTF-8", "WINDOWS-1252", out bytes_read);
        charset = "WINDOWS-1252";
    } catch (ConvertError error) {
        if (error is ConvertError.NO_CONVERSION) {
            try {
                output = GLib.convert (text, text.length, "UTF-8", "ISO-8859-1", out bytes_read);
                charset = "ISO-8859-1";
            } catch (Error error) { /* do nothing */ }
        }
    }

    if (bytes_read == text.length) {
        debug ("CONVERT: Guessed conversion from %s", charset);

        return output;
    }

    return null;
}

public string? prepare_input_text(string? text, PrepareInputTextOptions options, int dest_length) {
    if (text == null)
        return null;
    
    string? prepped = text;
    if (PrepareInputTextOptions.VALIDATE in options) {
        if (!text.validate()) {
            prepped = guess_convert (text);

            if (prepped == null) {
                return (options & PrepareInputTextOptions.INVALID_IS_NULL) != 0 ? null : "";
            }
        }
    }

    // Using composed form rather than GLib's default (decomposed) as NFC is the preferred form in
    // Linux and WWW.  More importantly, Pango seems to have serious problems displaying decomposed
    // forms of Korean language glyphs (and perhaps others).  See:
    // http://trac.yorba.org/ticket/2952
    if ((options & PrepareInputTextOptions.NORMALIZE) != 0)
        prepped = prepped.normalize(-1, NormalizeMode.NFC);
    
    if ((options & PrepareInputTextOptions.STRIP) != 0)
        prepped = prepped.strip();
        
    // Ticket #3245 - Prevent carriage return mayhem
    // in image titles, tag names, etc.
    if ((options & PrepareInputTextOptions.STRIP_CRLF) != 0)
        prepped = prepped.delimit("\n\r", ' ');
    
    if ((options & PrepareInputTextOptions.EMPTY_IS_NULL) != 0 && is_string_empty(prepped))
        return null;
    
    // Ticket #3196 - Allow calling functions to limit the length of the 
    // string we return to them. Passing any negative value is interpreted 
    // as 'do not truncate'.
    if (dest_length >= 0) { 
        StringBuilder sb = new StringBuilder(prepped);
        sb.truncate(dest_length);
        return sb.str;
    }
    
    // otherwise, return normally.
    return prepped;
}

public int64 parse_int64(string str, int num_base) {
    return g_ascii_strtoll(str, null, num_base);
}

namespace String {

public inline bool contains_char(string haystack, unichar needle) {
    return haystack.index_of_char(needle) >= 0;
}

public inline bool contains_str(string haystack, string needle) {
    return haystack.index_of(needle) >= 0;
}

public inline string? sliced_at(string str, int index) {
    return (index >= 0) ? str[index:str.length] : null;
}

public inline string? sliced_at_first_str(string haystack, string needle, int start_index = 0) {
    return sliced_at(haystack, haystack.index_of(needle, start_index));
}

public inline string? sliced_at_last_str(string haystack, string needle, int start_index = 0) {
    return sliced_at(haystack, haystack.last_index_of(needle, start_index));
}

public inline string? sliced_at_first_char(string haystack, unichar ch, int start_index = 0) {
    return sliced_at(haystack, haystack.index_of_char(ch, start_index));
}

public inline string? sliced_at_last_char(string haystack, unichar ch, int start_index = 0) {
    return sliced_at(haystack, haystack.last_index_of_char(ch, start_index));
}

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

public string remove_diacritics(string istring) {
    var builder = new StringBuilder ();
    unichar ch;
    int i = 0;
    while(istring.normalize().get_next_char(ref i, out ch)) {
        switch(ch.type()) {
            case UnicodeType.CONTROL:
            case UnicodeType.FORMAT:
            case UnicodeType.UNASSIGNED:
            case UnicodeType.NON_SPACING_MARK:
            case UnicodeType.COMBINING_MARK:
            case UnicodeType.ENCLOSING_MARK:
            // Ignore those
                continue;
        }
        builder.append_unichar(ch);
    }
    return builder.str;
}

public string to_hex_string(string str) {
    StringBuilder builder = new StringBuilder();
    
    uint8 *data = (uint8 *) str;
    while (*data != 0)
        builder.append_printf("%02Xh%s", *data++, (*data != 0) ? " " : "");
    
    return builder.str;
}

// A note on the collated_* and precollated_* methods:
//
// A bug report (http://trac.yorba.org/ticket/3152) indicated that two different Hirigana characters
// as Tag names would trigger an assertion.  Investigation showed that the characters' collation
// keys computed as equal when the locale was set to anything but the default locale (C) or
// Japanese.  A related bug was that another hash table was using str_equal, which does not use
// collation, meaning that in one table the strings were seen as the same and in another as
// different.
//
// The solution we arrived at is to use collation whenever possible, but if two strings have the
// same collation, then fall back on strcmp(), which looks for byte-for-byte comparisons.  Note
// that this technique requires that both strings have been properly composed (use
// prepare_input_text() for that task) so that equal UTF-8 strings are byte-for-byte equal as
// well.

// See note above.
public uint collated_hash(void *ptr) {
    string str = (string) ptr;
    
    return str_hash(str.collate_key());
}

// See note above.
public uint precollated_hash(void *ptr) {
    return str_hash((string) ptr);
}

// See note above.
public int collated_compare(void *a, void *b) {
    string astr = (string) a;
    string bstr = (string) b;
    
    int result = astr.collate(bstr);
    
    return (result != 0) ? result : strcmp(astr, bstr);
}

// See note above.
public int precollated_compare(string astr, string akey, string bstr, string bkey) {
    int result = strcmp(akey, bkey);
    
    return (result != 0) ? result : strcmp(astr, bstr);
}

// See note above.
public bool collated_equals(void *a, void *b) {
    return collated_compare(a, b) == 0;
}

// See note above.
public bool precollated_equals(string astr, string akey, string bstr, string bkey) {
    return precollated_compare(astr, akey, bstr, bkey) == 0;
}

}
