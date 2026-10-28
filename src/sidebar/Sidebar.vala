/* SPDX-FileCopyrightText: 2016 Software Freedom Conservancy Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

namespace Sidebar {

public void init() throws Error {
}

public void terminate() {
}

}

namespace Sidebar {

private static bool _entry_initialized = false;

public void init_entry() throws Error {
    if (_entry_initialized)
        return;
    _entry_initialized = true;

    Unit.init_entry();

    Sidebar.init();
}

public void terminate_entry() {


    Sidebar.terminate();

    Unit.terminate_entry();
}

}

