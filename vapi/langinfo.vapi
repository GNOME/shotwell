/* Copyright 2016 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */
namespace Nl {
    [CCode (cname="nl_item", cheader_filename = "langinfo.h")]
    enum Item {
        [CCode (cname="CODESET")]
        CODESET,
        [CCode (cname="D_T_FMT")]
        D_T_FMT,
        [CCode (cname="D_FMT")]
        D_FMT,
        [CCode (cname="T_FMT")]
        T_FMT,
        [CCode (cname="THOUSEP")]
        THOUSEP,
        [CCode (cname="RADIXCHAR")]
        RADIXCHAR
    }

    [CCode (cheader_filename = "langinfo.h")]
    static unowned string? langinfo (Item item);
}
