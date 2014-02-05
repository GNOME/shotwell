/* Copyright 2012-2014 Yorba Foundation
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

static Icon? opened_icon = null;
static Icon? closed_icon = null;
static Icon? have_photos_icon = null;

public void init() throws Error {
    opened_icon = new ThemedIcon(Resources.ICON_FOLDER_OPEN);
    closed_icon = new ThemedIcon(Resources.ICON_FOLDER_CLOSED);
    have_photos_icon = new ThemedIcon(Resources.ICON_FOLDER_DOCUMENTS);
}

public void terminate() {
    opened_icon = null;
    closed_icon = null;
    have_photos_icon = null;
}

}

