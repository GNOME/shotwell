/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* This file is the master unit file for the Folders unit.  It should be edited to include
 * whatever code is deemed necessary.
 *
 * The init() and terminate() methods are mandatory.
 *
 * If the unit needs to be configured prior to initialization, add the proper parameters to
 * the preconfigure() method, implement it, and ensure in init() that it's been called.
 */

namespace Folders {

static string? icon = null;
static string? have_photos_icon = null;

public void init() throws Error {
    icon = Resources.ICON_FOLDER;
    have_photos_icon = Resources.ICON_FOLDER_DOCUMENTS;
}

public void terminate() {
    icon = null;
    have_photos_icon = null;
}

}

namespace Folders {

private static bool _entry_initialized = false;

public void init_entry() throws Error {
    if (_entry_initialized)
        return;
    _entry_initialized = true;

    Unit.init_entry(); Sidebar.init_entry(); Photos.init_entry();

    Folders.init();
}

public void terminate_entry() {


    Folders.terminate();

    Unit.terminate_entry(); Sidebar.terminate_entry(); Photos.terminate_entry();
}

}

