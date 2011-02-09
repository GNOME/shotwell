/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Spitter is a reference Vala implementation of SPIT (Shotwell Pluggable Interfaces Technology).
// Spitter shows off all the power, versatility, and dynamicism of SPIT.
//
// This module does essentially nothing.  It is not installed alongside the other Shotwell
// deliverables.  It mainly exists to test SPIT in the compilation and initialization steps.

extern const string _VERSION;

private class Spitter : Object, Spit.Module {
    ~Spitter() {
        debug("DTOR: Spitter");
    }
    
    public string get_name() {
        return "SPIT Reference Module";
    }
    
    public string get_version() {
        return _VERSION;
    }
    
    public string get_id() {
        return "org.yorba.shotwell.spitter";
    }
    
    public Spit.Pluggable[]? get_pluggables() {
        return null;
    }
}

private Spitter? spitter = null;
private Spit.EntryPoint? compiler_entry_point = null;

// This entry point is required for all SPIT modules.
public unowned Spit.Module? spit_entry_point(int host_min_spit_interface, int host_max_spit_interface,
    out int module_spit_interface) {
    // this is purely for compilation, to verify that the entry point matches SpitEntryPoint's sig;
    // it does nothing functionally
    compiler_entry_point = spit_entry_point;
    
    module_spit_interface = Spit.negotiate_interfaces(host_min_spit_interface, host_max_spit_interface,
        Spit.CURRENT_INTERFACE);
    if (module_spit_interface == Spit.UNSUPPORTED_INTERFACE)
        return null;
    
    if (spitter == null)
        spitter = new Spitter();
    
    return spitter;
}

public void g_module_unload() {
    if (spitter != null)
        debug("%s %s unloaded", spitter.get_name(), spitter.get_version());
    else
        debug("spitter unloaded prior to spit_entry_point being called");
    
    spitter = null;
}

// This is here to keep valac happy.
private void dummy_main() {
}

