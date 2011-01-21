/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// This is the front-end interface for all modules (i.e. .so/.la files) that allows for Shotwell
// to query them for information and to get a list of all plug-ins stored in the module.  This
// is named Shotwell Pluggable Interface Technology (SPIT).  This is intended only to last long
// enough for another generic plug-in library (most like Peas) to be used later.

// The Spit namespace is used for all interfaces and code that are made available to plugins or
// are exposed by plugins.
namespace Spit {

public const int UNSUPPORTED_INTERFACE = -1;
public const int CURRENT_INTERFACE = 0;

// A utility function for checking host interfaces against one's own and returning the right value.
// Note that this only works if the caller operates on only one interface version (and cannot mutate
// between multiple ones).
public int negotiate_interfaces(int min_host_interface, int max_host_interface, int plugin_interface) {
    if (min_host_interface > plugin_interface || max_host_interface < plugin_interface)
        return UNSUPPORTED_INTERFACE;
    else
        return plugin_interface;
}

//
// SPIT API entry point.  Host application passes in the minimum and maximum version of the SPIT
// inteface it supports (values are inclusive).  The module returns the version it wishes to
// use and a pointer to a SpitWad (which will remain ref'ed as long as the module is loaded in
// memory).  The module should return UNSUPPORTED_SPIT_VERSION is the min/max are out of its
// range and null for its SpitWad.
//
[CCode (has_target = false)]
public delegate unowned Wad? EntryPoint(int host_min_spit_interface, int host_max_spit_interface,
    out int module_spit_interface);

//
// SPIT entry point name, which matches SpitEntryPoint's interface
//
public const string ENTRY_POINT_NAME = "spit_entry_point";

//
// A Wad represents an entire module (i.e. a .so/.la) which contains zero or more Shotwell
// plug-ins.  Once the module has been loaded into process space and this object has been
// loaded and held by Shotwell, all calls to the module and plug-ins are resolved through this
// interface.
//
public interface Wad : Object {
    //
    // Returns a (potentially) user-visible string describing the module (i.e. the .so/.la file).
    //
    public abstract string get_name();
    
    //
    // Returns a (potentially) user-visible string describing the module version.  Note that this
    // may be programmatically interpreted at some point, so use a widespread versioning scheme.
    //
    public abstract string get_version();
    
    //
    // Returns a unique identifier for this module.  This is used to differentiate between multiple
    // installed versions and to determine which one should be used (i.e. if a module is available
    // in a system directory and a user directory).  This name is case-sensitive.
    // 
    // Best practice: use a reverse-DNS-order scheme, a la Java's packages
    // (i.e. "org.yorba.shotwell.frotz").
    //
    public abstract string get_wad_name();
    
    //
    // Returns an array of Pluggables that represent each plug-in available in the module.
    // May return NULL or an empty array.
    //
    public abstract Pluggable[]? get_pluggables();
}

//
// Each plug-in in a module needs to implement this interface at a minimum.  Specific plug-in
// points may have (and probably will have) specific interface requirements as well.
//
public interface Pluggable : Object {
    // Like the Spit entry point, this mechanism allows for the host to negotiate with the Pluggable
    // for its interface version.  If the pluggable does not support an interface between the
    // two ranges (inclusive), it should return UNSUPPORTED_INTERFACE.
    public abstract int get_pluggable_interface(int min_host_interface, int max_host_interface);
}

}

