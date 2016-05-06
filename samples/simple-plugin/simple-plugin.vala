/* Copyright 2016 Software Freedom Conservancy Inc.
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
    public unowned string get_module_name() {
        return "Simple Plugin Sample";
    }
    
    public unowned string get_version() {
        return _VERSION;
    }
    
    // Every module needs to have a unique ID.
    public unowned string get_id() {
        return "org.yorba.shotwell.samples.simple-plugin";
    }
    
    public unowned Spit.Pluggable[]? get_pluggables() {
        return null;
    }
}

//
// spit_entry_point() is required for all SPIT modules.
//

public Spit.Module? spit_entry_point(Spit.EntryPointParams *params) {
    // Spit.negotiate_interfaces is a simple way to deal with the parameters from the host
    params->module_spit_interface = Spit.negotiate_interfaces(params->host_min_spit_interface,
        params->host_max_spit_interface, Spit.CURRENT_INTERFACE);
    
    return (params->module_spit_interface != Spit.UNSUPPORTED_INTERFACE)
        ? new SimplePluginModule() : null;
}

// This is here to keep valac happy.
private void dummy_main() {
}

