/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// This is the front-end interface for all modules (i.e. .so/.la files) that allows for Shotwell
// to query them for information and to get a list of all plug-ins stored in the module.  This
// is named Shotwell Pluggable Interface Technology (SPIT).  This is intended only to last long
// enough for another generic plug-in library (most like Peas) to be used later.

// Using Shotwell.Plugins namespace (rather than Plugins) for the benefit of external plugins
// and C code (so the interfaces will be seen as shotwell_plugins_publisher_get_name, etc.)
namespace Shotwell.Plugins {

public const int UNSUPPORTED_SPIT_VERSION = 0;
public const int SPIT_VERSION = 1;

/*
    SPIT API entry point.  Host application passes in its version of the API, module returns its
    version and a pointer to a SpitWad.  If module returns UNSUPPORTED_SPIT_VERSION the SpitWad
    should be null.
*/
[CCode (has_target = false)]
public delegate SpitWad? SpitEntryPoint(int host_spit_version, out int module_spit_version);

/*
    SPIT entry point name, which matches SpitEntryPoint's interface
*/
public const string SPIT_ENTRY_POINT = "spit_entry_point";

/*
    A SpitWad represents an entire module (i.e. a .so/.la) which contains zero or more Shotwell
    plug-ins.  Once the module has been loaded into process space and this object has been
    loaded and held by Shotwell, all calls to the module and plug-ins are resolved through this
    interface.
*/
public interface SpitWad : Object {
    /*
        Returns a (potentially) user-visible string describing the module (i.e. the .so/.la file).
    */
    public abstract string get_name();
    
    /*
        Returns a (potentially) user-visible string describing the module version.  Note that this
        may be programmatically interpreted at some point, so use a widespread versioning scheme.
    */
    public abstract string get_version();
    
    /*
        Returns a unique identifier for this module.  This is used to differentiate between multiple
        installed versions and to determine which one should be used (i.e. if a module is available
        in a system directory and a user directory).  This name is case-sensitive.
        
        Best practice: use a reverse-DNS-order scheme, a la Java's packages
        (i.e. "org.yorba.shotwell.frotz").
    */
    public abstract string get_wad_name();
    
    /*
        Returns an array of Pluggables that represent each plug-in available in the module.
        May return NULL or an empty array.
    */
    public abstract Pluggable[]? get_pluggables();
}

/*
    Each plug-in in a module needs to implement this interface at a minimum.  Specific plug-in
    points may have (and probably will have) specific interface requirements as well.
*/
public interface Pluggable : Object {
}

}

