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

private static int read_number(owned string s, ref int byte_index) {
    /*
     * Given a string in the form [numerals]*[everythingelse]*
     * returns the int value of the first block and increments index
     * by its length as a side effect.
     * Notice that "numerals" is not just 0-9 but everything else 
     * Unicode considers a numeral (see: string::isdigit())
     */
    int number = 0;

    while (s.length != 0 && s.get_char(0).isdigit()) {
        number = number*10;
        number += s.get_char(0).digit_value();
        int second_char = s.index_of_nth_char(1);
        s = s.substring(second_char);
        byte_index += second_char;
    }
    return number;
}

public static int compare(owned string a, owned string b) {
    /*
     * Implements natural comparison.
     * Essentially this means that, like strcmp does, foo > bar and 1 < 2
     * BUT, unlike strcmp, foo10 > foo2 and 1 < 02.
     * See naturalcmp-test.vala
     */
    const int INIT_VALUE = -255;
    int result = INIT_VALUE;

    assert (a.validate() && b.validate());
    bool a_eos = (a.length == 0);
    bool b_eos = (b.length == 0);

    while (!a_eos && !b_eos && result == INIT_VALUE) {
        assert (a.validate() && b.validate());
        unichar a_head = a.get_char(0);
        unichar b_head = b.get_char(0);
        if (a_head.isdigit() && b_head.isdigit()) {
            // both have trailing numerals: we have to parse the numbers
            int a_chop_bytes_depth = 0;
            // This is in bytes
            int a_number = read_number(a, ref a_chop_bytes_depth);
            string a_chopped = "";
            assert (a.length >= a_chop_bytes_depth);
            // read_number should not seek beyond string length.
            a_chopped = a.substring(a_chop_bytes_depth);

            int b_chop_bytes_depth = 0;
            int b_number = read_number(b, ref b_chop_bytes_depth);
            string b_chopped = "";
            assert (b.length >= b_chop_bytes_depth);
            b_chopped = b.substring(b_chop_bytes_depth);

            // We had decided earlier that we had two trailing numerals.
            // We should have chopped something off each string

            assert(a.length != a_chopped.length &&
                   b.length != b_chopped.length);

            if (a_number > b_number) {
                assert(result == INIT_VALUE);
                result = BFIRST;
            } else if (a_number < b_number) {
                assert(result == INIT_VALUE);
                result = AFIRST;
            } else {
                /* Nice, both numbers are exactly the same. 
                 * We evaulate whatever comes after them.
                 * Caveat: we'd get here if we had, e.g., asd0123 and asd123 (both evaluate to 123).
                 * Hence, we cannot assume that we chopped the same amount of chars off each
                 */
                a = a_chopped;
                b = b_chopped;
            }
        } else if (a_head.isdigit()) {
            // a starts with a numeral, b doesn't
            assert(result == INIT_VALUE);
            result = AFIRST;
        } else if (b_head.isdigit()) {
            // b starts with a numeral, a doesn't
            assert(result == INIT_VALUE);
            result = BFIRST;
        } else { // neither starts with a numberal, we handle this pair of chars strcmp-style
            if (a.get_char(0) > b.get_char(0)) {
                assert(result == INIT_VALUE);
                result = BFIRST;
            } else if (a.get_char(0) < b.get_char(0)) {
                assert(result == INIT_VALUE);
                result = AFIRST;
            } else {
                // equal
                int a_second_char = a.index_of_nth_char(1);
                int b_second_char = b.index_of_nth_char(1);
                a = a.substring(a_second_char);
                b = b.substring(b_second_char);
            }
        }        

        a_eos = (a.length == 0);
        b_eos = (b.length == 0);
    }

    if (a_eos && b_eos) {
        // a,b had equal length, reached the end.
        assert(result == INIT_VALUE);
        result = EQUAL;
    } else if (a_eos) { // a was shorter, reached a's end.
        assert(result == INIT_VALUE);
        result = AFIRST;
    } else if (b_eos) { // b was shorter, reached b's end.
        assert(result == INIT_VALUE);
        result = BFIRST;
    } else { // we didn't reach the end of either
        assert (result != INIT_VALUE); // We got something before running out of both a,b
    }

    return result;
}

}
