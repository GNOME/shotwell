/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/* This file is the master unit file for the AlienDb.FSpot unit.  It should be edited to include
 * whatever code is deemed necessary.
 *
 * The init() and terminate() methods are mandatory.
 *
 * If the unit needs to be configured prior to initialization, add the proper parameters to
 * the preconfigure() method, implement it, and ensure in init() that it's been called.
 */

namespace AlienDb.FSpot {

// preconfigure may be deleted if not used.
public void preconfigure() {
}

public void init() throws Error {
    FSpotDatabaseDriver.init();
    AlienDb.AlienDatabaseHandler.get_instance().register_driver(
        FSpotDatabaseDriver.get_instance()
    );
}

public void terminate() {
    AlienDb.AlienDatabaseHandler.get_instance().unregister_driver(
        FSpotDatabaseDriver.get_instance()
    );
    FSpotDatabaseDriver.terminate();
}

}

