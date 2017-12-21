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

