/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Util {
    // Use these file attributes when loading file information for a complete FileInfo objects
    public const string FILE_ATTRIBUTES = "standard::*,time::*,id::file,id::filesystem,etag::value";

    public const int64 USEC_PER_SEC = 1000000;

    // Returns true if the directory contains a .nomedia file (and thus should be
    // excluded from media scans/imports). Mirrors Android's .nomedia convention.
    public bool is_dir_nomedia_ignored(File dir) {
        try {
            return dir.get_child(".nomedia").query_exists(null);
        } catch (Error err) {
            return false;
        }
    }

    public void init() throws Error {
    }
    
    public void terminate() {
    }
}

namespace Util {

private static bool _entry_initialized = false;

public void init_entry() throws Error {
    if (_entry_initialized)
        return;
    _entry_initialized = true;

    Unit.init_entry();

    Util.init();
}

public void terminate_entry() {


    Util.terminate();

    Unit.terminate_entry();
}

}

