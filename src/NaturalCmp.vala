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

class NaturalCmp {

    private static const int AFIRST = -1; // Return this value if a precedes b
    private static const int BFIRST = 1;
    private static const int EQUAL = 0;

    private static bool is_number(char c) {
        return (c.to_string() in "0123456789");
    }

    private static int rip_number(owned string s, ref int index) {
        /* 
         * Given a string in the form [0-9]*[a-zA-Z, etc]*
         * returns the int value of the first block and increments index
         * by its length as a side effect.
         */
        int number = 0;
        while (s.length != 0 && is_number(s[0])) {
            number = number*10;
            number += int.parse(s[0].to_string());
            s = s.substring(1);
            index++;
        }
        return number;
    }

    public static int compare(string a, string b) {
        /* 
         * Implements natural comparison.
         * Essentially this means that, like strcmp does, foo > bar and 1 > 2
         * BUT, unlike strcmp, foo10 > foo2 and 1 < 02.
         * See naturalcmp-test.vala
         */ 

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
                if (is_number(a[0])) {
                    if (is_number(b[0])) {
                        // both have trailing numerals: we have to parse the numbers
                        int a_chopdepth = 0;
                        int a_number = rip_number(a, ref a_chopdepth);
                        string a_chopped = "";
                        if (a.length > a_chopdepth) {
                            a_chopped = a.substring(a_chopdepth);
                        }

                        int b_chopdepth = 0;
                        int b_number = rip_number(b, ref b_chopdepth);
                        string b_chopped = "";
                        if (b.length > b_chopdepth) {
                            b_chopped = b.substring(b_chopdepth);
                        }

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
                    if (is_number(b[0])) {
                        // b starts with a numeral, a doesn't
                        return BFIRST;
                    } else { // neither starts with a numberal, we handle this pair of chars strcmp-style
                        if (a[0] > b[0]) {
                            return BFIRST;
                        } else if (a[0] < b[0]) {
                            return AFIRST;
                        } else {
                            // equal
                            return compare(a.substring(1),
                                           b.substring(1));
                        }
                    }
                }
            }
        }
    }
}
