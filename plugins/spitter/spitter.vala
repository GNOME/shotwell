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

using Shotwell.Plugins;

extern const string _VERSION;

private class Spitter : Object, SpitWad {
    public string get_name() {
        return "SPIT Reference Module";
    }
    
    public string get_version() {
        return _VERSION;
    }
    
    public string get_wad_name() {
        return "org.yorba.shotwell.spitter";
    }
    
    public Pluggable[]? get_pluggables() {
        return null;
    }
}

private Spitter? spitter = null;

// This entry point is required for all SPIT modules.
public SpitWad? spit_entry_point(int host_spit_version, out int module_spit_version) {
    if (host_spit_version != SPIT_VERSION) {
        module_spit_version = UNSUPPORTED_SPIT_VERSION;
        
        return null;
    }
    
    module_spit_version = SPIT_VERSION;
    
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

