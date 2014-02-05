/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

[CCode (cprefix="", lower_case_cprefix="")]
namespace ExtendedPosix {
    [CCode (cheader_filename="unistd.h")]
    public long sysconf(int name);
    
    [CCode (cprefix="", lower_case_cprefix="")]
    enum ConfName {
        _SC_NPROCESSORS_CONF,
        _SC_NPROCESSORS_ONLN
    }
}

