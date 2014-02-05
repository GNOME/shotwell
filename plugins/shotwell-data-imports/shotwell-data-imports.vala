/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern const string _VERSION;

// "core services" are: F-Spot
private class ShotwellDataImportsCoreServices : Object, Spit.Module {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    // we need to get a module file handle because our pluggables have to load resources from the
    // module file directory
    public ShotwellDataImportsCoreServices(GLib.File module_file) {
        GLib.File resource_directory = module_file.get_parent();
        
        pluggables += new FSpotService(resource_directory);
    }
    
    public unowned string get_module_name() {
        return _("Core Data Import Services");
    }
    
    public unowned string get_version() {
        return _VERSION;
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.data_imports.core_services";
    }
    
    public unowned Spit.Pluggable[]? get_pluggables() {
        return pluggables;
    }
}

// This entry point is required for all SPIT modules.
public Spit.Module? spit_entry_point(Spit.EntryPointParams *params) {
    params->module_spit_interface = Spit.negotiate_interfaces(params->host_min_spit_interface,
        params->host_max_spit_interface, Spit.CURRENT_INTERFACE);
    
    return (params->module_spit_interface != Spit.UNSUPPORTED_INTERFACE)
        ? new ShotwellDataImportsCoreServices(params->module_file) : null;
}

