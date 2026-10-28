/* SPDX-FileCopyrightText: 2016 Software Freedom Conservancy Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

namespace Events {

public void init() throws Error {
    Events.Branch.init();
}

public void terminate() {
    Events.Branch.terminate();
}

}

namespace Events {

private static bool _entry_initialized = false;

public void init_entry() throws Error {
    if (_entry_initialized)
        return;
    _entry_initialized = true;

    Unit.init_entry(); Sidebar.init_entry();

    Events.init();
}

public void terminate_entry() {


    Events.terminate();

    Unit.terminate_entry(); Sidebar.terminate_entry();
}

}

