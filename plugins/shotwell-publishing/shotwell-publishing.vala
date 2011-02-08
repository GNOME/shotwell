/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

extern const string _VERSION;

// "core services" are: Facebook, Flickr, Picasa Web Albums, and YouTube
private class ShotwellPublishingCoreServices : Object, Spit.Wad {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    public ShotwellPublishingCoreServices() {
        pluggables += new FacebookService();
    }
    
    ~ShotwellPublishingCoreServices() {
    }
    
    public string get_name() {
        return "Core Publishing Services";
    }
    
    public string get_version() {
        return _VERSION;
    }
    
    public string get_wad_name() {
        return "org.yorba.shotwell.publishing.core_services";
    }
    
    public Spit.Pluggable[]? get_pluggables() {
        return pluggables;
    }
}

private ShotwellPublishingCoreServices? core_services = null;
private Spit.EntryPoint? compiler_entry_point = null;

// This entry point is required for all SPIT modules.
public unowned Spit.Wad? spit_entry_point(int host_min_spit_interface, int host_max_spit_interface,
    out int module_spit_interface) {
    // this is purely for compilation, to verify that the entry point matches SpitEntryPoint's sig;
    // it does nothing functionally
    compiler_entry_point = spit_entry_point;
    
    module_spit_interface = Spit.negotiate_interfaces(host_min_spit_interface, host_max_spit_interface,
        Spit.CURRENT_INTERFACE);
    if (module_spit_interface == Spit.UNSUPPORTED_INTERFACE)
        return null;
    
    if (core_services == null)
        core_services = new ShotwellPublishingCoreServices();
    
    return core_services;
}

public void g_module_unload() {
    if (core_services != null)
        debug("%s %s unloaded", core_services.get_name(), core_services.get_version());
    else
        debug("core_services unloaded prior to spit_entry_point being called");
    
    core_services = null;
}

// valac wants a default entry point, so valac gets a default entry point
private void dummy_main() {
}

