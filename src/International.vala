/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

extern const string _LANG_SUPPORT_DIR;

public const string TRANSLATABLE = "translatable";

namespace InternationalSupport {
const string SYSTEM_LOCALE = "";
const string LANGUAGE_SUPPORT_DIRECTORY = _LANG_SUPPORT_DIR;

void init(string package_name, string locale = SYSTEM_LOCALE) {
    Intl.setlocale(LocaleCategory.ALL, locale);

    Intl.bindtextdomain(package_name, LANGUAGE_SUPPORT_DIRECTORY);
    Intl.bind_textdomain_codeset(package_name, "UTF-8");
    Intl.textdomain(package_name);
}
}

