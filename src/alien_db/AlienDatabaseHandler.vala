/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb {

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
        // Check for null in case init() is called more than once.
        if(instance == null)
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
    
    public void add_menu_entries(Gtk.UIManager ui, string placeholder) {
        foreach (AlienDatabaseDriver driver in get_drivers()) {
            ui.add_ui(ui.new_merge_id(), placeholder,
                driver.get_menu_name(),
                driver.get_action_entry().name,
                Gtk.UIManagerItemType.MENUITEM, false);
        }
    }
}

}

