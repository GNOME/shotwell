/* Copyright 2009-2012 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace AlienDb {

/**
 * The error domain for alien databases
 */
public errordomain AlienDatabaseError {
    // Unsupported version: this can be due to an old legacy database,
    // a new database version that this version of Shotwell doesn't support
    // or a database version that could not be identified properly.
    UNSUPPORTED_VERSION
}

/**
 * A simple struct to represent an alien database ID.
 */
public class AlienDatabaseID {
    public AlienDatabaseDriverID driver_id;
    public string driver_specific_uri;
    
    public AlienDatabaseID(AlienDatabaseDriverID driver_id, string driver_specific_uri) {
        this.driver_id = driver_id;
        this.driver_specific_uri = driver_specific_uri;
    }
    
    public AlienDatabaseID.from_uri(string db_uri) {
        string[] uri_elements = db_uri.split(":", 2);
        if (uri_elements.length < 2) {
            error("Cannot create alien database ID from URI: %s", db_uri);
        } else {
            this.driver_id = new AlienDatabaseDriverID(uri_elements[0]);
            this.driver_specific_uri = uri_elements[1];
        }
    }
    
    public string to_uri() {
        return "%s:%s".printf(driver_id.id, driver_specific_uri);
    }
    
    public static uint hash(void *a) {
        return (
            AlienDatabaseDriverID.hash(&((AlienDatabaseID *) a)->driver_id) ^
            ((AlienDatabaseID *) a)->driver_specific_uri.hash()
        );
    }
    
    public static bool equal(void *a, void *b) {
        return (
            AlienDatabaseDriverID.equal(&((AlienDatabaseID *) a)->driver_id, &((AlienDatabaseID *) b)->driver_id) &&
            (((AlienDatabaseID *) a)->driver_specific_uri == ((AlienDatabaseID *) b)->driver_specific_uri)
        );
    }
}

/**
 * The main database interface that all plugins should implement. The driver
 * should return an instance of a class that implements this interface for
 * each open database. This interface is then used to query the underlying
 * database in order to import photographs. The driver itself is free to
 * instantiate objects of different classes for different database files if
 * required. For example, it is conceivable that a driver could supply
 * different implementations for different versions of the same database.
 */
public interface AlienDatabase : Object {
    public abstract string get_uri();
    
    public abstract string get_display_name();

    public abstract AlienDatabaseVersion get_version() throws DatabaseError;
    
    public abstract Gee.Collection<AlienDatabasePhoto> get_photos() throws DatabaseError;
}

}

