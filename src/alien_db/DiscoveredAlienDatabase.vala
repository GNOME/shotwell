/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb {

/**
 * A light-weight wrapper that contains enough information to display the
 * database entry in the library window but can delay instantiating the
 * actual database instance until it is actually needed.
 */
public class DiscoveredAlienDatabase : Object {
    private AlienDatabaseID id;
    private AlienDatabaseDriver driver;
    private AlienDatabase database;
    
    public DiscoveredAlienDatabase(AlienDatabaseID id) {
        this.id = id;
        driver = AlienDatabaseHandler.get_instance().get_driver(id.driver_id);
    }
    
    public AlienDatabaseID get_id() {
        return id;
    }
    
    public string get_uri() {
        return id.to_uri();
    }
    
    /**
     * This method creates an actual instance of the database interface.
     * It is called when the application is ready to present the database
     * to the user as a page in the main library window.
     */
    public AlienDatabase get_database() throws DatabaseError, AlienDatabaseError {
        if (database == null) {
            database = driver.open_database(id);
        }
        return database;
    }
    
    /**
     * Release the underlying database object.
     */
    public void release_database() {
        database = null;
    }
}

}

