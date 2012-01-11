/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb {

/**
 * A simple class to represent an alien database driver ID.
 */
public class AlienDatabaseDriverID {
    public string id;
    
    public AlienDatabaseDriverID(string id) {
        this.id = id;
    }
    
    public static uint hash(void *a) {
        return ((AlienDatabaseDriverID *) a)->id.hash();
    }
    
    public static bool equal(void *a, void *b) {
        return ((AlienDatabaseDriverID *) a)->id == ((AlienDatabaseDriverID *) b)->id;
    }
}

/**
 * The main driver interface that all plugins should implement. This driver
 * interface is designed to automatically discover databases and create
 * instances of AlienDatabase that can interrogate the data.
 */
public interface AlienDatabaseDriver : Object {
    /**
     * Return a unique ID for this alien database driver.
     */
    public abstract AlienDatabaseDriverID get_id();
    
    /**
     * Return the display name for this driver.
     */
    public abstract string get_display_name();
    
    /**
     * This method returns all databases that are automatically discovered by
     * the driver.
     */
    public abstract Gee.Collection<DiscoveredAlienDatabase> get_discovered_databases();
    
    /**
     * This method opens a database given a database ID and returns an object
     * that is able to interrogate the data contained in the database.
     */
    public abstract AlienDatabase open_database(AlienDatabaseID db_id) throws DatabaseError, AlienDatabaseError;
    
    /**
     * This method opens a database given a file and returns an object
     * that is able to interrogate the data contained in the database.
     */
    public abstract AlienDatabase open_database_from_file(File db_file) throws DatabaseError, AlienDatabaseError;
    
    public abstract string get_menu_name();
    
    public abstract Gtk.ActionEntry get_action_entry();
}

}

