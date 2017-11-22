/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Shotwell Pluggable Interface Technology (SPIT)
 *
 * This is the front-end interface for all modules (i.e. .so/.la files) that allows for Shotwell
 * to query them for information and to get a list of all plug-ins stored in the module. This
 * is named Shotwell Pluggable Interface Technology (SPIT). This is intended only to last long
 * enough for another generic plug-in library (most likely Peas) to be used later.
 *
 * The Spit namespace is used for all interfaces and code that are made available to plugins or
 * are exposed by plugins.
 *
 * More information can be found at [[https://wiki.gnome.org/Apps/Shotwell/Architecture/WritingPlugins]]
 */
namespace Spit {

/**
 * Reserved interface value denoting an unsupported interface version.
 *
 * All interface versions should be zero-based and incrementing.
 */
public const int UNSUPPORTED_INTERFACE = -1;

/**
 * Current version of the SPIT interface.
 */
public const int CURRENT_INTERFACE = 0;

/**
 * A utility function for checking host interfaces against one's own and returning the right value.
 *
 * Note that this only works if the caller operates on only one interface version (and cannot mutate
 * between multiple ones).
 *
 * @param min_host_interface The minimum supported host interface version.
 * @param max_host_interface The maximum supported host interface version.
 * @param plugin_interface The interface version supported by the Pluggable.
 * 
 * @return The plugin's interface version if supported, {@link UNSUPPORTED_INTERFACE} otherwise.
 */
public int negotiate_interfaces(int min_host_interface, int max_host_interface, int plugin_interface) {
    return (min_host_interface > plugin_interface || max_host_interface < plugin_interface)
        ? UNSUPPORTED_INTERFACE : plugin_interface;
}

/**
 * SPIT entry point parameters.
 *
 * The host application passes a pointer to this structure for the module's information.
 * The pointer should //not// be held, as it may be freed or reused by the host application
 * after calling the entry point. The module should copy any information it may need (or hold
 * a GObject reference) in its own memory space.
 *
 * Note that the module //must// fill in the module_spit_interface field with the SPIT interface
 * version it understands prior to returning control.
 */
public struct EntryPointParams {
    /**
     * The host's minimum supported interface version.
     */
    public int host_min_spit_interface;
    /**
     * The host's maximum supported interface version.
     */
    public int host_max_spit_interface;
    /**
     * The module returns here the interface version of SPIT it supports,
     * {@link UNSUPPORTED_INTERFACE} otherwise.
     */
    public int module_spit_interface;
    /**
     * A File object representing the library file (.so/la.) that the plugin was loaded from.
     */
    public File module_file;
}

/**
 * SPIT API entry point.
 *
 * Host application passes in the minimum and maximum version of the SPIT
 * interface it supports (values are inclusive) in the {@link EntryPointParams} struct. 
 * The module returns the version it wishes to use and a pointer to a {@link Spit.Module} (which 
 * will remain ref'ed by the host as long as the module is loaded in memory). The module should 
 * return {@link UNSUPPORTED_INTERFACE} if the min/max are out of its range and null for its 
 * Spit.Module. ({@link negotiate_interfaces} is good for dealing with this.)
 * 
 * @return A {@link Spit.Module} if the interface negotiation is acceptable, null otherwise.
 */
[CCode (has_target = false)]
public delegate Module? EntryPoint(EntryPointParams *params);

/**
 * SPIT entry point name, which matches {@link EntryPoint}'s interface
 */
public const string ENTRY_POINT_NAME = "spit_entry_point";

/**
 * A Module represents the resources of an entire dynamically-linked module (i.e. a .so/.la).
 *
 * A module holds zero or more Shotwell plugins ({@link Pluggable}). Once the module has been
 * loaded into process space this object is retrieved by Shotwell. All calls to the module and
 * its plugins are resolved through this interface.
 *
 * Note: The module is responsible for holding the reference to the Module object, of which there
 * should be only one in the library file. The module should implement a g_module_unload method
 * and drop the reference there.
 */
public interface Module : Object {
    /**
     * Returns a user-visible string describing the module.
     */
    public abstract unowned string get_module_name();
    
    /**
     * Returns a user-visible string describing the module version.
     * 
     * Note that this may be programmatically interpreted at some point, so use a widespread 
     * versioning scheme.
     */
    public abstract unowned string get_version();
    
    /**
     * Returns a unique identifier for this module.
     * 
     * This is used to differentiate between multiple
     * installed versions and to determine which one should be used (i.e. if a module is available
     * in a system directory and a user directory). This name is case-sensitive.
     * 
     * Best practice: use a reverse-DNS-order scheme, a la Java's packages
     * (i.e. "org.yorba.shotwell.frotz").
     */
    public abstract unowned string get_id();
    
    /**
     * Returns an array of {@link Pluggable} that represent each plugin available in the module.
     *
     * May return NULL or an empty array.
     */
    public abstract unowned Pluggable[]? get_pluggables();
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

/**
 * A structure holding an assortment of information about a {@link Pluggable}.
 */
public struct PluggableInfo {
    public string? version;
    public string? brief_description;
    /**
     * A comma-delimited list of the authors of this {@link Pluggable}.
     */
    public string? authors;
    public string? copyright;
    public string? license;
    public bool is_license_wordwrapped;
    public string? website_url;
    public string? website_name;
    public string? translators;
    /**
     * An icon representing this plugin at one or more sizes. Shotwell may select an icon 
     * according to the size that closest fits the control its being drawn in.
     */
    public Gdk.Pixbuf[]? icons;
}

/**
 * A generic interface to all Shotwell plugins.
 *
 * Each plugin in a module needs to implement this interface at a minimum. Extension
 * points may have (and probably will have) specific interface requirements as well.
 */
public interface Pluggable : Object {
    /**
     * Pluggable interface version negotiation.
     *
     * Like the {@link EntryPoint}, this mechanism allows for the host to negotiate with the Pluggable
     * for its interface version. If the pluggable does not support an interface between the
     * two ranges (inclusive), it should return {@link UNSUPPORTED_INTERFACE}.
     *
     * Note that this is ''not'' a negotiation of the SPIT interface versions (which is the
     * responsibility of {@link EntryPoint}. Rather, each extension point is expected to version
     * its own cluster of interfaces. It is that interface version that is being negotiated here.
     *
     * {@link negotiate_interfaces} can be used to implement this method.
     *
     * @param min_host_interface The host's minimum supported interface version number
     *        //for this Pluggable's intended extension point//.
     * @param max_host_interface The host's maximum supported interface version number
     *        //for this Pluggable's intended extension point//.
     *
     * @return The version number supported by the host and the Pluggable or
     *         {@link UNSUPPORTED_INTERFACE}.
     */
    public abstract int get_pluggable_interface(int min_host_interface, int max_host_interface);
    
    /**
     * Returns a unique identifier for this Pluggable.
     *
     * Like {@link Module.get_id}, best practice is to use a reverse-DNS-order scheme to avoid 
     * conflicts.
     */
    public abstract unowned string get_id();
    
    /**
     * Returns a user-visible name for the Pluggable.
     */
    public abstract unowned string get_pluggable_name();
    
    /**
     * Returns extra information about the Pluggable that is used to identify it to the user.
     */
    public abstract void get_info(ref PluggableInfo info);
    
    /**
     * Called when the Pluggable is enabled (activated) or disabled (deactivated).
     *
     * activation will be called at the start of the program if the user previously 
     * enabled/disabled it as well as during program execution if the user changes its state. Note 
     * that disabling a Pluggable does not require destroying existing resources or objects 
     * the Pluggable has previously handed off to the host.
     *
     * This is purely informational. The Pluggable should acquire any long-term resources
     * it may be holding onto here, or wait until an extension-specific call is made to it.
     *
     * @param enabled ``true`` if the Pluggable has been enabled, ``false`` otherwise.
     */
    public abstract void activation(bool enabled);
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

/**
 * An interface to common services supplied by the host (Shotwell).
 *
 * Each {@link Pluggable} is offered a HostInterface for needs common to most plugins.
 * 
 * Note that
 * a HostInterface is not explicitly handed to the Pluggable through the SPIT interface, but is expected 
 * to be offered to the Pluggable through an interface applicable to the extension point. This 
 * also allows the extension point to extend HostInterface to offer other services applicable to the
 * type of plugin.
 */
public interface HostInterface : Object {
    /**
     * Returns a File object representing the library file (.so/la.) that the plugin was loaded
     * from.
     */
    public abstract File get_module_file();
    
    /**
     * Get a boolean from a persistent configuration store.
     *
     * @param key The name of the value to be retrieved.
     * @param def The default value (returned if the key has not been previously set).
     *
     * @return The value associated with key, def if not set.
     */
    public abstract bool get_config_bool(string key, bool def);
    
    /**
     * Store a boolean in a persistent configuration store.
     *
     * @param key The name of the value to be stored.
     * @param val The value to be stored.
     */
    public abstract void set_config_bool(string key, bool val);
    
    /**
     * Get an integer from a persistent configuration store.
     *
     * @param key The name of the value to be retrieved.
     * @param def The default value (returned if the key has not been previously set).
     *
     * @return The value associated with key, def if not set.
     */
    public abstract int get_config_int(string key, int def);
    
    /**
     * Store an integer in a persistent configuration store.
     *
     * @param key The name of the value to be stored.
     * @param val The value to be stored.
     */
    public abstract void set_config_int(string key, int val);
    
    /**
     * Get a string from a persistent configuration store.
     *
     * @param key The name of the value to be retrieved.
     * @param def The default value (returned if the key has not been previously set).
     *
     * @return The value associated with key, def if not set.
     */
    public abstract string? get_config_string(string key, string? def);
    
    /**
     * Store a string in a persistent configuration store.
     *
     * @param key The name of the value to be stored.
     * @param val The value to be stored.
     */
    public abstract void set_config_string(string key, string? val);
    
    /**
     * Get a double from a persistent configuration store.
     *
     * @param key The name of the value to be retrieved.
     * @param def The default value (returned if the key has not been previously set).
     *
     * @return The value associated with key, def if not set.
     */
    public abstract double get_config_double(string key, double def);
    
    /**
     * Store a double in a persistent configuration store.
     *
     * @param key The name of the value to be stored.
     * @param val The value to be stored.
     */
    public abstract void set_config_double(string key, double val);
    
    /**
     * Delete the value from the persistent configuration store.
     */
    public abstract void unset_config_key(string key);
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

}

