/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Tags {

public void init() throws Error {
    Tags.SidebarEntry.init();
}

public void terminate() {
    Tags.SidebarEntry.terminate();
}

}

namespace Tags {

private static bool _entry_initialized = false;

public void init_entry() throws Error {
    if (_entry_initialized)
        return;
    _entry_initialized = true;

    Unit.init_entry(); Sidebar.init_entry();

    Tags.init();
}

public void terminate_entry() {


    Tags.terminate();

    Unit.terminate_entry(); Sidebar.terminate_entry();
}

}

