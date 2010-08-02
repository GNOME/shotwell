/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

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
 * The core handler that is responsible for handling the different plugins
 * and dispatching requests to the relevant driver.
 */
public class AlienDatabaseHandler {
    private static AlienDatabaseHandler instance;
    private Gee.Map<AlienDatabaseDriverID?, AlienDatabaseDriver> driver_map;
    
    /**
     * Initialisation method that creates a singleton instance.
     */
    public static void init() {
        instance = new AlienDatabaseHandler();
    }
    
    /**
     * Termination method that clears the singleton instance.
     */
    public static void terminate() {
        instance = null;
    }
    
    public static AlienDatabaseHandler get_instance() {
        return instance;
    }
    
    private AlienDatabaseHandler() {
        driver_map = new Gee.HashMap<AlienDatabaseDriverID?, AlienDatabaseDriver>(
            AlienDatabaseDriverID.hash, AlienDatabaseDriverID.equal, AlienDatabaseDriverID.equal
        );
        // at the moment, just one driver
        // TODO: change to a real plugin mechanism where each driver can
        // be installed independently from Shotwell
        register_driver(new FSpotDatabaseDriver());
    }
    
    public void register_driver(AlienDatabaseDriver driver) {
        driver_map.set(driver.get_id(), driver);
    }
    
    public void unregister_driver(AlienDatabaseDriver driver) {
        driver_map.unset(driver.get_id());
    }
    
    public Gee.Collection<AlienDatabaseDriver> get_drivers() {
        return driver_map.values;
    }
    
    public AlienDatabaseDriver get_driver(AlienDatabaseDriverID driver_id) {
        AlienDatabaseDriver driver = driver_map.get(driver_id);
        if (driver == null)
            warning("Could not find driver for id: %s", driver_id.id);
        return driver;
    }
    
    public Gee.Collection<DiscoveredAlienDatabase> get_discovered_databases() {
        Gee.ArrayList<DiscoveredAlienDatabase> discovered_databases =
            new Gee.ArrayList<DiscoveredAlienDatabase>();
        foreach (AlienDatabaseDriver driver in driver_map.values) {
            discovered_databases.add_all(driver.get_discovered_databases());
        }
        return discovered_databases;
    }
}

/**
 * A simple struct to represent an alien database driver ID.
 */
public struct AlienDatabaseDriverID {
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

/**
 * A simple struct to represent an alien database ID.
 */
public struct AlienDatabaseID {
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
            this.driver_id = AlienDatabaseDriverID(uri_elements[0]);
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

/**
 * The main interface for a single instance of a photo held in the database.
 * This interface assumes that the photograph can be accessed via the Vala
 * File classes.
 */
public interface AlienDatabasePhoto : Object {
    public abstract string get_folder_path();
    
    public abstract string get_filename();
    
    public abstract Gee.Collection<AlienDatabaseTag> get_tags();
    
    public abstract AlienDatabaseEvent? get_event();
    
    public abstract Rating get_rating();
    
    public abstract string? get_title();
    
    public abstract ImportID? get_import_id();
}

/**
 * The main interface for a single instance of a tag held in the database.
 */
public interface AlienDatabaseTag : Object {
    public abstract string get_name();
}

/**
 * The main interface for a single instance of an event held in the database.
 */
public interface AlienDatabaseEvent : Object {
    public abstract string get_name();
}

/**
 * A class that represents a version in the form x.y.z and is able to compare
 * different versions.
 */
public class AlienDatabaseVersion : Object, Gee.Comparable<AlienDatabaseVersion> {
    private int[] version;
    
    public AlienDatabaseVersion(int[] version) {
        this.version = version;
    }
    
    public AlienDatabaseVersion.from_string(string str_version, string separator = ".") {
        string[] version_items = str_version.split(separator);
        this.version = new int[version_items.length];
        for (int i = 0; i < version_items.length; i++)
            this.version[i] = version_items[i].to_int();
    }
    
    public string to_string() {
        string[] version_items = new string[this.version.length];
        for (int i = 0; i < this.version.length; i++)
            version_items[i] = this.version[i].to_string();
        return string.joinv(".", version_items);
    }
    
    public int compare_to(AlienDatabaseVersion other) {
        int max_len = ((this.version.length > other.version.length) ?
                       this.version.length : other.version.length);
        int res = 0;
        for(int i = 0; i < max_len; i++) {
            int this_v = (i < this.version.length ? this.version[i] : 0);
            int other_v = (i < other.version.length ? other.version[i] : 0);
            res = this_v - other_v;
            if (res != 0)
                break;
        }
        return res;
    }
}

