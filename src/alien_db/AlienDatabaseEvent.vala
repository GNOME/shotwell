/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb {

/**
 * The main interface for a single instance of an event held in the database.
 */
public interface AlienDatabaseEvent : Object {
    public abstract string get_name();
}

}

