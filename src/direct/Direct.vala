/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* This file is the master unit file for the Direct unit.  It should be edited to include
 * whatever code is deemed necessary.
 *
 * The init() and terminate() methods are mandatory.
 *
 * If the unit needs to be configured prior to initialization, add the proper parameters to
 * the preconfigure() method, implement it, and ensure in init() that it's been called.
 */

namespace Direct {

private File? initial_file = null;

public void preconfigure(File initial_file) {
    Direct.initial_file = initial_file;
}

public void init() throws Error {
    assert(initial_file != null);
    
    DirectPhoto.init(initial_file);
}

public void terminate() {
    DirectPhoto.terminate();
}

}

namespace Direct {

private static bool _entry_initialized = false;

public void init_entry() throws Error {
    if (_entry_initialized)
        return;
    _entry_initialized = true;

    Unit.init_entry(); Db.init_entry(); Util.init_entry(); Photos.init_entry(); Slideshow.init_entry(); Core.init_entry();

    Direct.init();
}

public void terminate_entry() {


    Direct.terminate();

    Unit.terminate_entry(); Db.terminate_entry(); Util.terminate_entry(); Photos.terminate_entry(); Slideshow.terminate_entry(); Core.terminate_entry();
}

}

namespace Direct {

public void app_init() throws Error {
    Direct.init_entry();
}

public void app_terminate() {
    Direct.terminate_entry();
}

}

