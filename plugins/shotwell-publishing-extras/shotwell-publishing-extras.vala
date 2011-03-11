/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

extern const string _VERSION;

private class ShotwellPublishingExtraServices : Object, Spit.Module {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    public ShotwellPublishingExtraServices() {
        pluggables += new YandexService();
    }
    
    public unowned string get_module_name() {
        return _("Shotwell Extra Publishing Services");
    }
    
    public unowned string get_version() {
        return _VERSION;
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.extras";
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
        ? new ShotwellPublishingExtraServices() : null;
}

// valac wants a default entry point, so valac gets a default entry point
private void dummy_main() {
}

