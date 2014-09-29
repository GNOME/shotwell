/**
 * NaturalCmp
 * Simple helper class for natural comparison in Vala.
 *
 * (c) Tobia Tesan <tobia.tesan@gmail.com>, 2014
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 */

namespace NaturalCmp {

private const int AFIRST = -1; // Return this value if a precedes b
private const int BFIRST = 1;
private const int EQUAL = 0;

private static int rip_number(owned string s, ref int index) {
    /*
     * Given a string in the form [0-9]*[a-zA-Z, etc]*
     * returns the int value of the first block and increments index
     * by its length as a side effect.
     */
    int number = 0;
    while (s.length != 0 && s.get_char(0).isdigit()) {
        number = number*10;
        number += s.get_char(0).digit_value();
        int second_char = s.index_of_nth_char(1);
        s = s.substring(second_char);
        index++;
    }
    return number;
}

public static int compare(string a, string b) {
    /*
     * Implements natural comparison.
     * Essentially this means that, like strcmp does, foo > bar and 1 < 2
     * BUT, unlike strcmp, foo10 > foo2 and 1 < 02.
     * See naturalcmp-test.vala
     */

    assert (a.validate() && b.validate());

    if (a.length == 0) {
        if (b.length == 0) {
            // a,b == ""
            return EQUAL;
        } else {
            // Just a == ""
            return AFIRST;
        }
    } else {  // a != ""
        if (b.length == 0) {
            return BFIRST;
        } else {
            // Both a,b != ""
            unichar a_head = a.get_char(0);
            unichar b_head = b.get_char(0);
            if (a_head.isdigit()) { 
                if (b_head.isdigit()) {
                    // both have trailing numerals: we have to parse the numbers
                    int a_chop_bytes_depth = 0;
                    // This is in bytes
                    int a_number = rip_number(a, ref a_chop_bytes_depth);
                    string a_chopped = "";
                    assert (a.length >= a_chop_bytes_depth);
                    // rip_number should not seek beyond string length.
                    a_chopped = a.substring(a_chop_bytes_depth);

                    int b_chop_bytes_depth = 0;
                    int b_number = rip_number(b, ref b_chop_bytes_depth);
                    string b_chopped = "";
                    assert (b.length >= b_chop_bytes_depth);
                    b_chopped = b.substring(b_chop_bytes_depth);

                    if (a_number > b_number) {
                        return BFIRST;
                    } else if (a_number < b_number) {
                        return AFIRST;
                    } else {
                        /* Nice, both numbers are exactly the same. 
                         * We evaulate whatever comes after them.
                         * Caveat: we'd get here if we had, e.g., asd0123 and asd123 (both evaluate to 123).
                         * Hence, we cannot assume that we chopped the same amount of chars off each
                         */
                        return compare(a_chopped,b_chopped);
                    }
                } else {
                    // a starts with a numeral, b doesn't
                    return AFIRST;
                }
            } else {
                if (b_head.isdigit()) {
                    // b starts with a numeral, a doesn't
                    return BFIRST;
                } else { // neither starts with a numberal, we handle this pair of chars strcmp-style
                    if (a.get_char(0) > b.get_char(0)) {
                        return BFIRST;
                    } else if (a.get_char(0) < b.get_char(0)) {
                        return AFIRST;
                    } else {
                        // equal
                        int a_second_char = a.index_of_nth_char(1);
                        int b_second_char = b.index_of_nth_char(1);
                        return compare(a.substring(a_second_char),
                                       b.substring(b_second_char));
                    }
                }
            }
        }
    }
}

}
