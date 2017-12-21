/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 *
 * Auto-generated file.  Do not modify!
 */

namespace Library {

private int _unit_init_count = 0;

public void init_entry() throws Error {
    if (_unit_init_count++ != 0)
        return;

    Unit.init_entry(); Util.init_entry(); Threads.init_entry(); Db.init_entry(); Plugins.init_entry(); Slideshow.init_entry(); Photos.init_entry(); Publishing.init_entry(); Core.init_entry(); Sidebar.init_entry(); Events.init_entry(); Tags.init_entry(); Camera.init_entry(); Searches.init_entry(); DataImports.init_entry(); Folders.init_entry();

    Library.init();
}

public void terminate_entry() {
    if (_unit_init_count == 0 || --_unit_init_count != 0)
        return;

    Library.terminate();

    Unit.terminate_entry(); Util.terminate_entry(); Threads.terminate_entry(); Db.terminate_entry(); Plugins.terminate_entry(); Slideshow.terminate_entry(); Photos.terminate_entry(); Publishing.terminate_entry(); Core.terminate_entry(); Sidebar.terminate_entry(); Events.terminate_entry(); Tags.terminate_entry(); Camera.terminate_entry(); Searches.terminate_entry(); DataImports.terminate_entry(); Folders.terminate_entry();
}

}
