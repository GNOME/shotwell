/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Unit {
    public void init() throws Error {
    }
    
    public void terminate() {
    }
}

namespace Unit {

private static bool _entry_initialized = false;

public void init_entry() throws Error {
    if (_entry_initialized)
        return;
    _entry_initialized = true;



    Unit.init();
}

public void terminate_entry() {


    Unit.terminate();


}

}

