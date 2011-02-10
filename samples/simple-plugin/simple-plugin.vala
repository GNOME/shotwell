/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

extern const string _VERSION;

//
// Each .so has a Spit.Module that describes the module and offers zero or more Spit.Pluggables
// to Shotwell to extend its functionality,
//

private class SimplePluginModule : Object, Spit.Module {
    public string get_name() {
        return "Simple Plugin Sample";
    }
    
    public string get_version() {
        return _VERSION;
    }
    
    // Every module needs to have a unique ID.
    public string get_id() {
        return "org.yorba.shotwell.samples.simple-plugin";
    }
    
    public Spit.Pluggable[]? get_pluggables() {
        return null;
    }
}

//
// The module is responsible for holding a ref to its Spit.Module until it's unloaded
// (see g_module_unload)
//

private SimplePluginModule? simple = null;

//
// spit_entry_point() is required for all SPIT modules.
//

public unowned Spit.Module? spit_entry_point(int host_min_spit_interface, int host_max_spit_interface,
    out int module_spit_interface) {
    // Spit.negotiate_interfaces is a simple way to deal with the parameters from the host
    module_spit_interface = Spit.negotiate_interfaces(host_min_spit_interface, host_max_spit_interface,
        Spit.CURRENT_INTERFACE);
    if (module_spit_interface == Spit.UNSUPPORTED_INTERFACE)
        return null;
    
    // Although the entry point should only be called once, easy to guard against the possibility
    // and still do the right thing
    if (simple == null)
        simple = new SimplePluginModule();
    
    return simple;
}

//
// The module is responsible for releasing its reference to its Spit.Module when the .so is
// unloaded from memory.
//

public void g_module_unload() {
    simple = null;
}

// This is here to keep valac happy.
private void dummy_main() {
}

