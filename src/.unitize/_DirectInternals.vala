/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 *
 * Auto-generated file.  Do not modify!
 */

namespace Direct {

private int _unit_init_count = 0;

public void init_entry() throws Error {
    if (_unit_init_count++ != 0)
        return;

    Unit.init_entry(); Db.init_entry(); Util.init_entry(); Photos.init_entry(); Slideshow.init_entry(); Core.init_entry();

    Direct.init();
}

public void terminate_entry() {
    if (_unit_init_count == 0 || --_unit_init_count != 0)
        return;

    Direct.terminate();

    Unit.terminate_entry(); Db.terminate_entry(); Util.terminate_entry(); Photos.terminate_entry(); Slideshow.terminate_entry(); Core.terminate_entry();
}

}
