/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb {

/**
 * The main interface for a single instance of a tag held in the database.
 */
public interface AlienDatabaseTag : Object {
    public abstract string get_name();
    
    public abstract AlienDatabaseTag? get_parent();
}

}

