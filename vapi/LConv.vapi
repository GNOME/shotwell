/* Copyright 2010-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */
namespace GLib {
    [Compact]
    [CCode (cheader_filename = "locale.h", cname = "struct lconv")]
    public class LConv {
      public string decimal_point;
      public string thousands_sep;
      public string grouping;

      public string int_curr_symbol;
      public string currency_symbol;
      public string mon_decimal_point;
      public string mon_thousands_sep;
      public string mon_grouping;
      public string positive_sign;
      public string negative_sign;
      public char int_frac_digits;
      public char frac_digits;

      public char p_cs_precedes;
      public char p_sep_by_space;
      public char n_cs_precedes;
      public char n_sep_by_space;

      public char p_sign_posn;
      public char n_sign_posn;

      public char int_p_cs_precedes;
      public char int_p_sep_by_space;
      public char int_n_cs_precedes;
      public char int_n_sep_by_space;
      public char int_p_sign_posn;
      public char int_n_sign_posn;
    }
	
    namespace Intl {
        [CCode (cname = "localeconv", cheader_filename = "locale.h")]
        public static unowned LConv localeconv();
    }
}

