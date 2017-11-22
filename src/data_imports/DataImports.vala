/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* This file is the master unit file for the DataImports unit.  It should be edited to include
 * whatever code is deemed necessary.
 *
 * The init() and terminate() methods are mandatory.
 *
 * If the unit needs to be configured prior to initialization, add the proper parameters to
 * the preconfigure() method, implement it, and ensure in init() that it's been called.
 */

namespace DataImports {

public void init() throws Error {
    string[] core_ids = new string[0];
    core_ids += "org.yorba.shotwell.dataimports.fspot";
    
    Plugins.register_extension_point(typeof(Spit.DataImports.Service), _("Data Imports"),
        Resources.IMPORT, core_ids);
}

public void terminate() {
}

}

