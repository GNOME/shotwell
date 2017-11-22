/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

/* This file is the master unit file for the Photo unit.  It should be edited to include
 * whatever code is deemed necessary.
 *
 * The init() and terminate() methods are mandatory.
 *
 * If the unit needs to be configured prior to initialization, add the proper parameters to
 * the preconfigure() method, implement it, and ensure in init() that it's been called.
 */

namespace Photos {

// preconfigure may be deleted if not used.
public void preconfigure() {
}

public void init() throws Error {
    foreach (PhotoFileFormat format in PhotoFileFormat.get_supported())
        format.init();
}

public void terminate() {
}

}

